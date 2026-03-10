## CardVisual.gd
## The visual representation of a single card in the player's hand.
##
## Scene tree expected:
##   CardVisual (Control)
##   ├── Background (Panel)
##   ├── ArtRect (TextureRect)
##   ├── CostLabel (Label)
##   ├── NameLabel (Label)
##   ├── TypeLabel (Label)
##   ├── DescLabel (Label)
##   └── StatsRow (HBoxContainer)   ← only visible for minion cards
##       ├── AtkLabel (Label)
##       └── HpLabel (Label)
class_name CardVisual
extends Control

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal card_clicked(card_visual: CardVisual)
signal card_hovered(card_visual: CardVisual)
signal card_unhovered(card_visual: CardVisual)

# ---------------------------------------------------------------------------
# Node references — found automatically in _ready()
# ---------------------------------------------------------------------------

var background: Panel
var art_rect: TextureRect
var cost_label: Label
var name_label: Label
var type_label: Label
var desc_label: Label
var stats_row: Control
var atk_label: Label
var hp_label: Label

# ---------------------------------------------------------------------------
# Card state
# ---------------------------------------------------------------------------

var card_data: CardData = null
var is_selected: bool = false
var is_playable: bool = true

# Scale constants — hover/select uses scale so HBoxContainer layout is unaffected
const SCALE_NORMAL   := Vector2(1.0, 1.0)
const SCALE_HOVER    := Vector2(1.12, 1.12)
const SCALE_SELECTED := Vector2(1.18, 1.18)

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_find_nodes()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func _find_nodes() -> void:
	background   = $Background   if has_node("Background")   else null
	art_rect     = $ArtRect      if has_node("ArtRect")      else null
	cost_label   = $CostLabel    if has_node("CostLabel")    else null
	name_label   = $NameLabel    if has_node("NameLabel")    else null
	type_label   = $TypeLabel    if has_node("TypeLabel")    else null
	desc_label   = $DescLabel    if has_node("DescLabel")    else null
	stats_row = $StatsRow          if has_node("StatsRow")          else null
	atk_label = $StatsRow/AtkLabel if has_node("StatsRow/AtkLabel") else null
	hp_label  = $StatsRow/HpLabel  if has_node("StatsRow/HpLabel")  else null

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(data: CardData) -> void:
	card_data = data

	if name_label:  name_label.text  = data.card_name
	if cost_label:  cost_label.text  = str(data.cost)
	if type_label:  type_label.text  = _type_string(data.card_type)
	if desc_label:  desc_label.text  = data.description

	var is_minion := data.card_type == Enums.CardType.MINION
	if stats_row: stats_row.visible = is_minion

	if is_minion:
		var md := data as MinionCardData
		if atk_label: atk_label.text = str(md.atk)
		if hp_label:  hp_label.text  = str(md.health)

	if art_rect and data.art_path != "":
		var tex := load(data.art_path) as Texture2D
		if tex:
			art_rect.texture = tex

	_refresh_playable_state()

# ---------------------------------------------------------------------------
# Playability
# ---------------------------------------------------------------------------

func set_playable(playable: bool) -> void:
	is_playable = playable
	_refresh_playable_state()

func _refresh_playable_state() -> void:
	modulate = Color(1, 1, 1, 1) if is_playable else Color(0.5, 0.5, 0.5, 1)

# ---------------------------------------------------------------------------
# Selection — uses scale so HBoxContainer layout is never broken
# ---------------------------------------------------------------------------

func select() -> void:
	is_selected = true
	_update_pivot()
	scale = SCALE_SELECTED

func deselect() -> void:
	is_selected = false
	scale = SCALE_NORMAL

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_mouse_entered() -> void:
	_update_pivot()
	if not is_selected:
		scale = SCALE_HOVER
	card_hovered.emit(self)

func _on_mouse_exited() -> void:
	if not is_selected:
		scale = SCALE_NORMAL
	card_unhovered.emit(self)

func _update_pivot() -> void:
	# Use custom_minimum_size as fallback if the layout hasn't run yet
	var s := size if size != Vector2.ZERO else custom_minimum_size
	pivot_offset = s / 2.0

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(self)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _type_string(card_type: Enums.CardType) -> String:
	match card_type:
		Enums.CardType.MINION:      return "Minion"
		Enums.CardType.SPELL:       return "Spell"
		Enums.CardType.TRAP:        return "Trap"
		Enums.CardType.ENVIRONMENT: return "Environment"
	return ""
