## VoidScoutProfile.gd
## AI profile for the Void Scout encounter (Act 4, Fight 10).
##
## Passives: void_might (shared Act 4, +1 crit to random minion each turn)
##           + void_precision (crit consumed → +200 ATK permanent)
##
## Strategy: Flood board with cheap Spirit minions, stack crits via
## Sovereign's Herald and void_might passive. Crit minions snowball
## via void_precision (+200 ATK per crit used). Tempo trading to
## protect high-ATK crit-buffed minions.
##
## Play order:
##   1. Sovereign's Herald first (grants crit to strongest minion)
##   2. Other regular minions (void_wisp, void_echo, void_shade, void_wraith)
##   3. Mana-only spells
##
## Resource growth:
##   Essence to 5 → Mana to 2 → Essence to 7
class_name VoidScoutProfile
extends CombatProfile

func play_phase() -> void:
	# Phase 1: Sovereign's Herald first (crit enabler — highest priority)
	await _play_heralds()
	if not agent.is_alive(): return
	# Phase 2: Other regular minions (cheap bodies for crit targets)
	await _play_regular_minions()
	if not agent.is_alive(): return
	# Phase 3: Spark-cost spells (Rift Collapse) — consume non-crit fuel
	await _play_spark_spells()
	if not agent.is_alive(): return
	# Phase 4: Void Wind — only against runes
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

## Cast Void Wind when opponent has any rune.
func _try_void_wind() -> void:
	var opponent_traps: Array = agent.scene._opponent_traps("enemy")
	if opponent_traps.is_empty():
		return
	var has_rune := false
	for trap in opponent_traps:
		if trap is TrapCardData and (trap as TrapCardData).is_rune:
			has_rune = true
			break
	if not has_rune:
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
	elif m < 2:
		state.enemy_mana_max += 1
	else:
		state.enemy_essence_max += 1

# ---------------------------------------------------------------------------
# Board awareness
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
# On-play targeting: Herald grants crit to highest-ATK friendly minion
# ---------------------------------------------------------------------------

func pick_on_play_target(mc: MinionCardData):
	if mc.id == "sovereigns_herald":
		return _pick_crit_target()
	return super.pick_on_play_target(mc)

## Legacy alias for child profiles.
func _pick_highest_atk_friendly() -> MinionInstance:
	return _pick_crit_target()

## Pick the best target for Sovereign's Herald crit grant.
## Priority: 1. Can attack this turn + no crit yet + highest ATK
##           2. Can attack this turn + highest ATK (even if has crit)
##           3. Any non-herald minion (fallback)
func _pick_crit_target() -> MinionInstance:
	# Pass 1: attackable minion without crit — best value
	var best_no_crit: MinionInstance = null
	for m: MinionInstance in agent.friendly_board:
		if m.card_data.id == "sovereigns_herald":
			continue
		if not m.can_attack():
			continue
		if m.has_critical_strike():
			continue
		if best_no_crit == null or m.effective_atk() > best_no_crit.effective_atk():
			best_no_crit = m
	if best_no_crit != null:
		return best_no_crit

	# Pass 2: attackable minion (even with crit) — stacking is still useful
	var best_attackable: MinionInstance = null
	for m: MinionInstance in agent.friendly_board:
		if m.card_data.id == "sovereigns_herald":
			continue
		if not m.can_attack():
			continue
		if best_attackable == null or m.effective_atk() > best_attackable.effective_atk():
			best_attackable = m
	if best_attackable != null:
		return best_attackable

	# Pass 3: any non-herald minion
	var best_any: MinionInstance = null
	for m: MinionInstance in agent.friendly_board:
		if m.card_data.id == "sovereigns_herald":
			continue
		if best_any == null or m.effective_atk() > best_any.effective_atk():
			best_any = m
	return best_any

# ---------------------------------------------------------------------------
# Play phases
# ---------------------------------------------------------------------------

## Play Sovereign's Heralds — only when there's an attackable non-Herald target.
## This ensures the crit is used this turn, not wasted on an exhausted minion.
func _play_heralds() -> void:
	var placed := true
	while placed:
		placed = false
		# Check if there's an attackable target for crit
		var has_attackable_target := false
		for m: MinionInstance in agent.friendly_board:
			if m.card_data.id != "sovereigns_herald" and m.can_attack():
				has_attackable_target = true
				break
		if not has_attackable_target:
			return  # Hold heralds until there's something to buff
		for inst in agent.hand.duplicate():
			if inst.card_data.id != "sovereigns_herald":
				continue
			var mc := inst.card_data as MinionCardData
			if mc.essence_cost > agent.essence:
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return
			agent.essence -= mc.essence_cost
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

## Play spark-cost spells — only when opponent has 2+ minions (AoE value).
## Consumes cheapest non-crit fuel to preserve crit-buffed minions.
func _play_spark_spells() -> void:
	if agent.scene._opponent_board("enemy").size() < 2:
		return
	var cast := true
	while cast:
		cast = false
		for inst in agent.hand.duplicate():
			if not (inst.card_data is SpellCardData):
				continue
			if inst.card_data.void_spark_cost <= 0:
				continue
			var spell := inst.card_data as SpellCardData
			var sc: int = _effective_spark_cost(spell)
			if agent.effective_spell_cost(spell) > agent.mana:
				continue
			var plan := _plan_spark_payment_no_crit(sc)
			if plan.is_empty():
				continue
			await _pay_sparks_smart(plan, DeckType.AGGRO)
			if not agent.is_alive(): return
			agent.mana -= agent.effective_spell_cost(spell)
			if not await agent.commit_play_spell(inst, pick_spell_target(spell)):
				return
			cast = true
			break

func _play_spark_minions() -> void:
	pass

## Plan spark payment preferring non-crit minions. Falls back to base if needed.
func _plan_spark_payment_no_crit(cost: int) -> Array[MinionInstance]:
	if cost <= 0:
		return []
	# Gather fuel without crit first
	var no_crit: Array[MinionInstance] = []
	for m: MinionInstance in agent.friendly_board:
		var sv: int = (m.card_data as MinionCardData).spark_value
		if sv > 0 and sv <= cost and not m.has_critical_strike():
			no_crit.append(m)
	# Sort by value ascending (cheapest first)
	no_crit.sort_custom(func(a: MinionInstance, b: MinionInstance) -> bool:
		return (a.effective_atk() + a.current_health) < (b.effective_atk() + b.current_health))
	var plan: Array[MinionInstance] = []
	var remaining := cost
	for m: MinionInstance in no_crit:
		if remaining <= 0:
			break
		plan.append(m)
		remaining -= (m.card_data as MinionCardData).spark_value
	if remaining <= 0:
		return plan
	# Not enough non-crit fuel — fall back to base payment
	return _plan_spark_payment(cost)

## Play regular (non-Herald) minions — cheap bodies for crit targets.
func _play_regular_minions() -> void:
	var placed := true
	while placed:
		placed = false
		var minion_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is MinionCardData and inst.card_data.id != "sovereigns_herald":
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
