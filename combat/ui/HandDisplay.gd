## HandDisplay.gd
## Manages the row of CardVisual nodes in the player's hand.
## Attach to the HBoxContainer (or similar) that holds hand cards.
##
## CombatScene calls add_card() when a card is drawn,
## and listens to card_selected signal to know which card the player wants to play.
class_name HandDisplay
extends HBoxContainer

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player clicks a card — passes the CardData to CombatScene
signal card_selected(card_data: CardData)

## Emitted when the player clicks an already-selected card to deselect it
signal card_deselected()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

## Path to the CardVisual scene to instantiate for each card drawn
@export var card_visual_scene: PackedScene

## Separation between cards in pixels (HBoxContainer theme override)
@export var card_spacing: int = 8

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _card_visuals: Array[CardVisual] = []
var _selected_visual: CardVisual = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Add a new card to the hand display
func add_card(card_data: CardData) -> void:
	if card_visual_scene == null:
		push_error("HandDisplay: card_visual_scene is not set in the Inspector.")
		return

	var visual: CardVisual = card_visual_scene.instantiate()
	add_child(visual)
	visual.setup(card_data)
	visual.card_clicked.connect(_on_card_clicked)
	_card_visuals.append(visual)

## Remove a specific card from the hand (called after it is played)
func remove_card(card_data: CardData) -> void:
	for visual in _card_visuals:
		if visual.card_data == card_data:
			_card_visuals.erase(visual)
			visual.queue_free()
			if _selected_visual == visual:
				_selected_visual = null
			return

## Deselect the currently selected card without playing it
func deselect_current() -> void:
	if _selected_visual:
		_selected_visual.deselect()
		_selected_visual = null

## Update which cards appear greyed out based on available resources
func refresh_playability(essence: int, mana: int) -> void:
	for visual in _card_visuals:
		if visual.card_data == null:
			continue
		var affordable: bool
		match visual.card_data.cost_type:
			Enums.CostType.ESSENCE:
				affordable = essence >= visual.card_data.cost
			Enums.CostType.MANA:
				affordable = mana >= visual.card_data.cost
			_:
				affordable = true
		visual.set_playable(affordable)

# ---------------------------------------------------------------------------
# Input handling
# ---------------------------------------------------------------------------

func _on_card_clicked(visual: CardVisual) -> void:
	# Clicking the already-selected card deselects it
	if _selected_visual == visual:
		visual.deselect()
		_selected_visual = null
		card_deselected.emit()
		return

	# Deselect the previous card
	if _selected_visual:
		_selected_visual.deselect()

	# Select the new card
	_selected_visual = visual
	visual.select()
	card_selected.emit(visual.card_data)
