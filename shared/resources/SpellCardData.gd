## SpellCardData.gd
## Card data for Spell type cards.
## Spells cost Mana, resolve immediately, then go to the discard pile.
class_name SpellCardData
extends CardData

## Whether this spell requires a target to be selected before resolving
@export var requires_target: bool = false

## Valid targets when requires_target is true
## e.g. "friendly_minion", "enemy_minion", "any_minion", "enemy_hero"
@export var target_type: String = ""

## Effect ID resolved when this spell is cast. Used when effect_steps is empty (legacy path).
@export var effect_id: String = ""

## Declarative effect steps. When non-empty, EffectResolver runs these instead
## of dispatching through the legacy _resolve_spell_effect match chain.
@export var effect_steps: Array = []

func _init() -> void:
	card_type = Enums.CardType.SPELL
	cost_type = Enums.CostType.MANA
