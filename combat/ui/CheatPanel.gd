## CheatPanel.gd
## Debug overlay (F12 toggle) for combat testing.
## Add cards, damage/heal heroes, unlock talents, grant relics, switch encounters.
class_name CheatPanel
extends CanvasLayer

var _scene: Node2D  ## CombatScene reference

var _visible_state: bool = false
var _card_input: LineEdit
var _dmg_input: SpinBox
var _status_lbl: Label
var _talent_dropdown: OptionButton
var _relic_dropdown: OptionButton
var _enemy_dropdown: OptionButton

func setup(scene: Node2D) -> void:
	_scene = scene
	layer = 128
	_build_ui()
	visible = false

func toggle() -> void:
	_visible_state = not _visible_state
	visible = _visible_state
	if _visible_state and _card_input:
		_card_input.call_deferred("grab_focus")

func rebuild_talent_tooltip() -> void:
	var tip_vbox: VBoxContainer = _scene._talent_tip_vbox
	if tip_vbox == null:
		return
	var found_talents := false
	var to_remove: Array[Node] = []
	for child in tip_vbox.get_children():
		if child is Label and (child as Label).text == "TALENTS":
			found_talents = true
			continue
		if found_talents:
			to_remove.append(child)
	for child in to_remove:
		child.queue_free()
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
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 3)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tip_vbox.add_child(row)
			var t_name := Label.new()
			t_name.text = td.talent_name
			t_name.add_theme_font_size_override("font_size", 15)
			t_name.add_theme_color_override("font_color", Color(0.92, 0.85, 1.0, 1))
			t_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t_name.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			row.add_child(t_name)
			var t_desc := Label.new()
			t_desc.text = td.description
			t_desc.add_theme_font_size_override("font_size", 12)
			t_desc.add_theme_color_override("font_color", Color(0.65, 0.62, 0.72, 1))
			t_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t_desc.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			row.add_child(t_desc)

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(300, 0)
	var vp_w: float = get_viewport().get_visible_rect().size.x
	root.set_position(Vector2(vp_w - 520, 10))
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "⚙ Cheat Panel  [F12]"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Add card to hand
	var hand_label := Label.new()
	hand_label.text = "Add card to hand (ID):"
	hand_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hand_label)

	var hand_row := HBoxContainer.new()
	vbox.add_child(hand_row)
	_card_input = LineEdit.new()
	_card_input.placeholder_text = "e.g. arcane_strike"
	_card_input.custom_minimum_size = Vector2(200, 0)
	_card_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_input.text_submitted.connect(func(_t): _add_card())
	hand_row.add_child(_card_input)
	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(_add_card)
	hand_row.add_child(add_btn)

	vbox.add_child(HSeparator.new())

	# Damage / heal heroes
	var dmg_label := Label.new()
	dmg_label.text = "Damage / Heal heroes:"
	dmg_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(dmg_label)

	var dmg_row := HBoxContainer.new()
	vbox.add_child(dmg_row)
	_dmg_input = SpinBox.new()
	_dmg_input.min_value = 0
	_dmg_input.max_value = 99999
	_dmg_input.value     = 500
	_dmg_input.step      = 100
	_dmg_input.custom_minimum_size = Vector2(110, 0)
	dmg_row.add_child(_dmg_input)

	# Cheat buttons route through combat_manager.apply_hero_damage so the full
	# pipeline (signals, triggers, VFX) runs — same path as in-game damage.
	# Tagged with source_card="cheat_panel" for log attribution.
	var dmg_player := Button.new()
	dmg_player.text = "Dmg Player"
	dmg_player.pressed.connect(func():
		_scene.combat_manager.apply_hero_damage("player",
				CombatManager.make_damage_info(int(_dmg_input.value), Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "cheat_panel")))
	dmg_row.add_child(dmg_player)

	var dmg_enemy := Button.new()
	dmg_enemy.text = "Dmg Enemy"
	dmg_enemy.pressed.connect(func():
		_scene.combat_manager.apply_hero_damage("enemy",
				CombatManager.make_damage_info(int(_dmg_input.value), Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "cheat_panel")))
	dmg_row.add_child(dmg_enemy)

	var kill_enemy := Button.new()
	kill_enemy.text = "Kill Enemy (5000)"
	kill_enemy.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
	kill_enemy.pressed.connect(func():
		_scene.combat_manager.apply_hero_damage("enemy",
				CombatManager.make_damage_info(5000, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "cheat_panel")))
	dmg_row.add_child(kill_enemy)

	var heal_row := HBoxContainer.new()
	vbox.add_child(heal_row)
	var heal_player := Button.new()
	heal_player.text = "Heal Player"
	heal_player.pressed.connect(func(): _scene._on_hero_healed("player", int(_dmg_input.value)))
	heal_row.add_child(heal_player)

	var heal_enemy := Button.new()
	heal_enemy.text = "Heal Enemy"
	heal_enemy.pressed.connect(func(): _scene._on_hero_healed("enemy", int(_dmg_input.value)))
	heal_row.add_child(heal_enemy)

	vbox.add_child(HSeparator.new())

	# Resources
	var res_btn := Button.new()
	res_btn.text = "Refill Resources (Essence + Mana)"
	res_btn.pressed.connect(func():
		_scene.turn_manager.gain_essence(_scene.turn_manager.essence_max)
		_scene.turn_manager.gain_mana(_scene.turn_manager.mana_max))
	vbox.add_child(res_btn)

	vbox.add_child(HSeparator.new())

	# VFX time scale — multiplier on every VfxSequence phase duration.
	# 1.0 = real-time. 2.0 = half-speed (phases are 2x longer). 0.5 = double-speed.
	var vfx_label := Label.new()
	vfx_label.text = "VFX time scale (>1 = slower):"
	vfx_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(vfx_label)

	var vfx_row := HBoxContainer.new()
	vbox.add_child(vfx_row)
	var vfx_slider := HSlider.new()
	vfx_slider.min_value = 0.25
	vfx_slider.max_value = 4.0
	vfx_slider.step = 0.25
	vfx_slider.value = BaseVfx.time_scale
	vfx_slider.custom_minimum_size = Vector2(180, 0)
	vfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vfx_val_lbl := Label.new()
	vfx_val_lbl.text = "%.2fx" % BaseVfx.time_scale
	vfx_val_lbl.custom_minimum_size = Vector2(50, 0)
	vfx_slider.value_changed.connect(func(v: float) -> void:
		BaseVfx.time_scale = v
		vfx_val_lbl.text = "%.2fx" % v)
	vfx_row.add_child(vfx_slider)
	vfx_row.add_child(vfx_val_lbl)

	vbox.add_child(HSeparator.new())

	# Unlock talent
	var talent_label := Label.new()
	talent_label.text = "Unlock talent:"
	talent_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(talent_label)

	var talent_row := HBoxContainer.new()
	vbox.add_child(talent_row)
	_talent_dropdown = OptionButton.new()
	_talent_dropdown.custom_minimum_size = Vector2(200, 0)
	_talent_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_talent_dropdown()
	talent_row.add_child(_talent_dropdown)
	var talent_btn := Button.new()
	talent_btn.text = "Unlock"
	talent_btn.pressed.connect(_unlock_selected_talent)
	talent_row.add_child(talent_btn)

	vbox.add_child(HSeparator.new())

	# Grant relic
	var relic_label := Label.new()
	relic_label.text = "Grant relic:"
	relic_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(relic_label)

	var relic_row := HBoxContainer.new()
	vbox.add_child(relic_row)
	_relic_dropdown = OptionButton.new()
	_relic_dropdown.custom_minimum_size = Vector2(200, 0)
	_relic_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_relic_dropdown()
	relic_row.add_child(_relic_dropdown)
	var relic_btn := Button.new()
	relic_btn.text = "Grant"
	relic_btn.pressed.connect(_grant_selected_relic)
	relic_row.add_child(relic_btn)

	vbox.add_child(HSeparator.new())

	# Change enemy encounter
	var enemy_label := Label.new()
	enemy_label.text = "Switch enemy:"
	enemy_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(enemy_label)

	var enemy_row := HBoxContainer.new()
	vbox.add_child(enemy_row)
	_enemy_dropdown = OptionButton.new()
	_enemy_dropdown.custom_minimum_size = Vector2(200, 0)
	_enemy_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_enemy_dropdown()
	enemy_row.add_child(_enemy_dropdown)
	var enemy_btn := Button.new()
	enemy_btn.text = "Switch"
	enemy_btn.pressed.connect(_switch_enemy)
	enemy_row.add_child(enemy_btn)

	# Status feedback
	_status_lbl = Label.new()
	_status_lbl.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_lbl)

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _add_card() -> void:
	var id := _card_input.text.strip_edges()
	if id == "":
		return
	# _card_for so the added copy reflects current talents/passives (overrides
	# applied via talent_overrides + CardModRules). Cheating a card in after
	# unlocking a talent mid-fight should show the talent's effects on it.
	var card: CardData = _scene._card_for("player", id)
	if card == null:
		_status_lbl.text = "Unknown card: " + id
		return
	_scene.turn_manager.add_to_hand(card)
	_status_lbl.text = ""
	_card_input.select_all()

func _populate_talent_dropdown() -> void:
	_talent_dropdown.clear()
	var talents: Array[TalentData] = TalentDatabase.get_talents_for_hero(GameManager.current_hero)
	for t in talents:
		var suffix := " [OWNED]" if GameManager.has_talent(t.id) else ""
		_talent_dropdown.add_item(t.talent_name + suffix)
		_talent_dropdown.set_item_metadata(_talent_dropdown.item_count - 1, t.id)

func _unlock_selected_talent() -> void:
	var idx: int = _talent_dropdown.selected
	if idx < 0:
		return
	var id: String = _talent_dropdown.get_item_metadata(idx)
	if GameManager.has_talent(id):
		_status_lbl.text = "Already unlocked: " + id
		return
	GameManager.add_talent_point()
	GameManager.unlock_talent(id)
	# Sync state.talents and clear the override cache so subsequent _card_for
	# lookups (token summons, draws, copy-to-hand effects) pick up the new
	# talent's overrides. Cards already in hand/deck keep their old card_data
	# by design — only newly created CardInstances get the new behavior.
	_scene._refresh_override_context()
	_scene.trigger_manager.clear()
	_scene._setup_triggers()
	rebuild_talent_tooltip()
	_populate_talent_dropdown()
	var talent: TalentData = TalentDatabase.get_talent(id)
	_status_lbl.text = "Unlocked: " + talent.talent_name
	_scene._log("  [CHEAT] Talent unlocked: %s" % talent.talent_name, _scene._LogType.PLAYER)

func _populate_relic_dropdown() -> void:
	_relic_dropdown.clear()
	var all_relics: Array[RelicData] = RelicDatabase.get_all()
	all_relics.sort_custom(func(a: RelicData, b: RelicData) -> bool: return a.act < b.act)
	for r in all_relics:
		var suffix := " [OWNED]" if r.id in GameManager.player_relics else ""
		_relic_dropdown.add_item("Act %d: %s%s" % [r.act, r.relic_name, suffix])
		_relic_dropdown.set_item_metadata(_relic_dropdown.item_count - 1, r.id)

func _grant_selected_relic() -> void:
	var idx: int = _relic_dropdown.selected
	if idx < 0:
		return
	var id: String = _relic_dropdown.get_item_metadata(idx)
	if id in GameManager.player_relics:
		_status_lbl.text = "Already owned: " + id
		return
	GameManager.player_relics.append(id)
	_scene._setup_relics()
	_populate_relic_dropdown()
	var relic: RelicData = RelicDatabase.get_relic(id)
	_status_lbl.text = "Granted: " + relic.relic_name
	_scene._log("  [CHEAT] Relic granted: %s" % relic.relic_name, _scene._LogType.PLAYER)

func _populate_enemy_dropdown() -> void:
	_enemy_dropdown.clear()
	const ACT_SIZES := [3, 3, 3, 6]
	for i in range(1, 16):
		var e: EnemyData = GameManager.get_encounter(i)
		if e == null:
			continue
		var act := 1
		var cumulative := 0
		for a in ACT_SIZES.size():
			cumulative += ACT_SIZES[a]
			if i <= cumulative:
				act = a + 1
				break
		var label := "A%d-%d: %s" % [act, i, e.enemy_name]
		_enemy_dropdown.add_item(label)
		_enemy_dropdown.set_item_metadata(_enemy_dropdown.item_count - 1, i)

func _switch_enemy() -> void:
	var idx: int = _enemy_dropdown.selected
	if idx < 0:
		return
	var encounter_idx: int = _enemy_dropdown.get_item_metadata(idx)
	GameManager.current_enemy = GameManager.get_encounter(encounter_idx)
	GameManager.run_node_index = encounter_idx
	AudioManager._current_scene_path = ""
	GameManager.go_to_scene("res://combat/board/CombatScene.tscn")
