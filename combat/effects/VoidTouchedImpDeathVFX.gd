## VoidTouchedImpDeathVFX.gd
## On-death AoE VFX for Void-Touched Imp — a void fissure cracks open across the
## enemy board, then erupts with violent void energy hitting all enemy minions.
##
## Phases:
##   Phase 1 — Fissure (0.35s):
##     Core flash at origin.  The dormant fissure texture reveals left-to-right
##     via a clip container across the full board width.  Additive blending
##     on black-background art makes only the glowing crack visible.
##     Small screen shake as the ground splits.
##
##   Phase 2 — Eruption (0.50s):
##     Cross-fade to the eruption texture (brighter, more intense).
##     `impact_hit` emitted at the eruption peak — sync damage here.
##     Per-target impact flashes + slot purple tint.
##     Heavy screen shake.  Ejecta particles burst from the fissure line.
##
##   Phase 3 — Fade (0.35s):
##     Eruption fades out.  Smoke wisps rise from the fissure line.
##
## Usage:
##   var vfx := VoidTouchedImpDeathVFX.create(origin_pos, target_slots, board_node)
##   combat_scene.$UI.add_child(vfx)
##   await vfx.impact_hit   # apply damage here
##   await vfx.finished
class_name VoidTouchedImpDeathVFX
extends Node

signal finished
signal impact_hit  ## Emitted at eruption peak — sync damage here.

const TEX_FISSURE: Texture2D  = preload("res://assets/art/fx/fissure_dormant.png")
const TEX_ERUPTION: Texture2D = preload("res://assets/art/fx/fissure_erupt.png")
const TEX_GLOW: Texture2D     = preload("res://assets/art/fx/glow_soft.png")

const SFX_FISSURE_CRACK: String = "res://assets/audio/sfx/minions/vti_fissure_crack.wav"
const SFX_FISSURE_ERUPT: String = "res://assets/audio/sfx/minions/vti_fissure_erupt.wav"

# ── Colors ───────────────────────────────────────────────────────────────────
const COLOR_CORE_FLASH: Color   = Color(1.0, 0.9, 1.0, 1.0)
const COLOR_IMPACT_FLASH: Color = Color(0.85, 0.45, 1.0, 0.90)

# ── Timing ───────────────────────────────────────────────────────────────────
const FISSURE_DURATION: float  = 0.60
const ERUPTION_DURATION: float = 0.50
const FADE_DURATION: float     = 0.35
const TOTAL_DURATION: float    = FISSURE_DURATION + ERUPTION_DURATION + FADE_DURATION

# ── Layout ───────────────────────────────────────────────────────────────────
const FISSURE_WIDTH: float  = 960.0   # texture display width (matches board)
const FISSURE_HEIGHT: float = 277.0   # texture display height

var _origin: Vector2 = Vector2.ZERO
var _target_slots: Array = []
var _board: Control = null    # the opponent's HBoxContainer board node

var _fissure_clip: Control = null    # clip container for left-to-right reveal
var _fissure_sprite: TextureRect = null
var _eruption_sprite: TextureRect = null

static var _circle_tex: ImageTexture


static func create(origin_pos: Vector2, target_slots: Array, board: Control) -> VoidTouchedImpDeathVFX:
	var vfx := VoidTouchedImpDeathVFX.new()
	vfx._origin = origin_pos
	vfx._target_slots = target_slots
	vfx._board = board
	return vfx


func _ready() -> void:
	_ensure_textures()
	_run()


func _run() -> void:
	var scene: Node = get_parent()
	if scene == null or not is_inside_tree():
		impact_hit.emit()
		finished.emit()
		queue_free()
		return

	# Calculate fissure position — centered on the target board horizontally,
	# vertically centered on the board's midline.
	var board_center: Vector2
	if _board and is_instance_valid(_board):
		board_center = _board.global_position + _board.size * 0.5
	else:
		# Fallback: use the origin position
		board_center = _origin

	var fissure_pos: Vector2 = Vector2(
		board_center.x - FISSURE_WIDTH * 0.5,
		board_center.y - FISSURE_HEIGHT * 0.5
	)

	# ═══ Phase 1: Fissure — crack rips left-to-right across the board ═══════
	AudioManager.play_sfx(SFX_FISSURE_CRACK, -6.0)

	# Clip container — grows from width 0→FISSURE_WIDTH to reveal the fissure
	# left-to-right.  clip_contents hides anything outside its rect.
	_fissure_clip = Control.new()
	_fissure_clip.clip_contents = true
	_fissure_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fissure_clip.position = fissure_pos
	_fissure_clip.set_size(Vector2(0.0, FISSURE_HEIGHT))
	_fissure_clip.z_index = 20
	_fissure_clip.z_as_relative = false
	scene.add_child(_fissure_clip)

	# Dormant fissure sprite inside the clip — full size, additive blending
	_fissure_sprite = _make_additive_texture_rect(TEX_FISSURE)
	_fissure_sprite.set_size(Vector2(FISSURE_WIDTH, FISSURE_HEIGHT))
	_fissure_sprite.position = Vector2.ZERO
	_fissure_clip.add_child(_fissure_sprite)

	# Reveal: clip width 0→full (left-to-right crack spread)
	var tw_open := create_tween()
	tw_open.tween_property(_fissure_clip, "size:x", FISSURE_WIDTH, FISSURE_DURATION) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# Ground-splitting shake — shake the target board (a Control with real
	# position), not the parent CanvasLayer (no position, no-ops).
	if _board and is_instance_valid(_board):
		ScreenShakeEffect.shake(_board, self, 8.0, 6)

	await get_tree().create_timer(FISSURE_DURATION).timeout
	if not is_inside_tree():
		impact_hit.emit()
		_cleanup()
		return

	# ═══ Phase 2: Eruption — intense void energy blasts upward ══════════════
	AudioManager.play_sfx(SFX_FISSURE_ERUPT, -4.0)

	# Eruption sprite — same position, overlays the dormant fissure
	_eruption_sprite = _make_additive_texture_rect(TEX_ERUPTION)
	_eruption_sprite.set_size(Vector2(FISSURE_WIDTH, FISSURE_HEIGHT))
	_eruption_sprite.position = fissure_pos
	_eruption_sprite.pivot_offset = Vector2(FISSURE_WIDTH * 0.5, FISSURE_HEIGHT * 0.5)
	_eruption_sprite.scale = Vector2(1.0, 0.8)
	_eruption_sprite.modulate.a = 0.0
	_eruption_sprite.z_index = 21
	_eruption_sprite.z_as_relative = false
	scene.add_child(_eruption_sprite)

	# Cross-fade: dormant dims, eruption brightens + scale punch
	var tw_erupt := create_tween().set_parallel(true)
	# Eruption fades in with a Y-scale punch (0.8→1.15→1.0)
	tw_erupt.tween_property(_eruption_sprite, "modulate:a", 1.0, 0.10) \
		.set_trans(Tween.TRANS_SINE)
	tw_erupt.tween_property(_eruption_sprite, "scale:y", 1.15, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_erupt.chain().tween_property(_eruption_sprite, "scale:y", 1.0, 0.15) \
		.set_trans(Tween.TRANS_SINE)
	# Dormant fades out
	tw_erupt.tween_property(_fissure_sprite, "modulate:a", 0.3, 0.15) \
		.set_trans(Tween.TRANS_SINE)

	# Impact at eruption peak (slight delay for the visual to read)
	await get_tree().create_timer(ERUPTION_DURATION * 0.30).timeout
	if not is_inside_tree():
		impact_hit.emit()
		_cleanup()
		return

	impact_hit.emit()
	_spawn_target_impacts(scene)

	# Heavy shake — shake the target board (Control with real position),
	# not a CanvasLayer (no position, no-ops).
	if _board and is_instance_valid(_board):
		ScreenShakeEffect.shake(_board, self, 16.0, 12)

	# Wait out remaining eruption
	var erupt_remaining: float = ERUPTION_DURATION * 0.70
	await get_tree().create_timer(erupt_remaining).timeout
	if not is_inside_tree():
		_cleanup()
		return

	# ═══ Phase 3: Fade — eruption dies down ═════════════════════════════════
	_spawn_smoke_wisps(scene, board_center)

	var tw_fade := create_tween().set_parallel(true)
	if is_instance_valid(_eruption_sprite):
		tw_fade.tween_property(_eruption_sprite, "modulate:a", 0.0, FADE_DURATION * 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw_fade.tween_property(_eruption_sprite, "scale:y", 0.6, FADE_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if is_instance_valid(_fissure_sprite):
		tw_fade.tween_property(_fissure_sprite, "modulate:a", 0.0, FADE_DURATION * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(FADE_DURATION).timeout

	_cleanup()


# ═════════════════════════════════════════════════════════════════════════════
# Per-Target Impact Flashes
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_target_impacts(parent: Node) -> void:
	for slot in _target_slots:
		if not is_instance_valid(slot):
			continue
		var s: Control = slot as Control
		var center: Vector2 = s.global_position + s.size * 0.5

		# Additive glow burst
		var flash := Sprite2D.new()
		flash.texture = TEX_GLOW
		var tex_size: float = flash.texture.get_width()
		var start_scale: float = 35.0 / maxf(tex_size, 1.0)
		flash.scale = Vector2.ONE * start_scale
		flash.global_position = center
		flash.modulate = COLOR_IMPACT_FLASH
		flash.z_index = 23
		flash.z_as_relative = false
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		flash.material = mat
		parent.add_child(flash)

		var tw := create_tween().set_parallel(true)
		tw.tween_property(flash, "scale", Vector2.ONE * start_scale * 2.8, 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(flash, "modulate:a", 0.0, 0.25) \
			.set_delay(0.06).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_callback(flash.queue_free)

		# Slot purple tint
		var orig_mod: Color = s.modulate
		var stw := s.create_tween()
		stw.tween_property(s, "modulate", Color(1.5, 0.5, 2.0, 1.0), 0.05)
		stw.tween_property(s, "modulate", orig_mod, 0.22)


# ═════════════════════════════════════════════════════════════════════════════
# Smoke Wisps (rise from fissure during fade)
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_smoke_wisps(parent: Node, center: Vector2) -> void:
	var wisps := CPUParticles2D.new()
	wisps.emitting = true
	wisps.amount = 8
	wisps.lifetime = 0.55
	wisps.one_shot = true
	wisps.explosiveness = 0.6
	wisps.randomness = 0.5
	wisps.local_coords = false
	wisps.texture = _circle_tex
	wisps.global_position = center

	wisps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	wisps.emission_rect_extents = Vector2(FISSURE_WIDTH * 0.35, 6.0)
	wisps.direction = Vector2(0, -1)
	wisps.spread = 25.0
	wisps.initial_velocity_min = 15.0
	wisps.initial_velocity_max = 50.0
	wisps.gravity = Vector2(0, -15.0)
	wisps.damping_min = 8.0
	wisps.damping_max = 25.0

	wisps.scale_amount_min = 0.25
	wisps.scale_amount_max = 0.55
	wisps.scale_amount_curve = _make_fade_curve()

	wisps.z_index = 19
	wisps.z_as_relative = false

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.5, 0.22, 0.7, 0.45))
	gradient.add_point(0.4, Color(0.35, 0.15, 0.5, 0.30))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.15, 0.06, 0.25, 0.0))
	wisps.color_ramp = gradient

	parent.add_child(wisps)
	get_tree().create_timer(wisps.lifetime + 0.15).timeout.connect(func() -> void:
		if is_instance_valid(wisps):
			wisps.queue_free())


# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

func _make_additive_texture_rect(tex: Texture2D) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tr.material = mat
	return tr


func _cleanup() -> void:
	if is_instance_valid(_fissure_clip):
		_fissure_clip.queue_free()  # also frees _fissure_sprite (child)
	elif is_instance_valid(_fissure_sprite):
		_fissure_sprite.queue_free()
	if is_instance_valid(_eruption_sprite):
		_eruption_sprite.queue_free()
	finished.emit()
	queue_free()


func _ensure_textures() -> void:
	if not _circle_tex:
		_circle_tex = _make_soft_circle()


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
