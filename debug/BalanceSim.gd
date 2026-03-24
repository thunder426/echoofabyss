## BalanceSim.gd
## Interactive headless combat simulator for balance testing.
## UI is built entirely in code — no .tscn content beyond the root node.
##
## How to open: navigate to res://debug/BalanceSim.tscn in the editor and run it,
## or add a button in TestLaunchScene that changes scene to it.
extends Control

# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _player_deck_input:  LineEdit
var _enemy_deck_input:   LineEdit
var _player_hp_input:    SpinBox
var _enemy_hp_input:     SpinBox
var _talents_input:      LineEdit
var _runs_input:         SpinBox
var _profile_button:     OptionButton
var _run_button:         Button
var _run_all_button:     Button
var _clear_button:       Button
var _log:                RichTextLabel

# ---------------------------------------------------------------------------
# Profile list (must match CombatSim._ENEMY_PROFILES keys)
# ---------------------------------------------------------------------------

const _PROFILES: Array[String] = ["feral_pack", "corrupted_brood", "default"]

# ---------------------------------------------------------------------------
# Default test deck
# ---------------------------------------------------------------------------

const _DEFAULT_DECK := "void_imp,void_imp,shadow_hound,shadow_hound,abyssal_brute,void_bolt,void_bolt"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.10, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Outer layout
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)

	# ── Title bar ──────────────────────────────────────────────────────────
	var title_bar := _make_panel(Color(0.10, 0.10, 0.16))
	title_bar.custom_minimum_size.y = 40
	outer.add_child(title_bar)

	var title_label := Label.new()
	title_label.text = "⚔  Balance Simulator"
	title_label.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	title_label.offset_left = 12
	title_label.offset_right = 400
	title_bar.add_child(title_label)

	# ── Main split: controls left, log right ───────────────────────────────
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 340
	outer.add_child(split)

	# Left panel — inputs
	var left := ScrollContainer.new()
	left.custom_minimum_size.x = 320
	split.add_child(left)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size.x = 310
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(vbox)

	# Padding
	var pad := Control.new()
	pad.custom_minimum_size.y = 8
	vbox.add_child(pad)

	# Inputs
	_player_deck_input = _add_lineedit(vbox, "Player deck (comma-separated IDs):", _DEFAULT_DECK)
	_enemy_deck_input  = _add_lineedit(vbox, "Enemy deck (blank = profile fallback):", "")
	_player_hp_input   = _add_spinbox(vbox,  "Player HP:", 3000, 100, 99999, 100)
	_enemy_hp_input    = _add_spinbox(vbox,  "Enemy HP:",  2000, 100, 99999, 100)
	_talents_input     = _add_lineedit(vbox, "Player talents (comma-separated):", "")
	_runs_input        = _add_spinbox(vbox,  "Simulations:", 100, 1, 10000, 50)

	# Profile selector
	vbox.add_child(_make_label("Enemy profile:"))
	_profile_button = OptionButton.new()
	for p in _PROFILES:
		_profile_button.add_item(p)
	_profile_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_profile_button)

	# Buttons
	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_box)

	_run_button = Button.new()
	_run_button.text = "▶  Run Selected"
	_run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_button.pressed.connect(_on_run_pressed)
	btn_box.add_child(_run_button)

	_run_all_button = Button.new()
	_run_all_button.text = "▶▶  Run All Profiles"
	_run_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_all_button.pressed.connect(_on_run_all_pressed)
	btn_box.add_child(_run_all_button)

	_clear_button = Button.new()
	_clear_button.text = "🗑 Clear"
	_clear_button.pressed.connect(func(): _log.clear())
	vbox.add_child(_clear_button)

	# Right panel — log
	var log_panel := _make_panel(Color(0.04, 0.04, 0.08))
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	split.add_child(log_panel)

	_log = RichTextLabel.new()
	_log.bbcode_enabled  = true
	_log.scroll_following = true
	_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log.offset_left   = 8
	_log.offset_top    = 8
	_log.offset_right  = -8
	_log.offset_bottom = -8
	log_panel.add_child(_log)

	_print_line("[color=#888]Balance Simulator ready. Configure inputs and click Run.[/color]")

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _on_run_pressed() -> void:
	var profile := _PROFILES[_profile_button.selected]
	await _run_sim(profile)

func _on_run_all_pressed() -> void:
	for profile in _PROFILES:
		await _run_sim(profile)
	_print_line("")
	_print_line("[color=#aaa]── All profiles done ──[/color]")

# ---------------------------------------------------------------------------
# Core sim runner
# ---------------------------------------------------------------------------

func _run_sim(profile: String) -> void:
	var player_deck := _parse_ids(_player_deck_input.text)
	var enemy_deck  := _parse_ids(_enemy_deck_input.text)
	var talents     := _parse_ids(_talents_input.text)
	var player_hp   := int(_player_hp_input.value)
	var enemy_hp    := int(_enemy_hp_input.value)
	var runs        := int(_runs_input.value)

	if player_deck.is_empty():
		_print_line("[color=#f66]✗ Player deck is empty.[/color]")
		return

	_set_buttons_disabled(true)
	_print_line("")
	_print_line("[color=#ccb]▶ Running %d sims vs [b]%s[/b] …[/color]" % [runs, profile])

	var sim   := CombatSim.new()
	var stats := await sim.run_many(runs, player_deck, profile,
			enemy_deck, player_hp, enemy_hp, talents)

	_print_results(profile, stats)
	_set_buttons_disabled(false)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

func _print_results(profile: String, s: Dictionary) -> void:
	var win_pct:  float = s.win_rate * 100.0
	var loss_pct: float = float(s.losses) / s.count * 100.0
	var draw_pct: float = float(s.draws)  / s.count * 100.0

	var win_col  := "[color=#6f6]" if win_pct > 50 else "[color=#f66]"

	_print_line("[b]%s[/b]  (n=%d)" % [profile, s.count])
	_print_line("  %sWin %.1f%%[/color]   Loss %.1f%%   Draw %.1f%%" % [
		win_col, win_pct, loss_pct, draw_pct])
	_print_line("  Avg turns: [b]%.1f[/b]   Avg player HP: [b]%+.0f[/b]   Avg enemy HP: [b]%+.0f[/b]" % [
		s.avg_turns, s.avg_player_hp, s.avg_enemy_hp])

func _print_line(text: String) -> void:
	_log.append_text(text + "\n")

# ---------------------------------------------------------------------------
# UI factory helpers
# ---------------------------------------------------------------------------

func _add_lineedit(parent: Control, label_text: String, default_text: String) -> LineEdit:
	parent.add_child(_make_label(label_text))
	var le := LineEdit.new()
	le.text = default_text
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(le)
	return le

func _add_spinbox(parent: Control, label_text: String, default_val: float,
		min_val: float, max_val: float, step: float) -> SpinBox:
	parent.add_child(_make_label(label_text))
	var sb := SpinBox.new()
	sb.min_value = min_val
	sb.max_value = max_val
	sb.step      = step
	sb.value     = default_val
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sb)
	return sb

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	return l

func _make_panel(color: Color) -> Panel:
	var p    := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	p.add_theme_stylebox_override("panel", style)
	return p

func _set_buttons_disabled(disabled: bool) -> void:
	_run_button.disabled     = disabled
	_run_all_button.disabled = disabled

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

func _parse_ids(text: String) -> Array[String]:
	var result: Array[String] = []
	for part in text.split(","):
		var id := part.strip_edges()
		if not id.is_empty():
			result.append(id)
	return result
