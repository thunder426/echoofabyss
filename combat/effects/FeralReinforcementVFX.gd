## FeralReinforcementVFX.gd
## Act 2 passive VFX — when a Human is summoned and Feral Reinforcement is
## active, a face-down card is added to the enemy hand. This VFX shows the
## moment of generation:
##   1. Radiant violet halo + scorch mark erupts from the summoned Human's slot
##   2. A face-down card arcs toward the enemy hero panel's hand indicator
##   3. Lands with a brief gold pulse on the enemy hand count label
##
## Phases:
##   1. ignite (0.50s) — origin halo fades up, surge mark scorches the slot
##   2. fly    (1.10s) — card back flies along an arc (start_pos → mid → end),
##                        scaling down + tilting; halos travel with it
##   3. land   (0.40s) — final fade + hand-indicator pulse; impact_hit fires
##                        at start (the "card landed" beat). Duration must
##                        outlast the longest internal tween (card_halo
##                        fade, 0.36s) — VfxSequence queue_frees the host
##                        when the phase ends, killing any tweens parented
##                        to it and leaving the card stuck on screen.
##
## Spawn via VfxController.spawn(); blocking via _on_play_vfx_active gate
## handled by the caller (CombatVFXBridge).
class_name FeralReinforcementVFX
extends BaseVfx

const TEX_SURGE: Texture2D = preload("res://assets/art/fx/feral_surge_mark.png")
const HALO_TINT: Color     = Color(0.90, 0.35, 1.00, 1.0)

const IGNITE_DURATION: float = 0.50
const FLY_DURATION: float    = 1.10
const LAND_DURATION: float   = 0.40
const FLY_ARC_HEIGHT: float  = 140.0   # mid-arc lift in pixels
const ORIGIN_HALO_SIZE: float = 320.0
const CARD_HALO_SIZE: float   = 280.0

# Caller passes the source slot, the enemy hero panel, and a UI root for the
# transient nodes (so they parent above board art but under HUD layers as
# the original bridge code did).
var _slot: BoardSlot = null
var _enemy_panel: Control = null
var _ui_root: Node = null
var _scene_ref: Node = null

var _start_pos: Vector2 = Vector2.ZERO
var _end_pos: Vector2 = Vector2.ZERO
var _mid_pos: Vector2 = Vector2.ZERO
var _card_back: Control = null
var _card_halo: TextureRect = null


static func create(slot: BoardSlot, enemy_panel: Control,
		ui_root: Node, scene: Node) -> FeralReinforcementVFX:
	var vfx := FeralReinforcementVFX.new()
	vfx._slot = slot
	vfx._enemy_panel = enemy_panel
	vfx._ui_root = ui_root
	vfx._scene_ref = scene
	vfx.impact_count = 0
	return vfx


func _play() -> void:
	if _slot == null or _enemy_panel == null or _ui_root == null:
		finished.emit()
		queue_free()
		return

	_start_pos = _slot.global_position + _slot.size * 0.5
	_end_pos   = _enemy_panel.global_position + _enemy_panel.size * 0.5
	_mid_pos   = _start_pos.lerp(_end_pos, 0.5)
	_mid_pos.y -= FLY_ARC_HEIGHT

	sequence().run([
		VfxPhase.new("ignite", IGNITE_DURATION, _build_ignite),
		VfxPhase.new("fly",    FLY_DURATION,    _build_fly),
		VfxPhase.new("land",   LAND_DURATION,   _build_land) \
			.emits_at_start(VfxSequence.RESERVED_IMPACT_HIT),
	])


# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: Origin halo + scorch mark
# ═════════════════════════════════════════════════════════════════════════════

func _build_ignite(_duration: float) -> void:
	# Origin halo — soft violet radial glow, fades up then back down. Lifetime
	# (0.36s rise + 1.10s decay) intentionally extends into the fly phase so
	# the source moment "lingers" as the card travels.
	var origin_halo := _make_radial_halo(ORIGIN_HALO_SIZE, HALO_TINT)
	origin_halo.position = _start_pos - origin_halo.size * 0.5
	origin_halo.z_index  = 17
	origin_halo.z_as_relative = false
	_ui_root.add_child(origin_halo)
	origin_halo.modulate.a = 0.0
	var oh_tw := create_tween().set_trans(Tween.TRANS_SINE)
	oh_tw.tween_property(origin_halo, "modulate:a", 0.85, 0.36).set_ease(Tween.EASE_OUT)
	oh_tw.tween_property(origin_halo, "modulate:a", 0.0, 1.10).set_ease(Tween.EASE_IN)
	oh_tw.tween_callback(origin_halo.queue_free)

	# Feral surge mark — brief scorch on the source slot. Lifetime tween runs
	# longer than the ignite phase (~1.5s total) and fades during the fly.
	var mark := TextureRect.new()
	mark.texture       = TEX_SURGE
	mark.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	mark.z_index       = 17
	mark.z_as_relative = false
	mark.modulate      = Color(1.0, 0.35, 0.45, 0.0)
	var mark_size := _slot.size * 0.9
	mark.size          = mark_size
	mark.position      = _slot.global_position + (_slot.size - mark_size) * 0.5
	mark.pivot_offset  = mark_size * 0.5
	mark.rotation      = randf_range(-0.25, 0.25)
	mark.scale         = Vector2(0.7, 0.7)
	_ui_root.add_child(mark)
	var mark_tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	mark_tw.tween_property(mark, "modulate:a", 0.7, 0.24).set_ease(Tween.EASE_OUT)
	mark_tw.tween_property(mark, "scale", Vector2(1.05, 1.05), 0.50).set_ease(Tween.EASE_OUT)
	mark_tw.chain()
	mark_tw.tween_property(mark, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN)
	mark_tw.tween_callback(mark.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2: Card arcs toward enemy hand
# ═════════════════════════════════════════════════════════════════════════════

func _build_fly(duration: float) -> void:
	# Face-down card construction (procedural panel with violet border + glyph).
	_card_back = _make_feral_card_back()
	_card_back.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_card_back.z_index        = 22
	_card_back.z_as_relative  = false
	_ui_root.add_child(_card_back)
	_card_back.pivot_offset   = _card_back.size * 0.5
	var start_scale := Vector2(0.55, 0.55)
	var end_scale   := Vector2(0.22, 0.22)
	_card_back.scale          = start_scale
	_card_back.modulate       = Color(1.0, 1.0, 1.0, 0.0)
	_card_back.position       = _start_pos - _card_back.size * 0.5

	# Travelling halo follows the card.
	_card_halo = _make_radial_halo(CARD_HALO_SIZE, HALO_TINT)
	_card_halo.z_index        = 21
	_card_halo.z_as_relative  = false
	_card_halo.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_card_halo.modulate.a     = 0.0
	_ui_root.add_child(_card_halo)
	_card_halo.scale = Vector2.ONE

	var card_back := _card_back
	var card_halo := _card_halo
	var start_pos := _start_pos
	var mid_pos   := _mid_pos
	var end_pos   := _end_pos

	var t := create_tween().set_parallel(true)
	t.tween_property(card_back, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(card_halo, "modulate:a", 0.75, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(card_back, "scale", end_scale, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(card_halo, "scale", Vector2(0.45, 0.45), duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Slight tilt during the first half, settle by mid-flight.
	t.tween_property(card_back, "rotation", randf_range(-0.35, 0.35), duration * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(card_back, "rotation", 0.0, duration * 0.5) \
		.set_delay(duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Quadratic Bézier arc: start → mid (peak) → end.
	var arc_callable := func(p: float) -> void:
		if not is_instance_valid(card_back): return
		var a: Vector2 = start_pos.lerp(mid_pos, p)
		var b: Vector2 = mid_pos.lerp(end_pos, p)
		var pt: Vector2 = a.lerp(b, p)
		card_back.position = pt - card_back.size * 0.5
		if is_instance_valid(card_halo):
			card_halo.position = pt - card_halo.size * 0.5
	t.tween_method(arc_callable, 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3: Final fade + hand-indicator pulse
# ═════════════════════════════════════════════════════════════════════════════

func _build_land(duration: float) -> void:
	if _card_back != null and is_instance_valid(_card_back):
		var ftw := create_tween().set_parallel(true)
		ftw.tween_property(_card_back, "modulate:a", 0.0, 0.30).set_ease(Tween.EASE_IN)
		if _card_halo != null and is_instance_valid(_card_halo):
			ftw.tween_property(_card_halo, "modulate:a", 0.0, 0.36).set_ease(Tween.EASE_IN)
		ftw.chain().tween_callback(func() -> void:
			if is_instance_valid(_card_back):
				_card_back.queue_free()
			if is_instance_valid(_card_halo):
				_card_halo.queue_free())

	# Hand-indicator pulse runs synchronously; it's a tween on the panel
	# itself so it persists past this VFX's queue_free.
	if _enemy_panel != null and is_instance_valid(_enemy_panel):
		_pulse_hand_indicator(_enemy_panel)


# ═════════════════════════════════════════════════════════════════════════════
# Helpers — extracted from CombatVFXBridge so they're self-contained here.
# (CombatVFXBridge keeps its copies for any future inline use; keeping them
# duplicated avoids cross-module coupling for these one-off procedural assets.)
# ═════════════════════════════════════════════════════════════════════════════

func _make_feral_card_back() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(160, 240)
	root.size = Vector2(160, 240)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color     = Color(0.08, 0.03, 0.10, 1.0)
	bg_style.border_color = Color(0.75, 0.25, 0.95, 1.0)
	bg_style.set_border_width_all(3)
	bg_style.set_corner_radius_all(8)
	bg_style.shadow_color = Color(0.60, 0.20, 0.90, 0.55)
	bg_style.shadow_size  = 10
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var inner := Panel.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 8; inner.offset_right = -8
	inner.offset_top  = 8; inner.offset_bottom = -8
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color     = Color(0.14, 0.05, 0.18, 1.0)
	inner_style.border_color = Color(0.45, 0.15, 0.60, 0.9)
	inner_style.set_border_width_all(1)
	inner_style.set_corner_radius_all(5)
	inner.add_theme_stylebox_override("panel", inner_style)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(inner)

	var glyph := Label.new()
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.text = "✦"
	glyph.add_theme_font_size_override("font_size", 96)
	glyph.add_theme_color_override("font_color", Color(0.95, 0.65, 1.0, 1.0))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(glyph)
	return root


func _make_radial_halo(diameter: float, tint: Color) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture        = _get_radial_halo_texture()
	tr.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode   = TextureRect.STRETCH_SCALE
	tr.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	tr.size           = Vector2(diameter, diameter)
	tr.pivot_offset   = tr.size * 0.5
	tr.modulate       = tint
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tr.material       = mat
	return tr


static var _radial_halo_tex: ImageTexture = null

static func _get_radial_halo_texture() -> ImageTexture:
	if _radial_halo_tex != null:
		return _radial_halo_tex
	const SIZE := 256
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre: float = float(SIZE) * 0.5
	for y in SIZE:
		for x in SIZE:
			var dx: float = (float(x) - centre) / centre
			var dy: float = (float(y) - centre) / centre
			var r: float  = sqrt(dx * dx + dy * dy)
			var a: float  = clampf(1.0 - r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)  # smoothstep
			a = a * a  # bias toward bright-centre / soft-outer
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_radial_halo_tex = ImageTexture.create_from_image(img)
	return _radial_halo_tex


func _pulse_hand_indicator(panel: Control) -> void:
	panel.pivot_offset = panel.size * 0.5
	var tw := panel.create_tween().set_trans(Tween.TRANS_BACK)
	tw.tween_property(panel, "modulate", Color(1.6, 1.3, 0.6, 1.0), 0.10).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate", Color.WHITE, 0.35).set_ease(Tween.EASE_IN_OUT)
