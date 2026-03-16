## TalentDatabase.gd
## Autoload — holds every talent definition for every hero.
## Access via: TalentDatabase.get_talent("imp_empowerment")
extends Node

var _talents: Dictionary = {}

func _ready() -> void:
	_register_lord_vael_talents()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func get_talent(id: String) -> TalentData:
	if _talents.has(id):
		return _talents[id]
	push_error("TalentDatabase: unknown talent id '%s'" % id)
	return null

## All talents for a given branch, sorted by tier (entry first, capstone last).
func get_branch(branch: String) -> Array[TalentData]:
	var result: Array[TalentData] = []
	for t in _talents.values():
		if t.branch == branch:
			result.append(t)
	result.sort_custom(func(a: TalentData, b: TalentData) -> bool: return a.tier < b.tier)
	return result

## Talents that can currently be unlocked: prerequisite met, not yet owned.
func get_available(unlocked: Array[String]) -> Array[TalentData]:
	var result: Array[TalentData] = []
	for t in _talents.values():
		if t.id in unlocked:
			continue
		if t.requires == "" or t.requires in unlocked:
			result.append(t)
	return result

## All talents belonging to a specific hero, sorted by branch then tier.
func get_talents_for_hero(hero_id: String) -> Array[TalentData]:
	var result: Array[TalentData] = []
	for t in _talents.values():
		if t.hero_id == hero_id:
			result.append(t)
	result.sort_custom(func(a: TalentData, b: TalentData) -> bool:
		if a.branch != b.branch:
			return a.branch < b.branch
		return a.tier < b.tier)
	return result

## Display name for a branch id. Falls back to the id itself if not mapped.
func get_branch_display_name(branch_id: String) -> String:
	const DISPLAY_NAMES: Dictionary = {
		"swarm":       "Endless Tide",
		"rune_master": "Rune Master",
		"void_bolt":   "Void Resonance",
	}
	return DISPLAY_NAMES.get(branch_id, branch_id)

## Short one-line description shown on the hero selection card.
func get_branch_description(branch_id: String) -> String:
	const DESCRIPTIONS: Dictionary = {
		"swarm":       "Overwhelm the board with Void Imps.",
		"rune_master": "Harness the Runes to unleash devastating grand rituals.",
		"void_bolt":   "Strike with amplified Void energy.",
	}
	return DESCRIPTIONS.get(branch_id, "")

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func _register(t: TalentData) -> void:
	_talents[t.id] = t

func _make(id: String, hero: String, name: String, desc: String,
		branch: String, tier: int, req: String) -> TalentData:
	var t := TalentData.new()
	t.id          = id
	t.hero_id     = hero
	t.talent_name = name
	t.description = desc
	t.branch      = branch
	t.tier        = tier
	t.requires    = req
	return t

# ---------------------------------------------------------------------------
# Lord Vael — 12 talents across 3 branches
# ---------------------------------------------------------------------------

func _register_lord_vael_talents() -> void:

	# -----------------------------------------------------------------------
	# Branch 1 — Board Swarm (Imp evolution & board flooding)
	# -----------------------------------------------------------------------

	_register(_make(
		"imp_evolution", "lord_vael", "Imp Evolution",
		"When you summon a Void Imp, add a Senior Void Imp to your hand.\nTrigger limit: once per turn.",
		"swarm", 0, ""))

	_register(_make(
		"swarm_discipline", "lord_vael", "Swarm Discipline",
		"Void Imps gain +100 HP.",
		"swarm", 1, "imp_evolution"))

	_register(_make(
		"imp_warband", "lord_vael", "Imp Warband",
		"When you summon a Senior Void Imp, all Void Imps gain +50 ATK permanently.",
		"swarm", 2, "swarm_discipline"))

	_register(_make(
		"abyssal_legion", "lord_vael", "Abyssal Legion",
		"If you control 3 or more Void Imps, they gain +100 ATK and +100 HP.",
		"swarm", 3, "imp_warband"))

	_register(_make(
		"void_echo", "lord_vael", "Void Echo",
		"CAPSTONE: Whenever you draw a Void Imp, add a free copy to your hand.",
		"swarm", 4, "abyssal_legion"))

	# -----------------------------------------------------------------------
	# Branch 2 — Rune Master (rune synergy & grand rituals)
	# -----------------------------------------------------------------------

	_register(_make(
		"rune_caller", "lord_vael", "Rune Caller",
		"Playing a Void Imp from hand draws a random Rune from your deck.",
		"rune_master", 0, ""))

	_register(_make(
		"runic_attunement", "lord_vael", "Runic Attunement",
		"All Rune aura effects are doubled.",
		"rune_master", 1, "rune_caller"))

	_register(_make(
		"ritual_surge", "lord_vael", "Ritual Surge",
		"When any ritual fires, summon 2 Void Imps.",
		"rune_master", 2, "runic_attunement"))

	var abyss_convergence := _make(
		"abyss_convergence", "lord_vael", "Abyss Convergence",
		"CAPSTONE: Grand Ritual — Blood, Dominion, and Shadow Runes on board simultaneously triggers Abyssal Dominion with no Environment required.\nConsumes all three Runes. Deals 300 damage to all enemy minions. All friendly Demons permanently gain +200 ATK and +200 HP.",
		"rune_master", 3, "ritual_surge")
	var grand_r := RitualData.new()
	grand_r.ritual_name  = "Abyssal Dominion"
	grand_r.description  = "Grand Ritual: Blood + Dominion + Shadow Runes"
	grand_r.required_runes = [
		Enums.RuneType.BLOOD_RUNE,
		Enums.RuneType.DOMINION_RUNE,
		Enums.RuneType.SHADOW_RUNE,
	]
	grand_r.effect_id = "abyssal_dominion"
	abyss_convergence.grand_ritual = grand_r
	_register(abyss_convergence)

	# -----------------------------------------------------------------------
	# Branch 3 — Void Bolt (mana burn & Void Mark scaling)
	# -----------------------------------------------------------------------

	_register(_make(
		"piercing_void", "lord_vael", "Piercing Void",
		"On play, Void Imps deal 200 Void Bolt damage and apply 1 Void Mark.\nVoid Imps cost +1 Mana.",
		"void_bolt", 0, ""))

	_register(_make(
		"deepened_curse", "lord_vael", "Deepened Curse",
		"Void Mark bonus increases from +25 to +50 damage per stack.",
		"void_bolt", 1, "piercing_void"))

	_register(_make(
		"death_bolt", "lord_vael", "Death Bolt",
		"When a Void Imp dies, deal 100 Void Bolt damage to the enemy hero.",
		"void_bolt", 2, "deepened_curse"))

	_register(_make(
		"void_manifestation", "lord_vael", "Void Manifestation",
		"CAPSTONE: Void Imps' attacks become Void Bolts targeting the enemy hero, ignoring Taunt.",
		"void_bolt", 3, "death_bolt"))
