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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _hand_card(state: SimState, side: String, id: String) -> CardInstance:
	return state.add_to_hand(side, CardDatabase.get_card(id))

static func _set_res(state: SimState, side: String, essence: int, mana: int) -> void:
	state.set_essence(side, essence)
	state.set_mana(side, mana)

static func _ready_minion(state: SimState, side: String, id: String) -> MinionInstance:
	var m: MinionInstance = TestHarness.spawn_friendly(state, id) if side == "player" else TestHarness.spawn_enemy(state, id)
	m.state = Enums.MinionState.NORMAL
	return m

static func _enemy_turn(state: SimState) -> void:
	state.is_player_turn = false

static func _snap(state: SimState) -> String:
	return "%s\nlog %d" % [state.digest_text(), state.command_log.size()]

static func _assert_refused(state: SimState, r: CommandResult, reason: String, before: String, label: String) -> void:
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
