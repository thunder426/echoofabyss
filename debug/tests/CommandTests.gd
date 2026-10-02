## CommandTests.gd
## Layer 5: CombatState commands (LIVE_SIM_UNIFICATION_PLAN.md 2A.1). One probe
## per command for the happy path and for refusals — a refused command must
## return ok=false and leave the state (digest + command_log) untouched.
class_name CommandTests
extends RefCounted

static func run_all() -> void:
	print("\n=== Layer 5: Command Tests ===")
	_refusals_change_nothing()
	_play_minion_player_pays_once()
	_play_minion_event_order()
	_slots_are_engine_slot_states()
	_journal_buff_applied_before_after()
	_journal_order_spell_kill_on_death_summon()
	_play_minion_enemy_target_and_discount()
	_play_minion_fiendish_pact()
	_play_spell_cast_event_before_resolution()
	_play_spell_cancelled_by_silence()
	_play_spell_countered()
	_play_spell_spark_fuel()
	_play_trap_both_sides_fire_placed()
	_play_trap_slot_cap_and_duplicate()
	_play_environment_replace_both_halves()
	_attack_guard_validation()
	_attack_enemy_cancelled_by_smoke_veil()
	_attack_hero()
	_consume_minion()
	_activate_relic()
	_hero_skill()
	_command_log_records_targets_by_slot()
	_turn_start_order_player()
	_turn_start_order_enemy()
	_end_turn_growth_applies_next_turn()
	_turn_start_expires_temp_buffs()
	_growth_curves_match_the_ported_sim_curves()
	_encounter_table_is_the_one_source()
	await _profile_play_pays_once()
	await _agent_spark_fuel_is_credited()
	_default_bot_void_execution_needs_a_human()
	_teardown_frees_the_fight()
	await _sim_run_frees_the_fight()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _hand_card(state: CombatState, side: String, id: String) -> CardInstance:
	return state.add_to_hand(side, CardDatabase.get_card(id))

static func _set_res(state: CombatState, side: String, essence: int, mana: int) -> void:
	state.set_essence(side, essence)
	state.set_mana(side, mana)

static func _ready_minion(state: CombatState, side: String, id: String) -> MinionInstance:
	var m: MinionInstance = TestHarness.spawn_friendly(state, id) if side == "player" else TestHarness.spawn_enemy(state, id)
	m.state = Enums.MinionState.NORMAL
	return m

static func _enemy_turn(state: CombatState) -> void:
	state.is_player_turn = false

static func _snap(state: CombatState) -> String:
	return "%s\nlog %d" % [state.digest_text(), state.command_log.size()]

static func _assert_refused(state: CombatState, r: CommandResult, reason: String, before: String, label: String) -> void:
	TestHarness.assert_false(r.ok, "%s: refused" % label)
	TestHarness.assert_eq(r.reason, reason, "%s: reason" % label)
	TestHarness.assert_eq(_snap(state), before, "%s: nothing changed" % label)

# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

static func _refusals_change_nothing() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / refusals change nothing", state):
		return
	var imp := _hand_card(state, "player", "void_imp")
	var brute := _hand_card(state, "player", "abyssal_brute")
	_set_res(state, "player", 1, 0)
	var before := _snap(state)
	_assert_refused(state, state.cmd_play_minion("player", brute, 0), "cost", before, "unaffordable minion")
	_assert_refused(state, state.cmd_play_minion("player", imp, 9), "bad_slot", before, "bad slot")
	TestHarness.spawn_friendly_at(state, "void_imp", 0)
	before = _snap(state)
	_assert_refused(state, state.cmd_play_minion("player", imp, 0), "slot_occupied", before, "occupied slot")
	var enemy_imp := _hand_card(state, "enemy", "rabid_imp")
	before = _snap(state)
	_assert_refused(state, state.cmd_play_minion("player", enemy_imp, 1), "not_in_hand", before, "card not in own hand")
	_assert_refused(state, state.cmd_play_minion("enemy", enemy_imp, 1), "not_your_turn", before, "off-turn play")
	_assert_refused(state, state.cmd_play_spell("player", imp, null), "wrong_card_type", before, "minion as spell")
	state.winner = "enemy"
	before = _snap(state)
	_assert_refused(state, state.cmd_play_minion("player", imp, 1), "combat_over", before, "after combat end")
	state.teardown()

# ---------------------------------------------------------------------------
# Minions
# ---------------------------------------------------------------------------

static func _play_minion_player_pays_once() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / play_minion pays the cost exactly once", state):
		return
	var hound := _hand_card(state, "player", "shadow_hound")
	_set_res(state, "player", 5, 3)
	var hand_before := state.player_hand.size()
	var r := state.cmd_play_minion("player", hound, 2)
	TestHarness.assert_true(r.ok, "accepted")
	TestHarness.assert_eq(state.player_essence, 3, "2 Essence paid once")
	TestHarness.assert_eq(state.player_mana, 3, "Mana untouched")
	TestHarness.assert_eq(state.player_hand.size(), hand_before - 1, "left the hand")
	TestHarness.assert_true(state.player_graveyard.has(hound), "card in graveyard")
	TestHarness.assert_eq(state.player_slots[2].minion.card_data.id, "shadow_hound", "placed in slot 2")
	TestHarness.assert_eq(state.command_log.size(), 1, "logged once")
	state.teardown()

## Plan 3.1a (D11): the engine owns plain SlotStates; place / clear stamp
## slot_index and emit slot_changed so the live view can follow.
static func _slots_are_engine_slot_states() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / slots are engine SlotStates: place / clear emit slot_changed", state):
		return
	var seen: Array = []
	state.slot_changed.connect(func(side: String, index: int) -> void: seen.append("%s:%d" % [side, index]))
	TestHarness.assert_true(state.player_slots[0] is SlotState, "player slot is a SlotState")
	TestHarness.assert_eq(state.player_slots.size(), CombatState.BOARD_MAX, "BOARD_MAX player slots")
	TestHarness.assert_eq(state.enemy_slots.size(), CombatState.BOARD_MAX, "BOARD_MAX enemy slots")
	TestHarness.assert_eq(state.enemy_slots[4].side, "enemy", "side stamped")
	TestHarness.assert_eq(state.enemy_slots[4].index, 4, "index stamped")
	var hound := _hand_card(state, "player", "shadow_hound")
	_set_res(state, "player", 5, 3)
	state.cmd_play_minion("player", hound, 3)
	var m: MinionInstance = state.player_slots[3].minion
	TestHarness.assert_true(m != null, "placed in slot 3")
	TestHarness.assert_eq(m.slot_index, 3, "slot_index stamped by place")
	TestHarness.assert_true(state.slot_for(m) == state.player_slots[3], "slot_for finds it")
	TestHarness.assert_true(state.slot_of("player", 3).minion == m, "slot_of reads it")
	TestHarness.assert_true(state.slot_of("player", 9) == null, "slot_of off-board is null")
	TestHarness.assert_eq(seen, ["player:3"], "slot_changed once on place")
	seen.clear()
	state.combat_manager.kill_minion(m)
	TestHarness.assert_true(state.player_slots[3].is_empty(), "slot freed on death")
	TestHarness.assert_true(state.slot_for(m) == null, "slot_for null after death")
	TestHarness.assert_eq(seen, ["player:3"], "slot_changed once on clear")
	state.teardown()

## Plan 3.1: BUFF_APPLIED carries the pre/post stats.
static func _journal_buff_applied_before_after() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("journal / BUFF_APPLIED carries before and after", state):
		return
	var imp := TestHarness.spawn_friendly_at(state, "void_imp", 0)
	var spell := TestHarness.make_test_spell([
		{"type": "BUFF_ATK", "scope": "SINGLE_CHOSEN", "amount": 200, "permanent": true}], "_j_buff", 0)
	var inst := state.add_to_hand("player", spell)
	var atk_before: int = imp.effective_atk()
	var start: int = state.journal.size()
	TestHarness.assert_true(state.cmd_play_spell("player", inst, imp).ok, "cast")
	var found: CombatEvent = null
	for i in range(start, state.journal.size()):
		var ev: CombatEvent = state.journal[i]
		if ev.kind == CombatEvent.Kind.BUFF_APPLIED:
			found = ev
			break
	TestHarness.assert_true(found != null, "BUFF_APPLIED journaled")
	if found != null:
		TestHarness.assert_eq(found.payload["minion"], imp, "minion")
		TestHarness.assert_eq(found.payload["atk_before"], atk_before, "atk_before")
		TestHarness.assert_eq(found.payload["atk_after"], atk_before + 200, "atk_after")
		TestHarness.assert_eq(found.payload["hp_before"], found.payload["hp_after"], "hp unchanged")
		TestHarness.assert_eq(found.side, "player", "side")
		TestHarness.assert_eq(found.seq, state.journal.find(found), "seq is the journal index")
	state.teardown()

## Plan 3.1 / 3.5: a spell that kills a minion with an on-death summon journals
## [SPELL_CAST, DAMAGE_DEALT, MINION_DIED, TOKEN_SUMMONED, SPELL_RESOLVED].
static func _journal_order_spell_kill_on_death_summon() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("journal / order: cast, damage, death, on-death summon, resolved", state):
		return
	var victim := TestHarness.spawn_enemy_at(state, "void_imp", 0)
	victim.granted_on_death_effects = [{"summon_id": "void_spark"}]
	var spell := TestHarness.make_test_spell([
		{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 900, "damage_school": "ARCANE"}], "_j_bolt", 0)
	var inst := state.add_to_hand("player", spell)
	var start: int = state.journal.size()
	TestHarness.assert_true(state.cmd_play_spell("player", inst, victim).ok, "cast")
	var watched: Array = [CombatEvent.Kind.SPELL_CAST, CombatEvent.Kind.DAMAGE_DEALT, CombatEvent.Kind.MINION_DIED,
			CombatEvent.Kind.TOKEN_SUMMONED, CombatEvent.Kind.SPELL_RESOLVED]
	var kinds: Array = []
	for i in range(start, state.journal.size()):
		var ev: CombatEvent = state.journal[i]
		if ev.kind in watched:
			kinds.append(ev.kind_name())
	TestHarness.assert_eq(kinds, ["SPELL_CAST", "DAMAGE_DEALT", "MINION_DIED", "TOKEN_SUMMONED", "SPELL_RESOLVED"], "journal order")
	TestHarness.assert_true(state.enemy_board.size() == 1 and state.enemy_board[0].card_data.id == "void_spark", "spark on the board")
	state.teardown()

static func _play_minion_event_order() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / play_minion: PLAYED before joining the board, SUMMONED after", state):
		return
	var seen: Dictionary = {}
	state.trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, func(ctx: EventContext) -> void:
		seen["played_on_board"] = state.player_board.has(ctx.minion)
		seen["played_in_slot"] = state.player_slots[0].minion == ctx.minion, 0)
	state.trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, func(ctx: EventContext) -> void:
		seen["summoned_on_board"] = state.player_board.has(ctx.minion), 0)
	var imp := _hand_card(state, "player", "void_imp")
	_set_res(state, "player", 1, 0)
	state.cmd_play_minion("player", imp, 0)
	TestHarness.assert_eq(seen.get("played_on_board"), false, "PLAYED: not yet in board array")
	TestHarness.assert_eq(seen.get("played_in_slot"), true, "PLAYED: already in its slot")
	TestHarness.assert_eq(seen.get("summoned_on_board"), true, "SUMMONED: on the board")
	state.teardown()

static func _play_minion_enemy_target_and_discount() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / play_minion enemy: per-card discount, on-play target", state):
		return
	_enemy_turn(state)
	var target := _ready_minion(state, "player", "void_imp")
	var seen: Dictionary = {}
	state.trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_PLAYED, func(_ctx: EventContext) -> void:
		seen["target"] = state.enemy_play_target, 0)
	state.enemy_essence_cost_discounts["shadow_hound"] = 1
	var hound := _hand_card(state, "enemy", "shadow_hound")
	_set_res(state, "enemy", 1, 0)
	var r := state.cmd_play_minion("enemy", hound, 0, target)
	TestHarness.assert_true(r.ok, "accepted at 1 Essence (2 - 1 discount)")
	TestHarness.assert_eq(state.enemy_essence, 0, "paid 1")
	TestHarness.assert_eq(seen.get("target"), target, "handler sees the chosen target")
	TestHarness.assert_eq(state.enemy_board.size(), 1, "on the enemy board")
	state.teardown()

static func _play_minion_fiendish_pact() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("commands / play_minion consumes the Fiendish Pact discount", state):
		return
	state._fiendish_pact_pending = 2
	var demon_id := "grafted_fiend"
	var demon := _hand_card(state, "player", demon_id)
	var full: int = (demon.card_data as MinionCardData).essence_cost
	_set_res(state, "player", 5, 5)
	var r := state.cmd_play_minion("player", demon, 0)
	TestHarness.assert_true(r.ok, "accepted")
	TestHarness.assert_eq(state.player_essence, 5 - maxi(0, full - 2), "paid the discounted cost")
	TestHarness.assert_eq(state._fiendish_pact_pending, 0, "pact consumed")
	state.teardown()

# ---------------------------------------------------------------------------
# Spells
# ---------------------------------------------------------------------------

static func _play_spell_cast_event_before_resolution() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / play_spell fires ON_PLAYER_SPELL_CAST before it resolves (D8)", state):
		return
	var victim := TestHarness.spawn_enemy(state, "abyssal_brute")
	var spell := TestHarness.make_test_spell([
		{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 200, "damage_school": "ARCANE"}], "_cmd_bolt", 2)
	var inst := state.add_to_hand("player", spell)
	var seen: Dictionary = {}
	state.trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, func(_ctx: EventContext) -> void:
		seen["hp_at_cast"] = victim.current_health, 0)
	_set_res(state, "player", 0, 3)
	var hp_before := victim.current_health
	var r := state.cmd_play_spell("player", inst, victim)
	TestHarness.assert_true(r.ok, "accepted")
	TestHarness.assert_eq(seen.get("hp_at_cast"), hp_before, "event saw the pre-damage board")
	TestHarness.assert_eq(victim.current_health, hp_before - 200, "then it resolved")
	TestHarness.assert_eq(state.player_mana, 1, "2 Mana paid once")
	state.teardown()

static func _play_spell_cancelled_by_silence() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / play_spell cancelled in ON_*_SPELL_CAST resolves nothing", state):
		return
	var victim := TestHarness.spawn_enemy(state, "abyssal_brute")
	var spell := TestHarness.make_test_spell([
		{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 200, "damage_school": "ARCANE"}], "_cmd_bolt", 1)
	var inst := state.add_to_hand("player", spell)
	state.trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, func(_ctx: EventContext) -> void:
		state._spell_cancelled = true, 0)
	_set_res(state, "player", 0, 1)
	var hp_before := victim.current_health
	var r := state.cmd_play_spell("player", inst, victim)
	TestHarness.assert_eq(r.reason, "cancelled", "reported cancelled")
	TestHarness.assert_eq(victim.current_health, hp_before, "no damage")
	TestHarness.assert_eq(state.player_mana, 0, "cost still paid")
	TestHarness.assert_false(state._spell_cancelled, "flag consumed")
	state.teardown()

static func _play_spell_countered() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / play_spell: Phase Disruptor counter stops it before the event", state):
		return
	_enemy_turn(state)
	var spell := TestHarness.make_test_spell([
		{"type": "DAMAGE_HERO", "amount": 300, "damage_school": "ARCANE"}], "_cmd_zap", 1)
	var inst := state.add_to_hand("enemy", spell)
	var fired: Array = [false]
	state.trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, func(_ctx: EventContext) -> void:
		fired[0] = true, 0)
	state._enemy_spell_counter = 1
	_set_res(state, "enemy", 0, 1)
	var hp_before := state.player_hp
	var r := state.cmd_play_spell("enemy", inst, null)
	TestHarness.assert_eq(r.reason, "countered", "reported countered")
	TestHarness.assert_eq(state.player_hp, hp_before, "no damage")
	TestHarness.assert_false(fired[0], "ON_ENEMY_SPELL_CAST not fired")
	TestHarness.assert_eq(state._enemy_spell_counter, 0, "counter used")
	state.teardown()

static func _play_spell_spark_fuel() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / play_spell spark cost: caller's fuel, else the engine's pick", state):
		return
	_enemy_turn(state)
	var w1 := TestHarness.spawn_enemy(state, "void_wisp")
	var w2 := TestHarness.spawn_enemy(state, "void_wisp")
	var w3 := TestHarness.spawn_enemy(state, "void_wisp")
	var spell := TestHarness.make_test_spell([], "_cmd_spark_spell", 1)
	spell.void_spark_cost = 2
	var inst := state.add_to_hand("enemy", spell)
	_set_res(state, "enemy", 0, 1)
	var before := _snap(state)
	_assert_refused(state, state.cmd_play_spell("enemy", inst, null, {"spark_fuel": [w1]}), "sparks", before, "short fuel")
	var r := state.cmd_play_spell("enemy", inst, null, {"spark_fuel": [w1, w3]})
	TestHarness.assert_true(r.ok, "accepted with 2 fuel")
	TestHarness.assert_false(state.enemy_board.has(w1) or state.enemy_board.has(w3), "the picked fuel was consumed")
	TestHarness.assert_true(state.enemy_board.has(w2), "the other wisp stayed")
	var inst2 := state.add_to_hand("enemy", spell)
	TestHarness.spawn_enemy(state, "void_wisp")
	_set_res(state, "enemy", 0, 1)
	r = state.cmd_play_spell("enemy", inst2, null)
	TestHarness.assert_true(r.ok, "accepted with the engine's pick")
	TestHarness.assert_eq(state.enemy_board.size(), 0, "engine consumed 2 wisps")
	state.teardown()

# ---------------------------------------------------------------------------
# Traps / environments
# ---------------------------------------------------------------------------

static func _play_trap_both_sides_fire_placed() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / play_trap fires ON_*_TRAP_PLACED on both sides (B6)", state):
		return
	var placed: Array = []
	state.trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TRAP_PLACED, func(_ctx: EventContext) -> void:
		placed.append("player"), 0)
	state.trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_TRAP_PLACED, func(_ctx: EventContext) -> void:
		placed.append("enemy"), 0)
	var p_trap := _hand_card(state, "player", "hidden_ambush")
	_set_res(state, "player", 0, 5)
	TestHarness.assert_true(state.cmd_play_trap("player", p_trap).ok, "player trap set")
	_enemy_turn(state)
	var e_trap := _hand_card(state, "enemy", "smoke_veil")
	_set_res(state, "enemy", 0, 5)
	TestHarness.assert_true(state.cmd_play_trap("enemy", e_trap).ok, "enemy trap set")
	TestHarness.assert_eq(placed, ["player", "enemy"], "both events fired")
	TestHarness.assert_eq(state.enemy_active_traps.size(), 1, "enemy trap in place")
	TestHarness.assert_eq(state.enemy_mana, 3, "enemy paid 2")
	state.teardown()

static func _play_trap_slot_cap_and_duplicate() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / play_trap refuses a duplicate trap and a 4th slot", state):
		return
	_set_res(state, "player", 0, 10)
	TestHarness.assert_true(state.cmd_play_trap("player", _hand_card(state, "player", "hidden_ambush")).ok, "first ambush")
	var dup := _hand_card(state, "player", "hidden_ambush")
	var before := _snap(state)
	_assert_refused(state, state.cmd_play_trap("player", dup), "duplicate_trap", before, "same trap twice")
	state.cmd_play_trap("player", _hand_card(state, "player", "void_rune"))
	state.cmd_play_trap("player", _hand_card(state, "player", "void_rune"))
	var fourth := _hand_card(state, "player", "smoke_veil")
	_set_res(state, "player", 0, 10)
	before = _snap(state)
	_assert_refused(state, state.cmd_play_trap("player", fourth), "trap_slots_full", before, "4th trap")
	state.teardown()

static func _play_environment_replace_both_halves() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / play_environment: replace tears down the old one for its owner", state):
		return
	_enemy_turn(state)
	# Both steps hit the owner's opponent, so the hero that loses HP shows whose
	# context each ran in: the old enemy environment's teardown must hit the player.
	var old_env := EnvironmentCardData.new()
	old_env.id = "_cmd_old_env"
	old_env.on_replace_effect_steps = [{"type": "DAMAGE_HERO", "amount": 50}]
	state.enemy_active_environment = old_env
	var new_env := EnvironmentCardData.new()
	new_env.id = "_cmd_new_env"
	new_env.cost = 1
	new_env.on_enter_effect_steps = [{"type": "DAMAGE_HERO", "amount": 100}]
	var inst := state.add_to_hand("enemy", new_env)
	_set_res(state, "enemy", 0, 1)
	var p_hp := state.player_hp
	var e_hp := state.enemy_hp
	var r := state.cmd_play_environment("enemy", inst)
	TestHarness.assert_true(r.ok, "accepted")
	TestHarness.assert_eq(state.enemy_active_environment, new_env, "enemy environment replaced")
	TestHarness.assert_eq(state.player_hp, p_hp - 150, "teardown + on-enter both ran as the enemy")
	TestHarness.assert_eq(state.enemy_hp, e_hp, "enemy hero untouched")
	TestHarness.assert_eq(state.active_environment, null, "player environment untouched")
	state.teardown()

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------

static func _attack_guard_validation() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / attack: Guard is enforced for both sides (B5)", state):
		return
	var p_atk := _ready_minion(state, "player", "shadow_hound")
	var e_guard := _ready_minion(state, "enemy", "abyssal_brute")
	var e_other := _ready_minion(state, "enemy", "void_imp")
	var before := _snap(state)
	_assert_refused(state, state.cmd_attack("player", p_atk, e_other), "guard", before, "player hits non-Guard")
	_assert_refused(state, state.cmd_attack_hero("player", p_atk), "guard", before, "player hits hero past Guard")
	TestHarness.assert_true(state.cmd_attack("player", p_atk, e_guard).ok, "player may hit the Guard")
	_enemy_turn(state)
	var e_atk := _ready_minion(state, "enemy", "abyssal_brute")  # 300/600 survives the trade
	var p_guard := _ready_minion(state, "player", "abyssal_brute")
	var p_other := _ready_minion(state, "player", "void_imp")
	before = _snap(state)
	_assert_refused(state, state.cmd_attack("enemy", e_atk, p_other), "guard", before, "enemy hits non-Guard")
	_assert_refused(state, state.cmd_attack_hero("enemy", e_atk), "guard", before, "enemy hits hero past Guard")
	TestHarness.assert_true(state.cmd_attack("enemy", e_atk, p_guard).ok, "enemy may hit the Guard")
	before = _snap(state)
	_assert_refused(state, state.cmd_attack("enemy", e_atk, p_guard), "cannot_attack", before, "exhausted attacker")
	state.teardown()

static func _attack_enemy_cancelled_by_smoke_veil() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / attack: Smoke Veil cancels the attack that triggered it", state):
		return
	state.active_traps.append(CardDatabase.get_card("smoke_veil") as TrapCardData)
	_enemy_turn(state)
	var e_atk := _ready_minion(state, "enemy", "shadow_hound")
	var hp_before := state.player_hp
	var r := state.cmd_attack_hero("enemy", e_atk)
	TestHarness.assert_eq(r.reason, "cancelled", "reported cancelled")
	TestHarness.assert_eq(state.player_hp, hp_before, "no damage")
	TestHarness.assert_false(state.attack_cancelled, "flag consumed")
	state.teardown()

static func _attack_hero() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / attack_hero: damage lands, SWIFT can't hit face", state):
		return
	var hound := _ready_minion(state, "player", "shadow_hound")
	var hp_before := state.enemy_hp
	TestHarness.assert_true(state.cmd_attack_hero("player", hound).ok, "accepted")
	TestHarness.assert_eq(state.enemy_hp, hp_before - hound.effective_atk(), "hero took the hit")
	TestHarness.assert_eq(hound.state, Enums.MinionState.EXHAUSTED, "attacker exhausted")
	var swift := _ready_minion(state, "player", "rabid_imp")
	swift.state = Enums.MinionState.SWIFT
	var before := _snap(state)
	_assert_refused(state, state.cmd_attack_hero("player", swift), "cannot_attack", before, "SWIFT at the hero")
	state.teardown()

# ---------------------------------------------------------------------------
# Consume / relic / hero skill
# ---------------------------------------------------------------------------

static func _consume_minion() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / consume_minion removes silently, fires SPARK_CONSUMED", state):
		return
	_enemy_turn(state)
	var wisp := TestHarness.spawn_enemy(state, "void_wisp")
	var events: Array = []
	state.trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_SPARK_CONSUMED, func(ctx: EventContext) -> void:
		events.append(ctx.damage), 0)
	var died: Array = [false]
	state.trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_DIED, func(_ctx: EventContext) -> void:
		died[0] = true, 0)
	TestHarness.assert_true(state.cmd_consume_minion("enemy", wisp).ok, "accepted")
	TestHarness.assert_false(state.enemy_board.has(wisp), "off the board")
	TestHarness.assert_eq(events, [1], "SPARK_CONSUMED with its spark value")
	TestHarness.assert_false(died[0], "no death event")
	state.teardown()

static func _activate_relic() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / activate_relic: Dark Mirror discount, Blood Chalice needs a target", state):
		return
	state.relic_runtime = RelicRuntime.new()
	state.relic_runtime.setup(["dark_mirror", "blood_chalice"])
	for rs: RelicRuntime.RelicState in state.relic_runtime.relics:
		rs.cooldown_remaining = 0  # relics start on cooldown
	var mirror: int = state.relic_runtime.find_by_id("dark_mirror")
	var chalice: int = state.relic_runtime.find_by_id("blood_chalice")
	TestHarness.assert_true(state.cmd_activate_relic(mirror).ok, "Dark Mirror")
	var hound := _hand_card(state, "player", "shadow_hound")
	_set_res(state, "player", 0, 0)
	TestHarness.assert_true(state.cmd_play_minion("player", hound, 0).ok, "2E minion free after Dark Mirror")
	var before := _snap(state)
	_assert_refused(state, state.cmd_activate_relic(chalice), "unavailable", before, "one relic per turn")
	state.relic_runtime.activated_this_turn = false
	before = _snap(state)
	_assert_refused(state, state.cmd_activate_relic(chalice), "no_target", before, "Blood Chalice without target")
	var victim := TestHarness.spawn_enemy(state, "abyssal_brute")
	var hp_before := victim.current_health
	TestHarness.assert_true(state.cmd_activate_relic(chalice, victim).ok, "Blood Chalice on a minion")
	TestHarness.assert_eq(victim.current_health, hp_before - 500, "500 to the chosen minion")
	state.teardown()

static func _hero_skill() -> void:
	var state := TestHarness.seris_state(["soul_forge"])
	if not TestHarness.begin_test("commands / hero_skill: soul_forge needs 3 Flesh", state):
		return
	var before := _snap(state)
	_assert_refused(state, state.cmd_hero_skill("player", "soul_forge"), "unavailable", before, "no Flesh")
	state.player_flesh = 3
	TestHarness.assert_true(state.cmd_hero_skill("player", "soul_forge").ok, "with 3 Flesh")
	TestHarness.assert_true(TestHarness.has_on_board(state, "player", "grafted_fiend"), "Grafted Fiend summoned")
	before = _snap(state)
	_assert_refused(state, state.cmd_hero_skill("player", "nope"), "no_skill", before, "unknown skill")
	state.teardown()

static func _command_log_records_targets_by_slot() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("commands / command_log records targets by slot and hero sentinel", state):
		return
	var hound := _ready_minion(state, "player", "shadow_hound")
	var victim := TestHarness.spawn_enemy_at(state, "void_imp", 3)
	state.cmd_attack("player", hound, victim)
	var rec: Dictionary = state.command_log[state.command_log.size() - 1]
	TestHarness.assert_eq(rec.get("cmd"), "attack", "cmd")
	TestHarness.assert_eq(rec.get("slot"), hound.slot_index, "attacker slot")
	TestHarness.assert_eq(rec.get("target"), {kind = "minion", side = "enemy", slot = 3}, "target by slot")
	var imp2 := _ready_minion(state, "player", "void_imp")
	state.cmd_attack_hero("player", imp2)
	rec = state.command_log[state.command_log.size() - 1]
	TestHarness.assert_eq(rec.get("target"), {kind = "hero", side = "enemy", slot = -1}, "hero sentinel")
	state.teardown()

# ---------------------------------------------------------------------------
# Turn engine (plan 2A.3)
# ---------------------------------------------------------------------------

static func _turn_start_order_player() -> void:
	var state := TestHarness.build_state({"player_deck": ["void_imp", "void_imp", "void_imp", "void_imp", "void_imp", "void_imp"]})
	if not TestHarness.begin_test("turn engine / player turn start: refill, draw, ready, then ON_PLAYER_TURN_START (D2)", state):
		return
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	imp.state = Enums.MinionState.EXHAUSTED
	state._relic_cost_reduction = 2
	var seen: Dictionary = {}
	state.trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TURN_START, func(_ctx: EventContext) -> void:
		seen["hand"] = state.player_hand.size()
		seen["essence"] = state.player_essence
		seen["ready"] = imp.state == Enums.MinionState.NORMAL
		seen["mirror"] = state._relic_cost_reduction, -1)
	var hand_before := state.player_hand.size()
	state.start_combat()
	TestHarness.assert_eq(state.turn_number, 1, "turn 1")
	TestHarness.assert_eq(seen.get("hand"), hand_before + 1, "event saw the drawn card")
	TestHarness.assert_eq(seen.get("essence"), 1, "event saw refilled Essence")
	TestHarness.assert_eq(seen.get("ready"), true, "event saw the board readied")
	TestHarness.assert_eq(seen.get("mirror"), 0, "Dark Mirror discount expired")
	state.teardown()

static func _turn_start_order_enemy() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("turn engine / enemy turn start: growth, refill, drain, draw, ready, then event (D9)", state):
		return
	state.start_combat()
	state.cmd_end_turn("player")   # enemy turn 1: no growth
	TestHarness.assert_eq(state.enemy_essence_max + state.enemy_mana_max, 2, "no growth on the enemy's first turn")
	state.end_turn("enemy")
	state.begin_turn("player")
	var brute := TestHarness.spawn_enemy(state, "abyssal_brute")
	brute.state = Enums.MinionState.EXHAUSTED
	state._enemy_void_mana_drain_pending = true
	var seen: Dictionary = {}
	state.trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_TURN_START, func(_ctx: EventContext) -> void:
		seen["max"] = state.enemy_essence_max + state.enemy_mana_max
		seen["essence"] = state.enemy_essence
		seen["mana"] = state.enemy_mana
		seen["hand"] = state.enemy_hand.size()
		seen["ready"] = brute.state == Enums.MinionState.NORMAL, -1)
	var hand_before := state.enemy_hand.size()
	state.cmd_end_turn("player")   # enemy turn 2
	TestHarness.assert_eq(seen.get("max"), 3, "grew before the event")
	TestHarness.assert_eq(seen.get("essence"), state.enemy_essence_max, "refilled before the event")
	TestHarness.assert_eq(seen.get("mana"), 0, "Void Rift Lord drain before the event")
	TestHarness.assert_eq(seen.get("hand"), mini(hand_before + 1, CombatState.HAND_MAX), "drew before the event")
	TestHarness.assert_eq(seen.get("ready"), true, "board readied before the event")
	state.teardown()

static func _end_turn_growth_applies_next_turn() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("turn engine / end-turn growth pick applies at the next player turn (D10)", state):
		return
	state.growth_hooks.erase("player")  # live: the player grows only by their pick
	state.start_combat()
	TestHarness.assert_true(state.cmd_end_turn("player", "essence").ok, "end turn with a pick")
	TestHarness.assert_eq(state.player_essence_max, 1, "not grown during the enemy turn")
	TestHarness.assert_eq(state.last_player_growth, "essence", "pick recorded at once (Abyssal Mandate)")
	state.cmd_end_turn("enemy")
	TestHarness.assert_eq(state.player_essence_max, 2, "grown at the player's turn start")
	TestHarness.assert_eq(state.player_essence, 2, "and refilled")
	TestHarness.assert_true(state.cmd_end_turn("player").ok, "end turn with no pick")
	state.cmd_end_turn("enemy")
	TestHarness.assert_eq(state.player_essence_max + state.player_mana_max, 3, "no pick → no growth")
	var before := _snap(state)
	_assert_refused(state, state.cmd_end_turn("enemy"), "not_your_turn", before, "off-turn end")
	state.teardown()

static func _turn_start_expires_temp_buffs() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("turn engine / a side's temp buffs expire at its turn start", state):
		return
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	var atk := imp.effective_atk()
	BuffSystem.apply(imp, Enums.BuffType.TEMP_ATK, 200, "probe", true, false)
	TestHarness.assert_eq(imp.effective_atk(), atk + 200, "temp buff applied")
	state.start_combat()
	TestHarness.assert_eq(imp.effective_atk(), atk, "expired at the player's turn start")
	state.teardown()

# ---------------------------------------------------------------------------
# Resource growth (plan 2A.4) — each profile's grow_resources, from 1/1 with an
# empty hand, turns 1-10: [essence_max, mana_max] per turn. Captured from the
# old sim growth callables before they were ported (D1), so live now runs the
# same curves sim was tuned with.
# ---------------------------------------------------------------------------

const _GROWTH_CURVES: Array = [
	["enemy", "default", [1,1,2,1,3,1,4,1,4,2,5,2,5,3,6,3,6,4,7,4]],
	["enemy", "feral_pack", [1,1,2,1,3,1,4,1,4,2,5,2,5,3,6,3,6,4,7,4]],
	["enemy", "feral_pack_screech", [1,1,2,1,3,1,4,1,4,2,5,2,6,2,6,3,7,3,8,3]],
	["enemy", "corrupted_brood", [1,1,2,1,3,1,4,1,4,2,5,2,5,3,6,3,6,4,7,4]],
	["enemy", "corrupted_brood_aggro", [1,1,2,1,3,1,4,1,4,2,5,2,5,3,6,3,6,4,7,4]],
	["enemy", "corrupted_brood_rune", [1,1,2,1,2,2,3,2,4,2,5,2,6,2,6,3,6,4,7,4]],
	["enemy", "matriarch", [1,1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,1,10]],
	["enemy", "matriarch_aggro", [1,1,2,1,3,1,4,1,4,2,5,2,6,2,6,3,6,4,7,4]],
	["enemy", "matriarch_sac", [1,1,2,1,3,1,4,1,4,2,5,2,6,2,6,3,6,4,7,4]],
	["enemy", "cultist_patrol", [1,1,2,1,2,2,3,2,4,2,5,2,6,2,7,2,8,2,9,2]],
	["enemy", "cultist_patrol_tempo", [1,1,2,1,2,2,3,2,4,2,5,2,5,3,6,3,7,3,7,4]],
	["enemy", "void_ritualist", [1,1,2,1,2,2,3,2,4,2,4,3,4,4,5,4,6,4,7,4]],
	["enemy", "corrupted_handler", [1,1,2,1,3,1,4,1,4,2,5,2,6,2,7,2,7,3,7,4]],
	["enemy", "rift_stalker", [1,1,2,1,3,1,4,1,5,1,5,2,5,3,6,3,7,3,8,3]],
	["enemy", "void_aberration", [1,1,2,1,3,1,4,1,4,2,4,3,5,3,6,3,6,4,6,5]],
	["enemy", "void_herald", [1,1,2,1,3,1,4,1,4,2,5,2,6,2,6,3,7,3,8,3]],
	["enemy", "void_scout", [1,1,2,1,3,1,4,1,5,1,5,2,6,2,7,2,8,2,9,2]],
	["enemy", "void_warband", [1,1,2,1,3,1,4,1,4,2,5,2,6,2,7,2,7,3,7,4]],
	["enemy", "void_captain", [1,1,2,1,3,1,4,1,5,1,5,2,5,3,6,3,7,3,8,3]],
	["enemy", "void_ritualist_prime", [1,1,1,2,1,3,1,4,2,4,3,4,3,5,3,6,4,6,4,7]],
	["enemy", "void_champion", [1,1,2,1,3,1,4,1,4,2,4,3,4,4,5,4,5,5,6,5]],
	["enemy", "abyss_sovereign", [1,1,2,1,3,1,4,1,5,1,5,2,6,2,7,2,8,2,9,2]],
	["enemy", "abyss_sovereign_p2", [1,1,2,1,3,1,4,1,5,1,5,2,6,2,7,2,8,2,9,2]],
	["enemy", "scored", [1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,1,10,1]],  # was the default curve: the enemy scored* profiles grew the PLAYER (bug fixed in 2A.4)
	["enemy", "scored_feral_pack", [1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,1,10,1]],  # was the default curve: the enemy scored* profiles grew the PLAYER (bug fixed in 2A.4)
	["enemy", "scored_corrupted_brood", [1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,1,10,1]],  # was the default curve: the enemy scored* profiles grew the PLAYER (bug fixed in 2A.4)
	["enemy", "scored_matriarch", [1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,1,10,1]],  # was the default curve: the enemy scored* profiles grew the PLAYER (bug fixed in 2A.4)
	["player", "default", [1,1,2,1,3,1,4,1,4,2,5,2,5,3,6,3,6,4,7,4]],
	["player", "swarm", [1,1,2,1,3,1,4,1,4,2,5,2,5,3,6,3,6,4,7,4]],
	["player", "spell_burn", [1,1,1,2,1,3,2,3,2,4,2,5,2,6,2,7,2,8,2,9]],
	["player", "rune_tempo", [1,1,2,1,2,2,2,3,2,4,3,4,4,4,4,5,5,5,6,5]],
	["player", "scored", [1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,1,10,1]],
	["player", "seris", [1,1,2,1,3,1,4,1,4,2,5,2,5,3,6,3,6,4,7,4]],
	["player", "fleshcraft", [1,1,2,1,3,1,4,1,4,2,5,2,5,3,6,3,6,4,7,4]],
	["player", "korrath", [1,1,2,1,3,1,4,1,4,2,5,2,5,3,6,3,6,4,7,4]],
]

static func _growth_curves_match_the_ported_sim_curves() -> void:
	for row: Array in _GROWTH_CURVES:
		var side: String = row[0]
		var id: String = row[1]
		var expected: Array = row[2]
		var state := TestHarness.build_state({})
		if not TestHarness.begin_test("growth / %s %s curve, turns 1-10" % [side, id], state):
			state.teardown()
			continue
		var prof: CombatProfile = ProfileRegistry.make(side, id)
		prof.setup(TestHarness.agent_for(state, side))
		state.enemy_hand.clear()
		state.player_hand.clear()
		state.start_combat()  # both sides 1/1
		var got: Array = []
		for turn in range(1, 11):
			prof.grow_resources(state, side, turn)
			got.append(state.essence_max_of(side))
			got.append(state.mana_max_of(side))
		TestHarness.assert_eq(got, expected, "curve")
		state.teardown()

# ---------------------------------------------------------------------------
# Agents (plan 2A.5) — profiles no longer pay; the commands do, exactly once.
# ---------------------------------------------------------------------------

static func _profile_play_pays_once() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("agents / a profile-driven play pays the card cost exactly once", state):
		return
	state.player_hand.clear()
	var hound := _hand_card(state, "player", "shadow_hound")
	_set_res(state, "player", 3, 0)
	var prof: CombatProfile = ProfileRegistry.make("player", "default")
	prof.setup(TestHarness.agent_for(state, "player"))
	await prof.play_phase()
	TestHarness.assert_true(state.player_board.size() == 1 and state.player_board[0].card_instance == hound, "hound played")
	TestHarness.assert_eq(state.player_essence, 1, "3 - 2 Essence: paid once")
	state.teardown()

static func _agent_spark_fuel_is_credited() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("agents / spark fuel a profile consumed is credited to its next play", state):
		return
	_enemy_turn(state)
	var agent := TestHarness.agent_for(state, "enemy")
	var w1 := TestHarness.spawn_enemy(state, "void_wisp")
	var w2 := TestHarness.spawn_enemy(state, "void_wisp")
	var keep := TestHarness.spawn_enemy(state, "void_wisp")
	var spell := TestHarness.make_test_spell([], "_agent_spark_spell", 1)
	spell.void_spark_cost = 2
	var inst := state.add_to_hand("enemy", spell)
	_set_res(state, "enemy", 0, 1)
	agent.consume_minion(w1)
	agent.consume_minion(w2)
	TestHarness.assert_true(await agent.commit_play_spell(inst), "played on the consumed fuel")
	TestHarness.assert_true(state.enemy_board.has(keep), "no extra fuel taken")
	TestHarness.assert_eq(state.enemy_mana, 0, "only the Mana cost paid")
	var inst2 := state.add_to_hand("enemy", spell)
	_set_res(state, "enemy", 0, 1)
	TestHarness.assert_false(await agent.commit_play_spell(inst2), "no fuel consumed → refused (the profile owns fuel)")
	TestHarness.assert_true(state.enemy_board.has(keep), "still untouched")
	state.teardown()

# ---------------------------------------------------------------------------
# Encounter data (plan 2A.7)
# ---------------------------------------------------------------------------

static func _encounter_table_is_the_one_source() -> void:
	if not TestHarness.begin_test("encounters / every enemy profile maps to an encounter; live builds from the table"):
		return
	for id: String in ProfileRegistry.ENEMY.keys():
		if id in ["default", "scored", "abyss_sovereign_p2"]:
			continue  # no encounter of their own (P2 passives come from the phase transition)
		TestHarness.assert_false(EncounterTable.entry_for_profile(id).is_empty(), "profile %s has an encounter" % id)
	for e: Dictionary in EncounterTable.ENCOUNTERS:
		var built: EnemyData = GameManager._build_encounter(e["index"])
		TestHarness.assert_true(built != null and built.hp == e["hp"] and built.ai_profile == e["ai_profile"],
			"F%d built from the table" % e["index"])
		TestHarness.assert_eq(EncounterTable.passives_for_profile(e["ai_profile"]), built.passives,
			"F%d sim passives = live passives" % e["index"])
	TestHarness.assert_true("champion_abyss_sovereign" in EncounterTable.passives_for_profile("abyss_sovereign"),
		"F15 sim now has the Sovereign champion passive")

## The default player bot casts Void Execution only with a friendly Human
## (its 700-damage bonus). The rule used to test a "human" minion tag no card
## has, so the bot never cast it (task 073).
static func _default_bot_void_execution_needs_a_human() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("agents / default bot: Void Execution only with a friendly Human", state):
		return
	var prof: CombatProfile = ProfileRegistry.make("player", "default")
	prof.setup(TestHarness.agent_for(state, "player"))
	var ve := CardDatabase.get_card("void_execution") as SpellCardData
	TestHarness.assert_false(prof.can_cast_spell(ve), "held on an empty board")
	TestHarness.spawn_friendly(state, "void_imp")
	TestHarness.assert_false(prof.can_cast_spell(ve), "held with only a Demon")
	TestHarness.spawn_friendly(state, "abyss_cultist")
	TestHarness.assert_true(prof.can_cast_spell(ve), "cast with a friendly Human")
	state.teardown()

# ---------------------------------------------------------------------------
# Lifecycle (task 049) — Godot frees a RefCounted by its count alone, so any
# helper, lambda or signal connection that points back at the state keeps the
# whole fight (journal, boards, decks) alive. teardown() must break them all;
# a sim batch runs thousands of fights. The state is never passed to
# begin_test: TestHarness._current_state would keep it alive.
# ---------------------------------------------------------------------------

static func _teardown_frees_the_fight() -> void:
	if not TestHarness.begin_test("lifecycle / teardown frees the state and its helpers (every cycle exercised)", null):
		return
	# abyss_convergence registers grand-ritual lambdas that capture the handlers.
	var state := TestHarness.build_state({"talents": ["abyss_convergence"]})
	_set_res(state, "player", 0, 10)
	TestHarness.assert_true(state.cmd_play_trap("player", _hand_card(state, "player", "blood_rune")).ok, "rune placed (aura lambdas)")
	TestHarness.assert_true(state.cmd_play_environment("player", _hand_card(state, "player", "abyssal_summoning_circle")).ok,
		"ritual environment played (ritual lambdas)")
	state.relic_runtime = RelicRuntime.new()
	state.relic_runtime.setup(["dark_mirror"])
	for rs: RelicRuntime.RelicState in state.relic_runtime.relics:
		rs.cooldown_remaining = 0
	TestHarness.assert_true(state.cmd_activate_relic(0).ok, "relic used (RelicEffects)")
	_add_driver_lambdas(state)
	var refs: Dictionary = {
		"state": weakref(state), "handlers": weakref(state._handlers), "trigger_manager": weakref(state.trigger_manager),
		"combat_manager": weakref(state.combat_manager), "hardcoded": weakref(state._hardcoded),
		"relic_effects": weakref(state.relic_effects),
	}
	state.teardown()
	state.teardown()  # idempotent: tests and the drivers may both call it
	state = null
	var alive: Array[String] = []
	for k: String in refs:
		if (refs[k] as WeakRef).get_ref() != null:
			alive.append(k)
	TestHarness.assert_eq(alive, [] as Array[String], "nothing outlives teardown")

## What a driver adds (CombatSim._build): a growth hook and a signal lambda, both
## capturing the state. Built here, not in the probe: the VM keeps a running
## function's temporaries alive until it returns, so a lambda made in the probe
## itself would hold the state regardless of teardown.
static func _add_driver_lambdas(state: CombatState) -> void:
	state.growth_hooks["player"] = func(side: String, turn: int) -> void: state.set_mana(side, turn)
	state.turn_ended.connect(func(_side: String) -> void: state.digest_text())

static func _sim_run_frees_the_fight() -> void:
	if not TestHarness.begin_test("lifecycle / CombatSim.run frees its state (growth hooks, profile swap, snapshots, diagnostics)", null):
		return
	var refs: Array = []
	var sim := CombatSim.new()
	sim.state_observer = func(st: CombatState) -> void: refs.append(weakref(st))
	sim.turn_snapshot_callback = func(_st: CombatState, _turn: int) -> void: pass
	var deck: Array[String] = PresetDecks.get_cards("swarm")
	var result: Dictionary = await sim.run(deck, "feral_pack", [] as Array[String], 3000, 2000, [], "swarm",
			[], [], {}, true, false, [], "lord_vael", 4242)
	TestHarness.assert_false(str(result.get("winner", "")).is_empty(), "the fight finished")
	TestHarness.assert_false((result["dmg_log"] as Array).is_empty(), "the result is read before teardown (dmg_log kept)")
	TestHarness.assert_eq(refs.size(), 1, "observer saw the state")
	TestHarness.assert_true(refs.size() == 1 and (refs[0] as WeakRef).get_ref() == null, "the state is freed once run returns")
