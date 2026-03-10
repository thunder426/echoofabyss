## EnvironmentCardData.gd
## Card data for Environment type cards.
## Environments cost Mana and create a persistent global board effect.
## Only ONE environment is active at a time — playing a new one replaces the old.
class_name EnvironmentCardData
extends CardData

## Effect ID applied every turn while this environment is active.
## References EffectDatabase for the passive logic.
@export var passive_effect_id: String = ""

## Effect ID triggered once when this environment is first played.
## Leave empty for no on-play burst effect.
@export var on_enter_effect_id: String = ""

## Effect ID triggered once when this environment is replaced by another.
## Useful for "when this leaves, do X" effects.
@export var on_replace_effect_id: String = ""

## Human-readable summary of what the passive does (shown on card)
@export_multiline var passive_description: String = ""

func _init() -> void:
	card_type = Enums.CardType.ENVIRONMENT
	cost_type = Enums.CostType.MANA
