## VoidHeraldProfile.gd
## AI profile for the Void Herald boss encounter (Act 3, Fight 9).
##
## Passive: void_mastery — all spark costs halved (ceil), minimum 1.
## Champion: Void Herald — after 6 spark-cost cards, all spark costs = 0,
##           void_rift stops generating sparks.
##
## Strategy: Spam spark-cost cards rapidly thanks to void_mastery discount.
## After champion: play everything for free (essence/mana only).
##
## Play order:
##   1. Spark-cost spells (Void Pulse draw, Rift Collapse AoE)
##   2. Spark-cost minions by priority: Void Rift Lord > Void Behemoth > Phase Stalker
##   3. Regular essence minions (Void Echo, Rift Tender)
##   4. Regular mana spells
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7 → Mana to 4
class_name VoidHeraldProfile
extends CombatProfile

func play_phase() -> void:
	# Phase 1: Rift Lord combos — Surge+RL (2M+4E) or Tender+RL (6E)
	await _try_surge_rl_combo()
	if not agent.is_alive(): return
	await _try_rift_lord_combo()
	if not agent.is_alive(): return
	# Phase 2: Void Behemoth — GUARD to protect hero (high priority)
	while await _play_spark_minion_by_id("void_behemoth"):
		if not agent.is_alive(): return
	# Phase 3: Phase Stalker — SWIFT pressure (higher priority than spells)
	while await _play_spark_minion_by_id("phase_stalker"):
		if not agent.is_alive(): return
	# Phase 4: Spirit Surge + Void Pulse combo (tutor + spark → draw 3)
	await _try_surge_pulse_combo()
	if not agent.is_alive(): return
	# Phase 5: Spark-cost spells (remaining)
	await _play_spark_spells()
	if not agent.is_alive(): return
	# Phase 4: Regular essence minions (including leftover Rift Tenders)
	await _play_regular_minions()
	if not agent.is_alive(): return
	# Phase 4: Void Wind — only against Void Runes
	await _try_void_wind()
	if not agent.is_alive(): return
	# Phase 5: Regular mana spells
	await _play_spells_pass()

func _is_tempo() -> bool:
	return true

func _get_spell_rules() -> Dictionary:
	return {
		"void_wind": {"cast_if": "never"},
		"spirit_surge": {"cast_if": "never"},
	}

## Cast Void Wind only when opponent has a Void Rune.
func _try_void_wind() -> void:
	var opponent_traps: Array = agent.scene._opponent_traps("enemy")
	if opponent_traps.is_empty():
		return
	var has_void_rune := false
	for trap in opponent_traps:
		if trap is TrapCardData and (trap as TrapCardData).is_rune \
				and (trap as TrapCardData).rune_type == Enums.RuneType.VOID_RUNE:
			has_void_rune = true
			break
	if not has_void_rune:
		return
	for inst in agent.hand.duplicate():
		if inst.card_data.id != "void_wind":
			continue
		var spell := inst.card_data as SpellCardData
		if agent.effective_spell_cost(spell) > agent.mana:
			continue
		agent.mana -= agent.effective_spell_cost(spell)
		await agent.commit_play_spell(inst, null)
		return

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
	if e < 4:
		state.enemy_essence_max += 1
	elif m < 2:
		state.enemy_mana_max += 1
	elif e < 6:
		state.enemy_essence_max += 1
	elif m < 3:
		state.enemy_mana_max += 1
	elif e < 8:
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

## Combo: play Rift Tender + Void Rift Lord together.
## Tender costs 2E and summons a spark. With passive spark = 2 sparks on board.
## RL costs 4E + 2 sparks (with mastery). Total: 6E needed.
## If RL not in hand or already played, just play tenders normally.
func _try_rift_lord_combo() -> void:
	var rl_inst: CardInstance = null
	var tender_inst: CardInstance = null
	for inst in agent.hand:
		if inst.card_data.id == "void_rift_lord" and rl_inst == null:
			rl_inst = inst
		elif inst.card_data.id == "rift_tender" and tender_inst == null:
			tender_inst = inst

	if rl_inst == null:
		# No Rift Lord in hand — just try to play it from spark pool if available
		return

	var rl_spark_cost: int = _effective_spark_cost(rl_inst.card_data)
	var rl_essence: int = (rl_inst.card_data as MinionCardData).essence_cost
	var current_sparks: int = _available_sparks()

	# Can play RL directly without tender combo?
	if current_sparks >= rl_spark_cost and agent.essence >= rl_essence:
		if _empty_slot_count() > 1 or _scene_has("_champion_vh_summoned"):
			await _play_spark_minion_by_id("void_rift_lord")
			return

	# Need tender to generate spark fuel — check if combo is affordable
	if tender_inst == null:
		return  # No tender available
	var tender_essence: int = (tender_inst.card_data as MinionCardData).essence_cost
	var total_essence_needed: int = tender_essence + rl_essence  # 2 + 4 = 6
	if agent.essence < total_essence_needed:
		return  # Can't afford combo yet — hold both cards

	# Sparks after tender: current + 1 (tender summon) — must be >= rl_spark_cost
	if current_sparks + 1 < rl_spark_cost:
		return  # Still not enough sparks even after tender

	# Need: tender(1) + tender's spark(1) = 2 slots. RL consumes the sparks freeing slots.
	if _empty_slot_count() < 2:
		return

	# Execute combo: Tender first, then RL
	var slot1: BoardSlot = agent.find_empty_slot()
	if slot1 == null:
		return
	agent.essence -= tender_essence
	if not await agent.commit_play_minion(tender_inst, slot1, null):
		return
	if not agent.is_alive():
		return
	# Now play RL with the spark from tender
	await _play_spark_minion_by_id("void_rift_lord")

## Combo: Spirit Surge (2M) → Void Rift Lord (4E + 2sparks with mastery).
## Surge summons a spark. With passive spark = 2 sparks on board. RL consumes both.
## Total: 4E + 2M. Available turn 5 with growth (4E + 2M).
func _try_surge_rl_combo() -> void:
	var surge_inst: CardInstance = null
	var rl_inst: CardInstance = null
	for inst in agent.hand:
		if inst.card_data.id == "spirit_surge" and surge_inst == null:
			surge_inst = inst
		elif inst.card_data.id == "void_rift_lord" and rl_inst == null:
			rl_inst = inst
	if surge_inst == null or rl_inst == null:
		return
	var rl_mc := rl_inst.card_data as MinionCardData
	var rl_spark_cost: int = _effective_spark_cost(rl_mc)
	var surge_cost: int = agent.effective_spell_cost(surge_inst.card_data as SpellCardData)
	# Need: 4E for RL + 2M for Surge
	if rl_mc.essence_cost > agent.essence or surge_cost > agent.mana:
		return
	# After Surge: current sparks + 1 (surge summon) must be >= rl_spark_cost
	if _available_sparks() + 1 < rl_spark_cost:
		return
	# Need 1 slot for surge's spark + 1 for RL = 2 slots
	if _empty_slot_count() < 2:
		return
	# Execute: Surge first (summons spark), then RL (consumes sparks)
	agent.mana -= surge_cost
	if not await agent.commit_play_spell(surge_inst, null):
		return
	if not agent.is_alive():
		return
	# Now play RL with the sparks
	await _play_spark_minion_by_id("void_rift_lord")

## Combo: Spirit Surge (2M, tutor + summon spark) → Void Pulse (1M + 1spark, draw 3).
## Total: 3M for tutor a spark-cost card + draw 3 + a spark on board.
func _try_surge_pulse_combo() -> void:
	var surge_inst: CardInstance = null
	var pulse_inst: CardInstance = null
	for inst in agent.hand:
		if inst.card_data.id == "spirit_surge" and surge_inst == null:
			surge_inst = inst
		elif inst.card_data.id == "void_pulse" and pulse_inst == null:
			pulse_inst = inst
	if surge_inst == null or pulse_inst == null:
		return
	# Need 3M total (2M surge + 1M pulse)
	var surge_cost: int = agent.effective_spell_cost(surge_inst.card_data as SpellCardData)
	var pulse_cost: int = agent.effective_spell_cost(pulse_inst.card_data as SpellCardData)
	if surge_cost + pulse_cost > agent.mana:
		return
	# Need 1 empty slot for the spark that Surge summons
	if _empty_slot_count() < 1:
		return
	# Play Surge first — tutors a spark-cost card + summons a spark
	agent.mana -= surge_cost
	if not await agent.commit_play_spell(surge_inst, null):
		return
	if not agent.is_alive():
		return
	# Now play Pulse — consumes the spark Surge just summoned
	var pulse_spark_cost: int = _effective_spark_cost(pulse_inst.card_data)
	if pulse_spark_cost > 0:
		var plan := _plan_spark_payment(pulse_spark_cost)
		if plan.is_empty():
			return
		await _pay_sparks_smart(plan, DeckType.AGGRO)
		if not agent.is_alive():
			return
	agent.mana -= pulse_cost
	await agent.commit_play_spell(pulse_inst, null)

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
			if sc > 0:
				var plan := _plan_spark_payment(sc)
				if plan.is_empty(): return
				await _pay_sparks_smart(plan, DeckType.AGGRO)
				if not agent.is_alive(): return
			agent.mana -= agent.effective_spell_cost(spell)
			if not await agent.commit_play_spell(best, pick_spell_target(spell)):
				return
			cast = true

## Play a specific spark-cost minion by ID.
func _play_spark_minion_by_id(target_id: String) -> bool:
	var _dbg: bool = agent.scene.get("debug_log_enabled") if agent.scene.get("debug_log_enabled") != null else false
	for inst in agent.hand.duplicate():
		if not (inst.card_data is MinionCardData):
			continue
		if inst.card_data.id != target_id:
			continue
		if not _can_afford_spark_card(inst.card_data):
			if _dbg:
				var mc := inst.card_data as MinionCardData
				var sc := _effective_spark_cost(mc)
				print("    [AI] SKIP %s: can't afford (need %dE+%dS, have %dE+%dS avail)" % [target_id, mc.essence_cost, sc, agent.essence, _available_sparks()])
			return false
		# Leave 1 slot for passive spark generation (unless champion suppressed it)
		var vh_alive := _scene_has("_champion_vh_summoned")
		if not vh_alive and _empty_slot_count() <= 1:
			return false
		var slot: BoardSlot = agent.find_empty_slot()
		if slot == null:
			return false
		var mc := inst.card_data as MinionCardData
		var sc: int = _effective_spark_cost(mc)
		if sc > 0:
			var plan := _plan_spark_payment(sc)
			if plan.is_empty():
				return false
			await _pay_sparks_smart(plan, DeckType.AGGRO)
			if not agent.is_alive():
				return false
		agent.essence -= mc.essence_cost
		agent.mana    -= agent.effective_minion_mana_cost(mc)
		if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
			return false
		return true
	return false

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
			# Leave 1 slot for spark (unless champion suppressed generation)
			var vh_alive := _scene_has("_champion_vh_summoned")
			if not vh_alive and _empty_slot_count() <= 1:
				continue
			# Rift Tender: needs extra slot for spark summon
			if mc.id == "rift_tender" and not vh_alive and _empty_slot_count() < 3:
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

func _spark_spell_priority(id: String) -> int:
	match id:
		"void_pulse":         return 3
		"rift_collapse":      return 2
		"dimensional_breach": return 1
	return 0

func _has_rift_lord_in_hand() -> bool:
	for inst in agent.hand:
		if inst.card_data.id == "void_rift_lord":
			return true
	return false

func _scene_has(field: String) -> bool:
	var val = agent.scene.get(field)
	return val != null and val == true
