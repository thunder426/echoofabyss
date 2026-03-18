## RelicDatabase.gd
## Autoload — holds every relic definition.
## Access: RelicDatabase.get_offer_for_act(1)  → Array[RelicData] of 3 random relics
extends Node

var _relics: Dictionary = {}

func _ready() -> void:
	_register_all_relics()

## Returns the RelicData for a given id, or null.
func get_relic(id: String) -> RelicData:
	return _relics.get(id, null)

## Returns up to 3 random relics offered at the end of the given act (1, 2, or 3).
func get_offer_for_act(act: int) -> Array[RelicData]:
	var pool: Array[RelicData] = []
	for r: RelicData in _relics.values():
		if r.act == act:
			pool.append(r)
	pool.shuffle()
	var result: Array[RelicData] = []
	for i in mini(3, pool.size()):
		result.append(pool[i])
	return result

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _reg(r: RelicData) -> void:
	_relics[r.id] = r

func _make(id: String, name: String, desc: String, act: int) -> RelicData:
	var r := RelicData.new()
	r.id          = id
	r.relic_name  = name
	r.description = desc
	r.act         = act
	return r

# ---------------------------------------------------------------------------
# All relics — 3 per act
# ---------------------------------------------------------------------------

func _register_all_relics() -> void:

	# ── Act 1 ──────────────────────────────────────────────────────────────
	_reg(_make("blood_pact",   "Blood Pact",
		"At the start of your turn, deal 1 damage to the enemy hero.", 1))

	_reg(_make("void_crystal", "Void Crystal",
		"Your first card each turn costs 0.", 1))

	_reg(_make("soul_ember",   "Soul Ember",
		"Gain 1 extra Essence at the start of each turn.", 1))

	# ── Act 2 ──────────────────────────────────────────────────────────────
	_reg(_make("shadow_veil",  "Shadow Veil",
		"Once per combat: the first damage your hero takes is ignored.", 2))

	_reg(_make("ancient_tome", "Ancient Tome",
		"Draw 1 extra card at the start of each turn.", 2))

	_reg(_make("demon_pact",   "Demon Pact",
		"When you summon a Demon, it gains +1 ATK.", 2))

	# ── Act 3 ──────────────────────────────────────────────────────────────
	_reg(_make("abyssal_core", "Abyssal Core",
		"When you summon any minion, it gains +1 / +1.", 3))

	_reg(_make("void_surge",   "Void Surge",
		"At the start of your turn, all friendly minions gain +1 ATK.", 3))

	_reg(_make("eternal_hunger", "Eternal Hunger",
		"Whenever your hero heals, deal that much damage to the enemy hero too.", 3))
