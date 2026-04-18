## BroodCallVFX.gd
## Summoning portal VFX for Brood Call — a green/red vortex that tears open at
## the target slot, pours green particles outward for a beat, then collapses
## before the minion appears.
##
## Layers:
##   1. Ground shadow (depth anchor, under the portal)
##   2. Shader-style radial halo behind portal (procedural gradient, additive)
##   3. Portal sprite (normal blend — asset is already saturated)
##   4. Continuous green particle emission from center — lifetime tuned so
##      particles fade before reaching the slot edge (contained within slot)
##   5. Portal + halo + shadow collapse; minion is placed after finished.
##
## Fire-and-forget via vfx_controller.spawn. Emits impact_hit right before
## collapse begins; finished fires after collapse completes.
class_name BroodCallVFX
extends BaseVfx

const TEX_PORTAL: Texture2D = preload("res://assets/art/fx/brood_portal.png")
const TEX_GLOW: Texture2D   = preload("res://assets/art/fx/glow_soft.png")

# ── Palette (matches portal art: green core, red flesh edge) ─────────────────
const COLOR_GREEN_CORE: Color  = Color(0.30, 0.95, 0.20, 1.0)
const COLOR_GREEN_BRIGHT: Color = Color(0.75, 1.00, 0.50, 1.0)
const COLOR_RED_EDGE: Color    = Color(0.90, 0.15, 0.10, 1.0)

# ── Sizing ───────────────────────────────────────────────────────────────────
const PORTAL_SIZE: float   = 180.0   # Fits inside a board slot
const SHADOW_SIZE: float   = 150.0
# Max radius particles should travel before fading — stays inside the slot.
const PARTICLE_REACH: float = 85.0

# ── Timing ───────────────────────────────────────────────────────────────────
const RAMP_DURATION: float     = 0.45   # portal + halo ramp-in
const HOLD_DURATION: float     = 0.70   # sustained emission phase
const COLLAPSE_DURATION: float = 0.22   # portal fade-out

var _target_slot: BoardSlot = null


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

	# ── Layer 1: Ground shadow ───────────────────────────────────────────────
	var shadow := Sprite2D.new()
	shadow.texture = TEX_GLOW
	shadow.modulate = Color(0.0, 0.0, 0.0, 0.35)
	shadow.z_index = -1
	var tex_size: float = maxf(TEX_GLOW.get_width(), TEX_GLOW.get_height())
	var shadow_scale: float = SHADOW_SIZE / maxf(tex_size, 1.0)
	shadow.scale = Vector2(shadow_scale, shadow_scale * 0.45)
	shadow.position = Vector2(0, 28)
	add_child(shadow)

	# ── Layer 2: Shader-style radial halo behind portal — bright-center, soft
	# falloff procedural gradient (same technique as CastingWindupVFX). Channel-
	# scaled tint prevents additive blending from washing to white.
	var halo := Sprite2D.new()
	halo.texture = CastingWindupVFX._get_glow_texture()
	var halo_mat := CanvasItemMaterial.new()
	halo_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = halo_mat
	# Dark-red + green biased halo — pulls portal's flesh-edge + core colors
	# outward. Channel scaling (vs. flat green/red) keeps the hue saturated.
	var halo_tint := Color(0.85, 0.20, 0.12, 1.0)  # deep red primary
	halo.modulate = Color(halo_tint.r, halo_tint.g, halo_tint.b, 0.0)
	var halo_tex_size: float = float(halo.texture.get_width())
	var halo_start_px: float = PORTAL_SIZE * 0.7
	var halo_end_px: float   = PORTAL_SIZE * 2.4
	halo.scale = Vector2.ONE * (halo_start_px / maxf(halo_tex_size, 1.0))
	add_child(halo)

	var halo_end_scale: Vector2 = Vector2.ONE * (halo_end_px / maxf(halo_tex_size, 1.0))
	var htw := create_tween()
	htw.set_parallel(true)
	htw.tween_property(halo, "modulate:a", 0.90, RAMP_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	htw.tween_property(halo, "scale", halo_end_scale, RAMP_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# ── Layer 3: Portal sprite (normal blend — art is already saturated) ─────
	var portal := Sprite2D.new()
	portal.texture = TEX_PORTAL
	var portal_tex_size: float = maxf(TEX_PORTAL.get_width(), TEX_PORTAL.get_height())
	var portal_target_scale: float = PORTAL_SIZE / maxf(portal_tex_size, 1.0)
	portal.scale = Vector2(portal_target_scale * 0.6, portal_target_scale * 0.6)
	portal.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(portal)

	var ptw := create_tween()
	ptw.set_parallel(true)
	ptw.tween_property(portal, "modulate:a", 1.0, RAMP_DURATION * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ptw.tween_property(portal, "scale", Vector2(portal_target_scale, portal_target_scale), RAMP_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# ── Layer 4: Continuous green particle emission from center ──────────────
	# Starts as portal opens, runs through ramp + hold, stops before collapse.
	# Lifetime × velocity tuned so particles fade out near PARTICLE_REACH radius.
	var particles := _spawn_flow_particles()

	# Wait for ramp-in, then hold while particles pour out.
	await get_tree().create_timer(RAMP_DURATION + HOLD_DURATION).timeout
	if not is_inside_tree():
		finished.emit()
		queue_free()
		return

	# Stop new emission — in-flight particles continue to fade out naturally.
	particles.emitting = false

	# ── Layer 5: Collapse ────────────────────────────────────────────────────
	impact_hit.emit(0)
	var collapse := create_tween()
	collapse.set_parallel(true)
	collapse.tween_property(portal, "modulate:a", 0.0, COLLAPSE_DURATION)
	collapse.tween_property(portal, "scale", Vector2(portal_target_scale * 0.3, portal_target_scale * 0.3), COLLAPSE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	collapse.tween_property(halo, "modulate:a", 0.0, COLLAPSE_DURATION)
	collapse.tween_property(shadow, "modulate:a", 0.0, COLLAPSE_DURATION)

	await get_tree().create_timer(COLLAPSE_DURATION + 0.05).timeout
	finished.emit()
	queue_free()


# ═════════════════════════════════════════════════════════════════════════════
# Particle flow
# ═════════════════════════════════════════════════════════════════════════════

## Continuous radial emission from the portal center. Velocity × lifetime is
## tuned so particles fade before reaching PARTICLE_REACH (slot edge).
func _spawn_flow_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 48
	# lifetime × avg velocity ≈ PARTICLE_REACH. 0.55 × ~155 ≈ 85 px reach.
	p.lifetime = 0.55
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0   # full 360° radial
	p.initial_velocity_min = 110.0
	p.initial_velocity_max = 200.0
	p.gravity = Vector2.ZERO
	p.damping_min = 1.2
	p.damping_max = 2.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	# Shrink over lifetime — sells "dissipating into the air" near edge.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = scale_curve
	# Color: bright green core → deeper green → fade to transparent at edge.
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
