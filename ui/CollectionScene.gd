## CollectionScene.gd
## Shows all permanently unlocked support cards across all runs.
## Accessible from the Main Menu.
extends Node2D

const CARD_VISUAL_SCENE := preload("res://combat/ui/CardVisual.tscn")
const PREVIEW_SIZE  := Vector2(300, 450)
const PREVIEW_OFFSET := Vector2(16, -PREVIEW_SIZE.y / 2.0)

var _preview: CardVisual = null

func _ready() -> void:
	$UI/BackButton.pressed.connect(_on_back)
	_setup_preview()
	_build_list()

func _process(_delta: float) -> void:
	if _preview and _preview.visible:
		_reposition_preview()

# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------

func _setup_preview() -> void:
	_preview = CARD_VISUAL_SCENE.instantiate() as CardVisual
	_preview.custom_minimum_size = PREVIEW_SIZE
	_preview.size                = PREVIEW_SIZE
	_preview.z_index             = 10
	_preview.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_preview.visible             = false
	$UI.add_child(_preview)

func _show_preview(card_id: String) -> void:
	var card := CardDatabase.get_card(card_id)
	if not card:
		return
	_preview.setup(card)
	_reposition_preview()
	_preview.visible = true

func _hide_preview() -> void:
	_preview.visible = false

func _reposition_preview() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var pos     := get_viewport().get_mouse_position() + PREVIEW_OFFSET
	pos.x = clamp(pos.x, 0, vp_size.x - PREVIEW_SIZE.x)
	pos.y = clamp(pos.y, 0, vp_size.y - PREVIEW_SIZE.y)
	_preview.position = pos

# ---------------------------------------------------------------------------
# List
# ---------------------------------------------------------------------------

func _build_list() -> void:
	var container: VBoxContainer = $UI/ScrollContainer/CardList
	for child in container.get_children():
		child.queue_free()

	var unlocks := GameManager.permanent_unlocks
	if unlocks.is_empty():
		var lbl := Label.new()
		lbl.text = "No cards unlocked yet.\nDefeat act bosses to permanently unlock Support cards."
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65, 1))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		container.add_child(lbl)
		return

	# Group by pool / rarity for readability.
	# For now, sort by rarity weight then name.
	var rarity_order := {"common": 0, "rare": 1, "epic": 2, "legendary": 3}
	var sorted := unlocks.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool:
		var ra: int = rarity_order.get(GameManager._SUPPORT_CARD_RARITIES.get(a, ""), 99)
		var rb: int = rarity_order.get(GameManager._SUPPORT_CARD_RARITIES.get(b, ""), 99)
		if ra != rb:
			return ra < rb
		var ca := CardDatabase.get_card(a)
		var cb := CardDatabase.get_card(b)
		return (ca.card_name if ca else a) < (cb.card_name if cb else b)
	)

	for card_id in sorted:
		var card := CardDatabase.get_card(card_id)
		if card == null:
			continue
		var rarity: String = GameManager._SUPPORT_CARD_RARITIES.get(card_id, "?")
		var rarity_color := _rarity_color(rarity)

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 48)
		row.add_theme_constant_override("separation", 16)

		var rarity_lbl := Label.new()
		rarity_lbl.text = "[%s]" % rarity.to_upper()
		rarity_lbl.custom_minimum_size = Vector2(120, 0)
		rarity_lbl.add_theme_font_size_override("font_size", 16)
		rarity_lbl.add_theme_color_override("font_color", rarity_color)
		rarity_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(rarity_lbl)

		var name_lbl := Label.new()
		name_lbl.text = card.card_name
		name_lbl.custom_minimum_size = Vector2(240, 0)
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(0.90, 0.90, 1.00, 1))
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = card.description
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.add_theme_font_size_override("font_size", 15)
		desc_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.80, 1))
		desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(desc_lbl)

		row.mouse_entered.connect(_show_preview.bind(card_id))
		row.mouse_exited.connect(_hide_preview)
		container.add_child(row)

		var sep := HSeparator.new()
		container.add_child(sep)

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"common":    return Color(0.75, 0.75, 0.75, 1)
		"rare":      return Color(0.30, 0.60, 1.00, 1)
		"epic":      return Color(0.70, 0.20, 0.90, 1)
		"legendary": return Color(1.00, 0.75, 0.10, 1)
	return Color(0.55, 0.55, 0.65, 1)

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_back() -> void:
	GameManager.go_to_scene("res://ui/MainMenu.tscn")
