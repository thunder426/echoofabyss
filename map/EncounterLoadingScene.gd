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

const _BTN_NORMAL  := "res://assets/art/buttons/button_normal.png"
const _BTN_HOVER   := "res://assets/art/buttons/button_hover.png"
const _BTN_PRESSED := "res://assets/art/buttons/button_pressed.png"

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
		GameManager.go_to_scene("res://ui/MainMenu.tscn")
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
const BAR_H       := 130  ## Total reserved height at top (label + bar + padding)
const BAR_W       := 400
const BAR_IMG_H   := 56   ## Height of the progression bar image
const BAR_TOP     := 6    ## Gap from screen top before the "ACT X" label
const ACT_LABEL_H := 50

const ACT_TITLES: Dictionary = {
	1: "THE IMP LAIR",
	2: "THE ABYSS DUNGEON",
	3: "THE VOID RIFT",
	4: "THE FINAL DESCENT",
}

func _add_act_bar(vp: Vector2) -> void:
	var bar_info := _get_progression_bar_info()
	var path: String = bar_info.path
	var act_num: int = bar_info.act
	if path == "" or not ResourceLoader.exists(path):
		return

	var bar_x: float  = (vp.x - BAR_W) * 0.5
	var label_y := BAR_TOP
	var bar_y   := label_y + ACT_LABEL_H + 4

	# "ACT X: TITLE" label — bold, violet, centred above the bar
	var act_title: String = ACT_TITLES.get(act_num, "") as String
	var label_text: String = "ACT %d: %s" % [act_num, act_title] if act_title != "" else "ACT %d" % act_num
	var act_lbl := RichTextLabel.new()
	act_lbl.bbcode_enabled = true
	act_lbl.text = "[center][b]%s[/b][/center]" % label_text
	act_lbl.scroll_active = false
	act_lbl.add_theme_font_size_override("bold_font_size", 40)
	act_lbl.add_theme_font_size_override("normal_font_size", 40)
	act_lbl.add_theme_color_override("default_color", COLOR_PURPLE)
	act_lbl.set_position(Vector2(0, label_y))
	act_lbl.set_size(Vector2(vp.x, ACT_LABEL_H))
	add_child(act_lbl)

	# Clip container forces the bar image to exactly BAR_W × BAR_IMG_H
	var clip := Control.new()
	clip.clip_contents = true
	clip.set_position(Vector2(bar_x, bar_y))
	clip.set_size(Vector2(BAR_W, BAR_IMG_H))
	add_child(clip)

	var bar := TextureRect.new()
	bar.texture = load(path)
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	clip.add_child(bar)

## Returns {path: String, act: int} for the current fight's progression bar.
## Reuses Act 1 bar images for acts with 3 fights (Acts 1-3).
func _get_progression_bar_info() -> Dictionary:
	var idx := GameManager.run_node_index
	var act: int = GameManager._act_for_index(idx)
	# Calculate fight number within this act (1-based)
	var cumulative := 0
	for i in act - 1:
		cumulative += GameManager.ACT_SIZES[i]
	var fight_in_act: int = idx - cumulative  # 1, 2, or 3

	# Per-fight bar images — reused across 3-fight acts
	const FIGHT_BARS: Array = [
		"res://assets/art/progression/backgrounds/a1_fight1_progression_bar.png",
		"res://assets/art/progression/backgrounds/a1_fight2_progression_bar.png",
		"res://assets/art/progression/backgrounds/a1_fight3_progression_bar.png",
	]
	if fight_in_act >= 1 and fight_in_act <= FIGHT_BARS.size():
		return {path = FIGHT_BARS[fight_in_act - 1], act = act}
	# Act 4 has 6 fights — use fight3 bar for fights 4-6 (last bar = most filled)
	if fight_in_act > FIGHT_BARS.size():
		return {path = FIGHT_BARS[FIGHT_BARS.size() - 1], act = act}
	return {path = "", act = act}

# ---------------------------------------------------------------------------
# Story Panel (left side)
# ---------------------------------------------------------------------------

func _add_story_panel(enemy: EnemyData, vp: Vector2) -> void:
	const MARGIN_X := 40
	const MARGIN_B := 90
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
	inner.add_theme_constant_override("separation", 12)
	margin.add_child(inner)

	# Act / encounter label (e.g. "ENCOUNTER I")
	if enemy.title != "":
		var act_lbl := Label.new()
		act_lbl.text = enemy.title.to_upper()
		act_lbl.add_theme_font_size_override("font_size", 14)
		act_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		act_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(act_lbl)

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

var _encounter_btn: Button = null

func _add_encounter_button(vp: Vector2) -> void:
	var btn := Button.new()
	btn.text = "ENCOUNTER"
	btn.set_position(Vector2(vp.x - 260, vp.y - 70))
	btn.set_size(Vector2(220, 50))
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", COLOR_GOLD)
	_apply_btn_style(btn)
	btn.pressed.connect(_on_encounter_pressed)
	add_child(btn)
	_encounter_btn = btn

func _add_view_deck_button(vp: Vector2) -> void:
	var btn := Button.new()
	btn.text = "View Deck"
	btn.set_position(Vector2(40, vp.y - 75))
	btn.set_size(Vector2(160, 46))
	btn.add_theme_font_size_override("font_size", 16)
	_apply_btn_style(btn)
	btn.pressed.connect(_on_view_deck_pressed)
	add_child(btn)

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_encounter_pressed() -> void:
	_show_button_spinner()
	# Threaded load keeps the main loop ticking so the spinner actually animates.
	# Synchronous change_scene_to_file would freeze _process for the whole load.
	var path := "res://combat/board/CombatScene.tscn"
	ResourceLoader.load_threaded_request(path)
	while true:
		await get_tree().process_frame
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("EncounterLoadingScene: threaded load failed for %s, falling back" % path)
			GameManager.go_to_scene(path)
			return
	var packed: PackedScene = ResourceLoader.load_threaded_get(path)
	UserProfile.save()
	get_tree().change_scene_to_packed(packed)

func _on_view_deck_pressed() -> void:
	GameManager.go_to_scene("res://ui/DeckViewerScene.tscn")

# ---------------------------------------------------------------------------
# Button Spinner
# ---------------------------------------------------------------------------

func _show_button_spinner() -> void:
	if _encounter_btn == null:
		return
	_encounter_btn.disabled = true
	_encounter_btn.text = "  LOADING"  # leading pad leaves room for the spinner

	# A spinning arc drawn into a Control via _draw — sits at the left edge of
	# the button, rotates while the synchronous load blocks the main thread.
	var spinner := _Spinner.new()
	spinner.size = Vector2(28, 28)
	spinner.position = Vector2(18, (_encounter_btn.size.y - 28) * 0.5)
	spinner.color = COLOR_PURPLE
	_encounter_btn.add_child(spinner)

class _Spinner extends Control:
	var color: Color = Color(1, 1, 1, 1)
	var _angle: float = 0.0

	func _process(delta: float) -> void:
		_angle += delta * TAU * 1.2  # ~1.2 full rotations per second
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius: float = min(size.x, size.y) * 0.5 - 2.0
		# Faint full ring for context
		draw_arc(center, radius, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.25), 3.0, true)
		# Bright arc that rotates
		draw_arc(center, radius, _angle, _angle + TAU * 0.3, 16, color, 3.0, true)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _apply_btn_style(btn: Button) -> void:
	if not ResourceLoader.exists(_BTN_NORMAL):
		return
	var hover_path   := _BTN_HOVER   if ResourceLoader.exists(_BTN_HOVER)   else _BTN_NORMAL
	var pressed_path := _BTN_PRESSED if ResourceLoader.exists(_BTN_PRESSED) else _BTN_NORMAL
	btn.add_theme_stylebox_override("normal",   _make_btn_style(_BTN_NORMAL))
	btn.add_theme_stylebox_override("hover",    _make_btn_style(hover_path))
	btn.add_theme_stylebox_override("pressed",  _make_btn_style(pressed_path))
	btn.add_theme_stylebox_override("disabled", _make_btn_style(_BTN_NORMAL))

func _make_btn_style(path: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(path)
	style.texture_margin_left   = 16.0
	style.texture_margin_top    = 16.0
	style.texture_margin_right  = 16.0
	style.texture_margin_bottom = 16.0
	return style

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
