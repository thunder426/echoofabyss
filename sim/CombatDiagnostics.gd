## CombatDiagnostics.gd
## Sim-only reporting attached to a CombatState (plan 4.2): the damage-to-enemy-
## hero log by source and the debug print of every combat-log line. Listens to
## the state's signals; the state writes to it directly only for Void Bolt's
## split log (base + Void Mark bonus). Live combat never attaches one.
##
##   state.diagnostics = CombatDiagnostics.new(state, dmg_log, debug)
class_name CombatDiagnostics
extends RefCounted

## Record damage dealt to the enemy hero: {turn, amount, source} per hit.
var dmg_log_enabled: bool = false
var dmg_log: Array = []
## Print every combat-log line (DebugSingleSim) and let profiles print their own.
var debug_log_enabled: bool = false

var _state: CombatState = null

func _init(state: CombatState, p_dmg_log: bool = false, p_debug: bool = false) -> void:
	_state = state
	dmg_log_enabled = p_dmg_log
	debug_log_enabled = p_debug
	state.damage_dealt.connect(_capture_damage)
	state.combat_log.connect(_print_log)

func log_damage(amount: int, source: String) -> void:
	if dmg_log_enabled:
		dmg_log.append({turn = _state.turn_number, amount = amount, source = source})

## Skips "__logged__" hits — Void Bolt already split-logged its base + mark bonus
## at the source (CombatState._deal_void_bolt_damage).
func _capture_damage(source: String, target: String, amount: int, _school: int, _was_crit: bool) -> void:
	if target != "enemy" or source == "__logged__":
		return
	log_damage(amount, source)

func _print_log(msg: String, _log_type: int) -> void:
	if debug_log_enabled:
		print(msg)
