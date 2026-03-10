## MinionCardData.gd
## Card data for Minion type cards.
## Minions cost Abyss Essence and occupy board slots.
## Combat uses ATK / HP — HP reaching 0 means the minion is destroyed.
class_name MinionCardData
extends CardData

## Base attack value
@export var atk: int = 1

## Hit points — minion is destroyed when this reaches 0
@export var health: int = 1

## Sub-type tag used for synergy triggers (e.g. "all your Demons gain +1 ATK")
@export var minion_type: Enums.MinionType = Enums.MinionType.DEMON

## Keywords this minion has (e.g. [Enums.Keyword.TAUNT, Enums.Keyword.RUSH])
@export var keywords: Array[int] = []

## Effect triggered when this minion is played from hand (Battlecry equivalent)
@export var on_play_effect: String = ""

## Effect triggered when this minion is destroyed (Deathrattle)
@export var on_vanish_effect: String = ""

func _init() -> void:
	card_type = Enums.CardType.MINION
	cost_type = Enums.CostType.ESSENCE
