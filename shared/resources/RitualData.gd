## RitualData.gd
## Defines a single ritual — a combination of runes that automatically triggers
## a powerful spell-like effect when all required runes are present on the board.
##
## 2-Rune rituals are attached to EnvironmentCardData.rituals and are registered
## when that environment is played, unregistered when it is replaced or destroyed.
##
## 3-Rune (Grand) rituals are attached to TalentData.grand_ritual and are
## registered once at combat start alongside all other passive handlers.
class_name RitualData
extends Resource

## Display name shown in the combat log when this ritual fires.
@export var ritual_name: String = ""

## Short description shown on the environment or talent card.
@export var description: String = ""

## Rune types required to trigger this ritual (Enums.RuneType values).
## All listed rune types must be present simultaneously on the board.
## 2-Rune rituals: exactly 2 entries.  Grand rituals: exactly 3 entries.
@export var required_runes: Array[int] = []

## Declarative effect steps run by EffectResolver when this ritual fires.
@export var effect_steps: Array = []
