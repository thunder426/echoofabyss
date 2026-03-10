## MinionInstance.gd
## The runtime state of a minion currently on the board.
## CardData (MinionCardData) is the static definition — MinionInstance is the live version.
class_name MinionInstance
extends RefCounted

# Who owns this minion
var owner: String = "player"  # "player" or "enemy"

# Original card definition — never modified
var card_data: MinionCardData

# Current stats — these change during combat
var current_atk: int = 0
var current_health: int = 0

# Temporary ATK bonus that expires at end of turn (e.g. from Dark Surge)
var temp_atk_bonus: int = 0

# Current state on the board
var state: Enums.MinionState = Enums.MinionState.EXHAUSTED

# Which board slot index this minion occupies (0–4)
var slot_index: int = -1

# ---------------------------------------------------------------------------
# Initialise from a CardData definition
# ---------------------------------------------------------------------------

static func create(data: MinionCardData, owner_id: String) -> MinionInstance:
	var instance := MinionInstance.new()
	instance.card_data = data
	instance.owner = owner_id
	instance.current_atk = data.atk
	instance.current_health = data.health
	# Minions are exhausted (cannot attack) on the turn they are summoned
	# unless they have the Rush keyword
	if Enums.Keyword.RUSH in data.keywords:
		instance.state = Enums.MinionState.NORMAL
	else:
		instance.state = Enums.MinionState.EXHAUSTED
	return instance

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Total effective ATK including temporary bonuses
func effective_atk() -> int:
	return current_atk + temp_atk_bonus

## True if this minion can be selected as an attacker
func can_attack() -> bool:
	return state == Enums.MinionState.NORMAL and effective_atk() > 0

## True if this minion has Taunt
func has_taunt() -> bool:
	return Enums.Keyword.TAUNT in card_data.keywords

## True if this minion has Lifedrain
func has_lifedrain() -> bool:
	return Enums.Keyword.LIFEDRAIN in card_data.keywords

## Called at the start of each player turn to clear temporary buffs
## and allow the minion to attack again
func on_turn_start() -> void:
	temp_atk_bonus = 0
	if state == Enums.MinionState.EXHAUSTED:
		state = Enums.MinionState.NORMAL

## Returns a readable summary for debug purposes
func debug_label() -> String:
	return "%s [ATK:%s HP:%s]" % [card_data.card_name, str(effective_atk()), str(current_health)]
