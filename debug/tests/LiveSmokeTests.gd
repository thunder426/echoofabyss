## LiveSmokeTests.gd
## Headless smoke test of the LIVE combat shell (CombatScene), which the rest of
## the suite never instantiates — every other test runs on SimState. Catches the
## class of bug where rules code works in sim and crashes live (task 040, B1).
##
## Run from tools/run_checks.sh (separate process: RunAllTests quits the tree),
## or directly:
##   godot --headless --path . res://debug/tests/LiveSmoke.tscn
## Exit code = failed checks. run_checks.sh also fails on any `SCRIPT ERROR`.
extends Node

const COMBAT_SCENE := "res://combat/board/CombatScene.tscn"
const TURN_TIMEOUT_MS := 20000

var _fails: int = 0

func _ready() -> void:
	UserProfile.saving_disabled = true
	# Small but non-zero: at 0, VfxSequence completes synchronously and drops
	# mid-phase beats (buff application, impact hits).
	BaseVfx.time_scale = 0.05
	await _f1_enemy_turn_completes()
	await _f13_vrp_champion_progress()
	print("LiveSmoke: %s (%d failed)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(_fails)

# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

## F1: combat boots, the opening hand is dealt, and a full enemy turn runs.
func _f1_enemy_turn_completes() -> void:
	var scene: Node = await _launch(1, "swarm")
	var tm = scene.turn_manager
	_check(scene.state.player_hp > 0, "F1: player hp > 0")
	_check(tm.player_hand.size() == 4, "F1: opening hand is 4 cards (got %d)" % tm.player_hand.size())
	_check(tm.is_player_turn, "F1: player acts first")
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
	await _teardown(scene)

## F13: Void Ritualist Prime's champion counter (bug B1 — crashed live on every
## enemy spell) ticks, summons exactly one champion, and stops.
func _f13_vrp_champion_progress() -> void:
	var scene: Node = await _launch(13, "swarm")
	var vb: CardData = CardDatabase.get_card("void_bolt")
	for i in 6:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "enemy")
		ctx.card = vb
		scene.trigger_manager.fire(ctx)
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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

## Free the scene only once its coroutines (hand draw stagger, VFX, death anims)
## have drained — freeing or detaching it mid-await makes them call get_tree()
## on a dead/detached node, which prints a SCRIPT ERROR that run_checks.sh flags.
func _teardown(scene: Node) -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < TURN_TIMEOUT_MS:
		var busy: bool = scene.hand_display._draw_playing or scene._on_play_vfx_active \
				or scene._active_death_anims > 0
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
