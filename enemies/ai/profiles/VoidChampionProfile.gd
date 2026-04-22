## VoidChampionProfile.gd
## AI profile for the Void Champion encounter (Act 4, Fight 14).
##
## Passive: void_might (shared) + champion_duel (enemy minions with any
## Critical Strike stacks are granted SPELL_IMMUNE; when a crit is consumed,
## immunity is removed). This makes crit both an offensive AND defensive tool.
##
## Strategy: Spread crits across the board for maximum spell immunity coverage.
## Throne's Command (mass crit) is the top spark priority — it grants
## spell immunity to the entire board. Herald targets the highest-HP
## friendly WITHOUT crit, ensuring new minions get protection first.
## Bastion Colossus is exceptionally strong here: 600/800 Guard that
## self-grants 2 crit stacks = instant spell immunity on summon.
##
## Play order:
##   1. Regular spirits + heralds (crits via herald spread protection)
##   2. Regular mana spells
##   3. Spark-cost spells (Throne's Command = mass spell immunity)
##   4. Spark-cost minions (Bastion Colossus self-crits)
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7
class_name VoidChampionProfile
extends VoidScoutProfile

## Throne's Command = mass crit = mass spell immunity. Highest priority.
## Dimensional Breach is not damage, handled separately via combo routine.
func _spark_spell_priority(id: String) -> int:
	match id:
		"thrones_command":   return 5
		"rift_collapse":     return 3
		"void_pulse":        return 2
	return 0

## Override turn order — strict priority: Breach (if enables combo or board room)
## → Bastion → Behemoth → Architect → Herald → rest → spells.
func play_phase() -> void:
	await _priority_pass()
	if not agent.is_alive(): return
	await _play_spells_pass()               # mana-only spells
	if not agent.is_alive(): return
	await _play_spark_spells()              # Throne's Command, Void Pulse

## One pass through the priority order. Loops until no more progress can be made.
func _priority_pass() -> void:
	var placed := true
	while placed:
		placed = false
		# 1. Breach — only if board has room for a big body AND Breach enables a combo.
		if await _try_breach_if_enables_combo():
			placed = true
			continue
		# 2. Bastion
		if await _play_big_body("bastion_colossus"):
			placed = true
			continue
		# 3. Behemoth
		if await _play_big_body("void_behemoth"):
			placed = true
			continue
		# 4. Architect (3E ramp)
		if await _play_simple_minion("void_architect"):
			placed = true
			continue
		# 5. Herald (only if there's an attackable target — reuses parent logic)
		if await _play_one_herald():
			placed = true
			continue
		# 6. Rest — regular spirit bodies (wisps, shades, phase stalker)
		if await _play_one_regular_body():
			placed = true
			continue

## Cast Dimensional Breach only when it enables summoning Bastion or Behemoth THIS TURN.
func _try_breach_if_enables_combo() -> bool:
	var breach_inst: CardInstance = _find_in_hand("dimensional_breach")
	if breach_inst == null:
		return false
	var breach_cost: int = agent.effective_spell_cost(breach_inst.card_data as SpellCardData)
	if breach_cost > agent.mana:
		return false
	if agent.find_empty_slot() == null:
		return false  # no room for the combo target
	# Does Breach enable Bastion OR Behemoth this turn?
	var sparks_after: int = _available_sparks() + 2
	var mana_after: int = agent.mana - breach_cost
	for id in ["bastion_colossus", "void_behemoth"]:
		var inst := _find_in_hand(id)
		if inst == null:
			continue
		var mc := inst.card_data as MinionCardData
		if mc.essence_cost > agent.essence:
			continue
		var body_mana: int = agent.effective_minion_mana_cost(mc)
		var shortfall: int = maxi(0, mc.void_spark_cost - sparks_after)
		if shortfall > 0 and not _has_mana_for_spark():
			continue
		if body_mana + shortfall > mana_after:
			continue
		# Combo viable — cast Breach.
		agent.mana -= breach_cost
		if not await agent.commit_play_spell(breach_inst, null):
			return false
		return true
	return false

## Play one simple essence+mana minion by id (no spark cost expected).
func _play_simple_minion(id: String) -> bool:
	var inst: CardInstance = _find_in_hand(id)
	if inst == null:
		return false
	var mc := inst.card_data as MinionCardData
	var mana_cost: int = agent.effective_minion_mana_cost(mc)
	if mc.essence_cost > agent.essence or mana_cost > agent.mana:
		return false
	var slot: BoardSlot = agent.find_empty_slot()
	if slot == null:
		return false
	agent.essence -= mc.essence_cost
	agent.mana -= mana_cost
	if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
		return false
	return true

## Play one Herald if there's an attackable non-Herald target.
func _play_one_herald() -> bool:
	var has_attackable := false
	for m: MinionInstance in agent.friendly_board:
		if m.card_data.id != "sovereigns_herald" and m.can_attack():
			has_attackable = true
			break
	if not has_attackable:
		return false
	return await _play_simple_minion("sovereigns_herald")

## Play one "rest" minion — cheap bodies (wisp/shade/phase_stalker). Cheapest first.
func _play_one_regular_body() -> bool:
	var skip_ids: Array[String] = [
		"sovereigns_herald", "bastion_colossus", "void_behemoth", "void_architect",
	]
	var candidates: Array[CardInstance] = []
	for inst in agent.hand:
		if not (inst.card_data is MinionCardData):
			continue
		if inst.card_data.id in skip_ids:
			continue
		candidates.append(inst)
	candidates.sort_custom(agent.sort_by_total_cost)
	for inst in candidates:
		var mc := inst.card_data as MinionCardData
		var mana_cost: int = agent.effective_minion_mana_cost(mc)
		if mc.essence_cost > agent.essence or mana_cost > agent.mana:
			continue
		# phase_stalker has spark cost — pay if we can, otherwise skip.
		if mc.void_spark_cost > 0:
			var sparks: int = _available_sparks()
			var shortfall: int = maxi(0, mc.void_spark_cost - sparks)
			if shortfall > 0 and not _has_mana_for_spark():
				continue
			if mana_cost + shortfall > agent.mana:
				continue
			var spark_to_pay: int = mini(sparks, mc.void_spark_cost)
			if spark_to_pay > 0:
				var plan := _plan_spark_payment_no_crit(spark_to_pay)
				if not plan.is_empty():
					await _pay_sparks_smart(plan, DeckType.AGGRO)
					if not agent.is_alive(): return false
			mana_cost += shortfall
		var slot: BoardSlot = agent.find_empty_slot()
		if slot == null:
			return false
		agent.essence -= mc.essence_cost
		agent.mana -= mana_cost
		if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
			return false
		return true
	return false

## Play Behemoth / Bastion if affordable right now (essence + mana + sparks, using
## mana_for_spark substitution when active).
func _play_big_body(id: String) -> bool:
	var inst: CardInstance = _find_in_hand(id)
	if inst == null:
		return false
	var mc := inst.card_data as MinionCardData
	if mc.essence_cost > agent.essence:
		return false
	var body_mana: int = agent.effective_minion_mana_cost(mc)
	var sparks: int = _available_sparks()
	var shortfall: int = maxi(0, mc.void_spark_cost - sparks)
	if shortfall > 0 and not _has_mana_for_spark():
		return false
	if body_mana + shortfall > agent.mana:
		return false
	var slot: BoardSlot = agent.find_empty_slot()
	if slot == null:
		return false
	# Pay sparks: consume what we have (up to spark cost) as non-crit fuel preferred.
	if mc.void_spark_cost > 0:
		var spark_to_pay: int = mini(sparks, mc.void_spark_cost)
		if spark_to_pay > 0:
			var plan := _plan_spark_payment_no_crit(spark_to_pay)
			if not plan.is_empty():
				await _pay_sparks_smart(plan, DeckType.AGGRO)
				if not agent.is_alive(): return false
	agent.essence -= mc.essence_cost
	agent.mana -= body_mana + shortfall
	if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
		return false
	return true

func _find_in_hand(id: String) -> CardInstance:
	for inst in agent.hand:
		if inst.card_data.id == id:
			return inst
	return null

func _has_mana_for_spark() -> bool:
	var passives = agent.scene.get("_active_enemy_passives")
	return passives != null and "mana_for_spark" in passives

# ---------------------------------------------------------------------------
# Herald targeting: spread crit for spell immunity coverage
# ---------------------------------------------------------------------------

func pick_on_play_target(mc: MinionCardData):
	if mc.id == "sovereigns_herald":
		return _pick_champion_crit_target()
	return super.pick_on_play_target(mc)

## Override: exclude big-body spark minions so they flow through the combo path
## (_try_breach_big_body_combo / _play_big_body) with proper spark-cost accounting.
func _play_regular_minions() -> void:
	var placed := true
	while placed:
		placed = false
		var minion_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if not (inst.card_data is MinionCardData):
				continue
			var id: String = inst.card_data.id
			if id == "sovereigns_herald" or id == "bastion_colossus" or id == "void_behemoth":
				continue
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

## Resource growth override: E4 → M4 → E5 → M5 → E6 (cap 11 combined).
## More mana-forward than parent to enable Throne's Command + mana_for_spark substitution.
func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_void_champion_growth(sim_state, turn)

func _void_champion_growth(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e: int = state.enemy_essence_max
	var m: int = state.enemy_mana_max
	if e + m >= 11:
		return
	# Growth order: E4 → M4 → E5 → M5 → E6
	if e < 4:
		state.enemy_essence_max += 1
	elif m < 4:
		state.enemy_mana_max += 1
	elif e < 5:
		state.enemy_essence_max += 1
	elif m < 5:
		state.enemy_mana_max += 1
	else:
		state.enemy_essence_max += 1

## Target the highest-HP friendly minion WITHOUT crit (needs spell immunity).
## If all minions already have crit, fall back to highest ATK (extra stacks).
func _pick_champion_crit_target() -> MinionInstance:
	var best: MinionInstance = null
	for m: MinionInstance in agent.friendly_board:
		if m.has_critical_strike():
			continue
		if best == null or m.current_health > best.current_health:
			best = m
	if best != null:
		return best
	# All have crit — stack on highest ATK for more attack charges
	return _pick_highest_atk_friendly()
