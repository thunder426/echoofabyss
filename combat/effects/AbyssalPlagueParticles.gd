## AbyssalPlagueParticles.gd
## Splash particle emitter that rides the wave front of Abyssal Plague.
##
## Creates two GPUParticles2D layers:
##   - droplets : bright emerald beads that arc upward and fall back (primary splash)
##   - mist     : faint wispy haze that lingers behind the front
##
## Usage: call spawn() once after the surge begins, passing the UI node to attach
## to, the wave geometry (band bounds in px, origin_y_px, direction_y),
## and the max_reach_px so we can track the front position each frame.
## The emitter follows the front automatically using the same cubic ease-out
## curve the shader uses for progress.
class_name AbyssalPlagueParticles
extends Node

const TEX_GLOW: Texture2D = preload("res://assets/art/fx/glow_soft.png")

# Colours
const COLOR_BRIGHT  : Color = Color(0.55, 1.00, 0.30, 1.00)  # lime-green droplet core
const COLOR_MID     : Color = Color(0.20, 0.80, 0.15, 0.60)  # mid-trail fade
const COLOR_FADE    : Color = Color(0.05, 0.40, 0.08, 0.00)  # fully transparent tail
const COLOR_MIST    : Color = Color(0.15, 0.65, 0.10, 0.35)
const COLOR_MIST_FADE: Color = Color(0.05, 0.30, 0.05, 0.00)

var _ui: Node = null
var _origin_y_px: float = 0.0
var _direction_y: float = -1.0
var _band_x_min_px: float = 0.0
var _band_x_max_px: float = 0.0
var _max_reach_px: float = 500.0
var _surge_duration: float = 5.5
var _elapsed: float = 0.0
var _running: bool = false

var _droplets: GPUParticles2D = null
var _mist: GPUParticles2D = null


static func spawn(ui: Node, origin_y_px: float, direction_y: float,
		band_x_min_px: float, band_x_max_px: float,
		max_reach_px: float, surge_duration: float) -> AbyssalPlagueParticles:
	var p := AbyssalPlagueParticles.new()
	p._ui = ui
	p._origin_y_px = origin_y_px
	p._direction_y = direction_y
	p._band_x_min_px = band_x_min_px
	p._band_x_max_px = band_x_max_px
	p._max_reach_px = max_reach_px
	p._surge_duration = surge_duration
	return p


func _ready() -> void:
	if _ui == null:
		queue_free()
		return
	_build_droplets()
	_build_mist()
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	var progress: float = _ease_out_cubic(_elapsed / _surge_duration)

	# Front Y position — same formula as the shader's progress * reach.
	# origin_y_px is in viewport pixels (e.g. 1.05 * 1080 = 1134 for player cast).
	# CanvasLayer children use screen coords directly so this maps correctly.
	var front_y_px: float = _origin_y_px + _direction_y * progress * _max_reach_px
	var band_center_x: float = (_band_x_min_px + _band_x_max_px) * 0.5

	# Clamp to visible screen range so particles don't spawn off-screen early
	var vp_h: float = get_viewport().get_visible_rect().size.y
	front_y_px = clampf(front_y_px, 0.0, vp_h)

	_droplets.position = Vector2(band_center_x, front_y_px)
	_mist.position = Vector2(band_center_x, front_y_px)

	# Stop emitting in the last 15% of surge so particles die before the wave fades
	var stop_at: float = _surge_duration * 0.85
	if _elapsed >= stop_at and _droplets.emitting:
		_droplets.emitting = false
		_mist.emitting = false

	if _elapsed >= _surge_duration + 1.0:
		_running = false
		queue_free()


func _build_droplets() -> void:
	_droplets = GPUParticles2D.new()
	_droplets.z_index = 17
	_droplets.z_as_relative = false
	_droplets.texture = TEX_GLOW
	_droplets.emitting = true
	_droplets.amount = 28
	_droplets.lifetime = 0.45
	_droplets.explosiveness = 0.0
	_droplets.randomness = 0.7
	_droplets.fixed_fps = 0
	_droplets.local_coords = false

	var mat := ParticleProcessMaterial.new()

	# Emit along a line spanning the wave width
	var band_width: float = _band_x_max_px - _band_x_min_px
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(band_width * 0.5, 2.0, 0.0)

	# Velocity — shoots in direction_y (upward for player cast = negative y)
	# with wide spread so droplets fan out
	mat.direction = Vector3(0.0, _direction_y, 0.0)
	mat.spread = 55.0
	mat.initial_velocity_min = 80.0
	mat.initial_velocity_max = 220.0

	# Gravity pulls back toward origin (opposite direction_y)
	mat.gravity = Vector3(0.0, -_direction_y * 420.0, 0.0)

	# Size — tiny sparks with high variance so no two look the same
	mat.scale_min = 0.015
	mat.scale_max = 0.055
	var size_curve := Curve.new()
	size_curve.add_point(Vector2(0.0, 1.0))
	size_curve.add_point(Vector2(0.6, 0.8))
	size_curve.add_point(Vector2(1.0, 0.0))
	var size_tex := CurveTexture.new()
	size_tex.curve = size_curve
	mat.scale_curve = size_tex

	# Color over lifetime — bright lime → mid green → transparent
	var grad := Gradient.new()
	grad.colors = PackedColorArray([COLOR_BRIGHT, COLOR_MID, COLOR_FADE])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	mat.color = COLOR_BRIGHT

	# Additive blend — droplets glow over the board
	_droplets.material = CanvasItemMaterial.new()
	(_droplets.material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_droplets.process_material = mat
	_ui.add_child(_droplets)


func _build_mist() -> void:
	_mist = GPUParticles2D.new()
	_mist.z_index = 16
	_mist.z_as_relative = false
	_mist.texture = TEX_GLOW
	_mist.emitting = true
	_mist.amount = 12
	_mist.lifetime = 0.7
	_mist.explosiveness = 0.0
	_mist.randomness = 0.8
	_mist.fixed_fps = 0
	_mist.local_coords = false

	var mat := ParticleProcessMaterial.new()

	var band_width: float = _band_x_max_px - _band_x_min_px
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(band_width * 0.5, 4.0, 0.0)

	# Mist drifts gently upward — slow, wide spread
	mat.direction = Vector3(0.0, _direction_y, 0.0)
	mat.spread = 80.0
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 90.0
	mat.gravity = Vector3(0.0, 0.0, 0.0)  # floats

	mat.scale_min = 0.04
	mat.scale_max = 0.12
	var size_curve := Curve.new()
	size_curve.add_point(Vector2(0.0, 0.0))
	size_curve.add_point(Vector2(0.2, 1.0))
	size_curve.add_point(Vector2(1.0, 0.0))
	var size_tex := CurveTexture.new()
	size_tex.curve = size_curve
	mat.scale_curve = size_tex

	var grad := Gradient.new()
	grad.colors = PackedColorArray([COLOR_MIST, COLOR_MIST_FADE])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	mat.color = COLOR_MIST

	_mist.material = CanvasItemMaterial.new()
	(_mist.material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_mist.process_material = mat
	_ui.add_child(_mist)


func _ease_out_cubic(x: float) -> float:
	var t: float = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)
