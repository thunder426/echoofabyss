## VfxGate.gd
## Counted-gate helper for animation gating in combat.
##
## CombatScene already has four hand-written gates (enemy_summon_reveal,
## enemy_spell_cast, on_play_vfx, death_anims) backed by bool flags / int
## counters and matching signals. Those are awaited by EnemyAI and by
## `_do_end_turn`. Adding a 5th gate type today means adding a new flag, a
## new signal, AND editing `_do_end_turn`'s while-loop.
##
## VfxGate is the additive path forward: any code that begins a new gate
## category just calls `vfx_gate.begin("my_name")` and `end("my_name")`.
## `_do_end_turn` already awaits `vfx_gate.is_any_active()`, so future gate
## types are picked up with zero edits to CombatScene.
##
## The existing four signals/flags are NOT migrated here — they are awaited
## externally by EnemyAI and migrating them would touch every awaiter. Leave
## them. Use VfxGate for NEW gating needs only.
##
## Counted (not boolean) so two parallel VFX of the same category nest
## correctly — `begin/begin/end/end` stays active until the second `end`.
class_name VfxGate
extends RefCounted

## Emitted when the last active gate of any kind ends (transition to idle).
signal idle

## name -> outstanding begin() count. Entries with count 0 stay in the dict
## but don't count toward `is_any_active()`.
var _counts: Dictionary = {}

## Begin a gated VFX. Pair with `end(name)` when the visual finishes.
func begin(name: String) -> void:
	_counts[name] = int(_counts.get(name, 0)) + 1

## End one outstanding gate of this name. Emits `idle` if this brings the
## total active gates to zero. Safe to call when count is already 0 (no-op).
func end(name: String) -> void:
	var cur: int = int(_counts.get(name, 0))
	if cur <= 0:
		return
	_counts[name] = cur - 1
	if not is_any_active():
		idle.emit()

## True if at least one gate of `name` is outstanding.
func is_active(name: String) -> bool:
	return int(_counts.get(name, 0)) > 0

## True if any gate (any name) is outstanding.
func is_any_active() -> bool:
	for k in _counts.keys():
		if int(_counts[k]) > 0:
			return true
	return false

## Suspend until all gates have ended. No-op if already idle.
func await_idle() -> void:
	if not is_any_active():
		return
	await idle
