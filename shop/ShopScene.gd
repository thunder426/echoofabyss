## ShopScene.gd
## Optional shop that appears before each act boss fight.
## Player spends Void Shards to buy cards (4 slots) and services (2 slots).
extends Control

const CardVisualScene := preload("res://combat/ui/CardVisual.tscn")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

const STANDARD_COST  := 2
const CHAMPION_COST  := 4
const COPY_CAP       := 2   ## Max copies of any non-champion card in deck

const COLOR_GOLD   := Color(0.90, 0.75, 0.20, 1.0)
const COLOR_PURPLE := Color(0.75, 0.35, 1.00, 1.0)
const COLOR_DIM    := Color(0.55, 0.52, 0.60, 1.0)
const COLOR_LIGHT  := Color(0.92, 0.90, 0.95, 1.0)
const COLOR_BG     := Color(0.04, 0.02, 0.08, 0.96)
const COLOR_RED    := Color(1.00, 0.30, 0.30, 1.0)

const VARIANT_CORE_UNITS: Array[String] = [
	"senior_void_imp", "runic_void_imp", "void_imp_wizard",
]

## Pool names that make up the always-available core card pool.
const CORE_POOL_NAMES: Array[String] = ["abyss_core", "neutral_core"]

## All possible services: id, display name, description, shard cost, available in first shop.
const ALL_SERVICES: Array = [
	{id="hp_restore",        name="HP Restoration",       desc="Restore 500 HP.",                                       cost=1, first_shop=true },
	{id="refresh_shop",      name="Refresh Shop",          desc="Reroll all card and service slots.",                    cost=1, first_shop=true },
	{id="random_card",       name="Random Card",           desc="Add a random card from any available pool to deck.",    cost=1, first_shop=true },
	{id="card_removal",      name="Card Removal",          desc="Remove one card from your deck permanently.",           cost=3, first_shop=false},
	{id="max_hp",            name="Max HP Increase",       desc="Permanently increase max HP by 300.",                   cost=4, first_shop=false},
	{id="expand_core_unit",  name="Expand Core Unit",      desc="Increase max Void Imp copies by 1 and add one to deck.",cost=3, first_shop=false},
	{id="core_unit_variant", name="Core Unit Variant",     desc="Add the branch-appropriate Void Imp variant to deck.",  cost=4, first_shop=false},
]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _is_first_shop: bool = false
var _vp: Vector2 = Vector2.ZERO

var _shard_label: Label       = null
var _card_row: HBoxContainer  = null
var _srv_row: HBoxContainer   = null

## Currently offered card IDs and their costs.
var _card_offers: Array[Dictionary] = []  # [{card_id, cost}]
## Currently offered services.
var _service_offers: Array[Dictionary] = []

## Panel shown when buying card_removal service (pick a deck card to remove).
var _remove_overlay: Control = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_is_first_shop = GameManager.void_shards <= 2
	call_deferred("_build_ui")

# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_vp = get_viewport_rect().size

	# Background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = COLOR_BG
	add_child(bg)

	# Title
	var title_lbl := Label.new()
	title_lbl.text = "SHOP"
	title_lbl.add_theme_font_size_override("font_size", 36)
	title_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	title_lbl.set_position(Vector2(_vp.x * 0.5 - 50, 18))
	add_child(title_lbl)

	# Shard count
	_shard_label = Label.new()
	_shard_label.add_theme_font_size_override("font_size", 20)
	_shard_label.add_theme_color_override("font_color", COLOR_PURPLE)
	_shard_label.set_position(Vector2(_vp.x * 0.5 + 80, 26))
	add_child(_shard_label)
	_update_shard_label()

	# --- Cards section ---
	var cards_hdr := Label.new()
	cards_hdr.text = "CARDS  —  Standard: %d Shards  |  Champion: %d Shards" % [STANDARD_COST, CHAMPION_COST]
	cards_hdr.add_theme_font_size_override("font_size", 14)
	cards_hdr.add_theme_color_override("font_color", COLOR_DIM)
	cards_hdr.set_position(Vector2(40, 76))
	add_child(cards_hdr)

	_card_row = HBoxContainer.new()
	_card_row.add_theme_constant_override("separation", 24)
	_card_row.set_position(Vector2(40, 104))
	add_child(_card_row)
	_populate_card_slots()

	# --- Services section ---
	var srv_hdr := Label.new()
	srv_hdr.text = "SERVICES"
	srv_hdr.add_theme_font_size_override("font_size", 14)
	srv_hdr.add_theme_color_override("font_color", COLOR_DIM)
	srv_hdr.set_position(Vector2(40, _vp.y - 210))
	add_child(srv_hdr)

	_srv_row = HBoxContainer.new()
	_srv_row.add_theme_constant_override("separation", 24)
	_srv_row.set_position(Vector2(40, _vp.y - 182))
	add_child(_srv_row)
	_populate_service_slots()

	# Leave button
	var leave_btn := Button.new()
	leave_btn.text = "LEAVE SHOP"
	leave_btn.set_size(Vector2(180, 50))
	leave_btn.set_position(Vector2(_vp.x - 210, _vp.y - 70))
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.add_theme_color_override("font_color", COLOR_GOLD)
	leave_btn.pressed.connect(_on_leave)
	add_child(leave_btn)

# ---------------------------------------------------------------------------
# Card slots
# ---------------------------------------------------------------------------

func _populate_card_slots() -> void:
	for child in _card_row.get_children():
		child.queue_free()
	_card_offers.clear()

	var branch_pool := _get_branch_pool()
	var full_pool   := _get_full_pool()

	# Slots 1-2: from branch pool; remainder up to 4: from any pool
	_fill_card_offers(branch_pool, 2)
	_fill_card_offers(full_pool, 4 - _card_offers.size())

	for offer in _card_offers:
		_add_card_slot(offer)

func _fill_card_offers(pool: Array[String], count: int) -> void:
	var shuffled := pool.duplicate()
	shuffled.shuffle()
	var added := 0
	for card_id in shuffled:
		if added >= count:
			break
		# Skip if already offered
		var already := false
		for o in _card_offers:
			if o.card_id == card_id:
				already = true
				break
		if already:
			continue
		var card := CardDatabase.get_card(card_id)
		if card == null:
			continue
		var is_champ := card is MinionCardData and (card as MinionCardData).is_champion
		# First shop: no champion cards
		if _is_first_shop and is_champ:
			continue
		var cost := CHAMPION_COST if is_champ else STANDARD_COST
		_card_offers.append({card_id = card_id, cost = cost})
		added += 1

func _add_card_slot(offer: Dictionary) -> void:
	var card_id: String = offer.card_id
	var cost: int       = offer.cost
	var card := CardDatabase.get_card(card_id)
	if card == null:
		return

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 6)
	_card_row.add_child(wrapper)

	# CardVisual
	var visual: CardVisual = CardVisualScene.instantiate()
	wrapper.add_child(visual)
	visual.apply_size_mode("shop")
	visual.setup(card)

	# Price label
	var price_lbl := Label.new()
	price_lbl.text = "%d Shards" % cost
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 14)
	price_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	wrapper.add_child(price_lbl)

	# Buy button
	var btn := Button.new()
	btn.text = "Buy"
	btn.custom_minimum_size = Vector2(200, 36)
	btn.add_theme_font_size_override("font_size", 15)
	var copies := GameManager.player_deck.count(card_id)
	var is_champ := card is MinionCardData and (card as MinionCardData).is_champion
	var cap := 1 if is_champ else COPY_CAP
	var can_buy := GameManager.void_shards >= cost and copies < cap
	btn.disabled = not can_buy
	btn.pressed.connect(_on_buy_card.bind(card_id, cost, wrapper))
	wrapper.add_child(btn)

func _on_buy_card(card_id: String, cost: int, slot_node: Control) -> void:
	if not GameManager.spend_shards(cost):
		return
	GameManager.player_deck.append(card_id)
	_update_shard_label()
	# Remove slot
	slot_node.queue_free()
	_update_remaining_buy_buttons()

# ---------------------------------------------------------------------------
# Service slots
# ---------------------------------------------------------------------------

func _populate_service_slots() -> void:
	for child in _srv_row.get_children():
		child.queue_free()
	_service_offers.clear()

	# Filter eligible services
	var eligible: Array[Dictionary] = []
	for svc in ALL_SERVICES:
		if _is_first_shop and not svc.first_shop:
			continue
		eligible.append(svc)

	eligible.shuffle()
	_service_offers = eligible.slice(0, 2)

	for svc in _service_offers:
		_add_service_slot(svc)

func _add_service_slot(svc: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 120)
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.08, 0.05, 0.14, 0.90)
	style.border_color = Color(0.35, 0.20, 0.55, 0.70)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	_srv_row.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   14)
	margin.add_theme_constant_override("margin_right",  14)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(margin)
	margin.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = svc.name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", COLOR_LIGHT)
	vbox.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = svc.desc
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", COLOR_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)

	var btn := Button.new()
	btn.text = "%d Shards" % svc.cost
	btn.add_theme_font_size_override("font_size", 14)
	btn.disabled = GameManager.void_shards < svc.cost
	btn.pressed.connect(_on_buy_service.bind(svc, btn))
	vbox.add_child(btn)

func _on_buy_service(svc: Dictionary, btn: Button) -> void:
	match svc.id:
		"hp_restore":
			if not GameManager.spend_shards(svc.cost): return
			GameManager.player_hp = mini(GameManager.player_hp + 500, GameManager.player_hp_max)
			btn.disabled = true
		"refresh_shop":
			if not GameManager.spend_shards(svc.cost): return
			_populate_card_slots()
			_populate_service_slots()
		"random_card":
			if not GameManager.spend_shards(svc.cost): return
			_grant_random_card()
			btn.disabled = true
		"card_removal":
			if not GameManager.spend_shards(svc.cost): return
			_show_card_removal_overlay()
			btn.disabled = true
		"max_hp":
			if not GameManager.spend_shards(svc.cost): return
			GameManager.player_hp_max += 300
			GameManager.player_hp    += 300
			btn.disabled = true
		"expand_core_unit":
			if not GameManager.spend_shards(svc.cost): return
			if GameManager.core_unit_limit < 6:
				GameManager.core_unit_limit += 1
				GameManager.player_deck.append("void_imp")
			btn.disabled = true
		"core_unit_variant":
			if not GameManager.spend_shards(svc.cost): return
			_grant_core_unit_variant()
			btn.disabled = true
	_update_shard_label()
	_update_remaining_buy_buttons()

# ---------------------------------------------------------------------------
# Service helpers
# ---------------------------------------------------------------------------

func _grant_random_card() -> void:
	var pool := _get_full_pool()
	pool.shuffle()
	for card_id in pool:
		var card := CardDatabase.get_card(card_id)
		if card == null:
			continue
		var is_champ := card is MinionCardData and (card as MinionCardData).is_champion
		var cap := 1 if is_champ else COPY_CAP
		if GameManager.player_deck.count(card_id) < cap:
			GameManager.player_deck.append(card_id)
			return

func _grant_core_unit_variant() -> void:
	var variant_id: String = ""
	if GameManager.has_talent("imp_evolution"):
		variant_id = "senior_void_imp"
	elif GameManager.has_talent("piercing_void"):
		variant_id = "void_imp_wizard"
	elif GameManager.has_talent("rune_caller"):
		variant_id = "runic_void_imp"
	else:
		var options := VARIANT_CORE_UNITS.duplicate()
		options.shuffle()
		variant_id = options[0]
	if GameManager.player_deck.count(variant_id) == 0:
		GameManager.player_deck.append(variant_id)

func _show_card_removal_overlay() -> void:
	if _remove_overlay:
		_remove_overlay.queue_free()

	var overlay := Panel.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 30
	var ovl_style := StyleBoxFlat.new()
	ovl_style.bg_color = Color(0.02, 0.01, 0.06, 0.96)
	ovl_style.border_color = COLOR_PURPLE
	ovl_style.set_border_width_all(2)
	overlay.add_theme_stylebox_override("panel", ovl_style)
	add_child(overlay)
	_remove_overlay = overlay

	var hdr := Label.new()
	hdr.text = "Choose a card to remove from your deck:"
	hdr.add_theme_font_size_override("font_size", 18)
	hdr.add_theme_color_override("font_color", COLOR_LIGHT)
	hdr.set_position(Vector2(40, 30))
	overlay.add_child(hdr)

	var scroll := ScrollContainer.new()
	scroll.set_position(Vector2(40, 76))
	scroll.set_size(Vector2(_vp.x - 80, _vp.y - 160))
	overlay.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	var unique_ids: Array[String] = []
	for id in GameManager.player_deck:
		if id not in unique_ids:
			unique_ids.append(id)

	for card_id in unique_ids:
		var card := CardDatabase.get_card(card_id)
		var btn := Button.new()
		btn.text = "%s  (×%d in deck)" % [card.card_name if card else card_id, GameManager.player_deck.count(card_id)]
		btn.custom_minimum_size = Vector2(0, 46)
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(func():
			var idx := GameManager.player_deck.find(card_id)
			if idx >= 0:
				GameManager.player_deck.remove_at(idx)
			overlay.queue_free()
			_remove_overlay = null
		)
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel (keep shards)"
	cancel.set_position(Vector2(40, _vp.y - 70))
	cancel.add_theme_font_size_override("font_size", 14)
	cancel.pressed.connect(func():
		# Refund the shards since we cancelled
		GameManager.earn_shards(3)  # card_removal cost is 3
		overlay.queue_free()
		_remove_overlay = null
		_update_shard_label()
		_update_remaining_buy_buttons()
	)
	overlay.add_child(cancel)

# ---------------------------------------------------------------------------
# Pool builders
# ---------------------------------------------------------------------------

## Cards from all active talent branch pools that are permanently unlocked.
func _get_branch_pool() -> Array[String]:
	var pool: Array[String] = []
	var seen: Dictionary = {}
	var branch_pool_names: Array[String] = []
	if GameManager.has_talent("piercing_void"):
		branch_pool_names.append("vael_piercing_void")
	if GameManager.has_talent("imp_evolution"):
		branch_pool_names.append("vael_endless_tide")
	if GameManager.has_talent("rune_caller"):
		branch_pool_names.append("vael_rune_master")
	if branch_pool_names.is_empty():
		branch_pool_names.append("vael_common")
	for card_id in CardDatabase.get_card_ids_in_pools(branch_pool_names):
		if card_id in GameManager.permanent_unlocks and card_id not in VARIANT_CORE_UNITS and card_id not in seen:
			pool.append(card_id)
			seen[card_id] = true
	return pool

## All cards from any available pool (core always available + unlocked support pools).
func _get_full_pool() -> Array[String]:
	var pool: Array[String] = []
	var seen: Dictionary = {}

	# Base pool — always available, no unlock gate
	for card_id in CardDatabase.get_card_ids_in_pools(CORE_POOL_NAMES):
		if card_id not in VARIANT_CORE_UNITS and card_id not in seen:
			pool.append(card_id)
			seen[card_id] = true

	# Talent branch support pools — require permanent unlock
	var talent_pools: Array[String] = []
	if GameManager.has_talent("piercing_void"):
		talent_pools.append("vael_piercing_void")
	if GameManager.has_talent("imp_evolution"):
		talent_pools.append("vael_endless_tide")
	if GameManager.has_talent("rune_caller"):
		talent_pools.append("vael_rune_master")

	for pool_name in talent_pools:
		for card_id in CardDatabase.get_card_ids_in_pools([pool_name]):
			if card_id in GameManager.permanent_unlocks and card_id not in VARIANT_CORE_UNITS and card_id not in seen:
				pool.append(card_id)
				seen[card_id] = true
	return pool

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _update_shard_label() -> void:
	if _shard_label:
		_shard_label.text = "◆ %d Shards" % GameManager.void_shards

## Refresh disabled state on all buy buttons after shard balance changes.
func _update_remaining_buy_buttons() -> void:
	if _card_row:
		for wrapper in _card_row.get_children():
			var btn: Button = null
			for child in wrapper.get_children():
				if child is Button:
					btn = child
					break
			if btn == null:
				continue
			# Find matching offer
			for offer in _card_offers:
				var card := CardDatabase.get_card(offer.card_id)
				if card == null:
					continue
				var is_champ := card is MinionCardData and (card as MinionCardData).is_champion
				var cap := 1 if is_champ else COPY_CAP
				btn.disabled = GameManager.void_shards < offer.cost or GameManager.player_deck.count(offer.card_id) >= cap

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_leave() -> void:
	GameManager.go_to_scene("res://map/EncounterLoadingScene.tscn")
