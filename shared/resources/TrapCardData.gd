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

## Declarative effect steps run by EffectResolver when this trap activates.
## Replaces the old string-based effect_id dispatch.
@export var effect_steps: Array = []

## If true the trap resets after triggering instead of being consumed (one-use by default)
@export var reusable: bool = false

## --- Rune subtype ---
## If true this card is a Rune: placed face-up, persistent (never auto-consumed by trigger),
## and acts as a ritual component checked by the ritual system on ON_RUNE_PLACED.
@export var is_rune: bool = false

## Which rune type this card represents (Enums.RuneType value).
## Only meaningful when is_rune = true.
@export var rune_type: int = Enums.RuneType.VOID_RUNE

## TriggerEvent the rune's primary aura handler listens to. -1 = no handler.
@export var aura_trigger: int = -1

## Steps run by EffectResolver when the primary aura trigger fires.
@export var aura_effect_steps: Array = []

## Optional second TriggerEvent (e.g. Soul Rune reset on enemy turn start). -1 = none.
@export var aura_secondary_trigger: int = -1

## Steps run when the secondary aura trigger fires.
@export var aura_secondary_steps: Array = []

## Steps run once immediately when the rune is placed (e.g. Dominion Rune existing-minion sweep).
@export var aura_on_place_steps: Array = []

## Steps run once when the rune is removed / destroyed (e.g. Dominion Rune buff teardown).
@export var aura_on_remove_steps: Array = []

## Glow color for the rune on the battlefield. Used for border and pulse glow.
## Default transparent = no custom glow (falls back to purple).
@export var rune_glow_color: Color = Color(0, 0, 0, 0)

func _init() -> void:
	card_type = Enums.CardType.TRAP
	cost_type = Enums.CostType.MANA
