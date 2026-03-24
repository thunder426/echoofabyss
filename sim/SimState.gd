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

var active_traps:       Array       = []   ## Array[TrapCardData]
var active_environment              = null ## EnvironmentCardData or null
var enemy_void_marks:   int         = 0

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

func _remove_rune_aura(_trap) -> void:
	pass  # no aura state in sim

func _unregister_env_rituals() -> void:
	pass  # no ritual state in sim

func _update_trap_display() -> void:
	pass  # no UI

func _update_environment_display() -> void:
	pass  # no UI

func _rune_aura_multiplier() -> int:
	return 0  # no rune auras in headless sim

func _minion_has_tag(minion: MinionInstance, tag: String) -> bool:
	if minion.card_data is MinionCardData:
		return tag in (minion.card_data as MinionCardData).minion_tags
	return false

func _has_talent(talent_id: String) -> bool:
	return talent_id in talents

func _resolve_hardcoded(_hardcoded_id: String, _ctx: EffectContext) -> void:
	pass  # hardcoded effects not simulated

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
