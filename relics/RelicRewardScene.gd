## RelicRewardScene.gd
## Shown after completing an act — player picks 1 of 3 relics.
extends Node2D

func _ready() -> void:
	var act := GameManager.get_completed_act()
	var offers := RelicDatabase.get_offer_for_act(act)
	_build_relic_buttons(offers)
	$UI/ActLabel.text = "Act %d Complete!" % act
	GameManager.last_boss_unlocks.clear()

func _build_relic_buttons(offers: Array[RelicData]) -> void:
	var container := $UI/RelicContainer
	for relic in offers:
		var panel := _make_relic_panel(relic)
		container.add_child(panel)

func _make_relic_panel(relic: RelicData) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 220)

	var style := StyleBoxFlat.new()
	style.bg_color          = Color(0.10, 0.06, 0.18, 1)
	style.border_color      = Color(0.55, 0.20, 0.90, 1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = relic.relic_name
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.60, 1.0, 1))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = relic.description
	desc_lbl.add_theme_font_size_override("font_size", 17)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95, 1))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_lbl)

	var btn := Button.new()
	btn.text = "Choose"
	btn.add_theme_font_size_override("font_size", 18)
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_relic_picked.bind(relic.id))
	vbox.add_child(btn)

	return panel

func _on_relic_picked(relic_id: String) -> void:
	GameManager.player_relics.append(relic_id)
	# Grant a talent point for completing the act, then send player to spend it
	GameManager.add_talent_point()
	GameManager.go_to_scene("res://talents/TalentSelectScene.tscn")
