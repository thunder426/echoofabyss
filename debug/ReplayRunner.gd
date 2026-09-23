## ReplayRunner.gd
## Plays a recorded sim fight back through the command log (plan 2A.8) and
## reports whether it reproduces: prints the final digest text, the first
## command that was refused (if any) and whether the digest matches the one
## recorded. Sim-recorded logs only until Phase 3.4 moves live input onto
## commands.
##
## Record:  godot --headless --path . res://debug/SimRunner.tscn -- --runs 1 --dump-replay /tmp/fight.json [--profile …]
## Replay:  godot --headless --path . res://debug/ReplayRunner.tscn -- /tmp/fight.json
extends Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("ReplayRunner: pass the replay JSON path after --")
		get_tree().quit(2)
		return
	var text: String = FileAccess.get_file_as_string(args[0])
	var record: Variant = JSON.parse_string(text)
	if not (record is Dictionary):
		print("ReplayRunner: %s is not a replay JSON" % args[0])
		get_tree().quit(2)
		return
	var out: Dictionary = CombatSim.new().replay(record)
	print(out["digest_text"])
	print("commands: %d  winner: %s" % [(record["command_log"] as Array).size(), out["winner"]])
	if int(out["failed_index"]) >= 0:
		print("REFUSED at command %d (%s): %s" % [out["failed_index"], out["reason"], JSON.stringify(out["failed_command"])])
	var same: bool = int(out["digest"]) == int(record.get("digest", 0))
	print("REPLAY %s" % ("OK — digest matches" if same else "DIVERGED — digest differs from the recording"))
	get_tree().quit(0 if same and int(out["failed_index"]) < 0 else 1)
