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
static var _current_state: CombatState = null
static var _current_label: String = ""

## Every state build_state made, as [WeakRef, generation] — the begin_test count
## when it was built. A test that never calls teardown() would otherwise leak
## its fight and leave it on the BuffSystem bus, where later tests' corruption
## removals reach it (task 049). Weak, so a state torn down by its test is
## still freed at once.
static var _built: Array = []
static var _generation: int = 0

static func begin_test(label: String, state: CombatState = null) -> bool:
	_teardown_finished(state)
	_generation += 1
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

## Build a minimal state through CombatState.setup_combat. Options keys:
##   hero_id        : String  — default "lord_vael"
##   talents        : Array[String]
##   hero_passives  : Array[String]
##   enemy_passives : Array[String]
##   player_deck    : Array[String] — default ["void_imp"]
##   enemy_deck     : Array[String] — default ["rabid_imp"]
##   player_hp      : int — default 3000
##   enemy_hp       : int — default 2000
static func build_state(opts: Dictionary = {}) -> CombatState:
	var config := CombatConfig.new()
	config.player_hero_id = opts.get("hero_id", "lord_vael")
	config.talents.assign(_str_array(opts.get("talents", [])))
	config.hero_passives.assign(_str_array(opts.get("hero_passives", [])))
	config.enemy_passives.assign(_str_array(opts.get("enemy_passives", [])))
	config.player_deck_ids.assign(_str_array(opts.get("player_deck", ["void_imp"])))
	config.enemy_deck_ids.assign(_str_array(opts.get("enemy_deck", ["rabid_imp"])))
	config.player_hp = opts.get("player_hp", 3000)
	config.enemy_hp = opts.get("enemy_hp", 2000)
	var state := CombatState.new()
	state.setup_combat(config)
	_built.append([weakref(state), _generation])
	return state

## Tear down the states built before the previous begin_test, except `keep`. A
## test builds its state just before its begin_test or just after it, so a state
## built since the previous begin_test may still be in use; an older one belongs
## to a test that has finished. (Never torn down later than that: teardown only
## resets the MinionInstance flags its own setup set.)
static func _teardown_finished(keep: CombatState) -> void:
	var live: Array = []
	for entry: Array in _built:
		var st: CombatState = (entry[0] as WeakRef).get_ref()
		if st == null:
			continue
		if st == keep or int(entry[1]) >= _generation:
			live.append(entry)
		else:
			st.teardown()
	_built = live

## Tear down every state build_state made (end of the suite).
static func teardown_all() -> void:
	for entry: Array in _built:
		var st: CombatState = (entry[0] as WeakRef).get_ref()
		if st != null:
			st.teardown()
	_built.clear()
	_current_state = null

static func _str_array(a: Variant) -> Array[String]:
	var out: Array[String] = []
	for v in a:
		out.append(str(v))
	return out

static func spawn_friendly(state: CombatState, id: String) -> MinionInstance:
	return _spawn(state, id, "player")

static func spawn_enemy(state: CombatState, id: String) -> MinionInstance:
	return _spawn(state, id, "enemy")

## Spawn a minion using state._card_for() so talent overrides and CardModRules
## deltas are applied — needed when a test cares about the post-override stats
## (e.g. Korrath's abyssal_knight under iron_formation needs to be HUMAN with the
## FORMATION keyword). For most tests `spawn_friendly` (base stats) is enough.
static func spawn_resolved_friendly(state: CombatState, id: String) -> MinionInstance:
	return _spawn_resolved(state, id, "player")

static func _spawn_resolved(state: CombatState, id: String, side: String) -> MinionInstance:
	var data: MinionCardData = state._card_for(side, id) as MinionCardData
	if data == null:
		push_error("TestHarness: _card_for returned null for '%s'" % id)
		return null
	var inst := MinionInstance.create(data, side)
	var board := state.player_board if side == "player" else state.enemy_board
	var slots := state.player_slots if side == "player" else state.enemy_slots
	board.append(inst)
	for slot: SlotState in slots:
		if slot.is_empty():
			slot.place(inst)
			break
	return inst

static func _spawn(state: CombatState, id: String, side: String) -> MinionInstance:
	var data: MinionCardData = CardDatabase.get_card(id) as MinionCardData
	if data == null:
		push_error("TestHarness: unknown minion id '%s'" % id)
		return null
	var inst := MinionInstance.create(data, side)
	var board := state.player_board if side == "player" else state.enemy_board
	var slots := state.player_slots if side == "player" else state.enemy_slots
	board.append(inst)
	for slot: SlotState in slots:
		if slot.is_empty():
			slot.place(inst)
			break
	return inst

## Spawn a card at a specific slot index (no first-empty search). Useful for
## adjacency tests where target slot index matters (Rally the Ranks, Formation
## sandwich setups). Returns null if the slot is already occupied.
static func spawn_friendly_at(state: CombatState, id: String, slot_index: int) -> MinionInstance:
	return _spawn_at(state, id, "player", slot_index)

static func spawn_enemy_at(state: CombatState, id: String, slot_index: int) -> MinionInstance:
	return _spawn_at(state, id, "enemy", slot_index)

static func _spawn_at(state: CombatState, id: String, side: String, slot_index: int) -> MinionInstance:
	var data: MinionCardData = CardDatabase.get_card(id) as MinionCardData
	if data == null:
		push_error("TestHarness: unknown minion id '%s'" % id)
		return null
	var slots := state.player_slots if side == "player" else state.enemy_slots
	if slot_index < 0 or slot_index >= slots.size():
		push_error("TestHarness: slot_index %d out of range" % slot_index)
		return null
	var slot: SlotState = slots[slot_index]
	if not slot.is_empty():
		push_error("TestHarness: slot %d already occupied" % slot_index)
		return null
	var inst := MinionInstance.create(data, side)
	var board := state.player_board if side == "player" else state.enemy_board
	board.append(inst)
	slot.place(inst)
	return inst

## EffectContext for a raw EffectResolver.run() call, bypassing card lifecycle.
static func make_ctx(state: CombatState, owner: String, source: MinionInstance = null,
		chosen_target: MinionInstance = null, extra_cast_data: Dictionary = {}) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.state = state
	ctx.owner = owner
	ctx.source = source
	ctx.chosen_target = chosen_target
	ctx.extra_cast_data = extra_cast_data
	return ctx

# ---------------------------------------------------------------------------
# Common state presets — mirror the per-hero setups used by L1/L2 tests.
# ---------------------------------------------------------------------------

static func seris_state(talents: Array[String] = []) -> CombatState:
	return build_state({
		"hero_id": "seris",
		"talents": talents,
		"hero_passives": ["fleshbind", "grafted_affinity"],
	})

static func vael_state(talents: Array[String] = []) -> CombatState:
	return build_state({
		"hero_id": "lord_vael",
		"talents": talents,
		"hero_passives": ["void_imp_boost"],
	})

static func korrath_state(talents: Array[String] = []) -> CombatState:
	return build_state({
		"hero_id": "korrath",
		"talents": talents,
		"hero_passives": ["abyssal_commander", "iron_legion"],
	})

# ---------------------------------------------------------------------------
# Trigger event firing — replaces ad-hoc EventContext.make/fire pairs.
# `fields` may set: minion, card, damage, attacker.
# ---------------------------------------------------------------------------

static func fire(state: CombatState, event: int, side: String, fields: Dictionary = {}) -> void:
	var ctx := EventContext.make(event, side)
	if fields.has("minion"):
		ctx.minion = fields["minion"]
	if fields.has("card"):
		ctx.card = fields["card"]
	if fields.has("damage"):
		ctx.damage = fields["damage"]
	if fields.has("attacker"):
		ctx.attacker = fields["attacker"]
	if fields.has("defender"):
		ctx.defender = fields["defender"]
	state.trigger_manager.fire(ctx)

# ---------------------------------------------------------------------------
# Board lookups
# ---------------------------------------------------------------------------

static func find_on_board(state: CombatState, side: String, card_id: String) -> MinionInstance:
	var board := state.player_board if side == "player" else state.enemy_board
	for raw in board:
		var m := raw as MinionInstance
		if m.card_data.id == card_id:
			return m
	return null

static func count_on_board(state: CombatState, side: String, card_id: String) -> int:
	var board := state.player_board if side == "player" else state.enemy_board
	var count := 0
	for raw in board:
		if (raw as MinionInstance).card_data.id == card_id:
			count += 1
	return count

static func has_on_board(state: CombatState, side: String, card_id: String) -> bool:
	return find_on_board(state, side, card_id) != null

## The HP the journal last showed for `m` from index `start` on: the last
## DAMAGE_DEALT / MINION_HEALED `hp_after` or MINION_STATS_CHANGED `hp` about it.
## What its slot label ends on once the presenter has played the journal (task 046).
## `missing` when no event carries its HP.
static func last_journal_hp(state: CombatState, start: int, m: MinionInstance, missing: int = -99999) -> int:
	var hp: int = missing
	for i in range(start, state.journal.size()):
		var ev: CombatEvent = state.journal[i]
		if ev.payload.get("minion") != m:
			continue
		match ev.kind:
			CombatEvent.Kind.DAMAGE_DEALT, CombatEvent.Kind.MINION_HEALED:
				hp = int(ev.payload.get("hp_after", hp))
			CombatEvent.Kind.MINION_STATS_CHANGED:
				hp = int(ev.payload.get("hp", hp))
	return hp

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
static func assert_board(state: CombatState, side: String, expected_ids: Array, label: String) -> bool:
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
static func _dump_state(state: CombatState) -> void:
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

## A StateAgent for `side` of `state` (the sim's agent — plan 2A.5).
static func agent_for(state: CombatState, side: String) -> StateAgent:
	var agent := StateAgent.new()
	agent.setup(state, side)
	return agent
