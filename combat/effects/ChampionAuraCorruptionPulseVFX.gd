## ChampionAuraCorruptionPulseVFX.gd
## Fires on the Abyss Cultist Patrol champion's slot to advertise its
## corruption aura — once on summon, and again each time the aura triggers a
## detonation on the player side. Three layers, tuned to keep the card art readable:
##
##   1. Rectangular rim glow around the slot (single inhale → exhale breath,
##      emerald palette) — advertises "I project an aura" in the same visual
##      language as AuraBreathingPulseVFX.
##   2. Emerald smoke wisps billowing up off the card — two staggered waves
##      emitted from a circular hotspot at the bottom-center of the card so
##      the cloud reads as organic rather than a rectangular emission plate.
##   3. A soft sonic shimmer ring at the pulse moment — reuses the
##      CorruptionApplyVFX shader at low strength for the audio/visual link.
##
## Fire-and-forget via VfxController.spawn(). impact_count = 0 (utility VFX).
class_name ChampionAuraCorruptionPulseVFX
extends BaseVfx

const SHADER_SONIC: Shader = preload("res://combat/effects/sonic_wave.gdshader")

# Procedural soft blob, built once and shared. Radial alpha falloff so the
# texture has no rectangular edge — critical for smoke that should blend into
# the background rather than showing the source PNG bounds.
static var _smoke_tex: ImageTexture

# ── Emerald / corruption palette (matches CorruptionDetonationVFX) ──────────
const COLOR_GLOW: Color         = Color(0.55, 1.0, 0.40, 1.0)    # rim glow base
const COLOR_SMOKE_BIRTH: Color  = Color(0.45, 0.95, 0.22, 0.80)  # bright emerald puff
const COLOR_SMOKE_MID: Color    = Color(0.22, 0.65, 0.10, 0.55)
const COLOR_SMOKE_DEATH: Color  = Color(0.08, 0.28, 0.05, 0.0)
const COLOR_SHIMMER_TINT: Color = Color(0.30, 0.85, 0.25, 0.45)

# Rim glow envelope (single inhale → exhale)
const SPREAD_START: float = 14.0
const SPREAD_PEAK: float  = 48.0
const SPREAD_FADE: float  = 64.0
const ALPHA_PEAK: float   = 0.80
const INHALE_TIME: float  = 0.30
const EXHALE_TIME: float  = 0.55

# Shimmer ring
const SHIMMER_RADIUS_PX: float = 70.0
const SHIMMER_DURATION: float  = 0.38

# Smoke cloud — thick, slow, drifty so it visibly rolls across the card rather
# than rising past it. Procedural soft-blob texture is used (no rectangular
# source-texture borders). Two staggered waves keep the cloud moving through
# the whole pulse.
const SMOKE_WAVE1_AMOUNT: int   = 22
const SMOKE_WAVE2_AMOUNT: int   = 16
const SMOKE_WAVE2_DELAY: float  = 0.30
const SMOKE_LIFETIME: float     = 1.80
const SMOKE_RISE_MIN: float     = 18.0    # slow upward drift
const SMOKE_RISE_MAX: float     = 48.0
const SMOKE_H_DRIFT: float      = 28.0    # sideways wander (±px/s)
const SMOKE_SCALE_MIN: float    = 1.10    # big blobs that overlap
const SMOKE_SCALE_MAX: float    = 1.85

var _target_slot: BoardSlot = null
var _rim: _RimGlow = null
var _fx_layer: CanvasLayer = null


static func create(target_slot: BoardSlot) -> ChampionAuraCorruptionPulseVFX:
	var vfx := ChampionAuraCorruptionPulseVFX.new()
	vfx._target_slot = target_slot
	vfx.impact_count = 0
	vfx.z_index = 90
	return vfx


func _play() -> void:
	if _target_slot == null or not _target_slot.is_inside_tree():
		finished.emit()
		queue_free()
		return

	# Anchor at the slot's top-left so local-coords emission lines up with the card.
	global_position = _target_slot.global_position

	# Layer 2a: first smoke wave — starts immediately so the plume is already
	# rising by the time the rim glow peaks.
	_spawn_smoke_wave(SMOKE_WAVE1_AMOUNT)

	# Layer 1: rim glow — single inhale then exhale + fade.
	_rim = _RimGlow.new()
	_rim.card_size = _target_slot.size
	_rim.color = COLOR_GLOW
	_rim.spread = SPREAD_START
	_rim.intensity = 0.0
	add_child(_rim)

	var tw_in := create_tween().set_parallel(true)
	tw_in.tween_method(_set_intensity, 0.0, ALPHA_PEAK, INHALE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_in.tween_method(_set_spread, SPREAD_START, SPREAD_PEAK, INHALE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw_in.finished
	if not is_inside_tree():
		_cleanup(); finished.emit(); queue_free(); return

	# Layer 3: sonic shimmer ring at the peak.
	_spawn_shimmer()

	# Layer 2b: second smoke wave — keeps the plume alive through the exhale.
	_spawn_smoke_wave(SMOKE_WAVE2_AMOUNT)

	# Rim exhale — fade out while spreading a little wider.
	var tw_out := create_tween().set_parallel(true)
	tw_out.tween_method(_set_intensity, ALPHA_PEAK, 0.0, EXHALE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw_out.tween_method(_set_spread, SPREAD_PEAK, SPREAD_FADE, EXHALE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw_out.finished

	# Let the smoke finish rising after the rim has faded.
	var trailing: float = maxf(SMOKE_LIFETIME - (INHALE_TIME + EXHALE_TIME), 0.0)
	if trailing > 0.0:
		await get_tree().create_timer(trailing).timeout

	_cleanup()
	finished.emit()
	queue_free()


func _cleanup() -> void:
	if is_instance_valid(_fx_layer):
		_fx_layer.queue_free()


func _set_intensity(v: float) -> void:
	if _rim != null and is_instance_valid(_rim):
		_rim.intensity = v
		_rim.queue_redraw()


func _set_spread(v: float) -> void:
	if _rim != null and is_instance_valid(_rim):
		_rim.spread = v
		_rim.queue_redraw()


# ═════════════════════════════════════════════════════════════════════════════
# Layer 1: Emerald smoke wisps rising off the card
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_smoke_wave(amount: int) -> void:
	var smoke := CPUParticles2D.new()
	smoke.emitting = true
	smoke.amount = amount
	smoke.lifetime = SMOKE_LIFETIME
	smoke.one_shot = true
	smoke.explosiveness = 0.25       # emission staggered across the first ~75% of lifetime
	smoke.randomness = 0.65
	smoke.local_coords = true
	smoke.texture = _ensure_smoke_texture()

	# Emit from a wide circular hotspot covering most of the card so blobs
	# spawn INSIDE the card area and drift both up and sideways — feels like
	# the card itself is smoldering, not a vent at the bottom.
	var emit_radius: float = minf(_target_slot.size.x, _target_slot.size.y) * 0.45
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = emit_radius
	smoke.position = _target_slot.size * Vector2(0.5, 0.55)

	# Slow upward drift with wide spread so some blobs wander sideways across
	# the card. Horizontal velocity variance adds organic turbulence.
	smoke.direction = Vector2(0, -1)
	smoke.spread = 55.0
	smoke.initial_velocity_min = SMOKE_RISE_MIN
	smoke.initial_velocity_max = SMOKE_RISE_MAX
	smoke.linear_accel_min = -10.0   # light deceleration so blobs linger
	smoke.linear_accel_max = -25.0
	smoke.gravity = Vector2(0, -8.0)
	# Side-to-side wiggle — each blob gets a random tangential velocity.
	smoke.tangential_accel_min = -SMOKE_H_DRIFT
	smoke.tangential_accel_max = SMOKE_H_DRIFT
	smoke.angular_velocity_min = -45.0
	smoke.angular_velocity_max = 45.0

	smoke.scale_amount_min = SMOKE_SCALE_MIN
	smoke.scale_amount_max = SMOKE_SCALE_MAX
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.45))   # small at birth
	scale_curve.add_point(Vector2(0.35, 1.0))   # peak mid-life
	scale_curve.add_point(Vector2(1.0, 1.25))   # grow while fading — cloud spreads out
	smoke.scale_amount_curve = scale_curve

	var gradient := Gradient.new()
	gradient.set_color(0, Color(COLOR_SMOKE_BIRTH.r, COLOR_SMOKE_BIRTH.g, COLOR_SMOKE_BIRTH.b, 0.0))
	gradient.add_point(0.12, COLOR_SMOKE_BIRTH)   # fast fade-in so no pop
	gradient.add_point(0.55, COLOR_SMOKE_MID)
	gradient.set_color(gradient.get_point_count() - 1, COLOR_SMOKE_DEATH)
	smoke.color_ramp = gradient

	# Additive so the smoke brightens rather than greying out the board.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	smoke.material = mat

	add_child(smoke)


## 96×96 radial soft blob with very gentle alpha falloff. Built once, shared
## across all instances of this VFX. Gentler falloff than _make_soft_circle so
## the blobs blend smoothly into each other with no visible edges.
static func _ensure_smoke_texture() -> ImageTexture:
	if _smoke_tex != null:
		return _smoke_tex
	var size: int = 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius: float = size * 0.5
	for y in size:
		for x in size:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var t: float = clampf(1.0 - d / radius, 0.0, 1.0)
			# pow 2.8 = softer shoulder, very smooth edge at the rim.
			var alpha: float = pow(t, 2.8)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_smoke_tex = ImageTexture.create_from_image(img)
	return _smoke_tex


# ═════════════════════════════════════════════════════════════════════════════
# Layer 2: Sonic shimmer ring (reuses CorruptionApply's visual language)
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_shimmer() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var scene: Node = get_parent().get_parent() if get_parent() else null
	if scene == null:
		return

	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 2
	scene.add_child(_fx_layer)

	var slot_center_px: Vector2 = _target_slot.global_position + _target_slot.size * 0.5
	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.z_index = 14
	rect.z_as_relative = false

	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SONIC
	mat.set_shader_parameter("aspect", vp_size.x / vp_size.y)
	mat.set_shader_parameter("tint", COLOR_SHIMMER_TINT)
	mat.set_shader_parameter("radius_max", SHIMMER_RADIUS_PX / vp_size.y)
	mat.set_shader_parameter("thickness", 0.05)
	mat.set_shader_parameter("strength", 0.012)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("alpha_multiplier", 1.0)
	mat.set_shader_parameter("center_uv", Vector2(
		slot_center_px.x / vp_size.x,
		slot_center_px.y / vp_size.y
	))
	rect.material = mat
	_fx_layer.add_child(rect)

	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			mat.set_shader_parameter("progress", p),
			0.0, 1.0, SHIMMER_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, SHIMMER_DURATION * 0.40
		).set_delay(SHIMMER_DURATION * 0.60).set_trans(Tween.TRANS_SINE)


# ═════════════════════════════════════════════════════════════════════════════
# _RimGlow — paints an outward rectangular emerald rim around the slot.
# Same draw pattern as AuraBreathingPulseVFX._RimGlow; duplicated here so we
# can tune step count / falloff independently.
# ═════════════════════════════════════════════════════════════════════════════

class _RimGlow extends Node2D:
	var card_size: Vector2 = Vector2.ZERO
	var color: Color = Color.WHITE
	var spread: float = 0.0
	var intensity: float = 0.0

	const STEPS: int = 14

	func _init() -> void:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat

	func _draw() -> void:
		if card_size == Vector2.ZERO or spread <= 0.0 or intensity <= 0.0:
			return
		for i in range(STEPS, 0, -1):
			var t: float = float(i) / float(STEPS)
			var offset_px: float = spread * t
			var falloff: float = pow(1.0 - t, 2.2)
			var a: float = intensity * falloff
			if a <= 0.001:
				continue
			var rect := Rect2(
				Vector2(-offset_px, -offset_px),
				card_size + Vector2(offset_px, offset_px) * 2.0
			)
			var c := Color(color.r, color.g, color.b, a)
			var width: float = maxf(spread / float(STEPS) * 1.6, 1.5)
			draw_rect(rect, c, false, width)
