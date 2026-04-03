## RelicDatabase.gd
## Autoload — holds every relic definition.
## Relics are activated abilities with charges and cooldowns.
##
## Offering rules:
##   Act 1 boss: choose 1 of 2 random relics from the Act 1 pool.
##   Act 2+ bosses: choose 1 of 2 random relics from that act's pool,
##                  OR +1 charge to a random existing relic.
extends Node

var _relics: Dictionary = {}

func _ready() -> void:
	_register_all_relics()

## Returns the RelicData for a given id, or null.
func get_relic(id: String) -> RelicData:
	return _relics.get(id, null)

## Returns 2 random relics offered at the end of the given act.
func get_offer_for_act(act: int) -> Array[RelicData]:
	var pool: Array[RelicData] = []
	for r: RelicData in _relics.values():
		if r.act == act:
			pool.append(r)
	pool.shuffle()
	var result: Array[RelicData] = []
	for i in mini(2, pool.size()):
		result.append(pool[i])
	return result

## Returns all registered relics (for debug/testing).
func get_all() -> Array[RelicData]:
	var all: Array[RelicData] = []
	for r: RelicData in _relics.values():
		all.append(r)
	return all

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _reg(r: RelicData) -> void:
	_relics[r.id] = r

func _make(id: String, rname: String, desc: String, act: int,
		charges: int, cooldown: int, effect_id: String,
		icon: String = "") -> RelicData:
	var r := RelicData.new()
	r.id          = id
	r.relic_name  = rname
	r.description = desc
	r.act         = act
	r.charges     = charges
	r.cooldown    = cooldown
	r.effect_id   = effect_id
	r.icon_path   = icon
	return r

# ---------------------------------------------------------------------------
# All relics — 4 per act
# ---------------------------------------------------------------------------

func _register_all_relics() -> void:

	# ── Act 1 (utility / resource) ─────────────────────────────────────────
	_reg(_make("scouts_lantern", "Scout's Lantern",
		"Draw 2 cards.", 1, 1, 3, "relic_draw_2",
		"res://assets/art/relics/relic_scout_lantern.png"))

	_reg(_make("imp_talisman", "Imp Talisman",
		"Add a Void Imp to your hand.", 1, 1, 3, "relic_add_void_imp",
		"res://assets/art/relics/relic_imp_talisman.png"))

	_reg(_make("mana_shard", "Mana Shard",
		"Gain +2 Mana this turn (cannot exceed max).", 1, 2, 2, "relic_refill_mana",
		"res://assets/art/relics/relic_mana_shard.png"))

	_reg(_make("bone_shield", "Bone Shield",
		"Your hero takes no damage until your next turn.", 1, 1, 5, "relic_hero_immune",
		"res://assets/art/relics/relic_bone_shield.png"))

	# ── Act 2 (tempo / removal) ───────────────────────────────────────────
	_reg(_make("void_lens", "Void Lens",
		"Cast Abyssal Plague: apply 1 Corruption to all enemies and deal 100 damage to all enemies.", 2, 1, 4, "relic_cast_plague",
		"res://assets/art/relics/void_lens.png"))

	_reg(_make("soul_anchor", "Soul Anchor",
		"Summon a 300/300 Void Spark and grant it Guard.", 2, 1, 4, "relic_summon_guardian",
		"res://assets/art/relics/soul_anchor.png"))

	_reg(_make("dark_mirror", "Dark Mirror",
		"Reduce the cost of your next card by 2 Essence and 2 Mana (minimum 0).", 2, 1, 3, "relic_cost_reduction",
		"res://assets/art/relics/dark_mirror.png"))

	_reg(_make("blood_chalice", "Blood Chalice",
		"Deal 500 damage to a target enemy.", 2, 1, 3, "relic_execute",
		"res://assets/art/relics/blood_chalice.png"))

	# ── Act 3 (powerful / game-swinging) ──────────────────────────────────
	_reg(_make("void_hourglass", "Void Hourglass",
		"Take an extra turn after this one.", 3, 1, 5, "relic_extra_turn"))

	_reg(_make("oblivion_seal", "Oblivion Seal",
		"Summon a 500/500 Void Demon with Lifedrain.", 3, 1, 5, "relic_summon_demon"))

	_reg(_make("nether_crown", "Nether Crown",
		"All friendly minions gain +200 ATK this turn.", 3, 1, 4, "relic_mass_buff"))

	_reg(_make("phantom_deck", "Phantom Deck",
		"Add a copy of your 3 highest-cost cards to your hand.", 3, 1, 4, "relic_copy_cards"))
