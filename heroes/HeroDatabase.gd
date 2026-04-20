## HeroDatabase.gd
## Autoload - single source of truth for all hero definitions.
## Usage: HeroDatabase.get_hero("lord_vael")
##        HeroDatabase.get_all_heroes()
##        HeroDatabase.has_passive("lord_vael", "void_imp_boost")
extends Node

var _heroes: Dictionary = {}

func _ready() -> void:
	_register_lord_vael()
	_register_seris()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns the HeroData for the given id, or null if not found.
func get_hero(id: String) -> HeroData:
	if _heroes.has(id):
		return _heroes[id]
	push_error("HeroDatabase: unknown hero id '%s'" % id)
	return null

## Returns all registered heroes in registration order.
func get_all_heroes() -> Array[HeroData]:
	var result: Array[HeroData] = []
	for h in _heroes.values():
		result.append(h as HeroData)
	return result

## Returns true if the given hero has the specified passive active.
## Use this in combat code instead of `current_hero == "lord_vael"` guards.
func has_passive(hero_id: String, passive_id: String) -> bool:
	var hero := get_hero(hero_id)
	if hero == null:
		return false
	for p in hero.passives:
		if p.id == passive_id:
			return true
	return false

# ---------------------------------------------------------------------------
# Registration helpers
# ---------------------------------------------------------------------------

func _register(h: HeroData) -> void:
	_heroes[h.id] = h

func _make_passive(id: String, desc: String, icon_path: String = "") -> HeroPassive:
	var p := HeroPassive.new()
	p.id = id
	p.description = desc
	p.icon_path = icon_path
	return p

# ---------------------------------------------------------------------------
# Lord Vael
# ---------------------------------------------------------------------------

func _register_lord_vael() -> void:
	var h := HeroData.new()
	h.id = "lord_vael"
	h.hero_name = "Lord Vael"
	h.title = "Void Caller"
	h.faction = "Abyss Order"
	h.portrait_path = "res://assets/art/hero_selection/hero_portrait/lord_vael_portrait.png"
	h.combat_portrait_path = "res://assets/art/heroes/combat_portraits/lord_vael_portrait_bf.png"
	h.frame_path = "res://assets/art/hero_selection/abyss_order_hero_frame.png"

	h.passives = [
		_make_passive(
			"void_imp_boost",
			"- VOID IMP CLAN minions have +100 ATK and +100 HP",
			"res://assets/art/passives/lord_vael/icon_void_imp_boost.png"
		),
		_make_passive(
			"void_imp_extra_copy",
			"- You may include up to 4 copies of Void Imp in your deck.",
			"res://assets/art/passives/lord_vael/icon_void_imp_extra_copy.png"
		),
	]

	# Branch IDs - must match TalentData.branch values registered in TalentDatabase.
	# Display names are resolved via TalentDatabase.get_branch_display_name(id).
	h.talent_branch_ids = ["swarm", "rune_master", "void_bolt"]

	# Cards available in the reward pool once permanently unlocked (boss drops).
	# Mirrors the "vael_common" pool in CardDatabase.
	h.hero_reward_pool = [
		"imp_recruiter", "blood_pact",
		"soul_taskmaster", "soul_shatter",
		"void_amplifier", "soul_rune",
	]

	h.flavor = "\"The Abyss does not consume - it remembers.\"\n- Lord Vael, at the Rift Convergence"
	_register(h)

# ---------------------------------------------------------------------------
# Seris, the Fleshbinder
# ---------------------------------------------------------------------------

func _register_seris() -> void:
	var h := HeroData.new()
	h.id = "seris"
	h.hero_name = "Seris"
	h.title = "the Fleshbinder"
	h.faction = "Abyss Order"
	h.portrait_path = "res://assets/art/hero_selection/hero_portrait/seris_portrait.png"
	h.select_portrait_extra_height = 50.0
	h.combat_portrait_path = "res://assets/art/heroes/combat_portraits/seris_portrait_bf.png"
	h.frame_path = "res://assets/art/hero_selection/abyss_order_hero_frame.png"

	h.passives = [
		_make_passive(
			"fleshbind",
			"- Whenever a friendly Demon dies, gain 1 Flesh.",
			"res://assets/art/passives/seris/icon_fleshbind.png"
		),
		_make_passive(
			"grafted_affinity",
			"- You may include up to 4 copies of Grafted Fiend in your deck.",
			"res://assets/art/passives/seris/icon_grafted_affinity.png"
		),
	]

	h.talent_branch_ids = ["fleshcraft", "demon_forge", "corruption_engine"]

	h.hero_reward_pool = []

	h.flavor = "\"Flesh remembers what the soul forgets.\"\n- Seris, the Fleshbinder"
	_register(h)
