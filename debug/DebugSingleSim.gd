## DebugSingleSim.gd
## Runs a single F7 sim with full debug logging.
## Usage: Godot_console.exe --headless --path ... res://debug/DebugSingleSim.tscn
extends Node

func _ready() -> void:
	await _run()
	get_tree().quit()

func _run() -> void:
	var sim := CombatSim.new()
	var deck: Array[String] = PresetDecks.get_cards("voidbolt_burst")
	var enemy_deck := EncounterDecks.get_deck("f10_a")
	var enemy_limited := EncounterDecks.get_deck_limited("f10_a")
	var talents: Array[String] = ["piercing_void", "deepened_curse", "death_bolt", "void_manifestation"]
	var hero_passives: Array[String] = ["void_imp_boost", "void_imp_extra_copy"]
	var relic_ids: Array[String] = ["scouts_lantern", "soul_anchor"]

	print("=== DEBUG SINGLE SIM: F10 Voidbolt SL+SA ===")
	print("Player deck: %s" % str(deck))
	print("Enemy deck: %s" % str(enemy_deck))
	print("")

	var r: Dictionary = await sim.run(
		deck, "void_scout", enemy_deck,
		3000, 5000, talents, "spell_burn",
		hero_passives, relic_ids, {"scouts_lantern": 1, "soul_anchor": 1},
		false, true, enemy_limited)

	print("\n=== RESULT ===")
	print("Winner: %s" % r["winner"])
	print("Turns: %d" % r["turns"])
	print("Player HP: %d" % r["player_hp"])
	print("Enemy HP: %d" % r["enemy_hp"])
	print("Crits consumed: %d" % r.get("enemy_crits_consumed", 0) if r.has("enemy_crits_consumed") else "N/A")
	print("Champion spawns: %d" % r.get("champion_summon_count", 0))
