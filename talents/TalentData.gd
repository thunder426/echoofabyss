## TalentData.gd
## Static definition of a single talent node in a hero's talent tree.
class_name TalentData
extends Resource

## Unique identifier used to look up and store this talent
var id: String = ""

## Display name shown in the talent tree UI
var talent_name: String = ""

## Effect description shown to the player
var description: String = ""

## Hero this talent belongs to (matches HeroData.id, e.g. "lord_vael")
var hero_id: String = ""

## Which branch this talent belongs to: "swarm" | "corruption" | "void_bolt"
var branch: String = ""

## Position in the branch (0 = entry node, 3 = capstone)
var tier: int = 0

## ID of the talent that must be unlocked first ("" = no prerequisite)
var requires: String = ""

## Optional 3-Rune Grand Ritual unlocked by this talent.
## Registered at combat start alongside other passive handlers.
## null = this talent does not grant a grand ritual.
var grand_ritual: RitualData = null
