## BalanceSim.gd
## Interactive balance simulator — runs inside the Godot editor.
## Select an Act 1 enemy, a player deck (preset or custom), hero talents,
## set the run count, then click Run.
##
## How to open: run res://debug/BalanceSim.tscn from the editor
## or navigate to it from TestLaunchScene.
extends Control

# ---------------------------------------------------------------------------
# Act 1 fight configs  (mirrors GameManager._make_encounter calls)
# ---------------------------------------------------------------------------
const _FIGHTS: Array = [
	{"label": "Fight 1  —  Rogue Imp Pack",      "hp": 1800, "profile": "feral_pack",       "encounter": 1, "talent_points": 1},
	{"label": "Fight 2  —  Corrupted Broodlings", "hp": 2400, "profile": "corrupted_brood",  "encounter": 2, "talent_points": 1},
	{"label": "Fight 3  —  Imp Matriarch",         "hp": 3500, "profile": "matriarch",        "encounter": 3, "talent_points": 1},
]

# ---------------------------------------------------------------------------
# Preset player decks  — sourced from PresetDecks (cards/data/PresetDecks.gd)
# ---------------------------------------------------------------------------
const _PRESETS: Array = PresetDecks.DECKS

# ---------------------------------------------------------------------------
# Branch ID → display name  (matches HeroData.talent_branch_ids values)
# ---------------------------------------------------------------------------
const _BRANCH_DISPLAY: Dictionary = {
	"swarm":       "Endless Tide",
	"rune_master": "Rune Master",
	"void_bolt":   "Void Resonance",
}

# ---------------------------------------------------------------------------
# Player AI profiles
# ---------------------------------------------------------------------------
const _PLAYER_PROFILES: Array = [
	{"id": "default",    "name": "Aggro / Swarm"},
	{"id": "spell_burn", "name": "Spell Burn"},
	{"id": "rune_tempo", "name": "Rune Tempo"},
]

# ---------------------------------------------------------------------------
# Talent tree  (Lord Vael, all branches)
# tier: int  —  0 = entry point, requires 0 prior points in branch
# requires: "" = no prerequisite, otherwise the talent_id that must be active
# ---------------------------------------------------------------------------
const _TALENTS: Array = [
	# ── Endless Tide ─────────────────────────────────────────────────────
	{"id":"imp_evolution",   "name":"Imp Evolution",   "branch":"Endless Tide",  "tier":0, "req":""},
	{"id":"swarm_discipline","name":"Swarm Discipline", "branch":"Endless Tide",  "tier":1, "req":"imp_evolution"},
	{"id":"imp_warband",     "name":"Imp Warband",      "branch":"Endless Tide",  "tier":2, "req":"swarm_discipline"},
	{"id":"void_echo",       "name":"Void Echo",        "branch":"Endless Tide",  "tier":3, "req":"imp_warband"},
	# ── Rune Master ──────────────────────────────────────────────────────
	{"id":"rune_caller",     "name":"Rune Caller",      "branch":"Rune Master",   "tier":0, "req":""},
	{"id":"runic_attunement","name":"Runic Attunement", "branch":"Rune Master",   "tier":1, "req":"rune_caller"},
	{"id":"ritual_surge",    "name":"Ritual Surge",     "branch":"Rune Master",   "tier":2, "req":"runic_attunement"},
	{"id":"abyss_convergence","name":"Abyss Convergence","branch":"Rune Master",  "tier":3, "req":"ritual_surge"},
	# ── Void Resonance ───────────────────────────────────────────────────
	{"id":"piercing_void",      "name":"Piercing Void",      "branch":"Void Resonance","tier":0,"req":""},
	{"id":"deepened_curse",     "name":"Deepened Curse",     "branch":"Void Resonance","tier":1,"req":"piercing_void"},
	{"id":"death_bolt",         "name":"Death Bolt",         "branch":"Void Resonance","tier":2,"req":"deepened_curse"},
	{"id":"void_manifestation", "name":"Void Manifestation", "branch":"Void Resonance","tier":3,"req":"death_bolt"},
]

# ---------------------------------------------------------------------------
# UI node references
# ---------------------------------------------------------------------------

var _fight_buttons:        Array[Button]  = []
var _profile_buttons:      Array[Button]  = []
var _hero_buttons:         Dictionary     = {}  # hero_id -> Button
var _hero_passives_label:  Label
var _deck_dropdown:        OptionButton
var _deck_cards:           Array          = []  # parallel to dropdown items: Array of Array[String]
var _enemy_deck_dropdown:  OptionButton         # "Encounter Deck" + saved enemy deck names
var _talent_checks:        Dictionary     = {}  # talent_id -> CheckBox
var _branch_cols:          Dictionary     = {}  # branch display name -> VBoxContainer
var _talent_points_label:  Label
var _runs_input:           SpinBox
var _run_button:           Button
var _clear_button:         Button
var _log:                  RichTextLabel

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _fight_idx: int            = 0
var _points_used: int          = 0
var _player_profile_id: String = "default"
var _selected_hero_id: String  = "lord_vael"

# ---------------------------------------------------------------------------
# Theme colours
# ---------------------------------------------------------------------------

const _C_BG       := Color(0.06, 0.06, 0.10)
const _C_PANEL    := Color(0.09, 0.09, 0.15)
const _C_SECTION  := Color(0.12, 0.12, 0.20)
const _C_BTN_SEL  := Color(0.30, 0.22, 0.55)
const _C_BTN_NRM  := Color(0.16, 0.16, 0.26)
const _C_LOG      := Color(0.04, 0.04, 0.08)
const _C_TEXT     := Color(0.80, 0.80, 0.92)
const _C_DIM      := Color(0.50, 0.50, 0.65)
const _C_GREEN    := Color(0.40, 0.90, 0.55)
const _C_RED      := Color(0.95, 0.40, 0.40)
const _C_GOLD     := Color(0.95, 0.82, 0.45)

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	_select_hero("lord_vael")
	_select_fight(0)
	_select_profile(0)

func _build_ui() -> void:
	# Full-rect background
	var bg := ColorRect.new()
	bg.color = _C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Root vbox: title bar + body
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# ── Title bar ──────────────────────────────────────────────────────────
	var title_bar := _panel(_C_PANEL)
	title_bar.custom_minimum_size.y = 40
	root.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "  Balance Simulator  —  Act 1"
	title_lbl.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	title_lbl.offset_left  = 8
	title_lbl.offset_right = 500
	title_bar.add_child(title_lbl)

	# ── Body: left controls | right log ────────────────────────────────────
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 380
	root.add_child(split)

	# Left panel
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 360
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 352
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	scroll.add_child(left)

	_build_hero_section(left)
	_build_enemy_section(left)
	_build_enemy_deck_section(left)
	_build_deck_section(left)
	_build_profile_section(left)
	_build_talent_section(left)
	_build_run_section(left)

	# Right panel — log
	var log_bg := _panel(_C_LOG)
	log_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_bg.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	split.add_child(log_bg)

	_log = RichTextLabel.new()
	_log.bbcode_enabled  = true
	_log.scroll_following = true
	_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log.offset_left   = 10
	_log.offset_top    = 10
	_log.offset_right  = -10
	_log.offset_bottom = -10
	log_bg.add_child(_log)

	_log.append_text("[color=#555]Balance Simulator ready. Select fight, deck, talents and click Run.[/color]\n")


# ---------------------------------------------------------------------------
# Section builders
# ---------------------------------------------------------------------------

func _build_hero_section(parent: Control) -> void:
	parent.add_child(_section_header("HERO"))
	var vbox := _section_body(parent)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	for hero: HeroData in HeroDatabase.get_all_heroes():
		var btn := _flat_button(hero.hero_name)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_select_hero.bind(hero.id))
		btn_row.add_child(btn)
		_hero_buttons[hero.id] = btn

	_hero_passives_label = _label("", _C_DIM)
	_hero_passives_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hero_passives_label)


func _build_enemy_section(parent: Control) -> void:
	parent.add_child(_section_header("ENEMY"))
	var vbox := _section_body(parent)

	for i in _FIGHTS.size():
		var fight: Dictionary = _FIGHTS[i]
		var btn   := _flat_button(fight.label)
		btn.pressed.connect(_select_fight.bind(i))
		vbox.add_child(btn)
		_fight_buttons.append(btn)


func _build_enemy_deck_section(parent: Control) -> void:
	parent.add_child(_section_header("ENEMY DECK"))
	var vbox := _section_body(parent)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	_enemy_deck_dropdown = OptionButton.new()
	_enemy_deck_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_enemy_deck_dropdown)

	var edit_btn := _flat_button("Edit Decks →")
	edit_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	edit_btn.pressed.connect(func(): GameManager.go_to_scene("res://debug/EnemyDeckBuilder.tscn"))
	row.add_child(edit_btn)

	_rebuild_enemy_deck_dropdown()


func _rebuild_enemy_deck_dropdown() -> void:
	if _enemy_deck_dropdown == null:
		return
	_enemy_deck_dropdown.clear()
	_enemy_deck_dropdown.add_item("Encounter Deck")
	var saved := EnemySavedDecks.load_all()
	var names: Array = saved.keys()
	names.sort()
	for name in names:
		if not (name as String).begins_with("encounter_"):
			_enemy_deck_dropdown.add_item(name as String)


func _build_deck_section(parent: Control) -> void:
	parent.add_child(_section_header("PLAYER DECK"))
	var vbox := _section_body(parent)

	_deck_dropdown = OptionButton.new()
	_deck_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_deck_dropdown)

	_rebuild_deck_dropdown()

func _rebuild_deck_dropdown() -> void:
	_deck_cards.clear()
	_deck_dropdown.clear()

	for preset: Dictionary in _PRESETS:
		var preset_hero: String = preset.get("hero", "") as String
		if not preset_hero.is_empty() and preset_hero != _selected_hero_id:
			continue
		_deck_cards.append(preset.cards)
		_deck_dropdown.add_item(preset.name as String)

	var saved: Dictionary = SavedDecks.load_all()
	if not saved.is_empty():
		var names: Array = saved.keys()
		names.sort()
		for deck_name: String in names:
			_deck_cards.append(saved[deck_name] as Array)
			_deck_dropdown.add_item("★ " + deck_name)

	if _deck_dropdown.item_count > 0:
		_deck_dropdown.select(0)


func _build_profile_section(parent: Control) -> void:
	parent.add_child(_section_header("PLAYER PROFILE"))
	var vbox := _section_body(parent)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vbox.add_child(row)

	for i in _PLAYER_PROFILES.size():
		var profile: Dictionary = _PLAYER_PROFILES[i]
		var btn := _flat_button(profile.name)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_select_profile.bind(i))
		row.add_child(btn)
		_profile_buttons.append(btn)


func _build_talent_section(parent: Control) -> void:
	parent.add_child(_section_header("TALENTS"))
	var vbox := _section_body(parent)

	_talent_points_label = _label("", _C_GOLD)
	vbox.add_child(_talent_points_label)

	# 3-column grid: one column per branch
	var branches := ["Endless Tide", "Rune Master", "Void Resonance"]
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(cols)

	for branch in branches:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		cols.add_child(col)
		_branch_cols[branch] = col  # store for hero-based visibility

		var branch_lbl := _label(branch, _C_GOLD)
		branch_lbl.add_theme_font_size_override("font_size", 11)
		col.add_child(branch_lbl)

		for talent in _TALENTS:
			if talent.branch != branch:
				continue
			var cb := CheckBox.new()
			cb.text = "  T%d  %s" % [talent.tier, talent.name]
			cb.add_theme_color_override("font_color", _C_TEXT)
			cb.add_theme_color_override("font_disabled_color", _C_DIM)
			cb.toggled.connect(_on_talent_toggled.bind(talent.id))
			col.add_child(cb)
			_talent_checks[talent.id] = cb


func _build_run_section(parent: Control) -> void:
	parent.add_child(_section_header("RUN"))
	var vbox := _section_body(parent)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	row.add_child(_label("Simulations:", _C_DIM))

	_runs_input = SpinBox.new()
	_runs_input.min_value = 10
	_runs_input.max_value = 5000
	_runs_input.step      = 50
	_runs_input.value     = 200
	_runs_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_runs_input)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_run_button = Button.new()
	_run_button.text = "Run Simulation"
	_run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_button.pressed.connect(_on_run_pressed)
	btn_row.add_child(_run_button)

	_clear_button = Button.new()
	_clear_button.text = "Clear"
	_clear_button.pressed.connect(func(): _log.clear())
	btn_row.add_child(_clear_button)

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _select_hero(id: String) -> void:
	_selected_hero_id = id
	for hid in _hero_buttons:
		_style_button(_hero_buttons[hid] as Button, hid == id)
	var hero: HeroData = HeroDatabase.get_hero(id)
	if hero != null and _hero_passives_label != null:
		var lines: Array[String] = []
		for p in hero.passives:
			lines.append((p as HeroPassive).description)
		_hero_passives_label.text = "\n".join(lines)
	_refresh_talent_branches()
	_rebuild_deck_dropdown()


func _refresh_talent_branches() -> void:
	var hero: HeroData = HeroDatabase.get_hero(_selected_hero_id)
	if hero == null or _branch_cols.is_empty():
		return
	var active_displays: Array[String] = []
	for branch_id in hero.talent_branch_ids:
		var display: String = _BRANCH_DISPLAY.get(branch_id, "") as String
		if not display.is_empty():
			active_displays.append(display)
	for display_name in _branch_cols:
		var col: VBoxContainer = _branch_cols[display_name] as VBoxContainer
		var is_active: bool = display_name in active_displays
		col.visible = is_active
		if not is_active:
			for talent in _TALENTS:
				if talent.branch == display_name:
					(_talent_checks[talent.id] as CheckBox).set_pressed_no_signal(false)
			_points_used = _count_checked()
	_refresh_talent_ui()


func _select_fight(idx: int) -> void:
	_fight_idx = idx
	for i in _fight_buttons.size():
		_style_button(_fight_buttons[i], i == idx)
	_clamp_talents_to_budget()
	_refresh_talent_ui()

func _select_profile(idx: int) -> void:
	_player_profile_id = (_PLAYER_PROFILES[idx] as Dictionary).id as String
	for i in _profile_buttons.size():
		_style_button(_profile_buttons[i], i == idx)

func _on_talent_toggled(pressed: bool, talent_id: String) -> void:
	var check: CheckBox = _talent_checks[talent_id]
	if pressed:
		# Recount after toggling on
		_points_used = _count_checked()
		var points_available: int = (_FIGHTS[_fight_idx] as Dictionary).get("talent_points", 1) as int
		if _points_used > points_available:
			# Over budget — undo
			check.set_pressed_no_signal(false)
			_points_used = _count_checked()
	else:
		_points_used = _count_checked()
		# Uncheck any talents that now have a broken prerequisite
		_cascade_uncheck(talent_id)

	_refresh_talent_ui()

func _cascade_uncheck(removed_id: String) -> void:
	for talent in _TALENTS:
		if talent.req == removed_id:
			var cb: CheckBox = _talent_checks[talent.id]
			if cb.button_pressed:
				cb.set_pressed_no_signal(false)
				_cascade_uncheck(talent.id)
	_points_used = _count_checked()

func _clamp_talents_to_budget() -> void:
	var limit: int = (_FIGHTS[_fight_idx] as Dictionary).get("talent_points", 1) as int
	# Uncheck all talents that now exceed point budget or have broken prerequisites
	# Simple approach: if checked count > limit, uncheck from highest tier down
	var checked_ids: Array[String] = _get_checked_ids()
	while _count_checked() > limit:
		# Remove highest-tier checked talent first
		var highest_tier: int    = -1
		var highest_id:   String = ""
		for tid in checked_ids:
			for t in _TALENTS:
				if t.id == tid and (t.tier as int) > highest_tier:
					highest_tier = t.tier
					highest_id   = tid
		if highest_id.is_empty(): break
		(_talent_checks[highest_id] as CheckBox).set_pressed_no_signal(false)
		checked_ids.erase(highest_id)
	_points_used = _count_checked()

func _refresh_talent_ui() -> void:
	var points_available: int = (_FIGHTS[_fight_idx] as Dictionary).get("talent_points", 1) as int
	_points_used = _count_checked()
	_talent_points_label.text = "Points: %d / %d" % [_points_used, points_available]

	var checked_ids := _get_checked_ids()

	for talent in _TALENTS:
		var cb: CheckBox = _talent_checks[talent.id]
		var req_met: bool   = (talent.req as String).is_empty() or ((talent.req as String) in checked_ids)
		var tier_ok: bool   = (talent.tier as int) <= points_available
		var can_check: bool = req_met and tier_ok and (_points_used < points_available or cb.button_pressed)
		cb.disabled = not can_check

# ---------------------------------------------------------------------------
# Sim runner
# ---------------------------------------------------------------------------

func _on_run_pressed() -> void:
	var fight: Dictionary = _FIGHTS[_fight_idx]
	var talents  := _get_checked_ids()
	var runs     := int(_runs_input.value)

	var sel_idx  := _deck_dropdown.selected
	var raw_cards: Array = _deck_cards[sel_idx] if sel_idx >= 0 and sel_idx < _deck_cards.size() else []
	var deck_ids: Array[String] = []
	for c in raw_cards:
		deck_ids.append(c as String)

	if deck_ids.is_empty():
		_log.append_text("[color=#f66]Player deck is empty — select a deck from the dropdown.[/color]\n")
		return

	# Collect hero passives
	var hero_passives: Array[String] = []
	var hero: HeroData = HeroDatabase.get_hero(_selected_hero_id)
	if hero != null:
		for p in hero.passives:
			hero_passives.append((p as HeroPassive).id)

	_run_button.disabled = true
	_clear_button.disabled = true

	_log.append_text("\n")
	var hero_name: String = hero.hero_name if hero != null else _selected_hero_id
	var profile_name: String = (_PLAYER_PROFILES[0] as Dictionary).name as String
	for p in _PLAYER_PROFILES:
		if (p as Dictionary).id == _player_profile_id:
			profile_name = (p as Dictionary).name as String
	var deck_name: String = _deck_dropdown.get_item_text(sel_idx)
	var enemy_deck_label: String = _enemy_deck_dropdown.get_item_text(_enemy_deck_dropdown.selected)
	_log.append_text("[color=#ccb]Running %d sims  vs  [b]%s[/b]  (enemy deck: %s)  [Hero: %s]  [Deck: %s]  [Profile: %s][/color]\n" % [runs, fight.label, enemy_deck_label, hero_name, deck_name, profile_name])
	if not talents.is_empty():
		_log.append_text("[color=#aaa]  Talents: %s[/color]\n" % ", ".join(talents))
	if not hero_passives.is_empty():
		_log.append_text("[color=#aaa]  Hero passives: %s[/color]\n" % ", ".join(hero_passives))

	# Enemy deck: custom saved deck if selected, otherwise use encounter deck (override or default)
	var enemy_deck: Array[String] = []
	var enemy_deck_sel := _enemy_deck_dropdown.selected
	if enemy_deck_sel > 0:
		var enemy_deck_name: String = _enemy_deck_dropdown.get_item_text(enemy_deck_sel)
		var saved_enemy := EnemySavedDecks.load_all()
		if enemy_deck_name in saved_enemy:
			for id in (saved_enemy[enemy_deck_name] as Array):
				enemy_deck.append(id as String)
	if enemy_deck.is_empty():
		var enc_idx: int = (fight as Dictionary).get("encounter", _fight_idx) as int
		var enc: EnemyData = GameManager.get_encounter(enc_idx)
		if enc != null:
			for id in enc.deck:
				enemy_deck.append(id as String)

	var sim   := CombatSim.new()
	var stats: Dictionary = await sim.run_many(
			runs,
			deck_ids,
			fight.profile as String,
			enemy_deck,
			3000,
			fight.hp as int,
			talents,
			_player_profile_id,
			hero_passives)

	_print_results(fight.label, stats)

	_run_button.disabled  = false
	_clear_button.disabled = false

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

func _print_results(label: String, s: Dictionary) -> void:
	var win_pct:  float = s.win_rate * 100.0
	var loss_pct: float = float(s.losses) / s.count * 100.0
	var draw_pct: float = float(s.draws)  / s.count * 100.0

	var win_col: String = "[color=#6f6]" if win_pct >= 50.0 else "[color=#f66]"

	_log.append_text("[b]%s[/b]  (n=%d)\n" % [label, s.count])
	_log.append_text("  %sWin %.1f%%[/color]   Loss %.1f%%   Draw %.1f%%\n" % [win_col, win_pct, loss_pct, draw_pct])
	_log.append_text("  Avg turns: [b]%.1f[/b]   Avg player HP: [b]%+.0f[/b]   Avg enemy HP: [b]%+.0f[/b]\n" % [
		s.avg_turns, s.avg_player_hp, s.avg_enemy_hp])

# ---------------------------------------------------------------------------
# Helpers — state queries
# ---------------------------------------------------------------------------

func _count_checked() -> int:
	var n := 0
	for cb in _talent_checks.values():
		if (cb as CheckBox).button_pressed: n += 1
	return n

func _get_checked_ids() -> Array[String]:
	var out: Array[String] = []
	for tid in _talent_checks:
		if (_talent_checks[tid] as CheckBox).button_pressed:
			out.append(tid)
	return out

func _parse_ids(text: String) -> Array[String]:
	var out: Array[String] = []
	for part in text.split(","):
		var id := part.strip_edges()
		if not id.is_empty():
			out.append(id)
	return out

# ---------------------------------------------------------------------------
# UI factory helpers
# ---------------------------------------------------------------------------

func _section_header(title: String) -> Control:
	var p     := _panel(_C_SECTION)
	p.custom_minimum_size.y = 28
	var lbl   := Label.new()
	lbl.text  = "  " + title
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
	style.bg_color              = _C_PANEL
	style.set_content_margin_all(10)
	wrapper.add_theme_stylebox_override("panel", style)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(wrapper)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(vbox)
	return vbox

func _flat_button(text: String) -> Button:
	var btn          := Button.new()
	btn.text          = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.flat          = false
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
