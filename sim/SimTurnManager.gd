## SimTurnManager.gd
## Duck-typed replacement for TurnManager used by EffectResolver when
## ctx.owner == "player" inside headless simulations.
## Only implements the methods EffectResolver actually calls.
class_name SimTurnManager
extends RefCounted

const HAND_SIZE_MAX = SimState.PLAYER_HAND_MAX  ## matches TurnManager.HAND_SIZE_MAX

var _sim: SimState

## No-op signal for duck-type compatibility with TurnManager.
signal resources_changed(essence: int, essence_max: int, mana: int, mana_max: int)

func setup(sim: SimState) -> void:
	_sim = sim

# ---------------------------------------------------------------------------
# EffectResolver API
# ---------------------------------------------------------------------------

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
	_sim._draw_player(1)

func add_to_hand(card: CardData) -> void:
	if _sim.player_hand.size() < SimState.PLAYER_HAND_MAX:
		_sim.player_hand.append(CardInstance.create(card))

func gain_mana(amount: int) -> void:
	_sim.player_mana = mini(_sim.player_mana + amount, _sim.player_mana_max)

func grow_mana_max(amount: int = 1) -> void:
	for _i in amount:
		if _sim.player_essence_max + _sim.player_mana_max >= SimState.COMBINED_RESOURCE_CAP:
			break
		_sim.player_mana_max += 1
		_sim.last_player_growth = "mana"

## Grow Essence maximum by amount, respecting the combined resource cap. Sim mirror
## of TurnManager.grow_essence_max. The live version takes no arg (+1 always); this
## one matches grow_mana_max's signature for call-site consistency.
func grow_essence_max(amount: int = 1) -> void:
	for _i in amount:
		if _sim.player_essence_max + _sim.player_mana_max >= SimState.COMBINED_RESOURCE_CAP:
			break
		_sim.player_essence_max += 1
		_sim.last_player_growth = "essence"

func gain_essence(amount: int) -> void:
	_sim.player_essence += amount

func convert_mana_to_essence(max_convert: int = -1) -> void:
	var amount := _sim.player_mana if max_convert < 0 else mini(_sim.player_mana, max_convert)
	_sim.player_mana     -= amount
	_sim.player_essence   = mini(_sim.player_essence + amount, SimState.ESSENCE_HARD_CAP)

func convert_essence_to_mana() -> void:
	var amount        := _sim.player_essence
	_sim.player_essence = 0
	_sim.player_mana    = mini(_sim.player_mana + amount, _sim.player_mana_max)
