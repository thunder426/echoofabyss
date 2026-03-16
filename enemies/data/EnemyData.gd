## EnemyData.gd
## Configuration resource for a single enemy encounter.
class_name EnemyData
extends Resource

@export var enemy_name: String = "Unknown"
@export var hp: int = 20
## Card IDs the enemy draws from. Overrides EnemyAI's built-in CARD_POOL.
@export var card_pool: Array[String] = []
