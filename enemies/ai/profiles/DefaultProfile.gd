## DefaultProfile.gd
## Generic AI profile used when no specific profile is assigned.
##
## Play phase  — interleaved: plays the cheapest affordable card each pass
##               (spells and minions treated equally, sorted by total cost).
## Attack phase — inherited smart default (guard → lethal trade → face/swift).
class_name DefaultProfile
extends CombatProfile

func play_phase() -> void:
	var made_a_play := true
	while made_a_play:
		made_a_play = false
		agent.hand.sort_custom(agent.sort_by_total_cost)
		for inst in agent.hand.duplicate():
			if inst.card_data is SpellCardData:
				var spell := inst.card_data as SpellCardData
				var cost: int = agent.effective_spell_cost(spell)
				if cost > agent.mana:
					continue
				agent.mana -= cost
				if not await agent.commit_play_spell(inst, pick_spell_target(spell)):
					return
				made_a_play = true
				break
			elif inst.card_data is MinionCardData:
				var mc := inst.card_data as MinionCardData
				if mc.essence_cost > agent.essence or mc.mana_cost > agent.mana:
					continue
				var slot: BoardSlot = agent.find_empty_slot()
				if slot == null:
					return  # board full — stop all play
				agent.essence -= mc.essence_cost
				agent.mana    -= mc.mana_cost
				if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
					return
				made_a_play = true
				break
