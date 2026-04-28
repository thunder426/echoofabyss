## LargePreview.gd
## The bottom-left card preview that pops up on hand-card / board-slot hover.
## Owns the CardVisual instance and positions it under $UI.
##
## Reads scene state for cost-discount preview (_spell_mana_discount,
## _relic_cost_reduction). CombatScene keeps thin facade methods so the
## existing internal callers (board hover, hand hover, animation code) work
## unchanged.
class_name LargePreview
extends RefCounted

const CARD_VISUAL_SCENE := preload("res://combat/ui/CardVisual.tscn")

var _scene: Node2D = null
var visual: CardVisual = null

func _init(scene: Node2D) -> void:
	_scene = scene

## Build the CardVisual and parent under $UI. No-op if $UI is missing.
func setup() -> void:
	var ui_root := _scene.get_node_or_null("UI")
	if ui_root == null:
		return
	visual = CARD_VISUAL_SCENE.instantiate() as CardVisual
	visual.apply_size_mode("combat_preview")
	visual.z_index      = 20
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.visible      = false
	ui_root.add_child(visual)
	# $UI is a CanvasLayer — children use screen-space position, not anchors
	var vp_size := _scene.get_viewport().get_visible_rect().size
	var ps      := visual.size
	visual.position = Vector2(16.0, vp_size.y - ps.y - 16.0)

func show_card(card_data: CardData, source_visual: CardVisual = null) -> void:
	if visual == null or card_data == null:
		return
	visual.setup(card_data)
	visual.enable_tooltip()
	var extra := -(source_visual.card_inst.mana_delta) if source_visual != null and source_visual.card_inst != null else 0
	visual.apply_cost_discount(_scene._spell_mana_discount() + _scene._relic_cost_reduction + extra)
	visual.apply_relic_cost_preview(_scene._relic_cost_reduction, _scene._relic_cost_reduction)
	visual.visible = true

func hide_card() -> void:
	if visual != null:
		visual.visible = false

func is_visible() -> bool:
	return visual != null and visual.visible
