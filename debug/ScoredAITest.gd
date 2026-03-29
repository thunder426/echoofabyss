## ScoredAITest.gd
## Side-by-side comparison: Original enemy AI vs Scored enemy AI.
## Uses real Act 1 encounters with correct decks, passives, talents, and profiles.
## Each matchup runs both original and scored enemy, prints delta.
##
## Run via:  Godot --headless --path project/ res://debug/ScoredAITest.tscn
extends Node

const RUNS_PER_TEST := 500

const HERO_PASSIVES: Array[String] = ["void_imp_boost", "void_imp_extra_copy"]

## Player configs: preset deck, matching player AI profile, matching tier-0 talent
const PLAYER_CONFIGS: Array = [
	{"deck": "swarm",          "profile": "default",    "talent": "imp_evolution"},
	{"deck": "voidbolt_burst", "profile": "spell_burn", "talent": "piercing_void"},
	{"deck": "death_circle",   "profile": "rune_tempo", "talent": "rune_caller"},
]

const ENCOUNTERS: Array = [
	{
		"name": "Abyss Cultist Patrol",
		"hp": 2800,
		"original": "cultist_patrol",
		"scored": "cultist_patrol",
		"deck": [
			"abyss_cultist", "abyss_cultist", "abyss_cultist", "abyss_cultist",
			"void_netter", "void_netter",
			"imp_recruiter", "imp_recruiter",
			"corruption_weaver", "corruption_weaver",
			"spell_taxer",
			"soul_collector",
			"void_screech", "void_screech",
			"abyssal_plague", "abyssal_plague",
		],
	},
]

func _ready() -> void:
	await _run_comparison()
	get_tree().quit()

func _run_comparison() -> void:
	print("")
	print("╔═══════════════════════════════════════════════════════════════════════════════════════════╗")
	print("║         Echo of Abyss — Original vs Scored Enemy AI  (real encounters)                  ║")
	print("║         %d runs per matchup  |  Hero passives ON  |  1 talent point each                 ║" % RUNS_PER_TEST)
	print("╚═══════════════════════════════════════════════════════════════════════════════════════════╝")
	print("")

	var sim := CombatSim.new()

	for pc in PLAYER_CONFIGS:
		var deck_id: String = pc["deck"]
		var player_profile: String = pc["profile"]
		var talent: String = pc["talent"]
		var deck: Array[String] = PresetDecks.get_cards(deck_id)
		if deck.is_empty():
			continue
		var talents: Array[String] = [talent]

		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print("  PLAYER: %s  |  profile: %s  |  talent: %s" % [deck_id.to_upper(), player_profile, talent])
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print("")
		print("  %-22s │ %-16s │ %7s %7s %6s │ %8s %8s │ %s" % [
			"Enemy", "Enemy AI", "Win%", "Loss%", "Draw%", "AvgTurns", "AvgPHP", "Delta"])
		print("  ──────────────────────┼──────────────────┼───────────────────────┼───────────────────┼──────")

		for enc in ENCOUNTERS:
			var enc_name: String = enc["name"]
			var enc_hp: int = enc["hp"]
			var orig_id: String = enc["original"]
			var scored_id: String = enc["scored"]
			var enc_deck: Array[String] = []
			enc_deck.assign(enc["deck"])

			# --- Original enemy ---
			print("  Running %s vs %s [%s]..." % [deck_id, enc_name, orig_id])
			var s_orig: Dictionary = await sim.run_many(
				RUNS_PER_TEST, deck, orig_id, enc_deck,
				3000, enc_hp, talents, player_profile, HERO_PASSIVES)
			var o_win: float = s_orig.win_rate * 100.0
			var o_loss: float = float(s_orig.losses) / s_orig.count * 100.0
			var o_draw: float = float(s_orig.draws) / s_orig.count * 100.0
			print("  %-22s │ %-16s │ %6.1f%% %6.1f%% %5.1f%% │ %7.1f  %+7.0f │" % [
				enc_name, orig_id,
				o_win, o_loss, o_draw, s_orig.avg_turns, s_orig.avg_player_hp])

			# --- Scored enemy ---
			print("  Running %s vs %s [%s]..." % [deck_id, enc_name, scored_id])
			var s_scored: Dictionary = await sim.run_many(
				RUNS_PER_TEST, deck, scored_id, enc_deck,
				3000, enc_hp, talents, player_profile, HERO_PASSIVES)
			var sc_win: float = s_scored.win_rate * 100.0
			var sc_loss: float = float(s_scored.losses) / s_scored.count * 100.0
			var sc_draw: float = float(s_scored.draws) / s_scored.count * 100.0
			var delta: float = sc_win - o_win
			var label: String = "HARDER" if delta < -2.0 else ("EASIER" if delta > 2.0 else "~SAME")
			print("  %-22s │ %-16s │ %6.1f%% %6.1f%% %5.1f%% │ %7.1f  %+7.0f │ %s (%+.1f%%)" % [
				"", scored_id,
				sc_win, sc_loss, sc_draw, s_scored.avg_turns, s_scored.avg_player_hp,
				label, delta])
			print("  ──────────────────────┼──────────────────┼───────────────────────┼───────────────────┼──────")

		print("")

	print("")
	print("Done. HARDER = scored enemy reduces player win rate. EASIER = scored enemy is weaker.")
