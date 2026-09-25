## ParityTests.gd
## Live ↔ engine parity (LIVE_SIM_UNIFICATION_PLAN.md 5.1). For each case × seed:
##
##   1. Engine run — CombatSim.run (plain CombatState, both sides StateAgent +
##      profile, base Pacer). Every accepted command's record and the state's
##      digest_text() at that moment are captured (command_recorded).
##   2. Live replay — the same fight in a headless CombatScene (GameManager run
##      state → CombatConfig.from_game_manager, same seed, presenter.instant).
##      The player's commands are replayed through the scene's input entry
##      points (hand-card select, slot / hero clicks, relic bar, skill buttons,
##      end turn); the enemy is the scene's own EnemyTurnRunner on the same
##      profile. A command the input layer cannot express (AI-only: spark fuel,
##      a skipped mandatory target, a random-target spell) is issued directly
##      and counted.
##   3. The command records and digests must match index by index, and the
##      final digests too. A mismatch prints the index, the command and the
##      differing digest lines.
##   4. Live smoke (plan 5.2): the fight has a winner and the presenter has
##      played the whole journal. The F1–F3 cases cover every Act 1 encounter.
##
## Run from tools/run_checks.sh, or directly:
##   godot --headless --path . res://debug/tests/Parity.tscn [-- --filter <substr>]
## Exit code = failed cases. run_checks.sh also fails on any `SCRIPT ERROR`.
extends Node

const COMBAT_SCENE := "res://combat/board/CombatScene.tscn"
const SEEDS: Array[int] = [11, 22, 33]
const STEP_TIMEOUT_MS := 20000

## One fight setup per case: encounter index, preset deck, hero, player
## profile, talents, relics.
const CASES: Array = [
	{name = "F1 swarm", encounter = 1, deck = "swarm", hero = "lord_vael", profile = "swarm",
		talents = ["imp_evolution"], relics = []},
	{name = "F2 voidbolt", encounter = 2, deck = "voidbolt_burst", hero = "lord_vael", profile = "spell_burn",
		talents = ["piercing_void", "deepened_curse"], relics = []},
	{name = "F3 death_circle", encounter = 3, deck = "death_circle", hero = "lord_vael", profile = "rune_tempo",
		talents = ["rune_caller", "runic_attunement"], relics = []},
	{name = "F4 seris corrupt", encounter = 4, deck = "seris_corruption_engine", hero = "seris", profile = "seris",
		talents = ["corrupt_flesh", "corrupt_detonation"], relics = ["bone_shield", "void_lens"]},
	{name = "F5 seris forge", encounter = 5, deck = "seris_demon_forge", hero = "seris", profile = "seris",
		talents = ["soul_forge", "fiend_offering"], relics = ["mana_shard", "blood_chalice"]},
	{name = "F6 korrath", encounter = 6, deck = "korrath_iron_legion", hero = "korrath", profile = "korrath",
		talents = ["iron_formation", "commanders_reach"], relics = ["mana_shard", "dark_mirror"]},
	{name = "F13 swarm", encounter = 13, deck = "swarm", hero = "lord_vael", profile = "swarm",
		talents = ["imp_evolution", "swarm_discipline", "imp_warband"], relics = []},
	{name = "F15 swarm", encounter = 15, deck = "swarm", hero = "lord_vael", profile = "swarm",
		talents = ["imp_evolution", "swarm_discipline", "imp_warband", "void_echo"],
		relics = ["scouts_lantern", "dark_mirror"]},
]

var _failed: int = 0
var _cases: int = 0
## Why a player command went straight to the engine instead of through input.
var _direct_reasons: Dictionary = {}
var _filter: String = ""

func _ready() -> void:
	_parse_args()
	UserProfile.saving_disabled = true
	# Small but non-zero (see LiveSmokeTests): at 0, VfxSequence drops beats.
	BaseVfx.time_scale = 0.05
	# Nothing here depends on wall-clock time: run the pacing timers and the
	# hand's draw tweens fast.
	Engine.time_scale = 10.0
	var t0: int = Time.get_ticks_msec()
	for c: Dictionary in CASES:
		if not _filter.is_empty() and not (c["name"] as String).containsn(_filter):
			continue
		for s: int in SEEDS:
			_cases += 1
			if not await _run_case(c, s):
				_failed += 1
	if not _direct_reasons.is_empty():
		print("Parity: player commands issued directly (no input path): %s" % JSON.stringify(_direct_reasons))
	print("Parity: %s (%d of %d cases failed, %.1f s)" % [
		"OK" if _failed == 0 else "FAILED", _failed, _cases, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(_failed)

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--filter" and i + 1 < args.size():
			_filter = args[i + 1]

# ---------------------------------------------------------------------------
# One case
# ---------------------------------------------------------------------------

func _run_case(c: Dictionary, rng_seed: int) -> bool:
	var label: String = "%s seed %d" % [c["name"], rng_seed]
	var t_start: int = Time.get_ticks_msec()
	_setup_run(c, rng_seed)
	var enemy: EnemyData = GameManager.current_enemy

	# 1. Engine run.
	var eng: Array = []
	var eng_state: Array = []  # [CombatState] — for its combat log on failure
	var sim := CombatSim.new()
	sim.state_observer = func(st: CombatState) -> void:
		eng_state.append(st)
		st.command_recorded.connect(func(i: int) -> void:
			eng.append({rec = st.command_log[i].duplicate(true), digest = st.digest_text(), jpos = st.journal.size()}))
	var deck: Array[String] = []
	deck.assign(GameManager.player_deck)
	var talents: Array[String] = []
	talents.assign(GameManager.unlocked_talents)
	var relics: Array[String] = []
	relics.assign(GameManager.player_relics)
	var result: Dictionary = await sim.run(deck, enemy.ai_profile, enemy.deck, GameManager.player_hp_max,
			enemy.hp, talents, c["profile"], _hero_passives(c["hero"]), relics, {}, false, false,
			enemy.limited_cards, c["hero"], rng_seed)
	var eng_final: String = result["digest_text"]

	# 2. Live replay.
	var t_live: int = Time.get_ticks_msec()
	GameManager.next_combat_seed = rng_seed
	var scene: Node = load(COMBAT_SCENE).instantiate()
	var st: CombatState = scene.state
	var live: Array = []
	st.command_recorded.connect(func(i: int) -> void:
		live.append({rec = st.command_log[i].duplicate(true), digest = st.digest_text(), jpos = st.journal.size()}))
	add_child(scene)
	scene.presenter.instant = true
	# The sim grows the player by its profile's curve at turn start; install the
	# same hook (live grows by the end-turn pick, which the sim never makes).
	var p_profile: CombatProfile = ProfileRegistry.make("player", c["profile"])
	var p_agent := StateAgent.new()
	p_agent.setup(st, "player")
	p_profile.setup(p_agent)
	st.growth_hooks["player"] = func(side: String, turn: int) -> void:
		p_profile.grow_resources(st, side, turn)

	var why: String = ""
	var ui: int = 0
	var direct: int = 0
	for i in eng.size():
		var rec: Dictionary = eng[i]["rec"]
		if rec["side"] == "player" and live.size() == i:
			await _wait_until(func() -> bool:
				return live.size() > i or not st.winner.is_empty() \
					or (st.is_player_turn and scene.presenter.is_idle() and not scene._end_turn_in_progress))
			if live.size() == i and st.winner.is_empty():
				var how: String = await _drive(scene, rec)
				if how == "ui":
					ui += 1
				else:
					direct += 1
					var key: String = "%s:%s" % [how, rec.get("card_id", "")]
					_direct_reasons[key] = int(_direct_reasons.get(key, 0)) + 1
		if not await _wait_until(func() -> bool: return live.size() > i):
			why = "live issued no command #%d (engine: %s; live turn %d, %s to act, winner '%s'; %s)" % [
				i, _rec_text(rec), st.turn_number, "player" if st.is_player_turn else "enemy", st.winner, _slots_text(scene)]
			break
		why = _compare(i, eng[i], live[i])
		if not why.is_empty():
			var from: int = maxi(0, i - 3)
			why += "\n  engine log, commands #%d–#%d:\n%s\n  live log, same span:\n%s" % [from, i,
				_log_between(eng_state[0], eng[from]["jpos"], eng[i]["jpos"] + 40),
				_log_between(st, live[from]["jpos"], st.journal.size())]
			break
	if why.is_empty():
		await _wait_until(func() -> bool: return scene.presenter.is_idle() \
				and (not st.winner.is_empty() or st.is_player_turn) and live.size() >= eng.size())
		if live.size() > eng.size():
			why = "live issued %d extra command(s), first: %s" % [live.size() - eng.size(), _rec_text(live[eng.size()]["rec"])]
		elif st.digest_text() != eng_final:
			why = "final state differs:\n%s" % _diff(eng_final, st.digest_text())
		# Live smoke matrix (plan 5.2): the fight ends, and the presenter has
		# played the whole journal.
		elif st.winner.is_empty():
			why = "no winner by turn %d" % st.turn_number
		elif not scene.presenter.is_idle() or scene.presenter.cursor != st.journal.size():
			why = "presenter not idle at the end (%d / %d events played)" % [scene.presenter.cursor, st.journal.size()]
	var live_winner: String = st.winner if not st.winner.is_empty() else "draw"
	await _teardown(scene)
	if why.is_empty():
		print("  PASS  %s — %d commands (%d player via input, %d direct), %s wins, turn %s  [engine %d ms, live %d ms]" % [
			label, eng.size(), ui, direct, live_winner, result["turns"], t_live - t_start, Time.get_ticks_msec() - t_live])
		return true
	print("  FAIL  %s — %s" % [label, why])
	return false

## The run state the live scene reads (CombatConfig.from_game_manager). The
## global RNG picks the encounter's deck variant, so seed it first.
func _setup_run(c: Dictionary, rng_seed: int) -> void:
	seed(rng_seed)
	GameManager.start_new_run()
	GameManager.current_hero = c["hero"]
	GameManager.player_deck = PresetDecks.get_cards(c["deck"])
	GameManager.unlocked_talents.assign(c["talents"])
	GameManager.player_relics.assign(c["relics"])
	GameManager.relic_bonus_charges = {}
	GameManager.player_hp_max = 3000
	GameManager.current_enemy = GameManager.get_encounter(c["encounter"])

static func _hero_passives(hero_id: String) -> Array[String]:
	var out: Array[String] = []
	var hero: HeroData = HeroDatabase.get_hero(hero_id)
	if hero != null:
		for p in hero.passives:
			out.append(p.id)
	return out

# ---------------------------------------------------------------------------
# Replaying a player command through the scene's input entry points
# ---------------------------------------------------------------------------

## Issue `rec` the way a player would. Returns "ui", or why it went straight
## to the engine (the reason is tallied).
func _drive(scene: Node, rec: Dictionary) -> String:
	var st: CombatState = scene.state
	var target: Variant = CombatSim.decode_target(st, rec.get("target"))
	var extra: Dictionary = rec.get("extra", {})
	var hand_index: int = int(rec.get("hand_index", -1))
	var inst: CardInstance = st.player_hand[hand_index] if hand_index >= 0 and hand_index < st.player_hand.size() else null
	var slot: int = int(rec.get("slot", -1))
	var spark_paid: bool = extra.has("spark_fuel") or int(extra.get("sparks_prepaid", 0)) > 0
	match rec["cmd"]:
		"play_minion":
			if inst == null or not (inst.card_data is MinionCardData):
				return _direct(st, rec, "bad_record")
			if spark_paid:
				return _direct(st, rec, "spark_fuel")
			var mc := inst.card_data as MinionCardData
			var t_type: String = scene._effective_target_type(mc)
			var optional: bool = scene._effective_target_optional(mc)
			var awaits: bool = (optional or mc.on_play_requires_target) and scene._has_valid_minion_on_play_targets_for(t_type)
			if target == null and awaits and not optional:
				return _direct(st, rec, "minion_skipped_mandatory_target")
			if target != null and not (awaits and target is MinionInstance and scene._is_valid_minion_on_play_target(target, t_type)):
				return _direct(st, rec, "minion_target_ui_cannot_pick")
			scene._on_hand_card_selected(inst)
			if target != null:
				_click_minion(scene, target)
			scene._on_player_slot_clicked_empty(scene.slot_node("player", slot))
			return "ui"
		"play_spell":
			if inst == null or not (inst.card_data is SpellCardData):
				return _direct(st, rec, "bad_record")
			if spark_paid:
				return _direct(st, rec, "spark_fuel")
			var spell := inst.card_data as SpellCardData
			if not spell.requires_target:
				if target != null:
					return _direct(st, rec, "untargeted_spell_given_target")
				scene._on_hand_card_selected(inst)
				return "ui"
			if target == null:
				return _direct(st, rec, "spell_random_target")
			if target is MinionInstance:
				if not scene._is_valid_spell_target(target, spell.target_type):
					return _direct(st, rec, "spell_target_ui_cannot_pick")
				var mc := (target as MinionInstance).card_data as MinionCardData
				if spell.id == "rally_the_ranks" and mc.is_race(Enums.MinionType.HUMAN) and mc.is_race(Enums.MinionType.DEMON):
					return _direct(st, rec, "choice_modal")
				scene._on_hand_card_selected(inst)
				_click_minion(scene, target)
				return "ui"
			if target is String and target == "enemy_hero":
				scene._on_hand_card_selected(inst)
				scene.input_handler.on_enemy_hero_spell_input(_left_click())
				return "ui"
			if target is TrapCardData and st.active_traps.has(target):
				scene._on_hand_card_selected(inst)
				scene.input_handler.on_trap_env_input(_left_click(), st.active_traps.find(target), null)
				return "ui"
			if target is EnvironmentCardData and target == st.active_environment:
				scene._on_hand_card_selected(inst)
				scene.input_handler.on_trap_env_input(_left_click(), -1, target)
				return "ui"
			return _direct(st, rec, "spell_target_ui_cannot_pick")
		"play_trap", "play_environment":
			if inst == null:
				return _direct(st, rec, "bad_record")
			scene._on_hand_card_selected(inst)
			return "ui"
		"attack", "attack_hero":
			var attacker: MinionInstance = st.slot_of("player", slot).minion if slot >= 0 else null
			if attacker == null:
				return _direct(st, rec, "bad_record")
			scene._on_player_slot_clicked_occupied(scene.slot_node("player", slot), attacker)
			if rec["cmd"] == "attack_hero":
				scene._on_enemy_hero_button_pressed()
			else:
				_click_minion(scene, target)
			return "ui"
		"activate_relic":
			scene._on_relic_activated(slot)
			if target is MinionInstance:
				_click_minion(scene, target)
			elif target is String and target == "enemy_hero":
				scene.input_handler.on_relic_target_hero_input(_left_click())
			return "ui"
		"hero_skill":
			var skill: String = extra.get("skill", "")
			if skill == "soul_forge" and scene._player_hero_panel.resource_bar != null:
				scene._player_hero_panel.resource_bar._on_forge_btn_pressed()
				return "ui"
			if skill == "seris_corrupt" and target is MinionInstance:
				scene._seris_corrupt_activate()
				_click_minion(scene, target)
				return "ui"
			return _direct(st, rec, "hero_skill_no_button")
		"end_turn":
			scene._do_end_turn(extra.get("growth", ""))
			return "ui"
	return _direct(st, rec, "no_input_for_" + str(rec["cmd"]))

func _direct(st: CombatState, rec: Dictionary, reason: String) -> String:
	CombatSim.apply_logged_command(st, rec)
	return reason

func _click_minion(scene: Node, m: MinionInstance) -> void:
	var node: BoardSlot = scene.slot_node(m.owner, m.slot_index)
	if m.owner == "enemy":
		scene._on_enemy_slot_clicked(node, m)
	else:
		scene._on_player_slot_clicked_occupied(node, m)

static func _left_click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	return ev

# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------

## "" when the live entry matches the engine's, else what differs.
func _compare(i: int, e: Dictionary, l: Dictionary) -> String:
	var er: Dictionary = _normalized(e["rec"])
	var lr: Dictionary = _normalized(l["rec"])
	if JSON.stringify(er, "", true) != JSON.stringify(lr, "", true):
		var board: PackedStringArray = []
		for line: String in (e["digest"] as String).split("\n"):
			if line.begins_with("board") or line.begins_with("player[") or line.begins_with("enemy["):
				board.append("    " + line)
		var state_diff: String = "" if e["digest"] == l["digest"] else "\n  state differs too:\n" + _diff(e["digest"], l["digest"])
		return "command #%d differs — engine %s, live %s\n  board before it:\n%s%s" % [
			i, _rec_text(e["rec"]), _rec_text(l["rec"]), "\n".join(board), state_diff]
	if e["digest"] != l["digest"]:
		return "state before command #%d (%s) differs:\n%s" % [i, _rec_text(e["rec"]), _diff(e["digest"], l["digest"])]
	return ""

## A record without the AI agents' zero spark prepayment (input never sends it).
static func _normalized(rec: Dictionary) -> Dictionary:
	var out: Dictionary = rec.duplicate(true)
	var extra: Dictionary = out.get("extra", {})
	if int(extra.get("sparks_prepaid", 0)) == 0:
		extra.erase("sparks_prepaid")
	return out

static func _rec_text(rec: Dictionary) -> String:
	return "%s %s %s slot %s target %s extra %s (turn %s)" % [rec.get("side"), rec.get("cmd"),
		rec.get("card_id"), rec.get("slot"), JSON.stringify(rec.get("target")), JSON.stringify(rec.get("extra")), rec.get("turn")]

## The combat-log lines (LOG events) journaled in [from, to).
static func _log_between(st: CombatState, from: int, to: int) -> String:
	var out: PackedStringArray = []
	for k in range(from, mini(to, st.journal.size())):
		var ev: CombatEvent = st.journal[k]
		if ev.kind == CombatEvent.Kind.LOG:
			out.append("    " + str(ev.payload.get("msg", "")))
	return "\n".join(out)

## Board occupancy as the engine holds it and as the slot views show it —
## the input layer reads the views.
static func _slots_text(scene: Node) -> String:
	var parts: PackedStringArray = []
	for side in ["player", "enemy"]:
		var eng_s: String = ""
		var view_s: String = ""
		for i in 5:
			eng_s += "_" if scene.state.slot_of(side, i).is_empty() else "M"
			view_s += "_" if scene.slot_node(side, i).is_empty() else "M"
		parts.append("%s engine %s view %s" % [side, eng_s, view_s])
	return ", ".join(parts)

static func _diff(a: String, b: String) -> String:
	var al: PackedStringArray = a.split("\n")
	var bl: PackedStringArray = b.split("\n")
	var out: PackedStringArray = []
	for k in maxi(al.size(), bl.size()):
		var x: String = al[k] if k < al.size() else "<none>"
		var y: String = bl[k] if k < bl.size() else "<none>"
		if x != y:
			out.append("    engine: %s\n    live:   %s" % [x, y])
		if out.size() >= 8:
			break
	return "\n".join(out)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _wait_until(cond: Callable, timeout_ms: int = STEP_TIMEOUT_MS) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout_ms:
			return false
		await get_tree().process_frame
	return true

## Free the scene once its coroutines have drained (see LiveSmokeTests).
func _teardown(scene: Node) -> void:
	await _wait_until(func() -> bool:
		return not scene.hand_display._draw_playing and scene.presenter.is_idle() and not scene._end_turn_in_progress)
	await get_tree().create_timer(0.2).timeout
	scene.queue_free()
	await get_tree().process_frame
