## VoidBoltProjectile.gd
## Animated void bolt projectile that flies from source to target with
## a spinning core, particle tail, and impact burst.
##
## Usage:
##   var bolt := VoidBoltProjectile.create(from_global, to_global)
##   add_child(bolt)
##   await bolt.finished
class_name VoidBoltProjectile
extends Node2D

signal finished
signal impact_hit  ## Emitted the moment the bolt reaches the target (before cleanup)

const CORE_TEXTURE: Texture2D = preload("res://assets/animation/spells/void_bolt/void_bolt_core.png")
const CORE_SIZE := 48.0          ## Display size of the core sprite
const FLIGHT_DURATION := 0.8     ## Seconds to reach target
const ARC_HEIGHT := 60.0         ## Peak height of the arc above the straight line
const SPIN_SPEED := 12.0         ## Radians per second
const PULSE_MIN := 0.85
const PULSE_MAX := 1.15
const PULSE_SPEED := 8.0         ## Scale pulse cycles per second

var _from: Vector2
var _to: Vector2
var _core: Sprite2D
var _particles: CPUParticles2D
var _sparks: CPUParticles2D
var _elapsed: float = 0.0
var _active: bool = true

static func create(from_pos: Vector2, to_pos: Vector2) -> VoidBoltProjectile:
	var bolt := VoidBoltProjectile.new()
	bolt._from = from_pos
	bolt._to = to_pos
	bolt.z_index = 200
	return bolt

func _ready() -> void:
	position = _from
	_build_core()
	_build_particles()
	_build_sparks()

func _build_core() -> void:
	_core = Sprite2D.new()
	_core.texture = CORE_TEXTURE
	var tex_size: float = _core.texture.get_width()
	if tex_size > 0:
		_core.scale = Vector2.ONE * (CORE_SIZE / tex_size)
	_core.modulate = Color(1.2, 1.0, 1.4, 1.0)  # slight purple-bright tint
	add_child(_core)

func _build_particles() -> void:
	_particles = CPUParticles2D.new()
	_particles.emitting = true
	_particles.amount = 48
	_particles.lifetime = 0.7
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.local_coords = false  # particles stay in world space (trail behind)

	# Soft circle texture so particles aren't squares
	_particles.texture = _make_soft_circle()

	# Emission — tight cluster around the core
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = 5.0

	# Movement — gentle drift outward
	_particles.direction = Vector2(0, 0)
	_particles.spread = 180.0
	_particles.initial_velocity_min = 8.0
	_particles.initial_velocity_max = 25.0
	_particles.gravity = Vector2.ZERO

	# Size — soft dots that shrink over lifetime
	_particles.scale_amount_min = 0.18
	_particles.scale_amount_max = 0.4
	_particles.scale_amount_curve = _make_fade_curve()

	# Color — bright purple core fading to transparent
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.9, 0.55, 1.0, 0.85))
	gradient.add_point(0.35, Color(0.6, 0.25, 0.9, 0.5))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.3, 0.1, 0.5, 0.0))
	_particles.color_ramp = gradient

	add_child(_particles)

func _build_sparks() -> void:
	_sparks = CPUParticles2D.new()
	_sparks.emitting = true
	_sparks.amount = 18
	_sparks.lifetime = 0.35
	_sparks.one_shot = false
	_sparks.explosiveness = 0.0
	_sparks.randomness = 1.0
	_sparks.local_coords = false

	_sparks.texture = _make_soft_circle()

	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 8.0

	# Sparks shoot outward faster than trail
	_sparks.direction = Vector2(0, 0)
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 40.0
	_sparks.initial_velocity_max = 120.0
	_sparks.damping_min = 80.0
	_sparks.damping_max = 150.0
	_sparks.gravity = Vector2.ZERO

	# Tiny bright dots
	_sparks.scale_amount_min = 0.06
	_sparks.scale_amount_max = 0.14

	# Flash in bright, vanish fast
	var spark_grad := Gradient.new()
	spark_grad.set_color(0, Color(1.0, 0.9, 1.0, 1.0))    # white-hot flash
	spark_grad.add_point(0.15, Color(0.95, 0.6, 1.0, 0.9)) # bright purple
	spark_grad.set_color(spark_grad.get_point_count() - 1, Color(0.5, 0.2, 0.8, 0.0))
	_sparks.color_ramp = spark_grad

	add_child(_sparks)

func _process(delta: float) -> void:
	if not _active:
		return

	_elapsed += delta
	var t: float = clampf(_elapsed / FLIGHT_DURATION, 0.0, 1.0)

	# Lerp position along arc
	var straight: Vector2 = _from.lerp(_to, t)
	# Parabolic arc: peak at t=0.5
	var arc_offset: float = -4.0 * ARC_HEIGHT * t * (t - 1.0)
	position = straight + Vector2(0, -arc_offset)

	# Spin the core
	if _core:
		_core.rotation += SPIN_SPEED * delta
		# Pulse scale
		var pulse: float = lerpf(PULSE_MIN, PULSE_MAX, (sin(_elapsed * PULSE_SPEED * TAU) + 1.0) * 0.5)
		var base_scale: float = CORE_SIZE / maxf(_core.texture.get_width(), 1) if _core.texture else 0.15
		_core.scale = Vector2.ONE * base_scale * pulse

	# Stretch in direction of travel (motion blur)
	var dir: Vector2 = (_to - _from).normalized()
	rotation = dir.angle()

	if t >= 1.0:
		_active = false
		_on_impact()

func _on_impact() -> void:
	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_bolt_impact.wav")
	impact_hit.emit()
	# Stop trail and spark emission
	if _particles:
		_particles.emitting = false
	if _sparks:
		_sparks.emitting = false

	# Impact burst — spawn a quick expanding ring + flash
	_spawn_impact_burst()

	# Fade out core
	if _core:
		var fade_tween := create_tween()
		fade_tween.tween_property(_core, "modulate:a", 0.0, 0.15)
		fade_tween.tween_property(_core, "scale", _core.scale * 1.8, 0.15)

	# Wait for particles to finish, then clean up
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	finished.emit()
	queue_free()

func _spawn_impact_burst() -> void:
	var burst := CPUParticles2D.new()
	burst.emitting = true
	burst.amount = 12
	burst.lifetime = 0.3
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.local_coords = true

	burst.texture = _make_soft_circle()

	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 3.0

	burst.direction = Vector2(0, 0)
	burst.spread = 180.0
	burst.initial_velocity_min = 60.0
	burst.initial_velocity_max = 140.0
	burst.gravity = Vector2.ZERO

	burst.scale_amount_min = 0.1
	burst.scale_amount_max = 0.25
	burst.scale_amount_curve = _make_fade_curve()

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.85, 1.0, 1.0))   # Bright white-purple
	gradient.set_color(1, Color(0.5, 0.15, 0.7, 0.0))   # Fade to transparent purple
	burst.color_ramp = gradient

	add_child(burst)

	# Flash — bright expanding circle using the core texture
	var flash := Sprite2D.new()
	flash.texture = CORE_TEXTURE
	var tex_size: float = flash.texture.get_width()
	if tex_size > 0:
		flash.scale = Vector2.ONE * (30.0 / tex_size)
	flash.modulate = Color(0.8, 0.5, 1.0, 0.7)
	add_child(flash)

	var flash_tween := create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", flash.scale * 4.0, 0.25).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.25)

func _make_fade_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	return curve

## Generate a 32x32 soft radial gradient circle texture at runtime.
## Used as particle texture so particles render as soft dots instead of squares.
static func _make_soft_circle() -> ImageTexture:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	for y in size:
		for x in size:
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha: float = clampf(1.0 - dist / radius, 0.0, 1.0)
			alpha *= alpha  # quadratic falloff for softer edges
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)
