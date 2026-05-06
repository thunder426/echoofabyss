## EscMenu.gd
## Global pause menu — press ESC from any scene to open.
## Built in code at autoload init so it overlays every scene without per-scene wiring.
extends CanvasLayer

const _BTN_PATH         := "res://assets/art/buttons/button_normal.png"
const _BTN_HOVER_PATH   := "res://assets/art/buttons/button_hover.png"
const _BTN_PRESSED_PATH := "res://assets/art/buttons/button_pressed.png"
const _FONT_PATH        := "res://assets/fonts/cinzel/CinzelDecorative-Bold.ttf"
const _MAIN_MENU_PATH   := "res://ui/MainMenu.tscn"

var _root: Control
var _dim: ColorRect
var _panel: VBoxContainer
var _resume_btn: Button
var _main_menu_btn: Button
var _quit_btn: Button

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide_menu()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_ESCAPE:
		return
	if _root.visible:
		_on_resume_pressed()
	else:
		if _is_on_main_menu():
			return
		show_menu()
	get_viewport().set_input_as_handled()

func show_menu() -> void:
	_root.visible = true
	get_tree().paused = true
	_resume_btn.grab_focus()

func hide_menu() -> void:
	_root.visible = false
	get_tree().paused = false

func _is_on_main_menu() -> bool:
	var current := get_tree().current_scene
	if current == null:
		return false
	return current.scene_file_path == _MAIN_MENU_PATH

func _on_resume_pressed() -> void:
	hide_menu()

func _on_main_menu_pressed() -> void:
	hide_menu()
	GameManager.go_to_scene(_MAIN_MENU_PATH)

func _on_quit_pressed() -> void:
	get_tree().quit()

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, 0.7)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_panel = VBoxContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(420, 0)
	_panel.add_theme_constant_override("separation", 24)
	_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(_panel)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ResourceLoader.exists(_FONT_PATH):
		title.add_theme_font_override("font", load(_FONT_PATH))
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0, 1.0))
	_panel.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	_panel.add_child(spacer)

	_resume_btn = _make_button("Resume")
	_resume_btn.pressed.connect(_on_resume_pressed)
	_panel.add_child(_resume_btn)

	_main_menu_btn = _make_button("Back to Main Menu")
	_main_menu_btn.pressed.connect(_on_main_menu_pressed)
	_panel.add_child(_main_menu_btn)

	_quit_btn = _make_button("Quit Game")
	_quit_btn.pressed.connect(_on_quit_pressed)
	_panel.add_child(_quit_btn)

	# After hierarchy attaches, position the panel by hand (PRESET_CENTER on a
	# VBoxContainer is unreliable until first layout — anchor via offsets).
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.offset_left = -210
	_panel.offset_right = 210
	_panel.offset_top = 320
	_panel.offset_bottom = 320

func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(420, 80)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(_FONT_PATH):
		btn.add_theme_font_override("font", load(_FONT_PATH))
	btn.add_theme_font_size_override("font_size", 28)
	btn.add_theme_color_override("font_color", Color(0.95, 0.9, 1.0, 1.0))
	if ResourceLoader.exists(_BTN_PATH):
		btn.add_theme_stylebox_override("normal",  _make_btn_style(_BTN_PATH))
		var hover_path: String = _BTN_HOVER_PATH if ResourceLoader.exists(_BTN_HOVER_PATH) else _BTN_PATH
		var pressed_path: String = _BTN_PRESSED_PATH if ResourceLoader.exists(_BTN_PRESSED_PATH) else _BTN_PATH
		btn.add_theme_stylebox_override("hover",   _make_btn_style(hover_path))
		btn.add_theme_stylebox_override("pressed", _make_btn_style(pressed_path))
	return btn

func _make_btn_style(path: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(path)
	style.texture_margin_left   = 16.0
	style.texture_margin_top    = 16.0
	style.texture_margin_right  = 16.0
	style.texture_margin_bottom = 16.0
	return style
