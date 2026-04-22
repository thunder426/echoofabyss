## VoidRitualistPrimeProfile.gd
## AI profile for the Void Ritualist Prime encounter (Act 4, Fight 13).
##
## Passive: void_might (shared) + dark_channeling (when the enemy casts a
## damage spell, consume 1 Critical Strike from a random friendly minion
## to deal 1.5x spell damage).
##
## Strategy: Spell-heavy deck. Play spirits and heralds first to stack crits,
## then cast damage spells (void_bolt, arcane_strike, sovereigns_decree)
## which get amplified by dark_channeling. Minion-first order ensures crits
## are on the board before damage spells fire.
##
## Play order:
##   1. Regular spirits + heralds (crits via herald + void_might)
##   2. Regular mana spells (void_bolt, arcane_strike — amplified by channeling)
##   3. Spark-cost spells (Sovereign's Decree for hero damage + corruption)
##   4. Spark-cost minions
##
## Resource growth:
##   Essence stays at 2 → Mana to 4 → Essence to 3 → Mana to 6 → Essence to 4 → Mana to 7
##   (mana-heavier than other Act 4 profiles — deck is spell-focused)
class_name VoidRitualistPrimeProfile
extends VoidScoutProfile

## Hold Arcane Strike while a friendly crit-carrier is on board — save crit
## consumes for bigger damage spells (Shatter/Lance/Bolt).
func can_cast_spell(spell: SpellCardData) -> bool:
	if not super.can_cast_spell(spell):
		return false
	if spell.id == "arcane_strike":
		for m: MinionInstance in agent.friendly_board:
			if m.has_critical_strike():
				return false
	return true

## Override turn order: mana spells BEFORE spark spells so amplified damage fires
## while crits are fresh; spark spells (Rift Collapse) only relevant vs board.
func play_phase() -> void:
	await _play_heralds()
	if not agent.is_alive(): return
	await _play_regular_minions()
	if not agent.is_alive(): return
	await _play_spells_pass()          # mana spells first (Shatter/Lance/Bolt/Arcane Strike)
	if not agent.is_alive(): return
	await _play_spark_spells()         # Rift Collapse / Void Pulse (parent skips Collapse when enemy board < 2)

## Spark spell priority — Decree (hero dmg + board corruption) > Collapse (AoE) > Pulse (draw).
func _spark_spell_priority(id: String) -> int:
	match id:
		"sovereigns_decree": return 4
		"rift_collapse":     return 3
		"void_pulse":        return 2
	return 0

## Override parent gate: parent skips all spark spells when opponent board < 2.
## We want Void Pulse (draw) to fire regardless, and only skip Rift Collapse
## specifically when opponent has zero minions.
func _play_spark_spells() -> void:
	var cast := true
	while cast:
		cast = false
		var spark_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if not (inst.card_data is SpellCardData):
				continue
			if inst.card_data.void_spark_cost <= 0:
				continue
			# Skip Rift Collapse when opponent has no minions (wasted cast).
			if inst.card_data.id == "rift_collapse" and agent.scene._opponent_board("enemy").is_empty():
				continue
			spark_hand.append(inst)
		spark_hand.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
			return _spark_spell_priority(a.card_data.id) > _spark_spell_priority(b.card_data.id))
		for inst in spark_hand:
			var spell := inst.card_data as SpellCardData
			var sc: int = _effective_spark_cost(spell)
			if agent.effective_spell_cost(spell) > agent.mana:
				continue
			# ritualist_spark_free passive makes sc == 0 → skip payment, just cast.
			if sc > 0:
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

## Override: cast most expensive damage spells first so Dark Channeling's
## 1.5x crit consume lands on the biggest hit (Shatter > Lance > Bolt > Arcane Strike).
## Void Pulse and other utility spells fall through to cheapest-last naturally.
func _play_spells_pass() -> void:
	var cast := true
	while cast:
		cast = false
		var spell_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is SpellCardData and inst.card_data.void_spark_cost <= 0:
				spell_hand.append(inst)
		spell_hand.sort_custom(_sort_mana_spell_priority)
		for inst in spell_hand:
			var spell := inst.card_data as SpellCardData
			var cost: int = agent.effective_spell_cost(spell)
			if cost > agent.mana:
				continue
			if not can_cast_spell(spell):
				continue
			agent.mana -= cost
			if not await agent.commit_play_spell(inst, pick_spell_target(spell)):
				return
			cast = true
			break

## Higher value = cast first. Shatter (biggest single amplified burst) > Lance > Bolt > Arcane Strike.
func _mana_spell_priority(id: String) -> int:
	match id:
		"void_shatter":   return 4
		"void_lance":     return 3
		"void_bolt":      return 2
		"arcane_strike":  return 1
	return 0

func _sort_mana_spell_priority(a: CardInstance, b: CardInstance) -> bool:
	var pa: int = _mana_spell_priority(a.card_data.id)
	var pb: int = _mana_spell_priority(b.card_data.id)
	if pa != pb:
		return pa > pb
	# Tiebreak: more expensive first (still favors amplified big hits)
	return a.card_data.cost > b.card_data.cost

# ---------------------------------------------------------------------------
# Resource growth — mana-heavier for spell-focused deck
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_ritualist_prime_growth(sim_state, turn)

func _ritualist_prime_growth(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e: int = state.enemy_essence_max
	var m: int = state.enemy_mana_max
	if e + m >= 11:
		return
	# Growth order: E2 → M4 → E3 → M6 → E4 → M7 (no growth beyond 2E on turn 1)
	if m < 4:
		state.enemy_mana_max += 1
	elif e < 3:
		state.enemy_essence_max += 1
	elif m < 6:
		state.enemy_mana_max += 1
	elif e < 4:
		state.enemy_essence_max += 1
	else:
		state.enemy_mana_max += 1
