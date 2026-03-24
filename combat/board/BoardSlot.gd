## BoardSlot.gd
## Represents one of the 5 board slots on either side.
## Empty slots show the plain Panel style.
## Occupied slots use the abyss_battlefield_minion.png frame with Cinzel Bold labels.
## Abyss-order non-shielded minions use abyss_battlefield_minion_generic.png:
##   no cost badge, no name bar — big art + status bar + ATK + HP only.
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
var _pulse_tween: Tween = null
var _pulse_t: float = 0.0

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
	"atk":    { "pos": Vector2(  28, 164), "size": Vector2( 52,  30), "font_size": 12 },

	# Status bar — bottom-center, full inner width so HBoxContainer can center icons
	"status": { "pos": Vector2( 14, 142), "size": Vector2(152,  24) },

	# HP  — bottom-right  (shows "+shield" suffix when active)
	"hp":     { "pos": Vector2(105, 164), "size": Vector2( 52,  30), "font_size": 12 },
}

# Generic frame layout (abyss_battlefield_minion_generic.png):
# No cost badge, no name bar — art fills the top portion of the slot.
const _CFG_GENERIC: Dictionary = {
	# Art window — larger, starts from near top edge
	"art":    { "pos": Vector2(  4,   4), "size": Vector2(172, 140) },

	# ATK  — bottom-left (same as normal)
	"atk":    { "pos": Vector2( 28, 163), "size": Vector2( 52,  30), "font_size": 12 },

	# Status bar — bottom-center (same as normal)
	"status": { "pos": Vector2( 14, 137), "size": Vector2(152,  23) },

	# HP  — bottom-right (same as normal)
	"hp":     { "pos": Vector2(105, 163), "size": Vector2( 52,  30), "font_size": 12 },
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
var _overlay:     Panel   # Border-glow highlight (transparent bg, coloured border + shadow)
var _cost_label:      Label
var _mana_cost_label: Label
var _name_label:      Label
var _atk_label:   Label
var _hp_label:    Label
var _status_bar:  HBoxContainer

var _bold_font: Font

var _is_hovered:    bool = false
var freeze_visuals: bool = false   # Set true during lunge to prevent empty-state flash

# Status bar tooltip
var _status_tooltip: Panel = null
var _using_generic:  bool = false

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_bold_font = load("res://assets/fonts/cinzel/Cinzel-Bold.ttf") \
		if ResourceLoader.exists("res://assets/fonts/cinzel/Cinzel-Bold.ttf") else null
	_build_styles()
	_build_visuals()
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_refresh_visuals()

# ---------------------------------------------------------------------------
# Empty-slot Panel styles (coloured border, dark bg)
# ---------------------------------------------------------------------------

func _build_styles() -> void:
	pass  # All highlight is handled via _overlay glow — no filled styles needed

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

	# --- Highlight overlay (border-glow panel, expands 4px outside slot to prevent shadow bleed) ---
	_overlay = Panel.new()
	_overlay.position     = Vector2(-4, -4)
	_overlay.size         = Vector2(SLOT_W + 8, SLOT_H + 8)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _blank := StyleBoxFlat.new()
	_blank.bg_color = Color(0, 0, 0, 0)
	_blank.draw_center = false
	_overlay.add_theme_stylebox_override("panel", _blank)
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
	_status_bar.mouse_filter = Control.MOUSE_FILTER_PASS
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

func _on_mouse_entered() -> void:
	_is_hovered = true
	if _highlight_mode == HighlightMode.VALID_TARGET:
		_start_pulse()
	elif _highlight_mode != HighlightMode.NONE:
		_refresh_visuals()

func _on_mouse_exited() -> void:
	_is_hovered = false
	_stop_pulse()
	if _highlight_mode != HighlightMode.NONE:
		_refresh_visuals()

func _start_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_method(func(v: float) -> void:
		_pulse_t = v
		_refresh_visuals(), 0.0, 1.0, 0.5)
	_pulse_tween.tween_method(func(v: float) -> void:
		_pulse_t = v
		_refresh_visuals(), 1.0, 0.0, 0.5)

func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	_pulse_t = 0.0

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
	if mode != HighlightMode.VALID_TARGET:
		_stop_pulse()
	_highlight_mode = mode
	_refresh_visuals()

func clear_highlight() -> void:
	set_highlight(HighlightMode.NONE)

# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------

func _refresh_visuals() -> void:
	if _overlay == null or freeze_visuals:
		return

	if minion == null:
		_show_empty_state()
	else:
		_show_occupied_state()

const _ABYSS_HEROES     := ["lord_vael"]
const _ABYSS_EMPTY_SLOT := "res://assets/art/frames/abyss_order/abyss_empty_slot.png"

func _show_empty_state() -> void:
	# Always transparent panel bg — highlight is purely a border glow
	var blank := StyleBoxFlat.new()
	blank.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", blank)

	# Abyss hero: show empty slot image
	if GameManager.current_hero in _ABYSS_HEROES and ResourceLoader.exists(_ABYSS_EMPTY_SLOT):
		_frame_rect.texture = load(_ABYSS_EMPTY_SLOT)
		_frame_rect.visible = true
	else:
		_frame_rect.visible = false

	# Border glow overlay (same as occupied slots)
	match _highlight_mode:
		HighlightMode.VALID_TARGET: _set_overlay_glow(Color(0.20, 0.70, 0.25, 1))
		HighlightMode.SELECTED:     _set_overlay_glow(Color(0.85, 0.75, 0.10, 1))
		HighlightMode.INVALID:      _set_overlay_glow(Color(0.70, 0.15, 0.15, 1))
		_:                          _clear_overlay()

	_art_rect.visible = false
	_set_labels_visible(false)

func _show_occupied_state() -> void:
	# Transparent Panel background — frame PNG takes over
	var blank := StyleBoxFlat.new()
	blank.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", blank)

	# Highlight: border glow on the overlay Panel (no fill tint)
	match _highlight_mode:
		HighlightMode.VALID_TARGET: _set_overlay_glow(Color(0.20, 0.70, 0.25, 1))
		HighlightMode.SELECTED:     _set_overlay_glow(Color(0.85, 0.75, 0.10, 1))
		HighlightMode.INVALID:      _set_overlay_glow(Color(0.70, 0.15, 0.15, 1))
		_:                          _clear_overlay()

	_frame_rect.visible = true
	# Pick frame based on faction, dual-cost, and shield state
	var _md_check := minion.card_data as MinionCardData
	var _is_dual  := _md_check != null and _md_check.mana_cost > 0
	var _has_shield := minion.has_shield() and minion.current_shield > 0
	var _faction := minion.card_data.faction
	var _use_generic := not _has_shield and (_faction == "abyss_order" or _faction == "neutral")
	_using_generic = _use_generic
	var _frame_path: String
	if _use_generic:
		_frame_path = "res://assets/art/frames/abyss_order/abyss_battlefield_minion_generic.png"
	elif _faction == "neutral":
		_frame_path = "res://assets/art/frames/neutral/neutral_dual_battlefield_minion.png" \
			if _is_dual else "res://assets/art/frames/neutral/neutral_battlefield_minion.png"
	else:
		_frame_path = "res://assets/art/frames/abyss_order/abyss_dual_battlefield_minion.png" \
			if _is_dual else "res://assets/art/frames/abyss_order/abyss_battlefield_minion.png"
	if ResourceLoader.exists(_frame_path):
		_frame_rect.texture = load(_frame_path)
	_set_labels_visible(true, _use_generic)

	# Reposition art rect based on which layout is active
	if _use_generic:
		_art_rect.position = _CFG_GENERIC["art"]["pos"]
		_art_rect.size     = _CFG_GENERIC["art"]["size"]
		_status_bar.position = _CFG_GENERIC["status"]["pos"]
		_status_bar.size     = _CFG_GENERIC["status"]["size"]
		_atk_label.position = _CFG_GENERIC["atk"]["pos"]
		_atk_label.size     = _CFG_GENERIC["atk"]["size"]
		_hp_label.position  = _CFG_GENERIC["hp"]["pos"]
		_hp_label.size      = _CFG_GENERIC["hp"]["size"]
	else:
		_art_rect.position = _CFG["art"]["pos"]
		_art_rect.size     = _CFG["art"]["size"]
		_status_bar.position = _CFG["status"]["pos"]
		_status_bar.size     = _CFG["status"]["size"]
		_atk_label.position = _CFG["atk"]["pos"]
		_atk_label.size     = _CFG["atk"]["size"]
		_hp_label.position  = _CFG["hp"]["pos"]
		_hp_label.size      = _CFG["hp"]["size"]

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

	# Cost — essence always top-left; mana top-right for dual-cost minions only.
	# Generic frame hides both cost labels entirely.
	var md := minion.card_data as MinionCardData
	if md:
		_cost_label.text      = str(md.essence_cost)
		_mana_cost_label.text = str(md.mana_cost) if md.mana_cost > 0 else ""
		_mana_cost_label.visible = md.mana_cost > 0 and not _use_generic
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
	_hide_status_tooltip()
	for child in _status_bar.get_children():
		child.queue_free()

	if minion.has_guard():
		_status_bar_add_interactive_icon("icon_guard.png", "GUARD",
			"Must be attacked before other friendly minions.")
	if minion.has_deathless():
		_status_bar_add_interactive_icon("icon_deathless.png", "DEATHLESS",
			"The first time this minion would die, it survives with 1 HP.")
	if corruption_total > 0:
		var stacks := corruption_total / 100
		_status_bar_add_interactive_icon("icon_corruption.png", "CORRUPTION",
			"x%d stacks — -%d ATK." % [stacks, corruption_total])
		_status_bar_add_count("x%d" % stacks, Color(0.85, 0.55, 1.00, 1))
	var on_death_body := _build_on_death_tooltip_body(minion)
	if not on_death_body.is_empty():
		_status_bar_add_interactive_icon("icon_on_death.png", "ON DEATH", on_death_body)
	if minion.owner == "player" and minion.can_attack():
		_status_bar_add_interactive_icon("icon_ready.png", "READY", "Can attack this turn.")
	elif minion.owner == "player" and minion.state == Enums.MinionState.EXHAUSTED:
		_status_bar_add_interactive_icon("icon_tired.png", "EXHAUSTED", "Cannot attack yet.")

	_status_bar.visible = _status_bar.get_child_count() > 0

func _set_overlay_glow(color: Color) -> void:
	var border_w: float = 3.0 + _pulse_t * 2.5
	var shadow_sz: float = 6.0 + _pulse_t * 8.0
	var shadow_a: float = 0.50 + _pulse_t * 0.30
	var s := StyleBoxFlat.new()
	s.bg_color   = Color(0, 0, 0, 0)
	s.draw_center = false
	s.set_border_width_all(border_w)
	s.border_color = color
	s.set_corner_radius_all(8)
	s.shadow_color = Color(color.r, color.g, color.b, shadow_a)
	s.shadow_size  = shadow_sz
	_overlay.add_theme_stylebox_override("panel", s)

func _clear_overlay() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color    = Color(0, 0, 0, 0)
	s.draw_center = false
	_overlay.add_theme_stylebox_override("panel", s)

func _set_labels_visible(v: bool, generic: bool = false) -> void:
	# Generic frame hides cost and name — only art, status bar, ATK, HP shown
	_cost_label.visible = v and not generic
	if not v or generic:
		_mana_cost_label.visible = false  # shown per-minion only when dual-cost
	_name_label.visible = v and not generic
	_atk_label.visible  = v
	_hp_label.visible   = v
	if not v:
		_status_bar.visible = false

# ---------------------------------------------------------------------------
# Status bar helpers
# ---------------------------------------------------------------------------

## Add an icon wrapped in a hoverable Control that shows a tooltip on mouse-enter.
func _status_bar_add_interactive_icon(filename: String, tip_title: String, tip_body: String) -> void:
	var tex := _load_icon(filename)
	if tex == null:
		return
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(_STATUS_ICON_SIZE, _STATUS_ICON_SIZE)
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	var rect := TextureRect.new()
	rect.texture             = tex
	rect.custom_minimum_size = Vector2(_STATUS_ICON_SIZE, _STATUS_ICON_SIZE)
	rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(rect)
	wrapper.mouse_entered.connect(_on_status_icon_hovered.bind(rect, tip_title, tip_body))
	wrapper.mouse_exited.connect(_on_status_icon_exited.bind(rect))
	_status_bar.add_child(wrapper)

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

## Build the on-death tooltip body for a minion — card description lines + granted effects.
func _build_on_death_tooltip_body(m: MinionInstance) -> String:
	var parts: Array[String] = []
	if m.card_data is MinionCardData:
		var mc := m.card_data as MinionCardData
		# Extract any "ON DEATH" lines from the card description
		for line in mc.description.split("\n"):
			if line.strip_edges().to_upper().begins_with("ON DEATH"):
				parts.append(line.strip_edges())
		# Fallback: card has effect data but no matching description line
		if parts.is_empty() and (mc.on_death_effect != "" or not mc.on_death_effect_steps.is_empty()):
			parts.append("Triggers an effect on death.")
	for eff in m.granted_on_death_effects:
		var desc: String = eff.get("description", "")
		if not desc.is_empty():
			parts.append(desc)
	return "\n".join(parts)

# ---------------------------------------------------------------------------
# Status bar tooltip — show/hide on icon hover
# ---------------------------------------------------------------------------

func _on_status_icon_hovered(icon: TextureRect, tip_title: String, tip_body: String) -> void:
	icon.modulate = Color(1.5, 1.5, 1.2, 1.0)
	_show_status_tooltip(tip_title, tip_body)

func _on_status_icon_exited(icon: TextureRect) -> void:
	icon.modulate = Color.WHITE
	_hide_status_tooltip()

func _show_status_tooltip(title: String, body: String) -> void:
	if _status_tooltip == null or not is_instance_valid(_status_tooltip):
		_build_status_tooltip_panel()
	var full_text := (title + "\n" + body) if not body.is_empty() else title
	var lbl := _status_tooltip.get_node_or_null("Label") as Label
	if lbl:
		lbl.text = full_text
	# Estimate panel height from line count (wrapping at ~22 chars per line, font size 10)
	var raw_lines := full_text.split("\n")
	var line_count := raw_lines.size()
	for raw in raw_lines:
		line_count += raw.length() / 22  # extra lines from wrapping
	var tip_h := 14 + line_count * 14
	_status_tooltip.size = Vector2(190, tip_h)
	# Position above status bar for player, below for enemy
	var sb_y: int = _CFG_GENERIC["status"]["pos"].y if _using_generic else _CFG["status"]["pos"].y
	if slot_owner == "enemy":
		_status_tooltip.position = Vector2(-5, sb_y + 27)
	else:
		_status_tooltip.position = Vector2(-5, sb_y - tip_h - 4)
	_status_tooltip.visible = true

func _hide_status_tooltip() -> void:
	if _status_tooltip != null and is_instance_valid(_status_tooltip):
		_status_tooltip.visible = false

func _build_status_tooltip_panel() -> void:
	var p := Panel.new()
	p.name = "StatusTooltip"
	p.visible = false
	p.z_index = 20
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color            = Color(0.06, 0.04, 0.10, 0.93)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color                = Color(0.55, 0.40, 0.75, 0.85)
	style.corner_radius_top_left      = 3
	style.corner_radius_top_right     = 3
	style.corner_radius_bottom_left   = 3
	style.corner_radius_bottom_right  = 3
	p.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.name             = "Label"
	lbl.position         = Vector2(7, 5)
	lbl.size             = Vector2(176, 100)
	lbl.autowrap_mode    = TextServer.AUTOWRAP_WORD_SMART
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.98, 1))
	lbl.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	if _bold_font:
		lbl.add_theme_font_override("font", _bold_font)
	p.add_child(lbl)
	add_child(p)
	_status_tooltip = p

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const _ICON_DIR := "res://assets/art/icons/"

func _load_icon(filename: String) -> Texture2D:
	var path := _ICON_DIR + filename
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
