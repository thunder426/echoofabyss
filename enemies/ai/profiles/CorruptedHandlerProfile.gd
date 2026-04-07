## CorruptedHandlerProfile.gd
## AI profile for the Corrupted Handler encounter (Act 2 Boss, Fight 6).
##
## Strategy: Void Unraveling spark loop + feral imp ATK buff.
##   1. Play spark generators first (brood_imp, void_spawner) — they create sparks on death
##   2. Play humans → they die in combat → spawn Void Sparks (void_unraveling)
##   3. Attack — humans/brood_imps die, generating sparks from multiple sources
##   4. Play feral imps AFTER attacks → buffs ALL sparks +100 ATK, then transfers to player board
##   5. Player board gets clogged with buffed corrupted sparks
##
## Play order:
##   1. Spark generators: brood_imp, void_spawner (before humans, so deaths create more sparks)
##   2. Spells: Dark Command (buff humans before they trade)
##   3. Humans: abyss_cultist, cult_fanatic (will die in combat → spawn sparks)
##   4. Attack phase — maximize deaths to generate sparks
##   5. Feral imps LAST — buff all sparks +100 ATK then transfer to player board
##
## Resource: E→4, M→2, E→7, then mana (need essence for brood_imp/spawner early)
class_name CorruptedHandlerProfile
extends CombatProfile

func play_phase() -> void:
	# Phase 1: Spark generators first — brood_imp and void_spawner
	# These need to be on board BEFORE humans die so their death triggers create sparks
	await _play_minions_by_id(["void_spawner"])
	if not agent.is_alive(): return
	await _play_minions_by_id(["brood_imp"])
	if not agent.is_alive(): return
	# Phase 2: Dark Command — buff humans before they go into combat
	await _play_spells_pass()
	if not agent.is_alive(): return
	# Phase 3: Humans — these will die in combat and generate sparks via void_unraveling
	var humans_played := 0
	var made_play := true
	while made_play and humans_played < 3:
		made_play = false
		if await _play_one_human():
			if not agent.is_alive(): return
			humans_played += 1
			made_play = true
	# Phase 4: Any remaining non-imp minions (void_stalker)
	await _play_remaining_non_imps()
	if not agent.is_alive(): return
	# Phase 5: Feral imps — corrupt all sparks on both boards
	while await _play_one_feral_imp():
		if not agent.is_alive(): return

func _get_spell_rules() -> Dictionary:
	return {
		"dark_command": {"cast_if": "has_friendly_type", "type": "HUMAN"},
	}

# ---------------------------------------------------------------------------
# Attack phase: attack first to kill humans/brood_imps, then play feral imps
# ---------------------------------------------------------------------------

func attack_phase() -> void:
	# Step 1: Attack with all minions — humans/brood_imps trade and die,
	# spawning Void Sparks via void_unraveling and brood_imp death effect
	var lethal_threat  := _opponent_threatens_lethal()
	var can_go_lethal  := _calc_lethal_damage() >= agent.opponent_hp
	if can_go_lethal:
		await _play_lethal_spells()
		if not agent.is_alive(): return

	# Corrupted sparks preserved for transfer. All other minions attack.
	# Prioritise board clear to free player slots for spark clog.
	# Skip opponent's corrupted sparks. Go face if all opponent minions are corrupted sparks.
	var only_zero_atk: bool = _opponent_only_zero_atk()

	# Pass 1: Uncorrupted sparks trade into real opponent minions (board clear)
	for minion in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(minion) or not minion.can_attack():
			continue
		if minion.card_data.id != "void_spark":
			continue
		if BuffSystem.has_type(minion, Enums.BuffType.CORRUPTION):
			continue  # corrupted sparks preserved for transfer
		if agent.opponent_board.is_empty():
			break
		var target := _pick_target_skip_corrupted_sparks(minion)
		if target != null:
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return

	# Pass 2: Non-spark minions — void_stalker goes face; others clear board
	for minion in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(minion) or not minion.can_attack():
			continue
		if minion.card_data.id == "void_spark":
			continue  # sparks handled in pass 1
		var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
		if can_go_lethal and guards.is_empty():
			if minion.can_attack_hero():
				if not await agent.do_attack_hero(minion):
					if not agent.is_alive(): return
			elif not agent.opponent_board.is_empty():
				var target := _pick_target_skip_corrupted_sparks(minion)
				if target != null:
					if not await agent.do_attack_minion(minion, target):
						if not agent.is_alive(): return
		elif not guards.is_empty():
			var target := _pick_best_guard(minion, guards)
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return
		elif _is_face_aggressor(minion) and minion.can_attack_hero():
			# Void Stalker: always go face when no guards blocking — constant hero pressure
			if not await agent.do_attack_hero(minion):
				if not agent.is_alive(): return
		elif only_zero_atk or agent.opponent_board.is_empty():
			# Only corrupted sparks left — go face
			if minion.can_attack_hero():
				if not await agent.do_attack_hero(minion):
					if not agent.is_alive(): return
		elif not agent.opponent_board.is_empty():
			# Board clear — kill real opponent minions to free slots for spark clog
			var target := _pick_target_skip_corrupted_sparks(minion)
			if target != null:
				if not await agent.do_attack_minion(minion, target):
					if not agent.is_alive(): return
			elif minion.can_attack_hero():
				if not await agent.do_attack_hero(minion):
					if not agent.is_alive(): return

	# Sparks auto-transfer at end of enemy turn via void_unraveling

# ---------------------------------------------------------------------------
# Resource growth — need essence early for brood_imp/void_spawner
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		if turn <= 1:
			return
		var e: int = sim_state.enemy_essence_max
		var m: int = sim_state.enemy_mana_max
		if e + m >= 11:
			return
		# Essence to 4 first (brood_imp at 2E, void_stalker at 3E, void_spawner at 4E)
		if e < 4:
			sim_state.enemy_essence_max += 1
		# Mana to 2 (dark_command)
		elif m < 2:
			sim_state.enemy_mana_max += 1
		# Essence to 7
		elif e < 7:
			sim_state.enemy_essence_max += 1
		else:
			sim_state.enemy_mana_max += 1

# ---------------------------------------------------------------------------
# Play helpers
# ---------------------------------------------------------------------------

func _play_minions_by_id(ids: Array[String]) -> void:
	var placed := true
	while placed:
		placed = false
		for inst in agent.hand.duplicate():
			if not (inst.card_data is MinionCardData):
				continue
			var mc := inst.card_data as MinionCardData
			if not (mc.id in ids):
				continue
			var ess_cost: int = agent.effective_minion_essence_cost(mc)
			if ess_cost > agent.essence or mc.mana_cost > agent.mana:
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return
			agent.essence -= ess_cost
			agent.mana    -= mc.mana_cost
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

func _play_one_human() -> bool:
	var candidates: Array[CardInstance] = []
	for inst in agent.hand:
		if not (inst.card_data is MinionCardData):
			continue
		var mc := inst.card_data as MinionCardData
		if _is_feral_imp(mc) or mc.id in ["brood_imp", "void_spawner"]:
			continue  # Skip imps and spark generators (already played)
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

func _play_remaining_non_imps() -> void:
	var placed := true
	while placed:
		placed = false
		if await _play_one_human():
			if not agent.is_alive(): return
			placed = true

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
		var slot: BoardSlot = agent.find_empty_slot()
		if slot == null:
			return false
		agent.essence -= ess_cost
		agent.mana    -= mc.mana_cost
		if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
			return false
		return true
	return false

# ---------------------------------------------------------------------------
# Targeting helpers
# ---------------------------------------------------------------------------

## Pick best target, skip 0-ATK minions (corrupted sparks, etc. — not worth attacking).
func _pick_target_skip_corrupted_sparks(attacker: MinionInstance) -> MinionInstance:
	var pool: Array[MinionInstance] = []
	for m in agent.opponent_board:
		if m.effective_atk() <= 0:
			continue
		pool.append(m)
	if pool.is_empty():
		return null
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

## True if all opponent minions have 0 ATK (or board is empty) — nothing worth attacking.
func _opponent_only_zero_atk() -> bool:
	if agent.opponent_board.is_empty():
		return true
	for m in agent.opponent_board:
		if m.effective_atk() > 0:
			return false
	return true

func _is_feral_imp(mc: MinionCardData) -> bool:
	return "feral_imp" in mc.minion_tags

## Void Stalker is a face aggressor — high ATK + Lifedrain, should pressure hero directly.
func _is_face_aggressor(minion: MinionInstance) -> bool:
	return minion.card_data.id == "void_stalker"
