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

const CORE_TEXTURE_PATH := "res://assets/animation/void_bolt_core.png"
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

func _build_core() -> void:
	_core = Sprite2D.new()
	if ResourceLoader.exists(CORE_TEXTURE_PATH):
		_core.texture = load(CORE_TEXTURE_PATH)
		# Scale texture down to CORE_SIZE
		var tex_size: float = _core.texture.get_width()
		if tex_size > 0:
			_core.scale = Vector2.ONE * (CORE_SIZE / tex_size)
	_core.modulate = Color(1.2, 1.0, 1.4, 1.0)  # slight purple-bright tint
	add_child(_core)

func _build_particles() -> void:
	_particles = CPUParticles2D.new()
	_particles.emitting = true
	_particles.amount = 40
	_particles.lifetime = 0.8
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.local_coords = false  # particles stay in world space (trail behind)

	# Emission
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = 10.0

	# Movement — slight outward drift
	_particles.direction = Vector2(0, 0)
	_particles.spread = 180.0
	_particles.initial_velocity_min = 20.0
	_particles.initial_velocity_max = 60.0
	_particles.gravity = Vector2.ZERO

	# Size — larger particles that shrink over lifetime
	_particles.scale_amount_min = 5.0
	_particles.scale_amount_max = 9.0
	_particles.scale_amount_curve = _make_fade_curve()

	# Color — bright purple to transparent, longer visible
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.85, 0.45, 1.0, 0.9))
	gradient.add_point(0.3, Color(0.6, 0.2, 0.9, 0.7))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.2, 0.05, 0.4, 0.0))
	_particles.color_ramp = gradient

	add_child(_particles)

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
	# Stop trail emission
	if _particles:
		_particles.emitting = false

	# Impact burst — spawn a quick expanding ring + flash
	_spawn_impact_burst()

	# Fade out core
	if _core:
		var fade_tween := create_tween()
		fade_tween.tween_property(_core, "modulate:a", 0.0, 0.15)
		fade_tween.tween_property(_core, "scale", _core.scale * 1.8, 0.15)

	# Wait for particles to finish, then clean up
	await get_tree().create_timer(0.5).timeout
	finished.emit()
	queue_free()

func _spawn_impact_burst() -> void:
	var burst := CPUParticles2D.new()
	burst.emitting = true
	burst.amount = 16
	burst.lifetime = 0.35
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.local_coords = true

	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 4.0

	burst.direction = Vector2(0, 0)
	burst.spread = 180.0
	burst.initial_velocity_min = 80.0
	burst.initial_velocity_max = 180.0
	burst.gravity = Vector2.ZERO

	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 4.0
	burst.scale_amount_curve = _make_fade_curve()

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.8, 1.0, 1.0))   # Bright white-purple
	gradient.set_color(1, Color(0.5, 0.15, 0.7, 0.0))   # Fade to transparent purple
	burst.color_ramp = gradient

	add_child(burst)

	# Flash — bright expanding circle using the core texture
	var flash := Sprite2D.new()
	if ResourceLoader.exists(CORE_TEXTURE_PATH):
		flash.texture = load(CORE_TEXTURE_PATH)
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
