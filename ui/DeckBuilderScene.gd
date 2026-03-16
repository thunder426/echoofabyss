## DeckBuilderScene.gd
## Lets the player build their starting deck before beginning a run.
## Left panel: all available cards (click to add).
## Right panel: current deck being built (click entry to remove).
## Hovering any inventory row shows a full CardVisual preview near the cursor.
extends Node2D

const MAX_DECK_SIZE  := 15
const MAX_COPIES     := 2
const MAX_COPIES_IMP  := 4  # Void Imp limit raised by Lord Vael Passive 2
const MAX_COPIES_LEGENDARY := 1

## Predefined starter decks for Lord Vael. Loaded directly into the deck,
## bypassing the EXCLUDED_IDS restriction so preset-only cards (e.g. void_rain) can appear.
const PREDEFINED_DECKS: Array = [
	{
		"id":   "swarm",
		"name": "Swarm",
		"desc": "Flood the board with Imps and Demons, buff them in bulk.",
		"cards": [
			"void_imp", "void_imp", "void_imp", "void_imp",
			"shadow_hound", "shadow_hound",
			"abyssal_brute",
			"void_spawner",
			"soul_leech", "soul_leech",
			"dark_surge", "dark_surge",
			"abyssal_reinforcement",
			"flux_siphon",
			"soul_cage",
		],
	},
	{
		"id":   "corrupt_control",
		"name": "Corrupt Control",
		"desc": "Corrupt the enemy board, then wipe it with mass removal.",
		"cards": [
			"void_imp", "void_imp", "void_imp", "void_imp",
			"abyss_cultist", "abyss_cultist",
			"void_netter", "void_netter",
			"corruption_weaver",
			"soul_collector",
			"corrupting_mist", "corrupting_mist",
			"corruption_collapse",
			"flux_siphon",
			"corruption_surge",
		],
	},
	{
		"id":   "voidbolt_burst",
		"name": "Voidbolt Burst",
		"desc": "Sacrifice Imps to draw spells, then burn the enemy hero with Void Bolts.",
		"cards": [
			"void_imp", "void_imp", "void_imp", "void_imp",
			"abyss_cultist",
			"traveling_merchant", "traveling_merchant",
			"void_bolt", "void_bolt", "void_bolt",
			"abyssal_sacrifice", "abyssal_sacrifice",
			"soul_leech",
			"death_bolt_trap",
			"void_rain",
		],
	},
	{
		"id":   "death_circle",
		"name": "Death Circle",
		"desc": "Place Runes to buff your Demons, then complete the ritual to summon a 500/500 Demon Ascendant.",
		"cards": [
			"abyssal_summoning_circle",
			"dominion_rune", "dominion_rune",
			"blood_rune", "blood_rune",
			"void_imp", "void_imp",
			"shadow_hound", "shadow_hound",
			"void_stalker",
			"void_spawner",
			"abyssal_brute",
			"soul_leech", "soul_leech",
			"abyssal_sacrifice",
			"dark_surge",
		],
	},
]

const CARD_VISUAL_SCENE := preload("res://combat/ui/CardVisual.tscn")

## Card IDs that should never appear in the deck builder (hero power tokens, enemy-only, support-only).
const EXCLUDED_IDS: Array[String] = [
	"wandering_spirit", "void_spark", "soldier", "senior_void_imp", "ritual_demon",
	"shadow_bolt", "void_barrage",
	# Void Bolt Support Pool — reward-only, never in starter deck build
	"mark_the_target", "imp_combustion", "dark_ritual_of_the_abyss", "imp_overload",
	"void_channeler", "abyssal_sacrificer", "abyssal_arcanist",
	"void_detonation", "soul_rupture", "void_rain", "mark_convergence",
	"mark_collapse", "void_archmagus", "abyss_ritual_circle",
	# Common Imp Support Pool — reward-only, never in starter deck build
	"abyssal_conjuring", "void_breach", "abyss_recruiter", "dark_nursery",
	"call_the_swarm", "imp_handler", "imp_barricade",
	"abyssal_taskmaster", "imp_hatchery", "imp_overseer",
]

## Cards limited to 1 copy per deck (Legendary rule).
const LEGENDARY_IDS: Array[String] = ["void_archmagus"]

## Preview card size shown on hover
const PREVIEW_SIZE := Vector2(400, 600)
## Offset from the cursor so the preview doesn't cover the button being hovered
const PREVIEW_OFFSET := Vector2(16, -PREVIEW_SIZE.y / 2.0)

var _inventory_ids: Array[String] = []
var _built_deck: Array[String]    = []

# Sort / filter state
var _sort_mode: int     = 1    # 0 = Name  1 = Cost  2 = Type
var _filter_type: int   = -1   # -1 = All  or Enums.CardType value
var _filter_faction: String = ""  # "" = All  "neutral"  "abyss_order"

var _sort_option: OptionButton      = null
var _filter_buttons: Array[Button]  = []
var _faction_buttons: Array[Button] = []

# ---------------------------------------------------------------------------
# Node refs (resolved in _ready)
# ---------------------------------------------------------------------------
var _inventory_container: VBoxContainer
var _deck_container: VBoxContainer
var _deck_count_label: Label
var _start_btn: Button

# Floating preview
var _preview: CardVisual = null

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_inventory_container = $UI/InventoryPanel/InventoryScroll/InventoryContainer
	_deck_container      = $UI/DeckPanel/DeckScroll/DeckContainer
	_deck_count_label    = $UI/DeckPanel/DeckCountLabel
	_start_btn           = $UI/DeckPanel/StartRunButton

	$UI/DeckPanel/ClearButton.pressed.connect(_on_clear)
	$UI/DeckPanel/BackButton.pressed.connect(_on_back)
	_start_btn.pressed.connect(_on_start_run)

	_setup_preview()
	_setup_predefined_deck_row()
	_setup_filter_sort_row()
	_setup_faction_row()
	_load_inventory()
	_rebuild_inventory_ui()
	_rebuild_deck_ui()

func _process(_delta: float) -> void:
	if _preview and _preview.visible:
		_reposition_preview()

# ---------------------------------------------------------------------------
# Preview panel
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
	# Clamp so the card never goes off-screen
	pos.x = clamp(pos.x, 0, vp_size.x - PREVIEW_SIZE.x)
	pos.y = clamp(pos.y, 0, vp_size.y - PREVIEW_SIZE.y)
	_preview.position = pos

# ---------------------------------------------------------------------------
# Predefined deck row (injected at the top of DeckPanel)
# ---------------------------------------------------------------------------

func _setup_predefined_deck_row() -> void:
	var row := $UI/DeckPanel/PresetRow
	row.add_theme_constant_override("separation", 8)
	for preset in PREDEFINED_DECKS:
		var btn := Button.new()
		btn.text = preset["name"]
		btn.custom_minimum_size = Vector2(130, 38)
		btn.add_theme_font_size_override("font_size", 14)
		btn.tooltip_text = preset["desc"]
		btn.pressed.connect(_on_load_preset.bind(preset["id"]))
		row.add_child(btn)

func _on_load_preset(preset_id: String) -> void:
	for preset in PREDEFINED_DECKS:
		if preset["id"] == preset_id:
			_built_deck.clear()
			for card_id in preset["cards"]:
				_built_deck.append(card_id as String)
			_rebuild_inventory_ui()
			_rebuild_deck_ui()
			return

# ---------------------------------------------------------------------------
# Filter / sort row
# ---------------------------------------------------------------------------

func _setup_filter_sort_row() -> void:
	var row := $UI/InventoryPanel/FilterSortRow

	var sort_lbl := Label.new()
	sort_lbl.text = "Sort:"
	sort_lbl.add_theme_font_size_override("font_size", 16)
	sort_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(sort_lbl)

	_sort_option = OptionButton.new()
	_sort_option.add_item("Name")
	_sort_option.add_item("Cost")
	_sort_option.add_item("Type")
	_sort_option.selected = 1   # default: sort by Cost
	_sort_option.custom_minimum_size = Vector2(110, 36)
	_sort_option.item_selected.connect(_on_sort_changed)
	row.add_child(_sort_option)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 0)
	row.add_child(spacer)

	var filter_lbl := Label.new()
	filter_lbl.text = "Filter:"
	filter_lbl.add_theme_font_size_override("font_size", 16)
	filter_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(filter_lbl)

	var filter_defs: Array = [
		["All",    -1],
		["Minion", Enums.CardType.MINION],
		["Spell",  Enums.CardType.SPELL],
		["Trap",   Enums.CardType.TRAP],
		["Env",    Enums.CardType.ENVIRONMENT],
	]
	for i in filter_defs.size():
		var btn := Button.new()
		btn.text = filter_defs[i][0]
		btn.custom_minimum_size = Vector2(72, 36)
		btn.add_theme_font_size_override("font_size", 15)
		btn.modulate = Color(1, 1, 1, 1) if i == 0 else Color(0.55, 0.55, 0.55, 1)
		var filter_val: int = filter_defs[i][1]
		btn.pressed.connect(_on_filter_changed.bind(filter_val))
		row.add_child(btn)
		_filter_buttons.append(btn)


func _setup_faction_row() -> void:
	var row := $UI/InventoryPanel/FactionRow
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = "Faction:"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var faction_defs: Array = [
		["All",         ""],
		["Neutral",     "neutral"],
		["Abyss Order", "abyss_order"],
	]
	for i in faction_defs.size():
		var btn := Button.new()
		btn.text = faction_defs[i][0]
		btn.custom_minimum_size = Vector2(100, 36)
		btn.add_theme_font_size_override("font_size", 15)
		btn.modulate = Color(1, 1, 1, 1) if i == 0 else Color(0.55, 0.55, 0.55, 1)
		var faction_val: String = faction_defs[i][1]
		btn.pressed.connect(_on_faction_filter_changed.bind(faction_val))
		row.add_child(btn)
		_faction_buttons.append(btn)

func _on_sort_changed(idx: int) -> void:
	_sort_mode = idx
	_rebuild_inventory_ui()

func _on_filter_changed(filter_val: int) -> void:
	_filter_type = filter_val
	for i in _filter_buttons.size():
		var active_vals: Array = [-1, Enums.CardType.MINION, Enums.CardType.SPELL,
				Enums.CardType.TRAP, Enums.CardType.ENVIRONMENT]
		_filter_buttons[i].modulate = Color(1, 1, 1, 1) if active_vals[i] == filter_val \
				else Color(0.55, 0.55, 0.55, 1)
	_rebuild_inventory_ui()

func _on_faction_filter_changed(faction_val: String) -> void:
	_filter_faction = faction_val
	var faction_vals: Array = ["", "neutral", "abyss_order"]
	for i in _faction_buttons.size():
		_faction_buttons[i].modulate = Color(1, 1, 1, 1) if faction_vals[i] == faction_val \
				else Color(0.55, 0.55, 0.55, 1)
	_rebuild_inventory_ui()

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

func _load_inventory() -> void:
	for card_id in CardDatabase.get_all_card_ids():
		if card_id not in EXCLUDED_IDS:
			_inventory_ids.append(card_id)
	_inventory_ids.sort()

# ---------------------------------------------------------------------------
# UI builders
# ---------------------------------------------------------------------------

func _rebuild_inventory_ui() -> void:
	for child in _inventory_container.get_children():
		child.queue_free()

	# --- Filter ---
	var visible_ids: Array[String] = []
	for card_id in _inventory_ids:
		var card := CardDatabase.get_card(card_id)
		if not card:
			continue
		if _filter_type != -1 and card.card_type != _filter_type:
			continue
		if _filter_faction != "" and card.faction != _filter_faction:
			continue
		visible_ids.append(card_id)

	# --- Sort ---
	match _sort_mode:
		1:  # Cost ascending
			visible_ids.sort_custom(func(a: String, b: String) -> bool:
				var ca := CardDatabase.get_card(a)
				var cb := CardDatabase.get_card(b)
				var cost_a: int = (ca as MinionCardData).essence_cost if ca is MinionCardData else ca.cost
				var cost_b: int = (cb as MinionCardData).essence_cost if cb is MinionCardData else cb.cost
				return cost_a < cost_b if cost_a != cost_b else ca.card_name < cb.card_name
			)
		2:  # Type, then name within type
			visible_ids.sort_custom(func(a: String, b: String) -> bool:
				var ca := CardDatabase.get_card(a)
				var cb := CardDatabase.get_card(b)
				return int(ca.card_type) < int(cb.card_type) if ca.card_type != cb.card_type \
						else ca.card_name < cb.card_name
			)
		_:  # Name (default — _inventory_ids already alphabetical)
			pass

	# --- Column header ---
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 0)
	_add_table_cell(header, "Cost",    88, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.60, 0.85, 1))
	_add_table_cell(header, "Type",    72, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.60, 0.85, 1))
	_add_table_cell(header, "Fac",     44, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.60, 0.85, 1))
	_add_table_cell(header, "Name",     0, HORIZONTAL_ALIGNMENT_LEFT,   Color(0.55, 0.60, 0.85, 1), true)
	_add_table_cell(header, "In Deck", 60, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.60, 0.85, 1))
	_inventory_container.add_child(header)
	_inventory_container.add_child(HSeparator.new())

	# --- Build rows ---
	var deck_full := _built_deck.size() >= MAX_DECK_SIZE
	for card_id in visible_ids:
		var card          := CardDatabase.get_card(card_id)
		var count_in_deck := _built_deck.count(card_id)
		var copy_limit    := MAX_COPIES_IMP if card_id == "void_imp" else (MAX_COPIES_LEGENDARY if card_id in LEGENDARY_IDS else MAX_COPIES)
		var maxed         := count_in_deck >= copy_limit

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 40)
		btn.disabled            = maxed or deck_full
		btn.modulate            = Color(0.60, 0.60, 0.60, 1) if maxed else Color(1, 1, 1, 1)
		btn.pressed.connect(_on_add_card.bind(card_id))
		btn.mouse_entered.connect(_show_preview.bind(card_id))
		btn.mouse_exited.connect(_hide_preview)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 0)
		btn.add_child(row)

		_add_table_cell(row, _cost_str(card), 88, HORIZONTAL_ALIGNMENT_CENTER, Color(0.95, 0.82, 0.40, 1))
		_add_table_cell(row, _card_type_label(card.card_type), 72, HORIZONTAL_ALIGNMENT_CENTER, _card_type_color(card))
		_add_table_cell(row, _faction_symbol(card), 44, HORIZONTAL_ALIGNMENT_CENTER, _faction_color(card))
		_add_table_cell(row, card.card_name, 0, HORIZONTAL_ALIGNMENT_LEFT, Color(0.95, 0.95, 0.95, 1), true)

		var copies_color: Color
		if maxed:
			copies_color = Color(1.00, 0.45, 0.30, 1)
		elif count_in_deck > 0:
			copies_color = Color(0.40, 0.90, 0.50, 1)
		else:
			copies_color = Color(0.65, 0.65, 0.65, 1)
		_add_table_cell(row, "%d / %d" % [count_in_deck, copy_limit], 60, HORIZONTAL_ALIGNMENT_CENTER, copies_color)

		_inventory_container.add_child(btn)

func _rebuild_deck_ui() -> void:
	for child in _deck_container.get_children():
		child.queue_free()

	# Count copies per card
	var counts: Dictionary = {}
	for card_id in _built_deck:
		counts[card_id] = counts.get(card_id, 0) + 1

	# Sort entries alphabetically by card name
	var sorted_ids: Array = counts.keys()
	sorted_ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := CardDatabase.get_card(a)
		var cb := CardDatabase.get_card(b)
		return ca.card_name < cb.card_name if (ca and cb) else a < b
	)

	for card_id in sorted_ids:
		var card  := CardDatabase.get_card(card_id)
		var count: int = counts[card_id]

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 40)
		btn.tooltip_text        = "Click to remove one copy"
		btn.pressed.connect(_on_remove_card.bind(card_id))
		btn.mouse_entered.connect(_show_preview.bind(card_id))
		btn.mouse_exited.connect(_hide_preview)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 0)
		btn.add_child(row)

		_add_table_cell(row, card.card_name, 0, HORIZONTAL_ALIGNMENT_LEFT, _card_type_color(card), true)
		_add_table_cell(row, "x%d" % count, 40, HORIZONTAL_ALIGNMENT_CENTER, Color(0.95, 0.82, 0.40, 1))
		_add_table_cell(row, "−", 30, HORIZONTAL_ALIGNMENT_CENTER, Color(0.90, 0.40, 0.40, 1))

		_deck_container.add_child(btn)

	var size := _built_deck.size()
	_deck_count_label.text = "Deck: %d / %d" % [size, MAX_DECK_SIZE]
	_start_btn.disabled    = size == 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns a formatted cost string for a card (e.g. "2E", "3M", "2E+1M").
func _cost_str(card: CardData) -> String:
	if card is MinionCardData:
		return "%dE+%dM" % [card.essence_cost, card.mana_cost] if card.mana_cost > 0 \
				else "%dE" % card.essence_cost
	return "%dM" % card.cost

## Adds a single table cell Label to parent with consistent styling.
func _add_table_cell(parent: HBoxContainer, text: String, min_width: int,
		align: HorizontalAlignment, color: Color, expand: bool = false) -> void:
	var lbl := Label.new()
	lbl.text                    = text
	lbl.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment    = align
	lbl.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	lbl.clip_text               = true
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 15)
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		lbl.custom_minimum_size = Vector2(min_width, 0)
	parent.add_child(lbl)

func _faction_symbol(card: CardData) -> String:
	match card.faction:
		"abyss_order": return "⬡"
		"neutral":     return "◇"
	return "?"

func _faction_color(card: CardData) -> Color:
	match card.faction:
		"abyss_order": return Color(0.75, 0.40, 1.00, 1)
		"neutral":     return Color(0.65, 0.70, 0.75, 1)
	return Color(0.9, 0.9, 0.9, 1)

func _card_type_label(card_type: Enums.CardType) -> String:
	match card_type:
		Enums.CardType.MINION:      return "Minion"
		Enums.CardType.SPELL:       return "Spell"
		Enums.CardType.TRAP:        return "Trap"
		Enums.CardType.ENVIRONMENT: return "Env"
	return "?"

func _card_type_color(card: CardData) -> Color:
	match card.card_type:
		Enums.CardType.MINION:      return Color(0.85, 0.65, 1.0,  1)
		Enums.CardType.SPELL:       return Color(0.45, 0.70, 1.0,  1)
		Enums.CardType.TRAP:        return Color(1.00, 0.65, 0.25, 1)
		Enums.CardType.ENVIRONMENT: return Color(0.35, 0.90, 0.50, 1)
	return Color(0.9, 0.9, 0.9, 1)

# ---------------------------------------------------------------------------
# Button callbacks
# ---------------------------------------------------------------------------

func _on_add_card(card_id: String) -> void:
	var limit := MAX_COPIES_IMP if card_id == "void_imp" else (MAX_COPIES_LEGENDARY if card_id in LEGENDARY_IDS else MAX_COPIES)
	if _built_deck.count(card_id) >= limit or _built_deck.size() >= MAX_DECK_SIZE:
		return
	_built_deck.append(card_id)
	_rebuild_inventory_ui()
	_rebuild_deck_ui()

func _on_remove_card(card_id: String) -> void:
	var idx := _built_deck.find(card_id)
	if idx >= 0:
		_built_deck.remove_at(idx)
	_rebuild_inventory_ui()
	_rebuild_deck_ui()

func _on_clear() -> void:
	_built_deck.clear()
	_rebuild_inventory_ui()
	_rebuild_deck_ui()

func _on_back() -> void:
	GameManager.go_to_scene("res://ui/MainMenu.tscn")

func _on_start_run() -> void:
	GameManager.player_deck = _built_deck.duplicate()
	GameManager.deck_built = true
	GameManager.go_to_scene("res://map/MapScene.tscn")
