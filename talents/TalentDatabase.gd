## TalentDatabase.gd
## Autoload — holds every talent definition for every hero.
## Access via: TalentDatabase.get_talent("imp_empowerment")
extends Node

var _talents: Dictionary = {}

func _ready() -> void:
	_register_lord_vael_talents()
	_register_seris_talents()

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
## Once any talent is unlocked, only talents from that same branch are available.
func get_available(unlocked: Array[String]) -> Array[TalentData]:
	# Determine which branch the player has committed to (if any).
	var committed_branch := ""
	for id in unlocked:
		if _talents.has(id):
			committed_branch = _talents[id].branch
			break  # All unlocked talents share the same branch by design.

	var result: Array[TalentData] = []
	for t in _talents.values():
		if t.id in unlocked:
			continue
		if committed_branch != "" and t.branch != committed_branch:
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
		"swarm":             "Endless Tide",
		"rune_master":       "Rune Master",
		"void_bolt":         "Void Resonance",
		"fleshcraft":        "Fleshcraft",
		"demon_forge":       "Demon Forge",
		"corruption_engine": "Corruption Engine",
	}
	return DISPLAY_NAMES.get(branch_id, branch_id)

## Short one-line description shown on the hero selection card.
func get_branch_description(branch_id: String) -> String:
	const DESCRIPTIONS: Dictionary = {
		"swarm":             "Overwhelm the board with Void Imps.",
		"rune_master":       "Harness the Runes to unleash devastating grand rituals.",
		"void_bolt":         "Strike with amplified Void energy.",
		"fleshcraft":        "Empower Grafted Fiends; grow them through kills.",
		"demon_forge":       "Sacrifice Demons to forge greater ones.",
		"corruption_engine": "Turn Corruption into power, detonate it for damage and Flesh.",
	}
	return DESCRIPTIONS.get(branch_id, "")

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func _register(t: TalentData) -> void:
	_talents[t.id] = t

func _make(id: String, hero: String, name: String, desc: String,
		branch: String, tier: int, req: String, icon_path: String = "") -> TalentData:
	var t := TalentData.new()
	t.id          = id
	t.hero_id     = hero
	t.talent_name = name
	t.description = desc
	t.branch      = branch
	t.tier        = tier
	t.requires    = req
	t.icon_path   = icon_path
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
		"swarm", 0, "", "res://assets/art/talents/lord_vael/icon_imp_evolution.png"))

	_register(_make(
		"swarm_discipline", "lord_vael", "Swarm Discipline",
		"VOID IMP CLAN minions gain +100 HP.",
		"swarm", 1, "imp_evolution", "res://assets/art/talents/lord_vael/icon_swarm_discipline.png"))

	_register(_make(
		"imp_warband", "lord_vael", "Imp Warband",
		"When you summon a Senior Void Imp, all other VOID IMP CLAN minions gain +50 ATK.",
		"swarm", 2, "swarm_discipline", "res://assets/art/talents/lord_vael/icon_imp_warband.png"))

	_register(_make(
		"void_echo", "lord_vael", "Void Echo",
		"CAPSTONE: Once per turn, when you draw a Void Imp, add a free Void Imp copy to your hand.",
		"swarm", 3, "imp_warband", "res://assets/art/talents/lord_vael/icon_void_echo.png"))

	# -----------------------------------------------------------------------
	# Branch 2 — Rune Master (rune synergy & grand rituals)
	# -----------------------------------------------------------------------

	_register(_make(
		"rune_caller", "lord_vael", "Rune Caller",
		"Playing a Void Imp from hand draws a random Rune from your deck. That Rune costs 1 less Mana this turn.",
		"rune_master", 0, "", "res://assets/art/talents/lord_vael/icon_rune_caller.png"))

	_register(_make(
		"runic_attunement", "lord_vael", "Runic Attunement",
		"All Rune aura effects are doubled.",
		"rune_master", 1, "rune_caller", "res://assets/art/talents/lord_vael/icon_runic_attunement.png"))

	_register(_make(
		"ritual_surge", "lord_vael", "Ritual Surge",
		"When any ritual fires, summon a Void Imp.",
		"rune_master", 2, "runic_attunement", "res://assets/art/talents/lord_vael/icon_ritual_surge.png"))

	var abyss_convergence := _make(
		"abyss_convergence", "lord_vael", "Abyss Convergence",
		"CAPSTONE: Grand Ritual — Blood, Dominion, and Shadow Runes on board simultaneously triggers Abyssal Dominion with no Environment required.\nConsumes all three Runes. Deals 300 damage to all enemy minions. Give all friendly Demons +200 ATK and +200 HP.",
		"rune_master", 3, "ritual_surge", "res://assets/art/talents/lord_vael/icon_abyss_convergence.png")
	var grand_r := RitualData.new()
	grand_r.ritual_name  = "Abyssal Dominion"
	grand_r.description  = "Grand Ritual: Blood + Dominion + Shadow Runes"
	grand_r.required_runes = [
		Enums.RuneType.BLOOD_RUNE,
		Enums.RuneType.DOMINION_RUNE,
		Enums.RuneType.SHADOW_RUNE,
	]
	grand_r.effect_steps = [
		{"type": "DAMAGE_MINION", "scope": "ALL_ENEMY",      "amount": 300},
		{"type": "BUFF_ATK",      "scope": "ALL_FRIENDLY", "filter": "DEMON", "amount": 200, "permanent": true, "source_tag": "abyssal_dominion"},
		{"type": "BUFF_HP",       "scope": "ALL_FRIENDLY", "filter": "DEMON", "amount": 200, "permanent": true},
	]
	abyss_convergence.grand_ritual = grand_r
	_register(abyss_convergence)

	# -----------------------------------------------------------------------
	# Branch 3 — Void Bolt (mana burn & Void Mark scaling)
	# -----------------------------------------------------------------------

	_register(_make(
		"piercing_void", "lord_vael", "Piercing Void",
		"On play, Void Imps deal 200 Void Bolt damage and apply 1 Void Mark.\nVoid Imps cost +1 Mana.",
		"void_bolt", 0, "", "res://assets/art/talents/lord_vael/icon_piercing_void.png"))

	_register(_make(
		"deepened_curse", "lord_vael", "Deepened Curse",
		"Void Mark bonus increases from +25 to +40 damage per stack.",
		"void_bolt", 1, "piercing_void", "res://assets/art/talents/lord_vael/icon_deepened_curse.png"))

	_register(_make(
		"death_bolt", "lord_vael", "Death Bolt",
		"When a VOID IMP CLAN minion dies, deal 100 Void Bolt damage to enemy hero.",
		"void_bolt", 2, "deepened_curse", "res://assets/art/talents/lord_vael/icon_death_bolt.png"))

	_register(_make(
		"void_manifestation", "lord_vael", "Void Manifestation",
		"CAPSTONE: VOID IMP CLAN minions deal Void Bolt damage when attacking enemy hero.",
		"void_bolt", 3, "death_bolt", "res://assets/art/talents/lord_vael/icon_void_manifestation.png"))

# ---------------------------------------------------------------------------
# Seris, the Fleshbinder — 12 talents across 3 branches
# ---------------------------------------------------------------------------

func _register_seris_talents() -> void:

	# -----------------------------------------------------------------------
	# Branch 1 — Fleshcraft (empower Fiends; grow through kills)
	# -----------------------------------------------------------------------

	_register(_make(
		"flesh_infusion", "seris", "Flesh Infusion",
		"When you play a Grafted Fiend, spend 1 Flesh to give it +200 ATK permanently.",
		"fleshcraft", 0, "", "res://assets/art/talents/seris/icon_flesh_infusion.png"))

	_register(_make(
		"grafted_constitution", "seris", "Grafted Constitution",
		"Grafted Fiend permanently gains +100/+100 whenever it kills an enemy minion.",
		"fleshcraft", 1, "flesh_infusion", "res://assets/art/talents/seris/icon_grafted_constitution.png"))

	_register(_make(
		"predatory_surge", "seris", "Predatory Surge",
		"Grafted Fiends enter with Swift. When a Grafted Fiend reaches 3 kill stacks, it permanently gains Siphon.",
		"fleshcraft", 2, "grafted_constitution", "res://assets/art/talents/seris/icon_predatory_surge.png"))

	_register(_make(
		"deathless_flesh", "seris", "Deathless Flesh",
		"CAPSTONE: When a Grafted Fiend would die, spend 2 Flesh instead. If fewer than 2 Flesh, it dies normally.",
		"fleshcraft", 3, "predatory_surge", "res://assets/art/talents/seris/icon_deathless_flesh.png"))

	# -----------------------------------------------------------------------
	# Branch 2 — Demon Forge (sacrifice Demons to forge greater ones)
	# -----------------------------------------------------------------------

	_register(_make(
		"soul_forge", "seris", "Soul Forge",
		"Spend 3 Flesh: summon a Grafted Fiend from outside your deck. Sacrificing any Demon adds 1 to the Forge Counter; at 3, summon a 500/500 Forged Demon and reset the counter.",
		"demon_forge", 0, "", "res://assets/art/talents/seris/icon_soul_forge.png"))

	_register(_make(
		"fiend_offering", "seris", "Fiend Offering",
		"When a Grafted Fiend is sacrificed to the Forge Counter, you may spend 2 Flesh to summon a 400/400 Lesser Demon.",
		"demon_forge", 1, "soul_forge", "res://assets/art/talents/seris/icon_fiend_offering.png"))

	_register(_make(
		"forge_momentum", "seris", "Forge Momentum",
		"Forge Counter requirement reduced to 2.",
		"demon_forge", 2, "fiend_offering", "res://assets/art/talents/seris/icon_forge_momentum.png"))

	_register(_make(
		"abyssal_forge", "seris", "Abyssal Forge",
		"CAPSTONE: When a Forged Demon is summoned, it randomly gains one of Void Growth, Void Pulse, or Flesh Bond. Spend 5 Flesh to grant all three instead.",
		"demon_forge", 3, "forge_momentum", "res://assets/art/talents/seris/icon_abyssal_forge.png"))

	# -----------------------------------------------------------------------
	# Branch 3 — Corruption Engine (weaponise Corruption, detonate for damage & Flesh)
	# -----------------------------------------------------------------------

	_register(_make(
		"corrupt_flesh", "seris", "Corrupt Flesh",
		"Corruption stacks on friendly Demons grant +100 ATK per stack instead of -100. Spend 1 Flesh: apply 1 Corruption stack to a chosen friendly Demon. If the target is a Grafted Fiend, apply 2 stacks instead.",
		"corruption_engine", 0, "", "res://assets/art/talents/seris/icon_corrupt_flesh.png"))

	_register(_make(
		"corrupt_detonation", "seris", "Corrupt Detonation",
		"Whenever Corruption stacks are removed from a friendly Demon by any means, deal 100 damage per stack to a random enemy.",
		"corruption_engine", 1, "corrupt_flesh", "res://assets/art/talents/seris/icon_corrupt_detonation.png"))

	_register(_make(
		"void_amplification", "seris", "Void Amplification",
		"Your spells deal +50 damage per Corruption stack across all friendly Demons.",
		"corruption_engine", 2, "corrupt_detonation", "res://assets/art/talents/seris/icon_void_amplification.png"))

	_register(_make(
		"void_resonance_seris", "seris", "Void Resonance",
		"CAPSTONE: When a friendly minion kills an enemy minion, gain 1 Flesh. When you cast a spell with 5 Flesh, consume all Flesh and cast the spell twice.",
		"corruption_engine", 3, "void_amplification", "res://assets/art/talents/seris/icon_void_resonance.png"))
