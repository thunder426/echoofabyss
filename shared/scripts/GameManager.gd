## GameManager.gd
## Global autoload — persists across all scenes.
## Holds run state, permanent unlocks, and scene transitions.
extends Node

## Fights in each act (Acts 1–3: 3 fights, Act 4: 6 fights).
const ACT_SIZES: Array[int] = [3, 3, 3, 6]
const TOTAL_ACTS  := 4
const TOTAL_FIGHTS := 15
## 0-based indices of the boss fight in each act.
const BOSS_INDICES: Array[int] = [2, 5, 8, 14]

# ---------------------------------------------------------------------------
# Support pool rarity table — used for boss drop rolls.
# Keys match card IDs in CardDatabase. Only cards that can be permanently
# unlocked need an entry here.
# ---------------------------------------------------------------------------
const _SUPPORT_CARD_RARITIES: Dictionary = {
	# Piercing Void pool (Lord Vael)
	"mark_the_target":            "common",
	"imp_combustion":             "common",
	"dark_ritual_of_the_abyss":   "common",
	"imp_overload":               "common",
	"void_channeler":             "rare",
	"abyssal_sacrificer":         "rare",
	"abyssal_arcanist":           "rare",
	"void_detonation":            "rare",
	"soul_rupture":               "rare",
	"void_bolt_rain":             "epic",
	"mark_convergence":           "epic",
	"mark_collapse":              "epic",
	"void_archmagus":             "legendary",
	# Common Imp Support Pool (Lord Vael, no talent requirement)
	"abyssal_conjuring":          "common",
	"void_breach":                "common",
	"abyss_recruiter":            "common",
	"dark_nursery":               "common",
	"call_the_swarm":             "rare",
	"imp_handler":                "rare",
	"imp_barricade":              "rare",
	"abyssal_taskmaster":         "epic",
	"imp_hatchery":               "epic",
	"imp_overseer":               "legendary",
}

## Per-rarity unlock chance (rolled once per eligible card per boss kill).
const _UNLOCK_CHANCE: Dictionary = {
	"common":    0.60,
	"rare":      0.25,
	"epic":      0.20,
	"legendary": 0.10,
}

# --- Run State ---
var run_active: bool = false
var player_hp_max: int = 3000
var player_hp: int = 3000         # current HP; persists between fights
## Max copies of the core unit allowed in deck; starts at 4 for Lord Vael.
## Increased by special reward #4 (up to 6).
var core_unit_limit: int = 4
## Set by HeroSelectScene before start_new_run() — not reset by start_new_run()
var current_hero: String = "lord_vael"

# --- Resources (in-combat, reset each combat) ---
var abyss_essence: int = 0
var abyss_essence_max: int = 1
var mana: int = 0
var mana_max: int = 1

# --- Deck & Cards ---
var player_deck: Array[String] = []   # card IDs
var player_relics: Array[String] = [] # relic IDs collected this run
var permanent_unlocks: Array[String] = []   # survives between runs
var last_boss_unlocks: Array[String] = []   # cards unlocked by the most recent boss kill; cleared after display

# --- Progression ---
var run_node_index: int = 0           # which encounter the player is on (0-based)
var current_enemy: EnemyData = null   # set before entering CombatScene

# --- Talents ---
var talent_points: int = 0
var unlocked_talents: Array[String] = []

## False until DeckBuilderScene finalises the deck — used by TalentSelectScene to know where to route
var deck_built: bool = false

# ---------------------------------------------------------------------------
# Scene Management
# ---------------------------------------------------------------------------

func go_to_scene(path: String) -> void:
	UserProfile.save()
	get_tree().change_scene_to_file(path)

# ---------------------------------------------------------------------------
# Run Management
# ---------------------------------------------------------------------------

func start_new_run() -> void:
	run_active = true
	run_node_index = 0
	player_relics = []
	abyss_essence_max = 1
	mana_max = 1
	player_hp_max = 3000
	player_hp = player_hp_max
	core_unit_limit = 4
	player_deck = _build_starter_deck()
	current_enemy = get_encounter(0)
	talent_points = 1       # initial point — spend before first fight
	unlocked_talents = []
	deck_built = false

func end_run(_victory: bool) -> void:
	# Boss drops are granted in advance_node() when the act boss is detected,
	# so nothing extra is needed here for the final boss.
	run_active = false
	current_enemy = null
	UserProfile.clear_run()  # wipes run from save, keeps permanent_unlocks

func advance_node() -> void:
	# Detect act boss BEFORE incrementing (boss indices: 2, 5, 8, 14).
	var act_boss_completed: bool = run_node_index in BOSS_INDICES
	var completed_act: int       = _act_for_index(run_node_index)

	run_node_index += 1
	if run_node_index < TOTAL_FIGHTS:
		current_enemy = get_encounter(run_node_index)

	if act_boss_completed:
		grant_boss_unlocks(completed_act)

func is_run_complete() -> bool:
	return run_node_index >= TOTAL_FIGHTS

## True when the player has just finished the last fight of an act.
## Call AFTER advance_node() — checks if run_node_index sits on an act boundary (3, 6, 9, 15).
func is_act_complete() -> bool:
	var boundary := 0
	for size in ACT_SIZES:
		boundary += size
		if run_node_index == boundary:
			return true
	return false

## Which act (1-based) the player is currently in.
func get_current_act() -> int:
	return _act_for_index(run_node_index)

## Which act (1-based) was just completed (call after advance_node + is_act_complete check).
func get_completed_act() -> int:
	return _act_for_index(run_node_index - 1)

## True when the current encounter is the final boss.
func is_boss_fight() -> bool:
	return run_node_index == TOTAL_FIGHTS - 1

## Maps a 0-based fight index to its act number (1-based).
func _act_for_index(index: int) -> int:
	var cumulative := 0
	for i in ACT_SIZES.size():
		cumulative += ACT_SIZES[i]
		if index < cumulative:
			return i + 1
	return ACT_SIZES.size()

# ---------------------------------------------------------------------------
# Boss Drop / Permanent Unlock System
# ---------------------------------------------------------------------------

## Roll permanent unlocks from all support pools relevant to the current run.
## act_number: 1–4 matching the act whose boss was just defeated.
## Eligible rarities scale with act: Act 1 → common only;
##   Act 2 → common + rare; Acts 3 & 4 → all rarities.
func grant_boss_unlocks(act_number: int) -> void:
	# Build the eligible rarity set for this act.
	var eligible: Array[String] = ["common"]
	if act_number >= 2:
		eligible.append("rare")
	if act_number >= 3:
		eligible.append("epic")
		eligible.append("legendary")

	# Gather all support pool cards relevant to the current hero + talents.
	var candidates: Array[String] = []
	if current_hero == "lord_vael":
		# Common Imp Support Pool is always available for Lord Vael
		for id in ["abyssal_conjuring", "void_breach", "abyss_recruiter", "dark_nursery",
				"call_the_swarm", "imp_handler", "imp_barricade",
				"abyssal_taskmaster", "imp_hatchery", "imp_overseer"]:
			candidates.append(id)
	if has_talent("piercing_void"):
		for id in ["mark_the_target", "imp_combustion", "dark_ritual_of_the_abyss", "imp_overload",
				"void_channeler", "abyssal_sacrificer", "abyssal_arcanist",
				"void_detonation", "soul_rupture", "void_bolt_rain", "mark_convergence",
				"mark_collapse", "void_archmagus"]:
			candidates.append(id)
	# Future support pools (other heroes / talents) appended here.

	# Roll each candidate that is eligible and not yet unlocked.
	last_boss_unlocks.clear()
	for card_id in candidates:
		if card_id in permanent_unlocks:
			continue  # already unlocked
		var rarity: String = _SUPPORT_CARD_RARITIES.get(card_id, "")
		if rarity not in eligible:
			continue
		var chance: float = _UNLOCK_CHANCE.get(rarity, 0.0)
		if randf() < chance:
			permanent_unlocks.append(card_id)
			last_boss_unlocks.append(card_id)

# ---------------------------------------------------------------------------
# Talent Management
# ---------------------------------------------------------------------------

func add_talent_point(amount: int = 1) -> void:
	talent_points += amount

func unlock_talent(id: String) -> void:
	if talent_points <= 0:
		push_error("GameManager: no talent points to spend")
		return
	if id in unlocked_talents:
		push_error("GameManager: talent '%s' already unlocked" % id)
		return
	unlocked_talents.append(id)
	talent_points -= 1

func has_talent(id: String) -> bool:
	return id in unlocked_talents

## Extra mana cost applied to a card by active talents.
## Used by CombatScene (play validation) and HandDisplay (affordability highlight).
func get_talent_mana_modifier(card: CardData) -> int:
	var extra := 0
	if card is MinionCardData and card.id == "void_imp" and has_talent("piercing_void"):
		extra += 1
	return extra

# ---------------------------------------------------------------------------
# Encounter Definitions — 4 acts (3 + 3 + 3 + 6 = 15 fights)
# Card pools and HP are placeholders; unique AI will be designed per-encounter later.
# ---------------------------------------------------------------------------

func get_encounter(index: int) -> EnemyData:
	match index:
		# -- Act 1: Imp Lair --
		0:  # Enemy
			return _make_encounter("Rogue Imp Pack", 1800,
				["void_imp", "void_imp", "void_imp", "shadow_hound", "shadow_hound"])
		1:  # Enemy
			return _make_encounter("Corrupted Broodlings", 2200,
				["void_imp", "void_imp", "void_imp", "shadow_hound", "shadow_hound", "void_bolt"])
		2:  # Boss
			return _make_encounter("Imp Matriarch", 3000,
				["void_imp", "void_imp", "shadow_hound", "shadow_hound", "abyssal_brute", "void_bolt"])
		# -- Act 2: Abyss Dungeon --
		3:  # Enemy
			return _make_encounter("Abyss Cultist Patrol", 3200,
				["shadow_hound", "shadow_hound", "abyssal_brute", "abyssal_brute", "void_bolt"])
		4:  # Enemy
			return _make_encounter("Void Ritualist", 3600,
				["shadow_hound", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "abyssal_plague"])
		5:  # Boss
			return _make_encounter("Corrupted Handler", 4400,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "abyssal_plague"])
		# -- Act 3: Void Rift World --
		6:  # Enemy
			return _make_encounter("Rift Stalker", 4200,
				["abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "abyssal_plague"])
		7:  # Enemy
			return _make_encounter("Void Aberration", 4800,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "abyssal_plague", "abyssal_plague"])
		8:  # Boss
			return _make_encounter("Void Herald", 6000,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "abyssal_plague", "abyssal_plague"])
		# -- Act 4: Void Castle --
		9:  # Enemy
			return _make_encounter("Void Scout", 5000,
				["abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "abyssal_plague"])
		10:  # Enemy
			return _make_encounter("Void Warband", 5500,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "abyssal_plague"])
		11:  # Elite
			return _make_encounter("Void Captain", 6200,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "abyssal_plague", "abyssal_plague"])
		12:  # Enemy
			return _make_encounter("Void Ritualist Prime", 6000,
				["abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "void_bolt", "abyssal_plague", "abyssal_plague"])
		13:  # Elite
			return _make_encounter("Void Champion", 7000,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "void_bolt", "abyssal_plague", "abyssal_plague"])
		14:  # Final Boss
			return _make_encounter("Abyss Sovereign", 10000,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "void_bolt", "abyssal_plague", "abyssal_plague"])
	return null

func _make_encounter(ename: String, ehp: int, pool: Array[String]) -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = ename
	e.hp = ehp
	e.deck = pool
	return e

func _build_starter_deck() -> Array[String]:
	var hero := HeroDatabase.get_hero(current_hero)
	if hero == null:
		push_error("GameManager: no HeroData for '%s', using empty deck" % current_hero)
		return []
	return hero.starter_deck.duplicate()
