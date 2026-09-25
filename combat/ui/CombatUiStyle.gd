## CombatUiStyle.gd
## Combat UI style and tooltip builders (moved off CombatScene in plan 4.4):
## panel styleboxes and the faction empty-slot look (static), and the hero
## panels' hover tooltips (talents / passives, enemy passives), which need the
## scene's viewport and UI root. Pure presentation — reads state, never writes.
class_name CombatUiStyle
extends RefCounted

var _scene: Node = null

func _init(scene: Node) -> void:
	_scene = scene

static func create_stylebox(bg: Color, border: Color, corner_radius: int = 4, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color     = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style

static func apply_slot_style(panel: Panel, bg: Color, border: Color) -> void:
	# Hide empty-slot image if the slot is now occupied/styled
	var img := panel.get_node_or_null("_empty_slot_bg") as TextureRect
	if img:
		img.visible = false
	panel.add_theme_stylebox_override("panel", create_stylebox(bg, border))

## Apply the faction empty-slot image (or fallback dark style) to a plain Panel.
## Pass lbl=null if the panel has no text label to manage.
static func apply_empty_slot(panel: Panel, lbl: Label) -> void:
	var empty_bg: String = HeroDatabase.empty_slot_bg_for_hero(GameManager.current_hero)
	var img := panel.get_node_or_null("_empty_slot_bg") as TextureRect
	if empty_bg != "" and ResourceLoader.exists(empty_bg):
		# Transparent panel so the image shows through
		var blank := StyleBoxFlat.new()
		blank.bg_color = Color(0, 0, 0, 0)
		panel.add_theme_stylebox_override("panel", blank)
		# Create image node on first use
		if img == null:
			img = TextureRect.new()
			img.name = "_empty_slot_bg"
			img.stretch_mode = TextureRect.STRETCH_SCALE
			img.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
			img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(img)
		img.texture = load(empty_bg)
		img.visible = true
		if lbl:
			lbl.visible = false
	else:
		if img:
			img.visible = false
		apply_slot_style(panel, Color(0.08, 0.08, 0.14, 1), Color(0.22, 0.22, 0.38, 1))
		if lbl:
			lbl.text    = "[ — ]"
			lbl.visible = true

## Build a floating tooltip panel scaffold (PanelContainer → MarginContainer → VBoxContainer).
## Anchors at bottom-left of the viewport. Returns {tip, tip_vbox}.
func build_hover_tooltip_scaffold(ui_root: Node, min_width: float, bg_color: Color, border_color: Color) -> Dictionary:
	var tip := PanelContainer.new()
	tip.visible             = false
	tip.z_index             = 50
	tip.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	tip.custom_minimum_size = Vector2(min_width, 0)
	tip.add_theme_stylebox_override("panel", create_stylebox(bg_color, border_color, 6))
	ui_root.add_child(tip)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(margin)
	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 8)
	tip_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(tip_vbox)
	tip.position = Vector2(16.0, 0.0)
	# Label text measurement is deferred to the first layout frame, so
	# get_minimum_size() returns 0-height on the very first hover call.
	# Connect minimum_size_changed so the panel self-sizes as soon as Godot
	# measures the content (typically one frame after being added to the tree).
	tip.minimum_size_changed.connect(func() -> void:
		if not tip.is_inside_tree():
			return
		var ms := tip.get_minimum_size()
		if ms.y > 0:
			tip.size = ms
			tip.position.y = _scene.get_viewport().get_visible_rect().size.y - ms.y - 16.0
	)
	return {tip = tip, tip_vbox = tip_vbox}

static func add_tooltip_icon_block(parent: VBoxContainer, title: String, body: String, icon_path: String,
		title_color: Color, body_color: Color) -> void:
	var outer := HBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_BEGIN
	outer.add_theme_constant_override("separation", 10)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(outer)

	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon_bg := PanelContainer.new()
		icon_bg.custom_minimum_size = Vector2(44, 44)
		icon_bg.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_style := StyleBoxFlat.new()
		icon_style.bg_color = Color(0.12, 0.08, 0.18, 0.92)
		icon_style.border_color = Color(0.48, 0.28, 0.72, 0.95)
		icon_style.set_border_width_all(1)
		icon_style.set_corner_radius_all(5)
		icon_style.content_margin_left = 4.0
		icon_style.content_margin_right = 4.0
		icon_style.content_margin_top = 4.0
		icon_style.content_margin_bottom = 4.0
		icon_bg.add_theme_stylebox_override("panel", icon_style)
		outer.add_child(icon_bg)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(36, 36)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(icon_path)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_bg.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	text_box.add_theme_constant_override("separation", 3)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(text_box)

	if title != "":
		var title_lbl := Label.new()
		title_lbl.text = title
		title_lbl.add_theme_font_size_override("font_size", 15)
		title_lbl.add_theme_color_override("font_color", title_color)
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_box.add_child(title_lbl)

	var body_lbl := Label.new()
	body_lbl.text = body
	body_lbl.add_theme_font_size_override("font_size", 12)
	body_lbl.add_theme_color_override("font_color", body_color)
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(body_lbl)

func add_talent_hover_icon(parent: HBoxContainer, _anchor_panel: Control) -> void:
	var icon_btn := Label.new()
	icon_btn.text = "✦"
	icon_btn.add_theme_font_size_override("font_size", 14)
	icon_btn.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0, 0.75))
	icon_btn.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	icon_btn.custom_minimum_size = Vector2(18, 18)
	icon_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(icon_btn)

	var ui_root: Node = _scene.get_node_or_null("UI")
	if ui_root == null:
		return
	var scaffold := build_hover_tooltip_scaffold(ui_root, 400, Color(0.05, 0.02, 0.10, 0.97), Color(0.55, 0.30, 0.85, 0.90))
	var tip: PanelContainer = scaffold.tip
	var tip_vbox: VBoxContainer = scaffold.tip_vbox
	_scene._talent_tip_vbox = tip_vbox

	# --- Passives section ---
	var hero_data := HeroDatabase.get_hero(GameManager.current_hero)
	if hero_data != null and not hero_data.passives.is_empty():
		var passive_hdr := Label.new()
		passive_hdr.text = "PASSIVES"
		passive_hdr.add_theme_font_size_override("font_size", 13)
		passive_hdr.add_theme_color_override("font_color", Color(0.55, 0.85, 0.65, 1.0))
		passive_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		passive_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(passive_hdr)

		for passive in hero_data.passives:
			add_tooltip_icon_block(
				tip_vbox,
				"",
				passive.description,
				passive.icon_path,
				Color(0.90, 0.90, 0.90, 1.0),
				Color(0.65, 0.82, 0.70, 1.0)
			)

		var passive_sep := HSeparator.new()
		passive_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(passive_sep)

	# --- Talents section ---
	var talents_hdr := Label.new()
	talents_hdr.text = "TALENTS"
	talents_hdr.add_theme_font_size_override("font_size", 13)
	talents_hdr.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0, 1.0))
	talents_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	talents_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_vbox.add_child(talents_hdr)

	if GameManager.unlocked_talents.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No talents unlocked"
		none_lbl.add_theme_font_size_override("font_size", 13)
		none_lbl.add_theme_color_override("font_color", Color(0.55, 0.52, 0.60, 1))
		none_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(none_lbl)
	else:
		for tid in GameManager.unlocked_talents:
			var td: TalentData = TalentDatabase.get_talent(tid)
			if td == null:
				continue
			add_tooltip_icon_block(
				tip_vbox,
				td.talent_name,
				td.description,
				td.icon_path,
				Color(0.92, 0.85, 1.0, 1.0),
				Color(0.65, 0.62, 0.72, 1.0)
			)

	icon_btn.mouse_entered.connect(func() -> void:
		icon_btn.add_theme_color_override("font_color", Color(0.90, 0.70, 1.0, 1.0))
		# PanelContainer in CanvasLayer has no parent Container to set its size —
		# force it to its content minimum size each time it is shown.
		tip.size = tip.get_minimum_size()
		tip.position.y = _scene.get_viewport().get_visible_rect().size.y - tip.size.y - 16.0
		tip.visible = true
	)
	icon_btn.mouse_exited.connect(func() -> void:
		icon_btn.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0, 0.75))
		tip.visible = false
	)

func add_enemy_passive_hover_icon(parent: HBoxContainer, ui_root: Node) -> void:
	const PASSIVE_INFO: Dictionary = {
		"pack_instinct": {
			"name": "Pack Instinct",
			"desc": "Each Feral Imp gains +50 ATK for every other Feral Imp on the board."
		},
		"champion_rogue_imp_pack": {
			"name": "Champion: Rogue Imp Pack",
			"desc": "Summoned after 4 Rabid Imps have attacked. SWIFT. AURA: All friendly FERAL IMP minions have +100 ATK."
		},
		"champion_corrupted_broodlings": {
			"name": "Champion: Corrupted Broodlings",
			"desc": "Summoned after 3 friendly minions have died. On death: Summon a Void-Touched Imp."
		},
		"champion_imp_matriarch": {
			"name": "Champion: Imp Matriarch",
			"desc": "Summoned after 2nd Pack Frenzy cast. GUARD. AURA: Pack Frenzy also gives all FERAL IMP minions +200 HP."
		},
		"champion_abyss_cultist_patrol": {
			"name": "Champion: Abyss Cultist Patrol",
			"desc": "Summoned after 5 corruption stacks consumed. AURA: Corruption applied to enemy minions instantly detonates for 100 damage per stack."
		},
		"champion_void_ritualist": {
			"name": "Champion: Void Ritualist",
			"desc": "Summoned when Ritual Sacrifice triggers. AURA: Rune placement costs 1 less Mana."
		},
		"champion_corrupted_handler": {
			"name": "Champion: Corrupted Handler",
			"desc": "Summoned after 3 Void Sparks created. AURA: Whenever a Void Spark is summoned, deal 200 damage to enemy hero."
		},
		"champion_duel": {
			"name": "Champion: Void Duel",
			"desc": "Enemy minions with Critical Strike have Spell Immune."
		},
		"corrupted_death": {
			"name": "Corrupted Death",
			"desc": "Void-Touched Imp costs 1 less Essence."
		},
		"ancient_frenzy": {
			"name": "Ancient Frenzy",
			"desc": "Pack Frenzy also gives all FERAL IMP minions Lifedrain this turn, and costs 1 less Mana. Starts with one extra Pack Frenzy in hand."
		},
		# ── Act 2 enemy passives ──────────────────────────────────────────────────
		"feral_reinforcement": {
			"name": "Feral Reinforcement",
			"desc": "The first Human summoned each turn adds a random FERAL IMP to your hand."
		},
		"corrupt_authority": {
			"name": "Corrupt Authority",
			"desc": "Each Human summoned applies 1 Corruption to a random enemy minion. Each FERAL IMP summoned consumes all Corruption stacks on enemy minions, dealing 100 damage per stack."
		},
		"ritual_sacrifice": {
			"name": "Ritual Sacrifice",
			"desc": "When a FERAL IMP is summoned and you have a Blood Rune and Dominion Rune active: consume both runes and the imp, deal 200 damage to 2 random enemy targets, then summon a 500/500 Demon."
		},
		"void_unraveling": {
			"name": "Void Unraveling",
			"desc": "When a FERAL IMP is summoned, all enemy Void Sparks are Corrupted and transferred to your board."
		},
	}

	var icon_btn := Label.new()
	icon_btn.text = "◉"
	icon_btn.add_theme_font_size_override("font_size", 13)
	icon_btn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.30, 0.75))
	icon_btn.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	icon_btn.custom_minimum_size = Vector2(18, 18)
	icon_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(icon_btn)

	var scaffold := build_hover_tooltip_scaffold(ui_root, 300, Color(0.06, 0.02, 0.10, 0.97), Color(0.75, 0.35, 0.20, 0.90))
	var tip: PanelContainer = scaffold.tip
	var tip_vbox: VBoxContainer = scaffold.tip_vbox

	var hdr := Label.new()
	hdr.text = "ENEMY PASSIVES"
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", Color(1.0, 0.60, 0.25, 1.0))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_vbox.add_child(hdr)

	for pid in _scene.state.enemy_passives:
		var info: Dictionary = PASSIVE_INFO.get(pid, {})
		var p_name: String = info.get("name", pid) as String
		var p_desc: String = info.get("desc", "") as String

		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = p_name
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.50, 1.0))
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_lbl)

		if p_desc != "":
			var desc_lbl := Label.new()
			desc_lbl.text = p_desc
			desc_lbl.add_theme_font_size_override("font_size", 12)
			desc_lbl.add_theme_color_override("font_color", Color(0.78, 0.65, 0.55, 1.0))
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			row.add_child(desc_lbl)

	icon_btn.mouse_entered.connect(func() -> void:
		icon_btn.add_theme_color_override("font_color", Color(1.0, 0.70, 0.40, 1.0))
		# PanelContainer in CanvasLayer has no parent Container to set its size —
		# force it to its content minimum size each time it is shown.
		tip.size = tip.get_minimum_size()
		tip.position.y = _scene.get_viewport().get_visible_rect().size.y - tip.size.y - 16.0
		tip.visible = true
	)
	icon_btn.mouse_exited.connect(func() -> void:
		icon_btn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.30, 0.75))
		tip.visible = false
	)
