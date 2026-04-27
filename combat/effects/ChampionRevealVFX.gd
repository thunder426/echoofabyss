## ChampionRevealVFX.gd
## Champion summon entrance reveal — large card preview with a "★ CHAMPION ★"
## banner sliding in below it. Held long enough to read, then fades out.
##
## Phases:
##   1. fade_in  (0.40s) — card + banner + title + name fade in together
##   2. hold     (2.80s) — read window
##   3. fade_out (0.35s) — both fade out together
##
## Spawn via VfxController.spawn(); caller awaits `finished` to know when the
## reveal is complete (then places the minion on the slot).
##
## Note: this is pure visual — placement, logging, and trigger firing are the
## caller's responsibility (see CombatVFXBridge.champion_summon_sequence).
class_name ChampionRevealVFX
extends BaseVfx

const FADE_IN_DURATION: float  = 0.40   # rounded up from the 0.30/0.35/0.40 stagger
const HOLD_DURATION: float     = 2.80
const FADE_OUT_DURATION: float = 0.35

var _card: CardData = null
var _ui_root: Node = null
var _visual: CardVisual = null
var _banner: ColorRect = null
var _title: Label = null
var _name_lbl: Label = null


static func create(card: CardData, ui_root: Node) -> ChampionRevealVFX:
	var vfx := ChampionRevealVFX.new()
	vfx._card = card
	vfx._ui_root = ui_root
	vfx.impact_count = 0
	return vfx


func _play() -> void:
	if _card == null or _ui_root == null:
		finished.emit()
		queue_free()
		return

	sequence().run([
		VfxPhase.new("fade_in",  FADE_IN_DURATION,  _build_fade_in),
		VfxPhase.new("hold",     HOLD_DURATION,     Callable()),
		VfxPhase.new("fade_out", FADE_OUT_DURATION, _build_fade_out),
	])


# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: Build card + banner + labels, animate them in
# ═════════════════════════════════════════════════════════════════════════════

func _build_fade_in(_duration: float) -> void:
	var vp := get_viewport().get_visible_rect().size

	# Card visual — top-anchored so the banner sits below.
	_visual = preload("res://combat/ui/CardVisual.tscn").instantiate()
	_visual.apply_size_mode("combat_preview")
	_visual.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_visual.z_index       = 20
	_visual.z_as_relative = false
	_visual.modulate      = Color(0, 0, 0, 0)
	_ui_root.add_child(_visual)
	_visual.setup(_card)
	var card_top_y: float = max(60.0, vp.y * 0.08)
	_visual.position = Vector2(vp.x / 2.0 - _visual.size.x / 2.0, card_top_y)

	# Banner background.
	var banner_y: float = card_top_y + _visual.size.y + 30.0
	_banner = ColorRect.new()
	_banner.color = Color(0.0, 0.0, 0.0, 0.0)
	_banner.set_size(Vector2(vp.x, 80))
	_banner.position = Vector2(0, banner_y)
	_banner.z_index = 25
	_banner.z_as_relative = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_banner)

	# Title — "★ CHAMPION ★"
	_title = Label.new()
	_title.text = "★  C H A M P I O N  ★"
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25, 0.0))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.position = Vector2(-200, 8)
	_title.set_size(Vector2(400, 30))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_title)

	# Card name subtitle.
	_name_lbl = Label.new()
	_name_lbl.text = _card.card_name
	_name_lbl.add_theme_font_size_override("font_size", 16)
	_name_lbl.add_theme_color_override("font_color", Color(0.90, 0.75, 0.50, 0.0))
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_name_lbl.position = Vector2(-200, 42)
	_name_lbl.set_size(Vector2(400, 25))
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_name_lbl)

	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_visual, "modulate", Color(1.2, 1.05, 0.75, 1.0), 0.3)
	t.tween_property(_banner, "color:a", 0.75, 0.3)
	t.tween_property(_title, "theme_override_colors/font_color:a", 1.0, 0.35)
	t.tween_property(_name_lbl, "theme_override_colors/font_color:a", 1.0, 0.4)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3: Fade out together, then the sequence runner queue_frees us
# (which also frees the children we added to _ui_root via tween_callback).
# ═════════════════════════════════════════════════════════════════════════════

func _build_fade_out(duration: float) -> void:
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if _visual != null and is_instance_valid(_visual):
		t.tween_property(_visual, "modulate:a", 0.0, duration)
	if _banner != null and is_instance_valid(_banner):
		t.tween_property(_banner, "modulate:a", 0.0, duration)
	t.chain().tween_callback(_cleanup)


func _cleanup() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
