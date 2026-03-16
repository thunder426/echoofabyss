## CardData.gd
## Base resource class for all cards.
## Extend this for each card type (MinionCardData, SpellCardData, etc.)
class_name CardData
extends Resource

## Unique identifier used to look up this card in CardDatabase
@export var id: String = ""

## Display name shown on the card
@export var card_name: String = ""

## Card type determines which subclass is used and what rules apply
@export var card_type: Enums.CardType = Enums.CardType.MINION

## Which resource pool is spent to play this card
@export var cost_type: Enums.CostType = Enums.CostType.ESSENCE

## Resource cost to play
@export var cost: int = 1

## Flavour/effect description shown on the card
@export_multiline var description: String = ""

## Path to the card artwork texture (e.g. "res://assets/art/cards/void_imp.png")
@export var art_path: String = ""

## If true this card can be offered as a permanent unlock after a final boss kill
@export var can_unlock: bool = false

## Faction this card belongs to. "neutral" or "abyss_order" (more factions added later)
@export var faction: String = "neutral"
