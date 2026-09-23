## SimState.gd
## Headless simulation shell over CombatState: setup, the sim turn engine, the
## profile hooks CombatSim needs, and the BuffSystem bus bridge. All gameplay
## rules live on CombatState (plan 1.4 — lint L5 keeps it that way).
## No scene tree, no timers, no UI.
##
## CombatSim creates one of these, builds two CombatAgents on top of it,
## and runs two CombatProfiles against each other.
class_name SimState
extends CombatState

## Callable SimTriggerSetup registered on BuffSystem.bus() for corruption_removed.
## Stored so teardown() can cleanly disconnect and avoid cross-sim leaks.
var _buff_bus_callable: Callable = Callable()

## Active enemy CombatProfile reference — CombatSim re-reads this each turn so
## the F15 phase transition can swap profiles mid-run.
var _e_profile: CombatProfile = null
## Factory callable (profile_id: String) -> CombatProfile. Bound by CombatSim.
var _e_profile_factory: Callable = Callable()

## AI profile id currently driving the enemy (sim mirror of EnemyAI.ai_profile).
var enemy_ai_profile: String = ""

## The enemy's sim agent (set by SimEnemyAgent.setup).
var enemy_ai: SimEnemyAgent

## Print every combat-log line (DebugSingleSim).
var debug_log_enabled: bool = false

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(p_deck_ids: Array[String], e_deck_ids: Array[String],
		p_hp: int = 3000, e_hp: int = 2000) -> void:
	player_hp_max = p_hp
	enemy_hp_max  = e_hp
	player_hp = p_hp
	enemy_hp  = e_hp

	# Build + shuffle both decks (combat-time lookup, so overrides apply). The
	# enemy draws its opening 5 inside setup_deck; the player's 3 are drawn below.
	setup_deck("player", p_deck_ids)
	setup_deck("enemy", e_deck_ids)

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

	combat_manager = CombatManager.new()
	combat_manager.scene = self
	combat_manager.minion_vanished.connect(_on_minion_vanished)
	combat_manager.hero_damaged.connect(_on_hero_damaged)
	combat_manager.hero_healed.connect(_on_hero_healed)

	damage_dealt.connect(_capture_damage_for_dmg_log)
	combat_log.connect(_print_debug_log)

	turn_manager = SimTurnManager.new()
	turn_manager.setup(self)

	_hardcoded = HardcodedEffects.new()
	_hardcoded.setup(self)

	draw_cards("player", 3)

## dmg_log: damage dealt to the enemy hero, by source. Skips "__logged__"
## entries (Void Bolt split-logs its base + mark bonus at the source — see
## _deal_void_bolt_damage).
func _capture_damage_for_dmg_log(source: String, target: String, amount: int, _school: int, _was_crit: bool) -> void:
	if not dmg_log_enabled or target != "enemy":
		return
	if source == "__logged__":
		return
	dmg_log.append({turn = turn_number, amount = amount, source = source})

func _print_debug_log(msg: String, _log_type: int) -> void:
	if debug_log_enabled:
		print(msg)

## Forwards BuffSystem.corruption_removed into this sim's TriggerManager so
## Corrupt Detonation (and other ON_CORRUPTION_REMOVED listeners) fire during sims.
## Hero targets currently have no listeners — silently skip rather than fabricate
## a minion-shaped EventContext.
func _on_corruption_removed_bus(target: Object, stacks: int) -> void:
	if trigger_manager == null or target == null or stacks <= 0:
		return
	if not (target is MinionInstance):
		return
	var minion: MinionInstance = target
	var ctx := EventContext.make(Enums.TriggerEvent.ON_CORRUPTION_REMOVED, minion.owner)
	ctx.minion = minion
	ctx.damage = stacks
	trigger_manager.fire(ctx)

## Disconnect global-bus subscriptions and drop references so this sim instance
## can be freed cleanly and its callbacks don't leak into the next sim run.
func teardown() -> void:
	var buff_bus: Object = BuffSystem.bus()
	if buff_bus != null and _buff_bus_callable.is_valid():
		if buff_bus.is_connected("corruption_removed", _buff_bus_callable):
			buff_bus.disconnect("corruption_removed", _buff_bus_callable)
	_buff_bus_callable = Callable()

# ---------------------------------------------------------------------------
# Turn helpers — called by CombatSim (the shared turn engine replaces these in 2A.3)
# ---------------------------------------------------------------------------

## Optional override set by a CombatProfile to replace the default resource-growth logic.
## Signature: func(turn_number: int) -> void
var player_growth_override: Callable = Callable()
var enemy_growth_override: Callable = Callable()

func begin_player_turn(turn: int) -> void:
	turn_number = turn
	is_player_turn = true
	if player_growth_override.is_valid():
		player_growth_override.call(turn)
	else:
		_grow_player_resources(turn)
	player_essence = player_essence_max
	player_mana    = player_mana_max
	player_spell_cost_penalty = _spell_tax_for_player_turn
	_spell_tax_for_player_turn = 0
	if _void_mana_drain_pending:
		_void_mana_drain_pending = false
		player_mana = 0
	for inst in player_hand:
		inst.reset_deltas()
	_fiendish_pact_pending = 0
	_once_per_turn_used.clear()
	if trigger_manager != null:
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_PLAYER_TURN_START))
	draw_cards("player", 1)
	_unexhaust_board(player_board)

func end_player_turn() -> void:
	if trigger_manager:
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_PLAYER_TURN_END, "player"))
	player_spell_cost_penalty = 0
	_enemy_traps_blocked = false

func begin_enemy_turn(turn: int) -> void:
	is_player_turn = false
	if enemy_growth_override.is_valid():
		enemy_growth_override.call(turn)
	else:
		_grow_enemy_resources(turn)
	enemy_essence = enemy_essence_max
	enemy_mana    = enemy_mana_max
	if _enemy_void_mana_drain_pending:
		_enemy_void_mana_drain_pending = false
		enemy_mana = 0
	enemy_spell_cost_penalty = _spell_tax_for_enemy_turn
	_spell_tax_for_enemy_turn = 0
	_enemy_fiendish_pact_pending = 0
	if trigger_manager != null:
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_ENEMY_TURN_START))
	draw_cards("enemy", 1)
	_unexhaust_board(enemy_board)

func end_enemy_turn() -> void:
	# Fire ON_ENEMY_TURN_END before cleanup (void_unraveling spark transfer)
	if trigger_manager:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_TURN_END, "enemy")
		trigger_manager.fire(ctx)
	enemy_spell_cost_penalty = 0
	_player_traps_blocked = false

func _grow_player_resources(turn: int) -> void:
	if turn <= 1: return
	if player_essence_max + player_mana_max >= COMBINED_RESOURCE_CAP: return
	if player_mana_max < player_essence_max - 2:
		player_mana_max += 1
		last_player_growth = "mana"
	else:
		player_essence_max += 1
		last_player_growth = "essence"

func _grow_enemy_resources(turn: int) -> void:
	if turn <= 1: return
	if enemy_essence_max + enemy_mana_max >= COMBINED_RESOURCE_CAP: return
	if enemy_mana_max < enemy_essence_max - 2:
		enemy_mana_max += 1
	else:
		enemy_essence_max += 1

func _unexhaust_board(board: Array[MinionInstance]) -> void:
	for minion in board:
		minion.on_turn_start()
