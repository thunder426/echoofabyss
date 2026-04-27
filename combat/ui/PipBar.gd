class_name PipBar
extends Control

## Manages the essence/mana pip bar columns in the combat UI.
## Extracted from CombatScene.gd — two vertical pip columns (essence left, mana right)
## above the player status panel, 10 pips each.

var _scene: Node2D

# Pip bar columns (essence left, mana right) — 10 pips each, built in setup()
var _pip_essence_panels: Array[Panel]       = []
var _pip_mana_panels:    Array[Panel]       = []
var _pip_essence_rects:  Array[TextureRect] = []
var _pip_mana_rects:     Array[TextureRect] = []
var _ess_pip_tex: GradientTexture2D = null
var _mna_pip_tex: GradientTexture2D = null
var _ess_ovf_tex: GradientTexture2D = null  # overflow/temp essence
var _mna_ovf_tex: GradientTexture2D = null  # overflow/temp mana
# Outer border panels — animated on resource gain/spend
var _ess_col_panel: Panel = null
var _mna_col_panel: Panel = null
var _ess_col_tween: Tween = null
var _mna_col_tween: Tween = null
# Previous values used to detect direction of change
var _prev_essence: int = -1
var _prev_mana:    int = -1
# Flesh counter widget (Seris only) — icon + "N/5" label, left of essence column.
var _flesh_root:     Control     = null
var _flesh_icon:     TextureRect = null
var _flesh_count_lbl: Label      = null
var _flesh_caption:  Label       = null
var _flesh_tween:    Tween       = null
var _prev_flesh:     int         = -1
var _flesh_tooltip:  Panel       = null
# Forge counter widget (Seris + soul_forge talent) — sits directly above the flesh widget.
var _forge_root:     Control     = null
var _forge_icon:     TextureRect = null
var _forge_count_lbl: Label      = null
var _forge_caption:  Label       = null
var _forge_tween:    Tween       = null
var _prev_forge:     int         = -1
var _forge_tooltip:  Panel       = null
# Card-cost blink — highlights which pips will be spent / gained when a card is selected
var _pip_ess_blink:  int   = 0   # essence pips to fade (spend)
var _pip_mna_blink:  int   = 0   # mana pips to fade (spend)
var _pip_ess_gain:   int   = 0   # essence pips to glow (gain)
var _pip_mna_gain:   int   = 0   # mana pips to glow (gain)
var _pip_blink_tween: Tween = null
var _pip_blink_phase: float = 0.0

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Build two vertical pip columns (essence left, mana right) above the player status panel.
## Each column holds MAX_PIPS pip panels; colors are updated by update().
func setup(scene: Node2D, ui_root: Node, essence_label: Label, mana_label: Label) -> void:
	_scene = scene

	const MAX_PIPS      := 10
	const PIP_W         := 20
	const PIP_H         := 22
	const PIP_GAP       := 4
	const PIP_CORNER    := 3
	const COL_GAP       := 12   # gap between the two columns
	const COL_BORDER    := 3    # inner padding inside the outer border panel
	const COL_W         := PIP_W + COL_BORDER * 2   # = 26px
	const COL_H         := MAX_PIPS * PIP_H + (MAX_PIPS - 1) * PIP_GAP  # = 256px
	# MARGIN_BOTTOM = player_panel_top(165) + label_h + gap leaves room below the pips
	const MARGIN_BOTTOM := 211
	const RIGHT_MARGIN  := 15
	const LBL_W         := 44   # fits "10/10" at font 13 with some breathing room
	const LBL_H         := 22
	# Column centres from screen-right edge (used for label centering)
	const MNA_CENTER    := RIGHT_MARGIN + COL_W / 2                     # = 28
	const ESS_CENTER    := RIGHT_MARGIN + COL_W + COL_GAP + COL_W / 2  # = 67

	# Reusable gradient textures: lighter at pip top, deeper at pip bottom
	_ess_pip_tex = _make_pip_gradient_tex(Color(0.72, 0.42, 0.96, 1.0), Color(0.62, 0.06, 0.18, 1.0))
	_mna_pip_tex = _make_pip_gradient_tex(Color(0.40, 0.78, 1.00, 1.0), Color(0.05, 0.18, 0.58, 1.0))
	# Overflow (temp) textures — gold->orange for essence, bright-cyan->teal for mana
	_ess_ovf_tex = _make_pip_gradient_tex(Color(1.00, 0.92, 0.38, 1.0), Color(0.95, 0.48, 0.05, 1.0))
	_mna_ovf_tex = _make_pip_gradient_tex(Color(0.65, 1.00, 1.00, 1.0), Color(0.08, 0.75, 0.90, 1.0))

	# --- Reposition existing scene labels to sit centred under their pip column ---
	# [label, col_center_from_right, font_color]
	for lbl_info in [
		[essence_label, ESS_CENTER, Color(0.78, 0.45, 1.0, 1.0)],
		[mana_label,    MNA_CENTER, Color(0.35, 0.70, 1.0, 1.0)],
	]:
		var lbl := lbl_info[0] as Label
		if lbl == null:
			continue
		var cx: float = float(lbl_info[1] as int)
		lbl.anchor_left              = 1.0
		lbl.anchor_right             = 1.0
		lbl.anchor_top               = 1.0
		lbl.anchor_bottom            = 1.0
		lbl.grow_horizontal          = Control.GROW_DIRECTION_BEGIN
		lbl.grow_vertical            = Control.GROW_DIRECTION_BEGIN
		lbl.offset_right             = -(cx - LBL_W / 2.0)
		lbl.offset_left              = -(cx + LBL_W / 2.0)
		lbl.offset_top               = -float(MARGIN_BOTTOM)
		lbl.offset_bottom            = -(MARGIN_BOTTOM - LBL_H)
		lbl.horizontal_alignment     = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", lbl_info[2] as Color)

	# --- Build two pip columns ---
	for col_idx in 2:
		var is_essence := col_idx == 0
		# col 0 (essence) sits to the LEFT of col 1 (mana)
		var col_right := RIGHT_MARGIN + (1 - col_idx) * (COL_W + COL_GAP)

		# Outer Panel — provides the visible border and receives the glow animation
		var col_panel := Panel.new()
		col_panel.mouse_filter    = Control.MOUSE_FILTER_IGNORE
		col_panel.anchor_left     = 1.0
		col_panel.anchor_right    = 1.0
		col_panel.anchor_top      = 1.0
		col_panel.anchor_bottom   = 1.0
		col_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		col_panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
		col_panel.offset_right    = -float(col_right)
		col_panel.offset_left     = col_panel.offset_right - COL_W
		col_panel.offset_bottom   = -float(MARGIN_BOTTOM)
		col_panel.offset_top      = col_panel.offset_bottom - COL_H
		col_panel.custom_minimum_size = Vector2(COL_W, COL_H)
		ui_root.add_child(col_panel)
		_apply_col_border_style(col_panel, 0.0, true, is_essence)

		if is_essence:
			_ess_col_panel = col_panel
		else:
			_mna_col_panel = col_panel

		# Inner margin to inset pips from the border
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left",   COL_BORDER)
		margin.add_theme_constant_override("margin_right",  COL_BORDER)
		margin.add_theme_constant_override("margin_top",    COL_BORDER)
		margin.add_theme_constant_override("margin_bottom", COL_BORDER)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col_panel.add_child(margin)

		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", PIP_GAP)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(vbox)

		# Spacer at top pushes visible pips to the bottom as max increases
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(spacer)

		# Pips: index 0 = value 10 (top), index 9 = value 1 (bottom)
		for _pip_idx in MAX_PIPS:
			var pip := Panel.new()
			pip.custom_minimum_size   = Vector2(PIP_W, PIP_H)
			pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pip.mouse_filter          = Control.MOUSE_FILTER_IGNORE
			pip.clip_contents         = true
			pip.visible               = false
			pip.add_theme_stylebox_override("panel",
				_create_stylebox(Color(0.10, 0.08, 0.16, 0.85),
					Color(0.28, 0.24, 0.38, 0.65), PIP_CORNER, 1))
			vbox.add_child(pip)

			var tr := TextureRect.new()
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tr.offset_left   =  1.0
			tr.offset_top    =  1.0
			tr.offset_right  = -1.0
			tr.offset_bottom = -1.0
			tr.stretch_mode  = TextureRect.STRETCH_SCALE
			tr.expand_mode   = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tr.texture       = _ess_pip_tex if is_essence else _mna_pip_tex
			tr.visible       = false
			tr.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			pip.add_child(tr)

			if is_essence:
				_pip_essence_panels.append(pip)
				_pip_essence_rects.append(tr)
			else:
				_pip_mana_panels.append(pip)
				_pip_mana_rects.append(tr)

	# --- Flesh counter widget (Seris) — built only if current hero has Fleshbind passive ---
	if HeroDatabase.has_passive(GameManager.current_hero, "fleshbind"):
		_build_flesh_widget(ui_root, RIGHT_MARGIN, COL_W, COL_GAP, COL_H, MARGIN_BOTTOM, LBL_H)

	# --- Forge counter widget (Seris + soul_forge talent) — sits above the flesh widget ---
	if GameManager.has_talent("soul_forge"):
		_build_forge_widget(ui_root, RIGHT_MARGIN, COL_W, COL_GAP, COL_H, MARGIN_BOTTOM, LBL_H)

	if _scene.turn_manager:
		update(_scene.turn_manager.essence, _scene.turn_manager.essence_max,
				_scene.turn_manager.mana, _scene.turn_manager.mana_max)
	update_flesh()
	update_forge()

func update(essence: int, essence_max: int, mana: int, mana_max: int) -> void:
	const MAX_PIPS     := 10
	const EMPTY_BG       := Color(0.10, 0.08, 0.16, 0.85)
	const EMPTY_BORDER   := Color(0.28, 0.24, 0.38, 0.65)
	const ESS_BORDER     := Color(0.62, 0.32, 0.88, 0.90)
	const MNA_BORDER     := Color(0.22, 0.58, 0.98, 0.90)
	# Overflow (temp) pips use distinct warm/cool accent borders per resource
	const ESS_OVF_BORDER := Color(0.98, 0.80, 0.12, 0.95)   # amber-gold  — essence overflow
	const MNA_OVF_BORDER := Color(0.20, 0.95, 0.88, 0.95)   # cyan-teal   — mana overflow

	if _pip_essence_panels.size() == MAX_PIPS:
		for i in MAX_PIPS:
			# i=0 -> value=10 (top), i=9 -> value=1 (bottom); bar fills from bottom up.
			var pip_value  := MAX_PIPS - i
			var pip        := _pip_essence_panels[i] as Panel
			var tr         := _pip_essence_rects[i]  as TextureRect
			var visible    := pip_value <= maxi(essence, essence_max)
			var filled     := pip_value <= essence
			var overflow   := filled and pip_value > essence_max
			pip.visible    = visible
			pip.modulate   = Color.WHITE
			tr.modulate    = Color.WHITE
			tr.visible     = filled
			if visible:
				if overflow:
					tr.texture = _ess_ovf_tex
					pip.add_theme_stylebox_override("panel",
						_create_stylebox(Color(0, 0, 0, 0), ESS_OVF_BORDER, 3, 1))
				else:
					tr.texture = _ess_pip_tex
					pip.add_theme_stylebox_override("panel",
						_create_stylebox(
							Color(0, 0, 0, 0) if filled else EMPTY_BG,
							ESS_BORDER if filled else EMPTY_BORDER, 3, 1))

	if _pip_mana_panels.size() == MAX_PIPS:
		for i in MAX_PIPS:
			var pip_value  := MAX_PIPS - i
			var pip        := _pip_mana_panels[i] as Panel
			var tr         := _pip_mana_rects[i]  as TextureRect
			var visible    := pip_value <= maxi(mana, mana_max)
			var filled     := pip_value <= mana
			var overflow   := filled and pip_value > mana_max
			pip.visible    = visible
			pip.modulate   = Color.WHITE
			tr.modulate    = Color.WHITE
			tr.visible     = filled
			if visible:
				if overflow:
					tr.texture = _mna_ovf_tex
					pip.add_theme_stylebox_override("panel",
						_create_stylebox(Color(0, 0, 0, 0), MNA_OVF_BORDER, 3, 1))
				else:
					tr.texture = _mna_pip_tex
					pip.add_theme_stylebox_override("panel",
						_create_stylebox(
							Color(0, 0, 0, 0) if filled else EMPTY_BG,
							MNA_BORDER if filled else EMPTY_BORDER, 3, 1))

## Start a slow blink showing spend (fade filled pips) and/or gain (glow empty pips).
## ess_cost/mana_cost = pips being spent; ess_gain/mna_gain = pips being gained (0 = skip).
func start_blink(ess_cost: int, mana_cost: int, ess_gain: int = 0, mna_gain: int = 0) -> void:
	_pip_ess_blink = ess_cost
	_pip_mna_blink = mana_cost
	_pip_ess_gain  = ess_gain
	_pip_mna_gain  = mna_gain
	if _pip_blink_tween:
		_pip_blink_tween.kill()
	_pip_blink_phase = 0.0
	_pip_blink_tween = create_tween().set_loops()
	_pip_blink_tween.tween_method(func(v: float) -> void:
			_pip_blink_phase = v
			_refresh_blink_pips(), 0.0, 1.0, 0.55)
	_pip_blink_tween.tween_method(func(v: float) -> void:
			_pip_blink_phase = v
			_refresh_blink_pips(), 1.0, 0.0, 0.55)

## Stop blinking and restore normal pip styles.
func stop_blink() -> void:
	if _pip_blink_tween:
		_pip_blink_tween.kill()
		_pip_blink_tween = null
	_pip_ess_blink  = 0
	_pip_mna_blink  = 0
	_pip_ess_gain   = 0
	_pip_mna_gain   = 0
	_pip_blink_phase = 0.0
	if _scene.turn_manager:
		update(_scene.turn_manager.essence, _scene.turn_manager.essence_max,
				_scene.turn_manager.mana, _scene.turn_manager.mana_max)

## Animate the pip column border with a gain (green) or spend (red-orange) glow.
## Pulse rises 0->1 in 0.15 s then decays 1->0 in 0.50 s.
func pulse_col(is_essence: bool, is_gain: bool) -> void:
	var panel := _ess_col_panel if is_essence else _mna_col_panel
	if panel == null:
		return
	if is_essence:
		if _ess_col_tween:
			_ess_col_tween.kill()
	else:
		if _mna_col_tween:
			_mna_col_tween.kill()
	var apply_fn := func(v: float) -> void:
		_apply_col_border_style(panel, v, is_gain, is_essence)
	var tween := create_tween()
	if is_essence:
		_ess_col_tween = tween
	else:
		_mna_col_tween = tween
	tween.tween_method(apply_fn, 0.0, 1.0, 0.15)
	tween.tween_method(apply_fn, 1.0, 0.0, 0.50)

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Create a small vertical-gradient texture used for filled pip interiors.
## color_top = colour at the top edge of the pip; color_bot = colour at the bottom edge.
func _make_pip_gradient_tex(color_top: Color, color_bot: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, color_top)
	grad.set_color(1, color_bot)
	var tex := GradientTexture2D.new()
	tex.gradient  = grad
	tex.fill      = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to   = Vector2(0.5, 1.0)
	tex.width     = 4
	tex.height    = 22
	return tex

## Repaint only the blinking pips based on the current _pip_blink_phase (0->1).
## Called every tween tick — fades spent pips, glows gain pips.
func _refresh_blink_pips() -> void:
	if not _scene.turn_manager:
		return
	const MAX_PIPS   := 10
	const ESS_BORDER := Color(0.62, 0.32, 0.88, 0.90)
	const MNA_BORDER := Color(0.22, 0.58, 0.98, 0.90)
	_blink_pip_range(_pip_essence_panels, _pip_essence_rects,
			_scene.turn_manager.essence, _pip_ess_blink, MAX_PIPS)
	_blink_pip_range(_pip_mana_panels, _pip_mana_rects,
			_scene.turn_manager.mana,    _pip_mna_blink, MAX_PIPS)
	_blink_pip_gain_range(_pip_essence_panels,
			_scene.turn_manager.essence, _pip_ess_gain, ESS_BORDER, MAX_PIPS)
	_blink_pip_gain_range(_pip_mana_panels,
			_scene.turn_manager.mana,    _pip_mna_gain, MNA_BORDER, MAX_PIPS)

func _blink_pip_range(panels: Array[Panel], rects: Array[TextureRect],
		current: int, cost: int, max_pips: int) -> void:
	if cost <= 0 or panels.size() != max_pips or current <= 0:
		return
	# The topmost filled pips are the ones that will be spent: indices [first, last].
	var first := max_pips - current
	var last  := first + cost - 1
	for i in range(clampi(first, 0, max_pips - 1), clampi(last, 0, max_pips - 1) + 1):
		var pip := panels[i] as Panel
		var tr  := rects[i]  as TextureRect
		if not pip.visible:
			continue
		# Fade only the gradient fill; the pip border stays visible as an empty-pip outline.
		tr.modulate.a = 1.0 - _pip_blink_phase

## Glow empty pips that will be filled by a gain effect (e.g. CONVERT_RESOURCE).
## Pips just above the current fill level pulse with the resource colour.
func _blink_pip_gain_range(panels: Array[Panel], current: int,
		gain: int, border_color: Color, max_pips: int) -> void:
	if gain <= 0 or panels.size() != max_pips:
		return
	# The empty pips that will be filled sit just above current fill.
	var first := max_pips - current - gain
	var last  := max_pips - current - 1
	for i in range(clampi(first, 0, max_pips - 1), clampi(last, 0, max_pips - 1) + 1):
		var pip := panels[i] as Panel
		# Force-show overflow pips that are hidden because they exceed the current max.
		# update() will restore correct visibility when the blink stops.
		pip.visible = true
		# Pulse the empty pip with resource colour to signal incoming gain.
		var s := StyleBoxFlat.new()
		s.bg_color     = Color(border_color.r, border_color.g, border_color.b,
				_pip_blink_phase * 0.30)
		s.border_color = border_color
		s.set_border_width_all(1)
		s.set_corner_radius_all(3)
		s.shadow_color = Color(border_color.r, border_color.g, border_color.b,
				_pip_blink_phase * 0.75)
		s.shadow_size  = int(_pip_blink_phase * 8.0)
		pip.add_theme_stylebox_override("panel", s)

## Apply the border/background style to a pip column's outer Panel.
## `pulse` 0->1 drives the shadow size and border brightness.
## `is_gain` selects green (gain) vs red-orange (spend) glow color.
func _apply_col_border_style(panel: Panel, pulse: float, is_gain: bool, is_essence: bool) -> void:
	var normal_bg     := Color(0.06, 0.05, 0.12, 0.88)
	var normal_border := Color(0.38, 0.28, 0.58, 0.75) if is_essence \
			else Color(0.22, 0.38, 0.72, 0.75)
	var s := StyleBoxFlat.new()
	s.bg_color = normal_bg
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	if pulse > 0.0:
		var glow := Color(0.22, 0.92, 0.35, 1.0) if is_gain \
				else Color(0.98, 0.32, 0.10, 1.0)
		s.border_color = normal_border.lerp(glow, pulse * 0.85)
		s.shadow_color = Color(glow.r, glow.g, glow.b, pulse * 0.75)
		s.shadow_size  = int(pulse * 14.0)
	else:
		s.border_color = normal_border
		s.shadow_size  = 0
	panel.add_theme_stylebox_override("panel", s)

func _create_stylebox(bg: Color, border: Color, corner_radius: int = 4, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color     = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style

# ---------------------------------------------------------------------------
# Flesh counter widget (Seris)
# ---------------------------------------------------------------------------

const _FLESH_ICON_PATH := "res://assets/art/icons/icon_flesh.png"
const _FLESH_WIDGET_GAP := 14        # gap between essence col left-edge and flesh widget
const _FLESH_ICON_SIZE  := 58
const _FLESH_COUNT_W    := 52
const _FLESH_CAPTION_H  := 16
const _FLESH_TOOLTIP_TITLE := "FLESH"
const _FLESH_TOOLTIP_BODY  := "Gained when a friendly Demon dies."

## Build the flesh widget: icon + "N/5" + "FLESH" caption, anchored bottom-right,
## sitting just left of the essence pip column. Only called when hero has Fleshbind.
func _build_flesh_widget(ui_root: Node, right_margin: int, col_w: int,
		col_gap: int, col_h: int, margin_bottom: int, lbl_h: int) -> void:
	# Essence column's left edge distance from screen-right = right_margin + 2*col_w + col_gap.
	var ess_col_left_from_right: int = right_margin + col_w + col_gap + col_w
	var widget_w: int = _FLESH_ICON_SIZE + 6 + _FLESH_COUNT_W   # icon + small gap + count
	var widget_right_from_right: int = ess_col_left_from_right + _FLESH_WIDGET_GAP
	var widget_left_from_right: int  = widget_right_from_right + widget_w
	# Align widget bottom with the ESSENCE/MANA label bottom so the "FLESH" caption
	# sits on the same baseline as those resource labels.
	var widget_h: int = _FLESH_ICON_SIZE + _FLESH_CAPTION_H + 2
	var widget_bottom_from_bottom: float = float(margin_bottom - lbl_h)

	var root := Control.new()
	root.anchor_left     = 1.0
	root.anchor_right    = 1.0
	root.anchor_top      = 1.0
	root.anchor_bottom   = 1.0
	root.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	root.offset_right    = -float(widget_right_from_right)
	root.offset_left     = -float(widget_left_from_right)
	root.offset_bottom   = -widget_bottom_from_bottom
	root.offset_top      = root.offset_bottom - float(widget_h)
	root.mouse_filter    = Control.MOUSE_FILTER_STOP  # hover for tooltip
	root.mouse_entered.connect(_on_flesh_hover_enter)
	root.mouse_exited.connect(_on_flesh_hover_exit)
	ui_root.add_child(root)
	_flesh_root = root

	# Icon (left side of widget)
	var icon := TextureRect.new()
	icon.anchor_left    = 0.0
	icon.anchor_top     = 0.0
	icon.offset_left    = 0.0
	icon.offset_top     = 0.0
	icon.offset_right   = float(_FLESH_ICON_SIZE)
	icon.offset_bottom  = float(_FLESH_ICON_SIZE)
	icon.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(_FLESH_ICON_PATH):
		icon.texture = load(_FLESH_ICON_PATH) as Texture2D
	root.add_child(icon)
	_flesh_icon = icon

	# Count label "N/5" — right of icon, vertically centred on icon
	var count := Label.new()
	count.anchor_left    = 0.0
	count.anchor_top     = 0.0
	count.offset_left    = float(_FLESH_ICON_SIZE + 6)
	count.offset_right   = float(_FLESH_ICON_SIZE + 6 + _FLESH_COUNT_W)
	count.offset_top     = 6.0
	count.offset_bottom  = float(_FLESH_ICON_SIZE)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	count.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 28)
	count.add_theme_color_override("font_color",           Color(0.92, 0.28, 0.30, 1.0))
	count.add_theme_color_override("font_shadow_color",    Color(0, 0, 0, 0.85))
	count.add_theme_constant_override("shadow_outline_size", 4)
	count.add_theme_constant_override("shadow_offset_x",     0)
	count.add_theme_constant_override("shadow_offset_y",     1)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(count)
	_flesh_count_lbl = count

	# Caption "FLESH" below icon — always-on label so player learns the name.
	var caption := Label.new()
	caption.anchor_left   = 0.0
	caption.anchor_right  = 0.0
	caption.offset_left   = 0.0
	caption.offset_right  = float(_FLESH_ICON_SIZE + 6 + _FLESH_COUNT_W)
	caption.offset_top    = float(_FLESH_ICON_SIZE + 2)
	caption.offset_bottom = float(_FLESH_ICON_SIZE + 2 + _FLESH_CAPTION_H)
	caption.text          = "FLESH"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color",        Color(0.85, 0.55, 0.55, 1.0))
	caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.80))
	caption.add_theme_constant_override("shadow_outline_size", 3)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	_flesh_caption = caption

## Refresh the flesh counter from scene state. Called whenever Flesh changes.
## Pulses the icon + recolors the number when value crosses key thresholds (3, 5).
func update_flesh() -> void:
	if _flesh_root == null or _scene == null:
		return
	var flesh: int = int(_scene.get("player_flesh"))
	var flesh_max: int = int(_scene.get("player_flesh_max"))
	if flesh_max <= 0:
		flesh_max = 5
	_flesh_count_lbl.text = "%d/%d" % [flesh, flesh_max]

	# Colour thresholds: 0 dim, 1-2 pale, 3-4 amber (Soul Forge ready), 5 hot red (capped).
	var col: Color
	if flesh <= 0:
		col = Color(0.55, 0.50, 0.52, 1.0)
	elif flesh <= 2:
		col = Color(0.92, 0.80, 0.78, 1.0)
	elif flesh < flesh_max:
		col = Color(1.00, 0.72, 0.28, 1.0)
	else:
		col = Color(1.00, 0.30, 0.30, 1.0)
	_flesh_count_lbl.add_theme_color_override("font_color", col)

	# Pulse the icon on any change (gain or spend).
	if _prev_flesh != -1 and flesh != _prev_flesh and _flesh_icon != null:
		if _flesh_tween != null and _flesh_tween.is_valid():
			_flesh_tween.kill()
		_flesh_icon.pivot_offset = _flesh_icon.size * 0.5
		_flesh_icon.scale = Vector2.ONE
		_flesh_tween = create_tween()
		var is_gain := flesh > _prev_flesh
		var flash := Color(1.4, 1.2, 1.2, 1.0) if is_gain else Color(1.2, 0.8, 0.8, 1.0)
		_flesh_tween.tween_property(_flesh_icon, "scale", Vector2(1.18, 1.18), 0.10).set_trans(Tween.TRANS_SINE)
		_flesh_tween.parallel().tween_property(_flesh_icon, "modulate", flash, 0.10)
		_flesh_tween.tween_property(_flesh_icon, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)
		_flesh_tween.parallel().tween_property(_flesh_icon, "modulate", Color.WHITE, 0.18)
	_prev_flesh = flesh

## Flesh hover handlers — show a status-style tooltip (matches BoardSlot status tooltip look).
func _on_flesh_hover_enter() -> void:
	if _flesh_tooltip == null or not is_instance_valid(_flesh_tooltip):
		_build_flesh_tooltip_panel()
	var lbl := _flesh_tooltip.get_node_or_null("Label") as Label
	if lbl:
		lbl.text = _FLESH_TOOLTIP_TITLE + "\n" + _FLESH_TOOLTIP_BODY
	# Size estimate — same formula as BoardSlot._show_status_tooltip.
	var raw_lines := (_FLESH_TOOLTIP_TITLE + "\n" + _FLESH_TOOLTIP_BODY).split("\n")
	var line_count: int = raw_lines.size()
	for raw in raw_lines:
		line_count += raw.length() / 22
	var tip_h: int = 14 + line_count * 14
	_flesh_tooltip.size = Vector2(190, tip_h)
	# Anchor tooltip above the flesh widget.
	if _flesh_root:
		var r := _flesh_root.get_global_rect()
		var vp := _flesh_root.get_viewport().get_visible_rect().size
		var x: float = clamp(r.position.x, 8.0, vp.x - _flesh_tooltip.size.x - 8.0)
		var y: float = r.position.y - _flesh_tooltip.size.y - 6.0
		if y < 8.0:
			y = r.position.y + r.size.y + 6.0
		_flesh_tooltip.global_position = Vector2(x, y)
	_flesh_tooltip.visible = true

func _on_flesh_hover_exit() -> void:
	if _flesh_tooltip != null and is_instance_valid(_flesh_tooltip):
		_flesh_tooltip.visible = false

func _build_flesh_tooltip_panel() -> void:
	var p := Panel.new()
	p.name = "FleshTooltip"
	p.visible = false
	p.z_index = 80
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.06, 0.04, 0.10, 0.93)
	style.border_color = Color(0.55, 0.40, 0.75, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.name               = "Label"
	lbl.position           = Vector2(7, 5)
	lbl.size               = Vector2(176, 100)
	lbl.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.98, 1))
	lbl.mouse_filter       = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl)
	# Attach tooltip to the same parent as the flesh widget so positioning uses the same space.
	var parent: Node = _flesh_root.get_parent() if _flesh_root else null
	if parent == null:
		parent = _scene
	parent.add_child(p)
	_flesh_tooltip = p

# ---------------------------------------------------------------------------
# Forge counter widget (Seris + soul_forge talent) — stacked above the flesh widget
# ---------------------------------------------------------------------------

const _FORGE_ICON_PATH := "res://assets/art/icons/icon_forge.png"
const _FORGE_ICON_SIZE  := 58
const _FORGE_COUNT_W    := 52
const _FORGE_CAPTION_H  := 16
const _FORGE_STACK_GAP  := 8         # gap between forge widget bottom and flesh widget top
const _FORGE_TOOLTIP_TITLE := "FORGE"
const _FORGE_TOOLTIP_BODY  := "Sacrificed Demons fill the Forge. At threshold, gain a Forge charge to summon a Grafted Fiend."

func _build_forge_widget(ui_root: Node, right_margin: int, col_w: int,
		col_gap: int, _col_h: int, margin_bottom: int, lbl_h: int) -> void:
	# Match the flesh widget's horizontal placement so they align as a stack.
	var ess_col_left_from_right: int = right_margin + col_w + col_gap + col_w
	var widget_w: int = _FORGE_ICON_SIZE + 6 + _FORGE_COUNT_W
	var widget_right_from_right: int = ess_col_left_from_right + _FLESH_WIDGET_GAP
	var widget_left_from_right: int  = widget_right_from_right + widget_w
	var widget_h: int = _FORGE_ICON_SIZE + _FORGE_CAPTION_H + 2

	# Bottom of the forge widget = top of the flesh widget + small gap.
	# Flesh widget bottom-from-bottom = (margin_bottom - lbl_h); its height = flesh widget_h.
	var flesh_widget_h: int = _FLESH_ICON_SIZE + _FLESH_CAPTION_H + 2
	var widget_bottom_from_bottom: float = float(margin_bottom - lbl_h) + float(flesh_widget_h) + float(_FORGE_STACK_GAP)

	var root := Control.new()
	root.anchor_left     = 1.0
	root.anchor_right    = 1.0
	root.anchor_top      = 1.0
	root.anchor_bottom   = 1.0
	root.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	root.offset_right    = -float(widget_right_from_right)
	root.offset_left     = -float(widget_left_from_right)
	root.offset_bottom   = -widget_bottom_from_bottom
	root.offset_top      = root.offset_bottom - float(widget_h)
	root.mouse_filter    = Control.MOUSE_FILTER_STOP
	root.mouse_entered.connect(_on_forge_hover_enter)
	root.mouse_exited.connect(_on_forge_hover_exit)
	ui_root.add_child(root)
	_forge_root = root

	var icon := TextureRect.new()
	icon.anchor_left   = 0.0
	icon.anchor_top    = 0.0
	icon.offset_left   = 0.0
	icon.offset_top    = 0.0
	icon.offset_right  = float(_FORGE_ICON_SIZE)
	icon.offset_bottom = float(_FORGE_ICON_SIZE)
	icon.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(_FORGE_ICON_PATH):
		icon.texture = load(_FORGE_ICON_PATH) as Texture2D
	root.add_child(icon)
	_forge_icon = icon

	var count := Label.new()
	count.anchor_left    = 0.0
	count.anchor_top     = 0.0
	count.offset_left    = float(_FORGE_ICON_SIZE + 6)
	count.offset_right   = float(_FORGE_ICON_SIZE + 6 + _FORGE_COUNT_W)
	count.offset_top     = 6.0
	count.offset_bottom  = float(_FORGE_ICON_SIZE)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	count.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 28)
	count.add_theme_color_override("font_color",        Color(1.00, 0.72, 0.28, 1.0))
	count.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	count.add_theme_constant_override("shadow_outline_size", 4)
	count.add_theme_constant_override("shadow_offset_x",     0)
	count.add_theme_constant_override("shadow_offset_y",     1)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(count)
	_forge_count_lbl = count

	var caption := Label.new()
	caption.anchor_left   = 0.0
	caption.anchor_right  = 0.0
	caption.offset_left   = 0.0
	caption.offset_right  = float(_FORGE_ICON_SIZE + 6 + _FORGE_COUNT_W)
	caption.offset_top    = float(_FORGE_ICON_SIZE + 2)
	caption.offset_bottom = float(_FORGE_ICON_SIZE + 2 + _FORGE_CAPTION_H)
	caption.text          = "FORGE"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color",        Color(0.95, 0.75, 0.45, 1.0))
	caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.80))
	caption.add_theme_constant_override("shadow_outline_size", 3)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	_forge_caption = caption

## Refresh the forge counter from scene state. Pulses the icon when the value
## changes (gain on Demon sacrifice, reset when a Forge charge is consumed).
func update_forge() -> void:
	if _forge_root == null or _scene == null:
		return
	var fc:  int = int(_scene.get("forge_counter"))
	var cap: int = int(_scene.get("forge_counter_threshold"))
	if cap <= 0:
		cap = 3
	_forge_count_lbl.text = "%d/%d" % [fc, cap]

	# Colour: dim when 0, warm amber as it ramps, hot when ready to fire.
	var col: Color
	if fc <= 0:
		col = Color(0.65, 0.55, 0.40, 1.0)
	elif fc < cap:
		col = Color(1.00, 0.78, 0.32, 1.0)
	else:
		col = Color(1.00, 0.55, 0.20, 1.0)
	_forge_count_lbl.add_theme_color_override("font_color", col)

	if _prev_forge != -1 and fc != _prev_forge and _forge_icon != null:
		if _forge_tween != null and _forge_tween.is_valid():
			_forge_tween.kill()
		_forge_icon.pivot_offset = _forge_icon.size * 0.5
		_forge_icon.scale = Vector2.ONE
		_forge_tween = create_tween()
		var is_gain := fc > _prev_forge
		var flash := Color(1.4, 1.2, 0.9, 1.0) if is_gain else Color(1.2, 0.9, 0.7, 1.0)
		_forge_tween.tween_property(_forge_icon, "scale", Vector2(1.18, 1.18), 0.10).set_trans(Tween.TRANS_SINE)
		_forge_tween.parallel().tween_property(_forge_icon, "modulate", flash, 0.10)
		_forge_tween.tween_property(_forge_icon, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)
		_forge_tween.parallel().tween_property(_forge_icon, "modulate", Color.WHITE, 0.18)
	_prev_forge = fc

func _on_forge_hover_enter() -> void:
	if _forge_tooltip == null or not is_instance_valid(_forge_tooltip):
		_build_forge_tooltip_panel()
	var lbl := _forge_tooltip.get_node_or_null("Label") as Label
	if lbl:
		lbl.text = _FORGE_TOOLTIP_TITLE + "\n" + _FORGE_TOOLTIP_BODY
	var raw_lines := (_FORGE_TOOLTIP_TITLE + "\n" + _FORGE_TOOLTIP_BODY).split("\n")
	var line_count: int = raw_lines.size()
	for raw in raw_lines:
		line_count += raw.length() / 22
	var tip_h: int = 14 + line_count * 14
	_forge_tooltip.size = Vector2(190, tip_h)
	if _forge_root:
		var r := _forge_root.get_global_rect()
		var vp := _forge_root.get_viewport().get_visible_rect().size
		var x: float = clamp(r.position.x, 8.0, vp.x - _forge_tooltip.size.x - 8.0)
		var y: float = r.position.y - _forge_tooltip.size.y - 6.0
		if y < 8.0:
			y = r.position.y + r.size.y + 6.0
		_forge_tooltip.global_position = Vector2(x, y)
	_forge_tooltip.visible = true

func _on_forge_hover_exit() -> void:
	if _forge_tooltip != null and is_instance_valid(_forge_tooltip):
		_forge_tooltip.visible = false

func _build_forge_tooltip_panel() -> void:
	var p := Panel.new()
	p.name = "ForgeTooltip"
	p.visible = false
	p.z_index = 80
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.06, 0.04, 0.10, 0.93)
	style.border_color = Color(0.75, 0.55, 0.30, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.name               = "Label"
	lbl.position           = Vector2(7, 5)
	lbl.size               = Vector2(176, 100)
	lbl.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.98, 0.92, 0.85, 1))
	lbl.mouse_filter       = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl)
	var parent: Node = _forge_root.get_parent() if _forge_root else null
	if parent == null:
		parent = _scene
	parent.add_child(p)
	_forge_tooltip = p
