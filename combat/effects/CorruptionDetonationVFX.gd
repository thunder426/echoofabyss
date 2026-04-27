## CorruptionDetonationVFX.gd
## Per-minion VFX for Corruption stacks rupturing into damage. The payoff of
## the Corruption Apply -> Detonation loop used by Abyss Cultist Patrol
## (Act 2, Fight 1) and the Cultist Patrol champion aura.
##
## Flow (per corrupted minion):
##   Phase 1 - Icon charge (0.80s): grow + shake the live corruption_icon;
##                                  shake intensity ramps until the burst.
##   Phase 2 - Rupture     (0.44s): core flash + sonic distortion + perspective
##                                  ring. impact_hit fires on the flash peak so
##                                  the caller applies damage on the visible
##                                  burst.
##   Phase 3 - Dissipate   (0.70s): volumetric body layers, ejecta particles,
##                                  smoke wisps, and a per-slot screen shake.
##
## Stack scaling:
##   stacks 1   - baseline
##   stacks 3-4 - 1.25x sizes, more ejecta, medium shake
##   stacks >=5 - 1.5x sizes, heaviest shake
##
## Spawn via VfxController.spawn(). The caller connects to impact_hit to apply
## damage + refresh the slot at the right frame (see CombatScene._play_corruption_detonations).
class_name CorruptionDetonationVFX
extends BaseVfx

const TEX_GLOW: Texture2D = preload("res://assets/art/fx/glow_soft.png")
const SHADER_SONIC: Shader = preload("res://combat/effects/sonic_wave.gdshader")

# ── Debug time scale ────────────────────────────────────────────────────────
# 1.0 is the shipping speed. Raise this to slow the whole effect down for
# tuning/debug; durations multiply by it and velocities divide by it.
const DEBUG_TIME_SCALE: float = 1.0

# ── Emerald / corruption palette ────────────────────────────────────────────
const COLOR_CORE_FLASH: Color     = Color(1.0, 1.0, 0.90, 1.0)   # white-hot core
const COLOR_VOID_BRIGHT: Color    = Color(0.78, 1.0, 0.70, 0.9)  # front body
const COLOR_VOID_MID: Color       = Color(0.45, 0.85, 0.25, 0.7) # mid body
const COLOR_VOID_DARK: Color      = Color(0.15, 0.65, 0.08, 0.6) # back body
const COLOR_RING: Color           = Color(0.55, 1.0, 0.40, 0.85) # shockwave ring
const COLOR_DISTORT_TINT: Color   = Color(0.25, 0.85, 0.20, 0.55)

# Phase 1 — live-icon charge-up. Icon grows and shakes; once it reaches peak
# size it stops growing but the shake keeps ramping until the explosion.
# The icon is NOT faded out here — the explosion overpowers it visually and
# the slot refresh on VFX.finished removes it for real.
const ICON_HOT_TINT: Color      = Color(2.6, 3.0, 1.5, 1.0)   # bright toxic-green brighten
const ICON_PUNCH_SCALE: Vector2 = Vector2(2.3, 2.3)
const ICON_GROW_TIME: float     = 0.44 * DEBUG_TIME_SCALE   # scale ramps up during this window
const ICON_SHAKE_TIME: float    = 0.36 * DEBUG_TIME_SCALE   # at peak size; shake keeps ramping
const PHASE1_DURATION: float    = ICON_GROW_TIME + ICON_SHAKE_TIME  # 0.80s at 1x
const ICON_SHAKE_TICK: float    = 0.030 * DEBUG_TIME_SCALE  # ~33Hz shake update
const ICON_SHAKE_AMP_START: float = 1.0   # px at t=0
const ICON_SHAKE_AMP_MID: float   = 5.0   # px at end of grow phase
const ICON_SHAKE_AMP_END: float   = 16.0  # px just before explosion

# Phase 2 — rupture
const CORE_SIZE_BASE: float         = 48.0
const RING_MAX_RADIUS_BASE: float   = 95.0
const DISTORT_RADIUS_PX_BASE: float = 130.0
const FLASH_PEAK: float             = 0.10 * DEBUG_TIME_SCALE  # impact_hit fires here
const DISTORT_DURATION: float       = 0.44 * DEBUG_TIME_SCALE
const RING_DURATION: float          = 0.44 * DEBUG_TIME_SCALE

# Phase 3 — dissipate
const BODY_SIZE_BASE: float  = 80.0
const PHASE3_DURATION: float = 0.70 * DEBUG_TIME_SCALE

var _slot: BoardSlot = null
var _stacks: int = 1
var _scale_mult: float = 1.0
var _shake_amp: float = 8.0
var _shake_ticks: int = 8
var _ejecta_count: int = 28
var _fx_layer: CanvasLayer = null


static func create(slot: BoardSlot, stacks: int) -> CorruptionDetonationVFX:
	var vfx := CorruptionDetonationVFX.new()
	vfx._slot = slot
	vfx._stacks = maxi(stacks, 1)
	vfx.z_index = 200
	if vfx._stacks >= 5:
		vfx._scale_mult = 1.5
		vfx._shake_amp = 22.0
		vfx._shake_ticks = 14
		vfx._ejecta_count = 55
	elif vfx._stacks >= 3:
		vfx._scale_mult = 1.25
		vfx._shake_amp = 14.0
		vfx._shake_ticks = 10
		vfx._ejecta_count = 42
	return vfx


func _play() -> void:
	if _slot == null or not is_instance_valid(_slot):
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return

	global_position = _slot.global_position + _slot.size * 0.5

	# Wait one frame so HBoxContainer in the status bar finishes laying out a
	# freshly-added corruption icon. Without this, when corruption is applied
	# in the same frame as the detonation fires (Cultist Patrol champion aura,
	# Plague + corrupt_detonation chain, etc.), the icon's global_position is
	# still its initial pre-layout value and the pulse animates from the bar's
	# leftmost edge instead of where the icon actually sits.
	await get_tree().process_frame
	if not is_inside_tree() or _slot == null or not is_instance_valid(_slot):
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return

	# ── Phase 1: pulse the live corruption icon on the status bar ──────────
	_start_icon_pulse()
	await get_tree().create_timer(PHASE1_DURATION).timeout
	if not is_inside_tree():
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return

	# ── Phase 2: rupture ───────────────────────────────────────────────────
	_hide_charged_icon()
	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_bolt_impact.wav")
	_spawn_distortion()
	_spawn_core_flash()
	_spawn_ring()
	await get_tree().create_timer(FLASH_PEAK).timeout
	if not is_inside_tree():
		finished.emit()
		queue_free()
		return
	# Damage lands on the flash peak — caller removes corruption + refreshes
	# the slot + applies spell damage inside this signal.
	impact_hit.emit(0)

	# ── Phase 3: dissipate ─────────────────────────────────────────────────
	_spawn_body_layers()
	_spawn_ejecta()
	_spawn_smoke_wisps()
	if _slot != null and _slot.is_inside_tree():
		ScreenShakeEffect.shake(_slot, self, _shake_amp, _shake_ticks)

	# Remainder of phase 2 plus all of phase 3
	var remainder: float = (DISTORT_DURATION - FLASH_PEAK) + PHASE3_DURATION
	await get_tree().create_timer(remainder).timeout
	if is_instance_valid(_fx_layer):
		_fx_layer.queue_free()
	finished.emit()
	queue_free()


# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: live-icon pulse
# ═════════════════════════════════════════════════════════════════════════════

func _start_icon_pulse() -> void:
	var icon: Control = null
	if _slot.has_method("get_corruption_icon_node"):
		icon = _slot.get_corruption_icon_node()
	if icon == null or not is_instance_valid(icon):
		return
	var original_scale: Vector2 = icon.scale
	icon.pivot_offset = icon.size * 0.5
	# Grow + brighten during Phase 1A; then locked at peak size during 1B.
	var tw := icon.create_tween().set_parallel(true)
	tw.tween_property(icon, "modulate", ICON_HOT_TINT, ICON_GROW_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(icon, "scale", original_scale * ICON_PUNCH_SCALE, ICON_GROW_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Ramping shake runs on top of the tween for the full Phase 1 duration.
	_run_icon_shake(icon)


## Fade and hide the charged corruption icon on the status bar as the
## explosion begins. The slot is frozen during the VFX so the normal refresh
## won't rebuild the status bar; without this, the oversized icon would hang
## under the burst until VFX.finished.
func _hide_charged_icon() -> void:
	if _slot == null or not is_instance_valid(_slot):
		return
	if not _slot.has_method("get_corruption_icon_node"):
		return
	var icon: Control = _slot.get_corruption_icon_node()
	if icon == null or not is_instance_valid(icon):
		return
	var fade_time: float = 0.10 * DEBUG_TIME_SCALE
	var tw := icon.create_tween()
	tw.tween_property(icon, "modulate:a", 0.0, fade_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(icon.hide)


## Fire-and-forget shake coroutine. Amplitude ramps from START -> MID across
## the grow window, then MID -> END across the shake-only window so the
## shake visibly intensifies as the icon locks at peak size.
func _run_icon_shake(icon: Control) -> void:
	if icon == null or not is_instance_valid(icon):
		return
	var origin: Vector2 = icon.position
	var elapsed: float = 0.0
	while elapsed < PHASE1_DURATION:
		if not is_instance_valid(icon) or not is_inside_tree():
			return
		var amp: float
		if elapsed < ICON_GROW_TIME:
			var t: float = elapsed / ICON_GROW_TIME
			amp = lerpf(ICON_SHAKE_AMP_START, ICON_SHAKE_AMP_MID, t)
		else:
			var t: float = (elapsed - ICON_GROW_TIME) / ICON_SHAKE_TIME
			amp = lerpf(ICON_SHAKE_AMP_MID, ICON_SHAKE_AMP_END, t * t)
		icon.position = origin + Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		await get_tree().create_timer(ICON_SHAKE_TICK).timeout
		elapsed += ICON_SHAKE_TICK
	if is_instance_valid(icon):
		icon.position = origin


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2a: Screen-space sonic distortion
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_distortion() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var scene: Node = get_parent().get_parent() if get_parent() else null
	if scene == null:
		return

	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 2
	scene.add_child(_fx_layer)

	var impact_pos: Vector2 = global_position
	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.z_index = 15
	rect.z_as_relative = false

	var aspect: float = vp_size.x / vp_size.y
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SONIC
	mat.set_shader_parameter("aspect", aspect)
	mat.set_shader_parameter("tint", COLOR_DISTORT_TINT)
	mat.set_shader_parameter("radius_max", (DISTORT_RADIUS_PX_BASE * _scale_mult) / vp_size.y)
	mat.set_shader_parameter("thickness", 0.06)
	mat.set_shader_parameter("strength", 0.028)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("alpha_multiplier", 1.0)
	mat.set_shader_parameter("center_uv", Vector2(
		impact_pos.x / vp_size.x,
		impact_pos.y / vp_size.y
	))
	rect.material = mat
	_fx_layer.add_child(rect)

	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			mat.set_shader_parameter("progress", p),
			0.0, 1.0, DISTORT_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, DISTORT_DURATION * 0.35
		).set_delay(DISTORT_DURATION * 0.65).set_trans(Tween.TRANS_SINE)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2b: Core flash
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_core_flash() -> void:
	var flash := Sprite2D.new()
	flash.texture = TEX_GLOW
	var tex_size: float = maxf(flash.texture.get_width(), 1.0)
	var size_px: float = CORE_SIZE_BASE * _scale_mult
	flash.scale = Vector2.ONE * (size_px * 0.35 / tex_size)
	flash.modulate = COLOR_CORE_FLASH
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = mat
	add_child(flash)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2.ONE * (size_px * 1.6 / tex_size), 0.12 * DEBUG_TIME_SCALE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.32 * DEBUG_TIME_SCALE) \
		.set_delay(0.08 * DEBUG_TIME_SCALE).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(flash.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2c: Perspective shockwave ring (Y-squashed)
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_ring() -> void:
	var ring := Sprite2D.new()
	ring.texture = _make_ring_texture()
	var tex_size: float = maxf(ring.texture.get_width(), 1.0)
	var start_scale: float = 18.0 / tex_size
	ring.scale = Vector2(start_scale, start_scale * 0.6)
	ring.modulate = COLOR_RING
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ring.material = mat
	add_child(ring)

	var target_scale_x: float = (RING_MAX_RADIUS_BASE * _scale_mult * 2.0) / tex_size
	var target_scale_y: float = target_scale_x * 0.6

	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale",
		Vector2(target_scale_x, target_scale_y), RING_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(0.04 * DEBUG_TIME_SCALE)
	tw.tween_property(ring, "modulate:a", 0.0, 0.28 * DEBUG_TIME_SCALE) \
		.set_delay(RING_DURATION - 0.20 * DEBUG_TIME_SCALE).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(ring.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3a: Volumetric body (3 staggered depth sprites)
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_body_layers() -> void:
	var body_size: float = BODY_SIZE_BASE * _scale_mult
	var configs: Array = [
		{"delay": 0.00 * DEBUG_TIME_SCALE, "color": COLOR_VOID_DARK,   "size_mult": 0.85, "growth": 1.45,
		 "offset": Vector2(randf_range(-6, 6), randf_range(2, 6)),
		 "fade_time": 0.60 * DEBUG_TIME_SCALE, "rotation": randf_range(-0.3, 0.3)},
		{"delay": 0.04 * DEBUG_TIME_SCALE, "color": COLOR_VOID_MID,    "size_mult": 1.00, "growth": 1.50,
		 "offset": Vector2(randf_range(-4, 4), randf_range(-2, 2)),
		 "fade_time": 0.50 * DEBUG_TIME_SCALE, "rotation": randf_range(-0.2, 0.2)},
		{"delay": 0.08 * DEBUG_TIME_SCALE, "color": COLOR_VOID_BRIGHT, "size_mult": 1.10, "growth": 1.60,
		 "offset": Vector2(randf_range(-5, 5), randf_range(-6, -2)),
		 "fade_time": 0.40 * DEBUG_TIME_SCALE, "rotation": randf_range(-0.25, 0.25)},
	]
	for cfg in configs:
		var color: Color     = cfg["color"] as Color
		var size_mult: float = float(cfg["size_mult"])
		var growth: float    = float(cfg["growth"])
		var offset: Vector2  = cfg["offset"] as Vector2
		var delay: float     = float(cfg["delay"])
		var fade_time: float = float(cfg["fade_time"])
		var rot: float       = float(cfg["rotation"])

		var sprite := Sprite2D.new()
		sprite.texture = TEX_GLOW
		var tex_size: float = maxf(sprite.texture.get_width(), 1.0)
		var start_scale: float = (body_size * size_mult * 0.3) / tex_size
		sprite.scale = Vector2.ONE * start_scale
		sprite.position = offset
		sprite.rotation = rot
		sprite.modulate = Color(color.r, color.g, color.b, 0.0)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = mat
		add_child(sprite)

		var end_scale: float = start_scale * growth
		var tw := create_tween().set_parallel(true)
		tw.tween_property(sprite, "modulate:a", color.a, 0.08 * DEBUG_TIME_SCALE).set_delay(delay)
		tw.tween_property(sprite, "scale", Vector2.ONE * end_scale, fade_time) \
			.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(sprite, "modulate:a", 0.0, fade_time * 0.6) \
			.set_delay(delay + fade_time * 0.4).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_callback(sprite.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3b: Hot ejecta particles (bright emerald sparks)
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_ejecta() -> void:
	var burst := CPUParticles2D.new()
	burst.emitting = true
	burst.amount = _ejecta_count
	burst.lifetime = 0.52 * DEBUG_TIME_SCALE
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.local_coords = true
	burst.texture = _make_soft_circle()

	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 6.0
	burst.direction = Vector2(0, 0)
	burst.spread = 180.0
	burst.initial_velocity_min = 55.0 / DEBUG_TIME_SCALE
	burst.initial_velocity_max = (120.0 * _scale_mult) / DEBUG_TIME_SCALE
	burst.damping_min = 75.0 / DEBUG_TIME_SCALE
	burst.damping_max = 150.0 / DEBUG_TIME_SCALE
	burst.gravity = Vector2.ZERO

	burst.scale_amount_min = 0.07
	burst.scale_amount_max = 0.16
	burst.scale_amount_curve = _make_fade_curve()

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 0.85, 1.0))
	gradient.add_point(0.2, Color(0.85, 1.0, 0.55, 0.95))
	gradient.add_point(0.55, Color(0.45, 0.85, 0.25, 0.75))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.12, 0.45, 0.05, 0.0))
	burst.color_ramp = gradient

	add_child(burst)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3c: Smoke wisps (dark-emerald residue)
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_smoke_wisps() -> void:
	var wisps := CPUParticles2D.new()
	wisps.emitting = true
	wisps.amount = 8
	wisps.lifetime = 0.84 * DEBUG_TIME_SCALE
	wisps.one_shot = true
	wisps.explosiveness = 0.85
	wisps.randomness = 0.5
	wisps.local_coords = true
	wisps.texture = _make_soft_circle()

	wisps.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	wisps.emission_sphere_radius = 10.0
	wisps.direction = Vector2(0, 0)
	wisps.spread = 180.0
	wisps.initial_velocity_min = 10.0 / DEBUG_TIME_SCALE
	wisps.initial_velocity_max = 27.5 / DEBUG_TIME_SCALE
	wisps.gravity = Vector2(0, -15.0 / DEBUG_TIME_SCALE)
	wisps.damping_min = 10.0 / DEBUG_TIME_SCALE
	wisps.damping_max = 20.0 / DEBUG_TIME_SCALE

	wisps.scale_amount_min = 0.22
	wisps.scale_amount_max = 0.48
	wisps.scale_amount_curve = _make_fade_curve()

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.30, 0.55, 0.15, 0.55))
	gradient.add_point(0.4, Color(0.18, 0.40, 0.10, 0.40))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.08, 0.22, 0.05, 0.0))
	wisps.color_ramp = gradient

	add_child(wisps)


# ═════════════════════════════════════════════════════════════════════════════
# Procedural textures
# ═════════════════════════════════════════════════════════════════════════════

## 64x64 donut ring — soft inner/outer edges for the perspective shockwave.
static func _make_ring_texture() -> ImageTexture:
	var size: int = 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var outer_radius: float = size * 0.48
	var inner_radius: float = size * 0.30
	var ring_center: float  = (inner_radius + outer_radius) * 0.5
	var half_width: float   = (outer_radius - inner_radius) * 0.5
	for y in size:
		for x in size:
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var ring_dist: float = absf(dist - ring_center)
			var alpha: float = clampf(1.0 - ring_dist / half_width, 0.0, 1.0)
			alpha *= alpha
			var outer_fade: float = clampf(1.0 - dist / outer_radius, 0.0, 1.0)
			alpha *= outer_fade
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


## 32x32 soft radial circle — particle texture.
static func _make_soft_circle() -> ImageTexture:
	var size: int = 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius: float = size * 0.5
	for y in size:
		for x in size:
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha: float = clampf(1.0 - dist / radius, 0.0, 1.0)
			alpha *= alpha
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


static func _make_fade_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	return curve
