## TestLaunchScene.gd
## Developer-only scene for setting up and launching test combats.
## Entire UI is built in code — no .tscn needed beyond the root node.
## Add to project autoload OR navigate to it directly during development.
extends Control

# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

# Preset-carried state (not exposed as UI fields since rarely tweaked)
var _preset_ai_profile:   String = ""
var _preset_passives:     Array[String] = []
var _preset_enemy_start_essence_max: int = 0
var _preset_enemy_start_mana_max:    int = 0

var _hand_input:          LineEdit
var _player_deck_input:   LineEdit
var _player_board_input:  LineEdit
var _enemy_hand_input:    LineEdit
var _enemy_board_input:   LineEdit
var _player_traps_input:  LineEdit
var _enemy_traps_input:   LineEdit
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
	_preset_card_test()  # sensible defaults so Launch works immediately

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
	_enemy_hand_input   = _add_row(vbox, "Enemy Hand (card IDs, added to enemy hand):", "")
	_player_traps_input = _add_row(vbox, "Player Traps (trap IDs, pre-placed):", "")
	_enemy_traps_input  = _add_row(vbox, "Enemy Traps (trap IDs, pre-placed):", "")
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

	# Quick-fill presets (dropdown)
	var preset_label := Label.new()
	preset_label.text = "Quick Presets:"
	preset_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(preset_label)

	var preset_dropdown := OptionButton.new()
	preset_dropdown.add_theme_font_size_override("font_size", 14)
	preset_dropdown.custom_minimum_size = Vector2(0, 36)
	preset_dropdown.add_item("Card Test",            0)
	preset_dropdown.add_item("Empty Board",          1)
	preset_dropdown.add_item("Full Hand",            2)
	preset_dropdown.add_item("Board Fight",          3)
	preset_dropdown.add_item("Spirit Fuel",          4)
	preset_dropdown.add_item("Act 3 Spirits",        5)
	preset_dropdown.add_item("Act 3 Spells",         6)
	preset_dropdown.add_item("Void Screech VFX",     7)
	preset_dropdown.add_item("Abyssal Plague VFX",   8)
	preset_dropdown.add_item("Void Bolt VFX",        9)
	preset_dropdown.item_selected.connect(_on_preset_selected)
	vbox.add_child(preset_dropdown)

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

func _on_preset_selected(index: int) -> void:
	# Default: clear AI profile / passives; individual presets override as needed
	_preset_ai_profile = ""
	_preset_passives   = []
	_preset_enemy_start_essence_max = 0
	_preset_enemy_start_mana_max    = 0
	match index:
		0: _preset_card_test()
		1: _preset_empty()
		2: _preset_full_hand()
		3: _preset_board_fight()
		4: _preset_spirit_fuel()
		5: _preset_act3_spirits()
		6: _preset_act3_spells()
		7: _preset_void_screech_vfx()
		8: _preset_abyssal_plague_vfx()
		9: _preset_void_bolt_vfx()

func _on_launch_pressed() -> void:
	_status_label.text = ""

	TestConfig.reset()
	TestConfig.hand_cards         = _parse_ids(_hand_input.text)
	TestConfig.player_deck_cards  = _parse_ids(_player_deck_input.text)
	TestConfig.player_board_cards = _parse_ids(_player_board_input.text)
	TestConfig.enemy_board_cards  = _parse_ids(_enemy_board_input.text)
	TestConfig.enemy_hand_cards   = _parse_ids(_enemy_hand_input.text)
	TestConfig.player_traps       = _parse_ids(_player_traps_input.text)
	TestConfig.enemy_traps        = _parse_ids(_enemy_traps_input.text)
	TestConfig.enemy_deck         = _parse_ids(_enemy_deck_input.text)
	TestConfig.enemy_name         = _enemy_name_input.text.strip_edges()
	TestConfig.player_hp          = int(_player_hp_input.value)
	TestConfig.enemy_hp           = int(_enemy_hp_input.value)
	TestConfig.infinite_resources = _inf_res_check.button_pressed
	TestConfig.enemy_ai_profile   = _preset_ai_profile
	TestConfig.enemy_passives     = _preset_passives.duplicate()
	TestConfig.enemy_start_essence_max = _preset_enemy_start_essence_max
	TestConfig.enemy_start_mana_max    = _preset_enemy_start_mana_max

	# Validate card IDs
	var all_ids := TestConfig.hand_cards + TestConfig.player_deck_cards + TestConfig.player_board_cards + TestConfig.enemy_board_cards + TestConfig.enemy_hand_cards + TestConfig.player_traps + TestConfig.enemy_traps + TestConfig.enemy_deck
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

## Card Test — generic preset with enemy targets on board, infinite resources,
## and high HP. Claude command fills hand_input / enemy_hand_input before launch.
func _preset_card_test() -> void:
	_preset_ai_profile        = "matriarch"
	_preset_passives          = []
	_hand_input.text          = "abyssal_plague, abyssal_plague, abyssal_plague"
	_player_deck_input.text   = ""
	_player_board_input.text  = ""
	_enemy_hand_input.text    = "brood_call, brood_call, brood_call"
	_enemy_board_input.text   = ""
	_player_traps_input.text  = ""
	_enemy_traps_input.text   = ""
	_enemy_deck_input.text    = "brood_call, brood_call, brood_call, brood_call, brood_call, brood_call"
	_preset_enemy_start_essence_max = 0
	_preset_enemy_start_mana_max    = 2
	_enemy_name_input.text    = "Card Test Dummy"
	_player_hp_input.value    = 9999
	_enemy_hp_input.value     = 9999
	_inf_res_check.button_pressed = true

func _preset_empty() -> void:
	_hand_input.text          = ""
	_player_deck_input.text   = ""
	_player_board_input.text  = ""
	_enemy_hand_input.text    = ""
	_enemy_board_input.text   = ""
	_player_traps_input.text  = ""
	_enemy_traps_input.text   = ""
	_enemy_name_input.text    = "Training Dummy"
	_player_hp_input.value    = 3000
	_enemy_hp_input.value     = 500

func _preset_full_hand() -> void:
	_hand_input.text          = "smoke_veil, hidden_ambush, silence_trap, death_trap"
	_player_deck_input.text   = ""
	_player_board_input.text  = ""
	_enemy_hand_input.text    = ""
	_enemy_board_input.text   = "shadow_hound, abyssal_brute"
	_player_traps_input.text  = ""
	_enemy_traps_input.text   = ""
	_enemy_name_input.text    = "Training Dummy"
	_player_hp_input.value    = 3000
	_enemy_hp_input.value     = 2000

func _preset_board_fight() -> void:
	_hand_input.text          = "arcane_strike, blood_pact"
	_player_deck_input.text   = ""
	_player_board_input.text  = "void_imp, shadow_hound, abyssal_brute"
	_enemy_hand_input.text    = ""
	_enemy_board_input.text   = "abyssal_brute, void_stalker"
	_player_traps_input.text  = ""
	_enemy_traps_input.text   = ""
	_enemy_name_input.text    = "Sparring Partner"
	_player_hp_input.value    = 3000
	_enemy_hp_input.value     = 3000

func _preset_act3_spells() -> void:
	_hand_input.text          = "void_shatter, spirit_surge, void_wind, void_pulse, rift_collapse, dimensional_breach"
	_player_deck_input.text   = "phase_stalker, void_behemoth, void_rift_lord, rift_warden, phase_stalker, void_behemoth"
	_player_board_input.text  = ""
	_enemy_hand_input.text    = ""
	_enemy_board_input.text   = "void_echo, rift_tender, hollow_sentinel, void_resonance"
	_player_traps_input.text  = ""
	_enemy_traps_input.text   = "hidden_ambush, smoke_veil"
	_enemy_deck_input.text    = "phase_disruptor, void_shatter, spirit_surge, void_wind, void_echo, rift_tender, hollow_sentinel, riftscarred_colossus"
	_enemy_name_input.text    = "Void Rift Spell Test"
	_player_hp_input.value    = 3000
	_enemy_hp_input.value     = 5000
	_inf_res_check.button_pressed = true

func _preset_act3_spirits() -> void:
	_hand_input.text          = "void_resonance, void_echo, hollow_sentinel, phase_disruptor, rift_warden, ethereal_titan, riftscarred_colossus, void_architect, rift_tender"
	_player_deck_input.text   = "void_echo, void_resonance, hollow_sentinel, phase_disruptor, rift_tender, riftscarred_colossus, ethereal_titan"
	_player_board_input.text  = ""
	_enemy_hand_input.text    = ""
	_enemy_board_input.text   = "void_echo, hollow_sentinel, rift_tender"
	_player_traps_input.text  = ""
	_enemy_traps_input.text   = ""
	_enemy_deck_input.text    = "void_resonance, void_resonance, void_echo, void_echo, hollow_sentinel, phase_disruptor, rift_tender, rift_tender, riftscarred_colossus, void_architect, rift_warden, ethereal_titan"
	_enemy_name_input.text    = "Void Rift Spirit Test"
	_player_hp_input.value    = 3000
	_enemy_hp_input.value     = 5000
	_inf_res_check.button_pressed = true

## Void Screech VFX test — enemy board pre-loaded with 3 feral imps, hand full
## of Void Screech. Enemy uses feral_pack AI which will cast void_screech every
## turn (gate `board_full_or_no_minions_in_hand` is true: hand has no minions).
## With 3 feral imps on board, chorus mode triggers — 3 rings converging on hero.
func _preset_void_screech_vfx() -> void:
	_preset_ai_profile        = "feral_pack"
	_preset_passives          = ["pack_instinct"]
	_hand_input.text          = ""
	_player_deck_input.text   = ""
	_player_board_input.text  = ""
	_enemy_hand_input.text    = ""
	_enemy_board_input.text   = "rabid_imp, brood_imp, imp_brawler"
	_player_traps_input.text  = ""
	_enemy_traps_input.text   = ""
	_enemy_deck_input.text    = "void_screech, void_screech, void_screech, void_screech, void_screech, void_screech, void_screech, void_screech"
	_enemy_name_input.text    = "Screech VFX Test"
	_player_hp_input.value    = 9999
	_enemy_hp_input.value     = 9999
	_inf_res_check.button_pressed = false

## Abyssal Plague VFX test — player has abyssal_plague in hand, enemy has 3-4
## minions on board to infect. Infinite resources so you can spam the spell.
func _preset_abyssal_plague_vfx() -> void:
	_preset_ai_profile        = ""
	_preset_passives          = []
	_hand_input.text          = "abyssal_plague, abyssal_plague, abyssal_plague, abyssal_plague"
	_player_deck_input.text   = "abyssal_plague, abyssal_plague, abyssal_plague, abyssal_plague"
	_player_board_input.text  = ""
	_enemy_hand_input.text    = ""
	_enemy_board_input.text   = "shadow_hound, abyssal_brute, void_stalker, abyss_cultist"
	_player_traps_input.text  = ""
	_enemy_traps_input.text   = ""
	_enemy_deck_input.text    = ""
	_enemy_name_input.text    = "Plague VFX Test"
	_player_hp_input.value    = 9999
	_enemy_hp_input.value     = 9999
	_inf_res_check.button_pressed = true

## Void Bolt VFX test — player has void_bolt spells to spam at the enemy hero.
## Infinite resources so you can cast every turn without worrying about mana.
func _preset_void_bolt_vfx() -> void:
	_preset_ai_profile        = ""
	_preset_passives          = []
	_hand_input.text          = "void_bolt, void_bolt, void_bolt, void_bolt"
	_player_deck_input.text   = "void_bolt, void_bolt, void_bolt, void_bolt"
	_player_board_input.text  = ""
	_enemy_hand_input.text    = ""
	_enemy_board_input.text   = ""
	_player_traps_input.text  = ""
	_enemy_traps_input.text   = ""
	_enemy_deck_input.text    = ""
	_enemy_name_input.text    = "Void Bolt VFX Test"
	_player_hp_input.value    = 9999
	_enemy_hp_input.value     = 9999
	_inf_res_check.button_pressed = true

func _preset_spirit_fuel() -> void:
	_hand_input.text          = "void_wisp, void_shade, void_wraith, void_revenant, bastion_colossus, sovereigns_decree, thrones_command, sovereigns_edict, sovereigns_herald"
	_player_deck_input.text   = "phase_stalker, void_pulse, rift_collapse, void_behemoth"
	_player_board_input.text  = ""
	_enemy_hand_input.text    = ""
	_enemy_board_input.text   = "void_wisp, void_shade, void_wraith"
	_player_traps_input.text  = ""
	_enemy_traps_input.text   = ""
	_enemy_deck_input.text    = "bastion_colossus, sovereigns_decree, thrones_command, phase_stalker, void_pulse"
	_enemy_name_input.text    = "Spirit Test"
	_player_hp_input.value    = 3000
	_enemy_hp_input.value     = 5000
	_inf_res_check.button_pressed = true

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
