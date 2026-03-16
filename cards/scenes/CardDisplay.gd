## CardDisplay.gd
## Visual representation of a single card.
## Call setup(card_data) to populate all visual elements.
## Designed at 200×280 — scale the root node to resize uniformly.
class_name CardDisplay
extends Control

# ---------------------------------------------------------------------------
# Frame textures — path keyed by [faction][card_type]
# Add entries here as new faction frames are produced.
# ---------------------------------------------------------------------------
const _FRAME_PATH: Dictionary = {
	"abyss_order": {
		Enums.CardType.MINION:      "res://assets/art/frames/abyss_order/frame_minion.png",
		Enums.CardType.SPELL:       "res://assets/art/frames/abyss_order/frame_spell.png",
		Enums.CardType.TRAP:        "res://assets/art/frames/abyss_order/frame_trap.png",
		Enums.CardType.ENVIRONMENT: "res://assets/art/frames/abyss_order/frame_environment.png",
	},
}

# ---------------------------------------------------------------------------
# Fallback faction frame colours (used when no frame texture is available)
# ---------------------------------------------------------------------------
const _FACTION_COLOR: Dictionary = {
	"abyss_order": Color(0.28, 0.12, 0.48, 1.0),
	"neutral":     Color(0.22, 0.22, 0.30, 1.0),
}
const _FACTION_BORDER: Dictionary = {
	"abyss_order": Color(0.65, 0.30, 1.00, 1.0),
	"neutral":     Color(0.55, 0.55, 0.70, 1.0),
}

# Card-type accent colours for the name banner (fallback only)
const _TYPE_COLOR: Dictionary = {
	Enums.CardType.MINION:      Color(0.18, 0.14, 0.32, 0.92),
	Enums.CardType.SPELL:       Color(0.10, 0.18, 0.38, 0.92),
	Enums.CardType.TRAP:        Color(0.30, 0.14, 0.14, 0.92),
	Enums.CardType.ENVIRONMENT: Color(0.10, 0.26, 0.18, 0.92),
}

# Rarity gem colours
const _RARITY_COLOR: Dictionary = {
	"common":    Color(0.65, 0.65, 0.70, 1.0),
	"rare":      Color(0.25, 0.55, 1.00, 1.0),
	"epic":      Color(0.65, 0.20, 0.90, 1.0),
	"legendary": Color(1.00, 0.75, 0.10, 1.0),
}

# Keyword display names
const _KEYWORD_NAME: Dictionary = {
	Enums.Keyword.TAUNT:          "Taunt",
	Enums.Keyword.RUSH:           "Rush",
	Enums.Keyword.LIFEDRAIN:      "Lifedrain",
	Enums.Keyword.SHIELD_REGEN_1: "Barrier I",
	Enums.Keyword.SHIELD_REGEN_2: "Barrier II",
}

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var _frame_border:    ColorRect     = $FrameBorder
@onready var _frame_bg:        ColorRect     = $FrameBg
@onready var _art_rect:        TextureRect   = $ArtArea
@onready var _art_placeholder: Label         = $ArtArea/ArtPlaceholder
@onready var _frame_texture:   TextureRect   = $FrameTexture
@onready var _name_bg:         ColorRect     = $NameBanner
@onready var _name_label:      Label         = $NameBanner/NameLabel
@onready var _type_label:      Label         = $TypeLabel
@onready var _faction_label:   Label         = $FactionLabel
@onready var _stats_bar:       HBoxContainer = $StatsBar
@onready var _atk_label:       Label         = $StatsBar/AtkLabel
@onready var _hp_label:        Label         = $StatsBar/HpLabel
@onready var _shield_label:    Label         = $StatsBar/ShieldLabel
@onready var _desc_bg:         ColorRect     = $DescBox
@onready var _desc_label:      RichTextLabel = $DescBox/DescLabel
@onready var _cost_badge:      TextureRect   = $CostBadge
@onready var _cost_number:     Label         = $CostBadge/CostNumber
@onready var _mana_badge:      TextureRect   = $ManaBadge
@onready var _mana_number:     Label         = $ManaBadge/ManaNumber
@onready var _rarity_gem:      ColorRect     = $RarityGem

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(card: CardData) -> void:
	if card == null:
		return

	var faction: String = card.faction if card.faction != "" else "neutral"

	# -- Frame texture or fallback ColorRects --
	_apply_frame(faction, card.card_type)

	# -- Card art --
	if card.art_path != "" and ResourceLoader.exists(card.art_path):
		_art_rect.texture = load(card.art_path)
		_art_placeholder.visible = false
	else:
		_art_rect.texture = null
		_art_placeholder.visible = true
		_art_placeholder.text = card.card_name

	# -- Name --
	_name_label.text = card.card_name

	# -- Type + faction row --
	var type_str := _type_name(card.card_type)
	if card is MinionCardData:
		type_str += "  ·  " + _minion_type_name(card.minion_type)
	_type_label.text = type_str

	var fac_symbol := "⬡" if faction == "abyss_order" else "◇"
	var fac_display := fac_symbol + " " + faction.replace("_", " ").capitalize()
	_faction_label.text = fac_display

	# -- Cost badge --
	_setup_cost_badge(card)

	# -- Stats (minions only) --
	if card is MinionCardData:
		_stats_bar.visible = true
		_atk_label.text    = "⚔ " + str(card.atk / 100) + "." + str((card.atk % 100) / 10)
		_hp_label.text     = "♥ " + str(card.health / 100) + "." + str((card.health % 100) / 10)
		if card.shield_max > 0:
			_shield_label.text    = "🛡 " + str(card.shield_max / 100)
			_shield_label.visible = true
		else:
			_shield_label.visible = false
	else:
		_stats_bar.visible = false

	# -- Description / keywords --
	var desc := ""
	if card is MinionCardData and card.keywords.size() > 0:
		var kw_parts: Array[String] = []
		for kw in card.keywords:
			kw_parts.append("[b]" + _KEYWORD_NAME.get(kw, "?") + "[/b]")
		desc = ", ".join(kw_parts) + "\n"
	desc += card.description
	_desc_label.text = desc

	# -- Rarity gem --
	var rarity: String = ""
	if card.can_unlock:
		rarity = GameManager._SUPPORT_CARD_RARITIES.get(card.id, "common")
	_rarity_gem.color = _RARITY_COLOR.get(rarity, Color(0.4, 0.4, 0.4, 1.0))

# ---------------------------------------------------------------------------
# Frame helper — loads faction frame texture or falls back to ColorRects
# ---------------------------------------------------------------------------

func _apply_frame(faction: String, card_type: Enums.CardType) -> void:
	var faction_frames: Dictionary = _FRAME_PATH.get(faction, {})
	var path: String = faction_frames.get(card_type, "")

	if path != "" and ResourceLoader.exists(path):
		# Custom frame PNG — hide fallback ColorRects, clear banner/desc backgrounds
		_frame_texture.texture = load(path)
		_frame_texture.visible = true
		_frame_border.visible  = false
		_frame_bg.visible      = false
		_name_bg.color         = Color(0, 0, 0, 0)
		_desc_bg.color         = Color(0, 0, 0, 0)
	else:
		# No frame art — use faction colour rects as fallback
		_frame_texture.texture = null
		_frame_texture.visible = false
		_frame_border.visible  = true
		_frame_bg.visible      = true
		_frame_border.color    = _FACTION_BORDER.get(faction, _FACTION_BORDER["neutral"])
		_frame_bg.color        = _FACTION_COLOR.get(faction, _FACTION_COLOR["neutral"])
		_name_bg.color         = _TYPE_COLOR.get(card_type, _TYPE_COLOR[Enums.CardType.MINION])
		_desc_bg.color         = Color(0.08, 0.06, 0.14, 0.90)

# ---------------------------------------------------------------------------
# Cost badge helper
# ---------------------------------------------------------------------------

func _setup_cost_badge(card: CardData) -> void:
	if card is MinionCardData:
		var md := card as MinionCardData
		_apply_badge(_cost_badge, _cost_number, "essence", md.essence_cost)
		if md.mana_cost > 0:
			_apply_badge(_mana_badge, _mana_number, "mana", md.mana_cost)
			_mana_badge.visible = true
		else:
			_mana_badge.visible = false
	else:
		_apply_badge(_cost_badge, _cost_number, "mana", card.cost)
		_mana_badge.visible = false

func _apply_badge(badge: TextureRect, number_label: Label, prefix: String, value: int) -> void:
	var path := "res://assets/art/badges/%s_badge.png" % prefix
	if ResourceLoader.exists(path):
		badge.texture = load(path)
	else:
		badge.texture = null
	number_label.text = str(value)

# ---------------------------------------------------------------------------
# Label helpers
# ---------------------------------------------------------------------------

func _type_name(t: Enums.CardType) -> String:
	match t:
		Enums.CardType.MINION:      return "Minion"
		Enums.CardType.SPELL:       return "Spell"
		Enums.CardType.TRAP:        return "Trap"
		Enums.CardType.ENVIRONMENT: return "Environment"
	return "?"

func _minion_type_name(t: Enums.MinionType) -> String:
	match t:
		Enums.MinionType.DEMON:     return "Demon"
		Enums.MinionType.SPIRIT:    return "Spirit"
		Enums.MinionType.BEAST:     return "Beast"
		Enums.MinionType.UNDEAD:    return "Undead"
		Enums.MinionType.HUMAN:     return "Human"
		Enums.MinionType.CONSTRUCT: return "Construct"
		Enums.MinionType.GIANT:     return "Giant"
	return "?"
