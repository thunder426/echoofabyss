## VoidHeraldProfile.gd
## AI profile for the Void Herald boss encounter (Act 3, Fight 9).
##
## Passive: void_mastery — all Void Spark costs halved (ceil), minimum 1.
## This makes the engine explosive:
##   - Dimensional Breach: 1M + 1 Spark → summon 3 Sparks (net +2)
##   - Void Behemoth: 3E + 1 Spark → 400/600 Guard
##   - Void Rift Lord: 4E + 2 Sparks → 400/600 + mana denial
##   - Rift Collapse: 2M + 1 Spark → 200 AoE
##
## Play order:
##   1. Dimensional Breach (engine — always first)
##   2. Void Rift Lord (mana denial — high priority)
##   3. Void Behemoth (cheap Guard)
##   4. Rift Collapse / Void Pulse (AoE + draw)
##   5. Spark-cost minions (Phase Stalker)
##   6. Regular cards as fallback
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7 → Mana to 4
class_name VoidHeraldProfile
extends CombatProfile

func play_phase() -> void:
	# Phase 1: Dimensional Breach — engine, play ALL copies
	while await _play_spark_spell_by_id("dimensional_breach"):
		if not agent.is_alive(): return
	# Phase 2: Void Rift Lord — mana denial
	await _play_spark_minion_by_id("void_rift_lord")
	if not agent.is_alive(): return
	# Phase 3: Void Behemoth — cheap Guard
	while await _play_spark_minion_by_id("void_behemoth"):
		if not agent.is_alive(): return
	# Phase 4: AoE and draw spells
	while await _play_spark_spell_by_id("rift_collapse"):
		if not agent.is_alive(): return
	while await _play_spark_spell_by_id("void_pulse"):
		if not agent.is_alive(): return
	# Phase 5: Phase Stalker
	while await _play_spark_minion_by_id("phase_stalker"):
		if not agent.is_alive(): return
	# Phase 6: Regular spells
	await _play_spells_pass()
	if not agent.is_alive(): return
	# Phase 7: Regular minions
	await _play_regular_minions()

func _get_spell_rules() -> Dictionary:
	return {
		"abyssal_plague": {"cast_if": "board_full_or_no_minions_in_hand"},
	}

# ---------------------------------------------------------------------------
# Resource growth
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_herald_growth(sim_state, turn)

func _herald_growth(state: Object, turn: int) -> void:
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
	elif e < 7:
		state.enemy_essence_max += 1
	elif m < 4:
		state.enemy_mana_max += 1
	else:
		state.enemy_essence_max += 1

# ---------------------------------------------------------------------------
# Spark helpers (same as other Act 3 profiles)
# ---------------------------------------------------------------------------

func _count_sparks() -> int:
	var count := 0
	for m: MinionInstance in agent.friendly_board:
		if m.card_data.id == "void_spark":
			count += 1
	return count

func _effective_spark_cost(card: CardData) -> int:
	var base: int = card.void_spark_cost
	if base <= 0:
		return 0
	var passives = agent.scene.get("_active_enemy_passives")
	if passives != null and "void_mastery" in passives:
		return maxi(ceili(float(base) / 2.0), 1)
	return base

func _consume_sparks(count: int) -> void:
	var consumed := 0
	for m: MinionInstance in agent.friendly_board.duplicate():
		if consumed >= count:
			break
		if m.card_data.id == "void_spark":
			agent.scene.combat_manager.kill_minion(m)
			consumed += 1
	var passives = agent.scene.get("_active_enemy_passives")
	if passives != null and "void_detonation_passive" in passives:
		var handlers: Object = agent.scene.get("_handlers")
		if handlers != null and handlers.has_method("apply_void_detonation"):
			handlers.apply_void_detonation(consumed)

func _can_afford_spark_card(card: CardData) -> bool:
	var spark_cost: int = _effective_spark_cost(card)
	if spark_cost <= 0:
		return false
	if spark_cost > _count_sparks():
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
# Play phases
# ---------------------------------------------------------------------------

func _play_spark_spell_by_id(target_id: String) -> bool:
	for inst in agent.hand.duplicate():
		if not (inst.card_data is SpellCardData):
			continue
		if inst.card_data.id != target_id:
			continue
		if not _can_afford_spark_card(inst.card_data):
			return false
		var spell := inst.card_data as SpellCardData
		var sc: int = _effective_spark_cost(spell)
		_consume_sparks(sc)
		agent.mana -= agent.effective_spell_cost(spell)
		if not await agent.commit_play_spell(inst, pick_spell_target(spell)):
			return false
		return true
	return false

func _play_spark_minion_by_id(target_id: String) -> bool:
	for inst in agent.hand.duplicate():
		if not (inst.card_data is MinionCardData):
			continue
		if inst.card_data.id != target_id:
			continue
		if not _can_afford_spark_card(inst.card_data):
			return false
		var slot: BoardSlot = agent.find_empty_slot()
		if slot == null:
			return false
		var mc := inst.card_data as MinionCardData
		var sc: int = _effective_spark_cost(mc)
		_consume_sparks(sc)
		agent.essence -= mc.essence_cost
		agent.mana    -= agent.effective_minion_mana_cost(mc)
		if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
			return false
		return true
	return false

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
