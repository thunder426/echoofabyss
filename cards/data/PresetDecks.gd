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
]

## Return the cards array for the given deck id, or [] if not found.
static func get_cards(deck_id: String) -> Array[String]:
	for d in DECKS:
		if (d as Dictionary).id == deck_id:
			var out: Array[String] = []
			out.assign((d as Dictionary).cards)
			return out
	return []
