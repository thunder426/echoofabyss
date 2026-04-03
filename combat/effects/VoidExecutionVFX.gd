## VoidExecutionVFX.gd
## Animated VFX for the Void Execution spell.
## An arc sweeps down onto the target (revealed via shader wipe),
## then detonates with an explosion burst.
##
## Usage:
##   var vfx := VoidExecutionVFX.create(target_global_pos)
##   parent.add_child(vfx)
##   await vfx.finished
class_name VoidExecutionVFX
extends Node2D

signal finished
signal impact_hit  ## Emitted when the arc completes and explosion begins

const ARC_TEXTURE: Texture2D = preload("res://assets/animation/spells/void_execution/void_execution_arc.png")
const EXPLOSION_TEXTURE: Texture2D = preload("res://assets/animation/spells/void_execution/void_execution_explosion.png")
const WIPE_SHADER: Shader = preload("res://combat/effects/void_execution_wipe.gdshader")

const DEFAULT_ARC_SIZE := 200.0
const DEFAULT_EXPLOSION_SIZE := 200.0
var _arc_size: float = DEFAULT_ARC_SIZE
var _explosion_size: float = DEFAULT_EXPLOSION_SIZE
const ARC_DURATION := 0.45
const HOLD_DURATION := 0.1
const EXPLOSION_DURATION := 0.5
const SHAKE_INTENSITY := 8.0
const SHAKE_COUNT := 6

var _target_pos: Vector2
var _arc: Sprite2D
var _explosion: Sprite2D
var _arc_material: ShaderMaterial

static func create(target_pos: Vector2, size_scale: float = 1.0) -> VoidExecutionVFX:
	var vfx := VoidExecutionVFX.new()
	vfx._target_pos = target_pos
	vfx._arc_size = DEFAULT_ARC_SIZE * size_scale
	vfx._explosion_size = DEFAULT_EXPLOSION_SIZE * size_scale
	vfx.z_index = 200
	return vfx

func _ready() -> void:
	position = _target_pos
	_build_arc()
	_build_explosion()
	_play()

func _build_arc() -> void:
	_arc = Sprite2D.new()
	_arc.texture = ARC_TEXTURE
	var tex_w: float = _arc.texture.get_width()
	var tex_h: float = _arc.texture.get_height()
	var scale_factor: float = _arc_size / maxf(tex_w, tex_h)
	_arc.scale = Vector2.ONE * scale_factor
	_arc.position = Vector2(0, -_arc_size * 0.3)
	_arc.modulate = Color(1.2, 1.0, 1.4, 1.0)

	# Shader for top-to-bottom wipe reveal
	_arc_material = ShaderMaterial.new()
	_arc_material.shader = WIPE_SHADER
	_arc_material.set_shader_parameter("progress", 0.0)
	_arc_material.set_shader_parameter("glow_strength", 0.0)
	_arc.material = _arc_material
	_arc.visible = false
	add_child(_arc)

func _build_explosion() -> void:
	_explosion = Sprite2D.new()
	_explosion.texture = EXPLOSION_TEXTURE
	var tex_size: float = maxf(_explosion.texture.get_width(), _explosion.texture.get_height())
	var scale_factor: float = _explosion_size / maxf(tex_size, 1.0)
	_explosion.scale = Vector2.ONE * scale_factor
	_explosion.modulate = Color(1.2, 1.0, 1.4, 0.0)
	_explosion.visible = false
	add_child(_explosion)

func _play() -> void:
	# Phase 1: Arc wipe reveal
	if _arc and _arc_material:
		_arc.visible = true
		var arc_tween := create_tween()
		arc_tween.set_parallel(true)
		arc_tween.tween_method(_set_arc_progress, 0.0, 1.0, ARC_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		arc_tween.tween_method(_set_arc_glow, 0.0, 2.5, ARC_DURATION * 0.6)
		arc_tween.tween_method(_set_arc_glow, 2.5, 0.5, ARC_DURATION * 0.4).set_delay(ARC_DURATION * 0.6)
		await arc_tween.finished
		if not is_inside_tree(): queue_free(); return

	# Phase 2: Hold + screen shake + SFX
	impact_hit.emit()
	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_execution.wav")
	_do_screen_shake()
	await get_tree().create_timer(HOLD_DURATION).timeout
	if not is_inside_tree(): queue_free(); return

	# Phase 3: Explosion
	if _arc:
		var arc_fade := create_tween()
		arc_fade.tween_property(_arc, "modulate:a", 0.0, 0.1)

	if _explosion:
		_explosion.visible = true
		_explosion.scale = Vector2.ONE * (_explosion_size / maxf(_explosion.texture.get_width(), 1.0)) * 0.3
		_explosion.modulate = Color(1.5, 1.2, 1.8, 1.0)
		var exp_tween := create_tween()
		exp_tween.set_parallel(true)
		var target_scale: float = _explosion_size / maxf(_explosion.texture.get_width(), 1.0)
		exp_tween.tween_property(_explosion, "scale", Vector2.ONE * target_scale * 1.1, EXPLOSION_DURATION * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		exp_tween.tween_property(_explosion, "modulate", Color(1.0, 0.8, 1.2, 1.0), EXPLOSION_DURATION * 0.3)
		# Then fade out
		exp_tween.tween_property(_explosion, "scale", Vector2.ONE * target_scale * 1.3, EXPLOSION_DURATION * 0.7).set_delay(EXPLOSION_DURATION * 0.3).set_ease(Tween.EASE_IN)
		exp_tween.tween_property(_explosion, "modulate:a", 0.0, EXPLOSION_DURATION * 0.7).set_delay(EXPLOSION_DURATION * 0.3).set_ease(Tween.EASE_IN)
		await exp_tween.finished
		if not is_inside_tree(): queue_free(); return

	# Spawn particle burst for extra juice
	_spawn_void_particles()
	await get_tree().create_timer(0.3).timeout
	if not is_inside_tree(): return
	finished.emit()
	queue_free()

func _set_arc_progress(value: float) -> void:
	if _arc_material:
		_arc_material.set_shader_parameter("progress", value)

func _set_arc_glow(value: float) -> void:
	if _arc_material:
		_arc_material.set_shader_parameter("glow_strength", value)

func _do_screen_shake() -> void:
	var canvas_layer: Node = get_parent()
	if not canvas_layer:
		return
	var original_offset: Vector2 = Vector2.ZERO
	if canvas_layer is CanvasLayer:
		original_offset = canvas_layer.offset
	for i in SHAKE_COUNT:
		if not is_inside_tree():
			if canvas_layer is CanvasLayer:
				canvas_layer.offset = original_offset
			return
		var offset := Vector2(
			randf_range(-SHAKE_INTENSITY, SHAKE_INTENSITY),
			randf_range(-SHAKE_INTENSITY, SHAKE_INTENSITY)
		)
		if canvas_layer is CanvasLayer:
			canvas_layer.offset = original_offset + offset
		await get_tree().create_timer(0.03).timeout
	if is_instance_valid(canvas_layer) and canvas_layer is CanvasLayer:
		canvas_layer.offset = original_offset

func _spawn_void_particles() -> void:
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
