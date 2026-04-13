## DebugSingleSim.gd
## Runs a single F11 sim with full debug logging.
## Usage: Godot_console.exe --headless --path ... res://debug/DebugSingleSim.tscn
extends Node

func _ready() -> void:
	await _run()
	get_tree().quit()

func _run() -> void:
	var sim := CombatSim.new()
	var deck: Array[String] = PresetDecks.get_cards("swarm")
	var enemy_deck := EncounterDecks.get_deck("f11_a")
	var enemy_limited := EncounterDecks.get_deck_limited("f11_a")
	var talents: Array[String] = ["imp_evolution", "swarm_discipline", "imp_warband", "void_echo"]
	var hero_passives: Array[String] = ["void_imp_boost", "void_imp_extra_copy"]
	var relic_ids: Array[String] = ["scouts_lantern", "soul_anchor"]

	print("=== DEBUG SINGLE SIM: F11 Void Warband vs Swarm SL+SA ===")
	print("Player deck: %s" % str(deck))
	print("Enemy deck: %s" % str(enemy_deck))
	print("")

	var r: Dictionary = await sim.run(
		deck, "void_warband", enemy_deck,
		3000, 5000, talents, "swarm",
		hero_passives, relic_ids, {"scouts_lantern": 1},
		false, true, enemy_limited)

	print("\n=== RESULT ===")
	print("Winner: %s" % r["winner"])
	print("Turns: %d" % r["turns"])
	print("Player HP: %d" % r["player_hp"])
	print("Enemy HP: %d" % r["enemy_hp"])
	print("Champion spawns: %d" % r.get("champion_summon_count", 0))
	print("Behemoth plays: %d" % r.get("vw_behemoth_plays", 0))
	print("Bastion plays: %d" % r.get("vw_bastion_plays", 0))
