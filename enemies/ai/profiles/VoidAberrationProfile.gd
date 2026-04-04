## VoidAberrationProfile.gd
## AI profile for the Void Aberration encounter (Act 3, Fight 8).
##
## Passive: void_detonation_passive — each Void Spark consumed as card cost
## deals 100 damage to all player minions AND the player hero.
##
## Strategy: Aggressively consume Sparks. Every spark-cost card played is both
## a card effect AND AoE chip damage. Maximize consumption triggers.
##
## Play order:
##   1. Dimensional Breach (consume 2 → 200 AoE + summon 3 = net +1)
##   2. Void Pulse spam (1M+1S = draw 3 + 100 AoE each)
##   3. Rift Collapse (2M+1S = 200 AoE + 100 detonation AoE)
##   4. Regular mana spells (void_bolt for hero pressure)
##   5. Spark-cost minions (Phase Stalker, Void Behemoth)
##   6. Regular essence minions (abyssal_brute)
##
## Resource growth:
##   Mana to 3 → Essence to 4 → Mana to 5 → Essence to 6
class_name VoidAberrationProfile
extends CombatProfile

func play_phase() -> void:
	# Phase 1: Dimensional Breach first — best card (200 AoE + 3 new sparks)
	await _play_spark_spell_by_id("dimensional_breach")
	if not agent.is_alive(): return
	# Phase 2: Void Pulse spam for draw + detonation
	while await _play_spark_spell_by_id("void_pulse"):
		if not agent.is_alive(): return
	# Phase 3: Rift Collapse
	await _play_spark_spell_by_id("rift_collapse")
	if not agent.is_alive(): return
	# Phase 4: Regular mana spells
	await _play_spells_pass()
	if not agent.is_alive(): return
	# Phase 5: Spark-cost minions
	await _play_spark_minions()
	if not agent.is_alive(): return
	# Phase 6: Regular essence minions
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
		_aberration_growth(sim_state, turn)

func _aberration_growth(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e: int = state.enemy_essence_max
	var m: int = state.enemy_mana_max
	if e + m >= 11:
		return
	if m < 3:
		state.enemy_mana_max += 1
	elif e < 4:
		state.enemy_essence_max += 1
	elif m < 5:
		state.enemy_mana_max += 1
	else:
		state.enemy_essence_max += 1

# ---------------------------------------------------------------------------
# Detonation helper — fires void_detonation_passive after smart spark payment
# ---------------------------------------------------------------------------

## Count how many void_spark entries are in the payment plan (each = 1 spark).
## Spirits with spark_value > 1 are NOT counted individually; only void_spark tokens.
func _fire_detonation_for_plan(plan: Array[MinionInstance]) -> void:
	var spark_count := 0
	for m: MinionInstance in plan:
		if (m.card_data as MinionCardData).id == "void_spark":
			spark_count += 1
		else:
			spark_count += (m.card_data as MinionCardData).spark_value
	if spark_count <= 0:
		return
	var passives = agent.scene.get("_active_enemy_passives")
	if passives != null and "void_detonation_passive" in passives:
		var handlers: Object = agent.scene.get("_handlers")
		if handlers != null and handlers.has_method("apply_void_detonation"):
			handlers.apply_void_detonation(spark_count)

# ---------------------------------------------------------------------------
# Play phases
# ---------------------------------------------------------------------------

## Try to play a specific spark-cost spell by ID. Returns true if played.
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
		var plan := _plan_spark_payment(sc)
		if plan.is_empty():
			return false
		await _pay_sparks_smart(plan, DeckType.TEMPO)
		if not agent.is_alive():
			return false
		_fire_detonation_for_plan(plan)
		agent.mana -= agent.effective_spell_cost(spell)
		if not await agent.commit_play_spell(inst, pick_spell_target(spell)):
			return false
		return true
	return false

## Play spark-cost minions — aggressive, spend all sparks.
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
			if plan.is_empty():
				return
			await _pay_sparks_smart(plan, DeckType.TEMPO)
			if not agent.is_alive():
				return
			_fire_detonation_for_plan(plan)
			agent.essence -= mc.essence_cost
			agent.mana    -= agent.effective_minion_mana_cost(mc)
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

## Play regular (non-spark) minions.
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
