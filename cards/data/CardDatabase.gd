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

# ---------------------------------------------------------------------------
# Token definitions — compact table for tokens summoned by card effects.
# Fields: id, name, atk, hp, type (Enums.MinionType key), faction, desc,
#         shield (optional, default 0), tags (optional), art (optional)
# ---------------------------------------------------------------------------
const _TOKEN_DEFS: Array[Dictionary] = [
	{"id": "void_spark", "name": "Void Spark", "atk": 100, "hp": 100, "type": "SPIRIT", "faction": "abyss_order", "desc": "A Spirit token.", "spark_value": 1, "art": "res://assets/art/minions/abyss_order/void_spark.png",  "battlefield_art": "res://assets/art/minions/abyss_order/void_spark_small.png"},
	{"id": "void_demon", "name": "Void Demon", "atk": 200, "hp": 200, "type": "DEMON",  "faction": "abyss_order", "desc": "Summoned by Void Summoning.", "art": "res://assets/art/minions/abyss_order/void_demon.png",  "battlefield_art": "res://assets/art/minions/abyss_order/void_demon_small.png"},
]

func _make_token(d: Dictionary) -> MinionCardData:
	var c := MinionCardData.new()
	c.id           = d["id"]
	c.card_name    = d["name"]
	c.essence_cost = 0
	c.atk          = d["atk"]
	c.health       = d["hp"]
	c.shield_max   = d.get("shield", 0)
	c.minion_type  = Enums.MinionType[d["type"]]
	c.faction      = d.get("faction", "")
	c.description  = d.get("desc", "")
	var tags: Array[String] = []
	tags.assign(d.get("tags", []))
	c.minion_tags  = tags
	c.spark_value  = d.get("spark_value", 0)
	c.art_path            = d.get("art", "")
	c.battlefield_art_path = d.get("battlefield_art", "")
	return c

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

## Returns card IDs whose pool field matches any value in the given list.
func get_card_ids_in_pools(pools: Array[String]) -> Array[String]:
	var ids: Array[String] = []
	for key in _cards.keys():
		var card: CardData = _cards[key]
		if card.pool in pools:
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
	var all: Array = []

	# --- Minions ---

	var void_imp := MinionCardData.new()
	void_imp.id             = "void_imp"
	void_imp.card_name      = "Void Imp"
	void_imp.essence_cost   = 1
	void_imp.description    = "ON PLAY: deal 100 damage to the enemy hero."
	void_imp.atk            = 100
	void_imp.health         = 100
	void_imp.minion_type    = Enums.MinionType.DEMON
	void_imp.on_play_effect_steps = [{"type": "DAMAGE_HERO", "amount": 100, "conditions": ["no_piercing_void"]}]
	void_imp.minion_tags    = ["void_imp", "base_void_imp"]
	void_imp.faction        = "abyss_order"
	void_imp.clan           = "Void Imp"
	void_imp.art_path             = "res://assets/art/minions/abyss_order/void_imp.png"
	void_imp.battlefield_art_path = "res://assets/art/minions/abyss_order/void_imp_small.png"
	all.append(void_imp)

	# Senior Void Imp — added to hand by Imp Evolution talent; counts as Void Imp
	var senior_void_imp := MinionCardData.new()
	senior_void_imp.id           = "senior_void_imp"
	senior_void_imp.card_name    = "Senior Void Imp"
	senior_void_imp.essence_cost = 2
	senior_void_imp.description  = "ON PLAY: deal 100 damage to the enemy hero."
	senior_void_imp.atk          = 300
	senior_void_imp.health       = 250
	senior_void_imp.minion_type  = Enums.MinionType.DEMON
	senior_void_imp.on_play_effect_steps = [{"type": "DAMAGE_HERO", "amount": 100, "conditions": ["no_piercing_void"]}]
	senior_void_imp.minion_tags          = ["void_imp", "senior_void_imp"]
	senior_void_imp.faction              = "abyss_order"
	senior_void_imp.clan                 = "Void Imp"
	senior_void_imp.art_path             = "res://assets/art/minions/abyss_order/senior_void_imp.png"
	senior_void_imp.battlefield_art_path = "res://assets/art/minions/abyss_order/senior_void_imp_small.png"
	all.append(senior_void_imp)

	# Runic Void Imp — variant core unit; offered via special reward
	var runic_void_imp := MinionCardData.new()
	runic_void_imp.id                    = "runic_void_imp"
	runic_void_imp.card_name             = "Runic Void Imp"
	runic_void_imp.essence_cost          = 2
	runic_void_imp.mana_cost             = 1
	runic_void_imp.description           = "ON PLAY: deal 300 damage to a selected enemy minion."
	runic_void_imp.atk                   = 200
	runic_void_imp.health                = 300
	runic_void_imp.minion_type           = Enums.MinionType.DEMON
	runic_void_imp.on_play_effect_steps  = [{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 300}]
	runic_void_imp.on_play_requires_target = true
	runic_void_imp.on_play_target_type   = "enemy_minion"
	runic_void_imp.minion_tags           = ["void_imp", "runic_void_imp"]
	runic_void_imp.faction               = "abyss_order"
	runic_void_imp.clan                  = "Void Imp"
	runic_void_imp.art_path              = "res://assets/art/minions/abyss_order/runic_void_imp.png"
	runic_void_imp.battlefield_art_path  = "res://assets/art/minions/abyss_order/runic_void_imp_small.png"
	all.append(runic_void_imp)

	# Void Imp Wizard — variant core unit; offered via special reward
	var void_imp_wizard := MinionCardData.new()
	void_imp_wizard.id           = "void_imp_wizard"
	void_imp_wizard.card_name    = "Void Imp Wizard"
	void_imp_wizard.essence_cost = 2
	void_imp_wizard.mana_cost    = 1
	void_imp_wizard.description  = "ON PLAY: deal 300 Void Bolt damage to the enemy hero and apply 1 VOID MARK."
	void_imp_wizard.atk          = 100
	void_imp_wizard.health       = 300
	void_imp_wizard.minion_type  = Enums.MinionType.DEMON
	void_imp_wizard.on_play_effect_steps = [
		{"type": "VOID_BOLT", "amount": 300},
		{"type": "VOID_MARK", "amount": 1},
	]
	void_imp_wizard.minion_tags  = ["void_imp", "void_imp_wizard"]
	void_imp_wizard.faction      = "abyss_order"
	void_imp_wizard.clan         = "Void Imp"
	void_imp_wizard.art_path             = "res://assets/art/minions/abyss_order/void_imp_wizard.png"
	void_imp_wizard.battlefield_art_path = "res://assets/art/minions/abyss_order/void_imp_wizard_small.png"
	all.append(void_imp_wizard)

	var shadow_hound := MinionCardData.new()
	shadow_hound.id             = "shadow_hound"
	shadow_hound.card_name      = "Shadow Hound"
	shadow_hound.essence_cost   = 2
	shadow_hound.description    = "ON PLAY: gains +100 ATK for each other Demon on your board."
	shadow_hound.atk            = 200
	shadow_hound.health         = 300
	shadow_hound.minion_type    = Enums.MinionType.DEMON
	shadow_hound.on_play_effect_steps = [{"type": "BUFF_ATK", "scope": "SELF", "amount": 100, "multiplier_key": "board_count", "multiplier_board": "friendly", "multiplier_filter": "race", "multiplier_tag": "demon", "exclude_self": true, "permanent": true}]
	shadow_hound.faction        = "abyss_order"
	shadow_hound.art_path             = "res://assets/art/minions/abyss_order/shadow_hound.png"
	shadow_hound.battlefield_art_path = "res://assets/art/minions/abyss_order/shwdow_hound_small.png"
	all.append(shadow_hound)

	var abyssal_brute := MinionCardData.new()
	abyssal_brute.id            = "abyssal_brute"
	abyssal_brute.card_name     = "Abyssal Brute"
	abyssal_brute.essence_cost  = 4
	abyssal_brute.description   = ""
	abyssal_brute.atk           = 300
	abyssal_brute.health        = 600
	abyssal_brute.minion_type   = Enums.MinionType.DEMON
	abyssal_brute.keywords.append(Enums.Keyword.GUARD)
	abyssal_brute.faction       = "abyss_order"
	abyssal_brute.art_path             = "res://assets/art/minions/abyss_order/abyssal_brute.png"
	abyssal_brute.battlefield_art_path = "res://assets/art/minions/abyss_order/abyssal_brute_small.png"
	all.append(abyssal_brute)

	# --- Spells ---

	var dark_empowerment := SpellCardData.new()
	dark_empowerment.id             = "dark_empowerment"
	dark_empowerment.card_name      = "Dark Empowerment"
	dark_empowerment.cost           = 1
	dark_empowerment.description    = "Give a friendly minion +150 ATK permanently. If it's a Demon, also give it +150 HP."
	dark_empowerment.requires_target = true
	dark_empowerment.target_type    = "friendly_minion"
	dark_empowerment.effect_steps = [
		{"type": "BUFF_ATK", "scope": "SINGLE_CHOSEN_FRIENDLY", "amount": 150, "permanent": true},
		{"type": "BUFF_HP",  "scope": "SINGLE_CHOSEN_FRIENDLY", "amount": 150, "conditions": ["is_demon"]},
	]
	dark_empowerment.faction        = "abyss_order"
	dark_empowerment.art_path       = "res://assets/art/spells/abyss_order/dark_empowerment.png"
	all.append(dark_empowerment)

	var abyssal_sacrifice := SpellCardData.new()
	abyssal_sacrifice.id             = "abyssal_sacrifice"
	abyssal_sacrifice.card_name      = "Abyssal Sacrifice"
	abyssal_sacrifice.cost           = 2
	abyssal_sacrifice.description    = "Destroy a friendly minion. Draw 2 cards."
	abyssal_sacrifice.requires_target = true
	abyssal_sacrifice.target_type    = "friendly_minion"

	abyssal_sacrifice.faction        = "abyss_order"
	abyssal_sacrifice.art_path       = "res://assets/art/spells/abyss_order/abyssal_sacrifice.png"
	abyssal_sacrifice.effect_steps = [
		{"type": "SACRIFICE", "scope": "SINGLE_CHOSEN_FRIENDLY"},
		{"type": "DRAW", "amount": 2},
	]
	all.append(abyssal_sacrifice)

	var abyssal_plague := SpellCardData.new()
	abyssal_plague.id          = "abyssal_plague"
	abyssal_plague.card_name   = "Abyssal Plague"
	abyssal_plague.cost        = 2
	abyssal_plague.description = "Apply 1 CORRUPTION to all enemy minions. Deal 100 damage to all enemy minions."
	abyssal_plague.effect_steps = [
		{"type": "CORRUPTION",    "scope": "ALL_ENEMY", "amount": 1},
		{"type": "DAMAGE_MINION", "scope": "ALL_ENEMY", "amount": 100},
	]
	abyssal_plague.faction     = "abyss_order"
	abyssal_plague.art_path    = "res://assets/art/spells/abyss_order/abyssal_plague.png"
	all.append(abyssal_plague)

	var void_summoning := SpellCardData.new()
	void_summoning.id          = "void_summoning"
	void_summoning.card_name   = "Void Summoning"
	void_summoning.cost        = 2
	void_summoning.description = "Summon a 300/300 Demon. If you control any Human, summon a 400/400 Demon instead."
	void_summoning.effect_steps = [
		{"type": "SUMMON", "card_id": "void_demon", "conditions": ["not_has_friendly_human"], "token_atk": 300, "token_hp": 300},
		{"type": "SUMMON", "card_id": "void_demon", "conditions": ["has_friendly_human"],     "token_atk": 400, "token_hp": 400},
	]
	void_summoning.faction     = "abyss_order"
	void_summoning.art_path    = "res://assets/art/spells/abyss_order/void_summoning.png"
	all.append(void_summoning)

	var void_execution := SpellCardData.new()
	void_execution.id             = "void_execution"
	void_execution.card_name      = "Void Execution"
	void_execution.cost           = 3
	void_execution.description    = "Deal 500 damage to a target enemy. If you control any Human, deal 700 instead."
	void_execution.requires_target = true
	void_execution.target_type    = "enemy_minion_or_hero"
	void_execution.effect_steps = [
		{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 500, "bonus_amount": 200, "bonus_conditions": ["has_friendly_human"]},
	]
	void_execution.faction        = "abyss_order"
	void_execution.art_path       = "res://assets/art/spells/abyss_order/void_execution.png"
	all.append(void_execution)

	var flux_siphon := SpellCardData.new()
	flux_siphon.id          = "flux_siphon"
	flux_siphon.card_name   = "Flux Siphon"
	flux_siphon.cost        = 0
	flux_siphon.description = "Convert up to 3 of your remaining Mana into Essence."
	flux_siphon.effect_steps = [{"type": "CONVERT_RESOURCE", "convert_from": "mana", "convert_to": "essence", "amount": 3}]
	flux_siphon.faction     = "neutral"
	flux_siphon.art_path    = "res://assets/art/spells/neutral/flux_siphon.png"
	all.append(flux_siphon)

	# ---------------------------------------------------------------------------
	# --- Neutral Core Set ---
	# ---------------------------------------------------------------------------

	# 1-cost
	var roadside_drifter := MinionCardData.new()
	roadside_drifter.id          = "roadside_drifter"
	roadside_drifter.card_name   = "Roadside Drifter"
	roadside_drifter.essence_cost = 1
	roadside_drifter.atk         = 100
	roadside_drifter.health      = 300
	roadside_drifter.minion_type = Enums.MinionType.HUMAN
	roadside_drifter.faction  = "neutral"
	roadside_drifter.art_path = "res://assets/art/minions/neutral/roadside_drifter.png"
	all.append(roadside_drifter)

	var ashland_forager := MinionCardData.new()
	ashland_forager.id          = "ashland_forager"
	ashland_forager.card_name   = "Ashland Forager"
	ashland_forager.essence_cost = 1
	ashland_forager.atk         = 200
	ashland_forager.health      = 200
	ashland_forager.minion_type = Enums.MinionType.BEAST
	ashland_forager.faction  = "neutral"
	ashland_forager.art_path = "res://assets/art/minions/neutral/ashland_forager.png"
	all.append(ashland_forager)

	# 2-cost
	var freelance_sellsword := MinionCardData.new()
	freelance_sellsword.id          = "freelance_sellsword"
	freelance_sellsword.card_name   = "Freelance Sellsword"
	freelance_sellsword.essence_cost = 2
	freelance_sellsword.atk         = 300
	freelance_sellsword.health      = 200
	freelance_sellsword.minion_type = Enums.MinionType.MERCENARY
	freelance_sellsword.faction  = "neutral"
	freelance_sellsword.art_path = "res://assets/art/minions/neutral/freelance_sellsword.png"
	all.append(freelance_sellsword)

	var traveling_merchant := MinionCardData.new()
	traveling_merchant.id             = "traveling_merchant"
	traveling_merchant.card_name      = "Traveling Merchant"
	traveling_merchant.description    = "ON PLAY: draw a card."
	traveling_merchant.essence_cost   = 2
	traveling_merchant.atk            = 100
	traveling_merchant.health         = 100
	traveling_merchant.minion_type    = Enums.MinionType.HUMAN
	traveling_merchant.on_play_effect_steps = [{"type": "DRAW", "amount": 1}]
	traveling_merchant.faction  = "neutral"
	traveling_merchant.art_path = "res://assets/art/minions/neutral/traveling_merchant.png"
	all.append(traveling_merchant)

	var trapbreaker_rogue := MinionCardData.new()
	trapbreaker_rogue.id             = "trapbreaker_rogue"
	trapbreaker_rogue.card_name      = "Trapbreaker Rogue"
	trapbreaker_rogue.description    = "ON PLAY: destroy a random enemy trap."
	trapbreaker_rogue.essence_cost   = 2
	trapbreaker_rogue.atk            = 250
	trapbreaker_rogue.health         = 200
	trapbreaker_rogue.minion_type    = Enums.MinionType.HUMAN
	trapbreaker_rogue.on_play_effect_steps = [{"type": "HARDCODED", "hardcoded_id": "destroy_random_enemy_trap"}]
	trapbreaker_rogue.faction  = "neutral"
	trapbreaker_rogue.art_path = "res://assets/art/minions/neutral/trapbreaker_rogue.png"
	all.append(trapbreaker_rogue)

	# 3-cost
	var caravan_guard := MinionCardData.new()
	caravan_guard.id          = "caravan_guard"
	caravan_guard.card_name   = "Caravan Guard"
	caravan_guard.essence_cost = 3
	caravan_guard.atk         = 350
	caravan_guard.health      = 350
	caravan_guard.minion_type = Enums.MinionType.MERCENARY
	caravan_guard.faction  = "neutral"
	caravan_guard.art_path = "res://assets/art/minions/neutral/caravan_guard.png"
	all.append(caravan_guard)

	var arena_challenger := MinionCardData.new()
	arena_challenger.id          = "arena_challenger"
	arena_challenger.card_name   = "Arena Challenger"
	arena_challenger.essence_cost = 3
	arena_challenger.atk         = 450
	arena_challenger.health      = 200
	arena_challenger.minion_type = Enums.MinionType.MERCENARY
	arena_challenger.faction   = "neutral"
	arena_challenger.art_path  = "res://assets/art/minions/neutral/arena_challenger.png"
	all.append(arena_challenger)

	var spell_taxer := MinionCardData.new()
	spell_taxer.id             = "spell_taxer"
	spell_taxer.card_name      = "Spell Taxer"
	spell_taxer.description    = "ON PLAY: enemy spells cost +1 Mana next turn."
	spell_taxer.essence_cost   = 3
	spell_taxer.atk            = 250
	spell_taxer.health         = 300
	spell_taxer.minion_type    = Enums.MinionType.HUMAN
	spell_taxer.on_play_effect_steps = [{"type": "HARDCODED", "hardcoded_id": "spell_taxer_effect"}]
	spell_taxer.faction        = "neutral"
	spell_taxer.art_path       = "res://assets/art/minions/neutral/spell_taxer.png"
	all.append(spell_taxer)

	var saboteur_adept := MinionCardData.new()
	saboteur_adept.id             = "saboteur_adept"
	saboteur_adept.card_name      = "Saboteur Adept"
	saboteur_adept.description    = "ON PLAY: enemy traps cannot trigger this turn."
	saboteur_adept.essence_cost   = 3
	saboteur_adept.atk            = 300
	saboteur_adept.health         = 300
	saboteur_adept.minion_type    = Enums.MinionType.HUMAN
	saboteur_adept.on_play_effect_steps = [{"type": "HARDCODED", "hardcoded_id": "saboteur_adept_effect"}]
	saboteur_adept.faction        = "neutral"
	saboteur_adept.art_path       = "res://assets/art/minions/neutral/sabateur_adept.png"
	all.append(saboteur_adept)

	var aether_bulwark := MinionCardData.new()
	aether_bulwark.id          = "aether_bulwark"
	aether_bulwark.card_name   = "Aether Bulwark"
	aether_bulwark.description = "PASSIVE: Magic Shield 300 (Shield Regen I)."
	aether_bulwark.essence_cost = 3
	aether_bulwark.mana_cost   = 2
	aether_bulwark.atk         = 300
	aether_bulwark.health      = 400
	aether_bulwark.shield_max  = 300
	aether_bulwark.minion_type = Enums.MinionType.CONSTRUCT
	aether_bulwark.keywords.append(Enums.Keyword.SHIELD_REGEN_1)
	aether_bulwark.faction     = "neutral"
	aether_bulwark.art_path    = "res://assets/art/minions/neutral/aether_bulwark.png"
	all.append(aether_bulwark)

	# 4-cost
	var bulwark_automaton := MinionCardData.new()
	bulwark_automaton.id          = "bulwark_automaton"
	bulwark_automaton.card_name   = "Bulwark Automaton"
	bulwark_automaton.description = "DEATHLESS."
	bulwark_automaton.essence_cost = 4
	bulwark_automaton.atk         = 300
	bulwark_automaton.health      = 500
	bulwark_automaton.minion_type = Enums.MinionType.CONSTRUCT
	bulwark_automaton.keywords    = [Enums.Keyword.DEATHLESS]
	bulwark_automaton.faction     = "neutral"
	bulwark_automaton.art_path    = "res://assets/art/minions/neutral/bulwark_automaton.png"
	all.append(bulwark_automaton)

	var wandering_warden := MinionCardData.new()
	wandering_warden.id          = "wandering_warden"
	wandering_warden.card_name   = "Wandering Warden"
	wandering_warden.description = "PASSIVE: Magic Shield 300 (Shield Regen I)."
	wandering_warden.essence_cost = 4
	wandering_warden.mana_cost   = 1
	wandering_warden.atk         = 300
	wandering_warden.health      = 400
	wandering_warden.shield_max  = 300
	wandering_warden.minion_type = Enums.MinionType.MERCENARY
	wandering_warden.keywords.append(Enums.Keyword.SHIELD_REGEN_1)
	wandering_warden.faction     = "neutral"
	wandering_warden.art_path    = "res://assets/art/minions/neutral/wandering_warden.png"
	all.append(wandering_warden)

	# 5-cost
	var ruins_archivist := MinionCardData.new()
	ruins_archivist.id             = "ruins_archivist"
	ruins_archivist.card_name      = "Ruins Archivist"
	ruins_archivist.description    = "ON PLAY: draw a card."
	ruins_archivist.essence_cost   = 5
	ruins_archivist.atk            = 450
	ruins_archivist.health         = 500
	ruins_archivist.minion_type    = Enums.MinionType.MERCENARY
	ruins_archivist.on_play_effect_steps = [{"type": "DRAW", "amount": 1}]
	ruins_archivist.faction        = "neutral"
	ruins_archivist.art_path       = "res://assets/art/minions/neutral/ruins_archivist.png"
	all.append(ruins_archivist)

	# 6–8 cost (big threats)
	var wildland_behemoth := MinionCardData.new()
	wildland_behemoth.id          = "wildland_behemoth"
	wildland_behemoth.card_name   = "Wildland Behemoth"
	wildland_behemoth.essence_cost = 6
	wildland_behemoth.atk         = 700
	wildland_behemoth.health      = 600
	wildland_behemoth.minion_type = Enums.MinionType.BEAST
	wildland_behemoth.faction     = "neutral"
	wildland_behemoth.art_path    = "res://assets/art/minions/neutral/wildland_behemoth.png"
	all.append(wildland_behemoth)

	var stone_sentinel := MinionCardData.new()
	stone_sentinel.id          = "stone_sentinel"
	stone_sentinel.card_name   = "Stone Sentinel"
	stone_sentinel.essence_cost = 7
	stone_sentinel.atk         = 900
	stone_sentinel.health      = 600
	stone_sentinel.minion_type = Enums.MinionType.MERCENARY
	stone_sentinel.faction     = "neutral"
	stone_sentinel.art_path    = "res://assets/art/minions/neutral/stone_sentinel.png"
	all.append(stone_sentinel)

	var rift_leviathan := MinionCardData.new()
	rift_leviathan.id          = "rift_leviathan"
	rift_leviathan.card_name   = "Rift Leviathan"
	rift_leviathan.essence_cost = 8
	rift_leviathan.atk         = 1000
	rift_leviathan.health      = 700
	rift_leviathan.minion_type = Enums.MinionType.BEAST
	rift_leviathan.faction     = "neutral"
	rift_leviathan.art_path    = "res://assets/art/minions/neutral/rift_leviathan.png"
	all.append(rift_leviathan)


	# --- Neutral Core Spells ---

	var energy_conversion := SpellCardData.new()
	energy_conversion.id          = "energy_conversion"
	energy_conversion.card_name   = "Energy Conversion"
	energy_conversion.cost        = 0
	energy_conversion.description = "Convert up to 3 of your remaining Essence into Mana."
	energy_conversion.faction      = "neutral"
	energy_conversion.art_path     = "res://assets/art/spells/neutral/energy_conversion.png"
	energy_conversion.effect_steps = [{"type": "CONVERT_RESOURCE", "convert_from": "essence", "convert_to": "mana"}]
	all.append(energy_conversion)

	var arcane_strike := SpellCardData.new()
	arcane_strike.id              = "arcane_strike"
	arcane_strike.card_name       = "Arcane Strike"
	arcane_strike.cost            = 1
	arcane_strike.description     = "Deal 300 damage to a target minion."
	arcane_strike.requires_target = true
	arcane_strike.target_type     = "any_minion"

	arcane_strike.faction         = "neutral"
	arcane_strike.art_path        = "res://assets/art/spells/neutral/arcane_strike.png"
	arcane_strike.effect_steps    = [{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 300}]
	all.append(arcane_strike)

	var purge := SpellCardData.new()
	purge.id              = "purge"
	purge.card_name       = "Purge"
	purge.cost            = 1
	purge.description     = "Remove all runtime effects from a target minion."
	purge.requires_target = true
	purge.target_type     = "any_minion"
	purge.faction         = "neutral"
	purge.art_path        = "res://assets/art/spells/neutral/purge.png"
	purge.effect_steps    = [{"type": "PURGE", "scope": "SINGLE_CHOSEN"}]
	all.append(purge)

	var cyclone := SpellCardData.new()
	cyclone.id          = "cyclone"
	cyclone.card_name   = "Cyclone"
	cyclone.cost        = 1
	cyclone.description    = "Destroy a target active Trap or the active Environment."
	cyclone.requires_target = true
	cyclone.target_type     = "trap_or_env"
	cyclone.effect_steps    = [{"type": "DESTROY", "scope": "SINGLE_CHOSEN_TRAP_OR_ENV"}]
	cyclone.faction         = "neutral"
	cyclone.art_path        = "res://assets/art/spells/neutral/cyclone.png"
	all.append(cyclone)

	var tactical_planning := SpellCardData.new()
	tactical_planning.id          = "tactical_planning"
	tactical_planning.card_name   = "Tactical Planning"
	tactical_planning.cost        = 1
	tactical_planning.description = "Draw a card."

	tactical_planning.faction      = "neutral"
	tactical_planning.art_path     = "res://assets/art/spells/neutral/tactical_planning.png"
	tactical_planning.effect_steps = [{"type": "DRAW", "amount": 1}]
	all.append(tactical_planning)

	var precision_strike := SpellCardData.new()
	precision_strike.id              = "precision_strike"
	precision_strike.card_name       = "Precision Strike"
	precision_strike.cost            = 3
	precision_strike.description     = "Deal 600 damage to a target minion."
	precision_strike.requires_target = true
	precision_strike.target_type     = "any_minion"

	precision_strike.faction         = "neutral"
	precision_strike.art_path        = "res://assets/art/spells/neutral/precision_strike.png"
	precision_strike.effect_steps    = [{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 600}]
	all.append(precision_strike)

	var hurricane := SpellCardData.new()
	hurricane.id          = "hurricane"
	hurricane.card_name   = "Hurricane"
	hurricane.cost        = 3
	hurricane.description = "Destroy all Traps and the active Environment on the battlefield, including your own."

	hurricane.faction        = "neutral"
	hurricane.art_path       = "res://assets/art/spells/neutral/hurricane.png"
	hurricane.effect_steps   = [
		{"type": "DESTROY", "scope": "ALL_TRAPS"},
		{"type": "DESTROY", "scope": "ACTIVE_ENVIRONMENT"},
	]
	all.append(hurricane)


	# --- Traps: Runes only (normal traps removed) ---

	# --- Environments ---

	var dark_covenant := EnvironmentCardData.new()
	dark_covenant.id                    = "dark_covenant"
	dark_covenant.card_name             = "Dark Covenant"
	dark_covenant.cost                  = 2
	dark_covenant.description           = "While any friendly Human is on your board, your Demons have +100 ATK.\nWhile any friendly Demon is on your board, your Humans have +100 HP."
	dark_covenant.passive_description   = "Demons have +100 ATK while a Human is present. Humans restore 100 HP each turn while a Demon is present."
	dark_covenant.passive_effect_steps  = [{"type": "HARDCODED", "hardcoded_id": "dark_covenant_passive"}]
	dark_covenant.on_replace_effect_steps = [{"type": "HARDCODED", "hardcoded_id": "dark_covenant_remove"}]
	dark_covenant.faction               = "abyss_order"
	dark_covenant.art_path              = "res://assets/art/environments/abyss_order/dark_convenant.png"
	all.append(dark_covenant)

	# -----------------------------------------------------------------------
	# Abyss Order — core card set
	# -----------------------------------------------------------------------

	# --- Corruption synergy minions ---

	var abyss_cultist := MinionCardData.new()
	abyss_cultist.id             = "abyss_cultist"
	abyss_cultist.card_name      = "Abyss Cultist"
	abyss_cultist.essence_cost   = 1
	abyss_cultist.description    = "ON PLAY: CORRUPT a random enemy minion, apply 1 stack of CORRUPTION to it."
	abyss_cultist.atk            = 100
	abyss_cultist.health         = 300
	abyss_cultist.minion_type    = Enums.MinionType.HUMAN
	abyss_cultist.on_play_effect_steps = [{"type": "CORRUPTION", "scope": "SINGLE_RANDOM", "amount": 1}]
	abyss_cultist.faction        = "abyss_order"
	abyss_cultist.art_path             = "res://assets/art/minions/abyss_order/abyss_cultist.png"
	abyss_cultist.battlefield_art_path = "res://assets/art/minions/abyss_order/abyss_cultist_small.png"
	all.append(abyss_cultist)

	var void_netter := MinionCardData.new()
	void_netter.id             = "void_netter"
	void_netter.card_name      = "Void Netter"
	void_netter.essence_cost   = 2
	void_netter.description             = "ON PLAY: deal 200 damage to a target enemy minion."
	void_netter.atk                     = 100
	void_netter.health                  = 300
	void_netter.minion_type             = Enums.MinionType.HUMAN
	void_netter.on_play_effect_steps    = [{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 200}]
	void_netter.on_play_requires_target = true
	void_netter.on_play_target_type     = "enemy_minion"
	void_netter.faction        = "abyss_order"
	void_netter.art_path             = "res://assets/art/minions/abyss_order/void_netter.png"
	void_netter.battlefield_art_path = "res://assets/art/minions/abyss_order/void_netter_small.png"
	all.append(void_netter)

	var corruption_weaver := MinionCardData.new()
	corruption_weaver.id             = "corruption_weaver"
	corruption_weaver.card_name      = "Corruption Weaver"
	corruption_weaver.essence_cost   = 3
	corruption_weaver.description    = "ON PLAY: CORRUPT all enemy minions, apply 1 stack of CORRUPTION to them"
	corruption_weaver.atk            = 100
	corruption_weaver.health         = 400
	corruption_weaver.minion_type    = Enums.MinionType.HUMAN
	corruption_weaver.on_play_effect_steps = [{"type": "CORRUPTION", "scope": "ALL_ENEMY", "amount": 1}]
	corruption_weaver.faction        = "abyss_order"
	corruption_weaver.art_path             = "res://assets/art/minions/abyss_order/corruption_weaver.png"
	corruption_weaver.battlefield_art_path = "res://assets/art/minions/abyss_order/corruption_weaver_small.png"
	all.append(corruption_weaver)

	var soul_collector := MinionCardData.new()
	soul_collector.id             = "soul_collector"
	soul_collector.card_name      = "Soul Collector"
	soul_collector.essence_cost   = 5
	soul_collector.description             = "ON PLAY: instantly kill a target Corrupted enemy minion."
	soul_collector.atk                     = 300
	soul_collector.health                  = 700
	soul_collector.minion_type             = Enums.MinionType.HUMAN
	soul_collector.on_play_effect_steps    = [{"type": "DESTROY", "scope": "SINGLE_CHOSEN", "filter": "CORRUPTED"}]
	soul_collector.on_play_requires_target = true
	soul_collector.on_play_target_type     = "corrupted_enemy_minion"
	soul_collector.faction        = "abyss_order"
	soul_collector.art_path             = "res://assets/art/minions/abyss_order/soul_collector.png"
	soul_collector.battlefield_art_path = "res://assets/art/minions/abyss_order/soul_collector_small.png"
	all.append(soul_collector)

	# --- Swift / aggressive ---

	var void_stalker := MinionCardData.new()
	void_stalker.id           = "void_stalker"
	void_stalker.card_name    = "Void Stalker"
	void_stalker.essence_cost = 3
	void_stalker.description  = ""
	void_stalker.atk          = 300
	void_stalker.health       = 200
	void_stalker.minion_type  = Enums.MinionType.DEMON
	void_stalker.keywords.append(Enums.Keyword.SWIFT)
	void_stalker.keywords.append(Enums.Keyword.LIFEDRAIN)
	void_stalker.faction      = "abyss_order"
	void_stalker.art_path             = "res://assets/art/minions/abyss_order/void_stalker.png"
	void_stalker.battlefield_art_path = "res://assets/art/minions/abyss_order/void_stalker_small.png"
	all.append(void_stalker)

	# --- Board-wide passive payoffs ---

	var void_spawner := MinionCardData.new()
	void_spawner.id           = "void_spawner"
	void_spawner.card_name    = "Void Spawner"
	void_spawner.essence_cost = 4
	void_spawner.description  = "PASSIVE: whenever a friendly demon dies, summon a 100/100 Void Spark."
	void_spawner.atk          = 200
	void_spawner.health       = 600
	void_spawner.minion_type  = Enums.MinionType.DEMON
	void_spawner.passive_effect_id = "void_spark_on_friendly_death"
	void_spawner.faction      = "abyss_order"
	void_spawner.art_path             = "res://assets/art/minions/abyss_order/void_spawner.png"
	void_spawner.battlefield_art_path = "res://assets/art/minions/abyss_order/void_spawner_small.png"
	all.append(void_spawner)

	var abyssal_tide := MinionCardData.new()
	abyssal_tide.id           = "abyssal_tide"
	abyssal_tide.card_name    = "Abyssal Tide"
	abyssal_tide.essence_cost = 5
	abyssal_tide.description  = "PASSIVE: whenever a friendly minion dies, deal 200 damage to the enemy hero."
	abyssal_tide.atk          = 400
	abyssal_tide.health       = 400
	abyssal_tide.minion_type  = Enums.MinionType.DEMON
	abyssal_tide.passive_effect_id = "deal_200_hero_on_friendly_death"
	abyssal_tide.faction      = "abyss_order"
	abyssal_tide.art_path             = "res://assets/art/minions/abyss_order/abyssal_tide.png"
	abyssal_tide.battlefield_art_path = "res://assets/art/minions/abyss_order/abyssal_tide_small.png"
	all.append(abyssal_tide)

	# --- Sacrifice finisher ---

	var void_devourer := MinionCardData.new()
	void_devourer.id             = "void_devourer"
	void_devourer.card_name      = "Void Devourer"
	void_devourer.essence_cost   = 6
	void_devourer.description    = "ON PLAY: sacrifice adjacent friendly minions. Gains +300 ATK and +300 HP per sacrificed."
	void_devourer.atk            = 200
	void_devourer.health         = 600
	void_devourer.minion_type    = Enums.MinionType.DEMON
	void_devourer.keywords.append(Enums.Keyword.GUARD)
	void_devourer.on_play_effect_steps = [{"type": "HARDCODED", "hardcoded_id": "void_devourer_sacrifice"}]
	void_devourer.faction        = "abyss_order"
	void_devourer.art_path             = "res://assets/art/minions/abyss_order/void_devourer.png"
	void_devourer.battlefield_art_path = "res://assets/art/minions/abyss_order/void_devourer_small.png"
	all.append(void_devourer)

	# --- Champion (max 1 copy, auto-summoned when 3 Void Imps are on board) ---

	var nyx_ael := MinionCardData.new()
	nyx_ael.id           = "nyx_ael"
	nyx_ael.card_name    = "Nyx'ael, Void Sovereign"
	nyx_ael.essence_cost = 5
	nyx_ael.description  = "CHAMPION: Summoned when 3 VOID IMP CLAN minions are on the battlefield. \nPASSIVE: At the start of your turn, deal 200 damage to all enemy minions."
	nyx_ael.atk          = 500
	nyx_ael.health       = 500
	nyx_ael.minion_type  = Enums.MinionType.DEMON
	nyx_ael.keywords.append(Enums.Keyword.CHAMPION)
	nyx_ael.minion_tags           = ["void_imp"]
	nyx_ael.is_champion           = true
	nyx_ael.auto_summon_condition = "board_tag_count"
	nyx_ael.auto_summon_tag       = "void_imp"
	nyx_ael.auto_summon_threshold = 3
	nyx_ael.on_turn_start_effect_steps = [{"type": "DAMAGE_MINION", "scope": "ALL_ENEMY", "amount": 200}]
	nyx_ael.faction      = "abyss_order"
	nyx_ael.clan         = "Void Imp"
	nyx_ael.art_path             = "res://assets/art/minions/abyss_order/nyx_ael.png"
	nyx_ael.battlefield_art_path = "res://assets/art/minions/abyss_order/nyx_ael_small.png"
	all.append(nyx_ael)

	# --- Tokens (not in player deck, summoned by effects) ---
	# Defined compactly via _TOKEN_DEFS at the bottom of this file; appended there.

	# --- Void Bolt card ecosystem (Mana-cost, Lord Vael void_bolt branch) ---

	var void_bolt_spell := SpellCardData.new()
	void_bolt_spell.id             = "void_bolt"
	void_bolt_spell.card_name      = "Void Bolt"
	void_bolt_spell.cost           = 2
	void_bolt_spell.description    = "Deal 500 Void Bolt damage to the enemy hero."
	void_bolt_spell.effect_steps = [
		{"type": "VOID_BOLT", "amount": 500},
		{"type": "VOID_MARK", "amount": 1, "conditions": ["has_piercing_void"]},
	]
	void_bolt_spell.requires_target = false
	void_bolt_spell.faction         = "abyss_order"
	void_bolt_spell.art_path        = "res://assets/art/spells/abyss_order/void_bolt.png"
	all.append(void_bolt_spell)

	# --- Neutral Traps ---

	var hidden_ambush := TrapCardData.new()
	hidden_ambush.id           = "hidden_ambush"
	hidden_ambush.card_name    = "Hidden Ambush"
	hidden_ambush.cost         = 1
	hidden_ambush.description  = "Trap: When an enemy minion attacks, deal 400 damage to that minion."
	hidden_ambush.trigger      = Enums.TriggerEvent.ON_ENEMY_ATTACK
	hidden_ambush.effect_steps = [{"type": "DAMAGE_MINION", "scope": "TRIGGER_MINION", "amount": 400}]
	hidden_ambush.art_path     = "res://assets/art/traps/neutral/hidden_ambush.png"
	hidden_ambush.faction      = "neutral"
	all.append(hidden_ambush)

	var smoke_veil := TrapCardData.new()
	smoke_veil.id           = "smoke_veil"
	smoke_veil.card_name    = "Smoke Veil"
	smoke_veil.cost         = 2
	smoke_veil.description  = "Trap: When an enemy minion attacks, cancel that attack and exhaust all enemy minions."
	smoke_veil.trigger      = Enums.TriggerEvent.ON_ENEMY_ATTACK
	smoke_veil.effect_steps = [{"type": "HARDCODED", "hardcoded_id": "smoke_veil"}]
	smoke_veil.art_path     = "res://assets/art/traps/neutral/smoke_veil.png"
	smoke_veil.faction      = "neutral"
	all.append(smoke_veil)

	var silence_trap := TrapCardData.new()
	silence_trap.id           = "silence_trap"
	silence_trap.card_name    = "Silence Trap"
	silence_trap.cost         = 2
	silence_trap.description  = "Trap: When the enemy casts a spell, cancel that spell entirely."
	silence_trap.trigger      = Enums.TriggerEvent.ON_ENEMY_SPELL_CAST
	silence_trap.effect_steps = [{"type": "HARDCODED", "hardcoded_id": "silence_trap"}]
	silence_trap.art_path     = "res://assets/art/traps/neutral/silence_trap.png"
	silence_trap.faction      = "neutral"
	all.append(silence_trap)

	var death_trap := TrapCardData.new()
	death_trap.id           = "death_trap"
	death_trap.card_name    = "Death Trap"
	death_trap.cost         = 2
	death_trap.description  = "Trap: When the enemy summons a minion, destroy that minion immediately."
	death_trap.trigger      = Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	death_trap.effect_steps = [{"type": "SACRIFICE", "scope": "TRIGGER_MINION"}]
	death_trap.art_path     = "res://assets/art/traps/neutral/death_trap.png"
	death_trap.faction      = "neutral"
	all.append(death_trap)

	# ---------------------------------------------------------------------------
	# --- Void Bolt Support Pool (Lord Vael, Piercing Void talent only) ---
	# ---------------------------------------------------------------------------

	# Spells
	var mark_the_target := SpellCardData.new()
	mark_the_target.id          = "mark_the_target"
	mark_the_target.card_name   = "Mark the Target"
	mark_the_target.cost        = 2
	mark_the_target.description = "Apply 2 VOID MARKS to the enemy hero. Draw a card."

	mark_the_target.art_path     = "res://assets/art/spells/abyss_order/mark_the_target.png"
	mark_the_target.faction      = "abyss_order"
	mark_the_target.effect_steps = [
		{"type": "VOID_MARK", "amount": 2},
		{"type": "DRAW", "amount": 1},
	]
	all.append(mark_the_target)

	var font_of_the_depths := SpellCardData.new()
	font_of_the_depths.id          = "font_of_the_depths"
	font_of_the_depths.card_name   = "Font of the Depths"
	font_of_the_depths.cost        = 1
	font_of_the_depths.description = "Permanently gain +1 maximum Mana. Draw a card."
	font_of_the_depths.art_path    = "res://assets/art/spells/abyss_order/font_of_the_depths.png"
	font_of_the_depths.faction     = "abyss_order"
	font_of_the_depths.effect_steps = [
		{"type": "GROW_MANA_MAX", "amount": 1},
		{"type": "DRAW", "amount": 1},
	]
	all.append(font_of_the_depths)

	var void_detonation := SpellCardData.new()
	void_detonation.id          = "void_detonation"
	void_detonation.card_name   = "Void Detonation"
	void_detonation.cost        = 4
	void_detonation.description = "Deal 500 Void Bolt damage to the enemy hero. Gain +50 damage per VOID MARK."
	void_detonation.effect_steps = [{"type": "HARDCODED", "hardcoded_id": "void_detonation_effect"}]
	void_detonation.art_path    = "res://assets/art/spells/abyss_order/void_detonation.png"
	void_detonation.faction     = "abyss_order"
	all.append(void_detonation)

	# Minions
	var abyssal_arcanist := MinionCardData.new()
	abyssal_arcanist.id            = "abyssal_arcanist"
	abyssal_arcanist.card_name     = "Abyssal Arcanist"
	abyssal_arcanist.description   = "ON PLAY: add a Void Bolt spell to your hand."
	abyssal_arcanist.essence_cost  = 1
	abyssal_arcanist.mana_cost     = 2
	abyssal_arcanist.atk           = 200
	abyssal_arcanist.health        = 300
	abyssal_arcanist.minion_type   = Enums.MinionType.HUMAN
	abyssal_arcanist.on_play_effect_steps = [{"type": "ADD_CARD", "card_id": "void_bolt"}]
	abyssal_arcanist.faction       = "abyss_order"
	abyssal_arcanist.art_path           = "res://assets/art/minions/abyss_order/abyssal_arcanist.png"
	abyssal_arcanist.battlefield_art_path = "res://assets/art/minions/abyss_order/abyssal_arcanist_small.png"
	all.append(abyssal_arcanist)

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
	void_archmagus.art_path             = "res://assets/art/minions/abyss_order/void_archmagus.png"
	void_archmagus.battlefield_art_path = "res://assets/art/minions/abyss_order/void_archmagus_small.png"
	all.append(void_archmagus)

	# ---------------------------------------------------------------------------
	# --- Lord Vael — Common Imp Support Pool (unlocked by defeating act bosses) ---
	# ---------------------------------------------------------------------------

	# Minions
	var imp_recruiter := MinionCardData.new()
	imp_recruiter.id             = "imp_recruiter"
	imp_recruiter.card_name      = "Imp Recruiter"
	imp_recruiter.description    = "ON PLAY: Add a Void Imp to your hand."
	imp_recruiter.essence_cost   = 2
	imp_recruiter.atk            = 200
	imp_recruiter.health         = 300
	imp_recruiter.minion_type    = Enums.MinionType.HUMAN
	imp_recruiter.on_play_effect_steps = [{"type": "ADD_CARD", "card_id": "void_imp"}]
	imp_recruiter.faction        = "abyss_order"
	imp_recruiter.art_path             = "res://assets/art/minions/abyss_order/imp_recruiter.png"
	imp_recruiter.battlefield_art_path = "res://assets/art/minions/abyss_order/imp_recruiter_small.png"
	all.append(imp_recruiter)

	var soul_taskmaster := MinionCardData.new()
	soul_taskmaster.id                = "soul_taskmaster"
	soul_taskmaster.card_name         = "Soul Taskmaster"
	soul_taskmaster.description       = "PASSIVE: whenever a friendly Demon dies, this minion permanently gains +50 ATK."
	soul_taskmaster.essence_cost      = 3
	soul_taskmaster.atk               = 250
	soul_taskmaster.health            = 400
	soul_taskmaster.minion_type       = Enums.MinionType.DEMON
	soul_taskmaster.passive_effect_id = "soul_taskmaster_gain_atk"
	soul_taskmaster.faction           = "abyss_order"
	soul_taskmaster.art_path             = "res://assets/art/minions/abyss_order/soul_taskmaster.png"
	soul_taskmaster.battlefield_art_path = "res://assets/art/minions/abyss_order/soul_taskmaster_small.png"
	all.append(soul_taskmaster)

	var void_amplifier := MinionCardData.new()
	void_amplifier.id                = "void_amplifier"
	void_amplifier.card_name         = "Void Amplifier"
	void_amplifier.description       = "PASSIVE: whenever you play a Demon, it enters with +100 ATK and +100 HP."
	void_amplifier.essence_cost      = 4
	void_amplifier.atk               = 250
	void_amplifier.health            = 350
	void_amplifier.minion_type       = Enums.MinionType.HUMAN
	void_amplifier.passive_effect_id = "void_amplifier_buff_demon"
	void_amplifier.faction           = "abyss_order"
	void_amplifier.art_path             = "res://assets/art/minions/abyss_order/void_amplifier.png"
	void_amplifier.battlefield_art_path = "res://assets/art/minions/abyss_order/void_amplifier_small.png"
	all.append(void_amplifier)

	# Spells
	var blood_pact := SpellCardData.new()
	blood_pact.id          = "blood_pact"
	blood_pact.card_name   = "Blood Pact"
	blood_pact.cost        = 2
	blood_pact.description    = "Sacrifice a friendly Human. All friendly Demons permanently gain +200 ATK and +100 HP."
	blood_pact.requires_target = true
	blood_pact.target_type     = "friendly_human"
	blood_pact.effect_steps    = [
		{"type": "SACRIFICE", "scope": "SINGLE_CHOSEN_FRIENDLY", "filter": "HUMAN"},
		{"type": "BUFF_ATK",  "scope": "ALL_FRIENDLY", "filter": "DEMON", "amount": 200, "permanent": true},
		{"type": "BUFF_HP",   "scope": "ALL_FRIENDLY", "filter": "DEMON", "amount": 100},
	]
	blood_pact.faction     = "abyss_order"
	blood_pact.art_path    = "res://assets/art/spells/abyss_order/blood_pact.png"
	all.append(blood_pact)

	var soul_shatter := SpellCardData.new()
	soul_shatter.id          = "soul_shatter"
	soul_shatter.card_name   = "Soul Shatter"
	soul_shatter.cost        = 3
	soul_shatter.description    = "Sacrifice a friendly Demon. Deal 200 AoE to all enemy minions. Deal 300 instead if the sacrifice had 300+ HP."
	soul_shatter.requires_target = true
	soul_shatter.target_type     = "friendly_demon"
	soul_shatter.effect_steps    = [{"type": "HARDCODED", "hardcoded_id": "soul_shatter"}]
	soul_shatter.faction     = "abyss_order"
	soul_shatter.art_path    = "res://assets/art/spells/abyss_order/soul_shatter.png"
	all.append(soul_shatter)

	# Rune
	var soul_rune := TrapCardData.new()
	soul_rune.id                       = "soul_rune"
	soul_rune.card_name                = "Soul Rune"
	soul_rune.cost                     = 2
	soul_rune.description              = "RUNE: Whenever a friendly Demon dies during the enemy's turn, summon a 100/100 Void Spark. Each copy triggers once per turn."
	soul_rune.is_rune                  = true
	soul_rune.rune_type                = Enums.RuneType.SOUL_RUNE
	soul_rune.aura_trigger             = Enums.TriggerEvent.ON_PLAYER_MINION_DIED
	soul_rune.aura_effect_steps        = [{"type": "HARDCODED", "hardcoded_id": "soul_rune_death"}]
	soul_rune.aura_secondary_trigger   = Enums.TriggerEvent.ON_ENEMY_TURN_START
	soul_rune.aura_secondary_steps     = [{"type": "HARDCODED", "hardcoded_id": "soul_rune_reset"}]
	soul_rune.faction                  = "abyss_order"
	soul_rune.art_path                 = "res://assets/art/traps/abyss_order/soul_rune.png"
	soul_rune.battlefield_art_path     = "res://assets/art/traps/abyss_order/soul_rune_battlefield.png"
	soul_rune.rune_glow_color          = Color(0.08, 0.35, 0.12, 1)  # Dark green
	all.append(soul_rune)

	# ---------------------------------------------------------------------------
	# --- Runes (Abyss Order — Trap subtype, persistent, face-up) ---
	# ---------------------------------------------------------------------------

	var void_rune := TrapCardData.new()
	void_rune.id               = "void_rune"
	void_rune.card_name        = "Void Rune"
	void_rune.cost             = 2
	void_rune.description      = "RUNE: At the start of your turn, deal 100 Void Bolt damage to the enemy hero."
	void_rune.is_rune          = true
	void_rune.rune_type        = Enums.RuneType.VOID_RUNE
	void_rune.aura_trigger     = Enums.TriggerEvent.ON_PLAYER_TURN_START
	void_rune.aura_effect_steps = [{"type": "VOID_BOLT", "amount": 100, "multiplier_key": "rune_aura"}]
	void_rune.faction          = "abyss_order"
	void_rune.art_path             = "res://assets/art/traps/abyss_order/void_rune.png"
	void_rune.battlefield_art_path = "res://assets/art/traps/abyss_order/void_rune_battlefield.png"
	void_rune.rune_glow_color      = Color(0.35, 0.12, 0.55, 1)  # Dark purple
	all.append(void_rune)

	var blood_rune := TrapCardData.new()
	blood_rune.id               = "blood_rune"
	blood_rune.card_name        = "Blood Rune"
	blood_rune.cost             = 2
	blood_rune.description      = "RUNE: Whenever a friendly minion dies, restore 100 HP to your hero."
	blood_rune.is_rune          = true
	blood_rune.rune_type        = Enums.RuneType.BLOOD_RUNE
	blood_rune.aura_trigger     = Enums.TriggerEvent.ON_PLAYER_MINION_DIED
	blood_rune.aura_effect_steps = [{"type": "HEAL_HERO", "amount": 100, "multiplier_key": "rune_aura"}]
	blood_rune.faction          = "abyss_order"
	blood_rune.art_path             = "res://assets/art/traps/abyss_order/blood_rune.png"
	blood_rune.battlefield_art_path = "res://assets/art/traps/abyss_order/blood_rune_battlefield.png"
	blood_rune.rune_glow_color      = Color(0.55, 0.08, 0.08, 1)  # Dark red
	all.append(blood_rune)

	var dominion_rune := TrapCardData.new()
	dominion_rune.id                = "dominion_rune"
	dominion_rune.card_name         = "Dominion Rune"
	dominion_rune.cost              = 2
	dominion_rune.description       = "RUNE: All friendly Demons have +100 ATK."
	dominion_rune.is_rune           = true
	dominion_rune.rune_type         = Enums.RuneType.DOMINION_RUNE
	dominion_rune.aura_trigger      = Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED
	dominion_rune.aura_effect_steps = [{"type": "BUFF_ATK", "scope": "TRIGGER_MINION", "filter": "DEMON", "amount": 100, "multiplier_key": "rune_aura", "source_tag": "dominion_rune"}]
	dominion_rune.aura_on_place_steps  = [{"type": "HARDCODED", "hardcoded_id": "dominion_rune_place"}]
	dominion_rune.aura_on_remove_steps = [{"type": "HARDCODED", "hardcoded_id": "dominion_rune_remove"}]
	dominion_rune.faction           = "abyss_order"
	dominion_rune.art_path              = "res://assets/art/traps/abyss_order/dominion_rune.png"
	dominion_rune.battlefield_art_path  = "res://assets/art/traps/abyss_order/dominion_rune_battlefield.png"
	dominion_rune.rune_glow_color       = Color(0.10, 0.20, 0.55, 1)  # Dark blue
	all.append(dominion_rune)

	var shadow_rune := TrapCardData.new()
	shadow_rune.id               = "shadow_rune"
	shadow_rune.card_name        = "Shadow Rune"
	shadow_rune.cost             = 2
	shadow_rune.description      = "RUNE: Enemy minions enter the board with 1 stack of CORRUPTION."
	shadow_rune.is_rune          = true
	shadow_rune.rune_type        = Enums.RuneType.SHADOW_RUNE
	shadow_rune.aura_trigger     = Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	shadow_rune.aura_effect_steps = [{"type": "CORRUPTION", "scope": "TRIGGER_MINION", "amount": 1, "multiplier_key": "rune_aura"}]
	shadow_rune.faction          = "abyss_order"
	shadow_rune.art_path             = "res://assets/art/traps/abyss_order/shadow_rune.png"
	shadow_rune.battlefield_art_path = "res://assets/art/traps/abyss_order/shadow_rune_battlefield.png"
	shadow_rune.rune_glow_color      = Color(0.35, 0.35, 0.40, 1)  # Dark grey-white
	all.append(shadow_rune)

	# ---------------------------------------------------------------------------
	# --- Ritual token (Special Summoned by ritual effects, not in any deck) ---
	# ---------------------------------------------------------------------------

	# All tokens are registered via _TOKEN_DEFS below.

	# ---------------------------------------------------------------------------
	# --- Ritual Environments (Abyss Order — core set) ---
	# ---------------------------------------------------------------------------

	var blood_dominion_ritual := RitualData.new()
	blood_dominion_ritual.ritual_name    = "Demon Ascendant"
	blood_dominion_ritual.description    = "Consume Blood + Dominion Runes. Deal 200 damage to 2 random enemy minions. Special Summon a 500/500 Demon."
	blood_dominion_ritual.required_runes = [Enums.RuneType.BLOOD_RUNE, Enums.RuneType.DOMINION_RUNE]
	blood_dominion_ritual.effect_steps   = [{"type": "HARDCODED", "hardcoded_id": "demon_ascendant"}]

	var abyssal_summoning_circle := EnvironmentCardData.new()
	abyssal_summoning_circle.id                         = "abyssal_summoning_circle"
	abyssal_summoning_circle.card_name                  = "Abyssal Summoning Circle"
	abyssal_summoning_circle.cost                       = 2
	abyssal_summoning_circle.description                = "Whenever a friendly Demon dies, deal 200 damage to the enemy hero. \nRITUAL: Blood + Dominion → Demon Ascendant."
	abyssal_summoning_circle.passive_description        = "Whenever a friendly Demon dies, deal 200 damage to the enemy hero."
	abyssal_summoning_circle.on_player_minion_died_steps = [{"type": "DAMAGE_HERO", "amount": 200, "conditions": ["dead_is_demon"]}]
	abyssal_summoning_circle.rituals                    = [blood_dominion_ritual]
	abyssal_summoning_circle.faction                    = "abyss_order"
	abyssal_summoning_circle.art_path                   = "res://assets/art/environments/abyss_order/abyssal_summoning_circle.png"
	all.append(abyssal_summoning_circle)

	# ---------------------------------------------------------------------------
	# --- Ritual Environments (Abyss Order — Piercing Void support pool) ---
	# ---------------------------------------------------------------------------

	var void_blood_ritual := RitualData.new()
	void_blood_ritual.ritual_name    = "Soul Cataclysm"
	void_blood_ritual.description    = "Consume Void + Blood Runes. Deal 400 Void Bolt damage to the enemy hero. Restore 400 HP to your hero."
	void_blood_ritual.required_runes = [Enums.RuneType.VOID_RUNE, Enums.RuneType.BLOOD_RUNE]
	void_blood_ritual.effect_steps   = [
		{"type": "VOID_BOLT", "amount": 400},
		{"type": "HEAL_HERO",  "amount": 400},
	]

	var abyss_ritual_circle := EnvironmentCardData.new()
	abyss_ritual_circle.id                  = "abyss_ritual_circle"
	abyss_ritual_circle.card_name           = "Abyss Ritual Circle"
	abyss_ritual_circle.cost                = 2
	abyss_ritual_circle.description         = "Each turn, deal 100 damage to a random minion (both sides). \nRITUAL: Void + Blood → Soul Cataclysm."
	abyss_ritual_circle.passive_description = "At the start of each turn, deal 100 damage to a random minion on the battlefield."
	abyss_ritual_circle.passive_effect_steps = [{"type": "HARDCODED", "hardcoded_id": "abyss_ritual_circle_passive"}]
	abyss_ritual_circle.fires_on_enemy_turn = true
	abyss_ritual_circle.rituals             = [void_blood_ritual]
	abyss_ritual_circle.art_path            = "res://assets/art/environments/abyss_order/abyss_ritual_circle.png"
	abyss_ritual_circle.faction             = "abyss_order"
	all.append(abyss_ritual_circle)

	# ---------------------------------------------------------------------------
	# --- Vael Endless Tide support pool (5 cards) ---
	# ---------------------------------------------------------------------------

	var imp_frenzy := SpellCardData.new()
	imp_frenzy.id              = "imp_frenzy"
	imp_frenzy.card_name       = "Imp Frenzy"
	imp_frenzy.cost            = 1
	imp_frenzy.description     = "Give a friendly VOID IMP CLAN minion +300 ATK."
	imp_frenzy.requires_target = true
	imp_frenzy.target_type     = "friendly_void_imp"
	imp_frenzy.effect_steps    = [{"type": "BUFF_ATK", "scope": "SINGLE_CHOSEN_FRIENDLY", "filter": "VOID_IMP", "amount": 300, "permanent": true}]
	imp_frenzy.art_path        = "res://assets/art/spells/abyss_order/imp_frenzy.png"
	imp_frenzy.faction         = "abyss_order"
	all.append(imp_frenzy)

	var imp_martyr := MinionCardData.new()
	imp_martyr.id                  = "imp_martyr"
	imp_martyr.card_name           = "Imp Martyr"
	imp_martyr.essence_cost        = 2
	imp_martyr.description         = "ON DEATH: Give all friendly VOID IMP CLAN minions +100/+100 permanently."
	imp_martyr.atk                 = 100
	imp_martyr.health              = 100
	imp_martyr.minion_type         = Enums.MinionType.DEMON
	imp_martyr.on_death_effect_steps = [
		{"type": "BUFF_ATK", "scope": "ALL_FRIENDLY", "filter": "VOID_IMP", "amount": 100, "permanent": true},
		{"type": "BUFF_HP",  "scope": "ALL_FRIENDLY", "filter": "VOID_IMP", "amount": 100},
	]
	imp_martyr.minion_tags         = ["void_imp"]
	imp_martyr.art_path            = "res://assets/art/minions/abyss_order/imp_martyr.png"
	imp_martyr.battlefield_art_path = "res://assets/art/minions/abyss_order/imp_martyr_small.png"
	imp_martyr.faction             = "abyss_order"
	imp_martyr.clan                = "Void Imp"
	all.append(imp_martyr)

	var imp_vessel := MinionCardData.new()
	imp_vessel.id                  = "imp_vessel"
	imp_vessel.card_name           = "Imp Vessel"
	imp_vessel.essence_cost        = 3
	imp_vessel.description         = "ON DEATH: Summon 2 Void Imps."
	imp_vessel.atk                 = 100
	imp_vessel.health              = 200
	imp_vessel.minion_type         = Enums.MinionType.DEMON
	imp_vessel.on_death_effect_steps = [
		{"type": "SUMMON", "card_id": "void_imp"},
		{"type": "SUMMON", "card_id": "void_imp"},
	]
	imp_vessel.minion_tags         = ["void_imp"]
	imp_vessel.art_path            = "res://assets/art/minions/abyss_order/imp_vessel.png"
	imp_vessel.battlefield_art_path = "res://assets/art/minions/abyss_order/imp_vessel_small.png"
	imp_vessel.faction             = "abyss_order"
	imp_vessel.clan                = "Void Imp"
	all.append(imp_vessel)

	var imp_idol := MinionCardData.new()
	imp_idol.id                    = "imp_idol"
	imp_idol.card_name             = "Imp Idol"
	imp_idol.essence_cost          = 5
	imp_idol.description           = "ON PLAY: Give all friendly VOID IMP CLAN minions DEATHLESS."
	imp_idol.atk                   = 300
	imp_idol.health                = 600
	imp_idol.minion_type           = Enums.MinionType.DEMON
	imp_idol.on_play_effect_steps  = [
		{"type": "GRANT_KEYWORD", "scope": "ALL_FRIENDLY", "filter": "VOID_IMP", "keyword": "DEATHLESS"},
	]
	imp_idol.minion_tags           = ["void_imp"]
	imp_idol.art_path              = "res://assets/art/minions/abyss_order/imp_idol.png"
	imp_idol.battlefield_art_path  = "res://assets/art/minions/abyss_order/imp_idol_small.png"
	imp_idol.faction               = "abyss_order"
	imp_idol.clan                  = "Void Imp"
	all.append(imp_idol)

	var vaels_colossal_guard := MinionCardData.new()
	vaels_colossal_guard.id                   = "vaels_colossal_guard"
	vaels_colossal_guard.card_name            = "Vael's Colossal Guard"
	vaels_colossal_guard.essence_cost         = 7
	vaels_colossal_guard.description          = "ON PLAY: Gain +300/+300 for each other VOID IMP CLAN minion on board. Give all other VOID IMP CLAN minions +100 ATK permanently."
	vaels_colossal_guard.atk                  = 300
	vaels_colossal_guard.health               = 300
	vaels_colossal_guard.minion_type          = Enums.MinionType.DEMON
	vaels_colossal_guard.keywords             = [Enums.Keyword.GUARD]
	vaels_colossal_guard.on_play_effect_steps = [
		{"type": "BUFF_ATK", "scope": "SELF", "amount": 300, "multiplier_key": "board_count", "multiplier_board": "friendly", "multiplier_filter": "tag", "multiplier_tag": "void_imp", "exclude_self": true, "permanent": true},
		{"type": "BUFF_HP",  "scope": "SELF", "amount": 300, "multiplier_key": "board_count", "multiplier_board": "friendly", "multiplier_filter": "tag", "multiplier_tag": "void_imp", "exclude_self": true},
		{"type": "BUFF_ATK", "scope": "ALL_FRIENDLY", "filter": "VOID_IMP", "amount": 100, "permanent": true, "exclude_self": true},
	]
	vaels_colossal_guard.minion_tags          = ["void_imp"]
	vaels_colossal_guard.faction              = "abyss_order"
	vaels_colossal_guard.clan                 = "Void Imp"
	vaels_colossal_guard.art_path             = "res://assets/art/minions/abyss_order/vaels_colossal_guard.png"
	vaels_colossal_guard.battlefield_art_path = "res://assets/art/minions/abyss_order/vaels_colossal_guard_small.png"
	all.append(vaels_colossal_guard)

	# ---------------------------------------------------------------------------
	# --- Vael Rune Master support pool (5 cards) ---
	# ---------------------------------------------------------------------------

	var runic_blast := SpellCardData.new()
	runic_blast.id          = "runic_blast"
	runic_blast.card_name   = "Runic Blast"
	runic_blast.cost        = 2
	runic_blast.description = "Deal 200 damage to 2 random enemy minions. If you have 2+ Runes, deal 200 to ALL enemy minions instead."
	runic_blast.effect_steps = [{"type": "HARDCODED", "hardcoded_id": "runic_blast"}]
	runic_blast.art_path    = "res://assets/art/spells/abyss_order/runic_blast.png"
	runic_blast.faction     = "abyss_order"
	all.append(runic_blast)

	var runic_echo := SpellCardData.new()
	runic_echo.id          = "runic_echo"
	runic_echo.card_name   = "Runic Echo"
	runic_echo.cost        = 2
	runic_echo.description = "Add a copy of each Rune on the battlefield to your hand."
	runic_echo.effect_steps = [{"type": "HARDCODED", "hardcoded_id": "runic_echo"}]
	runic_echo.art_path    = "res://assets/art/spells/abyss_order/runic_echo.png"
	runic_echo.faction     = "abyss_order"
	all.append(runic_echo)

	var rune_warden := MinionCardData.new()
	rune_warden.id                       = "rune_warden"
	rune_warden.card_name                = "Rune Warden"
	rune_warden.essence_cost             = 3
	rune_warden.description              = "PASSIVE: Whenever you place a Rune, this minion gains +200 ATK until end of turn."
	rune_warden.atk                      = 200
	rune_warden.health                   = 400
	rune_warden.minion_type              = Enums.MinionType.HUMAN
	rune_warden.passive_effect_id        = "rune_warden"
	rune_warden.art_path                 = "res://assets/art/minions/abyss_order/rune_warden.png"
	rune_warden.battlefield_art_path     = "res://assets/art/minions/abyss_order/rune_warden_small.png"
	rune_warden.faction                  = "abyss_order"
	all.append(rune_warden)

	var rune_seeker := MinionCardData.new()
	rune_seeker.id                      = "rune_seeker"
	rune_seeker.card_name               = "Rune Seeker"
	rune_seeker.essence_cost            = 3
	rune_seeker.description             = "ON PLAY: Search your deck for a Rune and add it to your hand."
	rune_seeker.atk                     = 150
	rune_seeker.health                  = 400
	rune_seeker.minion_type             = Enums.MinionType.HUMAN
	rune_seeker.on_play_effect_steps    = [{"type": "HARDCODED", "hardcoded_id": "rune_seeker_play"}]
	rune_seeker.art_path                = "res://assets/art/minions/abyss_order/rune_seeker.png"
	rune_seeker.battlefield_art_path    = "res://assets/art/minions/abyss_order/rune_seeker_small.png"
	rune_seeker.faction                 = "abyss_order"
	all.append(rune_seeker)

	var echo_rune := TrapCardData.new()
	echo_rune.id                 = "echo_rune"
	echo_rune.card_name          = "Echo Rune"
	echo_rune.cost               = 2
	echo_rune.description        = "RUNE (Wildcard): At the start of your turn, fire the effect of the last Rune you placed. Counts as any rune type for rituals."
	echo_rune.is_rune            = true
	echo_rune.is_wildcard_rune   = true
	echo_rune.aura_trigger       = Enums.TriggerEvent.ON_PLAYER_TURN_START
	echo_rune.aura_effect_steps  = [{"type": "HARDCODED", "hardcoded_id": "echo_rune_fire"}]
	echo_rune.art_path               = "res://assets/art/traps/abyss_order/echo_rune.png"
	echo_rune.battlefield_art_path   = "res://assets/art/traps/abyss_order/echo_rune_battlefield.png"
	echo_rune.rune_glow_color        = Color(0.20, 0.08, 0.35, 1)  # Dark black-purple
	echo_rune.faction                = "abyss_order"
	all.append(echo_rune)

	# ---------------------------------------------------------------------------
	# --- Feral Imp Clan — Act 1 enemy-only cards (pool="feral_imp_clan", not player-visible) ---
	# ---------------------------------------------------------------------------

	var rabid_imp := MinionCardData.new()
	rabid_imp.id           = "rabid_imp"
	rabid_imp.card_name    = "Rabid Imp"
	rabid_imp.essence_cost = 1
	rabid_imp.atk          = 200
	rabid_imp.health       = 100
	rabid_imp.minion_type  = Enums.MinionType.DEMON
	rabid_imp.keywords     = [Enums.Keyword.SWIFT]
	rabid_imp.minion_tags  = ["feral_imp"]
	rabid_imp.faction             = "abyss_order"
	rabid_imp.clan                = "Feral Imp"
	rabid_imp.art_path            = "res://assets/art/minions/feral_imp_clan/rabid_imp.png"
	rabid_imp.battlefield_art_path = "res://assets/art/minions/feral_imp_clan/rabid_imp_small.png"
	all.append(rabid_imp)

	var brood_imp := MinionCardData.new()
	brood_imp.id           = "brood_imp"
	brood_imp.card_name    = "Brood Imp"
	brood_imp.essence_cost = 2
	brood_imp.description  = "ON DEATH: Summon two 100/100 Void Sparks."
	brood_imp.atk          = 100
	brood_imp.health       = 300
	brood_imp.minion_type  = Enums.MinionType.DEMON
	brood_imp.on_death_effect_steps = [
		{"type": "SUMMON", "card_id": "void_spark"},
		{"type": "SUMMON", "card_id": "void_spark"},
	]
	brood_imp.minion_tags         = ["feral_imp"]
	brood_imp.faction             = "abyss_order"
	brood_imp.clan                = "Feral Imp"
	brood_imp.art_path            = "res://assets/art/minions/feral_imp_clan/brood_imp.png"
	brood_imp.battlefield_art_path = "res://assets/art/minions/feral_imp_clan/brood_imp_small.png"
	all.append(brood_imp)

	var imp_brawler := MinionCardData.new()
	imp_brawler.id           = "imp_brawler"
	imp_brawler.card_name    = "Imp Brawler"
	imp_brawler.essence_cost = 2
	imp_brawler.description  = ""
	imp_brawler.atk          = 300
	imp_brawler.health       = 250
	imp_brawler.minion_type  = Enums.MinionType.DEMON
	imp_brawler.minion_tags  = ["feral_imp"]
	imp_brawler.faction             = "abyss_order"
	imp_brawler.clan                = "Feral Imp"
	imp_brawler.art_path            = "res://assets/art/minions/feral_imp_clan/imp_brawler.png"
	imp_brawler.battlefield_art_path = "res://assets/art/minions/feral_imp_clan/imp_brawler_small.png"
	all.append(imp_brawler)

	var void_touched_imp := MinionCardData.new()
	void_touched_imp.id           = "void_touched_imp"
	void_touched_imp.card_name    = "Void-Touched Imp"
	void_touched_imp.essence_cost = 2
	void_touched_imp.description  = "ON DEATH: Deal 100 damage to all enemy minions."
	void_touched_imp.atk          = 200
	void_touched_imp.health       = 300
	void_touched_imp.minion_type  = Enums.MinionType.DEMON
	void_touched_imp.on_death_effect_steps = [
		{"type": "DAMAGE_MINION", "scope": "ALL_ENEMY", "amount": 100},
	]
	void_touched_imp.minion_tags  = ["feral_imp"]
	void_touched_imp.faction  = "abyss_order"
	void_touched_imp.clan     = "Feral Imp"
	void_touched_imp.art_path             = "res://assets/art/minions/feral_imp_clan/void_touched_imp.png"
	void_touched_imp.battlefield_art_path = "res://assets/art/minions/feral_imp_clan/void_touched_imp_small.png"
	all.append(void_touched_imp)

	var frenzied_imp := MinionCardData.new()
	frenzied_imp.id           = "frenzied_imp"
	frenzied_imp.card_name    = "Frenzied Imp"
	frenzied_imp.essence_cost = 3
	frenzied_imp.description  = "ON PLAY: Deal 100 damage to a random enemy minion, plus 100 more for each other FERAL IMP on your board."
	frenzied_imp.atk          = 300
	frenzied_imp.health       = 300
	frenzied_imp.minion_type  = Enums.MinionType.DEMON
	frenzied_imp.on_play_effect_steps = [
		{"type": "HARDCODED", "hardcoded_id": "frenzied_imp_play"},
	]
	frenzied_imp.minion_tags  = ["feral_imp"]
	frenzied_imp.faction              = "abyss_order"
	frenzied_imp.clan                 = "Feral Imp"
	frenzied_imp.art_path             = "res://assets/art/minions/feral_imp_clan/frienzied_imp.png"
	frenzied_imp.battlefield_art_path = "res://assets/art/minions/feral_imp_clan/frienzied_imp_small.png"
	all.append(frenzied_imp)

	var matriarchs_broodling := MinionCardData.new()
	matriarchs_broodling.id           = "matriarchs_broodling"
	matriarchs_broodling.card_name    = "Matriarch's Broodling"
	matriarchs_broodling.essence_cost = 4
	matriarchs_broodling.description  = "GUARD.\nON DEATH: Summon a Brood Imp."
	matriarchs_broodling.atk          = 200
	matriarchs_broodling.health       = 500
	matriarchs_broodling.minion_type  = Enums.MinionType.DEMON
	matriarchs_broodling.keywords     = [Enums.Keyword.GUARD]
	matriarchs_broodling.on_death_effect_steps = [
		{"type": "SUMMON", "card_id": "brood_imp"},
	]
	matriarchs_broodling.minion_tags  = ["feral_imp"]
	matriarchs_broodling.faction              = "abyss_order"
	matriarchs_broodling.clan                 = "Feral Imp"
	matriarchs_broodling.art_path             = "res://assets/art/minions/feral_imp_clan/matriarchs_broodling.png"
	matriarchs_broodling.battlefield_art_path = "res://assets/art/minions/feral_imp_clan/matriarchs_broodling_small.png"
	all.append(matriarchs_broodling)

	var rogue_imp_elder := MinionCardData.new()
	rogue_imp_elder.id           = "rogue_imp_elder"
	rogue_imp_elder.card_name    = "Rogue Imp Elder"
	rogue_imp_elder.essence_cost = 4
	rogue_imp_elder.description  = "PASSIVE (aura): All friendly FERAL IMP minions have +100 ATK."
	rogue_imp_elder.atk          = 300
	rogue_imp_elder.health       = 500
	rogue_imp_elder.minion_type  = Enums.MinionType.DEMON
	rogue_imp_elder.on_play_effect_steps = [
		{"type": "BUFF_ATK", "scope": "ALL_FRIENDLY", "filter": "FERAL_IMP", "amount": 100, "permanent": true, "source_tag": "rogue_imp_elder", "exclude_self": true},
	]
	rogue_imp_elder.on_death_effect_steps = [
		{"type": "HARDCODED", "hardcoded_id": "rogue_imp_elder_remove"},
	]
	rogue_imp_elder.minion_tags  = ["feral_imp"]
	rogue_imp_elder.faction              = "abyss_order"
	rogue_imp_elder.clan                 = "Feral Imp"
	rogue_imp_elder.art_path             = "res://assets/art/minions/feral_imp_clan/rogue_imp_elder.png"
	rogue_imp_elder.battlefield_art_path = "res://assets/art/minions/feral_imp_clan/rogue_imp_elder_small.png"
	all.append(rogue_imp_elder)

	# --- Enemy Champions (Act 1) — auto-summoned by passive handlers, not from deck ---

	var champion_rogue_imp_pack := MinionCardData.new()
	champion_rogue_imp_pack.id           = "champion_rogue_imp_pack"
	champion_rogue_imp_pack.card_name    = "Rogue Imp Pack"
	champion_rogue_imp_pack.essence_cost = 0
	champion_rogue_imp_pack.description  = "CHAMPION. SWIFT.\nSummoned after 4 Rabid Imp attacks.\nAura: All friendly FERAL IMP minions gain +100 ATK.\nOn death: Deal 20% of enemy hero max HP to enemy hero."
	champion_rogue_imp_pack.atk          = 300
	champion_rogue_imp_pack.health       = 400
	champion_rogue_imp_pack.minion_type  = Enums.MinionType.DEMON
	champion_rogue_imp_pack.keywords     = [Enums.Keyword.CHAMPION, Enums.Keyword.SWIFT]
	champion_rogue_imp_pack.is_champion  = true
	champion_rogue_imp_pack.minion_tags  = ["feral_imp", "enemy_champion"]
	champion_rogue_imp_pack.faction      = "abyss_order"
	champion_rogue_imp_pack.clan         = "Feral Imp"
	all.append(champion_rogue_imp_pack)

	var champion_corrupted_broodlings := MinionCardData.new()
	champion_corrupted_broodlings.id           = "champion_corrupted_broodlings"
	champion_corrupted_broodlings.card_name    = "Corrupted Broodlings"
	champion_corrupted_broodlings.essence_cost = 0
	champion_corrupted_broodlings.description  = "CHAMPION.\nOn death: Summon a Void-Touched Imp and deal 20% of enemy hero max HP to enemy hero."
	champion_corrupted_broodlings.atk          = 200
	champion_corrupted_broodlings.health       = 400
	champion_corrupted_broodlings.minion_type  = Enums.MinionType.DEMON
	champion_corrupted_broodlings.keywords     = [Enums.Keyword.CHAMPION]
	champion_corrupted_broodlings.is_champion  = true
	champion_corrupted_broodlings.minion_tags  = ["feral_imp", "enemy_champion"]
	champion_corrupted_broodlings.faction      = "abyss_order"
	champion_corrupted_broodlings.clan         = "Feral Imp"
	all.append(champion_corrupted_broodlings)

	var champion_imp_matriarch := MinionCardData.new()
	champion_imp_matriarch.id           = "champion_imp_matriarch"
	champion_imp_matriarch.card_name    = "Imp Matriarch"
	champion_imp_matriarch.essence_cost = 0
	champion_imp_matriarch.description  = "CHAMPION. GUARD.\nAura: Pack Frenzy also grants +200 HP to all FERAL IMP minions.\nOn death: Deal 20% of enemy hero max HP to enemy hero."
	champion_imp_matriarch.atk          = 300
	champion_imp_matriarch.health       = 500
	champion_imp_matriarch.minion_type  = Enums.MinionType.DEMON
	champion_imp_matriarch.keywords     = [Enums.Keyword.CHAMPION, Enums.Keyword.GUARD]
	champion_imp_matriarch.is_champion  = true
	champion_imp_matriarch.minion_tags  = ["feral_imp", "enemy_champion"]
	champion_imp_matriarch.faction      = "abyss_order"
	champion_imp_matriarch.clan         = "Feral Imp"
	all.append(champion_imp_matriarch)

	# Feral Imp Clan Spells

	var feral_surge := SpellCardData.new()
	feral_surge.id             = "feral_surge"
	feral_surge.card_name      = "Feral Surge"
	feral_surge.cost           = 1
	feral_surge.description    = "Give a friendly FERAL IMP minion +300 ATK this turn."
	feral_surge.requires_target = true
	feral_surge.target_type    = "friendly_feral_imp"
	feral_surge.effect_steps   = [
		{"type": "BUFF_ATK", "scope": "SINGLE_CHOSEN_FRIENDLY", "filter": "FERAL_IMP", "amount": 300, "permanent": false},
	]
	feral_surge.faction   = "abyss_order"
	feral_surge.art_path  = "res://assets/art/spells/feral_imp_clan/feral_surge.png"
	all.append(feral_surge)

	var void_screech := SpellCardData.new()
	void_screech.id          = "void_screech"
	void_screech.card_name   = "Void Screech"
	void_screech.cost        = 1
	void_screech.description = "Deal 250 damage to the enemy hero. If you have 3+ FERAL IMP minions on board, deal 350 instead."
	void_screech.effect_steps = [{"type": "HARDCODED", "hardcoded_id": "void_screech"}]
	void_screech.faction   = "abyss_order"
	void_screech.art_path  = "res://assets/art/spells/feral_imp_clan/void_screech.png"
	all.append(void_screech)

	var brood_call := SpellCardData.new()
	brood_call.id          = "brood_call"
	brood_call.card_name   = "Brood Call"
	brood_call.cost        = 2
	brood_call.description = "Summon a random FERAL IMP minion."
	brood_call.effect_steps = [{"type": "HARDCODED", "hardcoded_id": "brood_call"}]
	brood_call.faction   = "abyss_order"
	brood_call.art_path  = "res://assets/art/spells/feral_imp_clan/brood_call.png"
	all.append(brood_call)

	var pack_frenzy := SpellCardData.new()
	pack_frenzy.id          = "pack_frenzy"
	pack_frenzy.card_name   = "Pack Frenzy"
	pack_frenzy.cost        = 3
	pack_frenzy.description = "All friendly FERAL IMP minions gain +250 ATK and SWIFT this turn."
	pack_frenzy.effect_steps = [{"type": "HARDCODED", "hardcoded_id": "pack_frenzy"}]
	pack_frenzy.faction   = "abyss_order"
	pack_frenzy.art_path  = "res://assets/art/spells/feral_imp_clan/pack_frenzy.png"
	all.append(pack_frenzy)

	# --- Abyss Dungeon — Act 2 enemy-only cards (pool="abyss_cultist_clan", not player-visible) ---

	var cult_fanatic := MinionCardData.new()
	cult_fanatic.id           = "cult_fanatic"
	cult_fanatic.card_name    = "Cult Fanatic"
	cult_fanatic.essence_cost = 2
	cult_fanatic.description  = ""
	cult_fanatic.atk          = 300
	cult_fanatic.health       = 300
	cult_fanatic.minion_type  = Enums.MinionType.HUMAN
	cult_fanatic.art_path             = "res://assets/art/minions/abyss_cultist/cult_fanatic.png"
	cult_fanatic.battlefield_art_path = "res://assets/art/minions/abyss_cultist/cult_fanatic_small.png"
	cult_fanatic.faction      = "abyss_order"
	all.append(cult_fanatic)

	var dark_command := SpellCardData.new()
	dark_command.id          = "dark_command"
	dark_command.card_name   = "Dark Command"
	dark_command.cost        = 1
	dark_command.description = "Grant +100 ATK and +100 HP to all friendly Human minions."
	dark_command.effect_steps = [
		{"type": "BUFF_ATK", "scope": "ALL_FRIENDLY", "filter": "HUMAN", "amount": 100, "permanent": true},
		{"type": "BUFF_HP",  "scope": "ALL_FRIENDLY", "filter": "HUMAN", "amount": 100},
	]
	dark_command.art_path    = "res://assets/art/spells/abyss_cultist/dark_command.png"
	dark_command.faction     = "abyss_order"
	all.append(dark_command)

	# --- Enemy Champions (Act 2) — auto-summoned by passive handlers, not from deck ---

	var champion_abyss_cultist_patrol := MinionCardData.new()
	champion_abyss_cultist_patrol.id           = "champion_abyss_cultist_patrol"
	champion_abyss_cultist_patrol.card_name    = "Abyss Cultist Patrol"
	champion_abyss_cultist_patrol.essence_cost = 0
	champion_abyss_cultist_patrol.description  = "CHAMPION.\nSummoned after 4 corruption stacks consumed.\nAura: Corruption applied to player minions instantly detonates.\nOn death: Deal 20% of enemy hero max HP to enemy hero."
	champion_abyss_cultist_patrol.atk          = 300
	champion_abyss_cultist_patrol.health       = 300
	champion_abyss_cultist_patrol.minion_type  = Enums.MinionType.HUMAN
	champion_abyss_cultist_patrol.keywords     = [Enums.Keyword.CHAMPION]
	champion_abyss_cultist_patrol.is_champion  = true
	champion_abyss_cultist_patrol.minion_tags  = ["enemy_champion"]
	champion_abyss_cultist_patrol.faction      = "abyss_order"
	all.append(champion_abyss_cultist_patrol)

	var champion_void_ritualist := MinionCardData.new()
	champion_void_ritualist.id           = "champion_void_ritualist"
	champion_void_ritualist.card_name    = "Void Ritualist"
	champion_void_ritualist.essence_cost = 0
	champion_void_ritualist.description  = "CHAMPION.\nSummoned when ritual sacrifice triggers.\nAura: Rune placement costs 1 less Mana.\nOn death: Deal 20% of enemy hero max HP to enemy hero."
	champion_void_ritualist.atk          = 200
	champion_void_ritualist.health       = 300
	champion_void_ritualist.minion_type  = Enums.MinionType.HUMAN
	champion_void_ritualist.keywords     = [Enums.Keyword.CHAMPION]
	champion_void_ritualist.is_champion  = true
	champion_void_ritualist.minion_tags  = ["enemy_champion"]
	champion_void_ritualist.faction      = "abyss_order"
	all.append(champion_void_ritualist)

	var champion_corrupted_handler := MinionCardData.new()
	champion_corrupted_handler.id           = "champion_corrupted_handler"
	champion_corrupted_handler.card_name    = "Corrupted Handler"
	champion_corrupted_handler.essence_cost = 0
	champion_corrupted_handler.description  = "CHAMPION.\nSummoned after 4 void sparks created.\nAura: Whenever a Void Spark is summoned, deal 200 damage to player hero.\nOn death: Deal 20% of enemy hero max HP to enemy hero."
	champion_corrupted_handler.atk          = 300
	champion_corrupted_handler.health       = 300
	champion_corrupted_handler.minion_type  = Enums.MinionType.HUMAN
	champion_corrupted_handler.keywords     = [Enums.Keyword.CHAMPION]
	champion_corrupted_handler.is_champion  = true
	champion_corrupted_handler.minion_tags  = ["enemy_champion"]
	champion_corrupted_handler.faction      = "abyss_order"
	all.append(champion_corrupted_handler)

	# --- Void Rift World — Act 3 enemy-only cards (dual cost: mana/essence + Void Sparks) ---

	var void_pulse := SpellCardData.new()
	void_pulse.id              = "void_pulse"
	void_pulse.card_name       = "Void Pulse"
	void_pulse.cost            = 1
	void_pulse.void_spark_cost = 1
	void_pulse.description     = "Consume 1 Void Spark. Draw 3 cards."
	void_pulse.effect_steps    = [{"type": "DRAW", "amount": 3}]
	void_pulse.faction         = "abyss_order"
	void_pulse.art_path        = "res://assets/art/spells/abyss_order/void_pulse.png"
	all.append(void_pulse)

	var phase_stalker := MinionCardData.new()
	phase_stalker.id              = "phase_stalker"
	phase_stalker.card_name       = "Phase Stalker"
	phase_stalker.essence_cost    = 2
	phase_stalker.void_spark_cost = 1
	phase_stalker.description     = "Consume 1 Void Spark. Swift."
	phase_stalker.atk             = 400
	phase_stalker.health          = 300
	phase_stalker.minion_type     = Enums.MinionType.SPIRIT
	phase_stalker.keywords.append(Enums.Keyword.SWIFT)
	phase_stalker.faction         = "abyss_order"
	phase_stalker.art_path             = "res://assets/art/minions/abyss_order/phase_stalker.png"
	phase_stalker.battlefield_art_path = "res://assets/art/minions/abyss_order/phase_stalker_small.png"
	all.append(phase_stalker)

	var rift_collapse := SpellCardData.new()
	rift_collapse.id              = "rift_collapse"
	rift_collapse.card_name       = "Rift Collapse"
	rift_collapse.cost            = 2
	rift_collapse.void_spark_cost = 1
	rift_collapse.description     = "Consume 1 Void Spark. Deal 200 damage to all enemy minions."
	rift_collapse.effect_steps    = [{"type": "DAMAGE_MINION", "scope": "ALL_ENEMY", "amount": 200}]
	rift_collapse.faction         = "abyss_order"
	rift_collapse.art_path        = "res://assets/art/spells/abyss_order/rift_collapse.png"
	all.append(rift_collapse)

	var void_behemoth := MinionCardData.new()
	void_behemoth.id              = "void_behemoth"
	void_behemoth.card_name       = "Void Behemoth"
	void_behemoth.essence_cost    = 3
	void_behemoth.void_spark_cost = 2
	void_behemoth.description     = "Consume 2 Void Sparks. Guard."
	void_behemoth.atk             = 400
	void_behemoth.health          = 600
	void_behemoth.minion_type     = Enums.MinionType.SPIRIT
	void_behemoth.keywords.append(Enums.Keyword.GUARD)
	void_behemoth.faction         = "abyss_order"
	void_behemoth.art_path             = "res://assets/art/minions/abyss_order/void_behemoth.png"
	void_behemoth.battlefield_art_path = "res://assets/art/minions/abyss_order/void_behemoth_small.png"
	all.append(void_behemoth)

	var dimensional_breach := SpellCardData.new()
	dimensional_breach.id              = "dimensional_breach"
	dimensional_breach.card_name       = "Dimensional Breach"
	dimensional_breach.cost            = 1
	dimensional_breach.void_spark_cost = 2
	dimensional_breach.description     = "Consume 2 Void Sparks. Summon 3 Void Sparks."
	dimensional_breach.effect_steps    = [
		{"type": "SUMMON", "card_id": "void_spark"},
		{"type": "SUMMON", "card_id": "void_spark"},
		{"type": "SUMMON", "card_id": "void_spark"},
	]
	dimensional_breach.faction         = "abyss_order"
	dimensional_breach.art_path        = "res://assets/art/spells/abyss_order/dimensional_breach.png"
	all.append(dimensional_breach)

	var void_rift_lord := MinionCardData.new()
	void_rift_lord.id              = "void_rift_lord"
	void_rift_lord.card_name       = "Void Rift Lord"
	void_rift_lord.essence_cost    = 4
	void_rift_lord.void_spark_cost = 3
	void_rift_lord.description     = "Consume 3 Void Sparks. On play: set enemy Mana to 0 next turn."
	void_rift_lord.atk             = 400
	void_rift_lord.health          = 600
	void_rift_lord.minion_type     = Enums.MinionType.SPIRIT
	void_rift_lord.on_play_effect_steps = [{"type": "HARDCODED", "hardcoded_id": "void_rift_lord_mana_drain"}]
	void_rift_lord.faction         = "abyss_order"
	void_rift_lord.art_path             = "res://assets/art/minions/abyss_order/void_rift_lord.png"
	void_rift_lord.battlefield_art_path = "res://assets/art/minions/abyss_order/void_rift_lord_small.png"
	all.append(void_rift_lord)

	# ---------------------------------------------------------------------------
	# --- Act 4 — Void Castle enemy cards ---
	# ---------------------------------------------------------------------------

	# --- Void Spirit clan (textless, consumable as spark fuel) ---

	var void_wisp := MinionCardData.new()
	void_wisp.id            = "void_wisp"
	void_wisp.card_name     = "Void Wisp"
	void_wisp.essence_cost  = 1
	void_wisp.atk           = 150
	void_wisp.health        = 100
	void_wisp.minion_type   = Enums.MinionType.SPIRIT
	void_wisp.minion_tags   = ["void_spirit"]
	void_wisp.clan          = "Void Spirit"
	void_wisp.spark_value   = 1
	void_wisp.faction       = "abyss_order"
	void_wisp.art_path             = "res://assets/art/minions/abyss_order/void_wisp.png"
	void_wisp.battlefield_art_path = "res://assets/art/minions/abyss_order/void_wisp_small.png"
	all.append(void_wisp)

	var void_shade := MinionCardData.new()
	void_shade.id            = "void_shade"
	void_shade.card_name     = "Void Shade"
	void_shade.essence_cost  = 2
	void_shade.atk           = 250
	void_shade.health        = 200
	void_shade.minion_type   = Enums.MinionType.SPIRIT
	void_shade.minion_tags   = ["void_spirit"]
	void_shade.clan          = "Void Spirit"
	void_shade.spark_value   = 2
	void_shade.faction       = "abyss_order"
	void_shade.art_path             = "res://assets/art/minions/abyss_order/void_shade.png"
	void_shade.battlefield_art_path = "res://assets/art/minions/abyss_order/void_shade_small.png"
	all.append(void_shade)

	var void_wraith := MinionCardData.new()
	void_wraith.id            = "void_wraith"
	void_wraith.card_name     = "Void Wraith"
	void_wraith.essence_cost  = 3
	void_wraith.atk           = 300
	void_wraith.health        = 400
	void_wraith.minion_type   = Enums.MinionType.SPIRIT
	void_wraith.minion_tags   = ["void_spirit"]
	void_wraith.clan          = "Void Spirit"
	void_wraith.spark_value   = 3
	void_wraith.faction       = "abyss_order"
	void_wraith.art_path             = "res://assets/art/minions/abyss_order/void_wraith.png"
	void_wraith.battlefield_art_path = "res://assets/art/minions/abyss_order/void_wraith_small.png"
	all.append(void_wraith)

	var void_revenant := MinionCardData.new()
	void_revenant.id            = "void_revenant"
	void_revenant.card_name     = "Void Revenant"
	void_revenant.essence_cost  = 5
	void_revenant.atk           = 500
	void_revenant.health        = 500
	void_revenant.minion_type   = Enums.MinionType.SPIRIT
	void_revenant.minion_tags   = ["void_spirit"]
	void_revenant.clan          = "Void Spirit"
	void_revenant.spark_value   = 4
	void_revenant.faction       = "abyss_order"
	void_revenant.art_path             = "res://assets/art/minions/abyss_order/void_revenant.png"
	void_revenant.battlefield_art_path = "res://assets/art/minions/abyss_order/void_revenant_small.png"
	all.append(void_revenant)

	# --- Spark consumer spells ---

	var sovereigns_decree := SpellCardData.new()
	sovereigns_decree.id               = "sovereigns_decree"
	sovereigns_decree.card_name        = "Sovereign's Decree"
	sovereigns_decree.cost             = 2
	sovereigns_decree.void_spark_cost  = 2
	sovereigns_decree.description      = "Deal 300 damage to the enemy hero. Apply 2 Corruption to all enemy minions."
	sovereigns_decree.effect_steps     = [
		{"type": "DAMAGE_HERO", "amount": 300},
		{"type": "CORRUPTION", "scope": "ALL_ENEMY", "amount": 2},
	]
	sovereigns_decree.faction          = "abyss_order"
	sovereigns_decree.art_path         = "res://assets/art/spells/abyss_order/sovereigns_decree.png"
	all.append(sovereigns_decree)

	var thrones_command := SpellCardData.new()
	thrones_command.id               = "thrones_command"
	thrones_command.card_name        = "Throne's Command"
	thrones_command.cost             = 1
	thrones_command.void_spark_cost  = 3
	thrones_command.description      = "Grant all friendly minions +1 Critical Strike."
	thrones_command.effect_steps     = [{"type": "GRANT_CRITICAL_STRIKE", "scope": "ALL_FRIENDLY", "amount": 1}]
	thrones_command.faction          = "abyss_order"
	thrones_command.art_path         = "res://assets/art/spells/abyss_order/thrones_command.png"
	all.append(thrones_command)

	# --- Spark consumer minion ---

	var bastion_colossus := MinionCardData.new()
	bastion_colossus.id                   = "bastion_colossus"
	bastion_colossus.card_name            = "Bastion Colossus"
	bastion_colossus.essence_cost         = 4
	bastion_colossus.void_spark_cost      = 4
	bastion_colossus.description          = "ON PLAY: Gain 2 stacks of Critical Strike."
	bastion_colossus.atk                  = 600
	bastion_colossus.health               = 800
	bastion_colossus.minion_type          = Enums.MinionType.SPIRIT
	bastion_colossus.keywords             = [Enums.Keyword.GUARD]
	bastion_colossus.on_play_effect_steps = [{"type": "GRANT_CRITICAL_STRIKE", "scope": "SELF", "amount": 2}]
	bastion_colossus.faction              = "abyss_order"
	bastion_colossus.art_path             = "res://assets/art/minions/abyss_order/bastion_colossus.png"
	bastion_colossus.battlefield_art_path = "res://assets/art/minions/abyss_order/bastion_colossus_small.png"
	all.append(bastion_colossus)

	# --- Non-spark spells ---

	var sovereigns_edict := SpellCardData.new()
	sovereigns_edict.id          = "sovereigns_edict"
	sovereigns_edict.card_name   = "Sovereign's Edict"
	sovereigns_edict.cost        = 3
	sovereigns_edict.description = "Grant all current friendly minions 'ON DEATH: Summon a Void Spark.'"
	sovereigns_edict.effect_steps = [{"type": "GRANT_ON_DEATH_SUMMON", "scope": "ALL_FRIENDLY", "card_id": "void_spark"}]
	sovereigns_edict.faction     = "abyss_order"
	sovereigns_edict.art_path    = "res://assets/art/spells/abyss_order/sovereigns_edict.png"
	all.append(sovereigns_edict)

	# --- Non-spark minion ---

	var sovereigns_herald := MinionCardData.new()
	sovereigns_herald.id                       = "sovereigns_herald"
	sovereigns_herald.card_name                = "Sovereign's Herald"
	sovereigns_herald.essence_cost             = 2
	sovereigns_herald.description              = "ON PLAY: Grant a target friendly minion +1 Critical Strike."
	sovereigns_herald.atk                      = 200
	sovereigns_herald.health                   = 200
	sovereigns_herald.minion_type              = Enums.MinionType.DEMON
	sovereigns_herald.on_play_requires_target  = true
	sovereigns_herald.on_play_target_type      = "friendly_minion"
	sovereigns_herald.on_play_effect_steps     = [{"type": "GRANT_CRITICAL_STRIKE", "scope": "SINGLE_CHOSEN_FRIENDLY", "amount": 1}]
	sovereigns_herald.faction                  = "abyss_order"
	sovereigns_herald.art_path                 = "res://assets/art/minions/abyss_order/sovereigns_herald.png"
	sovereigns_herald.battlefield_art_path     = "res://assets/art/minions/abyss_order/sovereigns_herald_small.png"
	all.append(sovereigns_herald)

	# --- Pool assignments (controls deck builder visibility and collection) ---
	# "" = token/internal; cards with no entry stay ""
	var _card_pools := {
		# Abyss core (starter deck pool)
		"void_imp": "abyss_core",         "shadow_hound": "abyss_core",
		"abyssal_brute": "abyss_core",    "nyx_ael": "abyss_core",
		"abyss_cultist": "abyss_core",    "void_netter": "abyss_core",
		"corruption_weaver": "abyss_core","soul_collector": "abyss_core",
		"void_stalker": "abyss_core",     "void_spawner": "abyss_core",
		"abyssal_tide": "abyss_core",     "void_devourer": "abyss_core",
		"void_bolt": "abyss_core",        "dark_empowerment": "abyss_core",
		"abyssal_sacrifice": "abyss_core","abyssal_plague": "abyss_core",
		"void_summoning": "abyss_core",   "void_execution": "abyss_core",
		"dark_covenant": "abyss_core",    "abyssal_summoning_circle": "abyss_core",
		"void_rune": "abyss_core",        "blood_rune": "abyss_core",
		"dominion_rune": "abyss_core",    "shadow_rune": "abyss_core",
		# Neutral core (starter deck pool)
		"roadside_drifter": "neutral_core",  "ashland_forager": "neutral_core",
		"freelance_sellsword": "neutral_core","traveling_merchant": "neutral_core",
		"trapbreaker_rogue": "neutral_core", "caravan_guard": "neutral_core",
		"arena_challenger": "neutral_core",  "spell_taxer": "neutral_core",
		"saboteur_adept": "neutral_core",    "aether_bulwark": "neutral_core",
		"bulwark_automaton": "neutral_core", "wandering_warden": "neutral_core",
		"ruins_archivist": "neutral_core",   "wildland_behemoth": "neutral_core",
		"stone_sentinel": "neutral_core",    "rift_leviathan": "neutral_core",
		"energy_conversion": "neutral_core", "arcane_strike": "neutral_core",
		"purge": "neutral_core",             "cyclone": "neutral_core",
		"tactical_planning": "neutral_core", "precision_strike": "neutral_core",
		"hurricane": "neutral_core",         "flux_siphon": "neutral_core",
		"hidden_ambush": "neutral_core",     "smoke_veil": "neutral_core",
		"silence_trap": "neutral_core",      "death_trap": "neutral_core",
		# Lord Vael — Piercing Void unlock pool
		"font_of_the_depths": "vael_piercing_void",
		"mark_the_target": "vael_piercing_void",
		"void_detonation": "vael_piercing_void",
		"abyssal_arcanist": "vael_piercing_void",
		"void_archmagus": "vael_piercing_void",
		"abyss_ritual_circle": "vael_piercing_void",
		# Lord Vael — common unlock pool
		"imp_recruiter": "vael_common",  "blood_pact": "vael_common",
		"soul_taskmaster": "vael_common","soul_shatter": "vael_common",
		"void_amplifier": "vael_common", "soul_rune": "vael_common",
		# Lord Vael — Endless Tide unlock pool (imp_evolution talent)
		"imp_frenzy": "vael_endless_tide",       "imp_martyr": "vael_endless_tide",
		"imp_vessel": "vael_endless_tide",        "imp_idol": "vael_endless_tide",
		"vaels_colossal_guard": "vael_endless_tide",
		# Lord Vael — Rune Master unlock pool (rune_caller talent)
		"runic_blast": "vael_rune_master",       "runic_echo": "vael_rune_master",
		"rune_warden": "vael_rune_master",        "rune_seeker": "vael_rune_master",
		"echo_rune": "vael_rune_master",
		# Feral Imp Clan — Act 1 enemy-only pool (not visible to players)
		"rabid_imp": "feral_imp_clan",             "brood_imp": "feral_imp_clan",
		"imp_brawler": "feral_imp_clan",           "void_touched_imp": "feral_imp_clan",
		"frenzied_imp": "feral_imp_clan",          "matriarchs_broodling": "feral_imp_clan",
		"rogue_imp_elder": "feral_imp_clan",
		"feral_surge": "feral_imp_clan",           "void_screech": "feral_imp_clan",
		"brood_call": "feral_imp_clan",            "pack_frenzy": "feral_imp_clan",
		# Abyss Dungeon — Act 2 enemy-only pool (not visible to players)
		"cult_fanatic": "abyss_cultist_clan",     "dark_command": "abyss_cultist_clan",
		# Void Rift World — Act 3 enemy-only pool (not visible to players)
		"void_pulse": "void_rift",              "phase_stalker": "void_rift",
		"rift_collapse": "void_rift",           "void_behemoth": "void_rift",
		"dimensional_breach": "void_rift",      "void_rift_lord": "void_rift",
		# Void Castle — Act 4 enemy-only pool (not visible to players)
		"void_wisp": "void_castle",            "void_shade": "void_castle",
		"void_wraith": "void_castle",          "void_revenant": "void_castle",
		"sovereigns_decree": "void_castle",    "thrones_command": "void_castle",
		"bastion_colossus": "void_castle",     "sovereigns_edict": "void_castle",
		"sovereigns_herald": "void_castle",
	}
	# --- Act gate assignments (earliest act card appears in rewards/shop) ---
	var _card_act_gates := {
		# Piercing Void pool
		"font_of_the_depths": 1,
		"mark_the_target": 2,
		"void_detonation": 2,
		"abyssal_arcanist": 1,
		"void_archmagus": 4,
		"abyss_ritual_circle": 3,
		# Vael common pool
		"imp_recruiter": 1,               "blood_pact": 1,
		"soul_taskmaster": 2,             "soul_shatter": 2,
		"void_amplifier": 3,              "soul_rune": 3,
		# Endless Tide pool
		"imp_frenzy": 1,                  "imp_martyr": 2,
		"imp_vessel": 2,                  "imp_idol": 3,
		"vaels_colossal_guard": 4,
		# Rune Master pool
		"runic_blast": 1,                 "rune_seeker": 1,
		"rune_warden": 2,                 "runic_echo": 3,
		"echo_rune": 4,
	}
	# Append all token cards (pool = "", rarity = "")
	for td in _TOKEN_DEFS:
		all.append(_make_token(td))

	for c in all:
		c.pool   = _card_pools.get(c.id, "")
		c.act_gate = _card_act_gates.get(c.id, 0)

	for c in all:
		_register(c)
