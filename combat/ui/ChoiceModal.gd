## ChoiceModal.gd
## Generic 2–4 option choice modal for spell cast-time runtime parameters.
##
## Built programmatically (no .tscn) so callers don't need to load a scene file.
## Caller fills in a prompt label and a list of option dicts, calls `show_modal`,
## and awaits `choice_made` for the picked value.
##
## Usage:
##   var modal := ChoiceModal.new()
##   add_child(modal)
##   modal.show_modal("Choose a race", [{"label": "Human", "value": "human"},
##                                       {"label": "Demon", "value": "demon"}])
##   var picked: String = await modal.choice_made
##   modal.queue_free()
##
## Currently used by Rally the Ranks for the dual-tag race picker; designed to
## be reused for any future "spell needs a runtime parameter" use case.
class_name ChoiceModal
extends Control

## Emitted when the player clicks one of the option buttons. Carries the chosen
## option's `value` field (caller decides the value type — usually String).
signal choice_made(value)

const _PANEL_MIN_WIDTH := 480
const _BUTTON_MIN_HEIGHT := 64

var _panel: PanelContainer
var _prompt_label: Label
var _button_row: HBoxContainer

func _ready() -> void:
	# Fullscreen blocker — eat all input below this Control so the rest of the
	# board is non-interactive while the choice is pending. anchor_*_right=1.0
	# makes the Control fill its parent.
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Translucent dim layer covering the whole screen.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Centered panel container holding prompt + buttons.
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(_PANEL_MIN_WIDTH, 0)
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_prompt_label)

	_button_row = HBoxContainer.new()
	_button_row.add_theme_constant_override("separation", 12)
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_button_row)

## Populate the prompt and option buttons, then make the modal visible. Caller
## should `await modal.choice_made` to receive the picked value.
## options: Array of dicts shaped {"label": String, "value": Variant}.
func show_modal(prompt: String, options: Array) -> void:
	_prompt_label.text = prompt
	# Clear any previous buttons so the same modal instance can be reused.
	for child in _button_row.get_children():
		child.queue_free()
	for opt in options:
		var btn := Button.new()
		btn.text = opt.get("label", "?")
		btn.custom_minimum_size = Vector2(140, _BUTTON_MIN_HEIGHT)
		btn.add_theme_font_size_override("font_size", 18)
		var captured_value = opt.get("value")
		btn.pressed.connect(func() -> void: _on_picked(captured_value))
		_button_row.add_child(btn)
	visible = true

func _on_picked(value) -> void:
	visible = false
	choice_made.emit(value)
