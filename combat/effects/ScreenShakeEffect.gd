## ScreenShakeEffect.gd
## Reusable positional shake for any Node with a `position` property
## (Control, Node2D, or a UI container like $UI).
##
## Stores the target's original position, applies decaying random offsets
## for `ticks` iterations, then restores. Safe to await — returns when the
## shake finishes or the target leaves the tree.
##
## Usage:
##   await ScreenShakeEffect.shake(target_panel, self, 16.0, 12)
class_name ScreenShakeEffect
extends RefCounted

const DEFAULT_INTERVAL: float = 0.025

static func shake(target: Node, scene: Node, amplitude: float, ticks: int, interval: float = DEFAULT_INTERVAL) -> void:
	if target == null or scene == null or ticks <= 0 or amplitude <= 0.0:
		return
	if not (target is Control or target is Node2D):
		return
	# Share a single resting base across concurrent shakes on the same target.
	# Without this, a shake that starts while another is mid-loop would capture
	# the already-offset position as its baseline and restore to that wrong
	# spot on exit — leaving the target permanently displaced.
	var base_pos: Vector2
	if target.has_meta("_shake_base_pos"):
		base_pos = target.get_meta("_shake_base_pos")
	else:
		base_pos = _position_of(target)
		target.set_meta("_shake_base_pos", base_pos)
	target.set_meta("_shake_active", int(target.get_meta("_shake_active", 0)) + 1)
	for i in ticks:
		# Each tick awaits a timer; the scene (and the target) may be freed meanwhile.
		if not is_instance_valid(target) or not is_instance_valid(scene) \
				or not target.is_inside_tree() or not scene.is_inside_tree():
			_end_shake(target, base_pos)
			return
		var decay: float = 1.0 - (float(i) / float(ticks))
		var amp: float = amplitude * decay
		var offset := Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		_set_position(target, base_pos + offset)
		await scene.get_tree().create_timer(interval).timeout
	_end_shake(target, base_pos)


static func _end_shake(target: Node, base_pos: Vector2) -> void:
	if not is_instance_valid(target):
		return
	var remaining: int = int(target.get_meta("_shake_active", 1)) - 1
	if remaining <= 0:
		target.remove_meta("_shake_active")
		target.remove_meta("_shake_base_pos")
		_set_position(target, base_pos)
	else:
		target.set_meta("_shake_active", remaining)


## `position` of a Control or Node2D (the two shakeable kinds).
static func _position_of(target: Node) -> Vector2:
	return (target as Control).position if target is Control else (target as Node2D).position


static func _set_position(target: Node, pos: Vector2) -> void:
	if target is Control:
		(target as Control).position = pos
	elif target is Node2D:
		(target as Node2D).position = pos
