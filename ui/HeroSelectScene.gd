## HeroSelectScene.gd
## Pre-run hero and faction selection screen.
## Hero data is read from HeroDatabase autoload — do not hardcode heroes here.
## Route: MainMenu → HeroSelectScene → DeckBuilderScene
extends Node2D

# ---------------------------------------------------------------------------
# Asset paths (UI chrome only — hero-specific assets come from HeroData)
# ---------------------------------------------------------------------------

const _BG_PATH          := "res://assets/art/hero_selection/hero_select_background.png"
const _BTN_PATH         := "res://assets/menu/menu_button.png"
const _BTN_HOVER_PATH   := "res://assets/menu/menu_button_on_hover.png"
const _BTN_PRESSED_PATH := "res://assets/menu/menu_button_on_press.png"

# Hero panel fixed size — keeps portrait/frame from stretching to full screen height
const _PANEL_W := 560
const _PANEL_H := 700

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# CanvasLayer so all Controls anchor to the viewport, same as MainMenu
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Background
	if ResourceLoader.exists(_BG_PATH):
		var tex_bg := TextureRect.new()
		tex_bg.texture = load(_BG_PATH)
		tex_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		canvas.add_child(tex_bg)
	else:
		var col_bg := ColorRect.new()
		col_bg.color = Color(0.06, 0.04, 0.10, 1)
		col_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		canvas.add_child(col_bg)

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

	# Hero cards row — centred horizontally, expands vertically
	var heroes_row := HBoxContainer.new()
	heroes_row.alignment = BoxContainer.ALIGNMENT_CENTER
	heroes_row.add_theme_constant_override("separation", 60)
	heroes_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	heroes_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(heroes_row)

	for hero in HeroDatabase.get_all_heroes():
		heroes_row.add_child(_make_hero_panel(hero))

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

# Builds one hero card panel with a fixed size so portrait/frame never go huge.
# PanelContainer fits ALL its children to the same content rect — the frame
# TextureRect overlays the VBox content without needing a wrapper node.
func _make_hero_panel(hero: HeroData) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(_PANEL_W, _PANEL_H)

	# Transparent background — the frame PNG provides all visual framing.
	var style := StyleBoxEmpty.new()
	panel.add_theme_stylebox_override("panel", style)

	# MarginContainer keeps all content inside the frame's transparent window.
	# margin_top ~95 sits below the top ornament; left/right ~55 clear the side borders.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    105)
	margin.add_theme_constant_override("margin_bottom", 68)
	margin.add_theme_constant_override("margin_left",   90)
	margin.add_theme_constant_override("margin_right",  75)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 7)
	margin.add_child(vbox)

	# Portrait — fills the available width, crops height from centre.
	var portrait_path: String = hero.portrait_path
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		var portrait := TextureRect.new()
		portrait.texture = load(portrait_path)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.custom_minimum_size = Vector2(0, 200)
		portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait.clip_contents = true
		vbox.add_child(portrait)

	# Dark semi-transparent panel behind all text so it's readable over the portrait
	var text_panel := PanelContainer.new()
	text_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text_style := StyleBoxFlat.new()
	text_style.bg_color = Color(0.05, 0.03, 0.10, 0.82)
	text_style.border_color = Color(0.45, 0.18, 0.75, 0.7)
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

	# Faction
	var faction_lbl := Label.new()
	faction_lbl.text = hero.faction
	faction_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	faction_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faction_lbl.add_theme_font_size_override("font_size", 16)
	faction_lbl.add_theme_color_override("font_color", Color(0.70, 0.50, 1.0, 1))
	inner.add_child(faction_lbl)

	inner.add_child(HSeparator.new())

	# Passives
	var passive_header := Label.new()
	passive_header.text = "HERO PASSIVES"
	passive_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	passive_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	passive_header.add_theme_font_size_override("font_size", 14)
	passive_header.add_theme_color_override("font_color", Color(0.70, 0.50, 1.0, 1))
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
	branch_header.add_theme_color_override("font_color", Color(0.70, 0.50, 1.0, 1))
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
		blbl.add_theme_color_override("font_color", Color(0.80, 0.65, 1.0, 1))
		blbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		branch_box.add_child(blbl)

		var desc_lbl := Label.new()
		desc_lbl.text = TalentDatabase.get_branch_description(branch_id)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.75, 1))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		branch_box.add_child(desc_lbl)

		inner.add_child(branch_box)

	# Choose / Locked button — wrapped in a MarginContainer for exact gap control.
	# The VBoxContainer adds 7px separation above this wrapper; margin_top adds 2px more,
	# giving a 9px gap (≈5px less than the double-separation the old spacer node caused).
	var btn := Button.new()
	if true:  # all heroes in HeroDatabase are selectable; locked heroes are simply not registered yet
		btn.text = "Choose  →"
		btn.add_theme_font_size_override("font_size", 20)
		btn.custom_minimum_size = Vector2(0, 56)
		_apply_btn_style(btn)
		btn.pressed.connect(_on_hero_chosen.bind(hero.id))
	else:
		btn.text = "— Locked —"
		btn.disabled = true
		btn.add_theme_font_size_override("font_size", 18)
		btn.custom_minimum_size = Vector2(0, 56)
		btn.modulate = Color(0.4, 0.4, 0.5, 1)
	var btn_wrapper := MarginContainer.new()
	btn_wrapper.add_theme_constant_override("margin_top",    -15)
	btn_wrapper.add_theme_constant_override("margin_bottom", 0)
	btn_wrapper.add_theme_constant_override("margin_left",   0)
	btn_wrapper.add_theme_constant_override("margin_right",  0)
	btn_wrapper.add_child(btn)
	inner.add_child(btn_wrapper)

	# Frame overlay — PanelContainer places this at the same rect as vbox.
	# mouse_filter=IGNORE so clicks reach buttons in the vbox.
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
	style.texture_margin_top    = 16.0
	style.texture_margin_right  = 16.0
	style.texture_margin_bottom = 16.0
	return style

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_hero_chosen(hero_id: String) -> void:
	GameManager.current_hero = hero_id
	GameManager.start_new_run()
	GameManager.go_to_scene("res://talents/TalentSelectScene.tscn")
