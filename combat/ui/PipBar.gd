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

	if _scene.turn_manager:
		update(_scene.turn_manager.essence, _scene.turn_manager.essence_max,
				_scene.turn_manager.mana, _scene.turn_manager.mana_max)

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
