## EncounterTable.gd
## The 15 encounters as data (LIVE_SIM_UNIFICATION_PLAN.md 2A.7) — the one
## source for enemy HP, passives, default AI profile and story text. Live's
## GameManager builds EnemyData from it; the sim's CombatSim, BalanceSim and
## ScoredAITest read HP and passives from it. Enemy decks (and per-deck profile
## overrides) come from EncounterDecks.
class_name EncounterTable
extends RefCounted

## "variant_profiles": other AI profiles that play this encounter (deck variants
## in EncounterDecks, scored* test profiles) — they share its passives.
const ENCOUNTERS: Array = [
	{
		"index": 1, "name": "Rogue Imp Pack", "hp": 1800, "ai_profile": "feral_pack",
		"variant_profiles": ["feral_pack_screech", "scored_feral_pack"],
		"passives": ["pack_instinct", "champion_rogue_imp_pack"],
		"title": "ENCOUNTER I",
		"story": "The outer tunnels of the Imp Lair crawl with feral Void Imps freshly escaped from their cages. They are wild, disorganised — but their numbers are not to be underestimated.",
		"background": "res://assets/art/progression/backgrounds/a1_fight1_background.png",
		"portrait": "res://assets/art/enemies/portraits/rogue_imp_pack_portrait.png",
	},
	{
		"index": 2, "name": "Corrupted Broodlings", "hp": 2100, "ai_profile": "corrupted_brood",
		"variant_profiles": ["corrupted_brood_aggro", "corrupted_brood_rune", "scored_corrupted_brood"],
		"passives": ["corrupted_death", "champion_corrupted_broodlings"],
		"title": "ENCOUNTER II",
		"story": "Deeper in, the air turns thick with void energy. The broodlings here have been touched by something ancient — their eyes glow with a hunger that wasn't there before.",
		"background": "res://assets/art/progression/backgrounds/a1_fight2_background.png",
		"portrait": "res://assets/art/enemies/portraits/corrupted_broodlings_portrait.png",
	},
	{
		"index": 3, "name": "Imp Matriarch", "hp": 2200, "ai_profile": "matriarch",
		"variant_profiles": ["matriarch_aggro", "matriarch_sac", "scored_matriarch"],
		"passives": ["ancient_frenzy", "champion_imp_matriarch"],
		"title": "IMP MATRIARCH",
		"story": "At the heart of the lair, a monstrous Imp Matriarch holds court. She is the source of the corruption — ancient, cunning, and furious at the intrusion into her domain.",
		"background": "res://assets/art/progression/backgrounds/a1_fight3_background.png",
		"portrait": "res://assets/art/enemies/portraits/imp_matriarch_portrait.png",
	},
	{
		"index": 4, "name": "Abyss Cultist Patrol", "hp": 2800, "ai_profile": "cultist_patrol",
		"variant_profiles": ["cultist_patrol_tempo"],
		"passives": ["feral_reinforcement", "corrupt_authority", "champion_abyss_cultist_patrol"],
		"title": "ENCOUNTER I",
		"story": "The Abyss Dungeon. Cultists who willingly surrendered themselves to the void patrol these stone corridors. They have given up their names, their faces — only devotion remains.",
		"background": "res://assets/art/progression/backgrounds/fight4_loading.png",
		"portrait": "res://assets/art/enemies/portraits/abyss_cultist_patrol_portrait.png",
	},
	{
		"index": 5, "name": "Void Ritualist", "hp": 3400, "ai_profile": "void_ritualist",
		"variant_profiles": [],
		"passives": ["feral_reinforcement", "ritual_sacrifice", "champion_void_ritualist"],
		"title": "ENCOUNTER II",
		"story": "A Void Ritualist performs an unending ceremony in the dungeon's depths. Runes of blood and shadow cover every wall. Whatever he is summoning, it must not be allowed to complete.",
		"background": "res://assets/art/progression/backgrounds/fight5_loading.png",
		"portrait": "res://assets/art/enemies/portraits/void_ritualist_portrait.png",
	},
	{
		"index": 6, "name": "Corrupted Handler", "hp": 4000, "ai_profile": "corrupted_handler",
		"variant_profiles": [],
		"passives": ["feral_reinforcement", "void_unraveling", "champion_corrupted_handler"],
		"title": "CORRUPTED HANDLER",
		"story": "The Handler was once a warden of this dungeon. Now something else wears his shape. His eyes are empty voids. His commands come in a language that shouldn't exist.",
		"background": "res://assets/art/progression/backgrounds/fight6_loading.png",
		"portrait": "res://assets/art/enemies/portraits/corrupted_handler_portrait.png",
	},
	{
		"index": 7, "name": "Rift Stalker", "hp": 3000, "ai_profile": "rift_stalker",
		"variant_profiles": [],
		"passives": ["void_rift", "void_empowerment", "champion_rift_stalker"],
		"title": "ENCOUNTER I",
		"story": "The Void Rift World — a place where reality has frayed. Rift Stalkers phase between dimensions, attacking from angles that shouldn't exist. Stay focused. Don't let it disorient you.",
		"background": "res://assets/art/progression/backgrounds/fight7_loading.png",
		"portrait": "res://assets/art/enemies/portraits/rift_stalker_portrait.png",
	},
	{
		"index": 8, "name": "Void Aberration", "hp": 3400, "ai_profile": "void_aberration",
		"variant_profiles": [],
		"passives": ["void_rift", "void_detonation_passive", "champion_void_aberration"],
		"title": "ENCOUNTER II",
		"story": "A Void Aberration — a creature that should not exist in any plane. It was assembled from the broken remnants of things consumed by the rift. It has no purpose except destruction.",
		"background": "res://assets/art/progression/backgrounds/fight8_loading.png",
		"portrait": "res://assets/art/enemies/portraits/void_aberration_portrait.png",
	},
	{
		"index": 9, "name": "Void Herald", "hp": 4000, "ai_profile": "void_herald",
		"variant_profiles": [],
		"passives": ["void_rift", "void_mastery", "champion_void_herald"],
		"title": "VOID HERALD",
		"story": "The Void Herald speaks with the voice of the Abyss itself. It has crossed countless worlds before this one. It carries a message: the Abyss Sovereign is coming, and nothing will remain.",
		"background": "res://assets/art/progression/backgrounds/fight9_loading.png",
		"portrait": "res://assets/art/enemies/portraits/void_herald_portrait.png",
	},
	{
		"index": 10, "name": "Void Scout", "hp": 5000, "ai_profile": "void_scout",
		"variant_profiles": [],
		"passives": ["void_might", "void_precision", "champion_void_scout"],
		"title": "ENCOUNTER I",
		"story": "The Void Castle looms at the edge of existence. Void Scouts patrol its outer walls — swift, precise, and utterly loyal. The Sovereign's inner sanctum is somewhere beyond.",
		"background": "res://assets/art/progression/backgrounds/a1_combat_background.png",
		"portrait": "res://assets/art/enemies/portraits/void_scout_portrait.png",
	},
	{
		"index": 11, "name": "Void Warband", "hp": 5000, "ai_profile": "void_warband",
		"variant_profiles": [],
		"passives": ["void_might", "spirit_resonance", "champion_void_warband"],
		"title": "ENCOUNTER II",
		"story": "A full Void Warband stands between you and the castle's keep. These are the Sovereign's chosen soldiers — hardened by centuries of conquest across dying worlds.",
		"background": "res://assets/art/progression/backgrounds/a1_combat_background.png",
		"portrait": "res://assets/art/enemies/portraits/void_warband_portrait.png",
	},
	{
		"index": 12, "name": "Void Captain", "hp": 5000, "ai_profile": "void_captain",
		"variant_profiles": [],
		"passives": ["void_might", "captain_orders", "champion_void_captain"],
		"title": "VOID CAPTAIN",
		"story": "The Void Captain commands the castle's garrison. A veteran of a hundred conquests, she has never known defeat. She regards you with curiosity — a new species of prey.",
		"background": "res://assets/art/progression/backgrounds/a1_combat_background.png",
		"portrait": "res://assets/art/enemies/portraits/void_captain_portrait.png",
	},
	{
		"index": 13, "name": "Void Ritualist Prime", "hp": 5000, "ai_profile": "void_ritualist_prime",
		"variant_profiles": [],
		"passives": ["void_might", "dark_channeling", "ritualist_spark_free", "champion_void_ritualist_prime"],
		"title": "VOID RITUALIST PRIME",
		"story": "The Ritualist Prime is the Sovereign's high priest. He has spent his eternal life weaving void energy into a prison for the soul. He will try to do the same to you.",
		"background": "res://assets/art/progression/backgrounds/a1_combat_background.png",
		"portrait": "res://assets/art/enemies/portraits/void_ritualist_prime_portrait.png",
	},
	{
		"index": 14, "name": "Void Champion", "hp": 5000, "ai_profile": "void_champion",
		"variant_profiles": [],
		"passives": ["void_might", "mana_for_spark", "champion_void_champion"],
		"title": "VOID CHAMPION",
		"story": "The last guardian before the throne. The Void Champion was forged from pure abyss energy — no flesh, no weakness, no mercy. Beyond him, the Sovereign waits.",
		"background": "res://assets/art/progression/backgrounds/a1_combat_background.png",
		"portrait": "res://assets/art/enemies/portraits/void_champion_portrait.png",
	},
	{
		"index": 15, "name": "Abyss Sovereign", "hp": 3000, "ai_profile": "abyss_sovereign",
		"variant_profiles": [],
		"passives": ["void_might", "abyssal_mandate", "dark_channeling", "champion_abyss_sovereign"],
		"title": "ABYSS SOVEREIGN",
		"story": "At last. The Abyss Sovereign — the source of all corruption, the end of all things. It has devoured worlds without count. Today, it faces something it has never encountered: defiance.",
		"background": "res://assets/art/progression/backgrounds/a1_combat_background.png",
		"portrait": "",
	},
]

## The entry for encounter `index` (1-15), or {} if none.
static func entry(index: int) -> Dictionary:
	for e: Dictionary in ENCOUNTERS:
		if e["index"] == index:
			return e
	return {}

## A fresh EnemyData for encounter `index` (deck left empty — the caller picks
## one from EncounterDecks), or null.
static func make_enemy(index: int) -> EnemyData:
	var e: Dictionary = entry(index)
	if e.is_empty():
		return null
	var d := EnemyData.new()
	d.enemy_name = e["name"]
	d.hp = e["hp"]
	d.title = e["title"]
	d.story = e["story"]
	d.ai_profile = e["ai_profile"]
	d.passives.assign(e["passives"])
	if not (e["background"] as String).is_empty():
		d.background_path = e["background"]
	if not (e["portrait"] as String).is_empty():
		d.portrait_path = e["portrait"]
	return d

## The encounter an AI profile plays (its default or a variant), or {}.
static func entry_for_profile(profile_id: String) -> Dictionary:
	for e: Dictionary in ENCOUNTERS:
		if e["ai_profile"] == profile_id or profile_id in (e["variant_profiles"] as Array):
			return e
	return {}

## Enemy passives for a fight driven by `profile_id` ([] for profiles that
## belong to no encounter, e.g. "default").
static func passives_for_profile(profile_id: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(entry_for_profile(profile_id).get("passives", []))
	return out
