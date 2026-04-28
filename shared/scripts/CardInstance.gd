## CardInstance.gd
## A per-copy wrapper around a CardData definition.
## Every card drawn or added to a hand becomes its own CardInstance with a unique
## instance_id — two copies of the same card (e.g. two Void Imps) are distinct objects.
##
## mana_delta / essence_delta — per-turn adjustments to the displayed and effective cost,
## split per resource so a single card can be cheapened on one axis without touching the
## other (e.g. Fiendish Pact discounts essence on Demons; rune_caller discounts mana on
## Runes). Negative = cheaper. Both reset to 0 on player turn start (and on consume for
## one-shot pending discounts like Fiendish Pact).
class_name CardInstance
extends RefCounted

## Auto-incrementing counter shared across all instances this session.
static var _next_id: int = 0

## Unique identity — never reused.
var instance_id: int

## The immutable card definition this copy is based on.
var card_data: CardData

## Per-turn Mana cost modifier. Applied to spells/traps/environments (their single cost
## field) and the mana_cost portion of dual-cost minions. Negative = cheaper.
var mana_delta: int = 0

## Per-turn Essence cost modifier. Applied to MinionCardData.essence_cost only.
## Negative = cheaper.
var essence_delta: int = 0

## Turn number on which this card was played (left the hand to resolve).
## -1 while the card is still in deck or hand.  Stamped at graveyard append time.
var resolved_on_turn: int = -1

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

## Effective mana cost for this specific copy, accounting for mana_delta.
## For MinionCardData the mana_cost portion is adjusted (essence_cost goes through
## essence_delta, read separately by HandDisplay).
## For all other card types (Spell, Trap, Environment) the single cost field is adjusted.
func effective_cost() -> int:
	if card_data is MinionCardData:
		return maxi(0, (card_data as MinionCardData).mana_cost + mana_delta)
	return maxi(0, card_data.cost + mana_delta)

## Reset both per-turn deltas. Called at player turn start and when a pending discount
## is consumed (e.g. Fiendish Pact after the next Demon is played).
func reset_deltas() -> void:
	mana_delta = 0
	essence_delta = 0
