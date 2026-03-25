## SimState.gd
## Headless simulation state — duck-types as CombatScene for EffectResolver.
## No scene tree, no timers, no UI.  Pure game logic only.
##
## CombatSim creates one of these, builds two CombatAgents on top of it,
## and runs two CombatProfiles against each other.
class_name SimState
extends RefCounted

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const BOARD_MAX          := 5
const PLAYER_HAND_MAX    := 10  ## matches TurnManager.HAND_SIZE_MAX
const ENEMY_HAND_MAX     := 5   ## matches EnemyAI.HAND_MAX
const COMBINED_RESOURCE_CAP := 11
const ESSENCE_HARD_CAP   := 10

# ---------------------------------------------------------------------------
# Boards — shared by both agents
# ---------------------------------------------------------------------------

var player_board: Array[MinionInstance] = []
var enemy_board:  Array[MinionInstance] = []

## Pre-allocated BoardSlot placeholders (no scene tree — visuals never initialise).
## Profiles call find_empty_slot() which returns one of these.
var player_slots: Array[BoardSlot] = []
var enemy_slots:  Array[BoardSlot] = []

# ---------------------------------------------------------------------------
# Hero HP
# ---------------------------------------------------------------------------

var player_hp: int = 3000
var enemy_hp:  int = 2000

# ---------------------------------------------------------------------------
# Resources — profiles write these directly via agent.essence / agent.mana
# ---------------------------------------------------------------------------

var player_essence:     int = 0
var player_essence_max: int = 0
var player_mana:        int = 0
var player_mana_max:    int = 0

var enemy_essence:      int = 0
var enemy_essence_max:  int = 0
var enemy_mana:         int = 0
var enemy_mana_max:     int = 0

# ---------------------------------------------------------------------------
# Decks / hands / discards
# ---------------------------------------------------------------------------

var player_deck:    Array[CardData] = []
var player_hand:    Array[CardData] = []
var player_discard: Array[CardData] = []

var enemy_deck:    Array[CardData] = []
var enemy_hand:    Array[CardData] = []
var enemy_discard: Array[CardData] = []

# ---------------------------------------------------------------------------
# Traps / environment / void marks
# ---------------------------------------------------------------------------

var active_traps:       Array       = []   ## Array[TrapCardData] — player side
var active_environment              = null ## EnvironmentCardData or null — player side
var enemy_active_traps: Array       = []   ## Array[TrapCardData] — enemy side
var enemy_active_environment        = null ## EnvironmentCardData or null — enemy side
var enemy_void_marks:   int         = 0

## Aura handlers registered for each active rune — Array[{rune_id, entries}]
## where entries is Array[{event, handler}].
var _rune_aura_handlers: Array = []

## Ritual handlers registered for the current environment.
var _env_ritual_handlers: Array = []

# ---------------------------------------------------------------------------
# Spell cost modifier (enemy side, mirrors EnemyAI)
# ---------------------------------------------------------------------------

var enemy_spell_cost_penalty:   int        = 0
var enemy_spell_cost_discounts: Dictionary = {}

# ---------------------------------------------------------------------------
# Player talents (configure before running to simulate a talent build)
# ---------------------------------------------------------------------------

## Set of active talent IDs for the player. Example: ["piercing_void"]
var talents: Array[String] = []

## Imp Evolution once-per-turn gate — reset at the start of each player turn.
var imp_evolution_used_this_turn: bool = false

## Feral Instinct once-per-turn gate — reset at ON_ENEMY_TURN_START.
var feral_instinct_granted_this_turn: bool = false

## Active passive IDs for the current enemy encounter (e.g. ["feral_instinct", "pack_instinct"]).
## Set by CombatSim before calling SimTriggerSetup.setup().
var enemy_passives: Array[String] = []

# ---------------------------------------------------------------------------
# Sim result
# ---------------------------------------------------------------------------

var winner: String = ""  ## "player", "enemy", or "" while running

# ---------------------------------------------------------------------------
# Shared combat manager — both agents use this
# ---------------------------------------------------------------------------

var combat_manager: CombatManager

## TriggerManager — wired by SimTriggerSetup after SimState.setup().
var trigger_manager: TriggerManager = null

# ---------------------------------------------------------------------------
# Duck-typed scene sub-objects (EffectResolver accesses ctx.scene.turn_manager
# and ctx.scene.enemy_ai)
# ---------------------------------------------------------------------------

var turn_manager: SimTurnManager  ## set up in setup()
var enemy_ai: SimEnemyAgent       ## set by CombatSim after creating the agent
var _hardcoded: HardcodedEffects  ## set up in setup()

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(p_deck_ids: Array[String], e_deck_ids: Array[String],
		p_hp: int = 3000, e_hp: int = 2000) -> void:
	player_hp = p_hp
	enemy_hp  = e_hp

	# Build decks
	for id in p_deck_ids:
		var card := CardDatabase.get_card(id)
		if card:
			player_deck.append(card)
	player_deck.shuffle()

	for id in e_deck_ids:
		var card := CardDatabase.get_card(id)
		if card:
			enemy_deck.append(card)
	enemy_deck.shuffle()

	# Pre-allocate board slot placeholders (no scene tree — _ready never fires,
	# _overlay stays null, so _refresh_visuals() returns early — safe to use)
	for i in BOARD_MAX:
		var ps := BoardSlot.new()
		ps.slot_owner = "player"
		ps.index      = i
		player_slots.append(ps)
		var es := BoardSlot.new()
		es.slot_owner = "enemy"
		es.index      = i
		enemy_slots.append(es)

	# Wire up combat manager
	combat_manager = CombatManager.new()
	combat_manager.minion_vanished.connect(_on_minion_vanished)
	combat_manager.hero_damaged.connect(_on_hero_damaged)
	combat_manager.hero_healed.connect(_on_hero_healed)

	# Turn manager proxy (for EffectResolver DRAW / GRANT_MANA etc.)
	turn_manager = SimTurnManager.new()
	turn_manager.setup(self)

	# Hardcoded effect resolver
	_hardcoded = HardcodedEffects.new()
	_hardcoded.setup(self)

	# Draw opening hands
	_draw_player(3)
	_draw_enemy(5)

# ---------------------------------------------------------------------------
# Signal handlers — called by CombatManager
# ---------------------------------------------------------------------------

func _on_minion_vanished(minion: MinionInstance) -> void:
	player_board.erase(minion)
	enemy_board.erase(minion)
	# Clear the slot so it can be reused
	for slot in player_slots:
		if slot.minion == minion:
			slot.minion = null
			break
	for slot in enemy_slots:
		if slot.minion == minion:
			slot.minion = null
			break
	# Fire death trigger AFTER removal so passive recalculations see the correct board state
	if trigger_manager != null:
		var event := Enums.TriggerEvent.ON_PLAYER_MINION_DIED if minion.owner == "player" \
			else Enums.TriggerEvent.ON_ENEMY_MINION_DIED
		var ctx := EventContext.make(event, minion.owner)
		ctx.minion = minion
		trigger_manager.fire(ctx)

func _on_hero_damaged(target: String, amount: int) -> void:
	if target == "player":
		player_hp -= amount
		if player_hp <= 0 and winner.is_empty():
			winner = "enemy"
	else:
		enemy_hp -= amount
		if enemy_hp <= 0 and winner.is_empty():
			winner = "player"

func _on_hero_healed(target: String, amount: int) -> void:
	if target == "player":
		player_hp += amount
	else:
		enemy_hp += amount

# ---------------------------------------------------------------------------
# Scene API — called by EffectResolver
# ---------------------------------------------------------------------------

func _friendly_board(owner: String) -> Array:
	return player_board if owner == "player" else enemy_board

func _opponent_board(owner: String) -> Array:
	return enemy_board if owner == "player" else player_board

func _spell_dmg(minion: MinionInstance, amount: int) -> void:
	combat_manager.apply_spell_damage(minion, amount)

func _summon_token(card_id: String, owner: String, token_atk: int, token_hp: int, token_shield: int) -> void:
	var base := CardDatabase.get_card(card_id)
	if base == null or not (base is MinionCardData):
		return
	var board := player_board if owner == "player" else enemy_board
	var slots := player_slots if owner == "player" else enemy_slots
	# Find an empty slot
	var slot: BoardSlot = null
	for s in slots:
		if s.is_empty():
			slot = s
			break
	if slot == null:
		return  # board full
	# Duplicate card data to override stats without corrupting the original
	var mc := (base as MinionCardData).duplicate() as MinionCardData
	if token_atk > 0:    mc.atk        = token_atk
	if token_hp > 0:     mc.health     = token_hp
	if token_shield > 0: mc.shield_max = token_shield
	var instance := MinionInstance.create(mc, owner)
	board.append(instance)
	slot.place_minion(instance)
	if trigger_manager != null:
		var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" \
			else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
		var ctx := EventContext.make(event, owner)
		ctx.minion = instance
		ctx.card   = mc
		trigger_manager.fire(ctx)

func _corrupt_minion(target: MinionInstance) -> void:
	BuffSystem.apply(target, Enums.BuffType.CORRUPTION, 100, "corruption")

func _apply_void_mark(amount: int) -> void:
	enemy_void_marks += amount

func _deal_void_bolt_damage(amount: int) -> void:
	for m in enemy_board.duplicate():
		combat_manager.apply_spell_damage(m, amount)

func _log(_msg: Variant, _type: int = 0) -> void:
	pass  # no logging in headless sim

func _refresh_slot_for(_target) -> void:
	pass  # no UI

func _opponent_of(owner: String) -> String:
	return "enemy" if owner == "player" else "player"

func _find_random_enemy_minion() -> MinionInstance:
	return _find_random_minion(enemy_board)

func _find_random_minion(board: Array) -> MinionInstance:
	if board.is_empty():
		return null
	return board[randi() % board.size()]

func _refresh_dominion_aura(_active: bool, _amount: int = 100) -> void:
	pass  # no aura UI in sim

func _find_last_non_echo_rune() -> TrapCardData:
	for i in range(active_traps.size() - 1, -1, -1):
		var t := active_traps[i] as TrapCardData
		if t.is_rune and t.id != "echo_rune":
			return t
	return null

func _resolve_void_devourer_sacrifice(_devourer: MinionInstance, _owner: String) -> void:
	pass  # complex effect — not simulated

func _remove_rune_aura(rune: TrapCardData) -> void:
	for i in _rune_aura_handlers.size():
		if _rune_aura_handlers[i].rune_id == rune.id:
			for entry in _rune_aura_handlers[i].entries:
				trigger_manager.unregister(entry.event, entry.handler)
			_rune_aura_handlers.remove_at(i)
			break
	if not rune.aura_on_remove_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		EffectResolver.run(rune.aura_on_remove_steps, ctx)

func _unregister_env_rituals() -> void:
	for h in _env_ritual_handlers:
		trigger_manager.unregister(Enums.TriggerEvent.ON_RUNE_PLACED, h)
		trigger_manager.unregister(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, h)
	_env_ritual_handlers.clear()

func _update_trap_display() -> void:
	pass  # no UI

func _update_environment_display() -> void:
	pass  # no UI

func _rune_aura_multiplier() -> int:
	return 2 if "runic_attunement" in talents else 1

func _minion_has_tag(minion: MinionInstance, tag: String) -> bool:
	if minion.card_data is MinionCardData:
		return tag in (minion.card_data as MinionCardData).minion_tags
	return false

func _has_talent(talent_id: String) -> bool:
	return talent_id in talents

func _resolve_hardcoded(hardcoded_id: String, ctx: EffectContext) -> void:
	_hardcoded.resolve(hardcoded_id, ctx)

# ---------------------------------------------------------------------------
# Rune / trap / ritual / environment infrastructure
# ---------------------------------------------------------------------------

## Register persistent aura handlers for a newly placed rune.
func _apply_rune_aura(rune: TrapCardData) -> void:
	var entries: Array = []
	if rune.aura_trigger >= 0 and not rune.aura_effect_steps.is_empty():
		var h := func(event_ctx: EventContext):
			var ctx := EffectContext.make(self, "player")
			ctx.trigger_minion = event_ctx.minion
			EffectResolver.run(rune.aura_effect_steps, ctx)
		trigger_manager.register(rune.aura_trigger, h, 20)
		entries.append({event = rune.aura_trigger, handler = h})
	if rune.aura_secondary_trigger >= 0 and not rune.aura_secondary_steps.is_empty():
		var h2 := func(event_ctx: EventContext):
			var ctx := EffectContext.make(self, "player")
			ctx.trigger_minion = event_ctx.minion
			EffectResolver.run(rune.aura_secondary_steps, ctx)
		trigger_manager.register(rune.aura_secondary_trigger, h2, 20)
		entries.append({event = rune.aura_secondary_trigger, handler = h2})
	if not rune.aura_on_place_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		EffectResolver.run(rune.aura_on_place_steps, ctx)
	if not entries.is_empty():
		_rune_aura_handlers.append({rune_id = rune.id, entries = entries})

## Register 2-rune ritual handlers for the given environment.
func _register_env_rituals(env: EnvironmentCardData) -> void:
	for ritual in env.rituals:
		var r: RitualData = ritual
		var h := func(_ctx: EventContext): _handlers_ref.on_env_ritual(r)
		_env_ritual_handlers.append(h)
		trigger_manager.register(Enums.TriggerEvent.ON_RUNE_PLACED, h, 5)
		trigger_manager.register(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, h, 5)

## Run teardown steps for the outgoing environment.
func _unregister_env_aura(env: EnvironmentCardData) -> void:
	if not env.on_replace_effect_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		EffectResolver.run(env.on_replace_effect_steps, ctx)

## Fire matching non-rune traps for the given trigger event.
func _check_and_fire_traps(trigger: int, triggering_minion: MinionInstance = null) -> void:
	for trap in active_traps.duplicate():
		if trap.is_rune:
			continue
		if trap.trigger != trigger:
			continue
		var ctx := EffectContext.make(self, "player")
		ctx.trigger_minion = triggering_minion
		EffectResolver.run(trap.effect_steps, ctx)
		if not trap.reusable:
			active_traps.erase(trap)

## Returns true if the rune board satisfies the ritual's required rune types.
func _runes_satisfy(runes: Array, required: Array[int]) -> bool:
	var available: Array[int] = []
	for r in runes:
		available.append((r as TrapCardData).rune_type)
	for req in required:
		if req not in available:
			return false
	return true

## Consume the required runes and cast the ritual effect.
func _fire_ritual(ritual: RitualData) -> void:
	for req in ritual.required_runes:
		for i in active_traps.size():
			if active_traps[i].is_rune and active_traps[i].rune_type == req:
				_remove_rune_aura(active_traps[i])
				active_traps.remove_at(i)
				break
	var ritual_ctx := EffectContext.make(self, "player")
	EffectResolver.run(ritual.effect_steps, ritual_ctx)
	if "ritual_surge" in talents:
		_summon_void_imp()
		_summon_void_imp()

## Draw a random Rune card from the player's deck into hand.
func _draw_rune_from_deck() -> void:
	var runes_in_deck: Array = []
	for c in player_deck:
		if c is TrapCardData and (c as TrapCardData).is_rune:
			runes_in_deck.append(c)
	if runes_in_deck.is_empty():
		return
	var chosen: CardData = runes_in_deck[randi() % runes_in_deck.size()]
	player_deck.erase(chosen)
	if player_hand.size() < PLAYER_HAND_MAX:
		player_hand.append(chosen)

## Summon a Void Imp token on the player board (used by ritual_surge talent).
func _summon_void_imp() -> void:
	_summon_token("void_imp", "player", 0, 0, 0)

## Reference to the CombatHandlers instance — set by SimTriggerSetup for env rituals.
var _handlers_ref: CombatHandlers = null

# ---------------------------------------------------------------------------
# Card draw helpers
# ---------------------------------------------------------------------------

func _draw_player(count: int) -> void:
	for _i in count:
		if player_hand.size() >= PLAYER_HAND_MAX: break
		if player_deck.is_empty(): break  # finite deck — no reshuffle
		var card: CardData = player_deck.pop_front()
		player_hand.append(card)
		if trigger_manager != null:
			var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, "player")
			ctx.card = card
			trigger_manager.fire(ctx)

func _draw_enemy(count: int) -> void:
	for _i in count:
		if enemy_hand.size() >= ENEMY_HAND_MAX: break
		if enemy_deck.is_empty():
			if enemy_discard.is_empty(): break
			enemy_deck = enemy_discard.duplicate()
			enemy_discard.clear()
			enemy_deck.shuffle()
		enemy_hand.append(enemy_deck.pop_front())

# ---------------------------------------------------------------------------
# Turn helpers — called by CombatSim
# ---------------------------------------------------------------------------

func begin_player_turn(turn_number: int) -> void:
	_grow_player_resources(turn_number)
	player_essence = player_essence_max
	player_mana    = player_mana_max
	imp_evolution_used_this_turn = false
	if trigger_manager != null:
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_PLAYER_TURN_START))
	_draw_player(1)
	_unexhaust_board(player_board)

func begin_enemy_turn(turn_number: int) -> void:
	_grow_enemy_resources(turn_number)
	enemy_essence = enemy_essence_max
	enemy_mana    = enemy_mana_max
	if trigger_manager != null:
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_ENEMY_TURN_START))
	_draw_enemy(1)
	_unexhaust_board(enemy_board)

func _grow_player_resources(turn_number: int) -> void:
	if turn_number <= 1: return
	if player_essence_max + player_mana_max >= COMBINED_RESOURCE_CAP: return
	if player_mana_max < player_essence_max - 2:
		player_mana_max += 1
	else:
		player_essence_max += 1

func _grow_enemy_resources(turn_number: int) -> void:
	if turn_number <= 1: return
	if enemy_essence_max + enemy_mana_max >= COMBINED_RESOURCE_CAP: return
	if enemy_mana_max < enemy_essence_max - 2:
		enemy_mana_max += 1
	else:
		enemy_essence_max += 1

func _unexhaust_board(board: Array[MinionInstance]) -> void:
	for minion in board:
		minion.on_turn_start()
