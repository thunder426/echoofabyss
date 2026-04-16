## OnDeathIconVFX.gd
## Generic on-death icon stamp that plays on a board slot after a minion with
## on-death effects dies.  Shows the on-death skull icon at the slot center,
## holds briefly, then fades out.
##
## The `finished` signal fires after the icon disappears — callers should
## resolve on-death effects (damage, summons, etc.) only after awaiting it.
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name OnDeathIconVFX
extends Node

signal finished

const TEX_ON_DEATH: Texture2D = preload("res://assets/art/icons/icon_on_death.png")

# Timing
const FADE_IN: float   = 0.12
const HOLD: float      = 0.40
const FADE_OUT: float  = 0.25

# Visuals
const ICON_SIZE_PX: float = 64.0
const ICON_COLOR: Color   = Color(0.85, 0.55, 1.0, 1.0)  # soft purple tint

var _pos: Vector2    = Vector2.ZERO
var _size: Vector2   = Vector2.ZERO


static func create(slot_pos: Vector2, slot_size: Vector2) -> OnDeathIconVFX:
	var vfx := OnDeathIconVFX.new()
	vfx._pos  = slot_pos
	vfx._size = slot_size
	return vfx


func _ready() -> void:
	_run()


func _run() -> void:
	# `host` = VfxLayer (CanvasLayer layer 2, above UI).
	var host: Node = get_parent()
	if host == null or not is_inside_tree():
		finished.emit()
		queue_free()
		return

	var center: Vector2 = _pos + _size * 0.5

	# ── Icon — on-death skull ─────────────────────────────────────────────
	var icon := TextureRect.new()
	icon.texture       = TEX_ON_DEATH
	icon.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	icon.set_size(Vector2(ICON_SIZE_PX, ICON_SIZE_PX))
	icon.position      = center - Vector2(ICON_SIZE_PX, ICON_SIZE_PX) * 0.5
	icon.pivot_offset  = Vector2(ICON_SIZE_PX, ICON_SIZE_PX) * 0.5
	icon.modulate      = Color(ICON_COLOR.r, ICON_COLOR.g, ICON_COLOR.b, 0.0)
	icon.scale         = Vector2(1.6, 1.6)
	icon.z_index       = 25
	icon.z_as_relative = false
	host.add_child(icon)

	# ── Fade in + scale down (slam-in) ───────────────────────────────────
	var tw_in := create_tween().set_parallel(true)
	tw_in.tween_property(icon, "modulate:a", 1.0, FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_in.tween_property(icon, "scale", Vector2.ONE, FADE_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(FADE_IN).timeout
	if not is_inside_tree():
		_cleanup()
		return

	# ── Hold with gentle pulse ────────────────────────────────────────────
	var tw_pulse := create_tween().set_loops(2)
	tw_pulse.tween_property(icon, "scale", Vector2(1.08, 1.08), HOLD * 0.25) \
		.set_trans(Tween.TRANS_SINE)
	tw_pulse.tween_property(icon, "scale", Vector2.ONE, HOLD * 0.25) \
		.set_trans(Tween.TRANS_SINE)

	await get_tree().create_timer(HOLD).timeout
	if not is_inside_tree():
		_cleanup()
		return

	# ── Fade out + slight scale up ────────────────────────────────────────
	var tw_out := create_tween().set_parallel(true)
	tw_out.tween_property(icon, "modulate:a", 0.0, FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw_out.tween_property(icon, "scale", Vector2(1.25, 1.25), FADE_OUT) \
		.set_trans(Tween.TRANS_SINE)

	await get_tree().create_timer(FADE_OUT).timeout

	_cleanup()


func _cleanup() -> void:
	finished.emit()
	queue_free()
