## CorruptionApplyVFX.gd
## Per-minion VFX for applying a Corruption stack.
##
## Plays on a single BoardSlot in two phases:
##   Phase 1 — Stamp (0.45s):  corruption icon drops onto the card center,
##                             holds, then fades out
##   Phase 2 — Impact (0.35s): Void-Screech-style sonic distortion pulse with
##                             a barely-there dark-emerald shimmer
##
## Stat changes (BuffSystem.apply) are NOT driven by this VFX — the caller
## applies corruption BEFORE spawning so the ATK drop lines up with the
## triggering event (plague wave arrival, on-summon, etc.).
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name CorruptionApplyVFX
extends BaseVfx

const SHADER_SONIC: Shader      = preload("res://combat/effects/sonic_wave.gdshader")
const TEX_CORRUPTION: Texture2D = preload("res://assets/art/icons/icon_corruption.png")

# Stamp phase
const STAMP_FADE_IN: float   = 0.10
const STAMP_HOLD: float      = 0.20
const STAMP_FADE_OUT: float  = 0.15
const STAMP_DURATION: float  = STAMP_FADE_IN + STAMP_HOLD + STAMP_FADE_OUT
const STAMP_SIZE_PX: float   = 96.0
const STAMP_TINT: Color      = Color(1.0, 1.0, 1.0, 1.0)

# Impact phase
const IMPACT_DURATION: float    = 0.35
const IMPACT_RING_SCALE: float  = 0.85
const IMPACT_TINT: Color        = Color(0.22, 0.55, 0.28, 0.18)

var _slot: Control = null
var _slot_center: Vector2 = Vector2.ZERO
var _vp_size: Vector2 = Vector2.ZERO


static func create(slot: Control) -> CorruptionApplyVFX:
	var vfx := CorruptionApplyVFX.new()
	vfx._slot = slot
	vfx.impact_count = 0
	return vfx


func _play() -> void:
	if _slot == null or not is_instance_valid(_slot) or get_parent() == null:
		finished.emit()
		queue_free()
		return
	_vp_size = get_viewport().get_visible_rect().size
	if _vp_size.x <= 0.0 or _vp_size.y <= 0.0:
		finished.emit()
		queue_free()
		return
	_slot_center = _slot.global_position + _slot.size * 0.5

	AudioManager.play_sfx("res://assets/audio/sfx/spells/abyssal_plague_hit_low.wav", -6.0)

	sequence().run([
		VfxPhase.new("stamp",  STAMP_DURATION,  _build_stamp),
		VfxPhase.new("impact", IMPACT_DURATION, _build_impact),
	])


func _build_stamp(_duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var stamp := TextureRect.new()
	stamp.texture       = TEX_CORRUPTION
	stamp.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	stamp.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stamp.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	stamp.set_size(Vector2(STAMP_SIZE_PX, STAMP_SIZE_PX))
	stamp.position      = _slot_center - Vector2(STAMP_SIZE_PX, STAMP_SIZE_PX) * 0.5
	stamp.pivot_offset  = Vector2(STAMP_SIZE_PX, STAMP_SIZE_PX) * 0.5
	stamp.modulate      = Color(STAMP_TINT.r, STAMP_TINT.g, STAMP_TINT.b, 0.0)
	stamp.scale         = Vector2(1.55, 1.55)
	stamp.z_index       = 22
	stamp.z_as_relative = false
	host.add_child(stamp)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(stamp, "modulate:a", 1.0, STAMP_FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(stamp, "scale", Vector2.ONE, STAMP_FADE_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(stamp, "modulate:a", 1.0, STAMP_HOLD)
	tw.chain().tween_property(stamp, "modulate:a", 0.0, STAMP_FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(stamp, "scale", Vector2(1.20, 1.20), STAMP_FADE_OUT).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(stamp.queue_free)


func _build_impact(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var ring_rect := ColorRect.new()
	ring_rect.color = Color(1, 1, 1, 1)
	ring_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring_rect.z_index = 21
	ring_rect.z_as_relative = false

	var center_uv := Vector2(_slot_center.x / _vp_size.x, _slot_center.y / _vp_size.y)
	var ring_max_radius_px: float = maxf(_slot.size.x, _slot.size.y) * IMPACT_RING_SCALE
	var ring_max_radius_uv: float = ring_max_radius_px / _vp_size.y
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = SHADER_SONIC
	ring_mat.set_shader_parameter("center_uv", center_uv)
	ring_mat.set_shader_parameter("aspect", _vp_size.x / _vp_size.y)
	ring_mat.set_shader_parameter("radius_max", ring_max_radius_uv)
	ring_mat.set_shader_parameter("thickness", 0.055)
	ring_mat.set_shader_parameter("strength", 0.016)
	ring_mat.set_shader_parameter("tint", IMPACT_TINT)
	ring_mat.set_shader_parameter("progress", 0.0)
	ring_mat.set_shader_parameter("alpha_multiplier", 1.0)
	ring_rect.material = ring_mat
	host.add_child(ring_rect)

	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			ring_mat.set_shader_parameter("progress", p),
			0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			ring_mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, duration * 0.35
		).set_delay(duration * 0.65).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(ring_rect.queue_free)
