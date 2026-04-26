## EnemyAI.gd
## Enemy AI using the same dual-resource (Essence + Mana) system as the player.
## CombatScene calls run_turn() when the enemy turn starts.
## The AI plays cards from a real shuffled deck, then attacks, then emits ai_turn_finished.
##
## All decision logic lives in EnemyAIProfile subclasses (enemies/ai/profiles/).
## This file owns game state, signals, and public action helpers that profiles call.
class_name EnemyAI
extends Node

# ---------------------------------------------------------------------------
# Profile registry
# ---------------------------------------------------------------------------

const _PROFILES: Dictionary = {
	"default":         preload("res://enemies/ai/profiles/DefaultProfile.gd"),
	"feral_pack":      preload("res://enemies/ai/profiles/FeralPackProfile.gd"),
	"feral_pack_screech": preload("res://enemies/ai/profiles/FeralPackScreechProfile.gd"),
	"matriarch":       preload("res://enemies/ai/profiles/MatriarchProfile.gd"),
	"corrupted_brood": preload("res://enemies/ai/profiles/CorruptedBroodProfile.gd"),
	"corrupted_brood_aggro": preload("res://enemies/ai/profiles/CorruptedBroodAggroProfile.gd"),
	"matriarch_aggro":      preload("res://enemies/ai/profiles/MatriarchAggroProfile.gd"),
	"matriarch_sac":        preload("res://enemies/ai/profiles/MatriarchSacProfile.gd"),
	"corrupted_brood_rune": preload("res://enemies/ai/profiles/CorruptedBroodRuneProfile.gd"),
	"cultist_patrol":  preload("res://enemies/ai/profiles/CultistPatrolProfile.gd"),
	"cultist_patrol_tempo": preload("res://enemies/ai/profiles/CultistPatrolTempoProfile.gd"),
	"void_ritualist":    preload("res://enemies/ai/profiles/VoidRitualistProfile.gd"),
	"corrupted_handler": preload("res://enemies/ai/profiles/CorruptedHandlerProfile.gd"),
	"rift_stalker":      preload("res://enemies/ai/profiles/RiftStalkerProfile.gd"),
	"void_aberration":   preload("res://enemies/ai/profiles/VoidAberrationProfile.gd"),
	"void_herald":       preload("res://enemies/ai/profiles/VoidHeraldProfile.gd"),
	"void_scout":          preload("res://enemies/ai/profiles/VoidScoutProfile.gd"),
	"void_warband":        preload("res://enemies/ai/profiles/VoidWarbandProfile.gd"),
	"void_captain":        preload("res://enemies/ai/profiles/VoidCaptainProfile.gd"),
	"void_ritualist_prime": preload("res://enemies/ai/profiles/VoidRitualistPrimeProfile.gd"),
	"void_champion":       preload("res://enemies/ai/profiles/VoidChampionProfile.gd"),
	"abyss_sovereign":     preload("res://enemies/ai/profiles/AbyssSovereignProfile.gd"),
	"abyss_sovereign_p2":  preload("res://enemies/ai/profiles/AbyssSovereignPhase2Profile.gd"),
}

var _active_profile: CombatProfile = null

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the AI has finished all its actions for this turn.
signal ai_turn_finished()

## Emitted each time the AI summons a minion (lets CombatScene check traps).
## slot is passed so CombatScene can defer place_minion until after the reveal.
signal minion_summoned(minion: MinionInstance, slot: BoardSlot)

## Emitted when the AI casts a spell (lets CombatScene resolve + check traps).
signal enemy_spell_cast(spell: SpellCardData)

## Emitted just before an enemy minion attacks another minion.
signal enemy_about_to_attack(attacker: MinionInstance, target: MinionInstance)

## Emitted just before an enemy minion attacks the player hero.
signal enemy_attacking_hero(attacker: MinionInstance)

## Emitted when the AI places a trap or rune (lets CombatScene update display + route triggers).
signal trap_placed(trap: TrapCardData)

## Emitted when the AI plays an environment card.
signal environment_placed(env: EnvironmentCardData)

# ---------------------------------------------------------------------------
# References — set by CombatScene before run_turn()
# ---------------------------------------------------------------------------

var enemy_board: Array[MinionInstance]
var player_board: Array[MinionInstance]
var enemy_slots: Array[BoardSlot]
var combat_manager: CombatManager

## AI behaviour profile ID.  Setting this resets the active profile object.
var ai_profile: String = "default":
	set(value):
		ai_profile = value
		_active_profile = null

## Reference to CombatScene — used by profiles to inspect player board state.
var scene: Node = null

# ---------------------------------------------------------------------------
# Resources — mirrors the player's dual system with the same combined cap
# ---------------------------------------------------------------------------

var essence: int = 1
var essence_max: int = 1
var mana: int = 1
var mana_max: int = 1

## Skips resource growth on the very first turn so the enemy starts at 1E/1M.
var _first_turn: bool = true

## Shared combined cap with the player (essence_max + mana_max ≤ this).
const COMBINED_RESOURCE_CAP := 11

## Extra mana cost added to enemy spells this turn (from Spell Taxer).
var spell_cost_penalty: int = 0

## Persistent flat mana-cost adjustment from an active aura (e.g. Void Ritualist
## Prime champion reduces by 1). Negative = discount. Not reset per turn.
var spell_cost_aura: int = 0

## Per-card mana cost discounts keyed by card ID (e.g. {"pack_frenzy": 1}).
var spell_cost_discounts: Dictionary = {}

## Per-card essence cost discounts keyed by card ID (e.g. {"void_touched_imp": 1}).
var essence_cost_discounts: Dictionary = {}

## Flat essence-cost discount applied to every enemy minion this turn (e.g. F15
## Abyssal Mandate grants -2 after the player grows Essence). Negative = cheaper.
## Reset by whichever system sets it (mandate clears at end of enemy turn).
var minion_essence_cost_aura: int = 0

## Set to true by Smoke Veil trap to cancel the current attack.
var attack_cancelled: bool = false

## When non-null, Imp Barricade redirects the current attack to this minion.
var redirect_attack_target: MinionInstance = null

## Chosen non-minion target for the spell currently being cast (trap or environment).
## Set by commit_spell_cast before emitting; read by CombatScene to populate EffectContext.
var spell_chosen_target = null

## Chosen target for the on-play effect of the minion being summoned.
## MinionInstance for minion targets, TrapCardData/EnvironmentCardData for trap/env targets.
## Set by commit_minion_play before emitting; read by CombatScene to populate EffectContext.
var minion_play_chosen_target = null

## Active traps and runes placed by the enemy (mirrors the player's active_traps in CombatScene).
var active_traps: Array[TrapCardData] = []

## Slots claimed by a pending summon (reveal in progress) — excluded from find_empty_slot.
var _pending_slots: Array[BoardSlot] = []

## Active environment card played by the enemy (mirrors the player's active_environment).
var active_environment: EnvironmentCardData = null

# ---------------------------------------------------------------------------
# Deck — real shuffled deck drawn without replacement; on draw a fresh replacement is
# added back and the deck is reshuffled to simulate an infinite card pool.
# ---------------------------------------------------------------------------

var _deck: Array[CardInstance] = []
## Card IDs flagged as limited — drawn once per copy, not re-added to deck.
var _limited_cards: Array[String] = []
## Public read access to the enemy deck (for symmetric card effects like rune_seeker).
var deck: Array[CardInstance]:
	get: return _deck
## Unified enemy graveyard — every card the enemy plays this combat is appended here
## (minions, spells, traps, environments) at the moment it leaves the hand.
## Each entry has its `resolved_on_turn` stamped at append time.
## Full-combat record — never cleared mid-combat. Cleared in `setup_deck`.
var _graveyard: Array[CardInstance] = []
## Public read access (mirror of `deck`) — used by symmetric graveyard-querying effects.
var graveyard: Array[CardInstance]:
	get: return _graveyard
var hand: Array[CardInstance] = []
const HAND_MAX := 10

## Fallback deck used when no encounter deck is configured.
const FALLBACK_DECK: Array[String] = [
	"void_imp", "void_imp", "void_imp",
	"shadow_hound", "shadow_hound",
	"abyssal_brute",
	"void_bolt", "void_bolt",
]

# ---------------------------------------------------------------------------
# Timing
# ---------------------------------------------------------------------------

const ACTION_DELAY := 0.55

# ---------------------------------------------------------------------------
# Setup — called by CombatScene before the first turn
# ---------------------------------------------------------------------------

## Load and shuffle the enemy deck from a list of card IDs.
## Each ID becomes a CardInstance; on draw, a fresh replacement is inserted and reshuffled.
func setup_deck(card_ids: Array[String]) -> void:
	_deck.clear()
	_graveyard.clear()
	hand.clear()
	active_traps.clear()
	active_environment = null
	var ids := card_ids if not card_ids.is_empty() else FALLBACK_DECK
	for id in ids:
		var card := CardDatabase.get_card(id)
		if card:
			_deck.append(CardInstance.create(card))
	_deck.shuffle()
	_draw_cards(5)

## Add a CardData directly to the enemy's hand (used by ON_PLAY effects).
func add_to_hand(card: CardData) -> void:
	if hand.size() < HAND_MAX:
		hand.append(CardInstance.create(card))

## Add an existing CardInstance directly to the enemy hand (used by symmetric effects).
func add_instance_to_hand(inst: CardInstance) -> void:
	if hand.size() < HAND_MAX:
		hand.append(inst)

## Stamp `resolved_on_turn` and append to the unified graveyard.
## Called from every commit_play_* path the moment a card leaves hand.
func _send_to_graveyard(inst: CardInstance) -> void:
	var turn_no: int = 0
	if scene != null and scene.turn_manager != null:
		turn_no = scene.turn_manager.turn_number
	inst.resolved_on_turn = turn_no
	_graveyard.append(inst)

## Public wrapper — draw count cards from the enemy deck (used by passives).
func draw_cards(count: int) -> void:
	_draw_cards(count)

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

func run_turn() -> void:
	if _active_profile == null:
		_setup_profile()
	if _first_turn:
		_first_turn = false
	else:
		_choose_resource_growth()
	essence = essence_max
	mana    = mana_max
	_draw_cards(1)
	await _active_profile.play_phase()
	if not is_inside_tree(): return
	# Brief pause between the play phase and attack phase so that Swift-minion
	# summon animations fully settle before any attack animation begins.
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree(): return
	await _active_profile.attack_phase()
	if not is_inside_tree(): return
	ai_turn_finished.emit()

# ---------------------------------------------------------------------------
# Private — profile setup
# ---------------------------------------------------------------------------

func _setup_profile() -> void:
	var profile_script = _PROFILES.get(ai_profile, _PROFILES["default"])
	_active_profile = profile_script.new()
	var agent := EnemyAgent.new()
	agent.setup(self)
	_active_profile.setup(agent)

# ---------------------------------------------------------------------------
# Private — resource growth
# ---------------------------------------------------------------------------

func _choose_resource_growth() -> void:
	if essence_max + mana_max >= COMBINED_RESOURCE_CAP:
		return
	# Let the active profile override growth (e.g. Matriarch: pure mana).
	if _active_profile != null and _active_profile.grow_resources(self):
		return
	# Default: grow mana when it lags more than 2 behind essence; otherwise grow essence.
	if mana_max < essence_max - 2:
		mana_max += 1
	else:
		essence_max += 1

# ---------------------------------------------------------------------------
# Private — card draw
# ---------------------------------------------------------------------------

## Draw count cards from the deck.
## On each draw: move the instance to hand AND insert a fresh replacement into the deck,
## then reshuffle — simulating an infinite card pool without recycling discards.
func _draw_cards(count: int) -> void:
	for _i in count:
		if hand.size() >= HAND_MAX:
			break
		if _deck.is_empty():
			break
		var inst: CardInstance = _deck.pop_front()
		hand.append(inst)
		# Add a fresh replacement so the deck never truly empties
		# Limited cards are NOT re-added (one-time draw per copy)
		if inst.card_data.id not in _limited_cards:
			_deck.append(CardInstance.create(inst.card_data))
			_deck.shuffle()

# ---------------------------------------------------------------------------
# Public helpers — utilities for profiles
# ---------------------------------------------------------------------------

## Remove an enemy minion from the board silently (no death triggers, no animation).
## Used for Void Spirit consumption to pay spark costs.
func consume_minion(minion: MinionInstance) -> void:
	var spark_val: int = minion.effective_spark_value(scene)
	enemy_board.erase(minion)
	for slot in enemy_slots:
		if slot.minion == minion:
			slot.remove_minion()
			break
	scene._log("  %s consumed as spark fuel." % minion.card_data.card_name, 1)
	# Fire spark consumed event for passives (void_detonation, champion_vw, etc.)
	# Use effective value so spirit_resonance-boosted Spirits still fire.
	if spark_val > 0 and scene.trigger_manager:
		var event := Enums.TriggerEvent.ON_ENEMY_SPARK_CONSUMED if minion.owner == "enemy" \
			else Enums.TriggerEvent.ON_PLAYER_SPARK_CONSUMED
		var ctx := EventContext.make(event, minion.owner)
		ctx.minion = minion
		ctx.damage = spark_val
		scene.trigger_manager.fire(ctx)

## Returns the first empty enemy board slot, or null if board is full.
## Skips slots that are claimed by an in-progress summon reveal.
func find_empty_slot() -> BoardSlot:
	for slot in enemy_slots:
		if slot.is_empty() and not (slot in _pending_slots):
			return slot
	return null

## Returns a random guard, or a random player minion if no guards exist.
## Returns null when the player board is empty.
func pick_player_target() -> MinionInstance:
	if player_board.is_empty():
		return null
	var guards := CombatManager.get_taunt_minions(player_board)
	if not guards.is_empty():
		return guards[randi() % guards.size()]
	return player_board[randi() % player_board.size()]

## Returns the best target for a SWIFT minion (no guards present).
## Prefers killable targets (our ATK >= their HP), then highest ATK among those.
func pick_swift_target(attacker: MinionInstance) -> MinionInstance:
	var killable: Array[MinionInstance] = []
	for m in player_board:
		if attacker.effective_atk() >= m.current_health:
			killable.append(m)
	var pool := killable if not killable.is_empty() else player_board
	var best: MinionInstance = pool[0]
	for m in pool:
		if m.effective_atk() > best.effective_atk():
			best = m
	return best

## Returns true if the player has at least one active Rune or Environment.
func player_has_rune_or_environment() -> bool:
	if scene == null:
		return false
	if scene.active_environment != null:
		return true
	for trap in scene.active_traps:
		if (trap as TrapCardData).is_rune:
			return true
	return false

## Effective mana cost of a spell after penalty and discounts.
func effective_spell_cost(spell: SpellCardData) -> int:
	return max(0, spell.cost + spell_cost_penalty + spell_cost_aura - (spell_cost_discounts.get(spell.id, 0) as int))

# ---------------------------------------------------------------------------
# Public helpers — async actions for profiles
# ---------------------------------------------------------------------------

## Place a minion on the board (slot already found, resources already deducted).
## chosen_target: player minion chosen by the profile for the on-play effect, if any.
## Returns false if the scene tree is gone.
func commit_minion_play(inst: CardInstance, slot: BoardSlot, chosen_target = null) -> bool:
	var mc := inst.card_data as MinionCardData
	var instance := MinionInstance.create(mc, "enemy")
	instance.card_instance = inst
	enemy_board.append(instance)
	_pending_slots.append(slot)  # reserve slot without touching its visual
	hand.erase(inst)
	_send_to_graveyard(inst)
	minion_play_chosen_target = chosen_target
	minion_summoned.emit(instance, slot)
	if scene != null and scene.state != null:
		scene.state.minion_summoned.emit("enemy", instance, slot.index)
	if not is_inside_tree(): return false
	await get_tree().create_timer(ACTION_DELAY).timeout
	if not is_inside_tree(): return false
	# Wait for the card reveal animation to finish before the next AI action
	if scene != null and scene.get("_enemy_summon_reveal_active") == true:
		await scene.enemy_summon_reveal_done
	# Also wait for any on-play VFX (e.g. Frenzied Imp hurl) to finish so the
	# full animation plays before the next enemy action.
	if scene != null and scene.get("_on_play_vfx_active") == true:
		await scene.on_play_vfx_done
	return is_inside_tree()

## Cast a spell (resources already deducted).
## chosen_target: non-minion target (TrapCardData / EnvironmentCardData) chosen by the profile.
## Returns false if the scene tree is gone.
func commit_spell_cast(inst: CardInstance, chosen_target = null) -> bool:
	var spell := inst.card_data as SpellCardData
	hand.erase(inst)
	_send_to_graveyard(inst)
	spell_chosen_target = chosen_target
	enemy_spell_cast.emit(spell)
	if not is_inside_tree(): return false
	# Wait for the card cast animation + VFX to finish before the next AI action
	# so consecutive enemy spell VFX don't overlap.
	if scene != null and scene.get("_enemy_spell_cast_active") == true:
		await scene.enemy_spell_cast_done
	if not is_inside_tree(): return false
	await get_tree().create_timer(ACTION_DELAY).timeout
	return is_inside_tree()

## Place a trap or rune (resources already deducted).
## Returns false if the scene tree is gone.
func commit_play_trap(inst: CardInstance) -> bool:
	var trap := inst.card_data as TrapCardData
	hand.erase(inst)
	_send_to_graveyard(inst)
	active_traps.append(trap)
	trap_placed.emit(trap)
	if not is_inside_tree(): return false
	await get_tree().create_timer(ACTION_DELAY).timeout
	return is_inside_tree()

## Play an environment card (resources already deducted).
## Returns false if the scene tree is gone.
func commit_play_environment(inst: CardInstance) -> bool:
	var env := inst.card_data as EnvironmentCardData
	hand.erase(inst)
	_send_to_graveyard(inst)
	active_environment = env
	environment_placed.emit(env)
	if not is_inside_tree(): return false
	await get_tree().create_timer(ACTION_DELAY).timeout
	return is_inside_tree()

## Execute a minion-vs-minion attack, handling cancel and redirect.
## Returns false if the attack was skipped (cancelled / attacker died) or
## the scene tree is gone — the profile should check is_inside_tree() to
## distinguish the two cases.
func do_attack_minion(attacker: MinionInstance, target: MinionInstance) -> bool:
	if redirect_attack_target != null:
		target = redirect_attack_target
		redirect_attack_target = null
	# Enforce Guard: if the player board has any Guard minion, the attack must
	# be directed at one of them, regardless of how the profile chose the target.
	var guards := CombatManager.get_taunt_minions(player_board)
	if not guards.is_empty() and not target.has_guard():
		target = guards[randi() % guards.size()]
	enemy_about_to_attack.emit(attacker, target)
	if attack_cancelled:
		attack_cancelled = false
		return false
	if not enemy_board.has(attacker):
		return false
	combat_manager.resolve_minion_attack(attacker, target)
	if not is_inside_tree(): return false
	await get_tree().create_timer(ACTION_DELAY).timeout
	if not is_inside_tree(): return false
	await _wait_for_death_vfx()
	return is_inside_tree()

## Execute a minion-vs-hero attack, handling cancel and Imp Barricade redirect.
## Returns false if the attack was skipped or the scene tree is gone.
func do_attack_hero(attacker: MinionInstance) -> bool:
	# Enforce Guard: cannot attack hero while any player Guard minion is alive.
	if not CombatManager.get_taunt_minions(player_board).is_empty():
		return false
	enemy_attacking_hero.emit(attacker)
	if attack_cancelled:
		attack_cancelled = false
		return false
	if redirect_attack_target != null:
		var barricade := redirect_attack_target
		redirect_attack_target = null
		if enemy_board.has(attacker):
			combat_manager.resolve_minion_attack(attacker, barricade)
		if not is_inside_tree(): return false
		await get_tree().create_timer(ACTION_DELAY).timeout
		if not is_inside_tree(): return false
		await _wait_for_death_vfx()
		return is_inside_tree()
	if not enemy_board.has(attacker):
		return false
	combat_manager.resolve_minion_attack_hero(attacker, "player")
	if not is_inside_tree(): return false
	await get_tree().create_timer(ACTION_DELAY).timeout
	if not is_inside_tree(): return false
	await _wait_for_death_vfx()
	return is_inside_tree()

## Block until all in-flight minion-death animations finish so consecutive
## enemy actions don't overlap death / on-death VFX.
func _wait_for_death_vfx() -> void:
	if scene == null:
		return
	var active: Variant = scene.get("_active_death_anims")
	if active is int and (active as int) > 0:
		await scene.death_anims_done
