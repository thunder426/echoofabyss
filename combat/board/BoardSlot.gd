## BoardSlot.gd
## Represents one of the 5 board slots on either side.
## Empty slots show the plain Panel style.
## Occupied slots use the abyss_battlefield_minion.png frame with Cinzel Bold labels.
##
## Render order (bottom → top):
##   _art_rect   — minion art sits behind the frame window
##   _frame_rect — frame PNG overlays the art
##   _overlay    — semi-transparent highlight tint
##   labels      — cost / name / atk / hp / status bar (HBoxContainer of icons)
class_name BoardSlot
extends Panel

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal slot_clicked_empty(slot: BoardSlot)
signal slot_clicked_occupied(slot: BoardSlot, minion: MinionInstance)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var slot_owner: String = "player"
var index: int = 0
var minion: MinionInstance = null

# ---------------------------------------------------------------------------
# Highlight
# ---------------------------------------------------------------------------

enum HighlightMode { NONE, VALID_TARGET, SELECTED, INVALID }
var _highlight_mode: HighlightMode = HighlightMode.NONE

# ===========================================================================
# BATTLEFIELD TEXT CONFIG  (slot is 180 × 195 px)
# Tweak pos / size / font_size here to align labels with the frame artwork.
# "art" has no font_size — it is a TextureRect, not a label.
# ===========================================================================
# fmt: off
const _CFG: Dictionary = {
	# Minion art window — sits BEHIND the frame PNG
	"art":    { "pos": Vector2( 14,  26), "size": Vector2(152, 116) },

	# Essence cost — top-left gem (single and dual cost minions)
	"cost":      { "pos": Vector2(  1,  7), "size": Vector2( 30,  24), "font_size": 12 },
	# Mana cost — top-right gem (dual cost minions only)
	"mana_cost": { "pos": Vector2(148,  7), "size": Vector2( 30,  24), "font_size": 12 },

	# Card name — centered across full card width; long names drop to font_size_long
	"name":   { "pos": Vector2(  0,   4), "size": Vector2(179,  14), "font_size": 10, "font_size_long": 8, "long_threshold": 13 },

	# ATK  — bottom-left
	"atk":    { "pos": Vector2(  28, 165), "size": Vector2( 52,  30), "font_size": 12 },

	# Status bar — bottom-center, full inner width so HBoxContainer can center icons
	"status": { "pos": Vector2( 14, 144), "size": Vector2(152,  24) },

	# HP  — bottom-right  (shows "+shield" suffix when active)
	"hp":     { "pos": Vector2(105, 165), "size": Vector2( 52,  30), "font_size": 12 },
}
# fmt: on

const SLOT_W := 180
const SLOT_H := 195
const _STATUS_ICON_SIZE := 18
const _STATUS_FONT_SIZE := 9

# ---------------------------------------------------------------------------
# Visual nodes
# ---------------------------------------------------------------------------

var _frame_rect:  TextureRect
var _art_rect:    TextureRect
var _overlay:     ColorRect
var _cost_label:      Label
var _mana_cost_label: Label
var _name_label:      Label
var _atk_label:   Label
var _hp_label:    Label
var _status_bar:  HBoxContainer

var _bold_font: Font

# Empty-slot panel styles (same coloured-border look as before)
var _style_normal:   StyleBoxFlat
var _style_valid:    StyleBoxFlat
var _style_selected: StyleBoxFlat
var _style_invalid:  StyleBoxFlat

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_bold_font = load("res://assets/fonts/cinzel/Cinzel-Bold.ttf") \
		if ResourceLoader.exists("res://assets/fonts/cinzel/Cinzel-Bold.ttf") else null
	_build_styles()
	_build_visuals()
	gui_input.connect(_on_gui_input)
	_refresh_visuals()

# ---------------------------------------------------------------------------
# Empty-slot Panel styles (coloured border, dark bg)
# ---------------------------------------------------------------------------

func _build_styles() -> void:
	_style_normal   = _make_style(Color(0.10, 0.10, 0.18, 1), Color(0.25, 0.25, 0.40, 1))
	_style_valid    = _make_style(Color(0.08, 0.18, 0.10, 1), Color(0.20, 0.70, 0.25, 1))
	_style_selected = _make_style(Color(0.20, 0.18, 0.05, 1), Color(0.85, 0.75, 0.10, 1))
	_style_invalid  = _make_style(Color(0.18, 0.06, 0.06, 1), Color(0.70, 0.15, 0.15, 1))

func _make_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left   = 2; s.border_width_top    = 2
	s.border_width_right  = 2; s.border_width_bottom = 2
	s.border_color = border
	s.corner_radius_top_left    = 8; s.corner_radius_top_right   = 8
	s.corner_radius_bottom_right = 8; s.corner_radius_bottom_left = 8
	return s

# ---------------------------------------------------------------------------
# Build visual nodes
# ---------------------------------------------------------------------------

func _build_visuals() -> void:
	# --- Minion art (added FIRST = bottom layer, sits behind the frame) ---
	_art_rect = TextureRect.new()
	_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art_rect.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_art_rect.position     = _CFG["art"]["pos"]
	_art_rect.size         = _CFG["art"]["size"]
	_art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_rect.visible      = false
	add_child(_art_rect)

	# --- Frame PNG (added SECOND = overlays the art) ---
	_frame_rect = TextureRect.new()
	if ResourceLoader.exists("res://assets/art/frames/abyss_order/abyss_battlefield_minion.png"):
		_frame_rect.texture = load("res://assets/art/frames/abyss_order/abyss_battlefield_minion.png")
	_frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_frame_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_frame_rect.position     = Vector2.ZERO
	_frame_rect.size         = Vector2(SLOT_W, SLOT_H)
	_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_rect.visible      = false
	add_child(_frame_rect)

	# --- Highlight overlay ---
	_overlay = ColorRect.new()
	_overlay.position     = Vector2.ZERO
	_overlay.size         = Vector2(SLOT_W, SLOT_H)
	_overlay.color        = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	# --- Labels (hidden until occupied) ---
	_cost_label      = _make_label("cost",      Color(1.00, 0.85, 0.30, 1), HORIZONTAL_ALIGNMENT_CENTER, true)
	_mana_cost_label = _make_label("mana_cost", Color(0.40, 0.75, 1.00, 1), HORIZONTAL_ALIGNMENT_CENTER, true)
	_name_label      = _make_label("name",      Color(1.00, 1.00, 1.00, 1), HORIZONTAL_ALIGNMENT_CENTER, true)
	_atk_label  = _make_label("atk",  Color(1.00, 0.75, 0.25, 1), HORIZONTAL_ALIGNMENT_CENTER, true)
	_hp_label   = _make_label("hp",   Color(0.35, 1.00, 0.50, 1), HORIZONTAL_ALIGNMENT_CENTER, true)

	# --- Status bar (HBoxContainer — rebuilt each refresh) ---
	_status_bar = HBoxContainer.new()
	_status_bar.position = _CFG["status"]["pos"]
	_status_bar.size     = _CFG["status"]["size"]
	_status_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_bar.add_theme_constant_override("separation", 4)
	_status_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_bar.visible      = false
	add_child(_status_bar)

func _make_label(cfg_key: String, color: Color,
		align: HorizontalAlignment, use_bold: bool) -> Label:
	var cfg: Dictionary = _CFG[cfg_key]
	var lbl := Label.new()
	lbl.position = cfg["pos"]
	lbl.size     = cfg["size"]
	lbl.add_theme_font_size_override("font_size", cfg["font_size"])
	lbl.horizontal_alignment = align
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	lbl.clip_text    = false
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.visible      = false
	if use_bold and _bold_font:
		lbl.add_theme_font_override("font", _bold_font)
	add_child(lbl)
	return lbl

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_empty():
			slot_clicked_empty.emit(self)
		else:
			slot_clicked_occupied.emit(self, minion)

# ---------------------------------------------------------------------------
# Minion placement
# ---------------------------------------------------------------------------

func is_empty() -> bool:
	return minion == null

func place_minion(m: MinionInstance) -> void:
	minion = m
	minion.slot_index = index
	_refresh_visuals()

func remove_minion() -> void:
	minion = null
	_refresh_visuals()

# ---------------------------------------------------------------------------
# Highlight
# ---------------------------------------------------------------------------

func set_highlight(mode: HighlightMode) -> void:
	_highlight_mode = mode
	_refresh_visuals()

func clear_highlight() -> void:
	set_highlight(HighlightMode.NONE)

# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------

func _refresh_visuals() -> void:
	if _overlay == null:
		return

	if minion == null:
		_show_empty_state()
	else:
		_show_occupied_state()

func _show_empty_state() -> void:
	match _highlight_mode:
		HighlightMode.VALID_TARGET: add_theme_stylebox_override("panel", _style_valid)
		HighlightMode.SELECTED:     add_theme_stylebox_override("panel", _style_selected)
		HighlightMode.INVALID:      add_theme_stylebox_override("panel", _style_invalid)
		_:                          add_theme_stylebox_override("panel", _style_normal)
	_overlay.color      = Color(0, 0, 0, 0)
	_frame_rect.visible = false
	_art_rect.visible   = false
	_set_labels_visible(false)

func _show_occupied_state() -> void:
	# Transparent Panel background — frame PNG takes over
	var blank := StyleBoxFlat.new()
	blank.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", blank)

	# Highlight overlay tint
	match _highlight_mode:
		HighlightMode.VALID_TARGET: _overlay.color = Color(0.15, 0.80, 0.25, 0.28)
		HighlightMode.SELECTED:     _overlay.color = Color(0.90, 0.80, 0.10, 0.32)
		HighlightMode.INVALID:      _overlay.color = Color(0.80, 0.10, 0.10, 0.28)
		_:                          _overlay.color = Color(0, 0, 0, 0)

	_frame_rect.visible = true
	# Swap frame for dual-cost minions
	var _md_check := minion.card_data as MinionCardData
	var _is_dual  := _md_check != null and _md_check.mana_cost > 0
	var _frame_path := "res://assets/art/frames/abyss_order/abyss_dual_battlefield_minion.png" \
		if _is_dual else "res://assets/art/frames/abyss_order/abyss_battlefield_minion.png"
	if ResourceLoader.exists(_frame_path):
		_frame_rect.texture = load(_frame_path)
	_set_labels_visible(true)

	# Art — prefer battlefield_art_path when set, fall back to art_path
	_art_rect.visible = true
	var art_path := minion.card_data.battlefield_art_path
	if art_path == "":
		art_path = minion.card_data.art_path
	if art_path != "":
		var tex := load(art_path) as Texture2D
		_art_rect.texture = tex if tex else null
	else:
		_art_rect.texture = null

	# Cost — essence always top-left; mana top-right for dual-cost minions only
	var md := minion.card_data as MinionCardData
	if md:
		_cost_label.text      = str(md.essence_cost)
		_mana_cost_label.text = str(md.mana_cost) if md.mana_cost > 0 else ""
		_mana_cost_label.visible = md.mana_cost > 0
	else:
		_cost_label.text         = ""
		_mana_cost_label.text    = ""
		_mana_cost_label.visible = false

	# Name — smaller font for long names
	var _card_name := minion.card_data.card_name
	_name_label.text = _card_name
	var _name_cfg := _CFG["name"]
	var _name_fs: int = _name_cfg["font_size_long"] \
		if _card_name.length() >= _name_cfg["long_threshold"] \
		else _name_cfg["font_size"]
	_name_label.add_theme_font_size_override("font_size", _name_fs)

	# ATK — tinted darker when corrupted
	var corruption_total := BuffSystem.sum_type(minion, Enums.BuffType.CORRUPTION)
	_atk_label.text = str(minion.effective_atk())
	_atk_label.add_theme_color_override("font_color",
		Color(0.70, 0.45, 0.10, 1) if corruption_total > 0 else Color(1.00, 0.75, 0.25, 1))

	# HP — always green; blue tint when shield active
	var hp_text := str(minion.current_health)
	if minion.has_shield() and minion.current_shield > 0:
		hp_text += "+%d" % minion.current_shield
		_hp_label.add_theme_color_override("font_color", Color(0.40, 0.85, 1.00, 1))
	else:
		_hp_label.add_theme_color_override("font_color", Color(0.35, 1.00, 0.50, 1))
	_hp_label.text = hp_text

	# Status bar — clear and rebuild each refresh
	for child in _status_bar.get_children():
		child.queue_free()

	if minion.has_guard():
		_status_bar_add_icon("icon_guard.png")
	if minion.has_deathless():
		_status_bar_add_icon("icon_deathless.png")
	if corruption_total > 0:
		_status_bar_add_icon("icon_corruption.png")
		_status_bar_add_count("x%d" % (corruption_total / 100), Color(0.85, 0.55, 1.00, 1))
	if minion.owner == "player" and minion.can_attack():
		_status_bar_add_icon("icon_ready.png")
	elif minion.owner == "player" and minion.state == Enums.MinionState.EXHAUSTED:
		_status_bar_add_icon("icon_tired.png")

	_status_bar.visible = _status_bar.get_child_count() > 0

func _set_labels_visible(v: bool) -> void:
	_cost_label.visible = v
	if not v:
		_mana_cost_label.visible = false  # shown per-minion only when dual-cost
	_name_label.visible = v
	_atk_label.visible  = v
	_hp_label.visible   = v
	if not v:
		_status_bar.visible = false

# ---------------------------------------------------------------------------
# Status bar helpers
# ---------------------------------------------------------------------------

func _status_bar_add_icon(filename: String) -> void:
	var tex := _load_icon(filename)
	if tex == null:
		return
	var rect := TextureRect.new()
	rect.texture      = tex
	rect.custom_minimum_size = Vector2(_STATUS_ICON_SIZE, _STATUS_ICON_SIZE)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_bar.add_child(rect)

func _status_bar_add_count(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", _STATUS_FONT_SIZE)
	lbl.add_theme_color_override("font_color", color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _bold_font:
		lbl.add_theme_font_override("font", _bold_font)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_bar.add_child(lbl)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const _ICON_DIR := "res://assets/art/icons/"

func _load_icon(filename: String) -> Texture2D:
	var path := _ICON_DIR + filename
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
