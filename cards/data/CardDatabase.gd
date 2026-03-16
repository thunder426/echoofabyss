## CardDatabase.gd
## Autoload — holds every card definition in the game.
## Access any card by ID: CardDatabase.get_card("void_imp")
##
## STAT SCALE: all ATK, HP, Shield, and damage numbers use a ×100 base
## so that percentage-based talent modifiers have integer granularity.
## (e.g. a 300 ATK minion can receive +5% = +15 ATK from a talent.)
extends Node

## All registered cards keyed by their id string
var _cards: Dictionary = {}

func _ready() -> void:
	_register_wanderer_cards()

## Returns the CardData resource for a given id, or null if not found
func get_card(id: String) -> CardData:
	if _cards.has(id):
		return _cards[id]
	push_error("CardDatabase: unknown card id '%s'" % id)
	return null

## Returns all registered card IDs
func get_all_card_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _cards.keys():
		ids.append(key as String)
	return ids

## Returns a list of CardData for a given array of ids
func get_cards(ids: Array[String]) -> Array[CardData]:
	var result: Array[CardData] = []
	for id in ids:
		var card := get_card(id)
		if card:
			result.append(card)
	return result

# ---------------------------------------------------------------------------
# Registration helpers
# ---------------------------------------------------------------------------

func _register(card: CardData) -> void:
	if _cards.has(card.id):
		push_warning("CardDatabase: duplicate card id '%s'" % card.id)
	_cards[card.id] = card

# ---------------------------------------------------------------------------
# Wanderer starter cards
# ---------------------------------------------------------------------------

func _register_wanderer_cards() -> void:

	# --- Minions ---

	var void_imp := MinionCardData.new()
	void_imp.id             = "void_imp"
	void_imp.card_name      = "Void Imp"
	void_imp.essence_cost   = 1
	void_imp.description    = "On play: deal 100 damage to the enemy hero."
	void_imp.atk            = 100
	void_imp.health         = 100
	void_imp.minion_type    = Enums.MinionType.DEMON
	void_imp.on_play_effect = "deal_1_enemy_hero"
	void_imp.minion_tags    = ["void_imp", "base_void_imp"]
	void_imp.faction        = "abyss_order"
	void_imp.art_path       = "res://assets/art/minions/abyss_order/void_imp.png"
	_register(void_imp)

	# Senior Void Imp — added to hand by Imp Evolution talent; counts as Void Imp
	var senior_void_imp := MinionCardData.new()
	senior_void_imp.id           = "senior_void_imp"
	senior_void_imp.card_name    = "Senior Void Imp"
	senior_void_imp.essence_cost = 2
	senior_void_imp.description  = "Counts as Void Imp. On play: deal 100 damage to the enemy hero."
	senior_void_imp.atk          = 400
	senior_void_imp.health       = 300
	senior_void_imp.minion_type  = Enums.MinionType.DEMON
	senior_void_imp.on_play_effect = "deal_1_enemy_hero"
	senior_void_imp.minion_tags  = ["void_imp", "senior_void_imp"]
	senior_void_imp.faction      = "abyss_order"
	_register(senior_void_imp)

	var shadow_hound := MinionCardData.new()
	shadow_hound.id             = "shadow_hound"
	shadow_hound.card_name      = "Shadow Hound"
	shadow_hound.essence_cost   = 2
	shadow_hound.description    = "On play: gains +100 ATK for each other Demon on your board."
	shadow_hound.atk            = 200
	shadow_hound.health         = 300
	shadow_hound.minion_type    = Enums.MinionType.DEMON
	shadow_hound.on_play_effect = "shadow_hound_atk_bonus"
	shadow_hound.faction        = "abyss_order"
	shadow_hound.art_path       = "res://assets/art/minions/abyss_order/shadow_hound.png"
	_register(shadow_hound)

	var abyssal_brute := MinionCardData.new()
	abyssal_brute.id            = "abyssal_brute"
	abyssal_brute.card_name     = "Abyssal Brute"
	abyssal_brute.essence_cost  = 4
	abyssal_brute.description   = ""
	abyssal_brute.atk           = 300
	abyssal_brute.health        = 600
	abyssal_brute.minion_type   = Enums.MinionType.DEMON
	abyssal_brute.keywords.append(Enums.Keyword.TAUNT)
	abyssal_brute.faction       = "abyss_order"
	abyssal_brute.art_path      = "res://assets/art/minions/abyss_order/abyssal_brute.png"
	_register(abyssal_brute)

	# Wandering Spirit — spawned by hero power, not in deck
	var wandering_spirit := MinionCardData.new()
	wandering_spirit.id           = "wandering_spirit"
	wandering_spirit.card_name    = "Wandering Spirit"
	wandering_spirit.essence_cost = 0
	wandering_spirit.description  = "Summoned by hero power."
	wandering_spirit.atk          = 100
	wandering_spirit.health       = 200
	wandering_spirit.minion_type  = Enums.MinionType.SPIRIT
	_register(wandering_spirit)

	# --- Spells ---

	var soul_leech := SpellCardData.new()
	soul_leech.id              = "soul_leech"
	soul_leech.card_name       = "Soul Leech"
	soul_leech.cost            = 1
	soul_leech.description     = "Give a friendly Demon +100 ATK and +100 HP. Restore 100 HP to your hero."
	soul_leech.requires_target = true
	soul_leech.target_type     = "friendly_demon"
	soul_leech.effect_id       = "soul_leech_effect"
	soul_leech.faction         = "abyss_order"
	_register(soul_leech)

	var dark_surge := SpellCardData.new()
	dark_surge.id          = "dark_surge"
	dark_surge.card_name   = "Dark Surge"
	dark_surge.cost        = 2
	dark_surge.description = "All your Demons gain +100 ATK until end of turn."
	dark_surge.effect_id   = "dark_surge_effect"
	dark_surge.faction     = "abyss_order"
	_register(dark_surge)

	var flux_siphon := SpellCardData.new()
	flux_siphon.id          = "flux_siphon"
	flux_siphon.card_name   = "Flux Siphon"
	flux_siphon.cost        = 0
	flux_siphon.description = "Convert all your remaining Mana into Essence."
	flux_siphon.effect_id   = "flux_siphon_effect"
	_register(flux_siphon)

	var abyssal_sacrifice := SpellCardData.new()
	abyssal_sacrifice.id             = "abyssal_sacrifice"
	abyssal_sacrifice.card_name      = "Abyssal Sacrifice"
	abyssal_sacrifice.cost           = 2
	abyssal_sacrifice.description    = "Destroy a friendly minion. Draw 2 cards."
	abyssal_sacrifice.requires_target = true
	abyssal_sacrifice.target_type    = "friendly_minion"
	abyssal_sacrifice.effect_id      = "abyssal_sacrifice_effect"
	abyssal_sacrifice.faction        = "abyss_order"
	_register(abyssal_sacrifice)

	var corrupting_mist := SpellCardData.new()
	corrupting_mist.id          = "corrupting_mist"
	corrupting_mist.card_name   = "Corrupting Mist"
	corrupting_mist.cost        = 2
	corrupting_mist.description = "Apply 1 Corruption to all enemy minions (−100 ATK each)."
	corrupting_mist.effect_id   = "corrupting_mist_effect"
	corrupting_mist.faction     = "abyss_order"
	_register(corrupting_mist)

	var abyssal_fury := SpellCardData.new()
	abyssal_fury.id              = "abyssal_fury"
	abyssal_fury.card_name       = "Abyssal Fury"
	abyssal_fury.cost            = 3
	abyssal_fury.description     = "Give a friendly Demon +200 ATK permanently and grant it Lifedrain."
	abyssal_fury.requires_target = true
	abyssal_fury.target_type     = "friendly_demon"
	abyssal_fury.effect_id       = "abyssal_fury_effect"
	abyssal_fury.faction         = "abyss_order"
	_register(abyssal_fury)

	var abyssal_reinforcement := SpellCardData.new()
	abyssal_reinforcement.id          = "abyssal_reinforcement"
	abyssal_reinforcement.card_name   = "Abyssal Reinforcement"
	abyssal_reinforcement.cost        = 3
	abyssal_reinforcement.description = "Summon two 100/100 Void Sparks. Draw 1 card."
	abyssal_reinforcement.effect_id   = "abyssal_reinforcement_effect"
	abyssal_reinforcement.faction     = "abyss_order"
	_register(abyssal_reinforcement)

	var corruption_collapse := SpellCardData.new()
	corruption_collapse.id          = "corruption_collapse"
	corruption_collapse.card_name   = "Corruption Collapse"
	corruption_collapse.cost        = 5
	corruption_collapse.description = "Destroy all Corrupted enemy minions."
	corruption_collapse.effect_id   = "corruption_collapse_effect"
	corruption_collapse.faction     = "abyss_order"
	_register(corruption_collapse)

	var abyssal_purge := SpellCardData.new()
	abyssal_purge.id          = "abyssal_purge"
	abyssal_purge.card_name   = "Abyssal Purge"
	abyssal_purge.cost        = 5
	abyssal_purge.description = "Destroy all enemy traps. Deal 200 damage to all enemy minions."
	abyssal_purge.effect_id   = "abyssal_purge_effect"
	abyssal_purge.faction     = "abyss_order"
	_register(abyssal_purge)

	# ---------------------------------------------------------------------------
	# --- Neutral Core Set ---
	# ---------------------------------------------------------------------------

	# 1-cost
	var ashland_forager := MinionCardData.new()
	ashland_forager.id          = "ashland_forager"
	ashland_forager.card_name   = "Ashland Forager"
	ashland_forager.essence_cost = 1
	ashland_forager.atk         = 200
	ashland_forager.health      = 200
	ashland_forager.minion_type = Enums.MinionType.BEAST
	ashland_forager.faction     = "neutral"
	_register(ashland_forager)

	var wandering_pilgrim := MinionCardData.new()
	wandering_pilgrim.id          = "wandering_pilgrim"
	wandering_pilgrim.card_name   = "Wandering Pilgrim"
	wandering_pilgrim.essence_cost = 1
	wandering_pilgrim.atk         = 100
	wandering_pilgrim.health      = 300
	wandering_pilgrim.minion_type = Enums.MinionType.HUMAN
	wandering_pilgrim.faction     = "neutral"
	_register(wandering_pilgrim)

	# 2-cost
	var freelance_sellsword := MinionCardData.new()
	freelance_sellsword.id          = "freelance_sellsword"
	freelance_sellsword.card_name   = "Freelance Sellsword"
	freelance_sellsword.essence_cost = 2
	freelance_sellsword.atk         = 300
	freelance_sellsword.health      = 200
	freelance_sellsword.minion_type = Enums.MinionType.HUMAN
	freelance_sellsword.faction     = "neutral"
	_register(freelance_sellsword)

	var traveling_merchant := MinionCardData.new()
	traveling_merchant.id            = "traveling_merchant"
	traveling_merchant.card_name     = "Traveling Merchant"
	traveling_merchant.description   = "On play: draw a card."
	traveling_merchant.essence_cost  = 2
	traveling_merchant.atk           = 200
	traveling_merchant.health        = 200
	traveling_merchant.minion_type   = Enums.MinionType.HUMAN
	traveling_merchant.on_play_effect = "draw_1_card"
	traveling_merchant.faction       = "neutral"
	_register(traveling_merchant)

	var trapbreaker_rogue := MinionCardData.new()
	trapbreaker_rogue.id            = "trapbreaker_rogue"
	trapbreaker_rogue.card_name     = "Trapbreaker Rogue"
	trapbreaker_rogue.description   = "On play: destroy a random enemy trap."
	trapbreaker_rogue.essence_cost  = 2
	trapbreaker_rogue.atk           = 250
	trapbreaker_rogue.health        = 200
	trapbreaker_rogue.minion_type   = Enums.MinionType.HUMAN
	trapbreaker_rogue.on_play_effect = "destroy_random_enemy_trap"
	trapbreaker_rogue.faction       = "neutral"
	_register(trapbreaker_rogue)

	var arcane_ward_drone := MinionCardData.new()
	arcane_ward_drone.id            = "arcane_ward_drone"
	arcane_ward_drone.card_name     = "Arcane Ward Drone"
	arcane_ward_drone.description   = "Magic Shield 200 (regenerates 100 per turn)."
	arcane_ward_drone.essence_cost  = 2
	arcane_ward_drone.mana_cost     = 1
	arcane_ward_drone.atk           = 200
	arcane_ward_drone.health        = 200
	arcane_ward_drone.shield_max    = 200
	arcane_ward_drone.minion_type   = Enums.MinionType.CONSTRUCT
	arcane_ward_drone.keywords.append(Enums.Keyword.SHIELD_REGEN_1)
	arcane_ward_drone.faction       = "neutral"
	_register(arcane_ward_drone)

	# 3-cost
	var caravan_guard := MinionCardData.new()
	caravan_guard.id          = "caravan_guard"
	caravan_guard.card_name   = "Caravan Guard"
	caravan_guard.essence_cost = 3
	caravan_guard.atk         = 350
	caravan_guard.health      = 350
	caravan_guard.minion_type = Enums.MinionType.HUMAN
	caravan_guard.faction     = "neutral"
	_register(caravan_guard)

	var arena_challenger := MinionCardData.new()
	arena_challenger.id          = "arena_challenger"
	arena_challenger.card_name   = "Arena Challenger"
	arena_challenger.description = ""
	arena_challenger.essence_cost = 3
	arena_challenger.atk         = 450
	arena_challenger.health      = 200
	arena_challenger.minion_type = Enums.MinionType.HUMAN
	arena_challenger.keywords.append(Enums.Keyword.RUSH)
	arena_challenger.faction     = "neutral"
	_register(arena_challenger)

	var wandering_warden := MinionCardData.new()
	wandering_warden.id          = "wandering_warden"
	wandering_warden.card_name   = "Wandering Warden"
	wandering_warden.description = ""
	wandering_warden.essence_cost = 3
	wandering_warden.atk         = 200
	wandering_warden.health      = 500
	wandering_warden.minion_type = Enums.MinionType.SPIRIT
	wandering_warden.keywords.append(Enums.Keyword.TAUNT)
	wandering_warden.faction     = "neutral"
	_register(wandering_warden)

	var spell_taxer := MinionCardData.new()
	spell_taxer.id            = "spell_taxer"
	spell_taxer.card_name     = "Spell Taxer"
	spell_taxer.description   = "On play: enemy spells cost +1 Essence on their next turn."
	spell_taxer.essence_cost  = 3
	spell_taxer.atk           = 250
	spell_taxer.health        = 300
	spell_taxer.minion_type   = Enums.MinionType.HUMAN
	spell_taxer.on_play_effect = "spell_taxer_effect"
	spell_taxer.faction       = "neutral"
	_register(spell_taxer)

	var saboteur_adept := MinionCardData.new()
	saboteur_adept.id            = "saboteur_adept"
	saboteur_adept.card_name     = "Saboteur Adept"
	saboteur_adept.description   = "On play: enemy traps cannot trigger this turn."
	saboteur_adept.essence_cost  = 3
	saboteur_adept.atk           = 300
	saboteur_adept.health        = 300
	saboteur_adept.minion_type   = Enums.MinionType.HUMAN
	saboteur_adept.on_play_effect = "saboteur_adept_effect"
	saboteur_adept.faction       = "neutral"
	_register(saboteur_adept)

	var aether_bulwark := MinionCardData.new()
	aether_bulwark.id            = "aether_bulwark"
	aether_bulwark.card_name     = "Aether Bulwark"
	aether_bulwark.description   = "Magic Shield 300 (regenerates 100 per turn)."
	aether_bulwark.essence_cost  = 3
	aether_bulwark.mana_cost     = 2
	aether_bulwark.atk           = 300
	aether_bulwark.health        = 400
	aether_bulwark.shield_max    = 300
	aether_bulwark.minion_type   = Enums.MinionType.CONSTRUCT
	aether_bulwark.keywords.append(Enums.Keyword.SHIELD_REGEN_1)
	aether_bulwark.faction       = "neutral"
	_register(aether_bulwark)

	# 4-cost
	var bronze_sentinel := MinionCardData.new()
	bronze_sentinel.id          = "bronze_sentinel"
	bronze_sentinel.card_name   = "Bronze Sentinel"
	bronze_sentinel.essence_cost = 4
	bronze_sentinel.atk         = 450
	bronze_sentinel.health      = 450
	bronze_sentinel.minion_type = Enums.MinionType.CONSTRUCT
	bronze_sentinel.faction     = "neutral"
	_register(bronze_sentinel)

	var gatekeeper_golem := MinionCardData.new()
	gatekeeper_golem.id          = "gatekeeper_golem"
	gatekeeper_golem.card_name   = "Gatekeeper Golem"
	gatekeeper_golem.description = ""
	gatekeeper_golem.essence_cost = 4
	gatekeeper_golem.atk         = 400
	gatekeeper_golem.health      = 500
	gatekeeper_golem.minion_type = Enums.MinionType.CONSTRUCT
	gatekeeper_golem.keywords.append(Enums.Keyword.TAUNT)
	gatekeeper_golem.faction     = "neutral"
	_register(gatekeeper_golem)

	var bulwark_automaton := MinionCardData.new()
	bulwark_automaton.id          = "bulwark_automaton"
	bulwark_automaton.card_name   = "Bulwark Automaton"
	bulwark_automaton.description = "Shield 200 (physical, does not regenerate)."
	bulwark_automaton.essence_cost = 4
	bulwark_automaton.atk         = 300
	bulwark_automaton.health      = 500
	bulwark_automaton.shield_max  = 200
	bulwark_automaton.minion_type = Enums.MinionType.CONSTRUCT
	bulwark_automaton.faction     = "neutral"
	_register(bulwark_automaton)

	var runic_shieldbearer := MinionCardData.new()
	runic_shieldbearer.id            = "runic_shieldbearer"
	runic_shieldbearer.card_name     = "Runic Shieldbearer"
	runic_shieldbearer.description   = "Magic Shield 300 (regenerates 100 per turn)."
	runic_shieldbearer.essence_cost  = 4
	runic_shieldbearer.mana_cost     = 1
	runic_shieldbearer.atk           = 350
	runic_shieldbearer.health        = 350
	runic_shieldbearer.shield_max    = 300
	runic_shieldbearer.minion_type   = Enums.MinionType.CONSTRUCT
	runic_shieldbearer.keywords.append(Enums.Keyword.SHIELD_REGEN_1)
	runic_shieldbearer.faction       = "neutral"
	_register(runic_shieldbearer)

	# 5-cost
	var bastion_walker := MinionCardData.new()
	bastion_walker.id          = "bastion_walker"
	bastion_walker.card_name   = "Bastion Walker"
	bastion_walker.description = "Shield 300 (physical, does not regenerate)."
	bastion_walker.essence_cost = 5
	bastion_walker.atk         = 400
	bastion_walker.health      = 600
	bastion_walker.shield_max  = 300
	bastion_walker.minion_type = Enums.MinionType.CONSTRUCT
	bastion_walker.faction     = "neutral"
	_register(bastion_walker)

	var ruins_archivist := MinionCardData.new()
	ruins_archivist.id            = "ruins_archivist"
	ruins_archivist.card_name     = "Ruins Archivist"
	ruins_archivist.description   = "On play: draw a card."
	ruins_archivist.essence_cost  = 5
	ruins_archivist.atk           = 450
	ruins_archivist.health        = 500
	ruins_archivist.minion_type   = Enums.MinionType.HUMAN
	ruins_archivist.on_play_effect = "draw_1_card"
	ruins_archivist.faction       = "neutral"
	_register(ruins_archivist)

	# 6-8 cost (big threats)
	var wildland_behemoth := MinionCardData.new()
	wildland_behemoth.id          = "wildland_behemoth"
	wildland_behemoth.card_name   = "Wildland Behemoth"
	wildland_behemoth.essence_cost = 6
	wildland_behemoth.atk         = 700
	wildland_behemoth.health      = 600
	wildland_behemoth.minion_type = Enums.MinionType.BEAST
	wildland_behemoth.faction     = "neutral"
	_register(wildland_behemoth)

	var iron_mountain_titan := MinionCardData.new()
	iron_mountain_titan.id          = "iron_mountain_titan"
	iron_mountain_titan.card_name   = "Iron Mountain Titan"
	iron_mountain_titan.essence_cost = 7
	iron_mountain_titan.atk         = 900
	iron_mountain_titan.health      = 600
	iron_mountain_titan.minion_type = Enums.MinionType.GIANT
	iron_mountain_titan.faction     = "neutral"
	_register(iron_mountain_titan)

	var rift_leviathan := MinionCardData.new()
	rift_leviathan.id          = "rift_leviathan"
	rift_leviathan.card_name   = "Rift Leviathan"
	rift_leviathan.essence_cost = 8
	rift_leviathan.atk         = 1000
	rift_leviathan.health      = 700
	rift_leviathan.minion_type = Enums.MinionType.BEAST
	rift_leviathan.faction     = "neutral"
	_register(rift_leviathan)

	# --- Neutral tokens (summoned by effects, not deck-buildable) ---

	var soldier := MinionCardData.new()
	soldier.id          = "soldier"
	soldier.card_name   = "Soldier"
	soldier.essence_cost = 0
	soldier.atk         = 100
	soldier.health      = 100
	soldier.minion_type = Enums.MinionType.HUMAN
	soldier.faction     = "neutral"
	_register(soldier)

	# --- Neutral Core Spells ---

	var cyclone := SpellCardData.new()
	cyclone.id          = "cyclone"
	cyclone.card_name   = "Cyclone"
	cyclone.cost        = 2
	cyclone.description = "Destroy a random active Trap or the active Environment."
	cyclone.effect_id   = "cyclone_effect"
	cyclone.faction     = "neutral"
	_register(cyclone)

	var hurricane := SpellCardData.new()
	hurricane.id          = "hurricane"
	hurricane.card_name   = "Hurricane"
	hurricane.cost        = 5
	hurricane.description = "Destroy all Traps and the Environment on the battlefield, including your own."
	hurricane.effect_id   = "hurricane_effect"
	hurricane.faction     = "neutral"
	_register(hurricane)

	var arcane_strike := SpellCardData.new()
	arcane_strike.id             = "arcane_strike"
	arcane_strike.card_name      = "Arcane Strike"
	arcane_strike.cost           = 1
	arcane_strike.description    = "Deal 200 damage to a target minion."
	arcane_strike.requires_target = true
	arcane_strike.target_type    = "any_minion"
	arcane_strike.effect_id      = "arcane_strike_effect"
	arcane_strike.faction        = "neutral"
	_register(arcane_strike)

	var precision_strike := SpellCardData.new()
	precision_strike.id             = "precision_strike"
	precision_strike.card_name      = "Precision Strike"
	precision_strike.cost           = 3
	precision_strike.description    = "Deal 400 damage to a target minion."
	precision_strike.requires_target = true
	precision_strike.target_type    = "any_minion"
	precision_strike.effect_id      = "precision_strike_effect"
	precision_strike.faction        = "neutral"
	_register(precision_strike)

	var tactical_planning := SpellCardData.new()
	tactical_planning.id          = "tactical_planning"
	tactical_planning.card_name   = "Tactical Planning"
	tactical_planning.cost        = 2
	tactical_planning.description = "Draw a card."
	tactical_planning.effect_id   = "tactical_planning_effect"
	tactical_planning.faction     = "neutral"
	_register(tactical_planning)

	var emergency_reinforcements := SpellCardData.new()
	emergency_reinforcements.id          = "emergency_reinforcements"
	emergency_reinforcements.card_name   = "Emergency Reinforcements"
	emergency_reinforcements.cost        = 2
	emergency_reinforcements.description = "Summon two 100/100 Soldiers."
	emergency_reinforcements.effect_id   = "emergency_reinforcements_effect"
	emergency_reinforcements.faction     = "neutral"
	_register(emergency_reinforcements)

	var energy_conversion := SpellCardData.new()
	energy_conversion.id          = "energy_conversion"
	energy_conversion.card_name   = "Energy Conversion"
	energy_conversion.cost        = 0
	energy_conversion.description = "Convert all remaining Essence into Mana."
	energy_conversion.effect_id   = "energy_conversion_effect"
	energy_conversion.faction     = "neutral"
	_register(energy_conversion)

	var essence_surge := SpellCardData.new()
	essence_surge.id          = "essence_surge"
	essence_surge.card_name   = "Essence Surge"
	essence_surge.cost        = 2
	essence_surge.description = "Gain 3 Essence this turn only."
	essence_surge.effect_id   = "essence_surge_effect"
	essence_surge.faction     = "neutral"
	_register(essence_surge)

	var battlefield_tactics := SpellCardData.new()
	battlefield_tactics.id             = "battlefield_tactics"
	battlefield_tactics.card_name      = "Battlefield Tactics"
	battlefield_tactics.cost           = 2
	battlefield_tactics.description    = "Give a friendly minion +200 ATK until end of turn."
	battlefield_tactics.requires_target = true
	battlefield_tactics.target_type    = "friendly_minion"
	battlefield_tactics.effect_id      = "battlefield_tactics_effect"
	battlefield_tactics.faction        = "neutral"
	_register(battlefield_tactics)

	var reinforced_armor := SpellCardData.new()
	reinforced_armor.id             = "reinforced_armor"
	reinforced_armor.card_name      = "Reinforced Armor"
	reinforced_armor.cost           = 2
	reinforced_armor.description    = "Give a minion +300 Shield."
	reinforced_armor.requires_target = true
	reinforced_armor.target_type    = "any_minion"
	reinforced_armor.effect_id      = "reinforced_armor_effect"
	reinforced_armor.faction        = "neutral"
	_register(reinforced_armor)

	var shield_break := SpellCardData.new()
	shield_break.id             = "shield_break"
	shield_break.card_name      = "Shield Break"
	shield_break.cost           = 1
	shield_break.description    = "Remove all Shield from a target minion."
	shield_break.requires_target = true
	shield_break.target_type    = "any_minion"
	shield_break.effect_id      = "shield_break_effect"
	shield_break.faction        = "neutral"
	_register(shield_break)

	var purge := SpellCardData.new()
	purge.id             = "purge"
	purge.card_name      = "Purge"
	purge.cost           = 2
	purge.description    = "Remove all buffs from an enemy minion, or all debuffs from a friendly minion."
	purge.requires_target = true
	purge.target_type    = "any_minion"
	purge.effect_id      = "purge_effect"
	purge.faction        = "neutral"
	_register(purge)

	var battlefield_salvage := SpellCardData.new()
	battlefield_salvage.id             = "battlefield_salvage"
	battlefield_salvage.card_name      = "Battlefield Salvage"
	battlefield_salvage.cost           = 2
	battlefield_salvage.description    = "Destroy a friendly minion. Draw 2 cards."
	battlefield_salvage.requires_target = true
	battlefield_salvage.target_type    = "friendly_minion"
	battlefield_salvage.effect_id      = "battlefield_salvage_effect"
	battlefield_salvage.faction        = "neutral"
	_register(battlefield_salvage)

	var shockwave := SpellCardData.new()
	shockwave.id          = "shockwave"
	shockwave.card_name   = "Shockwave"
	shockwave.cost        = 4
	shockwave.description = "Deal 200 damage to all minions."
	shockwave.effect_id   = "shockwave_effect"
	shockwave.faction     = "neutral"
	_register(shockwave)

	# --- Enemy spells (used only by EnemyAI card pool, not in player deck builder) ---

	var shadow_bolt := SpellCardData.new()
	shadow_bolt.id          = "shadow_bolt"
	shadow_bolt.card_name   = "Shadow Bolt"
	shadow_bolt.cost        = 2
	shadow_bolt.description = "Deal 300 damage to the enemy hero."
	shadow_bolt.effect_id   = "shadow_bolt_effect"
	_register(shadow_bolt)

	var void_barrage := SpellCardData.new()
	void_barrage.id          = "void_barrage"
	void_barrage.card_name   = "Void Barrage"
	void_barrage.cost        = 2
	void_barrage.description = "Deal 100 damage to each enemy minion."
	void_barrage.effect_id   = "void_barrage_effect"
	_register(void_barrage)

	# --- Traps ---

	var void_snare := TrapCardData.new()
	void_snare.id          = "void_snare"
	void_snare.card_name   = "Void Snare"
	void_snare.cost        = 2
	void_snare.description = "Trap: When the enemy plays a spell, deal 300 damage to the enemy hero."
	void_snare.trigger     = Enums.TriggerEvent.ON_ENEMY_SPELL_CAST
	void_snare.effect_id   = "void_snare_effect"
	void_snare.faction     = "abyss_order"
	_register(void_snare)

	var soul_cage := TrapCardData.new()
	soul_cage.id          = "soul_cage"
	soul_cage.card_name   = "Soul Cage"
	soul_cage.cost        = 1
	soul_cage.description = "Trap: When the enemy summons a minion, deal 200 damage to the enemy hero."
	soul_cage.trigger     = Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	soul_cage.effect_id   = "soul_cage_effect"
	soul_cage.faction     = "abyss_order"
	_register(soul_cage)

	var phantom_recoil := TrapCardData.new()
	phantom_recoil.id          = "phantom_recoil"
	phantom_recoil.card_name   = "Phantom Recoil"
	phantom_recoil.cost        = 2
	phantom_recoil.description = "Trap: When your hero takes damage, restore 400 HP to your hero."
	phantom_recoil.trigger     = Enums.TriggerEvent.ON_HERO_DAMAGED
	phantom_recoil.effect_id   = "phantom_recoil_effect"
	_register(phantom_recoil)

	var abyss_retaliation := TrapCardData.new()
	abyss_retaliation.id          = "abyss_retaliation"
	abyss_retaliation.card_name   = "Abyss Retaliation"
	abyss_retaliation.cost        = 3
	abyss_retaliation.description = "Trap: When an enemy minion attacks, deal 400 damage to the enemy hero."
	abyss_retaliation.trigger     = Enums.TriggerEvent.ON_ENEMY_ATTACK
	abyss_retaliation.effect_id   = "abyss_retaliation_effect"
	abyss_retaliation.faction     = "abyss_order"
	_register(abyss_retaliation)

	# --- Environments ---

	var abyss_rift := EnvironmentCardData.new()
	abyss_rift.id                  = "abyss_rift"
	abyss_rift.card_name           = "Abyss Rift"
	abyss_rift.cost                = 3
	abyss_rift.description         = "Your Demons gain +100 ATK at the start of your turn."
	abyss_rift.passive_description = "Your Demons gain +100 ATK at the start of your turn."
	abyss_rift.passive_effect_id   = "abyss_rift_passive"
	abyss_rift.faction             = "abyss_order"
	_register(abyss_rift)

	# -----------------------------------------------------------------------
	# Abyss Order — core card set
	# -----------------------------------------------------------------------

	# --- Corruption synergy minions ---

	var abyss_cultist := MinionCardData.new()
	abyss_cultist.id             = "abyss_cultist"
	abyss_cultist.card_name      = "Abyss Cultist"
	abyss_cultist.essence_cost   = 1
	abyss_cultist.description    = "On play: Corrupt a random enemy minion (−100 ATK)."
	abyss_cultist.atk            = 100
	abyss_cultist.health         = 300
	abyss_cultist.minion_type    = Enums.MinionType.HUMAN
	abyss_cultist.on_play_effect = "abyss_cultist_corrupt"
	abyss_cultist.faction        = "abyss_order"
	abyss_cultist.art_path       = "res://assets/art/minions/abyss_order/abyss_cultist.png"
	_register(abyss_cultist)

	var void_netter := MinionCardData.new()
	void_netter.id             = "void_netter"
	void_netter.card_name      = "Void Netter"
	void_netter.essence_cost   = 2
	void_netter.description    = "On play: deal 200 damage to a random enemy minion."
	void_netter.atk            = 100
	void_netter.health         = 300
	void_netter.minion_type    = Enums.MinionType.HUMAN
	void_netter.on_play_effect = "void_netter_damage"
	void_netter.faction        = "abyss_order"
	void_netter.art_path       = "res://assets/art/minions/abyss_order/void_netter.png"
	_register(void_netter)

	var corruption_weaver := MinionCardData.new()
	corruption_weaver.id             = "corruption_weaver"
	corruption_weaver.card_name      = "Corruption Weaver"
	corruption_weaver.essence_cost   = 3
	corruption_weaver.description    = "On play: Corrupt all enemy minions (−100 ATK each)."
	corruption_weaver.atk            = 100
	corruption_weaver.health         = 400
	corruption_weaver.minion_type    = Enums.MinionType.HUMAN
	corruption_weaver.on_play_effect = "corruption_weaver_corrupt_all"
	corruption_weaver.faction        = "abyss_order"
	corruption_weaver.art_path       = "res://assets/art/minions/abyss_order/corruption_weaver.png"
	_register(corruption_weaver)

	var soul_collector := MinionCardData.new()
	soul_collector.id             = "soul_collector"
	soul_collector.card_name      = "Soul Collector"
	soul_collector.essence_cost   = 5
	soul_collector.description    = "On play: instantly kill a random Corrupted enemy minion."
	soul_collector.atk            = 300
	soul_collector.health         = 700
	soul_collector.minion_type    = Enums.MinionType.HUMAN
	soul_collector.on_play_effect = "soul_collector_execute"
	soul_collector.faction        = "abyss_order"
	soul_collector.art_path       = "res://assets/art/minions/abyss_order/soul_collector.png"
	_register(soul_collector)

	# --- Rush / aggressive ---

	var void_stalker := MinionCardData.new()
	void_stalker.id           = "void_stalker"
	void_stalker.card_name    = "Void Stalker"
	void_stalker.essence_cost = 3
	void_stalker.description  = ""
	void_stalker.atk          = 300
	void_stalker.health       = 200
	void_stalker.minion_type  = Enums.MinionType.DEMON
	void_stalker.keywords.append(Enums.Keyword.RUSH)
	void_stalker.keywords.append(Enums.Keyword.LIFEDRAIN)
	void_stalker.faction      = "abyss_order"
	void_stalker.art_path     = "res://assets/art/minions/abyss_order/void_stalker.png"
	_register(void_stalker)

	# --- Board-wide passive payoffs ---

	var void_spawner := MinionCardData.new()
	void_spawner.id           = "void_spawner"
	void_spawner.card_name    = "Void Spawner"
	void_spawner.essence_cost = 4
	void_spawner.description  = "Passive: when a friendly minion dies, summon a 100/100 Void Spark."
	void_spawner.atk          = 200
	void_spawner.health       = 600
	void_spawner.minion_type  = Enums.MinionType.DEMON
	void_spawner.passive_effect_id = "void_spark_on_friendly_death"
	void_spawner.faction      = "abyss_order"
	void_spawner.art_path     = "res://assets/art/minions/abyss_order/void_spawner.png"
	_register(void_spawner)

	var abyssal_tide := MinionCardData.new()
	abyssal_tide.id           = "abyssal_tide"
	abyssal_tide.card_name    = "Abyssal Tide"
	abyssal_tide.essence_cost = 5
	abyssal_tide.description  = "Passive: whenever a friendly minion dies, deal 200 damage to the enemy hero."
	abyssal_tide.atk          = 400
	abyssal_tide.health       = 400
	abyssal_tide.minion_type  = Enums.MinionType.DEMON
	abyssal_tide.passive_effect_id = "deal_200_hero_on_friendly_death"
	abyssal_tide.faction      = "abyss_order"
	abyssal_tide.art_path     = "res://assets/art/minions/abyss_order/abyssal_tide.png"
	_register(abyssal_tide)

	# --- Sacrifice finisher ---

	var void_devourer := MinionCardData.new()
	void_devourer.id             = "void_devourer"
	void_devourer.card_name      = "Void Devourer"
	void_devourer.essence_cost   = 6
	void_devourer.description    = "On play: sacrifice adjacent friendly minions. Gains +300 ATK and +300 HP per sacrificed."
	void_devourer.atk            = 200
	void_devourer.health         = 600
	void_devourer.minion_type    = Enums.MinionType.DEMON
	void_devourer.keywords.append(Enums.Keyword.TAUNT)
	void_devourer.on_play_effect = "void_devourer_sacrifice"
	void_devourer.faction        = "abyss_order"
	void_devourer.art_path       = "res://assets/art/minions/abyss_order/void_devourer.png"
	_register(void_devourer)

	# --- Champion (max 1 copy, auto-summoned when 3 Void Imps are on board) ---

	var nyx_ael := MinionCardData.new()
	nyx_ael.id           = "nyx_ael"
	nyx_ael.card_name    = "Nyx'ael, Void Sovereign"
	nyx_ael.essence_cost = 5
	nyx_ael.description  = "Auto-summoned when 3 Void Imps hit the board.\nPassive: At the start of your turn, Corrupt all enemies and deal 200 damage to each Corrupted enemy."
	nyx_ael.atk          = 500
	nyx_ael.health       = 500
	nyx_ael.minion_type  = Enums.MinionType.DEMON
	nyx_ael.keywords.append(Enums.Keyword.CHAMPION)
	nyx_ael.minion_tags           = ["void_champion"]
	nyx_ael.is_champion           = true
	nyx_ael.auto_summon_condition = "board_tag_count"
	nyx_ael.auto_summon_tag       = "void_imp"
	nyx_ael.auto_summon_threshold = 3
	nyx_ael.faction      = "abyss_order"
	nyx_ael.art_path     = "res://assets/art/minions/abyss_order/nyx_ael.png"
	_register(nyx_ael)

	# --- Token (not in player deck, summoned by effects) ---

	var void_spark := MinionCardData.new()
	void_spark.id           = "void_spark"
	void_spark.card_name    = "Void Spark"
	void_spark.essence_cost = 0
	void_spark.description  = "Summoned by Void Spawner."
	void_spark.atk          = 100
	void_spark.health       = 100
	void_spark.minion_type  = Enums.MinionType.DEMON
	void_spark.faction      = "abyss_order"
	_register(void_spark)

	# --- Void Bolt card ecosystem (Mana-cost, Lord Vael void_bolt branch) ---

	var void_bolt_spell := SpellCardData.new()
	void_bolt_spell.id             = "void_bolt"
	void_bolt_spell.card_name      = "Void Bolt"
	void_bolt_spell.cost           = 2
	void_bolt_spell.description    = "Deal 300 Void Bolt damage to the enemy hero. (Piercing Void: also apply 1 Void Mark.)"
	void_bolt_spell.effect_id       = "void_bolt_effect"
	void_bolt_spell.requires_target = false
	void_bolt_spell.faction         = "abyss_order"
	_register(void_bolt_spell)

	var void_bolt_rain := EnvironmentCardData.new()
	void_bolt_rain.id                  = "void_bolt_rain"
	void_bolt_rain.card_name           = "Void Bolt Rain"
	void_bolt_rain.cost                = 3
	void_bolt_rain.description         = "Environment: At the start of each turn, deal 100 Void Bolt damage to both heroes."
	void_bolt_rain.passive_description = "Both heroes take 100 Void Bolt damage each turn."
	void_bolt_rain.passive_effect_id   = "void_bolt_rain_passive"
	void_bolt_rain.faction             = "abyss_order"
	_register(void_bolt_rain)

	var death_bolt_trap := TrapCardData.new()
	death_bolt_trap.id          = "death_bolt_trap"
	death_bolt_trap.card_name   = "Death Bolt Trap"
	death_bolt_trap.cost        = 2
	death_bolt_trap.description = "Trap: When the enemy attacks, deal 200 Void Bolt damage to the enemy hero."
	death_bolt_trap.trigger     = Enums.TriggerEvent.ON_ENEMY_ATTACK
	death_bolt_trap.effect_id   = "death_bolt_trap_effect"
	death_bolt_trap.faction     = "abyss_order"
	_register(death_bolt_trap)

	var corruption_surge := TrapCardData.new()
	corruption_surge.id          = "corruption_surge"
	corruption_surge.card_name   = "Corruption Surge"
	corruption_surge.cost        = 2
	corruption_surge.description = "Trap: When the enemy summons a minion, apply 1 Corruption to it and deal 300 damage to it."
	corruption_surge.trigger     = Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	corruption_surge.effect_id   = "corruption_surge_effect"
	corruption_surge.faction     = "abyss_order"
	_register(corruption_surge)

	var abyssal_claim := TrapCardData.new()
	abyssal_claim.id          = "abyssal_claim"
	abyssal_claim.card_name   = "Abyssal Claim"
	abyssal_claim.cost        = 1
	abyssal_claim.description = "Trap: When a friendly minion dies during the enemy's turn, summon a 100/100 Void Spark and deal 200 damage to the enemy hero."
	abyssal_claim.trigger     = Enums.TriggerEvent.ON_PLAYER_MINION_DIED
	abyssal_claim.effect_id   = "abyssal_claim_effect"
	abyssal_claim.faction     = "abyss_order"
	_register(abyssal_claim)

	var void_collapse := TrapCardData.new()
	void_collapse.id          = "void_collapse"
	void_collapse.card_name   = "Void Collapse"
	void_collapse.cost        = 3
	void_collapse.description = "Trap: When the enemy summons a minion, deal 200 damage to all enemy minions."
	void_collapse.trigger     = Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	void_collapse.effect_id   = "void_collapse_effect"
	void_collapse.faction     = "abyss_order"
	_register(void_collapse)

	# --- Neutral Traps ---

	var hidden_ambush := TrapCardData.new()
	hidden_ambush.id          = "hidden_ambush"
	hidden_ambush.card_name   = "Hidden Ambush"
	hidden_ambush.cost        = 1
	hidden_ambush.description = "Trap: When an enemy minion attacks, deal 200 damage to that minion."
	hidden_ambush.trigger     = Enums.TriggerEvent.ON_ENEMY_ATTACK
	hidden_ambush.effect_id   = "hidden_ambush_effect"
	hidden_ambush.faction     = "neutral"
	_register(hidden_ambush)

	var arcane_rebound := TrapCardData.new()
	arcane_rebound.id          = "arcane_rebound"
	arcane_rebound.card_name   = "Arcane Rebound"
	arcane_rebound.cost        = 1
	arcane_rebound.description = "Trap: When the enemy plays a spell, deal 300 damage to the enemy hero."
	arcane_rebound.trigger     = Enums.TriggerEvent.ON_ENEMY_SPELL_CAST
	arcane_rebound.effect_id   = "arcane_rebound_effect"
	arcane_rebound.faction     = "neutral"
	_register(arcane_rebound)

	var null_seal := TrapCardData.new()
	null_seal.id          = "null_seal"
	null_seal.card_name   = "Null Seal"
	null_seal.cost        = 3
	null_seal.description = "Trap: When the enemy plays a spell, cancel that spell."
	null_seal.trigger     = Enums.TriggerEvent.ON_ENEMY_SPELL_CAST
	null_seal.effect_id   = "null_seal_effect"
	null_seal.faction     = "neutral"
	_register(null_seal)

	var gate_collapse := TrapCardData.new()
	gate_collapse.id          = "gate_collapse"
	gate_collapse.card_name   = "Gate Collapse"
	gate_collapse.cost        = 3
	gate_collapse.description = "Trap: When the enemy summons a minion, destroy that minion."
	gate_collapse.trigger     = Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	gate_collapse.effect_id   = "gate_collapse_effect"
	gate_collapse.faction     = "neutral"
	_register(gate_collapse)

	var trap_disruption := TrapCardData.new()
	trap_disruption.id          = "trap_disruption"
	trap_disruption.card_name   = "Trap Disruption"
	trap_disruption.cost        = 2
	trap_disruption.description = "Trap: When the enemy plays a trap, destroy it before it activates."
	trap_disruption.trigger     = Enums.TriggerEvent.ON_ENEMY_TRAP_PLACED
	trap_disruption.effect_id   = "trap_disruption_effect"
	trap_disruption.faction     = "neutral"
	_register(trap_disruption)

	var smoke_veil := TrapCardData.new()
	smoke_veil.id          = "smoke_veil"
	smoke_veil.card_name   = "Smoke Veil"
	smoke_veil.cost        = 2
	smoke_veil.description = "Trap: When an enemy minion attacks, cancel that attack and exhaust all enemy minions."
	smoke_veil.trigger     = Enums.TriggerEvent.ON_ENEMY_ATTACK
	smoke_veil.effect_id   = "smoke_veil_effect"
	smoke_veil.faction     = "neutral"
	_register(smoke_veil)

	var hidden_cache := TrapCardData.new()
	hidden_cache.id          = "hidden_cache"
	hidden_cache.card_name   = "Hidden Cache"
	hidden_cache.cost        = 2
	hidden_cache.description = "Trap: When the enemy summons a minion, draw 2 cards."
	hidden_cache.trigger     = Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	hidden_cache.effect_id   = "hidden_cache_effect"
	hidden_cache.faction     = "neutral"
	_register(hidden_cache)

	var trap_emergency_reinforcements := TrapCardData.new()
	trap_emergency_reinforcements.id          = "trap_emergency_reinforcements"
	trap_emergency_reinforcements.card_name   = "Emergency Reinforcements"
	trap_emergency_reinforcements.cost        = 2
	trap_emergency_reinforcements.description = "Trap: When your hero takes damage, summon two 100/200 Wandering Spirits."
	trap_emergency_reinforcements.trigger     = Enums.TriggerEvent.ON_HERO_DAMAGED
	trap_emergency_reinforcements.effect_id   = "trap_emergency_reinforcements_effect"
	trap_emergency_reinforcements.faction     = "neutral"
	_register(trap_emergency_reinforcements)

	var shock_mine := TrapCardData.new()
	shock_mine.id          = "shock_mine"
	shock_mine.card_name   = "Shock Mine"
	shock_mine.cost        = 3
	shock_mine.description = "Trap: When an enemy minion attacks, deal 200 damage to all enemy minions."
	shock_mine.trigger     = Enums.TriggerEvent.ON_ENEMY_ATTACK
	shock_mine.effect_id   = "shock_mine_effect"
	shock_mine.faction     = "neutral"
	_register(shock_mine)

	# ---------------------------------------------------------------------------
	# --- Void Bolt Support Pool (Lord Vael, Piercing Void talent only) ---
	# ---------------------------------------------------------------------------

	# Spells
	var mark_the_target := SpellCardData.new()
	mark_the_target.id          = "mark_the_target"
	mark_the_target.card_name   = "Mark the Target"
	mark_the_target.cost        = 2
	mark_the_target.description = "Apply 2 Void Marks to the enemy hero. Draw a card."
	mark_the_target.effect_id   = "mark_the_target_effect"
	mark_the_target.faction     = "abyss_order"
	_register(mark_the_target)

	var imp_combustion := SpellCardData.new()
	imp_combustion.id             = "imp_combustion"
	imp_combustion.card_name      = "Imp Combustion"
	imp_combustion.cost           = 1
	imp_combustion.description    = "Destroy a friendly Void Imp. Deal 200 Void Bolt damage to the enemy hero."
	imp_combustion.requires_target = true
	imp_combustion.target_type    = "friendly_void_imp"
	imp_combustion.effect_id      = "imp_combustion_effect"
	imp_combustion.faction        = "abyss_order"
	_register(imp_combustion)

	var dark_ritual := SpellCardData.new()
	dark_ritual.id             = "dark_ritual_of_the_abyss"
	dark_ritual.card_name      = "Dark Ritual of the Abyss"
	dark_ritual.cost           = 2
	dark_ritual.description    = "Destroy a friendly Void Imp. Draw 2 cards."
	dark_ritual.requires_target = true
	dark_ritual.target_type    = "friendly_void_imp"
	dark_ritual.effect_id      = "dark_ritual_effect"
	dark_ritual.faction        = "abyss_order"
	_register(dark_ritual)

	var imp_overload := SpellCardData.new()
	imp_overload.id          = "imp_overload"
	imp_overload.card_name   = "Imp Overload"
	imp_overload.cost        = 3
	imp_overload.description = "Summon 2 Void Imps. They die at the end of this turn."
	imp_overload.effect_id   = "imp_overload_effect"
	imp_overload.faction     = "abyss_order"
	_register(imp_overload)

	var void_detonation := SpellCardData.new()
	void_detonation.id          = "void_detonation"
	void_detonation.card_name   = "Void Detonation"
	void_detonation.cost        = 4
	void_detonation.description = "Deal 150 Void Bolt damage to the enemy hero. Gain +50 damage per Void Mark."
	void_detonation.effect_id   = "void_detonation_effect"
	void_detonation.faction     = "abyss_order"
	_register(void_detonation)

	var mark_convergence := SpellCardData.new()
	mark_convergence.id          = "mark_convergence"
	mark_convergence.card_name   = "Mark Convergence"
	mark_convergence.cost        = 5
	mark_convergence.description = "Double the number of Void Marks on the enemy hero."
	mark_convergence.effect_id   = "mark_convergence_effect"
	mark_convergence.faction     = "abyss_order"
	_register(mark_convergence)

	# Minions
	var void_channeler := MinionCardData.new()
	void_channeler.id            = "void_channeler"
	void_channeler.card_name     = "Void Channeler"
	void_channeler.description   = "Passive: whenever Void Bolt damage is dealt, apply 1 additional Void Mark."
	void_channeler.essence_cost  = 1
	void_channeler.mana_cost     = 2
	void_channeler.atk           = 100
	void_channeler.health        = 300
	void_channeler.minion_type   = Enums.MinionType.HUMAN
	void_channeler.on_void_bolt_passive_effect_id = "void_mark_per_channeler"
	void_channeler.faction       = "abyss_order"
	_register(void_channeler)

	var abyssal_sacrificer := MinionCardData.new()
	abyssal_sacrificer.id          = "abyssal_sacrificer"
	abyssal_sacrificer.card_name   = "Abyssal Sacrificer"
	abyssal_sacrificer.description = "Passive: whenever a friendly Void Imp dies, apply 1 Void Mark to the enemy hero."
	abyssal_sacrificer.essence_cost = 1
	abyssal_sacrificer.mana_cost   = 2
	abyssal_sacrificer.atk         = 100
	abyssal_sacrificer.health      = 300
	abyssal_sacrificer.minion_type = Enums.MinionType.HUMAN
	abyssal_sacrificer.passive_effect_id = "void_mark_on_void_imp_death"
	abyssal_sacrificer.faction     = "abyss_order"
	_register(abyssal_sacrificer)

	var abyssal_arcanist := MinionCardData.new()
	abyssal_arcanist.id            = "abyssal_arcanist"
	abyssal_arcanist.card_name     = "Abyssal Arcanist"
	abyssal_arcanist.description   = "On play: add a Void Bolt spell to your hand."
	abyssal_arcanist.essence_cost  = 2
	abyssal_arcanist.mana_cost     = 2
	abyssal_arcanist.atk           = 200
	abyssal_arcanist.health        = 300
	abyssal_arcanist.minion_type   = Enums.MinionType.HUMAN
	abyssal_arcanist.on_play_effect = "abyssal_arcanist_effect"
	abyssal_arcanist.faction       = "abyss_order"
	_register(abyssal_arcanist)

	var void_archmagus := MinionCardData.new()
	void_archmagus.id          = "void_archmagus"
	void_archmagus.card_name   = "Void Archmagus"
	void_archmagus.description = "Your spells cost 1 less Mana. Whenever you cast a spell, add a Void Bolt to your hand. Deck limit: 1."
	void_archmagus.essence_cost = 5
	void_archmagus.mana_cost   = 5
	void_archmagus.atk         = 400
	void_archmagus.health      = 600
	void_archmagus.minion_type                 = Enums.MinionType.HUMAN
	void_archmagus.mana_cost_discount          = 1
	void_archmagus.on_spell_cast_passive_effect_id = "add_void_bolt_on_spell"
	void_archmagus.faction                     = "abyss_order"
	_register(void_archmagus)

	# Traps
	var soul_rupture := TrapCardData.new()
	soul_rupture.id          = "soul_rupture"
	soul_rupture.card_name   = "Soul Rupture"
	soul_rupture.cost        = 2
	soul_rupture.description = "Trap: When a friendly Void Imp dies during the enemy's turn, deal 250 Void Bolt damage to the enemy hero."
	soul_rupture.trigger     = Enums.TriggerEvent.ON_PLAYER_MINION_DIED
	soul_rupture.effect_id   = "soul_rupture_effect"
	soul_rupture.faction     = "abyss_order"
	_register(soul_rupture)

	var mark_collapse := TrapCardData.new()
	mark_collapse.id          = "mark_collapse"
	mark_collapse.card_name   = "Mark Collapse"
	mark_collapse.cost        = 3
	mark_collapse.description = "Trap: At the start of the enemy's turn, if the enemy hero has 5+ Void Marks, consume all marks and deal 150 Void Bolt damage per mark."
	mark_collapse.trigger     = Enums.TriggerEvent.ON_ENEMY_TURN_START
	mark_collapse.effect_id   = "mark_collapse_effect"
	mark_collapse.faction     = "abyss_order"
	_register(mark_collapse)

	# Environment
	var void_rain := EnvironmentCardData.new()
	void_rain.id                  = "void_rain"
	void_rain.card_name           = "Void Rain"
	void_rain.cost                = 3
	void_rain.description         = "At the start of every turn, deal 100 Void Bolt damage to both heroes."
	void_rain.passive_description = "At the start of every turn, deal 100 Void Bolt damage to both heroes."
	void_rain.passive_effect_id   = "void_rain_passive"
	void_rain.fires_on_enemy_turn = true
	void_rain.faction             = "abyss_order"
	_register(void_rain)

	# ---------------------------------------------------------------------------
	# --- Lord Vael — Common Imp Support Pool (unlocked by defeating act bosses) ---
	# ---------------------------------------------------------------------------

	# Spells
	var abyssal_conjuring := SpellCardData.new()
	abyssal_conjuring.id          = "abyssal_conjuring"
	abyssal_conjuring.card_name   = "Abyssal Conjuring"
	abyssal_conjuring.cost        = 1
	abyssal_conjuring.description = "If your board is empty, summon a Void Imp. Otherwise summon a Void Spark."
	abyssal_conjuring.effect_id   = "abyssal_conjuring_effect"
	abyssal_conjuring.faction     = "abyss_order"
	_register(abyssal_conjuring)

	var call_the_swarm := SpellCardData.new()
	call_the_swarm.id          = "call_the_swarm"
	call_the_swarm.card_name   = "Call the Swarm"
	call_the_swarm.cost        = 4
	call_the_swarm.description = "Summon 2 Void Imps."
	call_the_swarm.effect_id   = "call_the_swarm_effect"
	call_the_swarm.faction     = "abyss_order"
	_register(call_the_swarm)

	var void_breach := SpellCardData.new()
	void_breach.id          = "void_breach"
	void_breach.card_name   = "Void Breach"
	void_breach.cost        = 2
	void_breach.description = "Add a Void Imp to your hand."
	void_breach.effect_id   = "void_breach_effect"
	void_breach.faction     = "abyss_order"
	_register(void_breach)

	# Minions
	var abyss_recruiter := MinionCardData.new()
	abyss_recruiter.id             = "abyss_recruiter"
	abyss_recruiter.card_name      = "Abyss Recruiter"
	abyss_recruiter.description    = "On play: add a Void Imp to your hand."
	abyss_recruiter.essence_cost   = 2
	abyss_recruiter.atk            = 200
	abyss_recruiter.health         = 300
	abyss_recruiter.minion_type    = Enums.MinionType.HUMAN
	abyss_recruiter.on_play_effect = "abyss_recruiter_effect"
	abyss_recruiter.faction        = "abyss_order"
	_register(abyss_recruiter)

	var imp_handler := MinionCardData.new()
	imp_handler.id          = "imp_handler"
	imp_handler.card_name   = "Imp Handler"
	imp_handler.description = "Passive: whenever a Void Imp is summoned, it gains +100 HP."
	imp_handler.essence_cost = 3
	imp_handler.atk         = 150
	imp_handler.health      = 400
	imp_handler.minion_type = Enums.MinionType.HUMAN
	imp_handler.passive_effect_id = "buff_void_imp_on_summon"
	imp_handler.faction     = "abyss_order"
	_register(imp_handler)

	var abyssal_taskmaster := MinionCardData.new()
	abyssal_taskmaster.id          = "abyssal_taskmaster"
	abyssal_taskmaster.card_name   = "Abyssal Taskmaster"
	abyssal_taskmaster.description = "Passive: whenever a friendly Void Imp dies, this minion gains +100 ATK."
	abyssal_taskmaster.essence_cost = 3
	abyssal_taskmaster.atk         = 300
	abyssal_taskmaster.health      = 400
	abyssal_taskmaster.minion_type = Enums.MinionType.DEMON
	abyssal_taskmaster.passive_effect_id = "gain_atk_on_void_imp_death"
	abyssal_taskmaster.faction     = "abyss_order"
	_register(abyssal_taskmaster)

	var imp_overseer := MinionCardData.new()
	imp_overseer.id          = "imp_overseer"
	imp_overseer.card_name   = "Imp Overseer"
	imp_overseer.description = "Passive: all friendly Void Imps have Taunt."
	imp_overseer.essence_cost = 3
	imp_overseer.atk         = 200
	imp_overseer.health      = 500
	imp_overseer.minion_type = Enums.MinionType.DEMON
	imp_overseer.minion_tags       = ["imp_overseer"]
	imp_overseer.passive_effect_id = "void_imp_taunt_aura"
	imp_overseer.on_summon_effect  = "grant_taunt_to_void_imps"
	imp_overseer.on_death_effect   = "remove_taunt_from_void_imps"
	imp_overseer.faction     = "abyss_order"
	_register(imp_overseer)

	# Traps
	var dark_nursery := TrapCardData.new()
	dark_nursery.id          = "dark_nursery"
	dark_nursery.card_name   = "Dark Nursery"
	dark_nursery.cost        = 2
	dark_nursery.description = "Trap: when a friendly minion dies during the enemy's turn, summon a Void Imp."
	dark_nursery.trigger     = Enums.TriggerEvent.ON_PLAYER_MINION_DIED
	dark_nursery.effect_id   = "dark_nursery_effect"
	dark_nursery.faction     = "abyss_order"
	_register(dark_nursery)

	var imp_barricade := TrapCardData.new()
	imp_barricade.id          = "imp_barricade"
	imp_barricade.card_name   = "Imp Barricade"
	imp_barricade.cost        = 1
	imp_barricade.description = "Trap: when an enemy minion attacks, summon a Void Imp and redirect that attack to it."
	imp_barricade.trigger     = Enums.TriggerEvent.ON_ENEMY_ATTACK
	imp_barricade.effect_id   = "imp_barricade_effect"
	imp_barricade.faction     = "abyss_order"
	_register(imp_barricade)

	# Environment
	var imp_hatchery := EnvironmentCardData.new()
	imp_hatchery.id                  = "imp_hatchery"
	imp_hatchery.card_name           = "Imp Hatchery"
	imp_hatchery.cost                = 3
	imp_hatchery.description         = "Environment: at the start of your turn, if you control fewer than 2 Void Imps, summon one."
	imp_hatchery.passive_description = "At the start of your turn, if you control fewer than 2 Void Imps, summon one."
	imp_hatchery.passive_effect_id   = "imp_hatchery_passive"
	imp_hatchery.faction             = "abyss_order"
	_register(imp_hatchery)

	# ---------------------------------------------------------------------------
	# --- Runes (Abyss Order — Trap subtype, persistent, face-up) ---
	# ---------------------------------------------------------------------------

	var void_rune := TrapCardData.new()
	void_rune.id            = "void_rune"
	void_rune.card_name     = "Void Rune"
	void_rune.cost          = 2
	void_rune.description   = "Rune: At the start of your turn, deal 100 Void Bolt damage to the enemy hero."
	void_rune.is_rune       = true
	void_rune.rune_type     = Enums.RuneType.VOID_RUNE
	void_rune.aura_effect_id = "void_rune_aura"
	void_rune.faction       = "abyss_order"
	_register(void_rune)

	var blood_rune := TrapCardData.new()
	blood_rune.id            = "blood_rune"
	blood_rune.card_name     = "Blood Rune"
	blood_rune.cost          = 2
	blood_rune.description   = "Rune: Whenever a friendly minion dies, restore 100 HP to your hero."
	blood_rune.is_rune       = true
	blood_rune.rune_type     = Enums.RuneType.BLOOD_RUNE
	blood_rune.aura_effect_id = "blood_rune_aura"
	blood_rune.faction       = "abyss_order"
	_register(blood_rune)

	var dominion_rune := TrapCardData.new()
	dominion_rune.id            = "dominion_rune"
	dominion_rune.card_name     = "Dominion Rune"
	dominion_rune.cost          = 1
	dominion_rune.description   = "Rune: All friendly Demons have +100 ATK."
	dominion_rune.is_rune       = true
	dominion_rune.rune_type     = Enums.RuneType.DOMINION_RUNE
	dominion_rune.aura_effect_id = "dominion_rune_aura"
	dominion_rune.faction       = "abyss_order"
	_register(dominion_rune)

	var shadow_rune := TrapCardData.new()
	shadow_rune.id            = "shadow_rune"
	shadow_rune.card_name     = "Shadow Rune"
	shadow_rune.cost          = 1
	shadow_rune.description   = "Rune: Enemy minions enter the board with 1 stack of Corruption."
	shadow_rune.is_rune       = true
	shadow_rune.rune_type     = Enums.RuneType.SHADOW_RUNE
	shadow_rune.aura_effect_id = "shadow_rune_aura"
	shadow_rune.faction       = "abyss_order"
	_register(shadow_rune)

	# ---------------------------------------------------------------------------
	# --- Ritual token (Special Summoned by ritual effects, not in any deck) ---
	# ---------------------------------------------------------------------------

	var ritual_demon := MinionCardData.new()
	ritual_demon.id           = "ritual_demon"
	ritual_demon.card_name    = "Demon Ascendant"
	ritual_demon.essence_cost = 0
	ritual_demon.description  = "Special Summoned by the Demon Ascendant ritual."
	ritual_demon.atk          = 500
	ritual_demon.health       = 500
	ritual_demon.minion_type  = Enums.MinionType.DEMON
	ritual_demon.faction      = "abyss_order"
	_register(ritual_demon)

	# ---------------------------------------------------------------------------
	# --- Ritual Environments (Abyss Order — core set) ---
	# ---------------------------------------------------------------------------

	var blood_dominion_ritual := RitualData.new()
	blood_dominion_ritual.ritual_name   = "Demon Ascendant"
	blood_dominion_ritual.description   = "Consume Blood + Dominion Runes. Deal 200 damage to 2 random enemy minions. Special Summon a 500/500 Demon."
	blood_dominion_ritual.required_runes = [Enums.RuneType.BLOOD_RUNE, Enums.RuneType.DOMINION_RUNE]
	blood_dominion_ritual.effect_id      = "demon_ascendant"

	var abyssal_summoning_circle := EnvironmentCardData.new()
	abyssal_summoning_circle.id                          = "abyssal_summoning_circle"
	abyssal_summoning_circle.card_name                   = "Abyssal Summoning Circle"
	abyssal_summoning_circle.cost                        = 3
	abyssal_summoning_circle.description                 = "Whenever a friendly minion dies, deal 100 damage to the enemy hero. Ritual: Blood + Dominion → Demon Ascendant."
	abyssal_summoning_circle.passive_description         = "Whenever a friendly minion dies, deal 100 damage to the enemy hero."
	abyssal_summoning_circle.passive_effect_id           = "abyssal_summoning_circle_passive"
	abyssal_summoning_circle.on_player_minion_died_effect_id = "abyssal_summoning_circle_death"
	abyssal_summoning_circle.rituals                     = [blood_dominion_ritual]
	abyssal_summoning_circle.faction                     = "abyss_order"
	_register(abyssal_summoning_circle)

	# ---------------------------------------------------------------------------
	# --- Ritual Environments (Abyss Order — Piercing Void support pool) ---
	# ---------------------------------------------------------------------------

	var void_blood_ritual := RitualData.new()
	void_blood_ritual.ritual_name   = "Soul Cataclysm"
	void_blood_ritual.description   = "Consume Void + Blood Runes. Deal 400 Void Bolt damage to the enemy hero. Restore 400 HP to your hero."
	void_blood_ritual.required_runes = [Enums.RuneType.VOID_RUNE, Enums.RuneType.BLOOD_RUNE]
	void_blood_ritual.effect_id      = "soul_cataclysm"

	var abyss_ritual_circle := EnvironmentCardData.new()
	abyss_ritual_circle.id                  = "abyss_ritual_circle"
	abyss_ritual_circle.card_name           = "Abyss Ritual Circle"
	abyss_ritual_circle.cost                = 3
	abyss_ritual_circle.description         = "Each turn, deal 100 damage to a random minion (both sides). Ritual: Void + Blood → Soul Cataclysm."
	abyss_ritual_circle.passive_description = "At the start of each turn, deal 100 damage to a random minion on the battlefield."
	abyss_ritual_circle.passive_effect_id   = "abyss_ritual_circle_passive"
	abyss_ritual_circle.fires_on_enemy_turn = true
	abyss_ritual_circle.rituals             = [void_blood_ritual]
	abyss_ritual_circle.faction             = "abyss_order"
	_register(abyss_ritual_circle)
