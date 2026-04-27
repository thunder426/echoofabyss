## VoidTouchedImpDeathVFX.gd
## On-death AoE VFX for Void-Touched Imp — a void fissure cracks open across
## the enemy board, then erupts hitting all enemy minions.
##
## Phases:
##   1. fissure  (0.60s) — clip-reveal crack left-to-right + small board shake
##   2. eruption (0.50s) — cross-fade to bright eruption + Y-scale punch.
##                          impact_hit fires at 30% into the phase (peak),
##                          per-target flashes spawn, heavy board shake.
##   3. fade     (0.35s) — eruption dies down, smoke wisps rise.
##
## Spawn via VfxController.spawn(); caller awaits impact_hit to apply damage.
class_name VoidTouchedImpDeathVFX
extends BaseVfx

const TEX_FISSURE: Texture2D  = preload("res://assets/art/fx/fissure_dormant.png")
const TEX_ERUPTION: Texture2D = preload("res://assets/art/fx/fissure_erupt.png")
const TEX_GLOW: Texture2D     = preload("res://assets/art/fx/glow_soft.png")

const SFX_FISSURE_CRACK: String = "res://assets/audio/sfx/minions/vti_fissure_crack.wav"
const SFX_FISSURE_ERUPT: String = "res://assets/audio/sfx/minions/vti_fissure_erupt.wav"

const COLOR_CORE_FLASH: Color   = Color(1.0, 0.9, 1.0, 1.0)
const COLOR_IMPACT_FLASH: Color = Color(0.85, 0.45, 1.0, 0.90)

const FISSURE_DURATION: float  = 0.60
const ERUPTION_DURATION: float = 0.50
const FADE_DURATION: float     = 0.35
const ERUPTION_PEAK_FRACTION: float = 0.30  # impact_hit at 30% into eruption

const FISSURE_WIDTH: float  = 960.0
const FISSURE_HEIGHT: float = 277.0

const BEAT_ERUPTION_PEAK := "eruption_peak"

var _origin: Vector2 = Vector2.ZERO
var _target_slots: Array = []
var _board: Control = null
var _board_center: Vector2 = Vector2.ZERO
var _fissure_pos: Vector2 = Vector2.ZERO

var _fissure_clip: Control = null
var _fissure_sprite: TextureRect = null
var _eruption_sprite: TextureRect = null

static var _circle_tex: ImageTexture


static func create(origin_pos: Vector2, target_slots: Array, board: Control) -> VoidTouchedImpDeathVFX:
	var vfx := VoidTouchedImpDeathVFX.new()
	vfx._origin = origin_pos
	vfx._target_slots = target_slots
	vfx._board = board
	return vfx


func _play() -> void:
	_ensure_textures()
	if get_parent() == null:
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return

	if _board and is_instance_valid(_board):
		_board_center = _board.global_position + _board.size * 0.5
	else:
		_board_center = _origin
	_fissure_pos = Vector2(
		_board_center.x - FISSURE_WIDTH * 0.5,
		_board_center.y - FISSURE_HEIGHT * 0.5
	)

	var seq := sequence()
	seq.on(BEAT_ERUPTION_PEAK, _on_eruption_peak)
	seq.run([
		VfxPhase.new("fissure",  FISSURE_DURATION,  _build_fissure),
		VfxPhase.new("eruption", ERUPTION_DURATION, _build_eruption) \
			.emits(BEAT_ERUPTION_PEAK, ERUPTION_PEAK_FRACTION) \
			.emits(VfxSequence.RESERVED_IMPACT_HIT, ERUPTION_PEAK_FRACTION),
		VfxPhase.new("fade",     FADE_DURATION,     _build_fade),
	])


# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: Fissure crack
# ═════════════════════════════════════════════════════════════════════════════

func _build_fissure(duration: float) -> void:
	AudioManager.play_sfx(SFX_FISSURE_CRACK, -6.0)
	var scene: Node = get_parent()
	if scene == null:
		return

	_fissure_clip = Control.new()
	_fissure_clip.clip_contents = true
	_fissure_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fissure_clip.position = _fissure_pos
	_fissure_clip.set_size(Vector2(0.0, FISSURE_HEIGHT))
	_fissure_clip.z_index = 20
	_fissure_clip.z_as_relative = false
	scene.add_child(_fissure_clip)

	_fissure_sprite = _make_additive_texture_rect(TEX_FISSURE)
	_fissure_sprite.set_size(Vector2(FISSURE_WIDTH, FISSURE_HEIGHT))
	_fissure_sprite.position = Vector2.ZERO
	_fissure_clip.add_child(_fissure_sprite)

	var tw_open := create_tween()
	tw_open.tween_property(_fissure_clip, "size:x", FISSURE_WIDTH, duration) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	if _board and is_instance_valid(_board):
		ScreenShakeEffect.shake(_board, self, 8.0, 6)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2: Eruption
# ═════════════════════════════════════════════════════════════════════════════

func _build_eruption(_duration: float) -> void:
	AudioManager.play_sfx(SFX_FISSURE_ERUPT, -4.0)
	var scene: Node = get_parent()
	if scene == null:
		return

	_eruption_sprite = _make_additive_texture_rect(TEX_ERUPTION)
	_eruption_sprite.set_size(Vector2(FISSURE_WIDTH, FISSURE_HEIGHT))
	_eruption_sprite.position = _fissure_pos
	_eruption_sprite.pivot_offset = Vector2(FISSURE_WIDTH * 0.5, FISSURE_HEIGHT * 0.5)
	_eruption_sprite.scale = Vector2(1.0, 0.8)
	_eruption_sprite.modulate.a = 0.0
	_eruption_sprite.z_index = 21
	_eruption_sprite.z_as_relative = false
	scene.add_child(_eruption_sprite)

	# Cross-fade: dormant dims, eruption brightens + Y-scale punch
	var tw_erupt := create_tween().set_parallel(true)
	tw_erupt.tween_property(_eruption_sprite, "modulate:a", 1.0, 0.10) \
		.set_trans(Tween.TRANS_SINE)
	tw_erupt.tween_property(_eruption_sprite, "scale:y", 1.15, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_erupt.chain().tween_property(_eruption_sprite, "scale:y", 1.0, 0.15) \
		.set_trans(Tween.TRANS_SINE)
	if _fissure_sprite != null and is_instance_valid(_fissure_sprite):
		tw_erupt.tween_property(_fissure_sprite, "modulate:a", 0.3, 0.15) \
			.set_trans(Tween.TRANS_SINE)


# Listener — fires at eruption peak (30% into the eruption phase).
func _on_eruption_peak() -> void:
	var scene: Node = get_parent()
	if scene == null:
		return
	_spawn_target_impacts(scene)
	if _board and is_instance_valid(_board):
		ScreenShakeEffect.shake(_board, self, 16.0, 12)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3: Fade
# ═════════════════════════════════════════════════════════════════════════════

func _build_fade(duration: float) -> void:
	var scene: Node = get_parent()
	if scene == null:
		return
	_spawn_smoke_wisps(scene, _board_center)

	var tw_fade := create_tween().set_parallel(true)
	if is_instance_valid(_eruption_sprite):
		tw_fade.tween_property(_eruption_sprite, "modulate:a", 0.0, duration * 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw_fade.tween_property(_eruption_sprite, "scale:y", 0.6, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if is_instance_valid(_fissure_sprite):
		tw_fade.tween_property(_fissure_sprite, "modulate:a", 0.0, duration * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw_fade.chain().tween_callback(func() -> void:
		if is_instance_valid(_fissure_clip):
			_fissure_clip.queue_free()
		elif is_instance_valid(_fissure_sprite):
			_fissure_sprite.queue_free()
		if is_instance_valid(_eruption_sprite):
			_eruption_sprite.queue_free())


# ═════════════════════════════════════════════════════════════════════════════
# Per-target impact flashes
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_target_impacts(parent: Node) -> void:
	for slot in _target_slots:
		if not is_instance_valid(slot):
			continue
		var s: Control = slot as Control
		var center: Vector2 = s.global_position + s.size * 0.5

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

		var orig_mod: Color = s.modulate
		var stw := s.create_tween()
		stw.tween_property(s, "modulate", Color(1.5, 0.5, 2.0, 1.0), 0.05)
		stw.tween_property(s, "modulate", orig_mod, 0.22)


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
