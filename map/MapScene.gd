## MapScene.gd
## Shows the full 4-act run map. Completed nodes are greyed, the active node is
## highlighted, and future nodes are locked. The player clicks the active node
## to enter combat.
extends Node2D

const ACT_NAMES := ["The Abyss Awakens", "Descent into Shadow", "The Void Rift", "The Final Reckoning"]

func _ready() -> void:
	# If the player has unspent talent points, send them to the talent screen first
	if GameManager.talent_points > 0:
		GameManager.go_to_scene("res://talents/TalentSelectScene.tscn")
		return
	_build_map()
	_update_footer()
	$UI/ViewDeckButton.pressed.connect(_on_view_deck_pressed)

# ---------------------------------------------------------------------------
# Map construction
# ---------------------------------------------------------------------------

func _build_map() -> void:
	var acts_container := $UI/ActsContainer
	for act_idx in GameManager.TOTAL_ACTS:
		var col := _make_act_column(act_idx)
		acts_container.add_child(col)

func _make_act_column(act_idx: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	col.add_theme_constant_override("separation", 12)

	# Act header
	var act_label := Label.new()
	act_label.text = "ACT %s\n%s" % [_roman(act_idx + 1), ACT_NAMES[act_idx]]
	act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act_label.add_theme_font_size_override("font_size", 20)
	act_label.add_theme_color_override("font_color", _act_header_color(act_idx))
	col.add_child(act_label)

	var hsep := HSeparator.new()
	col.add_child(hsep)

	# Compute the starting global index for this act
	var act_start: int = 1
	for i in act_idx:
		act_start += GameManager.ACT_SIZES[i]

	# Fight nodes
	var fights_this_act: int = GameManager.ACT_SIZES[act_idx]
	for fight_in_act in fights_this_act:
		var global_idx: int = act_start + fight_in_act
		var node_btn := _make_node_button(global_idx, fight_in_act)
		col.add_child(node_btn)

	# Relic indicator at the bottom of each act column
	var relic_lbl := _make_relic_indicator(act_idx, act_start + fights_this_act)
	col.add_child(relic_lbl)

	return col

func _make_node_button(global_idx: int, fight_in_act: int) -> Button:
	var enc := GameManager.get_encounter(global_idx)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(360, 100)
	btn.add_theme_font_size_override("font_size", 17)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var is_completed := global_idx < GameManager.run_node_index
	var is_active    := global_idx == GameManager.run_node_index
	var is_boss      := global_idx in GameManager.BOSS_INDICES

	if is_completed:
		var prefix := "⚔ BOSS: " if is_boss else "Fight %d:  " % (fight_in_act + 1)
		btn.text = "✓  %s%s\n   HP: %d  ·  DEFEATED" % [prefix, enc.enemy_name, enc.hp]
		btn.disabled = true
		btn.modulate = Color(0.40, 0.40, 0.45, 1)

	elif is_active:
		var prefix := "⚔ BOSS: " if is_boss else "Fight %d:  " % (fight_in_act + 1)
		btn.text = "%s%s\n   HP: %d  ·  [ Enter ]" % [prefix, enc.enemy_name, enc.hp]
		btn.pressed.connect(_on_encounter_pressed.bind(global_idx))

	else:
		btn.text = "Fight %d:  ???\n   [ LOCKED ]" % (fight_in_act + 1)
		btn.disabled = true
		btn.modulate = Color(0.22, 0.22, 0.28, 1)

	return btn

## act_boundary: the global_idx at which this act ends (exclusive upper bound).
func _make_relic_indicator(act_idx: int, act_boundary: int) -> Label:
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)

	var act_done := GameManager.run_node_index >= act_boundary

	if act_done:
		var relic_id: String = GameManager.player_relics[act_idx] if act_idx < GameManager.player_relics.size() else ""
		var relic := RelicDatabase.get_relic(relic_id)
		var rname := relic.relic_name if relic else "???"
		lbl.text = "✦ Relic: %s" % rname
		lbl.add_theme_color_override("font_color", Color(0.90, 0.75, 0.20, 1))
	else:
		lbl.text = "✦ Relic reward pending"
		lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55, 1))

	return lbl

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------

func _update_footer() -> void:
	var deck_lbl := $UI/DeckInfoLabel
	if deck_lbl:
		deck_lbl.text = "Deck: %d cards" % GameManager.player_deck.size()

	var relic_lbl := $UI/RelicsLabel
	if relic_lbl:
		if GameManager.player_relics.is_empty():
			relic_lbl.text = "Relics: none"
		else:
			var names := []
			for rid in GameManager.player_relics:
				var r := RelicDatabase.get_relic(rid)
				names.append(r.relic_name if r else rid)
			relic_lbl.text = "Relics: " + "  ·  ".join(names)

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_encounter_pressed(global_idx: int) -> void:
	GameManager.current_enemy = GameManager.get_encounter(global_idx)
	GameManager.go_to_scene("res://combat/board/CombatScene.tscn")

func _on_view_deck_pressed() -> void:
	GameManager.go_to_scene("res://ui/DeckViewerScene.tscn")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _roman(n: int) -> String:
	match n:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
	return str(n)

func _act_header_color(act_idx: int) -> Color:
	# get_current_act() returns 1-based; convert to 0-based for comparison
	var current_act: int = GameManager.get_current_act() - 1
	if act_idx < current_act:
		return Color(0.45, 0.45, 0.55, 1)  # completed — dimmed
	elif act_idx == current_act:
		return Color(0.75, 0.35, 1.0, 1)   # active — purple
	else:
		return Color(0.28, 0.28, 0.35, 1)  # locked — dark
