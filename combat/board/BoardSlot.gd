## BoardSlot.gd
## Represents one of the 5 board slots on either side.
## Attach this script to a Panel or Control node in the CombatScene.
## The slot visually shows the minion occupying it (or an empty state).
class_name BoardSlot
extends Panel

# ---------------------------------------------------------------------------
# Signals — CombatScene connects to these
# ---------------------------------------------------------------------------

## Player clicked an empty slot — they may want to play a minion here
signal slot_clicked_empty(slot: BoardSlot)

## Player clicked a slot with a minion — they may want to attack or inspect it
signal slot_clicked_occupied(slot: BoardSlot, minion: MinionInstance)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Which side this slot belongs to ("player" or "enemy")
var slot_owner: String = "player"

## Index of this slot on the board (0–4, left to right)
var index: int = 0

## The minion currently in this slot, or null if empty
var minion: MinionInstance = null

# ---------------------------------------------------------------------------
# Visual highlight states
# ---------------------------------------------------------------------------

## Highlight modes for UI feedback
enum HighlightMode { NONE, VALID_TARGET, SELECTED, INVALID }

var _highlight_mode: HighlightMode = HighlightMode.NONE

# Colour constants — replace with actual StyleBox in the full UI
const COLOR_NORMAL   := Color(0.15, 0.15, 0.20, 1.0)
const COLOR_VALID    := Color(0.20, 0.60, 0.20, 0.8)
const COLOR_SELECTED := Color(0.80, 0.70, 0.10, 0.9)
const COLOR_INVALID  := Color(0.60, 0.10, 0.10, 0.6)

# ---------------------------------------------------------------------------
# Child label nodes — created programmatically so no .tscn edits needed
# ---------------------------------------------------------------------------

var _name_label: Label
var _type_label: Label
var _stats_label: Label
var _state_label: Label

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_labels()
	gui_input.connect(_on_gui_input)
	_refresh_visuals()

func _build_labels() -> void:
	_name_label = _make_label(Vector2(4, 4), Vector2(172, 22), 13)
	_type_label = _make_label(Vector2(4, 28), Vector2(172, 18), 11)
	_stats_label = _make_label(Vector2(4, 160), Vector2(172, 20), 12)
	_state_label = _make_label(Vector2(4, 140), Vector2(172, 18), 11)
	_state_label.modulate = Color(1.0, 0.4, 0.4, 1.0)

func _make_label(pos: Vector2, sz: Vector2, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.position = pos
	lbl.size = sz
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.clip_text = true
	add_child(lbl)
	return lbl

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_empty():
			slot_clicked_empty.emit(self)
		else:
			slot_clicked_occupied.emit(self, minion)

# ---------------------------------------------------------------------------
# Minion placement
# ---------------------------------------------------------------------------

func is_empty() -> bool:
	return minion == null

func place_minion(m: MinionInstance) -> void:
	minion = m
	minion.slot_index = index
	_refresh_visuals()

func remove_minion() -> void:
	minion = null
	_refresh_visuals()

# ---------------------------------------------------------------------------
# Highlight control
# ---------------------------------------------------------------------------

func set_highlight(mode: HighlightMode) -> void:
	_highlight_mode = mode
	_refresh_visuals()

func clear_highlight() -> void:
	set_highlight(HighlightMode.NONE)

# ---------------------------------------------------------------------------
# Visuals (placeholder — will be replaced with proper art later)
# ---------------------------------------------------------------------------

func _refresh_visuals() -> void:
	match _highlight_mode:
		HighlightMode.VALID_TARGET:
			add_theme_color_override("bg_color", COLOR_VALID)
		HighlightMode.SELECTED:
			add_theme_color_override("bg_color", COLOR_SELECTED)
		HighlightMode.INVALID:
			add_theme_color_override("bg_color", COLOR_INVALID)
		_:
			add_theme_color_override("bg_color", COLOR_NORMAL)

	# Update minion info labels
	if _name_label == null:
		return
	if minion == null:
		_name_label.text = ""
		_type_label.text = ""
		_stats_label.text = ""
		_state_label.text = ""
		return

	_name_label.text = minion.card_data.card_name
	_type_label.text = _minion_type_string(minion.card_data.minion_type)
	_stats_label.text = "ATK:%s  HP:%s" % [str(minion.effective_atk()), str(minion.current_health)]

	# Taunt is always shown — it's critical targeting information
	if minion.has_taunt():
		_state_label.text = "[ Taunt ]"
	# Exhausted is only relevant for the player to know (enemy state doesn't matter to them)
	elif minion.owner == "player" and minion.state == Enums.MinionState.EXHAUSTED:
		_state_label.text = "[ Exhausted ]"
	else:
		_state_label.text = ""

func _minion_type_string(t: Enums.MinionType) -> String:
	match t:
		Enums.MinionType.DEMON:  return "Demon"
		Enums.MinionType.SPIRIT: return "Spirit"
		Enums.MinionType.BEAST:  return "Beast"
		Enums.MinionType.UNDEAD: return "Undead"
	return ""
