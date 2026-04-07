## VoidboltDmgDebug.gd
## Runs 5 Voidbolt vs F6 (Corrupted Handler) games and prints every point of
## enemy hero damage, labelled by source, turn by turn.
extends Node

const RUNS := 5

const DECK: Array[String] = [
	"void_imp","void_imp","void_imp","void_imp",
	"traveling_merchant","traveling_merchant",
	"void_bolt","void_bolt",
	"abyssal_sacrifice",
	"abyssal_plague","abyssal_plague",
	"void_rune","void_rune",
	"smoke_veil",
	"void_execution",
]
const ENEMY_DECK: Array[String] = [
	"abyss_cultist","abyss_cultist","abyss_cultist",
	"cult_fanatic","cult_fanatic",
	"brood_imp","brood_imp","brood_imp",
	"void_stalker","void_stalker",
	"void_spawner","void_spawner",
	"dark_command","dark_command",
]

func _ready() -> void:
	await _run()
	get_tree().quit()

func _run() -> void:
	var sim := CombatSim.new()
	print("=== Voidbolt vs F6 — Damage Source Log (%d runs) ===" % RUNS)

	for i in RUNS:
		var result: Dictionary = await sim.run(
			DECK, "corrupted_handler", ENEMY_DECK,
			3000, 4000,
			["piercing_void", "deepened_curse"],
			"spell_burn",
			["void_imp_boost", "void_imp_extra_copy"],
			["scouts_lantern"],
			{},
			true  # dmg_log enabled
		)

		print("\n--- Run %d | %s in %d turns | Player HP: %d | Enemy HP left: %d ---" % [
			i + 1,
			result.get("winner", "?").to_upper(),
			result.get("turns", 0),
			result.get("player_hp", 0),
			result.get("enemy_hp", 0),
		])

		var log: Array = result.get("dmg_log", [])
		var current_turn := -1
		var turn_total := 0
		var turn_sources: Dictionary = {}

		for entry in log:
			var t: int    = entry.get("turn", 0)
			var amt: int  = entry.get("amount", 0)
			var src: String = entry.get("source", "?")

			if t != current_turn:
				if current_turn >= 0:
					_print_turn_summary(current_turn, turn_total, turn_sources)
				current_turn = t
				turn_total = 0
				turn_sources = {}

			turn_total += amt
			turn_sources[src] = turn_sources.get(src, 0) + amt

		if current_turn >= 0:
			_print_turn_summary(current_turn, turn_total, turn_sources)

		# Grand total
		var grand_total := 0
		var grand_sources: Dictionary = {}
		for entry in log:
			grand_total += entry.get("amount", 0)
			var s: String = entry.get("source", "?")
			grand_sources[s] = grand_sources.get(s, 0) + entry.get("amount", 0)
		print("  TOTAL: %d dmg | %s" % [grand_total, _fmt_sources(grand_sources)])

func _print_turn_summary(turn: int, total: int, sources: Dictionary) -> void:
	print("  T%d  +%d dmg  [%s]" % [turn, total, _fmt_sources(sources)])

func _fmt_sources(sources: Dictionary) -> String:
	var parts: Array[String] = []
	for src in sources:
		parts.append("%s:%d" % [src, sources[src]])
	return "  ".join(parts)
