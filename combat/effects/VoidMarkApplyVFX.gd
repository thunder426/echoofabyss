## VoidMarkApplyVFX.gd
## Fire-and-forget VFX for applying Void Mark stacks.
##
## Shows the void-mark icon stamp centered on the enemy hero frame,
## drops in, holds briefly, then fades out. Includes an initial delay
## so the stamp appears after on-hit VFX (projectile impacts, etc.).
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name VoidMarkApplyVFX
extends BaseVfx

const TEX_VOIDMARK: Texture2D = preload("res://assets/art/icons/icon_voidmark.png")

const INITIAL_DELAY: float   = 0.30
const STAMP_FADE_IN: float   = 0.12
const STAMP_HOLD: float      = 0.22
const STAMP_FADE_OUT: float  = 0.18
const STAMP_TOTAL: float     = STAMP_FADE_IN + STAMP_HOLD + STAMP_FADE_OUT
const STAMP_SIZE_PX: float   = 112.0

var _target: Control = null


static func create(target: Control) -> VoidMarkApplyVFX:
	var vfx := VoidMarkApplyVFX.new()
	vfx._target = target
	vfx.impact_count = 0
	return vfx


func _play() -> void:
	if _target == null or not is_instance_valid(_target) or get_parent() == null:
		finished.emit()
		queue_free()
		return

	sequence().run([
		# Empty builder — just lets on-hit VFX settle before the stamp drops.
		VfxPhase.new("delay", INITIAL_DELAY, Callable()),
		VfxPhase.new("stamp", STAMP_TOTAL,   _build_stamp),
	])


func _build_stamp(_duration: float) -> void:
	var host: Node = get_parent()
	if host == null or not is_instance_valid(_target):
		return
	var target_center: Vector2 = _target.global_position + _target.size * 0.5

	var stamp := TextureRect.new()
	stamp.texture       = TEX_VOIDMARK
	stamp.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	stamp.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stamp.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	stamp.set_size(Vector2(STAMP_SIZE_PX, STAMP_SIZE_PX))
	stamp.position      = target_center - Vector2(STAMP_SIZE_PX, STAMP_SIZE_PX) * 0.5
	stamp.pivot_offset  = Vector2(STAMP_SIZE_PX, STAMP_SIZE_PX) * 0.5
	stamp.modulate      = Color(1.0, 1.0, 1.0, 0.0)
	stamp.scale         = Vector2(1.5, 1.5)
	stamp.z_index       = 22
	stamp.z_as_relative = false
	host.add_child(stamp)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(stamp, "modulate:a", 1.0, STAMP_FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(stamp, "scale", Vector2.ONE, STAMP_FADE_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(stamp, "modulate:a", 1.0, STAMP_HOLD)
	tw.chain().tween_property(stamp, "modulate:a", 0.0, STAMP_FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(stamp, "scale", Vector2(1.15, 1.15), STAMP_FADE_OUT) \
		.set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(stamp.queue_free)
