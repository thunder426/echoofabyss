## SwarmPlayerProfile.gd
## Player bot optimized for the Swarm (Endless Tide) preset deck.
##
## Strategy: Flood board with cheap Void Imps, scale with Shadow Hound,
## use Dominion Rune to buff all Demons, sacrifice tokens for draw + passive
## triggers (Void Spawner / Abyssal Tide), finish with Void Devourer.
##
## Play priority per turn:
##   1. Flux Siphon    — free mana→essence conversion for extra minion plays
##   2. Dominion Rune  — place BEFORE minions so aura buffs on-play
##   3. Void Imps      — flood board, chip damage, imp_evolution triggers
##   4. Shadow Hound   — scales with board count, play after imps
##   5. Other minions  — Void Stalker, Abyssal Brute, Void Spawner, etc.
##   6. Abyssal Sacrifice — draw 2, trigger death passives (Spawner/Tide)
##   7. Remaining spells/traps
##
## Resource growth:
##   Essence-first (board flood priority). Mana catches up when:
##   - Dominion Rune in hand + 3 Demons on board
##   - Abyssal Sacrifice in hand + low hand size + cheap token available
##   - Mana falls more than 2 behind Essence
##   Essence push when a minion in hand costs more than current essence_max.
##
## Attack: Aggro — go face when possible, trade only when under lethal threat
## or when guards block.
class_name SwarmPlayerProfile
extends CombatProfile

func _is_aggro() -> bool:
	return true

# ---------------------------------------------------------------------------
# Play phase — swarm-optimized order
# ---------------------------------------------------------------------------

func play_phase() -> void:
	# 1. Flux Siphon — free conversion, play before anything else
	await _play_spells_by_id(["flux_siphon"])
	if not agent.is_alive(): return
	# 2. Dominion Rune — place BEFORE minions so aura buffs on-play summons
	if _should_place_dominion_rune():
		await _play_traps_pass()
		if not agent.is_alive(): return
	# 3. Void Imps — cheap flood, imp_evolution trigger
	await _play_minions_by_id(["void_imp"])
	if not agent.is_alive(): return
	# 4. Shadow Hound — scales with board, play after imps
	await _play_minions_by_id(["shadow_hound"])
	if not agent.is_alive(): return
	# 5. All other minions — cheapest first (Stalker, Brute, Spawner)
	await _play_minions_pass()
	if not agent.is_alive(): return
	# 6. Dark Empowerment — buff highest HP demon on board
	await _play_dark_empowerment()
	if not agent.is_alive(): return
	# 7. Abyssal Sacrifice — draw 2, trigger death passives
	if _should_sacrifice():
		await _play_spells_by_id(["abyssal_sacrifice"])
		if not agent.is_alive(): return
	# 8. Play any imps/minions drawn from sacrifice
	await _play_minions_by_id(["void_imp"])
	if not agent.is_alive(): return
	await _play_minions_pass()
	if not agent.is_alive(): return
	# 9. Remaining spells and traps
	await _play_spells_pass()
	if not agent.is_alive(): return
	await _play_traps_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"dark_empowerment": {"cast_if": "before_attacks"},  # handled manually in _play_dark_empowerment
		"void_screech":     {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":          {"cast_if": "opponent_has_rune_or_env"},
	}

# ---------------------------------------------------------------------------
# Play decision helpers
# ---------------------------------------------------------------------------

## Cast Dark Empowerment on the highest-HP Demon on board. Skip if no Demon.
func _play_dark_empowerment() -> void:
	var cast := true
	while cast:
		cast = false
		var spell_inst: CardInstance = null
		for inst in agent.hand:
			if inst.card_data is SpellCardData and inst.card_data.id == "dark_empowerment":
				if agent.effective_spell_cost(inst.card_data as SpellCardData) <= agent.mana:
					spell_inst = inst
					break
		if spell_inst == null:
			return
		# Find highest-HP Demon on board
		var best: MinionInstance = null
		for m in agent.friendly_board:
			if m.card_data.minion_type == Enums.MinionType.DEMON:
				if best == null or m.current_health > best.current_health:
					best = m
		if best == null:
			return  # no Demon on board — don't cast
		agent.mana -= agent.effective_spell_cost(spell_inst.card_data as SpellCardData)
		if not await agent.commit_play_spell(spell_inst, best):
			return
		cast = true

## Place Dominion Rune early if we have 2+ Demons on board (buff future plays too).
func _should_place_dominion_rune() -> bool:
	var has_rune := false
	for inst in agent.hand:
		if inst.card_data is TrapCardData and inst.card_data.id == "dominion_rune":
			if inst.effective_cost() <= agent.mana:
				has_rune = true
				break
	if not has_rune:
		return false
	var demon_count := 0
	for m in agent.friendly_board:
		if m.card_data.minion_type == Enums.MinionType.DEMON:
			demon_count += 1
	return demon_count >= 2

## Sacrifice when hand is small and a cheap token is available.
## Don't sacrifice if hand is already large (5+ cards) — save for later.
func _should_sacrifice() -> bool:
	if agent.hand.size() > 4:
		return false
	var has_sacrifice := false
	for inst in agent.hand:
		if inst.card_data is SpellCardData and inst.card_data.id == "abyssal_sacrifice":
			if agent.effective_spell_cost(inst.card_data as SpellCardData) <= agent.mana:
				has_sacrifice = true
				break
	if not has_sacrifice:
		return false
	# Need a cheap token to sacrifice (Void Imp or Void Spark)
	for m in agent.friendly_board:
		var mc := m.card_data as MinionCardData
		if mc.essence_cost + mc.mana_cost <= 1:
			return true
	return false

# ---------------------------------------------------------------------------
# Resource growth — essence-first with mana catches
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.player_growth_override = func(turn: int) -> void:
		_grow_swarm(sim_state, turn)

func _grow_swarm(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e_max: int = state.player_essence_max
	var m_max: int = state.player_mana_max
	if e_max + m_max >= 11:
		return

	# Mana push — Dominion Rune in hand + 3 Demons on board
	if m_max < 2:
		for inst in state.player_hand:
			if inst.card_data is TrapCardData and inst.card_data.id == "dominion_rune":
				if _board_demon_count(state) >= 3:
					state.player_mana_max += 1
					return

	# Mana push — Abyssal Sacrifice in hand + low hand + cheap token
	if m_max < 2:
		for inst in state.player_hand:
			if inst.card_data is SpellCardData and inst.card_data.id == "abyssal_sacrifice":
				if state.player_hand.size() <= 3 and _has_cheap_token(state):
					state.player_mana_max += 1
					return

	# Essence push — minion in hand costs more than current essence_max
	for inst in state.player_hand:
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).essence_cost > e_max:
			state.player_essence_max += 1
			return

	# Default: essence-first; catch Mana up when it falls more than 2 behind
	if m_max < e_max - 2:
		state.player_mana_max += 1
	else:
		state.player_essence_max += 1

func _board_demon_count(state: Object) -> int:
	var n := 0
	for m in state.player_board:
		if (m as MinionInstance).card_data.minion_type == Enums.MinionType.DEMON:
			n += 1
	return n

func _has_cheap_token(state: Object) -> bool:
	for m in state.player_board:
		var mc: MinionCardData = (m as MinionInstance).card_data as MinionCardData
		if mc != null and mc.essence_cost + mc.mana_cost <= 1:
			return true
	return false

# ---------------------------------------------------------------------------
# Play-phase helpers (same pattern as SpellBurnPlayerProfile)
# ---------------------------------------------------------------------------

## Play all affordable minions whose ID is in ids, restarting after each play.
func _play_minions_by_id(ids: Array[String]) -> void:
	var placed: bool = true
	while placed:
		placed = false
		for inst in agent.hand.duplicate():
			if not (inst.card_data is MinionCardData):
				continue
			var mc := inst.card_data as MinionCardData
			if not (mc.id in ids):
				continue
			var ess_cost: int = agent.effective_minion_essence_cost(mc)
			var mana_cost: int = agent.effective_minion_mana_cost(mc)
			if ess_cost > agent.essence or mana_cost > agent.mana:
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return  # board full
			agent.essence -= ess_cost
			agent.mana    -= mana_cost
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

## Cast all affordable spells whose ID is in ids.
func _play_spells_by_id(ids: Array[String]) -> void:
	var cast: bool = true
	while cast:
		cast = false
		for inst in agent.hand.duplicate():
			if not (inst.card_data is SpellCardData):
				continue
			var spell := inst.card_data as SpellCardData
			if not (spell.id in ids):
				continue
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
