## VoidAberrationProfile.gd
## AI profile for the Void Aberration encounter (Act 3, Fight 8).
##
## Passive: void_detonation_passive — each spark consumed as card cost
## deals 100 damage (200 with champion) to all opponent minions AND hero.
##
## Strategy: Build board with cheap minions, then aggressively consume sparks
## to trigger detonation AoE. Every spark-cost card is both a play AND an AoE nuke.
##
## Play order:
##   1. Regular essence minions (void_echo, rift_tender — build board + generate sparks)
##   2. Mana-only spells
##   3. Spark-cost spells (void_pulse — draw + detonation)
##   4. Spark-cost minions (phase_stalker, void_behemoth — board + detonation)
##
## Resource growth:
##   Essence to 4 → Mana to 3 → Essence to 6 → Mana to 5
class_name VoidAberrationProfile
extends CombatProfile

func play_phase() -> void:
	# Phase 1: Spark-cost spells FIRST (detonation triggers — core mechanic)
	await _play_spark_spells()
	if not agent.is_alive(): return
	# Phase 2: Spark-cost minions (detonation + board presence)
	await _play_spark_minions()
	if not agent.is_alive(): return
	# Phase 3: Regular essence minions (fill remaining slots)
	await _play_regular_minions()
	if not agent.is_alive(): return
	# Phase 4: Void Wind — only cast when opponent has a Void Rune
	await _try_void_wind()
	if not agent.is_alive(): return
	# Phase 5: Mana-only spells
	await _play_spells_pass()

func _is_tempo() -> bool:
	return true

func _get_spell_rules() -> Dictionary:
	return {
		"void_wind": {"cast_if": "never"},
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
	if e < 4:
		state.enemy_essence_max += 1
	elif m < 3:
		state.enemy_mana_max += 1
	elif e < 6:
		state.enemy_essence_max += 1
	else:
		state.enemy_mana_max += 1

# ---------------------------------------------------------------------------
# Board awareness helpers
# ---------------------------------------------------------------------------

func _empty_slot_count() -> int:
	var slots: Array = []
	if agent.get("enemy_slots") != null:
		slots = agent.get("enemy_slots")
	elif agent.get("sim") != null:
		slots = agent.sim.enemy_slots
	var count := 0
	for slot in slots:
		if slot.is_empty():
			count += 1
	return count

# ---------------------------------------------------------------------------
# Play phases
# ---------------------------------------------------------------------------

## Cast Void Wind only when opponent has a Void Rune — destroys trap + heals 500 HP.
func _try_void_wind() -> void:
	var opponent_traps: Array = agent.scene._opponent_traps("enemy")
	if opponent_traps.is_empty():
		return
	# Only cast against Void Runes specifically
	var has_void_rune := false
	for trap in opponent_traps:
		if trap is TrapCardData and (trap as TrapCardData).is_rune \
				and (trap as TrapCardData).rune_type == Enums.RuneType.VOID_RUNE:
			has_void_rune = true
			break
	if not has_void_rune:
		return
	# Find void_wind in hand
	for inst in agent.hand.duplicate():
		if inst.card_data.id != "void_wind":
			continue
		var spell := inst.card_data as SpellCardData
		if agent.effective_spell_cost(spell) > agent.mana:
			continue
		agent.mana -= agent.effective_spell_cost(spell)
		await agent.commit_play_spell(inst, null)
		return

## Play regular (non-spark-cost) minions. Leave 1 slot for passive spark.
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
			# Always leave 1 slot for passive spark generation
			if _empty_slot_count() <= 1:
				continue
			# Rift Tender: needs 3 empty (itself + spark summon + passive spark slot)
			if mc.id == "rift_tender" and _empty_slot_count() < 3:
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

## Play spark-cost spells. Aggressive — cast whenever affordable.
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
			var sc: int = _effective_spark_cost(spell)
			var plan := _plan_spark_payment(sc)
			if plan.is_empty(): return
			await _pay_sparks_smart(plan, DeckType.AGGRO)
			if not agent.is_alive(): return
			agent.mana -= agent.effective_spell_cost(spell)
			if not await agent.commit_play_spell(best, pick_spell_target(spell)):
				return
			cast = true

## Play spark-cost minions. Aggressive — spend sparks for detonation triggers.
## Leave 1 slot for passive spark generation.
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
			# Leave 1 slot for passive spark
			if _empty_slot_count() <= 1:
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return
			var mc := inst.card_data as MinionCardData
			var sc: int = _effective_spark_cost(mc)
			var plan := _plan_spark_payment(sc)
			if plan.is_empty(): return
			await _pay_sparks_smart(plan, DeckType.AGGRO)
			if not agent.is_alive():
				return
			agent.essence -= mc.essence_cost
			agent.mana    -= agent.effective_minion_mana_cost(mc)
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

func _spark_spell_priority(id: String) -> int:
	match id:
		"void_pulse":         return 3  # Draw 3 + detonation
		"rift_collapse":      return 2  # AoE + detonation
		"dimensional_breach": return 1  # Summon sparks + detonation
	return 0
