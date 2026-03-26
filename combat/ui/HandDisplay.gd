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

## Emitted when the player clicks a card — passes the CardInstance to CombatScene
signal card_selected(card_inst: CardInstance)

## Emitted when the player clicks an already-selected card to deselect it
signal card_deselected()

## Emitted when the player hovers over a card (includes the specific CardVisual node)
signal card_hovered(card_data: CardData, visual: CardVisual)

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

## Add a new card to the hand display from a CardInstance.
func add_card(inst: CardInstance) -> void:
	if card_visual_scene == null:
		push_error("HandDisplay: card_visual_scene is not set in the Inspector.")
		return

	var visual: CardVisual = card_visual_scene.instantiate()
	add_child(visual)
	visual.apply_size_mode("hand")
	visual.setup(inst.card_data)
	visual.card_inst = inst
	visual.apply_talent_overlay()
	visual.card_clicked.connect(_on_card_clicked)
	visual.mouse_entered.connect(func() -> void:
		visual.z_index = 2
		card_hovered.emit(inst.card_data, visual))
	visual.mouse_exited.connect(func() -> void:
		if _selected_visual != visual:
			visual.z_index = 0
		card_unhovered.emit())
	_card_visuals.append(visual)

## Remove the card matching inst from the hand display.
func remove_card(inst: CardInstance) -> void:
	for visual in _card_visuals:
		if visual.card_inst != null and visual.card_inst.instance_id == inst.instance_id:
			_card_visuals.erase(visual)
			visual.queue_free()
			if _selected_visual == visual:
				_selected_visual = null
			return

## Remove the selected card from the hand WITHOUT freeing it, for use by flight animation.
## Caller is responsible for queue_free() when animation completes.
## Returns null if no card is selected.
func pop_selected_for_animation() -> CardVisual:
	if _selected_visual == null:
		return null
	var v := _selected_visual
	_card_visuals.erase(v)
	_selected_visual = null
	return v

## Returns the index of the card visual matching card_data, or 0 if not found.
func get_index_for(card_data: CardData) -> int:
	for i in _card_visuals.size():
		if _card_visuals[i].card_data == card_data:
			return i
	return 0

## Deselect the currently selected card without playing it
func deselect_current() -> void:
	if _selected_visual:
		_selected_visual.deselect()
		_selected_visual.z_index = 0
		_selected_visual = null

## Update mana cost display on all non-minion hand cards to reflect a global discount.
## The per-copy cost_delta on each CardInstance is also applied, so the displayed cost is
## max(0, card_data.cost - global_discount + cost_delta).
## (cost_delta is negative for cheaper cards, e.g. -1 from rune_caller.)
func refresh_spell_costs(discount: int) -> void:
	for visual in _card_visuals:
		if visual.card_inst == null or visual.card_inst.card_data is MinionCardData:
			continue
		# Total discount = global rune-aura discount + reversal of any per-copy delta.
		# cost_delta = -1 means 1 cheaper, so add 1 to discount.
		visual.apply_cost_discount(discount - visual.card_inst.cost_delta)

## Update gold condition-glow on cards whose bonus conditions are currently met
## AND the player can afford to play them.
func refresh_condition_glows(scene: Node, essence: int, mana: int) -> void:
	var ctx := EffectContext.make(scene, "player")
	var piercing_void_active := GameManager.has_talent("piercing_void")
	for visual in _card_visuals:
		if visual.card_inst == null or visual.card_inst.card_data == null:
			visual.set_condition_glow(false)
			continue
		var inst: CardInstance = visual.card_inst
		if not _card_has_active_condition(inst.card_data, ctx):
			visual.set_condition_glow(false)
			continue
		# Condition met — also require affordability
		var affordable: bool
		if inst.card_data is MinionCardData:
			var md := inst.card_data as MinionCardData
			var extra_mana := 1 if (md.id == "void_imp" and piercing_void_active) else 0
			affordable = essence >= md.essence_cost and mana >= (md.mana_cost + extra_mana)
		else:
			affordable = mana >= inst.effective_cost()
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
## Uses each card's effective_cost() which accounts for per-copy cost_delta.
func refresh_playability(essence: int, mana: int) -> void:
	var piercing_void_active := GameManager.has_talent("piercing_void")
	for visual in _card_visuals:
		if visual.card_inst == null or visual.card_inst.card_data == null:
			continue
		var inst: CardInstance = visual.card_inst
		var affordable: bool
		if inst.card_data is MinionCardData:
			var md := inst.card_data as MinionCardData
			var extra_mana := 1 if (md.id == "void_imp" and piercing_void_active) else 0
			affordable = essence >= md.essence_cost and mana >= (md.mana_cost + extra_mana)
		else:
			affordable = mana >= inst.effective_cost()
		visual.set_playable(affordable)

## Returns the last CardVisual added to the hand, or null if hand is empty.
func get_last_visual() -> CardVisual:
	return _card_visuals.back() if not _card_visuals.is_empty() else null

## Returns the currently selected CardVisual, or null.
func get_selected_visual() -> CardVisual:
	return _selected_visual

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
	card_selected.emit(visual.card_inst)
