## SummonSigilVFX.gd
## Generic summoning sigil VFX — reusable across sources (Brood Call, on-death
## summons, Void Spark, future spells). Three procedurally composed sprites
## (outer ring, inner ring, center glyph) retinted by a flavor palette sit on
## the target slot, bloom in, hold while counter-rotating, then collapse before
## the minion is placed.
##
## Phases:
##   1. ramp     (0.45s) — rings bloom in, halo fade-in, particles start
##   2. hold     (0.70s) — glyph pulses, spin accelerates, particles continue
##   3. pulse    (0.11s) — summon-complete pulse (rings + halo brighten)
##   4. collapse (0.27s) — everything fades; impact_hit fires at start
##                         (the moment the summon "lands").
##
## Spin runs as a continuous _process loop across ramp+hold (orthogonal to the
## sequence — driven by elapsed time, not phase boundaries).
##
## Fire-and-forget via vfx_controller.spawn.
class_name SummonSigilVFX
extends BaseVfx

## Flavor presets — pick at call site to match the summon source.
enum Flavor { VOID_GREEN, EMBER_RED, HOLY_GOLD, FROST_BLUE, ARCANE_PURPLE, BROOD, SPARK, BROOD_DARK }

# Default/generic summon sigil art.
const TEX_SUMMON_OUTER: Texture2D = preload("res://assets/art/fx/casting_glyphs/summon_sigil/summon_outer_ring.png")
const TEX_SUMMON_INNER: Texture2D = preload("res://assets/art/fx/casting_glyphs/summon_sigil/summon_inner_ring.png")
const TEX_SUMMON_GLYPH: Texture2D = preload("res://assets/art/fx/casting_glyphs/summon_sigil/summon_center_glyph.png")

const TEX_BROOD_OUTER: Texture2D  = preload("res://assets/art/fx/casting_glyphs/brood_sigil/brood_outer_ring.png")
const TEX_BROOD_INNER: Texture2D  = preload("res://assets/art/fx/casting_glyphs/brood_sigil/brood_inner_ring.png")
const TEX_BROOD_GLYPH: Texture2D  = preload("res://assets/art/fx/casting_glyphs/brood_sigil/brood_center_glyph.png")

const TEX_SPARK_OUTER: Texture2D  = preload("res://assets/art/fx/casting_glyphs/spark_sigil/spark_outer_ring.png")
const TEX_SPARK_INNER: Texture2D  = preload("res://assets/art/fx/casting_glyphs/spark_sigil/spark_inner_ring.png")
const TEX_SPARK_GLYPH: Texture2D  = preload("res://assets/art/fx/casting_glyphs/spark_sigil/spark_center_glyph.png")

const TEX_GLOW: Texture2D = preload("res://assets/art/fx/glow_soft.png")
const TEX_BLOOD_DROP: Texture2D = preload("res://assets/art/fx/blood_drop.png")
const TEX_SPARK: Texture2D = preload("res://assets/art/fx/spark_sprite.png")

const _FLAVOR_TABLE: Dictionary = {
	Flavor.VOID_GREEN:    [Color(0.55, 1.00, 0.45, 1.0), Color(0.20, 0.85, 0.15, 1.0)],
	Flavor.EMBER_RED:     [Color(1.00, 0.70, 0.30, 1.0), Color(0.95, 0.25, 0.10, 1.0)],
	Flavor.HOLY_GOLD:     [Color(1.00, 0.95, 0.65, 1.0), Color(1.00, 0.80, 0.25, 1.0)],
	Flavor.FROST_BLUE:    [Color(0.75, 0.95, 1.00, 1.0), Color(0.35, 0.70, 1.00, 1.0)],
	Flavor.ARCANE_PURPLE: [Color(0.90, 0.70, 1.00, 1.0), Color(0.60, 0.25, 0.90, 1.0)],
	Flavor.BROOD:         [Color(0.45, 1.00, 0.35, 1.0), Color(0.55, 0.05, 0.05, 1.0)],
	Flavor.SPARK:         [Color(0.85, 0.95, 1.00, 1.0), Color(0.55, 0.30, 0.95, 1.0)],
	Flavor.BROOD_DARK:    [Color(0.55, 1.00, 0.45, 1.0), Color(0.03, 0.08, 0.03, 1.0)],
}

# ── Sizing ──────────────────────────────────────────────────────────────────
const OUTER_SIZE: float  = 150.0
const INNER_SIZE: float  = 108.0
const GLYPH_SIZE: float  = 60.0
const HALO_START: float  = 120.0
const HALO_END: float    = 240.0
const SHADOW_SIZE: float = 150.0

# ── Timing ──────────────────────────────────────────────────────────────────
const RAMP_DURATION: float     = 0.45
const HOLD_DURATION: float     = 0.70
const COMPLETE_PULSE: float    = 0.22       # full pulse window
const PULSE_HALF: float        = COMPLETE_PULSE * 0.5  # phase used by sequence
const COLLAPSE_DURATION: float = 0.22
const COLLAPSE_TAIL: float     = 0.05       # padding after collapse for trailing tweens

# ── Rotation — start slow, accelerate to final speed across ramp+hold ───────
const OUTER_SPIN_START: float =  40.0
const OUTER_SPIN_END: float   = 260.0
const INNER_SPIN_START: float = -60.0
const INNER_SPIN_END: float   = -340.0

var _target_slot: BoardSlot = null
var _flavor: int = Flavor.VOID_GREEN

# Layer refs (built in _build_ramp, animated/torn down in later phases).
var _outer: Sprite2D = null
var _inner: Sprite2D = null
var _glyph: Sprite2D = null
var _halo: Sprite2D = null
var _shadow: Sprite2D = null
var _particles: CPUParticles2D = null
var _glyph_pulse: Tween = null

var _target_outer_scale: Vector2 = Vector2.ONE
var _target_inner_scale: Vector2 = Vector2.ONE
var _target_glyph_scale: Vector2 = Vector2.ONE
var _halo_pulse_scale: Vector2 = Vector2.ONE

var _spin_active: bool = false
var _spin_elapsed: float = 0.0
var _spin_total: float = RAMP_DURATION + HOLD_DURATION


static func create(target_slot: BoardSlot, flavor: int = Flavor.VOID_GREEN) -> SummonSigilVFX:
	var vfx := SummonSigilVFX.new()
	vfx._target_slot = target_slot
	vfx._flavor = flavor
	vfx.z_index = 200
	return vfx


func _play() -> void:
	if _target_slot == null or not _target_slot.is_inside_tree():
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return

	global_position = _target_slot.global_position + _target_slot.size * 0.5

	match _flavor:
		Flavor.BROOD:
			AudioManager.play_sfx("res://assets/audio/sfx/spells/brood_call.wav", -8.0)
		Flavor.SPARK:
			AudioManager.play_sfx("res://assets/audio/sfx/minions/spark_summon.wav", -10.0)
		_:
			AudioManager.play_sfx("res://assets/audio/sfx/spells/portal_open.wav", -8.0)

	sequence().run([
		VfxPhase.new("ramp",     RAMP_DURATION,                     _build_ramp),
		VfxPhase.new("hold",     HOLD_DURATION,                     Callable()),
		VfxPhase.new("pulse",    PULSE_HALF,                        _build_pulse),
		VfxPhase.new("collapse", COLLAPSE_DURATION + COLLAPSE_TAIL, _build_collapse) \
			.emits_at_start(VfxSequence.RESERVED_IMPACT_HIT),
	])


# ═════════════════════════════════════════════════════════════════════════════
# Phase builders
# ═════════════════════════════════════════════════════════════════════════════

func _build_ramp(duration: float) -> void:
	var palette: Array = _FLAVOR_TABLE.get(_flavor, _FLAVOR_TABLE[Flavor.VOID_GREEN])
	var primary: Color = palette[0]
	var secondary: Color = palette[1]

	var textures: Array = _textures_for(_flavor)
	var tex_outer: Texture2D = textures[0]
	var tex_inner: Texture2D = textures[1]
	var tex_glyph: Texture2D = textures[2]

	# Layer 1: Ground shadow
	_shadow = Sprite2D.new()
	_shadow.texture = TEX_GLOW
	_shadow.modulate = Color(0.0, 0.0, 0.0, 0.35)
	_shadow.z_index = -1
	var shadow_tex_size: float = maxf(TEX_GLOW.get_width(), TEX_GLOW.get_height())
	var shadow_scale: float = SHADOW_SIZE / maxf(shadow_tex_size, 1.0)
	_shadow.scale = Vector2(shadow_scale, shadow_scale * 0.45)
	_shadow.position = Vector2(0, 28)
	add_child(_shadow)

	# Layer 2: Halo
	_halo = Sprite2D.new()
	_halo.texture = CastingWindupVFX._get_glow_texture()
	var halo_mat := CanvasItemMaterial.new()
	halo_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halo.material = halo_mat
	_halo.modulate = Color(secondary.r, secondary.g, secondary.b, 0.0)
	var halo_tex_size: float = float(_halo.texture.get_width())

	var halo_start_px: float = HALO_START
	var halo_end_px: float = HALO_END
	var halo_peak_alpha: float = 0.75
	if _flavor == Flavor.SPARK:
		halo_start_px = 70.0
		halo_end_px   = 110.0
		halo_peak_alpha = 0.45

	_halo.scale = Vector2.ONE * (halo_start_px / maxf(halo_tex_size, 1.0))
	add_child(_halo)

	var halo_hold_scale: Vector2 = Vector2.ONE * (halo_end_px / maxf(halo_tex_size, 1.0))
	_halo_pulse_scale = halo_hold_scale * 1.20
	var htw := create_tween()
	htw.set_parallel(true)
	htw.tween_property(_halo, "modulate:a", halo_peak_alpha, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	htw.tween_property(_halo, "scale", halo_hold_scale, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Per-flavor sizing for rings/glyph.
	var outer_size_px: float = OUTER_SIZE
	var inner_size_px: float = INNER_SIZE
	var glyph_size_px: float = GLYPH_SIZE
	if _flavor == Flavor.SPARK:
		outer_size_px = 95.0
		inner_size_px = 70.0
		glyph_size_px = 40.0

	_outer = _make_sigil_sprite(tex_outer, outer_size_px, primary)
	add_child(_outer)
	_inner = _make_sigil_sprite(tex_inner, inner_size_px, primary)
	add_child(_inner)
	_glyph = _make_sigil_sprite(tex_glyph, glyph_size_px, primary)
	var glyph_mat := CanvasItemMaterial.new()
	glyph_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glyph.material = glyph_mat
	add_child(_glyph)

	_target_outer_scale = _outer.scale
	_target_inner_scale = _inner.scale
	_target_glyph_scale = _glyph.scale
	_outer.scale = _target_outer_scale * 0.35
	_inner.scale = _target_inner_scale * 0.25
	_glyph.scale = _target_glyph_scale * 0.30

	var rtw := create_tween()
	rtw.set_parallel(true)
	rtw.tween_property(_outer, "modulate:a", 1.0, duration * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rtw.tween_property(_outer, "scale", _target_outer_scale, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rtw.tween_property(_inner, "modulate:a", 1.0, duration * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rtw.tween_property(_inner, "scale", _target_inner_scale, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05)
	rtw.tween_property(_glyph, "modulate:a", 1.0, duration * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(0.10)
	rtw.tween_property(_glyph, "scale", _target_glyph_scale, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.10)

	# Glyph pulse loop runs across ramp + hold.
	_glyph_pulse = create_tween().set_loops()
	_glyph_pulse.tween_property(_glyph, "scale", _target_glyph_scale * 1.15, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glyph_pulse.tween_property(_glyph, "scale", _target_glyph_scale, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Flavor-specific particles.
	match _flavor:
		Flavor.BROOD:
			_particles = _spawn_blood_drip_particles(primary, secondary)
		Flavor.BROOD_DARK:
			_particles = _spawn_spark_inward_particles(primary, secondary)
		Flavor.SPARK:
			_particles = _spawn_spark_inward_particles(primary, secondary)
		_:
			_particles = _spawn_rise_particles(primary, secondary)

	# Spin loop drives rotation across ramp + hold via _process.
	_spin_total = RAMP_DURATION + HOLD_DURATION
	_spin_elapsed = 0.0
	_spin_active = true


func _build_pulse(duration: float) -> void:
	# End the loops + particle emission before the pulse plays.
	if _particles != null and is_instance_valid(_particles):
		_particles.emitting = false
	if _glyph_pulse != null and _glyph_pulse.is_valid():
		_glyph_pulse.kill()

	var tw := create_tween().set_parallel(true)
	if _outer != null:
		tw.tween_property(_outer, "scale", _target_outer_scale * 1.18, duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _inner != null:
		tw.tween_property(_inner, "scale", _target_inner_scale * 1.22, duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _glyph != null:
		tw.tween_property(_glyph, "scale", _target_glyph_scale * 1.35, duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _halo != null:
		tw.tween_property(_halo, "scale", _halo_pulse_scale, duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_halo, "modulate:a", 1.0, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _build_collapse(duration: float) -> void:
	_spin_active = false
	# Subtract tail so the visible collapse uses COLLAPSE_DURATION exactly,
	# matching original timing. The tail leaves the sequence alive briefly so
	# parallel tween_callback frees can run.
	var visible: float = maxf(duration - COLLAPSE_TAIL, 0.0)
	var tw := create_tween().set_parallel(true)
	if _outer != null:
		tw.tween_property(_outer, "modulate:a", 0.0, visible)
		tw.tween_property(_outer, "scale", _target_outer_scale * 0.3, visible) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _inner != null:
		tw.tween_property(_inner, "modulate:a", 0.0, visible)
		tw.tween_property(_inner, "scale", _target_inner_scale * 0.3, visible) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _glyph != null:
		tw.tween_property(_glyph, "modulate:a", 0.0, visible)
		tw.tween_property(_glyph, "scale", _target_glyph_scale * 0.2, visible) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _halo != null:
		tw.tween_property(_halo, "modulate:a", 0.0, visible)
	if _shadow != null:
		tw.tween_property(_shadow, "modulate:a", 0.0, visible)


# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not _spin_active:
		return
	_spin_elapsed += delta
	var t: float = clampf(_spin_elapsed / maxf(_spin_total, 0.001), 0.0, 1.0)
	var k: float = t * t
	var outer_speed: float = lerpf(OUTER_SPIN_START, OUTER_SPIN_END, k)
	var inner_speed: float = lerpf(INNER_SPIN_START, INNER_SPIN_END, k)
	if _outer != null and is_instance_valid(_outer):
		_outer.rotation_degrees += outer_speed * delta
	if _inner != null and is_instance_valid(_inner):
		_inner.rotation_degrees += inner_speed * delta


func _textures_for(flavor: int) -> Array:
	match flavor:
		Flavor.BROOD: return [TEX_BROOD_OUTER, TEX_BROOD_INNER, TEX_BROOD_GLYPH]
		Flavor.BROOD_DARK: return [TEX_BROOD_OUTER, TEX_BROOD_INNER, TEX_BROOD_GLYPH]
		Flavor.SPARK: return [TEX_SPARK_OUTER, TEX_SPARK_INNER, TEX_SPARK_GLYPH]
		_: return [TEX_SUMMON_OUTER, TEX_SUMMON_INNER, TEX_SUMMON_GLYPH]


func _make_sigil_sprite(tex: Texture2D, target_px: float, tint: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	var tex_size: float = maxf(tex.get_width(), tex.get_height())
	var k: float = target_px / maxf(tex_size, 1.0)
	s.scale = Vector2(k, k)
	s.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	return s


## Soft rising particles — generic upward drift for non-Brood flavors.
func _spawn_rise_particles(primary: Color, secondary: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 28
	p.lifetime = 0.65
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 30.0
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.initial_velocity_min = 45.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2.ZERO
	p.damping_min = 1.0
	p.damping_max = 1.8
	p.scale_amount_min = 1.5
	p.scale_amount_max = 2.8
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = scale_curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(primary.r, primary.g, primary.b, 0.9))
	ramp.add_point(0.6, Color(secondary.r, secondary.g, secondary.b, 0.55))
	ramp.set_color(1, Color(secondary.r, secondary.g, secondary.b, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p)
	p.emitting = true
	return p


## Spark particles — emit on a ring outside the sigil and fly inward toward
## center, additive blend, bright and fast.
func _spawn_spark_inward_particles(primary: Color, secondary: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 24
	p.lifetime = 0.45
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = 75.0
	p.direction = Vector2(1, 0)
	p.spread = 180.0
	p.initial_velocity_min = -220.0
	p.initial_velocity_max = -160.0
	p.gravity = Vector2.ZERO
	p.damping_min = 0.0
	p.damping_max = 0.0
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.055
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.6))
	scale_curve.add_point(Vector2(0.8, 1.1))
	scale_curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = scale_curve
	p.texture = TEX_SPARK
	p.color = Color(primary.r, primary.g, primary.b, 1.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.95))
	ramp.add_point(0.65, Color(secondary.r, secondary.g, secondary.b, 0.85))
	ramp.set_color(1, Color(secondary.r, secondary.g, secondary.b, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p)
	p.emitting = true
	return p


## Blood drip particles — spawn above the sigil, fall under gravity, fade near
## the floor.
func _spawn_blood_drip_particles(_primary: Color, _secondary: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 15
	p.lifetime = 0.90
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(65.0, 4.0)
	p.position = Vector2(0.0, -65.0)
	p.direction = Vector2(0, 1)
	p.spread = 10.0
	p.initial_velocity_min = 35.0
	p.initial_velocity_max = 85.0
	p.gravity = Vector2(0, 280.0)
	p.damping_min = 0.0
	p.damping_max = 0.2
	p.scale_amount_min = 0.015
	p.scale_amount_max = 0.025
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.7))
	scale_curve.add_point(Vector2(0.4, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.4))
	p.scale_amount_curve = scale_curve
	p.color = Color(1.0, 1.0, 1.0, 1.0)
	p.texture = TEX_BLOOD_DROP
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.add_point(0.80, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	return p
