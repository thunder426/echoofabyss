## VfxSequence.gd
## Declarative timeline runner for a VFX. Owns the state machine that every VFX
## used to hand-roll: phase iteration, await timer, is_inside_tree() guard,
## impact_hit emission, and final finished/queue_free.
##
## Two ways to express parallelism:
##   1. Sequential phases — `Phase.new(...)` entries in `run()`'s array.
##   2. Beat listeners    — `seq.on(beat, cb)` subscribes; phases or builders
##      fire the beat (`Phase.emits(beat, t_norm)` or `seq.emit_beat(beat)`)
##      and every listener runs in registration order.
##
## Beat names are local to one VFX run. The reserved name "impact_hit" is also
## forwarded to the host VFX's public `impact_hit(index)` signal so the
## VfxController's damage-sync contract is preserved without special-casing.
##
## Speed scaling: every phase duration and beat offset is multiplied by
## `effective_scale = BaseVfx.time_scale * sequence.time_scale * (phase.override if set)`.
## Builders receive the post-scale duration as their argument so internal
## tweens scale with the phase.
##
## Watchdog: in debug builds, a timer of (sum_of_durations + 2s) force-finishes
## the sequence if it stalls (e.g. an awaiting listener deadlocked). Logs the
## phase it was stuck on. Disable per-sequence with `disable_watchdog()`.
class_name VfxSequence
extends RefCounted

const RESERVED_IMPACT_HIT := "impact_hit"

var _host: BaseVfx = null            # the VFX that owns this sequence
var _listeners: Dictionary = {}       # beat: String -> Array[Callable]
var _impact_count: int = 0            # how many "impact_hit" beats have fired
var _aborted: bool = false
var _completed: bool = false
var _watchdog_enabled: bool = true
var _early_finished: bool = false     # `finished` already emitted via unblock_at
var _unblock_beats: Array = []        # beats that early-emit `finished`

## Sequence-level scale multiplier. Stacks with BaseVfx.time_scale and
## per-phase override.
var time_scale: float = 1.0

func _init(host: BaseVfx) -> void:
	_host = host

# ─────────────────────────────────────────────────────────────────────────────
# Listener registration
# ─────────────────────────────────────────────────────────────────────────────

## Subscribe a Callable to a named beat. Multiple listeners on the same beat
## fire in registration order. Listeners must not depend on each other —
## if they do, collapse them into one builder/listener.
func on(beat: String, cb: Callable) -> VfxSequence:
	if not _listeners.has(beat):
		_listeners[beat] = []
	(_listeners[beat] as Array).append(cb)
	return self

## Manually fire a beat from inside a builder. Use when the trigger moment is
## geometric or state-dependent (e.g. "wave reached target") instead of a
## fixed normalized time.
func emit_beat(beat: String, payload: Variant = null) -> void:
	_fire_beat(beat, payload)

## Disable the debug stuck-sequence watchdog for this run. Use only for VFX
## that legitimately exceed `total_duration + 2s` after scaling.
func disable_watchdog() -> VfxSequence:
	_watchdog_enabled = false
	return self

## Emit the host's public `finished` signal as soon as the named beat fires,
## but keep running the remaining phases (visuals continue trailing).
## queue_free still happens after the last phase ends.
##
## Use when game flow should resume at impact while the trailing wave/flash
## continues — same pattern as old VoidScreech that emitted finished early.
func unblock_at(beat: String) -> VfxSequence:
	if not _unblock_beats.has(beat):
		_unblock_beats.append(beat)
	return self

# ─────────────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────────────

## Execute the phase list. Called from BaseVfx subclass's `_play()`.
## On completion (or abort), emits the host VFX's `finished` signal and
## queue_frees the host. Safe to call exactly once per VFX.
func run(phases: Array) -> void:
	if _completed:
		push_error("VfxSequence.run called twice")
		return

	# Compute total duration up-front for the watchdog.
	var total_scaled: float = 0.0
	for p in phases:
		var ph: VfxPhase = p as VfxPhase
		total_scaled += ph.duration * _phase_scale(ph)

	if _watchdog_enabled and total_scaled > 0.0:
		_arm_watchdog(total_scaled + 2.0, phases)

	for p in phases:
		var ph: VfxPhase = p as VfxPhase
		if _aborted:
			break
		await _run_phase(ph)

	_finish()

func _run_phase(phase: VfxPhase) -> void:
	if _host == null or not _host.is_inside_tree():
		_aborted = true
		return

	var effective: float = phase.duration * _phase_scale(phase)

	# 1. Builder — receives the post-scale duration so tweens match.
	if phase.builder.is_valid():
		# Builder may be 0-arg or 1-arg. Try 1-arg first; fall back if signature
		# doesn't match. (Callable.call always passes args; mismatch errors
		# are caught by GDScript at call time, so we just try with duration.)
		phase.builder.call(effective)

	# 2. Schedule beats. t_norm=0 fires immediately, t_norm=1 fires at end.
	var pending_end_beats: Array = []
	for entry in phase.beats:
		var beat_name: String = entry["beat"]
		var t_norm: float = entry["t_norm"]
		if t_norm <= 0.0:
			_fire_beat(beat_name)
		elif t_norm >= 1.0:
			pending_end_beats.append(beat_name)
		else:
			_schedule_mid_beat(beat_name, effective * t_norm)

	# 3. Wait the phase out.
	if effective > 0.0:
		await _host.get_tree().create_timer(effective).timeout

	# 4. Tree check.
	if _host == null or not _host.is_inside_tree():
		_aborted = true
		return

	# 5. End-of-phase beats.
	for beat_name in pending_end_beats:
		_fire_beat(beat_name)

func _schedule_mid_beat(beat: String, delay: float) -> void:
	if _host == null or not _host.is_inside_tree():
		return
	var timer := _host.get_tree().create_timer(delay)
	var seq := self
	timer.timeout.connect(func() -> void:
		if seq != null and not seq._aborted and not seq._completed:
			seq._fire_beat(beat))

func _fire_beat(beat: String, payload: Variant = null) -> void:
	# Reserved: impact_hit also forwards to the host's public signal.
	if beat == RESERVED_IMPACT_HIT and _host != null and is_instance_valid(_host):
		_host.impact_hit.emit(_impact_count)
		_impact_count += 1

	# Unblock: emit `finished` early but keep running.
	if _unblock_beats.has(beat) and not _early_finished:
		_early_finished = true
		if _host != null and is_instance_valid(_host):
			_host.finished.emit()

	var listeners: Array = _listeners.get(beat, [])
	for cb in listeners:
		var c: Callable = cb
		if c.is_valid():
			# Listeners are fire-and-forget. If a listener wants to do async
			# work, it can; sequence does not await it.
			if payload == null:
				c.call()
			else:
				c.call(payload)

func _phase_scale(phase: VfxPhase) -> float:
	var s: float = BaseVfx.time_scale * time_scale
	if phase.time_scale_override > 0.0:
		s *= phase.time_scale_override
	return s

func _finish() -> void:
	if _completed:
		return
	_completed = true
	if _host == null or not is_instance_valid(_host):
		return
	# If `finished` was already emitted early via unblock_at, don't double-emit.
	if not _early_finished:
		_host.finished.emit()
	_host.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
# Watchdog (debug builds only)
# ─────────────────────────────────────────────────────────────────────────────

func _arm_watchdog(window: float, phases: Array) -> void:
	if not OS.is_debug_build():
		return
	if _host == null or not _host.is_inside_tree():
		return
	var seq := self
	var phase_names: Array = []
	for p in phases:
		phase_names.append((p as VfxPhase).name)
	var timer := _host.get_tree().create_timer(window)
	timer.timeout.connect(func() -> void:
		if seq == null or seq._completed:
			return
		push_warning("VfxSequence watchdog: stuck after %.2fs (phases: %s, host: %s)" % [
			window, phase_names, seq._host.get_class() if seq._host else "<null>"
		])
		seq._aborted = true
		seq._finish())
