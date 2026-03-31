## MainMenu.gd
## Title screen — Continue Run, New Run, Collection, or Quit.
extends Node2D

var _continue_btn: Button
var _reset_btn: Button
var _reset_confirm_pending: bool = false
var _reset_timer: SceneTreeTimer = null
var _bg_active: VideoStreamPlayer
var _bg_standby: VideoStreamPlayer
const _BG_SWAP_MARGIN: float = 0.15

const _BG_PATH          := "res://assets/menu/menu_background.png"
const _BTN_PATH         := "res://assets/art/buttons/button_normal.png"
const _BTN_HOVER_PATH   := "res://assets/art/buttons/button_hover.png"
const _BTN_PRESSED_PATH := "res://assets/art/buttons/button_pressed.png"

func _ready() -> void:
	# Load permanent unlocks (and run state if any) from disk.
	UserProfile.load_profile()

	_apply_menu_assets()

	_bg_active = $UI/BackgroundA
	_bg_standby = $UI/BackgroundB
	_bg_active.finished.connect(_on_bg_finished)

	_continue_btn = $UI/ContinueButton
	_reset_btn    = $UI/ResetButton
	$UI/NewRunButton.pressed.connect(_on_new_run_pressed)
	_continue_btn.pressed.connect(_on_continue_pressed)
	$UI/CollectionButton.pressed.connect(_on_collection_pressed)
	_reset_btn.pressed.connect(_on_reset_pressed)
	$UI/QuitButton.pressed.connect(_on_quit_pressed)

	# Enable Continue only when a saved run exists.
	_continue_btn.disabled = not UserProfile.has_active_run()
	if _continue_btn.disabled:
		_continue_btn.modulate = Color(0.45, 0.45, 0.50, 1)

func _process(_delta: float) -> void:
	if not _bg_active.is_playing():
		return
	var remaining: float = _bg_active.get_stream_length() - _bg_active.stream_position
	if remaining <= _BG_SWAP_MARGIN and not _bg_standby.is_playing():
		_bg_standby.visible = true
		_bg_standby.play()

func _on_bg_finished() -> void:
	_bg_active.stop()
	_bg_active.visible = false
	# Swap roles
	var tmp: VideoStreamPlayer = _bg_active
	_bg_active = _bg_standby
	_bg_standby = tmp
	_bg_active.finished.connect(_on_bg_finished)
	_bg_standby.finished.disconnect(_on_bg_finished)

func _on_new_run_pressed() -> void:
	# Discard any saved run (permanent unlocks are kept).
	UserProfile.clear_run()
	GameManager.start_new_run()
	GameManager.go_to_scene("res://ui/HeroSelectScene.tscn")

func _on_continue_pressed() -> void:
	# State already loaded by UserProfile.load_profile() in _ready.
	# Route to the right scene based on where the player left off.
	if not GameManager.deck_built:
		GameManager.go_to_scene("res://ui/DeckBuilderScene.tscn")
	elif GameManager.talent_points > 0:
		GameManager.go_to_scene("res://talents/TalentSelectScene.tscn")
	else:
		GameManager.go_to_scene("res://map/EncounterLoadingScene.tscn")

func _on_collection_pressed() -> void:
	GameManager.go_to_scene("res://ui/CollectionScene.tscn")

func _on_reset_pressed() -> void:
	if not _reset_confirm_pending:
		# First press — ask for confirmation.
		_reset_confirm_pending = true
		_reset_btn.text = "CONFIRM RESET? (click again)"
		_reset_btn.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25, 1))
		# Auto-cancel after 3 seconds if not confirmed.
		_reset_timer = get_tree().create_timer(3.0)
		_reset_timer.timeout.connect(_cancel_reset)
	else:
		# Second press — wipe everything.
		_cancel_reset()
		UserProfile.reset_all()
		# Reflect cleared state in the UI.
		_continue_btn.disabled = true
		_continue_btn.modulate = Color(0.45, 0.45, 0.50, 1)

func _cancel_reset() -> void:
	_reset_confirm_pending = false
	_reset_btn.text = "Reset All Progress"
	_reset_btn.add_theme_color_override("font_color", Color(0.55, 0.30, 0.30, 1))

func _on_quit_pressed() -> void:
	get_tree().quit()

func _make_btn_style(path: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(path)
	style.texture_margin_left   = 16.0
	style.texture_margin_top    = 16.0
	style.texture_margin_right  = 16.0
	style.texture_margin_bottom = 16.0
	return style

func _apply_menu_assets() -> void:
	if ResourceLoader.exists(_BTN_PATH):
		var style_normal := _make_btn_style(_BTN_PATH)
		var style_hover  := _make_btn_style(_BTN_HOVER_PATH   if ResourceLoader.exists(_BTN_HOVER_PATH)   else _BTN_PATH)
		var style_pressed := _make_btn_style(_BTN_PRESSED_PATH if ResourceLoader.exists(_BTN_PRESSED_PATH) else _BTN_PATH)
		for btn in [$UI/NewRunButton, $UI/ContinueButton,
				$UI/CollectionButton, $UI/QuitButton, $UI/ResetButton]:
			(btn as Button).add_theme_stylebox_override("normal",   style_normal)
			(btn as Button).add_theme_stylebox_override("hover",    style_hover)
			(btn as Button).add_theme_stylebox_override("pressed",  style_pressed)
			(btn as Button).add_theme_stylebox_override("disabled", style_normal)
