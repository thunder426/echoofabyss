## TestConfig.gd
## Autoload singleton that holds test combat configuration.
## Set fields and call launch() from TestLaunchScene to enter test combat.
extends Node

## True while a test combat is active. CombatScene reads this.
var enabled: bool = false

## Card IDs added to the player's hand at combat start.
var hand_cards: Array[String] = []

## Card IDs pre-summoned onto the player board at combat start.
var player_board_cards: Array[String] = []

## Card IDs pre-summoned onto the enemy board at combat start.
var enemy_board_cards: Array[String] = []

## Override player starting HP. -1 = use GameManager default (3000).
var player_hp: int = -1

## Override enemy starting HP. -1 = use enemy data default.
var enemy_hp: int = -1

## Enemy name shown in the HUD.
var enemy_name: String = "Training Dummy"

## Card IDs forming the player's draw deck at combat start. Empty = no draw pile.
var player_deck_cards: Array[String] = []

## Card IDs forming the enemy's deck. Empty = enemy passes every turn.
var enemy_deck: Array[String] = []

## Card IDs pre-placed as player traps at combat start.
var player_traps: Array[String] = []

## Card IDs pre-placed as enemy traps at combat start.
var enemy_traps: Array[String] = []

## If true, player starts with max essence + mana every turn (cheat).
var infinite_resources: bool = false

## Starting essence max for test mode (0 = use combat default).
var start_essence_max: int = 6

## Starting mana max for test mode (0 = use combat default).
var start_mana_max: int = 5

# ---------------------------------------------------------------------------

func reset() -> void:
	enabled             = false
	hand_cards          = []
	player_board_cards  = []
	enemy_board_cards   = []
	player_traps        = []
	enemy_traps         = []
	player_hp           = -1
	enemy_hp            = -1
	enemy_name          = "Training Dummy"
	player_deck_cards   = []
	enemy_deck          = []
	infinite_resources  = false
	start_essence_max   = 6
	start_mana_max      = 5

## Configure GameManager with a minimal test state then jump to CombatScene.
func launch() -> void:
	enabled = true

	# Keep any active run alive; if none, bootstrap minimal state
	if not GameManager.run_active:
		GameManager.run_active    = true
		GameManager.current_hero  = "lord_vael"

	# Build a minimal EnemyData for the test fight
	var e := EnemyData.new()
	e.enemy_name = enemy_name
	e.hp         = enemy_hp if enemy_hp > 0 else 2000
	e.deck       = enemy_deck
	GameManager.current_enemy = e

	# Override player HP if requested
	if player_hp > 0:
		GameManager.player_hp_max = player_hp
		GameManager.player_hp     = player_hp

	GameManager.player_deck = player_deck_cards

	GameManager.go_to_scene("res://combat/board/CombatScene.tscn")
