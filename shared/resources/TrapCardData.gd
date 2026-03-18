## TrapCardData.gd
## Card data for Trap type cards.
## Traps cost Mana, are placed face-down, and activate automatically
## when their trigger condition is met during the enemy's turn.
class_name TrapCardData
extends CardData

## The TriggerEvent that causes this trap to flip and resolve.
## Uses Enums.TriggerEvent values — the same unified event vocabulary as TriggerManager.
@export var trigger: int = Enums.TriggerEvent.ON_ENEMY_ATTACK

## Optional: minimum value required to trigger (e.g. only fire if enemy minion ATK >= value)
## Set to 0 to ignore.
@export var trigger_threshold: int = 0

## Effect ID resolved when this trap activates. References EffectDatabase.
@export var effect_id: String = ""

## If true the trap resets after triggering instead of being consumed (one-use by default)
@export var reusable: bool = false

## --- Rune subtype ---
## If true this card is a Rune: placed face-up, persistent (never auto-consumed by trigger),
## and acts as a ritual component checked by the ritual system on ON_RUNE_PLACED.
@export var is_rune: bool = false

## Which rune type this card represents (Enums.RuneType value).
## Only meaningful when is_rune = true.
@export var rune_type: int = Enums.RuneType.VOID_RUNE

## Aura effect identifier used by _apply_rune_aura / _remove_rune_aura in CombatScene.
## Maps to a known string: "void_rune_aura" | "blood_rune_aura" | "dominion_rune_aura" | "shadow_rune_aura"
## Only meaningful when is_rune = true.
@export var aura_effect_id: String = ""

func _init() -> void:
	card_type = Enums.CardType.TRAP
	cost_type = Enums.CostType.MANA
