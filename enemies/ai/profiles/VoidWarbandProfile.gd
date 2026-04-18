## VoidWarbandProfile.gd
## AI profile for the Void Warband encounter (Act 4, Fight 11).
##
## Passives: void_might (shared) + spirit_resonance (Spirits with crit have +1 spark_value)
##
## Strategy: Build a wide board of Spirits. void_might + Sovereign's Herald
## grant crits, which boost spark_value via spirit_resonance. Consume crit-buffed
## Spirits as fuel for spark-cost minions (Void Behemoth, Bastion Colossus).
##
## Play order (turn-gated priority):
##   Early (turn ≤ 4): Behemoth primary — focus on summoning Behemoth every turn.
##     Don't attack with crit-Spirits when Behemoth is playable (preserve fuel).
##   Late (turn ≥ 5): Bastion primary — try Bastion first, fall back to Behemoth.
##     Never save resources; if Bastion can't be summoned, play Behemoth instead.
##
## Resource growth:
##   Essence to 5 → Mana to 2 → Essence to 7 → Mana to 3
class_name VoidWarbandProfile
extends CombatProfile

const _LATE_TURN_THRESHOLD := 5

func play_phase() -> void:
	# Phase A: Void Lance — pure removal, highest priority if it has a target.
	#          Cast BEFORE Surge so Lance's 2M isn't blocked by Surge.
	await _play_void_lance()
	if not agent.is_alive(): return
	# Phase B: Spirit Surge — tutors a spark-cost card and summons a Void Spark.
	#          Only cast if it's actually useful (no spark card in hand OR no fuel).
	await _play_spirit_surge()
	if not agent.is_alive(): return
	# Phase 1: Cheap regular minions (board building)
	await _play_cheap_minions()
	if not agent.is_alive(): return
	# Phase 2: Sovereign's Herald (crit enabler)
	await _play_heralds()
	if not agent.is_alive(): return
	# Phase 3: Spark-cost minions (turn-gated priority)
	if _current_turn() >= _LATE_TURN_THRESHOLD:
		# Late game: Bastion first, fall through to Behemoth if Bastion can't be played
		await _play_spark_minion_by_id("bastion_colossus")
		if not agent.is_alive(): return
		while await _play_spark_minion_by_id("void_behemoth"):
			if not agent.is_alive(): return
	else:
		# Early game: Behemoth primary (cheaper, reliable)
		while await _play_spark_minion_by_id("void_behemoth"):
			if not agent.is_alive(): return
		# Still try Bastion in case fuel/essence stacked up
		await _play_spark_minion_by_id("bastion_colossus")
		if not agent.is_alive(): return
	# Phase 4: Spark-cost spells (Rift Collapse now that Lance is handled)
	await _play_spark_spells()
	if not agent.is_alive(): return
	# Phase 5: Regular mana spells
	await _play_spells_pass()

## Lance and Spirit Surge are handled in dedicated phases (A, B) — skip them
## in the generic spells pass so they don't get double-cast or mis-targeted.
func can_cast_spell(spell: SpellCardData) -> bool:
	if spell.id == "void_lance":
		return false
	if spell.id == "spirit_surge":
		return false
	return super.can_cast_spell(spell)

## Cast Void Lance on the best valid target (HP ≥ 400, highest HP).
## Fires multiple times if Lance is drawn more than once and targets remain.
func _play_void_lance() -> void:
	var cast := true
	while cast:
		cast = false
		for inst in agent.hand.duplicate():
			if inst.card_data.id != "void_lance":
				continue
			var spell := inst.card_data as SpellCardData
			if agent.effective_spell_cost(spell) > agent.mana:
				return
			var target: MinionInstance = _pick_lance_target()
			if target == null:
				return
			agent.mana -= agent.effective_spell_cost(spell)
			if not await agent.commit_play_spell(inst, target):
				return
			cast = true
			break

## Returns current turn number (works for both live scene and sim).
func _current_turn() -> int:
	var scene := agent.scene
	if scene == null:
		return 1
	# Sim exposes _current_turn; live scene exposes turn_manager.turn_number
	if scene.get("_current_turn") != null:
		return scene._current_turn
	if scene.get("turn_manager") != null:
		return scene.turn_manager.turn_number
	return 1

## Override spark payment execution. Crit-Spirit pre-attack rule:
##   - If VW board has at least 1 empty slot, crit-Spirit attacks first (crit fires
##     for face damage), then gets consumed as fuel.
##   - If board is full (no empty slot), skip the attack and consume silently.
## Non-crit fuel always attacks before being consumed (default).
func _pay_sparks_smart(plan: Array[MinionInstance], deck_type: DeckType) -> void:
	for m: MinionInstance in plan:
		if not m.can_attack():
			continue
		if not agent.is_alive():
			return
		var is_crit_spirit: bool = m.card_data.minion_type == Enums.MinionType.SPIRIT \
			and m.has_critical_strike()
		if is_crit_spirit and _empty_slot_count() <= 0:
			# Board full — preserve crit for consume (resonance +1 fuel)
			continue
		if (m.card_data as MinionCardData).spark_value == 1:
			await _fuel_attack(DeckType.AGGRO, m)
		else:
			await _fuel_attack(deck_type, m)
	for m: MinionInstance in plan:
		if agent.friendly_board.has(m):
			agent.consume_minion(m)

func _is_tempo() -> bool:
	return true

## Override attack phase: if any friendly Guard is on board, all minions go face.
## Rationale: Guard absorbs player retaliation, so other minions maximise hero damage.
## Falls through to default behavior if no Guard is present.
func attack_phase() -> void:
	if not _has_friendly_guard():
		await super.attack_phase()
		return
	# Skip lethal / tempo trade pre-passes — we're committing to face.
	var can_go_lethal: bool = _calc_lethal_damage() >= agent.opponent_hp
	if can_go_lethal:
		await _play_lethal_spells()
		if not agent.is_alive(): return
	for minion in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(minion) or not minion.can_attack():
			continue
		# Player guards still block us — hit them first
		var p_guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
		if not p_guards.is_empty():
			var target := _pick_best_guard(minion, p_guards)
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return
			continue
		# Go face
		if minion.can_attack_hero():
			if not await agent.do_attack_hero(minion):
				if not agent.is_alive(): return
		elif not agent.opponent_board.is_empty():
			# SWIFT minions can't hit face — trade into any target
			var target := agent.pick_swift_target(minion)
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return

func _has_friendly_guard() -> bool:
	for m: MinionInstance in agent.friendly_board:
		if m.has_guard():
			return true
	return false

func _get_spell_rules() -> Dictionary:
	return {}

# ---------------------------------------------------------------------------
# Resource growth
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_warband_growth(sim_state, turn)

func _warband_growth(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e: int = state.enemy_essence_max
	var m: int = state.enemy_mana_max
	if e + m >= 11:
		return
	# Lance-override: if essence would normally grow, but we have Void Lance in hand,
	# mana_max is still 1, and a ≥600 HP threat is on the board, bias into mana first.
	if m == 1 and _needs_mana_for_lance():
		state.enemy_mana_max += 1
		return
	# Base curve: Essence to 4 → Mana to 2 → Essence to 7 → Mana to 3
	if e < 4:
		state.enemy_essence_max += 1
	elif m < 2:
		state.enemy_mana_max += 1
	elif e < 7:
		state.enemy_essence_max += 1
	else:
		state.enemy_mana_max += 1

## True if Void Lance is in hand and there's a ≥600 HP enemy threat that it could kill.
func _needs_mana_for_lance() -> bool:
	var has_lance := false
	for inst in agent.hand:
		if inst.card_data.id == "void_lance":
			has_lance = true
			break
	if not has_lance:
		return false
	for m: MinionInstance in agent.opponent_board:
		if m.current_health >= 600:
			return true
	return false

# ---------------------------------------------------------------------------
# Board awareness
# ---------------------------------------------------------------------------

func _empty_slot_count() -> int:
	return agent.empty_slot_count()

# ---------------------------------------------------------------------------
# On-play targeting
# ---------------------------------------------------------------------------

func pick_on_play_target(mc: MinionCardData):
	if mc.id == "sovereigns_herald":
		return _pick_crit_target()
	return super.pick_on_play_target(mc)

## Void Lance: only target minions with HP ≥ 400; prefer highest HP.
func pick_spell_target(spell: SpellCardData):
	if spell.id == "void_lance":
		return _pick_lance_target()
	return super.pick_spell_target(spell)

func _pick_lance_target() -> MinionInstance:
	var best: MinionInstance = null
	for m: MinionInstance in agent.opponent_board:
		if m.current_health < 400:
			continue
		if best == null or m.current_health > best.current_health:
			best = m
	return best

## Pick the best crit target.
## Goal: the crit should be USED this turn (either by attacking, or by being
## consumed as fuel for spirit_resonance +1). Crit on a minion that won't attack
## AND won't be consumed is wasted — it may die to player AoE next turn.
##
## Priority tiers (pick highest-scoring in first non-empty tier):
##   1. Attackable + no crit + NOT in predicted fuel plan — crit attacks this turn
##   2. Attackable + no crit + IS in fuel plan — crit boosts fuel via resonance
##   3. Attackable (any crit state) — stack crit on an existing hitter
##   4. Any non-Herald minion — last resort
func _pick_crit_target() -> MinionInstance:
	var fuel_plan_ids: Dictionary = _predict_fuel_plan_ids()
	# Tier 1: attackable, no crit, not in fuel plan
	var best: MinionInstance = _best_in_pool(func(m: MinionInstance) -> bool:
		return m.can_attack() and not m.has_critical_strike() \
			and not fuel_plan_ids.has(m.get_instance_id()))
	if best != null:
		return best
	# Tier 2: attackable, no crit, in fuel plan (resonance payoff)
	best = _best_in_pool(func(m: MinionInstance) -> bool:
		return m.can_attack() and not m.has_critical_strike())
	if best != null:
		return best
	# Tier 3: attackable (any crit state) — stack crit on best hitter
	best = _best_in_pool(func(m: MinionInstance) -> bool:
		return m.can_attack())
	if best != null:
		return best
	# Tier 4: any non-Herald minion
	return _best_in_pool(func(_m: MinionInstance) -> bool: return true)

## Helper: pick the minion with highest (ATK + HP) from friendly_board
## that passes the filter and is not a Herald.
func _best_in_pool(filter: Callable) -> MinionInstance:
	var best: MinionInstance = null
	var best_score := -1
	for m: MinionInstance in agent.friendly_board:
		if m.card_data.id == "sovereigns_herald":
			continue
		if not filter.call(m):
			continue
		var score: int = m.effective_atk() + m.current_health
		if score > best_score:
			best_score = score
			best = m
	return best

## Predict which minions will be consumed as fuel this turn (before spark minions/spells play).
## Returns a set of instance_ids. Simulates the planner for each spark card in hand
## using current board state; does NOT mutate anything.
func _predict_fuel_plan_ids() -> Dictionary:
	var predicted: Dictionary = {}
	# Which spark cards are likely to play this turn? Check hand + affordability roughly.
	var spark_costs_to_pay: Array[int] = []
	for inst in agent.hand:
		var cd := inst.card_data
		if cd.void_spark_cost <= 0:
			continue
		# Minion spark: must afford essence + fuel
		if cd is MinionCardData:
			var mc := cd as MinionCardData
			if mc.essence_cost > agent.essence:
				continue
			if _available_sparks() < cd.void_spark_cost:
				continue
			spark_costs_to_pay.append(cd.void_spark_cost)
		elif cd is SpellCardData:
			var sp := cd as SpellCardData
			if agent.effective_spell_cost(sp) > agent.mana:
				continue
			if _available_sparks() < cd.void_spark_cost:
				continue
			# Lance: only if valid target
			if sp.id == "void_lance" and _pick_lance_target() == null:
				continue
			spark_costs_to_pay.append(cd.void_spark_cost)
	# Sort costs descending so bigger spenders claim fuel first (matches play order priority)
	spark_costs_to_pay.sort_custom(func(a: int, b: int) -> bool: return a > b)
	# For each cost, simulate planner picking non-crit non-predicted minions
	for cost in spark_costs_to_pay:
		var plan := _simulate_plan(cost, predicted)
		for m: MinionInstance in plan:
			predicted[m.get_instance_id()] = true
	return predicted

## Simulate planner greedy pick for a cost, excluding already-predicted minions.
func _simulate_plan(cost: int, exclude: Dictionary) -> Array[MinionInstance]:
	var pool: Array[MinionInstance] = []
	for m: MinionInstance in agent.friendly_board:
		if exclude.has(m.get_instance_id()):
			continue
		var sv: int = m.effective_spark_value(agent.scene)
		if sv > 0 and sv <= cost and not m.has_critical_strike():
			pool.append(m)
	pool.sort_custom(func(a: MinionInstance, b: MinionInstance) -> bool:
		return a.effective_spark_value(agent.scene) > b.effective_spark_value(agent.scene))
	var plan: Array[MinionInstance] = []
	var remaining := cost
	for m: MinionInstance in pool:
		if remaining <= 0:
			break
		plan.append(m)
		remaining -= m.effective_spark_value(agent.scene)
	if remaining > 0:
		return []  # unaffordable, don't reserve
	return plan

# ---------------------------------------------------------------------------
# Play phases
# ---------------------------------------------------------------------------

## True if any spark-cost minion is in hand that we'd want to save a slot for.
func _has_spark_minion_in_hand() -> bool:
	for inst in agent.hand:
		if not (inst.card_data is MinionCardData):
			continue
		if inst.card_data.void_spark_cost > 0:
			return true
	return false

## Cast Spirit Surge if it's valuable. Reasons to cast:
##   1. No spark-cost card in hand yet — tutor fetches one
##   2. Lance is in hand AND we have no fuel for it — summon a Void Spark
##   3. Any spark-cost card is in hand AND available fuel is 0 — summon fuel
func _play_spirit_surge() -> void:
	for inst in agent.hand.duplicate():
		if inst.card_data.id != "spirit_surge":
			continue
		var spell := inst.card_data as SpellCardData
		if agent.effective_spell_cost(spell) > agent.mana:
			return
		if _empty_slot_count() <= 0:
			return
		if not _should_cast_spirit_surge():
			return
		agent.mana -= agent.effective_spell_cost(spell)
		if not await agent.commit_play_spell(inst, null):
			return
		return

## Decide whether casting Spirit Surge is worth the 2M cost.
func _should_cast_spirit_surge() -> bool:
	# Reason 1: no spark-cost card in hand — tutor fetches one
	if not _has_any_spark_card_in_hand():
		return true
	# Reason 2+3: we have spark cards but no fuel → Surge's Void Spark is essential fuel
	if _available_sparks() == 0:
		return true
	return false

## True if any card in hand has void_spark_cost > 0 (minion or spell).
func _has_any_spark_card_in_hand() -> bool:
	for inst in agent.hand:
		if inst.card_data.void_spark_cost > 0:
			return true
	return false

## Play cheap regular minions (non-Herald, non-spark-cost) first.
## Reserves one board slot if a spark-cost minion is waiting in hand.
func _play_cheap_minions() -> void:
	var placed := true
	while placed:
		placed = false
		# Reserve a slot for spark-cost minions if any are in hand.
		var reserve: int = 1 if _has_spark_minion_in_hand() else 0
		if _empty_slot_count() <= reserve:
			return
		var minion_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if not (inst.card_data is MinionCardData):
				continue
			if inst.card_data.void_spark_cost > 0:
				continue
			if inst.card_data.id == "sovereigns_herald":
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

## Play Sovereign's Herald only if there's an attackable non-Herald target.
## Reserves one slot if a spark-cost minion is in hand.
func _play_heralds() -> void:
	var placed := true
	while placed:
		placed = false
		var reserve: int = 1 if _has_spark_minion_in_hand() else 0
		if _empty_slot_count() <= reserve:
			return
		var has_target := false
		for m: MinionInstance in agent.friendly_board:
			if m.card_data.id != "sovereigns_herald" and m.can_attack():
				has_target = true
				break
		if not has_target:
			return
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

## Play a specific spark-cost minion by ID. Consumes non-crit fuel first.
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
		var plan := _plan_spark_payment_no_crit(sc)
		if plan.is_empty():
			return false
		await _pay_sparks_smart(plan, DeckType.AGGRO)
		if not agent.is_alive():
			return false
		agent.essence -= mc.essence_cost
		agent.mana    -= agent.effective_minion_mana_cost(mc)
		if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
			return false
		# Track F11 spark minion plays
		if target_id == "void_behemoth":
			var b: int = agent.scene.get("_vw_behemoth_plays") if agent.scene.get("_vw_behemoth_plays") != null else 0
			agent.scene.set("_vw_behemoth_plays", b + 1)
		elif target_id == "bastion_colossus":
			var c: int = agent.scene.get("_vw_bastion_plays") if agent.scene.get("_vw_bastion_plays") != null else 0
			agent.scene.set("_vw_bastion_plays", c + 1)
		return true
	return false

## Play spark-cost spells (Rift Collapse, Void Lance, Void Pulse). Uses non-crit fuel.
## Void Lance is skipped if no ≥400 HP target exists.
func _play_spark_spells() -> void:
	var cast := true
	while cast:
		cast = false
		for inst in agent.hand.duplicate():
			if not (inst.card_data is SpellCardData):
				continue
			if inst.card_data.void_spark_cost <= 0:
				continue
			var spell := inst.card_data as SpellCardData
			if agent.effective_spell_cost(spell) > agent.mana:
				continue
			var target: Variant = pick_spell_target(spell)
			var sc: int = _effective_spark_cost(spell)
			var plan := _plan_spark_payment_warband(sc)
			if plan.is_empty():
				continue
			await _pay_sparks_smart(plan, DeckType.AGGRO)
			if not agent.is_alive(): return
			agent.mana -= agent.effective_spell_cost(spell)
			if not await agent.commit_play_spell(inst, target):
				return
			cast = true
			break

## Plan spark payment preferring non-crit minions (preserve crit fuel for bigger plays).
func _plan_spark_payment_no_crit(cost: int) -> Array[MinionInstance]:
	return _plan_spark_payment_warband(cost, false)

## Warband planner: prefers non-crit fuel, optionally reserves a Wisp for Lance combo.
## When payer is NOT Lance itself and Lance-with-target is in hand, the planner
## tries to avoid consuming the last Wisp (1-value fuel) so Lance can still be cast.
##
## IMPORTANT: Bastion Colossus and Void Behemoth are NEVER used as fuel.
## Their base spark_value is 0, but with spirit_resonance + crit they'd become
## effective 1 — we explicitly exclude them because they're end-goal cards,
## not fuel. (Bastion grants itself 2 crit on play, making this critical.)
func _plan_spark_payment_warband(cost: int, _is_lance: bool = false) -> Array[MinionInstance]:
	if cost <= 0:
		return []
	# Gather fuel without crit first — exclude big spark consumers
	var no_crit: Array[MinionInstance] = []
	for m: MinionInstance in agent.friendly_board:
		if _is_spark_consumer(m):
			continue
		var sv: int = m.effective_spark_value(agent.scene)
		if sv > 0 and sv <= cost and not m.has_critical_strike():
			no_crit.append(m)
	no_crit.sort_custom(func(a: MinionInstance, b: MinionInstance) -> bool:
		return a.effective_spark_value(agent.scene) > b.effective_spark_value(agent.scene))
	var plan: Array[MinionInstance] = []
	var remaining := cost
	for m: MinionInstance in no_crit:
		if remaining <= 0:
			break
		plan.append(m)
		remaining -= m.effective_spark_value(agent.scene)
	if remaining <= 0:
		return plan
	# Fall back to any fuel, but still exclude spark consumers
	var fallback: Array[MinionInstance] = []
	for m: MinionInstance in agent.friendly_board:
		if _is_spark_consumer(m):
			continue
		var sv: int = m.effective_spark_value(agent.scene)
		if sv > 0 and sv <= cost:
			fallback.append(m)
	fallback.sort_custom(func(a: MinionInstance, b: MinionInstance) -> bool:
		return a.effective_spark_value(agent.scene) > b.effective_spark_value(agent.scene))
	var plan2: Array[MinionInstance] = []
	var remaining2 := cost
	for m: MinionInstance in fallback:
		if remaining2 <= 0:
			break
		plan2.append(m)
		remaining2 -= m.effective_spark_value(agent.scene)
	if remaining2 <= 0:
		return plan2
	return []  # Can't afford without consuming spark consumers — don't cast

## True if this minion is a spark-consumer card that should NEVER be used as fuel.
func _is_spark_consumer(m: MinionInstance) -> bool:
	var id: String = m.card_data.id
	return id == "bastion_colossus" or id == "void_behemoth"
