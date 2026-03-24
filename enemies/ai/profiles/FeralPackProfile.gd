## FeralPackProfile.gd
## AI profile for the Feral Imp Pack encounter (fight 1).
##
## Play phase  — two-pass: minions first (cheapest first), then spells.
## Attack phase — inherited smart default (guard → lethal trade → face/swift).
## Spell rules  — feral_surge:  only if a Feral Imp is already on the board.
##               void_screech:  hold until board full or no minions left in hand.
##               cyclone:       only if opponent has an active Rune or Environment.
class_name FeralPackProfile
extends CombatProfile

func play_phase() -> void:
	await play_phase_two_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"feral_surge":  {"cast_if": "has_friendly_tag", "tag": "feral_imp"},
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":      {"cast_if": "opponent_has_rune_or_env"},
	}
