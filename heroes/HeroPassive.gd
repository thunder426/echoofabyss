## HeroPassive.gd
## A single passive ability belonging to a hero.
## Registered in HeroData.passives — gameplay effects are implemented in combat
## code and looked up via HeroDatabase.has_passive(hero_id, passive_id).
class_name HeroPassive
extends Resource

## Unique identifier — used by combat code to check if a passive is active.
## Example: "void_imp_boost", "void_imp_extra_copy", "void_imp_draw_copy"
var id: String = ""

## Human-readable description shown on the hero select card.
var description: String = ""

## Optional icon shown in passive tooltips and hero UI.
var icon_path: String = ""
