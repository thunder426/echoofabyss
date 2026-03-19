## CardPreviewScene.gd
## Quick preview of all card types at design-time.
## Open CardPreviewScene.tscn and run it to see how cards look.
extends Node2D

const CardDisplayScene := preload("res://cards/scenes/CardDisplay.tscn")

func _ready() -> void:
	# Sample card IDs to preview — one of each type
	var preview_ids: Array[String] = [
		"void_imp",        # Minion (essence, Abyss Order)
		"shadow_hound",    # Minion (essence, Abyss Order)
		"dark_surge",      # Spell (mana)
		"dominion_rune",   # Rune (mana)
		"abyss_ritual_circle",  # Environment (mana)
	]

	var x := 40
	var y := 60
	for card_id in preview_ids:
		var card_data := CardDatabase.get_card(card_id)
		if card_data == null:
			continue
		var display := CardDisplayScene.instantiate() as CardDisplay
		add_child(display)
		display.position = Vector2(x, y)
		display.setup(card_data)
		x += 220
		if x > 1700:
			x = 40
			y += 310
