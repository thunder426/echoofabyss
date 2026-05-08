## CultistPatrolTempoProfile.gd
## AI profile for the Abyss Cultist Patrol — Tempo/control variant.
##
## Tempo trading with corruption synergy. Play humans to trigger passives,
## use Soul Collector to execute corrupted minions, Void Execution for removal.
##
## Play order:
##   1. Shadow Rune (if not active)
##   2. Minions — prefer imp if corruption on enemy board, else human; highest ATK first
##   3. Void Summoning (only if human on board)
##   4. Dark Command (only if 2+ humans on board)
##   5. Void Execution (target enemy 500-700 HP if human, else <=500; or lethal face)
##   6. Remaining spells/traps
##
## Resource growth: 2E → 2M → 5E → 3M → 7E → 4M
class_name CultistPatrolTempoProfile
extends CombatProfile

func _is_aggro() -> bool:
	return true

func play_phase() -> void:
	# 1. Shadow Rune first if not active
	if not _has_active_rune("shadow_rune"):
		await _play_trap_by_id("shadow_rune")
		if not agent.is_alive(): return
	# 2. Minions — smart ordering
	await _play_minions_smart()
	if not agent.is_alive(): return
	# 3. Void Summoning (only with human on board)
	if _has_friendly_human():
		await _play_spell_by_id("void_summoning")
		if not agent.is_alive(): return
	# 4. Dark Command (only with 2+ humans)
	if _count_friendly_humans() >= 2:
		await _play_spell_by_id("dark_command")
		if not agent.is_alive(): return
	# 5. Void Execution
	if _should_cast_execution():
		await _play_spell_by_id("void_execution")
		if not agent.is_alive(): return
	# 6. Remaining
	await _play_spells_pass()
	if not agent.is_alive(): return
	await _play_traps_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"void_screech":    {"cast_if": "board_full_or_no_minions_in_hand"},
		"void_summoning":  {"cast_if": "never"},  # handled manually
		"void_execution":  {"cast_if": "never"},   # handled manually
		"dark_command":    {"cast_if": "never"},    # handled manually
		"feral_surge":     {"cast_if": "has_friendly_tag", "tag": "feral_imp"},
		"cyclone":         {"cast_if": "opponent_has_rune_or_env"},
	}

func can_cast_spell(spell: SpellCardData) -> bool:
	match spell.id:
		"void_summoning":
			return false
		"void_execution":
			return false
		"dark_command":
			return false
	return super.can_cast_spell(spell)

func pick_spell_target(spell: SpellCardData):
	if spell.id == "void_execution":
		return _pick_execution_target()
	return super.pick_spell_target(spell)

## Pick on-play target: Soul Collector targets highest-corruption enemy.
func pick_on_play_target(mc: MinionCardData):
	if mc.id == "soul_collector":
		return _pick_highest_corruption_target()
	return super.pick_on_play_target(mc)

## Resource growth: 2E → 2M → 5E → 3M → 7E → 4M
func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		if turn <= 1:
			return
		var e: int = sim_state.enemy_essence_max
		var m: int = sim_state.enemy_mana_max
		if e + m >= 11:
			return
		if e < 2:
			sim_state.enemy_essence_max += 1
		elif m < 2:
			sim_state.enemy_mana_max += 1
		elif e < 5:
			sim_state.enemy_essence_max += 1
		elif m < 3:
			sim_state.enemy_mana_max += 1
		elif e < 7:
			sim_state.enemy_essence_max += 1
		else:
			sim_state.enemy_mana_max += 1

# ---------------------------------------------------------------------------
# Smart minion play — prefer imp if corruption on enemy, else human, highest ATK first
# ---------------------------------------------------------------------------

func _play_minions_smart() -> void:
	var placed := true
	while placed:
		placed = false
		var has_corruption := _enemy_has_corruption()
		var candidates: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is MinionCardData:
				candidates.append(inst)
		if candidates.is_empty():
			return
		# Sort: prefer feral imps if corruption on enemy board, else humans; highest ATK first
		candidates.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
			var a_mc := a.card_data as MinionCardData
			var b_mc := b.card_data as MinionCardData
			var a_is_imp: bool = "feral_imp" in a_mc.minion_tags
			var b_is_imp: bool = "feral_imp" in b_mc.minion_tags
			var a_is_human: bool = a_mc.is_race(Enums.MinionType.HUMAN)
			var b_is_human: bool = b_mc.is_race(Enums.MinionType.HUMAN)
			# Priority: if corruption exists, imps first (for detonation); else humans first
			var a_prio: int = 0
			var b_prio: int = 0
			if has_corruption:
				if a_is_imp: a_prio = 2
				elif a_is_human: a_prio = 1
				if b_is_imp: b_prio = 2
				elif b_is_human: b_prio = 1
			else:
				if a_is_human: a_prio = 2
				elif a_is_imp: a_prio = 1
				if b_is_human: b_prio = 2
				elif b_is_imp: b_prio = 1
			if a_prio != b_prio:
				return a_prio > b_prio
			# Tie-break: highest ATK first
			return a_mc.atk > b_mc.atk)
		for inst in candidates:
			var mc := inst.card_data as MinionCardData
			var mana_cost: int = agent.effective_minion_mana_cost(mc)
			if mc.essence_cost > agent.essence or mana_cost > agent.mana:
				continue
			var slot := agent.find_empty_slot()
			if slot == null:
				return
			agent.essence -= mc.essence_cost
			agent.mana -= mana_cost
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

# ---------------------------------------------------------------------------
# Void Execution logic
# ---------------------------------------------------------------------------

func _should_cast_execution() -> bool:
	for inst in agent.hand:
		if inst.card_data is SpellCardData and inst.card_data.id == "void_execution":
			if agent.effective_spell_cost(inst.card_data as SpellCardData) <= agent.mana:
				return _pick_execution_target() != null
	return false

## VE target: enemy minion 500-700 HP (with human) or <=500 HP (without), or face if lethal.
func _pick_execution_target():
	var dmg: int = 700 if _has_friendly_human() else 500
	# Check face lethal
	if agent.opponent_hp <= dmg:
		return "hero"
	# Target highest HP enemy we can kill
	var best: MinionInstance = null
	for m in agent.opponent_board:
		if m.current_health <= dmg:
			if best == null or m.current_health > best.current_health:
				best = m
	return best

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _has_friendly_human() -> bool:
	for m in agent.friendly_board:
		if m.card_data is MinionCardData and (m.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN):
			return true
	return false

func _count_friendly_humans() -> int:
	var count := 0
	for m in agent.friendly_board:
		if m.card_data is MinionCardData and (m.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN):
			count += 1
	return count

func _enemy_has_corruption() -> bool:
	for m in agent.opponent_board:
		if BuffSystem.sum_type(m, Enums.BuffType.CORRUPTION) > 0:
			return true
	return false

func _pick_highest_corruption_target() -> MinionInstance:
	var best: MinionInstance = null
	var best_stacks: int = 0
	for m in agent.opponent_board:
		var stacks: int = BuffSystem.sum_type(m, Enums.BuffType.CORRUPTION)
		if stacks > best_stacks:
			best_stacks = stacks
			best = m
	return best

func _has_active_rune(rune_id: String) -> bool:
	if agent.scene == null:
		return false
	var traps: Variant = agent.scene.get("enemy_active_traps")
	if traps == null:
		traps = agent.scene.get("active_traps")
	if traps == null:
		return false
	for t in (traps as Array):
		if t is TrapCardData and (t as TrapCardData).id == rune_id:
			return true
	return false

func _play_spell_by_id(spell_id: String) -> void:
	for inst in agent.hand.duplicate():
		if not (inst.card_data is SpellCardData):
			continue
		if inst.card_data.id != spell_id:
			continue
		var cost: int = agent.effective_spell_cost(inst.card_data as SpellCardData)
		if cost > agent.mana:
			continue
		agent.mana -= cost
		var target = pick_spell_target(inst.card_data as SpellCardData)
		if not await agent.commit_play_spell(inst, target):
			return
		return

func _play_trap_by_id(trap_id: String) -> void:
	for inst in agent.hand.duplicate():
		if not (inst.card_data is TrapCardData):
			continue
		if inst.card_data.id != trap_id:
			continue
		var trap_cost: int = inst.effective_cost()
		if trap_cost > agent.mana:
			continue
		agent.mana -= trap_cost
		if not await agent.commit_play_trap(inst):
			return
		return
