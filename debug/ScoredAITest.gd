## ScoredAITest.gd — Voidbolt full run: Act 1 (1 talent, no relic) + Act 2 (2 talents, 1 relic each)
extends Node

const RUNS := 500
const HERO_PASSIVES: Array[String] = ["void_imp_boost", "void_imp_extra_copy"]
const T1: Array[String] = ["piercing_void"]
const T2: Array[String] = ["piercing_void", "deepened_curse"]
const RELICS: Array[String] = ["scouts_lantern", "imp_talisman", "mana_shard", "bone_shield"]

const ENCOUNTERS: Array = [
	{"fight": 1, "name": "Rogue Imp Pack",       "hp": 1800, "profile": "feral_pack",       "tp": 1,
	 "deck": ["rabid_imp","rabid_imp","rabid_imp","rabid_imp","brood_imp","brood_imp","brood_imp",
			  "imp_brawler","imp_brawler","imp_brawler","feral_surge","feral_surge","void_screech","void_screech"]},
	{"fight": 2, "name": "Corrupted Broodlings", "hp": 2400, "profile": "corrupted_brood",  "tp": 1,
	 "deck": ["brood_imp","brood_imp","void_touched_imp","void_touched_imp","void_touched_imp","void_touched_imp",
			  "rabid_imp","rabid_imp","rabid_imp","rabid_imp","void_screech","pack_frenzy","pack_frenzy"]},
	{"fight": 3, "name": "Imp Matriarch",        "hp": 3000, "profile": "matriarch",        "tp": 1,
	 "deck": ["rabid_imp","rabid_imp","rabid_imp","brood_imp","brood_imp","imp_brawler","imp_brawler",
			  "void_touched_imp","rogue_imp_elder","matriarchs_broodling","pack_frenzy","pack_frenzy",
			  "feral_surge","void_screech","brood_call"]},
	{"fight": 4, "name": "Cultist Patrol",       "hp": 2800, "profile": "cultist_patrol",   "tp": 2,
	 "deck": ["abyss_cultist","abyss_cultist","abyss_cultist","abyss_cultist",
			  "void_netter","void_stalker","corruption_weaver","corruption_weaver",
			  "cult_fanatic","cult_fanatic","void_stalker","spell_taxer","spell_taxer",
			  "dark_command","dark_command"]},
	{"fight": 5, "name": "Void Ritualist",       "hp": 3400, "profile": "void_ritualist",   "tp": 2,
	 "deck": ["abyss_cultist","abyss_cultist","abyss_cultist",
			  "cult_fanatic","cult_fanatic","cult_fanatic","corruption_weaver","corruption_weaver",
			  "void_stalker","dominion_rune","dominion_rune","blood_rune","blood_rune",
			  "dark_command","dark_command"]},
	{"fight": 6, "name": "Corrupted Handler",    "hp": 4000, "profile": "corrupted_handler", "tp": 2,
	 "deck": ["abyss_cultist","abyss_cultist","abyss_cultist",
			  "cult_fanatic","cult_fanatic","cult_fanatic","corruption_weaver","corruption_weaver",
			  "soul_collector","void_stalker","void_stalker","spell_taxer",
			  "dark_command","dark_command"]},
]

func _ready() -> void:
	await _run()
	get_tree().quit()

func _run() -> void:
	print("")
	print("╔══════════════════════════════════════════════════════════════════════════════════════╗")
	print("║   VOIDBOLT BURST Full Run  |  spell_burn  |  %d runs                                ║" % RUNS)
	print("║   Act 1: 1 talent, no relic  |  Act 2: 2 talents, 1 relic (4 variants + baseline)   ║")
	print("╚══════════════════════════════════════════════════════════════════════════════════════╝")
	print("")

	var sim := CombatSim.new()
	var deck: Array[String] = PresetDecks.get_cards("voidbolt_burst")

	print("  %-5s %-22s │ %4s │ %-16s │ %7s │ %8s │ %6s" % [
		"Fight", "Enemy", "HP", "Relic", "Win%", "AvgPHP", "Uses"])
	print("  ───── ──────────────────────┼──────┼──────────────────┼─────────┼──────────┼────────")

	for enc in ENCOUNTERS:
		var enc_deck: Array[String] = []
		enc_deck.assign(enc["deck"])
		var tp: int = enc["tp"]
		var talents: Array[String] = T2 if tp >= 2 else T1
		var is_act2: bool = tp >= 2

		if is_act2:
			# Baseline (no relic)
			print("  Running F%d baseline..." % enc["fight"])
			var s_base: Dictionary = await sim.run_many(
				RUNS, deck, enc["profile"] as String, enc_deck,
				3000, enc["hp"] as int, talents, "spell_burn", HERO_PASSIVES)
			var base_win: float = s_base.win_rate * 100.0
			print("  %-5d %-22s │ %4d │ %-16s │ %6.1f%% │ %+7.0f │    -" % [
				enc["fight"], enc["name"], enc["hp"], "(none)", base_win, s_base.avg_player_hp])

			# Each relic
			for relic_id in RELICS:
				var relic: RelicData = RelicDatabase.get_relic(relic_id)
				var relic_ids: Array[String] = [relic_id]
				print("  Running F%d + %s..." % [enc["fight"], relic_id])
				var s: Dictionary = await sim.run_many(
					RUNS, deck, enc["profile"] as String, enc_deck,
					3000, enc["hp"] as int, talents, "spell_burn", HERO_PASSIVES,
					relic_ids)
				var win_pct: float = s.win_rate * 100.0
				var avg_uses: float = s.get("avg_relic_activations", 0.0)
				var delta: float = win_pct - base_win
				print("  %-5s %-22s │ %4s │ %-16s │ %6.1f%% │ %+7.0f │ %5.2f (%+.1f%%)" % [
					"", "", "", relic.relic_name if relic else relic_id,
					win_pct, s.avg_player_hp, avg_uses, delta])
		else:
			# Act 1: no relic
			print("  Running F%d..." % enc["fight"])
			var s: Dictionary = await sim.run_many(
				RUNS, deck, enc["profile"] as String, enc_deck,
				3000, enc["hp"] as int, talents, "spell_burn", HERO_PASSIVES)
			var win_pct: float = s.win_rate * 100.0
			print("  %-5d %-22s │ %4d │ %-16s │ %6.1f%% │ %+7.0f │    -" % [
				enc["fight"], enc["name"], enc["hp"], "-", win_pct, s.avg_player_hp])

		print("  ───── ──────────────────────┼──────┼──────────────────┼─────────┼──────────┼────────")

	print("")
	print("Done.")
