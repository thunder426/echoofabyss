## CardVisual.gd
## The visual representation of a single card in the player's hand.
##
## Scene tree expected:
##   CardVisual (Control)
##   ├── Background (Panel)
##   ├── ArtRect (TextureRect)
##   ├── FrameTexture (TextureRect)
##   ├── NameLabel (Label)
##   ├── DescLabel (RichTextLabel)  ← keywords line 1 via BBCode, then description
##   ├── RaceLabel (Label)
##   ├── StatsRow (HBoxContainer)   ← only visible for minion cards
##   │   ├── AtkLabel (Label)
##   │   ├── HpLabel (Label)
##   │   └── ShieldLabel (Label)    ← only visible when shield_max > 0
##   ├── CostBadge (Control)
##   │   └── CostLabel (Label)
##   ├── ManaBadge (Control)
##   │   └── ManaLabel (Label)
##   └── FrameCostLabel / FrameManaLabel / FrameAtkLabel / FrameHpLabel
class_name CardVisual
extends Control

# ---------------------------------------------------------------------------
# Frame textures — keyed by [faction][card_type]; add entries for future factions
# ---------------------------------------------------------------------------
const _FRAME_PATH: Dictionary = {
	"abyss_order": {
		Enums.CardType.MINION:      "res://assets/art/frames/abyss_order/frame_minion.png",
		Enums.CardType.SPELL:       "res://assets/art/frames/abyss_order/frame_spell.png",
		Enums.CardType.TRAP:        "res://assets/art/frames/abyss_order/frame_trap.png",
		Enums.CardType.ENVIRONMENT: "res://assets/art/frames/abyss_order/frame_environment.png",
	},
}

## Minion frames — keyed by faction. One shared frame for all races within a faction.
## When present, activates stat overlays and the race tag bar.
const _MINION_FRAME_PATH: Dictionary = {
	"abyss_order": "res://assets/art/frames/abyss_order/abyss_minion.png",
}

# ---------------------------------------------------------------------------
# Layout configuration — ALL anchor positions live here.
# Each style key maps node names to [left, top, right, bottom] anchor values.
# To reposition any element, edit only this section.
# ---------------------------------------------------------------------------
# fmt: off
const _LAYOUT: Dictionary = {
	## Used when a faction minion frame (e.g. abyss_minion.png) is loaded.
	## Frame PNG has embedded cost/atk/hp panels — overlay labels are used.
	"minion_framed": {
		"art":        [0.08, 0.14, 0.92, 0.78],  # art window inside the frame
		"name":       [0.15, 0.10, 0.93, 0.18],  # card name strip (right of cost badge)
		"race":       [0.05, 0.67, 0.95, 0.72],  # race tag bar (between art and desc)
		"desc":       [0.16, 0.72, 0.85, 0.85],  # description text (keywords on line 1 via BBCode)
		"frame_cost": [0.01, 0.07, 0.28, 0.19],  # cost number overlay (top-left)
		"frame_mana": [0.26, 0.01, 0.54, 0.19],  # mana number overlay (top-centre)
		"frame_atk":  [0.07, 0.82, 0.42, 0.99],  # ATK number overlay (bottom-left)
		"frame_hp":   [0.58, 0.82, 0.82, 0.99],  # HP number overlay (bottom-right)
	},
	## Used for all non-minion cards and minions without a faction frame.
	## Drawn cost badge + StatsRow are used instead of overlay labels.
	"default": {
		"art":        [0.08, 0.14, 0.92, 0.62],  # art window
		"name":       [0.20, 0.03, 0.97, 0.16],  # card name strip
		"race":       [0.05, 0.57, 0.95, 0.64],  # race tag (hidden for non-minions)
		"desc":       [0.06, 0.62, 0.94, 0.88],  # description text (keywords on line 1 via BBCode)
		"stats":      [0.06, 0.88, 0.94, 0.97],  # ATK / HP row (minion fallback)
		"cost_badge": [0.01, 0.01, 0.25, 0.19],  # drawn cost badge
		"mana_badge": [0.23, 0.01, 0.47, 0.19],  # drawn mana badge
	},
}
# fmt: on

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal card_clicked(card_visual: CardVisual)
signal card_hovered(card_visual: CardVisual)
signal card_unhovered(card_visual: CardVisual)

# ---------------------------------------------------------------------------
# Node references — found automatically in _ready()
# ---------------------------------------------------------------------------

var background:    Panel
var art_rect:      TextureRect
var frame_texture: TextureRect
var cost_badge:    CostBadge
var mana_badge:    CostBadge
var cost_label:    Label
var mana_label:    Label
var name_label:    Label
var desc_label:    RichTextLabel
var stats_row:     Control
var atk_label:     Label
var hp_label:      Label
var shield_label:  Label
var race_label:    Label
# Frame-embedded stat overlays — visible only for faction minion frames
var frame_cost_label: Label
var frame_mana_label: Label
var frame_atk_label:  Label
var frame_hp_label:   Label

## True when using a faction minion frame (abyss_minion, etc.).
## Drives which stat display is shown.
var _using_minion_frame: bool = false

# ---------------------------------------------------------------------------
# Card state
# ---------------------------------------------------------------------------

var card_data: CardData = null
var is_selected: bool = false
var is_playable: bool = true

# Scale constants — hover/select uses scale so HBoxContainer layout is unaffected
const SCALE_NORMAL   := Vector2(1.0, 1.0)
const SCALE_HOVER    := Vector2(1.12, 1.12)
const SCALE_SELECTED := Vector2(1.18, 1.18)

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_find_nodes()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func _find_nodes() -> void:
	background        = $Background               if has_node("Background")               else null
	art_rect          = $ArtRect                  if has_node("ArtRect")                  else null
	frame_texture     = $FrameTexture             if has_node("FrameTexture")             else null
	cost_badge        = $CostBadge as CostBadge  if has_node("CostBadge")               else null
	mana_badge        = $ManaBadge as CostBadge  if has_node("ManaBadge")               else null
	cost_label        = $CostBadge/CostLabel     if has_node("CostBadge/CostLabel")     else null
	mana_label        = $ManaBadge/ManaLabel     if has_node("ManaBadge/ManaLabel")     else null
	name_label        = $NameLabel                if has_node("NameLabel")                else null
	desc_label        = $DescLabel as RichTextLabel if has_node("DescLabel")               else null
	stats_row         = $StatsRow                 if has_node("StatsRow")                 else null
	atk_label         = $StatsRow/AtkLabel        if has_node("StatsRow/AtkLabel")        else null
	hp_label          = $StatsRow/HpLabel         if has_node("StatsRow/HpLabel")         else null
	shield_label      = $StatsRow/ShieldLabel     if has_node("StatsRow/ShieldLabel")     else null
	race_label        = $RaceLabel                if has_node("RaceLabel")                else null
	frame_cost_label  = $FrameCostLabel           if has_node("FrameCostLabel")           else null
	frame_mana_label  = $FrameManaLabel           if has_node("FrameManaLabel")           else null
	frame_atk_label   = $FrameAtkLabel            if has_node("FrameAtkLabel")            else null
	frame_hp_label    = $FrameHpLabel             if has_node("FrameHpLabel")             else null

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(data: CardData) -> void:
	card_data = data

	var faction: String = data.faction if data.faction != "" else "neutral"

	# -- Frame texture: minion cards use a faction-specific minion frame --
	var is_minion := data.card_type == Enums.CardType.MINION
	if is_minion:
		var md := data as MinionCardData
		_apply_minion_frame(faction)
		if race_label:
			race_label.text    = _minion_type_string(md.minion_type)
			race_label.visible = true
	else:
		_using_minion_frame = false
		_apply_frame(faction, data.card_type)
		if race_label: race_label.visible = false

	# Apply layout for the resolved style
	_apply_layout("minion_framed" if _using_minion_frame else "default")

	if name_label:
		name_label.text = data.card_name
		_fit_name_font_size(data.card_name)
		var is_champion := data is MinionCardData and Enums.Keyword.CHAMPION in (data as MinionCardData).keywords
		name_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2, 1.0) if is_champion else Color(1.0, 1.0, 1.0, 1.0))
	if desc_label:
		var kw_str := ""
		if data is MinionCardData:
			kw_str = _keywords_string((data as MinionCardData).keywords)
		desc_label.text = _build_desc_bbcode(kw_str, data.description)

	if is_minion:
		var md := data as MinionCardData
		if _using_minion_frame:
			# Frame has embedded badge + stat panels — use overlay labels only
			if stats_row:  stats_row.visible  = false
			if cost_badge: cost_badge.visible  = false
			if mana_badge: mana_badge.visible  = false
			if frame_atk_label:
				frame_atk_label.visible = true
				frame_atk_label.text    = str(md.atk)
			if frame_hp_label:
				frame_hp_label.visible = true
				frame_hp_label.text    = str(md.health)
			if frame_cost_label:
				frame_cost_label.visible = true
				frame_cost_label.text    = str(md.essence_cost)
			if frame_mana_label:
				if md.mana_cost > 0:
					frame_mana_label.visible = true
					frame_mana_label.text    = str(md.mana_cost)
				else:
					frame_mana_label.visible = false
		else:
			# Fallback: drawn badge + StatsRow
			if stats_row: stats_row.visible = true
			_setup_cost_badge(data)
			if atk_label:  atk_label.text  = str(md.atk)
			if hp_label:   hp_label.text   = str(md.health)
			if shield_label:
				if md.shield_max > 0:
					shield_label.text    = "S:%d" % md.shield_max
					shield_label.visible = true
				else:
					shield_label.visible = false
	else:
		if stats_row: stats_row.visible = false
		_setup_cost_badge(data)

	if art_rect and data.art_path != "":
		var tex := load(data.art_path) as Texture2D
		if tex:
			art_rect.texture = tex

	_refresh_playable_state()

# ---------------------------------------------------------------------------
# Layout — applies anchor values from _LAYOUT to every node
# ---------------------------------------------------------------------------

func _apply_layout(style: String) -> void:
	var lay: Dictionary = _LAYOUT.get(style, _LAYOUT["default"])
	_set_anchors(art_rect,         lay.get("art"))
	_set_anchors(name_label,       lay.get("name"))
	_set_anchors(race_label,       lay.get("race"))
	_set_anchors(desc_label,       lay.get("desc"))
	_set_anchors(stats_row,        lay.get("stats"))
	_set_anchors(frame_cost_label, lay.get("frame_cost"))
	_set_anchors(frame_mana_label, lay.get("frame_mana"))
	_set_anchors(frame_atk_label,  lay.get("frame_atk"))
	_set_anchors(frame_hp_label,   lay.get("frame_hp"))
	_set_anchors(cost_badge,       lay.get("cost_badge"))
	_set_anchors(mana_badge,       lay.get("mana_badge"))

func _set_anchors(node: Control, a: Variant) -> void:
	if node == null or a == null:
		return
	node.anchor_left   = a[0]
	node.anchor_top    = a[1]
	node.anchor_right  = a[2]
	node.anchor_bottom = a[3]

# ---------------------------------------------------------------------------
# Frame helper — loads faction frame texture or falls back to Background panel
# ---------------------------------------------------------------------------

func _apply_frame(faction: String, card_type: Enums.CardType) -> void:
	if frame_texture == null:
		return
	var faction_frames: Dictionary = _FRAME_PATH.get(faction, {})
	var path: String = faction_frames.get(card_type, "")

	if path != "" and ResourceLoader.exists(path):
		frame_texture.texture = load(path)
		frame_texture.visible = true
		if background:
			background.visible = false
	else:
		frame_texture.texture = null
		frame_texture.visible = false
		if background:
			background.visible = true
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.07, 0.07, 0.14, 1)
			style.border_width_left   = 2
			style.border_width_top    = 2
			style.border_width_right  = 2
			style.border_width_bottom = 2
			style.border_color = _type_border_color(card_type)
			style.corner_radius_top_left    = 6
			style.corner_radius_top_right   = 6
			style.corner_radius_bottom_right = 6
			style.corner_radius_bottom_left = 6
			background.add_theme_stylebox_override("panel", style)

## Loads the faction's shared minion frame.
## Falls back to no frame (shows Background + art) if none defined.
func _apply_minion_frame(faction: String) -> void:
	var path: String = _MINION_FRAME_PATH.get(faction, "")
	if path != "" and ResourceLoader.exists(path):
		_using_minion_frame = true
		if frame_texture:
			frame_texture.texture = load(path)
			frame_texture.visible = true
		if background:
			background.visible = false
	else:
		_using_minion_frame = false
		if frame_texture:
			frame_texture.texture = null
			frame_texture.visible = false
		if background:
			background.visible = true
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.07, 0.07, 0.14, 1)
			style.border_width_left   = 2
			style.border_width_top    = 2
			style.border_width_right  = 2
			style.border_width_bottom = 2
			style.border_color = _type_border_color(Enums.CardType.MINION)
			style.corner_radius_top_left    = 6
			style.corner_radius_top_right   = 6
			style.corner_radius_bottom_right = 6
			style.corner_radius_bottom_left = 6
			background.add_theme_stylebox_override("panel", style)

# ---------------------------------------------------------------------------
# Talent overlay — call after setup() during combat to reflect unlocked talents
# ---------------------------------------------------------------------------

## Updates displayed stats, cost, and description based on currently unlocked talents.
## Only meaningful during combat; DeckBuilder previews call setup() before talents exist.
func apply_talent_overlay() -> void:
	if card_data == null or not (card_data is MinionCardData):
		return
	if card_data.id != "void_imp":
		return

	var md := card_data as MinionCardData
	var display_atk    := md.atk
	var display_hp     := md.health
	var display_cost_e := md.essence_cost
	var display_cost_m := md.mana_cost
	var talent_notes: Array[String] = []

	# Hero passive "void_imp_boost" is always-on during combat — show boosted stats
	if HeroDatabase.has_passive(GameManager.current_hero, "void_imp_boost"):
		display_atk += 100
		display_hp  += 100
		var hero := HeroDatabase.get_hero(GameManager.current_hero)
		talent_notes.append("%s: +100/+100 on summon (always)" % (hero.hero_name if hero else "Hero"))

	var unlocked: Array[String] = GameManager.unlocked_talents

	if "imp_empowerment" in unlocked:
		display_atk += 50
		talent_notes.append("Imp Empowerment: +50 ATK on summon")
	if "lord_of_imps" in unlocked:
		display_atk += 100
		display_hp  += 100
		talent_notes.append("Lord of Imps: +100/+100 on summon")
	if "piercing_void" in unlocked:
		display_cost_m += 1
		talent_notes.append("Piercing Void: 200 Void Bolt then +1 Void Mark on play")

	if talent_notes.is_empty():
		return

	if atk_label:       atk_label.text       = str(display_atk)
	if hp_label:        hp_label.text        = str(display_hp)
	if frame_atk_label: frame_atk_label.text = str(display_atk)
	if frame_hp_label:  frame_hp_label.text  = str(display_hp)
	# Re-run badge setup with updated costs so the badge and fallback stay in sync
	var overlay_data := card_data as MinionCardData
	overlay_data = overlay_data.duplicate() as MinionCardData
	overlay_data.essence_cost = display_cost_e
	overlay_data.mana_cost    = display_cost_m
	_setup_cost_badge(overlay_data)
	if desc_label:
		var kw_str := _keywords_string(md.keywords)
		var full_desc := md.description + "\n─\n" + "\n".join(talent_notes)
		desc_label.text = _build_desc_bbcode(kw_str, full_desc)

# ---------------------------------------------------------------------------
# Playability
# ---------------------------------------------------------------------------

func set_playable(playable: bool) -> void:
	is_playable = playable
	_refresh_playable_state()

func _refresh_playable_state() -> void:
	modulate = Color(1, 1, 1, 1) if is_playable else Color(0.5, 0.5, 0.5, 1)

# ---------------------------------------------------------------------------
# Selection — uses scale so HBoxContainer layout is never broken
# ---------------------------------------------------------------------------

func select() -> void:
	is_selected = true
	_update_pivot()
	scale = SCALE_SELECTED

func deselect() -> void:
	is_selected = false
	scale = SCALE_NORMAL

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_mouse_entered() -> void:
	_update_pivot()
	if not is_selected:
		scale = SCALE_HOVER
	card_hovered.emit(self)

func _on_mouse_exited() -> void:
	if not is_selected:
		scale = SCALE_NORMAL
	card_unhovered.emit(self)

func _update_pivot() -> void:
	# Use custom_minimum_size as fallback if the layout hasn't run yet
	var s := size if size != Vector2.ZERO else custom_minimum_size
	pivot_offset = s / 2.0

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(self)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _setup_cost_badge(data: CardData) -> void:
	if data is MinionCardData:
		var md := data as MinionCardData
		_apply_badge(cost_badge, cost_label, "essence", md.essence_cost)
		if mana_badge:
			if md.mana_cost > 0:
				_apply_badge(mana_badge, mana_label, "mana", md.mana_cost)
				mana_badge.visible = true
			else:
				mana_badge.visible = false
	else:
		_apply_badge(cost_badge, cost_label, "mana", data.cost)
		if mana_badge: mana_badge.visible = false

# Draws a circular gem badge via CostBadge._draw() — no PNG needed.
func _apply_badge(badge: CostBadge, number_label: Label, prefix: String, value: int) -> void:
	if badge == null:
		return
	if prefix == "essence":
		badge.rim_color = Color(0.70, 0.28, 1.00, 1.00)
		badge.bg_color  = Color(0.18, 0.06, 0.32, 0.95)
	else:  # mana
		badge.rim_color = Color(0.25, 0.60, 1.00, 1.00)
		badge.bg_color  = Color(0.05, 0.10, 0.35, 0.95)
	badge.queue_redraw()
	if number_label:
		number_label.text = str(value)

func _fit_name_font_size(card_name: String) -> void:
	var size: int
	var len := card_name.length()
	if len <= 10:   size = 25
	elif len <= 14: size = 22
	elif len <= 18: size = 20
	else:           size = 18
	name_label.add_theme_font_size_override("font_size", size)

## Builds BBCode for the desc box: keywords on line 1 (centered, gold, bold),
## then description below (normal). If no keywords, just plain description.
func _build_desc_bbcode(kw_str: String, description: String) -> String:
	if kw_str == "":
		return description
	return "[center][color=#ffe066][b]" + kw_str + "[/b][/color][/center]\n" + description

func _keywords_string(keywords: Array) -> String:
	if keywords.is_empty():
		return ""
	var parts: Array[String] = []
	for kw in keywords:
		match kw:
			Enums.Keyword.TAUNT:          parts.append("Taunt")
			Enums.Keyword.RUSH:           parts.append("Rush")
			Enums.Keyword.LIFEDRAIN:      parts.append("Lifedrain")
			Enums.Keyword.SHIELD_REGEN_1: parts.append("Shield Regen")
			Enums.Keyword.SHIELD_REGEN_2: parts.append("Shield Regen+")
			Enums.Keyword.CHAMPION:       parts.append("Champion")
	return ", ".join(parts)

func _minion_type_string(minion_type: Enums.MinionType) -> String:
	match minion_type:
		Enums.MinionType.DEMON:     return "Demon"
		Enums.MinionType.SPIRIT:    return "Spirit"
		Enums.MinionType.BEAST:     return "Beast"
		Enums.MinionType.UNDEAD:    return "Undead"
		Enums.MinionType.HUMAN:     return "Human"
		Enums.MinionType.CONSTRUCT: return "Construct"
		Enums.MinionType.GIANT:     return "Giant"
	return ""

func _type_string(card_type: Enums.CardType) -> String:
	match card_type:
		Enums.CardType.MINION:      return "Minion"
		Enums.CardType.SPELL:       return "Spell"
		Enums.CardType.TRAP:        return "Trap"
		Enums.CardType.ENVIRONMENT: return "Environment"
	return ""

func _type_border_color(card_type: Enums.CardType) -> Color:
	match card_type:
		Enums.CardType.MINION:      return Color(0.55, 0.15, 0.85, 1)  # purple
		Enums.CardType.SPELL:       return Color(0.15, 0.45, 0.85, 1)  # blue
		Enums.CardType.TRAP:        return Color(0.85, 0.45, 0.10, 1)  # orange
		Enums.CardType.ENVIRONMENT: return Color(0.15, 0.75, 0.35, 1)  # green
	return Color(0.5, 0.5, 0.5, 1)
