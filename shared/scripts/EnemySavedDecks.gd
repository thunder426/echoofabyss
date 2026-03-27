## EnemySavedDecks.gd
## Persists enemy decks to user://enemy_decks.json.
## Mirrors SavedDecks but kept separate so enemy decks don't pollute the player deck list.
class_name EnemySavedDecks
extends RefCounted

const SAVE_PATH := "user://enemy_decks.json"

## Returns all saved enemy decks as { deck_name: Array[card_id] }.
static func load_all() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return {}
	var data: Variant = json.get_data()
	if data is Dictionary:
		return data as Dictionary
	return {}

## Persists the full decks dictionary to disk.
static func save_all(decks: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(decks, "\t"))

## Saves (or overwrites) a single deck by name.
static func save_deck(deck_name: String, cards: Array) -> void:
	var all := load_all()
	all[deck_name] = cards
	save_all(all)

## Deletes a saved deck by name. No-op if not found.
static func delete_deck(deck_name: String) -> void:
	var all := load_all()
	all.erase(deck_name)
	save_all(all)
