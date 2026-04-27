## BroodCallVFX.gd
## Summoning portal VFX for Brood Call — a green/red vortex that tears open at
## the target slot, pours green particles outward for a beat, then collapses
## before the minion appears.
##
## Phases:
##   1. ramp     (0.45s) — shadow + halo + portal bloom in; particles start
##   2. hold     (0.70s) — sustained emission
##   3. collapse (0.27s) — portal/halo/shadow fade; impact_hit fires at start
##
## Spawn via vfx_controller.spawn().
class_name BroodCallVFX
extends BaseVfx

const TEX_PORTAL: Texture2D = preload("res://assets/art/fx/brood_portal.png")
const TEX_GLOW: Texture2D   = preload("res://assets/art/fx/glow_soft.png")

const COLOR_GREEN_CORE: Color  = Color(0.30, 0.95, 0.20, 1.0)
const COLOR_GREEN_BRIGHT: Color = Color(0.75, 1.00, 0.50, 1.0)
const COLOR_RED_EDGE: Color    = Color(0.90, 0.15, 0.10, 1.0)

const PORTAL_SIZE: float   = 180.0
const SHADOW_SIZE: float   = 150.0
const PARTICLE_REACH: float = 85.0

const RAMP_DURATION: float     = 0.45
const HOLD_DURATION: float     = 0.70
const COLLAPSE_DURATION: float = 0.22
const COLLAPSE_TAIL: float     = 0.05

var _target_slot: BoardSlot = null

var _shadow: Sprite2D = null
var _halo: Sprite2D = null
var _portal: Sprite2D = null
var _particles: CPUParticles2D = null
var _portal_target_scale: float = 1.0


static func create(target_slot: BoardSlot) -> BroodCallVFX:
	var vfx := BroodCallVFX.new()
	vfx._target_slot = target_slot
	vfx.z_index = 200
	return vfx


func _play() -> void:
	if _target_slot == null or not _target_slot.is_inside_tree():
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return

	global_position = _target_slot.global_position + _target_slot.size * 0.5
	AudioManager.play_sfx("res://assets/audio/sfx/spells/brood_call.wav", -8.0)

	sequence().run([
		VfxPhase.new("ramp",     RAMP_DURATION,                     _build_ramp),
		VfxPhase.new("hold",     HOLD_DURATION,                     Callable()),
		VfxPhase.new("collapse", COLLAPSE_DURATION + COLLAPSE_TAIL, _build_collapse) \
			.emits_at_start(VfxSequence.RESERVED_IMPACT_HIT),
	])


# ═════════════════════════════════════════════════════════════════════════════
# Phase builders
# ═════════════════════════════════════════════════════════════════════════════

func _build_ramp(duration: float) -> void:
	# Layer 1: Shadow
	_shadow = Sprite2D.new()
	_shadow.texture = TEX_GLOW
	_shadow.modulate = Color(0.0, 0.0, 0.0, 0.35)
	_shadow.z_index = -1
	var tex_size: float = maxf(TEX_GLOW.get_width(), TEX_GLOW.get_height())
	var shadow_scale: float = SHADOW_SIZE / maxf(tex_size, 1.0)
	_shadow.scale = Vector2(shadow_scale, shadow_scale * 0.45)
	_shadow.position = Vector2(0, 28)
	add_child(_shadow)

	# Layer 2: Halo
	_halo = Sprite2D.new()
	_halo.texture = CastingWindupVFX._get_glow_texture()
	var halo_mat := CanvasItemMaterial.new()
	halo_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halo.material = halo_mat
	var halo_tint := Color(0.85, 0.20, 0.12, 1.0)
	_halo.modulate = Color(halo_tint.r, halo_tint.g, halo_tint.b, 0.0)
	var halo_tex_size: float = float(_halo.texture.get_width())
	var halo_start_px: float = PORTAL_SIZE * 0.7
	var halo_end_px: float   = PORTAL_SIZE * 2.4
	_halo.scale = Vector2.ONE * (halo_start_px / maxf(halo_tex_size, 1.0))
	add_child(_halo)

	var halo_end_scale: Vector2 = Vector2.ONE * (halo_end_px / maxf(halo_tex_size, 1.0))
	var htw := create_tween()
	htw.set_parallel(true)
	htw.tween_property(_halo, "modulate:a", 0.90, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	htw.tween_property(_halo, "scale", halo_end_scale, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Layer 3: Portal
	_portal = Sprite2D.new()
	_portal.texture = TEX_PORTAL
	var portal_tex_size: float = maxf(TEX_PORTAL.get_width(), TEX_PORTAL.get_height())
	_portal_target_scale = PORTAL_SIZE / maxf(portal_tex_size, 1.0)
	_portal.scale = Vector2(_portal_target_scale * 0.6, _portal_target_scale * 0.6)
	_portal.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_portal)

	var ptw := create_tween()
	ptw.set_parallel(true)
	ptw.tween_property(_portal, "modulate:a", 1.0, duration * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ptw.tween_property(_portal, "scale", Vector2(_portal_target_scale, _portal_target_scale), duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Layer 4: Continuous emission (runs through ramp + hold).
	_particles = _spawn_flow_particles()


func _build_collapse(duration: float) -> void:
	if _particles != null and is_instance_valid(_particles):
		_particles.emitting = false

	var visible: float = maxf(duration - COLLAPSE_TAIL, 0.0)
	var tw := create_tween().set_parallel(true)
	if _portal != null:
		tw.tween_property(_portal, "modulate:a", 0.0, visible)
		tw.tween_property(_portal, "scale", Vector2(_portal_target_scale * 0.3, _portal_target_scale * 0.3), visible) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _halo != null:
		tw.tween_property(_halo, "modulate:a", 0.0, visible)
	if _shadow != null:
		tw.tween_property(_shadow, "modulate:a", 0.0, visible)


# ═════════════════════════════════════════════════════════════════════════════
# Particle flow
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_flow_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 48
	p.lifetime = 0.55
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 110.0
	p.initial_velocity_max = 200.0
	p.gravity = Vector2.ZERO
	p.damping_min = 1.2
	p.damping_max = 2.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = scale_curve
	var ramp := Gradient.new()
	ramp.set_color(0, COLOR_GREEN_BRIGHT)
	ramp.set_color(1, Color(COLOR_GREEN_CORE.r, COLOR_GREEN_CORE.g, COLOR_GREEN_CORE.b, 0.0))
	ramp.add_point(0.55, COLOR_GREEN_CORE)
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p)
	p.emitting = true
	return p
