## CorruptedBroodProfile.gd
## AI profile for the Corrupted Broodlings encounter (fight 2).
##
## Tempo deck — prioritises board control via trading. Death-trigger minions
## (void_touched_imp, brood_imp) punish the opponent for killing them, so
## keeping the board contested maximises passive value.
##
## Play phase  — two-pass: minions first (cheapest first), then spells.
## Attack phase — tempo: trade into opponent minions unless lethal available.
## Spell rules  — void_screech:  hold until board full or no minions left in hand.
##               cyclone:       only if opponent has an active Rune or Environment.
class_name CorruptedBroodProfile
extends CombatProfile

func play_phase() -> void:
	await play_phase_two_pass()

func _is_tempo() -> bool:
	return true

func _get_spell_rules() -> Dictionary:
	return {
		"feral_surge":  {"cast_if": "has_friendly_tag", "tag": "feral_imp"},
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":      {"cast_if": "opponent_has_rune_or_env"},
	}
