## BoardEvaluator.gd
## Static scoring functions for the AI system.
## All methods are static — no instance state. Works with any CombatAgent.
class_name BoardEvaluator
extends RefCounted

# ---------------------------------------------------------------------------
# Minion scoring
# ---------------------------------------------------------------------------

## Score a single minion's board value. Higher = more valuable.
static func score_minion(m: MinionInstance, w: ScoringWeights) -> float:
	var value: float = 0.0
	value += m.effective_atk() * w.atk_weight
	value += m.current_health * w.hp_weight
	value += m.current_shield * w.shield_weight

	# Keyword bonuses
	if m.has_guard():
		value += w.guard_bonus
	if m.has_lifedrain():
		value += w.lifedrain_bonus
	if m.has_deathless():
		value += w.deathless_bonus
	if m.state == Enums.MinionState.SWIFT:
		value += w.swift_bonus

	# Shield regen
	if Enums.Keyword.SHIELD_REGEN_2 in m.card_data.keywords:
		value += w.shield_regen_bonus * 2.0
	elif Enums.Keyword.SHIELD_REGEN_1 in m.card_data.keywords:
		value += w.shield_regen_bonus

	# On-death and passive effect value estimates
	value += _estimate_on_death_value(m, w)
	value += _estimate_passive_value(m, w)

	return value

## Score a board state from one side's perspective. Positive = good for us.
static func score_board(
		friendly_board: Array[MinionInstance],
		opponent_board: Array[MinionInstance],
		friendly_hp: int,
		opponent_hp: int,
		friendly_hand_size: int,
		opponent_hand_size: int,
		w: ScoringWeights) -> float:
	var score: float = 0.0

	for m in friendly_board:
		score += score_minion(m, w)
	for m in opponent_board:
		score -= score_minion(m, w)

	# Hero HP advantage
	score += (friendly_hp - opponent_hp) * w.hero_hp_weight

	# Card advantage
	score += (friendly_hand_size - opponent_hand_size) * w.hand_size_weight

	# Board presence
	score += (friendly_board.size() - opponent_board.size()) * w.board_count_weight

	# Empty board penalty
	if friendly_board.is_empty() and not opponent_board.is_empty():
		score -= w.empty_board_penalty

	return score

# ---------------------------------------------------------------------------
# Damage prediction (lightweight, no triggers)
# ---------------------------------------------------------------------------

## Predict whether a minion survives a given amount of damage.
static func predict_survives(m: MinionInstance, damage: int) -> bool:
	if damage <= 0:
		return true
	var remaining_shield: int = maxi(0, m.current_shield - damage)
	var hp_damage: int = maxi(0, damage - m.current_shield)
	if hp_damage >= m.current_health:
		return m.has_deathless()
	return true

## Predict a minion's value after taking damage (shields absorb first).
## Returns 0.0 if the minion dies (and doesn't have Deathless).
static func predict_value_after_damage(m: MinionInstance, damage: int, w: ScoringWeights) -> float:
	if damage <= 0:
		return score_minion(m, w)
	var shield_absorbed: int = mini(damage, m.current_shield)
	var remaining_shield: int = m.current_shield - shield_absorbed
	var hp_damage: int = damage - shield_absorbed
	var remaining_hp: int = m.current_health - hp_damage

	if remaining_hp <= 0:
		if m.has_deathless():
			# Deathless triggers: HP set to 50, deathless consumed
			remaining_hp = 50
			remaining_shield = 0
			var value: float = 0.0
			value += m.effective_atk() * w.atk_weight
			value += remaining_hp * w.hp_weight
			if m.has_guard():
				value += w.guard_bonus
			if m.has_lifedrain():
				value += w.lifedrain_bonus
			# No deathless bonus — consumed
			return value
		return 0.0  # Dead

	var value: float = 0.0
	value += m.effective_atk() * w.atk_weight
	value += remaining_hp * w.hp_weight
	value += remaining_shield * w.shield_weight
	if m.has_guard():
		value += w.guard_bonus
	if m.has_lifedrain():
		value += w.lifedrain_bonus
	if m.has_deathless():
		value += w.deathless_bonus
	return value

# ---------------------------------------------------------------------------
# Spell / effect step value estimation
# ---------------------------------------------------------------------------

## Estimate the value of an effect_steps array (for spells, on-play, on-death).
## board_context provides friendly_board and opponent_board for scope-aware estimates.
static func estimate_effect_steps_value(
		steps: Array,
		friendly_board: Array[MinionInstance],
		opponent_board: Array[MinionInstance],
		w: ScoringWeights) -> float:
	var value: float = 0.0
	for raw in steps:
		var step: EffectStep = EffectStep.from_dict(raw) if raw is Dictionary else raw as EffectStep
		if step == null:
			continue
		value += _estimate_step_value(step, friendly_board, opponent_board, w)
	return value

static func _estimate_step_value(
		step: EffectStep,
		friendly_board: Array[MinionInstance],
		opponent_board: Array[MinionInstance],
		w: ScoringWeights) -> float:
	match step.effect_type:
		EffectStep.EffectType.DAMAGE_HERO, EffectStep.EffectType.VOID_BOLT:
			return step.amount * w.face_damage_weight * w.hero_hp_weight
		EffectStep.EffectType.DAMAGE_MINION:
			return _estimate_damage_minion_value(step, opponent_board, w)
		EffectStep.EffectType.BUFF_ATK:
			return _estimate_buff_atk_value(step, friendly_board, w)
		EffectStep.EffectType.BUFF_HP:
			return step.amount * w.hp_weight
		EffectStep.EffectType.HEAL_HERO:
			return step.amount * w.hero_hp_weight
		EffectStep.EffectType.DRAW:
			return step.amount * w.hand_size_weight
		EffectStep.EffectType.SUMMON:
			return _estimate_summon_value(step, w)
		EffectStep.EffectType.CORRUPTION:
			return step.amount * w.atk_weight  # Reduces enemy ATK
		EffectStep.EffectType.GRANT_KEYWORD:
			return _estimate_keyword_grant_value(step, w)
		EffectStep.EffectType.GRANT_MANA, EffectStep.EffectType.GRANT_ESSENCE:
			return step.amount * 20.0  # Resource value heuristic
		EffectStep.EffectType.SACRIFICE:
			return -50.0  # Sacrificing one of ours is a cost
		EffectStep.EffectType.VOID_MARK:
			return step.amount * 25.0  # Void marks scale later damage
		EffectStep.EffectType.DESTROY:
			return 100.0  # Removing a trap/env has situational value
	return 0.0

static func _estimate_damage_minion_value(
		step: EffectStep,
		opponent_board: Array[MinionInstance],
		w: ScoringWeights) -> float:
	var damage: int = step.amount
	match step.scope:
		EffectStep.TargetScope.ALL_ENEMY, EffectStep.TargetScope.ALL_BOARD:
			# AoE: value = sum of damage dealt to each enemy minion
			var total: float = 0.0
			for m in opponent_board:
				if not predict_survives(m, damage):
					total += score_minion(m, w)
				else:
					total += damage * w.hp_weight
			return total
		_:
			# Single-target: value of best killable, or chip value
			var best_kill_value: float = 0.0
			for m in opponent_board:
				if damage >= m.current_health + m.current_shield:
					var mv: float = score_minion(m, w)
					if mv > best_kill_value:
						best_kill_value = mv
			if best_kill_value > 0.0:
				return best_kill_value
			return damage * w.hp_weight * 0.5

static func _estimate_buff_atk_value(
		step: EffectStep,
		friendly_board: Array[MinionInstance],
		w: ScoringWeights) -> float:
	match step.scope:
		EffectStep.TargetScope.ALL_FRIENDLY, EffectStep.TargetScope.ALL_BOARD:
			return step.amount * w.atk_weight * friendly_board.size()
		_:
			return step.amount * w.atk_weight

static func _estimate_summon_value(step: EffectStep, w: ScoringWeights) -> float:
	# Use token stats if overridden, else try to look up the card
	var atk: int = step.token_atk
	var hp: int = step.token_hp
	if atk == 0 and hp == 0 and step.card_id != "":
		var card_data: CardData = CardDatabase.get_card(step.card_id)
		if card_data is MinionCardData:
			var mc := card_data as MinionCardData
			atk = mc.atk
			hp = mc.health
	return atk * w.atk_weight + hp * w.hp_weight

static func _estimate_keyword_grant_value(step: EffectStep, w: ScoringWeights) -> float:
	match step.keyword:
		Enums.Keyword.GUARD:
			return w.guard_bonus
		Enums.Keyword.LIFEDRAIN:
			return w.lifedrain_bonus
		Enums.Keyword.DEATHLESS:
			return w.deathless_bonus
		Enums.Keyword.SWIFT:
			return w.swift_bonus
	return 50.0  # Default for unknown keywords

# ---------------------------------------------------------------------------
# On-death / passive value estimation
# ---------------------------------------------------------------------------

## Estimate the value of a minion's on-death effects.
## On-death summons add value (enemy's on-death spawns make them worth MORE to keep alive,
## but also make killing them less clean). For scoring purposes, this adds to minion value.
static func _estimate_on_death_value(m: MinionInstance, w: ScoringWeights) -> float:
	var mc := m.card_data as MinionCardData
	if mc == null:
		return 0.0
	if mc.on_death_effect_steps.is_empty():
		return 0.0
	var value: float = 0.0
	for raw in mc.on_death_effect_steps:
		var step: EffectStep = EffectStep.from_dict(raw) if raw is Dictionary else raw as EffectStep
		if step == null:
			continue
		match step.effect_type:
			EffectStep.EffectType.SUMMON:
				value += _estimate_summon_value(step, w)
			EffectStep.EffectType.DAMAGE_HERO, EffectStep.EffectType.DAMAGE_MINION:
				value += step.amount * w.atk_weight * 0.5
			EffectStep.EffectType.BUFF_ATK, EffectStep.EffectType.BUFF_HP:
				value += step.amount * w.atk_weight * 0.3
			EffectStep.EffectType.DRAW:
				value += step.amount * w.hand_size_weight * 0.5
	return value * w.on_death_weight

## Estimate the value of a minion's passive effects while on board.
static func _estimate_passive_value(m: MinionInstance, w: ScoringWeights) -> float:
	var mc := m.card_data as MinionCardData
	if mc == null:
		return 0.0
	var value: float = 0.0
	# Mana cost discount is a persistent value (saves mana each turn)
	if mc.mana_cost_discount > 0:
		value += mc.mana_cost_discount * 30.0
	# Turn-start effects (recurring value)
	if not mc.on_turn_start_effect_steps.is_empty():
		for raw in mc.on_turn_start_effect_steps:
			var step: EffectStep = EffectStep.from_dict(raw) if raw is Dictionary else raw as EffectStep
			if step == null:
				continue
			match step.effect_type:
				EffectStep.EffectType.BUFF_ATK:
					value += step.amount * w.atk_weight * 0.5
				EffectStep.EffectType.DAMAGE_HERO:
					value += step.amount * w.hero_hp_weight * 0.5
				EffectStep.EffectType.DRAW:
					value += step.amount * w.hand_size_weight * 0.5
				_:
					value += 25.0  # Small default for unknown recurring effects
	# Spell-cast passives (value depends on spell frequency, hard to estimate)
	if mc.on_spell_cast_passive_effect_id != "":
		value += 50.0
	# Void bolt passives
	if mc.on_void_bolt_passive_effect_id != "":
		value += 50.0
	return value * w.passive_weight
