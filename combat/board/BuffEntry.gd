## BuffEntry.gd
## A single buff or debuff applied to a MinionInstance.
## Created and managed exclusively by BuffSystem — do not construct directly.
class_name BuffEntry
extends RefCounted

## Which stat or keyword this entry modifies (Enums.BuffType value)
var type: int = 0

## Magnitude of the effect.
## For stat buffs: the numeric bonus/penalty value.
## For keyword grants (GRANT_TAUNT, GRANT_LIFEDRAIN): always 1.
## For CORRUPTION: ATK penalty per stack (100 normally, 200 with abyssal_weakening talent).
var amount: int = 0

## Who/what applied this buff. Used by BuffSystem.remove_source for targeted removal
## (e.g. removing all "dominion_rune" buffs when the rune leaves the board).
var source: String = ""

## If true, this entry is cleared by BuffSystem.expire_temp at the start of the owner's turn.
var is_temp: bool = false
