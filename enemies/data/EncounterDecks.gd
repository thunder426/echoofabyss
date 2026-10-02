## EncounterDecks.gd
## Unified enemy deck database.  Stores named decks and per-encounter pools
## (which deck IDs are available for each fight).  One deck is picked from the
## pool per fight, from the run seed (pick_for_run).
##
## The data is `res://enemies/data/encounter_decks.json`, committed to the repo
## and the only source (task 047). debug/EnemyDeckBuilder edits it in place,
## which works in editor runs only: res:// is read-only in an export.
##
##   {
##     "pools": { "1": ["f1_a", "f1_b"], "2": ["f2_a"] },
##     "decks": {
##       "f1_a": { "cards": ["card_id", ...] },
##       "f1_b": { "cards": [...], "ai_profile": "feral_pack_screech" },
##       "f8_a": { "cards": [...], "limited": ["void_wind"] }
##     }
##   }
##
## Each deck is an object with:
##   - "cards": Array of card IDs (required)
##   - "ai_profile": String (optional) — overrides the encounter's default AI profile
##   - "limited": Array of card IDs (optional) — drawn once, not re-added
##
## All decks are equal — no "default vs custom" distinction.
class_name EncounterDecks
extends RefCounted

const DATA_PATH := "res://enemies/data/encounter_decks.json"

## The parsed file, read once per process; save_data replaces it.
static var _cache: Dictionary = {}

# ---------------------------------------------------------------------------
# Load / Save
# ---------------------------------------------------------------------------

## The parsed deck file. A missing or broken file is an error, not an empty
## database: every fight would silently play the fallback deck (live) or be
## skipped (sim). Callers must not mutate the result — mutators work on a copy.
static func load_data() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	_cache = _read_file()
	return _cache

static func _read_file() -> Dictionary:
	var empty := {"pools": {}, "decks": {}}
	if not FileAccess.file_exists(DATA_PATH):
		push_error("EncounterDecks: %s is missing" % DATA_PATH)
		return empty
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("EncounterDecks: can't open %s (%s)" % [DATA_PATH, error_string(FileAccess.get_open_error())])
		return empty
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		push_error("EncounterDecks: %s line %d: %s" % [DATA_PATH, json.get_error_line(), json.get_error_message()])
		return empty
	var data: Variant = json.get_data()
	if not data is Dictionary:
		push_error("EncounterDecks: %s is not a JSON object" % DATA_PATH)
		return empty
	var d := data as Dictionary
	if not d.has("pools"):
		d["pools"] = {}
	if not d.has("decks"):
		d["decks"] = {}
	return d

## Writes `data` to the repo file (editor runs only). Unsorted keys keep the
## file's layout, so an edit diffs as the entries it touched.
static func save_data(data: Dictionary) -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if f == null:
		push_error("EncounterDecks: can't write %s (%s)" % [DATA_PATH, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data, "\t", false) + "\n")
	_cache = data

## A deep copy of the data for a mutator to edit and pass to save_data.
static func _load_for_edit() -> Dictionary:
	return load_data().duplicate(true)

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

## A deck entry with these `cards` and `ai_profile` ("" = none), keeping the
## other fields of `existing` (its `limited` list).
static func _entry_with(existing: Variant, cards: Array, ai_profile: String) -> Dictionary:
	var entry: Dictionary = {"cards": cards}
	if not ai_profile.is_empty():
		entry["ai_profile"] = ai_profile
	var limited: Array = _parse_deck_entry(existing).limited as Array
	if not limited.is_empty():
		entry["limited"] = limited
	return entry

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

## The deck for encounter `encounter_index` in the run seeded `run_seed`:
## {"id", "cards", "ai_profile"}. Stateless, so a run gets the same deck for a
## fight however often it asks (CheatPanel lists all 15), and nothing draws
## from the global RNG.
static func pick_for_run(encounter_index: int, run_seed: int) -> Dictionary:
	var pool := get_pool(encounter_index)
	if pool.is_empty():
		return {"id": "", "cards": [], "ai_profile": ""}
	var deck_id: String = pool[posmod(hash([run_seed, encounter_index]), pool.size())]
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

## Create or update a deck. Keeps its ai_profile if none is given, and its
## limited list.
static func save_deck(deck_id: String, cards: Array, ai_profile: String = "") -> void:
	var data := _load_for_edit()
	var existing: Variant = (data.decks as Dictionary).get(deck_id)
	var profile: String = ai_profile
	if profile.is_empty():
		profile = _parse_deck_entry(existing).ai_profile as String
	data.decks[deck_id] = _entry_with(existing, cards, profile)
	save_data(data)

## Set or clear the AI profile for a deck.
static func set_deck_profile(deck_id: String, ai_profile: String) -> void:
	var data := _load_for_edit()
	if not (data.decks as Dictionary).has(deck_id):
		return
	var existing: Variant = data.decks[deck_id]
	data.decks[deck_id] = _entry_with(existing, _parse_deck_entry(existing).cards as Array, ai_profile)
	save_data(data)

## Delete a deck entirely — removes from decks AND from all pools.
static func delete_deck(deck_id: String) -> void:
	var data := _load_for_edit()
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
	var data := _load_for_edit()
	var key := str(encounter_index)
	if not (data.pools as Dictionary).has(key):
		data.pools[key] = []
	var pool: Array = data.pools[key] as Array
	if deck_id not in pool:
		pool.append(deck_id)
	save_data(data)

## Remove a deck from an encounter's pool (doesn't delete the deck itself).
static func remove_from_pool(encounter_index: int, deck_id: String) -> void:
	var data := _load_for_edit()
	var key := str(encounter_index)
	if not (data.pools as Dictionary).has(key):
		return
	var pool: Array = data.pools[key] as Array
	pool.erase(deck_id)
	save_data(data)
