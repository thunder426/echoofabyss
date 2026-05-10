class_name PlayerHeroPanel
extends Control
## Player hero status panel (bottom-right) — name, portrait, HP bar, HP label.

# -- Scene reference --------------------------------------------------------
var _scene: Node2D = null

# -- Exposed nodes ----------------------------------------------------------
## The header row so CombatScene can inject talent hover icon after setup.
var header_row: HBoxContainer = null

# -- Hero-specific resource bar (Seris Flesh/Forge) -------------------------
## Created only when the current hero has a matching passive/talent. May be null.
var resource_bar: SerisResourceBar = null

# -- HP bar -----------------------------------------------------------------
var _hp_label: Label = null
var _hp_bar_fill: TextureRect = null
var _hp_bar_drain: ColorRect = null
var _hp_bar_bg: Control = null
var _hp_bar_tween: Tween = null

# -- Korrath debuff badges --------------------------------------------------
# Single net-armour row: icon + label swap based on sign of (armour - sum AB).
# Positive → green Armour icon; negative → red Armour Break icon; zero hides.
var _armour_net_row: HBoxContainer = null
var _armour_net_icon: TextureRect = null
var _armour_net_label: Label = null
# Separate Corruption stack badge — independent from armour math.
var _corruption_row: HBoxContainer = null
var _corruption_label: Label = null

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Build the player hero status panel. Caller must add self to the scene tree.
func setup(scene: Node2D, ui_root: Node) -> void:
	_scene = scene

	# Configure self
	custom_minimum_size = Vector2(300, 155)
	anchor_left   = 1.0
	anchor_right  = 1.0
	anchor_top    = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN
	offset_left   = -310.0
	offset_right  = -10.0
	offset_top    = -165.0
	offset_bottom = -10.0
	mouse_filter  = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

	# Layer 1: dark background with border
	var player_bg_fill := Panel.new()
	player_bg_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_bg_fill.add_theme_stylebox_override("panel", _create_stylebox(Color(0.06, 0.06, 0.14, 0.93), Color(0.35, 0.55, 0.90, 1.0), 6))
	player_bg_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(player_bg_fill)

	# Layer 2: hero combat portrait (if available)
	var hero_data: HeroData = HeroDatabase.get_hero(GameManager.current_hero)
	var combat_portrait: String = hero_data.combat_portrait_path if hero_data else ""
	if combat_portrait != "":
		var bg_tex := TextureRect.new()
		bg_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_tex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.texture      = load(combat_portrait)
		bg_tex.modulate     = Color(1, 1, 1, 0.45)
		bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_tex)

		var overlay := ColorRect.new()
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.color = Color(0.0, 0.0, 0.0, 0.45)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)

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

	# Name header row
	var hero := HeroDatabase.get_hero(GameManager.current_hero)
	header_row = HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_theme_constant_override("separation", 6)
	vbox.add_child(header_row)

	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0, 1))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hero:
		name_lbl.text = hero.hero_name.to_upper()
	header_row.add_child(name_lbl)

	# Talent hover icon — injected by CombatScene after setup
	_scene._add_talent_hover_icon(header_row, self)

	var player_bar: Dictionary = _build_hp_bar(vbox, Color(0.30, 0.75, 0.35, 1.0))
	_hp_bar_fill  = player_bar["fill"] as TextureRect
	_hp_bar_drain = player_bar["drain"] as ColorRect
	_hp_bar_bg    = player_bar["bg"] as Control

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 13)
	_hp_label.add_theme_color_override("font_color", Color(0.95, 0.40, 0.40, 1))
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hp_label)

	# Korrath — single net-armour row (icon swaps on sign) + separate Corruption row.
	# Hidden when their respective values are zero so non-Korrath fights stay clean.
	_armour_net_row = _build_korrath_badge_row(vbox,
			"res://assets/art/icons/icon_armour.png", Color(0.70, 1.00, 0.55, 1))
	# Children: [icon, label] — grab refs so we can mutate texture/color/text live.
	for child in _armour_net_row.get_children():
		if child is TextureRect:
			_armour_net_icon = child
		elif child is Label:
			_armour_net_label = child
	_corruption_row = _build_korrath_badge_row(vbox,
			"res://assets/art/icons/icon_corruption.png", Color(0.85, 0.55, 1.00, 1))
	_corruption_label = _corruption_row.get_child(_corruption_row.get_child_count() - 1) as Label

	# Hero-specific resource bar (Seris Flesh/Forge) — null for heroes without matching passives.
	resource_bar = SerisResourceBar.maybe_create(_scene)
	if resource_bar != null:
		vbox.add_child(resource_bar)

# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------

func update(current_hp: int, max_hp: int) -> void:
	if not _hp_label:
		return
	_hp_label.text = "❤ HP: %d / %d" % [current_hp, max_hp]
	if _hp_bar_fill and max_hp > 0:
		var new_ratio: float = clampf(float(current_hp) / float(max_hp), 0.0, 1.0)
		var old_ratio: float = _hp_bar_fill.anchor_right
		_hp_bar_fill.anchor_right = new_ratio
		_update_hp_bar_gradient(_hp_bar_fill, new_ratio)
		if new_ratio < old_ratio - 0.001:
			_animate_hp_drain(_hp_bar_drain, _hp_bar_bg, old_ratio, new_ratio)
		elif new_ratio > old_ratio + 0.001:
			_animate_hp_heal(_hp_bar_bg, old_ratio, new_ratio)

## Korrath — refresh Korrath debuff badges. Armour and AB share one row whose
## icon and label swap based on the signed net (armour - armour_break): positive
## shows green Armour, negative shows red Armour Break, zero hides. Corruption
## is its own independent stack badge.
func update_korrath_debuffs(armour: int, armour_break: int, corruption_stacks: int) -> void:
	if _armour_net_row != null:
		var net: int = armour - armour_break
		if net == 0:
			_armour_net_row.visible = false
		else:
			_armour_net_row.visible = true
			if net > 0:
				if _armour_net_icon != null and ResourceLoader.exists("res://assets/art/icons/icon_armour.png"):
					_armour_net_icon.texture = load("res://assets/art/icons/icon_armour.png")
				if _armour_net_label != null:
					_armour_net_label.text = "Armour %d" % net
					_armour_net_label.add_theme_color_override("font_color", Color(0.70, 1.00, 0.55, 1))
			else:
				if _armour_net_icon != null and ResourceLoader.exists("res://assets/art/icons/icon_armour_break.png"):
					_armour_net_icon.texture = load("res://assets/art/icons/icon_armour_break.png")
				if _armour_net_label != null:
					_armour_net_label.text = "Armour Break %d" % -net
					_armour_net_label.add_theme_color_override("font_color", Color(1.00, 0.45, 0.45, 1))
	if _corruption_row != null:
		_corruption_row.visible = corruption_stacks > 0
		if corruption_stacks > 0 and _corruption_label != null:
			_corruption_label.text = "Corrupt ×%d" % corruption_stacks

## Build a hidden-by-default badge row with an icon + label.
func _build_korrath_badge_row(parent: Container, icon_path: String, label_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.visible = false
	parent.add_child(row)
	if ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture             = load(icon_path)
		icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(14, 14)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", label_color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	return row

# ---------------------------------------------------------------------------
# HP bar helpers (duplicated from EnemyHeroPanel — small, no base class needed)
# ---------------------------------------------------------------------------

func _build_hp_bar(parent: VBoxContainer, fill_color: Color) -> Dictionary:
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

	var bar_clip := Control.new()
	bar_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_clip.clip_contents = true
	bar_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_container.add_child(bar_clip)

	var drain := ColorRect.new()
	drain.anchor_top    = 0.0
	drain.anchor_bottom = 1.0
	drain.anchor_left   = 0.0
	drain.anchor_right  = 1.0
	drain.color = Color(0.95, 0.45, 0.10, 0.85)
	drain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_clip.add_child(drain)

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

func _animate_hp_drain(drain: ColorRect, bg: Control, old_ratio: float, new_ratio: float) -> void:
	if _hp_bar_tween and _hp_bar_tween.is_valid():
		_hp_bar_tween.kill()
	_spawn_bar_flash(bg, new_ratio, old_ratio, Color(1, 0.3, 0.3, 0.7), 0.35)
	drain.anchor_right = old_ratio
	_hp_bar_tween = create_tween()
	_hp_bar_tween.tween_interval(0.35)
	_hp_bar_tween.tween_property(drain, "anchor_right", new_ratio, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

func _animate_hp_heal(bg: Control, old_ratio: float, new_ratio: float) -> void:
	_spawn_bar_flash(bg, old_ratio, new_ratio, Color(0.3, 1.0, 0.4, 0.6), 0.5)

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

func _update_hp_bar_gradient(bar_fill: TextureRect, ratio: float) -> void:
	var base_color: Color = Color(0.85, 0.25, 0.30, 1.0).lerp(Color(0.30, 0.75, 0.35, 1.0), ratio)
	var grad_tex: GradientTexture2D = bar_fill.texture as GradientTexture2D
	if grad_tex and grad_tex.gradient:
		grad_tex.gradient.set_color(0, base_color.lightened(0.15))
		grad_tex.gradient.set_color(1, base_color.darkened(0.15))

func _create_stylebox(bg: Color, border: Color, corner_radius: int = 4, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color     = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style
