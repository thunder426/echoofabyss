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

## Emitted when the player hovers over a card
signal card_hovered(card_data: CardData)

## Emitted when the player stops hovering over a card
signal card_unhovered()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

## Path to the CardVisual scene to instantiate for each card drawn
@export var card_visual_scene: PackedScene

## Overlap between adjacent cards in pixels — negative means cards overlap.
## Positive values add a gap. Adjust to taste.
@export var card_spacing: int = -48

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _card_visuals: Array[CardVisual] = []
var _selected_visual: CardVisual = null

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_theme_constant_override("separation", card_spacing)

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
	visual.apply_size_mode("hand")
	visual.setup(card_data)
	visual.apply_talent_overlay()
	visual.card_clicked.connect(_on_card_clicked)
	visual.mouse_entered.connect(func() -> void:
		visual.z_index = 2
		card_hovered.emit(card_data))
	visual.mouse_exited.connect(func() -> void:
		if _selected_visual != visual:
			visual.z_index = 0
		card_unhovered.emit())
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
		_selected_visual.z_index = 0
		_selected_visual = null

## Update mana cost display on non-minion hand cards to reflect a discount.
## Pass 0 to reset all costs to their base values (white color).
func refresh_spell_costs(discount: int) -> void:
	for visual in _card_visuals:
		visual.apply_cost_discount(discount)

## Update gold condition-glow on cards whose bonus conditions are currently met
## AND the player can afford to play them.
func refresh_condition_glows(scene: Node, essence: int, mana: int) -> void:
	var ctx := EffectContext.make(scene, "player")
	var piercing_void_active := GameManager.has_talent("piercing_void")
	for visual in _card_visuals:
		if visual.card_data == null:
			visual.set_condition_glow(false)
			continue
		if not _card_has_active_condition(visual.card_data, ctx):
			visual.set_condition_glow(false)
			continue
		# Condition met — also require affordability
		var affordable: bool
		if visual.card_data is MinionCardData:
			var md := visual.card_data as MinionCardData
			var extra_mana := 1 if (md.id == "void_imp" and piercing_void_active) else 0
			affordable = essence >= md.essence_cost and mana >= (md.mana_cost + extra_mana)
		else:
			affordable = mana >= visual.card_data.cost
		visual.set_condition_glow(affordable)

func _card_has_active_condition(card: CardData, ctx: EffectContext) -> bool:
	var steps: Array = []
	if card is SpellCardData:
		steps = (card as SpellCardData).effect_steps
	elif card is MinionCardData:
		steps = (card as MinionCardData).on_play_effect_steps
	for raw in steps:
		var step: EffectStep = EffectStep.from_dict(raw) if raw is Dictionary else raw as EffectStep
		if step == null:
			continue
		if not step.bonus_conditions.is_empty() and ConditionResolver.check_all(step.bonus_conditions, ctx, null):
			return true
	return false

## Update which cards appear greyed out based on available resources.
## Accounts for piercing_void talent adding +1 Mana to Void Imps.
func refresh_playability(essence: int, mana: int) -> void:
	var piercing_void_active := GameManager.has_talent("piercing_void")
	for visual in _card_visuals:
		if visual.card_data == null:
			continue
		var affordable: bool
		if visual.card_data is MinionCardData:
			var md := visual.card_data as MinionCardData
			var extra_mana := 1 if (md.id == "void_imp" and piercing_void_active) else 0
			affordable = essence >= md.essence_cost and mana >= (md.mana_cost + extra_mana)
		else:
			affordable = mana >= visual.card_data.cost
		visual.set_playable(affordable)

# ---------------------------------------------------------------------------
# Input handling
# ---------------------------------------------------------------------------

func _on_card_clicked(visual: CardVisual) -> void:
	# Clicking the already-selected card deselects it
	if _selected_visual == visual:
		visual.deselect()
		visual.z_index = 0
		_selected_visual = null
		card_deselected.emit()
		return

	# Deselect the previous card
	if _selected_visual:
		_selected_visual.deselect()
		_selected_visual.z_index = 0

	# Select the new card
	_selected_visual = visual
	visual.z_index = 3
	visual.select()
	card_selected.emit(visual.card_data)
