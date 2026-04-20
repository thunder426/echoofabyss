## Act3RelicsSmokeTest.gd
## Quick probes for the 4 rebalanced Act 3 relics. Fires each in isolation on a
## SimState, then asserts the observable effect landed.
extends Node

var _pass := 0
var _fail := 0

func _ready() -> void:
	print("=== Act 3 Relics Smoke Test ===\n")
	_test_void_hourglass()
	_test_oblivion_seal()
	_test_nether_crown()
	_test_phantom_deck()
	print("\n=== %d passed, %d failed ===" % [_pass, _fail])
	get_tree().quit(_fail)

func _build_state() -> SimState:
	var state := SimState.new()
	state.talents = []
	state.hero_passives = []
	state.enemy_passives = []
	state.setup(["void_imp"], ["rabid_imp"], 3000, 2000)
	var ts := SimTriggerSetup.new()
	ts.setup(state)
	return state

func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s %s" % [name, detail])
	else:
		_fail += 1
		print("  FAIL  %s %s" % [name, detail])

func _test_void_hourglass() -> void:
	var state := _build_state()
	# setup() gives E_max=1, M_max=1 per CombatSim.run; mimic that here.
	state.player_essence_max = 1
	state.player_mana_max = 1
	var fx := RelicEffects.new()
	fx.setup(state)
	fx.resolve("relic_extra_turn")
	_check("Void Hourglass: +1 max Essence, +1 max Mana",
		state.player_essence_max == 2 and state.player_mana_max == 2,
		"(E_max=%d, M_max=%d)" % [state.player_essence_max, state.player_mana_max])
	state.teardown()

func _test_oblivion_seal() -> void:
	var state := _build_state()
	state.player_essence_max = 5
	state.player_mana_max = 5
	var enemy_hp_before: int = state.enemy_hp
	var traps_before: int = state.active_traps.size()
	var fx := RelicEffects.new()
	fx.setup(state)
	fx.resolve("relic_summon_demon")
	var traps_after: int = state.active_traps.size()
	var hp_dealt: int = enemy_hp_before - state.enemy_hp
	# No enemy minions on board → hero must take the 200 damage.
	_check("Oblivion Seal: rune placed + 200 damage to enemy hero",
		traps_after == traps_before + 1 and hp_dealt == 200,
		"(traps %d→%d, hp dealt=%d)" % [traps_before, traps_after, hp_dealt])
	state.teardown()

func _test_nether_crown() -> void:
	var state := _build_state()
	# Put 2 minions on board
	var data := CardDatabase.get_card("void_imp") as MinionCardData
	for i in 2:
		var m := MinionInstance.create(data, "player")
		state.player_board.append(m)
	var before_atks: Array[int] = []
	for m in state.player_board:
		before_atks.append((m as MinionInstance).effective_atk())
	var fx := RelicEffects.new()
	fx.setup(state)
	fx.resolve("relic_mass_buff")
	var ok := true
	for i in state.player_board.size():
		var delta: int = (state.player_board[i] as MinionInstance).effective_atk() - before_atks[i]
		if delta != 100:
			ok = false
	_check("Nether Crown: +100 ATK to all friendlies (permanent)",
		ok,
		"(board size=%d)" % state.player_board.size())
	state.teardown()

func _test_phantom_deck() -> void:
	var state := _build_state()
	# Pad hand with 3 cards
	var imp := CardDatabase.get_card("void_imp")
	for i in 3:
		state.turn_manager.add_to_hand(imp)
	var before: int = state.player_hand.size()
	var fx := RelicEffects.new()
	fx.setup(state)
	fx.resolve("relic_copy_cards")
	var after: int = state.player_hand.size()
	_check("Phantom Deck: copied 2 random cards into hand",
		after == before + 2,
		"(hand %d→%d)" % [before, after])
	state.teardown()
