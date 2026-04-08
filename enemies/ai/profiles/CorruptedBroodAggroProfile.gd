## CorruptedBroodAggroProfile.gd
## AI profile for the Corrupted Broodlings — Aggro variant.
##
## Goes face instead of trading. Relies on void_touched_imp AoE death triggers
## firing when the PLAYER kills them, not via self-trades. Feral surge on
## highest ATK minion for maximum face damage.
class_name CorruptedBroodAggroProfile
extends CombatProfile

func play_phase() -> void:
	await play_phase_two_pass()

func _is_aggro() -> bool:
	return true

func _get_spell_rules() -> Dictionary:
	return {
		"feral_surge":  {"cast_if": "has_friendly_tag", "tag": "feral_imp"},
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":      {"cast_if": "opponent_has_rune_or_env"},
	}
