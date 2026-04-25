## CollectionScene.gd
## Shows all support cards. Unlocked = full color; locked = dimmed with lock icon.
## Accessible from the Main Menu.
extends Node2D

const CARD_VISUAL_SCENE := preload("res://combat/ui/CardVisual.tscn")
const PREVIEW_SIZE   := Vector2(480, 720)
const PREVIEW_OFFSET := Vector2(16, -PREVIEW_SIZE.y / 2.0)

# ---------------------------------------------------------------------------
# Filter state  (-1 / "" = All)
# ---------------------------------------------------------------------------

var _filter_type:   int    = -1
var _filter_act_gate: int = 0   # 0 = All
var _filter_status: int    = 0   # 0=All  1=Unlocked  2=Locked
var _filter_pool:   String = ""  # "" = All

# ---------------------------------------------------------------------------
# Node refs
# ---------------------------------------------------------------------------

var _preview:   CardVisual    = null
var _container: VBoxContainer = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_container = $UI/ScrollContainer/CardList
	$UI/BackButton.pressed.connect(_on_back)
	_setup_preview()
	_setup_filters()
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
# Filter UI — 3 OptionButton dropdowns in FilterRow
# ---------------------------------------------------------------------------

func _setup_filters() -> void:
	var row: HBoxContainer = $UI/FilterRow

	_add_dropdown(row, "Type",
		["All", "Minion", "Spell", "Trap", "Env"],
		func(idx: int) -> void:
			var vals := [-1, Enums.CardType.MINION, Enums.CardType.SPELL,
				Enums.CardType.TRAP, Enums.CardType.ENVIRONMENT]
			_filter_type = vals[idx]
			_build_list()
	)

	_add_dropdown(row, "Act",
		["All Acts", "Act 1", "Act 2", "Act 3", "Act 4"],
		func(idx: int) -> void:
			_filter_act_gate = idx
			_build_list()
	)

	_add_dropdown(row, "Status",
		["All", "Unlocked", "Locked"],
		func(idx: int) -> void:
			_filter_status = idx
			_build_list()
	)

	_add_dropdown(row, "Pool",
		["All Pools", "Vael Pool", "Void Bolt Pool", "Endless Tide Pool", "Rune Master Pool", "Feral Imp Clan", "Abyss Cultist Clan", "Void Rift", "Void Castle"],
		func(idx: int) -> void:
			var vals := ["", "vael_common", "vael_piercing_void", "vael_endless_tide", "vael_rune_master", "feral_imp_clan", "abyss_cultist_clan", "void_rift", "void_castle"]
			_filter_pool = vals[idx]
			_build_list()
	)

func _add_dropdown(parent: HBoxContainer, label_text: String,
		items: Array, on_change: Callable) -> void:
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lbl)

	var opt := OptionButton.new()
	for item in items:
		opt.add_item(item)
	opt.selected = 0
	opt.custom_minimum_size = Vector2(150, 36)
	opt.add_theme_font_size_override("font_size", 14)
	opt.item_selected.connect(on_change)
	parent.add_child(opt)

	# Small spacer between dropdowns
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 0)
	parent.add_child(spacer)

# ---------------------------------------------------------------------------
# List
# ---------------------------------------------------------------------------

func _build_list() -> void:
	for child in _container.get_children():
		child.queue_free()

	var unlocked := GameManager.permanent_unlocks

	# --- Filter ---
	var visible_ids: Array[String] = []
	for card_id in CardDatabase.get_card_ids_in_pools(["vael_common", "vael_piercing_void", "vael_endless_tide", "vael_rune_master", "feral_imp_clan", "abyss_cultist_clan", "void_rift", "void_castle"]):
		var card := CardDatabase.get_card(card_id)
		if not card:
			continue
		var is_unlocked := true

		if _filter_type != -1 and card.card_type != _filter_type:
			continue
		if _filter_act_gate != 0 and card.act_gate != _filter_act_gate:
			continue
		if _filter_status == 1 and not is_unlocked:
			continue
		if _filter_status == 2 and is_unlocked:
			continue
		if _filter_pool != "" and not (_filter_pool in card.pools):
			continue
		visible_ids.append(card_id)

	if visible_ids.is_empty():
		var lbl := Label.new()
		lbl.text = "No cards match the current filters."
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65, 1))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_container.add_child(lbl)
		return

	# --- Sort: pool asc, then act_gate asc, then name ---
	# Cards in multiple pools sort by their first pool entry (the order they're listed
	# in CardDatabase._card_pools) — stable across builds.
	var pool_order := {"vael_common": 0, "vael_piercing_void": 1, "vael_endless_tide": 2, "vael_rune_master": 3, "feral_imp_clan": 4, "abyss_cultist_clan": 5, "void_rift": 6, "void_castle": 7}
	var first_pool_for := func(card: CardData) -> String:
		if card == null or card.pools.is_empty():
			return ""
		return card.pools[0]
	visible_ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := CardDatabase.get_card(a)
		var cb := CardDatabase.get_card(b)
		var pa: int = pool_order.get(first_pool_for.call(ca), 99)
		var pb: int = pool_order.get(first_pool_for.call(cb), 99)
		if pa != pb:
			return pa < pb
		var ra: int = ca.act_gate if ca else 99
		var rb: int = cb.act_gate if cb else 99
		if ra != rb:
			return ra < rb
		return (ca.card_name if ca else a) < (cb.card_name if cb else b)
	)

	# --- Column header ---
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	_add_cell(header, "",            28,  HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.60, 0.85, 1))
	_add_cell(header, "Pool",       130, HORIZONTAL_ALIGNMENT_LEFT,   Color(0.55, 0.60, 0.85, 1))
	_add_cell(header, "Act",        100, HORIZONTAL_ALIGNMENT_LEFT,   Color(0.55, 0.60, 0.85, 1))
	_add_cell(header, "Type",        60, HORIZONTAL_ALIGNMENT_LEFT,   Color(0.55, 0.60, 0.85, 1))
	_add_cell(header, "Name",       200, HORIZONTAL_ALIGNMENT_LEFT,   Color(0.55, 0.60, 0.85, 1))
	_add_cell(header, "Description", 500, HORIZONTAL_ALIGNMENT_LEFT,  Color(0.55, 0.60, 0.85, 1), true)
	_container.add_child(header)
	_container.add_child(HSeparator.new())

	# --- Rows ---
	for card_id in visible_ids:
		var card        := CardDatabase.get_card(card_id)
		if not card:
			continue
		var is_unlocked := card_id in unlocked

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 44)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		if not is_unlocked:
			row.modulate = Color(0.45, 0.45, 0.50, 1)

		# Comma-join all pools the card belongs to (e.g. "Vael Common, Demon Forge").
		# Color uses the first pool — visually consistent with sort order.
		var pool_displays: Array[String] = []
		for p in card.pools:
			pool_displays.append(_pool_display_name(p))
		var pool_display: String = ", ".join(pool_displays) if not pool_displays.is_empty() else ""
		var primary_pool: String = card.pools[0] if not card.pools.is_empty() else ""
		_add_cell(row, "🔓" if is_unlocked else "🔒", 28, HORIZONTAL_ALIGNMENT_CENTER,
			Color(1, 1, 1, 1))
		_add_cell(row, pool_display, 130, HORIZONTAL_ALIGNMENT_LEFT,
			_pool_color(primary_pool))
		_add_cell(row, _act_gate_label(card.act_gate), 100, HORIZONTAL_ALIGNMENT_LEFT,
			_act_gate_color(card.act_gate))
		_add_cell(row, _type_str(card.card_type), 60, HORIZONTAL_ALIGNMENT_LEFT,
			Color(0.60, 0.65, 0.80, 1))
		_add_cell(row, card.card_name, 200, HORIZONTAL_ALIGNMENT_LEFT,
			Color(0.90, 0.90, 1.00, 1))
		_add_cell(row, card.description, 500, HORIZONTAL_ALIGNMENT_LEFT,
			Color(0.65, 0.65, 0.75, 1), true)

		row.mouse_entered.connect(_show_preview.bind(card_id))
		row.mouse_exited.connect(_hide_preview)
		_container.add_child(row)
		_container.add_child(HSeparator.new())

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _add_cell(parent: HBoxContainer, text: String, min_w: int,
		align: HorizontalAlignment, color: Color, expand: bool = false) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = align
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.custom_minimum_size = Vector2(min_w, 0)
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		lbl.clip_text = true
	parent.add_child(lbl)

func _type_str(t: Enums.CardType) -> String:
	match t:
		Enums.CardType.MINION:      return "Minion"
		Enums.CardType.SPELL:       return "Spell"
		Enums.CardType.TRAP:        return "Trap"
		Enums.CardType.ENVIRONMENT: return "Env"
	return "?"

func _pool_display_name(pool: String) -> String:
	match pool:
		"vael_common":        return "Vael Pool"
		"vael_piercing_void": return "Void Bolt Pool"
		"vael_endless_tide":  return "Endless Tide Pool"
		"vael_rune_master":   return "Rune Master Pool"
		"feral_imp_clan":           return "Feral Imp Clan"
		"abyss_cultist_clan":       return "Abyss Cultist Clan"
		"void_rift":                return "Void Rift"
		"void_castle":              return "Void Castle"
	return pool

func _pool_color(pool: String) -> Color:
	match pool:
		"vael_common":        return Color(0.65, 1.00, 0.55, 1)
		"vael_piercing_void": return Color(0.55, 0.80, 1.00, 1)
		"vael_endless_tide":  return Color(1.00, 0.70, 0.30, 1)
		"vael_rune_master":   return Color(0.90, 0.55, 1.00, 1)
		"feral_imp_clan":           return Color(1.00, 0.45, 0.35, 1)
		"abyss_cultist_clan":       return Color(0.80, 0.50, 0.90, 1)
		"void_rift":                return Color(0.70, 0.20, 0.90, 1)
		"void_castle":              return Color(1.00, 0.75, 0.10, 1)
	return Color(0.55, 0.55, 0.65, 1)

func _act_gate_label(gate: int) -> String:
	if gate == 4:
		return "Champion"
	if gate >= 1:
		return "Act %d" % gate
	return "—"

func _act_gate_color(gate: int) -> Color:
	match gate:
		1: return Color(0.75, 0.75, 0.75, 1)
		2: return Color(0.30, 0.60, 1.00, 1)
		3: return Color(0.70, 0.20, 0.90, 1)
		4: return Color(1.00, 0.75, 0.10, 1)
	return Color(0.55, 0.55, 0.65, 1)

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_back() -> void:
	GameManager.go_to_scene("res://ui/MainMenu.tscn")
