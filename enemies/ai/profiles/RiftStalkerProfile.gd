## RiftStalkerProfile.gd
## AI profile for the Rift Stalker encounter (Act 3, Fight 7).
##
## Passive: void_empowerment — all enemy Void Sparks enter as 200/200.
## The 200/200 Sparks are real threats, so the AI conserves at least 1 Spark
## on the board as an attacker when possible.
##
## Play order:
##   1. Regular mana spells (void_bolt, abyssal_plague — spend mana early)
##   2. Spark-cost spells (Void Pulse for draw, Rift Collapse for AoE)
##   3. Regular essence minions (abyssal_brute, void_stalker)
##   4. Spark-cost minions (Phase Stalker, Void Behemoth)
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7
class_name RiftStalkerProfile
extends CombatProfile

func play_phase() -> void:
	# Phase 1: Regular mana spells
	await _play_spells_pass()
	if not agent.is_alive(): return
	# Phase 2: Spark-cost spells
	await _play_spark_spells()
	if not agent.is_alive(): return
	# Phase 3: Regular essence minions
	await _play_regular_minions()
	if not agent.is_alive(): return
	# Phase 4: Spark-cost minions
	await _play_spark_minions()

func _get_spell_rules() -> Dictionary:
	return {
		"abyssal_plague": {"cast_if": "board_full_or_no_minions_in_hand"},
	}

# ---------------------------------------------------------------------------
# Resource growth
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_rift_stalker_growth(sim_state, turn)

func _rift_stalker_growth(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e: int = state.enemy_essence_max
	var m: int = state.enemy_mana_max
	if e + m >= 11:
		return
	if e < 5:
		state.enemy_essence_max += 1
	elif m < 3:
		state.enemy_mana_max += 1
	else:
		state.enemy_essence_max += 1

# ---------------------------------------------------------------------------
# Play phases
# ---------------------------------------------------------------------------

## Play spark-cost spells from hand. Conservative: keep at least 1 Spark if possible.
func _play_spark_spells() -> void:
	var cast := true
	while cast:
		cast = false
		var best: CardInstance = null
		var best_priority := -1
		for inst in agent.hand:
			if not (inst.card_data is SpellCardData):
				continue
			if inst.card_data.void_spark_cost <= 0:
				continue
			if not _can_afford_spark_card(inst.card_data):
				continue
			# Conservative: skip if this would use our last spark
			var sc: int = _effective_spark_cost(inst.card_data)
			if _available_sparks() - sc < 1 and _available_sparks() > 1:
				continue
			var p: int = _spark_spell_priority(inst.card_data.id)
			if p > best_priority:
				best = inst
				best_priority = p
		if best != null:
			var spell := best.card_data as SpellCardData
			var sc: int = _effective_spark_cost(spell)
			var plan := _plan_spark_payment(sc)
			if plan.is_empty(): return
			await _pay_sparks_smart(plan, DeckType.TEMPO)
			if not agent.is_alive(): return
			agent.mana -= agent.effective_spell_cost(spell)
			if not await agent.commit_play_spell(best, pick_spell_target(spell)):
				return
			cast = true

## Play regular (non-spark-cost) minions.
func _play_regular_minions() -> void:
	var placed := true
	while placed:
		placed = false
		var minion_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is MinionCardData and inst.card_data.void_spark_cost <= 0:
				minion_hand.append(inst)
		minion_hand.sort_custom(agent.sort_by_total_cost)
		for inst in minion_hand:
			var mc := inst.card_data as MinionCardData
			var mana_cost: int = agent.effective_minion_mana_cost(mc)
			if mc.essence_cost > agent.essence or mana_cost > agent.mana:
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return
			agent.essence -= mc.essence_cost
			agent.mana    -= mana_cost
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

## Play spark-cost minions.
func _play_spark_minions() -> void:
	var placed := true
	while placed:
		placed = false
		for inst in agent.hand.duplicate():
			if not (inst.card_data is MinionCardData):
				continue
			if inst.card_data.void_spark_cost <= 0:
				continue
			if not _can_afford_spark_card(inst.card_data):
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return
			var mc := inst.card_data as MinionCardData
			var sc: int = _effective_spark_cost(mc)
			var plan := _plan_spark_payment(sc)
			if plan.is_empty(): return
			await _pay_sparks_smart(plan, DeckType.TEMPO)
			if not agent.is_alive(): return
			agent.essence -= mc.essence_cost
			agent.mana    -= agent.effective_minion_mana_cost(mc)
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

func _spark_spell_priority(id: String) -> int:
	match id:
		"rift_collapse": return 3
		"void_pulse":    return 2
		"dimensional_breach": return 1
	return 0
