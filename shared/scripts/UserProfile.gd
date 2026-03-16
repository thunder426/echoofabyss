## UserProfile.gd
## Autoload — persists permanent unlocks and active run state across sessions.
## All save/load goes through user://profile.json.
extends Node

const SAVE_PATH := "user://profile.json"

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Save the full current state (permanent unlocks + active run if any).
## Called automatically by GameManager.go_to_scene().
func save() -> void:
	var data: Dictionary = {
		"permanent_unlocks": GameManager.permanent_unlocks,
		"run": null,
	}
	if GameManager.run_active:
		data["run"] = {
			"current_hero":     GameManager.current_hero,
			"player_deck":      GameManager.player_deck,
			"player_relics":    GameManager.player_relics,
			"run_node_index":   GameManager.run_node_index,
			"player_hp_max":    GameManager.player_hp_max,
			"talent_points":    GameManager.talent_points,
			"unlocked_talents": GameManager.unlocked_talents,
			"deck_built":       GameManager.deck_built,
		}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("UserProfile: cannot open '%s' for writing (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

## Load profile from disk into GameManager.
## Always restores permanent_unlocks. Also restores run state if one was saved.
## Returns true if the file existed and was parsed successfully.
func load_profile() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("UserProfile: save file corrupt, ignoring.")
		return false

	# Always restore permanent unlocks — needed even on New Run
	var raw_unlocks = parsed.get("permanent_unlocks", [])
	GameManager.permanent_unlocks.assign(raw_unlocks)

	# Restore run state if present
	var run = parsed.get("run", null)
	if run is Dictionary:
		GameManager.run_active      = true
		GameManager.current_hero    = run.get("current_hero", "lord_vael")
		GameManager.run_node_index  = int(run.get("run_node_index", 0))
		GameManager.player_hp_max   = int(run.get("player_hp_max", 3000))
		GameManager.talent_points   = int(run.get("talent_points", 0))
		GameManager.deck_built      = bool(run.get("deck_built", false))
		GameManager.player_deck.assign(run.get("player_deck", []))
		GameManager.player_relics.assign(run.get("player_relics", []))
		GameManager.unlocked_talents.assign(run.get("unlocked_talents", []))
		GameManager.current_enemy   = GameManager.get_encounter(GameManager.run_node_index)

	return true

## True if a save file exists that contains an active in-progress run.
func has_active_run() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	return parsed is Dictionary and parsed.get("run", null) is Dictionary

## End the current run in the save file (keeps permanent_unlocks, clears run key).
func clear_run() -> void:
	GameManager.run_active = false
	save()

## Wipe ALL progress — permanent unlocks and active run — and delete the save file.
## Called from the Main Menu "Reset All Progress" confirmation.
func reset_all() -> void:
	GameManager.permanent_unlocks.clear()
	GameManager.last_boss_unlocks.clear()
	GameManager.run_active = false
	GameManager.player_deck.clear()
	GameManager.player_relics.clear()
	GameManager.unlocked_talents.clear()
	GameManager.talent_points = 0
	GameManager.run_node_index = 0
	GameManager.deck_built = false
	GameManager.current_enemy = null
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
