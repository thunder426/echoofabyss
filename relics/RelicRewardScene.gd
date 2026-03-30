## RelicRewardScene.gd
## Shown after completing an act — player picks 1 of 2 relics,
## or from Act 2 onwards can choose to +1 charge a random existing relic instead.
extends Node2D

const COLOR_PURPLE := Color(0.85, 0.60, 1.0, 1)
const COLOR_GOLD   := Color(0.90, 0.75, 0.20, 1)
const COLOR_TEXT    := Color(0.85, 0.85, 0.95, 1)
const COLOR_DIM    := Color(0.55, 0.52, 0.60, 1)

func _ready() -> void:
	var act := GameManager.get_completed_act()
	var offers := RelicDatabase.get_offer_for_act(act)
	_build_ui(act, offers)
	GameManager.last_boss_unlocks.clear()

func _build_ui(act: int, offers: Array[RelicData]) -> void:
	var container := $UI/RelicContainer
	# Clear any existing children
	for child in container.get_children():
		child.queue_free()

	$UI/ActLabel.text = "Act %d Complete!" % act

	# Option A & B: pick 1 of 2 relics
	for relic in offers:
		var panel := _make_relic_panel(relic)
		container.add_child(panel)

	# Option C: +1 charge to existing relic (Act 2+ only, if player has relics)
	if act >= 2 and not GameManager.player_relics.is_empty():
		var upgrade_panel := _make_upgrade_panel()
		container.add_child(upgrade_panel)

func _make_relic_panel(relic: RelicData) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 260)

	var style := StyleBoxFlat.new()
	style.bg_color          = Color(0.10, 0.06, 0.18, 1)
	style.border_color      = Color(0.55, 0.20, 0.90, 1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = relic.relic_name
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", COLOR_PURPLE)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = relic.description
	desc_lbl.add_theme_font_size_override("font_size", 16)
	desc_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_lbl)

	# Stats line: charges / cooldown
	var stats_lbl := Label.new()
	stats_lbl.text = "Charges: %d  |  Cooldown: %d turns" % [relic.charges, relic.cooldown]
	stats_lbl.add_theme_font_size_override("font_size", 14)
	stats_lbl.add_theme_color_override("font_color", COLOR_DIM)
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats_lbl)

	var btn := Button.new()
	btn.text = "Choose"
	btn.add_theme_font_size_override("font_size", 18)
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_relic_picked.bind(relic.id))
	vbox.add_child(btn)

	return panel

func _make_upgrade_panel() -> PanelContainer:
	# Pick a random existing relic to offer the upgrade on
	var existing_ids: Array[String] = GameManager.player_relics.duplicate()
	existing_ids.shuffle()
	var upgrade_id: String = existing_ids[0]
	var upgrade_relic: RelicData = RelicDatabase.get_relic(upgrade_id)
	var current_bonus: int = GameManager.relic_bonus_charges.get(upgrade_id, 0) as int
	var total_charges: int = upgrade_relic.charges + current_bonus + 1 if upgrade_relic else 0

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 260)

	var style := StyleBoxFlat.new()
	style.bg_color          = Color(0.08, 0.10, 0.06, 1)
	style.border_color      = Color(0.70, 0.65, 0.20, 1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "Empower Relic"
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = "+1 charge to %s\n(%d → %d charges)" % [
		upgrade_relic.relic_name if upgrade_relic else upgrade_id,
		total_charges - 1, total_charges]
	desc_lbl.add_theme_font_size_override("font_size", 16)
	desc_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_lbl)

	var btn := Button.new()
	btn.text = "Empower"
	btn.add_theme_font_size_override("font_size", 18)
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_upgrade_picked.bind(upgrade_id))
	vbox.add_child(btn)

	return panel

func _on_relic_picked(relic_id: String) -> void:
	GameManager.player_relics.append(relic_id)
	_proceed()

func _on_upgrade_picked(relic_id: String) -> void:
	var current: int = GameManager.relic_bonus_charges.get(relic_id, 0) as int
	GameManager.relic_bonus_charges[relic_id] = current + 1
	_proceed()

func _proceed() -> void:
	GameManager.add_talent_point()
	GameManager.go_to_scene("res://talents/TalentSelectScene.tscn")
