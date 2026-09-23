## Compiles every .gd in the project (after autoloads are up) and fails on any
## script that does not load — catches parse errors in scripts no test touches
## (UI, debug scenes). Run by tools/run_checks.sh:
##   godot --headless --path . --script res://tools/lint/load_all_scripts.gd
extends SceneTree
var _done := false
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var bad := 0
	var files: Array[String] = []
	_walk("res://", files)
	var own_path: String = (get_script() as Script).resource_path
	for f in files:
		if f == own_path:
			continue  # recompiling the running script breaks the VM
		var s: Script = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
		if s == null or not s.can_instantiate():
			bad += 1
			print("LOADFAIL ", f)
	print("load_all: %d scripts, %d failed" % [files.size(), bad])
	quit(bad)
	return true
func _walk(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null: return
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "addons": continue
		_walk(dir.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
