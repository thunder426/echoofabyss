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
##   Mana to 2 first (enables rune placement turn 2), then essence to 4,
##   then mana to 4, then essence to 6.
class_name VoidRitualistProfile
extends CombatProfile

const _MAX_HUMANS_PER_TURN := 3

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
		"dark_command": {"cast_if": "has_friendly_type", "type": "HUMAN"},
	}

# ---------------------------------------------------------------------------
# Resource growth
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		if turn <= 1:
			return
		var e: int = sim_state.enemy_essence_max
		var m: int = sim_state.enemy_mana_max
		if e + m >= 11:
			return
		# Essence to 2 first (cult_fanatic turn 1)
		if e < 2:
			sim_state.enemy_essence_max += 1
		# Mana to 2 (enables rune placement)
		elif m < 2:
			sim_state.enemy_mana_max += 1
		# Essence to 4 (rune_seeker at 3E, double cult_fanatic)
		elif e < 4:
			sim_state.enemy_essence_max += 1
		# Mana to 4 (double rune or rune + dark_command)
		elif m < 4:
			sim_state.enemy_mana_max += 1
		# Essence to 7
		else:
			sim_state.enemy_essence_max += 1

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
		var ess_cost: int = agent.effective_minion_essence_cost(mc)
		if ess_cost > agent.essence or mc.mana_cost > agent.mana:
			continue
		var slot: BoardSlot = agent.find_empty_slot()
		if slot == null:
			return false
		agent.essence -= ess_cost
		agent.mana    -= mc.mana_cost
		if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
			return false
		return true
	return false

## Play one feral imp (cheapest first — cheapest is best for ritual trigger).
## If both runes are active (ritual ready), ensure enough board slots for
## the ritual summons: imp (1) + Demon Ascendant (1) + Champion (1, first time).
## The imp dies during ritual, freeing 1 slot, so we need 2 free slots
## before playing the imp (3 slots needed - 1 freed = 2).
## If champion already summoned, only 1 extra slot needed (imp + Demon - imp death = 1).
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
		var ess_cost: int = agent.effective_minion_essence_cost(mc)
		if ess_cost > agent.essence or mc.mana_cost > agent.mana:
			continue
		# Check if ritual will trigger (both runes active)
		var slots_needed: int = 1  # just the imp itself
		if _ritual_ready():
			# Ritual: imp dies (frees 1), Demon Ascendant needs 1, Champion needs 1 (first time)
			var champion_summoned: bool = agent.scene != null and agent.scene.get("_champion_vr_summoned") == true
			slots_needed = 3 if not champion_summoned else 2  # imp + demon + champion, or imp + demon
		if agent.empty_slot_count() < slots_needed:
			return false
		var slot: BoardSlot = agent.find_empty_slot()
		if slot == null:
			return false
		agent.essence -= ess_cost
		agent.mana    -= mc.mana_cost
		if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
			return false
		return true
	return false

## Returns true if both blood_rune and dominion_rune are in enemy active traps.
func _ritual_ready() -> bool:
	if agent.scene == null:
		return false
	var traps: Variant = agent.scene.get("enemy_active_traps")
	if traps == null:
		traps = agent.scene.get("active_traps")
	if traps == null or not (traps is Array):
		return false
	var has_blood := false
	var has_dominion := false
	for t in (traps as Array):
		if t is TrapCardData:
			if (t as TrapCardData).rune_type == Enums.RuneType.BLOOD_RUNE:
				has_blood = true
			elif (t as TrapCardData).rune_type == Enums.RuneType.DOMINION_RUNE:
				has_dominion = true
	return has_blood and has_dominion

func _is_feral_imp(mc: MinionCardData) -> bool:
	return "feral_imp" in mc.minion_tags
