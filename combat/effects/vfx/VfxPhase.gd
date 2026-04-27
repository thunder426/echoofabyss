## VfxPhase.gd
## One phase of a VfxSequence — a named, time-bounded slice of a VFX timeline.
##
## A phase carries:
##   - `name`        : human label, used by the watchdog warning
##   - `duration`    : how long the phase runs (before scaling)
##   - `builder`     : Callable(effective_duration: float) -> void, called once
##                     when the phase begins. Spawns sprites/tweens/particles.
##                     Receives the post-scale duration so internal tweens
##                     match the phase length.
##   - `beats`       : Array of {beat: String, t_norm: float} scheduled to
##                     fire at t_norm * effective_duration into the phase
##   - `time_scale_override`: per-phase multiplier; -1.0 means inherit
##
## Methods are chainable:
##   Phase.new("burst", 0.9, _build_burst).emits("impact_hit", 0.6).time_scale(0.5)
class_name VfxPhase
extends RefCounted

var name: String = ""
var duration: float = 0.0
var builder: Callable = Callable()
var beats: Array = []  # Array[{beat: String, t_norm: float}]
var time_scale_override: float = -1.0  # -1.0 = inherit sequence/global

func _init(p_name: String = "", p_duration: float = 0.0, p_builder: Callable = Callable()) -> void:
	name = p_name
	duration = p_duration
	builder = p_builder

## Schedule a beat to fire at `t_norm` (0..1) of this phase's duration.
## t_norm = 0.0 fires at phase start, 1.0 fires at phase end.
## The reserved beat name "impact_hit" also forwards to the public
## BaseVfx.impact_hit signal (with index = number of impacts emitted so far).
func emits(beat: String, t_norm: float = 0.0) -> VfxPhase:
	beats.append({"beat": beat, "t_norm": clampf(t_norm, 0.0, 1.0)})
	return self

## Shorthand for `emits(beat, 0.0)`.
func emits_at_start(beat: String) -> VfxPhase:
	return emits(beat, 0.0)

## Shorthand for `emits(beat, 1.0)`.
func emits_at_end(beat: String) -> VfxPhase:
	return emits(beat, 1.0)

## Override the time scale for this phase only. Use sparingly — global or
## sequence-level scaling covers most cases.
func time_scale(s: float) -> VfxPhase:
	time_scale_override = s
	return self
