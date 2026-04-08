## EnemyDeckBuilder.gd
## Debug tool for building and managing enemy encounter deck variants.
## Each encounter has a pool of deck IDs; one is randomly picked at combat start.
## Navigate here from BalanceSim; Back returns to BalanceSim.
extends Control

const _ENCOUNTER_NAMES: Array = [
	"Fight 1  —  Rogue Imp Pack",
	"Fight 2  —  Corrupted Broodlings",
	"Fight 3  —  Imp Matriarch",
	"Fight 4  —  Abyss Cultist Patrol",
	"Fight 5  —  Void Ritualist",
	"Fight 6  —  Corrupted Handler",
	"Fight 7  —  Rift Stalker",
	"Fight 8  —  Void Aberration",
	"Fight 9  —  Void Herald",
	"Fight 10  —  Void Scout",
	"Fight 11  —  Void Warband",
	"Fight 12  —  Void Captain",
	"Fight 13  —  Void Ritualist Prime",
	"Fight 14  —  Void Champion",
	"Fight 15  —  Abyss Sovereign",
]

const CARD_VISUAL_SCENE := preload("res://combat/ui/CardVisual.tscn")

## Floating preview — same size and offset as DeckBuilderScene
const PREVIEW_SIZE   := Vector2(480, 720)
const PREVIEW_OFFSET := Vector2(16, -PREVIEW_SIZE.y / 2.0)

# ---------------------------------------------------------------------------
# Pool filter groups
# ---------------------------------------------------------------------------

const _POOL_FILTERS: Array = [
	{"label": "All",         "pools": []},
	{"label": "Feral Imp",   "pools": ["feral_imp_clan"]},
	{"label": "Abyss Cult",  "pools": ["abyss_cultist_clan"]},
	{"label": "Void Rift",   "pools": ["void_rift"]},
	{"label": "Void Castle", "pools": ["void_castle"]},
	{"label": "Abyss Order", "pools": ["abyss_core"]},
	{"label": "Neutral",     "pools": ["neutral_core"]},
	{"label": "Vael",        "pools": ["vael_piercing_void", "vael_common", "vael_endless_tide", "vael_rune_master"]},
	{"label": "Tokens",      "pools": [""]},
]

# ---------------------------------------------------------------------------
# Theme colours  (matches BalanceSim)
# ---------------------------------------------------------------------------

const _C_BG      := Color(0.06, 0.06, 0.10)
const _C_PANEL   := Color(0.09, 0.09, 0.15)
const _C_SECTION := Color(0.12, 0.12, 0.20)
const _C_BTN_SEL := Color(0.30, 0.22, 0.55)
const _C_BTN_NRM := Color(0.16, 0.16, 0.26)
const _C_TEXT    := Color(0.80, 0.80, 0.92)
const _C_DIM     := Color(0.50, 0.50, 0.65)
const _C_GREEN   := Color(0.40, 0.90, 0.55)
const _C_RED     := Color(0.95, 0.40, 0.40)
const _C_GOLD    := Color(0.95, 0.82, 0.45)

# ---------------------------------------------------------------------------
# UI refs
# ---------------------------------------------------------------------------

var _filter_buttons:    Array[Button] = []
var _card_list_vbox:    VBoxContainer
var _deck_list_vbox:    VBoxContainer
var _deck_name_input:   LineEdit
var _count_label:       Label
var _encounter_dropdown: OptionButton
var _pool_list_vbox:    VBoxContainer
var _status_label:      Label
var _preview:           CardVisual    = null

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _current_filter:   int           = 0
var _current_deck:     Array[String] = []  # card IDs, with duplicates
var _current_deck_id:  String        = ""  # deck ID being edited
var _current_encounter: int          = 1   # 1-based encounter index

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	_setup_preview()
	_apply_filter(0)
	_on_encounter_selected(0)

func _process(_delta: float) -> void:
	if _preview and _preview.visible:
		_reposition_preview()

# ---------------------------------------------------------------------------
# Card preview  (identical pattern to DeckBuilderScene)
# ---------------------------------------------------------------------------

func _setup_preview() -> void:
	_preview = CARD_VISUAL_SCENE.instantiate() as CardVisual
	_preview.custom_minimum_size = PREVIEW_SIZE
	_preview.size                = PREVIEW_SIZE
	_preview.z_index             = 10
	_preview.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_preview.visible             = false
	add_child(_preview)

func _show_preview(card_id: String) -> void:
	var card := CardDatabase.get_card(card_id)
	if not card:
		return
	_preview.setup(card)
	_preview.enable_tooltip()
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
# Build UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = _C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# ── Title bar ──────────────────────────────────────────────────────────
	var title_bar := _panel(_C_PANEL)
	title_bar.custom_minimum_size.y = 40
	root.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "  Enemy Deck Builder"
	title_lbl.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	title_lbl.offset_left  = 8
	title_lbl.offset_right = 500
	title_bar.add_child(title_lbl)

	# ── Body split ─────────────────────────────────────────────────────────
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 460
	root.add_child(split)

	_build_card_browser(split)
	_build_deck_editor(split)

# ---------------------------------------------------------------------------
# Left panel — card browser
# ---------------------------------------------------------------------------

func _build_card_browser(parent: Control) -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 450
	left.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	parent.add_child(left)

	# Pool filter row
	left.add_child(_section_header("CARD POOL"))
	var filter_body := _section_body(left)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_body.add_child(filter_row)

	for i in _POOL_FILTERS.size():
		var f: Dictionary = _POOL_FILTERS[i]
		var btn := _flat_button(f.label as String)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_apply_filter.bind(i))
		filter_row.add_child(btn)
		_filter_buttons.append(btn)

	# Card list
	left.add_child(_section_header("CARDS  (click to add)"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	var bg2 := ColorRect.new()
	bg2.color = _C_PANEL
	bg2.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.add_child(bg2)

	_card_list_vbox = VBoxContainer.new()
	_card_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_list_vbox.add_theme_constant_override("separation", 1)
	scroll.add_child(_card_list_vbox)

# ---------------------------------------------------------------------------
# Right panel — deck editor + encounter pool manager
# ---------------------------------------------------------------------------

func _build_deck_editor(parent: Control) -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	parent.add_child(right)

	# ── Encounter selector ─────────────────────────────────────────────────
	right.add_child(_section_header("ENCOUNTER"))
	var enc_body := _section_body(right)

	_encounter_dropdown = OptionButton.new()
	_encounter_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in _ENCOUNTER_NAMES.size():
		_encounter_dropdown.add_item(_ENCOUNTER_NAMES[i] as String)
	_encounter_dropdown.item_selected.connect(_on_encounter_selected)
	enc_body.add_child(_encounter_dropdown)

	# ── Encounter pool ─────────────────────────────────────────────────────
	right.add_child(_section_header("DECK POOL  (click to edit)"))

	var pool_scroll := ScrollContainer.new()
	pool_scroll.custom_minimum_size.y = 100
	pool_scroll.size_flags_vertical = Control.SIZE_FILL
	pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(pool_scroll)

	var pool_bg := ColorRect.new()
	pool_bg.color = _C_PANEL
	pool_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pool_scroll.add_child(pool_bg)

	_pool_list_vbox = VBoxContainer.new()
	_pool_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pool_list_vbox.add_theme_constant_override("separation", 1)
	pool_scroll.add_child(_pool_list_vbox)

	# ── Deck name + card count ─────────────────────────────────────────────
	right.add_child(_section_header("EDITING DECK"))
	var name_body := _section_body(right)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_body.add_child(name_row)

	_deck_name_input = LineEdit.new()
	_deck_name_input.placeholder_text = "Deck ID..."
	_deck_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_deck_name_input)

	_count_label = _label("0 cards", _C_GOLD)
	name_row.add_child(_count_label)

	# ── Current deck card list ─────────────────────────────────────────────
	right.add_child(_section_header("CARDS  (click to remove one)"))

	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(deck_scroll)

	var dbg := ColorRect.new()
	dbg.color = _C_PANEL
	dbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	deck_scroll.add_child(dbg)

	_deck_list_vbox = VBoxContainer.new()
	_deck_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_list_vbox.add_theme_constant_override("separation", 1)
	deck_scroll.add_child(_deck_list_vbox)

	# ── Actions ────────────────────────────────────────────────────────────
	right.add_child(_section_header("ACTIONS"))
	var action_body := _section_body(right)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	action_body.add_child(row1)

	var save_btn := Button.new()
	save_btn.text = "Save Deck"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(save_btn, false)
	save_btn.pressed.connect(_on_save_pressed)
	row1.add_child(save_btn)

	var new_btn := Button.new()
	new_btn.text = "New Deck"
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(new_btn, false)
	new_btn.pressed.connect(_on_new_pressed)
	row1.add_child(new_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	_style_button(clear_btn, false)
	clear_btn.pressed.connect(_on_clear_pressed)
	row1.add_child(clear_btn)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	action_body.add_child(row2)

	var add_pool_btn := Button.new()
	add_pool_btn.text = "Add to Pool"
	add_pool_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(add_pool_btn, false)
	add_pool_btn.pressed.connect(_on_add_to_pool)
	row2.add_child(add_pool_btn)

	var rm_pool_btn := Button.new()
	rm_pool_btn.text = "Remove from Pool"
	rm_pool_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(rm_pool_btn, false)
	rm_pool_btn.pressed.connect(_on_remove_from_pool)
	row2.add_child(rm_pool_btn)

	var del_btn := Button.new()
	del_btn.text = "Delete Deck"
	_style_button(del_btn, false)
	del_btn.pressed.connect(_on_delete_pressed)
	row2.add_child(del_btn)

	_status_label = _label("", _C_DIM)
	action_body.add_child(_status_label)

	# ── Back ───────────────────────────────────────────────────────────────
	right.add_child(_section_header(""))
	var nav_body := _section_body(right)

	var back_btn := Button.new()
	back_btn.text = "← Back to Balance Simulator"
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(back_btn, false)
	back_btn.pressed.connect(func(): GameManager.go_to_scene("res://debug/BalanceSim.tscn"))
	nav_body.add_child(back_btn)

# ---------------------------------------------------------------------------
# Card browser logic
# ---------------------------------------------------------------------------

func _apply_filter(idx: int) -> void:
	_current_filter = idx
	for i in _filter_buttons.size():
		_style_button(_filter_buttons[i], i == idx)
	_rebuild_card_list()

func _rebuild_card_list() -> void:
	for child in _card_list_vbox.get_children():
		child.queue_free()

	var cards := _get_filtered_cards()
	var last_pool := ""

	for card in cards:
		# Pool divider
		if card.pool != last_pool:
			last_pool = card.pool
			var div := Label.new()
			div.text = "  — %s —" % (card.pool if card.pool != "" else "token")
			div.add_theme_color_override("font_color", _C_GOLD)
			div.add_theme_font_size_override("font_size", 11)
			_card_list_vbox.add_child(div)

		var btn := Button.new()
		btn.text = "  %s  %s    %s" % [_type_tag(card), card.card_name, _cost_str(card)]
		btn.flat = false
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_color", _C_TEXT)
		_style_button(btn, false)
		btn.mouse_entered.connect(_show_preview.bind(card.id))
		btn.mouse_exited.connect(_hide_preview)
		btn.pressed.connect(_add_card.bind(card.id))
		_card_list_vbox.add_child(btn)

func _get_filtered_cards() -> Array[CardData]:
	var filter: Dictionary = _POOL_FILTERS[_current_filter]
	var pools: Array = filter.pools
	var result: Array[CardData] = []
	for id in CardDatabase.get_all_card_ids():
		var card: CardData = CardDatabase.get_card(id)
		if card == null:
			continue
		if pools.is_empty() or card.pool in pools:
			result.append(card)
	result.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.pool != b.pool:
			return a.pool < b.pool
		return a.card_name < b.card_name)
	return result

# ---------------------------------------------------------------------------
# Encounter pool logic
# ---------------------------------------------------------------------------

func _on_encounter_selected(idx: int) -> void:
	_current_encounter = idx + 1  # 1-based
	_rebuild_pool_list()

func _rebuild_pool_list() -> void:
	for child in _pool_list_vbox.get_children():
		child.queue_free()

	var pool := EncounterDecks.get_pool(_current_encounter)
	if pool.is_empty():
		var lbl := _label("  (no decks in pool)", _C_DIM)
		_pool_list_vbox.add_child(lbl)
		return

	for deck_id in pool:
		var cards := EncounterDecks.get_deck(deck_id)
		var is_selected: bool = deck_id == _current_deck_id
		var btn := Button.new()
		btn.text = "  %s  (%d cards)" % [deck_id, cards.size()]
		btn.flat = false
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(btn, is_selected)
		btn.pressed.connect(_load_deck.bind(deck_id))
		_pool_list_vbox.add_child(btn)

# ---------------------------------------------------------------------------
# Deck editor logic
# ---------------------------------------------------------------------------

func _add_card(id: String) -> void:
	_current_deck.append(id)
	_rebuild_deck_display()

func _remove_one(id: String) -> void:
	var idx := _current_deck.rfind(id)
	if idx >= 0:
		_current_deck.remove_at(idx)
	_rebuild_deck_display()

func _rebuild_deck_display() -> void:
	for child in _deck_list_vbox.get_children():
		child.queue_free()

	# Count occurrences
	var counts: Dictionary = {}
	for id in _current_deck:
		counts[id] = counts.get(id, 0) + 1

	# Maintain order by first occurrence
	var seen: Array[String] = []
	for id in _current_deck:
		if id not in seen:
			seen.append(id)

	for id in seen:
		var card: CardData = CardDatabase.get_card(id)
		var cname: String = card.card_name if card else id
		var count: int = counts[id]

		var btn := Button.new()
		btn.text = "  %s  ×%d" % [cname, count]
		btn.flat = false
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_color", _C_TEXT)
		_style_button(btn, false)
		btn.mouse_entered.connect(_show_preview.bind(id))
		btn.mouse_exited.connect(_hide_preview)
		btn.pressed.connect(_remove_one.bind(id))
		_deck_list_vbox.add_child(btn)

	_count_label.text = "%d cards" % _current_deck.size()

# ---------------------------------------------------------------------------
# Load a specific deck into the editor
# ---------------------------------------------------------------------------

func _load_deck(deck_id: String) -> void:
	_current_deck_id = deck_id
	_current_deck = EncounterDecks.get_deck(deck_id)
	_deck_name_input.text = deck_id
	_rebuild_deck_display()
	_rebuild_pool_list()
	_status("Loaded  \"%s\"  (%d cards)." % [deck_id, _current_deck.size()], _C_GREEN)

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	var deck_id := _deck_name_input.text.strip_edges()
	if deck_id.is_empty():
		_status("Enter a deck ID first.", _C_RED)
		return
	if _current_deck.is_empty():
		_status("Deck is empty.", _C_RED)
		return
	EncounterDecks.save_deck(deck_id, _current_deck)
	_current_deck_id = deck_id
	_rebuild_pool_list()
	_status("Saved  \"%s\"  (%d cards)." % [deck_id, _current_deck.size()], _C_GREEN)

func _on_new_pressed() -> void:
	_current_deck.clear()
	_current_deck_id = ""
	_deck_name_input.text = ""
	_rebuild_deck_display()
	_rebuild_pool_list()
	_status("New deck — enter an ID and add cards.", _C_DIM)

func _on_clear_pressed() -> void:
	_current_deck.clear()
	_rebuild_deck_display()
	_status("", _C_DIM)

func _on_add_to_pool() -> void:
	var deck_id := _deck_name_input.text.strip_edges()
	if deck_id.is_empty():
		_status("Enter a deck ID first.", _C_RED)
		return
	# Make sure the deck exists in the database
	var existing := EncounterDecks.get_deck(deck_id)
	if existing.is_empty() and _current_deck.is_empty():
		_status("Deck \"%s\" doesn't exist. Save it first." % deck_id, _C_RED)
		return
	# Save current cards if editing
	if not _current_deck.is_empty():
		EncounterDecks.save_deck(deck_id, _current_deck)
		_current_deck_id = deck_id
	EncounterDecks.add_to_pool(_current_encounter, deck_id)
	_rebuild_pool_list()
	_status("Added  \"%s\"  to Fight %d pool." % [deck_id, _current_encounter], _C_GREEN)

func _on_remove_from_pool() -> void:
	var deck_id := _deck_name_input.text.strip_edges()
	if deck_id.is_empty():
		_status("Enter a deck ID first.", _C_RED)
		return
	EncounterDecks.remove_from_pool(_current_encounter, deck_id)
	_rebuild_pool_list()
	_status("Removed  \"%s\"  from Fight %d pool." % [deck_id, _current_encounter], _C_GREEN)

func _on_delete_pressed() -> void:
	var deck_id := _deck_name_input.text.strip_edges()
	if deck_id.is_empty():
		_status("Enter a deck ID first.", _C_RED)
		return
	EncounterDecks.delete_deck(deck_id)
	if _current_deck_id == deck_id:
		_current_deck_id = ""
		_current_deck.clear()
		_deck_name_input.text = ""
		_rebuild_deck_display()
	_rebuild_pool_list()
	_status("Deleted  \"%s\"  from all pools and database." % deck_id, _C_DIM)

func _status(msg: String, color: Color) -> void:
	_status_label.text = msg
	_status_label.add_theme_color_override("font_color", color)

# ---------------------------------------------------------------------------
# Card display helpers
# ---------------------------------------------------------------------------

func _type_tag(card: CardData) -> String:
	if card is MinionCardData: return "[M]"
	if card is SpellCardData:  return "[S]"
	if card is TrapCardData:   return "[T]"
	return "   "

func _cost_str(card: CardData) -> String:
	if card is MinionCardData:
		var mc := card as MinionCardData
		if mc.mana_cost > 0:
			return "E%d M%d" % [mc.essence_cost, mc.mana_cost]
		return "E%d" % mc.essence_cost
	if card is SpellCardData:
		return "M%d" % (card as SpellCardData).cost
	if card is TrapCardData:
		return "M%d" % (card as TrapCardData).cost
	return ""

# ---------------------------------------------------------------------------
# UI factory helpers  (matches BalanceSim style)
# ---------------------------------------------------------------------------

func _section_header(title: String) -> Control:
	var p    := _panel(_C_SECTION)
	p.custom_minimum_size.y = 24
	var lbl  := Label.new()
	lbl.text = "  " + title
	lbl.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	lbl.offset_left  = 0
	lbl.offset_right = 400
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", _C_DIM)
	p.add_child(lbl)
	return p

func _section_body(parent: Control) -> VBoxContainer:
	var wrapper := PanelContainer.new()
	var style   := StyleBoxFlat.new()
	style.bg_color = _C_PANEL
	style.set_content_margin_all(8)
	wrapper.add_theme_stylebox_override("panel", style)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(wrapper)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(vbox)
	return vbox

func _flat_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn, false)
	return btn

func _style_button(btn: Button, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = _C_BTN_SEL if selected else _C_BTN_NRM
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal",   style)
	btn.add_theme_stylebox_override("hover",    style)
	btn.add_theme_stylebox_override("pressed",  style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.add_theme_color_override("font_color", _C_TEXT if selected else _C_DIM)

func _label(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	return lbl

func _panel(color: Color) -> Panel:
	var p     := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	p.add_theme_stylebox_override("panel", style)
	return p
