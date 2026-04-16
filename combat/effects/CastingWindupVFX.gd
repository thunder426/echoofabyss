## CastingWindupVFX.gd
## Faction-themed glyph that appears at the caster position while a spell's
## large preview card is held on screen (~1.07s). Sells the cast windup so the
## preview delay feels deliberate rather than sluggish.
##
## One glyph — same sprite — rotates continuously and pulses. Two halo sprites
## parented under it inherit its rotation/scale, and their alphas ramp from 0
## to very strong so the glyph appears to emit more and more light outward.
## The main glyph alpha stays 1.0 the entire time; only halos + shader glow
## change. On release the whole unit fades out together.
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name CastingWindupVFX
extends Node2D

const TEX_VOID: Texture2D      = preload("res://assets/art/fx/casting_glyphs/void_glyph.png")
const TEX_FERAL: Texture2D     = preload("res://assets/art/fx/casting_glyphs/feral_glyph.png")
const TEX_CORRUPTED: Texture2D = preload("res://assets/art/fx/casting_glyphs/corrupted_glyph.png")
const TEX_ABYSS: Texture2D     = preload("res://assets/art/fx/casting_glyphs/abyss_glyph.png")
const SHADER_GLOW: Shader      = preload("res://combat/effects/casting_glyph_glow.gdshader")

const GLYPH_SIZE_PLAYER: float = 160.0
const GLYPH_SIZE_ENEMY: float  = 100.0

const FADE_IN: float  = 0.22
const HOLD: float     = 0.63
const FADE_OUT: float = 0.22
const TOTAL: float    = FADE_IN + HOLD + FADE_OUT

# Faction palettes — tint applied via modulate (asset is white line-art).
const TINT_VOID: Color      = Color(0.45, 0.22, 0.70, 1.0)  # darker purple / violet
const TINT_FERAL: Color     = Color(0.55, 0.95, 0.35, 1.0)  # feral green + red accent
const TINT_CORRUPTED: Color = Color(0.55, 0.90, 0.40, 1.0)  # sickly green (placeholder tuning)
const TINT_ABYSS: Color     = Color(0.55, 0.30, 0.85, 1.0)  # deep violet (placeholder tuning)

# Halo tint channel-scaling per faction. Additive blending washes toward white
# at peak intensity — suppress off-hue channels so the halo holds its color.
const HALO_SCALE_VOID: Vector3      = Vector3(0.65, 0.35, 0.95)  # purple halo
const HALO_SCALE_FERAL: Vector3     = Vector3(0.95, 0.10, 0.10)  # dark red halo
const HALO_SCALE_CORRUPTED: Vector3 = Vector3(0.15, 0.55, 0.15)  # dark green halo
const HALO_SCALE_ABYSS: Vector3     = Vector3(0.22, 0.05, 0.32)  # dark violet-black

var _faction: String = "void"
var _center: Vector2 = Vector2.ZERO
var _is_enemy: bool  = false

# Cached procedural radial-gradient glow texture, shared across all instances.
static var _glow_tex: ImageTexture = null


static func create(faction: String, center: Vector2, is_enemy: bool) -> CastingWindupVFX:
	var vfx := CastingWindupVFX.new()
	vfx._faction  = faction
	vfx._center   = center
	vfx._is_enemy = is_enemy
	vfx.z_index = 190
	return vfx


func _ready() -> void:
	global_position = _center

	var tex: Texture2D = _texture_for(_faction)
	if tex == null:
		queue_free()
		return

	var target_size: float = GLYPH_SIZE_ENEMY if _is_enemy else GLYPH_SIZE_PLAYER
	var tex_max: float = maxf(tex.get_width(), tex.get_height())
	var target_scale: float = target_size / maxf(tex_max, 1.0)

	var tint: Color = _tint_for(_faction)

	# ── Radial glow halo (procedural soft-circle gradient, additive, tinted).
	#    Sits UNDER the glyph — emits diffuse outward light. Does NOT rotate.
	# Use a deeper, more saturated tint for the glow so additive blending
	# doesn't wash the hue out to white at peak intensity.
	var hs: Vector3 = _halo_scale_for(_faction)
	var glow_tint := Color(tint.r * hs.x, tint.g * hs.y, tint.b * hs.z, 1.0)
	var glow := Sprite2D.new()
	glow.texture = _get_glow_texture()
	glow.modulate = Color(glow_tint.r, glow_tint.g, glow_tint.b, 0.0)
	# Size glow to comfortably extend beyond the glyph.
	var glow_tex_size: float = float(glow.texture.get_width())
	var glow_target_px: float = target_size * 2.2
	glow.scale = Vector2.ONE * (glow_target_px / maxf(glow_tex_size, 1.0))
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	add_child(glow)

	# ── Main glyph (Sprite2D) — carries rotation & scale.
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	sprite.scale = Vector2.ONE * target_scale
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_GLOW
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("white_mix", 0.0)
	mat.set_shader_parameter("thickness", 3.0)
	mat.set_shader_parameter("tex_size", Vector2(tex.get_width(), tex.get_height()))
	sprite.material = mat
	add_child(sprite)

	# ── Tween 1: smooth continuous rotation across the entire lifetime.
	# Feral spins CCW, others CW; all factions use the same smooth linear spin.
	var rotate_dir: float = -1.0 if _faction == "feral" else 1.0
	var total_rot: float  = TAU * 0.6 * rotate_dir
	var rot_tw := create_tween()
	rot_tw.tween_property(sprite, "rotation", total_rot, TOTAL) \
		.set_trans(Tween.TRANS_LINEAR)

	# ── Glyph shader intensity: void (player) ramps up for a charge-up feel.
	# Other factions keep their base color flat throughout the windup.
	if _faction == "void":
		var set_intensity := func(v: float) -> void:
			mat.set_shader_parameter("intensity", v)
		var glow_tw := create_tween()
		glow_tw.tween_method(set_intensity, 0.0, 0.5, FADE_IN) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		glow_tw.tween_method(set_intensity, 0.5, 6.0, HOLD) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		glow_tw.tween_method(set_intensity, 6.0, 0.0, FADE_OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# ── Halo alpha: fade in to full, hold flat, fade out on release.
	var halo_tw := create_tween()
	halo_tw.tween_property(glow, "modulate:a", 0.85, FADE_IN) \
		.set_trans(Tween.TRANS_SINE)
	halo_tw.tween_property(glow, "modulate:a", 0.85, HOLD)
	halo_tw.tween_property(glow, "modulate:a", 0.0, FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# ── Halo scale — grows steadily outward across the whole windup, then pops
	# on release. Starts small so the growth is clearly felt as the cast charges.
	var halo_peak_scale: Vector2 = glow.scale
	glow.scale = halo_peak_scale * 0.55
	var glow_scale_tw := create_tween()
	glow_scale_tw.tween_property(glow, "scale", halo_peak_scale * 0.85, FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	glow_scale_tw.tween_property(glow, "scale", halo_peak_scale * 1.35, HOLD) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	glow_scale_tw.tween_property(glow, "scale", halo_peak_scale * 1.65, FADE_OUT) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# ── Tween 5: scale pulse to MAX only at the very end (release/cast moment).
	# Holds target_scale through fade-in and hold, then pops to max during fade-out.
	var pulse_tw := create_tween()
	pulse_tw.tween_interval(FADE_IN + HOLD)
	pulse_tw.tween_property(sprite, "scale", Vector2.ONE * (target_scale * 1.45),
		FADE_OUT).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# ── Tween 6: cleanup at total duration.
	var life_tw := create_tween()
	life_tw.tween_interval(TOTAL)
	life_tw.tween_callback(queue_free)


func _texture_for(faction: String) -> Texture2D:
	match faction:
		"void":      return TEX_VOID
		"feral":     return TEX_FERAL
		"corrupted": return TEX_CORRUPTED
		"abyss":     return TEX_ABYSS
		_:           return TEX_VOID


## Lazily build a soft radial-gradient circle texture, cached statically so
## every CastingWindupVFX instance reuses the same GPU texture.
## White RGB + alpha fall-off; tinting is applied per-instance via modulate.
static func _get_glow_texture() -> ImageTexture:
	if _glow_tex != null:
		return _glow_tex
	const SIZE := 256
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre: float = float(SIZE) * 0.5
	for y in SIZE:
		for x in SIZE:
			var dx: float = (float(x) - centre) / centre
			var dy: float = (float(y) - centre) / centre
			var r: float = sqrt(dx * dx + dy * dy)
			# Smooth falloff: 1.0 at centre, 0 at edge. Use a curve that stays
			# bright in the centre and falls off softly.
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)  # smoothstep
			a = a * a  # bias further toward bright-centre / soft-outer
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


func _tint_for(faction: String) -> Color:
	match faction:
		"void":      return TINT_VOID
		"feral":     return TINT_FERAL
		"corrupted": return TINT_CORRUPTED
		"abyss":     return TINT_ABYSS
		_:           return TINT_VOID


func _halo_scale_for(faction: String) -> Vector3:
	match faction:
		"void":      return HALO_SCALE_VOID
		"feral":     return HALO_SCALE_FERAL
		"corrupted": return HALO_SCALE_CORRUPTED
		"abyss":     return HALO_SCALE_ABYSS
		_:           return HALO_SCALE_VOID
