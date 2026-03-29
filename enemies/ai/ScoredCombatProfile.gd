## ScoredCombatProfile.gd
## CombatProfile subclass that uses scoring to decide all actions.
## Runs a unified action loop (interleaved play + attack) instead of
## separate play_phase / attack_phase.
##
## Specialized profiles subclass this and:
##   1. Override _init() to adjust _weights fields
##   2. Override _adjust_* hooks for profile-specific rules
##   3. Override setup_resource_growth() for custom growth logic
class_name ScoredCombatProfile
extends CombatProfile

var _weights: ScoringWeights = ScoringWeights.new()
var _use_lookahead: bool = true

## Override in subclasses to customize weights.
func get_weights() -> ScoringWeights:
	return _weights

# ---------------------------------------------------------------------------
# Phase overrides — play_phase is empty, all logic in attack_phase
# ---------------------------------------------------------------------------

## Empty — all decisions happen in the unified action loop.
func play_phase() -> void:
	pass

## Unified action loop: scores ALL possible actions (play card, attack minion,
## attack hero) each step, picks the best, executes, then re-evaluates.
func attack_phase() -> void:
	# Fast-path: check for lethal first (inherited from CombatProfile)
	var lethal_damage: int = _calc_lethal_damage()
	if lethal_damage >= agent.opponent_hp:
		await _play_lethal_spells()
		if not agent.is_alive():
			return
		# After buff/damage spells, go face with everyone
		for m in agent.friendly_board.duplicate():
			if not agent.friendly_board.has(m) or not m.can_attack():
				continue
			var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
			if guards.is_empty() and m.can_attack_hero():
				if not await agent.do_attack_hero(m):
					return
			elif not guards.is_empty():
				var g := _pick_best_guard(m, guards)
				if not await agent.do_attack_minion(m, g):
					return
			elif not agent.opponent_board.is_empty():
				var t := agent.pick_swift_target(m)
				if not await agent.do_attack_minion(m, t):
					return
		return

	# Main unified action loop
	var max_iterations: int = 30  # Safety cap
	for _iter in max_iterations:
		if not agent.is_alive():
			return
		var best: Dictionary = _find_best_action()
		if best.is_empty():
			break
		if not await _execute_action(best):
			return

# ---------------------------------------------------------------------------
# Action enumeration and scoring
# ---------------------------------------------------------------------------

func _find_best_action() -> Dictionary:
	var w: ScoringWeights = get_weights()
	var best_score: float = w.action_threshold
	var best: Dictionary = {}

	var global_adj: float = _global_context_adjustment()

	# --- Score all PLAY actions ---
	for inst in agent.hand:
		var play_score: float = _score_play(inst, w) + global_adj
		play_score = _adjust_play_score(inst, play_score)
		if play_score > best_score:
			best_score = play_score
			best = {type = "play", inst = inst, score = play_score}

	# --- Score all ATTACK actions ---
	var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
	for attacker in agent.friendly_board:
		if not attacker.can_attack():
			continue

		# Minion targets (guards only if guards exist)
		var targets: Array[MinionInstance] = guards if not guards.is_empty() else agent.opponent_board.duplicate()
		for target in targets:
			var atk_score: float = _score_attack_minion(attacker, target, w) + global_adj
			atk_score = _adjust_attack_score(attacker, target, atk_score)
			if atk_score > best_score:
				best_score = atk_score
				best = {type = "attack_minion", attacker = attacker, target = target, score = atk_score}

		# Hero attack (only if no guards and can attack hero)
		if guards.is_empty() and attacker.can_attack_hero():
			var face_score: float = _score_attack_hero(attacker, w) + global_adj
			if face_score > best_score:
				best_score = face_score
				best = {type = "attack_hero", attacker = attacker, score = face_score}

	return best

# ---------------------------------------------------------------------------
# Play scoring
# ---------------------------------------------------------------------------

func _score_play(inst: CardInstance, w: ScoringWeights) -> float:
	var card: CardData = inst.card_data
	if card is MinionCardData:
		return _score_play_minion(inst, card as MinionCardData, w)
	elif card is SpellCardData:
		return _score_play_spell(inst, card as SpellCardData, w)
	elif card is TrapCardData:
		return _score_play_trap(inst, card as TrapCardData, w)
	elif card is EnvironmentCardData:
		return _score_play_environment(inst, card as EnvironmentCardData, w)
	return -1.0

func _score_play_minion(inst: CardInstance, mc: MinionCardData, w: ScoringWeights) -> float:
	if mc.essence_cost > agent.essence or mc.mana_cost > agent.mana:
		return -1.0
	var empty_slots: int = agent.empty_slot_count()
	if empty_slots <= 0:
		return -1.0
	# Base minion value on board
	var hypothetical: MinionInstance = MinionInstance.create(mc, "friendly")
	var minion_value: float = BoardEvaluator.score_minion(hypothetical, w)
	# Board fill bonus — rewards flooding (more empty slots = higher bonus)
	minion_value += empty_slots * w.board_fill_bonus
	# On-play effect value
	var on_play_value: float = BoardEvaluator.estimate_effect_steps_value(
			mc.on_play_effect_steps, agent.friendly_board, agent.opponent_board, w)
	return minion_value + on_play_value

func _score_play_spell(inst: CardInstance, spell: SpellCardData, w: ScoringWeights) -> float:
	var cost: int = agent.effective_spell_cost(spell)
	if cost > agent.mana:
		return -1.0
	if not can_cast_spell(spell):
		return -1.0
	return BoardEvaluator.estimate_effect_steps_value(
			spell.effect_steps, agent.friendly_board, agent.opponent_board, w)

func _score_play_trap(inst: CardInstance, trap: TrapCardData, w: ScoringWeights) -> float:
	var trap_cost: int = inst.effective_cost()
	if trap_cost > agent.mana:
		return -1.0
	# Runes have persistent aura value
	if trap.is_rune:
		var aura_value: float = BoardEvaluator.estimate_effect_steps_value(
				trap.aura_effect_steps, agent.friendly_board, agent.opponent_board, w)
		# Aura fires repeatedly — estimate 3 turns of value
		return aura_value * 3.0 + 50.0
	# Regular traps: flat heuristic (trigger timing is hard to predict)
	return 80.0

func _score_play_environment(inst: CardInstance, env: EnvironmentCardData, w: ScoringWeights) -> float:
	if env.cost > agent.mana:
		return -1.0
	# Don't replace an existing environment (wasteful)
	var scene: Object = agent.scene
	if scene != null and scene.get("active_environment") != null:
		return -1.0
	# Passive + ritual value
	var passive_value: float = BoardEvaluator.estimate_effect_steps_value(
			env.passive_effect_steps, agent.friendly_board, agent.opponent_board, w)
	# Passive fires each turn — estimate 3 turns
	var ritual_bonus: float = env.rituals.size() * 100.0
	return passive_value * 3.0 + ritual_bonus

# ---------------------------------------------------------------------------
# Attack scoring
# ---------------------------------------------------------------------------

func _score_attack_minion(attacker: MinionInstance, target: MinionInstance, w: ScoringWeights) -> float:
	var atk_damage: int = attacker.effective_atk()
	var def_damage: int = target.effective_atk()

	# Value before attack
	var our_value_before: float = BoardEvaluator.score_minion(attacker, w)
	our_value_before = _adjust_minion_value(attacker, our_value_before, true)
	var their_value_before: float = BoardEvaluator.score_minion(target, w)
	their_value_before = _adjust_minion_value(target, their_value_before, false)

	# Value after attack
	var our_value_after: float = BoardEvaluator.predict_value_after_damage(attacker, def_damage, w)
	var their_value_after: float = BoardEvaluator.predict_value_after_damage(target, atk_damage, w)

	var attacker_survives: bool = BoardEvaluator.predict_survives(attacker, def_damage)
	var target_survives: bool = BoardEvaluator.predict_survives(target, atk_damage)

	# Net value swing: how much better off are we?
	var our_loss: float = our_value_before - our_value_after
	var their_loss: float = their_value_before - their_value_after
	var delta: float = their_loss - our_loss

	# Lifedrain healing bonus
	if attacker.has_lifedrain() and atk_damage > 0:
		delta += atk_damage * w.hero_hp_weight

	# Overkill penalty (wasted damage)
	if not target_survives:
		var total_hp: int = target.current_health + target.current_shield
		var overkill: int = maxi(0, atk_damage - total_hp)
		if target.has_deathless():
			overkill = 0
		delta -= overkill * w.overkill_penalty

	# 1-turn lookahead: opponent's best response
	if _use_lookahead:
		var opponent_response: float = _estimate_opponent_response(
				attacker, attacker_survives, target, target_survives, w)
		delta -= opponent_response * w.lookahead_discount

	return delta

func _score_attack_hero(attacker: MinionInstance, w: ScoringWeights) -> float:
	var damage: int = attacker.effective_atk()
	var score: float = damage * w.face_damage_weight * w.hero_hp_weight

	# Lethal bonus
	if damage >= agent.opponent_hp:
		score += w.lethal_bonus

	# Lifedrain
	if attacker.has_lifedrain():
		score += damage * w.hero_hp_weight

	# No lookahead penalty for face attacks — the opponent responds regardless
	# of whether we go face or trade. Lookahead is only meaningful when comparing
	# "trade minion A into minion B" (removes a threat) vs doing nothing.
	# Face attacks should be evaluated on pure damage value.

	return score

# ---------------------------------------------------------------------------
# 1-turn lookahead
# ---------------------------------------------------------------------------

## Estimate the opponent's best greedy response after we attack a minion.
func _estimate_opponent_response(
		our_attacker: MinionInstance, our_attacker_alive: bool,
		their_target: MinionInstance, their_target_alive: bool,
		w: ScoringWeights) -> float:
	var total_gain: float = 0.0
	for opp_m in agent.opponent_board:
		# Skip the target if it died
		if opp_m == their_target and not their_target_alive:
			continue
		if opp_m.effective_atk() <= 0:
			continue
		var best_gain: float = 0.0
		# Check each of our minions as a target
		for our_m in agent.friendly_board:
			if our_m == our_attacker and not our_attacker_alive:
				continue
			var our_m_value: float = BoardEvaluator.score_minion(our_m, w)
			var opp_m_value: float = BoardEvaluator.score_minion(opp_m, w)
			var our_m_dies: bool = not BoardEvaluator.predict_survives(our_m, opp_m.effective_atk())
			var opp_m_dies: bool = not BoardEvaluator.predict_survives(opp_m, our_m.effective_atk())
			var gain: float = 0.0
			if our_m_dies:
				gain += our_m_value  # They destroy our minion
			if opp_m_dies:
				gain -= opp_m_value  # But they lose theirs
			if gain > best_gain:
				best_gain = gain
		# Face attack option
		var face_gain: float = opp_m.effective_atk() * w.face_damage_weight * w.hero_hp_weight
		if face_gain > best_gain:
			best_gain = face_gain
		total_gain += best_gain
	return total_gain

## (Removed: _estimate_opponent_face_response — face attacks no longer use
## lookahead because the opponent responds regardless of our action choice.
## Lookahead only matters for trade vs. trade comparison.)

# ---------------------------------------------------------------------------
# Action execution
# ---------------------------------------------------------------------------

func _execute_action(action: Dictionary) -> bool:
	match action.type:
		"play":
			return await _execute_play(action.inst as CardInstance)
		"attack_minion":
			return await agent.do_attack_minion(
					action.attacker as MinionInstance,
					action.target as MinionInstance)
		"attack_hero":
			return await agent.do_attack_hero(action.attacker as MinionInstance)
	return true

func _execute_play(inst: CardInstance) -> bool:
	var card: CardData = inst.card_data
	if card is MinionCardData:
		var mc := card as MinionCardData
		agent.essence -= mc.essence_cost
		agent.mana -= mc.mana_cost
		var slot: BoardSlot = agent.find_empty_slot()
		if slot == null:
			return true  # Board filled between scoring and execution
		return await agent.commit_play_minion(inst, slot, pick_on_play_target(mc))
	elif card is SpellCardData:
		var spell := card as SpellCardData
		agent.mana -= agent.effective_spell_cost(spell)
		return await agent.commit_play_spell(inst, pick_spell_target(spell))
	elif card is TrapCardData:
		agent.mana -= inst.effective_cost()
		return await agent.commit_play_trap(inst)
	elif card is EnvironmentCardData:
		agent.mana -= (card as EnvironmentCardData).cost
		return await agent.commit_play_environment(inst)
	return true

# ---------------------------------------------------------------------------
# Resource growth (hand-aware scoring)
# ---------------------------------------------------------------------------

## Install a scored growth strategy. Override setup_resource_growth on profile.
func setup_resource_growth(sim_state: Object) -> void:
	sim_state.player_growth_override = func(turn: int) -> void:
		_scored_growth(sim_state, turn)

func _scored_growth(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e_max: int = state.player_essence_max
	var m_max: int = state.player_mana_max
	if e_max + m_max >= 11:
		return
	var e_value: float = _growth_value_essence(state, e_max + 1, m_max)
	var m_value: float = _growth_value_mana(state, e_max, m_max + 1)
	if e_value >= m_value:
		state.player_essence_max += 1
	else:
		state.player_mana_max += 1

func _growth_value_essence(state: Object, new_e: int, m: int) -> float:
	var w: ScoringWeights = get_weights()
	var value: float = 20.0  # Base essence value
	var hand: Array = state.player_hand
	for inst in hand:
		if inst.card_data is MinionCardData:
			var mc: MinionCardData = inst.card_data as MinionCardData
			var could_before: bool = mc.essence_cost <= (new_e - 1) and mc.mana_cost <= m
			var can_now: bool = mc.essence_cost <= new_e and mc.mana_cost <= m
			if can_now and not could_before:
				var hyp: MinionInstance = MinionInstance.create(mc, "friendly")
				value += BoardEvaluator.score_minion(hyp, w)
	return value * w.resource_unlock_weight

func _growth_value_mana(state: Object, e: int, new_m: int) -> float:
	var w: ScoringWeights = get_weights()
	var value: float = 15.0  # Base mana value
	var hand: Array = state.player_hand
	for inst in hand:
		if inst.card_data is SpellCardData:
			var spell: SpellCardData = inst.card_data as SpellCardData
			var could_before: bool = spell.cost <= (new_m - 1)
			var can_now: bool = spell.cost <= new_m
			if can_now and not could_before:
				value += BoardEvaluator.estimate_effect_steps_value(
						spell.effect_steps, [], [], w)
		elif inst.card_data is TrapCardData:
			var trap_cost: int = inst.effective_cost()
			var could_before: bool = trap_cost <= (new_m - 1)
			var can_now: bool = trap_cost <= new_m
			if can_now and not could_before:
				value += 100.0
		elif inst.card_data is MinionCardData:
			var mc: MinionCardData = inst.card_data as MinionCardData
			if mc.mana_cost > 0:
				var could_before: bool = mc.essence_cost <= e and mc.mana_cost <= (new_m - 1)
				var can_now: bool = mc.essence_cost <= e and mc.mana_cost <= new_m
				if can_now and not could_before:
					var hyp: MinionInstance = MinionInstance.create(mc, "friendly")
					value += BoardEvaluator.score_minion(hyp, w)
	return value * w.resource_unlock_weight

# ---------------------------------------------------------------------------
# Profile override hooks (extensibility)
# ---------------------------------------------------------------------------

## Adjust a minion's base score. Use for passive auras, synergy bonuses,
## on-death spawn value, or enemy hero passive awareness.
func _adjust_minion_value(m: MinionInstance, base_value: float, _is_friendly: bool) -> float:
	return base_value

## Adjust an attack action's score. Use for on-death trigger awareness,
## rune interactions, trap awareness.
func _adjust_attack_score(_attacker: MinionInstance, _target: MinionInstance, base_delta: float) -> float:
	return base_delta

## Adjust a card play action's score. Use for combo setups, synergy chains,
## buff-before-attack sequencing.
func _adjust_play_score(_card: CardInstance, base_value: float) -> float:
	return base_value

## Called once per action loop iteration for global context adjustments:
## active runes, environment cards, hero passives, board-wide auras.
func _global_context_adjustment() -> float:
	return 0.0

## Estimate opponent hand size (unknown in live game, knowable in sim).
## Default: 5 (midpoint).
func _estimate_opponent_hand_size() -> int:
	return 5
