## EnemyData.gd
## Configuration resource for a single enemy encounter.
class_name EnemyData
extends Resource

@export var enemy_name: String = "Unknown"
@export var hp: int = 20
## Card IDs that form the enemy's deck. Shuffled once at combat start; drawn without replacement (reshuffles when empty).
@export var deck: Array[String] = []
## Short title shown on the encounter loading screen (e.g. "ENCOUNTER I").
@export var title: String = ""
## Flavour text / story shown on the left panel of the encounter loading screen.
@export var story: String = ""
## Path to the full-screen background art for the encounter loading screen.
@export var background_path: String = "res://assets/art/progression/backgrounds/a1_combat_background.png"
## Passive IDs active for this encounter (e.g. "feral_instinct", "pack_instinct").
@export var passives: Array[String] = []
## AI behaviour profile ID. "default" = generic EnemyAI logic; others are encounter-specific.
@export var ai_profile: String = "default"
