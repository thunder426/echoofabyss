## RelicBar.gd
## UI component showing equipped relics as clickable icons with charge/cooldown overlays.
## Cooldown is shown as a clock-sweep dim overlay (like a pie timer).
## Hover shows a detailed tooltip panel. Click to activate.
class_name RelicBar
extends HBoxContainer

signal relic_activated(index: int)
signal relic_hovered(effect_id: String)
signal relic_unhovered()

const ICON_SIZE := Vector2(76, 76)
const COLOR_READY    := Color(0.70, 0.50, 1.00, 1.0)
const COLOR_SPENT    := Color(0.20, 0.18, 0.25, 0.4)
const COLOR_CHARGES  := Color(0.90, 0.80, 0.20, 1.0)
const COLOR_CD_OVERLAY := Color(0.0, 0.0, 0.0, 0.65)
const COLOR_NAME     := Color(0.85, 0.60, 1.0, 1.0)
const COLOR_DESC     := Color(0.85, 0.85, 0.95, 1.0)
const COLOR_STATS    := Color(0.55, 0.52, 0.60, 1.0)
const COLOR_TIP_BG   := Color(0.06, 0.04, 0.12, 0.95)
const COLOR_TIP_BORDER := Color(0.55, 0.30, 0.80, 0.90)

var _runtime: RelicRuntime
var _buttons: Array[Button] = []
var _charge_labels: Array[Label] = []
var _cd_overlays: Array[Control] = []  # ClockOverlay instances
var _tooltip_layer: CanvasLayer
var _tooltip: PanelContainer
var _tip_name: Label
var _tip_desc: Label
var _tip_stats: Label

# ---------------------------------------------------------------------------
# Clock overlay — draws a pie-shaped dim sector like a clock timer
# ---------------------------------------------------------------------------

class ClockOverlay extends Control:
	## Fraction of the clock that is dimmed (0.0 = clear, 1.0 = fully dimmed).
	## The dim sector sweeps clockwise from 12 o'clock.
	var fraction: float = 0.0:
		set(v):
			fraction = v
			queue_redraw()

	var overlay_color: Color = Color(0.0, 0.0, 0.0, 0.65)

	func _draw() -> void:
		if fraction <= 0.0:
			return
		if fraction >= 1.0:
			draw_rect(Rect2(Vector2.ZERO, size), overlay_color)
			return
		# Draw a pie sector counter-clockwise from 12 o'clock.
		# fraction = 1/3 → dim the 8→12 clock portion (counter-clockwise sweep).
		var center := size / 2.0
		var radius := maxf(size.x, size.y)
		var start_angle: float = -PI / 2.0  # 12 o'clock
		var sweep: float = fraction * TAU    # how much to dim
		# Sweep counter-clockwise = negative direction
		var points: PackedVector2Array = PackedVector2Array()
		points.append(center)
		var segments: int = maxi(12, int(fraction * 48))
		for i in segments + 1:
			var angle: float = start_angle - sweep * (float(i) / float(segments))
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(points, overlay_color)

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(runtime: RelicRuntime) -> void:
	_runtime = runtime
	_build_tooltip()
	_build_icons()
	refresh()

func _build_tooltip() -> void:
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.layer = 100
	add_child(_tooltip_layer)

	_tooltip = PanelContainer.new()
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_TIP_BG
	style.border_color = COLOR_TIP_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left   = 14
	style.content_margin_right  = 14
	style.content_margin_top    = 10
	style.content_margin_bottom = 10
	_tooltip.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(vbox)

	_tip_name = Label.new()
	_tip_name.add_theme_font_size_override("font_size", 18)
	_tip_name.add_theme_color_override("font_color", COLOR_NAME)
	_tip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tip_name)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", COLOR_TIP_BORDER)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	_tip_desc = Label.new()
	_tip_desc.add_theme_font_size_override("font_size", 14)
	_tip_desc.add_theme_color_override("font_color", COLOR_DESC)
	_tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_desc.custom_minimum_size.x = 220
	_tip_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tip_desc)

	_tip_stats = Label.new()
	_tip_stats.add_theme_font_size_override("font_size", 12)
	_tip_stats.add_theme_color_override("font_color", COLOR_STATS)
	_tip_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tip_stats)

	_tooltip_layer.add_child(_tooltip)

func _build_icons() -> void:
	for child in get_children():
		if child == _tooltip_layer:
			continue
		child.queue_free()
	_buttons.clear()
	_charge_labels.clear()
	_cd_overlays.clear()

	for i in _runtime.relics.size():
		var rs: RelicRuntime.RelicState = _runtime.relics[i]
		var container := Control.new()
		container.custom_minimum_size = ICON_SIZE
		container.clip_contents = true

		# Main button with icon
		var btn := Button.new()
		btn.custom_minimum_size = ICON_SIZE
		btn.set_position(Vector2.ZERO)
		btn.set_size(ICON_SIZE)
		btn.pressed.connect(_on_relic_clicked.bind(i))
		btn.mouse_entered.connect(_on_hover_enter.bind(i, container))
		btn.mouse_exited.connect(_on_hover_exit.bind(container))
		if rs.data.icon_path != "" and ResourceLoader.exists(rs.data.icon_path):
			var icon_style := StyleBoxTexture.new()
			icon_style.texture = load(rs.data.icon_path)
			btn.add_theme_stylebox_override("normal", icon_style)
			btn.add_theme_stylebox_override("hover", icon_style)
			btn.add_theme_stylebox_override("pressed", icon_style)
			btn.add_theme_stylebox_override("disabled", icon_style)
		container.add_child(btn)
		_buttons.append(btn)

		# Clock-sweep cooldown overlay
		var cd_overlay := ClockOverlay.new()
		cd_overlay.overlay_color = COLOR_CD_OVERLAY
		cd_overlay.set_position(Vector2.ZERO)
		cd_overlay.set_size(ICON_SIZE)
		cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_overlay.visible = false
		container.add_child(cd_overlay)
		_cd_overlays.append(cd_overlay)

		# Charge counter (bottom-right)
		var charge_lbl := Label.new()
		charge_lbl.add_theme_font_size_override("font_size", 14)
		charge_lbl.add_theme_color_override("font_color", COLOR_CHARGES)
		charge_lbl.set_position(Vector2(ICON_SIZE.x - 18, ICON_SIZE.y - 20))
		charge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(charge_lbl)
		_charge_labels.append(charge_lbl)

		add_child(container)

## Update visual state of all relic buttons.
func refresh() -> void:
	if _runtime == null:
		return
	for i in _runtime.relics.size():
		if i >= _buttons.size():
			break
		var rs: RelicRuntime.RelicState = _runtime.relics[i]
		var btn: Button = _buttons[i]
		var charge_lbl: Label = _charge_labels[i]
		var cd_overlay: ClockOverlay = _cd_overlays[i] as ClockOverlay

		# Update charge display
		charge_lbl.text = str(rs.charges_remaining)

		# Button state
		var can_use: bool = _runtime.can_activate(i)
		btn.disabled = not can_use

		if rs.charges_remaining <= 0:
			# Spent: full dim, no overlay, no charge
			btn.modulate = COLOR_SPENT
			cd_overlay.visible = false
			charge_lbl.visible = false
		elif rs.cooldown_remaining > 0:
			# On cooldown: show clock sweep
			btn.modulate = COLOR_READY
			cd_overlay.visible = true
			cd_overlay.fraction = float(rs.cooldown_remaining) / float(rs.data.cooldown)
			charge_lbl.visible = true
		elif _runtime.activated_this_turn:
			# Already used a relic this turn
			btn.modulate = Color(0.55, 0.45, 0.70, 0.8)
			cd_overlay.visible = false
			charge_lbl.visible = true
		else:
			# Ready to use
			btn.modulate = COLOR_READY
			cd_overlay.visible = false
			charge_lbl.visible = true

# ---------------------------------------------------------------------------
# Hover tooltip
# ---------------------------------------------------------------------------

func _on_hover_enter(index: int, container: Control) -> void:
	if index < 0 or index >= _runtime.relics.size():
		return
	var rs: RelicRuntime.RelicState = _runtime.relics[index]

	# Glow effect when ready
	if _runtime.can_activate(index):
		var glow_tween := create_tween().set_loops()
		glow_tween.set_meta("glow_owner", container)
		container.set_meta("glow_tween", glow_tween)
		glow_tween.tween_property(container, "modulate", Color(1.3, 1.2, 1.5, 1.0), 0.4)
		glow_tween.tween_property(container, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)

	# Notify scene for resource preview (e.g. mana pip blink)
	if _runtime.can_activate(index):
		relic_hovered.emit(rs.data.effect_id)

	_tip_name.text = rs.data.relic_name
	_tip_desc.text = rs.data.description

	var status: String
	if rs.charges_remaining <= 0:
		status = "Spent"
	elif rs.cooldown_remaining > 0:
		status = "Ready in %d turn(s)" % rs.cooldown_remaining
	elif _runtime.activated_this_turn:
		status = "Already used a relic this turn"
	else:
		status = "Ready — click to activate"

	_tip_stats.text = "Charges: %d / %d  |  Cooldown: %d turns\n%s" % [
		rs.charges_remaining, rs.data.charges + rs.bonus_charges,
		rs.data.cooldown, status]

	var btn: Button = _buttons[index]
	var btn_global: Vector2 = btn.global_position
	_tooltip.reset_size()
	var tip_size: Vector2 = _tooltip.size
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var tip_x: float = btn_global.x + ICON_SIZE.x - tip_size.x
	var tip_y: float = btn_global.y - tip_size.y - 12
	tip_x = clampf(tip_x, 8.0, vp_size.x - tip_size.x - 8.0)
	tip_y = maxf(tip_y, 8.0)
	_tooltip.position = Vector2(tip_x, tip_y)
	_tooltip.visible = true

func _on_hover_exit(container: Control) -> void:
	_tooltip.visible = false
	relic_unhovered.emit()
	# Stop glow and reset modulate
	var tween = container.get_meta("glow_tween") if container.has_meta("glow_tween") else null
	if tween != null and tween is Tween:
		(tween as Tween).kill()
		container.remove_meta("glow_tween")
	container.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_relic_clicked(index: int) -> void:
	if _runtime != null and _runtime.can_activate(index):
		relic_activated.emit(index)
