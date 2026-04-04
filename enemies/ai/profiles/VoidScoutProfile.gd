## VoidScoutProfile.gd
## AI profile for the Void Scout encounter (Act 4, Fight 10).
##
## Passives: void_might (shared) + void_precision (crit → +200 ATK permanent)
##
## Strategy: Play spirit minions as board presence and spark fuel.
## Sovereign's Herald delivers targeted crits to the biggest minion,
## which snowballs via void_precision. Spark-cost cards consume
## Void Sparks first, then cheapest spirits.
##
## Play order:
##   1. Regular spirits (flood board for fuel + bodies)
##   2. Sovereign's Herald (delivers crits to strongest minion)
##   3. Regular mana spells
##   4. Spark-cost spells (Void Pulse for draw, Rift Collapse for AoE)
##   5. Spark-cost minions (Phase Stalker, Void Behemoth, Bastion Colossus)
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7
class_name VoidScoutProfile
extends CombatProfile

func play_phase() -> void:
	# Phase 1: Flood spirits + heralds
	await _play_regular_minions()
	if not agent.is_alive(): return
	# Phase 2: Mana spells
	await _play_spells_pass()
	if not agent.is_alive(): return
	# Phase 3: Spark-cost spells
	await _play_spark_spells()
	if not agent.is_alive(): return
	# Phase 4: Spark-cost minions
	await _play_spark_minions()

func _get_spell_rules() -> Dictionary:
	return {}

# ---------------------------------------------------------------------------
# Resource growth
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_void_scout_growth(sim_state, turn)

func _void_scout_growth(state: Object, turn: int) -> void:
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
# Spark affordability (uses shared _available_sparks from CombatProfile)
# ---------------------------------------------------------------------------

func _can_afford_spark_card(card: CardData) -> bool:
	var spark_cost: int = card.void_spark_cost
	if spark_cost <= 0:
		return false
	if not _can_afford_sparks(spark_cost):
		return false
	if card is SpellCardData:
		var spell := card as SpellCardData
		return agent.effective_spell_cost(spell) <= agent.mana
	elif card is MinionCardData:
		var mc := card as MinionCardData
		var mana_cost: int = agent.effective_minion_mana_cost(mc)
		return mc.essence_cost <= agent.essence and mana_cost <= agent.mana
	return false

# ---------------------------------------------------------------------------
# On-play targeting: Herald grants crit to highest-ATK friendly minion
# ---------------------------------------------------------------------------

func pick_on_play_target(mc: MinionCardData):
	if mc.id == "sovereigns_herald":
		return _pick_highest_atk_friendly()
	return super.pick_on_play_target(mc)

func _pick_highest_atk_friendly() -> MinionInstance:
	var best: MinionInstance = null
	for m: MinionInstance in agent.friendly_board:
		if best == null or m.effective_atk() > best.effective_atk():
			best = m
	return best

# ---------------------------------------------------------------------------
# Play phases
# ---------------------------------------------------------------------------

## Play regular (non-spark-cost) minions: spirits and heralds.
func _play_regular_minions() -> void:
	var placed := true
	while placed:
		placed = false
		var minion_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is MinionCardData and inst.card_data.void_spark_cost <= 0:
				minion_hand.append(inst)
		# Cheapest first to flood the board
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

## Play spark-cost spells from hand. Spirits attack before being consumed.
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
			var p: int = _spark_spell_priority(inst.card_data.id)
			if p > best_priority:
				best = inst
				best_priority = p
		if best != null:
			var spell := best.card_data as SpellCardData
			var plan := _plan_spark_payment(spell.void_spark_cost)
			if plan.is_empty():
				return
			await _pay_sparks_smart(plan, DeckType.TEMPO)
			if not agent.is_alive(): return
			agent.mana -= agent.effective_spell_cost(spell)
			if not await agent.commit_play_spell(best, pick_spell_target(spell)):
				return
			cast = true

## Play spark-cost minions, most expensive first. Spirits attack before consumed.
func _play_spark_minions() -> void:
	var placed := true
	while placed:
		placed = false
		var spark_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is MinionCardData and inst.card_data.void_spark_cost > 0:
				spark_hand.append(inst)
		# Most expensive first — prioritise Bastion Colossus over Phase Stalker
		spark_hand.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
			return a.card_data.void_spark_cost > b.card_data.void_spark_cost)
		for inst in spark_hand:
			if not _can_afford_spark_card(inst.card_data):
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return
			var mc := inst.card_data as MinionCardData
			var plan := _plan_spark_payment(mc.void_spark_cost)
			if plan.is_empty():
				continue
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
		"rift_collapse":     return 3
		"void_pulse":        return 2
		"sovereigns_decree": return 1
	return 0
