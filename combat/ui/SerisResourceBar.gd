class_name SerisResourceBar
extends VBoxContainer
## Seris, the Fleshbinder — active skill buttons (Soul Forge, Corrupt Flesh).
## The Flesh and Forge counters live in PipBar; this bar only owns clickable
## abilities. Each button has a hover tooltip with name + description + cost.
##
## Driven by CombatScene._on_forge_changed / _on_flesh_changed hooks which call
## refresh() to re-evaluate castable / disabled state per button.
##
## Visibility is determined by talents:
##   - Soul Forge button:   shown when "soul_forge" talent is unlocked.
##   - Corrupt Flesh button: shown when "corrupt_flesh" talent is unlocked.
## On other heroes / runs the bar is invisible and takes no layout space.

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
	var has_forge: bool   = GameManager.has_talent("soul_forge")
	var has_corrupt: bool = GameManager.has_talent("corrupt_flesh")
	if not has_forge and not has_corrupt:
		return null
	var bar := SerisResourceBar.new()
	bar._scene = scene
	bar._build(has_forge, has_corrupt)
	return bar

func _build(has_forge: bool, has_corrupt: bool) -> void:
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Flesh + Forge counters live in PipBar (big icon + N/M label next to the
	# essence / mana columns). SerisResourceBar only owns the active skill buttons.

	if has_forge or has_corrupt:
		_skill_row = HBoxContainer.new()
		_skill_row.add_theme_constant_override("separation", 8)
		_skill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_skill_row)

	if has_forge:
		_forge_btn = _make_skill_button(
			"soul_forge",
			"Spend %d Flesh: Summon a Grafted Fiend." % _FORGE_BTN_FLESH_COST,
			_on_forge_btn_pressed)
		_skill_row.add_child(_forge_btn)

	if has_corrupt:
		_corrupt_btn = _make_skill_button(
			"corrupt_flesh",
			"Spend 1 Flesh: Apply Corruption to a friendly Demon. Once per turn.",
			_on_corrupt_btn_pressed)
		_skill_row.add_child(_corrupt_btn)

	refresh()

## Build an icon-only active-skill button. The icon is loaded from
## TalentData.icon_path. Hover shows a styled tooltip matching the BoardSlot
## status tooltip; castable state pulses the icon with a warm glow.
func _make_skill_button(talent_id: String, tip_body: String, cb: Callable) -> Button:
	var td: TalentData = TalentDatabase.get_talent(talent_id)
	var btn := Button.new()
	btn.custom_minimum_size = _SKILL_ICON_SIZE
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
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

	# Hover tooltip — lazy-built Panel matching the BoardSlot status tooltip.
	# Built on first hover so the bar is already in the scene tree by then.
	var tip_ref: Array = [null]
	btn.mouse_entered.connect(func() -> void:
		if tip_ref[0] == null or not is_instance_valid(tip_ref[0]):
			tip_ref[0] = _build_status_style_tooltip()
		_show_skill_tooltip(tip_ref[0], btn, tip_body)
	)
	btn.mouse_exited.connect(func() -> void:
		if tip_ref[0] != null and is_instance_valid(tip_ref[0]):
			tip_ref[0].visible = false
	)
	btn.tree_exiting.connect(func() -> void:
		if tip_ref[0] != null and is_instance_valid(tip_ref[0]):
			tip_ref[0].queue_free()
	)
	return btn

func _skill_panel_style(highlight: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.04, 0.12, 0.85) if not highlight else Color(0.14, 0.08, 0.20, 0.95)
	sb.border_color = Color(0.55, 0.30, 0.85, 0.90) if highlight else Color(0.30, 0.18, 0.45, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb

## Build a Panel styled like BoardSlot._build_status_tooltip_panel — small,
## dark-violet bordered, fixed 190px width with autowrap label inside.
##
## Marked top_level so its position/size are in global coordinates regardless
## of where it is parented (the parent VBoxContainer's layout doesn't apply).
## Parented to the bar itself — guaranteed to be in the scene tree at hover
## time, since the tooltip is lazy-built on first mouse_entered.
func _build_status_style_tooltip() -> Panel:
	var p := Panel.new()
	p.name = "SkillTooltip"
	p.visible = false
	p.top_level = true
	p.z_index = 200
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
	add_child(p)
	return p

## Position the tooltip above the button (or below if the button is too close
## to the top of the viewport) and make it visible.
func _show_skill_tooltip(tip: Panel, anchor: Control, body: String) -> void:
	if not tip.is_inside_tree() or not anchor.is_inside_tree():
		return
	var lbl := tip.get_node_or_null("Label") as Label
	if lbl:
		lbl.text = body
	# Estimate panel height from line count (wrapping ~22 chars per line, font 10).
	var raw_lines := body.split("\n")
	var line_count: int = raw_lines.size()
	for raw in raw_lines:
		line_count += raw.length() / 22
	var tip_h: int = 14 + line_count * 14
	tip.size = Vector2(190, tip_h)
	var anchor_rect := anchor.get_global_rect()
	var vp := anchor.get_viewport().get_visible_rect().size
	var x: float = clamp(anchor_rect.position.x, 8.0, vp.x - tip.size.x - 8.0)
	var y: float = anchor_rect.position.y - tip.size.y - 6.0
	if y < 8.0:
		y = anchor_rect.position.y + anchor_rect.size.y + 6.0
	tip.global_position = Vector2(x, y)
	tip.visible = true

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

# ---------------------------------------------------------------------------
# Refresh — called from CombatScene after state changes
# ---------------------------------------------------------------------------

## Re-evaluate castable / disabled state for each skill button.
func refresh() -> void:
	if _scene == null:
		return
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
