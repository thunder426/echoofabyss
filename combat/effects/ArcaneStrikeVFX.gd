## ArcaneStrikeVFX.gd
## Impact VFX for Arcane Strike — a quick, precise arcane fracture stamped onto
## the target. No projectile phase; the effect appears directly at impact.
##
## Layers:
##   1. Crack stamp (additive fracture texture — the main visual)
##   2. Light screen shake (listener on `slam` beat)
##
## Spawn via VfxController — do not parent manually.
class_name ArcaneStrikeVFX
extends BaseVfx

const TEX_CRACK: Texture2D = preload("res://assets/art/fx/arcane_strike_impact.png")

const COLOR_BRIGHT: Color = Color(0.40, 0.55, 1.0, 0.95)
const CRACK_SIZE: float = 160.0

const SLAM_DURATION: float  = 0.06
const HOLD_DURATION: float  = 0.30
const FADE_DURATION: float  = 0.25

const SHAKE_AMPLITUDE: float = 5.0
const SHAKE_TICKS: int       = 6

var _target_slot: BoardSlot
var _stamp: Sprite2D = null
var _target_scale: float = 1.0


static func create(target_slot: BoardSlot) -> ArcaneStrikeVFX:
	var vfx := ArcaneStrikeVFX.new()
	vfx._target_slot = target_slot
	vfx.z_index = 200
	return vfx


func _play() -> void:
	if _target_slot == null:
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return
	global_position = _target_slot.global_position + _target_slot.size * 0.5
	AudioManager.play_sfx("res://assets/audio/sfx/spells/arcane_strike_impact.wav", -8.0)

	var seq := sequence()
	seq.on("slam", _do_shake)
	seq.run([
		# Slam in — crack appears, scale + alpha overshoot. Damage syncs
		# to end of slam (just before hold) — same beat as old tween_callback.
		VfxPhase.new("slam", SLAM_DURATION, _build_slam) \
			.emits_at_end("slam") \
			.emits_at_end(VfxSequence.RESERVED_IMPACT_HIT),
		VfxPhase.new("hold", HOLD_DURATION, Callable()),
		VfxPhase.new("fade", FADE_DURATION, _build_fade),
	])


func _build_slam(duration: float) -> void:
	_stamp = Sprite2D.new()
	_stamp.texture = TEX_CRACK
	var tex_size: float = maxf(_stamp.texture.get_width(), _stamp.texture.get_height())
	_target_scale = CRACK_SIZE / maxf(tex_size, 1.0)
	# Slam in slightly oversized, then settle.
	_stamp.scale = Vector2.ONE * (_target_scale * 1.25)
	_stamp.rotation = randf_range(-0.20, 0.20)
	_stamp.modulate = Color(COLOR_BRIGHT.r, COLOR_BRIGHT.g, COLOR_BRIGHT.b, 0.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_stamp.material = mat
	add_child(_stamp)

	var alpha_dur: float = duration * 0.66  # 0.04 of 0.06 — same ratio as old code
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_stamp, "modulate:a", COLOR_BRIGHT.a, alpha_dur) \
		.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_stamp, "scale", Vector2.ONE * _target_scale, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_fade(duration: float) -> void:
	if _stamp == null or not is_instance_valid(_stamp):
		return
	var tw := create_tween()
	tw.tween_property(_stamp, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _do_shake() -> void:
	if _target_slot == null or not _target_slot.is_inside_tree():
		return
	ScreenShakeEffect.shake(_target_slot, _target_slot, SHAKE_AMPLITUDE, SHAKE_TICKS)
