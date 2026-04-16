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
	var pos_variant: Variant = target.get("position")
	if pos_variant == null:
		return
	var base_pos: Vector2 = pos_variant
	for i in ticks:
		if not target.is_inside_tree() or not scene.is_inside_tree():
			target.set("position", base_pos)
			return
		var decay: float = 1.0 - (float(i) / float(ticks))
		var amp: float = amplitude * decay
		var offset := Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		target.set("position", base_pos + offset)
		await scene.get_tree().create_timer(interval).timeout
	target.set("position", base_pos)
