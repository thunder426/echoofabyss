## BoardSlot.gd
## Represents one of the 5 board slots on either side.
## Empty slots show the plain Panel style.
## Occupied slots use the abyss_battlefield_minion.png frame with Cinzel Bold labels.
## Abyss-order non-shielded minions use abyss_battlefield_minion_generic_v2.png:
##   no cost badge, no name bar — big art + status bar + ATK + HP only.
##
## Render order (bottom → top):
##   _art_rect   — minion art sits behind the frame window
##   _frame_rect — frame PNG overlays the art
##   _overlay    — semi-transparent highlight tint
##   labels      — cost / name / atk / hp / status bar (HBoxContainer of icons)
class_name BoardSlot
extends Panel

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal slot_clicked_empty(slot: BoardSlot)
signal slot_clicked_occupied(slot: BoardSlot, minion: MinionInstance)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var slot_owner: String = "player"
var index: int = 0
var minion: MinionInstance = null

# ---------------------------------------------------------------------------
# Highlight
# ---------------------------------------------------------------------------

enum HighlightMode { NONE, VALID_TARGET, SELECTED, INVALID, PLACEMENT }
var _highlight_mode: HighlightMode = HighlightMode.NONE
var _pulse_tween: Tween = null
var _pulse_t: float = 0.0
## Optional per-slot override for the VALID_TARGET glow color. When set
## (alpha > 0), it replaces the default green so spells can flag specific
## targets — e.g. Dark Empowerment marking Demons in violet to telegraph
## the conditional HP bonus. Reset to Color(0,0,0,0) by clear_highlight().
var _highlight_color_override: Color = Color(0, 0, 0, 0)

# ===========================================================================
# BATTLEFIELD TEXT CONFIG  (slot is 180 × 195 px)
# Tweak pos / size / font_size here to align labels with the frame artwork.
# "art" has no font_size — it is a TextureRect, not a label.
# ===========================================================================
# fmt: off
const _CFG: Dictionary = {
	# Minion art window — sits BEHIND the frame PNG
	"art":    { "pos": Vector2( 14,  26), "size": Vector2(152, 116) },

	# Essence cost — top-left gem (single and dual cost minions)
	"cost":      { "pos": Vector2(  1,  7), "size": Vector2( 30,  24), "font_size": 12 },
	# Mana cost — top-right gem (dual cost minions only)
	"mana_cost": { "pos": Vector2(148,  7), "size": Vector2( 30,  24), "font_size": 12 },

	# Card name — centered across full card width; long names drop to font_size_long
	"name":   { "pos": Vector2(  0,   4), "size": Vector2(179,  14), "font_size": 10, "font_size_long": 8, "long_threshold": 13 },

	# ATK  — bottom-left
	"atk":    { "pos": Vector2(  28, 164), "size": Vector2( 52,  30), "font_size": 12 },

	# Status bar — bottom-center, full inner width so HBoxContainer can center icons
	"status": { "pos": Vector2( 14, 142), "size": Vector2(152,  24) },

	# HP  — bottom-right  (shows "+shield" suffix when active)
	"hp":     { "pos": Vector2(105, 164), "size": Vector2( 52,  30), "font_size": 12 },
}

# Generic frame layout (abyss_battlefield_minion_generic_v2.png):
# No cost badge, no name bar — art fills the top portion of the slot.
const _CFG_GENERIC: Dictionary = {
	# Art window — larger, starts from near top edge
	"art":    { "pos": Vector2(  21, 10), "size": Vector2(140, 140) },

	# ATK  — bottom-left (same as normal)
	"atk":    { "pos": Vector2( 20, 163), "size": Vector2( 52,  30), "font_size": 12 },

	# Status bar — bottom-center (same as normal)
	"status": { "pos": Vector2( 14, 142), "size": Vector2(152,  23) },

	# HP  — bottom-right (same as normal)
	"hp":     { "pos": Vector2(108, 163), "size": Vector2( 52,  30), "font_size": 12 },
}
# fmt: on

const SLOT_W := 180
const SLOT_H := 195
const _STATUS_ICON_SIZE := 18
const _STATUS_FONT_SIZE := 9

# ---------------------------------------------------------------------------
# Visual nodes
# ---------------------------------------------------------------------------

var _frame_rect:  TextureRect
var _art_rect:    TextureRect
var _overlay:     Panel   # Border-glow highlight (transparent bg, coloured border + shadow)
var _cost_label:      Label
var _mana_cost_label: Label
var _name_label:      Label
var _atk_label:   Label
var _hp_label:    Label
var _status_bar:  HBoxContainer

var _bold_font: Font

var _is_hovered:    bool = false
var freeze_visuals: bool = false   # Set true during lunge to prevent empty-state flash

# Status bar tooltip
var _status_tooltip: Panel = null
var _using_generic:  bool = false

# Animated label tweens — track per-label so consecutive stat changes pick up
# from the live displayed value and don't fight each other. Used by
# _animate_label_to_int (HP and ATK).
var _atk_value_tween: Tween = null
var _hp_value_tween:  Tween = null
const _STAT_ANIM_DURATION: float = 0.35
const _STAT_ANIM_MIN_DELTA: int  = 2


# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_bold_font = load("res://assets/fonts/cinzel/Cinzel-Bold.ttf") \
		if ResourceLoader.exists("res://assets/fonts/cinzel/Cinzel-Bold.ttf") else null
	_build_styles()
	_build_visuals()
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_refresh_visuals()

# ---------------------------------------------------------------------------
# Empty-slot Panel styles (coloured border, dark bg)
# ---------------------------------------------------------------------------

func _build_styles() -> void:
	pass  # All highlight is handled via _overlay glow — no filled styles needed

# ---------------------------------------------------------------------------
# Build visual nodes
# ---------------------------------------------------------------------------

func _build_visuals() -> void:
	# --- Minion art (added FIRST = bottom layer, sits behind the frame) ---
	_art_rect = TextureRect.new()
	_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art_rect.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_art_rect.position     = _CFG["art"]["pos"]
	_art_rect.size         = _CFG["art"]["size"]
	_art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_rect.visible      = false
	add_child(_art_rect)

	# --- Frame PNG (added SECOND = overlays the art) ---
	_frame_rect = TextureRect.new()
	if ResourceLoader.exists("res://assets/art/frames/abyss_order/abyss_battlefield_minion.png"):
		_frame_rect.texture = load("res://assets/art/frames/abyss_order/abyss_battlefield_minion.png")
	_frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_frame_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_frame_rect.position     = Vector2.ZERO
	_frame_rect.size         = Vector2(SLOT_W, SLOT_H)
	_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_rect.visible      = false
	add_child(_frame_rect)

	# --- Highlight overlay (border-glow panel, expands 4px outside slot to prevent shadow bleed) ---
	_overlay = Panel.new()
	_overlay.position     = Vector2(-4, -4)
	_overlay.size         = Vector2(SLOT_W + 8, SLOT_H + 8)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _blank := StyleBoxFlat.new()
	_blank.bg_color = Color(0, 0, 0, 0)
	_blank.draw_center = false
	_overlay.add_theme_stylebox_override("panel", _blank)
	add_child(_overlay)

	# --- Labels (hidden until occupied) ---
	_cost_label      = _make_label("cost",      Color(1.00, 0.85, 0.30, 1), HORIZONTAL_ALIGNMENT_CENTER, true)
	_mana_cost_label = _make_label("mana_cost", Color(0.40, 0.75, 1.00, 1), HORIZONTAL_ALIGNMENT_CENTER, true)
	_name_label      = _make_label("name",      Color(1.00, 1.00, 1.00, 1), HORIZONTAL_ALIGNMENT_CENTER, true)
	_atk_label  = _make_label("atk",  Color(1.00, 0.75, 0.25, 1), HORIZONTAL_ALIGNMENT_CENTER, true)
	_hp_label   = _make_label("hp",   Color(0.35, 1.00, 0.50, 1), HORIZONTAL_ALIGNMENT_CENTER, true)

	# --- Status bar (HBoxContainer — rebuilt each refresh) ---
	_status_bar = HBoxContainer.new()
	_status_bar.position = _CFG["status"]["pos"]
	_status_bar.size     = _CFG["status"]["size"]
	_status_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_bar.add_theme_constant_override("separation", 4)
	_status_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_status_bar.visible      = false
	add_child(_status_bar)

func _make_label(cfg_key: String, color: Color,
		align: HorizontalAlignment, use_bold: bool) -> Label:
	var cfg: Dictionary = _CFG[cfg_key]
	var lbl := Label.new()
	lbl.position = cfg["pos"]
	lbl.size     = cfg["size"]
	lbl.add_theme_font_size_override("font_size", cfg["font_size"])
	lbl.horizontal_alignment = align
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	lbl.clip_text    = false
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.visible      = false
	if use_bold and _bold_font:
		lbl.add_theme_font_override("font", _bold_font)
	add_child(lbl)
	return lbl

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_empty():
			slot_clicked_empty.emit(self)
		else:
			slot_clicked_occupied.emit(self, minion)

func _on_mouse_entered() -> void:
	_is_hovered = true
	if _highlight_mode == HighlightMode.VALID_TARGET or _highlight_mode == HighlightMode.PLACEMENT:
		_start_pulse()
	elif _highlight_mode != HighlightMode.NONE:
		_refresh_visuals()

func _on_mouse_exited() -> void:
	_is_hovered = false
	_stop_pulse()
	if _highlight_mode != HighlightMode.NONE:
		_refresh_visuals()

func _start_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_method(func(v: float) -> void:
		_pulse_t = v
		_refresh_visuals(), 0.0, 1.0, 0.5)
	_pulse_tween.tween_method(func(v: float) -> void:
		_pulse_t = v
		_refresh_visuals(), 1.0, 0.0, 0.5)

func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	_pulse_t = 0.0

# ---------------------------------------------------------------------------
# Minion placement
# ---------------------------------------------------------------------------

func is_empty() -> bool:
	return minion == null

func place_minion(m: MinionInstance) -> void:
	minion = m
	minion.slot_index = index
	_refresh_visuals()

func remove_minion() -> void:
	minion = null
	# Force-clear even if mid-lunge/sacrifice — the minion is gone, so the
	# freeze (meant to hide transient empty-state flashes) would otherwise
	# leave stale art on a now-dead slot. Death VFX renders in $UI, not here.
	freeze_visuals = false
	_refresh_visuals()

# ---------------------------------------------------------------------------
# Highlight
# ---------------------------------------------------------------------------

func set_highlight(mode: HighlightMode, color_override: Color = Color(0, 0, 0, 0)) -> void:
	if mode != HighlightMode.VALID_TARGET and mode != HighlightMode.PLACEMENT:
		_stop_pulse()
	_highlight_mode = mode
	_highlight_color_override = color_override
	_refresh_visuals()

func clear_highlight() -> void:
	_highlight_color_override = Color(0, 0, 0, 0)
	set_highlight(HighlightMode.NONE)

# ---------------------------------------------------------------------------
# Stat label — snap helpers and VFX-anchored tweens
# ---------------------------------------------------------------------------
##
## Architecture: regular refresh paths (_show_occupied_state, refresh_stats_only)
## SNAP labels directly via _snap_atk_label / _snap_hp_label. These are the
## "ground truth" updates that keep labels in sync with state.
##
## Tweens are triggered only by VFX paths via animate_hp_change / animate_atk_change.
## The VFX is the visible authorization to show a stat change; the tween animates
## the label from the pre-change value to the current minion value at that moment.
##
## Critically: snap helpers KILL any in-flight tween so they don't fight each
## other. A tween in progress is fine, but the next refresh hard-overrides it.

## Smart-write the ATK label. If the displayed value already matches `value`,
## no-op. If different and the displayed text is a pure int, START A TWEEN
## from displayed → value. If different but displayed is non-numeric (initial
## empty / formatted), snap directly. If a tween is already running, leaves
## it alone (the tween knows the correct end value and is mid-flight).
func _snap_atk_label(value: int) -> void:
	if _atk_value_tween != null and _atk_value_tween.is_valid():
		return
	var current_text: String = _atk_label.text
	if not current_text.is_valid_int():
		_atk_label.text = str(value)
		return
	var displayed: int = current_text.to_int()
	if displayed == value:
		return
	# Stat changed — animate from displayed to new value.
	_run_label_tween(_atk_label, displayed, value, "atk")

## Smart-write the HP label. Same rules as _snap_atk_label, but the HP label
## also handles shield-suffix variants ("1500+200"). When the new text is the
## shield format, snap directly (no tween — format change). When both old and
## new are pure ints, tween. Otherwise snap.
func _snap_hp_label(text: String) -> void:
	if _hp_value_tween != null and _hp_value_tween.is_valid():
		return
	if _hp_label.text == text:
		return
	# Tween only when both values are pure ints (no shield suffix transitions).
	if text.is_valid_int() and _hp_label.text.is_valid_int():
		var old_value: int = _hp_label.text.to_int()
		var new_value: int = text.to_int()
		_run_label_tween(_hp_label, old_value, new_value, "hp")
		return
	_hp_label.text = text

## VFX-anchored: tween HP from `from_hp` to `to_hp`, in sync with the floating
## "-N" popup. Caller passes both values to avoid ambiguity about whether
## state mutation has run yet (different paths emit signals before vs after
## applying damage).
##
## Snaps without animation when:
##   - Minion missing
##   - Shield active (label format includes "+N")
##   - |delta| < _STAT_ANIM_MIN_DELTA
##   - VFX time scale is zero
func animate_hp_change(from_hp: int, to_hp: int) -> void:
	if minion == null:
		return
	# Shield variant — snap, don't tween.
	if minion.has_shield() and minion.current_shield > 0:
		_hp_label.add_theme_color_override("font_color", Color(0.40, 0.85, 1.00, 1))
		_snap_hp_label("%d+%d" % [minion.current_health, minion.current_shield])
		return
	_hp_label.add_theme_color_override("font_color", Color(0.35, 1.00, 0.50, 1))
	_run_label_tween(_hp_label, from_hp, to_hp, "hp")

## VFX-anchored: tween ATK from `from_atk` → current effective_atk(). Caller
## passes the pre-buff snapshot so the start point is correct regardless of
## what the label happens to display.
func animate_atk_change(from_atk: int) -> void:
	if minion == null:
		return
	var corruption_total := BuffSystem.sum_type(minion, Enums.BuffType.CORRUPTION)
	_atk_label.add_theme_color_override("font_color",
		Color(0.70, 0.45, 0.10, 1) if corruption_total > 0 else Color(1.00, 0.75, 0.25, 1))
	var post_atk: int = minion.effective_atk()
	_run_label_tween(_atk_label, from_atk, post_atk, "atk")



## Internal: run a tween from old→new on `label`, tracked under `which` ("hp" or "atk").
## Cancels any active tween on that label first. Snaps if delta is too small or
## duration would be zero.
func _run_label_tween(label: Label, old_value: int, new_value: int, which: String) -> void:
	# Kill the matching active tween for this label.
	if which == "hp":
		if _hp_value_tween != null and _hp_value_tween.is_valid():
			_hp_value_tween.kill()
			_hp_value_tween = null
	else:
		if _atk_value_tween != null and _atk_value_tween.is_valid():
			_atk_value_tween.kill()
			_atk_value_tween = null

	var delta: int = absi(new_value - old_value)
	if delta < _STAT_ANIM_MIN_DELTA:
		label.text = str(new_value)
		return
	var duration: float = _STAT_ANIM_DURATION * BaseVfx.time_scale
	if duration <= 0.0:
		label.text = str(new_value)
		return

	# Force the start value so the tween begins from the correct pre-change
	# number regardless of what the label was previously displaying.
	label.text = str(old_value)
	var tw := create_tween()
	# Linear pacing so the number ticks at a constant rate — feels like a
	# counter "spinning down" rather than snapping.
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(label):
			label.text = str(int(round(v))),
		float(old_value), float(new_value), duration) \
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(label):
			label.text = str(new_value))

	if which == "hp":
		_hp_value_tween = tw
	else:
		_atk_value_tween = tw

# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------

func _refresh_visuals() -> void:
	if _overlay == null:
		return

	# When frozen (lunge / sacrifice / damage-VFX hold), skip the heavy refresh
	# (frame, art, status icons) but STILL update the stat labels so HP/ATK
	# tweens visibly track during the freeze window. Labels are pure text
	# overlays — updating them never disrupts a VFX.
	if freeze_visuals:
		if minion != null:
			refresh_stats_only()
		return

	if minion == null:
		_show_empty_state()
	else:
		_show_occupied_state()

## Refresh ONLY the HP and ATK label values, bypassing freeze_visuals.
## SNAPS labels (no animation) — tweens are the VFX paths' responsibility.
## Used by the spell-damage-popup path AFTER animate_hp_change has been called
## and finished, or in places where we just want the labels in sync with state.
func refresh_stats_only() -> void:
	if minion == null:
		return
	var corruption_total := BuffSystem.sum_type(minion, Enums.BuffType.CORRUPTION)
	var effective_atk := minion.effective_atk()
	_atk_label.add_theme_color_override("font_color",
		Color(0.70, 0.45, 0.10, 1) if corruption_total > 0 else Color(1.00, 0.75, 0.25, 1))
	_snap_atk_label(effective_atk)

	if minion.has_shield() and minion.current_shield > 0:
		_hp_label.add_theme_color_override("font_color", Color(0.40, 0.85, 1.00, 1))
		_snap_hp_label("%d+%d" % [minion.current_health, minion.current_shield])
	else:
		_hp_label.add_theme_color_override("font_color", Color(0.35, 1.00, 0.50, 1))
		_snap_hp_label(str(minion.current_health))

const _ABYSS_HEROES     := ["lord_vael", "seris"]
const _ABYSS_EMPTY_SLOT := "res://assets/art/frames/abyss_order/abyss_empty_slot.png"

func _show_empty_state() -> void:
	# Kill any in-flight stat tweens — the slot is now empty, the previous
	# minion's HP/ATK animation must not keep writing to the labels.
	if _atk_value_tween != null and _atk_value_tween.is_valid():
		_atk_value_tween.kill()
		_atk_value_tween = null
	if _hp_value_tween != null and _hp_value_tween.is_valid():
		_hp_value_tween.kill()
		_hp_value_tween = null
	# Always transparent panel bg — highlight is purely a border glow
	var blank := StyleBoxFlat.new()
	blank.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", blank)

	# Abyss hero: show empty slot image
	if GameManager.current_hero in _ABYSS_HEROES and ResourceLoader.exists(_ABYSS_EMPTY_SLOT):
		_frame_rect.texture = load(_ABYSS_EMPTY_SLOT)
		_frame_rect.visible = true
	else:
		_frame_rect.visible = false

	# Border glow overlay (same as occupied slots)
	match _highlight_mode:
		HighlightMode.VALID_TARGET: _set_overlay_glow(_valid_target_color())
		HighlightMode.SELECTED:     _set_overlay_glow(Color(0.85, 0.75, 0.10, 1))
		HighlightMode.INVALID:      _set_overlay_glow(Color(0.70, 0.15, 0.15, 1))
		HighlightMode.PLACEMENT:    _set_overlay_glow(Color(0.608, 0.349, 0.714, 1))  # violet
		_:                          _clear_overlay()

	_art_rect.visible = false
	_set_labels_visible(false)

func _show_occupied_state() -> void:
	# Transparent Panel background — frame PNG takes over
	var blank := StyleBoxFlat.new()
	blank.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", blank)

	# Highlight: border glow on the overlay Panel (no fill tint)
	match _highlight_mode:
		HighlightMode.VALID_TARGET: _set_overlay_glow(_valid_target_color())
		HighlightMode.SELECTED:     _set_overlay_glow(Color(0.85, 0.75, 0.10, 1))
		HighlightMode.INVALID:      _set_overlay_glow(Color(0.70, 0.15, 0.15, 1))
		HighlightMode.PLACEMENT:    _set_overlay_glow(Color(0.608, 0.349, 0.714, 1))  # violet
		_:                          _clear_overlay()

	_frame_rect.visible = true
	# Pick frame based on faction, dual-cost, and shield state
	var _md_check := minion.card_data as MinionCardData
	var _is_dual  := _md_check != null and _md_check.mana_cost > 0
	var _has_shield := minion.has_shield() and minion.current_shield > 0
	var _faction := minion.card_data.faction
	var _use_generic := not _has_shield and (_faction == "abyss_order" or _faction == "neutral")
	_using_generic = _use_generic
	var _frame_path: String
	if _use_generic:
		_frame_path = "res://assets/art/frames/abyss_order/abyss_battlefield_minion_generic_v2.png"
	elif _faction == "neutral":
		_frame_path = "res://assets/art/frames/neutral/neutral_dual_battlefield_minion.png" \
			if _is_dual else "res://assets/art/frames/neutral/neutral_battlefield_minion.png"
	else:
		_frame_path = "res://assets/art/frames/abyss_order/abyss_dual_battlefield_minion.png" \
			if _is_dual else "res://assets/art/frames/abyss_order/abyss_battlefield_minion.png"
	if ResourceLoader.exists(_frame_path):
		_frame_rect.texture = load(_frame_path)
	_set_labels_visible(true, _use_generic)

	# Reposition art rect based on which layout is active
	if _use_generic:
		_art_rect.position = _CFG_GENERIC["art"]["pos"]
		_art_rect.size     = _CFG_GENERIC["art"]["size"]
		_status_bar.position = _CFG_GENERIC["status"]["pos"]
		_atk_label.position = _CFG_GENERIC["atk"]["pos"]
		_atk_label.size     = _CFG_GENERIC["atk"]["size"]
		_hp_label.position  = _CFG_GENERIC["hp"]["pos"]
		_hp_label.size      = _CFG_GENERIC["hp"]["size"]
	else:
		_art_rect.position = _CFG["art"]["pos"]
		_art_rect.size     = _CFG["art"]["size"]
		_status_bar.position = _CFG["status"]["pos"]
		_atk_label.position = _CFG["atk"]["pos"]
		_atk_label.size     = _CFG["atk"]["size"]
		_hp_label.position  = _CFG["hp"]["pos"]
		_hp_label.size      = _CFG["hp"]["size"]

	# Art — prefer battlefield_art_path when set, fall back to art_path
	_art_rect.visible = true
	var art_path := minion.card_data.battlefield_art_path
	if art_path == "":
		art_path = minion.card_data.art_path
	if art_path != "":
		var tex := load(art_path) as Texture2D
		_art_rect.texture = tex if tex else null
	else:
		_art_rect.texture = null

	# Cost — essence always top-left; mana top-right for dual-cost minions only.
	# Generic frame hides both cost labels entirely.
	var md := minion.card_data as MinionCardData
	if md:
		_cost_label.text      = str(md.essence_cost)
		_mana_cost_label.text = str(md.mana_cost) if md.mana_cost > 0 else ""
		_mana_cost_label.visible = md.mana_cost > 0 and not _use_generic
	else:
		_cost_label.text         = ""
		_mana_cost_label.text    = ""
		_mana_cost_label.visible = false

	# Name — smaller font for long names
	var _card_name := minion.card_data.card_name
	_name_label.text = _card_name
	var _name_cfg := _CFG["name"]
	var _name_fs: int = _name_cfg["font_size_long"] \
		if _card_name.length() >= _name_cfg["long_threshold"] \
		else _name_cfg["font_size"]
	_name_label.add_theme_font_size_override("font_size", _name_fs)

	# ATK — tinted darker when corrupted. Snap label directly; tweens are
	# triggered only by the VFX paths (animate_atk_change / animate_hp_change).
	var corruption_total := BuffSystem.sum_type(minion, Enums.BuffType.CORRUPTION)
	var effective_atk := minion.effective_atk()
	_atk_label.add_theme_color_override("font_color",
		Color(0.70, 0.45, 0.10, 1) if corruption_total > 0 else Color(1.00, 0.75, 0.25, 1))
	_snap_atk_label(effective_atk)

	# HP — always green; blue tint when shield active.
	if minion.has_shield() and minion.current_shield > 0:
		_hp_label.add_theme_color_override("font_color", Color(0.40, 0.85, 1.00, 1))
		_snap_hp_label("%d+%d" % [minion.current_health, minion.current_shield])
	else:
		_hp_label.add_theme_color_override("font_color", Color(0.35, 1.00, 0.50, 1))
		_snap_hp_label(str(minion.current_health))

	# Buffed-stat highlight: slow pulse on any stat differing from base.
	#   ATK: corruption → debuff dim; above base (no corruption) → buff glow
	#   HP:  current_health above base → buff glow (no HP debuff concept yet)
	var atk_mode: String = ""
	if corruption_total > 0:
		atk_mode = "debuff"
	elif effective_atk > minion.current_atk:
		atk_mode = "buff"
	var hp_mode: String = "buff" if minion.current_health > minion.card_data.health else ""
	_set_buff_glow(_atk_label, atk_mode)
	_set_buff_glow(_hp_label,  hp_mode)

	# Status bar — clear and rebuild each refresh
	_hide_status_tooltip()
	for child in _status_bar.get_children():
		_status_bar.remove_child(child)
		child.queue_free()

	if minion.has_guard():
		_status_bar_add_interactive_icon("icon_guard.png", "GUARD",
			"Must be attacked before other friendly minions.")
	if minion.has_deathless():
		_status_bar_add_interactive_icon("icon_deathless.png", "DEATHLESS",
			"The first time this minion would die, it survives with 1 HP.")
	if minion.has_immune():
		_status_bar_add_interactive_icon("icon_guard.png", "IMMUNE",
			"Cannot take any damage.")
	elif minion.has_spell_immune():
		_status_bar_add_interactive_icon("icon_guard.png", "SPELL IMMUNE",
			"Immune to all spell effects.")
	if minion.has_ethereal():
		_status_bar_add_interactive_icon("icon_ethereal.png", "ETHEREAL",
			"Takes 50% less damage from minion attacks, 50% more from spell effects.")
	if minion.has_pierce():
		_status_bar_add_interactive_icon("icon_pierce.png", "PIERCE",
			"Excess damage from killing a minion carries through to the enemy hero.")
	if minion.has_lifedrain():
		_status_bar_add_interactive_icon("icon_lifedrain.png", "LIFEDRAIN",
			"Damage dealt to the enemy hero heals your hero by the same amount.")
	if minion.has_critical_strike():
		var crit_stacks: int = minion.critical_strike_stacks()
		_status_bar_add_interactive_icon("icon_critical_strike.png", "CRITICAL STRIKE",
			"x%d — Next attack deals double damage. Consumes 1 stack." % crit_stacks)
		_status_bar_add_count("x%d" % crit_stacks, Color(1.00, 0.60, 0.20, 1))
	var mc := minion.card_data as MinionCardData
	if mc.spark_value > 0:
		_status_bar_add_interactive_icon("icon_spirit_fuel.png", "SPIRIT FUEL",
			"Can be consumed to pay %d Spark cost." % mc.spark_value)
		_status_bar_add_count("x%d" % mc.spark_value, Color(0.75, 0.50, 1.00, 1))
	if corruption_total > 0:
		var stacks := corruption_total / 100
		_status_bar_add_interactive_icon("icon_corruption.png", "CORRUPTION",
			"x%d stacks — -%d ATK." % [stacks, corruption_total])
		var _corr_icon: Node = _status_bar.get_child(_status_bar.get_child_count() - 1)
		_corr_icon.name = "corruption_icon"
		_status_bar_add_count("x%d" % stacks, Color(0.85, 0.55, 1.00, 1))
		var _corr_count: Node = _status_bar.get_child(_status_bar.get_child_count() - 1)
		_corr_count.name = "corruption_count"
	var on_death_body := _build_on_death_tooltip_body(minion)
	if not on_death_body.is_empty():
		_status_bar_add_interactive_icon("icon_on_death.png", "ON DEATH", on_death_body)
	if minion.owner == "player" and minion.can_attack():
		_status_bar_add_interactive_icon("icon_ready.png", "READY", "Can attack this turn.")
	elif minion.owner == "player" and minion.state == Enums.MinionState.EXHAUSTED:
		_status_bar_add_interactive_icon("icon_tired.png", "EXHAUSTED", "Cannot attack yet.")

	# Set status bar size from config (always controlled here, not in place_minion)
	var cfg_status: Dictionary = (_CFG_GENERIC if _using_generic else _CFG)["status"]
	_status_bar.size = cfg_status["size"]
	_status_bar.visible = _status_bar.get_child_count() > 0

## Looping modulate-pulse tweens for the ATK/HP labels when the stat is buffed
## or debuffed. Keyed by label so each stat pulses independently. Stopped +
## cleared when the stat returns to base.
##
## Buff pulse brightens toward white ("stat is empowered"); debuff pulse
## dims toward gray ("stat is being drained") — the semantic opposition
## reads clearly without fighting the existing darkened-orange color.
var _buff_glow_tweens: Dictionary = {}

const _BUFF_GLOW_PERIOD: float = 1.2
const _BUFF_GLOW_PEAK: Color   = Color(2.2, 2.2, 2.2, 1.0)   # buff: brighten toward white
const _DEBUFF_GLOW_PEAK: Color = Color(0.55, 0.55, 0.55, 1.0) # debuff: dim toward gray

func _set_buff_glow(lbl: Label, mode: String) -> void:
	# mode: "buff", "debuff", or "" (off)
	if lbl == null:
		return
	var existing: Tween = _buff_glow_tweens.get(lbl, null)
	if mode == "":
		if existing != null and existing.is_valid():
			existing.kill()
		_buff_glow_tweens.erase(lbl)
		lbl.modulate = Color(1, 1, 1, 1)
		return
	# If already pulsing in the same mode, let it continue seamlessly.
	var current_mode: String = _buff_glow_tweens.get("%s_mode" % lbl.get_instance_id(), "")
	if existing != null and existing.is_valid() and current_mode == mode:
		return
	if existing != null and existing.is_valid():
		existing.kill()
	lbl.modulate = Color(1, 1, 1, 1)
	var peak: Color = _BUFF_GLOW_PEAK if mode == "buff" else _DEBUFF_GLOW_PEAK
	var tw := lbl.create_tween().set_loops()
	tw.tween_property(lbl, "modulate", peak, _BUFF_GLOW_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(lbl, "modulate", Color(1, 1, 1, 1), _BUFF_GLOW_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)
	_buff_glow_tweens[lbl] = tw
	_buff_glow_tweens["%s_mode" % lbl.get_instance_id()] = mode

## Resolve the VALID_TARGET glow color — caller-supplied override wins when
## set, otherwise the default green. Override alpha doubles as the "is set"
## flag (Color(0,0,0,0) = unset).
func _valid_target_color() -> Color:
	if _highlight_color_override.a > 0.0:
		return _highlight_color_override
	return Color(0.20, 0.70, 0.25, 1)

func _set_overlay_glow(color: Color) -> void:
	var border_w: float = 3.0 + _pulse_t * 2.5
	var shadow_sz: float = 6.0 + _pulse_t * 8.0
	var shadow_a: float = 0.50 + _pulse_t * 0.30
	var s := StyleBoxFlat.new()
	s.bg_color   = Color(0, 0, 0, 0)
	s.draw_center = false
	s.set_border_width_all(border_w)
	s.border_color = color
	s.set_corner_radius_all(8)
	s.shadow_color = Color(color.r, color.g, color.b, shadow_a)
	s.shadow_size  = shadow_sz
	_overlay.add_theme_stylebox_override("panel", s)

func _clear_overlay() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color    = Color(0, 0, 0, 0)
	s.draw_center = false
	_overlay.add_theme_stylebox_override("panel", s)

func _set_labels_visible(v: bool, generic: bool = false) -> void:
	# Generic frame hides cost and name — only art, status bar, ATK, HP shown
	_cost_label.visible = v and not generic
	if not v or generic:
		_mana_cost_label.visible = false  # shown per-minion only when dual-cost
	_name_label.visible = v and not generic
	_atk_label.visible  = v
	_hp_label.visible   = v
	if not v:
		_status_bar.visible = false

# ---------------------------------------------------------------------------
# Status bar helpers
# ---------------------------------------------------------------------------

## Add an icon wrapped in a hoverable Control that shows a tooltip on mouse-enter.
func _status_bar_add_interactive_icon(filename: String, tip_title: String, tip_body: String) -> void:
	var tex := _load_icon(filename)
	if tex == null:
		return
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(_STATUS_ICON_SIZE, _STATUS_ICON_SIZE)
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	var rect := TextureRect.new()
	rect.texture             = tex
	rect.custom_minimum_size = Vector2(_STATUS_ICON_SIZE, _STATUS_ICON_SIZE)
	rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(rect)
	wrapper.mouse_entered.connect(_on_status_icon_hovered.bind(rect, tip_title, tip_body))
	wrapper.mouse_exited.connect(_on_status_icon_exited.bind(rect))
	_status_bar.add_child(wrapper)

func _status_bar_add_count(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", _STATUS_FONT_SIZE)
	lbl.add_theme_color_override("font_color", color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _bold_font:
		lbl.add_theme_font_override("font", _bold_font)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_bar.add_child(lbl)

## Blink the corruption icon + stack counter in the status bar.
## Call AFTER `_refresh_slot_for` so the status bar is freshly rebuilt with
## the up-to-date stack count and our tagged nodes exist.
func blink_corruption_status() -> void:
	var icon: Control = _status_bar.get_node_or_null("corruption_icon") as Control
	var count: Label  = _status_bar.get_node_or_null("corruption_count") as Label
	_blink_node(icon)
	_blink_node(count)

## Returns the live corruption icon node on the status bar, or null if there
## isn't one. Used by CorruptionDetonationVFX to pulse the real on-card icon
## before the slot is refreshed + stacks consumed.
func get_corruption_icon_node() -> Control:
	if _status_bar == null:
		return null
	return _status_bar.get_node_or_null("corruption_icon") as Control

func _blink_node(node: CanvasItem) -> void:
	if node == null or not is_instance_valid(node):
		return
	var original: Color = node.modulate
	var hot := Color(2.2, 1.1, 2.5, 1.0)  # brighten toward corruption purple
	var tw := node.create_tween()
	tw.tween_property(node, "modulate", hot, 0.08).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "modulate", original, 0.14).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "modulate", hot, 0.08).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "modulate", original, 0.20).set_trans(Tween.TRANS_SINE)

## Flash the ATK label and drop a chevron next to it — signals that this
## minion's ATK just changed from Corruption. Direction depends on whether
## Seris' Corrupt Flesh inversion is active for this minion: friendly Demons
## with the talent gain ATK from Corruption (up-chevron), everyone else loses
## ATK (down-chevron).
func flash_atk_debuff() -> void:
	if _atk_label == null or not is_instance_valid(_atk_label):
		return
	var inverted: bool = MinionInstance.corruption_inverts_on_friendly_demons \
			and minion != null \
			and minion.owner == "player" \
			and minion.card_data is MinionCardData \
			and minion.card_data.minion_type == Enums.MinionType.DEMON
	var flash_color: Color = Color(0.55, 2.4, 0.45, 1.0) if inverted else Color(2.4, 0.35, 0.35, 1.0)
	var original: Color = _atk_label.modulate
	var tw := _atk_label.create_tween()
	tw.tween_property(_atk_label, "modulate", flash_color, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_atk_label, "modulate", original, 0.32).set_trans(Tween.TRANS_SINE)

	if inverted:
		var up_chevron := preload("res://combat/effects/BuffChevronVFX.gd").new()
		add_child(up_chevron)
		up_chevron.set_size(Vector2(14, 16))
		up_chevron.position = _atk_label.position + Vector2(_atk_label.size.x - 10.0, _atk_label.size.y * 0.5 - 8.0)
		up_chevron.play()
	else:
		var chevron := CorruptionChevronVFX.new()
		add_child(chevron)
		chevron.set_size(Vector2(14, 16))
		chevron.position = _atk_label.position + Vector2(_atk_label.size.x - 10.0, _atk_label.size.y * 0.5 - 8.0)
		chevron.play()

## Build the on-death tooltip body for a minion — card description lines + granted effects.
func _build_on_death_tooltip_body(m: MinionInstance) -> String:
	var parts: Array[String] = []
	if m.card_data is MinionCardData:
		var mc := m.card_data as MinionCardData
		# Extract any "ON DEATH" lines from the card description
		for line in mc.description.split("\n"):
			if line.strip_edges().to_upper().begins_with("ON DEATH"):
				parts.append(line.strip_edges())
		# Fallback: card has effect data but no matching description line
		# Skip purely internal HARDCODED steps (e.g. aura cleanup) — not player-visible effects
		var has_visible_death_effect := mc.on_death_effect != ""
		if not has_visible_death_effect:
			for raw in mc.on_death_effect_steps:
				var step_type: String = raw.get("type", "") if raw is Dictionary else ""
				if step_type != "HARDCODED":
					has_visible_death_effect = true
					break
		if parts.is_empty() and has_visible_death_effect:
			parts.append("Triggers an effect on death.")
	for eff in m.granted_on_death_effects:
		var desc: String = eff.get("description", "")
		if not desc.is_empty():
			parts.append(desc)
	return "\n".join(parts)

# ---------------------------------------------------------------------------
# Status bar tooltip — show/hide on icon hover
# ---------------------------------------------------------------------------

func _on_status_icon_hovered(icon: TextureRect, tip_title: String, tip_body: String) -> void:
	icon.modulate = Color(1.5, 1.5, 1.2, 1.0)
	_show_status_tooltip(tip_title, tip_body)

func _on_status_icon_exited(icon: TextureRect) -> void:
	icon.modulate = Color.WHITE
	_hide_status_tooltip()

func _show_status_tooltip(title: String, body: String) -> void:
	if _status_tooltip == null or not is_instance_valid(_status_tooltip):
		_build_status_tooltip_panel()
	var full_text := (title + "\n" + body) if not body.is_empty() else title
	var lbl := _status_tooltip.get_node_or_null("Label") as Label
	if lbl:
		lbl.text = full_text
	# Estimate panel height from line count (wrapping at ~22 chars per line, font size 10)
	var raw_lines := full_text.split("\n")
	var line_count := raw_lines.size()
	for raw in raw_lines:
		line_count += raw.length() / 22  # extra lines from wrapping
	var tip_h := 14 + line_count * 14
	_status_tooltip.size = Vector2(190, tip_h)
	# Position above status bar for player, below for enemy
	var sb_y: int = _CFG_GENERIC["status"]["pos"].y if _using_generic else _CFG["status"]["pos"].y
	if slot_owner == "enemy":
		_status_tooltip.position = Vector2(-5, sb_y + 27)
	else:
		_status_tooltip.position = Vector2(-5, sb_y - tip_h - 4)
	_status_tooltip.visible = true

func _hide_status_tooltip() -> void:
	if _status_tooltip != null and is_instance_valid(_status_tooltip):
		_status_tooltip.visible = false

func _build_status_tooltip_panel() -> void:
	var p := Panel.new()
	p.name = "StatusTooltip"
	p.visible = false
	p.z_index = 20
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color            = Color(0.06, 0.04, 0.10, 0.93)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color                = Color(0.55, 0.40, 0.75, 0.85)
	style.corner_radius_top_left      = 3
	style.corner_radius_top_right     = 3
	style.corner_radius_bottom_left   = 3
	style.corner_radius_bottom_right  = 3
	p.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.name             = "Label"
	lbl.position         = Vector2(7, 5)
	lbl.size             = Vector2(176, 100)
	lbl.autowrap_mode    = TextServer.AUTOWRAP_WORD_SMART
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.98, 1))
	lbl.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	if _bold_font:
		lbl.add_theme_font_override("font", _bold_font)
	p.add_child(lbl)
	add_child(p)
	_status_tooltip = p

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const _ICON_DIR := "res://assets/art/icons/"

func _load_icon(filename: String) -> Texture2D:
	var path := _ICON_DIR + filename
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
