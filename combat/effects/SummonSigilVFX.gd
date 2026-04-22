## SummonSigilVFX.gd
## Generic summoning sigil VFX — reusable across sources (Brood Call, on-death
## summons, Void Spark, future spells). Three procedurally composed sprites
## (outer ring, inner ring, center glyph) retinted by a flavor palette sit on
## the target slot, bloom in, hold while counter-rotating, then collapse before
## the minion is placed.
##
## Layers (bottom → top):
##   1. Ground shadow (depth anchor)
##   2. Additive halo (radial glow, tinted to flavor)
##   3. Outer ring sprite — rotates clockwise, accelerates across the hold
##   4. Inner ring sprite — rotates counter-clockwise, accelerates across the hold
##   5. Center glyph — pulses scale + flavor-specific particles
##
## Rings start small and grow during ramp-up, spin accelerates toward the end,
## and the whole sigil pulses once on summon completion before collapse.
##
## Fire-and-forget via vfx_controller.spawn. Emits impact_hit right before
## collapse (the moment the summon "lands"), then finished after collapse.
class_name SummonSigilVFX
extends BaseVfx

## Flavor presets — pick at call site to match the summon source.
## Each flavor selects its own textures, palette, and particle style.
enum Flavor { VOID_GREEN, EMBER_RED, HOLY_GOLD, FROST_BLUE, ARCANE_PURPLE, BROOD, SPARK, BROOD_DARK }

# Default/generic summon sigil art.
const TEX_SUMMON_OUTER: Texture2D = preload("res://assets/art/fx/casting_glyphs/summon_sigil/summon_outer_ring.png")
const TEX_SUMMON_INNER: Texture2D = preload("res://assets/art/fx/casting_glyphs/summon_sigil/summon_inner_ring.png")
const TEX_SUMMON_GLYPH: Texture2D = preload("res://assets/art/fx/casting_glyphs/summon_sigil/summon_center_glyph.png")

# Brood Call-specific sigil art.
const TEX_BROOD_OUTER: Texture2D  = preload("res://assets/art/fx/casting_glyphs/brood_sigil/brood_outer_ring.png")
const TEX_BROOD_INNER: Texture2D  = preload("res://assets/art/fx/casting_glyphs/brood_sigil/brood_inner_ring.png")
const TEX_BROOD_GLYPH: Texture2D  = preload("res://assets/art/fx/casting_glyphs/brood_sigil/brood_center_glyph.png")

# Spark Summon-specific sigil art.
const TEX_SPARK_OUTER: Texture2D  = preload("res://assets/art/fx/casting_glyphs/spark_sigil/spark_outer_ring.png")
const TEX_SPARK_INNER: Texture2D  = preload("res://assets/art/fx/casting_glyphs/spark_sigil/spark_inner_ring.png")
const TEX_SPARK_GLYPH: Texture2D  = preload("res://assets/art/fx/casting_glyphs/spark_sigil/spark_center_glyph.png")

const TEX_GLOW: Texture2D = preload("res://assets/art/fx/glow_soft.png")
const TEX_BLOOD_DROP: Texture2D = preload("res://assets/art/fx/blood_drop.png")
const TEX_SPARK: Texture2D = preload("res://assets/art/fx/spark_sprite.png")

# Primary = rings + glyph tint. Secondary = halo + particle tint.
const _FLAVOR_TABLE: Dictionary = {
	Flavor.VOID_GREEN:    [Color(0.55, 1.00, 0.45, 1.0), Color(0.20, 0.85, 0.15, 1.0)],
	Flavor.EMBER_RED:     [Color(1.00, 0.70, 0.30, 1.0), Color(0.95, 0.25, 0.10, 1.0)],
	Flavor.HOLY_GOLD:     [Color(1.00, 0.95, 0.65, 1.0), Color(1.00, 0.80, 0.25, 1.0)],
	Flavor.FROST_BLUE:    [Color(0.75, 0.95, 1.00, 1.0), Color(0.35, 0.70, 1.00, 1.0)],
	Flavor.ARCANE_PURPLE: [Color(0.90, 0.70, 1.00, 1.0), Color(0.60, 0.25, 0.90, 1.0)],
	# Brood: sickly green rings + deep dark-red halo (flesh-rite read).
	Flavor.BROOD:         [Color(0.45, 1.00, 0.35, 1.0), Color(0.55, 0.05, 0.05, 1.0)],
	# Spark: bright cyan-white rings + violet halo (primary tints rings; halo
	# uses a 2-stop white→purple gradient built separately in _play).
	Flavor.SPARK:         [Color(0.85, 0.95, 1.00, 1.0), Color(0.55, 0.30, 0.95, 1.0)],
	# Brood Dark: acid-green rings + near-black halo (Matriarch's Broodling
	# death-summon read — distinct from BROOD's bloody flesh-rite).
	Flavor.BROOD_DARK:    [Color(0.55, 1.00, 0.45, 1.0), Color(0.03, 0.08, 0.03, 1.0)],
}

# ── Sizing (fits within a board slot) ───────────────────────────────────────
const OUTER_SIZE: float  = 150.0
const INNER_SIZE: float  = 108.0
const GLYPH_SIZE: float  = 60.0
const HALO_START: float  = 120.0
const HALO_END: float    = 240.0
const SHADOW_SIZE: float = 150.0

# ── Timing ──────────────────────────────────────────────────────────────────
const RAMP_DURATION: float     = 0.45   # rings grow in + start slow spin
const HOLD_DURATION: float     = 0.70   # spin accelerates, particles flow
const COMPLETE_PULSE: float    = 0.22   # summon-complete pulse (scale + bright)
const COLLAPSE_DURATION: float = 0.22

# ── Rotation — start slow, accelerate to final speed over ramp+hold ─────────
const OUTER_SPIN_START: float =  40.0
const OUTER_SPIN_END: float   = 260.0
const INNER_SPIN_START: float = -60.0
const INNER_SPIN_END: float   = -340.0

var _target_slot: BoardSlot = null
var _flavor: int = Flavor.VOID_GREEN

var _outer: Sprite2D = null
var _inner: Sprite2D = null

var _spin_active: bool = false
var _spin_elapsed: float = 0.0
# Used to map elapsed time → spin speed ramp (start → end across ramp+hold).
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

	var palette: Array = _FLAVOR_TABLE.get(_flavor, _FLAVOR_TABLE[Flavor.VOID_GREEN])
	var primary: Color = palette[0]
	var secondary: Color = palette[1]

	var textures: Array = _textures_for(_flavor)
	var tex_outer: Texture2D = textures[0]
	var tex_inner: Texture2D = textures[1]
	var tex_glyph: Texture2D = textures[2]

	# SFX per flavor. Everything else rides on the portal-open drone.
	match _flavor:
		Flavor.BROOD:
			AudioManager.play_sfx("res://assets/audio/sfx/spells/brood_call.wav", -8.0)
		Flavor.SPARK:
			AudioManager.play_sfx("res://assets/audio/sfx/minions/spark_summon.wav", -10.0)
		_:
			AudioManager.play_sfx("res://assets/audio/sfx/spells/portal_open.wav", -8.0)

	# ── Layer 1: Ground shadow ──────────────────────────────────────────────
	var shadow := Sprite2D.new()
	shadow.texture = TEX_GLOW
	shadow.modulate = Color(0.0, 0.0, 0.0, 0.35)
	shadow.z_index = -1
	var shadow_tex_size: float = maxf(TEX_GLOW.get_width(), TEX_GLOW.get_height())
	var shadow_scale: float = SHADOW_SIZE / maxf(shadow_tex_size, 1.0)
	shadow.scale = Vector2(shadow_scale, shadow_scale * 0.45)
	shadow.position = Vector2(0, 28)
	add_child(shadow)

	# ── Layer 2: Additive halo — purple/secondary tint, soft and restrained
	# so it doesn't wash out the sigil lines. SPARK uses a dimmer peak alpha
	# and smaller size so the halo stays inside the slot.
	var halo := Sprite2D.new()
	halo.texture = CastingWindupVFX._get_glow_texture()
	var halo_mat := CanvasItemMaterial.new()
	halo_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = halo_mat
	halo.modulate = Color(secondary.r, secondary.g, secondary.b, 0.0)
	var halo_tex_size: float = float(halo.texture.get_width())

	# Per-flavor halo sizing. SPARK is smaller + dimmer so rings stay readable.
	var halo_start_px: float = HALO_START
	var halo_end_px: float = HALO_END
	var halo_peak_alpha: float = 0.75
	if _flavor == Flavor.SPARK:
		halo_start_px = 70.0
		halo_end_px   = 110.0
		halo_peak_alpha = 0.45

	halo.scale = Vector2.ONE * (halo_start_px / maxf(halo_tex_size, 1.0))
	add_child(halo)

	var halo_hold_scale: Vector2 = Vector2.ONE * (halo_end_px / maxf(halo_tex_size, 1.0))
	var halo_pulse_scale: Vector2 = halo_hold_scale * 1.20
	var htw := create_tween()
	htw.set_parallel(true)
	htw.tween_property(halo, "modulate:a", halo_peak_alpha, RAMP_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	htw.tween_property(halo, "scale", halo_hold_scale, RAMP_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Per-flavor ring/glyph sizing. SPARK is tighter so it fits inside a slot.
	var outer_size_px: float = OUTER_SIZE
	var inner_size_px: float = INNER_SIZE
	var glyph_size_px: float = GLYPH_SIZE
	if _flavor == Flavor.SPARK:
		outer_size_px = 95.0
		inner_size_px = 70.0
		glyph_size_px = 40.0

	# ── Layer 3: Outer ring (rings start SMALL and grow during ramp-up) ─────
	_outer = _make_sigil_sprite(tex_outer, outer_size_px, primary)
	add_child(_outer)

	# ── Layer 4: Inner ring ─────────────────────────────────────────────────
	_inner = _make_sigil_sprite(tex_inner, inner_size_px, primary)
	add_child(_inner)

	# ── Layer 5: Center glyph ───────────────────────────────────────────────
	var glyph := _make_sigil_sprite(tex_glyph, glyph_size_px, primary)
	var glyph_mat := CanvasItemMaterial.new()
	glyph_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glyph.material = glyph_mat
	add_child(glyph)

	# Bloom-in: rings start very small + faded, grow to full.
	var target_outer_scale: Vector2 = _outer.scale
	var target_inner_scale: Vector2 = _inner.scale
	var target_glyph_scale: Vector2 = glyph.scale
	_outer.scale = target_outer_scale * 0.35
	_inner.scale = target_inner_scale * 0.25
	glyph.scale  = target_glyph_scale  * 0.30

	var rtw := create_tween()
	rtw.set_parallel(true)
	rtw.tween_property(_outer, "modulate:a", 1.0, RAMP_DURATION * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rtw.tween_property(_outer, "scale", target_outer_scale, RAMP_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rtw.tween_property(_inner, "modulate:a", 1.0, RAMP_DURATION * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rtw.tween_property(_inner, "scale", target_inner_scale, RAMP_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05)
	rtw.tween_property(glyph, "modulate:a", 1.0, RAMP_DURATION * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(0.10)
	rtw.tween_property(glyph, "scale", target_glyph_scale, RAMP_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.10)

	# Gentle glyph pulse across the hold phase.
	var pulse := create_tween().set_loops()
	pulse.tween_property(glyph, "scale", target_glyph_scale * 1.15, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glyph, "scale", target_glyph_scale, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Flavor-specific particles.
	var particles: CPUParticles2D
	match _flavor:
		Flavor.BROOD:
			particles = _spawn_blood_drip_particles(primary, secondary)
		Flavor.BROOD_DARK:
			particles = _spawn_spark_inward_particles(primary, secondary)
		Flavor.SPARK:
			particles = _spawn_spark_inward_particles(primary, secondary)
		_:
			particles = _spawn_rise_particles(primary, secondary)

	# Rotation accelerates from START → END across ramp+hold via _process.
	_spin_total = RAMP_DURATION + HOLD_DURATION
	_spin_elapsed = 0.0
	_spin_active = true

	await get_tree().create_timer(RAMP_DURATION + HOLD_DURATION).timeout
	if not is_inside_tree():
		finished.emit()
		queue_free()
		return

	particles.emitting = false
	pulse.kill()

	# ── Summon-complete pulse — brighten + scale up, then settle ────────────
	# Tells the player the ritual finished; the minion lands on the pulse peak.
	var pulse_tw := create_tween().set_parallel(true)
	pulse_tw.tween_property(_outer, "scale", target_outer_scale * 1.18, COMPLETE_PULSE * 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse_tw.tween_property(_inner, "scale", target_inner_scale * 1.22, COMPLETE_PULSE * 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse_tw.tween_property(glyph, "scale", target_glyph_scale * 1.35, COMPLETE_PULSE * 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse_tw.tween_property(halo, "scale", halo_pulse_scale, COMPLETE_PULSE * 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pulse_tw.tween_property(halo, "modulate:a", 1.0, COMPLETE_PULSE * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(COMPLETE_PULSE * 0.5).timeout
	if not is_inside_tree():
		finished.emit()
		queue_free()
		return

	# ── Collapse ────────────────────────────────────────────────────────────
	impact_hit.emit(0)

	_spin_active = false
	var collapse := create_tween().set_parallel(true)
	collapse.tween_property(_outer, "modulate:a", 0.0, COLLAPSE_DURATION)
	collapse.tween_property(_outer, "scale", target_outer_scale * 0.3, COLLAPSE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	collapse.tween_property(_inner, "modulate:a", 0.0, COLLAPSE_DURATION)
	collapse.tween_property(_inner, "scale", target_inner_scale * 0.3, COLLAPSE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	collapse.tween_property(glyph, "modulate:a", 0.0, COLLAPSE_DURATION)
	collapse.tween_property(glyph, "scale", target_glyph_scale * 0.2, COLLAPSE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	collapse.tween_property(halo, "modulate:a", 0.0, COLLAPSE_DURATION)
	collapse.tween_property(shadow, "modulate:a", 0.0, COLLAPSE_DURATION)

	await get_tree().create_timer(COLLAPSE_DURATION + 0.05).timeout
	finished.emit()
	queue_free()


# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not _spin_active:
		return
	_spin_elapsed += delta
	var t: float = clampf(_spin_elapsed / maxf(_spin_total, 0.001), 0.0, 1.0)
	# Quadratic ease-in: slow at start, fast at end.
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


## Spark particles — spawn on a ring outside the sigil and fly inward toward
## center, additive blend, bright and fast. Uses the spark sprite directly.
func _spawn_spark_inward_particles(primary: Color, secondary: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 24
	p.lifetime = 0.45
	p.local_coords = true
	# Emit on a ring just inside the slot edge so sparks stay contained.
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = 75.0
	# Per-particle inward velocity: negative speed with 360° spread flies
	# each spark toward the center regardless of spawn angle.
	p.direction = Vector2(1, 0)
	p.spread = 180.0
	p.initial_velocity_min = -220.0
	p.initial_velocity_max = -160.0
	p.gravity = Vector2.ZERO
	p.damping_min = 0.0
	p.damping_max = 0.0
	# Spark sprite is ~260 px — small scale keeps each one ~8–14 px.
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.055
	# Sparks grow slightly as they converge, then vanish at center.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.6))
	scale_curve.add_point(Vector2(0.8, 1.1))
	scale_curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = scale_curve
	p.texture = TEX_SPARK
	# Base color carries the flavor's cool-white so sparks read bright; ramp
	# tints slightly purple on ingress then fades to transparent at center.
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


## Blood drip particles — spawn above the sigil, fall downward under gravity,
## grow slightly as they fall (stretched teardrop read), fade near the floor.
func _spawn_blood_drip_particles(primary: Color, secondary: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 15
	p.lifetime = 0.90
	p.local_coords = true
	# Emit from a wide thin band above the sigil so drops form along the top arc.
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(65.0, 4.0)
	p.position = Vector2(0.0, -65.0)  # above the ring
	p.direction = Vector2(0, 1)       # downward
	p.spread = 10.0
	p.initial_velocity_min = 35.0
	p.initial_velocity_max = 85.0
	p.gravity = Vector2(0, 280.0)     # accelerate downward
	p.damping_min = 0.0
	p.damping_max = 0.2
	# blood_drop.png is ~260×260 — smaller scale keeps each drop ~6–10 px.
	p.scale_amount_min = 0.015
	p.scale_amount_max = 0.025
	# Drops grow slightly then fade out near the bottom.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.7))
	scale_curve.add_point(Vector2(0.4, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.4))
	p.scale_amount_curve = scale_curve
	# Blood-drop asset already looks like a droplet — keep base color white so
	# the texture's native dark red shows. Ramp only fades alpha over lifetime.
	p.color = Color(1.0, 1.0, 1.0, 1.0)
	p.texture = TEX_BLOOD_DROP
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.add_point(0.80, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	p.color_ramp = ramp
	# Normal blend (not additive) — blood should look dense/wet, not glowing.
	add_child(p)
	p.emitting = true
	return p
