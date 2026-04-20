## BalanceSimBatch.gd
## Automated batch balance sim that reads decks from PresetDecks and GameManager.
## No hardcoded card lists — everything loaded from game data.
##
## Run via:
##   Godot_console.exe --headless --path /path/to/project res://debug/BalanceSimBatch.tscn -- [args]
##
## Arguments (all optional):
##   --act 1           Run only Act 1 fights (default: both 1 and 2)
##   --act 2           Run only Act 2 fights
##   --fight 6         Run only a specific fight number (overrides --act)
##   --runs 200        Simulations per combination (default: 200)
##   --preset swarm    Run only one preset (default: all)
##   --variant 0       Run only a specific variant index (default: all)
##   --hero seris      Run only presets for a specific hero (default: all)
extends Node

# ---------------------------------------------------------------------------
# Configuration — maps preset IDs to profiles, talents, hero passives
# ---------------------------------------------------------------------------

const _PRESET_CONFIG: Dictionary = {
	"swarm": {
		"hero": "lord_vael",
		"profile": "swarm",
		"hero_passives": ["void_imp_boost", "void_imp_extra_copy"],
		"talents_by_act": {
			1: ["imp_evolution"],
			2: ["imp_evolution", "swarm_discipline"],
			3: ["imp_evolution", "swarm_discipline", "imp_warband"],
			4: ["imp_evolution", "swarm_discipline", "imp_warband", "void_echo"],
		},
	},
	"voidbolt_burst": {
		"hero": "lord_vael",
		"profile": "spell_burn",
		"hero_passives": ["void_imp_boost", "void_imp_extra_copy"],
		"talents_by_act": {
			1: ["piercing_void"],
			2: ["piercing_void", "deepened_curse"],
			3: ["piercing_void", "deepened_curse", "death_bolt"],
			4: ["piercing_void", "deepened_curse", "death_bolt", "void_manifestation"],
		},
	},
	"death_circle": {
		"hero": "lord_vael",
		"profile": "rune_tempo",
		"hero_passives": ["void_imp_boost", "void_imp_extra_copy"],
		"talents_by_act": {
			1: ["rune_caller"],
			2: ["rune_caller", "runic_attunement"],
			3: ["rune_caller", "runic_attunement", "ritual_surge"],
			4: ["rune_caller", "runic_attunement", "ritual_surge", "abyss_convergence"],
		},
	},
	# ── Seris, the Fleshbinder ───────────────────────────────────────────────
	"seris_fleshcraft": {
		"hero": "seris",
		"profile": "seris",
		"hero_passives": ["fleshbind", "grafted_affinity"],
		"talents_by_act": {
			1: ["flesh_infusion"],
			2: ["flesh_infusion", "grafted_constitution"],
			3: ["flesh_infusion", "grafted_constitution", "predatory_surge"],
			4: ["flesh_infusion", "grafted_constitution", "predatory_surge", "deathless_flesh"],
		},
	},
	"seris_demon_forge": {
		"hero": "seris",
		"profile": "seris",
		"hero_passives": ["fleshbind", "grafted_affinity"],
		"talents_by_act": {
			1: ["soul_forge"],
			2: ["soul_forge", "fiend_offering"],
			3: ["soul_forge", "fiend_offering", "forge_momentum"],
			4: ["soul_forge", "fiend_offering", "forge_momentum", "abyssal_forge"],
		},
	},
	"seris_corruption_engine": {
		"hero": "seris",
		"profile": "seris",
		"hero_passives": ["fleshbind", "grafted_affinity"],
		"talents_by_act": {
			1: ["corrupt_flesh"],
			2: ["corrupt_flesh", "corrupt_detonation"],
			3: ["corrupt_flesh", "corrupt_detonation", "void_amplification"],
			4: ["corrupt_flesh", "corrupt_detonation", "void_amplification", "void_resonance_seris"],
		},
	},
}

const _ACT_FIGHTS: Dictionary = {
	1: [1, 2, 3],
	2: [4, 5, 6],
	3: [7, 8, 9],
	4: [10, 11, 12],
}

const _ACT_RELICS: Dictionary = {
	1: [],  # no relics in Act 1
	2: [["scouts_lantern"], ["imp_talisman"], ["mana_shard"], ["bone_shield"]],
	# Act 3: 1 Act-1 relic + 1 Act-2 relic (2 combos per preset for variance)
	3: [
		["scouts_lantern", "soul_anchor"],
		["imp_talisman",   "soul_anchor"],
		["mana_shard",     "blood_chalice"],
		["mana_shard",     "dark_mirror"],
		["bone_shield",    "void_lens"],
		["scouts_lantern", "dark_mirror"],
	],
	# Act 4: same combos as Act 3, 1 random relic gets +1 bonus charge (applied per-run)
	4: [
		["scouts_lantern", "soul_anchor"],
		["imp_talisman",   "soul_anchor"],
		["mana_shard",     "blood_chalice"],
		["mana_shard",     "dark_mirror"],
		["bone_shield",    "void_lens"],
		["scouts_lantern", "dark_mirror"],
	],
}

# Act 4: +1 bonus charge to ONE of the 2 relics (random per run).
# Implemented by splitting each sim run: half with bonus on relic[0], half with bonus on relic[1].

# Short display names for presets
const _PRESET_NAMES: Dictionary = {
	"swarm": "Swarm",
	"voidbolt_burst": "Voidbolt",
	"death_circle": "DeathCircle",
	"seris_fleshcraft": "S.Flesh",
	"seris_demon_forge": "S.Forge",
	"seris_corruption_engine": "S.Corr",
}

# Short display names for relics
const _RELIC_NAMES: Dictionary = {
	"scouts_lantern": "SL",
	"imp_talisman":   "IT",
	"mana_shard":     "MS",
	"bone_shield":    "BS",
	"void_lens":      "VL",
	"soul_anchor":    "SA",
	"dark_mirror":    "DM",
	"blood_chalice":  "BC",
	"void_hourglass": "VH",
	"oblivion_seal":  "OS",
	"nether_crown":   "NC",
	"phantom_deck":   "PD",
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

func _ready() -> void:
	await _run()
	get_tree().quit()

func _run() -> void:
	var args := _parse_args()
	var runs: int = args.runs
	var acts: Array = args.acts
	var preset_filter: String = args.preset
	var fight_filter: int = args.fight
	var variant_filter: int = args.variant  # -1 = all
	var hero_filter: String = args.hero  # "" = all heroes

	print("")
	print("=== Echo of Abyss — Batch Balance Simulator ===")
	print("Runs per combination: %d" % runs)
	if fight_filter > 0:
		print("Fight filter: F%d" % fight_filter)
	else:
		print("Acts: %s" % str(acts))
	if not preset_filter.is_empty():
		print("Preset filter: %s" % preset_filter)
	if not hero_filter.is_empty():
		print("Hero filter: %s" % hero_filter)
	print("")

	var sim := CombatSim.new()

	# When --fight N is given, find which act it belongs to and run only that fight
	if fight_filter > 0:
		var fight_act := 0
		for act_key in _ACT_FIGHTS:
			if fight_filter in _ACT_FIGHTS[act_key]:
				fight_act = act_key as int
				break
		if fight_act == 0:
			print("ERROR: Fight %d not found in any act." % fight_filter)
			return
		acts = [fight_act]

	for act in acts:
		var act_int: int = act as int
		var fights: Array = _ACT_FIGHTS.get(act_int, [])
		var relics: Array = _ACT_RELICS.get(act_int, [])

		# Filter to specific fight if requested
		if fight_filter > 0:
			fights = fights.filter(func(f): return f == fight_filter)

		print("--- Act %d ---" % act_int)

		for preset_data in PresetDecks.DECKS:
			var preset_id: String = preset_data.id
			if not preset_filter.is_empty() and preset_id != preset_filter:
				continue

			var config: Dictionary = _PRESET_CONFIG.get(preset_id, {})
			if config.is_empty():
				continue

			var preset_hero: String = config.get("hero", "lord_vael")
			if not hero_filter.is_empty() and preset_hero != hero_filter:
				continue

			var deck: Array[String] = PresetDecks.get_cards(preset_id)
			var profile_id: String = config.profile
			var hero_passives: Array[String] = []
			hero_passives.assign(config.hero_passives)
			var talents_map: Dictionary = config.get("talents_by_act", {})
			var talents: Array[String] = []
			if talents_map.has(act_int):
				talents.assign(talents_map[act_int])
			# Capstone talent rewards: add cards to deck
			if "abyss_convergence" in talents:
				deck.append("echo_rune")
				deck.append("echo_rune")

			var preset_name: String = _PRESET_NAMES.get(preset_id, preset_id)

			# Determine relic combinations to run
			# Each entry in relics is an Array[String] of relic ids (1 or 2 relics).
			# Empty relics array → one combo with no relics.
			var relic_combos: Array = []
			if relics.is_empty():
				relic_combos.append([])
			else:
				for r in relics:
					relic_combos.append(r as Array)

			for fight_idx in fights:
				var enc: EnemyData = GameManager._build_encounter(fight_idx as int)
				if enc == null:
					continue

				var enemy_hp: int = enc.hp
				var default_profile: String = enc.ai_profile

				# Get all deck IDs in the encounter's pool
				var pool := EncounterDecks.get_pool(fight_idx as int)
				if pool.is_empty():
					push_warning("No decks in pool for fight %d" % fight_idx)
					continue

				# Filter to specific variant if requested
				var variants_to_run: Array[int] = []
				if variant_filter >= 0:
					if variant_filter < pool.size():
						variants_to_run.append(variant_filter)
					else:
						push_warning("Variant %d out of range for fight %d (pool size %d)" % [variant_filter, fight_idx, pool.size()])
						continue
				else:
					for vi in pool.size():
						variants_to_run.append(vi)

				for vi in variants_to_run:
					var deck_id: String = pool[vi]
					var enemy_deck := EncounterDecks.get_deck(deck_id)
					var enemy_limited := EncounterDecks.get_deck_limited(deck_id)
					# Per-deck AI profile override
					var deck_profile := EncounterDecks.get_deck_profile(deck_id)
					var enemy_profile: String = deck_profile if not deck_profile.is_empty() else default_profile

					for relic in relic_combos:
						var relic_ids: Array[String] = []
						relic_ids.assign(relic as Array)

						var parts: Array[String] = []
						for rid in relic_ids:
							parts.append(_RELIC_NAMES.get(rid as String, rid as String))
						var relic_display: String = "+".join(parts) if not parts.is_empty() else "none"

						var s: Dictionary
						if act_int >= 4 and relic_ids.size() >= 2:
							# Act 4: +1 bonus to exactly ONE relic per run, randomly split.
							# Simulate by running half the runs with bonus on relic[0] and half on relic[1].
							var half_a: int = runs / 2
							var half_b: int = runs - half_a
							var bonus_a: Dictionary = {relic_ids[0]: 1}
							var bonus_b: Dictionary = {relic_ids[1]: 1}
							var s_a: Dictionary = await sim.run_many(
								half_a, deck, enemy_profile, enemy_deck,
								3000, enemy_hp, talents, profile_id,
								hero_passives, relic_ids, bonus_a,
								enemy_limited, preset_hero)
							var s_b: Dictionary = await sim.run_many(
								half_b, deck, enemy_profile, enemy_deck,
								3000, enemy_hp, talents, profile_id,
								hero_passives, relic_ids, bonus_b,
								enemy_limited, preset_hero)
							s = _merge_stats(s_a, s_b, half_a, half_b)
						else:
							var bonus_charges: Dictionary = {}
							s = await sim.run_many(
								runs, deck, enemy_profile, enemy_deck,
								3000, enemy_hp, talents, profile_id,
								hero_passives, relic_ids, bonus_charges,
								enemy_limited, preset_hero)

						_print_row(preset_name, relic_display, enc.enemy_name, fight_idx as int, s, deck_id)

	print("")
	print("Done.")

# ---------------------------------------------------------------------------
# Stat merging — combine two run_many results proportionally by their counts.
# ---------------------------------------------------------------------------

func _merge_stats(s_a: Dictionary, s_b: Dictionary, n_a: int, n_b: int) -> Dictionary:
	var total: int = n_a + n_b
	if total == 0:
		return s_a
	var merged: Dictionary = {}
	for key in s_a.keys():
		var val_a = s_a[key]
		var val_b: Variant = s_b.get(key, val_a)
		if val_a is int and val_b is int:
			merged[key] = (val_a as int) + (val_b as int)
		elif val_a is float and val_b is float:
			# Weighted average for average-style keys
			merged[key] = ((val_a as float) * n_a + (val_b as float) * n_b) / float(total)
		elif val_a is Dictionary and val_b is Dictionary:
			# Sum per-key (death tracking dicts)
			var sub: Dictionary = {}
			for k in (val_a as Dictionary).keys():
				sub[k] = int(val_a[k]) + int((val_b as Dictionary).get(k, 0))
			merged[key] = sub
		else:
			merged[key] = val_a
	merged["count"] = total
	return merged

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

func _print_row(preset: String, relic: String, fight_name: String, fight_idx: int, s: Dictionary, deck_id: String = "") -> void:
	var win_pct: float = s.win_rate * 100.0
	var loss_pct: float = float(s.losses) / s.count * 100.0
	var avg_hp: float = s.avg_player_hp
	var avg_turns: float = s.avg_turns
	var champ: float = s.get("avg_champion_summons", 0.0)

	var deck_label := " [%s]" % deck_id if not deck_id.is_empty() else ""
	var line := "%-10s | %-4s | F%d %-22s | Win %5.1f%% | Loss %5.1f%% | T %4.1f | HP %+5.0f | Champ %.2f%s" % [
		preset, relic, fight_idx, fight_name, win_pct, loss_pct, avg_turns, avg_hp, champ, deck_label]
	print(line)

	# Extra stats line if any non-zero
	var det: float = s.get("avg_corruption_det", 0.0)
	var rit: float = s.get("avg_ritual_invoke", 0.0)
	var p_rit: float = s.get("avg_player_ritual", 0.0)
	var sb: float = s.get("avg_spark_buff", 0.0)
	var aura: float = s.get("avg_ch_aura_dmg", 0.0)
	var clog: float = s.get("avg_clogged_slots", 0.0)
	var sv: float = s.get("avg_smoke_veil_fires", 0.0)
	var sv_d: float = s.get("avg_smoke_veil_dmg", 0.0)
	var pl: float = s.get("avg_plague_fires", 0.0)
	var pl_k: float = s.get("avg_plague_kills", 0.0)
	var vb_c: float = s.get("avg_void_bolt_casts", 0.0)
	var vb_d: float = s.get("avg_void_bolt_dmg", 0.0)
	var vi_d: float = s.get("avg_void_imp_dmg", 0.0)
	var spk_d: float = s.get("avg_spark_atk_dmg", 0.0)
	var hsb: float = s.get("avg_sentinel_buffs", 0.0)
	var imm: float = s.get("avg_immune_prevented", 0.0)
	var rc_c: float = s.get("avg_collapse_casts", 0.0)
	var rc_k: float = s.get("avg_collapse_kills", 0.0)
	var rl_p: float = s.get("avg_rift_lord_plays", 0.0)
	var rl_g: int = s.get("rift_lord_games", 0)
	var rl_wr: float = s.get("rift_lord_win_rate", 0.0)

	var extras: Array[String] = []
	if det > 0: extras.append("Det:%.1f" % det)
	if rit > 0: extras.append("Rit:%.1f" % rit)
	if p_rit > 0: extras.append("PRit:%.1f" % p_rit)
	if sb > 0: extras.append("SpkB:%.1f" % sb)
	if aura > 0: extras.append("Aura:%.0f" % aura)
	if clog > 0.1: extras.append("Clog:%.1f" % clog)
	if sv > 0: extras.append("SV:%.1f/%.0f" % [sv, sv_d])
	if pl > 0: extras.append("Plg:%.1f/%.1f" % [pl, pl_k])
	if vb_c > 0: extras.append("VB:%.1fx/%.0fdmg" % [vb_c, vb_d])
	if vi_d > 0: extras.append("Imp:%.0f" % vi_d)
	if spk_d > 0: extras.append("SpkDmg:%.0f" % spk_d)
	if hsb > 0: extras.append("Snt:%.1f" % hsb)
	if imm > 0: extras.append("Imm:%.0f" % imm)
	if rc_c > 0: extras.append("RC:%.1fx/%.1fk" % [rc_c, rc_k])
	var crt: float = s.get("avg_crits_consumed", 0.0)
	if crt > 0: extras.append("Crt:%.1f" % crt)
	if rl_p > 0: extras.append("RL:%.1fx(%d g,%.0f%%wr)" % [rl_p, rl_g, rl_wr * 100.0])
	var vw_beh: float = s.get("avg_vw_behemoth", 0.0)
	var vw_bas: float = s.get("avg_vw_bastion", 0.0)
	if vw_beh > 0 or vw_bas > 0:
		extras.append("VW:Beh%.2f/Bas%.2f" % [vw_beh, vw_bas])
	var vw_dc: float = s.get("avg_vw_death_crit", 0.0)
	if vw_dc > 0:
		extras.append("DCrit:%.2f" % vw_dc)
	# Behemoth/Bastion death cause breakdown
	var beh_lost: Dictionary = s.get("vw_behemoth_lost_total", {})
	var bas_lost: Dictionary = s.get("vw_bastion_lost_total", {})
	if beh_lost.size() > 0 and (int(beh_lost["consumed"]) + int(beh_lost["damage"]) + int(beh_lost["combat"]) + int(beh_lost["survived"])) > 0:
		extras.append("BehL:c%d/d%d/b%d/s%d" % [beh_lost["consumed"], beh_lost["damage"], beh_lost["combat"], beh_lost["survived"]])
	if bas_lost.size() > 0 and (int(bas_lost["consumed"]) + int(bas_lost["damage"]) + int(bas_lost["combat"]) + int(bas_lost["survived"])) > 0:
		extras.append("BasL:c%d/d%d/b%d/s%d" % [bas_lost["consumed"], bas_lost["damage"], bas_lost["combat"], bas_lost["survived"]])

	if not extras.is_empty():
		print("             %s" % " | ".join(extras))

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------

func _parse_args() -> Dictionary:
	var result := {
		"acts": [1, 2],
		"runs": 200,
		"preset": "",
		"fight": 0,
		"variant": -1,
		"hero": "",  # "" = all heroes, else filter to a specific hero id
	}

	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--act":
				if i + 1 < args.size():
					result.acts = [int(args[i + 1])]
					i += 1
			"--fight":
				if i + 1 < args.size():
					result.fight = int(args[i + 1])
					i += 1
			"--runs":
				if i + 1 < args.size():
					result.runs = int(args[i + 1])
					i += 1
			"--preset":
				if i + 1 < args.size():
					result.preset = args[i + 1]
					i += 1
			"--variant":
				if i + 1 < args.size():
					result.variant = int(args[i + 1])
					i += 1
			"--hero":
				if i + 1 < args.size():
					result.hero = args[i + 1]
					i += 1
		i += 1

	return result
