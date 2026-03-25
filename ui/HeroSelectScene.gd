## HeroSelectScene.gd
## Pre-run hero and faction selection screen.
## Hero data is read from HeroDatabase autoload — do not hardcode heroes here.
## Route: MainMenu → HeroSelectScene → DeckBuilderScene
extends Node2D

# ---------------------------------------------------------------------------
# FactionTheme — all faction-specific colours and the background image path.
# Add a new entry to _get_theme() when a new faction is introduced.
# ---------------------------------------------------------------------------
class FactionTheme:
	var bg_path:         String  ## background image for this faction's hero-select screen
	var accent:          Color   ## section headers, faction label on card, "SELECT FACTION" label
	var accent_dim:      Color   ## branch name labels, unselected faction-btn font
	var accent_muted:    Color   ## branch description labels
	var card_bg:         Color   ## hero card text-panel background
	var card_border:     Color   ## hero card text-panel border
	var btn_sel_bg:      Color   ## faction toggle button — selected background
	var btn_sel_border:  Color   ## faction toggle button — selected border
	var btn_hover_border: Color  ## faction toggle button — hover border
	var btn_font_sel:    Color   ## faction toggle button — selected font
	var btn_font_unsel:  Color   ## faction toggle button — unselected font

func _get_theme(faction_id: String) -> FactionTheme:
	var t := FactionTheme.new()
	match faction_id:
		"neutral":
			t.bg_path          = "res://assets/art/hero_selection/neutral_heroselection.png"
			t.accent           = Color(0.82, 0.58, 0.22, 1.00)  # bronze
			t.accent_dim       = Color(0.90, 0.72, 0.35, 1.00)  # bright gold
			t.accent_muted     = Color(0.65, 0.50, 0.28, 1.00)  # muted bronze
			t.card_bg          = Color(0.07, 0.05, 0.02, 0.82)  # dark leather
			t.card_border      = Color(0.60, 0.40, 0.15, 0.70)  # bronze border
			t.btn_sel_bg       = Color(0.28, 0.18, 0.05, 0.90)  # dark bronze
			t.btn_sel_border   = Color(0.82, 0.58, 0.22, 1.00)  # bronze
			t.btn_hover_border = Color(0.95, 0.75, 0.35, 1.00)  # bright gold
			t.btn_font_sel     = Color(1.00, 0.90, 0.70, 1.00)  # warm gold-white
			t.btn_font_unsel   = Color(0.60, 0.48, 0.28, 1.00)  # muted bronze
		_: # "abyss_order" and default
			t.bg_path          = "res://assets/art/hero_selection/abyss_heroselection.png"
			t.accent           = Color(0.70, 0.50, 1.00, 1.00)
			t.accent_dim       = Color(0.80, 0.65, 1.00, 1.00)
			t.accent_muted     = Color(0.60, 0.60, 0.75, 1.00)
			t.card_bg          = Color(0.05, 0.03, 0.10, 0.82)
			t.card_border      = Color(0.45, 0.18, 0.75, 0.70)
			t.btn_sel_bg       = Color(0.40, 0.15, 0.70, 0.90)
			t.btn_sel_border   = Color(0.80, 0.50, 1.00, 1.00)
			t.btn_hover_border = Color(0.90, 0.65, 1.00, 1.00)
			t.btn_font_sel     = Color(0.98, 0.90, 1.00, 1.00)
			t.btn_font_unsel   = Color(0.60, 0.50, 0.75, 1.00)
	return t

# ---------------------------------------------------------------------------
# Asset paths (UI chrome only — hero-specific assets come from HeroData)
# ---------------------------------------------------------------------------

const _BTN_PATH         := "res://assets/art/buttons/button_normal.png"
const _BTN_HOVER_PATH   := "res://assets/art/buttons/button_hover.png"
const _BTN_PRESSED_PATH := "res://assets/art/buttons/button_pressed.png"

# Hero panel fixed size — keeps portrait/frame from stretching to full screen height
const _PANEL_W := 560
const _PANEL_H := 700

# Page-level faction selection — written to GameManager on hero choose
var _selected_faction: String = "abyss_order"
var _faction_btns: Array[Button] = []
# hero panel visibility: Array of {panel: Control, faction: String}
var _hero_panels: Array = []
# dynamic refs updated when faction changes
var _bg_tex: TextureRect = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var theme := _get_theme(_selected_faction)

	# CanvasLayer so all Controls anchor to the viewport, same as MainMenu
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Background — store ref so _refresh_hero_visibility() can swap the texture
	_bg_tex = TextureRect.new()
	_bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_bg(theme)
	canvas.add_child(_bg_tex)

	# Root layout fills viewport via CanvasLayer
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	canvas.add_child(root)

	# Title
	var title := Label.new()
	title.text = "CHOOSE YOUR HERO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.98, 0.94, 0.78, 1))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("outline_size", 4)
	root.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "Select a hero and faction before building your deck."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.82, 0.78, 0.92, 1))
	subtitle.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	subtitle.add_theme_constant_override("outline_size", 3)
	root.add_child(subtitle)

	# Faction selector bar
	root.add_child(_make_faction_bar(theme))

	# Hero cards row — centred horizontally, expands vertically
	var heroes_row := HBoxContainer.new()
	heroes_row.alignment = BoxContainer.ALIGNMENT_CENTER
	heroes_row.add_theme_constant_override("separation", 60)
	heroes_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	heroes_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(heroes_row)

	_hero_panels.clear()
	for hero in HeroDatabase.get_all_heroes():
		var hero_theme := _get_theme(hero.faction.to_lower().replace(" ", "_"))
		var panel := _make_hero_panel(hero, hero_theme)
		heroes_row.add_child(panel)
		_hero_panels.append({"panel": panel, "faction": hero.faction})
	_refresh_hero_visibility()

	# Back button
	var back_btn := Button.new()
	back_btn.text = "← Back to Menu"
	back_btn.custom_minimum_size = Vector2(280, 60)
	back_btn.add_theme_font_size_override("font_size", 20)
	_apply_btn_style(back_btn)
	back_btn.pressed.connect(func(): GameManager.go_to_scene("res://ui/MainMenu.tscn"))

	var back_center := CenterContainer.new()
	back_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_center.add_child(back_btn)
	root.add_child(back_center)

# ---------------------------------------------------------------------------
# Hero card panel
# Builds one hero card with a fixed size so portrait/frame never go huge.
# PanelContainer fits ALL its children to the same content rect — the frame
# TextureRect overlays the VBox content without needing a wrapper node.
# ---------------------------------------------------------------------------

func _make_hero_panel(hero: HeroData, theme: FactionTheme) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(_PANEL_W, _PANEL_H)

	# Transparent background — the frame PNG provides all visual framing.
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	# MarginContainer keeps all content inside the frame's transparent window.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    105)
	margin.add_theme_constant_override("margin_bottom", 63)
	margin.add_theme_constant_override("margin_left",   90)
	margin.add_theme_constant_override("margin_right",  75)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 7)
	margin.add_child(vbox)

	# Portrait
	if hero.portrait_path != "" and ResourceLoader.exists(hero.portrait_path):
		var portrait := TextureRect.new()
		portrait.texture = load(hero.portrait_path)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.custom_minimum_size = Vector2(0, 200)
		portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait.clip_contents = true
		vbox.add_child(portrait)

	# Dark semi-transparent panel behind all text
	var text_panel := PanelContainer.new()
	text_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	var text_style := StyleBoxFlat.new()
	text_style.bg_color = theme.card_bg
	text_style.border_color = theme.card_border
	text_style.set_border_width_all(1)
	text_style.set_corner_radius_all(6)
	text_style.content_margin_left   = 10.0
	text_style.content_margin_right  = 10.0
	text_style.content_margin_top    = 8.0
	text_style.content_margin_bottom = 8.0
	text_panel.add_theme_stylebox_override("panel", text_style)
	vbox.add_child(text_panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 7)
	text_panel.add_child(inner)

	# Name · title
	var name_lbl := Label.new()
	name_lbl.text = "%s  ·  %s" % [hero.hero_name, hero.title]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.add_theme_color_override("font_color", Color(0.98, 0.94, 0.78, 1))
	name_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	name_lbl.add_theme_constant_override("outline_size", 3)
	inner.add_child(name_lbl)

	# Faction label
	var faction_lbl := Label.new()
	faction_lbl.text = hero.faction
	faction_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	faction_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faction_lbl.add_theme_font_size_override("font_size", 16)
	faction_lbl.add_theme_color_override("font_color", theme.accent)
	inner.add_child(faction_lbl)

	inner.add_child(HSeparator.new())

	# Passives
	var passive_header := Label.new()
	passive_header.text = "HERO PASSIVES"
	passive_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	passive_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	passive_header.add_theme_font_size_override("font_size", 14)
	passive_header.add_theme_color_override("font_color", theme.accent)
	inner.add_child(passive_header)

	for passive in hero.passives:
		var plbl := Label.new()
		plbl.text = passive.description
		plbl.add_theme_font_size_override("font_size", 13)
		plbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95, 1))
		plbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(plbl)

	inner.add_child(HSeparator.new())

	# Talent branches
	var branch_header := Label.new()
	branch_header.text = "TALENT BRANCHES"
	branch_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	branch_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	branch_header.add_theme_font_size_override("font_size", 14)
	branch_header.add_theme_color_override("font_color", theme.accent)
	inner.add_child(branch_header)

	for branch_id in hero.talent_branch_ids:
		var branch_box := VBoxContainer.new()
		branch_box.add_theme_constant_override("separation", 1)
		branch_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var blbl := Label.new()
		blbl.text = TalentDatabase.get_branch_display_name(branch_id)
		blbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		blbl.add_theme_font_size_override("font_size", 14)
		blbl.add_theme_color_override("font_color", theme.accent_dim)
		blbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		branch_box.add_child(blbl)

		var desc_lbl := Label.new()
		desc_lbl.text = TalentDatabase.get_branch_description(branch_id)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", theme.accent_muted)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		branch_box.add_child(desc_lbl)

		inner.add_child(branch_box)

	# Spacer inside the dark text panel — absorbs spare space so content stays
	# at the top and the dark background covers all the way to the panel bottom.
	var inner_spacer := Control.new()
	inner_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(inner_spacer)

	# Choose / Locked button — lives in the vbox BELOW the spacer, so it always
	# sits at a fixed distance from the card bottom (controlled by margin_bottom
	# on the outer MarginContainer). The spacer above absorbs all spare space.
	var btn := Button.new()
	if true:  # all heroes in HeroDatabase are selectable; locked heroes are simply not registered yet
		btn.text = "Choose  →"
		btn.add_theme_font_size_override("font_size", 16)
		btn.custom_minimum_size = Vector2(300, 38)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_apply_btn_style(btn)
		btn.pressed.connect(_on_hero_chosen.bind(hero.id))
	else:
		btn.text = "— Locked —"
		btn.disabled = true
		btn.add_theme_font_size_override("font_size", 16)
		btn.custom_minimum_size = Vector2(300, 38)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.modulate = Color(0.4, 0.4, 0.5, 1)
	var btn_center := CenterContainer.new()
	btn_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_center.z_index = 1
	btn_center.add_child(btn)
	vbox.add_child(btn_center)

	# Frame overlay — mouse_filter=IGNORE so clicks reach buttons beneath
	if hero.frame_path != "" and ResourceLoader.exists(hero.frame_path):
		var frame := TextureRect.new()
		frame.texture = load(hero.frame_path)
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.custom_minimum_size = Vector2(0, 0)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(frame)

	return panel

# ---------------------------------------------------------------------------
# Faction bar
# ---------------------------------------------------------------------------

func _make_faction_bar(theme: FactionTheme) -> Control:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	const FACTIONS: Array = [["abyss_order", "Abyss Order"], ["neutral", "Neutral"]]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	center.add_child(row)

	_faction_btns.clear()
	for fdata in FACTIONS:
		var fid: String   = fdata[0]
		var fname: String = fdata[1]
		var fb := Button.new()
		fb.text = fname
		fb.custom_minimum_size = Vector2(200, 44)
		fb.add_theme_font_size_override("font_size", 18)
		_set_faction_btn_style(fb, fid == _selected_faction, _get_theme(fid))
		_faction_btns.append(fb)
		row.add_child(fb)
		var captured_fid := fid
		fb.pressed.connect(func():
			_selected_faction = captured_fid
			var new_theme := _get_theme(_selected_faction)
			for i in _faction_btns.size():
				var fid_i: String = FACTIONS[i][0]
				_set_faction_btn_style(_faction_btns[i], fid_i == _selected_faction, _get_theme(fid_i))
			_refresh_hero_visibility(new_theme)
		)

	return center

func _refresh_hero_visibility(theme: FactionTheme = null) -> void:
	if theme == null:
		theme = _get_theme(_selected_faction)
	for entry in _hero_panels:
		var faction_id: String = (entry["faction"] as String).to_lower().replace(" ", "_")
		entry["panel"].visible = (faction_id == _selected_faction)
	# Swap background and header label colour to match the active faction
	_apply_bg(theme)

func _apply_bg(theme: FactionTheme) -> void:
	if _bg_tex == null:
		return
	if ResourceLoader.exists(theme.bg_path):
		_bg_tex.texture = load(theme.bg_path)
	else:
		_bg_tex.texture = null

func _set_faction_btn_style(btn: Button, selected: bool, theme: FactionTheme) -> void:
	var s := StyleBoxFlat.new()
	if selected:
		s.bg_color     = theme.btn_sel_bg
		s.border_color = theme.btn_sel_border
	else:
		s.bg_color     = Color(0.08, 0.05, 0.15, 0.80)
		s.border_color = Color(0.35, 0.25, 0.50, 0.60)
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.content_margin_left   = 16.0
	s.content_margin_right  = 16.0
	s.content_margin_top    = 8.0
	s.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("normal",  s)
	btn.add_theme_stylebox_override("pressed", s)
	var s_hover := s.duplicate() as StyleBoxFlat
	s_hover.border_color = theme.btn_hover_border
	btn.add_theme_stylebox_override("hover", s_hover)
	btn.add_theme_color_override("font_color",
		theme.btn_font_sel if selected else theme.btn_font_unsel)

# ---------------------------------------------------------------------------
# Button style helpers
# ---------------------------------------------------------------------------

func _apply_btn_style(btn: Button) -> void:
	if not ResourceLoader.exists(_BTN_PATH):
		return
	var hover_path   := _BTN_HOVER_PATH   if ResourceLoader.exists(_BTN_HOVER_PATH)   else _BTN_PATH
	var pressed_path := _BTN_PRESSED_PATH if ResourceLoader.exists(_BTN_PRESSED_PATH) else _BTN_PATH
	btn.add_theme_stylebox_override("normal",   _make_btn_style(_BTN_PATH))
	btn.add_theme_stylebox_override("hover",    _make_btn_style(hover_path))
	btn.add_theme_stylebox_override("pressed",  _make_btn_style(pressed_path))
	btn.add_theme_stylebox_override("disabled", _make_btn_style(_BTN_PATH))

func _make_btn_style(path: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(path)
	style.texture_margin_left   = 16.0
	style.texture_margin_top    = 4.0
	style.texture_margin_right  = 16.0
	style.texture_margin_bottom = 4.0
	style.content_margin_top    = 2.0
	style.content_margin_bottom = 2.0
	return style

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_hero_chosen(hero_id: String) -> void:
	GameManager.current_hero    = hero_id
	GameManager.current_faction = _selected_faction
	GameManager.start_new_run()
	GameManager.go_to_scene("res://talents/TalentSelectScene.tscn")
