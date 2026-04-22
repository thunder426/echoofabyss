## DebugF13LossAnalysis.gd
## Runs N Swarm vs F13 (Void Ritualist Prime) games and captures per-turn
## snapshots to diagnose WHY the enemy boss loses.
##
## Tracks per turn:
##   - Enemy board size & total ATK (pressure)
##   - Enemy hand size + uncastable cards (hand bloat / resource tension)
##   - Enemy mana/essence caps + unused
##   - Player board size + total ATK (pressure faced)
##   - Damage dealt to enemy hero this turn, by source
##
## Prints per-game turn-by-turn table, then an aggregate summary.
## Usage: Godot_console --headless --path ... res://debug/DebugF13LossAnalysis.tscn -- [--games N]
extends Node

const GAMES_DEFAULT := 5

var _all_games: Array = []  ## each entry: {snapshots: [...], winner, turns, final_enemy_hp}

func _ready() -> void:
	await _run()
	get_tree().quit()

func _run() -> void:
	var games: int = GAMES_DEFAULT
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--games" and i + 1 < args.size():
			games = int(args[i + 1])

	print("=== F13 Loss Analysis: Swarm vs Void Ritualist Prime (%d games) ===\n" % games)

	var deck: Array[String] = PresetDecks.get_cards("swarm")
	var enemy_deck := EncounterDecks.get_deck("f13_a")
	var enemy_limited := EncounterDecks.get_deck_limited("f13_a")
	var talents: Array[String] = ["imp_evolution", "swarm_discipline", "imp_warband", "void_echo"]
	var hero_passives: Array[String] = ["void_imp_boost", "void_imp_extra_copy"]
	var relic_ids: Array[String] = ["mana_shard", "dark_mirror"]  # MS+DM — historically the weak combo

	for g in games:
		var snapshots: Array = []
		var prev_enemy_hp := 5000
		var sim := CombatSim.new()
		sim.turn_snapshot_callback = func(st: SimState, turn: int) -> void:
			var enemy_board_atk := 0
			for m: MinionInstance in st.enemy_board: enemy_board_atk += m.effective_atk()
			var player_board_atk := 0
			for m: MinionInstance in st.player_board: player_board_atk += m.effective_atk()
			var uncastable := 0
			for inst in st.enemy_hand:
				if not _is_castable(inst, st):
					uncastable += 1
			snapshots.append({
				"turn": turn,
				"e_hp": st.enemy_hp,
				"p_hp": st.player_hp,
				"dmg_this_turn": prev_enemy_hp - st.enemy_hp,
				"e_board": st.enemy_board.size(),
				"e_board_atk": enemy_board_atk,
				"p_board": st.player_board.size(),
				"p_board_atk": player_board_atk,
				"e_hand": st.enemy_hand.size(),
				"e_uncastable": uncastable,
				"e_mana": st.enemy_mana_max,
				"e_essence": st.enemy_essence_max,
				"e_hand_names": _hand_names(st.enemy_hand),
			})
			prev_enemy_hp = st.enemy_hp

		var r: Dictionary = await sim.run(
			deck, "void_ritualist_prime", enemy_deck,
			3000, 5000, talents, "swarm",
			hero_passives, relic_ids, {},
			true, false, enemy_limited)

		_all_games.append({
			"snapshots": snapshots,
			"winner": r["winner"],
			"turns": r["turns"],
			"final_enemy_hp": r["enemy_hp"],
			"final_player_hp": r["player_hp"],
			"dmg_log": r.get("dmg_log", []),
		})
		_print_game(g + 1, _all_games[-1])

	_print_summary()

func _is_castable(inst: CardInstance, st: SimState) -> bool:
	var cd = inst.card_data
	if cd is SpellCardData:
		var sp := cd as SpellCardData
		if sp.cost > st.enemy_mana:
			return false
		if sp.void_spark_cost > 0:
			var spark := 0
			for m: MinionInstance in st.enemy_board:
				spark += (m.card_data as MinionCardData).spark_value
			if sp.void_spark_cost > spark:
				return false
		return true
	elif cd is MinionCardData:
		var mc := cd as MinionCardData
		if mc.essence_cost > st.enemy_essence:
			return false
		return true
	return true

func _hand_names(hand: Array[CardInstance]) -> String:
	var names: Array[String] = []
	for inst in hand: names.append(inst.card_data.id)
	return ",".join(names)

func _print_game(idx: int, g: Dictionary) -> void:
	print("--- Game %d — winner: %s, turns: %d, final enemy HP: %d, player HP: %d ---" % [
		idx, g.winner, g.turns, g.final_enemy_hp, g.final_player_hp])
	print("%-4s %-6s %-6s %-5s %-8s %-8s %-8s %-8s %-5s %-6s %-5s %-5s" % [
		"T", "eHP", "pHP", "dHP", "eBrd", "eAtk", "pBrd", "pAtk", "eHnd", "eUncst", "eM", "eE"])
	for s in g.snapshots:
		print("%-4d %-6d %-6d %-5d %-8d %-8d %-8d %-8d %-5d %-6d %-5d %-5d" % [
			s.turn, s.e_hp, s.p_hp, s.dmg_this_turn,
			s.e_board, s.e_board_atk, s.p_board, s.p_board_atk,
			s.e_hand, s.e_uncastable, s.e_mana, s.e_essence])
	# Damage source breakdown
	var src_totals: Dictionary = {}
	for entry in g.dmg_log:
		src_totals[entry.source] = int(src_totals.get(entry.source, 0)) + int(entry.amount)
	if not src_totals.is_empty():
		var parts: Array[String] = []
		var keys := src_totals.keys()
		keys.sort_custom(func(a, b): return int(src_totals[a]) > int(src_totals[b]))
		for k in keys: parts.append("%s:%d" % [k, int(src_totals[k])])
		print("  Dmg sources: %s" % ", ".join(parts))
	print("")

func _print_summary() -> void:
	var losses: Array = []   # enemy-lost games (winner == "player")
	var wins: Array = []     # enemy-won
	for g in _all_games:
		if g.winner == "player": losses.append(g)
		elif g.winner == "enemy": wins.append(g)
	print("=== SUMMARY ===")
	print("Enemy wins: %d / %d" % [wins.size(), _all_games.size()])
	print("Enemy losses: %d / %d" % [losses.size(), _all_games.size()])

	if losses.is_empty():
		print("No enemy losses to analyze.")
		return

	# Aggregate: avg enemy board size, hand size, uncastable count per turn
	var max_t := 0
	for g in losses:
		for s in g.snapshots:
			if s.turn > max_t: max_t = s.turn
	print("\n-- Per-turn averages across losses --")
	print("%-4s %-6s %-6s %-6s %-6s %-6s %-6s" % ["T", "eBrd", "eAtk", "pBrd", "pAtk", "eHnd", "eUncst"])
	for t in range(1, max_t + 1):
		var n := 0
		var sum_eb := 0; var sum_ea := 0; var sum_pb := 0; var sum_pa := 0
		var sum_eh := 0; var sum_eu := 0
		for g in losses:
			for s in g.snapshots:
				if s.turn == t:
					n += 1
					sum_eb += s.e_board; sum_ea += s.e_board_atk
					sum_pb += s.p_board; sum_pa += s.p_board_atk
					sum_eh += s.e_hand;  sum_eu += s.e_uncastable
					break
		if n > 0:
			print("%-4d %-6.1f %-6.0f %-6.1f %-6.0f %-6.1f %-6.1f" % [
				t, float(sum_eb)/n, float(sum_ea)/n,
				float(sum_pb)/n, float(sum_pa)/n,
				float(sum_eh)/n, float(sum_eu)/n])

	# Diagnose failure patterns per-game
	print("\n-- Loss-cause tagging (per game) --")
	for i in losses.size():
		var g: Dictionary = losses[i]
		var tags: Array[String] = _tag_loss_causes(g)
		print("  Game #%d (t=%d, eHP end=%d): %s" % [i + 1, g.turns, g.final_enemy_hp, ", ".join(tags)])

	print("\n-- Suggestions --")
	_print_suggestions(losses)

func _tag_loss_causes(g: Dictionary) -> Array[String]:
	var tags: Array[String] = []
	var snaps: Array = g.snapshots
	if snaps.is_empty():
		return ["no_data"]

	# Outpaced: player board ATK outgrew enemy board ATK consistently
	var p_dominates := 0
	for s in snaps:
		if s.p_board_atk > s.e_board_atk + 200:
			p_dominates += 1
	if p_dominates >= max(2, snaps.size() / 2):
		tags.append("player_board_outpaces")

	# Swarmed: player board often ≥ 4 minions
	var heavy_board := 0
	for s in snaps:
		if s.p_board >= 4: heavy_board += 1
	if heavy_board >= 2:
		tags.append("player_swarm_pressure")

	# Hand bloat: avg uncastable ≥ 1.5 on last 3 turns
	var last: Array = snaps.slice(max(0, snaps.size() - 3))
	var sum_unc := 0
	for s in last: sum_unc += s.e_uncastable
	if last.size() > 0 and float(sum_unc) / last.size() >= 1.5:
		tags.append("enemy_hand_bloat")

	# Resource tension: mana_max < 4 on turn 4+
	for s in snaps:
		if s.turn >= 4 and s.e_mana < 4:
			tags.append("enemy_mana_starved_mid")
			break

	# No AoE clear: enemy board shrank while player board grew over 3 consecutive turns
	if snaps.size() >= 3:
		for i in range(snaps.size() - 2):
			var a = snaps[i]; var b = snaps[i + 1]; var c = snaps[i + 2]
			if c.p_board > a.p_board + 1 and c.e_board <= a.e_board:
				tags.append("no_board_clear")
				break

	# Burst damage: single-turn damage to enemy hero > 1500
	for s in snaps:
		if s.dmg_this_turn > 1500:
			tags.append("burst_dmg_t%d:%d" % [s.turn, s.dmg_this_turn])

	if tags.is_empty():
		tags.append("grind_loss")
	return tags

func _print_suggestions(losses: Array) -> void:
	# Count how often each tag appears
	var tag_counts: Dictionary = {}
	for g in losses:
		for t in _tag_loss_causes(g):
			# Normalize burst tag (trim turn/amount)
			var key: String = t.split(":")[0].split("_t")[0] if t.begins_with("burst") else t
			tag_counts[key] = int(tag_counts.get(key, 0)) + 1

	var n := losses.size()
	var suggestions: Array[String] = []
	if int(tag_counts.get("player_board_outpaces", 0)) >= n / 2:
		suggestions.append("• Player board consistently outscales. Consider: add a 2nd AoE spell (e.g. +1 Rift Collapse or Void Shatter), raise enemy minion ATK stats, or add a buff-your-board passive.")
	if int(tag_counts.get("player_swarm_pressure", 0)) >= n / 2:
		suggestions.append("• Player floods board (4+ minions often). Boss lacks board-wide clear. Add Rift Collapse copy, or raise collapse damage to 300.")
	if int(tag_counts.get("enemy_hand_bloat", 0)) >= n / 2:
		suggestions.append("• Enemy hand clogs late-game (uncastable cards). Consider: lower costs, better mana growth, or add a mana-cheat card.")
	if int(tag_counts.get("enemy_mana_starved_mid", 0)) >= n / 2:
		suggestions.append("• Mana max stays < 4 into mid-game. Accelerate mana growth in VoidRitualistPrimeProfile resource curve.")
	if int(tag_counts.get("no_board_clear", 0)) >= n / 2:
		suggestions.append("• Enemy fails to clear growing player boards. Prioritize Rift Collapse, add a second AoE, or tune AoE damage up.")
	if int(tag_counts.get("burst", 0)) >= n / 2:
		suggestions.append("• Enemy dies to burst turns (>1500 in one turn). Consider: enemy healing, damage-reduction aura, or HP increase.")
	if int(tag_counts.get("grind_loss", 0)) >= n / 2:
		suggestions.append("• Losses are slow grinds — consider raising enemy HP or adding end-game threat.")

	if suggestions.is_empty():
		print("  (no single dominant pattern — losses are varied)")
	else:
		for s in suggestions: print("  " + s)
