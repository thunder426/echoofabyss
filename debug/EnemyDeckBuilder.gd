## EnemyDeckBuilder.gd
## Debug tool for building and saving enemy decks.
## Has access to all card pools including feral_imp_clan.
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

var _filter_buttons:  Array[Button] = []
var _card_list_vbox:  VBoxContainer
var _deck_list_vbox:  VBoxContainer
var _deck_name_input: LineEdit
var _count_label:     Label
var _saved_dropdown:  OptionButton
var _del_btn:         Button
var _status_label:    Label

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _current_filter: int           = 0
var _current_deck:   Array[String] = []  # card IDs, with duplicates
var _preview:        CardVisual    = null

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	_setup_preview()
	_apply_filter(0)

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
# Build
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

	var bg := ColorRect.new()
	bg.color = _C_PANEL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.add_child(bg)

	_card_list_vbox = VBoxContainer.new()
	_card_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_list_vbox.add_theme_constant_override("separation", 1)
	scroll.add_child(_card_list_vbox)

# ---------------------------------------------------------------------------
# Right panel — deck editor
# ---------------------------------------------------------------------------

func _build_deck_editor(parent: Control) -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	parent.add_child(right)

	# ── Deck name ──────────────────────────────────────────────────────────
	right.add_child(_section_header("DECK"))
	var name_body := _section_body(right)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_body.add_child(name_row)

	_deck_name_input = LineEdit.new()
	_deck_name_input.placeholder_text = "Deck name..."
	_deck_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_deck_name_input)

	_count_label = _label("0 cards", _C_GOLD)
	name_row.add_child(_count_label)

	# ── Current deck list ──────────────────────────────────────────────────
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

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	action_body.add_child(save_row)

	var save_btn := Button.new()
	save_btn.text = "Save Deck"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(save_btn, false)
	save_btn.pressed.connect(_on_save_pressed)
	save_row.add_child(save_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	_style_button(clear_btn, false)
	clear_btn.pressed.connect(_on_clear_pressed)
	save_row.add_child(clear_btn)

	# ── Saved decks ────────────────────────────────────────────────────────
	right.add_child(_section_header("ENEMY DECKS"))
	var saved_body := _section_body(right)

	var saved_row := HBoxContainer.new()
	saved_row.add_theme_constant_override("separation", 8)
	saved_body.add_child(saved_row)

	_saved_dropdown = OptionButton.new()
	_saved_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saved_row.add_child(_saved_dropdown)

	var load_btn := Button.new()
	load_btn.text = "Load"
	_style_button(load_btn, false)
	load_btn.pressed.connect(_on_load_pressed)
	saved_row.add_child(load_btn)

	_del_btn = Button.new()
	_del_btn.text = "Delete"
	_style_button(_del_btn, false)
	_del_btn.pressed.connect(_on_delete_pressed)
	saved_row.add_child(_del_btn)

	_status_label = _label("", _C_DIM)
	saved_body.add_child(_status_label)

	_saved_dropdown.item_selected.connect(func(_i: int) -> void: _refresh_del_btn())
	_rebuild_saved_dropdown()

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
		var name: String = card.card_name if card else id
		var count: int = counts[id]

		var btn := Button.new()
		btn.text = "  %s  ×%d" % [name, count]
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
# Save / load / delete
# ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	var deck_name := _deck_name_input.text.strip_edges()
	if deck_name.is_empty():
		_status("Enter a deck name first.", _C_RED)
		return
	if _current_deck.is_empty():
		_status("Deck is empty.", _C_RED)
		return
	EnemySavedDecks.save_deck(deck_name, _current_deck)
	_rebuild_saved_dropdown()
	for i in _saved_dropdown.item_count:
		if (_saved_dropdown.get_item_metadata(i) as String) == deck_name:
			_saved_dropdown.select(i)
			break
	_status("Saved  \"%s\"  (%d cards)." % [deck_name, _current_deck.size()], _C_GREEN)

func _on_clear_pressed() -> void:
	_current_deck.clear()
	_rebuild_deck_display()
	_status("", _C_DIM)

func _on_load_pressed() -> void:
	var idx := _saved_dropdown.selected
	if idx < 0 or _saved_dropdown.item_count == 0:
		return
	var key: String = _saved_dropdown.get_item_metadata(idx) as String
	var all := EnemySavedDecks.load_all()
	_current_deck.clear()
	if all.has(key):
		for id in (all[key] as Array):
			_current_deck.append(id as String)
	elif key.begins_with("encounter_"):
		# Not customised yet — seed from hardcoded default
		var enc_idx := int(key.trim_prefix("encounter_"))
		for id in GameManager.get_default_encounter_deck(enc_idx):
			_current_deck.append(id as String)
	_deck_name_input.text = key
	_rebuild_deck_display()
	_status("Loaded  \"%s\"  (%d cards)." % [key, _current_deck.size()], _C_GREEN)

func _on_delete_pressed() -> void:
	var idx := _saved_dropdown.selected
	if idx < 0 or _saved_dropdown.item_count == 0:
		return
	var key: String = _saved_dropdown.get_item_metadata(idx) as String
	EnemySavedDecks.delete_deck(key)
	_rebuild_saved_dropdown()
	_status("Deleted  \"%s\"." % key, _C_DIM)

func _rebuild_saved_dropdown() -> void:
	_saved_dropdown.clear()
	var all := EnemySavedDecks.load_all()

	# Encounter decks always shown first, marked ★ when customised
	# Keys use 1-based fight numbers to match GameManager.get_encounter()
	for i in _ENCOUNTER_NAMES.size():
		var fight_num := i + 1
		var key := "encounter_%d" % fight_num
		var display: String = _ENCOUNTER_NAMES[i]
		if all.has(key):
			display += "  ★"
		_saved_dropdown.add_item(display)
		_saved_dropdown.set_item_metadata(_saved_dropdown.item_count - 1, key)

	# Custom named decks (any key not starting with "encounter_")
	var custom_names: Array = []
	for k in all.keys():
		if not (k as String).begins_with("encounter_"):
			custom_names.append(k)
	custom_names.sort()
	for name in custom_names:
		_saved_dropdown.add_item(name as String)
		_saved_dropdown.set_item_metadata(_saved_dropdown.item_count - 1, name as String)
	_refresh_del_btn()

func _refresh_del_btn() -> void:
	if _del_btn == null or _saved_dropdown == null:
		return
	var idx := _saved_dropdown.selected
	if idx < 0 or _saved_dropdown.item_count == 0:
		_del_btn.disabled = true
		return
	var key: String = _saved_dropdown.get_item_metadata(idx) as String
	_del_btn.disabled = key.begins_with("encounter_")

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
