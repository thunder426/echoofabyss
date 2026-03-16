## MinionCardData.gd
## Card data for Minion type cards.
## Minions cost Abyss Essence and occupy board slots.
## Combat uses ATK / HP — HP reaching 0 means the minion is destroyed.
class_name MinionCardData
extends CardData

## Abyss Essence cost to play this minion
@export var essence_cost: int = 1

## Additional Mana cost (0 = pure-essence minion; dual-cost minions need both)
@export var mana_cost: int = 0

## Base attack value
@export var atk: int = 1

## Hit points — minion is destroyed when this reaches 0
@export var health: int = 1

## Maximum Shield value (0 = no shield). Shield absorbs damage before HP.
## Physical shields (no SHIELD_REGEN keyword) do not regenerate.
## Magic shields (SHIELD_REGEN_1/2) regenerate at the start of the owner's turn.
@export var shield_max: int = 0

## Sub-type tag used for synergy triggers (e.g. "all your Demons gain +1 ATK")
@export var minion_type: Enums.MinionType = Enums.MinionType.DEMON

## Keywords this minion has (e.g. [Enums.Keyword.TAUNT, Enums.Keyword.RUSH])
@export var keywords: Array[int] = []

## Effect triggered when this minion is played from hand (On Play).
## Does NOT fire when summoned by a spell, trap, or other effect.
@export var on_play_effect: String = ""

## Effect triggered whenever this minion enters the board from ANY source
## (hand play, spell effect, trap effect, token generation, etc.) (On Summon).
@export var on_summon_effect: String = ""

## Effect triggered when this minion is destroyed (On Death).
@export var on_death_effect: String = ""

## Persistent board passive effect ID. Resolved by CombatScene whenever a
## friendly minion dies or a friendly minion is summoned. Empty = no passive.
@export var passive_effect_id: String = ""

## Effect ID resolved when the player casts any spell while this minion is on board.
## E.g. "add_void_bolt_on_spell" for Void Archmagus.
@export var on_spell_cast_passive_effect_id: String = ""

## Effect ID resolved each time _deal_void_bolt_damage fires while this minion is on board.
## E.g. "void_mark_per_channeler" for Void Channeler.
@export var on_void_bolt_passive_effect_id: String = ""

## Reduces the Mana cost of all player spells by this amount while this minion is on board.
## Multiple minions stack (e.g. two Archmagus = -2). Floor is 0.
@export var mana_cost_discount: int = 0

## Family / synergy tags used for data-driven queries instead of hardcoded card ID checks.
## Examples: "void_imp", "base_void_imp", "senior_void_imp", "void_champion", "imp_overseer".
## Add all applicable tags; CombatScene queries with _minion_has_tag() / _card_has_tag().
@export var minion_tags: Array[String] = []

## If true, this card is a champion that can be auto-summoned when its condition is met.
@export var is_champion: bool = false

## Condition type for auto-summon. Currently supported: "board_tag_count".
@export var auto_summon_condition: String = ""

## For "board_tag_count": the minion tag to count on the player board.
@export var auto_summon_tag: String = ""

## For "board_tag_count": the minimum count needed to trigger auto-summon.
@export var auto_summon_threshold: int = 0

func _init() -> void:
	card_type = Enums.CardType.MINION
