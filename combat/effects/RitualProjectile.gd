## RitualProjectile.gd
## Ritual-tinted projectile mirroring VoidBoltProjectile's structure (spinning
## core, glow halo, flame trail, embers, arcing flight). Recolored toward the
## blood/dominion ritual palette — crimson core with gold-violet flame —
## instead of the void-bolt purple. Fired from a ritual's merged orb at screen
## center toward an arbitrary target position.
##
## Emits `impact_hit(0)` at the moment of impact so the caller can sync damage
## with the visual landing. The bolt then plays a brief impact flash and frees
## itself.
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name RitualProjectile
extends BaseVfx

const CORE_SIZE: float        = 56.0   # ritual bolt is heavier than a void bolt
const GLOW_SIZE: float        = 110.0
const FLIGHT_DURATION: float  = 1.0    # 1.0s ritual travel — see DemonAscendantRitualVFX
const ARC_HEIGHT: float       = 80.0
const SPIN_SPEED: float       = 14.0
const PULSE_MIN: float        = 0.85
const PULSE_MAX: float        = 1.15
const PULSE_SPEED: float      = 8.0
const IMPACT_FADE: float      = 0.20
const IMPACT_LINGER: float    = 0.45  # wait for trailing particles to clear

const COLOR_CORE: Color       = Color(1.0, 0.55, 0.45, 1.0)   # white-hot crimson
const COLOR_GLOW: Color       = Color(1.0, 0.30, 0.25, 0.55)  # ritual-red glow halo
const COLOR_IMPACT_FLASH: Color = Color(1.0, 0.85, 0.5, 0.95) # gold-warm impact flash

# Summon variant — used for the Demon Ascendant landing bolt (the third bolt
# in the volley). Heavier core + cooler violet/dominion tint so it reads as a
# distinct "this is the summoning charge" vs. the two red damage bolts.
const SUMMON_CORE_SIZE: float        = 78.0
const SUMMON_GLOW_SIZE: float        = 150.0
const SUMMON_COLOR_CORE: Color       = Color(0.80, 0.65, 1.0, 1.0)  # white-violet core
const SUMMON_COLOR_GLOW: Color       = Color(0.55, 0.30, 0.95, 0.55) # dominion-violet halo
const SUMMON_COLOR_IMPACT: Color     = Color(0.85, 0.75, 1.0, 0.0)   # impact flash skipped — shockwave handles arrival

var _from: Vector2
var _to:   Vector2
var _for_summon: bool = false
var _core: Sprite2D = null
var _glow: Sprite2D = null
var _flame_inner: CPUParticles2D = null
var _flame_outer: CPUParticles2D = null
var _embers: CPUParticles2D = null
var _elapsed: float = 0.0
var _active: bool = true
var _prev_pos: Vector2

# Cached procedural textures (created once, shared by all instances).
static var _flame_tex: ImageTexture
static var _circle_tex: ImageTexture
static var _ember_tex: ImageTexture

static func create(from_pos: Vector2, to_pos: Vector2) -> RitualProjectile:
	var p := RitualProjectile.new()
	p._from = from_pos
	p._to   = to_pos
	p.z_index = 260
	p.impact_count = 1
	return p

## Summon variant: heavier violet bolt used for the Demon Ascendant landing
## charge. Visually distinct from the red damage bolts so the volley reads as
## "two attacks + one summon" rather than three identical projectiles. The
## landing flash is suppressed — the RitualSummonImpactVFX shockwaves are the
## arrival beat, not a soft-glow flash.
static func create_for_summon(from_pos: Vector2, to_pos: Vector2) -> RitualProjectile:
	var p := RitualProjectile.create(from_pos, to_pos)
	p._for_summon = true
	return p

func _play() -> void:
	var cast_sfx := "res://assets/audio/sfx/spells/void_spawning.wav" if _for_summon \
		else "res://assets/audio/sfx/spells/void_bolt_cast.wav"
	AudioManager.play_sfx(cast_sfx, -2.0)
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
	_core.texture = _circle_tex
	var tex_size: float = _core.texture.get_width()
	var size: float = SUMMON_CORE_SIZE if _for_summon else CORE_SIZE
	if tex_size > 0:
		_core.scale = Vector2.ONE * (size / tex_size)
	_core.modulate = SUMMON_COLOR_CORE if _for_summon else COLOR_CORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_core.material = mat
	add_child(_core)

func _build_glow() -> void:
	_glow = Sprite2D.new()
	_glow.texture = _circle_tex
	var tex_size: float = _glow.texture.get_width()
	var size: float = SUMMON_GLOW_SIZE if _for_summon else GLOW_SIZE
	_glow.scale = Vector2.ONE * (size / maxf(tex_size, 1.0))
	_glow.modulate = SUMMON_COLOR_GLOW if _for_summon else COLOR_GLOW
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
	_flame_inner.local_coords = false

	_flame_inner.texture = _flame_tex
	_flame_inner.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_flame_inner.emission_sphere_radius = 18.0
	_flame_inner.direction = Vector2(-1, 0)
	_flame_inner.spread = 30.0
	_flame_inner.initial_velocity_min = 25.0
	_flame_inner.initial_velocity_max = 65.0
	_flame_inner.damping_min = 35.0
	_flame_inner.damping_max = 70.0
	_flame_inner.gravity = Vector2(0, -12.0)
	_flame_inner.scale_amount_min = 0.6
	_flame_inner.scale_amount_max = 1.0
	_flame_inner.scale_amount_curve = _make_flame_size_curve()
	_flame_inner.angle_min = -180.0
	_flame_inner.angle_max =  180.0

	# Color ramp: white-hot core → bright gold → crimson → deep wine → fade.
	# Reads as ritual fire (blood + gold) instead of void purple.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.95, 0.85, 0.95))
	gradient.add_point(0.15, Color(1.0, 0.80, 0.40, 0.90))   # bright gold
	gradient.add_point(0.40, Color(1.0, 0.40, 0.30, 0.75))   # vivid crimson
	gradient.add_point(0.70, Color(0.65, 0.10, 0.35, 0.45))  # wine
	gradient.set_color(gradient.get_point_count() - 1, Color(0.30, 0.05, 0.20, 0.0))
	_flame_inner.color_ramp = gradient

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
	_flame_outer.emission_sphere_radius = 24.0
	_flame_outer.direction = Vector2(-1, 0)
	_flame_outer.spread = 50.0
	_flame_outer.initial_velocity_min = 10.0
	_flame_outer.initial_velocity_max = 40.0
	_flame_outer.damping_min = 15.0
	_flame_outer.damping_max = 40.0
	_flame_outer.gravity = Vector2(0, -8.0)
	_flame_outer.scale_amount_min = 0.7
	_flame_outer.scale_amount_max = 1.2
	_flame_outer.scale_amount_curve = _make_flame_size_curve()
	_flame_outer.angle_min = -180.0
	_flame_outer.angle_max =  180.0

	# Outer cone — wispier and a touch more violet to hint at the dominion side
	# of the ritual (so the bolt isn't pure red).
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.55, 0.35, 0.55))
	gradient.add_point(0.30, Color(0.75, 0.25, 0.45, 0.40))
	gradient.add_point(0.60, Color(0.45, 0.10, 0.50, 0.20))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.20, 0.05, 0.30, 0.0))
	_flame_outer.color_ramp = gradient

	add_child(_flame_outer)

func _build_embers() -> void:
	_embers = CPUParticles2D.new()
	_embers.emitting = true
	_embers.amount = 14
	_embers.lifetime = 0.3
	_embers.one_shot = false
	_embers.explosiveness = 0.0
	_embers.randomness = 1.0
	_embers.local_coords = false

	_embers.texture = _ember_tex
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = 12.0
	_embers.direction = Vector2(-1, 0)
	_embers.spread = 55.0
	_embers.initial_velocity_min = 50.0
	_embers.initial_velocity_max = 130.0
	_embers.damping_min = 100.0
	_embers.damping_max = 200.0
	_embers.gravity = Vector2.ZERO
	_embers.scale_amount_min = 0.08
	_embers.scale_amount_max = 0.18
	_embers.scale_amount_curve = _make_fade_curve()

	# Bright gold sparks → fade to crimson → out.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	gradient.add_point(0.2, Color(1.0, 0.6, 0.3, 0.85))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.65, 0.15, 0.20, 0.0))
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

	# Lerp position along arc.
	var straight: Vector2 = _from.lerp(_to, t)
	var arc_offset: float = -4.0 * ARC_HEIGHT * t * (t - 1.0)
	position = straight + Vector2(0, -arc_offset)

	# Compute travel direction from frame-to-frame movement so the bolt orients itself.
	var travel_dir: Vector2 = (position - _prev_pos).normalized()
	if travel_dir.length_squared() < 0.001:
		travel_dir = (_to - _from).normalized()
	_prev_pos = position

	rotation = travel_dir.angle()

	# Spin the core (independent of node rotation) and pulse its scale.
	if _core:
		_core.rotation += SPIN_SPEED * delta
		var pulse: float = lerpf(PULSE_MIN, PULSE_MAX, (sin(_elapsed * PULSE_SPEED * TAU) + 1.0) * 0.5)
		var core_size_now: float = SUMMON_CORE_SIZE if _for_summon else CORE_SIZE
		var base_scale: float = core_size_now / maxf(_core.texture.get_width(), 1) if _core.texture else 0.15
		_core.scale = Vector2.ONE * base_scale * pulse

	if _glow:
		var glow_pulse: float = lerpf(0.45, 0.65, (sin(_elapsed * 6.0) + 1.0) * 0.5)
		_glow.modulate.a = glow_pulse

	# Flame trails point opposite of travel direction.
	var backward: Vector2 = -travel_dir
	if _flame_inner: _flame_inner.direction = backward
	if _flame_outer: _flame_outer.direction = backward
	if _embers:      _embers.direction      = backward

	if t >= 1.0:
		_active = false
		_on_impact()

# ═════════════════════════════════════════════════════════════════════════════
# Impact
# ═════════════════════════════════════════════════════════════════════════════

func _on_impact() -> void:
	# Damage bolts get the standard impact thud. The summon bolt's arrival is
	# punctuated by RitualSummonImpactVFX (shockwaves + slot shake), so we skip
	# the bolt's own impact SFX/flash here to avoid stacking two arrival beats.
	if not _for_summon:
		AudioManager.play_sfx("res://assets/audio/sfx/spells/void_bolt_impact.wav", -2.0)
	impact_hit.emit(0)

	if _flame_inner: _flame_inner.emitting = false
	if _flame_outer: _flame_outer.emitting = false
	if _embers:      _embers.emitting      = false

	if not _for_summon:
		_spawn_impact_flash()

	if _core:
		var fade_tween := create_tween()
		fade_tween.tween_property(_core, "modulate:a", 0.0, IMPACT_FADE)
		fade_tween.parallel().tween_property(_core, "scale", _core.scale * 1.8, IMPACT_FADE)
	if _glow:
		var glow_tween := create_tween()
		glow_tween.tween_property(_glow, "modulate:a", 0.0, IMPACT_FADE)

	await get_tree().create_timer(IMPACT_LINGER).timeout
	if not is_inside_tree():
		return
	finished.emit()
	queue_free()

func _spawn_impact_flash() -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var flash := Sprite2D.new()
	flash.texture = _circle_tex
	var tex_size: float = flash.texture.get_width()
	var size: float = GLOW_SIZE * 1.3
	flash.scale = Vector2.ONE * (size / maxf(tex_size, 1.0))
	flash.modulate = COLOR_IMPACT_FLASH
	flash.global_position = global_position
	flash.z_index = 261
	flash.z_as_relative = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = mat
	host.add_child(flash)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "modulate:a", 0.0, IMPACT_FADE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(flash, "scale", flash.scale * 1.7, IMPACT_FADE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(flash.queue_free)

# ═════════════════════════════════════════════════════════════════════════════
# Procedural Textures (mirrors VoidBoltProjectile — same shapes work for both)
# ═════════════════════════════════════════════════════════════════════════════

func _ensure_textures() -> void:
	if not _flame_tex:
		_flame_tex = _make_flame_texture()
	if not _circle_tex:
		_circle_tex = _make_soft_circle()
	if not _ember_tex:
		_ember_tex = _make_soft_circle_small()

static func _make_flame_texture() -> ImageTexture:
	var w := 48
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cy: float = h * 0.5
	for y in h:
		for x in w:
			var px: float = x + 0.5
			var py: float = y + 0.5
			var nx: float = px / float(w)
			var ny: float = (py - cy) / (h * 0.5)
			var width: float
			if nx < 0.65:
				var tail_t: float = nx / 0.65
				width = tail_t * tail_t * 0.9
			else:
				var head_t: float = (nx - 0.65) / 0.35
				width = 0.9 * (1.0 - head_t * head_t)
			var dist_from_center: float = absf(ny)
			if width <= 0.001:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))
				continue
			var edge: float = clampf(1.0 - dist_from_center / maxf(width, 0.001), 0.0, 1.0)
			var alpha: float = edge * edge
			alpha *= 0.4 + 0.6 * nx
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

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

static func _make_flame_size_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.08, 1.0))
	curve.add_point(Vector2(0.25, 0.6))
	curve.add_point(Vector2(0.5, 0.25))
	curve.add_point(Vector2(0.75, 0.08))
	curve.add_point(Vector2(1.0, 0.0))
	return curve

static func _make_fade_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	return curve
