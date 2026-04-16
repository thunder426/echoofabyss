## CorruptedDeathSummonVFX.gd
## Special summon VFX for Void-Touched Imps when the "corrupted_death" passive
## is active (Fight 2 — Corrupted Broodlings).
##
## Plays on a BoardSlot after the minion lands, in three phases:
##   Phase 1 — Void Crack   (0.20s): dark-purple vertical slash at slot center
##   Phase 2 — Corruption Bloom (0.40s): green-purple sonic distortion ring
##   Phase 3 — Death Wisps  (0.50s): ghostly particles drift upward and fade
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name CorruptedDeathSummonVFX
extends Node

signal finished

const SHADER_SONIC: Shader = preload("res://combat/effects/sonic_wave.gdshader")

# ── Phase 1: Void Crack ──────────────────────────────────────────────────────
const CRACK_DURATION: float  = 0.20
const CRACK_WIDTH: float     = 4.0
const CRACK_HEIGHT_RATIO: float = 0.7   # fraction of slot height
const CRACK_COLOR: Color     = Color(0.45, 0.12, 0.65, 0.95)  # dark purple

# ── Phase 2: Corruption Bloom ────────────────────────────────────────────────
const BLOOM_DURATION: float     = 0.40
const BLOOM_RING_SCALE: float   = 0.70   # max radius as fraction of slot size
const BLOOM_THICKNESS: float    = 0.07
const BLOOM_STRENGTH: float     = 0.020
const BLOOM_TINT: Color         = Color(0.30, 0.70, 0.25, 0.28)  # sickly green shimmer

# ── Phase 3: Death Wisps ─────────────────────────────────────────────────────
const WISP_COUNT: int        = 6
const WISP_DURATION: float   = 0.50
const WISP_SIZE: Vector2     = Vector2(8.0, 8.0)
const WISP_RISE_PX: float    = 60.0   # how far wisps drift upward
const WISP_SPREAD: float     = 40.0   # horizontal scatter
const WISP_COLORS: Array     = [
	Color(0.40, 0.85, 0.30, 0.70),   # toxic green
	Color(0.55, 0.20, 0.75, 0.65),   # void purple
	Color(0.30, 0.95, 0.40, 0.55),   # bright green
	Color(0.65, 0.15, 0.80, 0.60),   # deep violet
]

var _slot: Control = null
var _host: Node = null  # VfxLayer (CanvasLayer layer 2)


static func create(slot: Control) -> CorruptedDeathSummonVFX:
	var vfx := CorruptedDeathSummonVFX.new()
	vfx._slot = slot
	return vfx


func _ready() -> void:
	_run()


func _run() -> void:
	_host = get_parent()
	if _slot == null or not is_instance_valid(_slot) or _host == null:
		finished.emit()
		queue_free()
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		finished.emit()
		queue_free()
		return

	var slot_center_px: Vector2 = _slot.global_position + _slot.size * 0.5
	var center_uv := Vector2(slot_center_px.x / vp_size.x, slot_center_px.y / vp_size.y)

	# VfxLayer is CanvasLayer layer=2 above UI — SCREEN_TEXTURE captures the
	# full pre-VFX scene when the sonic shader reads it.
	# ── Phase 1: Void Crack — dark-purple vertical slash ─────────────────
	var crack_h: float = _slot.size.y * CRACK_HEIGHT_RATIO
	var crack := ColorRect.new()
	crack.color = CRACK_COLOR
	crack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crack.set_size(Vector2(CRACK_WIDTH, 0.0))
	crack.position = slot_center_px - Vector2(CRACK_WIDTH * 0.5, 0.0)
	crack.pivot_offset = Vector2(CRACK_WIDTH * 0.5, 0.0)
	crack.z_index = 22
	crack.z_as_relative = false
	_host.add_child(crack)

	# Crack tears open from center
	var tw_crack := create_tween().set_parallel(true)
	tw_crack.tween_property(crack, "size:y", crack_h, CRACK_DURATION * 0.6) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw_crack.tween_property(crack, "position:y", slot_center_px.y - crack_h * 0.5, CRACK_DURATION * 0.6) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Glow pulse — brighten then dim
	tw_crack.tween_property(crack, "color:a", 1.0, CRACK_DURATION * 0.3) \
		.set_trans(Tween.TRANS_SINE)
	tw_crack.chain().tween_property(crack, "color:a", 0.0, CRACK_DURATION * 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Width pulse — crack briefly widens then collapses
	tw_crack.tween_property(crack, "size:x", CRACK_WIDTH * 2.5, CRACK_DURATION * 0.4) \
		.set_trans(Tween.TRANS_SINE)
	tw_crack.chain().tween_property(crack, "size:x", 0.0, CRACK_DURATION * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(CRACK_DURATION).timeout
	if not is_inside_tree():
		_cleanup()
		return
	if is_instance_valid(crack):
		crack.queue_free()

	# ── Phase 2: Corruption Bloom — sonic distortion ring ────────────────
	var bloom_rect := ColorRect.new()
	bloom_rect.color = Color(1, 1, 1, 1)  # shader overrides
	bloom_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bloom_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bloom_rect.z_index = 21
	bloom_rect.z_as_relative = false

	var ring_max_px: float = maxf(_slot.size.x, _slot.size.y) * BLOOM_RING_SCALE
	var ring_max_uv: float = ring_max_px / vp_size.y
	var bloom_mat := ShaderMaterial.new()
	bloom_mat.shader = SHADER_SONIC
	bloom_mat.set_shader_parameter("center_uv", center_uv)
	bloom_mat.set_shader_parameter("aspect", vp_size.x / vp_size.y)
	bloom_mat.set_shader_parameter("radius_max", ring_max_uv)
	bloom_mat.set_shader_parameter("thickness", BLOOM_THICKNESS)
	bloom_mat.set_shader_parameter("strength", BLOOM_STRENGTH)
	bloom_mat.set_shader_parameter("tint", BLOOM_TINT)
	bloom_mat.set_shader_parameter("progress", 0.0)
	bloom_mat.set_shader_parameter("alpha_multiplier", 1.0)
	bloom_rect.material = bloom_mat
	_host.add_child(bloom_rect)

	var tw_bloom := create_tween().set_parallel(true)
	tw_bloom.tween_method(func(p: float) -> void:
			bloom_mat.set_shader_parameter("progress", p),
			0.0, 1.0, BLOOM_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw_bloom.tween_method(func(a: float) -> void:
			bloom_mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, BLOOM_DURATION * 0.3
		).set_delay(BLOOM_DURATION * 0.7).set_trans(Tween.TRANS_SINE)

	# Spawn death wisps during the bloom (overlapping phases for fluidity)
	_spawn_wisps(slot_center_px)

	await get_tree().create_timer(BLOOM_DURATION).timeout
	if not is_inside_tree():
		_cleanup()
		return
	if is_instance_valid(bloom_rect):
		bloom_rect.queue_free()

	# Wait for wisps to finish (they run independently for WISP_DURATION)
	await get_tree().create_timer(WISP_DURATION * 0.5).timeout

	_cleanup()


func _spawn_wisps(center: Vector2) -> void:
	for i in WISP_COUNT:
		var wisp := ColorRect.new()
		var color_idx: int = i % WISP_COLORS.size()
		wisp.color = WISP_COLORS[color_idx]
		wisp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wisp.set_size(WISP_SIZE)
		# Scatter around slot center
		var offset_x: float = (randf() - 0.5) * WISP_SPREAD
		var offset_y: float = (randf() - 0.5) * WISP_SPREAD * 0.4
		wisp.position = center + Vector2(offset_x, offset_y) - WISP_SIZE * 0.5
		wisp.pivot_offset = WISP_SIZE * 0.5
		wisp.z_index = 23
		wisp.z_as_relative = false
		_host.add_child(wisp)

		# Each wisp drifts upward with slight lateral wobble, shrinks, and fades
		var drift_x: float = (randf() - 0.5) * 20.0
		var rise: float = WISP_RISE_PX * (0.6 + randf() * 0.4)
		var delay: float = randf() * 0.12   # stagger start
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


func _cleanup() -> void:
	finished.emit()
	queue_free()
