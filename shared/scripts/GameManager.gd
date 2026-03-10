## GameManager.gd
## Global autoload — persists across all scenes.
## Holds run state, permanent unlocks, and scene transitions.
extends Node

# --- Run State ---
var run_active: bool = false
var current_act: int = 1
var current_node: int = 0
var player_hp: int = 30
var player_hp_max: int = 30

# --- Resources (in-combat, reset each combat) ---
var abyss_essence: int = 0
var abyss_essence_max: int = 1
var mana: int = 0
var mana_max: int = 1

# --- Deck & Cards ---
var player_deck: Array[String] = []   # card IDs
var permanent_unlocks: Array[String] = []  # survives between runs

# --- Scene Management ---
func go_to_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

# --- Run Management ---
func start_new_run() -> void:
	run_active = true
	current_act = 1
	current_node = 0
	player_hp = player_hp_max
	abyss_essence_max = 1
	mana_max = 1
	player_deck = _build_starter_deck()

func end_run(victory: bool) -> void:
	run_active = false
	if victory:
		pass  # TODO: grant permanent unlocks

func _build_starter_deck() -> Array[String]:
	# Returns card IDs for the Wanderer's starting deck
	return [
		"void_imp", "void_imp", "void_imp",
		"shadow_hound", "shadow_hound",
		"abyssal_brute",
		"soul_leech", "soul_leech",
		"dark_surge",
		"void_snare",
	]
