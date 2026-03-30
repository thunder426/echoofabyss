## VoidRitualistProfile.gd
## AI profile for the Void Ritualist encounter (Act 2, Fight 2).
##
## Strategy: Place runes → play humans (draw imps via feral_reinforcement) →
##           play feral imps LAST to trigger ritual_sacrifice if both runes active.
##
## Play order:
##   1. Runes/traps (need Blood Rune + Dominion Rune for ritual)
##   2. Humans (trigger feral_reinforcement → draw feral imp)
##   3. Spells (Dark Command to buff humans)
##   4. Feral imps LAST (cheapest first — triggers ritual_sacrifice if runes ready)
##
## Resource growth:
##   If abyss_cultist in hand → mana to 2 first (enables rune placement turn 2)
##   Then essence to 5, then mana to 4, then essence to 7.
class_name VoidRitualistProfile
extends CombatProfile

const _MAX_HUMANS_PER_TURN := 2

func play_phase() -> void:
	# Phase 1: Place runes first (ritual components)
	await _play_traps_pass()
	if not agent.is_alive(): return
	# Phase 2: Play humans (triggers feral_reinforcement → draws imps)
	var humans_played := 0
	var made_play := true
	while made_play and humans_played < _MAX_HUMANS_PER_TURN:
		made_play = false
		if await _play_one_human():
			if not agent.is_alive(): return
			humans_played += 1
			made_play = true
	# Phase 3: Spells (Dark Command, etc.)
	await _play_spells_pass()
	if not agent.is_alive(): return
	# Phase 4: Feral imps LAST (cheapest first — trigger ritual_sacrifice)
	while await _play_one_feral_imp():
		if not agent.is_alive(): return
	# Phase 5: Any remaining minions (non-human, non-imp)
	await _play_minions_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
	}

# ---------------------------------------------------------------------------
# Resource growth
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_ritualist_growth(sim_state, turn)

func _ritualist_growth(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e: int = state.enemy_essence_max
	var m: int = state.enemy_mana_max
	if e + m >= 11:
		return
	# If abyss_cultist in hand and mana < 2 → grow mana first (enables rune turn 2)
	if m < 2:
		var has_cultist := false
		for inst in state.enemy_hand:
			if inst.card_data.id == "abyss_cultist":
				has_cultist = true
				break
		if has_cultist:
			state.enemy_mana_max += 1
			return
	# Essence to 5
	if e < 5:
		state.enemy_essence_max += 1
		return
	# Mana to 4
	if m < 4:
		state.enemy_mana_max += 1
		return
	# Essence to 7
	state.enemy_essence_max += 1

# ---------------------------------------------------------------------------
# Play helpers
# ---------------------------------------------------------------------------

## Play one human minion (non-imp). Returns true if played.
func _play_one_human() -> bool:
	var candidates: Array[CardInstance] = []
	for inst in agent.hand:
		if not (inst.card_data is MinionCardData):
			continue
		var mc := inst.card_data as MinionCardData
		if _is_feral_imp(mc):
			continue  # Skip imps — save for last
		candidates.append(inst)
	candidates.sort_custom(agent.sort_by_total_cost)
	for inst in candidates:
		var mc := inst.card_data as MinionCardData
		if mc.essence_cost > agent.essence or mc.mana_cost > agent.mana:
			continue
		var slot: BoardSlot = agent.find_empty_slot()
		if slot == null:
			return false
		agent.essence -= mc.essence_cost
		agent.mana    -= mc.mana_cost
		if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
			return false
		return true
	return false

## Play one feral imp (cheapest first — cheapest is best for ritual trigger).
func _play_one_feral_imp() -> bool:
	var candidates: Array[CardInstance] = []
	for inst in agent.hand:
		if not (inst.card_data is MinionCardData):
			continue
		if _is_feral_imp(inst.card_data as MinionCardData):
			candidates.append(inst)
	candidates.sort_custom(agent.sort_by_total_cost)
	for inst in candidates:
		var mc := inst.card_data as MinionCardData
		if mc.essence_cost > agent.essence or mc.mana_cost > agent.mana:
			continue
		var slot: BoardSlot = agent.find_empty_slot()
		if slot == null:
			return false
		agent.essence -= mc.essence_cost
		agent.mana    -= mc.mana_cost
		if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
			return false
		return true
	return false

func _is_feral_imp(mc: MinionCardData) -> bool:
	return "feral_imp" in mc.minion_tags
