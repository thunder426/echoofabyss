## CombatSetup.gd
## Registers all conditional handlers (talents, hero passives, enemy passives)
## and shared always-on handlers into TriggerManager.
## Used by both CombatScene._setup_triggers() and SimTriggerSetup.
##
## To add a new talent, hero passive, or enemy passive:
##   1. Add its handler method to CombatHandlers.gd
##   2. Add an entry to _REGISTRY below — triggers and/or stat overrides
##   No other files need to change.
##
## Registry entry shape:
##   "passive_id": {
##       "triggers": [ { "event": TriggerEvent, "method": "handler_name", "priority": int }, ... ],
##       "stats":    { "scene_field_name": value, ... }   -- applied via scene.set() at setup
##   }
class_name CombatSetup
extends RefCounted

const _REGISTRY: Dictionary = {
	# ── Player talents ────────────────────────────────────────────────────────
	"void_echo": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN,      "method": "on_card_drawn_void_echo",        "priority": 0  }],
		"stats":    {}
	},
	"rune_caller": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED,   "method": "on_played_rune_caller",          "priority": 0  }],
		"stats":    {}
	},
	"swarm_discipline": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "method": "on_summon_swarm_discipline",     "priority": 20 }],
		"stats":    {}
	},
	"abyssal_legion": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "method": "on_summon_abyssal_legion",       "priority": 21 }],
		"stats":    {}
	},
	"piercing_void": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "method": "on_summon_piercing_void",        "priority": 23 }],
		"stats":    {}
	},
	"imp_evolution": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "method": "on_summon_imp_evolution",        "priority": 24 }],
		"stats":    {}
	},
	"imp_warband": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "method": "on_summon_imp_warband",          "priority": 25 }],
		"stats":    {}
	},
	"death_bolt": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_DIED,     "method": "on_player_minion_died_death_bolt", "priority": 10 }],
		"stats":    {}
	},
	"deepened_curse": {
		"triggers": [],
		"stats":    { "void_mark_damage_per_stack": 50 }
	},
	"runic_attunement": {
		"triggers": [],
		"stats":    { "rune_aura_multiplier": 2 }
	},

	# ── Hero passives ─────────────────────────────────────────────────────────
	"void_imp_boost": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "method": "on_summon_passive_void_imp_boost", "priority": 0 }],
		"stats":    {}
	},

	# ── Enemy passives ────────────────────────────────────────────────────────
	"feral_instinct": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_START,      "method": "on_enemy_turn_feral_instinct_reset", "priority": 5 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_feral_instinct",     "priority": 1 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     "method": "on_enemy_died_feral_instinct",       "priority": 4 },
		],
		"stats": {}
	},
	"pack_instinct": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_board_changed_pack_instinct", "priority": 9 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     "method": "on_board_changed_pack_instinct", "priority": 3 },
		],
		"stats": {}
	},
	"corrupted_death": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED, "method": "on_enemy_died_corrupted_death", "priority": 6 }],
		"stats":    {}
	},
	# ── Enemy champion passives (Act 1) ──────────────────────────────────────
	"champion_rogue_imp_pack": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_ATTACK,          "method": "on_enemy_attack_champion_rip",       "priority": 50 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_champion_rip_aura",   "priority": 80 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     "method": "on_enemy_died_champion_rip",          "priority": 80 },
		],
		"stats": { "_champion_rip_summoned": false }
	},
	"champion_corrupted_broodlings": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED, "method": "on_enemy_died_champion_cb", "priority": 81 },
		],
		"stats": { "_champion_cb_death_count": 0, "_champion_cb_summoned": false }
	},
	"champion_imp_matriarch": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_SPELL_CAST,  "method": "on_enemy_spell_champion_im",        "priority": 50 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED, "method": "on_enemy_died_champion_im",          "priority": 82 },
		],
		"stats": { "_champion_im_frenzy_count": 0, "_champion_im_summoned": false }
	},
	# ── Act 2 enemy passives ──────────────────────────────────────────────────
	"feral_reinforcement": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_feral_reinforcement", "priority": 3 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_START, "method": "on_enemy_turn_reset_feral_reinforcement", "priority": 0 },
		],
		"stats":    { "_imp_caller_fired": false }
	},
	"corrupt_authority": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_corrupt_authority_human", "priority": 2 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_corrupt_authority_imp",   "priority": 4 },
		],
		"stats": {}
	},
	"ritual_sacrifice": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_ritual_sacrifice", "priority": 2 }],
		"stats":    {}
	},
	"void_unraveling": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     "method": "on_enemy_died_void_unraveling",   "priority": 2 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_void_unraveling", "priority": 2 },
		],
		"stats": {}
	},
	# ancient_frenzy: cost discount applied here; hand injection is live-only (handled in CombatScene._setup_triggers)
	"ancient_frenzy": {
		"triggers": [],
		"stats":    {}
	},
	# ── Act 3 enemy passives ──────────────────────────────────────────────────
	"void_rift": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_START, "method": "on_enemy_turn_void_rift", "priority": 3 }],
		"stats":    {}
	},
	"void_empowerment": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_void_empowerment", "priority": 1 }],
		"stats":    {}
	},
	# void_detonation_passive: no triggers — invoked directly by AI profile's _consume_sparks()
	"void_detonation_passive": {
		"triggers": [],
		"stats":    {}
	},
	# void_mastery: no triggers — AI profile checks for this passive to halve spark costs
	"void_mastery": {
		"triggers": [],
		"stats":    {}
	},
	# ── Act 4 enemy passives ──────────────────────────────────────────────────
	"void_might": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_START, "method": "on_enemy_turn_void_might", "priority": 5 }],
		"stats":    {}
	},
	"abyss_awakened": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_START, "method": "on_enemy_turn_abyss_awakened", "priority": 5 }],
		"stats":    {}
	},
	"void_precision": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_ATTACK, "method": "on_enemy_attack_void_precision_pre",  "priority": 0 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_ATTACK, "method": "on_enemy_attack_void_precision_post", "priority": 99 },
		],
		"stats":    { "_vp_pre_crit_stacks": 0 }
	},
	"spirit_conscription": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_START,      "method": "on_enemy_turn_reset_spirit_conscription", "priority": 0 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_spirit_conscription",     "priority": 6 },
		],
		"stats":    { "_spirit_conscription_fired": false }
	},
	"captain_orders": {
		"triggers": [],
		"stats":    { "crit_multiplier": 2.5 }
	},
	"dark_channeling": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "method": "on_enemy_spell_dark_channeling", "priority": 0 }],
		"stats":    { "_dark_channeling_active": false, "_dark_channeling_multiplier": 1.0 }
	},
	"champion_duel": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_START, "method": "on_enemy_turn_champion_duel_refresh",  "priority": 10 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_ATTACK,     "method": "on_enemy_attack_champion_duel_refresh", "priority": 98 },
		],
		"stats":    {}
	},
}

func setup(
		tm: TriggerManager,
		h: CombatHandlers,
		scene: Object,
		talents: Array[String],
		hero_passives: Array[String],
		enemy_passives: Array[String]) -> void:

	# ── Shared always-on handlers (both live and sim) ─────────────────────────
	tm.register(Enums.TriggerEvent.ON_PLAYER_TURN_START,     h.on_player_turn_environment,           10)
	tm.register(Enums.TriggerEvent.ON_PLAYER_TURN_START,     h.on_minion_turn_start_passives,        21)
	tm.register(Enums.TriggerEvent.ON_ENEMY_TURN_START,      h.on_enemy_turn_environment,            10)
	tm.register(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST,     h.on_void_archmagus_spell,               0)
	tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED,  h.on_player_minion_played_effect,       10)
	tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, h.on_summon_board_synergies,           30)
	tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, h.on_enemy_minion_played_effect,         5)
	tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, h.on_enemy_summon_rogue_imp_elder,       7)
	tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED,    h.on_player_minion_died_board_passives,  0)
	tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED,    h.on_minion_died_death_effect,           5)
	tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     h.on_minion_died_death_effect,           5)
	tm.register(Enums.TriggerEvent.ON_RUNE_PLACED,           h.on_player_minion_died_rune_warden,     5)

	# ── Conditional: registry-driven registration and stat overrides ──────────
	for id in talents:       _apply(id, tm, h, scene)
	for id in hero_passives: _apply(id, tm, h, scene)
	for id in enemy_passives:
		_apply(id, tm, h, scene)
		# ancient_frenzy: grant pack_frenzy cost discount (shared side effect)
		if id == "ancient_frenzy":
			var ai = scene.get("enemy_ai")
			if ai != null:
				(ai.spell_cost_discounts as Dictionary)["pack_frenzy"] = 1
		# corrupted_death: void_touched_imp costs 1 less essence
		if id == "corrupted_death":
			var ai = scene.get("enemy_ai")
			if ai != null:
				(ai.essence_cost_discounts as Dictionary)["void_touched_imp"] = 1

	# ── Grand rituals from talents (data-driven via TalentDatabase) ───────────
	for talent_id in talents:
		var talent: TalentData = TalentDatabase.get_talent(talent_id)
		if talent != null and talent.grand_ritual != null:
			var gr: RitualData = talent.grand_ritual
			tm.register(Enums.TriggerEvent.ON_RUNE_PLACED,
				func(_ctx: EventContext): h.on_grand_ritual(gr), 0)
			tm.register(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED,
				func(_ctx: EventContext): h.on_grand_ritual(gr), 0)

func _apply(id: String, tm: TriggerManager, h: CombatHandlers, scene: Object) -> void:
	if not _REGISTRY.has(id):
		return
	var entry: Dictionary = _REGISTRY[id]
	for t in entry["triggers"]:
		tm.register(t["event"], Callable(h, t["method"]), t["priority"])
	for stat in entry["stats"]:
		scene.set(stat, entry["stats"][stat])
