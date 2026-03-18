## EnemyData.gd
## Configuration resource for a single enemy encounter.
class_name EnemyData
extends Resource

@export var enemy_name: String = "Unknown"
@export var hp: int = 20
## Card IDs that form the enemy's deck. Shuffled once at combat start; drawn without replacement (reshuffles when empty).
@export var deck: Array[String] = []
