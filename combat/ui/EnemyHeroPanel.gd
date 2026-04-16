class_name EnemyHeroPanel
extends Control
## Manages the enemy hero status panel UI in combat — name, portrait, HP bar,
## resource stats, void marks, champion progress, and attack/spell targeting highlights.

signal hero_pressed

# -- Scene reference --------------------------------------------------------
var _scene: Node2D = null

# -- Exposed nodes ----------------------------------------------------------
## The border overlay panel drawn on top (sibling in ui_root, not child of self).
var highlight_panel: Panel = null
## The header row so CombatScene can inject passive icons.
var header_row: HBoxContainer = null

# -- HP bar -----------------------------------------------------------------
var _enemy_status_hp_label: Label = null
var _enemy_hp_bar_fill: TextureRect = null
var _enemy_hp_bar_drain: ColorRect = null
var _enemy_hp_bar_bg: Control = null
var _enemy_hp_bar_tween: Tween = null

# -- Resource labels --------------------------------------------------------
var _enemy_status_essence_label: Label = null
var _enemy_status_mana_label: Label = null
var _enemy_status_hand_label: Label = null

# -- Void marks -------------------------------------------------------------
var _enemy_status_marks_row: HBoxContainer = null
var _enemy_status_marks_label: Label = null

# -- Champion progress ------------------------------------------------------
var _champion_progress_row: HBoxContainer = null
var _champion_progress_label: Label = null
var _champion_progress_pips: Array[Label] = []
var _champion_progress_current: int = 0
var _champion_progress_max: int = 0
var _champion_progress_tween: Tween = null

# -- Attack / spell pulse ---------------------------------------------------
var _enemy_hero_attackable: bool = false
var _hero_attack_tween: Tween = null
var _hero_attack_pulse: float = 0.0
var _hero_spell_tween: Tween = null
var _hero_spell_pulse: float = 0.0

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Build the entire enemy hero status panel.  The caller must add `self` to the
## scene tree — this method does NOT add self to `ui_root`.
func setup(scene: Node2D, ui_root: Node) -> void:
	_scene = scene

	# Configure self (replaces the old standalone `panel` Control)
	custom_minimum_size = Vector2(300, 155)
	anchor_left    = 0.5
	anchor_right   = 0.5
	anchor_top     = 0.0
	anchor_bottom  = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_left    = -150.0
	offset_right   = 150.0
	offset_top     = 5.0
	offset_bottom  = 160.0
	mouse_filter   = Control.MOUSE_FILTER_IGNORE

	# Layer 1: dark background
	var bg_fill := Panel.new()
	bg_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_fill.add_theme_stylebox_override("panel", _create_stylebox(Color(0.08, 0.04, 0.13, 0.93), Color(0.55, 0.20, 0.80, 1), 6))
	bg_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_fill)

	# Layer 2: enemy portrait (if available) — clipped to panel bounds
	var enemy_portrait_path: String = GameManager.current_enemy.portrait_path if GameManager.current_enemy else ""
	if enemy_portrait_path != "":
		var portrait_clip := Control.new()
		portrait_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait_clip.clip_contents = true
		portrait_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(portrait_clip)

		var bg_tex := TextureRect.new()
		bg_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_tex.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.texture       = load(enemy_portrait_path)
		bg_tex.modulate      = Color(1, 1, 1, 0.45)
		bg_tex.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		portrait_clip.add_child(bg_tex)

		# Layer 2b: dark overlay so text stays readable over the portrait
		var overlay := ColorRect.new()
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.color = Color(0.0, 0.0, 0.0, 0.45)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_clip.add_child(overlay)

	# Layer 3: content
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	_build_enemy_portrait_row(vbox, ui_root)
	var enemy_bar: Dictionary = _build_hp_bar(vbox, Color(0.85, 0.25, 0.30, 1.0))
	_enemy_hp_bar_fill  = enemy_bar["fill"] as TextureRect
	_enemy_hp_bar_drain = enemy_bar["drain"] as ColorRect
	_enemy_hp_bar_bg    = enemy_bar["bg"] as Control

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	_build_enemy_stats_cols(vbox)

	gui_input.connect(_on_enemy_hero_frame_input)

	# Highlight border — sibling in ui_root, same position as self, drawn on top
	var highlight := Panel.new()
	highlight.anchor_left    = anchor_left
	highlight.anchor_right   = anchor_right
	highlight.anchor_top     = anchor_top
	highlight.anchor_bottom  = anchor_bottom
	highlight.grow_horizontal = grow_horizontal
	highlight.offset_left    = offset_left
	highlight.offset_right   = offset_right
	highlight.offset_top     = offset_top
	highlight.offset_bottom  = offset_bottom
	var blank_style := StyleBoxFlat.new()
	blank_style.bg_color = Color(0, 0, 0, 0)
	blank_style.set_border_width_all(0)
	blank_style.set_corner_radius_all(6)
	highlight.add_theme_stylebox_override("panel", blank_style)
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(highlight)
	highlight_panel = highlight

	_update()

# ---------------------------------------------------------------------------
# Portrait row
# ---------------------------------------------------------------------------

## Build the name header + passive icon row for the enemy status panel.
func _build_enemy_portrait_row(vbox: VBoxContainer, ui_root: Node) -> void:
	header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header_row)

	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.70, 1.0, 1))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	if GameManager.current_enemy:
		var prefix: String = "⚔ BOSS  " if GameManager.is_boss_fight() else ""
		name_lbl.text = prefix + GameManager.current_enemy.enemy_name.to_upper()
	header_row.add_child(name_lbl)

	if not _scene._active_enemy_passives.is_empty():
		_scene._add_enemy_passive_hover_icon(header_row, ui_root)

# ---------------------------------------------------------------------------
# HP bar
# ---------------------------------------------------------------------------

## Build an HP bar with gradient fill, glow edge, and damage-drain layer.
## Returns { fill, drain, bg }.
func _build_hp_bar(parent: VBoxContainer, fill_color: Color) -> Dictionary:
	# Outer container with rounded dark background
	var bar_container := PanelContainer.new()
	bar_container.custom_minimum_size = Vector2(0, 12)
	bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.03, 0.08, 0.8)
	bg_style.border_color = Color(0.25, 0.15, 0.35, 0.6)
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(3)
	bar_container.add_theme_stylebox_override("panel", bg_style)
	parent.add_child(bar_container)

	# Inner clip region
	var bar_clip := Control.new()
	bar_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_clip.clip_contents = true
	bar_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_container.add_child(bar_clip)

	# Drain layer — shows old HP in orange/red gradient, tweens down after damage
	var drain := ColorRect.new()
	drain.anchor_top    = 0.0
	drain.anchor_bottom = 1.0
	drain.anchor_left   = 0.0
	drain.anchor_right  = 1.0
	drain.color = Color(0.95, 0.45, 0.10, 0.85)
	drain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_clip.add_child(drain)

	# Fill layer — gradient from bright top to deeper bottom
	var fill_top: Color = fill_color.lightened(0.35)
	var fill_bot: Color = fill_color.darkened(0.25)
	var fill_grad := Gradient.new()
	fill_grad.set_color(0, fill_top)
	fill_grad.set_color(1, fill_bot)
	var fill_tex := GradientTexture2D.new()
	fill_tex.gradient  = fill_grad
	fill_tex.fill      = GradientTexture2D.FILL_LINEAR
	fill_tex.fill_from = Vector2(0.5, 0.0)
	fill_tex.fill_to   = Vector2(0.5, 1.0)
	fill_tex.width     = 4
	fill_tex.height    = 12

	var fill := TextureRect.new()
	fill.anchor_top    = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_left   = 0.0
	fill.anchor_right  = 1.0
	fill.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode  = TextureRect.STRETCH_SCALE
	fill.texture       = fill_tex
	fill.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	bar_clip.add_child(fill)

	# Glow highlight along top edge
	var glow := ColorRect.new()
	glow.anchor_left   = 0.0
	glow.anchor_right  = 1.0
	glow.anchor_top    = 0.0
	glow.anchor_bottom = 0.0
	glow.offset_bottom = 3
	glow.color = Color(1, 1, 1, 0.2)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.add_child(glow)

	return { "fill": fill, "drain": drain, "bg": bar_clip }

## Animate HP loss: flash only the lost portion, hold the drain at old position, then tween it down.
func _animate_hp_drain(drain: ColorRect, bg: Control, old_ratio: float, new_ratio: float) -> void:
	# Kill existing drain tween
	if _enemy_hp_bar_tween and _enemy_hp_bar_tween.is_valid():
		_enemy_hp_bar_tween.kill()

	# Flash only the lost portion (new_ratio -> old_ratio)
	_spawn_bar_flash(bg, new_ratio, old_ratio, Color(1, 0.3, 0.3, 0.7), 0.35)

	# Drain bar: hold at old position, then tween down to new position
	drain.anchor_right = old_ratio
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(drain, "anchor_right", new_ratio, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_enemy_hp_bar_tween = tw

## Animate HP gain: flash only the gained portion green.
func _animate_hp_heal(bg: Control, old_ratio: float, new_ratio: float) -> void:
	_spawn_bar_flash(bg, old_ratio, new_ratio, Color(0.3, 1.0, 0.4, 0.6), 0.5)

## Spawn a self-cleaning flash overlay on a portion of an HP bar.
## Multiple flashes can coexist (e.g. two blood runes healing simultaneously).
func _spawn_bar_flash(bg: Control, left: float, right: float, color: Color, duration: float) -> void:
	var flash := ColorRect.new()
	flash.anchor_left   = left
	flash.anchor_right  = right
	flash.anchor_top    = 0.0
	flash.anchor_bottom = 1.0
	flash.offset_left   = 0
	flash.offset_right  = 0
	flash.offset_top    = 0
	flash.offset_bottom = 0
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, duration)
	tw.tween_callback(flash.queue_free)

## Update the HP bar gradient colors based on current HP ratio (green->red).
func _update_hp_bar_gradient(bar_fill: TextureRect, ratio: float) -> void:
	var base_color: Color = Color(0.85, 0.25, 0.30, 1.0).lerp(Color(0.30, 0.75, 0.35, 1.0), ratio)
	var grad_tex: GradientTexture2D = bar_fill.texture as GradientTexture2D
	if grad_tex and grad_tex.gradient:
		grad_tex.gradient.set_color(0, base_color.lightened(0.15))
		grad_tex.gradient.set_color(1, base_color.darkened(0.15))

# ---------------------------------------------------------------------------
# Stats columns
# ---------------------------------------------------------------------------

## Build the two-column stats area (HP/Essence/Mana/Hand + Void Mark row).
func _build_enemy_stats_cols(vbox: VBoxContainer) -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cols)

	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 3)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left_col)

	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 3)
	right_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(right_col)

	_enemy_status_hp_label = Label.new()
	_enemy_status_hp_label.add_theme_font_size_override("font_size", 12)
	_enemy_status_hp_label.add_theme_color_override("font_color", Color(0.95, 0.40, 0.40, 1))
	_enemy_status_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_enemy_status_hp_label)

	_enemy_status_essence_label = Label.new()
	_enemy_status_essence_label.add_theme_font_size_override("font_size", 12)
	_enemy_status_essence_label.add_theme_color_override("font_color", Color(0.70, 0.40, 1.0, 1))
	_enemy_status_essence_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_enemy_status_essence_label)

	_enemy_status_mana_label = Label.new()
	_enemy_status_mana_label.add_theme_font_size_override("font_size", 12)
	_enemy_status_mana_label.add_theme_color_override("font_color", Color(0.30, 0.65, 1.0, 1))
	_enemy_status_mana_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_enemy_status_mana_label)

	_enemy_status_hand_label = Label.new()
	_enemy_status_hand_label.add_theme_font_size_override("font_size", 12)
	_enemy_status_hand_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85, 1))
	_enemy_status_hand_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_enemy_status_hand_label)

	_enemy_status_marks_row = HBoxContainer.new()
	_enemy_status_marks_row.add_theme_constant_override("separation", 4)
	_enemy_status_marks_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_status_marks_row.visible = false
	right_col.add_child(_enemy_status_marks_row)

	const VOIDMARK_ICON := "res://assets/art/icons/icon_voidmark.png"
	if ResourceLoader.exists(VOIDMARK_ICON):
		var vm_icon := TextureRect.new()
		vm_icon.texture             = load(VOIDMARK_ICON)
		vm_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vm_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		vm_icon.custom_minimum_size = Vector2(14, 14)
		vm_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vm_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		_enemy_status_marks_row.add_child(vm_icon)

	_enemy_status_marks_label = Label.new()
	_enemy_status_marks_label.add_theme_font_size_override("font_size", 12)
	_enemy_status_marks_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15, 1))
	_enemy_status_marks_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_status_marks_row.add_child(_enemy_status_marks_label)

	# Champion progress row
	_champion_progress_row = HBoxContainer.new()
	_champion_progress_row.add_theme_constant_override("separation", 4)
	_champion_progress_row.mouse_filter = Control.MOUSE_FILTER_STOP
	_champion_progress_row.visible = false
	right_col.add_child(_champion_progress_row)

	var champ_icon := Label.new()
	champ_icon.text = "★"
	champ_icon.add_theme_font_size_override("font_size", 13)
	champ_icon.add_theme_color_override("font_color", Color(1.0, 0.78, 0.10, 1))
	champ_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_champion_progress_row.add_child(champ_icon)

	_champion_progress_label = Label.new()
	_champion_progress_label.add_theme_font_size_override("font_size", 12)
	_champion_progress_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.10, 1))
	_champion_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_champion_progress_row.add_child(_champion_progress_label)

	_champion_progress_pips.clear()

	# Champion progress hover tooltip
	_setup_champion_progress_tooltip(right_col)

# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------

## Refresh all displayed stats from the provided combat state.
func update(enemy_hp: int, enemy_hp_max: int, enemy_ai: Node, enemy_void_marks: int) -> void:
	if _enemy_status_hp_label:
		_enemy_status_hp_label.text = "❤ HP: %d / %d" % [enemy_hp, enemy_hp_max]
	if _enemy_hp_bar_fill and enemy_hp_max > 0:
		var new_ratio: float = clampf(float(enemy_hp) / float(enemy_hp_max), 0.0, 1.0)
		var old_ratio: float = _enemy_hp_bar_fill.anchor_right
		_enemy_hp_bar_fill.anchor_right = new_ratio
		_update_hp_bar_gradient(_enemy_hp_bar_fill, new_ratio)
		if new_ratio < old_ratio - 0.001:
			_animate_hp_drain(_enemy_hp_bar_drain, _enemy_hp_bar_bg, old_ratio, new_ratio)
		elif new_ratio > old_ratio + 0.001:
			_animate_hp_heal(_enemy_hp_bar_bg, old_ratio, new_ratio)
	if _enemy_status_essence_label:
		var ess_max: int = enemy_ai.essence_max if enemy_ai else 0
		var ess_cur: int = enemy_ai.essence if enemy_ai else 0
		_enemy_status_essence_label.text = "◆ Essence: %d / %d" % [ess_cur, ess_max]
	if _enemy_status_mana_label:
		var mana_max: int = enemy_ai.mana_max if enemy_ai else 0
		var mana_cur: int = enemy_ai.mana if enemy_ai else 0
		_enemy_status_mana_label.text = "◈ Mana: %d / %d" % [mana_cur, mana_max]
	if _enemy_status_hand_label:
		var hand_size: int = enemy_ai.hand.size() if enemy_ai else 0
		_enemy_status_hand_label.text = "🂠 Hand: %d" % hand_size
	if _enemy_status_marks_row:
		if enemy_void_marks > 0:
			if _enemy_status_marks_label:
				_enemy_status_marks_label.text = "Void Mark ×%d" % enemy_void_marks
			_enemy_status_marks_row.visible = true
		else:
			_enemy_status_marks_row.visible = false

## Internal initial refresh (called at end of setup with zeroed-out values).
func _update() -> void:
	update(0, 0, null, 0)

# ---------------------------------------------------------------------------
# Hero attack pulse
# ---------------------------------------------------------------------------

func show_attackable(attackable: bool) -> void:
	_enemy_hero_attackable = attackable
	if attackable:
		start_attack_pulse()
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		stop_attack_pulse()
		if highlight_panel:
			var clear_style := StyleBoxFlat.new()
			clear_style.bg_color = Color(0, 0, 0, 0)
			clear_style.set_border_width_all(0)
			clear_style.set_corner_radius_all(6)
			highlight_panel.add_theme_stylebox_override("panel", clear_style)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

## Apply green border style (static, no shadow) — used when hero is a valid attack target.
func _apply_hero_attack_style() -> void:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(6)
	s.bg_color     = Color(0, 0, 0, 0)
	s.border_color = Color(0.25, 0.92, 0.40, 1.0)
	s.set_border_width_all(3)
	s.shadow_color = Color(0.25, 0.92, 0.40, 0.45 + _hero_attack_pulse * 0.35)
	s.shadow_size  = int(8.0 + _hero_attack_pulse * 10.0)
	if highlight_panel:
		highlight_panel.add_theme_stylebox_override("panel", s)

## Show static green border and wire hover signals for glow-on-hover.
func start_attack_pulse() -> void:
	_hero_attack_pulse = 0.0
	_apply_hero_attack_style()
	if not mouse_entered.is_connected(_on_hero_attack_hover_enter):
		mouse_entered.connect(_on_hero_attack_hover_enter)
		mouse_exited.connect(_on_hero_attack_hover_exit)

## Remove attack-target style and disconnect hover signals.
func stop_attack_pulse() -> void:
	if _hero_attack_tween:
		_hero_attack_tween.kill()
		_hero_attack_tween = null
	_hero_attack_pulse = 0.0
	if mouse_entered.is_connected(_on_hero_attack_hover_enter):
		mouse_entered.disconnect(_on_hero_attack_hover_enter)
		mouse_exited.disconnect(_on_hero_attack_hover_exit)

func _on_hero_attack_hover_enter() -> void:
	if _hero_attack_tween:
		_hero_attack_tween.kill()
	_hero_attack_tween = create_tween().set_loops()
	_hero_attack_tween.tween_method(func(v: float) -> void:
		_hero_attack_pulse = v
		_apply_hero_attack_style(), 0.0, 1.0, 0.5)
	_hero_attack_tween.tween_method(func(v: float) -> void:
		_hero_attack_pulse = v
		_apply_hero_attack_style(), 1.0, 0.0, 0.5)

func _on_hero_attack_hover_exit() -> void:
	if _hero_attack_tween:
		_hero_attack_tween.kill()
		_hero_attack_tween = null
	_hero_attack_pulse = 0.0
	_apply_hero_attack_style()

func _on_enemy_hero_frame_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _enemy_hero_attackable:
			hero_pressed.emit()

# ---------------------------------------------------------------------------
# Enemy hero spell-target pulse
# ---------------------------------------------------------------------------

func _apply_hero_spell_style() -> void:
	var border_w: float = 3.0 + _hero_spell_pulse * 2.5
	var shadow_sz: float = 8.0 + _hero_spell_pulse * 10.0
	var shadow_a: float  = 0.55 + _hero_spell_pulse * 0.30
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(6)
	s.bg_color     = Color(0, 0, 0, 0)
	s.border_color = Color(0.20, 0.85, 0.30, 1.0)
	s.set_border_width_all(border_w)
	s.shadow_color = Color(0.20, 0.85, 0.30, shadow_a)
	s.shadow_size  = shadow_sz
	if highlight_panel:
		highlight_panel.add_theme_stylebox_override("panel", s)

func start_spell_pulse() -> void:
	# Apply static border immediately; pulse begins only on hover.
	_hero_spell_pulse = 0.0
	_apply_hero_spell_style()
	if not mouse_entered.is_connected(_on_hero_spell_hover_enter):
		mouse_entered.connect(_on_hero_spell_hover_enter)
		mouse_exited.connect(_on_hero_spell_hover_exit)

func stop_spell_pulse() -> void:
	if _hero_spell_tween:
		_hero_spell_tween.kill()
		_hero_spell_tween = null
	_hero_spell_pulse = 0.0
	if mouse_entered.is_connected(_on_hero_spell_hover_enter):
		mouse_entered.disconnect(_on_hero_spell_hover_enter)
		mouse_exited.disconnect(_on_hero_spell_hover_exit)

func _on_hero_spell_hover_enter() -> void:
	if _hero_spell_tween:
		_hero_spell_tween.kill()
	_hero_spell_tween = create_tween().set_loops()
	_hero_spell_tween.tween_method(func(v: float) -> void:
		_hero_spell_pulse = v
		_apply_hero_spell_style(), 0.0, 1.0, 0.5)
	_hero_spell_tween.tween_method(func(v: float) -> void:
		_hero_spell_pulse = v
		_apply_hero_spell_style(), 1.0, 0.0, 0.5)

func _on_hero_spell_hover_exit() -> void:
	if _hero_spell_tween:
		_hero_spell_tween.kill()
		_hero_spell_tween = null
	_hero_spell_pulse = 0.0
	_apply_hero_spell_style()

# ---------------------------------------------------------------------------
# Champion progress
# ---------------------------------------------------------------------------

## Called by CombatHandlers when champion progress increments.
func update_champion_progress(current: int, total: int) -> void:
	var prev: int = _champion_progress_current
	_champion_progress_current = current
	_champion_progress_max = total
	if not _champion_progress_row:
		return
	_champion_progress_row.visible = true

	# Build pips on first call or when total changes
	if _champion_progress_pips.size() != total:
		for p in _champion_progress_pips:
			p.queue_free()
		_champion_progress_pips.clear()
		for i in total:
			var pip := Label.new()
			pip.text = "◇"
			pip.add_theme_font_size_override("font_size", 14)
			pip.add_theme_color_override("font_color", Color(0.40, 0.35, 0.50, 0.6))
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_champion_progress_row.add_child(pip)
			_champion_progress_pips.append(pip)

	# Update pip states
	var ratio: float = float(current) / float(total) if total > 0 else 0.0
	for i in total:
		var pip: Label = _champion_progress_pips[i]
		if i < current:
			pip.text = "◆"
			# Color by urgency
			if ratio >= 1.0:
				pip.add_theme_color_override("font_color", Color(1.0, 0.25, 0.15, 1))
			elif ratio >= 0.75:
				pip.add_theme_color_override("font_color", Color(1.0, 0.50, 0.12, 1))
			elif ratio >= 0.5:
				pip.add_theme_color_override("font_color", Color(1.0, 0.82, 0.20, 1))
			else:
				pip.add_theme_color_override("font_color", Color(0.85, 0.70, 0.40, 1))
		else:
			pip.text = "◇"
			pip.add_theme_color_override("font_color", Color(0.40, 0.35, 0.50, 0.6))

	# Animate the newly filled pip(s)
	for i in range(prev, current):
		if i >= 0 and i < _champion_progress_pips.size():
			_animate_pip_fill(_champion_progress_pips[i])

	# Update label text
	if ratio >= 1.0:
		_champion_progress_label.text = "SUMMONING..."
		_champion_progress_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.15, 1))
		# Shake the whole row when threshold reached
		_champion_progress_shake()
	else:
		_champion_progress_label.text = ""
		_champion_progress_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.10, 1))

	# Pulse the row on every increment
	if _champion_progress_tween:
		_champion_progress_tween.kill()
	_champion_progress_row.pivot_offset = _champion_progress_row.size / 2.0
	_champion_progress_tween = create_tween()
	_champion_progress_tween.tween_property(_champion_progress_row, "scale", Vector2(1.15, 1.15), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_champion_progress_tween.tween_property(_champion_progress_row, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Animate a pip being filled — scale pop + glow flash.
func _animate_pip_fill(pip: Label) -> void:
	pip.pivot_offset = pip.size / 2.0
	var tw := create_tween().set_parallel(true)
	# Scale pop
	tw.tween_property(pip, "scale", Vector2(1.8, 1.8), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Bright flash
	tw.tween_property(pip, "modulate", Color(2.0, 1.8, 0.5, 1), 0.08)
	tw.chain().set_parallel(true)
	tw.tween_property(pip, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(pip, "modulate", Color.WHITE, 0.4)

## Rapid shake on the progress row when champion is about to summon.
func _champion_progress_shake() -> void:
	var row := _champion_progress_row
	if row == null:
		return
	var original_pos: Vector2 = row.position
	var shake_tw := create_tween()
	for i in 8:
		var offset := Vector2(randf_range(-3.0, 3.0), randf_range(-1.5, 1.5))
		shake_tw.tween_property(row, "position", original_pos + offset, 0.03)
	shake_tw.tween_property(row, "position", original_pos, 0.03)

## Called by CombatHandlers when the enemy champion is killed — hide progress, show reward feedback.
func on_champion_killed() -> void:
	if _champion_progress_row:
		# Turn all pips green
		for pip in _champion_progress_pips:
			pip.text = "✦"
			pip.add_theme_color_override("font_color", Color(0.35, 0.90, 0.55, 1))
		_champion_progress_label.text = "Champion slain!"
		_champion_progress_label.add_theme_color_override("font_color", Color(0.35, 0.90, 0.55, 1))
		if _champion_progress_tween:
			_champion_progress_tween.kill()
		_champion_progress_row.pivot_offset = _champion_progress_row.size / 2.0
		_champion_progress_tween = create_tween()
		# Scale pop
		_champion_progress_tween.tween_property(_champion_progress_row, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_champion_progress_tween.parallel().tween_property(_champion_progress_row, "modulate", Color(0.5, 2.0, 0.5, 1), 0.12)
		_champion_progress_tween.tween_property(_champion_progress_row, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_SINE)
		_champion_progress_tween.parallel().tween_property(_champion_progress_row, "modulate", Color.WHITE, 0.4)
		_champion_progress_tween.tween_interval(2.5)
		_champion_progress_tween.tween_property(_champion_progress_row, "modulate", Color(1, 1, 1, 0), 0.6)

# ---------------------------------------------------------------------------
# Champion progress tooltip
# ---------------------------------------------------------------------------

## Build and attach a hover tooltip to the champion progress row showing the summon condition.
func _setup_champion_progress_tooltip(_parent: Node) -> void:
	var ui_root := _scene.get_node_or_null("UI")
	if ui_root == null:
		return

	# Find the active champion passive
	var champ_id: String = ""
	for pid in _scene._active_enemy_passives:
		if pid.begins_with("champion_"):
			champ_id = pid
			break
	if champ_id == "":
		return

	# Champion info — same data as PASSIVE_INFO in _add_enemy_passive_hover_icon
	const CHAMPION_INFO: Dictionary = {
		"champion_rogue_imp_pack": {
			"name": "Rogue Imp Pack",
			"condition": "4 different Rabid Imps have attacked",
			"stats": "200 ATK / 400 HP — SWIFT",
			"aura": "All friendly FERAL IMP minions have +100 ATK.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
		"champion_corrupted_broodlings": {
			"name": "Corrupted Broodlings",
			"condition": "3 friendly minions have died",
			"stats": "200 ATK / 400 HP",
			"aura": "",
			"on_death": "Summon a Void-Touched Imp. Deal 20% of max HP to enemy hero.",
		},
		"champion_imp_matriarch": {
			"name": "Imp Matriarch",
			"condition": "2nd Pack Frenzy cast",
			"stats": "300 ATK / 500 HP — GUARD",
			"aura": "Pack Frenzy also gives all FERAL IMP minions +200 HP.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
		"champion_abyss_cultist_patrol": {
			"name": "Abyss Cultist Patrol",
			"condition": "5 corruption stacks consumed",
			"stats": "300 ATK / 300 HP",
			"aura": "Corruption applied to enemy minions instantly detonates.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
		"champion_void_ritualist": {
			"name": "Void Ritualist",
			"condition": "Ritual Sacrifice triggers",
			"stats": "200 ATK / 300 HP",
			"aura": "Rune placement costs 1 less Mana.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
		"champion_corrupted_handler": {
			"name": "Corrupted Handler",
			"condition": "3 Void Sparks created",
			"stats": "300 ATK / 300 HP",
			"aura": "Whenever a Void Spark is summoned, deal 200 damage to enemy hero.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
		"champion_duel": {
			"name": "Void Duel",
			"condition": "Always active",
			"stats": "",
			"aura": "Enemy minions with Critical Strike have Spell Immune.",
			"on_death": "",
		},
		"champion_rift_stalker": {
			"name": "Rift Stalker",
			"condition": "Void Sparks have dealt 1500 damage",
			"stats": "400 ATK / 400 HP",
			"aura": "All friendly Void Sparks are immune.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
		"champion_void_aberration": {
			"name": "Void Aberration",
			"condition": "5 sparks consumed as costs",
			"stats": "300 ATK / 300 HP — ETHEREAL",
			"aura": "Void Detonation deals 200 damage instead of 100.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
		"champion_void_herald": {
			"name": "Void Herald",
			"condition": "6 spark-cost cards played",
			"stats": "200 ATK / 500 HP",
			"aura": "All spark costs become 0. Void Rift stops generating sparks.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
		"champion_void_scout": {
			"name": "Void Scout",
			"condition": "5 critical strikes consumed",
			"stats": "400 ATK / 500 HP",
			"aura": "Critical Strike deals 2.5x damage instead of 2x.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
		"champion_void_warband": {
			"name": "Void Warband",
			"condition": "3 Spirits consumed as fuel",
			"stats": "500 ATK / 600 HP — 1 Critical Strike",
			"aura": "When a friendly Spirit with Crit is consumed, summon a 100/100 Void Spark.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
		"champion_void_captain": {
			"name": "Void Captain",
			"condition": "2 Throne's Command cast",
			"stats": "300 ATK / 600 HP — 2 Critical Strike",
			"aura": "When a friendly minion consumes a Critical Strike, deal 100 damage to each of 2 random enemies.",
			"on_death": "Deal 20% of max HP to enemy hero.",
		},
	}

	var info: Dictionary = CHAMPION_INFO.get(champ_id, {})
	if info.is_empty():
		return

	var scaffold: Dictionary = _scene._build_hover_tooltip_scaffold(ui_root, 280, Color(0.08, 0.04, 0.02, 0.97), Color(1.0, 0.70, 0.15, 0.85))
	var tip: PanelContainer = scaffold.tip
	var tip_vbox: VBoxContainer = scaffold.tip_vbox

	# Header
	var hdr := Label.new()
	hdr.text = "★ CHAMPION"
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", Color(1.0, 0.78, 0.15, 1.0))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_vbox.add_child(hdr)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = info.get("name", champ_id) as String
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.65, 1.0))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_vbox.add_child(name_lbl)

	# Stats
	var stats_str: String = info.get("stats", "") as String
	if stats_str != "":
		var stats_lbl := Label.new()
		stats_lbl.text = stats_str
		stats_lbl.add_theme_font_size_override("font_size", 12)
		stats_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.65, 1.0))
		stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(stats_lbl)

	# Summon condition
	var cond_row := VBoxContainer.new()
	cond_row.add_theme_constant_override("separation", 2)
	cond_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_vbox.add_child(cond_row)

	var cond_hdr := Label.new()
	cond_hdr.text = "SUMMON CONDITION"
	cond_hdr.add_theme_font_size_override("font_size", 11)
	cond_hdr.add_theme_color_override("font_color", Color(0.65, 0.55, 0.45, 1.0))
	cond_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cond_row.add_child(cond_hdr)

	var cond_lbl := Label.new()
	cond_lbl.text = info.get("condition", "") as String
	cond_lbl.add_theme_font_size_override("font_size", 13)
	cond_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.20, 1.0))
	cond_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cond_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cond_row.add_child(cond_lbl)

	# Aura
	var aura_str: String = info.get("aura", "") as String
	if aura_str != "":
		var aura_row := VBoxContainer.new()
		aura_row.add_theme_constant_override("separation", 2)
		aura_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(aura_row)

		var aura_hdr := Label.new()
		aura_hdr.text = "AURA"
		aura_hdr.add_theme_font_size_override("font_size", 11)
		aura_hdr.add_theme_color_override("font_color", Color(0.65, 0.55, 0.45, 1.0))
		aura_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		aura_row.add_child(aura_hdr)

		var aura_lbl := Label.new()
		aura_lbl.text = aura_str
		aura_lbl.add_theme_font_size_override("font_size", 12)
		aura_lbl.add_theme_color_override("font_color", Color(0.90, 0.80, 0.60, 1.0))
		aura_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		aura_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		aura_row.add_child(aura_lbl)

	# On death
	var death_str: String = info.get("on_death", "") as String
	if death_str != "":
		var death_row := VBoxContainer.new()
		death_row.add_theme_constant_override("separation", 2)
		death_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(death_row)

		var death_hdr := Label.new()
		death_hdr.text = "ON DEATH"
		death_hdr.add_theme_font_size_override("font_size", 11)
		death_hdr.add_theme_color_override("font_color", Color(0.65, 0.55, 0.45, 1.0))
		death_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		death_row.add_child(death_hdr)

		var death_lbl := Label.new()
		death_lbl.text = death_str
		death_lbl.add_theme_font_size_override("font_size", 12)
		death_lbl.add_theme_color_override("font_color", Color(0.85, 0.45, 0.35, 1.0))
		death_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		death_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		death_row.add_child(death_lbl)

	# Connect hover events
	_champion_progress_row.mouse_entered.connect(func() -> void:
		tip.size = tip.get_minimum_size()
		tip.position.y = get_viewport().get_visible_rect().size.y - tip.size.y - 16.0
		tip.visible = true
	)
	_champion_progress_row.mouse_exited.connect(func() -> void:
		tip.visible = false
	)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _create_stylebox(bg: Color, border: Color, corner_radius: int = 4, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color     = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style
