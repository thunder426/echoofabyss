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

## Optional path to a video file used as animated card art (.ogv).
## If set and the file exists, it overrides art_path in CardVisual.
@export var art_video_path: String = ""

## Optional dedicated art for the battlefield slot display (BoardSlot).
## When set, BoardSlot uses this instead of art_path so you can supply
## a cropped / differently-framed version optimised for the smaller slot.
@export var battlefield_art_path: String = ""

## Faction this card belongs to. "neutral" or "abyss_order" (more factions added later)
@export var faction: String = "neutral"

## Card pool this card belongs to. Controls where it appears (deck builder, collection).
## "" = token/internal; "abyss_core" / "neutral_core" = starter deck pool;
## "vael_common" / "vael_piercing_void" = Lord Vael unlock pools.
@export var pool: String = ""

## Act gate: earliest act this card can appear in rewards/shop (1–4).
## 0 = token/internal card, not available through acquisition.
@export var act_gate: int = 0

## Void Spark cost — enemy-only dual cost. To play this card, the enemy must
## sacrifice this many Void Spark tokens from their board IN ADDITION to the
## normal mana/essence cost. 0 = no Spark cost (normal card).
@export var void_spark_cost: int = 0
