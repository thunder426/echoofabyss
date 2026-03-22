## EnemyAI.gd
## Enemy AI using the same dual-resource (Essence + Mana) system as the player.
## CombatScene calls run_turn() when the enemy turn starts.
## The AI plays cards from a real shuffled deck, then attacks, then emits ai_turn_finished.
class_name EnemyAI
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the AI has finished all its actions for this turn
signal ai_turn_finished()

## Emitted each time the AI summons a minion (lets CombatScene check ON_ENEMY_SUMMON traps)
signal minion_summoned(minion: MinionInstance)

## Emitted when the AI casts a spell (lets CombatScene resolve effect + check ON_ENEMY_SPELL traps)
signal enemy_spell_cast(spell: SpellCardData)

## Emitted just before an enemy minion attacks another minion
signal enemy_about_to_attack(attacker: MinionInstance, target: MinionInstance)

## Emitted just before an enemy minion attacks the player hero
signal enemy_attacking_hero(attacker: MinionInstance)

# ---------------------------------------------------------------------------
# References — set by CombatScene before run_turn()
# ---------------------------------------------------------------------------

var enemy_board: Array[MinionInstance]
var player_board: Array[MinionInstance]
var enemy_slots: Array[BoardSlot]
var combat_manager: CombatManager

## AI behaviour profile — set by CombatScene from EnemyData.ai_profile before run_turn().
var ai_profile: String = "default"

## Reference to CombatScene — used by profile-specific logic to read player board state.
var scene: Node = null

# ---------------------------------------------------------------------------
# Resources — mirrors the player's dual system with the same combined cap
# ---------------------------------------------------------------------------

var essence: int = 0
var essence_max: int = 0
var mana: int = 0
var mana_max: int = 0

## Shared combined cap with the player (essence_max + mana_max ≤ this).
const COMBINED_RESOURCE_CAP := 11

## Extra mana cost added to enemy spells this turn (from Spell Taxer).
var spell_cost_penalty: int = 0

## Per-card mana cost discounts keyed by card ID (e.g. {"pack_frenzy": 1}).
## Set by CombatScene when ancient_frenzy passive is active.
var spell_cost_discounts: Dictionary = {}

## Set to true by Smoke Veil trap to cancel the current attack.
var attack_cancelled: bool = false

## When non-null, Imp Barricade redirected this attack to the given player minion.
var redirect_attack_target: MinionInstance = null

# ---------------------------------------------------------------------------
# Deck — a real shuffled deck drawn without replacement; reshuffles when empty
# ---------------------------------------------------------------------------

var _deck: Array[CardData] = []
var _discard: Array[CardData] = []
var hand: Array[CardData] = []
const HAND_MAX := 5

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
func setup_deck(card_ids: Array[String]) -> void:
	_deck.clear()
	_discard.clear()
	hand.clear()
	var ids := card_ids if not card_ids.is_empty() else FALLBACK_DECK
	for id in ids:
		var card := CardDatabase.get_card(id)
		if card:
			_deck.append(card)
	_deck.shuffle()
	_draw_cards(5)

## Add a card directly to the enemy's hand (used by ON_PLAY effects like Abyssal Arcanist).
func add_to_hand(card: CardData) -> void:
	if hand.size() < HAND_MAX:
		hand.append(card)

## Public wrapper — draw count cards from the enemy deck (used by passive effects).
func draw_cards(count: int) -> void:
	_draw_cards(count)

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

func run_turn() -> void:
	_choose_resource_growth()
	essence = essence_max
	mana    = mana_max
	_draw_cards(1)
	if ai_profile == "feral_pack":
		await _play_phase_feral_pack()
		await _attack_phase_feral_pack()
	else:
		await _play_phase()
		await _attack_phase()
	ai_turn_finished.emit()

# ---------------------------------------------------------------------------
# Resource growth — mirrors the player's combined soft cap
# ---------------------------------------------------------------------------

func _choose_resource_growth() -> void:
	if essence_max + mana_max >= COMBINED_RESOURCE_CAP:
		return
	# Grow mana when it lags more than 2 behind essence; otherwise grow essence.
	# This gives the enemy a natural 2:1 essence-to-mana ratio over time.
	if mana_max < essence_max - 2:
		mana_max += 1
	else:
		essence_max += 1

# ---------------------------------------------------------------------------
# Card draw — draws from deck, reshuffles discard when deck is empty
# ---------------------------------------------------------------------------

func _draw_cards(count: int) -> void:
	for _i in count:
		if hand.size() >= HAND_MAX:
			break
		if _deck.is_empty():
			if _discard.is_empty():
				break  # No cards left at all
			_deck = _discard.duplicate()
			_discard.clear()
			_deck.shuffle()
		hand.append(_deck.pop_front())

# ---------------------------------------------------------------------------
# Play phase — spend resources on minions and spells, cheapest first
# ---------------------------------------------------------------------------

func _play_phase() -> void:
	var made_a_play := true
	while made_a_play:
		made_a_play = false
		hand.sort_custom(_sort_by_total_cost)
		for card in hand.duplicate():
			if card is SpellCardData:
				var spell := card as SpellCardData
				var effective_cost: int = max(0, spell.cost + spell_cost_penalty - (spell_cost_discounts.get(spell.id, 0) as int))
				if effective_cost > mana:
					continue
				mana -= effective_cost
				hand.erase(card)
				_discard.append(card)
				enemy_spell_cast.emit(spell)
				made_a_play = true
				if not is_inside_tree(): return
				await get_tree().create_timer(ACTION_DELAY).timeout
				if not is_inside_tree(): return
				break
			elif card is MinionCardData:
				var mc := card as MinionCardData
				if mc.essence_cost > essence or mc.mana_cost > mana:
					continue
				var slot := _find_empty_enemy_slot()
				if slot == null:
					return  # Board full
				essence -= mc.essence_cost
				mana    -= mc.mana_cost
				var instance := MinionInstance.create(mc, "enemy")
				enemy_board.append(instance)
				slot.place_minion(instance)
				hand.erase(card)
				_discard.append(card)
				minion_summoned.emit(instance)
				made_a_play = true
				if not is_inside_tree(): return
				await get_tree().create_timer(ACTION_DELAY).timeout
				if not is_inside_tree(): return
				break

func _sort_by_total_cost(a: CardData, b: CardData) -> bool:
	var ac := (a as MinionCardData).essence_cost + (a as MinionCardData).mana_cost \
		if a is MinionCardData else a.cost
	var bc := (b as MinionCardData).essence_cost + (b as MinionCardData).mana_cost \
		if b is MinionCardData else b.cost
	return ac < bc

# ---------------------------------------------------------------------------
# Attack phase — every ready minion attacks
# ---------------------------------------------------------------------------

func _attack_phase() -> void:
	for minion in enemy_board.duplicate():
		if not enemy_board.has(minion):
			continue
		if not minion.can_attack():
			continue

		var target := _pick_player_target()
		if target != null:
			enemy_about_to_attack.emit(minion, target)
			if attack_cancelled:
				attack_cancelled = false
				continue
			if redirect_attack_target != null:
				target = redirect_attack_target
				redirect_attack_target = null
			if not enemy_board.has(minion):
				continue
			combat_manager.resolve_minion_attack(minion, target)
		else:
			if not minion.can_attack_hero():
				continue
			enemy_attacking_hero.emit(minion)
			if attack_cancelled:
				attack_cancelled = false
				continue
			if redirect_attack_target != null:
				var barricade_target := redirect_attack_target
				redirect_attack_target = null
				if enemy_board.has(minion):
					combat_manager.resolve_minion_attack(minion, barricade_target)
				if not is_inside_tree(): return
				await get_tree().create_timer(ACTION_DELAY).timeout
				if not is_inside_tree(): return
				continue
			if not enemy_board.has(minion):
				continue
			combat_manager.resolve_minion_attack_hero(minion, "player")

		if not is_inside_tree(): return
		await get_tree().create_timer(ACTION_DELAY).timeout
		if not is_inside_tree(): return

# ---------------------------------------------------------------------------
# Target selection
# ---------------------------------------------------------------------------

func _find_empty_enemy_slot() -> BoardSlot:
	for slot in enemy_slots:
		if slot.is_empty():
			return slot
	return null

func _pick_player_target() -> MinionInstance:
	if player_board.is_empty():
		return null
	var guards := CombatManager.get_taunt_minions(player_board)
	if not guards.is_empty():
		return guards[randi() % guards.size()]
	return player_board[randi() % player_board.size()]

# ---------------------------------------------------------------------------
# Feral Pack AI profile — play phase
# ---------------------------------------------------------------------------

func _play_phase_feral_pack() -> void:
	# Pass 1: flood the board with minions, cheapest first
	var placed_minion := true
	while placed_minion:
		placed_minion = false
		var minion_hand: Array[CardData] = []
		for c in hand:
			if c is MinionCardData:
				minion_hand.append(c)
		minion_hand.sort_custom(_sort_by_total_cost)
		for card in minion_hand:
			var mc := card as MinionCardData
			if mc.essence_cost > essence or mc.mana_cost > mana:
				continue
			var slot := _find_empty_enemy_slot()
			if slot == null:
				break  # board full — stop minion pass
			essence -= mc.essence_cost
			mana    -= mc.mana_cost
			var instance := MinionInstance.create(mc, "enemy")
			enemy_board.append(instance)
			slot.place_minion(instance)
			hand.erase(card)
			_discard.append(card)
			minion_summoned.emit(instance)
			placed_minion = true
			if not is_inside_tree(): return
			await get_tree().create_timer(ACTION_DELAY).timeout
			if not is_inside_tree(): return
			break

	# Pass 2: cast affordable spells that meet their conditions
	var cast_spell := true
	while cast_spell:
		cast_spell = false
		var spell_hand: Array[CardData] = []
		for c in hand:
			if c is SpellCardData:
				spell_hand.append(c)
		spell_hand.sort_custom(_sort_by_total_cost)
		for card in spell_hand:
			var spell := card as SpellCardData
			var eff_cost: int = max(0, spell.cost + spell_cost_penalty - (spell_cost_discounts.get(spell.id, 0) as int))
			if eff_cost > mana:
				continue
			if not _feral_pack_can_cast(spell):
				continue
			mana -= eff_cost
			hand.erase(card)
			_discard.append(card)
			enemy_spell_cast.emit(spell)
			cast_spell = true
			if not is_inside_tree(): return
			await get_tree().create_timer(ACTION_DELAY).timeout
			if not is_inside_tree(): return
			break

## Returns true when the feral_pack profile is allowed to cast this spell.
func _feral_pack_can_cast(spell: SpellCardData) -> bool:
	match spell.id:
		"feral_surge":
			# Only if at least one Feral Imp is already on the board
			for m in enemy_board:
				if m.card_data is MinionCardData and \
						"feral_imp" in (m.card_data as MinionCardData).minion_tags:
					return true
			return false
		"void_screech":
			# Only if board is full OR no minions remain in hand
			if _find_empty_enemy_slot() == null:
				return true
			for c in hand:
				if c is MinionCardData:
					return false  # minion still available — hold Void Screech
			return true
		"cyclone":
			# Only if the player has an active Rune or Environment
			return _player_has_rune_or_environment()
		_:
			return true

## Pick the best target for a SWIFT minion with no guards present.
## Prefers targets it can kill (our ATK >= their HP), then highest ATK among those.
## Falls back to highest ATK target if none are killable.
func _pick_swift_target(attacker: MinionInstance) -> MinionInstance:
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

func _player_has_rune_or_environment() -> bool:
	if scene == null:
		return false
	if scene.active_environment != null:
		return true
	for trap in scene.active_traps:
		if (trap as TrapCardData).is_rune:
			return true
	return false

# ---------------------------------------------------------------------------
# Feral Pack AI profile — attack phase
# ---------------------------------------------------------------------------

func _attack_phase_feral_pack() -> void:
	for minion in enemy_board.duplicate():
		if not enemy_board.has(minion):
			continue
		if not minion.can_attack():
			continue

		var guards := CombatManager.get_taunt_minions(player_board)
		if not guards.is_empty():
			# Must attack a guard. Prefer guards we survive (guard.ATK <= our HP).
			var safe: Array[MinionInstance] = []
			for g in guards:
				if g.effective_atk() <= minion.current_health:
					safe.append(g)
			var target: MinionInstance
			if not safe.is_empty():
				target = safe[randi() % safe.size()]
			else:
				# All guards kill us — pick the lowest-ATK guard
				target = guards[0]
				for g in guards:
					if g.effective_atk() < target.effective_atk():
						target = g
			enemy_about_to_attack.emit(minion, target)
			if attack_cancelled:
				attack_cancelled = false
				continue
			if redirect_attack_target != null:
				target = redirect_attack_target
				redirect_attack_target = null
			if not enemy_board.has(minion):
				continue
			combat_manager.resolve_minion_attack(minion, target)
		elif minion.can_attack_hero():
			# No guards — NORMAL minion attacks hero
			enemy_attacking_hero.emit(minion)
			if attack_cancelled:
				attack_cancelled = false
				continue
			if redirect_attack_target != null:
				var barricade_target := redirect_attack_target
				redirect_attack_target = null
				if enemy_board.has(minion):
					combat_manager.resolve_minion_attack(minion, barricade_target)
				if not is_inside_tree(): return
				await get_tree().create_timer(ACTION_DELAY).timeout
				if not is_inside_tree(): return
				continue
			if not enemy_board.has(minion):
				continue
			combat_manager.resolve_minion_attack_hero(minion, "player")
		elif not player_board.is_empty():
			# No guards — SWIFT minion attacks: prefer killable targets, then highest ATK
			var swift_target := _pick_swift_target(minion)
			enemy_about_to_attack.emit(minion, swift_target)
			if attack_cancelled:
				attack_cancelled = false
				continue
			if redirect_attack_target != null:
				swift_target = redirect_attack_target
				redirect_attack_target = null
			if not enemy_board.has(minion):
				continue
			combat_manager.resolve_minion_attack(minion, swift_target)
		else:
			continue

		if not is_inside_tree(): return
		await get_tree().create_timer(ACTION_DELAY).timeout
		if not is_inside_tree(): return
