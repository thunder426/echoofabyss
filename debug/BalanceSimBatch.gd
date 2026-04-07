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
		},
	},
	"voidbolt_burst": {
		"profile": "spell_burn",
		"hero_passives": ["void_imp_boost", "void_imp_extra_copy"],
		"talents_by_act": {
			1: ["piercing_void"],
			2: ["piercing_void", "deepened_curse"],
			3: ["piercing_void", "deepened_curse", "death_bolt"],
		},
	},
	"death_circle": {
		"profile": "rune_tempo",
		"hero_passives": ["void_imp_boost", "void_imp_extra_copy"],
		"talents_by_act": {
			1: ["rune_caller"],
			2: ["rune_caller", "runic_attunement"],
			3: ["rune_caller", "runic_attunement", "ritual_surge"],
		},
	},
}

const _ACT_FIGHTS: Dictionary = {
	1: [1, 2, 3],
	2: [4, 5, 6],
}

const _ACT_RELICS: Dictionary = {
	1: [],  # no relics in Act 1
	2: ["scouts_lantern", "imp_talisman", "mana_shard", "bone_shield"],
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
	"imp_talisman": "IT",
	"mana_shard": "MS",
	"bone_shield": "BS",
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

			var preset_name: String = _PRESET_NAMES.get(preset_id, preset_id)

			# Determine relic combinations to run
			var relic_combos: Array = []
			if relics.is_empty():
				relic_combos.append("")  # no relic
			else:
				for r in relics:
					relic_combos.append(r as String)

			for fight_idx in fights:
				var enc: EnemyData = GameManager.get_encounter(fight_idx as int)
				if enc == null:
					continue

				var enemy_deck: Array[String] = []
				for id in enc.deck:
					enemy_deck.append(id as String)
				var enemy_hp: int = enc.hp
				var enemy_profile: String = enc.ai_profile

				for relic in relic_combos:
					var relic_ids: Array[String] = []
					if not (relic as String).is_empty():
						relic_ids.append(relic as String)

					var relic_display: String = _RELIC_NAMES.get(relic, "none") if not (relic as String).is_empty() else "none"

					var s: Dictionary = await sim.run_many(
						runs, deck, enemy_profile, enemy_deck,
						3000, enemy_hp, talents, profile_id,
						hero_passives, relic_ids)

					_print_row(preset_name, relic_display, enc.enemy_name, fight_idx as int, s)

	print("")
	print("Done.")

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

func _print_row(preset: String, relic: String, fight_name: String, fight_idx: int, s: Dictionary) -> void:
	var win_pct: float = s.win_rate * 100.0
	var loss_pct: float = float(s.losses) / s.count * 100.0
	var avg_hp: float = s.avg_player_hp
	var avg_turns: float = s.avg_turns
	var champ: float = s.get("avg_champion_summons", 0.0)

	var line := "%-10s | %-4s | F%d %-22s | Win %5.1f%% | Loss %5.1f%% | T %4.1f | HP %+5.0f | Champ %.2f" % [
		preset, relic, fight_idx, fight_name, win_pct, loss_pct, avg_turns, avg_hp, champ]
	print(line)

	# Extra stats line if any non-zero
	var det: float = s.get("avg_corruption_det", 0.0)
	var rit: float = s.get("avg_ritual_invoke", 0.0)
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

	var extras: Array[String] = []
	if det > 0: extras.append("Det:%.1f" % det)
	if rit > 0: extras.append("Rit:%.1f" % rit)
	if sb > 0: extras.append("SpkB:%.1f" % sb)
	if aura > 0: extras.append("Aura:%.0f" % aura)
	if clog > 0.1: extras.append("Clog:%.1f" % clog)
	if sv > 0: extras.append("SV:%.1f/%.0f" % [sv, sv_d])
	if pl > 0: extras.append("Plg:%.1f/%.1f" % [pl, pl_k])
	if vb_c > 0: extras.append("VB:%.1fx/%.0fdmg" % [vb_c, vb_d])
	if vi_d > 0: extras.append("Imp:%.0f" % vi_d)

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
		i += 1

	return result
