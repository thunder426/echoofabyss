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
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN,  "method": "on_card_drawn_void_echo",       "priority": 0 },
			{ "event": Enums.TriggerEvent.ON_PLAYER_TURN_START,  "method": "on_player_turn_start_void_echo", "priority": 99 },
		],
		"stats":    { "_void_echo_fired_this_turn": false }
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
		"stats":    { "void_mark_damage_per_stack": 40 }
	},
	"runic_attunement": {
		"triggers": [],
		"stats":    { "rune_aura_multiplier": 2 }
	},
	"ritual_surge": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_RITUAL_FIRED, "method": "on_ritual_fired_ritual_surge", "priority": 0 }],
		"stats":    {}
	},
	# ── Seris — Fleshcraft branch ────────────────────────────────────────────
	"flesh_infusion": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, "method": "on_played_flesh_infusion", "priority": 30 },
			# Grafted Constitution (formerly T1) was merged into Flesh Infusion; the +100/+100-on-kill
			# trigger is now part of T0. Predatory Surge's "3 kill stacks → Siphon" still reads
			# kill_stacks maintained by this handler.
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED, "method": "on_enemy_died_grafted_constitution", "priority": 30 },
		],
		"stats":    {}
	},
	"grafting_ritual": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, "method": "on_played_grafting_ritual", "priority": 20 }],
		"stats":    {}
	},
	"predatory_surge": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "method": "on_summon_predatory_surge", "priority": 30 }],
		"stats":    {}
	},
	# deathless_flesh — no trigger; handled by CombatScene._try_save_from_death hook.
	"deathless_flesh": {
		"triggers": [],
		"stats":    {}
	},
	# ── Seris — Demon Forge branch ───────────────────────────────────────────
	# soul_forge has no trigger — activation via SerisResourceBar button, sacrifice tick via _on_demon_sacrificed.
	"soul_forge": {
		"triggers": [],
		"stats":    {}
	},
	# fiend_offering — extension of _on_demon_sacrificed; no extra trigger needed.
	"fiend_offering": {
		"triggers": [],
		"stats":    {}
	},
	# forge_momentum — lowers the Forge Counter threshold from 3 to 2 via stat override.
	"forge_momentum": {
		"triggers": [],
		"stats":    { "forge_counter_threshold": 2 }
	},
	# abyssal_forge — grants auras at Forged Demon summon (inside _summon_forged_demon);
	# aura effects themselves fire on turn end / flesh spent (see on_turn_end_forge_auras / _on_flesh_spent).
	"abyssal_forge": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_TURN_END, "method": "on_turn_end_forge_auras", "priority": 30 }],
		"stats":    {}
	},
	# ── Seris — Corruption Engine branch ─────────────────────────────────────
	# corrupt_flesh — the ATK inversion is a MinionInstance global flag; the activated
	# ability (button → scene._seris_corrupt_activate) has no trigger. Turn-start reset
	# of the 1/turn flag registers here.
	"corrupt_flesh": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_TURN_START, "method": "on_turn_start_corrupt_flesh_reset", "priority": 5 }],
		"stats":    {}
	},
	"corrupt_detonation": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_CORRUPTION_REMOVED, "method": "on_corruption_removed_detonation", "priority": 30 }],
		"stats":    {}
	},
	# void_amplification — scene reads the talent inside _pre_player_spell_cast; no trigger needed.
	"void_amplification": {
		"triggers": [],
		"stats":    {}
	},
	# void_resonance_seris — capstone. Half 1: +1 Flesh on any enemy minion death (handler).
	# Half 2: double-cast spell when Flesh>=5 (handled by scene._post_player_spell_cast).
	"void_resonance_seris": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED, "method": "on_enemy_died_void_resonance", "priority": 40 }],
		"stats":    {}
	},

	# ── Hero passives ─────────────────────────────────────────────────────────
	"void_imp_boost": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "method": "on_summon_passive_void_imp_boost", "priority": 0 }],
		"stats":    {}
	},
	# Seris, the Fleshbinder — friendly Demon deaths grant 1 Flesh (capped).
	"fleshbind": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_DIED, "method": "on_minion_died_fleshbind", "priority": 0 }],
		"stats":    {}
	},
	# grafted_affinity — deck-builder concern only (copy cap); no combat-time triggers.
	"grafted_affinity": {
		"triggers": [],
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
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,  "method": "on_enemy_died_corrupted_death",    "priority": 6 },
		],
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
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_void_unraveling_human", "priority": 1 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_void_unraveling_imp",   "priority": 2 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_END,        "method": "on_enemy_turn_end_void_unraveling",     "priority": 5 },
		],
		"stats": {}
	},
	# ancient_frenzy: cost discount applied here; hand injection is live-only (handled in CombatScene._setup_triggers)
	"ancient_frenzy": {
		"triggers": [],
		"stats":    {}
	},
	# ── Enemy champion passives (Act 2) ──────────────────────────────────────
	"champion_abyss_cultist_patrol": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_champion_acp_corrupt", "priority": 81 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     "method": "on_enemy_died_champion_acp",           "priority": 83 },
		],
		"stats": { "_champion_acp_stacks_consumed": 0, "_champion_acp_summoned": false }
	},
	"champion_void_ritualist": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_champion_vr", "priority": 82 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     "method": "on_enemy_died_champion_vr",  "priority": 84 },
		],
		"stats": { "_champion_vr_summoned": false }
	},
	"champion_corrupted_handler": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_champion_ch_spark_buff", "priority": 83 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     "method": "on_enemy_died_champion_ch",              "priority": 85 },
		],
		"stats": { "_champion_ch_spark_count": 0, "_champion_ch_summoned": false }
	},
	# ── Act 3 enemy champion passives ────────────────────────────────────────
	"champion_rift_stalker": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_ATTACK,           "method": "on_enemy_attack_champion_rs",        "priority": 86 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED,  "method": "on_enemy_summon_champion_rs_immune", "priority": 87 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,      "method": "on_enemy_died_champion_rs",          "priority": 88 },
		],
		"stats": { "_champion_rs_spark_dmg": 0, "_champion_rs_summoned": false }
	},
	"champion_void_aberration": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_SPARK_CONSUMED,  "method": "on_spark_consumed_champion_va", "priority": 89 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     "method": "on_enemy_died_champion_va",     "priority": 90 },
		],
		"stats": { "_champion_va_sparks_consumed": 0, "_champion_va_summoned": false }
	},
	"champion_void_herald": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_SPELL_CAST,       "method": "on_enemy_spark_card_champion_vh", "priority": 91 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED,  "method": "on_enemy_spark_card_champion_vh", "priority": 91 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,      "method": "on_enemy_died_champion_vh",       "priority": 92 },
		],
		"stats": { "_champion_vh_spark_cards_played": 0, "_champion_vh_summoned": false }
	},
	# ── Act 4 enemy champion passives ────────────────────────────────────────
	"champion_void_scout": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_END,     "method": "on_enemy_turn_end_champion_vs",    "priority": 50 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,  "method": "on_enemy_died_champion_vs",        "priority": 93 },
		],
		"stats": { "_champion_vs_crits_consumed": 0, "_champion_vs_summoned": false }
	},
	"champion_void_warband": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_SPARK_CONSUMED, "method": "on_spark_consumed_champion_vw", "priority": 95 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,    "method": "on_enemy_died_champion_vw",     "priority": 94 },
		],
		"stats": { "_champion_vw_spirits_consumed": 0, "_champion_vw_summoned": false }
	},
	"champion_void_captain": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_SPELL_CAST,  "method": "on_enemy_spell_champion_vc", "priority": 91 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED, "method": "on_enemy_died_champion_vc",  "priority": 95 },
		],
		"stats": { "_champion_vc_tc_cast": 0, "_champion_vc_summoned": false }
	},
	"champion_void_champion": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_PLAYER_MINION_DIED, "method": "on_player_died_champion_vch", "priority": 91 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED,  "method": "on_enemy_died_champion_vch",  "priority": 95 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_END,     "method": "on_enemy_turn_end_champion_vch_aura", "priority": 10 },
		],
		"stats": { "_champion_vch_crit_kills": 0, "_champion_vch_summoned": false }
	},
	"champion_void_ritualist_prime": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_SPELL_CAST,  "method": "on_enemy_spell_champion_vrp", "priority": 92 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_DIED, "method": "on_enemy_died_champion_vrp",  "priority": 96 },
		],
		"stats": { "_champion_vrp_spells_cast": 0, "_champion_vrp_summoned": false }
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
	"void_detonation_passive": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_ENEMY_SPARK_CONSUMED, "method": "on_spark_consumed_void_detonation", "priority": 5 }],
		"stats":    {}
	},
	# void_mastery: no triggers — AI profile checks for this passive to halve spark costs
	"void_mastery": {
		"triggers": [],
		"stats":    {}
	},
	"ritualist_spark_free": {
		# F13 Void Ritualist Prime: all enemy spell spark costs become 0.
		# Checked in CombatProfile._effective_spark_cost via _active_enemy_passives.
		"triggers": [],
		"stats":    {}
	},
	"mana_for_spark": {
		# F14 Void Champion: if enemy lacks sparks, each missing spark costs 1 extra Mana.
		# Checked in CombatProfile._can_afford_spark_card / payment logic.
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
		"triggers": [],  # Handled directly by CombatManager._post_crit()
		"stats":    {}
	},
	"spirit_resonance": {
		# Shared enemy passive — 2 effects in one:
		#   1. Spirits with crit have +1 effective spark_value (checked in MinionInstance.effective_spark_value)
		#   2. Consuming a crit-Spirit as fuel spawns a 100/100 Void Spark
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_SPARK_CONSUMED, "method": "on_spark_consumed_spirit_resonance", "priority": 90 },
		],
		"stats":    {}
	},
	"spirit_conscription": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_START,      "method": "on_enemy_turn_reset_spirit_conscription", "priority": 0 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "method": "on_enemy_summon_spirit_conscription",     "priority": 6 },
		],
		"stats":    { "_spirit_conscription_fired": false }
	},
	"captain_orders": {
		"triggers": [{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_END, "method": "on_enemy_turn_end_captain_orders", "priority": 40 }],
		"stats":    {}
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
	# F15 Phase 1 — Abyssal Mandate: the player's resource growth choice is
	# echoed back as an enemy-turn discount. Grow Essence → enemy minions cost
	# -2 Essence next turn; grow Mana → enemy spells cost -2 Mana next turn.
	"abyssal_mandate": {
		"triggers": [
			{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_START, "method": "on_enemy_turn_start_abyssal_mandate", "priority": 8 },
			{ "event": Enums.TriggerEvent.ON_ENEMY_TURN_END,   "method": "on_enemy_turn_end_abyssal_mandate",   "priority": 8 },
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
	# Rogue Imp Elder aura — symmetric, fires on every summon/death on either side
	tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, h.on_minion_event_rogue_imp_elder_aura,  7)
	tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED,  h.on_minion_event_rogue_imp_elder_aura,  7)
	tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED,     h.on_minion_event_rogue_imp_elder_aura,  7)
	tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_DIED,      h.on_minion_event_rogue_imp_elder_aura,  7)
	tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED,    h.on_player_minion_died_board_passives,  0)
	tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED,    h.on_minion_died_death_effect,           5)
	tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     h.on_minion_died_death_effect,           5)
	tm.register(Enums.TriggerEvent.ON_RUNE_PLACED,           h.on_player_minion_died_rune_warden,     5)
	tm.register(Enums.TriggerEvent.ON_PLAYER_TURN_END,      h.on_turn_end_hollow_sentinel,          20)
	tm.register(Enums.TriggerEvent.ON_ENEMY_TURN_END,       h.on_turn_end_hollow_sentinel,          20)
	# Pack Frenzy is "+250 ATK and SWIFT this turn" — revert on turn end
	# (not next turn start) so the buff doesn't bleed into the opponent's turn.
	tm.register(Enums.TriggerEvent.ON_PLAYER_TURN_END,      h.on_turn_end_pack_frenzy_revert,       10)
	tm.register(Enums.TriggerEvent.ON_ENEMY_TURN_END,       h.on_turn_end_pack_frenzy_revert,       10)

	# ── Global flags from talents ────────────────────────────────────────────
	# Reset per-combat globals, then set from active talents. Resetting here is important
	# for sim batches where CombatSetup is reused across many state instances.
	MinionInstance.corruption_inverts_on_friendly_demons = "corrupt_flesh" in talents

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

## Public entrypoint for dynamic passive (un)registration — used by the F15
## phase transition to swap passives mid-combat without tearing down the whole
## trigger system.
static func apply_passive(id: String, tm: TriggerManager, h: CombatHandlers, scene: Object) -> void:
	if not _REGISTRY.has(id):
		return
	var entry: Dictionary = _REGISTRY[id]
	for t in entry["triggers"]:
		tm.register(t["event"], Callable(h, t["method"]), t["priority"])
	for stat in entry["stats"]:
		scene.set(stat, entry["stats"][stat])

static func unapply_passive(id: String, tm: TriggerManager, h: CombatHandlers) -> void:
	if not _REGISTRY.has(id):
		return
	var entry: Dictionary = _REGISTRY[id]
	for t in entry["triggers"]:
		tm.unregister(t["event"], Callable(h, t["method"]))
