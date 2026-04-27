## BaseVfx.gd
## Convention base for every combat VFX.
##
## Contract:
##   - Extends Node2D (so it has a position for shake routing, even if unused).
##   - Parented to CombatScene.VfxLayer (a CanvasLayer at layer 2 — above the
##     UI CanvasLayer at layer 1). VfxController.spawn() enforces this; never
##     add a VFX manually to CombatScene or $UI.
##   - Emits `impact_hit(index)` once per logical impact (single-target: i=0;
##     AoE: i=0..N-1). VfxController awaits each and fires damage callbacks
##     synced to the visual.
##   - Emits `finished` when the full visible effect has ended, then calls
##     queue_free.
##
## Subclass responsibility:
##   Override `_play()` — run the animation, emit `impact_hit(i)` at the right
##   frames, emit `finished`, and queue_free. Do NOT override `_ready()`.
##
## Apply/utility VFX (VoidMarkApply, CorruptionApply, etc.) still extend this
## but set `impact_count = 0` so the controller skips damage gating.
class_name BaseVfx
extends Node2D

signal impact_hit(index: int)  ## Emitted once per impact. Controller awaits this before applying damage.
signal finished                ## Emitted when the visible effect has ended.

## How many impact_hit emissions the controller should await for this VFX.
## 1 = single-hit (default). N = staggered AoE. 0 = apply/utility (no damage gate).
var impact_count: int = 1

## Global time scale — multiplied into every VfxSequence phase duration and
## beat offset. 1.0 = real-time. Set via debug knob or settings.
## Per-sequence override: `seq.time_scale`. Per-phase override: `phase.time_scale(s)`.
static var time_scale: float = 1.0

## Lazily-created sequence runner. Subclasses get one via `sequence()`.
var _sequence: VfxSequence = null

func _ready() -> void:
	_play()

## Subclass entry point. Override this — not _ready.
##
## New-style: build a VfxSequence and call `seq.run([Phase.new(...), ...])`.
## See ArcaneStrikeVFX for the canonical template.
##
## Old-style (still supported): hand-roll the timeline with awaits, emit
## `impact_hit(i)` at the right frame, emit `finished`, and queue_free.
func _play() -> void:
	push_error("BaseVfx._play must be overridden by subclass")
	finished.emit()
	queue_free()

## Get (or lazily create) this VFX's sequence runner. Call from `_play()`.
func sequence() -> VfxSequence:
	if _sequence == null:
		_sequence = VfxSequence.new(self)
	return _sequence

## Shake a node with a real position (BoardSlot, hero panel, or VfxShakeRoot).
## Never pass a CanvasLayer — moving a CanvasLayer.offset shakes every node in
## that layer (including the HUD), and multiple VFX shaking at once fight each
## other. Per-hit shakes should target the slot/panel; full-screen shakes
## should target VfxShakeRoot.
func shake(target: Node, amplitude: float, ticks: int) -> void:
	if target == null or not target.is_inside_tree():
		return
	if target is CanvasLayer:
		push_error("BaseVfx.shake: target is CanvasLayer — shake a Control/Node2D instead")
		return
	await ScreenShakeEffect.shake(target, self, amplitude, ticks)
