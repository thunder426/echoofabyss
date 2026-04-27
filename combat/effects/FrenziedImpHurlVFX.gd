## FrenziedImpHurlVFX.gd
## Frenzied Imp on-play VFX — rage sigil windup, crimson-void axe hurl,
## spinning flight with ember trail, cleave impact on target.
##
## Phases:
##   1. windup (0.25s) — rage sigil flares + pulses under imp
##   2. launch (0.08s) — muzzle flash + ember burst at source; axe appears
##   3. travel (0.40s) — spinning axe arcs to target with energy trail
##                       (arc + spin driven by _process loop, orthogonal to phases)
##   4. impact (0.45s) — impact_hit fires at start; cleave gash, sonic ring,
##                       embers, screen shake; axe buries then fades.
##
## Visual scaling (sigil glow, axe size, spin rate, ember count, shake amp)
## intensifies with `feral_count` passed at create time.
##
## Note: this VFX ships at 2.0x slow-mo via `seq.time_scale = 2.0` (the original
## TIME_SCALE was always-on). BaseVfx.time_scale composes on top so the global
## debug knob still works.
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name FrenziedImpHurlVFX
extends BaseVfx

const TEX_AXE: Texture2D    = preload("res://assets/art/fx/frenzy_axe.png")
const TEX_TRAIL: Texture2D  = preload("res://assets/art/fx/frenzy_trail.png")
const TEX_GASH: Texture2D   = preload("res://assets/art/fx/axe_gash.png")
const TEX_SIGIL: Texture2D  = preload("res://assets/art/fx/rage_sigil.png")
const SHADER_SONIC: Shader  = preload("res://combat/effects/sonic_wave.gdshader")

const COLOR_CRIMSON: Color      = Color(1.0, 0.18, 0.12)
const COLOR_HOT: Color          = Color(1.0, 0.55, 0.30)
const COLOR_VOID_EDGE: Color    = Color(0.45, 0.12, 0.65)
const COLOR_WHITE_HOT: Color    = Color(1.0, 0.9, 1.0)

# Slow-mo factor preserved via sequence time_scale (originally TIME_SCALE const).
const VFX_SLOWMO: float = 2.0
const WINDUP_DUR: float = 0.25
const LAUNCH_DUR: float = 0.08
const TRAVEL_DUR: float = 0.40
const IMPACT_DUR: float = 0.45
const FADE_DUR: float   = 0.25

const AXE_BASE_SIZE: float   = 70.0
const SIGIL_BASE_SIZE: float = 95.0
const ARC_HEIGHT: float      = 55.0

var _source_pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO
var _target_slot: BoardSlot = null
var _shake_target: Node = null
var _feral_count: int = 0

# Travel-loop state
var _axe: Sprite2D = null
var _axe_ghost: Sprite2D = null
var _trail_inner: CPUParticles2D = null
var _trail_outer: CPUParticles2D = null
var _travel_elapsed: float = 0.0
var _travel_active: bool = false
var _travel_total: float = TRAVEL_DUR * VFX_SLOWMO
var _prev_travel_pos: Vector2 = Vector2.ZERO
var _spin_speed: float = 16.0

static var _spark_tex: ImageTexture


static func create(source_pos: Vector2, target_pos: Vector2, feral_count: int,
		shake_target: Node = null, target_slot: BoardSlot = null) -> FrenziedImpHurlVFX:
	var vfx := FrenziedImpHurlVFX.new()
	vfx._source_pos = source_pos
	vfx._target_pos = target_pos
	vfx._feral_count = maxi(feral_count, 0)
	vfx._shake_target = shake_target
	vfx._target_slot = target_slot
	vfx.z_index = 200
	return vfx


func _play() -> void:
	_ensure_textures()
	var seq := sequence()
	seq.time_scale = VFX_SLOWMO
	# Cache the post-scale travel duration for the _process loop.
	_travel_total = TRAVEL_DUR * VFX_SLOWMO * BaseVfx.time_scale
	seq.run([
		VfxPhase.new("windup", WINDUP_DUR, _build_windup),
		VfxPhase.new("launch", LAUNCH_DUR, _build_launch),
		VfxPhase.new("travel", TRAVEL_DUR, _build_travel),
		VfxPhase.new("impact", IMPACT_DUR + FADE_DUR, _build_impact) \
			.emits_at_start(VfxSequence.RESERVED_IMPACT_HIT),
	])


# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: Windup
# ═════════════════════════════════════════════════════════════════════════════

func _build_windup(duration: float) -> void:
	var intensity: float = _intensity_scale()

	var sigil := Sprite2D.new()
	sigil.texture = TEX_SIGIL
	sigil.global_position = _source_pos
	var base_scale: float = SIGIL_BASE_SIZE / float(TEX_SIGIL.get_width())
	base_scale *= lerpf(1.0, 1.35, intensity)
	sigil.scale = Vector2.ONE * base_scale * 0.2
	sigil.modulate = Color(1.0, 0.7, 0.7, 0.0)
	sigil.z_index = -1
	var sigil_mat := CanvasItemMaterial.new()
	sigil_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sigil.material = sigil_mat
	add_child(sigil)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(sigil, "scale", Vector2.ONE * base_scale, duration * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sigil, "modulate:a", 1.0, duration * 0.4)
	tw.tween_property(sigil, "rotation", TAU * 0.4, duration)
	var pulse_tw := create_tween().set_loops(2)
	pulse_tw.tween_property(sigil, "modulate", Color(1.3, 0.6, 0.5, 1.0), duration * 0.24)
	pulse_tw.tween_property(sigil, "modulate", Color(1.0, 0.9, 0.85, 1.0), duration * 0.24)

	# Ember sparks rising off the sigil
	var sparks := CPUParticles2D.new()
	sparks.emitting = true
	sparks.amount = int(lerpf(14, 28, intensity))
	sparks.lifetime = 0.45 * VFX_SLOWMO
	sparks.one_shot = true
	sparks.explosiveness = 0.0
	sparks.local_coords = false
	sparks.texture = _spark_tex
	sparks.global_position = _source_pos
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = SIGIL_BASE_SIZE * 0.35
	sparks.direction = Vector2(0, -1)
	sparks.spread = 40.0
	sparks.initial_velocity_min = 60.0 / VFX_SLOWMO
	sparks.initial_velocity_max = 160.0 / VFX_SLOWMO
	sparks.gravity = Vector2(0, -80.0 / (VFX_SLOWMO * VFX_SLOWMO))
	sparks.scale_amount_min = 0.15
	sparks.scale_amount_max = 0.30
	sparks.scale_amount_curve = _fade_curve()
	var sp_grad := Gradient.new()
	sp_grad.set_color(0, Color(1.0, 0.95, 0.9, 1.0))
	sp_grad.add_point(0.3, Color(1.0, 0.4, 0.25, 0.9))
	sp_grad.set_color(sp_grad.get_point_count() - 1, Color(0.5, 0.08, 0.08, 0.0))
	sparks.color_ramp = sp_grad
	var sp_mat := CanvasItemMaterial.new()
	sp_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sparks.material = sp_mat
	add_child(sparks)

	# Sigil shatters at end of windup (timed via tween)
	var sh_tw := create_tween().set_parallel(true)
	sh_tw.tween_interval(duration)
	sh_tw.tween_property(sigil, "scale", sigil.scale * 1.8, duration * 0.72) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT).set_delay(duration)
	sh_tw.tween_property(sigil, "modulate:a", 0.0, duration * 0.72).set_delay(duration)
	sh_tw.chain().tween_callback(sigil.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2: Launch
# ═════════════════════════════════════════════════════════════════════════════

func _build_launch(_duration: float) -> void:
	var intensity: float = _intensity_scale()
	AudioManager.play_sfx("res://assets/audio/sfx/minions/frenzied_imp_flight.wav", -8.0)

	var embers := CPUParticles2D.new()
	embers.emitting = true
	embers.amount = int(lerpf(18, 34, intensity))
	embers.lifetime = 0.35 * VFX_SLOWMO
	embers.one_shot = true
	embers.explosiveness = 1.0
	embers.local_coords = false
	embers.texture = _spark_tex
	embers.global_position = _source_pos
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	var launch_dir: Vector2 = (_target_pos - _source_pos).normalized()
	embers.direction = launch_dir if launch_dir.length_squared() > 0.001 else Vector2(1, 0)
	embers.spread = 55.0
	embers.initial_velocity_min = 120.0 / VFX_SLOWMO
	embers.initial_velocity_max = 280.0 / VFX_SLOWMO
	embers.gravity = Vector2.ZERO
	embers.damping_min = 180.0 / VFX_SLOWMO
	embers.damping_max = 320.0 / VFX_SLOWMO
	embers.scale_amount_min = 0.15
	embers.scale_amount_max = 0.32
	embers.scale_amount_curve = _fade_curve()
	var e_grad := Gradient.new()
	e_grad.set_color(0, Color(1.0, 0.95, 0.9, 1.0))
	e_grad.add_point(0.35, Color(1.0, 0.3, 0.2, 0.85))
	e_grad.set_color(e_grad.get_point_count() - 1, Color(0.35, 0.06, 0.25, 0.0))
	embers.color_ramp = e_grad
	var e_mat := CanvasItemMaterial.new()
	e_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = e_mat
	add_child(embers)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3: Travel — _process drives arc + spin
# ═════════════════════════════════════════════════════════════════════════════

func _build_travel(duration: float) -> void:
	var intensity: float = _intensity_scale()
	_spin_speed = lerpf(14.0, 22.0, intensity) / VFX_SLOWMO

	_axe = Sprite2D.new()
	_axe.texture = TEX_AXE
	var tex_w: float = float(TEX_AXE.get_width())
	var axe_scale_base: float = (AXE_BASE_SIZE / maxf(tex_w, 1.0)) * lerpf(1.0, 1.25, intensity)
	_axe.scale = Vector2.ONE * axe_scale_base
	_axe.global_position = _source_pos
	_axe.modulate = Color(1.7, 0.75, 0.70, 1.0)
	var axe_mat := CanvasItemMaterial.new()
	axe_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_axe.material = axe_mat
	add_child(_axe)

	_axe_ghost = Sprite2D.new()
	_axe_ghost.texture = TEX_AXE
	_axe_ghost.scale = _axe.scale
	_axe_ghost.modulate = Color(1.3, 0.4, 0.3, 0.35)
	var ghost_mat := CanvasItemMaterial.new()
	ghost_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_axe_ghost.material = ghost_mat
	add_child(_axe_ghost)

	# Inner trail
	_trail_inner = CPUParticles2D.new()
	_trail_inner.emitting = true
	_trail_inner.amount = int(lerpf(60, 100, intensity))
	_trail_inner.lifetime = 0.35 * VFX_SLOWMO
	_trail_inner.one_shot = false
	_trail_inner.explosiveness = 0.0
	_trail_inner.local_coords = false
	_trail_inner.texture = _spark_tex
	_trail_inner.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_trail_inner.emission_sphere_radius = 4.0
	_trail_inner.direction = Vector2(-1, 0)
	_trail_inner.spread = 18.0
	_trail_inner.initial_velocity_min = 10.0 / VFX_SLOWMO
	_trail_inner.initial_velocity_max = 22.0 / VFX_SLOWMO
	_trail_inner.damping_min = 20.0 / VFX_SLOWMO
	_trail_inner.damping_max = 40.0 / VFX_SLOWMO
	_trail_inner.scale_amount_min = 0.7
	_trail_inner.scale_amount_max = 1.1
	_trail_inner.scale_amount_curve = _fade_curve()
	var ti_grad := Gradient.new()
	ti_grad.set_color(0, Color(1.0, 0.9, 0.85, 0.95))
	ti_grad.add_point(0.25, Color(1.0, 0.35, 0.22, 0.85))
	ti_grad.add_point(0.6, Color(0.75, 0.12, 0.15, 0.55))
	ti_grad.set_color(ti_grad.get_point_count() - 1, Color(0.35, 0.05, 0.2, 0.0))
	_trail_inner.color_ramp = ti_grad
	var ti_mat := CanvasItemMaterial.new()
	ti_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail_inner.material = ti_mat
	add_child(_trail_inner)

	# Outer trail
	_trail_outer = CPUParticles2D.new()
	_trail_outer.emitting = true
	_trail_outer.amount = int(lerpf(32, 52, intensity))
	_trail_outer.lifetime = 0.50 * VFX_SLOWMO
	_trail_outer.one_shot = false
	_trail_outer.explosiveness = 0.0
	_trail_outer.randomness = 0.4
	_trail_outer.local_coords = false
	_trail_outer.texture = _spark_tex
	_trail_outer.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_trail_outer.emission_sphere_radius = 8.0
	_trail_outer.direction = Vector2(-1, 0)
	_trail_outer.spread = 35.0
	_trail_outer.initial_velocity_min = 5.0 / VFX_SLOWMO
	_trail_outer.initial_velocity_max = 16.0 / VFX_SLOWMO
	_trail_outer.damping_min = 12.0 / VFX_SLOWMO
	_trail_outer.damping_max = 28.0 / VFX_SLOWMO
	_trail_outer.scale_amount_min = 1.0
	_trail_outer.scale_amount_max = 1.6
	_trail_outer.scale_amount_curve = _fade_curve()
	var to_grad := Gradient.new()
	to_grad.set_color(0, Color(0.8, 0.2, 0.3, 0.55))
	to_grad.add_point(0.4, Color(0.55, 0.1, 0.35, 0.4))
	to_grad.set_color(to_grad.get_point_count() - 1, Color(0.25, 0.05, 0.3, 0.0))
	_trail_outer.color_ramp = to_grad
	var to_mat := CanvasItemMaterial.new()
	to_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail_outer.material = to_mat
	add_child(_trail_outer)

	_prev_travel_pos = _source_pos
	_travel_elapsed = 0.0
	_travel_total = duration   # use the post-scale phase duration
	_travel_active = true


func _process(delta: float) -> void:
	if not _travel_active or _axe == null:
		return
	_travel_elapsed += delta
	var t: float = clampf(_travel_elapsed / _travel_total, 0.0, 1.0)
	if t >= 1.0:
		_travel_active = false
		if _trail_inner:
			_trail_inner.emitting = false
		if _trail_outer:
			_trail_outer.emitting = false
	var straight: Vector2 = _source_pos.lerp(_target_pos, t)
	var arc_offset: float = -4.0 * ARC_HEIGHT * t * (t - 1.0)
	var pos: Vector2 = straight + Vector2(0, -arc_offset)
	_axe.global_position = pos

	var travel_dir: Vector2 = (pos - _prev_travel_pos).normalized()
	if travel_dir.length_squared() < 0.001:
		travel_dir = (_target_pos - _source_pos).normalized()
	_prev_travel_pos = pos

	_axe.rotation += _spin_speed * delta

	if _axe_ghost:
		_axe_ghost.global_position = pos - travel_dir * 18.0
		_axe_ghost.rotation = _axe.rotation - 0.6

	var backward: Vector2 = -travel_dir
	if _trail_inner:
		_trail_inner.global_position = pos + backward * (AXE_BASE_SIZE * 0.25)
		_trail_inner.direction = backward
	if _trail_outer:
		_trail_outer.global_position = pos + backward * (AXE_BASE_SIZE * 0.45)
		_trail_outer.direction = backward


# ═════════════════════════════════════════════════════════════════════════════
# Phase 4: Impact
# ═════════════════════════════════════════════════════════════════════════════

func _build_impact(_duration: float) -> void:
	var intensity: float = _intensity_scale()

	if _trail_inner:
		_trail_inner.emitting = false
	if _trail_outer:
		_trail_outer.emitting = false

	AudioManager.play_sfx("res://assets/audio/sfx/minions/frenzied_imp_impact.wav", -6.0)

	# Cleave gash
	for i in 2:
		var gash := Sprite2D.new()
		gash.texture = TEX_GASH
		gash.global_position = _target_pos
		var gash_mat := CanvasItemMaterial.new()
		gash_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		gash.material = gash_mat
		var gash_base: float = lerpf(0.11, 0.16, intensity)
		gash.scale = Vector2.ONE * gash_base * 0.6
		gash.rotation = (-0.35 + 0.7 * i) + randf_range(-0.1, 0.1)
		gash.modulate = Color(1.15, 0.9, 0.85, 0.0)
		gash.z_index = 2
		add_child(gash)
		var g_tw := create_tween().set_parallel(true)
		g_tw.tween_property(gash, "modulate:a", 1.0, 0.06 * VFX_SLOWMO)
		g_tw.tween_property(gash, "scale", Vector2.ONE * gash_base, 0.12 * VFX_SLOWMO) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		g_tw.chain().tween_property(gash, "modulate:a", 0.0, IMPACT_DUR * VFX_SLOWMO - 0.12 * VFX_SLOWMO)
		g_tw.chain().tween_callback(gash.queue_free)

	_spawn_sonic_ring(intensity)
	_spawn_impact_embers(intensity)

	# Axe buries and fades
	if _axe:
		var final_rot: float = _axe.rotation + 0.25
		var axe_tw := create_tween().set_parallel(true)
		axe_tw.tween_property(_axe, "rotation", final_rot, 0.08 * VFX_SLOWMO) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		axe_tw.tween_property(_axe, "scale", _axe.scale * 1.1, 0.08 * VFX_SLOWMO)
		axe_tw.chain().tween_property(_axe, "modulate:a", 0.0, FADE_DUR * VFX_SLOWMO)
	if _axe_ghost:
		var gh_tw := create_tween()
		gh_tw.tween_property(_axe_ghost, "modulate:a", 0.0, 0.12 * VFX_SLOWMO)

	# Screen shake
	if _shake_target != null and _shake_target is Node and is_instance_valid(_shake_target) \
			and not (_shake_target is CanvasLayer):
		var amp: float = lerpf(10.0, 22.0, intensity)
		var ticks: int = int(lerpf(10, 14, intensity))
		ScreenShakeEffect.shake(_shake_target, self, amp, ticks)


func _spawn_sonic_ring(intensity: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 2
	host.add_child(fx_layer)

	var rect := ColorRect.new()
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(rect)

	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SONIC
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center_uv: Vector2 = _target_pos / viewport_size
	mat.set_shader_parameter("center_uv", center_uv)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("radius_max", lerpf(0.10, 0.16, intensity))
	mat.set_shader_parameter("thickness", 0.05)
	mat.set_shader_parameter("strength", lerpf(0.015, 0.025, intensity))
	mat.set_shader_parameter("aspect", viewport_size.x / maxf(viewport_size.y, 1.0))
	mat.set_shader_parameter("tint", Color(0.8, 0.05, 0.05, 1.0))
	mat.set_shader_parameter("alpha_multiplier", 1.0)
	rect.material = mat

	var set_progress := func(v: float) -> void:
		if is_instance_valid(mat):
			mat.set_shader_parameter("progress", v)
	var cleanup := func() -> void:
		if is_instance_valid(fx_layer):
			fx_layer.queue_free()
	var tw := create_tween()
	tw.tween_method(set_progress, 0.0, 1.0, 0.32 * VFX_SLOWMO) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_callback(cleanup)


func _spawn_impact_embers(intensity: float) -> void:
	var embers := CPUParticles2D.new()
	embers.emitting = true
	embers.amount = int(lerpf(26, 48, intensity))
	embers.lifetime = 0.45 * VFX_SLOWMO
	embers.one_shot = true
	embers.explosiveness = 1.0
	embers.local_coords = false
	embers.texture = _spark_tex
	embers.global_position = _target_pos
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	embers.direction = Vector2(0, -1)
	embers.spread = 180.0
	embers.initial_velocity_min = 160.0 / VFX_SLOWMO
	embers.initial_velocity_max = 360.0 / VFX_SLOWMO
	embers.gravity = Vector2(0, 180.0 / (VFX_SLOWMO * VFX_SLOWMO))
	embers.damping_min = 120.0 / VFX_SLOWMO
	embers.damping_max = 220.0 / VFX_SLOWMO
	embers.scale_amount_min = 0.18
	embers.scale_amount_max = 0.35
	embers.scale_amount_curve = _fade_curve()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.85, 1.0))
	grad.add_point(0.3, Color(1.0, 0.3, 0.2, 0.9))
	grad.add_point(0.7, Color(0.55, 0.08, 0.2, 0.5))
	grad.set_color(grad.get_point_count() - 1, Color(0.3, 0.04, 0.25, 0.0))
	embers.color_ramp = grad
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = mat
	add_child(embers)


# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

func _intensity_scale() -> float:
	return clampf(float(_feral_count) / 4.0, 0.0, 1.0)


func _ensure_textures() -> void:
	if not _spark_tex:
		_spark_tex = _make_soft_dot()


static func _make_soft_dot() -> ImageTexture:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius: float = size * 0.5
	for y in size:
		for x in size:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var a: float = clampf(1.0 - d / radius, 0.0, 1.0)
			a *= a
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


static func _fade_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	return c
