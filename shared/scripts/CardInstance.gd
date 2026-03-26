## CardInstance.gd
## A per-copy wrapper around a CardData definition.
## Every card drawn or added to a hand becomes its own CardInstance with a unique
## instance_id — two copies of the same card (e.g. two Void Imps) are distinct objects.
##
## cost_delta  — per-turn adjustment to the displayed and effective cost.
##               -1 = rune_caller discount this turn.  Cleared at player turn start.
##               Positive values would increase cost (e.g. piercing_void +1 Mana
##               is handled in the MinionCardData directly, not via cost_delta).
class_name CardInstance
extends RefCounted

## Auto-incrementing counter shared across all instances this session.
static var _next_id: int = 0

## Unique identity — never reused.
var instance_id: int

## The immutable card definition this copy is based on.
var card_data: CardData

## Per-turn cost modifier.  Negative = cheaper.  Cleared on player turn start.
var cost_delta: int = 0

# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

## Create a fresh CardInstance wrapping the given CardData.
static func create(data: CardData) -> CardInstance:
	var inst := CardInstance.new()
	inst.instance_id = _next_id
	_next_id += 1
	inst.card_data = data
	return inst

# ---------------------------------------------------------------------------
# Cost helpers
# ---------------------------------------------------------------------------

## Effective mana cost for this specific copy, accounting for cost_delta.
## For MinionCardData the mana_cost portion is adjusted (essence_cost is unchanged).
## For all other card types (Spell, Trap, Environment) the single cost field is adjusted.
func effective_cost() -> int:
	if card_data is MinionCardData:
		return maxi(0, (card_data as MinionCardData).mana_cost + cost_delta)
	return maxi(0, card_data.cost + cost_delta)
