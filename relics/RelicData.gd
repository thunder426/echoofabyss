## RelicData.gd
## Static definition of a relic.
## Relics are activated abilities with limited charges and cooldowns.
class_name RelicData
extends Resource

var id: String = ""
var relic_name: String = ""
var description: String = ""
var act: int = 1           ## Which act this relic is offered in (1, 2, or 3)
var charges: int = 1       ## Number of uses per combat
var cooldown: int = 2      ## Turns before first use and between uses
var effect_id: String = "" ## Effect identifier for activation logic
var icon_path: String = "" ## Path to relic icon texture (e.g. "res://assets/art/relics/relic_bone_shield.png")
