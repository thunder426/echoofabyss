## SimRunner.gd
## Headless CLI entry point for CombatSim.
## Run via:
##   Godot_console.exe --headless --path /path/to/project res://debug/SimRunner.tscn -- [args]
##
## Arguments (all optional, pass after --):
##   --deck      "id1,id2,..."   Player deck card IDs  (default: built-in test deck)
##   --profile   feral_pack      Enemy profile ID       (default: default)
##   --runs      100             Number of simulations  (default: 100)
##   --player-hp 3000            Player starting HP     (default: 3000)
##   --enemy-hp  2000            Enemy starting HP      (default: 2000)
##   --talents   "t1,t2"         Player talent IDs      (default: none)
##   --hero-passives "p1,p2"     Player hero passive IDs (default: none)
##   --all-profiles              Run against every registered profile
##
## Example:
##   Godot_console.exe --headless --path project/ res://debug/SimRunner.tscn -- \
##       --deck "void_imp,void_imp,shadow_hound,void_bolt" --profile feral_pack --runs 200
extends Node

const _DEFAULT_DECK := "void_imp,void_imp,shadow_hound,shadow_hound,abyssal_brute,void_bolt,void_bolt"
const _ALL_PROFILES: Array[String] = ["feral_pack", "corrupted_brood", "default"]

func _ready() -> void:
	await _run()
	get_tree().quit()

func _run() -> void:
	var args := _parse_args()

	print("")
	print("=== Echo of Abyss — Balance Simulator ===")
	print("Deck:      %s" % ",".join(args.deck))
	if not args.talents.is_empty():
		print("Talents:   %s" % ",".join(args.talents))
	if not args.hero_passives.is_empty():
		print("Passives:  %s" % ",".join(args.hero_passives))
	print("Runs:      %d" % args.runs)
	print("Player HP: %d   Enemy HP: %d" % [args.player_hp, args.enemy_hp])
	print("")

	var profiles: Array[String] = []
	if args.all_profiles:
		profiles.assign(_ALL_PROFILES)
	else:
		profiles.append(args.profile as String)

	var sim := CombatSim.new()

	for profile in profiles:
		print("▶  %s …" % profile)
		var s: Dictionary = await sim.run_many(
			args.runs,
			args.deck,
			profile,
			args.enemy_deck,
			args.player_hp,
			args.enemy_hp,
			args.talents,
			args.player_profile,
			args.hero_passives,
			args.relics
		)
		_print_result(profile, s)

	print("")
	print("Done.")

func _print_result(profile: String, s: Dictionary) -> void:
	var win_pct:  float = s.win_rate * 100.0
	var loss_pct: float = float(s.losses) / s.count * 100.0
	var draw_pct: float = float(s.draws)  / s.count * 100.0
	var avg_hp:   float = s.avg_player_hp
	var avg_champ: float = s.get("avg_champion_summons", 0.0)

	print("  %-18s  Win %5.1f%%  Loss %5.1f%%  Draw %4.1f%%  AvgTurns %4.1f  AvgHP %+.0f  Champ %.2f" % [
		profile, win_pct, loss_pct, draw_pct, s.avg_turns, avg_hp, avg_champ])
	# Print extra stats if non-zero
	var sv_fires: float = s.get("avg_smoke_veil_fires", 0.0)
	var sv_dmg:   float = s.get("avg_smoke_veil_dmg", 0.0)
	var pl_fires: float = s.get("avg_plague_fires", 0.0)
	var pl_kills: float = s.get("avg_plague_kills", 0.0)
	if sv_fires > 0 or pl_fires > 0:
		print("    SmokeVeil: %.2f fires, %.0f dmg prevented  |  Plague: %.2f fires, %.2f kills" % [
			sv_fires, sv_dmg, pl_fires, pl_kills])
	var corr_det: float = s.get("avg_corruption_det", 0.0)
	var ritual:   float = s.get("avg_ritual_invoke", 0.0)
	var spark_b:  float = s.get("avg_spark_buff", 0.0)
	var aura_dmg: float = s.get("avg_ch_aura_dmg", 0.0)
	var clogged: float = s.get("avg_clogged_slots", 0.0)
	if corr_det > 0 or ritual > 0 or spark_b > 0 or aura_dmg > 0 or clogged > 0:
		print("    Detonations: %.2f  |  Rituals: %.2f  |  SparkBuffs: %.2f  |  AuraDmg: %.0f  |  Clogged: %.1f" % [corr_det, ritual, spark_b, aura_dmg, clogged])

func _parse_args() -> Dictionary:
	var result := {
		"deck":             _split(_DEFAULT_DECK),
		"enemy_deck":       [] as Array[String],
		"profile":          "default",
		"player_profile":   "default",
		"runs":             100,
		"player_hp":        3000,
		"enemy_hp":         2000,
		"talents":          [] as Array[String],
		"hero_passives":    [] as Array[String],
		"relics":           [] as Array[String],
		"all_profiles":     false,
	}

	var args := OS.get_cmdline_user_args()
	var i    := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--deck":
				if i + 1 < args.size():
					result.deck = _split(args[i + 1]); i += 1
			"--enemy-deck":
				if i + 1 < args.size():
					result.enemy_deck = _split(args[i + 1]); i += 1
			"--profile":
				if i + 1 < args.size():
					result.profile = args[i + 1]; i += 1
			"--runs":
				if i + 1 < args.size():
					result.runs = int(args[i + 1]); i += 1
			"--player-hp":
				if i + 1 < args.size():
					result.player_hp = int(args[i + 1]); i += 1
			"--enemy-hp":
				if i + 1 < args.size():
					result.enemy_hp = int(args[i + 1]); i += 1
			"--talents":
				if i + 1 < args.size():
					result.talents = _split(args[i + 1]); i += 1
			"--hero-passives":
				if i + 1 < args.size():
					result.hero_passives = _split(args[i + 1]); i += 1
			"--relics":
				if i + 1 < args.size():
					result.relics = _split(args[i + 1]); i += 1
			"--player-profile":
				if i + 1 < args.size():
					result.player_profile = args[i + 1]; i += 1
			"--all-profiles":
				result.all_profiles = true
		i += 1

	return result

func _split(text: String) -> Array[String]:
	var out: Array[String] = []
	for part in text.split(","):
		var s := part.strip_edges()
		if not s.is_empty():
			out.append(s)
	return out
