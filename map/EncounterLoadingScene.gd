## EncounterLoadingScene.gd
## Per-fight loading screen shown before each encounter.
## Displays the fight's background art, act progression bar, fight title,
## flavour story text, and an ENCOUNTER button to proceed into combat.
extends Control

const COLOR_PURPLE      := Color(0.75, 0.35, 1.00, 1.0)
const COLOR_GOLD        := Color(0.90, 0.75, 0.20, 1.0)
const COLOR_TEXT_LIGHT  := Color(0.92, 0.90, 0.95, 1.0)
const COLOR_TEXT_DIM    := Color(0.55, 0.52, 0.60, 1.0)
const COLOR_BG_PANEL    := Color(0.04, 0.02, 0.08, 0.72)

func _ready() -> void:
	# Redirect to talent screen if there are unspent points
	if GameManager.talent_points > 0:
		GameManager.go_to_scene("res://talents/TalentSelectScene.tscn")
		return

	# Deferred so the viewport has finished sizing this node before we build anchored children.
	call_deferred("_build_ui")

# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var enemy: EnemyData = GameManager.current_enemy
	if enemy == null:
		push_error("EncounterLoadingScene: current_enemy is null")
		return

	var vp := get_viewport_rect().size

	# --- Background ---
	var bg := TextureRect.new()
	bg.set_position(Vector2.ZERO)
	bg.set_size(vp)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	bg.texture = load(enemy.background_path) if ResourceLoader.exists(enemy.background_path) else null
	add_child(bg)

	# Dark vignette overlay for readability
	var overlay := ColorRect.new()
	overlay.set_position(Vector2.ZERO)
	overlay.set_size(vp)
	overlay.color = Color(0.0, 0.0, 0.0, 0.45)
	add_child(overlay)

	# --- Top bar: act progression ---
	_add_act_bar(vp)

	# --- Left panel: title + story ---
	_add_story_panel(enemy, vp)

	# --- Bottom-right: ENCOUNTER button ---
	_add_encounter_button(vp)

	# --- Bottom-left: View Deck button ---
	_add_view_deck_button(vp)

# ---------------------------------------------------------------------------
# Act Progression Bar
# ---------------------------------------------------------------------------

func _add_act_bar(vp: Vector2) -> void:
	var path := _get_progression_bar_path()
	if path == "" or not ResourceLoader.exists(path):
		return

	var bar := TextureRect.new()
	bar.texture = load(path)
	bar.set_position(Vector2.ZERO)
	bar.set_size(Vector2(vp.x, 80))
	bar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bar.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	add_child(bar)

func _get_progression_bar_path() -> String:
	var idx := GameManager.run_node_index
	# Act 1 has per-fight progression bar images (fights 0, 1, 2).
	const ACT1_BARS: Array = [
		"res://assets/art/progression/backgrounds/a1_fight1_progression_bar.png",
		"res://assets/art/progression/backgrounds/a1_fight2_progression_bar.png",
		"res://assets/art/progression/backgrounds/a1_fight3_progression_bar.png",
	]
	if idx < ACT1_BARS.size():
		return ACT1_BARS[idx]
	# Future acts: add their bar paths here.
	return ""

# ---------------------------------------------------------------------------
# Story Panel (left side)
# ---------------------------------------------------------------------------

func _add_story_panel(enemy: EnemyData, vp: Vector2) -> void:
	const BAR_H    := 80
	const MARGIN_X := 40
	const MARGIN_B := 60
	var panel_w: float = vp.x * 0.44
	var panel_h: float = vp.y - BAR_H - MARGIN_B

	var panel := PanelContainer.new()
	panel.set_position(Vector2(MARGIN_X, BAR_H))
	panel.set_size(Vector2(panel_w, panel_h))
	panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_BG_PANEL))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   28)
	margin.add_theme_constant_override("margin_right",  28)
	margin.add_theme_constant_override("margin_top",    28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)
	margin.add_child(inner)

	# Fight title
	var title_lbl := Label.new()
	title_lbl.text = enemy.enemy_name.to_upper()
	title_lbl.add_theme_font_size_override("font_size", 34)
	title_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(title_lbl)

	# Divider
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", COLOR_PURPLE)
	inner.add_child(sep)

	# Story text
	var story_lbl := Label.new()
	story_lbl.text = enemy.story
	story_lbl.add_theme_font_size_override("font_size", 16)
	story_lbl.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	story_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(story_lbl)

# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _add_encounter_button(vp: Vector2) -> void:
	var btn := Button.new()
	btn.text = "ENCOUNTER"
	btn.set_position(Vector2(vp.x - 260, vp.y - 70))
	btn.set_size(Vector2(220, 50))
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", COLOR_GOLD)
	btn.pressed.connect(_on_encounter_pressed)
	add_child(btn)

func _add_view_deck_button(vp: Vector2) -> void:
	var btn := Button.new()
	btn.text = "View Deck"
	btn.set_position(Vector2(40, vp.y - 70))
	btn.set_size(Vector2(160, 50))
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_on_view_deck_pressed)
	add_child(btn)

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_encounter_pressed() -> void:
	GameManager.go_to_scene("res://combat/board/CombatScene.tscn")

func _on_view_deck_pressed() -> void:
	GameManager.go_to_scene("res://ui/DeckViewerScene.tscn")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_panel_style(bg_color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color         = bg_color
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.35, 0.20, 0.55, 0.60)
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	return s
