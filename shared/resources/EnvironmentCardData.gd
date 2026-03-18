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

## 2-Rune rituals this environment enables.
## Each entry is a RitualData with exactly 2 required_runes.
## These handlers are registered when this environment is played and
## unregistered when it is replaced or destroyed.
@export var rituals: Array[RitualData] = []

## If true, the passive also fires on the enemy's turn (ON_ENEMY_TURN_START).
## Standard environments only fire on the player's turn.
@export var fires_on_enemy_turn: bool = false

## Effect ID to apply when a friendly player minion dies while this environment is active.
## Leave empty for no on-death environment effect.
@export var on_player_minion_died_effect_id: String = ""

func _init() -> void:
	card_type = Enums.CardType.ENVIRONMENT
	cost_type = Enums.CostType.MANA
