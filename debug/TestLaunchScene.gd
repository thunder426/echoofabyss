## TestLaunchScene.gd
## Developer-only scene for setting up and launching test combats.
## Entire UI is built in code — no .tscn needed beyond the root node.
## Add to project autoload OR navigate to it directly during development.
extends Control

# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _hand_input:          LineEdit
var _player_deck_input:   LineEdit
var _player_board_input:  LineEdit
var _enemy_board_input:   LineEdit
var _enemy_deck_input:    LineEdit
var _enemy_name_input:    LineEdit
var _player_hp_input:    SpinBox
var _enemy_hp_input:     SpinBox
var _inf_res_check:      CheckBox
var _status_label:       Label

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	_preset_full_hand()  # sensible defaults so Launch works immediately

func _build_ui() -> void:
	# Full-screen dark background
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Centered scroll container
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_CENTER)
	scroll.custom_minimum_size = Vector2(560, 700)
	scroll.offset_left   = -280
	scroll.offset_top    = -350
	scroll.offset_right  = 280
	scroll.offset_bottom = 350
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(540, 0)
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "⚙  Test Combat Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	vbox.add_child(title)

	vbox.add_child(_sep())

	# Input rows
	_hand_input         = _add_row(vbox, "Player Hand (card IDs, comma-separated):",
								   "arcane_strike, void_rune")
	_player_deck_input  = _add_row(vbox, "Player Deck (card IDs, draw pile — leave blank for no deck):", "")
	_player_board_input = _add_row(vbox, "Player Board (card IDs, pre-summoned):",
								   "shadow_hound")
	_enemy_board_input  = _add_row(vbox, "Enemy Board (card IDs, pre-summoned):",
								   "abyssal_brute")
	_enemy_deck_input   = _add_row(vbox, "Enemy Deck (card IDs, leave blank for passive enemy):", "")
	_enemy_name_input   = _add_row(vbox, "Enemy Name:", "Training Dummy")

	vbox.add_child(_sep())

	# HP spin boxes
	_player_hp_input = _add_spinbox(vbox, "Player HP (0 = default 3000):", 0, 0, 99999)
	_enemy_hp_input  = _add_spinbox(vbox, "Enemy HP (0 = default 2000):",  0, 0, 99999)

	# Infinite resources checkbox
	_inf_res_check = CheckBox.new()
	_inf_res_check.text = "Infinite Resources (player starts with max essence + mana every turn)"
	_inf_res_check.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_inf_res_check)

	vbox.add_child(_sep())

	# Quick-fill presets
	var preset_label := Label.new()
	preset_label.text = "Quick Presets:"
	preset_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(preset_label)

	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	vbox.add_child(presets)

	_preset_btn(presets, "Empty Board",   _preset_empty)
	_preset_btn(presets, "Full Hand",     _preset_full_hand)
	_preset_btn(presets, "Board Fight",   _preset_board_fight)

	vbox.add_child(_sep())

	# Launch button
	var launch_btn := Button.new()
	launch_btn.text = "▶  Launch Test Combat"
	launch_btn.custom_minimum_size = Vector2(0, 50)
	launch_btn.add_theme_font_size_override("font_size", 18)
	launch_btn.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4))
	launch_btn.pressed.connect(_on_launch_pressed)
	vbox.add_child(launch_btn)

	# Balance Simulator button
	var sim_btn := Button.new()
	sim_btn.text = "⚔  Balance Simulator"
	sim_btn.pressed.connect(func(): GameManager.go_to_scene("res://debug/BalanceSim.tscn"))
	vbox.add_child(sim_btn)

	# Back button
	var back_btn := Button.new()
	back_btn.text = "← Back to Main Menu"
	back_btn.pressed.connect(func(): GameManager.go_to_scene("res://ui/MainMenu.tscn"))
	vbox.add_child(back_btn)

	# Status label
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	vbox.add_child(_status_label)

# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

func _on_launch_pressed() -> void:
	_status_label.text = ""

	TestConfig.reset()
	TestConfig.hand_cards         = _parse_ids(_hand_input.text)
	TestConfig.player_deck_cards  = _parse_ids(_player_deck_input.text)
	TestConfig.player_board_cards = _parse_ids(_player_board_input.text)
	TestConfig.enemy_board_cards  = _parse_ids(_enemy_board_input.text)
	TestConfig.enemy_deck         = _parse_ids(_enemy_deck_input.text)
	TestConfig.enemy_name         = _enemy_name_input.text.strip_edges()
	TestConfig.player_hp          = int(_player_hp_input.value)
	TestConfig.enemy_hp           = int(_enemy_hp_input.value)
	TestConfig.infinite_resources = _inf_res_check.button_pressed

	# Validate card IDs
	var all_ids := TestConfig.hand_cards + TestConfig.player_deck_cards + TestConfig.player_board_cards + TestConfig.enemy_board_cards + TestConfig.enemy_deck
	var bad: Array[String] = []
	for id in all_ids:
		if id != "" and CardDatabase.get_card(id) == null:
			bad.append(id)
	if not bad.is_empty():
		_status_label.text = "Unknown card IDs: " + ", ".join(bad)
		return

	TestConfig.launch()

# ---------------------------------------------------------------------------
# Presets
# ---------------------------------------------------------------------------

func _preset_empty() -> void:
	_hand_input.text          = ""
	_player_deck_input.text   = ""
	_player_board_input.text  = ""
	_enemy_board_input.text   = ""
	_enemy_name_input.text    = "Training Dummy"
	_player_hp_input.value    = 3000
	_enemy_hp_input.value     = 500

func _preset_full_hand() -> void:
	_hand_input.text          = "smoke_veil, hidden_ambush, silence_trap, death_trap"
	_player_deck_input.text   = ""
	_player_board_input.text  = ""
	_enemy_board_input.text   = "shadow_hound, abyssal_brute"
	_enemy_name_input.text    = "Training Dummy"
	_player_hp_input.value    = 3000
	_enemy_hp_input.value     = 2000

func _preset_board_fight() -> void:
	_hand_input.text          = "arcane_strike, blood_pact"
	_player_deck_input.text   = ""
	_player_board_input.text  = "void_imp, shadow_hound, abyssal_brute"
	_enemy_board_input.text   = "abyssal_brute, void_stalker"
	_enemy_name_input.text    = "Sparring Partner"
	_player_hp_input.value    = 3000
	_enemy_hp_input.value     = 3000

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _add_row(parent: VBoxContainer, label_text: String, placeholder: String) -> LineEdit:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	parent.add_child(lbl)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 34)
	parent.add_child(edit)
	return edit

func _add_spinbox(parent: VBoxContainer, label_text: String, default_val: float, min_val: float, max_val: float) -> SpinBox:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(280, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hbox.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value     = default_val
	spin.step      = 100
	spin.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(spin)
	return spin

func _preset_btn(parent: HBoxContainer, label: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _sep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 4)
	return s

func _parse_ids(text: String) -> Array[String]:
	var result: Array[String] = []
	for part in text.split(","):
		var id := part.strip_edges()
		if id != "":
			result.append(id)
	return result
