## RunAllTests.gd
## Entry point for the layered effect/handler/scenario test suite.
##
## Usage:
##   Godot --headless --path echoofabyss res://debug/tests/RunAllTests.tscn -- [--verbose|-v] [--filter <substr>]
##
## Exit code = number of failed assertions (0 = all green).
extends Node

const TestHarnessScript        = preload("res://debug/tests/TestHarness.gd")
const CardEffectTestsScript    = preload("res://debug/tests/CardEffectTests.gd")
const TriggerHandlerTestsScript = preload("res://debug/tests/TriggerHandlerTests.gd")
const ScenarioTestsScript      = preload("res://debug/tests/ScenarioTests.gd")
const DamageTypeTestsScript    = preload("res://debug/tests/DamageTypeTests.gd")

func _ready() -> void:
	_parse_args()
	TestHarnessScript.reset_counters()

	print("=== EchoOfAbyss Test Suite ===")
	if TestHarnessScript.filter_substr != "":
		print("  filter: %s" % TestHarnessScript.filter_substr)
	if TestHarnessScript.verbose:
		print("  verbose: on (state dump on failure)")

	DamageTypeTestsScript.run_all()
	CardEffectTestsScript.run_all()
	TriggerHandlerTestsScript.run_all()
	await ScenarioTestsScript.run_all()

	print("\n=== %s ===" % TestHarnessScript.summary())
	get_tree().quit(TestHarnessScript.fail_count())

func _parse_args() -> void:
	# User args (after "--" separator) are in get_cmdline_user_args; engine-level
	# flags are in get_cmdline_args. Check both so either invocation style works.
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	var i := 0
	while i < args.size():
		var a := String(args[i])
		if a == "--verbose" or a == "-v":
			TestHarnessScript.verbose = true
		elif a == "--filter":
			if i + 1 < args.size():
				TestHarnessScript.filter_substr = String(args[i + 1])
				i += 1
		i += 1
