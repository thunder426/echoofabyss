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
# ---------------------------------------------------------------------------
# Frame config — ALL per-frame settings live here (path, layout, fonts).
# Add a new entry here to define a fully independent style for any frame PNG.
# minion_frame: true → uses embedded cost/atk/hp overlay labels instead of badges.
# ---------------------------------------------------------------------------
# fmt: off

## Maps faction → card_type → frame style key in _FRAME_CONFIG.
const _FACTION_FRAME: Dictionary = {
	"abyss_order": {
		Enums.CardType.MINION:      "abyss_minion",
		Enums.CardType.SPELL:       "abyss_spell",
		Enums.CardType.TRAP:        "abyss_trap",
		Enums.CardType.ENVIRONMENT: "abyss_env",
	},
	"neutral": {
		Enums.CardType.MINION:      "neutral_essence_minion",
		Enums.CardType.SPELL:       "neutral_spell",
		Enums.CardType.TRAP:        "neutral_trap",
		Enums.CardType.ENVIRONMENT: "neutral_env",
	},
}

## Tooltip layout config per faction. Keyed by card_data.faction; falls back to "default".
const _FACTION_TOOLTIP_CFG: Dictionary = {
	"abyss_order": {
		"anchor":              Vector2(0.85, 0.25),
		"w_scale":             0.6,  "h_scale":    0.6,
		"title_font":          15,   "body_font":  11,
		"title_rect":          [0.15, 0.18, 0.85, 0.30],
		"body_rect":           [0.15, 0.30, 0.85, 0.96],
		"desc_keyword_color":  Color(0.75, 0.50, 1.00, 1.0),  # purple — on dark card box
		"tooltip_keyword_color": Color(0.75, 0.50, 1.00, 1.0),  # purple — on dark tooltip panel
		"race_color":          Color(0.75, 0.50, 1.00, 1.0),  # purple
		"name_color":          Color(1.00, 1.00, 1.00, 1.0),  # white
		"text_color":          Color(1.00, 1.00, 1.00, 1.0),  # white
	},
	"neutral": {
		"anchor":              Vector2(0.85, 0.25),
		"w_scale":             0.6,  "h_scale":    0.6,
		"title_font":          15,   "body_font":  11,
		"title_rect":          [0.15, 0.165, 0.85, 0.30],
		"body_rect":           [0.16, 0.26, 0.90, 0.96],
		"desc_keyword_color":  Color(0.48, 0.29, 0.04, 1.0),  # dark amber-brown — on light parchment
		"tooltip_keyword_color": Color(1.00, 0.82, 0.30, 1.0),  # bright gold — on dark brown tooltip
		"race_color":          Color(1.00, 1.00, 1.00, 1.0),  # white
		"name_color":          Color(1.00, 1.00, 1.00, 1.0),  # white
		"name_outline_size":   3,
		"name_outline_color":  Color(0.05, 0.03, 0.01, 1.0),  # near-black
		"text_color":          Color(0.08, 0.05, 0.02, 1.0),  # near-black
	},
	"default": {
		"anchor":              Vector2(1.0, 0.0),
		"w_scale":             0.62, "h_scale":    1.0,
		"title_font":          15,   "body_font":  11,
		"title_rect":          [0.05, 0.03, 0.95, 0.22],
		"body_rect":           [0.05, 0.24, 0.95, 0.97],
		"desc_keyword_color":  Color(0.75, 0.50, 1.00, 1.0),  # purple
		"tooltip_keyword_color": Color(0.75, 0.50, 1.00, 1.0),  # purple
		"race_color":          Color(0.75, 0.50, 1.00, 1.0),  # purple
		"name_color":          Color(1.00, 1.00, 1.00, 1.0),  # white
		"text_color":          Color(1.00, 1.00, 1.00, 1.0),  # white
	},
}

## Per-frame style config. Each entry is fully self-contained.
const _FRAME_CONFIG: Dictionary = {
	# ── Abyss Order dual-cost minion frame (essence + mana) ────────────────
	"abyss_dual_minion": {
		"path":         "res://assets/art/frames/abyss_order/abyss_dual_minion.png",
		"minion_frame": true,
		"layout": {
			"art":     [0.08, 0.14, 0.92, 0.78],
			"name":    [0.15, 0.09, 0.93, 0.14],
			"race":    [0.05, 0.65, 0.95, 0.72],
			"desc":    [0.17, 0.72, 0.85, 0.85],
			"essence": [0.01, 0.05, 0.28, 0.18],
			"mana":    [0.75, 0.05, 0.99, 0.18],
			"atk":     [0.08, 0.87, 0.42, 0.94],
			"hp":      [0.58, 0.87, 0.80, 0.94],
		},
		"fonts": {
			"desc_normal": 14, "desc_bold": 15,
			"shield": 11, "race": 15,
			"essence": 28, "mana": 28, "atk": 20, "hp": 20,
			"name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]],
		},
	},
	# ── Abyss Order dual-cost minion frame (hand size) ──────────────────────
	"abyss_dual_minion_small": {
		"path":         "res://assets/art/frames/abyss_order/abyss_dual_minion.png",
		"minion_frame": true,
		"layout": {
			"art":     [0.08, 0.14, 0.92, 0.78],
			"name":    [0.15, 0.12, 0.93, 0.15],
			"race":    [0.05, 0.72, 0.95, 0.72],
			"desc":    [0.16, 0.76, 0.85, 0.85],
			"essence": [0.01, 0.07, 0.28, 0.19],
			"mana":    [0.26, 0.01, 0.54, 0.19],
			"atk":     [0.10, 0.89, 0.42, 0.93],
			"hp":      [0.58, 0.89, 0.81, 0.93],
		},
		"fonts": {
			"desc_normal": 14, "desc_bold": 15,
			"shield": 11, "race": 15,
			"essence": 28, "mana": 18, "atk": 20, "hp": 20,
			"name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]],
		},
	},
	# ── Abyss Order minion frame (hand size) — less glowy variant ──────────
	"abyss_minion_small": {
		"path":         "res://assets/art/frames/abyss_order/abyss_minion_small.png",
		"minion_frame": true,
		"layout": {
			"art":     [0.08, 0.14, 0.92, 0.78],
			"name":    [0.15, 0.12, 0.93, 0.15],
			"race":    [0.05, 0.72, 0.95, 0.72],
			"desc":    [0.16, 0.76, 0.85, 0.85],
			"essence": [0.01, 0.07, 0.28, 0.19],
			"mana":    [0.26, 0.01, 0.54, 0.19],
			"atk":     [0.10, 0.89, 0.42, 0.93],
			"hp":      [0.58, 0.89, 0.81, 0.93],
		},
		"fonts": {
			"desc_normal": 14, "desc_bold": 15,
			"shield": 11, "race": 15,
			"essence": 28, "mana": 18, "atk": 20, "hp": 20,
			"name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]],
		},
	},
	# ── Abyss Order minion frame — embedded stat panels, race tag bar ──────
	"abyss_minion": {
		"path":         "res://assets/art/frames/abyss_order/abyss_minion.png",
		"minion_frame": true,
		"layout": {
			"art":     [0.08, 0.11, 0.92, 0.78],
			"name":    [0.15, 0.06, 0.93, 0.11],
			"race":    [0.05, 0.70, 0.95, 0.75],
			"desc":    [0.16, 0.76, 0.85, 0.87],
			"essence": [0.01, 0.06, 0.28, 0.11],
			"mana":    [0.26, 0.01, 0.54, 0.19],
			"atk":     [0.09, 0.90, 0.42, 0.95],
			"hp":      [0.56, 0.90, 0.81, 0.95],
		},
		"fonts": {
			"desc_normal": 14, "desc_bold": 15,
			"shield": 11, "race": 15,
			"essence": 28, "mana": 18, "atk": 20, "hp": 20,
			"name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]],
		},
	},
	# ── Abyss Order spell frame ─────────────────────────────────────────────
	"abyss_spell": {
		"path":    "res://assets/art/frames/abyss_order/abyss_spell.png",
		"layout": {
			"art":  [0.05, 0.14, 0.95, 0.70],
			"name": [0.15, 0.085, 0.93, 0.12],
			"desc": [0.16, 0.73, 0.85, 0.85],
			"mana": [0.05, 0.08, 0.20, 0.12],
		},
		"fonts": { "desc_normal": 14, "desc_bold": 15, "mana": 28, "name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]] },
	},
	# ── Abyss Order trap frame ──────────────────────────────────────────────
	"abyss_trap": {
		"path":    "res://assets/art/frames/abyss_order/abyss_trap.png",
		"layout": {
			"art":  [0.05, 0.06, 0.95, 0.75],
			"name": [0.15, 0.06, 0.93, 0.11],
			"desc": [0.16, 0.72, 0.85, 0.90],
			"mana": [0.06, 0.06, 0.20, 0.10],
		},
		"fonts": { "desc_normal": 14, "desc_bold": 15, "mana": 28, "name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]] },
	},
	# ── Abyss Order environment frame ───────────────────────────────────────
	"abyss_env": {
		"path":    "res://assets/art/frames/abyss_order/abyss_environment.png",
		"layout": {
			"art":  [0.08, 0.10, 0.92, 0.72],
			"name": [0.20, 0.05, 0.97, 0.10],
			"desc": [0.16, 0.71, 0.88, 0.90],
			"mana": [0.03, 0.04, 0.25, 0.10],
		},
		"fonts": { "desc_normal": 14, "desc_bold": 15, "mana": 28, "name_tiers": [[10, 22], [14, 20], [18, 18], [999, 16]] },
	},
	# ── Neutral essence-only minion ─────────────────────────────────────────
	"neutral_essence_minion": {
		"path":         "res://assets/art/frames/neutral/neutral_essence_minion.png",
		"minion_frame": true,
		"layout": {
			"art":     [0.08, 0.14, 0.92, 0.63],
			"name":    [0.15, 0.03, 0.85, 0.10],
			"race":    [0.05, 0.10, 0.95, 0.15],
			"desc":    [0.16, 0.67, 0.85, 0.90],
			"essence": [0.01, 0.05, 0.24, 0.10],
			"atk":     [0.08, 0.84, 0.42, 0.91],
			"hp":      [0.58, 0.84, 0.92, 0.91],
		},
		"fonts": {
			"desc_normal": 14, "desc_bold": 15,
			"shield": 11, "race": 15,
			"essence": 28, "atk": 20, "hp": 20,
			"name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]],
		},
	},
	# ── Neutral dual-cost minion (essence + mana) — shield at bottom-centre ─
	"neutral_essence_mana_minion": {
		"path":         "res://assets/art/frames/neutral/neutral_essence_mana_minion.png",
		"minion_frame": true,
		"has_frame_shield": true,
		"layout": {
			"art":     [0.08, 0.12, 0.92, 0.65],
			"name":    [0.15, 0.03, 0.85, 0.10],
			"race":    [0.05, 0.10, 0.95, 0.15],
			"desc":    [0.16, 0.67, 0.85, 0.90],
			"essence": [0.01, 0.05, 0.24, 0.10],
			"mana":    [0.76, 0.05, 0.99, 0.10],
			"atk":     [0.08, 0.85, 0.42, 0.91],
			"shield":  [0.42, 0.85, 0.73, 0.91],
			"hp":      [0.58, 0.85, 0.92, 0.91],
		},
		"fonts": {
			"desc_normal": 14, "desc_bold": 15,
			"shield": 18, "race": 15,
			"essence": 28, "mana": 28, "atk": 20, "hp": 20,
			"name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]],
		},
	},
	# ── Neutral spell ────────────────────────────────────────────────────────
	"neutral_spell": {
		"path":    "res://assets/art/frames/neutral/neutral_spell.png",
		"layout": {
			"art":  [0.05, 0.12, 0.95, 0.68],
			"name": [0.15, 0.05, 0.85, 0.10],
			"desc": [0.16, 0.69, 0.88, 0.85],
			"mana": [0.01, 0.06, 0.24, 0.11],
		},
		"fonts": { "desc_normal": 14, "desc_bold": 15, "mana": 28, "name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]] },
	},
	# ── Neutral trap ─────────────────────────────────────────────────────────
	"neutral_trap": {
		"path":    "res://assets/art/frames/neutral/neutral_trap.png",
		"layout": {
			"art":  [0.05, 0.10, 0.95, 0.70],
			"name": [0.15, 0.04, 0.85, 0.09],
			"desc": [0.16, 0.69, 0.88, 0.85],
			"mana": [0.01, 0.05, 0.22, 0.10],
		},
		"fonts": { "desc_normal": 14, "desc_bold": 15, "mana": 28, "name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]] },
	},
	# ── Neutral environment ──────────────────────────────────────────────────
	"neutral_env": {
		"path":    "res://assets/art/frames/neutral/neutral_environment.png",
		"layout": {
			"art":  [0.05, 0.14, 0.95, 0.70],
			"name": [0.15, 0.05, 0.85, 0.10],
			"desc": [0.16, 0.69, 0.88, 0.85],
			"mana": [0.01, 0.06, 0.24, 0.11],
		},
		"fonts": { "desc_normal": 14, "desc_bold": 15, "mana": 28, "name_tiers": [[10, 22], [14, 20], [18, 18], [999, 16]] },
	},
	# ── Default — no frame PNG, uses drawn badge + Background panel ─────────
	"default": {
		"path":    "",
		"layout": {
			"art":     [0.08, 0.14, 0.92, 0.62],
			"name":    [0.20, 0.03, 0.97, 0.16],
			"race":    [0.05, 0.57, 0.95, 0.64],
			"desc":    [0.06, 0.62, 0.94, 0.88],
			"stats":   [0.06, 0.88, 0.94, 0.97],
			"essence": [0.01, 0.01, 0.25, 0.19],
			"mana":    [0.23, 0.01, 0.47, 0.19],
		},
		"fonts": {
			"desc_normal": 14, "desc_bold": 15,
			"shield": 11, "race": 15,
			"essence": 25, "mana": 15, "atk": 11, "hp": 11,
			"name_tiers": [[10, 25], [14, 22], [18, 20], [999, 18]],
		},
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
var video_art:     VideoStreamPlayer
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
var frame_cost_label:   RichTextLabel
var frame_mana_label:   Label
var frame_atk_label:    Label
var frame_hp_label:     Label
var frame_shield_label: Label

## Active frame style key — resolved from _FACTION_FRAME during setup().
var _frame_style: String = "default"
## Hex color string for keyword highlights in the description box — faction-specific.
var _kw_color_hex: String = "c080ff"

# ---------------------------------------------------------------------------
# Card state
# ---------------------------------------------------------------------------

var card_data: CardData = null
## Per-copy instance wrapper — set by HandDisplay after setup(). Null for non-hand visuals.
var card_inst: CardInstance = null
var is_selected: bool = false
var is_playable: bool = true
var condition_active: bool = false
var _glow_pulse: float = 0.0   # 0..1, animated by tween on hover
var _glow_tween: Tween = null
var _glow_overlay: Panel = null

# Scale constants — hover/select uses scale so HBoxContainer layout is unaffected
const SCALE_NORMAL   := Vector2(1.0, 1.0)
const SCALE_HOVER    := Vector2(1.12, 1.12)
const SCALE_SELECTED := Vector2(1.18, 1.18)

# ---------------------------------------------------------------------------
# Size modes — card dimensions and font_scale per display context.
# Call apply_size_mode("hand") etc. before setup() on any CardVisual instance.
# font_scale multiplies every font size from the active frame config's "fonts" dict,
# including "name_tiers". Tooltip proportions are set per frame style above.
# ---------------------------------------------------------------------------
# fmt: off

const _SIZE_CONFIG: Dictionary = {
	## Default full-size card (200×300) — baseline font sizes
	"default":        { "card_size": Vector2(200, 300), "font_scale": 0.42 },
	## Hand cards in combat — smaller so more fit in hand
	"hand":           { "card_size": Vector2(160, 240), "font_scale": 0.33 },
	## Hover preview shown in bottom-left during combat
	"combat_preview": { "card_size": Vector2(336, 504), "font_scale": 0.7  },
	## Large preview in deck builder — the largest display
	"deck_preview":   { "card_size": Vector2(480, 720), "font_scale": 1.0  },
	## Reward / shop pick cards — fits 3 across comfortably
	"reward":         { "card_size": Vector2(270, 405), "font_scale": 0.56 },
	## Shop card slots — fits 4 across
	"shop":           { "card_size": Vector2(260, 390), "font_scale": 0.54 },
}
# fmt: on

var font_scale: float = 1.0
var size_mode:  String = "default"

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_find_nodes()
	_glow_overlay = Panel.new()
	_glow_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow_overlay.offset_left   = -4
	_glow_overlay.offset_top    = -4
	_glow_overlay.offset_right  =  4
	_glow_overlay.offset_bottom =  4
	_glow_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _blank := StyleBoxFlat.new()
	_blank.bg_color = Color(0, 0, 0, 0)
	_blank.draw_center = false
	_glow_overlay.add_theme_stylebox_override("panel", _blank)
	add_child(_glow_overlay)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func _find_nodes() -> void:
	background        = $Background               if has_node("Background")               else null
	art_rect          = $ArtRect                  if has_node("ArtRect")                  else null
	video_art         = $VideoArt as VideoStreamPlayer if has_node("VideoArt")            else null
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
	frame_shield_label = $FrameShieldLabel        if has_node("FrameShieldLabel")         else null

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(data: CardData) -> void:
	if data == null:
		push_error("CardVisual.setup() called with null data")
		return
	card_data = data

	# Reset frame overlay labels so reused nodes don't bleed minion state onto spells
	if frame_cost_label:
		frame_cost_label.visible = false
		frame_cost_label.add_theme_color_override("default_color", Color(1.0, 1.0, 1.0, 1.0))
	if frame_mana_label: frame_mana_label.visible = false
	if frame_atk_label:  frame_atk_label.visible  = false
	if frame_hp_label:    frame_hp_label.visible    = false
	if frame_shield_label: frame_shield_label.visible = false
	if cost_badge:       cost_badge.visible        = false
	if mana_badge:       mana_badge.visible        = false

	var faction: String = data.faction if data.faction != "" else "neutral"
	var style_key: String = _FACTION_FRAME.get(faction, {}).get(data.card_type, "default")
	var _talent_mana := GameManager.get_talent_mana_modifier(data) if data is MinionCardData else 0
	var is_dual := data is MinionCardData and \
		((data as MinionCardData).mana_cost > 0 or _talent_mana > 0)
	# Neutral: swap to dual-cost frame when minion has both costs
	if style_key == "neutral_essence_minion" and is_dual:
		style_key = "neutral_essence_mana_minion"
	_apply_frame_config(style_key, data.card_type, data.faction)

	var is_minion := data.card_type == Enums.CardType.MINION
	if is_minion:
		var md := data as MinionCardData
		if race_label:
			var type_str := _minion_type_string(md.minion_type)
			race_label.text    = type_str
			race_label.visible = type_str != ""
			var _rfaction: String = data.faction if data != null else "default"
			var _rcfg: Dictionary = _FACTION_TOOLTIP_CFG.get(_rfaction, _FACTION_TOOLTIP_CFG["default"])
			race_label.add_theme_color_override("font_color", _rcfg.get("race_color", Color(0.75, 0.50, 1.00, 1.0)))
	else:
		if race_label: race_label.visible = false

	if name_label:
		name_label.text = data.card_name
		_fit_name_font_size(data.card_name)
		var is_champion := data is MinionCardData and Enums.Keyword.CHAMPION in (data as MinionCardData).keywords
		var _nfaction: String = data.faction if data != null else "default"
		var _ncfg: Dictionary = _FACTION_TOOLTIP_CFG.get(_nfaction, _FACTION_TOOLTIP_CFG["default"])
		var _base_name_color: Color = _ncfg.get("name_color", Color(1.0, 1.0, 1.0, 1.0))
		name_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2, 1.0) if is_champion else _base_name_color)
		var _name_outline: int = _ncfg.get("name_outline_size", 0)
		name_label.add_theme_constant_override("outline_size", _name_outline)
		if _name_outline > 0:
			name_label.add_theme_color_override("font_outline_color", _ncfg.get("name_outline_color", Color(0, 0, 0, 1)))
	if desc_label:
		var _dfaction: String = data.faction if data != null else "default"
		var _dcfg: Dictionary = _FACTION_TOOLTIP_CFG.get(_dfaction, _FACTION_TOOLTIP_CFG["default"])
		desc_label.add_theme_color_override("default_color", _dcfg.get("text_color", Color(1, 1, 1, 1)))
		var kw_str := ""
		if data is MinionCardData:
			kw_str = _keywords_string((data as MinionCardData).keywords, (data as MinionCardData).clan)
		desc_label.text = _build_desc_bbcode(kw_str, data.description)
		# Shrink font after layout so content fits without scrolling
		call_deferred("_fit_desc_font_size")

	var _is_minion_frame: bool = _FRAME_CONFIG.get(_frame_style, {}).get("minion_frame", false)
	if is_minion:
		var md := data as MinionCardData
		if _is_minion_frame:
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
				var _frame_mana := md.mana_cost + GameManager.get_talent_mana_modifier(md)
				if _frame_mana > 0:
					# Dual cost: show "E / M" in the top-left essence badge.
					frame_cost_label.text    = "[center][color=#d4a0ff]%d[/color][color=#cccccc]/[/color][color=#90c8ff]%d[/color][/center]" % [md.essence_cost, _frame_mana]
				else:
					frame_cost_label.text    = "[center]%d[/center]" % md.essence_cost
				frame_cost_label.visible = true
				if frame_mana_label: frame_mana_label.visible = false
			var _has_frame_shield: bool = _FRAME_CONFIG.get(_frame_style, {}).get("has_frame_shield", false)
			if frame_shield_label:
				if _has_frame_shield and md.shield_max > 0:
					frame_shield_label.visible = true
					frame_shield_label.text    = str(md.shield_max)
				else:
					frame_shield_label.visible = false
		else:
			if stats_row: stats_row.visible = true
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
		if frame_cost_label:
			frame_cost_label.visible = true
			frame_cost_label.text    = "[center]%d[/center]" % data.cost

	if data.art_video_path != "" and ResourceLoader.exists(data.art_video_path):
		var stream := load(data.art_video_path) as VideoStream
		if stream and video_art:
			video_art.stream  = stream
			video_art.visible = true
			video_art.play()
			if art_rect: art_rect.visible = false
	elif art_rect and data.art_path != "":
		if video_art: video_art.visible = false
		var tex := load(data.art_path) as Texture2D
		if tex:
			art_rect.texture = tex
			art_rect.visible = true

	_apply_font_scale()
	_refresh_playable_state()

# ---------------------------------------------------------------------------
# Frame config apply — resolves texture, layout, and _frame_style in one call
# ---------------------------------------------------------------------------

func _apply_frame_config(style_key: String, card_type: Enums.CardType, faction: String = "default") -> void:
	var cfg: Dictionary = _FRAME_CONFIG.get(style_key, _FRAME_CONFIG["default"])
	var path: String = cfg.get("path", "")

	# Derive keyword highlight color from faction tooltip config
	var tip_c: Color = _FACTION_TOOLTIP_CFG.get(faction, _FACTION_TOOLTIP_CFG["default"]).get("desc_keyword_color", Color(0.75, 0.50, 1.00, 1.0))
	_kw_color_hex = "%02x%02x%02x" % [int(tip_c.r * 255), int(tip_c.g * 255), int(tip_c.b * 255)]

	if path != "" and ResourceLoader.exists(path):
		_frame_style = style_key
		if frame_texture:
			frame_texture.texture = load(path)
			frame_texture.visible = true
		if background: background.visible = false
	else:
		_frame_style = "default"
		if frame_texture:
			frame_texture.texture = null
			frame_texture.visible = false
		if background:
			background.visible = true
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.07, 0.07, 0.14, 1)
			sb.border_width_left = 2; sb.border_width_top = 2
			sb.border_width_right = 2; sb.border_width_bottom = 2
			sb.border_color = _type_border_color(card_type)
			sb.corner_radius_top_left = 6; sb.corner_radius_top_right = 6
			sb.corner_radius_bottom_right = 6; sb.corner_radius_bottom_left = 6
			background.add_theme_stylebox_override("panel", sb)

	var lay: Dictionary = _FRAME_CONFIG.get(_frame_style, _FRAME_CONFIG["default"])["layout"]
	_set_anchors(art_rect,         lay.get("art"))
	_set_anchors(video_art,        lay.get("art"))
	_set_anchors(name_label,       lay.get("name"))
	_set_anchors(race_label,       lay.get("race"))
	_set_anchors(desc_label,       lay.get("desc"))
	_set_anchors(stats_row,        lay.get("stats"))
	# Spell frames have no "essence" key — fall back to "mana" so frame_cost_label
	# is positioned over the frame's cost art area.
	_set_anchors(frame_cost_label, lay.get("essence", lay.get("mana")))
	_set_anchors(frame_mana_label, lay.get("mana"))
	_set_anchors(frame_atk_label,    lay.get("atk"))
	_set_anchors(frame_hp_label,     lay.get("hp"))
	_set_anchors(frame_shield_label, lay.get("shield"))

func _set_anchors(node: Control, a: Variant) -> void:
	if node == null or a == null:
		return
	node.anchor_left   = a[0]
	node.anchor_top    = a[1]
	node.anchor_right  = a[2]
	node.anchor_bottom = a[3]
	node.offset_left   = 0
	node.offset_top    = 0
	node.offset_right  = 0
	node.offset_bottom = 0

# ---------------------------------------------------------------------------
# Talent overlay — call after setup() during combat to reflect unlocked talents
# ---------------------------------------------------------------------------

## Apply a mana cost discount to non-minion cards (spells/traps/envs).
## Shows the effective cost in green when discounted, white otherwise.
## Call after setup() whenever the board discount changes.
func apply_cost_discount(discount: int) -> void:
	if card_data == null or card_data is MinionCardData:
		return
	var effective := maxi(0, card_data.cost - discount)
	if frame_cost_label and frame_cost_label.visible:
		var _hex: String
		if discount > 0 and card_data.cost > 0:
			_hex = "4dff4d"  # Green — discounted
		elif discount < 0:
			_hex = "ff4d4d"  # Red — increased
		else:
			_hex = "ffffff"  # White — normal
		frame_cost_label.text = "[center][color=#%s]%d[/color][/center]" % [_hex, effective]

## Updates displayed stats, cost, and description based on currently unlocked talents.
## Only meaningful during combat; DeckBuilder previews call setup() before talents exist.
func apply_talent_overlay() -> void:
	if card_data == null or not (card_data is MinionCardData):
		return
	if card_data.id != "void_imp":
		return

	var md := card_data as MinionCardData
	var display_atk := md.atk
	var display_hp  := md.health
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
		talent_notes.append("Piercing Void: 200 Void Bolt then +1 Void Mark on play")

	if talent_notes.is_empty():
		return

	if atk_label:       atk_label.text       = str(display_atk)
	if hp_label:        hp_label.text        = str(display_hp)
	if frame_atk_label: frame_atk_label.text = str(display_atk)
	if frame_hp_label:  frame_hp_label.text  = str(display_hp)
	# Cost display is handled by setup() via frame_cost_label / frame_mana_label — nothing to update here.

# ---------------------------------------------------------------------------
# Playability
# ---------------------------------------------------------------------------

func set_playable(playable: bool) -> void:
	is_playable = playable
	_refresh_playable_state()

func set_condition_glow(active: bool) -> void:
	condition_active = active
	if not active:
		_stop_glow_pulse()
	_update_glow_overlay()

func _refresh_playable_state() -> void:
	modulate = Color(1, 1, 1, 1) if is_playable else Color(0.45, 0.45, 0.55, 1.0)
	_update_glow_overlay()

func _update_glow_overlay() -> void:
	if _glow_overlay == null:
		return
	var s := StyleBoxFlat.new()
	s.bg_color    = Color(0, 0, 0, 0)
	s.draw_center = false
	s.set_corner_radius_all(6)
	if condition_active:
		# Gold — conditional bonus is available
		var border_w: float = 3.0 + _glow_pulse * 2.5
		var shadow_sz: float = 8.0 + _glow_pulse * 10.0
		var shadow_a: float  = 0.60 + _glow_pulse * 0.30
		s.border_color = Color(1.0, 0.78, 0.10, 1.0)
		s.set_border_width_all(border_w)
		s.shadow_color = Color(1.0, 0.78, 0.10, shadow_a)
		s.shadow_size  = shadow_sz
	# unaffordable — no border, just dim modulate
	_glow_overlay.add_theme_stylebox_override("panel", s)

# ---------------------------------------------------------------------------
# Selection — uses scale so HBoxContainer layout is never broken
# ---------------------------------------------------------------------------

func select() -> void:
	is_selected = true
	var s := size if size != Vector2.ZERO else custom_minimum_size
	pivot_offset = Vector2(s.x / 2.0, s.y)  # bottom-center → card lifts upward
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "scale", Vector2(1.1, 1.1), 0.12)
	_update_glow_overlay()

func deselect() -> void:
	is_selected = false
	_update_pivot()  # restore center pivot
	scale = SCALE_NORMAL
	_update_glow_overlay()

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_mouse_entered() -> void:
	_update_pivot()
	if not is_selected:
		scale = SCALE_HOVER
	if condition_active:
		_start_glow_pulse()
	card_hovered.emit(self)

func _on_mouse_exited() -> void:
	if not is_selected:
		scale = SCALE_NORMAL
	_stop_glow_pulse()
	card_unhovered.emit(self)

func _start_glow_pulse() -> void:
	if _glow_tween:
		_glow_tween.kill()
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_method(func(v: float) -> void:
		_glow_pulse = v
		_update_glow_overlay(), 0.0, 1.0, 0.5)
	_glow_tween.tween_method(func(v: float) -> void:
		_glow_pulse = v
		_update_glow_overlay(), 1.0, 0.0, 0.5)

func _stop_glow_pulse() -> void:
	if _glow_tween:
		_glow_tween.kill()
		_glow_tween = null
	_glow_pulse = 0.0
	_update_glow_overlay()

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


## Sets card_size, font_scale, and size_mode from _SIZE_CONFIG.
## Call before setup() so fonts and layout reflect the correct context.
func apply_size_mode(mode: String) -> void:
	size_mode = mode
	var cfg: Dictionary = _SIZE_CONFIG.get(mode, _SIZE_CONFIG["default"])
	font_scale = cfg["font_scale"]
	custom_minimum_size = cfg["card_size"]
	size = cfg["card_size"]

## Shrink desc font size until the content fits within the label's visible height.
## Called deferred so the label has completed layout and content_height is accurate.
func _fit_desc_font_size() -> void:
	if not is_instance_valid(self) or not is_instance_valid(desc_label):
		return
	var f: Dictionary = _FRAME_CONFIG.get(_frame_style, _FRAME_CONFIG["default"])["fonts"]
	var base_normal: int = roundi(f["desc_normal"] * font_scale)
	var base_bold:   int = roundi(f["desc_bold"]   * font_scale)
	var min_size := maxi(6, roundi(base_normal * 0.6))
	var normal_size := base_normal
	var bold_size   := base_bold
	while normal_size > min_size and desc_label.get_content_height() > desc_label.size.y:
		normal_size -= 1
		bold_size    = maxi(min_size, bold_size - 1)
		desc_label.add_theme_font_size_override("normal_font_size", normal_size)
		desc_label.add_theme_font_size_override("bold_font_size",   bold_size)

func _fit_name_font_size(card_name: String) -> void:
	var tiers: Array = _FRAME_CONFIG.get(_frame_style, _FRAME_CONFIG["default"])["fonts"].get(
		"name_tiers", [[10, 25], [14, 22], [18, 20], [999, 18]])
	var len := card_name.length()
	var base: int = tiers[-1][1]
	for tier in tiers:
		if len <= tier[0]:
			base = tier[1]
			break
	name_label.add_theme_font_size_override("font_size", roundi(base * font_scale))

func _apply_font_scale() -> void:
	var s := font_scale
	var f: Dictionary = _FRAME_CONFIG.get(_frame_style, _FRAME_CONFIG["default"])["fonts"]
	if desc_label:
		desc_label.add_theme_font_size_override("normal_font_size", roundi(f["desc_normal"] * s))
		desc_label.add_theme_font_size_override("bold_font_size",   roundi(f["desc_bold"]   * s))
	if atk_label:        atk_label.add_theme_font_size_override(       "font_size", roundi(f.get("atk",     11) * s))
	if hp_label:         hp_label.add_theme_font_size_override(        "font_size", roundi(f.get("hp",      11) * s))
	if shield_label:     shield_label.add_theme_font_size_override(    "font_size", roundi(f.get("shield",  11) * s))
	if race_label:       race_label.add_theme_font_size_override(      "font_size", roundi(f.get("race",    15) * s))
	if cost_label:       cost_label.add_theme_font_size_override(      "font_size", roundi(f.get("essence", 25) * s))
	if mana_label:       mana_label.add_theme_font_size_override(      "font_size", roundi(f.get("mana",    15) * s))
	# frame_cost_label is a RichTextLabel — uses "normal_font_size"; spells fall back to "mana"
	if frame_cost_label: frame_cost_label.add_theme_font_size_override("normal_font_size", roundi(f.get("essence", f.get("mana", 25)) * s))
	if frame_mana_label: frame_mana_label.add_theme_font_size_override("font_size", roundi(f.get("mana",    15) * s))
	if frame_atk_label:    frame_atk_label.add_theme_font_size_override(   "font_size", roundi(f.get("atk",    20) * s))
	if frame_hp_label:     frame_hp_label.add_theme_font_size_override(    "font_size", roundi(f.get("hp",     20) * s))
	if frame_shield_label: frame_shield_label.add_theme_font_size_override("font_size", roundi(f.get("shield", 18) * s))

## Builds BBCode for the desc box: keywords on line 1 (centered, gold, bold),
## then description below (normal). If no keywords, just plain description.
## Special terminology that gets highlighted violet+bold in descriptions.
const _TRIGGER_TERMS: Array[String] = [
	"ON PLAY", "ON DEATH", "ON SUMMON", "ON ATTACK", "ON DAMAGE", "ON HEAL",
	"ON TURN START", "ON TURN END", "ON DRAW", "ON DISCARD",
	"PASSIVE", "AURA", "RITUAL", "RUNE", "CORRUPTION", "CORRUPT",
	"VOID MARKS", "VOID MARK", "DEATHLESS",
	"VOID IMPS", "VOID IMP",    # clan name — plural before singular to avoid partial match
	"FERAL IMPS", "FERAL IMP", # clan name — plural before singular to avoid partial match
]

func _highlight_triggers(text: String) -> String:
	var result := text
	for term in _TRIGGER_TERMS:
		result = result.replace(term, "[color=#" + _kw_color_hex + "][b]" + term + "[/b][/color]")
	return result

func _build_desc_bbcode(kw_str: String, description: String) -> String:
	var desc := _highlight_triggers(description)
	if kw_str == "":
		return desc
	return "[center][color=#" + _kw_color_hex + "][b]" + kw_str + "[/b][/color][/center]\n" + desc

func _keywords_string(keywords: Array, clan: String = "") -> String:
	var parts: Array[String] = []
	for kw in keywords:
		match kw:
			Enums.Keyword.GUARD:          parts.append("Guard")
			Enums.Keyword.SWIFT:          parts.append("Swift")
			Enums.Keyword.LIFEDRAIN:      parts.append("Lifedrain")
			Enums.Keyword.SHIELD_REGEN_1: parts.append("Shield Regen")
			Enums.Keyword.SHIELD_REGEN_2: parts.append("Shield Regen+")
			Enums.Keyword.CHAMPION:       parts.append("Champion")
			Enums.Keyword.RUNE:           parts.append("Rune")
			Enums.Keyword.CORRUPTION:     parts.append("Corruption")
			Enums.Keyword.DEATHLESS:      parts.append("Deathless")
			Enums.Keyword.VOID_MARK:      pass  # display-only; not shown in keyword line
	if clan != "":
		parts.append("Clan: " + clan)
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
		Enums.MinionType.MERCENARY: return "Mercenary"
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

# ===========================================================================
# Keyword / Ritual Tooltip Panel
# Shown to the right of the card in large preview contexts only.
# Call enable_tooltip() after setup() from DeckBuilderScene, CollectionScene,
# and CombatScene (combat_preview). The panel is rebuilt each call.
# ===========================================================================

var _tooltip: Control = null

## keyword enum value → [display_name, description]
const _KEYWORD_TOOLTIP: Dictionary = {
	Enums.Keyword.GUARD:          ["Guard",       "Must be attacked before other targets can be chosen."],
	Enums.Keyword.SWIFT:          ["Swift",       "Can attack enemy minions on the turn played. Cannot attack the enemy hero that turn."],
	Enums.Keyword.LIFEDRAIN:      ["Lifedrain",   "Damage dealt to the enemy hero heals your hero by the same amount."],
	Enums.Keyword.SHIELD_REGEN_1: ["Barrier I",   "Regenerates 1 Shield at the start of your turn."],
	Enums.Keyword.SHIELD_REGEN_2: ["Barrier II",  "Regenerates 2 Shield at the start of your turn."],
	Enums.Keyword.CHAMPION:       ["Champion",    "A legendary unit. Can only be summoned when its board condition is met."],
	Enums.Keyword.RUNE:           ["Rune",        "Placed face-up. Provides an ongoing aura effect until consumed by a Ritual."],
	Enums.Keyword.CORRUPTION:     ["Corruption",  "Reduces the afflicted minion's ATK by 100 per stack."],
	Enums.Keyword.DEATHLESS:      ["Deathless",   "Prevents the next fatal hit once. Sets HP to 50 instead of dying. Consumed after use."],
	Enums.Keyword.VOID_MARK:      ["Void Mark",   "A debuff stack placed on the enemy hero. Void Bolt deals bonus damage per stack."],
	Enums.Keyword.RITUAL:         ["Ritual",      "A powerful effect triggered by consuming the required Runes on the field."],
}

## RuneType enum value → display name used in the ritual tooltip
const _RUNE_TOOLTIP_NAME: Dictionary = {
	Enums.RuneType.VOID_RUNE:     "Void Rune",
	Enums.RuneType.BLOOD_RUNE:    "Blood Rune",
	Enums.RuneType.DOMINION_RUNE: "Dominion Rune",
	Enums.RuneType.SHADOW_RUNE:   "Shadow Rune",
}

## keyword enum value → icon path shown before the keyword name in the tooltip
const _KEYWORD_ICON: Dictionary = {
	Enums.Keyword.GUARD:          "res://assets/art/icons/icon_guard.png",
	Enums.Keyword.SWIFT:          "res://assets/art/icons/icon_swift.png",
	Enums.Keyword.LIFEDRAIN:      "res://assets/art/icons/icon_lifedrain.png",
	Enums.Keyword.SHIELD_REGEN_1: "res://assets/art/icons/icon_rune.png",
	Enums.Keyword.SHIELD_REGEN_2: "res://assets/art/icons/icon_rune.png",
	Enums.Keyword.CHAMPION:       "res://assets/art/icons/icon_champion.png",
	Enums.Keyword.RUNE:           "res://assets/art/icons/icon_rune.png",
	Enums.Keyword.CORRUPTION:     "res://assets/art/icons/icon_corruption.png",
	Enums.Keyword.DEATHLESS:      "res://assets/art/icons/icon_deathless.png",
	Enums.Keyword.VOID_MARK:      "res://assets/art/icons/icon_voidmark.png",
	Enums.Keyword.RITUAL:         "res://assets/art/icons/icon_ritual.png",
}

## Build and show the tooltip panel to the right of this card.
## Call after setup() in deck builder, collection, and combat large preview contexts.
## Shows keywords (minions, runes, corruption cards) and/or ritual info (environments).
## Silently does nothing and removes any existing panel if the card has neither.
func enable_tooltip() -> void:
	if card_data == null:
		return

	# Collect all keywords to display
	var keywords: Array = []
	if card_data is MinionCardData:
		keywords.append_array((card_data as MinionCardData).keywords)
	# Rune cards are traps with is_rune=true
	if card_data is TrapCardData and (card_data as TrapCardData).is_rune:
		keywords.append(Enums.Keyword.RUNE)
	# Any card whose description mentions CORRUPTION or CORRUPT gets the Corruption keyword
	if ("CORRUPTION" in card_data.description or "CORRUPT" in card_data.description) and not Enums.Keyword.CORRUPTION in keywords:
		keywords.append(Enums.Keyword.CORRUPTION)
	# Cards that apply or scale with Void Marks get the Void Mark tooltip entry
	if ("VOID MARK" in card_data.description) and not Enums.Keyword.VOID_MARK in keywords:
		keywords.append(Enums.Keyword.VOID_MARK)
	# Cards that grant or reference Deathless get the Deathless keyword tooltip entry
	if ("DEATHLESS" in card_data.description) and not Enums.Keyword.DEATHLESS in keywords:
		keywords.append(Enums.Keyword.DEATHLESS)

	var has_rituals := card_data is EnvironmentCardData \
		and (card_data as EnvironmentCardData).rituals.size() > 0
	# Environment cards with rituals get the Ritual keyword tooltip entry
	if has_rituals and not Enums.Keyword.RITUAL in keywords:
		keywords.append(Enums.Keyword.RITUAL)
	var clan: String = ""
	if card_data is MinionCardData:
		clan = (card_data as MinionCardData).clan
	if keywords.is_empty() and not has_rituals and clan.is_empty():
		_remove_tooltip()
		return
	_build_tooltip(keywords, has_rituals, clan)

func _remove_tooltip() -> void:
	if _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.queue_free()
	_tooltip = null

func _build_tooltip(keywords: Array, has_rituals: bool, clan: String = "") -> void:
	_remove_tooltip()
	clip_contents = false  # allow the tooltip to render outside the card rect

	var faction: String = card_data.faction if card_data != null else "default"
	var tip_cfg: Dictionary = _FACTION_TOOLTIP_CFG.get(faction, _FACTION_TOOLTIP_CFG["default"])
	var kw_color: Color = tip_cfg.get("tooltip_keyword_color", Color(0.75, 0.50, 1.00, 1.0))
	var anchor:    Vector2    = tip_cfg.get("anchor", Vector2(1.0, 0.0))
	var card_w    := maxi(roundi(custom_minimum_size.x), 1)
	var card_h    := maxi(roundi(custom_minimum_size.y), 1)
	var tip_w     := roundi(card_w * float(tip_cfg.get("w_scale", 0.62)))
	var tip_h     := roundi(card_h * float(tip_cfg.get("h_scale", 1.0)))
	var t_size    := maxi(roundi(float(tip_cfg.get("title_font", 15)) * font_scale), 7)
	var b_size    := maxi(roundi(float(tip_cfg.get("body_font",  11)) * font_scale), 6)
	var tr: Array  = tip_cfg.get("title_rect", [0.05, 0.03, 0.95, 0.22])
	var br: Array  = tip_cfg.get("body_rect",  [0.05, 0.24, 0.95, 0.97])

	var bold_font: Font = load("res://assets/fonts/cinzel/Cinzel-Bold.ttf")

	# Root container — sized and positioned relative to the card
	_tooltip = Control.new()
	_tooltip.position            = Vector2(roundi(card_w * anchor.x), roundi(card_h * anchor.y))
	_tooltip.custom_minimum_size = Vector2(tip_w, tip_h)
	_tooltip.size                = Vector2(tip_w, tip_h)
	_tooltip.clip_contents       = true
	add_child(_tooltip)

	# Background — explicit size, no anchors, so the layout engine can't override it
	var bg := TextureRect.new()
	var _tooltip_tex_path: String = "res://assets/art/frames/neutral/neutral_tooltip.png" \
		if card_data != null and card_data.faction == "neutral" \
		else "res://assets/art/frames/abyss_order/abyss_tooltip.png"
	bg.texture      = load(_tooltip_tex_path)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	bg.position     = Vector2.ZERO
	bg.size         = Vector2(tip_w, tip_h)
	_tooltip.add_child(bg)

	# Title container — independently positioned, center-aligned
	var title_box := VBoxContainer.new()
	title_box.position            = Vector2(tr[0] * tip_w, tr[1] * tip_h)
	title_box.size                = Vector2((tr[2] - tr[0]) * tip_w, (tr[3] - tr[1]) * tip_h)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tooltip.add_child(title_box)

	# Body container — independently positioned, left-aligned
	var body_box := VBoxContainer.new()
	body_box.position             = Vector2(br[0] * tip_w, br[1] * tip_h)
	body_box.size                 = Vector2((br[2] - br[0]) * tip_w, (br[3] - br[1]) * tip_h)
	body_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tooltip.add_child(body_box)

	# --- Keywords + Clan + Rituals section (single "Keywords" title) ---
	if keywords.size() > 0 or clan != "" or has_rituals:
		_tooltip_title(title_box, "Keywords", t_size, bold_font, Color(1.0, 1.0, 1.0, 0.95))

	for kw in keywords:
		var info: Array = _KEYWORD_TOOLTIP.get(kw, [])
		if info.is_empty():
			continue
		var icon_path: String = _KEYWORD_ICON.get(kw, "")
		_tooltip_icon_title(body_box, info[0], t_size, bold_font, kw_color, icon_path)
		_tooltip_body(body_box, info[1], b_size, body_box.size.x, bold_font)

	if clan != "":
		_tooltip_icon_title(body_box, "Clan: " + clan, t_size, bold_font, kw_color, "res://assets/art/icons/icon_clan.png")
		_tooltip_body(body_box, "This minion belongs to the " + clan + " clan. Card effects that reference " + clan + "s affect it.", b_size, body_box.size.x, bold_font)

	if has_rituals:
		for ritual in (card_data as EnvironmentCardData).rituals:
			var body_str := "Ritual - " + ritual.ritual_name + ": " + ritual.description
			_tooltip_body(body_box, body_str, b_size, body_box.size.x, bold_font)

## Icon + bold label row (left-aligned) — used for keyword names in the body container.
func _tooltip_icon_title(parent: VBoxContainer, text: String,
		font_size: int, bold_font: Font, color: Color, icon_path: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 4)

	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture             = load(icon_path)
		icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(font_size, font_size)
		icon.size                = Vector2(font_size, font_size)
		hbox.add_child(icon)

	var lbl := Label.new()
	lbl.text                  = text
	lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_LEFT
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_override("font", bold_font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	hbox.add_child(lbl)
	parent.add_child(hbox)

## Bold center-aligned label added to the title container.
func _tooltip_title(parent: VBoxContainer, text: String,
		font_size: int, bold_font: Font, color: Color) -> void:
	var lbl := Label.new()
	lbl.text                    = text
	lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_override("font", bold_font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)

## Left-aligned body label added to the body container.
func _tooltip_body(parent: VBoxContainer, text: String,
		font_size: int, wrap_w: float, bold_font: Font) -> void:
	var lbl := Label.new()
	lbl.text                    = text
	lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_LEFT
	lbl.autowrap_mode           = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size     = Vector2(wrap_w, 0)
	lbl.add_theme_font_override("font", bold_font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.85, 1.0))
	parent.add_child(lbl)
