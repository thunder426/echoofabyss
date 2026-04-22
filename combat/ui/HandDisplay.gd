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

## Emitted after a generated card's animation finishes so playability can be refreshed
signal card_anim_finished()

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
var _draw_queue: Array[CardInstance] = []
var _draw_playing: bool = false
const _DRAW_STAGGER: float = 0.2
var _gen_queue: Array[CardInstance] = []
var _gen_playing: bool = false
const _GEN_STAGGER: float = 0.5

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_theme_constant_override("separation", card_spacing)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Add a new card to the hand display from a CardInstance.
## Cards are queued and revealed one-by-one with a shimmer animation.
func add_card(inst: CardInstance) -> void:
	if card_visual_scene == null:
		push_error("HandDisplay: card_visual_scene is not set in the Inspector.")
		return
	_draw_queue.append(inst)
	if not _draw_playing:
		_play_draw_queue()

func _play_draw_queue() -> void:
	_draw_playing = true
	while not _draw_queue.is_empty():
		var inst: CardInstance = _draw_queue.pop_front()
		_add_card_with_shimmer(inst)
		await get_tree().create_timer(_DRAW_STAGGER).timeout
	_draw_playing = false

func _add_card_with_shimmer(inst: CardInstance) -> void:
	var visual: CardVisual = card_visual_scene.instantiate()
	visual.modulate = Color(0.6, 0.3, 1.0, 0.0)
	add_child(visual)
	visual.apply_size_mode("hand")
	visual.setup(inst.card_data)
	visual.modulate = Color(0.6, 0.3, 1.0, 0.0)
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

	# Void shimmer animation
	var s: Vector2 = visual.size if visual.size != Vector2.ZERO else visual.custom_minimum_size
	visual.pivot_offset = s / 2.0
	visual.scale = Vector2(0.7, 0.7)
	var tw := create_tween()
	tw.set_parallel(true)
	# Scale up
	tw.tween_property(visual, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# Fade in with purple tint then settle
	tw.tween_property(visual, "modulate", Color(0.8, 0.6, 1.3, 1.0), 0.15).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "modulate", Color(1, 1, 1, 1), 0.2).set_delay(0.15)
	# Refresh playability after animation completes
	tw.chain().tween_callback(card_anim_finished.emit)

## Add a generated card with a shadow rise effect.
## Cards are queued and revealed one-by-one.
func add_card_generated(inst: CardInstance) -> void:
	if card_visual_scene == null:
		push_error("HandDisplay: card_visual_scene is not set in the Inspector.")
		return
	_gen_queue.append(inst)
	if not _gen_playing:
		_play_gen_queue()

func _play_gen_queue() -> void:
	_gen_playing = true
	while not _gen_queue.is_empty():
		var inst: CardInstance = _gen_queue.pop_front()
		_add_card_with_shadow_rise(inst)
		await get_tree().create_timer(_GEN_STAGGER).timeout
	_gen_playing = false

func _add_card_with_shadow_rise(inst: CardInstance) -> void:
	var visual: CardVisual = card_visual_scene.instantiate()
	visual.modulate = Color(0.1, 0.0, 0.15, 0.0)
	add_child(visual)
	visual.apply_size_mode("hand")
	visual.setup(inst.card_data)
	visual.modulate = Color(0.1, 0.0, 0.15, 0.0)
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

	var s: Vector2 = visual.size if visual.size != Vector2.ZERO else visual.custom_minimum_size
	visual.pivot_offset = Vector2(s.x / 2.0, s.y)
	# Start below final position
	visual.position.y += s.y * 0.4

	# Add dark glow behind the card
	var glow := Panel.new()
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(0.1, 0.0, 0.2, 0.8)
	glow_style.set_corner_radius_all(12)
	glow_style.shadow_color = Color(0.0, 0.0, 0.0, 0.9)
	glow_style.shadow_size = 20
	glow_style.shadow_offset = Vector2(0, 4)
	glow.add_theme_stylebox_override("panel", glow_style)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.size = s + Vector2(16, 16)
	glow.position = Vector2(-8, -8)
	glow.modulate = Color(1, 1, 1, 0)
	visual.add_child(glow)
	visual.move_child(glow, 0)

	# Shadow rise: slide up from below, dark silhouette brightens to full color
	var tw := create_tween()
	tw.set_parallel(true)
	# Slide up
	tw.tween_property(visual, "position:y", visual.position.y - s.y * 0.4, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Dark glow appears then fades
	tw.tween_property(glow, "modulate:a", 1.0, 0.15)
	tw.tween_property(glow, "modulate:a", 0.0, 0.3).set_delay(0.3)
	# Dark silhouette fades in
	tw.tween_property(visual, "modulate", Color(0.2, 0.1, 0.3, 0.8), 0.15)
	# Then brightens with purple tint
	tw.tween_property(visual, "modulate", Color(0.7, 0.4, 1.0, 1.0), 0.2).set_delay(0.15)
	# Then settles to normal
	tw.tween_property(visual, "modulate", Color(1, 1, 1, 1), 0.2).set_delay(0.35)
	# Clean up glow and refresh playability
	tw.chain().tween_callback(glow.queue_free)
	tw.chain().tween_callback(card_anim_finished.emit)

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

## Apply Dark Mirror relic cost preview to all minion cards in hand.
## Also folds the per-instance cost_delta (e.g. Fiendish Pact -2 on Demons) into the essence side.
func refresh_relic_cost_preview(ess_reduction: int, mana_reduction: int) -> void:
	for visual in _card_visuals:
		if visual.card_inst == null:
			continue
		var inst_ess_bonus: int = -visual.card_inst.cost_delta  # negative delta = reduction
		visual.apply_relic_cost_preview(ess_reduction + inst_ess_bonus, mana_reduction)

## Update which cards appear greyed out based on available resources.
## Uses each card's effective_cost() which accounts for per-copy cost_delta.
## relic_ess_reduction / relic_mana_reduction: Dark Mirror discount applied to the next card.
func refresh_playability(essence: int, mana: int, relic_ess_reduction: int = 0, relic_mana_reduction: int = 0) -> void:
	var piercing_void_active := GameManager.has_talent("piercing_void")
	for visual in _card_visuals:
		if visual.card_inst == null or visual.card_inst.card_data == null:
			continue
		var inst: CardInstance = visual.card_inst
		var affordable: bool
		if inst.card_data is MinionCardData:
			var md := inst.card_data as MinionCardData
			var extra_mana := 1 if (md.id == "void_imp" and piercing_void_active) else 0
			# cost_delta is negative for a discount (e.g. Fiendish Pact = -2 on Demons in hand).
			var inst_ess_bonus: int = -inst.cost_delta
			var eff_ess := maxi(0, md.essence_cost - relic_ess_reduction - inst_ess_bonus)
			var eff_mana := maxi(0, md.mana_cost + extra_mana - relic_mana_reduction)
			affordable = essence >= eff_ess and mana >= eff_mana
		else:
			var eff_cost := maxi(0, inst.effective_cost() - relic_mana_reduction)
			affordable = mana >= eff_cost
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
