## Targeting.gd
## Target validation, slot highlighting, and the on-play target prompt.
##
## Inputs:  a card or spell in hand, board state on the scene
## Outputs: highlighted BoardSlots, an optional "click a target" prompt label
##
## Owns the prompt label node. Highlighting reads scene state (player_slots,
## enemy_slots, enemy_board, _enemy_status_panel, _enemy_hero_panel) directly
## via the injected _scene reference.
##
## CombatScene keeps thin facade methods (_highlight_slots, _clear_all_highlights,
## _show_target_prompt, etc.) so the heavily-coupled play-card flow stays
## readable without prefixing every call with `targeting.`.
class_name Targeting
extends RefCounted

var _scene: Node2D = null
var prompt_label: Label = null

func _init(scene: Node2D) -> void:
	_scene = scene

## Build the on-play target-prompt label and parent it under $UI.
## Called from CombatScene._find_nodes after $UI is available.
func setup() -> void:
	prompt_label = Label.new()
	prompt_label.text = ""
	prompt_label.add_theme_font_override("font", _scene.DAMAGE_FONT)
	prompt_label.add_theme_font_size_override("font_size", 18)
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	prompt_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	prompt_label.add_theme_constant_override("shadow_offset_x", 2)
	prompt_label.add_theme_constant_override("shadow_offset_y", 2)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.anchors_preset = Control.PRESET_CENTER_TOP
	prompt_label.position = Vector2(960 - 400, 500)
	prompt_label.size = Vector2(800, 50)
	prompt_label.z_index = 90
	prompt_label.visible = false
	_scene.get_node("UI").add_child(prompt_label)

# ---------------------------------------------------------------------------
# Highlighting
# ---------------------------------------------------------------------------

## Apply VALID_TARGET highlight to slots in `slots` matching `filter`.
## color_picker (optional) returns a per-slot glow color (Color(0,0,0,0) = default green).
func highlight_slots(slots: Array, filter: Callable, color_picker: Callable = Callable()) -> void:
	for slot in slots:
		if filter.call(slot):
			var c: Color = Color(0, 0, 0, 0)
			if color_picker.is_valid():
				c = color_picker.call(slot)
			slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET, c)

func clear_all_highlights() -> void:
	for slot in _scene.player_slots:
		slot.clear_highlight()
	for slot in _scene.enemy_slots:
		slot.clear_highlight()
	if _scene._enemy_status_panel and _scene._enemy_status_panel.gui_input.is_connected(_scene._on_enemy_hero_spell_input):
		_scene._enemy_status_panel.gui_input.disconnect(_scene._on_enemy_hero_spell_input)
		_scene._enemy_hero_panel.stop_spell_pulse()
	if _scene._enemy_status_panel and _scene._enemy_status_panel.gui_input.is_connected(_scene._on_relic_target_hero_input):
		_scene._enemy_status_panel.gui_input.disconnect(_scene._on_relic_target_hero_input)
		_scene._enemy_hero_panel.stop_spell_pulse()
	_scene._enemy_hero_panel.show_attackable(false)

func highlight_empty_player_slots() -> void:
	clear_all_highlights()
	highlight_slots(_scene.player_slots, func(s): return s.is_empty())

func highlight_valid_attack_targets() -> void:
	clear_all_highlights()
	if _scene.selected_attacker == null:
		return
	for slot in _scene.player_slots:
		if slot.minion == _scene.selected_attacker:
			slot.set_highlight(BoardSlot.HighlightMode.SELECTED)
			break
	var has_taunt := CombatManager.board_has_taunt(_scene.enemy_board)
	for slot in _scene.enemy_slots:
		if slot.is_empty():
			continue
		var valid: bool = (not has_taunt) or slot.minion.has_guard()
		slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET if valid else BoardSlot.HighlightMode.INVALID)
	_scene._enemy_hero_panel.show_attackable(not has_taunt and _scene.selected_attacker.can_attack_hero())

func highlight_minion_on_play_targets(card: MinionCardData) -> void:
	clear_all_highlights()
	var target_type: String = effective_target_type(card)
	var hits_enemy    := target_type in ["enemy_minion", "corrupted_enemy_minion"]
	var hits_friendly := target_type in ["friendly_minion", "friendly_minion_other", "friendly_demon"]
	if hits_enemy:
		highlight_slots(_scene.enemy_slots,  func(s): return not s.is_empty() and is_valid_minion_on_play_target(s.minion, target_type))
	if hits_friendly:
		highlight_slots(_scene.player_slots, func(s): return not s.is_empty() and is_valid_minion_on_play_target(s.minion, target_type))

func highlight_spell_targets(spell: SpellCardData) -> void:
	clear_all_highlights()
	if spell.target_type == "trap_or_env":
		_scene._setup_trap_env_targeting()
		return
	var hits_friendly := spell.target_type in ["friendly_minion", "friendly_human", "friendly_demon", "friendly_human_or_demon", "friendly_void_imp", "friendly_feral_imp", "any_minion", "any_minion_or_enemy_hero"]
	var hits_enemy    := spell.target_type in ["enemy_minion", "any_minion", "enemy_minion_or_hero", "any_minion_or_enemy_hero"]
	var hits_hero     := spell.target_type in ["enemy_minion_or_hero", "any_minion_or_enemy_hero"]
	var color_picker: Callable = spell_highlight_color_picker(spell)
	if hits_friendly:
		highlight_slots(
			_scene.player_slots,
			func(s): return not s.is_empty() and is_valid_spell_target(s.minion, spell.target_type),
			color_picker)
	if hits_enemy:
		highlight_slots(_scene.enemy_slots, func(s): return not s.is_empty(), color_picker)
	if hits_hero and _scene._enemy_status_panel:
		_scene._enemy_status_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_scene._enemy_status_panel.gui_input.connect(_scene._on_enemy_hero_spell_input)
		_scene._enemy_hero_panel.start_spell_pulse()

## Per-spell color picker for the VALID_TARGET highlight. Returns a Callable
## mapping a BoardSlot to a glow color (or Color(0,0,0,0) for the default
## green). Used to telegraph spell-specific conditional behavior — e.g. Dark
## Empowerment marks Demon targets in violet.
func spell_highlight_color_picker(spell: SpellCardData) -> Callable:
	match spell.id:
		"dark_empowerment":
			var demon_color := Color(0.70, 0.30, 1.00, 1.0)
			return func(s: BoardSlot) -> Color:
				if s.minion != null and (s.minion.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
					return demon_color
				return Color(0, 0, 0, 0)
		_:
			return Callable()

## Apply the SELECTED highlight to the slot holding `minion`. Used by the
## optional-target flow after a target is clicked.
func mark_selected_target(minion: MinionInstance) -> void:
	var slot: BoardSlot = _scene._find_slot_for(minion)
	if slot != null:
		slot.set_highlight(BoardSlot.HighlightMode.SELECTED)

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

func has_valid_minion_on_play_targets(card: MinionCardData) -> bool:
	return has_valid_minion_on_play_targets_for(card.on_play_target_type)

func has_valid_minion_on_play_targets_for(target_type: String) -> bool:
	if target_type.is_empty():
		return false
	var hits_enemy    := target_type in ["enemy_minion", "corrupted_enemy_minion"]
	var hits_friendly := target_type in ["friendly_minion", "friendly_minion_other", "friendly_demon"]
	if hits_enemy:
		for slot in _scene.enemy_slots:
			if not slot.is_empty() and is_valid_minion_on_play_target(slot.minion, target_type):
				return true
	if hits_friendly:
		for slot in _scene.player_slots:
			if not slot.is_empty() and is_valid_minion_on_play_target(slot.minion, target_type):
				return true
	return false

func is_valid_minion_on_play_target(minion: MinionInstance, target_type: String) -> bool:
	match target_type:
		"enemy_minion":           return true
		"corrupted_enemy_minion": return BuffSystem.has_type(minion, Enums.BuffType.CORRUPTION)
		"friendly_minion":        return true
		"friendly_minion_other":  return true
		"friendly_demon":
			return minion != null and minion.card_data is MinionCardData \
				and (minion.card_data as MinionCardData).is_race(Enums.MinionType.DEMON)
	return false

func is_valid_spell_target(minion: MinionInstance, target_type: String) -> bool:
	match target_type:
		"friendly_human":    return (minion.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN)
		"friendly_demon":    return (minion.card_data as MinionCardData).is_race(Enums.MinionType.DEMON)
		"friendly_human_or_demon":
			# Rally the Ranks — Human OR Demon (either via primary minion_type or via
			# extra_minion_types, since is_race covers both). Dual-tag minions like
			# Squire of the Order or Abyssal Knight under runeforge_strike match.
			var mc := minion.card_data as MinionCardData
			return mc != null and (mc.is_race(Enums.MinionType.HUMAN) or mc.is_race(Enums.MinionType.DEMON))
		"friendly_minion":   return true
		"friendly_void_imp": return _scene._minion_has_tag(minion, "void_imp")
		"friendly_feral_imp": return _scene._minion_has_tag(minion, "feral_imp")
		"enemy_minion":           return true
		"any_minion":             return true
		"any_minion_or_enemy_hero": return true
		"enemy_minion_or_hero":     return minion.owner == "enemy"
	return false

# ---------------------------------------------------------------------------
# Talent-gated card-targeting overrides
# ---------------------------------------------------------------------------

func effective_target_type(mc: MinionCardData) -> String:
	if mc == null:
		return ""
	if mc.id == "grafted_fiend" and _scene._has_talent("grafting_ritual"):
		return "friendly_demon"
	return mc.on_play_target_type

func effective_target_optional(mc: MinionCardData) -> bool:
	if mc == null:
		return false
	if mc.id == "grafted_fiend" and _scene._has_talent("grafting_ritual"):
		return true
	return mc.on_play_target_optional

func effective_target_prompt(mc: MinionCardData) -> String:
	if mc == null:
		return ""
	if mc.id == "grafted_fiend" and _scene._has_talent("grafting_ritual"):
		return "Click a Demon to transform into a Grafted Fiend, or click a slot to summon without effect."
	return mc.on_play_target_prompt

# ---------------------------------------------------------------------------
# Prompt label
# ---------------------------------------------------------------------------

## Fade-in the prompt with the given text. Empty text → hide.
func show_prompt(text: String) -> void:
	if prompt_label == null:
		return
	if text.is_empty():
		hide_prompt()
		return
	prompt_label.text = text
	if prompt_label.visible and prompt_label.modulate.a > 0.9:
		return
	prompt_label.visible = true
	prompt_label.modulate = Color(1, 1, 1, 0)
	var tw := _scene.create_tween()
	tw.tween_property(prompt_label, "modulate:a", 1.0, 0.2)

func hide_prompt() -> void:
	if prompt_label == null or not prompt_label.visible:
		return
	var tw := _scene.create_tween()
	tw.tween_property(prompt_label, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func() -> void: prompt_label.visible = false)
