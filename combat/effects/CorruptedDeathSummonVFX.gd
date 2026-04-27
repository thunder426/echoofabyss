## CorruptedDeathSummonVFX.gd
## Special summon VFX for Void-Touched Imps when the "corrupted_death" passive
## is active (Fight 2 — Corrupted Broodlings).
##
## Phases:
##   1. crack (0.20s) — dark-purple vertical slash at slot center
##   2. bloom (0.40s) — green-purple sonic distortion ring; wisps spawn at start
##   3. wisp_tail (0.25s) — let trailing wisps finish drifting before queue_free
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name CorruptedDeathSummonVFX
extends BaseVfx

const SHADER_SONIC: Shader = preload("res://combat/effects/sonic_wave.gdshader")

# Phase 1
const CRACK_DURATION: float  = 0.20
const CRACK_WIDTH: float     = 4.0
const CRACK_HEIGHT_RATIO: float = 0.7
const CRACK_COLOR: Color     = Color(0.45, 0.12, 0.65, 0.95)

# Phase 2
const BLOOM_DURATION: float     = 0.40
const BLOOM_RING_SCALE: float   = 0.70
const BLOOM_THICKNESS: float    = 0.07
const BLOOM_STRENGTH: float     = 0.020
const BLOOM_TINT: Color         = Color(0.30, 0.70, 0.25, 0.28)

# Phase 3
const WISP_TAIL_DURATION: float = 0.25
const WISP_COUNT: int        = 6
const WISP_DURATION: float   = 0.50
const WISP_SIZE: Vector2     = Vector2(8.0, 8.0)
const WISP_RISE_PX: float    = 60.0
const WISP_SPREAD: float     = 40.0
const WISP_COLORS: Array     = [
	Color(0.40, 0.85, 0.30, 0.70),
	Color(0.55, 0.20, 0.75, 0.65),
	Color(0.30, 0.95, 0.40, 0.55),
	Color(0.65, 0.15, 0.80, 0.60),
]

var _slot: Control = null
var _slot_center: Vector2 = Vector2.ZERO
var _vp_size: Vector2 = Vector2.ZERO
var _crack: ColorRect = null
var _bloom_rect: ColorRect = null


static func create(slot: Control) -> CorruptedDeathSummonVFX:
	var vfx := CorruptedDeathSummonVFX.new()
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

	sequence().run([
		VfxPhase.new("crack",     CRACK_DURATION,     _build_crack),
		VfxPhase.new("bloom",     BLOOM_DURATION,     _build_bloom_and_wisps),
		VfxPhase.new("wisp_tail", WISP_TAIL_DURATION, Callable()),
	])


func _build_crack(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var crack_h: float = _slot.size.y * CRACK_HEIGHT_RATIO
	_crack = ColorRect.new()
	_crack.color = CRACK_COLOR
	_crack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crack.set_size(Vector2(CRACK_WIDTH, 0.0))
	_crack.position = _slot_center - Vector2(CRACK_WIDTH * 0.5, 0.0)
	_crack.pivot_offset = Vector2(CRACK_WIDTH * 0.5, 0.0)
	_crack.z_index = 22
	_crack.z_as_relative = false
	host.add_child(_crack)

	var crack := _crack
	var tw := create_tween().set_parallel(true)
	tw.tween_property(crack, "size:y", crack_h, duration * 0.6) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(crack, "position:y", _slot_center.y - crack_h * 0.5, duration * 0.6) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(crack, "color:a", 1.0, duration * 0.3) \
		.set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(crack, "color:a", 0.0, duration * 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(crack, "size:x", CRACK_WIDTH * 2.5, duration * 0.4) \
		.set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(crack, "size:x", 0.0, duration * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(crack.queue_free)


func _build_bloom_and_wisps(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return

	# Bloom — sonic distortion ring
	_bloom_rect = ColorRect.new()
	_bloom_rect.color = Color(1, 1, 1, 1)
	_bloom_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bloom_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bloom_rect.z_index = 21
	_bloom_rect.z_as_relative = false

	var center_uv := Vector2(_slot_center.x / _vp_size.x, _slot_center.y / _vp_size.y)
	var ring_max_px: float = maxf(_slot.size.x, _slot.size.y) * BLOOM_RING_SCALE
	var ring_max_uv: float = ring_max_px / _vp_size.y
	var bloom_mat := ShaderMaterial.new()
	bloom_mat.shader = SHADER_SONIC
	bloom_mat.set_shader_parameter("center_uv", center_uv)
	bloom_mat.set_shader_parameter("aspect", _vp_size.x / _vp_size.y)
	bloom_mat.set_shader_parameter("radius_max", ring_max_uv)
	bloom_mat.set_shader_parameter("thickness", BLOOM_THICKNESS)
	bloom_mat.set_shader_parameter("strength", BLOOM_STRENGTH)
	bloom_mat.set_shader_parameter("tint", BLOOM_TINT)
	bloom_mat.set_shader_parameter("progress", 0.0)
	bloom_mat.set_shader_parameter("alpha_multiplier", 1.0)
	_bloom_rect.material = bloom_mat
	host.add_child(_bloom_rect)

	var bloom := _bloom_rect
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			bloom_mat.set_shader_parameter("progress", p),
			0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			bloom_mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, duration * 0.3
		).set_delay(duration * 0.7).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(bloom.queue_free)

	# Wisps spawn at bloom start; each lives for ~WISP_DURATION.
	_spawn_wisps()


func _spawn_wisps() -> void:
	var host: Node = get_parent()
	if host == null:
		return
	for i in WISP_COUNT:
		var wisp := ColorRect.new()
		var color_idx: int = i % WISP_COLORS.size()
		wisp.color = WISP_COLORS[color_idx]
		wisp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wisp.set_size(WISP_SIZE)
		var offset_x: float = (randf() - 0.5) * WISP_SPREAD
		var offset_y: float = (randf() - 0.5) * WISP_SPREAD * 0.4
		wisp.position = _slot_center + Vector2(offset_x, offset_y) - WISP_SIZE * 0.5
		wisp.pivot_offset = WISP_SIZE * 0.5
		wisp.z_index = 23
		wisp.z_as_relative = false
		host.add_child(wisp)

		var drift_x: float = (randf() - 0.5) * 20.0
		var rise: float = WISP_RISE_PX * (0.6 + randf() * 0.4)
		var delay: float = randf() * 0.12
		var dur: float = WISP_DURATION * (0.7 + randf() * 0.3)

		var tw := wisp.create_tween().set_parallel(true)
		tw.tween_property(wisp, "position:y", wisp.position.y - rise, dur) \
			.set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(wisp, "position:x", wisp.position.x + drift_x, dur) \
			.set_delay(delay).set_trans(Tween.TRANS_SINE)
		tw.tween_property(wisp, "modulate:a", 0.0, dur * 0.6) \
			.set_delay(delay + dur * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(wisp, "scale", Vector2(0.3, 0.3), dur) \
			.set_delay(delay).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_callback(wisp.queue_free)
