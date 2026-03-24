## CorruptedBroodProfile.gd
## AI profile for the Corrupted Broodlings encounter (fight 2).
##
## Play phase  — two-pass: minions first (cheapest first), then spells.
## Attack phase — inherited smart default (guard → lethal trade → face/swift).
## Spell rules  — brood_call:   only if the board still has an empty slot.
##               void_screech:  hold until board full or no minions left in hand.
##               cyclone:       only if opponent has an active Rune or Environment.
class_name CorruptedBroodProfile
extends CombatProfile

func play_phase() -> void:
	await play_phase_two_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"brood_call":   {"cast_if": "board_not_full"},
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":      {"cast_if": "opponent_has_rune_or_env"},
	}
