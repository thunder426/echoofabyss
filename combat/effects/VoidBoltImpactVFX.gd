## VoidBoltImpactVFX.gd
## Controlled void detonation at impact point — 6-layer volumetric explosion
## designed to feel 3D through depth layering, perspective, and screen distortion.
##
## Layers (all fire on the single "burst" phase — the explosion is composite,
## not phased; layers stagger via per-tween delays inside the builder):
##   1. Ground shadow (dark ellipse — anchors volume to surface)
##   2. Screen distortion shockwave (sonic_wave shader — fake parallax)
##   3. Core flash (additive glow — the ignition point)
##   4. Perspective shockwave ring (Y-squashed donut — implies sphere)
##   5. Volumetric body (3 staggered glow sprites — back/mid/front depth)
##   6. Two-tier particles (hot ejecta + slow smoke wisps)
##
## Note: this VFX is shipped at 2.5× slow-mo via the per-sequence time_scale
## (the original DEBUG_TIME_SCALE was always-on). BaseVfx.time_scale still
## composes on top, so the global debug knob keeps working.
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name VoidBoltImpactVFX
extends BaseVfx

const TEX_GLOW: Texture2D = preload("res://assets/art/fx/glow_soft.png")
const SHADER_SONIC: Shader = preload("res://combat/effects/sonic_wave.gdshader")

# ── Colors ───────────────────────────────────────────────────────────────────
const COLOR_CORE_FLASH: Color   = Color(1.0, 0.9, 1.0, 1.0)
const COLOR_VOID_BRIGHT: Color  = Color(0.85, 0.55, 1.0, 0.9)
const COLOR_VOID_MID: Color     = Color(0.6, 0.3, 0.9, 0.7)
const COLOR_VOID_DARK: Color    = Color(0.35, 0.12, 0.55, 0.5)
const COLOR_RING: Color         = Color(0.7, 0.4, 1.0, 0.8)
const WAVE_TINT: Color          = Color(0.35, 0.10, 0.70, 0.35)

# ── Sizing ───────────────────────────────────────────────────────────────────
const CORE_SIZE: float             = 40.0
const RING_MAX_RADIUS: float       = 120.0
const BODY_SIZE: float             = 80.0
const SHADOW_SIZE: Vector2         = Vector2(100.0, 40.0)
const DISTORTION_RADIUS_PX: float  = 140.0

# ── Timing ───────────────────────────────────────────────────────────────────
# Original VFX shipped with DEBUG_TIME_SCALE=2.5 always on. Preserve that
# runtime feel via the sequence's time_scale; the global BaseVfx.time_scale
# still composes for the debug knob.
const VFX_SLOWMO: float    = 2.5
const BURST_DURATION: float = 0.45
const TAIL_DURATION: float  = 0.10

var _impact_pos: Vector2
var _fx_layer: CanvasLayer = null


static func create(impact_pos: Vector2) -> VoidBoltImpactVFX:
	var vfx := VoidBoltImpactVFX.new()
	vfx._impact_pos = impact_pos
	vfx.z_index = 200
	vfx.impact_count = 0   # caller doesn't sync damage to this VFX
	return vfx


func _play() -> void:
	global_position = _impact_pos
	var seq := sequence()
	seq.time_scale = VFX_SLOWMO
	seq.run([
		VfxPhase.new("burst", BURST_DURATION, _build_burst),
		# tail keeps the host alive briefly so trailing tweens can finish
		VfxPhase.new("tail",  TAIL_DURATION,  _cleanup_fx_layer),
	])


# Builders share a "scale" — the per-tween delays/durations were tuned against
# DEBUG_TIME_SCALE=2.5. Now that VFX_SLOWMO is on the sequence, builders use
# their original raw values; the sequence multiplies the phase budget but the
# inner tweens are the ones we want to scale, so we apply VFX_SLOWMO inside
# the builders too. (This keeps tween durations consistent with the original.)


# ═════════════════════════════════════════════════════════════════════════════
# Phase builders
# ═════════════════════════════════════════════════════════════════════════════

func _build_burst(_duration: float) -> void:
	var ui: Node = get_parent()
	var scene: Node = ui.get_parent() if ui else null

	_spawn_ground_shadow()
	if scene:
		_spawn_distortion(scene)
	_spawn_core_flash()
	_spawn_ring()
	_spawn_body_layers()
	_spawn_ejecta()
	_spawn_smoke_wisps()


func _cleanup_fx_layer(_duration: float) -> void:
	# Empty — `tail` phase exists only to keep the host alive while trailing
	# tweens finish. Sequence will queue_free us when the phase ends. Free the
	# CanvasLayer here to avoid leaks; tweens that target nodes inside it have
	# already self-freed via tween_callbacks.
	if is_instance_valid(_fx_layer):
		_fx_layer.queue_free()


# ═════════════════════════════════════════════════════════════════════════════
# Layer 1: Screen Distortion Shockwave
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_distortion(scene: Node) -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 2
	scene.add_child(_fx_layer)

	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.z_index = 15
	rect.z_as_relative = false

	var aspect: float = vp_size.x / vp_size.y
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SONIC
	mat.set_shader_parameter("aspect", aspect)
	mat.set_shader_parameter("tint", WAVE_TINT)
	mat.set_shader_parameter("radius_max", DISTORTION_RADIUS_PX / vp_size.y)
	mat.set_shader_parameter("thickness", 0.08)
	mat.set_shader_parameter("strength", 0.022)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("alpha_multiplier", 1.0)
	mat.set_shader_parameter("center_uv", Vector2(
		_impact_pos.x / vp_size.x,
		_impact_pos.y / vp_size.y
	))
	rect.material = mat
	_fx_layer.add_child(rect)

	var duration: float = 0.20 * VFX_SLOWMO
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			mat.set_shader_parameter("progress", p),
			0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, duration * 0.35).set_delay(duration * 0.65).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(rect.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Layer 2: Core Flash
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_core_flash() -> void:
	var flash := Sprite2D.new()
	flash.texture = TEX_GLOW
	var tex_size: float = flash.texture.get_width()
	flash.scale = Vector2.ONE * (CORE_SIZE / maxf(tex_size, 1.0))
	flash.modulate = COLOR_CORE_FLASH
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = mat
	add_child(flash)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", flash.scale * 1.6, 0.06 * VFX_SLOWMO) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.12 * VFX_SLOWMO) \
		.set_delay(0.04 * VFX_SLOWMO).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(flash.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Layer 3: Perspective Shockwave Ring
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_ring() -> void:
	var ring := Sprite2D.new()
	ring.texture = _make_ring_texture()
	var tex_size: float = ring.texture.get_width()
	var start_scale: float = 20.0 / maxf(tex_size, 1.0)
	ring.scale = Vector2(start_scale, start_scale * 0.6)
	ring.modulate = COLOR_RING
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ring.material = mat
	add_child(ring)

	var target_scale_x: float = (RING_MAX_RADIUS * 2.0) / maxf(tex_size, 1.0)
	var target_scale_y: float = target_scale_x * 0.6

	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale",
		Vector2(target_scale_x, target_scale_y), 0.22 * VFX_SLOWMO) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(0.03 * VFX_SLOWMO)
	tw.tween_property(ring, "modulate:a", 0.0, 0.14 * VFX_SLOWMO) \
		.set_delay(0.12 * VFX_SLOWMO).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(ring.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Layer 4: Volumetric Body (3 staggered depth sprites)
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_body_layers() -> void:
	var configs: Array = [
		{"delay": 0.00 * VFX_SLOWMO, "color": COLOR_VOID_DARK,   "size_mult": 0.85,
		 "growth": 1.4, "offset": Vector2(randf_range(-6, 6), randf_range(2, 6)),
		 "fade_time": 0.30 * VFX_SLOWMO, "rotation": randf_range(-0.3, 0.3)},
		{"delay": 0.02 * VFX_SLOWMO, "color": COLOR_VOID_MID,    "size_mult": 1.0,
		 "growth": 1.5, "offset": Vector2(randf_range(-4, 4), randf_range(-2, 2)),
		 "fade_time": 0.25 * VFX_SLOWMO, "rotation": randf_range(-0.2, 0.2)},
		{"delay": 0.04 * VFX_SLOWMO, "color": COLOR_VOID_BRIGHT,  "size_mult": 1.1,
		 "growth": 1.6, "offset": Vector2(randf_range(-5, 5), randf_range(-6, -2)),
		 "fade_time": 0.20 * VFX_SLOWMO, "rotation": randf_range(-0.25, 0.25)},
	]

	for cfg in configs:
		var color: Color = cfg["color"] as Color
		var size_mult: float = float(cfg["size_mult"])
		var growth: float = float(cfg["growth"])
		var offset: Vector2 = cfg["offset"] as Vector2
		var delay: float = float(cfg["delay"])
		var fade_time: float = float(cfg["fade_time"])
		var rot: float = float(cfg["rotation"])

		var sprite := Sprite2D.new()
		sprite.texture = TEX_GLOW
		var tex_size: float = sprite.texture.get_width()
		var start_scale: float = (BODY_SIZE * size_mult * 0.3) / maxf(tex_size, 1.0)
		sprite.scale = Vector2.ONE * start_scale
		sprite.position = offset
		sprite.rotation = rot
		sprite.modulate = Color(color.r, color.g, color.b, 0.0)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = mat
		add_child(sprite)

		var end_scale: float = start_scale * growth
		var tw := create_tween().set_parallel(true)
		tw.tween_property(sprite, "modulate:a", color.a, 0.04 * VFX_SLOWMO).set_delay(delay)
		tw.tween_property(sprite, "scale", Vector2.ONE * end_scale, fade_time) \
			.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(sprite, "modulate:a", 0.0, fade_time * 0.6) \
			.set_delay(delay + fade_time * 0.4).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_callback(sprite.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Layer 5a: Hot Ejecta Particles
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_ejecta() -> void:
	var burst := CPUParticles2D.new()
	burst.emitting = true
	burst.amount = 16
	burst.lifetime = 0.22 * VFX_SLOWMO
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.local_coords = true
	burst.texture = _make_soft_circle()

	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 6.0
	burst.direction = Vector2(0, 0)
	burst.spread = 180.0
	burst.initial_velocity_min = 100.0 / VFX_SLOWMO
	burst.initial_velocity_max = 220.0 / VFX_SLOWMO
	burst.damping_min = 150.0 / VFX_SLOWMO
	burst.damping_max = 300.0 / VFX_SLOWMO
	burst.gravity = Vector2.ZERO

	burst.scale_amount_min = 0.06
	burst.scale_amount_max = 0.15
	burst.scale_amount_curve = _make_fade_curve()

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.9, 1.0, 1.0))
	gradient.add_point(0.2, Color(0.9, 0.6, 1.0, 0.9))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.4, 0.15, 0.6, 0.0))
	burst.color_ramp = gradient

	add_child(burst)


# ═════════════════════════════════════════════════════════════════════════════
# Layer 5b: Smoke Wisps
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_smoke_wisps() -> void:
	var wisps := CPUParticles2D.new()
	wisps.emitting = true
	wisps.amount = 8
	wisps.lifetime = 0.40 * VFX_SLOWMO
	wisps.one_shot = true
	wisps.explosiveness = 0.85
	wisps.randomness = 0.5
	wisps.local_coords = true
	wisps.texture = _make_soft_circle()

	wisps.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	wisps.emission_sphere_radius = 10.0
	wisps.direction = Vector2(0, 0)
	wisps.spread = 180.0
	wisps.initial_velocity_min = 20.0 / VFX_SLOWMO
	wisps.initial_velocity_max = 55.0 / VFX_SLOWMO
	wisps.gravity = Vector2(0, -30.0 / VFX_SLOWMO)
	wisps.damping_min = 20.0 / VFX_SLOWMO
	wisps.damping_max = 40.0 / VFX_SLOWMO

	wisps.scale_amount_min = 0.2
	wisps.scale_amount_max = 0.45
	wisps.scale_amount_curve = _make_fade_curve()

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.5, 0.25, 0.7, 0.6))
	gradient.add_point(0.4, Color(0.35, 0.15, 0.5, 0.4))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.2, 0.08, 0.3, 0.0))
	wisps.color_ramp = gradient

	add_child(wisps)


# ═════════════════════════════════════════════════════════════════════════════
# Layer 6: Ground Shadow
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_ground_shadow() -> void:
	var shadow := Sprite2D.new()
	shadow.texture = TEX_GLOW
	var tex_size: float = shadow.texture.get_width()
	var start_scale := Vector2(
		SHADOW_SIZE.x / maxf(tex_size, 1.0) * 0.3,
		SHADOW_SIZE.y / maxf(tex_size, 1.0) * 0.3
	)
	shadow.scale = start_scale
	shadow.position = Vector2(0, 8)
	shadow.modulate = Color(0.0, 0.0, 0.0, 0.0)
	shadow.z_index = -1
	add_child(shadow)

	var target_scale := Vector2(
		SHADOW_SIZE.x / maxf(tex_size, 1.0),
		SHADOW_SIZE.y / maxf(tex_size, 1.0)
	)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(shadow, "modulate:a", 0.25, 0.04 * VFX_SLOWMO)
	tw.tween_property(shadow, "scale", target_scale, 0.12 * VFX_SLOWMO) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(shadow, "modulate:a", 0.0, 0.25 * VFX_SLOWMO) \
		.set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(shadow.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Procedural Textures
# ═════════════════════════════════════════════════════════════════════════════

static func _make_ring_texture() -> ImageTexture:
	var size: int = 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var outer_radius: float = size * 0.48
	var inner_radius: float = size * 0.30
	var ring_center: float = (inner_radius + outer_radius) * 0.5
	var half_width: float = (outer_radius - inner_radius) * 0.5
	for y in size:
		for x in size:
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var ring_dist: float = absf(dist - ring_center)
			var alpha: float = clampf(1.0 - ring_dist / half_width, 0.0, 1.0)
			alpha *= alpha
			var outer_fade: float = clampf(1.0 - dist / outer_radius, 0.0, 1.0)
			alpha *= outer_fade
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


static func _make_soft_circle() -> ImageTexture:
	var size: int = 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius: float = size * 0.5
	for y in size:
		for x in size:
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha: float = clampf(1.0 - dist / radius, 0.0, 1.0)
			alpha *= alpha
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


static func _make_fade_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	return curve
