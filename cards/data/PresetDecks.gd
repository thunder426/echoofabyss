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
	# Fleshcraft — Grafted Fiends snowball through kills, backed by a steady
	# stream of cheap Demon bodies (Imps, Spawning tokens, Butcher sacs) that
	# feed Flesh. Fiendish Pact chains big Fiend turns; Deathless Flesh spends
	# the banked Flesh to keep late-game Fiends alive.
	{
		"id":   "seris_fleshcraft",
		"hero": "seris",
		"name": "Fleshcraft",
		"desc": "Cheap Demon bodies die to bank Flesh while Grafted Fiends grow through kills. Fiendish Pact discounts Fiend turns; Deathless Flesh spends banked Flesh to save them late.",
		"cards": [
			"grafted_fiend", "grafted_fiend", "grafted_fiend", "grafted_fiend",
			"void_imp", "void_imp",
			"grafted_butcher",
			"shadow_hound",
			"abyssal_brute",
			"fiendish_pact", "fiendish_pact",
			"void_spawning", "void_spawning",
			"dark_empowerment",
			"dominion_rune",
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
