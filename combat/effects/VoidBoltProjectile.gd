## VoidBoltProjectile.gd
## Animated void bolt projectile — a bright spinning core with a burning
## purple flame tail streaming behind it.
##
## Layers:
##   1. Core sprite (spinning, pulsing)
##   2. Core glow (additive oversized soft circle — energy halo)
##   3. Inner flame trail (dense, tight, bright — the hot exhaust)
##   4. Outer flame wisps (wider, slower, darker — billowing edges)
##   5. Ember sparks (tiny bright dots shed from the flame)
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name VoidBoltProjectile
extends BaseVfx

const CORE_TEXTURE: Texture2D = preload("res://assets/animation/spells/void_bolt/void_bolt_core.png")
const CORE_SIZE := 48.0          ## Display size of the core sprite
const GLOW_SIZE := 96.0          ## Additive glow halo around core
const FLIGHT_DURATION := 0.8     ## Seconds to reach target
const ARC_HEIGHT := 60.0         ## Peak height of the arc above the straight line
const SPIN_SPEED := 12.0         ## Radians per second
const PULSE_MIN := 0.85
const PULSE_MAX := 1.15
const PULSE_SPEED := 8.0         ## Scale pulse cycles per second

var _from: Vector2
var _to: Vector2
var _core: Sprite2D
var _glow: Sprite2D
var _flame_inner: CPUParticles2D
var _flame_outer: CPUParticles2D
var _embers: CPUParticles2D
var _elapsed: float = 0.0
var _active: bool = true
var _prev_pos: Vector2

## Cached procedural textures (created once, shared by all instances)
static var _flame_tex: ImageTexture
static var _circle_tex: ImageTexture
static var _ember_tex: ImageTexture

static func create(from_pos: Vector2, to_pos: Vector2) -> VoidBoltProjectile:
	var bolt := VoidBoltProjectile.new()
	bolt._from = from_pos
	bolt._to = to_pos
	bolt.z_index = 200
	return bolt

func _play() -> void:
	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_bolt_cast.wav")
	position = _from
	_prev_pos = _from
	_ensure_textures()
	_build_core()
	_build_glow()
	_build_flame_inner()
	_build_flame_outer()
	_build_embers()

# ═════════════════════════════════════════════════════════════════════════════
# Construction
# ═════════════════════════════════════════════════════════════════════════════

func _build_core() -> void:
	_core = Sprite2D.new()
	_core.texture = CORE_TEXTURE
	var tex_size: float = _core.texture.get_width()
	if tex_size > 0:
		_core.scale = Vector2.ONE * (CORE_SIZE / tex_size)
	_core.modulate = Color(1.2, 1.0, 1.4, 1.0)
	add_child(_core)

func _build_glow() -> void:
	_glow = Sprite2D.new()
	_glow.texture = _circle_tex
	var tex_size: float = _glow.texture.get_width()
	_glow.scale = Vector2.ONE * (GLOW_SIZE / maxf(tex_size, 1.0))
	_glow.modulate = Color(0.7, 0.3, 1.0, 0.5)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	add_child(_glow)

func _build_flame_inner() -> void:
	_flame_inner = CPUParticles2D.new()
	_flame_inner.emitting = true
	_flame_inner.amount = 64
	_flame_inner.lifetime = 0.45
	_flame_inner.one_shot = false
	_flame_inner.explosiveness = 0.0
	_flame_inner.local_coords = false  # world space — forms the trail

	_flame_inner.texture = _flame_tex

	# Wide emission around the core — particles born across the full core width
	_flame_inner.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_flame_inner.emission_sphere_radius = 16.0

	# Particles flow backward — direction will be updated in _process
	_flame_inner.direction = Vector2(-1, 0)
	_flame_inner.spread = 30.0  # Wide cone at root, particles converge as they shrink
	_flame_inner.initial_velocity_min = 25.0
	_flame_inner.initial_velocity_max = 65.0
	_flame_inner.damping_min = 35.0
	_flame_inner.damping_max = 70.0
	_flame_inner.gravity = Vector2(0, -12.0)  # Slight upward drift (heat rises)

	# Size — born big (wraps the core), shrinks to a point = comet taper
	_flame_inner.scale_amount_min = 0.6
	_flame_inner.scale_amount_max = 1.0
	_flame_inner.scale_amount_curve = _make_flame_size_curve()

	# Rotation — random per particle for organic look
	_flame_inner.angle_min = -180.0
	_flame_inner.angle_max = 180.0

	# Color: white-hot core → bright purple → deep purple → transparent
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.9, 1.0, 0.95))       # white-hot birth
	gradient.add_point(0.15, Color(0.95, 0.6, 1.0, 0.9))     # bright lavender
	gradient.add_point(0.4, Color(0.7, 0.25, 0.95, 0.7))     # vivid purple
	gradient.add_point(0.7, Color(0.45, 0.1, 0.7, 0.4))      # deep purple
	gradient.set_color(gradient.get_point_count() - 1, Color(0.2, 0.05, 0.35, 0.0))  # fade out
	_flame_inner.color_ramp = gradient

	# Additive blending for that fiery glow
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flame_inner.material = mat

	add_child(_flame_inner)

func _build_flame_outer() -> void:
	_flame_outer = CPUParticles2D.new()
	_flame_outer.emitting = true
	_flame_outer.amount = 48
	_flame_outer.lifetime = 0.5
	_flame_outer.one_shot = false
	_flame_outer.explosiveness = 0.0
	_flame_outer.randomness = 0.4
	_flame_outer.local_coords = false

	_flame_outer.texture = _flame_tex

	_flame_outer.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_flame_outer.emission_sphere_radius = 22.0

	# Very wide cone — these form the fat billowing base around the core
	_flame_outer.direction = Vector2(-1, 0)
	_flame_outer.spread = 50.0
	_flame_outer.initial_velocity_min = 10.0
	_flame_outer.initial_velocity_max = 40.0
	_flame_outer.damping_min = 15.0
	_flame_outer.damping_max = 40.0
	_flame_outer.gravity = Vector2(0, -8.0)

	# Large particles — envelope the core area, shrink to wisps
	_flame_outer.scale_amount_min = 0.7
	_flame_outer.scale_amount_max = 1.2
	_flame_outer.scale_amount_curve = _make_flame_size_curve()

	_flame_outer.angle_min = -180.0
	_flame_outer.angle_max = 180.0

	# Darker purple, more transparent — wispy edges
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.7, 0.35, 0.95, 0.6))       # starts vivid
	gradient.add_point(0.3, Color(0.5, 0.15, 0.75, 0.4))     # deepens
	gradient.add_point(0.6, Color(0.3, 0.08, 0.5, 0.2))      # dark wisps
	gradient.set_color(gradient.get_point_count() - 1, Color(0.15, 0.03, 0.25, 0.0))
	_flame_outer.color_ramp = gradient

	add_child(_flame_outer)

func _build_embers() -> void:
	_embers = CPUParticles2D.new()
	_embers.emitting = true
	_embers.amount = 12
	_embers.lifetime = 0.3
	_embers.one_shot = false
	_embers.explosiveness = 0.0
	_embers.randomness = 1.0
	_embers.local_coords = false

	_embers.texture = _ember_tex

	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = 10.0

	# Embers shed sideways and backward from the flame
	_embers.direction = Vector2(-1, 0)
	_embers.spread = 55.0
	_embers.initial_velocity_min = 50.0
	_embers.initial_velocity_max = 130.0
	_embers.damping_min = 100.0
	_embers.damping_max = 200.0
	_embers.gravity = Vector2.ZERO

	# Tiny bright dots
	_embers.scale_amount_min = 0.08
	_embers.scale_amount_max = 0.18
	_embers.scale_amount_curve = _make_fade_curve()

	# Flash bright, die fast
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.85, 1.0, 1.0))
	gradient.add_point(0.2, Color(0.9, 0.5, 1.0, 0.8))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.4, 0.1, 0.6, 0.0))
	_embers.color_ramp = gradient

	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_embers.material = mat

	add_child(_embers)

# ═════════════════════════════════════════════════════════════════════════════
# Flight
# ═════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not _active:
		return

	_elapsed += delta
	var t: float = clampf(_elapsed / FLIGHT_DURATION, 0.0, 1.0)

	# Lerp position along arc
	var straight: Vector2 = _from.lerp(_to, t)
	var arc_offset: float = -4.0 * ARC_HEIGHT * t * (t - 1.0)
	position = straight + Vector2(0, -arc_offset)

	# Compute actual travel direction from frame-to-frame movement
	var travel_dir: Vector2 = (position - _prev_pos).normalized()
	if travel_dir.length_squared() < 0.001:
		travel_dir = (_to - _from).normalized()
	_prev_pos = position

	# Orient the whole node along travel direction
	rotation = travel_dir.angle()

	# Spin the core (independent of node rotation)
	if _core:
		_core.rotation += SPIN_SPEED * delta
		var pulse: float = lerpf(PULSE_MIN, PULSE_MAX, (sin(_elapsed * PULSE_SPEED * TAU) + 1.0) * 0.5)
		var base_scale: float = CORE_SIZE / maxf(_core.texture.get_width(), 1) if _core.texture else 0.15
		_core.scale = Vector2.ONE * base_scale * pulse

	# Pulse the glow
	if _glow:
		var glow_pulse: float = lerpf(0.4, 0.6, (sin(_elapsed * 6.0) + 1.0) * 0.5)
		_glow.modulate.a = glow_pulse

	# Point flame particles backward relative to travel direction
	# Particles use world-space direction, so we give them the opposite of travel
	var backward: Vector2 = -travel_dir
	if _flame_inner:
		_flame_inner.direction = backward
	if _flame_outer:
		_flame_outer.direction = backward
	if _embers:
		_embers.direction = backward

	if t >= 1.0:
		_active = false
		_on_impact()

# ═════════════════════════════════════════════════════════════════════════════
# Impact
# ═════════════════════════════════════════════════════════════════════════════

func _on_impact() -> void:
	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_bolt_impact.wav")
	impact_hit.emit(0)

	# Stop all flame emission
	if _flame_inner:
		_flame_inner.emitting = false
	if _flame_outer:
		_flame_outer.emitting = false
	if _embers:
		_embers.emitting = false

	# 6-layer volumetric impact explosion
	var impact_vfx := VoidBoltImpactVFX.create(global_position)
	get_parent().add_child(impact_vfx)

	# Fade out core + glow
	if _core:
		var fade_tween := create_tween()
		fade_tween.tween_property(_core, "modulate:a", 0.0, 0.15)
		fade_tween.tween_property(_core, "scale", _core.scale * 1.8, 0.15)
	if _glow:
		var glow_tween := create_tween()
		glow_tween.tween_property(_glow, "modulate:a", 0.0, 0.12)

	# Wait for trailing particles to finish, then clean up
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		return
	finished.emit()
	queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# Procedural Textures
# ═════════════════════════════════════════════════════════════════════════════

func _ensure_textures() -> void:
	if not _flame_tex:
		_flame_tex = _make_flame_texture()
	if not _circle_tex:
		_circle_tex = _make_soft_circle()
	if not _ember_tex:
		_ember_tex = _make_soft_circle_small()

## 32x32 teardrop / flame shape — bright rounded head tapering to a wispy tail.
## Oriented pointing RIGHT (+X) so it aligns with particle direction.
static func _make_flame_texture() -> ImageTexture:
	var w := 48
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cy: float = h * 0.5

	for y in h:
		for x in w:
			var px: float = x + 0.5
			var py: float = y + 0.5

			# Normalized coords: nx goes 0 (left/tail) to 1 (right/head)
			var nx: float = px / float(w)
			var ny: float = (py - cy) / (h * 0.5)  # -1 to 1

			# Width envelope: narrow at tail (nx=0), full at ~0.65, rounds off at head (nx=1)
			var width: float
			if nx < 0.65:
				# Tail to body: cubic ease-in for tapered tail
				var tail_t: float = nx / 0.65
				width = tail_t * tail_t * 0.9
			else:
				# Body to head: smooth round-off
				var head_t: float = (nx - 0.65) / 0.35
				width = 0.9 * (1.0 - head_t * head_t)

			# How far from center vs allowed width
			var dist_from_center: float = absf(ny)
			if width <= 0.001:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))
				continue

			var edge: float = clampf(1.0 - dist_from_center / maxf(width, 0.001), 0.0, 1.0)
			# Quadratic falloff for soft edges
			var alpha: float = edge * edge

			# Brighten the head, dim the tail
			var brightness: float = 0.4 + 0.6 * nx
			alpha *= brightness

			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(img)

## 32x32 soft radial circle — used for the core glow halo.
static func _make_soft_circle() -> ImageTexture:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	for y in size:
		for x in size:
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha: float = clampf(1.0 - dist / radius, 0.0, 1.0)
			alpha *= alpha
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

## 16x16 tiny soft dot — used for ember sparks.
static func _make_soft_circle_small() -> ImageTexture:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	for y in size:
		for x in size:
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha: float = clampf(1.0 - dist / radius, 0.0, 1.0)
			alpha *= alpha
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

## Curve: fat at birth (root of flame), tapers aggressively to a thin tip = comet shape.
static func _make_flame_size_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))   # full size at root
	curve.add_point(Vector2(0.08, 1.0))  # holds full briefly
	curve.add_point(Vector2(0.25, 0.6))  # starts tapering
	curve.add_point(Vector2(0.5, 0.25))  # noticeably thinner
	curve.add_point(Vector2(0.75, 0.08)) # wispy thin
	curve.add_point(Vector2(1.0, 0.0))   # gone
	return curve

static func _make_fade_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	return curve
