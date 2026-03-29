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

const _FERAL_IMP_THRESHOLD := 3

func play_phase() -> void:
	await play_phase_two_pass()

func attack_phase() -> void:
	# Cast pack_frenzy before attacks if enough imps on board
	var pf := _find_pack_frenzy()
	if pf != null and agent.effective_spell_cost(pf.card_data as SpellCardData) <= agent.mana:
		var imp_count := 0
		for m in agent.friendly_board:
			if agent.scene != null and agent.scene._minion_has_tag(m, "feral_imp"):
				imp_count += 1
		if imp_count >= _FERAL_IMP_THRESHOLD:
			agent.mana -= agent.effective_spell_cost(pf.card_data as SpellCardData)
			if not await agent.commit_play_spell(pf, null):
				return
	await super.attack_phase()

func _get_spell_rules() -> Dictionary:
	return {
		"pack_frenzy":  {"cast_if": "before_attacks"},
		"brood_call":   {"cast_if": "board_not_full"},
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":      {"cast_if": "opponent_has_rune_or_env"},
	}

func _find_pack_frenzy() -> CardInstance:
	for inst in agent.hand:
		if inst.card_data is SpellCardData and (inst.card_data as SpellCardData).id == "pack_frenzy":
			return inst
	return null
