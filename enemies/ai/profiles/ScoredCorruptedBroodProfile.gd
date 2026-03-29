## ScoredCorruptedBroodProfile.gd
## Scored AI profile for the Corrupted Broodlings encounter.
## Uses original two-pass play (flood board) + Pack Frenzy timing +
## original attack logic. Scoring hooks available for fine-tuning.
class_name ScoredCorruptedBroodProfile
extends ScoredCombatProfile

const _FERAL_IMP_THRESHOLD := 3

func play_phase() -> void:
	await play_phase_two_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"pack_frenzy":  {"cast_if": "before_attacks"},
		"brood_call":   {"cast_if": "board_not_full"},
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":      {"cast_if": "opponent_has_rune_or_env"},
	}

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
	# Original CombatProfile attack logic
	var lethal_threat  := _opponent_threatens_lethal()
	var can_go_lethal  := _calc_lethal_damage() >= agent.opponent_hp
	if can_go_lethal:
		await _play_lethal_spells()
		if not agent.is_alive(): return
	for minion in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(minion) or not minion.can_attack():
			continue
		var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
		if can_go_lethal and guards.is_empty():
			if minion.can_attack_hero():
				if not await agent.do_attack_hero(minion):
					if not agent.is_alive(): return
			elif not agent.opponent_board.is_empty():
				var target := agent.pick_swift_target(minion)
				if not await agent.do_attack_minion(minion, target):
					if not agent.is_alive(): return
		elif not guards.is_empty():
			var target := _pick_best_guard(minion, guards)
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return
		elif lethal_threat and not agent.opponent_board.is_empty():
			var target := agent.pick_swift_target(minion)
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return
		elif minion.can_attack_hero():
			if not await agent.do_attack_hero(minion):
				if not agent.is_alive(): return
		elif not agent.opponent_board.is_empty():
			var target := agent.pick_swift_target(minion)
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return

func _find_pack_frenzy() -> CardInstance:
	for inst in agent.hand:
		if inst.card_data is SpellCardData and (inst.card_data as SpellCardData).id == "pack_frenzy":
			return inst
	return null
