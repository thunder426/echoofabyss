## SimTurnManager.gd
## Headless stand-in for TurnManager — a façade over the player side of the
## CombatState turn/resource/deck API (LIVE_SIM_UNIFICATION_PLAN.md 1.3). Rules
## code no longer calls it; it remains for sim/test callers until 2A.3 deletes it.
class_name SimTurnManager
extends RefCounted

const HAND_SIZE_MAX = CombatState.HAND_MAX  ## matches TurnManager.HAND_SIZE_MAX

var _sim: SimState

## No-op signal for duck-type compatibility with TurnManager.
signal resources_changed(essence: int, essence_max: int, mana: int, mana_max: int)

func setup(sim: SimState) -> void:
	_sim = sim

var is_player_turn: bool:
	get: return _sim.is_player_turn

var turn_number: int:
	get: return _sim.turn_number

var player_hand: Array[CardInstance]:
	get: return _sim.player_hand

var player_deck: Array[CardInstance]:
	get: return _sim.player_deck

var essence: int:
	get: return _sim.player_essence
	set(v): _sim.player_essence = v

var essence_max: int:
	get: return _sim.player_essence_max

var mana: int:
	get: return _sim.player_mana
	set(v): _sim.player_mana = v

var mana_max: int:
	get: return _sim.player_mana_max

func draw_card() -> void:
	_sim.draw_cards("player", 1)

func add_to_hand(card: CardData) -> void:
	_sim.add_to_hand("player", card)

func add_instance_to_hand(inst: CardInstance) -> void:
	_sim.add_to_hand("player", inst)

func gain_mana(amount: int) -> void:
	_sim.gain_mana("player", amount)

func grow_mana_max(amount: int = 1) -> void:
	_sim.grow_mana_max("player", amount)
	_sim.last_player_growth = "mana"

func grow_essence_max(amount: int = 1) -> void:
	_sim.grow_essence_max("player", amount)
	_sim.last_player_growth = "essence"

func gain_essence(amount: int) -> void:
	_sim.gain_essence("player", amount)

func convert_mana_to_essence(max_convert: int = -1) -> void:
	_sim.convert_mana_to_essence("player", max_convert)

func convert_essence_to_mana() -> void:
	_sim.convert_essence_to_mana("player")
