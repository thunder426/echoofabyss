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
extends Node

# ---------------------------------------------------------------------------
# Configuration — maps preset IDs to profiles, talents, hero passives
# ---------------------------------------------------------------------------

const _PRESET_CONFIG: Dictionary = {
	"swarm": {
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
		"profile": "rune_tempo",
		"hero_passives": ["void_imp_boost", "void_imp_extra_copy"],
		"talents_by_act": {
			1: ["rune_caller"],
			2: ["rune_caller", "runic_attunement"],
			3: ["rune_caller", "runic_attunement", "ritual_surge"],
			4: ["rune_caller", "runic_attunement", "ritual_surge", "abyss_convergence"],
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
	# Act 3: 1 representative Act 1 relic + 1 representative Act 2 relic
	# Swarm:       scouts_lantern + soul_anchor
	# Voidbolt:    mana_shard    + blood_chalice
	# DeathCircle: bone_shield   + void_lens
	3: [
		["scouts_lantern", "soul_anchor"],
		["mana_shard",     "blood_chalice"],
		["bone_shield",    "void_lens"],
	],
	# Act 4: same 2 relics as Act 3 but with +1 bonus charge each
	4: [
		["scouts_lantern", "soul_anchor"],
		["mana_shard",     "blood_chalice"],
		["bone_shield",    "void_lens"],
	],
}

# Act 4: +1 bonus charge to each relic
const _ACT4_BONUS_CHARGES: Dictionary = {
	"scouts_lantern": 1, "soul_anchor": 1,
	"mana_shard": 1,     "blood_chalice": 1,
	"bone_shield": 1,    "void_lens": 1,
}

# Short display names for presets
const _PRESET_NAMES: Dictionary = {
	"swarm": "Swarm",
	"voidbolt_burst": "Voidbolt",
	"death_circle": "DeathCircle",
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

	print("")
	print("=== Echo of Abyss — Batch Balance Simulator ===")
	print("Runs per combination: %d" % runs)
	if fight_filter > 0:
		print("Fight filter: F%d" % fight_filter)
	else:
		print("Acts: %s" % str(acts))
	if not preset_filter.is_empty():
		print("Preset filter: %s" % preset_filter)
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

						var bonus_charges: Dictionary = _ACT4_BONUS_CHARGES if act_int >= 4 else {}
						var s: Dictionary = await sim.run_many(
							runs, deck, enemy_profile, enemy_deck,
							3000, enemy_hp, talents, profile_id,
							hero_passives, relic_ids, bonus_charges,
							enemy_limited)

						_print_row(preset_name, relic_display, enc.enemy_name, fight_idx as int, s, deck_id)

	print("")
	print("Done.")

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
		i += 1

	return result
