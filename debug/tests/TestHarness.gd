## TestHarness.gd
## Shared state builder, assertion helpers, and result recording for all
## layered effect/handler/scenario tests.
##
## All assertions are non-throwing: failures are recorded into `results` so one
## bad test doesn't abort the run. Call `reset()` between tests.
class_name TestHarness
extends RefCounted

# ---------------------------------------------------------------------------
# Runtime switches — set by RunAllTests from CLI args
# ---------------------------------------------------------------------------

static var verbose: bool = false
static var filter_substr: String = ""

# ---------------------------------------------------------------------------
# Result recording
# ---------------------------------------------------------------------------

static var _pass_count: int = 0
static var _fail_count: int = 0
static var _skip_count: int = 0
static var _failures: Array = []   ## Array[{label, detail}]
static var _current_state: SimState = null
static var _current_label: String = ""

static func begin_test(label: String, state: SimState = null) -> bool:
	_current_label = label
	_current_state = state
	if filter_substr != "" and not label.to_lower().contains(filter_substr.to_lower()):
		_skip_count += 1
		return false
	return true

static func reset_counters() -> void:
	_pass_count = 0
	_fail_count = 0
	_skip_count = 0
	_failures.clear()

static func summary() -> String:
	return "%d passed, %d failed, %d skipped" % [_pass_count, _fail_count, _skip_count]

static func fail_count() -> int:
	return _fail_count

# ---------------------------------------------------------------------------
# State builder
# ---------------------------------------------------------------------------

## Build a minimal SimState with triggers wired. Options keys:
##   hero_id        : String  — default "lord_vael"
##   talents        : Array[String]
##   hero_passives  : Array[String]
##   enemy_passives : Array[String]
##   player_deck    : Array[String] — default ["void_imp"]
##   enemy_deck     : Array[String] — default ["rabid_imp"]
##   player_hp      : int — default 3000
##   enemy_hp       : int — default 2000
static func build_state(opts: Dictionary = {}) -> SimState:
	var state := SimState.new()
	state.player_hero_id = opts.get("hero_id", "lord_vael")
	var talents_opt = opts.get("talents", [])
	var talents_typed: Array[String] = []
	for t in talents_opt:
		talents_typed.append(str(t))
	state.talents = talents_typed
	var hp_opt = opts.get("hero_passives", [])
	var hp_typed: Array[String] = []
	for p in hp_opt:
		hp_typed.append(str(p))
	state.hero_passives = hp_typed
	var ep_opt = opts.get("enemy_passives", [])
	var ep_typed: Array[String] = []
	for p in ep_opt:
		ep_typed.append(str(p))
	state.enemy_passives = ep_typed

	var p_deck_opt = opts.get("player_deck", ["void_imp"])
	var p_deck_typed: Array[String] = []
	for id in p_deck_opt:
		p_deck_typed.append(str(id))
	var e_deck_opt = opts.get("enemy_deck", ["rabid_imp"])
	var e_deck_typed: Array[String] = []
	for id in e_deck_opt:
		e_deck_typed.append(str(id))

	state.setup(p_deck_typed, e_deck_typed, opts.get("player_hp", 3000), opts.get("enemy_hp", 2000))
	# Wire SimEnemyAgent so handlers that reach through state.enemy_ai (hand
	# add, cost discounts, _draw_cards) have something to call. CombatSim.run
	# does this during normal combat; tests need it explicitly.
	var e_agent := SimEnemyAgent.new()
	e_agent.setup(state)
	var ts := SimTriggerSetup.new()
	ts.setup(state)
	return state

static func spawn_friendly(state: SimState, id: String) -> MinionInstance:
	return _spawn(state, id, "player")

static func spawn_enemy(state: SimState, id: String) -> MinionInstance:
	return _spawn(state, id, "enemy")

static func _spawn(state: SimState, id: String, side: String) -> MinionInstance:
	var data: MinionCardData = CardDatabase.get_card(id) as MinionCardData
	if data == null:
		push_error("TestHarness: unknown minion id '%s'" % id)
		return null
	var inst := MinionInstance.create(data, side)
	var board := state.player_board if side == "player" else state.enemy_board
	var slots := state.player_slots if side == "player" else state.enemy_slots
	board.append(inst)
	for slot in slots:
		if slot.minion == null:
			slot.minion = inst
			inst.slot_index = slot.index
			break
	return inst

## EffectContext for a raw EffectResolver.run() call, bypassing card lifecycle.
static func make_ctx(state: SimState, owner: String, source: MinionInstance = null,
		chosen_target: MinionInstance = null) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.scene = state
	ctx.owner = owner
	ctx.source = source
	ctx.chosen_target = chosen_target
	return ctx

# ---------------------------------------------------------------------------
# Common state presets — mirror the per-hero setups used by L1/L2 tests.
# ---------------------------------------------------------------------------

static func seris_state(talents: Array[String] = []) -> SimState:
	return build_state({
		"hero_id": "seris",
		"talents": talents,
		"hero_passives": ["fleshbind", "grafted_affinity"],
	})

static func vael_state(talents: Array[String] = []) -> SimState:
	return build_state({
		"hero_id": "lord_vael",
		"talents": talents,
		"hero_passives": ["void_imp_boost"],
	})

# ---------------------------------------------------------------------------
# Trigger event firing — replaces ad-hoc EventContext.make/fire pairs.
# `fields` may set: minion, card, damage, attacker.
# ---------------------------------------------------------------------------

static func fire(state: SimState, event: int, side: String, fields: Dictionary = {}) -> void:
	var ctx := EventContext.make(event, side)
	if fields.has("minion"):
		ctx.minion = fields["minion"]
	if fields.has("card"):
		ctx.card = fields["card"]
	if fields.has("damage"):
		ctx.damage = fields["damage"]
	if fields.has("attacker"):
		ctx.attacker = fields["attacker"]
	state.trigger_manager.fire(ctx)

# ---------------------------------------------------------------------------
# Board lookups
# ---------------------------------------------------------------------------

static func find_on_board(state: SimState, side: String, card_id: String) -> MinionInstance:
	var board := state.player_board if side == "player" else state.enemy_board
	for raw in board:
		var m := raw as MinionInstance
		if m.card_data.id == card_id:
			return m
	return null

static func count_on_board(state: SimState, side: String, card_id: String) -> int:
	var board := state.player_board if side == "player" else state.enemy_board
	var count := 0
	for raw in board:
		if (raw as MinionInstance).card_data.id == card_id:
			count += 1
	return count

static func has_on_board(state: SimState, side: String, card_id: String) -> bool:
	return find_on_board(state, side, card_id) != null

# ---------------------------------------------------------------------------
# Synthetic spell builder for tests that need a CardData with a specific shape
# (e.g. a damage-dealing spell to trigger _spell_deals_damage gating).
# ---------------------------------------------------------------------------

static func make_test_spell(steps: Array, spell_id: String = "_test_spell", cost: int = 1) -> SpellCardData:
	var s := SpellCardData.new()
	s.id = spell_id
	s.card_name = "Test Spell"
	s.cost = cost
	s.effect_steps = steps
	return s

# ---------------------------------------------------------------------------
# Layer 3 helper: assert that a CombatSim.run() result has the expected
# structural invariants (winner key present + non-empty, turn count under cap).
# ---------------------------------------------------------------------------

static func assert_clean_finish(result: Dictionary, label_prefix: String) -> bool:
	var ok := true
	ok = assert_true(result.has("winner"), "%s / result has winner key" % label_prefix) and ok
	ok = assert_true(result.has("turns"), "%s / result has turns key" % label_prefix) and ok
	ok = assert_ne(result.get("winner", ""), "", "%s / winner is non-empty" % label_prefix) and ok
	ok = assert_true((result.get("turns", 0) as int) < 60, "%s / did not hit MAX_TURNS cap" % label_prefix) and ok
	return ok

# ---------------------------------------------------------------------------
# Assertions — each records pass/fail and returns the boolean outcome
# ---------------------------------------------------------------------------

static func assert_eq(actual, expected, label: String) -> bool:
	if actual == expected:
		return _record_pass(label)
	return _record_fail(label, "expected %s, got %s" % [_repr(expected), _repr(actual)])

static func assert_ne(actual, unexpected, label: String) -> bool:
	if actual != unexpected:
		return _record_pass(label)
	return _record_fail(label, "expected value != %s, got %s" % [_repr(unexpected), _repr(actual)])

static func assert_true(cond: bool, label: String) -> bool:
	if cond:
		return _record_pass(label)
	return _record_fail(label, "expected true, got false")

static func assert_false(cond: bool, label: String) -> bool:
	if not cond:
		return _record_pass(label)
	return _record_fail(label, "expected false, got true")

static func assert_approx(actual: float, expected: float, tolerance: float, label: String) -> bool:
	if absf(actual - expected) <= tolerance:
		return _record_pass(label)
	return _record_fail(label, "expected %f ± %f, got %f" % [expected, tolerance, actual])

## Assert that the board on `side` contains exactly these card ids (in order).
static func assert_board(state: SimState, side: String, expected_ids: Array, label: String) -> bool:
	var board := state.player_board if side == "player" else state.enemy_board
	var actual_ids: Array = []
	for m in board:
		actual_ids.append((m as MinionInstance).card_data.id)
	if actual_ids == expected_ids:
		return _record_pass(label)
	return _record_fail(label, "expected board %s, got %s" % [_repr(expected_ids), _repr(actual_ids)])

# ---------------------------------------------------------------------------
# Internal — result recording + dump
# ---------------------------------------------------------------------------

static func _record_pass(label: String) -> bool:
	_pass_count += 1
	if verbose:
		print("  PASS: %s" % _full_label(label))
	return true

static func _record_fail(label: String, detail: String) -> bool:
	_fail_count += 1
	var full_label := _full_label(label)
	print("  FAIL: %s — %s" % [full_label, detail])
	_failures.append({"label": full_label, "detail": detail})
	if verbose and _current_state != null:
		_dump_state(_current_state)
	return false

static func _full_label(label: String) -> String:
	if _current_label == "":
		return label
	return "%s / %s" % [_current_label, label]

## Full board-and-resources dump, printed under a failed assertion when --verbose.
static func _dump_state(state: SimState) -> void:
	print("    --- state dump ---")
	print("    hero hp: player=%d enemy=%d" % [state.player_hp, state.enemy_hp])
	print("    resources: player ess=%d/%d mana=%d/%d flesh=%d"
			% [state.player_essence, state.player_essence_max,
			state.player_mana, state.player_mana_max, state.player_flesh])
	print("    resources: enemy  ess=%d/%d mana=%d/%d"
			% [state.enemy_essence, state.enemy_essence_max,
			state.enemy_mana, state.enemy_mana_max])
	print("    hand sizes: player=%d enemy=%d" % [state.player_hand.size(), state.enemy_hand.size()])
	_dump_board("player", state.player_board)
	_dump_board("enemy ", state.enemy_board)
	if not state.hero_passives.is_empty():
		print("    hero passives: %s" % _repr(state.hero_passives))
	if not state.enemy_passives.is_empty():
		print("    enemy passives: %s" % _repr(state.enemy_passives))
	if not state.talents.is_empty():
		print("    talents: %s" % _repr(state.talents))
	print("    ------------------")

static func _dump_board(label: String, board: Array) -> void:
	if board.is_empty():
		print("    %s board: (empty)" % label)
		return
	var parts: Array = []
	for raw in board:
		var m := raw as MinionInstance
		parts.append("%s[%d/%d]" % [m.card_data.id, m.effective_atk(), m.current_hp])
	print("    %s board: %s" % [label, ", ".join(parts)])

static func _repr(value) -> String:
	if value == null:
		return "null"
	return str(value)
