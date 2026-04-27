## GraftedButcherVFX.gd
## ON PLAY VFX for Grafted Butcher — feast on a friendly sacrifice, engorge,
## then unleash a crimson cleaver wave across the enemy board (200 AoE).
##
## Phases:
##   1. tendril    (0.49s) — graft tether retracts toward the Butcher
##   2. engorge    (0.60s) — radial flash + butcher panel punch + mild shake
##   3. wave_open  (0.66s) — cleaver wave reveals across enemy board;
##                            distortion band + gore chunks; impact_hit fires
##                            at end of this phase (60% of full wave duration)
##   4. wave_tail  (0.44s) — remaining wave sweep + per-target impact flashes
##                            + heavy board shake (kicked off at impact)
##   5. settle     (0.50s) — wave fades, residual gore falls
##
## Spawn via VfxController.spawn(); caller awaits impact_hit to apply damage.
class_name GraftedButcherVFX
extends BaseVfx

const TEX_WAVE: Texture2D    = preload("res://assets/art/fx/meat_cleaver_wave.png")
const TEX_TENDRIL: Texture2D = preload("res://assets/art/fx/flesh_graft_tendril.png")
const TEX_ENGORGE: Texture2D = preload("res://assets/art/fx/butcher_engorge_glow.png")
const TEX_CHUNK_1: Texture2D = preload("res://assets/art/fx/flesh_chunk_1.png")
const TEX_CHUNK_2: Texture2D = preload("res://assets/art/fx/flesh_chunk_2.png")
const TEX_CHUNK_3: Texture2D = preload("res://assets/art/fx/flesh_chunk_3.png")

const SHADER_CRESCENT_SHOCK: Shader = preload("res://combat/effects/crescent_shockwave.gdshader")

const SFX_GRAFT: String   = "res://assets/audio/sfx/minions/grafted_butcher_graft.wav"
const SFX_CLEAVER: String = "res://assets/audio/sfx/minions/grafted_butcher_cleaver.wav"

const COLOR_WAVE_TINT: Color    = Color(1.15, 0.55, 0.75, 1.0)
const COLOR_ENGORGE_TINT: Color = Color(1.0, 0.85, 0.95, 1.0)
const COLOR_TENDRIL_TINT: Color = Color(1.0, 0.75, 0.90, 1.0)
const COLOR_IMPACT_FLASH: Color = Color(1.0, 0.35, 0.55, 0.95)
const COLOR_BUTCHER_FEED: Color = Color(1.6, 0.7, 1.1, 1.0)
const COLOR_WAVE_DISTORT: Color = Color(1.0, 0.25, 0.35, 0.14)

# Original timing: TENDRIL 0.70 (* 0.7 await), ENGORGE 0.60, WAVE 1.10 with
# impact at 60%. Reorganized into 5 phases that match the visible beats.
const TENDRIL_DURATION: float    = 0.70 * 0.7   # only 70% of tendril plays before engorge starts
const ENGORGE_DURATION: float    = 0.60
const WAVE_DURATION: float       = 1.10
const WAVE_OPEN_FRACTION: float  = 0.60         # impact_hit fires after this much of the wave
const SETTLE_DURATION: float     = 0.50

const WAVE_WIDTH: float  = 960.0
const WAVE_HEIGHT: float = 270.0

var _butcher_panel: Control = null
var _sac_center: Vector2 = Vector2.ZERO
var _enemy_board: Control = null
var _target_slots: Array = []

var _fx_layer: CanvasLayer = null
var _wave_clip: Control = null
var _wave_sprite: TextureRect = null
var _butcher_center: Vector2 = Vector2.ZERO
var _board_center: Vector2 = Vector2.ZERO
var _sweep_left_to_right: bool = true

static var _chunk_variants: Array[Texture2D] = []


static func create(butcher_panel: Control, sac_center: Vector2,
		enemy_board: Control, target_slots: Array) -> GraftedButcherVFX:
	var vfx := GraftedButcherVFX.new()
	vfx._butcher_panel = butcher_panel
	vfx._sac_center = sac_center
	vfx._enemy_board = enemy_board
	vfx._target_slots = target_slots
	return vfx


func _play() -> void:
	if _chunk_variants.is_empty():
		_chunk_variants = [TEX_CHUNK_1, TEX_CHUNK_2, TEX_CHUNK_3]

	if _butcher_panel and is_instance_valid(_butcher_panel):
		_butcher_center = _butcher_panel.global_position + _butcher_panel.size * 0.5
	if _enemy_board and is_instance_valid(_enemy_board):
		_board_center = _enemy_board.global_position + _enemy_board.size * 0.5
	else:
		_board_center = _butcher_center
	_sweep_left_to_right = _butcher_center.x <= _board_center.x

	var seq := sequence()
	seq.on("wave_arrived", _on_wave_arrived)
	seq.run([
		VfxPhase.new("tendril",   TENDRIL_DURATION,                       _build_tendril),
		VfxPhase.new("engorge",   ENGORGE_DURATION,                       _build_engorge),
		VfxPhase.new("wave_open", WAVE_DURATION * WAVE_OPEN_FRACTION,     _build_wave) \
			.emits_at_end(VfxSequence.RESERVED_IMPACT_HIT) \
			.emits_at_end("wave_arrived"),
		VfxPhase.new("wave_tail", WAVE_DURATION * (1.0 - WAVE_OPEN_FRACTION), Callable()),
		VfxPhase.new("settle",    SETTLE_DURATION,                        _build_settle),
	])


# ═════════════════════════════════════════════════════════════════════════════
# Phase 1 — Graft tendril
# ═════════════════════════════════════════════════════════════════════════════

func _build_tendril(_duration: float) -> void:
	AudioManager.play_sfx(SFX_GRAFT, -6.0)
	if _sac_center == Vector2.ZERO or _butcher_center == Vector2.ZERO:
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var tex_w: float = TEX_TENDRIL.get_width()
	var delta: Vector2 = _butcher_center - _sac_center
	var distance: float = delta.length()
	if distance < 1.0 or tex_w < 1.0:
		return
	var display_h: float = clampf(distance * 0.20, 40.0, 100.0)

	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = _sac_center
	clip.pivot_offset = Vector2(0.0, display_h * 0.5)
	clip.rotation = delta.angle()
	clip.set_size(Vector2(0.0, display_h))
	clip.z_index = 21
	clip.z_as_relative = false
	parent.add_child(clip)

	var tendril := _make_additive_texture_rect(TEX_TENDRIL)
	tendril.set_size(Vector2(distance, display_h))
	tendril.position = Vector2.ZERO
	tendril.modulate = COLOR_TENDRIL_TINT
	clip.add_child(tendril)

	# Original: reveal 0.55, hold 0.15, fade 0.30 (sums to 1.0 of original
	# TENDRIL_DURATION 0.70). Phase budget is only 0.7*0.7=0.49 (only the
	# reveal+hold portion), the fade overlaps with engorge phase.
	var orig_total: float = 0.70
	var tw := create_tween()
	tw.tween_property(clip, "size:x", distance, orig_total * 0.55) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(orig_total * 0.15)
	tw.tween_property(clip, "modulate:a", 0.0, orig_total * 0.30) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(clip.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2 — Engorge
# ═════════════════════════════════════════════════════════════════════════════

func _build_engorge(duration: float) -> void:
	if _butcher_center == Vector2.ZERO:
		return
	var parent: Node = get_parent()
	if parent == null:
		return

	var flash := Sprite2D.new()
	flash.texture = TEX_ENGORGE
	flash.global_position = _butcher_center
	flash.z_index = 22
	flash.z_as_relative = false
	flash.modulate = COLOR_ENGORGE_TINT
	flash.modulate.a = 0.0
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = mat
	var tex_size: float = flash.texture.get_width()
	var start_scale: float = 140.0 / maxf(tex_size, 1.0)
	flash.scale = Vector2.ONE * start_scale * 0.5
	parent.add_child(flash)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2.ONE * start_scale * 1.25, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(flash, "modulate:a", 0.0, duration - 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(flash.queue_free)

	if _butcher_panel and is_instance_valid(_butcher_panel):
		_punch_butcher_panel(_butcher_panel)
		ScreenShakeEffect.shake(_butcher_panel, self, 6.0, 5)


func _punch_butcher_panel(panel: Control) -> void:
	var orig_mod: Color = panel.modulate
	var orig_scale: Vector2 = panel.scale
	panel.pivot_offset = panel.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate", COLOR_BUTCHER_FEED, 0.07)
	tw.tween_property(panel, "scale", orig_scale * 1.08, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(panel, "modulate", orig_mod, 0.22) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_property(panel, "scale", orig_scale, 0.20) \
		.set_trans(Tween.TRANS_SINE)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3 — Cleaver wave (open)
# ═════════════════════════════════════════════════════════════════════════════

func _build_wave(_duration: float) -> void:
	AudioManager.play_sfx(SFX_CLEAVER, -3.0)
	var scene: Node = get_parent()
	if scene == null:
		return

	var wave_pos: Vector2 = Vector2(
		_board_center.x - WAVE_WIDTH * 0.5,
		_board_center.y - WAVE_HEIGHT * 0.5
	)

	_wave_clip = Control.new()
	_wave_clip.clip_contents = true
	_wave_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_clip.position = wave_pos
	_wave_clip.set_size(Vector2(0.0, WAVE_HEIGHT))
	_wave_clip.z_index = 20
	_wave_clip.z_as_relative = false
	scene.add_child(_wave_clip)

	_wave_sprite = _make_additive_texture_rect(TEX_WAVE)
	_wave_sprite.set_size(Vector2(WAVE_WIDTH, WAVE_HEIGHT))
	_wave_sprite.position = Vector2.ZERO
	_wave_sprite.modulate = COLOR_WAVE_TINT
	_wave_clip.add_child(_wave_sprite)

	# Wave reveals over the FULL WAVE_DURATION (spans wave_open + wave_tail).
	var tw_open := create_tween()
	tw_open.tween_property(_wave_clip, "size:x", WAVE_WIDTH, WAVE_DURATION) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	_spawn_wave_distortion(scene)
	_spawn_gore_chunks(scene)


# Listener fired at end of wave_open phase (impact moment).
func _on_wave_arrived() -> void:
	var scene: Node = get_parent()
	if scene == null:
		return
	_spawn_target_impacts(scene)
	if _enemy_board and is_instance_valid(_enemy_board):
		ScreenShakeEffect.shake(_enemy_board, self, 14.0, 10)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 5 — Settle (wave fades)
# ═════════════════════════════════════════════════════════════════════════════

func _build_settle(duration: float) -> void:
	if not is_instance_valid(_wave_sprite):
		return
	var tw_fade := create_tween().set_parallel(true)
	tw_fade.tween_property(_wave_sprite, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw_fade.tween_callback(func() -> void:
		if is_instance_valid(_wave_clip):
			_wave_clip.queue_free()
		if is_instance_valid(_fx_layer):
			_fx_layer.queue_free())


# ═════════════════════════════════════════════════════════════════════════════
# Helpers (distortion, gore, impacts, additive rect)
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_wave_distortion(parent: Node) -> void:
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 2
	parent.add_child(_fx_layer)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var strip_height: float = WAVE_HEIGHT * 2.2
	var strip_top: float = _board_center.y - strip_height * 0.5
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.position = Vector2(0.0, strip_top)
	rect.set_size(Vector2(vp.x, strip_height))

	var mat := ShaderMaterial.new()
	mat.shader = SHADER_CRESCENT_SHOCK
	mat.set_shader_parameter("head_reach", 0.10)
	mat.set_shader_parameter("band_thickness", 0.12)
	mat.set_shader_parameter("strength", 0.022)
	mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	mat.set_shader_parameter("tint", COLOR_WAVE_DISTORT)
	mat.set_shader_parameter("alpha_multiplier", 1.0)
	rect.material = mat
	_fx_layer.add_child(rect)

	var board_y_uv: float = clampf(_board_center.y / maxf(vp.y, 1.0), 0.0, 1.0)
	var start_x: float = (_board_center.x - WAVE_WIDTH * 0.5) / maxf(vp.x, 1.0)
	var end_x: float = (_board_center.x + WAVE_WIDTH * 0.5) / maxf(vp.x, 1.0)
	mat.set_shader_parameter("head_uv", Vector2(start_x, board_y_uv))

	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(mat):
			var cx: float = lerpf(start_x, end_x, t)
			mat.set_shader_parameter("head_uv", Vector2(cx, board_y_uv)),
		0.0, 1.0, WAVE_DURATION) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _spawn_gore_chunks(parent: Node) -> void:
	var emit_count: int = 40
	var dir_sign: float = 1.0
	for i in emit_count:
		var t: float = float(i) / float(emit_count - 1)
		var x_offset: float = (t - 0.5) * WAVE_WIDTH * 0.9
		x_offset += randf_range(-35.0, 35.0)
		var y_jitter: float = randf_range(-55.0, 55.0)
		var spawn_pos: Vector2 = Vector2(_board_center.x + x_offset, _board_center.y + y_jitter)
		var delay: float = t * WAVE_DURATION * 0.85 + randf_range(-0.03, 0.03)
		_spawn_single_chunk(parent, spawn_pos, dir_sign, maxf(delay, 0.0))


func _spawn_single_chunk(parent: Node, pos: Vector2, dir_sign: float,
		delay: float) -> void:
	var tex: Texture2D = _chunk_variants[randi() % _chunk_variants.size()]
	var chunk := Sprite2D.new()
	chunk.texture = tex
	chunk.global_position = pos
	chunk.z_index = 22
	chunk.z_as_relative = false
	chunk.modulate = Color(1.0, 0.8, 0.85, 0.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	chunk.material = mat
	var tex_w: float = tex.get_width()
	var base_scale: float = randf_range(0.12, 0.22) * (120.0 / maxf(tex_w, 1.0))
	chunk.scale = Vector2.ONE * base_scale
	chunk.rotation = randf_range(-PI, PI)
	parent.add_child(chunk)

	var travel: Vector2 = Vector2(
		randf_range(50.0, 120.0) * dir_sign,
		randf_range(-60.0, 40.0)
	)
	var gravity: Vector2 = Vector2(0, randf_range(160.0, 260.0))
	var lifetime: float = randf_range(0.35, 0.60)

	var tw := create_tween().set_parallel(true)
	tw.tween_interval(delay)
	tw.chain()
	tw.tween_property(chunk, "modulate:a", 1.0, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(chunk, "rotation",
			chunk.rotation + randf_range(-3.0, 3.0), lifetime) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(p: float) -> void:
		if is_instance_valid(chunk):
			chunk.global_position = pos + travel * p + gravity * p * p * 0.5,
		0.0, 1.0, lifetime).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(chunk, "modulate:a", 0.0, 0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(chunk.queue_free)


func _spawn_target_impacts(parent: Node) -> void:
	for slot in _target_slots:
		if not is_instance_valid(slot):
			continue
		var s: Control = slot as Control
		var center: Vector2 = s.global_position + s.size * 0.5

		var flash := Sprite2D.new()
		flash.texture = TEX_ENGORGE
		flash.global_position = center
		flash.modulate = COLOR_IMPACT_FLASH
		flash.z_index = 23
		flash.z_as_relative = false
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		flash.material = mat
		var tex_size: float = flash.texture.get_width()
		var start_scale: float = 60.0 / maxf(tex_size, 1.0)
		flash.scale = Vector2.ONE * start_scale * 0.6
		parent.add_child(flash)

		var tw := create_tween().set_parallel(true)
		tw.tween_property(flash, "scale", Vector2.ONE * start_scale * 1.3, 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(flash, "modulate:a", 0.0, 0.28) \
			.set_delay(0.05).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_callback(flash.queue_free)

		var orig_mod: Color = s.modulate
		var stw := s.create_tween()
		stw.tween_property(s, "modulate", Color(1.8, 0.6, 0.8, 1.0), 0.05)
		stw.tween_property(s, "modulate", orig_mod, 0.22)


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
