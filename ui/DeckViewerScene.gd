## DeckViewerScene.gd
## Shows all cards currently in the player's deck, grouped and sorted.
## Hovering a row shows a full CardVisual preview near the cursor.
extends Node2D

const CARD_VISUAL_SCENE := preload("res://combat/ui/CardVisual.tscn")
const PREVIEW_SIZE   := Vector2(220, 320)
const PREVIEW_OFFSET := Vector2(20, -PREVIEW_SIZE.y / 2.0)

var _preview: CardVisual = null

func _ready() -> void:
	$UI/BackButton.pressed.connect(_on_back)
	_setup_preview()
	_build_deck_list()

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
# Deck list
# ---------------------------------------------------------------------------

func _build_deck_list() -> void:
	var container := $UI/DeckScroll/DeckContainer
	var deck      := GameManager.player_deck

	# Count copies per card
	var counts: Dictionary = {}
	for card_id in deck:
		counts[card_id] = counts.get(card_id, 0) + 1

	# Sort alphabetically by card name
	var sorted_ids: Array = counts.keys()
	sorted_ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := CardDatabase.get_card(a)
		var cb := CardDatabase.get_card(b)
		return ca.card_name < cb.card_name if (ca and cb) else a < b
	)

	for card_id in sorted_ids:
		var card  := CardDatabase.get_card(card_id)
		if not card:
			continue
		var count: int = counts[card_id]

		var lbl := Label.new()
		lbl.custom_minimum_size = Vector2(0, 40)
		lbl.text                = _card_entry(card, count)
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", _card_color(card))
		# Enable mouse events so hover preview works
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		lbl.mouse_entered.connect(_show_preview.bind(card_id))
		lbl.mouse_exited.connect(_hide_preview)
		container.add_child(lbl)

	$UI/TitleLabel.text = "Current Deck  (%d cards)" % deck.size()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _card_entry(card: CardData, count: int) -> String:
	var cost_str: String
	if card is MinionCardData:
		cost_str = "[%dE+%dM]" % [card.essence_cost, card.mana_cost] if card.mana_cost > 0 \
				 else "[%dE]" % card.essence_cost
	else:
		cost_str = "[%dM]" % card.cost
	var copies := "  x%d" % count if count > 1 else ""
	return "%s  %s%s" % [cost_str, card.card_name, copies]

func _card_color(card: CardData) -> Color:
	match card.card_type:
		Enums.CardType.MINION:      return Color(0.85, 0.65, 1.0,  1)
		Enums.CardType.SPELL:       return Color(0.45, 0.70, 1.0,  1)
		Enums.CardType.TRAP:        return Color(1.00, 0.65, 0.25, 1)
		Enums.CardType.ENVIRONMENT: return Color(0.35, 0.90, 0.50, 1)
	return Color(0.9, 0.9, 0.9, 1)

func _on_back() -> void:
	GameManager.go_to_scene("res://map/EncounterLoadingScene.tscn")
