## VoidExecutionVFX.gd
## Animated VFX for the Void Execution spell.
## An arc sweeps down onto the target (revealed via shader wipe),
## then detonates with an explosion burst.
##
## Phases:
##   1. Arc        — top-to-bottom shader-wipe reveal of the descending arc
##   2. Hold       — brief pause + impact_hit + screen shake + SFX
##   3. Explosion  — burst sprite scales/fades + void particle burst
##
## Spawn via VfxController — do not parent manually.
class_name VoidExecutionVFX
extends BaseVfx

const ARC_TEXTURE: Texture2D = preload("res://assets/animation/spells/void_execution/void_execution_arc.png")
const EXPLOSION_TEXTURE: Texture2D = preload("res://assets/animation/spells/void_execution/void_execution_explosion.png")
const WIPE_SHADER: Shader = preload("res://combat/effects/void_execution_wipe.gdshader")

const DEFAULT_ARC_SIZE := 200.0
const DEFAULT_EXPLOSION_SIZE := 200.0

const ARC_DURATION       := 0.45
const HOLD_DURATION      := 0.10
const EXPLOSION_DURATION := 0.50
const PARTICLE_TAIL      := 0.30

const SHAKE_AMPLITUDE := 8.0
const SHAKE_TICKS := 6

var _target_pos: Vector2
var _shake_target: Node = null
var _arc_size: float = DEFAULT_ARC_SIZE
var _explosion_size: float = DEFAULT_EXPLOSION_SIZE

var _arc: Sprite2D = null
var _explosion: Sprite2D = null
var _arc_material: ShaderMaterial = null


static func create(target_pos: Vector2, size_scale: float = 1.0, shake_target: Node = null) -> VoidExecutionVFX:
	var vfx := VoidExecutionVFX.new()
	vfx._target_pos = target_pos
	vfx._arc_size = DEFAULT_ARC_SIZE * size_scale
	vfx._explosion_size = DEFAULT_EXPLOSION_SIZE * size_scale
	vfx._shake_target = shake_target
	vfx.z_index = 200
	return vfx


func _play() -> void:
	position = _target_pos
	_build_arc_node()
	_build_explosion_node()

	var seq := sequence()
	seq.on("impact", _on_impact)
	seq.run([
		VfxPhase.new("arc",       ARC_DURATION,       _build_arc_anim),
		VfxPhase.new("hold",      HOLD_DURATION,      Callable()) \
			.emits_at_start("impact") \
			.emits_at_start(VfxSequence.RESERVED_IMPACT_HIT),
		VfxPhase.new("explosion", EXPLOSION_DURATION, _build_explosion_anim),
		VfxPhase.new("tail",      PARTICLE_TAIL,      _spawn_void_particles),
	])


# ═════════════════════════════════════════════════════════════════════════════
# Construction (synchronous — runs from _play before sequence kicks off)
# ═════════════════════════════════════════════════════════════════════════════

func _build_arc_node() -> void:
	_arc = Sprite2D.new()
	_arc.texture = ARC_TEXTURE
	var tex_w: float = _arc.texture.get_width()
	var tex_h: float = _arc.texture.get_height()
	var scale_factor: float = _arc_size / maxf(tex_w, tex_h)
	_arc.scale = Vector2.ONE * scale_factor
	_arc.position = Vector2(0, -_arc_size * 0.3)
	_arc.modulate = Color(1.2, 1.0, 1.4, 1.0)

	_arc_material = ShaderMaterial.new()
	_arc_material.shader = WIPE_SHADER
	_arc_material.set_shader_parameter("progress", 0.0)
	_arc_material.set_shader_parameter("glow_strength", 0.0)
	_arc.material = _arc_material
	_arc.visible = false
	add_child(_arc)


func _build_explosion_node() -> void:
	_explosion = Sprite2D.new()
	_explosion.texture = EXPLOSION_TEXTURE
	var tex_size: float = maxf(_explosion.texture.get_width(), _explosion.texture.get_height())
	var scale_factor: float = _explosion_size / maxf(tex_size, 1.0)
	_explosion.scale = Vector2.ONE * scale_factor
	_explosion.modulate = Color(1.2, 1.0, 1.4, 0.0)
	_explosion.visible = false
	add_child(_explosion)


# ═════════════════════════════════════════════════════════════════════════════
# Phase builders
# ═════════════════════════════════════════════════════════════════════════════

func _build_arc_anim(duration: float) -> void:
	if _arc == null or _arc_material == null:
		return
	_arc.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_set_arc_progress, 0.0, 1.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(_set_arc_glow, 0.0, 2.5, duration * 0.6)
	tw.tween_method(_set_arc_glow, 2.5, 0.5, duration * 0.4).set_delay(duration * 0.6)


func _build_explosion_anim(duration: float) -> void:
	# Arc fades out as the explosion appears.
	if _arc != null and is_instance_valid(_arc):
		var arc_fade := create_tween()
		arc_fade.tween_property(_arc, "modulate:a", 0.0, 0.10)

	if _explosion == null:
		return
	_explosion.visible = true
	var target_scale: float = _explosion_size / maxf(_explosion.texture.get_width(), 1.0)
	_explosion.scale = Vector2.ONE * target_scale * 0.3
	_explosion.modulate = Color(1.5, 1.2, 1.8, 1.0)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_explosion, "scale", Vector2.ONE * target_scale * 1.1, duration * 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_explosion, "modulate", Color(1.0, 0.8, 1.2, 1.0), duration * 0.3)
	tw.tween_property(_explosion, "scale", Vector2.ONE * target_scale * 1.3, duration * 0.7) \
		.set_delay(duration * 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(_explosion, "modulate:a", 0.0, duration * 0.7) \
		.set_delay(duration * 0.3).set_ease(Tween.EASE_IN)


func _spawn_void_particles(_duration: float) -> void:
	var burst := CPUParticles2D.new()
	burst.emitting = true
	burst.amount = 24
	burst.lifetime = 0.5
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.local_coords = true
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 20.0
	burst.direction = Vector2(0, 0)
	burst.spread = 180.0
	burst.initial_velocity_min = 60.0
	burst.initial_velocity_max = 160.0
	burst.gravity = Vector2.ZERO
	burst.scale_amount_min = 3.0
	burst.scale_amount_max = 6.0
	var fade_curve := Curve.new()
	fade_curve.add_point(Vector2(0, 1))
	fade_curve.add_point(Vector2(1, 0))
	burst.scale_amount_curve = fade_curve
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.7, 1.0, 1.0))
	gradient.set_color(1, Color(0.4, 0.1, 0.6, 0.0))
	burst.color_ramp = gradient
	add_child(burst)


# ═════════════════════════════════════════════════════════════════════════════
# Listeners
# ═════════════════════════════════════════════════════════════════════════════

func _on_impact() -> void:
	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_execution.wav")
	if _shake_target != null:
		ScreenShakeEffect.shake(_shake_target, self, SHAKE_AMPLITUDE, SHAKE_TICKS)


# ═════════════════════════════════════════════════════════════════════════════
# Shader callbacks
# ═════════════════════════════════════════════════════════════════════════════

func _set_arc_progress(value: float) -> void:
	if _arc_material:
		_arc_material.set_shader_parameter("progress", value)


func _set_arc_glow(value: float) -> void:
	if _arc_material:
		_arc_material.set_shader_parameter("glow_strength", value)
