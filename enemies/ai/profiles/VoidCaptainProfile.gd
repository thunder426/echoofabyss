## VoidCaptainProfile.gd
## AI profile for the Void Captain encounter (Act 4, Fight 12).
##
## Passives: void_might (shared) + captain_orders (TC costs 1 less spark;
##           at end of turn, consume 1 crit from each minion → deal ATK to hero).
##
## Strategy: Stack crits via Herald + Throne's Command on a wide board.
## Crits auto-cash at end of turn for face damage, so wide crit distribution wins.
## Bastion Colossus is the late-game finisher (Guard + self-crits).
##
## Play order:
##   1. Regular minions (board presence for TC targets)
##   2. Sovereign's Herald (crit to strongest attacker)
##   3. Throne's Command (mass crit — only when 2+ friendly minions)
##   4. Other spark-cost spells (Rift Collapse — AoE)
##   5. Bastion Colossus (spark-cost minion — late game)
##   6. Mana-only spells
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7
class_name VoidCaptainProfile
extends VoidScoutProfile

func play_phase() -> void:
	# Phase 1: Regular minions (bodies for crit targets)
	await _play_regular_minions()
	if not agent.is_alive(): return
	# Phase 2: Sovereign's Herald (crit to strongest attacker)
	await _play_heralds()
	if not agent.is_alive(): return
	# Phase 3: Throne's Command (mass crit — only when 2+ friendly minions)
	await _play_thrones_command()
	if not agent.is_alive(): return
	# Phase 4: Other spark-cost spells (Rift Collapse — AoE when opponent has 2+)
	await _play_spark_spells_aoe()
	if not agent.is_alive(): return
	# Phase 5: Rift Warden (signature — GUARD ETHEREAL, aura damage)
	await _play_spark_minion_by_id("rift_warden")
	if not agent.is_alive(): return
	# Phase 6: Bastion Colossus (big finisher)
	await _play_spark_minion_by_id("bastion_colossus")
	if not agent.is_alive(): return
	# Phase 8: Void Wind against runes
	await _try_void_wind()
	if not agent.is_alive(): return
	# Phase 9: Mana-only spells
	await _play_spells_pass()

# ---------------------------------------------------------------------------
# Resource growth — E to 5 → M to 3 → E to 7
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_void_captain_growth(sim_state, turn)

func _void_captain_growth(state: Object, turn: int) -> void:
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
# Throne's Command — mass crit, only when 2+ friendly minions on board
# ---------------------------------------------------------------------------

func _play_thrones_command() -> void:
	if agent.friendly_board.size() < 2:
		return
	for inst in agent.hand.duplicate():
		if inst.card_data.id != "thrones_command":
			continue
		var spell := inst.card_data as SpellCardData
		var sc: int = _effective_spark_cost(spell)
		if agent.effective_spell_cost(spell) > agent.mana:
			continue
		if sc > 0:
			var plan := _plan_spark_payment_no_crit(sc)
			if plan.is_empty():
				continue
			await _pay_sparks_smart(plan, DeckType.AGGRO)
			if not agent.is_alive(): return
		agent.mana -= agent.effective_spell_cost(spell)
		if not await agent.commit_play_spell(inst, pick_spell_target(spell)):
			return
		return

# ---------------------------------------------------------------------------
# Spark-cost AoE spells (Rift Collapse) — only when opponent has 2+ minions
# ---------------------------------------------------------------------------

func _play_spark_spells_aoe() -> void:
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
			if inst.card_data.id == "thrones_command":
				continue  # Already handled
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

# ---------------------------------------------------------------------------
# Spark-cost minion (Bastion Colossus) — inherited from VoidWarband pattern
# ---------------------------------------------------------------------------

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
		return true
	return false

## Throne's Command is highest priority — mass crit at 2.5x multiplier.
func _spark_spell_priority(id: String) -> int:
	match id:
		"thrones_command":   return 5
		"rift_collapse":     return 3
		"void_pulse":        return 2
	return 0
