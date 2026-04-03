## HeroDatabase.gd
## Autoload — single source of truth for all hero definitions.
## Usage: HeroDatabase.get_hero("lord_vael")
##        HeroDatabase.get_all_heroes()
##        HeroDatabase.has_passive("lord_vael", "void_imp_boost")
extends Node

var _heroes: Dictionary = {}

func _ready() -> void:
	_register_lord_vael()

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

func _make_passive(id: String, desc: String) -> HeroPassive:
	var p := HeroPassive.new()
	p.id          = id
	p.description = desc
	return p

# ---------------------------------------------------------------------------
# Lord Vael
# ---------------------------------------------------------------------------

func _register_lord_vael() -> void:
	var h := HeroData.new()
	h.id            = "lord_vael"
	h.hero_name     = "Lord Vael"
	h.title         = "Void Caller"
	h.faction       = "Abyss Order"
	h.portrait_path = "res://assets/art/hero_selection/hero_portrait/lord_vael_portrait.png"
	h.frame_path    = "res://assets/art/hero_selection/abyss_order_hero_frame.png"

	h.passives = [
		_make_passive("void_imp_boost",
			"● VOID IMP CLAN minions have +100 ATK and +100 HP"),
		_make_passive("void_imp_extra_copy",
			"● You may include up to 4 copies of Void Imp in your deck."),
	]

	# Branch IDs — must match TalentData.branch values registered in TalentDatabase.
	# Display names are resolved via TalentDatabase.get_branch_display_name(id).
	h.talent_branch_ids = ["swarm", "rune_master", "void_bolt"]

	# Cards available in the reward pool once permanently unlocked (boss drops).
	# Mirrors the "vael_common" pool in CardDatabase.
	h.hero_reward_pool = [
		"imp_recruiter", "blood_pact",
		"soul_taskmaster", "soul_shatter",
		"void_amplifier", "soul_rune",
	]

	h.flavor = "\"The Abyss does not consume — it remembers.\"\n— Lord Vael, at the Rift Convergence"
	_register(h)
