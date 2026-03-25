## TalentSelectScene.gd
## Programmatic talent selection UI.
## Shows 3 branch columns × 4 tier rows.
## Player spends all pending talent_points then returns to MapScene.
extends Node

const _BTN_NORMAL  := "res://assets/art/buttons/button_normal.png"
const _BTN_HOVER   := "res://assets/art/buttons/button_hover.png"
const _BTN_PRESSED := "res://assets/art/buttons/button_pressed.png"

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------

const BRANCH_COLORS := {
	"swarm":       Color(0.30, 0.80, 0.30, 1),
	"rune_master": Color(0.90, 0.60, 0.10, 1),
	"void_bolt":   Color(0.20, 0.60, 1.00, 1),
}
const BRANCH_COLOR_DEFAULT := Color(0.70, 0.70, 0.70, 1)

# ---------------------------------------------------------------------------
# Node refs (built programmatically)
# ---------------------------------------------------------------------------

var _root_vbox: VBoxContainer
var _points_label: Label
var _revert_btn: Button
var _branch_columns: Dictionary = {}   # branch id -> VBoxContainer
var _talent_buttons: Dictionary = {}   # talent id -> Button

# Snapshot taken on scene entry — used to detect and undo picks made here.
var _entry_talents: Array[String] = []
var _entry_points: int = 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_entry_talents = GameManager.unlocked_talents.duplicate()
	_entry_points  = GameManager.talent_points
	_build_ui()
	_refresh()

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Full-screen background
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.10, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Root layout
	_root_vbox = VBoxContainer.new()
	_root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_vbox.add_theme_constant_override("separation", 20)
	_root_vbox.set("theme_override_constants/margin_left", 60)
	_root_vbox.set("theme_override_constants/margin_right", 60)
	add_child(_root_vbox)

	# Title
	var title := Label.new()
	title.text = "TALENT TREE — Lord Vael"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.75, 0.35, 1.0, 1))
	_root_vbox.add_child(title)

	# Points label
	_points_label = Label.new()
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.add_theme_font_size_override("font_size", 20)
	_root_vbox.add_child(_points_label)

	# Revert button — only visible after picking something on this screen
	_revert_btn = Button.new()
	_revert_btn.text = "↩  Undo Last Choice"
	_revert_btn.custom_minimum_size = Vector2(240, 44)
	_revert_btn.add_theme_font_size_override("font_size", 16)
	_revert_btn.add_theme_color_override("font_color", Color(1.0, 0.60, 0.30, 1))
	_apply_btn_style(_revert_btn)
	_revert_btn.visible = false
	_revert_btn.pressed.connect(_on_revert_pressed)
	var revert_center := CenterContainer.new()
	revert_center.add_child(_revert_btn)
	_root_vbox.add_child(revert_center)

	# Branch columns
	var cols_container := HBoxContainer.new()
	cols_container.alignment = BoxContainer.ALIGNMENT_CENTER
	cols_container.add_theme_constant_override("separation", 40)
	cols_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(cols_container)

	var hero := HeroDatabase.get_hero(GameManager.current_hero)
	var branches: Array = hero.talent_branch_ids if hero else []
	for branch in branches:
		var col := _make_branch_column(branch)
		_branch_columns[branch] = col
		cols_container.add_child(col)

	# Continue button
	var done_btn := Button.new()
	done_btn.text = "Continue →"
	done_btn.custom_minimum_size = Vector2(300, 60)
	done_btn.add_theme_font_size_override("font_size", 20)
	_apply_btn_style(done_btn)
	done_btn.pressed.connect(_on_done_pressed)

	var btn_center := CenterContainer.new()
	btn_center.add_child(done_btn)
	_root_vbox.add_child(btn_center)

func _make_branch_column(branch: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(480, 0)
	col.add_theme_constant_override("separation", 12)

	# Branch header
	var header := Label.new()
	header.text = TalentDatabase.get_branch_display_name(branch).to_upper()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", BRANCH_COLORS.get(branch, BRANCH_COLOR_DEFAULT))
	col.add_child(header)

	var sep := HSeparator.new()
	col.add_child(sep)

	# Talent buttons (tier 0 → 3)
	var talents := TalentDatabase.get_branch(branch)
	for talent in talents:
		var btn := _make_talent_button(talent)
		_talent_buttons[talent.id] = btn
		col.add_child(btn)

	return col

func _make_talent_button(talent: TalentData) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(460, 90)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_size_override("font_size", 15)
	_apply_btn_style(btn)
	btn.pressed.connect(_on_talent_pressed.bind(talent.id))
	return btn

# ---------------------------------------------------------------------------
# State refresh
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var points := GameManager.talent_points
	var unlocked: Array[String] = GameManager.unlocked_talents
	var available := TalentDatabase.get_available(unlocked)
	var available_ids: Array[String] = []
	for t in available:
		available_ids.append(t.id)

	# Show revert only when something was picked on this screen
	_revert_btn.visible = GameManager.unlocked_talents.size() > _entry_talents.size()

	# Update points label
	if points > 0:
		_points_label.text = "Talent Points Available: %d  — Click a talent to unlock it" % points
		_points_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1))
	else:
		_points_label.text = "No talent points remaining. Press Continue to proceed."
		_points_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65, 1))

	# Update each talent button
	for id in _talent_buttons:
		var btn: Button = _talent_buttons[id]
		var talent: TalentData = TalentDatabase.get_talent(id)
		var tier_label := "★★★★".substr(0, talent.tier + 1)  # ★ = tier 0, ★★ = tier 1, etc.
		var capstone_tag := "  [CAPSTONE]" if talent.tier == 3 else ""
		btn.text = "%s  %s%s\n%s" % [tier_label, talent.talent_name, capstone_tag, talent.description]

		if id in unlocked:
			btn.disabled = true
			btn.modulate = Color(0.3, 0.9, 0.3, 1)   # green = owned
		elif id in available_ids and points > 0:
			btn.disabled = false
			btn.modulate = Color(1, 1, 1, 1)           # bright = clickable
		elif id in available_ids:
			btn.disabled = true
			btn.modulate = Color(0.6, 0.6, 0.6, 1)    # greyed = no points
		else:
			btn.disabled = true
			btn.modulate = Color(0.28, 0.22, 0.35, 1)  # dark = locked

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_talent_pressed(id: String) -> void:
	GameManager.unlock_talent(id)
	_refresh()

func _on_revert_pressed() -> void:
	GameManager.unlocked_talents = _entry_talents.duplicate()
	GameManager.talent_points    = _entry_points
	_refresh()

func _on_done_pressed() -> void:
	if not GameManager.deck_built:
		GameManager.go_to_scene("res://ui/DeckBuilderScene.tscn")
	else:
		GameManager.go_to_scene("res://map/EncounterLoadingScene.tscn")

# ---------------------------------------------------------------------------
# Button style helpers
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
