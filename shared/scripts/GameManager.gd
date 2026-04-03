## GameManager.gd
## Global autoload — persists across all scenes.
## Holds run state, permanent unlocks, and scene transitions.
extends Node

## Fights in each act (Acts 1–3: 3 fights, Act 4: 6 fights).
const ACT_SIZES: Array[int] = [3, 3, 3, 6]
const TOTAL_ACTS  := 4
const TOTAL_FIGHTS := 15
## 1-based indices of the boss fight in each act.
const BOSS_INDICES: Array[int] = [3, 6, 9, 15]

## Per-act-gate unlock chance (rolled once per eligible card per boss kill).
const _UNLOCK_CHANCE: Dictionary = {
	1: 0.60,
	2: 0.25,
	3: 0.20,
	4: 0.10,
}

# --- Run State ---
var run_active: bool = false
var void_shards: int = 0
var player_hp_max: int = 3000
var player_hp: int = 3000         # current HP; persists between fights
## Max copies of the core unit allowed in deck; starts at 4 for Lord Vael.
## Increased by special reward #4 (up to 6).
var core_unit_limit: int = 4
## Set by HeroSelectScene before start_new_run() — not reset by start_new_run()
var current_hero: String = "lord_vael"
## Faction chosen on HeroSelectScene; used by DeckBuilderScene to pre-filter cards
var current_faction: String = "abyss_order"

# --- Resources (in-combat, reset each combat) ---
var abyss_essence: int = 0
var abyss_essence_max: int = 1
var mana: int = 0
var mana_max: int = 1

# --- Deck & Cards ---
var player_deck: Array[String] = []   # card IDs
var player_relics: Array[String] = []          # relic IDs collected this run
var relic_bonus_charges: Dictionary = {}       # relic_id → int bonus charges from upgrades
var permanent_unlocks: Array[String] = []   # survives between runs
var last_boss_unlocks: Array[String] = []   # cards unlocked by the most recent boss kill; cleared after display

# --- Progression ---
var run_node_index: int = 1           # which encounter the player is on (1-based)
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
	run_node_index = 1
	player_relics = []
	relic_bonus_charges = {}
	abyss_essence_max = 1
	mana_max = 1
	player_hp_max = 3000
	player_hp = player_hp_max
	core_unit_limit = 4
	current_enemy = get_encounter(1)
	talent_points = 1       # initial point — spend before first fight
	unlocked_talents = []
	deck_built = false
	void_shards = 0

func end_run(_victory: bool) -> void:
	# Boss drops are granted in advance_node() when the act boss is detected,
	# so nothing extra is needed here for the final boss.
	run_active = false
	current_enemy = null
	UserProfile.clear_run()  # wipes run from save, keeps permanent_unlocks

func earn_shards(amount: int) -> void:
	void_shards += amount

func spend_shards(amount: int) -> bool:
	if void_shards < amount:
		return false
	void_shards -= amount
	return true

func advance_node() -> void:
	# Detect act boss BEFORE incrementing (boss indices: 3, 6, 9, 15).
	var act_boss_completed: bool = run_node_index in BOSS_INDICES
	var completed_act: int       = _act_for_index(run_node_index)

	run_node_index += 1
	if run_node_index <= TOTAL_FIGHTS:
		current_enemy = get_encounter(run_node_index)

	if act_boss_completed:
		grant_boss_unlocks(completed_act)

func is_run_complete() -> bool:
	return run_node_index > TOTAL_FIGHTS

## True when the player has just finished the last fight of an act.
## Call AFTER advance_node() — checks if run_node_index sits on an act boundary (4, 7, 10, 16).
func is_act_complete() -> bool:
	var boundary := 1
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
	return run_node_index == TOTAL_FIGHTS

## Maps a 1-based fight index to its act number (1-based).
func _act_for_index(index: int) -> int:
	var cumulative := 0
	for i in ACT_SIZES.size():
		cumulative += ACT_SIZES[i]
		if index <= cumulative:
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
	# Gather all support pool cards relevant to the current hero + talents.
	var candidates: Array[String] = []
	if current_hero == "lord_vael":
		candidates.append_array(CardDatabase.get_card_ids_in_pools(["vael_common"]))
	if has_talent("piercing_void"):
		candidates.append_array(CardDatabase.get_card_ids_in_pools(["vael_piercing_void"]))
	if has_talent("imp_evolution"):
		candidates.append_array(CardDatabase.get_card_ids_in_pools(["vael_endless_tide"]))
	if has_talent("rune_caller"):
		candidates.append_array(CardDatabase.get_card_ids_in_pools(["vael_rune_master"]))
	# Future support pools (other heroes / talents) appended here.

	# Roll each candidate whose act_gate <= current act and not yet unlocked.
	last_boss_unlocks.clear()
	for card_id in candidates:
		if card_id in permanent_unlocks:
			continue  # already unlocked
		var card := CardDatabase.get_card(card_id)
		if not card or card.act_gate == 0 or card.act_gate > act_number:
			continue
		var chance: float = _UNLOCK_CHANCE.get(card.act_gate, 0.0)
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
	var e: EnemyData = _build_encounter(index)
	if e == null:
		return null
	var key := "encounter_%d" % index
	var saved := EnemySavedDecks.load_all()
	if saved.has(key):
		var custom: Array[String] = []
		for id in (saved[key] as Array):
			custom.append(id as String)
		e.deck = custom
	return e

## Returns the default (non-overridden) deck for an encounter.
## Used by EnemyDeckBuilder to load vanilla decks for editing.
func get_default_encounter_deck(index: int) -> Array[String]:
	var e: EnemyData = _build_encounter(index)
	if e == null:
		return []
	return e.deck

func _build_encounter(index: int) -> EnemyData:
	match index:
		# -- Act 1: Imp Lair --
		1:
			return _make_encounter("Rogue Imp Pack", 1800,
				["rabid_imp", "rabid_imp", "rabid_imp", "rabid_imp",
				"brood_imp", "brood_imp", "brood_imp",
				"imp_brawler", "imp_brawler", "imp_brawler",
				"feral_surge", "feral_surge",
				"void_screech", "void_screech"],
				"ENCOUNTER I",
				"The outer tunnels of the Imp Lair crawl with feral Void Imps freshly escaped from their cages. They are wild, disorganised — but their numbers are not to be underestimated.",
				"res://assets/art/progression/backgrounds/a1_fight1_background.png",
				["feral_instinct", "pack_instinct"], "feral_pack")
		2:
			return _make_encounter("Corrupted Broodlings", 2400,
				["brood_imp", "brood_imp",
				"void_touched_imp", "void_touched_imp", "void_touched_imp", "void_touched_imp",
				"rabid_imp", "rabid_imp", "rabid_imp", "rabid_imp",
				"void_screech",
				"pack_frenzy", "pack_frenzy"],
				"ENCOUNTER II",
				"Deeper in, the air turns thick with void energy. The broodlings here have been touched by something ancient — their eyes glow with a hunger that wasn't there before.",
				"res://assets/art/progression/backgrounds/a1_fight2_background.png",
				["feral_instinct", "corrupted_death"], "corrupted_brood")
		3:
			return _make_encounter("Imp Matriarch", 3000,
				# Combo boss: flood board with cheap imps, then swing with Pack Frenzy.
				# Ancient Frenzy drops Pack Frenzy to 2M; Rogue Imp Elder makes the
				# +250 ATK buff land at +350 effective ATK. Turn 5 is the danger window.
				[
					"rabid_imp",      "rabid_imp",      "rabid_imp",
					"brood_imp",      "brood_imp",
					"imp_brawler",    "imp_brawler",
					"void_touched_imp",
					"rogue_imp_elder",
					"matriarchs_broodling",
					"pack_frenzy",    "pack_frenzy",
					"feral_surge",
					"void_screech",
					"brood_call",
				],
				"IMP MATRIARCH",
				"At the heart of the lair, a monstrous Imp Matriarch holds court. She is the source of the corruption — ancient, cunning, and furious at the intrusion into her domain.",
				"res://assets/art/progression/backgrounds/a1_fight3_background.png",
				["feral_instinct", "ancient_frenzy"], "matriarch")
		# -- Act 2: Abyss Dungeon --
		4:
			return _make_encounter("Abyss Cultist Patrol", 2800,
				[
					"abyss_cultist", "abyss_cultist", "abyss_cultist", "abyss_cultist",
					"void_netter",
					"void_stalker",
					"corruption_weaver", "corruption_weaver",
					"cult_fanatic", "cult_fanatic",
					"void_stalker",
					"spell_taxer", "spell_taxer",
					"dark_command", "dark_command",
				],
				"ENCOUNTER I",
				"The Abyss Dungeon. Cultists who willingly surrendered themselves to the void patrol these stone corridors. They have given up their names, their faces — only devotion remains.",
				"res://assets/art/progression/backgrounds/fight4_loading.png",
				["feral_reinforcement", "corrupt_authority"], "cultist_patrol")
		5:
			return _make_encounter("Void Ritualist", 3400,
				[
					"abyss_cultist", "abyss_cultist", "abyss_cultist",
					"cult_fanatic", "cult_fanatic", "cult_fanatic",
					"corruption_weaver", "corruption_weaver",
					"void_stalker",
					"dominion_rune", "dominion_rune",
					"blood_rune", "blood_rune",
					"dark_command", "dark_command",
				],
				"ENCOUNTER II",
				"A Void Ritualist performs an unending ceremony in the dungeon's depths. Runes of blood and shadow cover every wall. Whatever he is summoning, it must not be allowed to complete.",
				"res://assets/art/progression/backgrounds/fight5_loading.png",
				["feral_reinforcement", "ritual_sacrifice"], "void_ritualist")
		6:
			return _make_encounter("Corrupted Handler", 4000,
				[
					"abyss_cultist", "abyss_cultist", "abyss_cultist",
					"cult_fanatic", "cult_fanatic", "cult_fanatic",
					"corruption_weaver", "corruption_weaver",
					"soul_collector",
					"void_stalker", "void_stalker",
					"spell_taxer",
					"dark_command", "dark_command",
				],
				"CORRUPTED HANDLER",
				"The Handler was once a warden of this dungeon. Now something else wears his shape. His eyes are empty voids. His commands come in a language that shouldn't exist.",
				"res://assets/art/progression/backgrounds/fight6_loading.png",
				["feral_reinforcement", "void_unraveling"], "corrupted_handler")
		# -- Act 3: Void Rift World --
		7:
			return _make_encounter("Rift Stalker", 3800,
				[
					"void_pulse", "void_pulse",
					"phase_stalker", "phase_stalker",
					"rift_collapse",
					"void_behemoth",
					"abyssal_brute", "abyssal_brute",
					"void_stalker", "void_stalker",
					"void_bolt", "void_bolt",
					"abyssal_plague",
				],
				"ENCOUNTER I",
				"The Void Rift World — a place where reality has frayed. Rift Stalkers phase between dimensions, attacking from angles that shouldn't exist. Stay focused. Don't let it disorient you.",
				"res://assets/art/progression/backgrounds/fight7_loading.png",
				["void_rift", "void_empowerment"], "rift_stalker")
		8:
			return _make_encounter("Void Aberration", 4600,
				[
					"void_pulse", "void_pulse", "void_pulse",
					"rift_collapse", "rift_collapse",
					"dimensional_breach", "dimensional_breach",
					"phase_stalker",
					"void_behemoth",
					"abyssal_brute", "abyssal_brute",
					"void_bolt", "void_bolt",
					"abyssal_plague",
				],
				"ENCOUNTER II",
				"A Void Aberration — a creature that should not exist in any plane. It was assembled from the broken remnants of things consumed by the rift. It has no purpose except destruction.",
				"res://assets/art/progression/backgrounds/fight8_loading.png",
				["void_rift", "void_detonation_passive"], "void_aberration")
		9:
			return _make_encounter("Void Herald", 6500,
				[
					"void_pulse", "void_pulse",
					"phase_stalker", "phase_stalker",
					"rift_collapse", "rift_collapse",
					"void_behemoth", "void_behemoth",
					"dimensional_breach", "dimensional_breach",
					"void_rift_lord", "void_rift_lord",
					"abyssal_brute",
					"void_bolt",
					"abyssal_plague",
				],
				"VOID HERALD",
				"The Void Herald speaks with the voice of the Abyss itself. It has crossed countless worlds before this one. It carries a message: the Abyss Sovereign is coming, and nothing will remain.",
				"res://assets/art/progression/backgrounds/fight9_loading.png",
				["void_rift", "void_mastery"], "void_herald")
		# -- Act 4: Void Castle --
		10:
			return _make_encounter("Void Scout", 5000,
				["abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "abyssal_plague"],
				"ENCOUNTER I",
				"The Void Castle looms at the edge of existence. Void Scouts patrol its outer walls — swift, precise, and utterly loyal. The Sovereign's inner sanctum is somewhere beyond.",
				"res://assets/art/progression/backgrounds/a1_combat_background.png")
		11:
			return _make_encounter("Void Warband", 5600,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "abyssal_plague"],
				"ENCOUNTER II",
				"A full Void Warband stands between you and the castle's keep. These are the Sovereign's chosen soldiers — hardened by centuries of conquest across dying worlds.",
				"res://assets/art/progression/backgrounds/a1_combat_background.png")
		12:
			return _make_encounter("Void Captain", 6200,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "abyssal_plague", "abyssal_plague"],
				"VOID CAPTAIN",
				"The Void Captain commands the castle's garrison. A veteran of a hundred conquests, she has never known defeat. She regards you with curiosity — a new species of prey.",
				"res://assets/art/progression/backgrounds/a1_combat_background.png")
		13:
			return _make_encounter("Void Ritualist Prime", 7000,
				["abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "void_bolt", "abyssal_plague", "abyssal_plague"],
				"ENCOUNTER IV",
				"The Ritualist Prime is the Sovereign's high priest. He has spent his eternal life weaving void energy into a prison for the soul. He will try to do the same to you.",
				"res://assets/art/progression/backgrounds/a1_combat_background.png")
		14:
			return _make_encounter("Void Champion", 7800,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "void_bolt", "abyssal_plague", "abyssal_plague"],
				"VOID CHAMPION",
				"The last guardian before the throne. The Void Champion was forged from pure abyss energy — no flesh, no weakness, no mercy. Beyond him, the Sovereign waits.",
				"res://assets/art/progression/backgrounds/a1_combat_background.png")
		15:
			return _make_encounter("Abyss Sovereign", 10000,
				["abyssal_brute", "abyssal_brute", "abyssal_brute", "abyssal_brute", "void_bolt", "void_bolt", "void_bolt", "abyssal_plague", "abyssal_plague"],
				"ABYSS SOVEREIGN",
				"At last. The Abyss Sovereign — the source of all corruption, the end of all things. It has devoured worlds without count. Today, it faces something it has never encountered: defiance.",
				"res://assets/art/progression/backgrounds/a1_combat_background.png")
	return null

func _make_encounter(ename: String, ehp: int, pool: Array[String],
		etitle: String = "", estory: String = "", ebg: String = "",
		epassives: Array[String] = [], eai_profile: String = "default") -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = ename
	e.hp = ehp
	e.deck = pool
	e.title = etitle
	e.story = estory
	e.passives = epassives
	e.ai_profile = eai_profile
	if ebg != "":
		e.background_path = ebg
	return e

