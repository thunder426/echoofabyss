## TrapCardData.gd
## Card data for Trap type cards.
## Traps cost Mana, are placed face-down, and activate automatically
## when their trigger condition is met during the enemy's turn.
class_name TrapCardData
extends CardData

## The condition that causes this trap to flip and resolve
@export var trigger: Enums.TrapTrigger = Enums.TrapTrigger.ON_ENEMY_ATTACK

## Optional: minimum value required to trigger (e.g. only fire if enemy minion ATK >= value)
## Set to 0 to ignore.
@export var trigger_threshold: int = 0

## Effect ID resolved when this trap activates. References EffectDatabase.
@export var effect_id: String = ""

## If true the trap resets after triggering instead of being consumed (one-use by default)
@export var reusable: bool = false

func _init() -> void:
	card_type = Enums.CardType.TRAP
	cost_type = Enums.CostType.MANA
