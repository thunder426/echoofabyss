## RiftStalkerProfile.gd
## AI profile for the Rift Stalker encounter (Act 3, Fight 7).
##
## Strategy:
##   - Build board with Void Echoes and Rift Tenders first
##   - Hold Void Pulse and Phase Stalker until board is full (4+ minions)
##   - Rift Tender only played when 2+ empty slots (leaves room for spark summon)
##   - Reserve 1 empty slot for champion when spark damage is near threshold
##   - Hollow Sentinel played when sparks are on board (buffs their ATK)
##
## Play order:
##   1. Regular essence minions (void_echo, rift_tender, hollow_sentinel)
##   2. Mana spells (void_wind, spirit_surge — if in deck)
##   3. When board has 4+ minions: spark-cost spells (void_pulse)
##   4. When board has 4+ minions: spark-cost minions (phase_stalker)
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7
class_name RiftStalkerProfile
extends CombatProfile

const _BOARD_FULL_THRESHOLD := 4  # Consider board "full enough" to play finishers
const _CHAMPION_DMG_THRESHOLD := 1000
const _CHAMPION_RESERVE_RATIO := 0.7  # Start reserving a slot at 70% of threshold

func play_phase() -> void:
	# Phase 0: Trade a spark to make room for Hollow Sentinel if needed
	await _make_room_for_sentinel()
	if not agent.is_alive(): return
	# Phase 1: Regular essence minions (board building)
	await _play_regular_minions()
	if not agent.is_alive(): return
	# Phase 2: Mana-only spells
	await _play_spells_pass()
	if not agent.is_alive(): return
	# Phase 2b: Rift Collapse AoE — when enemy has 3+ minions
	await _try_rift_collapse_aoe()
	if not agent.is_alive(): return
	# Phase 3: Spark-cost spells (only when board is developed)
	if agent.friendly_board.size() >= _BOARD_FULL_THRESHOLD:
		await _play_spark_spells()
		if not agent.is_alive(): return
		# Phase 4: Spark-cost minions
		await _play_spark_minions()

func _is_tempo() -> bool:
	return true

func attack_phase() -> void:
	# Pass 1: Non-spark, non-champion minions always trade (board control)
	# These are expendable — they should clear threats before sparks go face
	await _trade_non_sparks()
	if not agent.is_alive(): return

	# Pass 2: If champion is alive, sparks protect it; otherwise sparks go face
	await _spark_attack_phase()
	if not agent.is_alive(): return

	# Pass 3: Champion goes face (never trades)
	await _champion_attack_phase()

## Non-spark, non-champion, non-sentinel minions: trade into enemy minions.
## When champion is alive, sentinel is protected (handled by _champion_attack_phase).
func _trade_non_sparks() -> void:
	var has_champion := _champion_rs_is_alive()
	for m: MinionInstance in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(m) or not m.can_attack():
			continue
		if m.card_data.id == "void_spark" or m.card_data.id == "champion_rift_stalker":
			continue
		# When champion alive, sentinel goes face (handled in _champion_attack_phase)
		if has_champion and (m.card_data as MinionCardData).passive_effect_id == "hollow_sentinel_spark_buff":
			continue
		var guards := CombatManager.get_taunt_minions(agent.opponent_board)
		if not guards.is_empty():
			var target := _pick_best_guard(m, guards)
			if not await agent.do_attack_minion(m, target):
				if not agent.is_alive(): return
		elif not agent.opponent_board.is_empty():
			# Use tempo trade logic — favored/trade-up/multi-kill
			var target := _pick_tempo_trade(m)
			if target != null:
				if not await agent.do_attack_minion(m, target):
					if not agent.is_alive(): return
			elif m.can_attack_hero():
				if not await agent.do_attack_hero(m):
					if not agent.is_alive(): return
		elif m.can_attack_hero():
			if not await agent.do_attack_hero(m):
				if not agent.is_alive(): return

## Sparks: when champion alive, clear enemy board to protect champion + hollow.
## When no champion, go face.
func _spark_attack_phase() -> void:
	var has_champion := _champion_rs_is_alive()

	for m: MinionInstance in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(m) or not m.can_attack():
			continue
		if m.card_data.id != "void_spark":
			continue
		var guards := CombatManager.get_taunt_minions(agent.opponent_board)
		if not guards.is_empty():
			if not await agent.do_attack_minion(m, guards[0]):
				if not agent.is_alive(): return
			continue
		if has_champion and not agent.opponent_board.is_empty():
			# Champion on board: sparks trade into enemy minions to protect champion + hollow
			# Pick highest ATK enemy to reduce threat
			var best_target: MinionInstance = null
			var best_atk := 0
			for enemy: MinionInstance in agent.opponent_board:
				if enemy.effective_atk() > best_atk:
					best_target = enemy
					best_atk = enemy.effective_atk()
			if best_target != null:
				if not await agent.do_attack_minion(m, best_target):
					if not agent.is_alive(): return
				continue
		# No champion or empty enemy board — go face
		if m.can_attack_hero():
			if not await agent.do_attack_hero(m):
				if not agent.is_alive(): return

## Champion and Hollow Sentinel go face. Never trade.
func _champion_attack_phase() -> void:
	for m: MinionInstance in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(m) or not m.can_attack():
			continue
		if m.card_data.id != "champion_rift_stalker" and (m.card_data as MinionCardData).passive_effect_id != "hollow_sentinel_spark_buff":
			continue
		var guards := CombatManager.get_taunt_minions(agent.opponent_board)
		if not guards.is_empty():
			var target := _pick_best_guard(m, guards)
			if not await agent.do_attack_minion(m, target):
				if not agent.is_alive(): return
		elif m.can_attack_hero():
			if not await agent.do_attack_hero(m):
				if not agent.is_alive(): return

## Pick a single favored or trade-up target for a minion (used by non-spark attackers).
func _pick_tempo_trade(attacker: MinionInstance) -> MinionInstance:
	var a_dmg: int = attacker.effective_atk()
	var a_hp: int = attacker.current_health
	var a_value: int = a_dmg + a_hp
	var best: MinionInstance = null
	var best_score: float = -1.0
	for target: MinionInstance in agent.opponent_board:
		var t_hp: int = target.current_health + target.current_shield
		var t_atk: int = target.effective_atk()
		var t_value: int = t_atk + target.current_health
		var can_kill: bool = a_dmg >= t_hp
		var survives: bool = t_atk < a_hp
		if can_kill and survives and t_atk * 2 >= a_dmg:
			# Favored: kill + survive, target not too small
			var score: float = t_atk + 1000.0
			if score > best_score:
				best_score = score
				best = target
		elif can_kill and not survives and a_value < t_value:
			# Trade-up: both die, our minion is smaller
			var score: float = float(t_atk)
			if score > best_score:
				best_score = score
				best = target
	return best

func _champion_rs_is_alive() -> bool:
	for m: MinionInstance in agent.friendly_board:
		if m.card_data.id == "champion_rift_stalker":
			return true
	return false

## Cast Rift Collapse when enemy has 3+ minions.
## Pick the lowest ATK spark, let it attack first (trade or face), then consume + cast.
func _try_rift_collapse_aoe() -> void:
	if agent.opponent_board.size() < 2:
		return
	# Find rift_collapse in hand
	var collapse_inst: CardInstance = null
	for inst in agent.hand:
		if inst.card_data.id == "rift_collapse":
			collapse_inst = inst
			break
	if collapse_inst == null:
		return
	var spell := collapse_inst.card_data as SpellCardData
	if agent.effective_spell_cost(spell) > agent.mana:
		return
	if not _can_afford_sparks(_effective_spark_cost(spell)):
		return
	# Pick lowest ATK spark to sacrifice
	var sparks: Array[MinionInstance] = []
	for m: MinionInstance in agent.friendly_board:
		if m.card_data.id == "void_spark":
			sparks.append(m)
	if sparks.is_empty():
		return
	sparks.sort_custom(func(a: MinionInstance, b: MinionInstance) -> bool:
		return a.effective_atk() < b.effective_atk())
	var fuel: MinionInstance = sparks[0]
	# Let fuel spark attack first before consuming
	if fuel.can_attack():
		var guards := CombatManager.get_taunt_minions(agent.opponent_board)
		if not guards.is_empty():
			if not await agent.do_attack_minion(fuel, guards[0]):
				if not agent.is_alive(): return
		elif fuel.can_attack_hero():
			if not await agent.do_attack_hero(fuel):
				if not agent.is_alive(): return
		elif not agent.opponent_board.is_empty():
			var weakest: MinionInstance = agent.opponent_board[0]
			for e: MinionInstance in agent.opponent_board:
				if e.current_health < weakest.current_health:
					weakest = e
			if not await agent.do_attack_minion(fuel, weakest):
				if not agent.is_alive(): return
	# Consume the spark and cast
	if not agent.friendly_board.has(fuel):
		return  # Spark died during attack — can't consume
	agent.consume_minion(fuel)
	agent.mana -= agent.effective_spell_cost(spell)
	# Track kills
	var pre_count: int = agent.opponent_board.size()
	if agent.scene.get("_rift_collapse_casts") != null:
		agent.scene._rift_collapse_casts += 1
	await agent.commit_play_spell(collapse_inst, pick_spell_target(spell))
	if agent.scene.get("_rift_collapse_kills") != null:
		var killed: int = pre_count - agent.opponent_board.size()
		agent.scene._rift_collapse_kills += killed

func _get_spell_rules() -> Dictionary:
	return {}

# ---------------------------------------------------------------------------
# Resource growth
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_rift_stalker_growth(sim_state, turn)

func _rift_stalker_growth(state: Object, turn: int) -> void:
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
# Board awareness helpers
# ---------------------------------------------------------------------------

func _empty_slot_count() -> int:
	return agent.empty_slot_count()

func _should_reserve_champion_slot() -> bool:
	var spark_dmg: int = agent.scene.get("_champion_rs_spark_dmg") if agent.scene.get("_champion_rs_spark_dmg") != null else 0
	var summoned: bool = agent.scene.get("_champion_rs_summoned") if agent.scene.get("_champion_rs_summoned") != null else false
	if summoned:
		return false  # Champion already on board
	return spark_dmg >= int(_CHAMPION_DMG_THRESHOLD * _CHAMPION_RESERVE_RATIO)

# ---------------------------------------------------------------------------
# Play phases
# ---------------------------------------------------------------------------

## If board is full and Hollow Sentinel is in hand, trade a minion to make space.
## Never sacrifice sparks when champion + hollow are both on board.
## Among eligible minions, pick the lowest ATK+HP (cheapest to lose).
func _make_room_for_sentinel() -> void:
	if _empty_slot_count() > 0:
		return
	# Check if Hollow Sentinel is in hand and affordable
	var has_sentinel_in_hand := false
	for inst in agent.hand:
		if inst.card_data.id == "hollow_sentinel":
			var mc := inst.card_data as MinionCardData
			if mc.essence_cost <= agent.essence:
				has_sentinel_in_hand = true
				break
	if not has_sentinel_in_hand:
		return
	var has_champion := _champion_rs_is_alive()
	var has_hollow := _has_hollow_on_board()
	# Never sacrifice champion or hollow sentinel
	# Never sacrifice sparks when both champion and hollow are on board
	var eligible: Array[MinionInstance] = []
	for m: MinionInstance in agent.friendly_board:
		if not m.can_attack():
			continue
		if m.card_data.id == "champion_rift_stalker":
			continue
		if (m.card_data as MinionCardData).passive_effect_id == "hollow_sentinel_spark_buff":
			continue
		if m.card_data.id == "void_spark" and has_champion and has_hollow:
			continue
		eligible.append(m)
	if eligible.is_empty():
		return
	# Pick lowest ATK+HP to sacrifice
	eligible.sort_custom(func(a: MinionInstance, b: MinionInstance) -> bool:
		return (a.effective_atk() + a.current_health) < (b.effective_atk() + b.current_health))
	var sacrifice: MinionInstance = eligible[0]
	# Trade the sacrifice into the enemy
	var guards := CombatManager.get_taunt_minions(agent.opponent_board)
	if guards.is_empty():
		if sacrifice.can_attack_hero():
			await agent.do_attack_hero(sacrifice)
		elif not agent.opponent_board.is_empty():
			var target := agent.pick_swift_target(sacrifice)
			await agent.do_attack_minion(sacrifice, target)
	else:
		await agent.do_attack_minion(sacrifice, guards[0])

func _has_hollow_on_board() -> bool:
	for m: MinionInstance in agent.friendly_board:
		if (m.card_data as MinionCardData).passive_effect_id == "hollow_sentinel_spark_buff":
			return true
	return false

## True if the enemy board has at least one Void Spark.
func _has_sparks_on_board() -> bool:
	for m: MinionInstance in agent.friendly_board:
		if m.card_data.id == "void_spark":
			return true
	return false

## Sort minions by play priority: Hollow Sentinel always first (key piece),
## then by cost (cheapest first).
func _sort_by_play_priority(a: CardInstance, b: CardInstance) -> bool:
	var a_sentinel := a.card_data.id == "hollow_sentinel"
	var b_sentinel := b.card_data.id == "hollow_sentinel"
	if a_sentinel != b_sentinel:
		return a_sentinel  # Sentinel always first — must be on board before champion
	return agent.sort_by_total_cost(a, b)

## Play regular (non-spark-cost) minions with board awareness.
func _play_regular_minions() -> void:
	var _dbg: bool = agent.scene.get("debug_log_enabled") if agent.scene.get("debug_log_enabled") != null else false
	var placed := true
	while placed:
		placed = false
		var minion_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is MinionCardData and inst.card_data.void_spark_cost <= 0:
				minion_hand.append(inst)
		minion_hand.sort_custom(_sort_by_play_priority)
		if _dbg and not minion_hand.is_empty():
			var names: Array[String] = []
			for inst in minion_hand: names.append(inst.card_data.card_name)
			print("    [AI] Regular minions in hand: %s | Empty slots: %d | Essence: %d | Mana: %d" % [", ".join(names), _empty_slot_count(), agent.essence, agent.mana])
		for inst in minion_hand:
			var mc := inst.card_data as MinionCardData
			var mana_cost: int = agent.effective_minion_mana_cost(mc)
			if mc.essence_cost > agent.essence or mana_cost > agent.mana:
				if _dbg: print("    [AI] SKIP %s: can't afford (need %dE+%dM, have %dE+%dM)" % [mc.card_name, mc.essence_cost, mana_cost, agent.essence, agent.mana])
				continue
			var is_sentinel := mc.id == "hollow_sentinel"
			# Hollow Sentinel: only needs 1 open slot (for itself) — exempt from extra reserves
			# Other minions: leave 1 slot for passive spark generation
			if not is_sentinel and _empty_slot_count() <= 1:
				if _dbg: print("    [AI] SKIP %s: need 2+ empty slots, have %d" % [mc.card_name, _empty_slot_count()])
				continue
			if is_sentinel and _empty_slot_count() < 1:
				if _dbg: print("    [AI] SKIP Hollow Sentinel: no empty slots")
				continue
			# Rift Tender: needs 3 empty (itself + spark summon + passive spark slot)
			if mc.id == "rift_tender" and _empty_slot_count() < 3:
				if _dbg: print("    [AI] SKIP Rift Tender: need 3 empty, have %d" % _empty_slot_count())
				continue
			# Reserve an extra slot for champion when near threshold (not for sentinel)
			if not is_sentinel and _should_reserve_champion_slot() and _empty_slot_count() <= 2:
				if _dbg: print("    [AI] SKIP %s: champion slot reserved" % mc.card_name)
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

## Play spark-cost spells. Only called when board is developed.
func _play_spark_spells() -> void:
	var cast := true
	while cast:
		cast = false
		var best: CardInstance = null
		var best_priority := -1
		for inst in agent.hand:
			if not (inst.card_data is SpellCardData):
				continue
			if inst.card_data.void_spark_cost <= 0:
				continue
			if not _can_afford_spark_card(inst.card_data):
				continue
			var p: int = _spark_spell_priority(inst.card_data.id)
			if p > best_priority:
				best = inst
				best_priority = p
		if best != null:
			var spell := best.card_data as SpellCardData
			var sc: int = _effective_spark_cost(spell)
			var plan := _plan_spark_payment(sc)
			if plan.is_empty(): return
			await _pay_sparks_smart(plan, DeckType.TEMPO)
			if not agent.is_alive(): return
			agent.mana -= agent.effective_spell_cost(spell)
			if not await agent.commit_play_spell(best, pick_spell_target(spell)):
				return
			cast = true

## Play spark-cost minions. Only called when board is developed.
func _play_spark_minions() -> void:
	var placed := true
	while placed:
		placed = false
		for inst in agent.hand.duplicate():
			if not (inst.card_data is MinionCardData):
				continue
			if inst.card_data.void_spark_cost <= 0:
				continue
			if not _can_afford_spark_card(inst.card_data):
				continue
			# Always leave 1 slot open for passive spark generation
			if _empty_slot_count() <= 1:
				continue
			# Reserve an extra slot for champion
			if _should_reserve_champion_slot() and _empty_slot_count() <= 2:
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return
			var mc := inst.card_data as MinionCardData
			var sc: int = _effective_spark_cost(mc)
			var plan := _plan_spark_payment(sc)
			if plan.is_empty(): return
			await _pay_sparks_smart(plan, DeckType.TEMPO)
			if not agent.is_alive(): return
			agent.essence -= mc.essence_cost
			agent.mana    -= agent.effective_minion_mana_cost(mc)
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

func _spark_spell_priority(id: String) -> int:
	match id:
		"void_pulse":    return 2
		"rift_collapse": return 3
		"dimensional_breach": return 1
	return 0
