## LiveSmokeTests.gd
## Headless smoke test of the LIVE combat shell (CombatScene), which the rest of
## the suite never instantiates — every other test runs on CombatState. Catches the
## class of bug where rules code works in sim and crashes live (task 040, B1).
##
## Run from tools/run_checks.sh (separate process: RunAllTests quits the tree),
## or directly:
##   godot --headless --path . res://debug/tests/LiveSmoke.tscn
## Exit code = failed checks. run_checks.sh also fails on any `SCRIPT ERROR`.
extends Node

const COMBAT_SCENE := "res://combat/board/CombatScene.tscn"
const TURN_TIMEOUT_MS := 20000
const FIGHT_TIMEOUT_MS := 90000

var _fails: int = 0

func _ready() -> void:
	UserProfile.saving_disabled = true
	# Small but non-zero: at 0, VfxSequence completes synchronously and drops
	# mid-phase beats (buff application, impact hits).
	BaseVfx.time_scale = 0.05
	await _f1_enemy_turn_completes()
	await _f13_vrp_champion_progress()
	await _live_rules_paths()
	await _ai_vs_ai_fight()
	print("LiveSmoke: %s (%d failed)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(_fails)

# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

## F1: combat boots, the opening hand is dealt, and a full enemy turn runs.
func _f1_enemy_turn_completes() -> void:
	var scene: Node = await _launch(1, "swarm")
	var tm: CombatState = scene.state
	_check(scene.state.player_hp > 0, "F1: player hp > 0")
	_check(tm.player_hand.size() == 4, "F1: opening hand is 4 cards (got %d)" % tm.player_hand.size())
	_check(tm.is_player_turn, "F1: player acts first")
	var e_grave_before: int = scene.state.enemy_graveyard.size()
	scene._do_end_turn("essence")
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < TURN_TIMEOUT_MS:
		await get_tree().process_frame
		if tm.is_player_turn and tm.turn_number >= 2:
			break
	_check(tm.is_player_turn and tm.turn_number == 2,
		"F1: enemy turn completed and turn 2 began (turn=%d, player_turn=%s)" % [tm.turn_number, tm.is_player_turn])
	if tm.turn_number == 2:
		print("LiveSmoke: enemy turn completed")
	await scene.presenter.pump_and_wait_idle()
	_check(scene.presenter.is_idle() and scene.presenter.cursor == scene.state.journal.size(),
		"F1: presenter idle with the journal fully played (%d / %d)" % [scene.presenter.cursor, scene.state.journal.size()])
	# Shared turn engine (plan 2A.3): the pick applies at the next turn start (D10);
	# the enemy opens at 1/1 and doesn't grow on its first turn.
	var st: CombatState = scene.state
	_check(st.player_essence_max == 2 and st.player_mana_max == 1,
		"F1: Essence pick applied on turn 2 (%d/%d)" % [st.player_essence_max, st.player_mana_max])
	_check(st.enemy_essence_max == 1 and st.enemy_mana_max == 1,
		"F1: enemy at 1/1 after its first turn (%d/%d)" % [st.enemy_essence_max, st.enemy_mana_max])
	# Plan 2A.5: profiles no longer deduct costs — the state commands pay them.
	var played: int = st.enemy_graveyard.size() - e_grave_before
	_check(played == 0 or st.enemy_essence + st.enemy_mana < 2,
		"F1: the enemy paid for its %d play(s) (left %dE/%dM)" % [played, st.enemy_essence, st.enemy_mana])
	await _teardown(scene)

## F13: Void Ritualist Prime's champion counter (bug B1 — crashed live on every
## enemy spell) ticks, summons exactly one champion, and stops.
func _f13_vrp_champion_progress() -> void:
	var scene: Node = await _launch(13, "swarm")
	var vb: CardData = CardDatabase.get_card("void_bolt")
	for i in 6:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "enemy")
		ctx.card = vb
		scene.state.trigger_manager.fire(ctx)
		await get_tree().process_frame
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < TURN_TIMEOUT_MS:
		if _count_on_board(scene.state.enemy_board, "champion_void_ritualist_prime") > 0:
			break
		await get_tree().process_frame
	_check(scene.state._champion_vrp_summoned, "F13: champion flagged summoned")
	_check(scene.state._champion_vrp_spells_cast == 5, "F13: counter stopped at 5 (got %d)" % scene.state._champion_vrp_spells_cast)
	var champions: int = _count_on_board(scene.state.enemy_board, "champion_void_ritualist_prime")
	_check(champions == 1, "F13: exactly one champion on board (got %d)" % champions)
	await _teardown(scene)

## The shared CombatState handlers driving the live presenter (plan 1.4):
## token summons both sides, a lethal minion attack (_on_minion_vanished →
## death animation + on-death deferral), hero damage and a clamped heal
## (_on_hero_damaged_visual / _on_hero_healed_visual). run_checks.sh fails on
## any SCRIPT ERROR these paths print.
func _live_rules_paths() -> void:
	var scene: Node = await _launch(1, "swarm")
	var st: CombatState = scene.state
	st._summon_token("void_imp", "player")
	st._summon_token("shadow_hound", "enemy")
	var attacker: MinionInstance = st.player_board.back() if not st.player_board.is_empty() else null
	var defender: MinionInstance = st.enemy_board.back() if not st.enemy_board.is_empty() else null
	_check(attacker != null and defender != null, "live: tokens summoned on both boards")
	if attacker == null or defender == null:
		await _teardown(scene)
		return
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < TURN_TIMEOUT_MS and (attacker.slot_index < 0 or defender.slot_index < 0):
		await get_tree().process_frame
	defender.current_health = 1
	scene.state.combat_manager.resolve_minion_attack(attacker, defender)
	await _drain(scene)
	_check(not st.enemy_board.has(defender), "live: lethal attack removed the defender")
	var enemy_before: int = st.enemy_hp
	scene.state.combat_manager.apply_hero_damage("enemy",
			CombatManager.make_damage_info(100, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE))
	_check(st.enemy_hp == enemy_before - 100, "live: enemy hero took 100 (%d → %d)" % [enemy_before, st.enemy_hp])
	scene.state.combat_manager.apply_hero_damage("player",
			CombatManager.make_damage_info(300, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE))
	st._on_hero_healed("player", 1000)
	_check(st.player_hp == st.player_hp_max, "live: heal clamps at max HP (%d / %d)" % [st.player_hp, st.player_hp_max])
	await _drain(scene)
	# Trap routing (plan 2A.2): the state springs + consumes the trap, the
	# presenter's play_trap_reveals resolves it at its card animation's impact.
	var trap := TrapCardData.new()
	trap.id = "_smoke_probe_trap"
	trap.card_name = "Probe Trap"
	trap.trigger = Enums.TriggerEvent.ON_ENEMY_TURN_START
	trap.effect_steps = [{"type": "DAMAGE_HERO", "amount": 100}]
	st.active_traps.append(trap)
	var trap_hp: int = st.enemy_hp
	scene.state.trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_ENEMY_TURN_START, "enemy"))
	_check(not st.active_traps.has(trap), "live: sprung trap consumed at once")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < TURN_TIMEOUT_MS and st.enemy_hp == trap_hp:
		await get_tree().process_frame
	_check(st.enemy_hp == trap_hp - 100, "live: trap resolved at its reveal (%d → %d)" % [trap_hp, st.enemy_hp])
	await get_tree().create_timer(1.0).timeout  # the reveal's trailing gap
	# Relic bar → state.cmd_activate_relic (plan 2A.6). Blood Chalice asks for a
	# target first and only spends its charge once one is picked.
	st.relic_runtime = RelicRuntime.new()
	st.relic_runtime.setup(["dark_mirror", "blood_chalice"])
	for rs: RelicRuntime.RelicState in st.relic_runtime.relics:
		rs.cooldown_remaining = 0
	scene._on_relic_activated(st.relic_runtime.find_by_id("dark_mirror"))
	_check(st._relic_cost_reduction == 2, "live: Dark Mirror via the command")
	st.relic_runtime.activated_this_turn = false
	var chalice: int = st.relic_runtime.find_by_id("blood_chalice")
	scene._on_relic_activated(chalice)
	_check(st.relic_runtime.get_state(chalice).charges_remaining > 0 and not st.relic_runtime.activated_this_turn,
		"live: Blood Chalice waits for a target before spending")
	var chalice_hp: int = st.enemy_hp
	scene._resolve_relic_target_hero()
	_check(st.enemy_hp == chalice_hp - 500, "live: Blood Chalice hit the enemy hero (%d → %d)" % [chalice_hp, st.enemy_hp])
	await _drain(scene)
	print("LiveSmoke: live rules paths completed")
	await _teardown(scene)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## A whole fight in the real scene (plan 3.5): the player is a StateAgent on
## the default player profile, the enemy the scene's own EnemyTurnRunner; the presenter
## runs with `instant` so nothing animates. Ends with a winner, the presenter
## idle and the journal fully played.
func _ai_vs_ai_fight() -> void:
	GameManager.next_combat_seed = 7  # a reproducible fight
	var scene: Node = await _launch(1, "swarm")
	var st: CombatState = scene.state
	scene.presenter.instant = true
	var agent := StateAgent.new()
	agent.setup(st, "player")
	var profile: CombatProfile = ProfileRegistry.make("player", "default")
	profile.setup(agent)
	# The agent ends its turns with no growth pick; grow it by the profile's
	# curve instead, as the sim does.
	st.growth_hooks["player"] = func(side: String, turn: int) -> void:
		profile.grow_resources(st, side, turn)
	var t0: int = Time.get_ticks_msec()
	var turns: int = 0
	while st.winner.is_empty() and not scene.state._combat_ended and Time.get_ticks_msec() - t0 < FIGHT_TIMEOUT_MS:
		if st.is_player_turn:
			await profile.play_phase()
			if st.winner.is_empty():
				await profile.attack_phase()
			if st.winner.is_empty() and st.is_player_turn:
				await scene.presenter.pump_and_wait_idle()
				st.cmd_end_turn("player")
				turns += 1
		await get_tree().process_frame
	_check(not st.winner.is_empty(), "fight: a winner within %d s (player turns %d, hp %d / %d)" % [FIGHT_TIMEOUT_MS / 1000, turns, st.player_hp, st.enemy_hp])
	await scene.presenter.pump_and_wait_idle()
	_check(scene.presenter.is_idle() and scene.presenter.cursor == st.journal.size(),
		"fight: presenter idle with the journal fully played (%d / %d)" % [scene.presenter.cursor, st.journal.size()])
	print("LiveSmoke: AI-vs-AI fight completed (%s wins, turn %d, %d events)" % [st.winner, st.turn_number, st.journal.size()])
	await _teardown(scene)

func _launch(encounter: int, deck_preset: String) -> Node:
	GameManager.start_new_run()
	GameManager.current_hero = "lord_vael"
	GameManager.current_enemy = GameManager.get_encounter(encounter)
	GameManager.player_deck = _preset(deck_preset)
	var scene: Node = load(COMBAT_SCENE).instantiate()
	add_child(scene)
	for i in 5:
		await get_tree().process_frame
	return scene

## Wait for the scene's in-flight VFX / death animations to finish.
func _drain(scene: Node) -> void:
	await scene.presenter.pump_and_wait_idle()
	_check(scene.presenter.cursor == scene.state.journal.size(), "presenter played the whole journal")

## Free the scene only once its coroutines (hand draw stagger, VFX, death anims)
## have drained — freeing or detaching it mid-await makes them call get_tree()
## on a dead/detached node, which prints a SCRIPT ERROR that run_checks.sh flags.
func _teardown(scene: Node) -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < TURN_TIMEOUT_MS:
		var busy: bool = scene.hand_display._draw_playing or not scene.presenter.is_idle()
		if not busy:
			break
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	scene.queue_free()
	await get_tree().process_frame

func _preset(preset_id: String) -> Array[String]:
	var ids: Array[String] = []
	for entry in PresetDecks.DECKS:
		if entry.get("id", "") == preset_id:
			for c in (entry.get("cards", []) as Array):
				ids.append(str(c))
	return ids

func _count_on_board(board: Array, card_id: String) -> int:
	var n: int = 0
	for m: MinionInstance in board:
		if m.card_data.id == card_id:
			n += 1
	return n

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s" % label)
