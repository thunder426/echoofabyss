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
		"desc": "Sacrifice cheap Demons to forge greater ones. Grafted Butcher and Abyssal Sacrifice tick the Forge; Void Spawning and Fiendish Pact keep the bodies and tempo flowing.",
		"cards": [
			"void_imp", "void_imp",
			"grafted_butcher", "grafted_butcher",
			"grafted_fiend", "grafted_fiend", "grafted_fiend", "grafted_fiend",
			"void_devourer",
			"fiendish_pact", "fiendish_pact",
			"void_spawning", "void_spawning",
			"abyssal_sacrifice", "abyssal_sacrifice",
		],
	},
	# Corruption Engine — spell-heavy. Grafted Fiends act as Corruption batteries
	# for Void Amplification; spells double via Void Resonance at 5 Flesh.
	# Shadow Rune debuffs enemies on entry (classic use — doesn't feed the engine).
	{
		"id":   "seris_corruption_engine",
		"hero": "seris",
		"name": "Corruption Engine",
		"desc": "Corrupt your own Fiends with Cultist and Weaver to pump their ATK; spend Corruption with Flesh Rend and detonations for damage. Void Spawning and Fiendish Pact keep fresh Demons coming in to corrupt.",
		"cards": [
			"abyss_cultist",
			"void_imp", "void_imp",
			"corruption_weaver", "corruption_weaver",
			"grafted_fiend", "grafted_fiend", "grafted_fiend", "grafted_fiend",
			"fiendish_pact", "fiendish_pact",
			"void_spawning", "void_spawning",
			"flesh_rend", "flesh_rend",
		],
	},
	# ── Korrath, the Abyssal Commander ─────────────────────────────────────
	# Iron Legion — Human-heavy frame for Branch 1 Infernal Bulwark or Branch 2
	# Runic Knight (Human-path). Four knights anchor the build; the Human
	# minion package gives Formation partners on day one and Iron Resolve
	# fodder once T2 lands. Dominion Rune is hedged: it buffs Demon-knight
	# under Runic Transcendence's dual-tag, and any future demon allies.
	{
		"id":   "korrath_iron_legion",
		"hero": "korrath",
		"name": "Iron Legion",
		"desc": "A Human-heavy frame for Infernal Bulwark or Runic Knight (Human path). Four Abyssal Knights anchor the formation; Cultists and Soul Collectors fill out the Human pair count. Dominion Rune buffs the knight under Runic Transcendence.",
		"cards": [
			"abyssal_knight", "abyssal_knight", "abyssal_knight", "abyssal_knight",
			"abyss_cultist", "abyss_cultist",
			"soul_collector", "soul_collector",
			"corruption_weaver",
			"traveling_merchant", "traveling_merchant",
			"roadside_drifter",
			"spell_taxer",
			"abyssal_sacrifice",
			"dominion_rune",
		],
	},
	# Abyssal Vanguard — Demon-heavy frame for Branch 3 Abyssal Breaker. Knight
	# becomes a Demon under Corrupting Presence; Void Imps and Shadow Hounds fuel
	# Path of Destruction's Demon-attack AB stacks. Abyssal Sacrifice + Shadow
	# Rune apply Corruption to enemies, which Corrupting Presence converts into
	# armour strip and Path of Ruination's spells amplify by +100/stack.
	{
		"id":   "korrath_abyssal_vanguard",
		"hero": "korrath",
		"name": "Abyssal Vanguard",
		"desc": "A Demon-heavy frame for Abyssal Breaker. Knight retags Demon under Corrupting Presence; Void Imps and Shadow Hounds drive Path of Destruction's AB stacks. Shadow Rune seeds Corruption on enemy entry to fuel Path of Ruination spell amplification.",
		"cards": [
			"abyssal_knight", "abyssal_knight", "abyssal_knight", "abyssal_knight",
			"void_imp", "void_imp", "void_imp", "void_imp",
			"shadow_hound", "shadow_hound",
			"abyssal_brute",
			"abyssal_sacrifice", "abyssal_sacrifice",
			"shadow_rune",
			"dominion_rune",
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
