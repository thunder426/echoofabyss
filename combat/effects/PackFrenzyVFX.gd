## PackFrenzyVFX.gd
## Full VFX for the Pack Frenzy spell — a crimson warcry from the caster hero
## that sweeps across the friendly board, igniting each Feral Imp with a
## red-green radiant wave.
##
## Owns the full buff visual for source="pack_frenzy" — the generic
## BuffApplyVFX is filtered out in CombatScene so this effect doesn't double up.
##
## Phases:
##   1. windup    (0.55s) — caster hero howl: inward particle stream + haze
##   2. wave      (variable) — shader sonic wave + screen shake; impact_hit
##                              emits via seq.emit_beat() at the geometric
##                              earliest-arrival time (when wave touches the
##                              closest imp). Per-imp ignition glyph + spark
##                              burst staggered by per-slot arrival time.
##   3. tail      (variable) — let lingering particles + glyphs play out
##
## Spawn via vfx_controller.spawn — do not parent manually.
class_name PackFrenzyVFX
extends BaseVfx

const SHADER_SONIC: Shader  = preload("res://combat/effects/sonic_wave.gdshader")
const SHADER_GLYPH_GLOW: Shader = preload("res://combat/effects/casting_glyph_glow.gdshader")
const TEX_FERAL_GLYPH: Texture2D = preload("res://assets/art/fx/casting_glyphs/feral_glyph.png")

const COLOR_RED_CORE: Color     = Color(1.00, 0.22, 0.12, 1.0)
const COLOR_RED_HOT: Color      = Color(1.00, 0.55, 0.30, 1.0)
const COLOR_RED_DARK: Color     = Color(0.55, 0.10, 0.06, 1.0)
const COLOR_GREEN_CORE: Color   = Color(0.55, 1.00, 0.55, 1.0)
const COLOR_GREEN_BRIGHT: Color = Color(0.78, 1.00, 0.70, 1.0)

const GLYPH_TINT: Color         = Color(0.55, 0.95, 0.35, 1.0)
const GLYPH_HALO_SCALE: Vector3 = Vector3(0.95, 0.10, 0.10)
const GLYPH_HALO_SCALE_GREEN: Vector3 = Vector3(0.10, 0.70, 0.15)

const WAVE_TINT_RED: Color    = Color(1.00, 0.22, 0.12, 0.12)
const WAVE_TINT_GREEN: Color  = Color(0.55, 1.00, 0.55, 0.12)

const WINDUP_DURATION: float = 0.55
const WAVE_DURATION: float   = 0.50

const GLYPH_SIZE: float = 120.0
const GLYPH_LIFE: float = 0.70
const GLYPH_FADE_IN: float = 0.16
const GLYPH_FADE_OUT: float = 0.22

const WINDUP_EMIT_RADIUS: float = 160.0

const BEAT_WAVE_ARRIVED := "wave_arrived"

var _caster_panel: Control = null
var _target_slots: Array = []
var _is_matriarch: bool = false
var _windup_nodes: Array = []
var _caster_center: Vector2 = Vector2.ZERO
var _slot_arrivals: Array = []   # Array[{slot, arrival_t}]
var _earliest_arrival: float = 0.0


static func create(caster_panel: Control, target_slots: Array,
		is_matriarch: bool) -> PackFrenzyVFX:
	var vfx := PackFrenzyVFX.new()
	vfx._caster_panel = caster_panel
	vfx._target_slots = target_slots
	vfx._is_matriarch = is_matriarch
	vfx.z_index = 200
	vfx.impact_count = 0
	return vfx


func _play() -> void:
	if _caster_panel == null or get_parent() == null or not _caster_panel.is_inside_tree():
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return

	_caster_center = _caster_panel.global_position + _caster_panel.size * 0.5

	# Tail length matches the original "wave_tail + finale" trailing window so
	# linger particles + glyphs have time to fade naturally before queue_free.
	var tail_dur: float = WAVE_DURATION + GLYPH_LIFE + 0.35 + 0.80

	var seq := sequence()
	seq.on(BEAT_WAVE_ARRIVED, _on_wave_arrived)
	seq.run([
		VfxPhase.new("windup", WINDUP_DURATION, _build_windup),
		VfxPhase.new("wave",   WAVE_DURATION,   _build_wave),
		VfxPhase.new("tail",   tail_dur,        Callable()),
	])


# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: Caster windup — continuous inward particle stream + haze
# ═════════════════════════════════════════════════════════════════════════════

func _build_windup(_duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	_windup_nodes = []

	# Subtle full-screen red haze
	var haze := ColorRect.new()
	haze.color = Color(COLOR_RED_CORE.r, COLOR_RED_CORE.g, COLOR_RED_CORE.b, 0.0)
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	haze.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	haze.z_index = 10
	haze.z_as_relative = false
	host.add_child(haze)
	var htw := haze.create_tween()
	htw.tween_property(haze, "color:a", 0.10, WINDUP_DURATION * 0.6) \
			.set_trans(Tween.TRANS_SINE)
	_windup_nodes.append(haze)

	_windup_nodes.append(_make_inward_emitter(host, _caster_center, COLOR_RED_HOT, COLOR_RED_CORE))
	_windup_nodes.append(_make_inward_emitter(host, _caster_center, COLOR_GREEN_BRIGHT, COLOR_GREEN_CORE))


func _make_inward_emitter(host: Node, center: Vector2,
		start_col: Color, mid_col: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = center
	p.z_index = 14
	p.z_as_relative = false
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 42
	p.lifetime = 0.45
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = WINDUP_EMIT_RADIUS
	p.direction = Vector2(0, -1)
	p.spread = 0.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 20.0
	p.gravity = Vector2.ZERO
	p.radial_accel_min = -900.0
	p.radial_accel_max = -1200.0
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 1.6
	p.scale_amount_max = 2.6
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = scale_curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(start_col.r, start_col.g, start_col.b, 0.0))
	ramp.add_point(0.20, start_col)
	ramp.add_point(0.70, mid_col)
	ramp.set_color(1, Color(mid_col.r, mid_col.g, mid_col.b, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	host.add_child(p)
	p.emitting = true
	# Free after lifetime expires post-windup
	var free_tw := p.create_tween()
	free_tw.tween_interval(WINDUP_DURATION + p.lifetime + 0.1)
	free_tw.tween_callback(func() -> void:
			if is_instance_valid(p):
				p.queue_free())
	return p


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2: Radiant wave + per-imp ignition (geometry-driven impact_hit beat)
# ═════════════════════════════════════════════════════════════════════════════

func _build_wave(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return

	# Stop windup emission — in-flight motes finish naturally.
	for n in _windup_nodes:
		if is_instance_valid(n) and n is CPUParticles2D:
			(n as CPUParticles2D).emitting = false
		elif is_instance_valid(n):
			var cr := n as ColorRect
			if cr != null:
				var ftw := cr.create_tween()
				ftw.tween_property(cr, "color:a", 0.0, 0.18)
				ftw.tween_callback(cr.queue_free)
	_windup_nodes.clear()

	# Compute max reach based on furthest imp.
	var max_reach: float = 400.0
	for slot in _target_slots:
		var s := slot as BoardSlot
		if s == null or not s.is_inside_tree():
			continue
		var c: Vector2 = s.global_position + s.size * 0.5
		max_reach = maxf(max_reach, _caster_center.distance_to(c) + 120.0)

	_spawn_sonic_wave(host, _caster_center, duration, max_reach)
	ScreenShakeEffect.shake(_caster_panel, self, 10.0, 10)

	# Compute per-slot arrival times.
	_earliest_arrival = duration
	_slot_arrivals.clear()
	for slot in _target_slots:
		var s := slot as BoardSlot
		if s == null or not s.is_inside_tree():
			continue
		var c: Vector2 = s.global_position + s.size * 0.5
		var dist: float = _caster_center.distance_to(c)
		var ratio: float = clampf(dist / max_reach, 0.0, 1.0)
		var arrival_t: float = duration * (1.0 - pow(1.0 - ratio, 1.0 / 3.0))
		_slot_arrivals.append({"slot": s, "arrival_t": arrival_t})
		if arrival_t < _earliest_arrival:
			_earliest_arrival = arrival_t

	# Schedule the impact beat at the earliest arrival.
	var seq := sequence()
	if _earliest_arrival <= 0.0:
		seq.emit_beat(BEAT_WAVE_ARRIVED)
	else:
		var tree := get_tree()
		if tree != null:
			tree.create_timer(_earliest_arrival).timeout.connect(func() -> void:
				if is_instance_valid(self) and is_inside_tree():
					seq.emit_beat(BEAT_WAVE_ARRIVED))


# Listener — fires when the wave reaches the first imp.
func _on_wave_arrived() -> void:
	impact_hit.emit(0)
	var host: Node = get_parent()
	if host == null:
		return
	var finale: float = GLYPH_LIFE + 0.35
	for entry in _slot_arrivals:
		var s: BoardSlot = entry["slot"]
		var local_delay: float = maxf(float(entry["arrival_t"]) - _earliest_arrival, 0.0)
		_spawn_imp_ignition(host, s, local_delay, finale)


# ═════════════════════════════════════════════════════════════════════════════
# Sonic wave shader
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_sonic_wave(host: Node, center: Vector2, duration: float,
		max_radius_px: float) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var aspect: float = vp.x / vp.y

	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.z_index = 15
	rect.z_as_relative = false

	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SONIC
	mat.set_shader_parameter("aspect", aspect)
	mat.set_shader_parameter("tint", WAVE_TINT_RED)
	mat.set_shader_parameter("radius_max", max_radius_px / vp.y)
	mat.set_shader_parameter("thickness", 0.22)
	mat.set_shader_parameter("strength", 0.030)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("alpha_multiplier", 1.0)
	mat.set_shader_parameter("center_uv", Vector2(center.x / vp.x, center.y / vp.y))
	rect.material = mat
	host.add_child(rect)

	var tw := rect.create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			mat.set_shader_parameter("progress", p),
			0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, duration * 0.30).set_delay(duration * 0.70) \
			.set_trans(Tween.TRANS_SINE)

	# Tint oscillation red <-> green
	var ctw := rect.create_tween()
	var cycles: int = 3
	var step: float = duration / float(cycles * 2)
	var cur_red: bool = true
	for _i in cycles * 2:
		var from_col: Color = WAVE_TINT_RED if cur_red else WAVE_TINT_GREEN
		var to_col: Color = WAVE_TINT_GREEN if cur_red else WAVE_TINT_RED
		ctw.tween_method(func(c: Color) -> void:
				mat.set_shader_parameter("tint", c),
				from_col, to_col, step) \
				.set_trans(Tween.TRANS_SINE)
		cur_red = not cur_red
	ctw.tween_callback(rect.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Per-imp glyph + spark burst + linger
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_imp_ignition(host: Node, slot: BoardSlot, delay: float,
		linger_emit_time: float) -> void:
	if slot == null or not slot.is_inside_tree():
		return
	var center: Vector2 = slot.global_position + slot.size * 0.5
	_spawn_feral_glyph(host, center, delay)

	# Radial ember spark burst
	var burst := CPUParticles2D.new()
	burst.position = center
	burst.z_index = 14
	burst.z_as_relative = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 14
	burst.lifetime = 0.50
	burst.local_coords = true
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 4.0
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.initial_velocity_min = 130.0
	burst.initial_velocity_max = 240.0
	burst.gravity = Vector2.ZERO
	burst.damping_min = 1.5
	burst.damping_max = 2.5
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 3.5
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.2))
	burst.scale_amount_curve = scale_curve
	var ramp := Gradient.new()
	ramp.set_color(0, COLOR_RED_HOT)
	ramp.add_point(0.5, COLOR_RED_CORE)
	ramp.set_color(1, Color(COLOR_RED_DARK.r, COLOR_RED_DARK.g, COLOR_RED_DARK.b, 0.0))
	burst.color_ramp = ramp
	var b_mat := CanvasItemMaterial.new()
	b_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	burst.material = b_mat
	burst.emitting = false
	host.add_child(burst)
	var btw := burst.create_tween()
	btw.tween_interval(delay)
	btw.tween_callback(func() -> void:
			if is_instance_valid(burst):
				burst.emitting = true)
	btw.tween_interval(burst.lifetime + 0.1)
	btw.tween_callback(burst.queue_free)

	# Lingering rising sparks
	var linger := CPUParticles2D.new()
	linger.position = center
	linger.z_index = 14
	linger.z_as_relative = false
	linger.one_shot = false
	linger.amount = 16 if _is_matriarch else 11
	linger.lifetime = 0.70
	linger.local_coords = true
	linger.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	linger.emission_sphere_radius = 52.0
	linger.direction = Vector2(0, -1)
	linger.spread = 30.0
	linger.initial_velocity_min = 70.0
	linger.initial_velocity_max = 125.0
	linger.gravity = Vector2(0, -60.0)
	linger.scale_amount_min = 3.2
	linger.scale_amount_max = 5.0
	var linger_scale := Curve.new()
	linger_scale.add_point(Vector2(0.0, 1.0))
	linger_scale.add_point(Vector2(1.0, 0.1))
	linger.scale_amount_curve = linger_scale
	var linger_ramp := Gradient.new()
	if _is_matriarch:
		linger_ramp.set_color(0, COLOR_RED_HOT)
		linger_ramp.add_point(0.25, COLOR_GREEN_BRIGHT)
		linger_ramp.add_point(0.50, COLOR_RED_CORE)
		linger_ramp.add_point(0.75, COLOR_GREEN_CORE)
		linger_ramp.set_color(1, Color(COLOR_RED_DARK.r, COLOR_RED_DARK.g, COLOR_RED_DARK.b, 0.0))
	else:
		linger_ramp.set_color(0, COLOR_RED_HOT)
		linger_ramp.add_point(0.6, COLOR_RED_CORE)
		linger_ramp.set_color(1, Color(COLOR_RED_DARK.r, COLOR_RED_DARK.g, COLOR_RED_DARK.b, 0.0))
	linger.color_ramp = linger_ramp
	var l_mat := CanvasItemMaterial.new()
	l_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	linger.material = l_mat
	linger.emitting = false
	host.add_child(linger)
	var ltw := linger.create_tween()
	ltw.tween_interval(delay + 0.12)
	ltw.tween_callback(func() -> void:
			if is_instance_valid(linger):
				linger.emitting = true)
	ltw.tween_interval(linger_emit_time)
	ltw.tween_callback(func() -> void:
			if is_instance_valid(linger):
				linger.emitting = false)
	ltw.tween_interval(linger.lifetime + 0.1)
	ltw.tween_callback(linger.queue_free)


func _spawn_feral_glyph(host: Node, center: Vector2, delay: float) -> void:
	var root := Node2D.new()
	root.position = center
	root.z_index = 16
	root.z_as_relative = false
	host.add_child(root)

	var tex_max: float = maxf(TEX_FERAL_GLYPH.get_width(), TEX_FERAL_GLYPH.get_height())
	var target_scale: float = GLYPH_SIZE / maxf(tex_max, 1.0)

	var halo_tex: Texture2D = CastingWindupVFX._get_glow_texture()
	var halo := _make_halo_sprite(halo_tex, GLYPH_TINT, GLYPH_HALO_SCALE)
	var halo_tex_size: float = float(halo_tex.get_width())
	var halo_peak_scale: Vector2 = Vector2.ONE * (GLYPH_SIZE * 2.2 / maxf(halo_tex_size, 1.0))
	halo.scale = halo_peak_scale * 0.55
	root.add_child(halo)

	var halo_green: Sprite2D = null
	if _is_matriarch:
		halo_green = _make_halo_sprite(halo_tex, GLYPH_TINT, GLYPH_HALO_SCALE_GREEN)
		halo_green.scale = halo_peak_scale * 0.45
		root.add_child(halo_green)

	var sprite := Sprite2D.new()
	sprite.texture = TEX_FERAL_GLYPH
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	sprite.scale = Vector2.ONE * target_scale
	var gmat := ShaderMaterial.new()
	gmat.shader = SHADER_GLYPH_GLOW
	gmat.set_shader_parameter("intensity", 0.0)
	gmat.set_shader_parameter("tint", GLYPH_TINT)
	gmat.set_shader_parameter("white_mix", 0.0)
	gmat.set_shader_parameter("thickness", 3.0)
	gmat.set_shader_parameter("tex_size",
			Vector2(TEX_FERAL_GLYPH.get_width(), TEX_FERAL_GLYPH.get_height()))
	sprite.material = gmat
	root.add_child(sprite)

	var int_tw := root.create_tween()
	int_tw.tween_interval(delay)
	int_tw.tween_method(func(v: float) -> void:
			gmat.set_shader_parameter("intensity", v),
			0.0, 3.0, GLYPH_FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	int_tw.tween_method(func(v: float) -> void:
			gmat.set_shader_parameter("intensity", v),
			3.0, 5.0, GLYPH_LIFE - GLYPH_FADE_IN - GLYPH_FADE_OUT) \
			.set_trans(Tween.TRANS_SINE)
	int_tw.tween_method(func(v: float) -> void:
			gmat.set_shader_parameter("intensity", v),
			5.0, 0.0, GLYPH_FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	var rot_tw := root.create_tween()
	rot_tw.tween_interval(delay)
	rot_tw.tween_property(sprite, "rotation", -TAU, GLYPH_LIFE) \
			.from(0.0).set_trans(Tween.TRANS_LINEAR)

	var sc_tw := root.create_tween()
	sc_tw.tween_interval(delay)
	sc_tw.tween_property(root, "scale", Vector2(1.0, 1.0), GLYPH_FADE_IN) \
			.from(Vector2(0.55, 0.55)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sc_tw.tween_interval(GLYPH_LIFE - GLYPH_FADE_IN - GLYPH_FADE_OUT)
	sc_tw.tween_property(root, "scale", Vector2(1.30, 1.30), GLYPH_FADE_OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var a_tw := root.create_tween()
	a_tw.tween_interval(delay)
	a_tw.tween_property(sprite, "modulate:a", 1.0, GLYPH_FADE_IN) \
			.set_trans(Tween.TRANS_SINE)
	a_tw.tween_interval(GLYPH_LIFE - GLYPH_FADE_IN - GLYPH_FADE_OUT)
	a_tw.tween_property(sprite, "modulate:a", 0.0, GLYPH_FADE_OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	var halo_tw := root.create_tween()
	halo_tw.tween_interval(delay)
	halo_tw.tween_property(halo, "modulate:a", 0.90, GLYPH_FADE_IN) \
			.set_trans(Tween.TRANS_SINE)
	halo_tw.parallel().tween_property(halo, "scale", halo_peak_scale * 0.90,
			GLYPH_FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	halo_tw.tween_property(halo, "scale", halo_peak_scale * 1.30,
			GLYPH_LIFE - GLYPH_FADE_IN - GLYPH_FADE_OUT) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	halo_tw.tween_property(halo, "scale", halo_peak_scale * 1.60, GLYPH_FADE_OUT) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	halo_tw.parallel().tween_property(halo, "modulate:a", 0.0, GLYPH_FADE_OUT) \
			.set_trans(Tween.TRANS_SINE)

	if halo_green != null:
		var halo_g_peak: Vector2 = halo_peak_scale * 0.85
		var gtw := root.create_tween()
		gtw.tween_interval(delay + GLYPH_FADE_IN * 0.5)
		gtw.tween_property(halo_green, "modulate:a", 0.75, GLYPH_FADE_IN) \
				.set_trans(Tween.TRANS_SINE)
		gtw.parallel().tween_property(halo_green, "scale", halo_g_peak * 0.80,
				GLYPH_FADE_IN).set_trans(Tween.TRANS_SINE)
		gtw.tween_property(halo_green, "scale", halo_g_peak * 1.45,
				GLYPH_LIFE - GLYPH_FADE_IN - GLYPH_FADE_OUT) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		gtw.tween_property(halo_green, "modulate:a", 0.0, GLYPH_FADE_OUT) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	var life_tw := root.create_tween()
	life_tw.tween_interval(delay + GLYPH_LIFE + 0.05)
	life_tw.tween_callback(root.queue_free)


func _make_halo_sprite(tex: Texture2D, base_tint: Color, scale_vec: Vector3) -> Sprite2D:
	var halo_tint := Color(
			base_tint.r * scale_vec.x,
			base_tint.g * scale_vec.y,
			base_tint.b * scale_vec.z, 1.0)
	var s := Sprite2D.new()
	s.texture = tex
	s.modulate = Color(halo_tint.r, halo_tint.g, halo_tint.b, 0.0)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	return s
