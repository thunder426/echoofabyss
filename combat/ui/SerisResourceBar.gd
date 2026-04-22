class_name SerisResourceBar
extends VBoxContainer
## Seris, the Fleshbinder — resource bar showing Flesh pips (0–5) and, when the
## Soul Forge talent is unlocked, Forge Counter pips (0–2 or 0–3).
##
## Driven by CombatScene._on_flesh_changed / _on_forge_changed hooks which call
## refresh() to re-read scene.player_flesh / scene.forge_counter. This keeps
## the bar passive — handlers update scene state and don't need a UI reference.
##
## Visibility is determined by the current hero:
##   - Flesh row: shown when the current hero's "fleshbind" passive is active.
##   - Forge row: shown when the current hero has the "soul_forge" talent unlocked.
## On other heroes / runs the bar is invisible and takes no layout space.

const _PIP_ICON_FILLED := "res://assets/art/icons/icon_flesh_filled.png"
const _PIP_ICON_EMPTY  := "res://assets/art/icons/icon_flesh_empty.png"
const _FORGE_ICON_FILLED := "res://assets/art/icons/icon_forge_filled.png"
const _FORGE_ICON_EMPTY  := "res://assets/art/icons/icon_forge_empty.png"

const _PIP_SIZE := Vector2(18, 18)
const _SKILL_ICON_SIZE := Vector2(56, 56)

## Glow color pulsed on castable skill icons.
const _GLOW_COLOR_CASTABLE := Color(1.35, 1.20, 0.85, 1.0)
const _GLOW_COLOR_IDLE     := Color(1.00, 1.00, 1.00, 1.0)
const _GLOW_COLOR_DISABLED := Color(0.45, 0.45, 0.45, 1.0)

var _scene: Object = null
var _skill_row: HBoxContainer = null
## Per-skill castable state so refresh() only restarts the glow tween on change.
var _skill_castable: Dictionary = {}  # button -> bool
var _skill_tweens:   Dictionary = {}  # button -> Tween

var _flesh_row:      HBoxContainer = null
var _flesh_pips:     Array[TextureRect] = []
var _flesh_label:    Label = null

var _forge_row:      HBoxContainer = null
var _forge_pips:     Array[TextureRect] = []
var _forge_label:    Label = null

## Soul Forge activation button — visible only when the soul_forge talent is active.
## Click: spend 3 Flesh → summon Grafted Fiend. Disabled when Flesh < 3.
var _forge_btn:      Button = null
const _FORGE_BTN_FLESH_COST := 3
const _FORGE_BTN_SUMMON_ID  := "grafted_fiend"

## Corrupt Flesh activation button — visible only when the corrupt_flesh talent is active.
## Click: enter target mode, then click a friendly Demon to apply Corruption.
## Disabled when Flesh < 1, already used this turn, or no valid targets.
var _corrupt_btn:    Button = null

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

## Create and return a new resource bar wired to the given scene.
## Returns null if the current hero has neither a Flesh nor a Forge resource —
## caller should treat null as "no bar needed for this hero".
static func maybe_create(scene: Object) -> SerisResourceBar:
	var hero_id: String = GameManager.current_hero
	var has_flesh: bool   = HeroDatabase.has_passive(hero_id, "fleshbind")
	var has_forge: bool   = GameManager.has_talent("soul_forge")
	var has_corrupt: bool = GameManager.has_talent("corrupt_flesh")
	if not has_flesh and not has_forge and not has_corrupt:
		return null
	var bar := SerisResourceBar.new()
	bar._scene = scene
	bar._build(has_flesh, has_forge, has_corrupt)
	return bar

func _build(has_flesh: bool, has_forge: bool, has_corrupt: bool) -> void:
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Flesh row moved to PipBar (big icon + count next to essence/mana columns).
	# SerisResourceBar still keeps the Forge row + skill buttons below.

	if has_forge:
		_forge_row = _build_pip_row("Forge")
		_forge_label = _forge_row.get_node("Label") as Label
		var fcap: int = int(_scene.get("forge_counter_threshold")) if _scene.get("forge_counter_threshold") != null else 3
		_forge_pips = _spawn_pips(_forge_row, fcap, _FORGE_ICON_EMPTY)
		add_child(_forge_row)

	if has_forge or has_corrupt:
		_skill_row = HBoxContainer.new()
		_skill_row.add_theme_constant_override("separation", 8)
		_skill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_skill_row)

	if has_forge:
		_forge_btn = _make_skill_button(
			"soul_forge",
			"Forge Fiend — spend %d Flesh to summon a Grafted Fiend." % _FORGE_BTN_FLESH_COST,
			_on_forge_btn_pressed)
		_skill_row.add_child(_forge_btn)

	if has_corrupt:
		_corrupt_btn = _make_skill_button(
			"corrupt_flesh",
			"Corrupt Demon — spend 1 Flesh to apply Corruption to a friendly Demon. Once per turn.",
			_on_corrupt_btn_pressed)
		_skill_row.add_child(_corrupt_btn)

	refresh()

## Build an icon-only active-skill button. The icon is loaded from
## TalentData.icon_path so selection UI, hover tooltip, and the active button
## all pull from the same source. Hover shows a tooltip; castable state pulses
## the icon with a warm glow.
func _make_skill_button(talent_id: String, extra_body: String, cb: Callable) -> Button:
	var td: TalentData = TalentDatabase.get_talent(talent_id)
	var btn := Button.new()
	btn.custom_minimum_size = _SKILL_ICON_SIZE
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal",   _skill_panel_style(false))
	btn.add_theme_stylebox_override("hover",    _skill_panel_style(true))
	btn.add_theme_stylebox_override("pressed",  _skill_panel_style(true))
	btn.add_theme_stylebox_override("disabled", _skill_panel_style(false))
	if td != null and td.icon_path != "" and ResourceLoader.exists(td.icon_path):
		btn.icon = load(td.icon_path) as Texture2D
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", 48)
	btn.pressed.connect(cb)
	_skill_castable[btn] = false

	# Hover tooltip — built once, shown/hidden on enter/exit.
	var tip := _build_skill_tooltip(td, extra_body)
	btn.mouse_entered.connect(func() -> void:
		_position_tooltip_above(tip, btn)
		tip.visible = true
	)
	btn.mouse_exited.connect(func() -> void:
		tip.visible = false
	)
	btn.tree_exiting.connect(func() -> void:
		if is_instance_valid(tip):
			tip.queue_free()
	)
	return btn

func _skill_panel_style(highlight: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.04, 0.12, 0.85) if not highlight else Color(0.14, 0.08, 0.20, 0.95)
	sb.border_color = Color(0.55, 0.30, 0.85, 0.90) if highlight else Color(0.30, 0.18, 0.45, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb

func _build_skill_tooltip(td: TalentData, extra_body: String) -> PanelContainer:
	var tip := PanelContainer.new()
	tip.visible = false
	tip.z_index = 80
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.custom_minimum_size = Vector2(260, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.02, 0.10, 0.97)
	sb.border_color = Color(0.55, 0.30, 0.85, 0.90)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	tip.add_theme_stylebox_override("panel", sb)
	# Attach to a CanvasLayer ancestor if available so tooltip renders above the board.
	var ui_root: Node = get_tree().root
	for anc in get_tree().get_nodes_in_group("ui_root"):
		ui_root = anc
		break
	ui_root.add_child(tip)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   14)
	margin.add_theme_constant_override("margin_right",  14)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	if td != null:
		var title := Label.new()
		title.text = td.talent_name
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(0.92, 0.85, 1.0, 1.0))
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(title)

		var desc := Label.new()
		desc.text = td.description
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.82, 0.78, 0.88, 1.0))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(240, 0)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc)

	if extra_body != "":
		var body := Label.new()
		body.text = extra_body
		body.add_theme_font_size_override("font_size", 12)
		body.add_theme_color_override("font_color", Color(0.70, 0.90, 0.75, 1.0))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(240, 0)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(body)

	return tip

func _position_tooltip_above(tip: PanelContainer, anchor: Control) -> void:
	if not tip.is_inside_tree() or not anchor.is_inside_tree():
		return
	var ms := tip.get_minimum_size()
	if ms.y > 0:
		tip.size = ms
	var anchor_rect := anchor.get_global_rect()
	var viewport_size := get_viewport().get_visible_rect().size
	var x: float = clamp(anchor_rect.position.x, 8.0, viewport_size.x - tip.size.x - 8.0)
	var y: float = anchor_rect.position.y - tip.size.y - 8.0
	if y < 8.0:
		y = anchor_rect.position.y + anchor_rect.size.y + 8.0
	tip.position = Vector2(x, y)

## Update icon modulate + glow tween based on castable state.
func _set_skill_castable(btn: Button, castable: bool, disabled: bool) -> void:
	if btn == null:
		return
	btn.disabled = disabled
	var was: bool = bool(_skill_castable.get(btn, false))
	if was == castable and _skill_tweens.has(btn):
		return
	_skill_castable[btn] = castable
	var old_tween: Tween = _skill_tweens.get(btn)
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	if disabled:
		btn.modulate = _GLOW_COLOR_DISABLED
		return
	if not castable:
		btn.modulate = _GLOW_COLOR_IDLE
		return
	# Castable — pulse between idle and glow.
	var tw := create_tween().set_loops()
	tw.tween_property(btn, "modulate", _GLOW_COLOR_CASTABLE, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(btn, "modulate", _GLOW_COLOR_IDLE,     0.6).set_trans(Tween.TRANS_SINE)
	_skill_tweens[btn] = tw

func _build_pip_row(caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = caption
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.60, 1))
	lbl.custom_minimum_size = Vector2(40, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	return row

func _spawn_pips(row: HBoxContainer, count: int, empty_icon: String) -> Array[TextureRect]:
	var pips: Array[TextureRect] = []
	var empty_tex: Texture2D = load(empty_icon) as Texture2D
	for i in count:
		var pip := TextureRect.new()
		pip.custom_minimum_size = _PIP_SIZE
		pip.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pip.texture      = empty_tex
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
		pips.append(pip)
	return pips

# ---------------------------------------------------------------------------
# Refresh — called from CombatScene after state changes
# ---------------------------------------------------------------------------

## Re-read counters from the scene and update pip fills.
func refresh() -> void:
	if _scene == null:
		return
	if _forge_row != null:
		var fc: int        = int(_scene.get("forge_counter"))
		var forge_cap: int = int(_scene.get("forge_counter_threshold"))
		_set_pips(_forge_pips, fc, forge_cap, _FORGE_ICON_FILLED, _FORGE_ICON_EMPTY)
		if _forge_label:
			_forge_label.text = "Forge %d/%d" % [fc, forge_cap]
	if _forge_btn != null:
		var flesh: int = int(_scene.get("player_flesh"))
		var castable: bool = flesh >= _FORGE_BTN_FLESH_COST
		_set_skill_castable(_forge_btn, castable, not castable)
	if _corrupt_btn != null:
		var flesh: int = int(_scene.get("player_flesh"))
		var used: bool = bool(_scene.get("_seris_corrupt_used_this_turn"))
		var castable: bool = flesh >= 1 and not used
		_set_skill_castable(_corrupt_btn, castable, not castable)

## Click handler for the Soul Forge button. Delegates to the scene so the
## actual game-state mutation stays symmetric with sim (sim triggers the
## same _soul_forge_activate method via its agent profile if ever needed).
func _on_forge_btn_pressed() -> void:
	if _scene == null:
		return
	if _scene.has_method("_soul_forge_activate"):
		_scene._soul_forge_activate()
	refresh()

func _on_corrupt_btn_pressed() -> void:
	if _scene == null:
		return
	if _scene.has_method("_seris_corrupt_activate"):
		_scene._seris_corrupt_activate()
	refresh()

func _set_pips(pips: Array[TextureRect], value: int, cap: int, filled_icon: String, empty_icon: String) -> void:
	var filled_tex: Texture2D = load(filled_icon) as Texture2D
	var empty_tex:  Texture2D = load(empty_icon) as Texture2D
	for i in pips.size():
		var pip := pips[i]
		if i >= cap:
			pip.visible = false
			continue
		pip.visible = true
		pip.texture = filled_tex if i < value else empty_tex

