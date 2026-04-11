## EncounterDecks.gd
## Unified enemy deck database.  Stores named decks and per-encounter pools
## (which deck IDs are available for each fight).  One deck is randomly picked
## from the pool at combat start.
##
## Persists to user://encounter_decks.json with this structure:
##   {
##     "pools": { "1": ["f1_a", "f1_b"], "2": ["f2_a"] },
##     "decks": {
##       "f1_a": { "cards": ["card_id", ...] },
##       "f1_b": { "cards": [...], "ai_profile": "feral_pack_screech" }
##     }
##   }
##
## Each deck is an object with:
##   - "cards": Array of card IDs (required)
##   - "ai_profile": String (optional) — overrides the encounter's default AI profile
##
## All decks are equal — no "default vs custom" distinction.
class_name EncounterDecks
extends RefCounted

const SAVE_PATH := "user://encounter_decks.json"

# ---------------------------------------------------------------------------
# Load / Save
# ---------------------------------------------------------------------------

static func load_data() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"pools": {}, "decks": {}}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {"pools": {}, "decks": {}}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return {"pools": {}, "decks": {}}
	var data: Variant = json.get_data()
	if data is Dictionary:
		var d := data as Dictionary
		if not d.has("pools"):
			d["pools"] = {}
		if not d.has("decks"):
			d["decks"] = {}
		return d
	return {"pools": {}, "decks": {}}

static func save_data(data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))

# ---------------------------------------------------------------------------
# Internal: extract cards/profile from a deck entry (handles both formats)
# ---------------------------------------------------------------------------

## Returns {"cards": Array, "ai_profile": String} from a raw deck entry.
## Supports both old format (plain array) and new format (dict with cards key).
static func _parse_deck_entry(entry: Variant) -> Dictionary:
	if entry is Dictionary:
		var d := entry as Dictionary
		var cards: Array = d.get("cards", []) as Array
		var profile: String = d.get("ai_profile", "") as String
		var limited: Array = d.get("limited", []) as Array
		return {"cards": cards, "ai_profile": profile, "limited": limited}
	if entry is Array:
		# Legacy format: plain array of card IDs
		return {"cards": entry as Array, "ai_profile": "", "limited": []}
	return {"cards": [], "ai_profile": "", "limited": []}

# ---------------------------------------------------------------------------
# Pool queries
# ---------------------------------------------------------------------------

## Returns the deck IDs assigned to an encounter's pool.
static func get_pool(encounter_index: int) -> Array[String]:
	var data := load_data()
	var pools: Dictionary = data.pools
	var key := str(encounter_index)
	if not pools.has(key):
		return []
	var ids: Array[String] = []
	for id in (pools[key] as Array):
		ids.append(id as String)
	return ids

## How many decks are in an encounter's pool.
static func variant_count(encounter_index: int) -> int:
	return get_pool(encounter_index).size()

# ---------------------------------------------------------------------------
# Deck queries
# ---------------------------------------------------------------------------

## Returns the card list for a specific deck ID.
static func get_deck(deck_id: String) -> Array[String]:
	var data := load_data()
	var decks: Dictionary = data.decks
	if not decks.has(deck_id):
		return []
	var parsed := _parse_deck_entry(decks[deck_id])
	var cards: Array[String] = []
	for id in (parsed.cards as Array):
		cards.append(id as String)
	return cards

## Returns the list of limited card IDs for a deck (one-time draw, not re-added).
static func get_deck_limited(deck_id: String) -> Array[String]:
	var data := load_data()
	var decks: Dictionary = data.decks
	if not decks.has(deck_id):
		return []
	var parsed := _parse_deck_entry(decks[deck_id])
	var result: Array[String] = []
	for id in (parsed.limited as Array):
		result.append(id as String)
	return result

## Returns the AI profile override for a deck, or "" if none set.
static func get_deck_profile(deck_id: String) -> String:
	var data := load_data()
	var decks: Dictionary = data.decks
	if not decks.has(deck_id):
		return ""
	var parsed := _parse_deck_entry(decks[deck_id])
	return parsed.ai_profile as String

## Picks a random deck from an encounter's pool and returns its card list.
static func pick_random(encounter_index: int) -> Array[String]:
	var pool := get_pool(encounter_index)
	if pool.is_empty():
		return []
	var deck_id: String = pool[randi() % pool.size()]
	return get_deck(deck_id)

## Same as pick_random but also returns the chosen deck ID and AI profile.
static func pick_random_with_id(encounter_index: int) -> Dictionary:
	var pool := get_pool(encounter_index)
	if pool.is_empty():
		return {"id": "", "cards": [], "ai_profile": ""}
	var deck_id: String = pool[randi() % pool.size()]
	return {"id": deck_id, "cards": get_deck(deck_id), "ai_profile": get_deck_profile(deck_id)}

## Returns all deck IDs across all pools and orphans.
static func get_all_deck_ids() -> Array[String]:
	var data := load_data()
	var decks: Dictionary = data.decks
	var ids: Array[String] = []
	for key in decks:
		ids.append(key as String)
	ids.sort()
	return ids

# ---------------------------------------------------------------------------
# Deck mutations
# ---------------------------------------------------------------------------

## Create or update a deck. Preserves ai_profile if not specified.
static func save_deck(deck_id: String, cards: Array, ai_profile: String = "") -> void:
	var data := load_data()
	var entry: Dictionary = {}
	# Preserve existing profile if not overriding
	if (data.decks as Dictionary).has(deck_id):
		var existing := _parse_deck_entry(data.decks[deck_id])
		entry["ai_profile"] = existing.ai_profile as String
	entry["cards"] = cards
	if not ai_profile.is_empty():
		entry["ai_profile"] = ai_profile
	# Omit ai_profile key entirely if empty (cleaner JSON)
	if (entry.get("ai_profile", "") as String).is_empty():
		entry.erase("ai_profile")
	data.decks[deck_id] = entry
	save_data(data)

## Set or clear the AI profile for a deck.
static func set_deck_profile(deck_id: String, ai_profile: String) -> void:
	var data := load_data()
	if not (data.decks as Dictionary).has(deck_id):
		return
	var parsed := _parse_deck_entry(data.decks[deck_id])
	var entry := {"cards": parsed.cards}
	if not ai_profile.is_empty():
		entry["ai_profile"] = ai_profile
	data.decks[deck_id] = entry
	save_data(data)

## Delete a deck entirely — removes from decks AND from all pools.
static func delete_deck(deck_id: String) -> void:
	var data := load_data()
	(data.decks as Dictionary).erase(deck_id)
	for key in data.pools:
		var pool: Array = data.pools[key] as Array
		pool.erase(deck_id)
	save_data(data)

# ---------------------------------------------------------------------------
# Pool mutations
# ---------------------------------------------------------------------------

## Add a deck to an encounter's pool (no-op if already present).
static func add_to_pool(encounter_index: int, deck_id: String) -> void:
	var data := load_data()
	var key := str(encounter_index)
	if not (data.pools as Dictionary).has(key):
		data.pools[key] = []
	var pool: Array = data.pools[key] as Array
	if deck_id not in pool:
		pool.append(deck_id)
	save_data(data)

## Remove a deck from an encounter's pool (doesn't delete the deck itself).
static func remove_from_pool(encounter_index: int, deck_id: String) -> void:
	var data := load_data()
	var key := str(encounter_index)
	if not (data.pools as Dictionary).has(key):
		return
	var pool: Array = data.pools[key] as Array
	pool.erase(deck_id)
	save_data(data)
