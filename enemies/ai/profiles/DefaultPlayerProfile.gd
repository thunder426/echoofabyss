## DefaultPlayerProfile.gd
## Competitive player bot for balance simulation.
##
## Play phase  — two-pass: flood board with minions (cheapest first), then cast spells.
## Attack phase — inherited smart default (guard → lethal trade → face/swift).
## Spell rules  — void_execution: only if a Human is on the friendly board.
##               void_screech:   hold until board full or no minions left in hand.
##               cyclone:        only if opponent has an active Rune or Environment.
class_name DefaultPlayerProfile
extends CombatProfile

func play_phase() -> void:
	await play_phase_two_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"void_execution": {"cast_if": "has_friendly_tag", "tag": "human"},
		"void_screech":   {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":        {"cast_if": "opponent_has_rune_or_env"},
	}
