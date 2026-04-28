## CardDatabase.gd
## Autoload — holds every card definition in the game.
## Access any card by ID: CardDatabase.get_card("void_imp")
##
## STAT SCALE: all ATK, HP, Shield, and damage numbers use a ×100 base
## so that percentage-based talent modifiers have integer granularity.
## (e.g. a 300 ATK minion can receive +5% = +15 ATK from a talent.)
extends Node

const _CardModRules = preload("res://cards/data/CardModRules.gd")

## All registered cards keyed by their id string
var _cards: Dictionary = {}

## Override-applied card cache, keyed by "<id>|<sorted_relevant_talents>".
## Cleared per-combat via clear_override_cache(). Lets get_card_for_combat()
## return a stable instance per (card, talent-set) so identity comparisons and
## repeated lookups don't allocate.
var _override_cache: Dictionary = {}

# ---------------------------------------------------------------------------
# Token definitions — compact table for tokens summoned by card effects.
# Fields: id, name, atk, hp, type (Enums.MinionType key), faction, desc,
#         shield (optional, default 0), tags (optional), art (optional)
# ---------------------------------------------------------------------------
const _TOKEN_DEFS: Array[Dictionary] = [
	{"id": "void_spark", "name": "Void Spark", "atk": 100, "hp": 100, "type": "SPIRIT", "faction": "abyss_order", "desc": "", "spark_value": 1, "art": "res://assets/art/minions/abyss_order/void_spark.png"},
	{"id": "void_demon", "name": "Void Demon", "atk": 200, "hp": 200, "type": "DEMON",  "faction": "abyss_order", "desc": "", "art": "res://assets/art/minions/abyss_order/void_demon.png"},
	{"id": "lesser_demon", "name": "Lesser Demon", "atk": 400, "hp": 400, "type": "DEMON", "faction": "abyss_order", "desc": "Summoned by Seris's Fiend Offering.", "tags": ["lesser_demon", "demon"], "art": "res://assets/art/minions/abyss_order/lesser_demon.png"},
	{"id": "forged_demon", "name": "Forged Demon", "atk": 500, "hp": 500, "type": "DEMON", "faction": "abyss_order", "desc": "Forged by Seris's Soul Forge.",    "tags": ["forged_demon", "demon"], "art": "res://assets/art/minions/abyss_order/forged_demon.png"},
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
	return c

func _ready() -> void:
	_register_wanderer_cards()

## Returns the CardData resource for a given id, or null if not found.
## STATIC LOOKUP — no talent overrides applied. Use this from menus, deck builder,
## collection, descriptions, tests, and any non-combat surface.
func get_card(id: String) -> CardData:
	if _cards.has(id):
		return _cards[id]
	push_error("CardDatabase: unknown card id '%s'" % id)
	return null

## Returns the CardData with talent_overrides + CardModRules applied for the given
## side's talents and passives. Use this when CONSTRUCTING NEW COMBAT CONTENT —
## token summons, copy-to-hand, draw helpers, deck/hand initialization at combat
## start. Anywhere a CardInstance will be created and used during combat.
##
## ctx keys (all optional, defaults treat the side as having nothing active):
##   "side":           "player" | "enemy"        (default "player")
##   "talents":        Array[String]              (default [])
##   "hero_passives":  Array[String]              (default [])
##   "enemy_passives": Array[String]              (default [])
##
## Composition order:
##   1. Per-card talent_overrides apply first (replacement on the duplicate).
##   2. CardModRules apply second as deltas on the post-override values.
##
## - Returns the base card unchanged when no overrides or rules match.
## - Caches by (card_id, sorted-relevant-keys) so repeat lookups are O(1).
func get_card_for_combat(id: String, ctx: Dictionary) -> CardData:
	var base: CardData = _cards.get(id)
	if base == null:
		push_error("CardDatabase: unknown card id '%s'" % id)
		return null

	var side: String = ctx.get("side", "player")
	var talents: Array[String] = []
	talents.assign(ctx.get("talents", []))
	var hero_passives: Array[String] = []
	hero_passives.assign(ctx.get("hero_passives", []))
	var enemy_passives: Array[String] = []
	enemy_passives.assign(ctx.get("enemy_passives", []))

	# Compute the relevant keys that actually affect THIS card so the cache key
	# is stable regardless of unrelated unlocks. talent_id matches against ANY
	# of the side's active lists (talents, hero_passives, enemy_passives) — IDs
	# are unique across categories, so a single name resolves unambiguously.
	var relevant_overrides: Array[String] = []
	for ovr_any in base.talent_overrides:
		var ovr: Dictionary = ovr_any
		var t: String = ovr.get("talent_id", "")
		if t == "" or t in relevant_overrides:
			continue
		var active: bool = (t in talents) or (t in hero_passives) or (t in enemy_passives)
		if active:
			relevant_overrides.append(t)
	relevant_overrides.sort()

	var matching: Array = _CardModRules.matching_rules(base, side, talents, hero_passives, enemy_passives)
	var matching_ids: Array[String] = []
	for r in matching:
		matching_ids.append((r as Dictionary).get("id", ""))
	matching_ids.sort()

	if relevant_overrides.is_empty() and matching.is_empty():
		return base

	var cache_key: String = "%s|%s|%s|%s" % [id, side, "|".join(relevant_overrides), "|".join(matching_ids)]
	if _override_cache.has(cache_key):
		return _override_cache[cache_key]

	# Shallow-duplicate the resource, then deep-copy any field we actually
	# overwrite. Avoids relying on duplicate(true) deep-copy semantics for
	# nested arrays-of-dicts.
	var clone: CardData = base.duplicate(false)

	# Step 1: per-card overrides (replacement)
	for ovr_any in base.talent_overrides:
		var ovr: Dictionary = ovr_any
		if not (ovr.get("talent_id", "") in relevant_overrides):
			continue
		for field in ovr:
			if field == "talent_id":
				continue
			if not (field in clone):
				push_warning("CardDatabase: talent_override on '%s' references unknown field '%s'" % [id, field])
				continue
			var val = ovr[field]
			if val is Array or val is Dictionary:
				val = _deep_copy(val)
			clone.set(field, val)

	# Step 2: clan/filter delta rules (additive on top of overrides)
	for rule_any in matching:
		var rule: Dictionary = rule_any
		if rule.has("atk_delta") and "atk" in clone:
			clone.set("atk", clone.get("atk") + int(rule.atk_delta))
		if rule.has("hp_delta") and "health" in clone:
			clone.set("health", clone.get("health") + int(rule.hp_delta))
		if rule.has("cost_delta"):
			# CardData.cost (mana cost) is the universal cost field; minions also
			# carry essence_cost. Apply cost_delta to the field that's actually
			# being used for this card type. Spells/traps/environments use cost;
			# minions use essence_cost (+ optional mana_cost).
			if clone is MinionCardData:
				var mc: MinionCardData = clone
				mc.essence_cost = max(0, mc.essence_cost + int(rule.cost_delta))
			else:
				clone.cost = max(0, clone.cost + int(rule.cost_delta))

	_override_cache[cache_key] = clone
	return clone

## Deep copy for nested Array/Dictionary structures of plain values
## (no Resources). Used to isolate override field values from their source dicts.
func _deep_copy(v: Variant) -> Variant:
	if v is Array:
		var out_a: Array = []
		for item in (v as Array):
			out_a.append(_deep_copy(item))
		return out_a
	if v is Dictionary:
		var out_d: Dictionary = {}
		for k in (v as Dictionary):
			out_d[k] = _deep_copy(v[k])
		return out_d
	return v

## Drop all override-applied clones. Called at combat start so a different
## hero/talent set in the next combat doesn't reuse stale overrides.
func clear_override_cache() -> void:
	_override_cache.clear()

## Returns all registered card IDs
func get_all_card_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _cards.keys():
		ids.append(key as String)
	return ids

## Returns card IDs that belong to any of the requested pools. Uses set intersection,
## so a dual-pool card (e.g. soul_shatter in vael_common + seris_demon_forge) is returned
## by either lookup but never duplicated.
func get_card_ids_in_pools(pools: Array[String]) -> Array[String]:
	var ids: Array[String] = []
	for key in _cards.keys():
		var card: CardData = _cards[key]
		for p in card.pools:
			if p in pools:
				ids.append(key as String)
				break
	return ids

## Returns a list of CardData for a given array of ids
func get_cards(ids: Array[String]) -> Array[CardData]:
	var result: Array[CardData] = []
	for id in ids:
		var card := get_card(id)
		if card:
			result.append(card)
	return result

## Combat-time batch lookup. Mirrors get_cards() but applies talent_overrides
## and CardModRules per the side's ctx. Use for deck/hand init at combat start.
func get_cards_for_combat(ids: Array[String], ctx: Dictionary) -> Array[CardData]:
	var result: Array[CardData] = []
	for id in ids:
		var card := get_card_for_combat(id, ctx)
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
	void_imp.description    = "ON PLAY: Deal 100 damage to enemy hero."
	void_imp.atk            = 100
	void_imp.health         = 100
	void_imp.minion_type    = Enums.MinionType.DEMON
	void_imp.on_play_effect_steps = [{"type": "DAMAGE_HERO", "amount": 100, "conditions": ["no_piercing_void"]}]
	# piercing_void talent (Void Bolt T0): Void Imp costs +1 Mana (base 1E, becomes
	# 1E+1M). The on-play retag (200 Void Bolt damage + 1 Void Mark) lives in
	# on_summon_piercing_void handler — keeping that path because it routes through
	# scene-specific Void Bolt damage helpers and VFX that don't translate cleanly
	# to a declarative effect-step swap. Cost change is pure data, fits the override.
	void_imp.talent_overrides = [
		{ "talent_id": "piercing_void", "mana_cost": 1 },
	]
	void_imp.minion_tags    = ["void_imp", "base_void_imp"]
	void_imp.faction        = "abyss_order"
	void_imp.clan           = "Void Imp"
	void_imp.art_path             = "res://assets/art/minions/abyss_order/void_imp.png"
	all.append(void_imp)

	# Senior Void Imp — added to hand by Imp Evolution talent; counts as Void Imp
	var senior_void_imp := MinionCardData.new()
	senior_void_imp.id           = "senior_void_imp"
	senior_void_imp.card_name    = "Senior Void Imp"
	senior_void_imp.essence_cost = 2
	senior_void_imp.description  = "ON PLAY: Deal 100 damage to enemy hero."
	senior_void_imp.atk          = 300
	senior_void_imp.health       = 250
	senior_void_imp.minion_type  = Enums.MinionType.DEMON
	senior_void_imp.on_play_effect_steps = [{"type": "DAMAGE_HERO", "amount": 100, "conditions": ["no_piercing_void"]}]
	senior_void_imp.minion_tags          = ["void_imp", "senior_void_imp"]
	senior_void_imp.faction              = "abyss_order"
	senior_void_imp.clan                 = "Void Imp"
	senior_void_imp.art_path             = "res://assets/art/minions/abyss_order/senior_void_imp.png"
	all.append(senior_void_imp)

	# Runic Void Imp — variant core unit; offered via special reward
	var runic_void_imp := MinionCardData.new()
	runic_void_imp.id                    = "runic_void_imp"
	runic_void_imp.card_name             = "Runic Void Imp"
	runic_void_imp.essence_cost          = 2
	runic_void_imp.mana_cost             = 1
	runic_void_imp.description           = "ON PLAY: Deal 300 damage to an enemy minion."
	runic_void_imp.atk                   = 200
	runic_void_imp.health                = 300
	runic_void_imp.minion_type           = Enums.MinionType.DEMON
	runic_void_imp.on_play_effect_steps  = [{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 300}]
	runic_void_imp.on_play_target_optional = true
	runic_void_imp.on_play_target_type     = "enemy_minion"
	runic_void_imp.on_play_target_prompt   = "Click an enemy minion to deal 300 damage, or click a slot to summon without effect."
	runic_void_imp.minion_tags           = ["void_imp", "runic_void_imp"]
	runic_void_imp.faction               = "abyss_order"
	runic_void_imp.clan                  = "Void Imp"
	runic_void_imp.art_path              = "res://assets/art/minions/abyss_order/runic_void_imp.png"
	all.append(runic_void_imp)

	# Grafted Fiend — Seris core unit. Deck cap raised to 4 by Grafted Affinity passive.
	var grafted_fiend := MinionCardData.new()
	grafted_fiend.id             = "grafted_fiend"
	grafted_fiend.card_name      = "Grafted Fiend"
	grafted_fiend.essence_cost   = 3
	grafted_fiend.description    = ""
	grafted_fiend.atk            = 300
	grafted_fiend.health         = 300
	grafted_fiend.minion_type    = Enums.MinionType.DEMON
	grafted_fiend.minion_tags    = ["grafted_fiend"]
	grafted_fiend.faction        = "abyss_order"
	grafted_fiend.art_path             = "res://assets/art/minions/abyss_order/grafted_fiend.png"
	all.append(grafted_fiend)

	# --- Seris Core Pool ------------------------------------------------------
	# Hero-gated starter pool visible only when Seris is the active hero. Pool
	# assignment lives in the _card_pools dict at the bottom of this file.

	# Void Spawning — 1M, two 100/100 Void Demon tokens. Early board + Flesh fuel.
	var void_spawning := SpellCardData.new()
	void_spawning.id          = "void_spawning"
	void_spawning.card_name   = "Void Spawning"
	void_spawning.cost        = 1
	void_spawning.description = "Summon two 100/100 Void Demons."
	void_spawning.effect_steps = [
		{"type": "SUMMON", "card_id": "void_demon", "token_atk": 100, "token_hp": 100},
		{"type": "SUMMON", "card_id": "void_demon", "token_atk": 100, "token_hp": 100},
	]
	void_spawning.art_path    = "res://assets/art/spells/abyss_order/void_spawning.png"
	void_spawning.faction     = "abyss_order"
	all.append(void_spawning)

	# Fiendish Pact — 1M, draw + cheapen next Demon played this turn.
	var fiendish_pact := SpellCardData.new()
	fiendish_pact.id          = "fiendish_pact"
	fiendish_pact.card_name   = "Fiendish Pact"
	fiendish_pact.cost        = 1
	fiendish_pact.description = "Draw a card. Your next Demon costs 2 less Essence this turn."
	fiendish_pact.effect_steps = [
		{"type": "DRAW", "amount": 1},
		{"type": "HARDCODED", "hardcoded_id": "fiendish_pact"},
	]
	fiendish_pact.art_path    = "res://assets/art/spells/abyss_order/fiendish_pact.png"
	fiendish_pact.faction     = "abyss_order"
	all.append(fiendish_pact)

	# Grafted Butcher — 2E minion. ON PLAY: sacrifice a friendly minion, then 200 AoE.
	var grafted_butcher := MinionCardData.new()
	grafted_butcher.id              = "grafted_butcher"
	grafted_butcher.card_name       = "Grafted Butcher"
	grafted_butcher.essence_cost    = 2
	grafted_butcher.atk             = 200
	grafted_butcher.health          = 100
	grafted_butcher.minion_type     = Enums.MinionType.DEMON
	grafted_butcher.description     = "ON PLAY: SACRIFICE another friendly minion. Deal 200 damage to all enemy minions."
	grafted_butcher.on_play_requires_target = true
	grafted_butcher.on_play_target_type   = "friendly_minion_other"
	grafted_butcher.on_play_target_prompt = "Click a friendly minion to sacrifice."
	grafted_butcher.on_play_effect_steps  = [{"type": "HARDCODED", "hardcoded_id": "grafted_butcher"}]
	grafted_butcher.art_path        = "res://assets/art/minions/abyss_order/grafted_butcher.png"
	grafted_butcher.faction         = "abyss_order"
	all.append(grafted_butcher)

	# Flesh Rend — 2M, 300 damage, doubled at 3+ Flesh.
	var flesh_rend := SpellCardData.new()
	flesh_rend.id              = "flesh_rend"
	flesh_rend.card_name       = "Flesh Rend"
	flesh_rend.cost            = 2
	flesh_rend.description     = "Deal 300 damage to a minion or enemy hero. If you have 3+ Flesh, deal 600 instead."
	flesh_rend.requires_target = true
	flesh_rend.target_type     = "any_minion_or_enemy_hero"
	flesh_rend.effect_steps    = [
		{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 300, "bonus_amount": 300, "bonus_conditions": ["flesh_gte_3"]},
	]
	flesh_rend.art_path        = "res://assets/art/spells/abyss_order/flesh_rend.png"
	flesh_rend.faction         = "abyss_order"
	all.append(flesh_rend)

	# --- end Seris Core Pool --------------------------------------------------

	# --- Seris Common Support Pool --------------------------------------------
	# Branch-neutral cards offered as combat rewards and shop picks for Seris.
	# Flesh-spend semantics (see feedback_flesh_spend_semantics):
	#   SPEND_FLESH       = all-or-nothing; enhanced effects gated via "flesh_spent_this_cast".
	#   SPEND_FLESH_UP_TO = partial; bonuses scale via bonus_conditions + flesh_spent_this_cast.

	# Flesh Harvester — 2E Demon 200/300. ON PLAY: gain 1 Flesh.
	var flesh_harvester := MinionCardData.new()
	flesh_harvester.id           = "flesh_harvester"
	flesh_harvester.card_name    = "Flesh Harvester"
	flesh_harvester.essence_cost = 2
	flesh_harvester.atk          = 200
	flesh_harvester.health       = 300
	flesh_harvester.minion_type  = Enums.MinionType.DEMON
	flesh_harvester.description  = "ON PLAY: Gain 1 Flesh."
	flesh_harvester.on_play_effect_steps = [
		{"type": "GAIN_FLESH", "amount": 1},
	]
	flesh_harvester.art_path     = "res://assets/art/minions/abyss_order/flesh_harvester.png"
	flesh_harvester.faction      = "abyss_order"
	all.append(flesh_harvester)

	# Ravenous Fiend — 3E Demon 400/300. ON DEATH: gain 2 Flesh.
	var ravenous_fiend := MinionCardData.new()
	ravenous_fiend.id           = "ravenous_fiend"
	ravenous_fiend.card_name    = "Ravenous Fiend"
	ravenous_fiend.essence_cost = 3
	ravenous_fiend.atk          = 400
	ravenous_fiend.health       = 300
	ravenous_fiend.minion_type  = Enums.MinionType.DEMON
	ravenous_fiend.description  = "ON DEATH: Gain 2 Flesh."
	ravenous_fiend.on_death_effect_steps = [
		{"type": "GAIN_FLESH", "amount": 2},
	]
	ravenous_fiend.art_path     = "res://assets/art/minions/abyss_order/ravenous_fiend.png"
	ravenous_fiend.faction      = "abyss_order"
	all.append(ravenous_fiend)

	# Feast of Flesh — 1M Spell. Sacrifice a friendly Demon. Gain 2 Flesh. Draw 1.
	var feast_of_flesh := SpellCardData.new()
	feast_of_flesh.id              = "feast_of_flesh"
	feast_of_flesh.card_name       = "Feast of Flesh"
	feast_of_flesh.cost            = 1
	feast_of_flesh.description     = "Sacrifice a friendly Demon. Gain 2 Flesh. Draw a card."
	feast_of_flesh.requires_target = true
	feast_of_flesh.target_type     = "friendly_minion"
	feast_of_flesh.effect_steps    = [
		{"type": "SACRIFICE", "scope": "SINGLE_CHOSEN_FRIENDLY", "filter": "DEMON"},
		{"type": "GAIN_FLESH", "amount": 2},
		{"type": "DRAW", "amount": 1},
	]
	feast_of_flesh.art_path        = "res://assets/art/spells/abyss_order/feast_of_flesh.png"
	feast_of_flesh.faction         = "abyss_order"
	all.append(feast_of_flesh)

	# Mend the Flesh — 1M Spell. AoE heal 200; 350 if 1 Flesh spent.
	var mend_the_flesh := SpellCardData.new()
	mend_the_flesh.id          = "mend_the_flesh"
	mend_the_flesh.card_name   = "Mend the Flesh"
	mend_the_flesh.cost        = 1
	mend_the_flesh.description = "Heal all friendly minions for 200 HP. Spend 1 Flesh: heal 350 HP instead."
	mend_the_flesh.effect_steps = [
		{"type": "SPEND_FLESH", "amount": 1},
		{"type": "HEAL_MINION", "scope": "ALL_FRIENDLY", "amount": 200,
			"bonus_amount": 150, "bonus_conditions": ["flesh_spent_this_cast"]},
	]
	mend_the_flesh.art_path    = "res://assets/art/spells/abyss_order/mend_the_flesh.png"
	mend_the_flesh.faction     = "abyss_order"
	all.append(mend_the_flesh)

	# Flesh Eruption — 3M Spell. 250 to all enemies (minions + hero); 400 if 2 Flesh spent.
	var flesh_eruption := SpellCardData.new()
	flesh_eruption.id          = "flesh_eruption"
	flesh_eruption.card_name   = "Flesh Eruption"
	flesh_eruption.cost        = 3
	flesh_eruption.description = "Deal 250 damage to all enemies. Spend 2 Flesh: deal 400 damage instead."
	flesh_eruption.effect_steps = [
		{"type": "SPEND_FLESH", "amount": 2},
		{"type": "DAMAGE_MINION", "scope": "ALL_ENEMY", "amount": 250,
			"bonus_amount": 150, "bonus_conditions": ["flesh_spent_this_cast"]},
		{"type": "DAMAGE_HERO", "amount": 250,
			"bonus_amount": 150, "bonus_conditions": ["flesh_spent_this_cast"]},
	]
	flesh_eruption.art_path    = "res://assets/art/spells/abyss_order/flesh_eruption.png"
	flesh_eruption.faction     = "abyss_order"
	all.append(flesh_eruption)

	# Gorged Fiend — 3E Demon 300/300. ON PLAY: spend up to 3 Flesh, +150/+150 per spent.
	var gorged_fiend := MinionCardData.new()
	gorged_fiend.id           = "gorged_fiend"
	gorged_fiend.card_name    = "Gorged Fiend"
	gorged_fiend.essence_cost = 3
	gorged_fiend.atk          = 300
	gorged_fiend.health       = 300
	gorged_fiend.minion_type  = Enums.MinionType.DEMON
	gorged_fiend.description  = "ON PLAY: Spend up to 3 Flesh. Gain +150 ATK and +150 HP per Flesh spent."
	gorged_fiend.on_play_effect_steps = [
		{"type": "SPEND_FLESH_UP_TO", "amount": 3},
		{"type": "BUFF_ATK", "scope": "SELF", "amount": 150, "multiplier_key": "flesh_spent",
			"permanent": true, "source_tag": "gorged_fiend", "conditions": ["flesh_spent_this_cast"]},
		{"type": "BUFF_HP",  "scope": "SELF", "amount": 150, "multiplier_key": "flesh_spent",
			"source_tag": "gorged_fiend", "conditions": ["flesh_spent_this_cast"]},
	]
	gorged_fiend.art_path     = "res://assets/art/minions/abyss_order/gorged_fiend.png"
	gorged_fiend.faction      = "abyss_order"
	all.append(gorged_fiend)

	# Flesh-Stitched Horror — 4E Demon 400/400. ON PLAY: spend 2 Flesh → GUARD and +300 HP.
	var flesh_stitched_horror := MinionCardData.new()
	flesh_stitched_horror.id           = "flesh_stitched_horror"
	flesh_stitched_horror.card_name    = "Flesh-Stitched Horror"
	flesh_stitched_horror.essence_cost = 4
	flesh_stitched_horror.atk          = 400
	flesh_stitched_horror.health       = 400
	flesh_stitched_horror.minion_type  = Enums.MinionType.DEMON
	flesh_stitched_horror.description  = "ON PLAY: Spend 2 Flesh: gain GUARD and +300 HP."
	flesh_stitched_horror.on_play_effect_steps = [
		{"type": "SPEND_FLESH", "amount": 2},
		{"type": "GRANT_KEYWORD", "scope": "SELF", "keyword": "GUARD",
			"source_tag": "flesh_stitched_horror", "conditions": ["flesh_spent_this_cast"]},
		{"type": "BUFF_HP", "scope": "SELF", "amount": 300,
			"source_tag": "flesh_stitched_horror", "conditions": ["flesh_spent_this_cast"]},
	]
	flesh_stitched_horror.art_path     = "res://assets/art/minions/abyss_order/flesh_stitched_horror.png"
	flesh_stitched_horror.faction      = "abyss_order"
	all.append(flesh_stitched_horror)

	# Flesh Rune — 2M Rune. Start of turn: destroy if <2 Flesh, else spend 2 and summon 300/300 Void Spark.
	var flesh_rune := TrapCardData.new()
	flesh_rune.id             = "flesh_rune"
	flesh_rune.card_name      = "Flesh Rune"
	flesh_rune.cost           = 2
	flesh_rune.description    = "RUNE: At the start of your turn, spend 2 Flesh: summon a 300/300 Void Spark. If you do not have enough Flesh, destroy this Rune."
	flesh_rune.is_rune        = true
	# Reuse VOID_RUNE glow/type for now — dedicated RuneType enum entry can be added later if needed.
	flesh_rune.rune_type      = Enums.RuneType.VOID_RUNE
	flesh_rune.aura_trigger   = Enums.TriggerEvent.ON_PLAYER_TURN_START
	flesh_rune.aura_effect_steps = [
		# Self-destruct first if we cannot afford the upkeep. Destroying the rune
		# mid-run still allows the subsequent steps to short-circuit via the gate.
		{"type": "DESTROY", "scope": "SOURCE_RUNE", "conditions": ["flesh_lt_2"]},
		# Pay the upkeep.
		{"type": "SPEND_FLESH", "amount": 2, "conditions": ["flesh_gte_2"]},
		# Summon a 300/300 Void Spark only on successful spend.
		{"type": "SUMMON", "card_id": "void_spark", "token_atk": 300, "token_hp": 300,
			"conditions": ["flesh_spent_this_cast"]},
	]
	flesh_rune.faction        = "abyss_order"
	flesh_rune.art_path      = "res://assets/art/traps/abyss_order/flesh_rune.png"
	flesh_rune.battlefield_art_path = "res://assets/art/traps/abyss_order/flesh_rune_battlefield.png"
	flesh_rune.rune_glow_color = Color(0.55, 0.08, 0.08, 1)  # Deep red, like Blood Rune
	all.append(flesh_rune)

	# --- end Seris Common Support Pool ----------------------------------------

	# --- Seris Fleshcraft Pool ------------------------------------------------
	# Branch 1 support pool. Unlocked when player takes flesh_infusion (Fleshcraft T0).
	# See RewardScene._get_active_support_pool_ids. All members share the grafted_fiend
	# clan where applicable so on-entry aura multipliers and on-death hooks line up.

	# Grafted Reaver — 2E Grafted Fiend 200/300. ON PLAY: +100 ATK per other friendly Grafted Fiend.
	var grafted_reaver := MinionCardData.new()
	grafted_reaver.id           = "grafted_reaver"
	grafted_reaver.card_name    = "Grafted Reaver"
	grafted_reaver.essence_cost = 2
	grafted_reaver.atk          = 200
	grafted_reaver.health       = 300
	grafted_reaver.minion_type  = Enums.MinionType.DEMON
	grafted_reaver.minion_tags  = ["grafted_fiend"]
	grafted_reaver.description  = "ON PLAY: Gain +100 ATK for each other friendly Grafted Fiend."
	grafted_reaver.on_play_effect_steps = [
		{"type": "BUFF_ATK", "scope": "SELF", "amount": 100,
			"multiplier_key": "board_count", "multiplier_board": "friendly",
			"multiplier_filter": "tag", "multiplier_tag": "grafted_fiend",
			"exclude_self": true, "permanent": true, "source_tag": "grafted_reaver"},
	]
	grafted_reaver.art_path     = "res://assets/art/minions/abyss_order/grafted_reaver.png"
	grafted_reaver.faction      = "abyss_order"
	all.append(grafted_reaver)

	# Flesh Scout — 1E Grafted Fiend 100/200. ON PLAY: draw 2 if friendly Grafted Fiends have 3+ total kill stacks.
	var flesh_scout := MinionCardData.new()
	flesh_scout.id           = "flesh_scout"
	flesh_scout.card_name    = "Flesh Scout"
	flesh_scout.essence_cost = 1
	flesh_scout.atk          = 100
	flesh_scout.health       = 200
	flesh_scout.minion_type  = Enums.MinionType.DEMON
	flesh_scout.minion_tags  = ["grafted_fiend"]
	flesh_scout.description  = "ON PLAY: If friendly Grafted Fiends have 3 or more total kill stacks, draw 2 cards."
	flesh_scout.on_play_effect_steps = [
		{"type": "DRAW", "amount": 2, "conditions": ["friendly_grafted_fiend_kill_stacks_gte_3"]},
	]
	flesh_scout.art_path     = "res://assets/art/minions/abyss_order/flesh_scout.png"
	flesh_scout.faction      = "abyss_order"
	all.append(flesh_scout)

	# Flesh Surgeon — 2E Human 100/300. ON PLAY: heal a Grafted Fiend to full; spend 1 Flesh for +200 max HP.
	var flesh_surgeon := MinionCardData.new()
	flesh_surgeon.id           = "flesh_surgeon"
	flesh_surgeon.card_name    = "Flesh Surgeon"
	flesh_surgeon.essence_cost = 2
	flesh_surgeon.atk          = 100
	flesh_surgeon.health       = 300
	flesh_surgeon.minion_type  = Enums.MinionType.HUMAN
	flesh_surgeon.description  = "ON PLAY: Heal a friendly Grafted Fiend to full. Spend 1 Flesh: also give it +200 HP permanently."
	flesh_surgeon.on_play_requires_target = true
	flesh_surgeon.on_play_target_type     = "friendly_minion"
	flesh_surgeon.on_play_target_prompt   = "Choose a friendly Grafted Fiend to mend."
	flesh_surgeon.on_play_effect_steps = [
		# Try to pay — all-or-nothing. The heal always happens; the +200 max HP only if Flesh was spent.
		{"type": "SPEND_FLESH", "amount": 1},
		# Base effect: heal to current max first.
		{"type": "HEAL_MINION_FULL", "scope": "SINGLE_CHOSEN_FRIENDLY"},
		# Then raise max HP by 200 (does not refill — leaves the new buffer empty).
		{"type": "BUFF_HP", "scope": "SINGLE_CHOSEN_FRIENDLY", "amount": 200,
			"source_tag": "flesh_surgeon", "conditions": ["flesh_spent_this_cast"]},
	]
	flesh_surgeon.art_path     = "res://assets/art/minions/abyss_order/flesh_surgeon.png"
	flesh_surgeon.faction      = "abyss_order"
	all.append(flesh_surgeon)

	# Flesh Sacrament — 2M Spell. Grant 1 kill stack; Spend 2 Flesh → 3 stacks instead.
	# Grant pattern: always apply 1 stack, then apply 2 more if the spend succeeded (1 + 2 = 3).
	var flesh_sacrament := SpellCardData.new()
	flesh_sacrament.id              = "flesh_sacrament"
	flesh_sacrament.card_name       = "Flesh Sacrament"
	flesh_sacrament.cost            = 2
	flesh_sacrament.description     = "Give a friendly Grafted Fiend 1 kill stack. Spend 2 Flesh: give it 3 kill stacks instead."
	flesh_sacrament.requires_target = true
	flesh_sacrament.target_type     = "friendly_minion"
	flesh_sacrament.effect_steps = [
		{"type": "SPEND_FLESH", "amount": 2},
		{"type": "GRANT_KILL_STACKS", "scope": "SINGLE_CHOSEN_FRIENDLY", "amount": 1},
		{"type": "GRANT_KILL_STACKS", "scope": "SINGLE_CHOSEN_FRIENDLY", "amount": 2,
			"conditions": ["flesh_spent_this_cast"]},
	]
	flesh_sacrament.art_path        = "res://assets/art/spells/abyss_order/flesh_sacrament.png"
	flesh_sacrament.faction         = "abyss_order"
	all.append(flesh_sacrament)

	# Matron of Flesh — 5E Grafted Fiend 400/600. ON PLAY: +100/+100 per other friendly Fiend; on kill, gain 1 Flesh.
	var matron_of_flesh := MinionCardData.new()
	matron_of_flesh.id           = "matron_of_flesh"
	matron_of_flesh.card_name    = "Matron of Flesh"
	matron_of_flesh.essence_cost = 5
	matron_of_flesh.atk          = 400
	matron_of_flesh.health       = 600
	matron_of_flesh.minion_type  = Enums.MinionType.DEMON
	matron_of_flesh.minion_tags  = ["grafted_fiend"]
	matron_of_flesh.description  = "ON PLAY: Gain +100 ATK and +100 HP for each other friendly Grafted Fiend. Whenever this minion kills an enemy minion, gain 1 Flesh."
	matron_of_flesh.on_play_effect_steps = [
		{"type": "BUFF_ATK", "scope": "SELF", "amount": 100,
			"multiplier_key": "board_count", "multiplier_board": "friendly",
			"multiplier_filter": "tag", "multiplier_tag": "grafted_fiend",
			"exclude_self": true, "permanent": true, "source_tag": "matron_of_flesh"},
		{"type": "BUFF_HP",  "scope": "SELF", "amount": 100,
			"multiplier_key": "board_count", "multiplier_board": "friendly",
			"multiplier_filter": "tag", "multiplier_tag": "grafted_fiend",
			"exclude_self": true, "source_tag": "matron_of_flesh"},
	]
	matron_of_flesh.on_kill_effect_steps = [
		{"type": "GAIN_FLESH", "amount": 1},
	]
	matron_of_flesh.art_path     = "res://assets/art/minions/abyss_order/matron_of_flesh.png"
	matron_of_flesh.faction      = "abyss_order"
	all.append(matron_of_flesh)

	# --- end Seris Fleshcraft Pool --------------------------------------------

	# --- Seris Demon Forge Pool -----------------------------------------------
	# Branch 2 support pool. Unlocked when player takes soul_forge (Demon Forge T0).
	# Theme: sacrifice Demons to feed the Forge Counter; ON LEAVE-driven payoffs.
	# Soul Shatter (vael_common) is dual-pooled into seris_demon_forge below.

	# Altar Thrall — 2E Demon 300/300 SWIFT. End of turn: sacrifice self.
	var altar_thrall := MinionCardData.new()
	altar_thrall.id           = "altar_thrall"
	altar_thrall.card_name    = "Altar Thrall"
	altar_thrall.essence_cost = 2
	altar_thrall.atk          = 300
	altar_thrall.health       = 300
	altar_thrall.minion_type  = Enums.MinionType.DEMON
	altar_thrall.keywords     = [Enums.Keyword.SWIFT]
	altar_thrall.description  = "SWIFT. At the end of your turn, sacrifice this minion."
	altar_thrall.on_turn_end_effect_steps = [
		{"type": "SACRIFICE", "scope": "SELF"},
	]
	altar_thrall.art_path     = "res://assets/art/minions/abyss_order/altar_thrall.png"
	altar_thrall.faction      = "abyss_order"
	all.append(altar_thrall)

	# Forge Acolyte — 3E Human 100/400. Whenever you sacrifice a Demon, gain 1 Flesh.
	# Implementation: a board-presence passive listening on ON_PLAYER_MINION_SACRIFICED.
	# Uses passive_effect_id pattern (existing string-dispatch system) so the listener
	# stays narrow and on-scene. NOTE: passive_effect_id today only fires on death; we
	# need to extend the dispatcher to also handle sacrifice. Done below.
	var forge_acolyte := MinionCardData.new()
	forge_acolyte.id                 = "forge_acolyte"
	forge_acolyte.card_name          = "Forge Acolyte"
	forge_acolyte.essence_cost       = 3
	forge_acolyte.atk                = 100
	forge_acolyte.health             = 400
	forge_acolyte.minion_type        = Enums.MinionType.HUMAN
	forge_acolyte.description        = "PASSIVE: Whenever you sacrifice a Demon, gain 1 Flesh."
	forge_acolyte.passive_effect_id  = "forge_acolyte_flesh_on_sacrifice"
	forge_acolyte.art_path           = "res://assets/art/minions/abyss_order/forge_acolyte.png"
	forge_acolyte.faction            = "abyss_order"
	all.append(forge_acolyte)

	# Ember Pact — 1M Spell. Sacrifice a friendly Demon. Gain 1 Flesh. +1 Forge Counter.
	var ember_pact := SpellCardData.new()
	ember_pact.id              = "ember_pact"
	ember_pact.card_name       = "Ember Pact"
	ember_pact.cost            = 1
	ember_pact.description     = "Sacrifice a friendly Demon. Gain 1 Flesh. Add +1 Forge Counter."
	ember_pact.requires_target = true
	ember_pact.target_type     = "friendly_minion"
	ember_pact.effect_steps    = [
		{"type": "SACRIFICE", "scope": "SINGLE_CHOSEN_FRIENDLY", "filter": "DEMON"},
		{"type": "GAIN_FLESH", "amount": 1},
		{"type": "GAIN_FORGE_COUNTER", "amount": 1},
	]
	ember_pact.art_path        = "res://assets/art/spells/abyss_order/ember_pact.png"
	ember_pact.faction         = "abyss_order"
	all.append(ember_pact)

	# Bound Offering — 2E Demon 200/200. ON LEAVE: summon two 100/100 Void Demons.
	var bound_offering := MinionCardData.new()
	bound_offering.id           = "bound_offering"
	bound_offering.card_name    = "Bound Offering"
	bound_offering.essence_cost = 2
	bound_offering.atk          = 200
	bound_offering.health       = 200
	bound_offering.minion_type  = Enums.MinionType.DEMON
	bound_offering.description  = "ON LEAVE: Summon two 100/100 Void Demons."
	bound_offering.on_leave_effect_steps = [
		{"type": "SUMMON", "card_id": "void_demon", "token_atk": 100, "token_hp": 100},
		{"type": "SUMMON", "card_id": "void_demon", "token_atk": 100, "token_hp": 100},
	]
	bound_offering.art_path     = "res://assets/art/minions/abyss_order/bound_offering.png"
	bound_offering.faction      = "abyss_order"
	all.append(bound_offering)

	# Forgeborn Tyrant — 6E Demon 500/500. ON DEATH and ON LEAVE: +3 Forge Counter.
	# Both triggers fire if sacrificed (ON LEAVE only) or killed in combat (ON DEATH only).
	# No double-fire on a single removal: sacrifice path skips ON DEATH per the strict rule.
	var forgeborn_tyrant := MinionCardData.new()
	forgeborn_tyrant.id           = "forgeborn_tyrant"
	forgeborn_tyrant.card_name    = "Forgeborn Tyrant"
	forgeborn_tyrant.essence_cost = 6
	forgeborn_tyrant.atk          = 500
	forgeborn_tyrant.health       = 500
	forgeborn_tyrant.minion_type  = Enums.MinionType.DEMON
	forgeborn_tyrant.description  = "ON DEATH and ON LEAVE: Add +3 Forge Counter."
	forgeborn_tyrant.on_death_effect_steps = [
		{"type": "GAIN_FORGE_COUNTER", "amount": 3},
	]
	forgeborn_tyrant.on_leave_effect_steps = [
		{"type": "GAIN_FORGE_COUNTER", "amount": 3},
	]
	forgeborn_tyrant.art_path     = "res://assets/art/minions/abyss_order/forgeborn_tyrant.png"
	forgeborn_tyrant.faction      = "abyss_order"
	all.append(forgeborn_tyrant)

	# --- end Seris Demon Forge Pool -------------------------------------------

	# --- Seris Corruption Engine Pool -----------------------------------------
	# Branch 3 support pool. Unlocked when player takes corrupt_flesh (Corruption Engine T0).
	# Theme: stack Corruption on friendly Demons as an ATK buff (post-T0 inversion),
	# detonate stacks for AoE pressure (T1), feed spell-damage scaling (T2),
	# and replay spell turns (T3).

	# Bloodscribe Imp — 1E Demon 100/100. ON PLAY: Add a Flesh Rend to your hand.
	var bloodscribe_imp := MinionCardData.new()
	bloodscribe_imp.id           = "bloodscribe_imp"
	bloodscribe_imp.card_name    = "Bloodscribe Imp"
	bloodscribe_imp.essence_cost = 1
	bloodscribe_imp.atk          = 100
	bloodscribe_imp.health       = 100
	bloodscribe_imp.minion_type  = Enums.MinionType.DEMON
	bloodscribe_imp.description  = "ON PLAY: Add a Flesh Rend to your hand."
	bloodscribe_imp.on_play_effect_steps = [
		{"type": "ADD_CARD", "card_id": "flesh_rend"},
	]
	bloodscribe_imp.art_path     = "res://assets/art/minions/abyss_order/bloodscribe_imp.png"
	bloodscribe_imp.faction      = "abyss_order"
	all.append(bloodscribe_imp)

	# Tainted Ritualist — 2E Human 100/300. ON PLAY: Apply 1 Corruption to a friendly Demon.
	# Spend 1 Flesh: apply 2 instead.
	# The "Spend 1: 2 stacks instead" pattern: SPEND_FLESH gates a +1 bonus_amount on the CORRUPTION step.
	# Base 1 stack always applies; bonus +1 stack only if Flesh was spent this cast.
	var tainted_ritualist := MinionCardData.new()
	tainted_ritualist.id           = "tainted_ritualist"
	tainted_ritualist.card_name    = "Tainted Ritualist"
	tainted_ritualist.essence_cost = 2
	tainted_ritualist.atk          = 100
	tainted_ritualist.health       = 300
	tainted_ritualist.minion_type  = Enums.MinionType.HUMAN
	tainted_ritualist.description  = "ON PLAY: Apply 1 Corruption to a friendly Demon. Spend 1 Flesh: apply 2 instead."
	tainted_ritualist.on_play_requires_target = true
	tainted_ritualist.on_play_target_type     = "friendly_demon"
	tainted_ritualist.on_play_effect_steps = [
		{"type": "SPEND_FLESH", "amount": 1},
		{"type": "CORRUPTION", "scope": "SINGLE_CHOSEN_FRIENDLY", "filter": "DEMON",
			"amount": 1, "bonus_amount": 1, "bonus_conditions": ["flesh_spent_this_cast"]},
	]
	tainted_ritualist.art_path     = "res://assets/art/minions/abyss_order/tainted_ritualist.png"
	tainted_ritualist.faction      = "abyss_order"
	all.append(tainted_ritualist)

	# Festering Fiend — 3E Demon 300/400. ON PLAY: Apply 2 Corruption to itself.
	# ON DEATH: Apply 1 Corruption to a random friendly Demon.
	var festering_fiend := MinionCardData.new()
	festering_fiend.id           = "festering_fiend"
	festering_fiend.card_name    = "Festering Fiend"
	festering_fiend.essence_cost = 3
	festering_fiend.atk          = 300
	festering_fiend.health       = 400
	festering_fiend.minion_type  = Enums.MinionType.DEMON
	festering_fiend.description  = "ON PLAY: Apply 2 Corruption to itself. ON DEATH: Apply 1 Corruption to a random friendly Demon."
	festering_fiend.on_play_effect_steps = [
		{"type": "CORRUPTION", "scope": "SELF", "amount": 2},
	]
	# ON DEATH targets a random friendly Demon other than self (self is already gone, but exclude_self
	# also serves as future-proof against death-rebirth interactions).
	festering_fiend.on_death_effect_steps = [
		{"type": "CORRUPTION", "scope": "FILTERED_RANDOM_FRIENDLY", "filter": "DEMON",
			"amount": 1, "exclude_self": true},
	]
	festering_fiend.art_path     = "res://assets/art/minions/abyss_order/festering_fiend.png"
	festering_fiend.faction      = "abyss_order"
	all.append(festering_fiend)

	# Self-Mutilation — 1M Spell. Apply 2 Corruption to a friendly Demon. Draw a card.
	var self_mutilation := SpellCardData.new()
	self_mutilation.id              = "self_mutilation"
	self_mutilation.card_name       = "Self-Mutilation"
	self_mutilation.cost            = 1
	self_mutilation.description     = "Apply 2 Corruption to a friendly Demon. Draw a card."
	self_mutilation.requires_target = true
	self_mutilation.target_type     = "friendly_demon"
	self_mutilation.effect_steps    = [
		{"type": "CORRUPTION", "scope": "SINGLE_CHOSEN_FRIENDLY", "filter": "DEMON", "amount": 2},
		{"type": "DRAW", "amount": 1},
	]
	self_mutilation.art_path        = "res://assets/art/spells/abyss_order/self_mutilation.png"
	self_mutilation.faction         = "abyss_order"
	all.append(self_mutilation)

	# Resonant Outburst — 2M Spell. Deal 100 damage to all enemies. Spend 2 Flesh: deal 300 instead.
	# Pattern matches Flesh Eruption: SPEND_FLESH gates a +200 bonus on both the minion AoE and hero damage.
	var resonant_outburst := SpellCardData.new()
	resonant_outburst.id          = "resonant_outburst"
	resonant_outburst.card_name   = "Resonant Outburst"
	resonant_outburst.cost        = 2
	resonant_outburst.description = "Deal 100 damage to all enemies. Spend 2 Flesh: deal 300 instead."
	resonant_outburst.effect_steps = [
		{"type": "SPEND_FLESH", "amount": 2},
		{"type": "DAMAGE_MINION", "scope": "ALL_ENEMY", "amount": 100,
			"bonus_amount": 200, "bonus_conditions": ["flesh_spent_this_cast"]},
		{"type": "DAMAGE_HERO", "amount": 100,
			"bonus_amount": 200, "bonus_conditions": ["flesh_spent_this_cast"]},
	]
	resonant_outburst.art_path    = "res://assets/art/spells/abyss_order/resonant_outburst.png"
	resonant_outburst.faction     = "abyss_order"
	all.append(resonant_outburst)

	# Voidshaped Acolyte — 3E Demon 300/300. ON PLAY: Place a Shadow Rune on the enemy's battlefield.
	# Symmetric: the rune is placed on the *opponent* of the caster, so it's enemy-side when player casts
	# and player-side if enemy ever casts. From the caster's perspective the rune corrupts the OPPONENT'S
	# minions on entry — read from the opponent's perspective ("their" minions = caster's friendlies)
	# this means caster's Demons enter with 1 Corruption stack, which with corrupt_flesh active becomes
	# +100 ATK per summon.
	var voidshaped_acolyte := MinionCardData.new()
	voidshaped_acolyte.id           = "voidshaped_acolyte"
	voidshaped_acolyte.card_name    = "Voidshaped Acolyte"
	voidshaped_acolyte.essence_cost = 3
	voidshaped_acolyte.atk          = 300
	voidshaped_acolyte.health       = 300
	voidshaped_acolyte.minion_type  = Enums.MinionType.DEMON
	voidshaped_acolyte.description  = "ON PLAY: Place a Shadow Rune on the enemy's battlefield."
	voidshaped_acolyte.on_play_effect_steps = [
		{"type": "PLACE_RUNE_ON_OPPONENT", "card_id": "shadow_rune"},
	]
	voidshaped_acolyte.art_path     = "res://assets/art/minions/abyss_order/voidshaped_acolyte.png"
	voidshaped_acolyte.faction      = "abyss_order"
	all.append(voidshaped_acolyte)

	# Recursive Hex — 5M Spell. Copy each spell you cast last turn (excluding Recursive Hex)
	# into your hand. Deal 200 damage to enemy hero per spell copied.
	# Implementation notes:
	# - "Last turn" is computed from the graveyard: ctx.scene._friendly_graveyard(ctx.owner)
	#   has Recursive Hex itself as the most recent entry (appended at remove_from_hand /
	#   commit_play_spell time). Its resolved_on_turn is the current turn; we filter for
	#   resolved_on_turn == current - 1.
	# - Self-copy is filtered by exclude_card_id so multiple Recursive Hex casts in the
	#   same turn last turn (or any turn) cannot self-replicate.
	# - Copies are fresh CardInstances at base cost. If hand is full, excess copies burn
	#   silently (matches add_to_hand semantics on both real and sim).
	# - Hero damage is paid based on the graveyard-query count, not how many copies actually
	#   landed in hand — so a full-hand cast still does the face damage.
	var recursive_hex := SpellCardData.new()
	recursive_hex.id          = "recursive_hex"
	recursive_hex.card_name   = "Recursive Hex"
	recursive_hex.cost        = 5
	recursive_hex.description = "Copy each spell you cast last turn (excluding Recursive Hex) into your hand. Deal 200 damage to enemy hero per spell copied."
	recursive_hex.effect_steps = [
		{"type": "COPY_LAST_TURN_SPELLS_FROM_GRAVEYARD", "amount": 200, "exclude_card_id": "recursive_hex"},
	]
	recursive_hex.art_path    = "res://assets/art/spells/abyss_order/recursive_hex.png"
	recursive_hex.faction     = "abyss_order"
	all.append(recursive_hex)

	# --- end Seris Corruption Engine Pool -------------------------------------

	# Void Imp Wizard — variant core unit; offered via special reward
	var void_imp_wizard := MinionCardData.new()
	void_imp_wizard.id           = "void_imp_wizard"
	void_imp_wizard.card_name    = "Void Imp Wizard"
	void_imp_wizard.essence_cost = 2
	void_imp_wizard.mana_cost    = 1
	void_imp_wizard.description  = "ON PLAY: Deal 300 Void Bolt damage to enemy hero and apply 1 VOID MARK."
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
	all.append(void_imp_wizard)

	var shadow_hound := MinionCardData.new()
	shadow_hound.id             = "shadow_hound"
	shadow_hound.card_name      = "Shadow Hound"
	shadow_hound.essence_cost   = 2
	shadow_hound.description    = "ON PLAY: Gain +100 ATK for each other friendly Demon on board."
	shadow_hound.atk            = 200
	shadow_hound.health         = 300
	shadow_hound.minion_type    = Enums.MinionType.DEMON
	shadow_hound.on_play_effect_steps = [{"type": "BUFF_ATK", "scope": "SELF", "amount": 100, "multiplier_key": "board_count", "multiplier_board": "friendly", "multiplier_filter": "race", "multiplier_tag": "demon", "exclude_self": true, "permanent": true}]
	shadow_hound.faction        = "abyss_order"
	shadow_hound.art_path             = "res://assets/art/minions/abyss_order/shadow_hound.png"
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
	all.append(abyssal_brute)

	# --- Spells ---

	var dark_empowerment := SpellCardData.new()
	dark_empowerment.id             = "dark_empowerment"
	dark_empowerment.card_name      = "Dark Empowerment"
	dark_empowerment.cost           = 1
	dark_empowerment.description    = "Give a friendly minion +150 ATK. If it is a Demon, also give +150 HP."
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
	abyssal_sacrifice.description    = "SACRIFICE a friendly minion. Draw 2 cards."
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
		{"type": "DAMAGE_MINION", "scope": "ALL_ENEMY", "amount": 100, "damage_school": "VOID"},
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
	void_execution.description    = "Deal 500 damage to an enemy minion or enemy hero. If you control any Human, deal 700 instead."
	void_execution.requires_target = true
	void_execution.target_type    = "enemy_minion_or_hero"
	void_execution.effect_steps = [
		{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 500, "bonus_amount": 200, "bonus_conditions": ["has_friendly_human"], "damage_school": "VOID"},
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
	traveling_merchant.description    = "ON PLAY: Draw a card."
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
	trapbreaker_rogue.description    = "ON PLAY: Destroy a random enemy trap."
	trapbreaker_rogue.essence_cost   = 2
	trapbreaker_rogue.atk            = 250
	trapbreaker_rogue.health         = 200
	trapbreaker_rogue.minion_type    = Enums.MinionType.HUMAN
	trapbreaker_rogue.on_play_effect_steps = [{"type": "DESTROY", "scope": "SINGLE_RANDOM_OPPONENT_TRAP"}]
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
	spell_taxer.description    = "ON PLAY: Enemy spells cost +1 Mana next turn."
	spell_taxer.essence_cost   = 3
	spell_taxer.atk            = 250
	spell_taxer.health         = 300
	spell_taxer.minion_type    = Enums.MinionType.HUMAN
	spell_taxer.on_play_effect_steps = [{"type": "TAX_OPPONENT_SPELLS_NEXT_TURN"}]
	spell_taxer.faction        = "neutral"
	spell_taxer.art_path       = "res://assets/art/minions/neutral/spell_taxer.png"
	all.append(spell_taxer)

	var saboteur_adept := MinionCardData.new()
	saboteur_adept.id             = "saboteur_adept"
	saboteur_adept.card_name      = "Saboteur Adept"
	saboteur_adept.description    = "ON PLAY: Enemy traps cannot trigger this turn."
	saboteur_adept.essence_cost   = 3
	saboteur_adept.atk            = 300
	saboteur_adept.health         = 300
	saboteur_adept.minion_type    = Enums.MinionType.HUMAN
	saboteur_adept.on_play_effect_steps = [{"type": "BLOCK_OPPONENT_TRAPS_THIS_TURN"}]
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
	bulwark_automaton.description = ""
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
	ruins_archivist.description    = "ON PLAY: Draw a card."
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
	arcane_strike.description     = "Deal 300 damage to a minion."
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
	purge.description     = "Remove all buffs and debuffs from a minion."
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
	cyclone.description    = "Destroy an active Trap/Rune or the active Environment."
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
	precision_strike.description     = "Deal 600 damage to a minion."
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
	dark_covenant.description           = "AURA: While a friendly Human is on board, all friendly Demons have +100 ATK.\nWhile a friendly Demon is on board, all friendly Humans have +100 HP."
	dark_covenant.passive_description   = "AURA: All friendly Demons have +100 ATK while a friendly Human is present. All friendly Humans have +100 HP while a friendly Demon is present."
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
	abyss_cultist.description    = "ON PLAY: Apply 1 CORRUPTION to a random enemy minion."
	abyss_cultist.atk            = 100
	abyss_cultist.health         = 300
	abyss_cultist.minion_type    = Enums.MinionType.HUMAN
	abyss_cultist.on_play_effect_steps = [{"type": "CORRUPTION", "scope": "SINGLE_RANDOM", "amount": 1}]
	# corrupt_flesh (Seris T0) re-aims this card at friendly Demons so it feeds
	# the Corruption Engine's friendly-Demon ATK loop and the corrupt_detonation chain.
	abyss_cultist.talent_overrides = [
		{
			"talent_id": "corrupt_flesh",
			"description": "ON PLAY: Apply 1 CORRUPTION to a random friendly Demon.",
			"on_play_effect_steps": [{"type": "CORRUPTION", "scope": "FILTERED_RANDOM_FRIENDLY", "filter": "DEMON", "amount": 1}],
		},
	]
	abyss_cultist.faction        = "abyss_order"
	abyss_cultist.art_path             = "res://assets/art/minions/abyss_order/abyss_cultist.png"
	all.append(abyss_cultist)

	var void_netter := MinionCardData.new()
	void_netter.id             = "void_netter"
	void_netter.card_name      = "Void Netter"
	void_netter.essence_cost   = 2
	void_netter.description             = "ON PLAY: Deal 200 damage to an enemy minion."
	void_netter.atk                     = 100
	void_netter.health                  = 300
	void_netter.minion_type             = Enums.MinionType.HUMAN
	void_netter.on_play_effect_steps    = [{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 200}]
	void_netter.on_play_target_optional = true
	void_netter.on_play_target_type     = "enemy_minion"
	void_netter.on_play_target_prompt   = "Click an enemy minion to deal 200 damage, or click a slot to summon without effect."
	void_netter.faction        = "abyss_order"
	void_netter.art_path             = "res://assets/art/minions/abyss_order/void_netter.png"
	all.append(void_netter)

	var corruption_weaver := MinionCardData.new()
	corruption_weaver.id             = "corruption_weaver"
	corruption_weaver.card_name      = "Corruption Weaver"
	corruption_weaver.essence_cost   = 3
	corruption_weaver.description    = "ON PLAY: Apply 1 CORRUPTION to all enemy minions."
	corruption_weaver.atk            = 100
	corruption_weaver.health         = 400
	corruption_weaver.minion_type    = Enums.MinionType.HUMAN
	corruption_weaver.on_play_effect_steps = [{"type": "CORRUPTION", "scope": "ALL_ENEMY", "amount": 1}]
	# corrupt_flesh (Seris T0) — see abyss_cultist note. Board-wide friendly version
	# stacks meaningfully with corrupt_detonation (T1) and void_amplification (T2).
	corruption_weaver.talent_overrides = [
		{
			"talent_id": "corrupt_flesh",
			"description": "ON PLAY: Apply 1 CORRUPTION to all friendly Demons.",
			"on_play_effect_steps": [{"type": "CORRUPTION", "scope": "ALL_FRIENDLY", "filter": "DEMON", "amount": 1}],
		},
	]
	corruption_weaver.faction        = "abyss_order"
	corruption_weaver.art_path             = "res://assets/art/minions/abyss_order/corruption_weaver.png"
	all.append(corruption_weaver)

	var soul_collector := MinionCardData.new()
	soul_collector.id             = "soul_collector"
	soul_collector.card_name      = "Soul Collector"
	soul_collector.essence_cost   = 5
	soul_collector.description             = "ON PLAY: Destroy a Corrupted enemy minion."
	soul_collector.atk                     = 300
	soul_collector.health                  = 700
	soul_collector.minion_type             = Enums.MinionType.HUMAN
	soul_collector.on_play_effect_steps    = [{"type": "DESTROY", "scope": "SINGLE_CHOSEN", "filter": "CORRUPTED"}]
	soul_collector.on_play_target_optional = true
	soul_collector.on_play_target_type     = "corrupted_enemy_minion"
	soul_collector.on_play_target_prompt   = "Click a Corrupted enemy minion to destroy it, or click a slot to summon without effect."
	soul_collector.faction        = "abyss_order"
	soul_collector.art_path             = "res://assets/art/minions/abyss_order/soul_collector.png"
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
	all.append(void_stalker)

	# --- Board-wide passive payoffs ---

	var void_spawner := MinionCardData.new()
	void_spawner.id           = "void_spawner"
	void_spawner.card_name    = "Void Spawner"
	void_spawner.essence_cost = 4
	void_spawner.description  = "PASSIVE: Whenever a friendly Demon dies, summon a 100/100 Void Spark."
	void_spawner.atk          = 200
	void_spawner.health       = 600
	void_spawner.minion_type  = Enums.MinionType.DEMON
	void_spawner.passive_effect_id = "void_spark_on_friendly_death"
	void_spawner.faction      = "abyss_order"
	void_spawner.art_path             = "res://assets/art/minions/abyss_order/void_spawner.png"
	all.append(void_spawner)

	var abyssal_tide := MinionCardData.new()
	abyssal_tide.id           = "abyssal_tide"
	abyssal_tide.card_name    = "Abyssal Tide"
	abyssal_tide.essence_cost = 5
	abyssal_tide.description  = "PASSIVE: Whenever a friendly minion dies, deal 200 damage to enemy hero."
	abyssal_tide.atk          = 400
	abyssal_tide.health       = 400
	abyssal_tide.minion_type  = Enums.MinionType.DEMON
	abyssal_tide.passive_effect_id = "deal_200_hero_on_friendly_death"
	abyssal_tide.faction      = "abyss_order"
	abyssal_tide.art_path             = "res://assets/art/minions/abyss_order/abyssal_tide.png"
	all.append(abyssal_tide)

	# --- Sacrifice finisher ---

	var void_devourer := MinionCardData.new()
	void_devourer.id             = "void_devourer"
	void_devourer.card_name      = "Void Devourer"
	void_devourer.essence_cost   = 6
	void_devourer.description    = "ON PLAY: SACRIFICE adjacent friendly minions. Gain +300 ATK and +300 HP per sacrificed minion."
	void_devourer.atk            = 200
	void_devourer.health         = 600
	void_devourer.minion_type    = Enums.MinionType.DEMON
	void_devourer.keywords.append(Enums.Keyword.GUARD)
	void_devourer.on_play_effect_steps = [{"type": "HARDCODED", "hardcoded_id": "void_devourer_sacrifice"}]
	void_devourer.faction        = "abyss_order"
	void_devourer.art_path             = "res://assets/art/minions/abyss_order/void_devourer.png"
	all.append(void_devourer)

	# --- Champion (max 1 copy, auto-summoned when 3 Void Imps are on board) ---

	var nyx_ael := MinionCardData.new()
	nyx_ael.id           = "nyx_ael"
	nyx_ael.card_name    = "Nyx'ael, Void Sovereign"
	nyx_ael.essence_cost = 5
	nyx_ael.description  = "Summoned when 3 VOID IMP CLAN minions are on the battlefield.\nPASSIVE: At the start of your turn, deal 200 damage to all enemy minions."
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
	all.append(nyx_ael)

	# --- Tokens (not in player deck, summoned by effects) ---
	# Defined compactly via _TOKEN_DEFS at the bottom of this file; appended there.

	# --- Void Bolt card ecosystem (Mana-cost, Lord Vael void_bolt branch) ---

	var void_bolt_spell := SpellCardData.new()
	void_bolt_spell.id             = "void_bolt"
	void_bolt_spell.card_name      = "Void Bolt"
	void_bolt_spell.cost           = 2
	void_bolt_spell.description    = "Deal 500 Void Bolt damage to enemy hero."
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
	hidden_ambush.description  = "TRAP: When an enemy minion attacks, deal 400 damage to that minion."
	hidden_ambush.trigger      = Enums.TriggerEvent.ON_ENEMY_ATTACK
	hidden_ambush.effect_steps = [{"type": "DAMAGE_MINION", "scope": "TRIGGER_MINION", "amount": 400}]
	hidden_ambush.art_path     = "res://assets/art/traps/neutral/hidden_ambush.png"
	hidden_ambush.faction      = "neutral"
	all.append(hidden_ambush)

	var smoke_veil := TrapCardData.new()
	smoke_veil.id           = "smoke_veil"
	smoke_veil.card_name    = "Smoke Veil"
	smoke_veil.cost         = 2
	smoke_veil.description  = "TRAP: When an enemy minion attacks, cancel that attack and exhaust all enemy minions."
	smoke_veil.trigger      = Enums.TriggerEvent.ON_ENEMY_ATTACK
	smoke_veil.effect_steps = [{"type": "HARDCODED", "hardcoded_id": "smoke_veil"}]
	smoke_veil.art_path     = "res://assets/art/traps/neutral/smoke_veil.png"
	smoke_veil.faction      = "neutral"
	all.append(smoke_veil)

	var silence_trap := TrapCardData.new()
	silence_trap.id           = "silence_trap"
	silence_trap.card_name    = "Silence Trap"
	silence_trap.cost         = 2
	silence_trap.description  = "TRAP: When enemy casts a spell, cancel that spell."
	silence_trap.trigger      = Enums.TriggerEvent.ON_ENEMY_SPELL_CAST
	silence_trap.effect_steps = [{"type": "CANCEL_OPPONENT_SPELL"}]
	silence_trap.art_path     = "res://assets/art/traps/neutral/silence_trap.png"
	silence_trap.faction      = "neutral"
	all.append(silence_trap)

	var death_trap := TrapCardData.new()
	death_trap.id           = "death_trap"
	death_trap.card_name    = "Death Trap"
	death_trap.cost         = 2
	death_trap.description  = "TRAP: When enemy summons a minion, destroy that minion."
	death_trap.trigger      = Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	death_trap.effect_steps = [{"type": "KILL_MINION", "scope": "TRIGGER_MINION"}]
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
	mark_the_target.description = "Apply 2 VOID MARKS to enemy hero. Draw a card."

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
	font_of_the_depths.description = "Gain +1 maximum Mana. Draw a card."
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
	void_detonation.description = "Deal 500 Void Bolt damage to enemy hero. Gain +50 damage per VOID MARK on enemy hero."
	void_detonation.effect_steps = [{"type": "VOID_BOLT", "base_amount": 500, "amount": 50, "multiplier_key": "void_marks"}]
	void_detonation.art_path    = "res://assets/art/spells/abyss_order/void_detonation.png"
	void_detonation.faction     = "abyss_order"
	all.append(void_detonation)

	# Minions
	var abyssal_arcanist := MinionCardData.new()
	abyssal_arcanist.id            = "abyssal_arcanist"
	abyssal_arcanist.card_name     = "Abyssal Arcanist"
	abyssal_arcanist.description   = "ON PLAY: Add a Void Bolt spell to your hand."
	abyssal_arcanist.essence_cost  = 1
	abyssal_arcanist.mana_cost     = 2
	abyssal_arcanist.atk           = 200
	abyssal_arcanist.health        = 300
	abyssal_arcanist.minion_type   = Enums.MinionType.HUMAN
	abyssal_arcanist.on_play_effect_steps = [{"type": "ADD_CARD", "card_id": "void_bolt"}]
	abyssal_arcanist.faction       = "abyss_order"
	abyssal_arcanist.art_path           = "res://assets/art/minions/abyss_order/abyssal_arcanist.png"
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
	all.append(imp_recruiter)

	var soul_taskmaster := MinionCardData.new()
	soul_taskmaster.id                = "soul_taskmaster"
	soul_taskmaster.card_name         = "Soul Taskmaster"
	soul_taskmaster.description       = "PASSIVE: Whenever a friendly Demon dies, this minion gains +50 ATK."
	soul_taskmaster.essence_cost      = 3
	soul_taskmaster.atk               = 250
	soul_taskmaster.health            = 400
	soul_taskmaster.minion_type       = Enums.MinionType.DEMON
	soul_taskmaster.passive_effect_id = "soul_taskmaster_gain_atk"
	soul_taskmaster.faction           = "abyss_order"
	soul_taskmaster.art_path             = "res://assets/art/minions/abyss_order/soul_taskmaster.png"
	all.append(soul_taskmaster)

	var void_amplifier := MinionCardData.new()
	void_amplifier.id                = "void_amplifier"
	void_amplifier.card_name         = "Void Amplifier"
	void_amplifier.description       = "PASSIVE: Whenever you play a Demon, it enters with +100 ATK and +100 HP."
	void_amplifier.essence_cost      = 4
	void_amplifier.atk               = 250
	void_amplifier.health            = 350
	void_amplifier.minion_type       = Enums.MinionType.HUMAN
	void_amplifier.passive_effect_id = "void_amplifier_buff_demon"
	void_amplifier.faction           = "abyss_order"
	void_amplifier.art_path             = "res://assets/art/minions/abyss_order/void_amplifier.png"
	all.append(void_amplifier)

	# Spells
	var blood_pact := SpellCardData.new()
	blood_pact.id          = "blood_pact"
	blood_pact.card_name   = "Blood Pact"
	blood_pact.cost        = 2
	blood_pact.description    = "SACRIFICE a friendly Human. Give all friendly Demons +200 ATK and +100 HP."
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
	soul_shatter.description    = "SACRIFICE a friendly Demon. Deal 200 damage to all enemy minions. Deal 300 if the sacrifice had 300+ HP."
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
	soul_rune.aura_extra_trigger       = Enums.TriggerEvent.ON_PLAYER_MINION_SACRIFICED
	soul_rune.aura_effect_steps        = [{"type": "HARDCODED", "hardcoded_id": "soul_rune_death"}]
	soul_rune.aura_secondary_trigger   = Enums.TriggerEvent.ON_ENEMY_TURN_START
	soul_rune.aura_secondary_steps     = [{"type": "HARDCODED", "hardcoded_id": "soul_rune_reset"}]
	soul_rune.faction                  = "abyss_order"
	soul_rune.art_path                 = "res://assets/art/traps/abyss_order/soul_rune_premium.png"
	soul_rune.battlefield_art_path     = "res://assets/art/traps/abyss_order/soul_rune_battlefield.png"
	soul_rune.rune_glow_color          = Color(0.35, 0.08, 0.55, 1)  # Dark purple
	all.append(soul_rune)

	# ---------------------------------------------------------------------------
	# --- Runes (Abyss Order — Trap subtype, persistent, face-up) ---
	# ---------------------------------------------------------------------------

	var void_rune := TrapCardData.new()
	void_rune.id               = "void_rune"
	void_rune.card_name        = "Void Rune"
	void_rune.cost             = 2
	void_rune.description      = "RUNE: At the start of your turn, deal 100 Void Bolt damage to enemy hero."
	void_rune.is_rune          = true
	void_rune.rune_type        = Enums.RuneType.VOID_RUNE
	void_rune.aura_trigger     = Enums.TriggerEvent.ON_PLAYER_TURN_START
	void_rune.aura_effect_steps = [{"type": "VOID_BOLT", "amount": 100, "multiplier_key": "rune_aura"}]
	void_rune.faction          = "abyss_order"
	void_rune.art_path             = "res://assets/art/traps/abyss_order/void_rune_clean.png"
	void_rune.battlefield_art_path = "res://assets/art/traps/abyss_order/void_rune_battlefield.png"
	void_rune.rune_glow_color      = Color(0.35, 0.12, 0.55, 1)  # Dark purple
	all.append(void_rune)

	var blood_rune := TrapCardData.new()
	blood_rune.id               = "blood_rune"
	blood_rune.card_name        = "Blood Rune"
	blood_rune.cost             = 2
	blood_rune.description      = "RUNE: Whenever a friendly minion dies, heal your hero for 100 HP."
	blood_rune.is_rune          = true
	blood_rune.rune_type        = Enums.RuneType.BLOOD_RUNE
	blood_rune.aura_trigger        = Enums.TriggerEvent.ON_PLAYER_MINION_DIED
	blood_rune.aura_extra_trigger  = Enums.TriggerEvent.ON_PLAYER_MINION_SACRIFICED
	blood_rune.aura_effect_steps   = [{"type": "HEAL_HERO", "amount": 100, "multiplier_key": "rune_aura"}]
	blood_rune.faction          = "abyss_order"
	blood_rune.art_path             = "res://assets/art/traps/abyss_order/blood_rune_clean.png"
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
	# Backfill on place + auto-strip on remove are handled by the aura system
	# (driven by source_tag in aura_effect_steps).
	dominion_rune.faction           = "abyss_order"
	dominion_rune.art_path              = "res://assets/art/traps/abyss_order/dominion_rune_clean.png"
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
	# Future-only by design: existing enemy minions never had a "play moment" to be
	# corrupted, so don't retroactively stack CORRUPTION on them at placement.
	shadow_rune.aura_backfill_on_place = false
	shadow_rune.faction          = "abyss_order"
	shadow_rune.art_path             = "res://assets/art/traps/abyss_order/shadow_rune_clean.png"
	shadow_rune.battlefield_art_path = "res://assets/art/traps/abyss_order/shadow_rune_battlefield_v2.png"
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
	blood_dominion_ritual.description    = "Consume Blood + Dominion Runes. Deal 200 damage to 2 random enemy minions. Summon a 500/500 Demon."
	blood_dominion_ritual.required_runes = [Enums.RuneType.BLOOD_RUNE, Enums.RuneType.DOMINION_RUNE]
	blood_dominion_ritual.effect_steps   = [
		{"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM", "amount": 200, "random_picks": 2},
		{"type": "SUMMON", "card_id": "void_demon", "token_atk": 500, "token_hp": 500},
	]

	var abyssal_summoning_circle := EnvironmentCardData.new()
	abyssal_summoning_circle.id                         = "abyssal_summoning_circle"
	abyssal_summoning_circle.card_name                  = "Abyssal Summoning Circle"
	abyssal_summoning_circle.cost                       = 2
	abyssal_summoning_circle.description                = "Whenever a friendly Demon dies, deal 200 damage to enemy hero. \nRITUAL: Blood + Dominion → Demon Ascendant."
	abyssal_summoning_circle.passive_description        = "Whenever a friendly Demon dies, deal 200 damage to enemy hero."
	abyssal_summoning_circle.on_player_minion_died_steps = [{"type": "DAMAGE_HERO", "amount": 200, "damage_school": "VOID", "conditions": ["dead_is_demon"]}]
	abyssal_summoning_circle.rituals                    = [blood_dominion_ritual]
	abyssal_summoning_circle.faction                    = "abyss_order"
	abyssal_summoning_circle.art_path                   = "res://assets/art/environments/abyss_order/abyssal_summoning_circle.png"
	all.append(abyssal_summoning_circle)

	# ---------------------------------------------------------------------------
	# --- Ritual Environments (Abyss Order — Piercing Void support pool) ---
	# ---------------------------------------------------------------------------

	var void_blood_ritual := RitualData.new()
	void_blood_ritual.ritual_name    = "Soul Cataclysm"
	void_blood_ritual.description    = "Consume Void + Blood Runes. Deal 400 Void Bolt damage to enemy hero. Heal your hero for 400 HP."
	void_blood_ritual.required_runes = [Enums.RuneType.VOID_RUNE, Enums.RuneType.BLOOD_RUNE]
	void_blood_ritual.effect_steps   = [
		{"type": "VOID_BOLT", "amount": 400},
		{"type": "HEAL_HERO",  "amount": 400},
	]

	var abyss_ritual_circle := EnvironmentCardData.new()
	abyss_ritual_circle.id                  = "abyss_ritual_circle"
	abyss_ritual_circle.card_name           = "Abyss Ritual Circle"
	abyss_ritual_circle.cost                = 2
	abyss_ritual_circle.description         = "Each turn, deal 100 damage to a random minion. \nRITUAL: Void + Blood → Soul Cataclysm."
	abyss_ritual_circle.passive_description = "At the start of each turn, deal 100 damage to a random minion."
	abyss_ritual_circle.passive_effect_steps = [{
		"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM_BOTH_BOARDS",
		"amount": 100, "damage_school": "VOID",
	}]
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
	imp_martyr.description         = "ON DEATH: Give all friendly VOID IMP CLAN minions +100 ATK and +100 HP."
	imp_martyr.atk                 = 100
	imp_martyr.health              = 100
	imp_martyr.minion_type         = Enums.MinionType.DEMON
	imp_martyr.on_death_effect_steps = [
		{"type": "BUFF_ATK", "scope": "ALL_FRIENDLY", "filter": "VOID_IMP", "amount": 100, "permanent": true},
		{"type": "BUFF_HP",  "scope": "ALL_FRIENDLY", "filter": "VOID_IMP", "amount": 100},
	]
	imp_martyr.minion_tags         = ["void_imp"]
	imp_martyr.art_path            = "res://assets/art/minions/abyss_order/imp_martyr.png"
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
	imp_idol.faction               = "abyss_order"
	imp_idol.clan                  = "Void Imp"
	all.append(imp_idol)

	var vaels_colossal_guard := MinionCardData.new()
	vaels_colossal_guard.id                   = "vaels_colossal_guard"
	vaels_colossal_guard.card_name            = "Vael's Colossal Guard"
	vaels_colossal_guard.essence_cost         = 7
	vaels_colossal_guard.description          = "ON PLAY: Gain +300 ATK and +300 HP for each other VOID IMP CLAN minion on board. Give all other VOID IMP CLAN minions +100 ATK."
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
	all.append(vaels_colossal_guard)

	# ---------------------------------------------------------------------------
	# --- Vael Rune Master support pool (5 cards) ---
	# ---------------------------------------------------------------------------

	var runic_blast := SpellCardData.new()
	runic_blast.id          = "runic_blast"
	runic_blast.card_name   = "Runic Blast"
	runic_blast.cost        = 2
	runic_blast.description = "Deal 200 damage to 2 random enemy minions. If you have 2+ Runes, deal 200 to all enemy minions instead."
	runic_blast.effect_steps = [
		{"type": "DAMAGE_MINION", "scope": "ALL_ENEMY", "amount": 200,
		 "conditions": ["owner_runes_gte_2"]},
		{"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM", "amount": 200,
		 "random_picks": 2, "conditions": ["not_owner_runes_gte_2"]},
	]
	runic_blast.art_path    = "res://assets/art/spells/abyss_order/runic_blast.png"
	runic_blast.faction     = "abyss_order"
	all.append(runic_blast)

	var runic_echo := SpellCardData.new()
	runic_echo.id          = "runic_echo"
	runic_echo.card_name   = "Runic Echo"
	runic_echo.cost        = 2
	runic_echo.description = "Add a copy of each Rune on the battlefield to your hand."
	runic_echo.effect_steps = [{"type": "COPY_OWNER_RUNES_TO_HAND"}]
	runic_echo.art_path    = "res://assets/art/spells/abyss_order/runic_echo.png"
	runic_echo.faction     = "abyss_order"
	all.append(runic_echo)

	var rune_warden := MinionCardData.new()
	rune_warden.id                       = "rune_warden"
	rune_warden.card_name                = "Rune Warden"
	rune_warden.essence_cost             = 3
	rune_warden.description              = "PASSIVE: Whenever you place a Rune, this minion gains +200 ATK this turn."
	rune_warden.atk                      = 200
	rune_warden.health                   = 400
	rune_warden.minion_type              = Enums.MinionType.HUMAN
	rune_warden.passive_effect_id        = "rune_warden"
	rune_warden.art_path                 = "res://assets/art/minions/abyss_order/rune_warden.png"
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
	rune_seeker.on_play_effect_steps    = [{"type": "TUTOR", "tutor_filter": "rune"}]
	rune_seeker.art_path                = "res://assets/art/minions/abyss_order/rune_seeker.png"
	rune_seeker.faction                 = "abyss_order"
	all.append(rune_seeker)

	var echo_rune := TrapCardData.new()
	echo_rune.id                 = "echo_rune"
	echo_rune.card_name          = "Echo Rune"
	echo_rune.cost               = 2
	echo_rune.description        = "RUNE (Wildcard): Counts as any rune type for rituals."
	echo_rune.is_rune            = true
	echo_rune.is_wildcard_rune   = true
	echo_rune.art_path               = "res://assets/art/traps/abyss_order/echo_rune_premium.png"
	echo_rune.battlefield_art_path   = "res://assets/art/traps/abyss_order/echo_rune_battlefield.png"
	echo_rune.rune_glow_color        = Color(0.95, 0.65, 0.25, 1)  # Warm gold/amber — matches the art
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
	all.append(frenzied_imp)

	var matriarchs_broodling := MinionCardData.new()
	matriarchs_broodling.id           = "matriarchs_broodling"
	matriarchs_broodling.card_name    = "Matriarch's Broodling"
	matriarchs_broodling.essence_cost = 4
	matriarchs_broodling.description  = "ON DEATH: Summon a Brood Imp."
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
	all.append(matriarchs_broodling)

	var rogue_imp_elder := MinionCardData.new()
	rogue_imp_elder.id           = "rogue_imp_elder"
	rogue_imp_elder.card_name    = "Rogue Imp Elder"
	rogue_imp_elder.essence_cost = 4
	rogue_imp_elder.description  = "AURA: All friendly FERAL IMP minions have +100 ATK."
	rogue_imp_elder.atk          = 300
	rogue_imp_elder.health       = 500
	rogue_imp_elder.minion_type  = Enums.MinionType.DEMON
	# Self-tag "rogue_imp_elder" lets the presence-aura board_count multiplier count
	# how many Elders are alive on the same side (so 2 Elders → +200 each, etc.).
	rogue_imp_elder.minion_tags  = ["feral_imp", "rogue_imp_elder"]
	rogue_imp_elder.presence_aura_steps = [{
		"type": "BUFF_ATK",
		"scope": "ALL_FRIENDLY",
		"filter": "FERAL_IMP",
		"amount": 100,
		"source_tag": "rogue_imp_elder_aura",
		"multiplier_key": "board_count",
		"multiplier_board": "friendly",
		"multiplier_filter": "tag",
		"multiplier_tag": "rogue_imp_elder",
	}]
	rogue_imp_elder.faction              = "abyss_order"
	rogue_imp_elder.clan                 = "Feral Imp"
	rogue_imp_elder.art_path             = "res://assets/art/minions/feral_imp_clan/rogue_imp_elder.png"
	all.append(rogue_imp_elder)

	# --- Enemy Champions (Act 1) — auto-summoned by passive handlers, not from deck ---

	var champion_rogue_imp_pack := MinionCardData.new()
	champion_rogue_imp_pack.id           = "champion_rogue_imp_pack"
	champion_rogue_imp_pack.card_name    = "Rogue Imp Pack"
	champion_rogue_imp_pack.essence_cost = 0
	champion_rogue_imp_pack.description  = "Summoned after 4 Rabid Imp attacks.\nAURA: All friendly FERAL IMP minions have +100 ATK."
	champion_rogue_imp_pack.atk          = 300
	champion_rogue_imp_pack.health       = 400
	champion_rogue_imp_pack.minion_type  = Enums.MinionType.DEMON
	champion_rogue_imp_pack.keywords     = [Enums.Keyword.CHAMPION, Enums.Keyword.SWIFT]
	champion_rogue_imp_pack.is_champion  = true
	champion_rogue_imp_pack.minion_tags  = ["feral_imp", "enemy_champion"]
	champion_rogue_imp_pack.faction              = "abyss_order"
	champion_rogue_imp_pack.clan                 = "Feral Imp"
	champion_rogue_imp_pack.art_path             = "res://assets/art/minions/feral_imp_clan/rogue_imp_pack.png"
	all.append(champion_rogue_imp_pack)

	var champion_corrupted_broodlings := MinionCardData.new()
	champion_corrupted_broodlings.id           = "champion_corrupted_broodlings"
	champion_corrupted_broodlings.card_name    = "Corrupted Broodlings"
	champion_corrupted_broodlings.essence_cost = 0
	champion_corrupted_broodlings.description  = "ON DEATH: Summon a Void-Touched Imp."
	champion_corrupted_broodlings.atk          = 200
	champion_corrupted_broodlings.health       = 400
	champion_corrupted_broodlings.minion_type  = Enums.MinionType.DEMON
	champion_corrupted_broodlings.keywords     = [Enums.Keyword.CHAMPION]
	champion_corrupted_broodlings.is_champion  = true
	champion_corrupted_broodlings.minion_tags  = ["feral_imp", "enemy_champion"]
	champion_corrupted_broodlings.art_path             = "res://assets/art/minions/feral_imp_clan/champion_corrupted_broodlings.png"
	champion_corrupted_broodlings.faction      = "abyss_order"
	champion_corrupted_broodlings.clan         = "Feral Imp"
	all.append(champion_corrupted_broodlings)

	var champion_imp_matriarch := MinionCardData.new()
	champion_imp_matriarch.id           = "champion_imp_matriarch"
	champion_imp_matriarch.card_name    = "Imp Matriarch"
	champion_imp_matriarch.essence_cost = 0
	champion_imp_matriarch.description  = "AURA: Pack Frenzy also gives all FERAL IMP minions +200 HP."
	champion_imp_matriarch.atk          = 300
	champion_imp_matriarch.health       = 500
	champion_imp_matriarch.minion_type  = Enums.MinionType.DEMON
	champion_imp_matriarch.keywords     = [Enums.Keyword.CHAMPION, Enums.Keyword.GUARD]
	champion_imp_matriarch.is_champion  = true
	champion_imp_matriarch.minion_tags  = ["feral_imp", "enemy_champion"]
	champion_imp_matriarch.art_path             = "res://assets/art/minions/feral_imp_clan/champion_imp_matriarch.png"
	champion_imp_matriarch.faction      = "abyss_order"
	champion_imp_matriarch.clan         = "Feral Imp"
	all.append(champion_imp_matriarch)

	# Feral Imp Clan Spells

	var feral_surge := SpellCardData.new()
	feral_surge.id             = "feral_surge"
	feral_surge.card_name      = "Feral Surge"
	feral_surge.cost           = 1
	feral_surge.description    = "Give a friendly FERAL IMP minion +300 ATK."
	feral_surge.requires_target = true
	feral_surge.target_type    = "friendly_feral_imp"
	feral_surge.effect_steps   = [
		{"type": "BUFF_ATK", "scope": "SINGLE_CHOSEN_FRIENDLY", "filter": "FERAL_IMP", "amount": 300, "permanent": true},
	]
	feral_surge.faction   = "abyss_order"
	feral_surge.art_path  = "res://assets/art/spells/feral_imp_clan/feral_surge.png"
	all.append(feral_surge)

	var void_screech := SpellCardData.new()
	void_screech.id          = "void_screech"
	void_screech.card_name   = "Void Screech"
	void_screech.cost        = 1
	void_screech.description = "Deal 250 damage to enemy hero. If you have 3+ FERAL IMP minions on board, deal 350 instead."
	void_screech.effect_steps = [{
		"type": "DAMAGE_HERO", "amount": 250,
		"bonus_amount": 100, "bonus_conditions": ["feral_imp_count_gte_3"],
	}]
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
	pack_frenzy.description = "Give all friendly FERAL IMP minions +250 ATK and SWIFT this turn."
	pack_frenzy.effect_steps = [{"type": "HARDCODED", "hardcoded_id": "pack_frenzy"}]
	# ancient_frenzy enemy passive: pack_frenzy costs 1 less (3 → 2). Was applied
	# via runtime spell_cost_discounts dict in CombatSetup; migrated here so the
	# enemy hand displays the discounted cost from turn 1 and the source-of-truth
	# lives on the card.
	pack_frenzy.talent_overrides = [
		{ "talent_id": "ancient_frenzy", "cost": 2 },
	]
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
	cult_fanatic.faction      = "abyss_order"
	all.append(cult_fanatic)

	var dark_command := SpellCardData.new()
	dark_command.id          = "dark_command"
	dark_command.card_name   = "Dark Command"
	dark_command.cost        = 1
	dark_command.description = "Give all friendly Human minions +100 ATK and +100 HP."
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
	champion_abyss_cultist_patrol.description  = "Summoned after 4 corruption stacks consumed.\nAURA: Corruption applied to enemy minions instantly detonates."
	champion_abyss_cultist_patrol.atk          = 300
	champion_abyss_cultist_patrol.health       = 300
	champion_abyss_cultist_patrol.minion_type  = Enums.MinionType.HUMAN
	champion_abyss_cultist_patrol.keywords     = [Enums.Keyword.CHAMPION]
	champion_abyss_cultist_patrol.is_champion  = true
	champion_abyss_cultist_patrol.minion_tags  = ["enemy_champion"]
	champion_abyss_cultist_patrol.art_path             = "res://assets/art/minions/abyss_order/champion_abyss_cultist_patrol.png"
	champion_abyss_cultist_patrol.faction      = "abyss_order"
	all.append(champion_abyss_cultist_patrol)

	var champion_void_ritualist := MinionCardData.new()
	champion_void_ritualist.id           = "champion_void_ritualist"
	champion_void_ritualist.card_name    = "Void Ritualist"
	champion_void_ritualist.essence_cost = 0
	champion_void_ritualist.description  = "Summoned when ritual sacrifice triggers.\nAURA: Rune placement costs 1 less Mana."
	champion_void_ritualist.atk          = 200
	champion_void_ritualist.health       = 300
	champion_void_ritualist.minion_type  = Enums.MinionType.HUMAN
	champion_void_ritualist.keywords     = [Enums.Keyword.CHAMPION]
	champion_void_ritualist.is_champion  = true
	champion_void_ritualist.minion_tags  = ["enemy_champion"]
	champion_void_ritualist.art_path             = "res://assets/art/minions/abyss_order/champion_void_ritualist.png"
	champion_void_ritualist.faction      = "abyss_order"
	all.append(champion_void_ritualist)

	var champion_corrupted_handler := MinionCardData.new()
	champion_corrupted_handler.id           = "champion_corrupted_handler"
	champion_corrupted_handler.card_name    = "Corrupted Handler"
	champion_corrupted_handler.essence_cost = 0
	champion_corrupted_handler.description  = "Summoned after 3 void sparks created.\nAURA: Whenever a Void Spark is summoned, deal 200 damage to enemy hero."
	champion_corrupted_handler.atk          = 300
	champion_corrupted_handler.health       = 300
	champion_corrupted_handler.minion_type  = Enums.MinionType.HUMAN
	champion_corrupted_handler.keywords     = [Enums.Keyword.CHAMPION]
	champion_corrupted_handler.is_champion  = true
	champion_corrupted_handler.minion_tags  = ["enemy_champion"]
	champion_corrupted_handler.art_path             = "res://assets/art/minions/abyss_order/champion_corrupted_handler.png"
	champion_corrupted_handler.faction      = "abyss_order"
	all.append(champion_corrupted_handler)

	# --- Act 3 champions ---

	var champion_rift_stalker := MinionCardData.new()
	champion_rift_stalker.id           = "champion_rift_stalker"
	champion_rift_stalker.card_name    = "Rift Stalker"
	champion_rift_stalker.essence_cost = 0
	champion_rift_stalker.description  = "Summoned after Void Sparks deal 1500 damage.\nAURA: All friendly Void Sparks are immune."
	champion_rift_stalker.atk          = 400
	champion_rift_stalker.health       = 400
	champion_rift_stalker.minion_type  = Enums.MinionType.SPIRIT
	champion_rift_stalker.keywords     = [Enums.Keyword.CHAMPION]
	champion_rift_stalker.is_champion  = true
	champion_rift_stalker.minion_tags  = ["enemy_champion"]
	champion_rift_stalker.art_path             = "res://assets/art/minions/abyss_order/champion_rift_stalker.png"
	champion_rift_stalker.faction      = "abyss_order"
	all.append(champion_rift_stalker)

	var champion_void_aberration := MinionCardData.new()
	champion_void_aberration.id           = "champion_void_aberration"
	champion_void_aberration.card_name    = "Void Aberration"
	champion_void_aberration.essence_cost = 0
	champion_void_aberration.description  = "Summoned after 5 sparks consumed as costs.\nAURA: Void Detonation deals 200 damage instead of 100."
	champion_void_aberration.atk          = 300
	champion_void_aberration.health       = 300
	champion_void_aberration.minion_type  = Enums.MinionType.SPIRIT
	champion_void_aberration.keywords     = [Enums.Keyword.CHAMPION, Enums.Keyword.ETHEREAL]
	champion_void_aberration.is_champion  = true
	champion_void_aberration.minion_tags  = ["enemy_champion"]
	champion_void_aberration.art_path             = "res://assets/art/minions/abyss_order/champion_void_aberration.png"
	champion_void_aberration.faction      = "abyss_order"
	all.append(champion_void_aberration)

	var champion_void_herald := MinionCardData.new()
	champion_void_herald.id           = "champion_void_herald"
	champion_void_herald.card_name    = "Void Herald"
	champion_void_herald.essence_cost = 0
	champion_void_herald.description  = "Summoned after 6 spark-cost cards played.\nAURA: All spark costs become 0. Void Rift stops generating sparks."
	champion_void_herald.atk          = 200
	champion_void_herald.health       = 500
	champion_void_herald.minion_type  = Enums.MinionType.SPIRIT
	champion_void_herald.keywords     = [Enums.Keyword.CHAMPION]
	champion_void_herald.is_champion  = true
	champion_void_herald.minion_tags  = ["enemy_champion"]
	champion_void_herald.art_path             = "res://assets/art/minions/abyss_order/champion_void_herald.png"
	champion_void_herald.faction      = "abyss_order"
	all.append(champion_void_herald)

	# --- Act 4 champions ---

	var champion_void_scout := MinionCardData.new()
	champion_void_scout.id           = "champion_void_scout"
	champion_void_scout.card_name    = "Void Scout"
	champion_void_scout.essence_cost = 0
	champion_void_scout.description  = "Summoned after 5 critical strikes consumed.\nAURA: Critical Strike deals 2.5x damage instead of 2x."
	champion_void_scout.atk          = 400
	champion_void_scout.health       = 500
	champion_void_scout.minion_type  = Enums.MinionType.SPIRIT
	champion_void_scout.keywords     = [Enums.Keyword.CHAMPION]
	champion_void_scout.is_champion  = true
	champion_void_scout.minion_tags  = ["enemy_champion"]
	champion_void_scout.art_path             = "res://assets/art/minions/abyss_order/champion_void_scout.png"
	champion_void_scout.faction      = "abyss_order"
	all.append(champion_void_scout)

	var champion_void_warband := MinionCardData.new()
	champion_void_warband.id           = "champion_void_warband"
	champion_void_warband.card_name    = "Void Warband"
	champion_void_warband.essence_cost = 0
	champion_void_warband.description  = "Summoned after 3 Spirits consumed as fuel.\nOn summon: gains 1 Critical Strike.\nAURA: When a friendly Spirit with Crit is consumed, summon a 100/100 Void Spark."
	champion_void_warband.atk          = 500
	champion_void_warband.health       = 600
	champion_void_warband.minion_type  = Enums.MinionType.SPIRIT
	champion_void_warband.keywords     = [Enums.Keyword.CHAMPION]
	champion_void_warband.is_champion  = true
	champion_void_warband.minion_tags  = ["enemy_champion"]
	champion_void_warband.art_path             = "res://assets/art/minions/abyss_order/champion_void_warband.png"
	champion_void_warband.faction      = "abyss_order"
	all.append(champion_void_warband)

	var champion_void_captain := MinionCardData.new()
	champion_void_captain.id           = "champion_void_captain"
	champion_void_captain.card_name    = "Void Captain"
	champion_void_captain.essence_cost = 0
	champion_void_captain.description  = "Summoned after 2 Throne's Command cast.\nOn summon: gains 2 Critical Strike.\nAURA: When a friendly minion consumes a Critical Strike, deal 100 damage to each of 2 random enemies."
	champion_void_captain.atk          = 300
	champion_void_captain.health       = 600
	champion_void_captain.minion_type  = Enums.MinionType.SPIRIT
	champion_void_captain.keywords     = [Enums.Keyword.CHAMPION]
	champion_void_captain.is_champion  = true
	champion_void_captain.minion_tags  = ["enemy_champion"]
	champion_void_captain.art_path             = "res://assets/art/minions/abyss_order/champion_void_captain.png"
	champion_void_captain.faction      = "abyss_order"
	all.append(champion_void_captain)

	var champion_void_champion := MinionCardData.new()
	champion_void_champion.id           = "champion_void_champion"
	champion_void_champion.card_name    = "Void Champion"
	champion_void_champion.essence_cost = 0
	champion_void_champion.description  = "Summoned after 3 enemy minions killed by Critical Strike.\nOn summon: gains 3 Critical Strike.\nAURA: At end of enemy turn, gain +1 max Mana and +1 max Essence."
	champion_void_champion.atk          = 500
	champion_void_champion.health       = 600
	champion_void_champion.minion_type  = Enums.MinionType.SPIRIT
	champion_void_champion.keywords     = [Enums.Keyword.CHAMPION]
	champion_void_champion.is_champion  = true
	champion_void_champion.minion_tags  = ["enemy_champion"]
	champion_void_champion.art_path     = "res://assets/art/minions/abyss_order/champion_void_champion.png"
	champion_void_champion.faction      = "abyss_order"
	all.append(champion_void_champion)

	var champion_void_ritualist_prime := MinionCardData.new()
	champion_void_ritualist_prime.id           = "champion_void_ritualist_prime"
	champion_void_ritualist_prime.card_name    = "Void Ritualist Prime"
	champion_void_ritualist_prime.essence_cost = 0
	champion_void_ritualist_prime.description  = "Summoned after 5 enemy spells cast.\nOn summon: gains 2 Critical Strike.\nAURA: Friendly spells cost 1 less Mana."
	champion_void_ritualist_prime.atk          = 100
	champion_void_ritualist_prime.health       = 500
	champion_void_ritualist_prime.minion_type  = Enums.MinionType.SPIRIT
	champion_void_ritualist_prime.keywords     = [Enums.Keyword.CHAMPION]
	champion_void_ritualist_prime.is_champion  = true
	champion_void_ritualist_prime.minion_tags  = ["enemy_champion"]
	champion_void_ritualist_prime.art_path     = "res://assets/art/minions/abyss_order/champion_void_ritualist_prime.png"
	champion_void_ritualist_prime.faction      = "abyss_order"
	all.append(champion_void_ritualist_prime)

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
	phase_stalker.description     = "Consume 1 Void Spark."
	phase_stalker.atk             = 400
	phase_stalker.health          = 300
	phase_stalker.minion_type     = Enums.MinionType.SPIRIT
	phase_stalker.keywords.append(Enums.Keyword.SWIFT)
	phase_stalker.faction         = "abyss_order"
	phase_stalker.art_path             = "res://assets/art/minions/abyss_order/phase_stalker.png"
	all.append(phase_stalker)

	var rift_collapse := SpellCardData.new()
	rift_collapse.id              = "rift_collapse"
	rift_collapse.card_name       = "Rift Collapse"
	rift_collapse.cost            = 1
	rift_collapse.void_spark_cost = 1
	rift_collapse.description     = "Consume 1 Void Spark. Deal 200 damage to all enemy minions."
	rift_collapse.effect_steps    = [{"type": "DAMAGE_MINION", "scope": "ALL_ENEMY", "amount": 200, "damage_school": "VOID"}]
	rift_collapse.faction         = "abyss_order"
	rift_collapse.art_path        = "res://assets/art/spells/abyss_order/rift_collapse.png"
	all.append(rift_collapse)

	var void_lance := SpellCardData.new()
	void_lance.id              = "void_lance"
	void_lance.card_name       = "Void Lance"
	void_lance.cost            = 2
	void_lance.description     = "Deal 600 damage to a minion."
	void_lance.requires_target = true
	void_lance.target_type     = "any_minion"
	void_lance.effect_steps    = [{"type": "DAMAGE_MINION", "scope": "SINGLE_CHOSEN", "amount": 600, "damage_school": "VOID"}]
	void_lance.art_path        = "res://assets/art/spells/abyss_order/void_lance.png"
	void_lance.faction         = "abyss_order"
	all.append(void_lance)

	var void_behemoth := MinionCardData.new()
	void_behemoth.id              = "void_behemoth"
	void_behemoth.card_name       = "Void Behemoth"
	void_behemoth.essence_cost    = 3
	void_behemoth.void_spark_cost = 2
	void_behemoth.description     = "Consume 2 Void Sparks."
	void_behemoth.atk             = 400
	void_behemoth.health          = 600
	void_behemoth.minion_type     = Enums.MinionType.SPIRIT
	void_behemoth.keywords.append(Enums.Keyword.GUARD)
	void_behemoth.faction         = "abyss_order"
	void_behemoth.art_path             = "res://assets/art/minions/abyss_order/void_behemoth.png"
	all.append(void_behemoth)

	var dimensional_breach := SpellCardData.new()
	dimensional_breach.id              = "dimensional_breach"
	dimensional_breach.card_name       = "Dimensional Breach"
	dimensional_breach.cost            = 1
	dimensional_breach.void_spark_cost = 0
	dimensional_breach.description     = "Summon 2 Void Sparks."
	dimensional_breach.effect_steps    = [
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
	void_rift_lord.description     = "Consume 3 Void Sparks. ON PLAY: Set enemy Mana to 0 next turn."
	void_rift_lord.atk             = 400
	void_rift_lord.health          = 600
	void_rift_lord.minion_type     = Enums.MinionType.SPIRIT
	void_rift_lord.on_play_effect_steps = [{"type": "QUEUE_OPPONENT_MANA_DRAIN_NEXT_TURN"}]
	void_rift_lord.faction         = "abyss_order"
	void_rift_lord.art_path             = "res://assets/art/minions/abyss_order/void_rift_lord.png"
	all.append(void_rift_lord)

	# --- Act 3 new spells (mana-only, no spark cost) ---

	var void_shatter := SpellCardData.new()
	void_shatter.id          = "void_shatter"
	void_shatter.card_name   = "Void Shatter"
	void_shatter.cost        = 3
	void_shatter.description = "Deal 100 damage to a random enemy 8 times."
	void_shatter.effect_steps = [
		{"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM_ANY", "amount": 100, "damage_school": "VOID"},
		{"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM_ANY", "amount": 100, "damage_school": "VOID"},
		{"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM_ANY", "amount": 100, "damage_school": "VOID"},
		{"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM_ANY", "amount": 100, "damage_school": "VOID"},
		{"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM_ANY", "amount": 100, "damage_school": "VOID"},
		{"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM_ANY", "amount": 100, "damage_school": "VOID"},
		{"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM_ANY", "amount": 100, "damage_school": "VOID"},
		{"type": "DAMAGE_MINION", "scope": "SINGLE_RANDOM_ANY", "amount": 100, "damage_school": "VOID"},
	]
	void_shatter.requires_target = false
	void_shatter.art_path    = "res://assets/art/spells/abyss_order/void_shatter.png"
	void_shatter.faction     = "abyss_order"
	all.append(void_shatter)

	var spirit_surge := SpellCardData.new()
	spirit_surge.id          = "spirit_surge"
	spirit_surge.card_name   = "Spirit Surge"
	spirit_surge.cost        = 2
	spirit_surge.description = "Draw a Spark Cost card from your deck. Summon a 100/100 Void Spark."
	spirit_surge.effect_steps = [
		{"type": "TUTOR", "tutor_filter": "spark_cost"},
		{"type": "SUMMON", "card_id": "void_spark"},
	]
	spirit_surge.requires_target = false
	spirit_surge.art_path    = "res://assets/art/spells/abyss_order/spirit_surge.png"
	spirit_surge.faction     = "abyss_order"
	all.append(spirit_surge)

	var void_wind := SpellCardData.new()
	void_wind.id          = "void_wind"
	void_wind.card_name   = "Void Wind"
	void_wind.cost        = 1
	void_wind.description = "Destroy a random enemy trap. Heal your hero for 500 HP."
	void_wind.effect_steps = [
		{"type": "DESTROY", "scope": "SINGLE_RANDOM_OPPONENT_TRAP"},
		{"type": "HEAL_HERO", "amount": 500},
	]
	void_wind.requires_target = false
	void_wind.art_path    = "res://assets/art/spells/abyss_order/void_wind.png"
	void_wind.faction     = "abyss_order"
	all.append(void_wind)

	# ---------------------------------------------------------------------------
	# --- Act 4 — Void Castle enemy cards ---
	# ---------------------------------------------------------------------------

	# --- Spirit fuel minions (textless, consumable as spark fuel) ---

	var void_wisp := MinionCardData.new()
	void_wisp.id            = "void_wisp"
	void_wisp.card_name     = "Void Wisp"
	void_wisp.essence_cost  = 1
	void_wisp.atk           = 150
	void_wisp.health        = 200
	void_wisp.minion_type   = Enums.MinionType.SPIRIT
	void_wisp.spark_value   = 1
	void_wisp.faction       = "abyss_order"
	void_wisp.art_path             = "res://assets/art/minions/abyss_order/void_wisp.png"
	all.append(void_wisp)

	var void_shade := MinionCardData.new()
	void_shade.id            = "void_shade"
	void_shade.card_name     = "Void Shade"
	void_shade.essence_cost  = 2
	void_shade.atk           = 250
	void_shade.health        = 250
	void_shade.minion_type   = Enums.MinionType.SPIRIT
	void_shade.spark_value   = 2
	void_shade.faction       = "abyss_order"
	void_shade.art_path             = "res://assets/art/minions/abyss_order/void_shade.png"
	all.append(void_shade)

	var void_wraith := MinionCardData.new()
	void_wraith.id            = "void_wraith"
	void_wraith.card_name     = "Void Wraith"
	void_wraith.essence_cost  = 3
	void_wraith.atk           = 300
	void_wraith.health        = 400
	void_wraith.minion_type   = Enums.MinionType.SPIRIT
	void_wraith.spark_value   = 3
	void_wraith.faction       = "abyss_order"
	void_wraith.art_path             = "res://assets/art/minions/abyss_order/void_wraith.png"
	all.append(void_wraith)

	var void_revenant := MinionCardData.new()
	void_revenant.id            = "void_revenant"
	void_revenant.card_name     = "Void Revenant"
	void_revenant.essence_cost  = 5
	void_revenant.atk           = 500
	void_revenant.health        = 500
	void_revenant.minion_type   = Enums.MinionType.SPIRIT
	void_revenant.spark_value   = 4
	void_revenant.faction       = "abyss_order"
	void_revenant.art_path             = "res://assets/art/minions/abyss_order/void_revenant.png"
	all.append(void_revenant)

	# --- Spark consumer spells ---

	var sovereigns_decree := SpellCardData.new()
	sovereigns_decree.id               = "sovereigns_decree"
	sovereigns_decree.card_name        = "Sovereign's Decree"
	sovereigns_decree.cost             = 2
	sovereigns_decree.void_spark_cost  = 2
	sovereigns_decree.description      = "Deal 300 damage to enemy hero. Apply 2 Corruption to all enemy minions."
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
	thrones_command.void_spark_cost  = 2
	thrones_command.description      = "Give all friendly minions +1 Critical Strike."
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
	bastion_colossus.keywords             = [Enums.Keyword.GUARD, Enums.Keyword.ETHEREAL]
	bastion_colossus.on_play_effect_steps = [{"type": "GRANT_CRITICAL_STRIKE", "scope": "SELF", "amount": 2}]
	bastion_colossus.faction              = "abyss_order"
	bastion_colossus.art_path             = "res://assets/art/minions/abyss_order/bastion_colossus.png"
	all.append(bastion_colossus)

	# --- Non-spark spells ---

	var sovereigns_edict := SpellCardData.new()
	sovereigns_edict.id          = "sovereigns_edict"
	sovereigns_edict.card_name   = "Sovereign's Edict"
	sovereigns_edict.cost        = 3
	sovereigns_edict.description = "Give all friendly minions 'ON DEATH: Summon a Void Spark.'"
	sovereigns_edict.effect_steps = [{"type": "GRANT_ON_DEATH_SUMMON", "scope": "ALL_FRIENDLY", "card_id": "void_spark"}]
	sovereigns_edict.faction     = "abyss_order"
	sovereigns_edict.art_path    = "res://assets/art/spells/abyss_order/sovereigns_edict.png"
	all.append(sovereigns_edict)

	# --- Non-spark minion ---

	var sovereigns_herald := MinionCardData.new()
	sovereigns_herald.id                       = "sovereigns_herald"
	sovereigns_herald.card_name                = "Sovereign's Herald"
	sovereigns_herald.essence_cost             = 2
	sovereigns_herald.description              = "ON PLAY: Give a friendly minion +1 Critical Strike."
	sovereigns_herald.atk                      = 200
	sovereigns_herald.health                   = 200
	sovereigns_herald.minion_type              = Enums.MinionType.SPIRIT
	sovereigns_herald.on_play_target_optional  = true
	sovereigns_herald.on_play_target_type      = "friendly_minion"
	sovereigns_herald.on_play_target_prompt    = "Click a friendly minion to buff, or click a slot to summon without effect."
	sovereigns_herald.on_play_effect_steps     = [{"type": "GRANT_CRITICAL_STRIKE", "scope": "SINGLE_CHOSEN_FRIENDLY", "amount": 1}]
	sovereigns_herald.faction                  = "abyss_order"
	sovereigns_herald.art_path                 = "res://assets/art/minions/abyss_order/sovereigns_herald.png"
	all.append(sovereigns_herald)

	# --- New Act 3-4 Spirit minions ──────────────────────────────────────────

	var void_resonance := MinionCardData.new()
	void_resonance.id              = "void_resonance"
	void_resonance.card_name       = "Void Resonance"
	void_resonance.essence_cost    = 1
	void_resonance.description     = "ON PLAY: Heal your hero for 300 HP."
	void_resonance.atk             = 100
	void_resonance.health          = 100
	void_resonance.minion_type     = Enums.MinionType.SPIRIT
	void_resonance.keywords.append(Enums.Keyword.ETHEREAL)
	void_resonance.on_play_effect_steps = [{"type": "HEAL_HERO", "amount": 300}]
	void_resonance.art_path             = "res://assets/art/minions/abyss_order/void_resonance.png"
	void_resonance.faction         = "abyss_order"
	all.append(void_resonance)

	var void_echo := MinionCardData.new()
	void_echo.id              = "void_echo"
	void_echo.card_name       = "Void Echo"
	void_echo.essence_cost    = 2
	void_echo.description     = "ON PLAY: Draw 1 card."
	void_echo.atk             = 200
	void_echo.health          = 150
	void_echo.minion_type     = Enums.MinionType.SPIRIT
	void_echo.keywords.append(Enums.Keyword.SWIFT)
	void_echo.keywords.append(Enums.Keyword.ETHEREAL)
	void_echo.on_play_effect_steps = [{"type": "DRAW", "amount": 1}]
	void_echo.art_path             = "res://assets/art/minions/abyss_order/void_echo.png"
	void_echo.faction         = "abyss_order"
	all.append(void_echo)

	var rift_tender := MinionCardData.new()
	rift_tender.id              = "rift_tender"
	rift_tender.card_name       = "Rift Tender"
	rift_tender.essence_cost    = 2
	rift_tender.description     = "ON PLAY: Summon a 100/100 Void Spark."
	rift_tender.atk             = 150
	rift_tender.health          = 250
	rift_tender.minion_type     = Enums.MinionType.SPIRIT
	rift_tender.on_play_effect_steps = [{"type": "SUMMON", "card_id": "void_spark"}]
	rift_tender.art_path             = "res://assets/art/minions/abyss_order/rift_tender.png"
	rift_tender.faction         = "abyss_order"
	all.append(rift_tender)

	var hollow_sentinel := MinionCardData.new()
	hollow_sentinel.id              = "hollow_sentinel"
	hollow_sentinel.card_name       = "Hollow Sentinel"
	hollow_sentinel.essence_cost    = 4
	hollow_sentinel.description     = "AURA: At the end of your turn, give all friendly Void Sparks +100 ATK."
	hollow_sentinel.atk             = 300
	hollow_sentinel.health          = 500
	hollow_sentinel.minion_type     = Enums.MinionType.SPIRIT
	hollow_sentinel.keywords.append(Enums.Keyword.ETHEREAL)
	hollow_sentinel.passive_effect_id = "hollow_sentinel_spark_buff"
	hollow_sentinel.art_path             = "res://assets/art/minions/abyss_order/hollow_sentinel.png"
	hollow_sentinel.faction         = "abyss_order"
	all.append(hollow_sentinel)

	var phase_disruptor := MinionCardData.new()
	phase_disruptor.id              = "phase_disruptor"
	phase_disruptor.card_name       = "Phase Disruptor"
	phase_disruptor.essence_cost    = 3
	phase_disruptor.description     = "ON PLAY: Counter the next spell the enemy casts."
	phase_disruptor.atk             = 300
	phase_disruptor.health          = 250
	phase_disruptor.minion_type     = Enums.MinionType.SPIRIT
	phase_disruptor.keywords.append(Enums.Keyword.ETHEREAL)
	phase_disruptor.on_play_effect_steps = [{"type": "COUNTER_SPELL"}]
	phase_disruptor.art_path             = "res://assets/art/minions/abyss_order/phase_disruptor.png"
	phase_disruptor.faction         = "abyss_order"
	all.append(phase_disruptor)

	var void_architect := MinionCardData.new()
	void_architect.id              = "void_architect"
	void_architect.card_name       = "Void Architect"
	void_architect.essence_cost    = 3
	void_architect.description     = "ON PLAY: Increase max Mana by 1."
	void_architect.atk             = 250
	void_architect.health          = 400
	void_architect.minion_type     = Enums.MinionType.SPIRIT
	void_architect.on_play_effect_steps = [{"type": "GROW_MANA_MAX", "amount": 1}]
	void_architect.art_path             = "res://assets/art/minions/abyss_order/void_architect.png"
	void_architect.faction         = "abyss_order"
	all.append(void_architect)

	var riftscarred_colossus := MinionCardData.new()
	riftscarred_colossus.id              = "riftscarred_colossus"
	riftscarred_colossus.card_name       = "Riftscarred Colossus"
	riftscarred_colossus.essence_cost    = 4
	riftscarred_colossus.description     = "ON PLAY: Summon a 100/100 Void Spark."
	riftscarred_colossus.atk             = 500
	riftscarred_colossus.health          = 300
	riftscarred_colossus.minion_type     = Enums.MinionType.SPIRIT
	riftscarred_colossus.keywords.append(Enums.Keyword.SWIFT)
	riftscarred_colossus.on_play_effect_steps = [{"type": "SUMMON", "card_id": "void_spark"}]
	riftscarred_colossus.art_path             = "res://assets/art/minions/abyss_order/riftscarred_colossus.png"
	riftscarred_colossus.faction         = "abyss_order"
	all.append(riftscarred_colossus)

	var rift_warden := MinionCardData.new()
	rift_warden.id              = "rift_warden"
	rift_warden.card_name       = "Rift Warden"
	rift_warden.essence_cost    = 4
	rift_warden.void_spark_cost = 1
	rift_warden.description     = "AURA: Damage prevented by Ethereal is dealt to the enemy hero."
	rift_warden.atk             = 350
	rift_warden.health          = 400
	rift_warden.minion_type     = Enums.MinionType.SPIRIT
	rift_warden.keywords.append(Enums.Keyword.GUARD)
	rift_warden.keywords.append(Enums.Keyword.ETHEREAL)
	rift_warden.passive_effect_id = "rift_warden_siphon"
	rift_warden.art_path             = "res://assets/art/minions/abyss_order/rift_warden.png"
	rift_warden.faction         = "abyss_order"
	all.append(rift_warden)

	var ethereal_titan := MinionCardData.new()
	ethereal_titan.id              = "ethereal_titan"
	ethereal_titan.card_name       = "Ethereal Titan"
	ethereal_titan.essence_cost    = 5
	ethereal_titan.description     = ""
	ethereal_titan.atk             = 600
	ethereal_titan.health          = 400
	ethereal_titan.minion_type     = Enums.MinionType.SPIRIT
	ethereal_titan.keywords.append(Enums.Keyword.SWIFT)
	ethereal_titan.keywords.append(Enums.Keyword.ETHEREAL)
	ethereal_titan.keywords.append(Enums.Keyword.PIERCE)
	ethereal_titan.art_path             = "res://assets/art/minions/abyss_order/ethereal_titan.png"
	ethereal_titan.faction         = "abyss_order"
	all.append(ethereal_titan)

	# --- Pool assignments (controls deck builder visibility and collection) ---
	# Each value is an Array[String] — most cards live in one pool, but a card may
	# belong to multiple (e.g. soul_shatter is in both vael_common and seris_demon_forge).
	# Cards with no entry default to [] (token/internal — not surfaced through acquisition).
	var _card_pools := {
		# Abyss core (starter deck pool)
		"void_imp": ["abyss_core"],         "shadow_hound": ["abyss_core"],
		"abyssal_brute": ["abyss_core"],    "nyx_ael": ["abyss_core"],
		"abyss_cultist": ["abyss_core"],    "void_netter": ["abyss_core"],
		"corruption_weaver": ["abyss_core"],"soul_collector": ["abyss_core"],
		"void_stalker": ["abyss_core"],     "void_spawner": ["abyss_core"],
		"abyssal_tide": ["abyss_core"],     "void_devourer": ["abyss_core"],
		"void_bolt": ["abyss_core"],        "dark_empowerment": ["abyss_core"],
		"abyssal_sacrifice": ["abyss_core"],"abyssal_plague": ["abyss_core"],
		"void_summoning": ["abyss_core"],   "void_execution": ["abyss_core"],
		"dark_covenant": ["abyss_core"],    "abyssal_summoning_circle": ["abyss_core"],
		"void_rune": ["abyss_core"],        "blood_rune": ["abyss_core"],
		"dominion_rune": ["abyss_core"],    "shadow_rune": ["abyss_core"],
		"grafted_fiend": ["abyss_core"],
		# Seris Core Pool — visible only when Seris is the active hero (see DeckBuilderScene._deck_builder_pools_for_hero)
		"void_spawning": ["seris_core"],
		"fiendish_pact": ["seris_core"],
		"grafted_butcher": ["seris_core"],
		"flesh_rend": ["seris_core"],
		# Seris Common Support Pool — combat reward / shop pool for Seris (see RewardScene._get_active_support_pool_ids)
		"flesh_harvester": ["seris_common"],
		"ravenous_fiend": ["seris_common"],
		"feast_of_flesh": ["seris_common"],
		"mend_the_flesh": ["seris_common"],
		"flesh_eruption": ["seris_common"],
		"gorged_fiend": ["seris_common"],
		"flesh_stitched_horror": ["seris_common"],
		"flesh_rune": ["seris_common"],
		# Seris Fleshcraft Pool — unlocked by flesh_infusion talent
		"grafted_reaver": ["seris_fleshcraft"],
		"flesh_scout": ["seris_fleshcraft"],
		"flesh_surgeon": ["seris_fleshcraft"],
		"flesh_sacrament": ["seris_fleshcraft"],
		"matron_of_flesh": ["seris_fleshcraft"],
		# Seris Demon Forge Pool — unlocked by soul_forge talent
		"altar_thrall": ["seris_demon_forge"],
		"forge_acolyte": ["seris_demon_forge"],
		"ember_pact": ["seris_demon_forge"],
		"bound_offering": ["seris_demon_forge"],
		"forgeborn_tyrant": ["seris_demon_forge"],
		# Seris Corruption Engine Pool — unlocked by corrupt_flesh talent
		# font_of_the_depths is dual-pooled (also vael_piercing_void) — see below.
		"bloodscribe_imp": ["seris_corruption"],
		"tainted_ritualist": ["seris_corruption"],
		"festering_fiend": ["seris_corruption"],
		"self_mutilation": ["seris_corruption"],
		"resonant_outburst": ["seris_corruption"],
		"voidshaped_acolyte": ["seris_corruption"],
		"recursive_hex": ["seris_corruption"],
		# Neutral core (starter deck pool)
		"roadside_drifter": ["neutral_core"],  "ashland_forager": ["neutral_core"],
		"freelance_sellsword": ["neutral_core"],"traveling_merchant": ["neutral_core"],
		"trapbreaker_rogue": ["neutral_core"], "caravan_guard": ["neutral_core"],
		"arena_challenger": ["neutral_core"],  "spell_taxer": ["neutral_core"],
		"saboteur_adept": ["neutral_core"],    "aether_bulwark": ["neutral_core"],
		"bulwark_automaton": ["neutral_core"], "wandering_warden": ["neutral_core"],
		"ruins_archivist": ["neutral_core"],   "wildland_behemoth": ["neutral_core"],
		"stone_sentinel": ["neutral_core"],    "rift_leviathan": ["neutral_core"],
		"energy_conversion": ["neutral_core"], "arcane_strike": ["neutral_core"],
		"purge": ["neutral_core"],             "cyclone": ["neutral_core"],
		"tactical_planning": ["neutral_core"], "precision_strike": ["neutral_core"],
		"hurricane": ["neutral_core"],         "flux_siphon": ["neutral_core"],
		"hidden_ambush": ["neutral_core"],     "smoke_veil": ["neutral_core"],
		"silence_trap": ["neutral_core"],      "death_trap": ["neutral_core"],
		# Lord Vael — Piercing Void unlock pool
		# font_of_the_depths is dual-pooled — also offered to Corruption Engine decks.
		"font_of_the_depths": ["vael_piercing_void", "seris_corruption"],
		"mark_the_target": ["vael_piercing_void"],
		"void_detonation": ["vael_piercing_void"],
		"abyssal_arcanist": ["vael_piercing_void"],
		"void_archmagus": ["vael_piercing_void"],
		"abyss_ritual_circle": ["vael_piercing_void"],
		# Lord Vael — common unlock pool
		"imp_recruiter": ["vael_common"],  "blood_pact": ["vael_common"],
		"soul_taskmaster": ["vael_common"],
		# soul_shatter is dual-pooled — also offered to Demon Forge decks.
		"soul_shatter": ["vael_common", "seris_demon_forge"],
		"void_amplifier": ["vael_common"], "soul_rune": ["vael_common"],
		# Lord Vael — Endless Tide unlock pool (imp_evolution talent)
		"imp_frenzy": ["vael_endless_tide"],       "imp_martyr": ["vael_endless_tide"],
		"imp_vessel": ["vael_endless_tide"],        "imp_idol": ["vael_endless_tide"],
		"vaels_colossal_guard": ["vael_endless_tide"],
		# Lord Vael — Rune Master unlock pool (rune_caller talent)
		"runic_blast": ["vael_rune_master"],       "runic_echo": ["vael_rune_master"],
		"rune_warden": ["vael_rune_master"],        "rune_seeker": ["vael_rune_master"],
		# echo_rune: removed from pool — granted as capstone reward (abyss_convergence)
		# Feral Imp Clan — Act 1 enemy-only pool (not visible to players)
		"rabid_imp": ["feral_imp_clan"],             "brood_imp": ["feral_imp_clan"],
		"imp_brawler": ["feral_imp_clan"],           "void_touched_imp": ["feral_imp_clan"],
		"frenzied_imp": ["feral_imp_clan"],          "matriarchs_broodling": ["feral_imp_clan"],
		"rogue_imp_elder": ["feral_imp_clan"],
		"feral_surge": ["feral_imp_clan"],           "void_screech": ["feral_imp_clan"],
		"brood_call": ["feral_imp_clan"],            "pack_frenzy": ["feral_imp_clan"],
		# Abyss Dungeon — Act 2 enemy-only pool (not visible to players)
		"cult_fanatic": ["abyss_cultist_clan"],     "dark_command": ["abyss_cultist_clan"],
		# Void Rift World — Act 3 enemy-only pool (not visible to players)
		"void_pulse": ["void_rift"],              "phase_stalker": ["void_rift"],
		"rift_collapse": ["void_rift"],           "void_behemoth": ["void_rift"],
		"dimensional_breach": ["void_rift"],      "void_rift_lord": ["void_rift"],
		"void_resonance": ["void_rift"],          "void_echo": ["void_rift"],
		"rift_tender": ["void_rift"],             "hollow_sentinel": ["void_rift"],
		"phase_disruptor": ["void_rift"],         "void_architect": ["void_rift"],
		"riftscarred_colossus": ["void_rift"],    "rift_warden": ["void_rift"],
		"ethereal_titan": ["void_rift"],
		"void_shatter": ["void_rift"],            "spirit_surge": ["void_rift"],
		"void_wind": ["void_rift"],
		# Void Castle — Act 4 enemy-only pool (not visible to players)
		"void_wisp": ["void_castle"],            "void_shade": ["void_castle"],
		"void_wraith": ["void_castle"],          "void_revenant": ["void_castle"],
		"sovereigns_decree": ["void_castle"],    "thrones_command": ["void_castle"],
		"bastion_colossus": ["void_castle"],     "sovereigns_edict": ["void_castle"],
		"sovereigns_herald": ["void_castle"],
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
		# Seris common pool — gate by rarity (Common=1, Rare=2, Epic=3)
		"flesh_harvester": 1,             "ravenous_fiend": 1,
		"feast_of_flesh": 1,              "mend_the_flesh": 1,
		"flesh_eruption": 1,
		"gorged_fiend": 2,                "flesh_stitched_horror": 2,
		"flesh_rune": 3,
		# Seris Fleshcraft pool
		"grafted_reaver": 1,              "flesh_scout": 1,
		"flesh_surgeon": 1,
		"flesh_sacrament": 2,
		"matron_of_flesh": 3,
		# Seris Demon Forge pool (soul_shatter already gated above for vael_common at 2)
		"altar_thrall": 1,                "forge_acolyte": 1,
		"ember_pact": 1,
		"bound_offering": 2,
		"forgeborn_tyrant": 3,
		# Seris Corruption Engine pool (font_of_the_depths already gated above for vael_piercing_void at 1)
		"bloodscribe_imp": 1,             "tainted_ritualist": 1,
		"festering_fiend": 1,             "self_mutilation": 1,
		"resonant_outburst": 2,           "voidshaped_acolyte": 2,
		"recursive_hex": 3,
	}
	# Append all token cards (pool = "", rarity = "")
	for td in _TOKEN_DEFS:
		all.append(_make_token(td))

	for c in all:
		var p: Array = _card_pools.get(c.id, [])
		var pools_typed: Array[String] = []
		pools_typed.assign(p)
		c.pools    = pools_typed
		c.act_gate = _card_act_gates.get(c.id, 0)

	for c in all:
		_register(c)
