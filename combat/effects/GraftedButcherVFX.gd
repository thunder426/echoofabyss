## GraftedButcherVFX.gd
## ON PLAY VFX for Grafted Butcher — the Butcher feasts on a friendly
## sacrifice, engorges, then unleashes a crimson cleaver wave across the
## enemy board dealing 200 AoE.
##
## Phases (~1.35s):
##   1. Graft tether (0.00-0.35s):
##       • Jagged sinew-and-violet-lightning tendril anchors at the sacrifice
##         slot, tapered end aimed at the Butcher. Quick crimson pulse travels
##         along it as it retracts.
##   2. Engorge flash (0.25-0.55s, overlaps):
##       • Radial crimson-violet burst on the Butcher, white-hot core.
##       • Butcher panel scale-punch + brief red tint — "he's feeding."
##       • Mild screen shake.
##   3. Cleaver wave (0.55-1.10s):
##       • Meat-cleaver crescent reveals left-to-right across the enemy board
##         via a clip container. sonic_wave shader distortion band travels
##         with the wave. Gore chunks (3 variants) spray from the leading
##         edge.
##       • impact_hit emits at the wave's peak — caller applies 200 damage
##         to each enemy minion synced with per-target crimson flashes +
##         heavy board shake.
##   4. Settle (1.10-1.35s):
##       • Wave fades, residual gore falls under gravity.
##
## Usage:
##   var vfx := GraftedButcherVFX.create(butcher_panel, sac_center,
##           enemy_board, enemy_slots)
##   vfx_controller.spawn(vfx)
##   await vfx.impact_hit   # apply damage here
##   await vfx.finished
class_name GraftedButcherVFX
extends Node

signal finished
signal impact_hit  ## Emitted at cleaver wave peak — sync AoE damage here.

const TEX_WAVE: Texture2D    = preload("res://assets/art/fx/meat_cleaver_wave.png")
const TEX_TENDRIL: Texture2D = preload("res://assets/art/fx/flesh_graft_tendril.png")
const TEX_ENGORGE: Texture2D = preload("res://assets/art/fx/butcher_engorge_glow.png")
const TEX_CHUNK_1: Texture2D = preload("res://assets/art/fx/flesh_chunk_1.png")
const TEX_CHUNK_2: Texture2D = preload("res://assets/art/fx/flesh_chunk_2.png")
const TEX_CHUNK_3: Texture2D = preload("res://assets/art/fx/flesh_chunk_3.png")

const SHADER_CRESCENT_SHOCK: Shader = preload("res://combat/effects/crescent_shockwave.gdshader")

const SFX_GRAFT: String   = "res://assets/audio/sfx/minions/grafted_butcher_graft.wav"
const SFX_CLEAVER: String = "res://assets/audio/sfx/minions/grafted_butcher_cleaver.wav"

# ── Colors ───────────────────────────────────────────────────────────────────
const COLOR_WAVE_TINT: Color    = Color(1.15, 0.55, 0.75, 1.0)  # brighten crimson/violet
const COLOR_ENGORGE_TINT: Color = Color(1.0, 0.85, 0.95, 1.0)
const COLOR_TENDRIL_TINT: Color = Color(1.0, 0.75, 0.90, 1.0)
const COLOR_IMPACT_FLASH: Color = Color(1.0, 0.35, 0.55, 0.95)
const COLOR_BUTCHER_FEED: Color = Color(1.6, 0.7, 1.1, 1.0)
const COLOR_WAVE_DISTORT: Color = Color(1.0, 0.25, 0.35, 0.14)

# ── Timing ───────────────────────────────────────────────────────────────────
const TENDRIL_DURATION: float = 0.70
const ENGORGE_DURATION: float = 0.60
const WAVE_DURATION: float    = 1.10
const SETTLE_DURATION: float  = 0.50

# ── Layout ───────────────────────────────────────────────────────────────────
const WAVE_WIDTH: float  = 960.0
const WAVE_HEIGHT: float = 270.0

var _butcher_panel: Control = null
var _sac_center: Vector2 = Vector2.ZERO
var _enemy_board: Control = null
var _target_slots: Array = []

var _fx_layer: CanvasLayer = null
var _wave_clip: Control = null
var _wave_sprite: TextureRect = null

static var _chunk_variants: Array[Texture2D] = []


static func create(butcher_panel: Control, sac_center: Vector2,
		enemy_board: Control, target_slots: Array) -> GraftedButcherVFX:
	var vfx := GraftedButcherVFX.new()
	vfx._butcher_panel = butcher_panel
	vfx._sac_center = sac_center
	vfx._enemy_board = enemy_board
	vfx._target_slots = target_slots
	return vfx


func _ready() -> void:
	if _chunk_variants.is_empty():
		_chunk_variants = [TEX_CHUNK_1, TEX_CHUNK_2, TEX_CHUNK_3]
	_run()


func _run() -> void:
	var scene: Node = get_parent()
	if scene == null or not is_inside_tree():
		impact_hit.emit()
		finished.emit()
		queue_free()
		return

	var butcher_center: Vector2 = Vector2.ZERO
	if _butcher_panel and is_instance_valid(_butcher_panel):
		butcher_center = _butcher_panel.global_position + _butcher_panel.size * 0.5

	# ═══ Phase 1: Graft tether ══════════════════════════════════════════════
	AudioManager.play_sfx(SFX_GRAFT, -6.0)
	if _sac_center != Vector2.ZERO and butcher_center != Vector2.ZERO:
		_spawn_graft_tendril(scene, _sac_center, butcher_center)

	await get_tree().create_timer(TENDRIL_DURATION * 0.7).timeout
	if not is_inside_tree():
		impact_hit.emit(); _cleanup(); return

	# ═══ Phase 2: Engorge flash on the Butcher ══════════════════════════════
	if butcher_center != Vector2.ZERO:
		_spawn_engorge_flash(scene, butcher_center)
	if _butcher_panel and is_instance_valid(_butcher_panel):
		_punch_butcher_panel(_butcher_panel)
		ScreenShakeEffect.shake(_butcher_panel, self, 6.0, 5)

	await get_tree().create_timer(ENGORGE_DURATION).timeout
	if not is_inside_tree():
		impact_hit.emit(); _cleanup(); return

	# ═══ Phase 3: Cleaver wave across enemy board ═══════════════════════════
	AudioManager.play_sfx(SFX_CLEAVER, -3.0)
	var board_center: Vector2
	if _enemy_board and is_instance_valid(_enemy_board):
		board_center = _enemy_board.global_position + _enemy_board.size * 0.5
	else:
		board_center = butcher_center

	var wave_pos: Vector2 = Vector2(
		board_center.x - WAVE_WIDTH * 0.5,
		board_center.y - WAVE_HEIGHT * 0.5
	)
	# Determine sweep direction — if butcher is to the left of the board,
	# sweep left→right, otherwise right→left (for enemy Seris future support).
	var sweep_left_to_right: bool = butcher_center.x <= board_center.x

	# Clip container reveals the wave left→right (same pattern as fissure VFX).
	# Clip grows from width 0 → WAVE_WIDTH; sprite inside stays at full size.
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

	var tw_open := create_tween()
	tw_open.tween_property(_wave_clip, "size:x", WAVE_WIDTH, WAVE_DURATION) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# Screen-space distortion travelling with the wave's leading edge
	_spawn_wave_distortion(scene, board_center, sweep_left_to_right)

	# Gore chunks spraying along the wave front
	_spawn_gore_chunks(scene, board_center, sweep_left_to_right)

	# Impact lands at ~60% of the wave sweep — the leading edge has reached
	# most of the board by then.
	await get_tree().create_timer(WAVE_DURATION * 0.60).timeout
	if not is_inside_tree():
		impact_hit.emit(); _cleanup(); return

	impact_hit.emit()
	_spawn_target_impacts(scene)
	if _enemy_board and is_instance_valid(_enemy_board):
		ScreenShakeEffect.shake(_enemy_board, self, 14.0, 10)

	var wave_remaining: float = WAVE_DURATION * 0.40
	await get_tree().create_timer(wave_remaining).timeout
	if not is_inside_tree():
		_cleanup(); return

	# ═══ Phase 4: Settle — wave fades ═══════════════════════════════════════
	var tw_fade := create_tween().set_parallel(true)
	if is_instance_valid(_wave_sprite):
		tw_fade.tween_property(_wave_sprite, "modulate:a", 0.0, SETTLE_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(SETTLE_DURATION).timeout
	_cleanup()


# ═════════════════════════════════════════════════════════════════════════════
# Phase 1 — Graft tendril
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_graft_tendril(parent: Node, from_pos: Vector2, to_pos: Vector2) -> void:
	var tex_w: float = TEX_TENDRIL.get_width()
	var tex_h: float = TEX_TENDRIL.get_height()
	var delta: Vector2 = to_pos - from_pos
	var distance: float = delta.length()
	if distance < 1.0 or tex_w < 1.0:
		return

	# Display height caps so a long tendril doesn't look like a huge slab.
	var display_h: float = clampf(distance * 0.20, 40.0, 100.0)

	# Rotating clip container — position at from_pos, rotated to aim at to_pos.
	# clip_contents clips its children to its own rect in local (pre-rotation)
	# space, so growing size.x from 0→distance reveals the tendril outward
	# from the sacrificed minion toward the Butcher.
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = from_pos
	clip.pivot_offset = Vector2(0.0, display_h * 0.5)
	clip.rotation = delta.angle()
	clip.set_size(Vector2(0.0, display_h))
	clip.z_index = 21
	clip.z_as_relative = false
	parent.add_child(clip)

	# Full-length tendril inside the clip. Offset Y so the tendril centers on
	# the clip's horizontal midline (matches the pivot_offset above).
	var tendril := _make_additive_texture_rect(TEX_TENDRIL)
	tendril.set_size(Vector2(distance, display_h))
	tendril.position = Vector2.ZERO
	tendril.modulate = COLOR_TENDRIL_TINT
	clip.add_child(tendril)

	# Reveal: clip width 0 → distance (same pattern as fissure / cleaver wave).
	var tw := create_tween()
	tw.tween_property(clip, "size:x", distance, TENDRIL_DURATION * 0.55) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Brief hold, then retract (fade out).
	tw.tween_interval(TENDRIL_DURATION * 0.15)
	tw.tween_property(clip, "modulate:a", 0.0, TENDRIL_DURATION * 0.30) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(clip.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2 — Engorge flash on the Butcher
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_engorge_flash(parent: Node, center: Vector2) -> void:
	var flash := Sprite2D.new()
	flash.texture = TEX_ENGORGE
	flash.global_position = center
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
	tw.chain().tween_property(flash, "modulate:a", 0.0, ENGORGE_DURATION - 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(flash.queue_free)


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
# Phase 3 — Wave distortion band (sonic_wave shader on a CanvasLayer)
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_wave_distortion(parent: Node, board_center: Vector2,
		_sweep_left_to_right: bool) -> void:
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 2
	parent.add_child(_fx_layer)

	# ColorRect spans the wave's Y-band plus vertical margin for the shock
	# bands emitted above/below the sweep line. Horizontal coverage is the
	# full viewport so shock bands can extend up and down freely.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var strip_height: float = WAVE_HEIGHT * 2.2  # room for above+below shock bands
	var strip_top: float = board_center.y - strip_height * 0.5
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.position = Vector2(0.0, strip_top)
	rect.set_size(Vector2(vp.x, strip_height))

	var mat := ShaderMaterial.new()
	mat.shader = SHADER_CRESCENT_SHOCK
	mat.set_shader_parameter("head_reach", 0.10)       # ~10% of screen width
	mat.set_shader_parameter("band_thickness", 0.12)   # ~12% of screen height
	mat.set_shader_parameter("strength", 0.022)
	mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	mat.set_shader_parameter("tint", COLOR_WAVE_DISTORT)
	mat.set_shader_parameter("alpha_multiplier", 1.0)
	rect.material = mat
	_fx_layer.add_child(rect)

	# Sweep the head along the wave's path. Wave reveals left→right from
	# wave_pos, so the leading edge travels board-left → board-right.
	var board_y_uv: float = clampf(board_center.y / maxf(vp.y, 1.0), 0.0, 1.0)
	var start_x: float = (board_center.x - WAVE_WIDTH * 0.5) / maxf(vp.x, 1.0)
	var end_x: float = (board_center.x + WAVE_WIDTH * 0.5) / maxf(vp.x, 1.0)
	mat.set_shader_parameter("head_uv", Vector2(start_x, board_y_uv))

	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(mat):
			var cx: float = lerpf(start_x, end_x, t)
			mat.set_shader_parameter("head_uv", Vector2(cx, board_y_uv)),
		0.0, 1.0, WAVE_DURATION) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3 — Gore chunks spraying along the wave front
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_gore_chunks(parent: Node, board_center: Vector2,
		sweep_left_to_right: bool) -> void:
	# Emit at staggered times across the sweep so chunks keep up with the wave.
	# The wave always reveals left→right, so chunks spawn and spray rightward.
	var emit_count: int = 40
	var dir_sign: float = 1.0
	for i in emit_count:
		var t: float = float(i) / float(emit_count - 1)
		# Spawn along the wave's leading edge as it sweeps, with horizontal
		# jitter so chunks don't queue up in a perfect line.
		var x_offset: float = (t - 0.5) * WAVE_WIDTH * 0.9
		x_offset += randf_range(-35.0, 35.0)
		var y_jitter: float = randf_range(-55.0, 55.0)
		var spawn_pos: Vector2 = Vector2(board_center.x + x_offset, board_center.y + y_jitter)
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
	# Two-phase motion: initial shove + gravity fall
	tw.tween_method(func(p: float) -> void:
		if is_instance_valid(chunk):
			chunk.global_position = pos + travel * p + gravity * p * p * 0.5,
		0.0, 1.0, lifetime).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(chunk, "modulate:a", 0.0, 0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(chunk.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3 — Per-target crimson flashes on each enemy minion
# ═════════════════════════════════════════════════════════════════════════════

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

		# Slot crimson tint
		var orig_mod: Color = s.modulate
		var stw := s.create_tween()
		stw.tween_property(s, "modulate", Color(1.8, 0.6, 0.8, 1.0), 0.05)
		stw.tween_property(s, "modulate", orig_mod, 0.22)


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
	if is_instance_valid(_wave_clip):
		_wave_clip.queue_free()  # also frees _wave_sprite (child)
	elif is_instance_valid(_wave_sprite):
		_wave_sprite.queue_free()
	if is_instance_valid(_fx_layer):
		_fx_layer.queue_free()
	finished.emit()
	queue_free()
