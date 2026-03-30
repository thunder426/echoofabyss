## CorruptedHandlerProfile.gd
## AI profile for the Corrupted Handler encounter (Act 2 Boss, Fight 6).
##
## Strategy: Void Unraveling loop.
##   1. Play humans → they die in combat → spawn Void Sparks on enemy board
##   2. Play feral imps AFTER Void Sparks exist → transfers corrupted sparks to player board
##   3. Player board gets clogged with weak corrupted 100/100 minions
##
## Play order:
##   1. Humans first (triggers feral_reinforcement → draws imp, generates board presence)
##   2. Spells (Dark Command to buff humans)
##   3. Feral imps LAST — only after friendly Void Sparks exist (triggers void_unraveling transfer)
##
## Attack: ignore enemy Void Sparks with 0 ATK (not worth attacking).
##
## Resource: essence to 7, then mana to 2, then all essence.
class_name CorruptedHandlerProfile
extends CombatProfile

const _MAX_HUMANS_PER_TURN := 2

func play_phase() -> void:
	# Phase 1: Play humans (triggers feral_reinforcement → draws imp)
	var humans_played := 0
	var made_play := true
	while made_play and humans_played < _MAX_HUMANS_PER_TURN:
		made_play = false
		if await _play_one_human():
			if not agent.is_alive(): return
			humans_played += 1
			made_play = true
	# Phase 2: Spells (Dark Command, etc.)
	await _play_spells_pass()
	if not agent.is_alive(): return
	# Phase 3: Any remaining non-imp minions
	await _play_remaining_non_imps()
	# NOTE: Feral imps are held for attack_phase — play AFTER attacks so
	# humans die in combat first, spawning Void Sparks, then imp summon
	# triggers the transfer.

func _get_spell_rules() -> Dictionary:
	return {
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
	}

# ---------------------------------------------------------------------------
# Attack phase: skip 0-ATK Void Sparks on opponent board
# ---------------------------------------------------------------------------

func attack_phase() -> void:
	# Step 1: Attack with all minions — humans trade and die, spawning Void Sparks
	var lethal_threat  := _opponent_threatens_lethal()
	var can_go_lethal  := _calc_lethal_damage() >= agent.opponent_hp
	if can_go_lethal:
		await _play_lethal_spells()
		if not agent.is_alive(): return
	for minion in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(minion) or not minion.can_attack():
			continue
		var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
		if can_go_lethal and guards.is_empty():
			if minion.can_attack_hero():
				if not await agent.do_attack_hero(minion):
					if not agent.is_alive(): return
			elif not agent.opponent_board.is_empty():
				var target := _pick_target_ignore_sparks(minion)
				if target != null:
					if not await agent.do_attack_minion(minion, target):
						if not agent.is_alive(): return
		elif not guards.is_empty():
			var target := _pick_best_guard(minion, guards)
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return
		elif lethal_threat and not agent.opponent_board.is_empty():
			var target := _pick_target_ignore_sparks(minion)
			if target != null:
				if not await agent.do_attack_minion(minion, target):
					if not agent.is_alive(): return
		elif minion.can_attack_hero():
			if not await agent.do_attack_hero(minion):
				if not agent.is_alive(): return
		elif not agent.opponent_board.is_empty():
			var target := _pick_target_ignore_sparks(minion)
			if target != null:
				if not await agent.do_attack_minion(minion, target):
					if not agent.is_alive(): return

	# Step 2: AFTER attacks — play feral imps to trigger Void Spark transfer
	# Humans that died in combat spawned Void Sparks; now the imp summon transfers them.
	if _has_friendly_void_sparks():
		while await _play_one_feral_imp():
			if not agent.is_alive(): return

## Override targeting: Soul Collector should target corrupted minions.
func pick_on_play_target(mc: MinionCardData):
	if mc.id == "soul_collector":
		return _pick_highest_corruption_target()
	return super.pick_on_play_target(mc)

# ---------------------------------------------------------------------------
# Resource growth
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_handler_growth(sim_state, turn)

func _handler_growth(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e: int = state.enemy_essence_max
	var m: int = state.enemy_mana_max
	if e + m >= 11:
		return
	# Essence to 7 first
	if e < 7:
		state.enemy_essence_max += 1
		return
	# Then mana to 2
	if m < 2:
		state.enemy_mana_max += 1
		return
	# Then all essence
	state.enemy_essence_max += 1

# ---------------------------------------------------------------------------
# Play helpers
# ---------------------------------------------------------------------------

## Play any remaining non-imp minions (e.g. void_stalker).
func _play_remaining_non_imps() -> void:
	var placed := true
	while placed:
		placed = false
		if await _play_one_human():
			if not agent.is_alive(): return
			placed = true

func _play_one_human() -> bool:
	var candidates: Array[CardInstance] = []
	for inst in agent.hand:
		if not (inst.card_data is MinionCardData):
			continue
		var mc := inst.card_data as MinionCardData
		if _is_feral_imp(mc):
			continue
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

# ---------------------------------------------------------------------------
# Targeting helpers
# ---------------------------------------------------------------------------

## Pick best target but skip 0-ATK Void Sparks (not worth attacking).
func _pick_target_ignore_sparks(attacker: MinionInstance) -> MinionInstance:
	var pool: Array[MinionInstance] = []
	for m in agent.opponent_board:
		if m.card_data.id == "void_spark" and m.effective_atk() <= 0:
			continue
		pool.append(m)
	if pool.is_empty():
		return null
	# Killable first → highest ATK
	var killable: Array[MinionInstance] = []
	for m in pool:
		if attacker.effective_atk() >= m.current_health:
			killable.append(m)
	var candidates := killable if not killable.is_empty() else pool
	var best: MinionInstance = candidates[0]
	for m in candidates:
		if m.effective_atk() > best.effective_atk():
			best = m
	return best

func _pick_highest_corruption_target() -> MinionInstance:
	var best: MinionInstance = null
	var best_stacks: int = 0
	for m in agent.opponent_board:
		var stacks: int = BuffSystem.sum_type(m, Enums.BuffType.CORRUPTION)
		if stacks > best_stacks:
			best_stacks = stacks
			best = m
	return best

func _has_friendly_void_sparks() -> bool:
	for m in agent.friendly_board:
		if m.card_data.id == "void_spark":
			return true
	return false

func _is_feral_imp(mc: MinionCardData) -> bool:
	return "feral_imp" in mc.minion_tags
