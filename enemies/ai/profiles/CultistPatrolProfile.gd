## CultistPatrolProfile.gd
## AI profile for the Abyss Cultist Patrol encounter (Act 2, Fight 1).
##
## Strategy: Corruption → Detonation loop.
##   1. Play HUMAN minions first (triggers feral_reinforcement + corrupt_authority).
##      Human summons apply Corruption to player minions and draw feral imps.
##   2. Then play FERAL IMPS from hand (triggers corrupt_authority detonation).
##      Each imp summon consumes all Corruption stacks on player minions for 200 dmg/stack.
##   3. Then spells (void_screech for face, soul_collector for removal).
##
## Attack phase — inherited smart default (guard → lethal → face/swift).
class_name CultistPatrolProfile
extends CombatProfile

## Resource growth: essence-heavy since the deck is almost all essence minions.
## Only grow mana to 2 (for void_screech) once essence reaches 4.
func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		if turn <= 1:
			return
		var e: int = sim_state.enemy_essence_max
		var m: int = sim_state.enemy_mana_max
		if e + m >= 11:
			return
		# Get mana to 2 early (for abyssal_plague / void_screech), then essence
		if m < 2 and e >= 2:
			sim_state.enemy_mana_max += 1
		else:
			sim_state.enemy_essence_max += 1

## Max humans to play per turn. Saves the rest for future turns so the
## corruption-detonation loop fires consistently every turn instead of
## dumping all humans turn 1 and running out of corruption sources.
const _MAX_HUMANS_PER_TURN := 2

func play_phase() -> void:
	# Play up to _MAX_HUMANS_PER_TURN humans, interleaved with imp detonations.
	var humans_played := 0
	var made_play := true
	while made_play:
		made_play = false
		# Play one human if under budget
		if humans_played < _MAX_HUMANS_PER_TURN:
			if await _play_one_minion_by_type(false):
				if not agent.is_alive(): return
				humans_played += 1
				made_play = true
				# Immediately play any feral imps we just drew (detonate corruption)
				while await _play_one_minion_by_type(true):
					if not agent.is_alive(): return
				continue
		# Human budget reached or no humans left — play remaining imps
		if await _play_one_minion_by_type(true):
			if not agent.is_alive(): return
			made_play = true
	# Spells after all minions
	await _play_spells_pass()
	if not agent.is_alive(): return
	# Traps/environments
	await _play_traps_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
	}

## Override targeting: Soul Collector should only target corrupted minions.
## For other cards, use default targeting.
func pick_on_play_target(mc: MinionCardData):
	if mc.id == "soul_collector":
		return _pick_highest_corruption_target()
	return super.pick_on_play_target(mc)

# ---------------------------------------------------------------------------
# Play helpers — split minion plays by human vs feral imp
# ---------------------------------------------------------------------------

## Play ONE minion of a category. Returns true if a minion was played.
## If play_imps is false, play a human. If true, play a feral imp.
func _play_one_minion_by_type(play_imps: bool) -> bool:
	var candidates: Array[CardInstance] = []
	for inst in agent.hand:
		if not (inst.card_data is MinionCardData):
			continue
		var is_imp: bool = _card_is_feral_imp(inst.card_data as MinionCardData)
		if play_imps == is_imp:
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

# ---------------------------------------------------------------------------
# Targeting helpers
# ---------------------------------------------------------------------------

## Pick the player minion with the most Corruption stacks (best Soul Collector target).
func _pick_highest_corruption_target() -> MinionInstance:
	var best: MinionInstance = null
	var best_stacks: int = 0
	for m in agent.opponent_board:
		var stacks: int = BuffSystem.sum_type(m, Enums.BuffType.CORRUPTION)
		if stacks > best_stacks:
			best_stacks = stacks
			best = m
	return best

func _card_is_feral_imp(mc: MinionCardData) -> bool:
	return "feral_imp" in mc.minion_tags
