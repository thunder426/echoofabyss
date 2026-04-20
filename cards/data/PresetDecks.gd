## PresetDecks.gd
## Single source of truth for all predefined starter decks.
## Used by DeckBuilderScene (player-facing) and BalanceSim (bot testing).
class_name PresetDecks
extends RefCounted

## Each entry: id, hero, name, desc, cards (Array[String]).
## hero — the hero_id this deck is designed for (used by BalanceSim for filtering).
const DECKS: Array = [
	{
		"id":   "swarm",
		"hero": "lord_vael",
		"name": "Swarm",
		"desc": "Flood the board with Imps and Demons. Shadow Hound scales with board width; Dark Empowerment pumps your strongest Demon.",
		"cards": [
			"void_imp", "void_imp", "void_imp", "void_imp",
			"shadow_hound", "shadow_hound",
			"void_stalker", "void_stalker",
			"abyssal_brute",
			"void_spawner",
			"abyssal_sacrifice", "abyssal_sacrifice",
			"dark_empowerment", "dark_empowerment",
			"dominion_rune",
		],
	},
	{
		"id":   "voidbolt_burst",
		"hero": "lord_vael",
		"name": "Voidbolt Burst",
		"desc": "Sacrifice Imps to fuel your spells, then burn the enemy hero with Void Bolts.",
		"cards": [
			"void_imp", "void_imp", "void_imp", "void_imp",
			"traveling_merchant", "traveling_merchant",
			"void_bolt", "void_bolt",
			"abyssal_sacrifice",
			"arcane_strike",
			"abyssal_plague", "abyssal_plague",
			"void_rune", "void_rune",
			"void_execution",
		],
	},
	{
		"id":   "death_circle",
		"hero": "lord_vael",
		"name": "Death Circle",
		"desc": "Place Runes to empower your Demons, then complete the ritual to summon a Demon Ascendant.",
		"cards": [
			"void_imp", "void_imp", "void_imp", "void_imp",
			"abyssal_summoning_circle",
			"dominion_rune", "dominion_rune",
			"blood_rune", "blood_rune",
			"shadow_hound",
			"void_netter",
			"caravan_guard", "caravan_guard",
			"abyssal_brute",
			"abyssal_sacrifice",
		],
	},
	# ── Seris, the Fleshbinder ─────────────────────────────────────────────
	# Fleshcraft — Grafted Fiends snowball through kills. Defensive shell to keep
	# them alive until they scale; removal to weaken enemies into kill range.
	# Avoids sacrifice spells (those destroy your own engine).
	{
		"id":   "seris_fleshcraft",
		"hero": "seris",
		"name": "Fleshcraft",
		"desc": "Four Grafted Fiends grow through kills. Defensive plays keep them alive; Deathless Flesh turns late-run Fiends into unkillable scalers.",
		"cards": [
			"grafted_fiend", "grafted_fiend", "grafted_fiend", "grafted_fiend",
			"void_imp", "void_imp",
			"shadow_hound",
			"abyssal_brute",
			"void_netter",
			"caravan_guard", "caravan_guard",
			"dark_empowerment",
			"dominion_rune",
			"flux_siphon",
			"hidden_ambush",
		],
	},
	# Demon Forge — sacrifice engine. Cheap Demon bodies to feed the Forge Counter;
	# Abyssal Sacrifice is the key spell (destroy → draw 2 + Forge tick + Fleshbind).
	# Void Spawner makes each sacrifice net-positive with a Spark replacement.
	{
		"id":   "seris_demon_forge",
		"hero": "seris",
		"name": "Demon Forge",
		"desc": "Sacrifice cheap Demons to forge greater ones. Void Spawner replaces losses with Sparks; Abyssal Sacrifice draws into the next wave.",
		"cards": [
			"grafted_fiend", "grafted_fiend", "grafted_fiend", "grafted_fiend",
			"void_imp", "void_imp", "void_imp",
			"shadow_hound",
			"void_spawner",
			"void_devourer",
			"abyssal_sacrifice", "abyssal_sacrifice",
			"dominion_rune",
			"flux_siphon",
			"caravan_guard",
		],
	},
	# Corruption Engine — spell-heavy. Grafted Fiends act as Corruption batteries
	# for Void Amplification; spells double via Void Resonance at 5 Flesh.
	# Shadow Rune debuffs enemies on entry (classic use — doesn't feed the engine).
	{
		"id":   "seris_corruption_engine",
		"hero": "seris",
		"name": "Corruption Engine",
		"desc": "Corrupt your Fiends to pump them and amplify spells. Void Resonance double-casts at 5 Flesh; Corrupt Detonation turns lost Corruption into damage.",
		"cards": [
			"grafted_fiend", "grafted_fiend", "grafted_fiend", "grafted_fiend",
			"abyss_cultist",
			"void_imp",
			"shadow_hound",
			"corruption_weaver",
			"void_bolt", "void_bolt",
			"abyssal_plague",
			"void_execution",
			"dark_empowerment",
			"shadow_rune",
			"flux_siphon",
		],
	},
]

## Return the cards array for the given deck id, or [] if not found.
static func get_cards(deck_id: String) -> Array[String]:
	for d in DECKS:
		if (d as Dictionary).id == deck_id:
			var out: Array[String] = []
			out.assign((d as Dictionary).cards)
			return out
	return []
