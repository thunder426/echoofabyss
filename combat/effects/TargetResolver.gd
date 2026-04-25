## TargetResolver.gd
## Resolves the pool of targets for a given EffectStep and EffectContext.
## Returns Array — elements are MinionInstance for minion-targeting scopes,
## or TrapCardData for trap-targeting scopes.
## Hero/global effects (DAMAGE_HERO, HEAL_HERO, DRAW, etc.) bypass TargetResolver entirely.
class_name TargetResolver
extends RefCounted

static func resolve(step: EffectStep, ctx: EffectContext) -> Array:
	var pool := _base_pool(step.scope, ctx)

	# Apply minion filter (skips non-MinionInstance elements like TrapCardData)
	if step.filter != EffectStep.MinionFilter.NONE:
		pool = pool.filter(func(t): return _passes_filter(step.filter, t, ctx))

	# Exclude the source minion itself when requested (skip for SELF scope — source is the point)
	if step.exclude_self and ctx.source != null and step.scope != EffectStep.TargetScope.SELF:
		pool = pool.filter(func(t): return t != ctx.source)

	match step.scope:
		EffectStep.TargetScope.SINGLE_CHOSEN, EffectStep.TargetScope.SINGLE_CHOSEN_FRIENDLY:
			# Return the chosen target only if it is still alive (in pool); otherwise fizzle.
			if ctx.chosen_target != null and pool.has(ctx.chosen_target):
				return [ctx.chosen_target]
			return []
		EffectStep.TargetScope.SINGLE_RANDOM, EffectStep.TargetScope.FILTERED_RANDOM, EffectStep.TargetScope.FILTERED_RANDOM_FRIENDLY, EffectStep.TargetScope.SINGLE_RANDOM_TRAP, EffectStep.TargetScope.SINGLE_RANDOM_ANY:
			return _random_one(pool)
		_:
			return pool

# ---------------------------------------------------------------------------
# Base pool builders
# ---------------------------------------------------------------------------

static func _base_pool(scope: EffectStep.TargetScope, ctx: EffectContext) -> Array:
	var scene = ctx.scene
	match scope:
		EffectStep.TargetScope.SELF:
			return [ctx.source] if ctx.source != null else []
		EffectStep.TargetScope.ALL_ENEMY, EffectStep.TargetScope.SINGLE_RANDOM, EffectStep.TargetScope.FILTERED_RANDOM:
			return scene._opponent_board(ctx.owner).duplicate()
		EffectStep.TargetScope.FILTERED_RANDOM_FRIENDLY:
			return scene._friendly_board(ctx.owner).duplicate()
		EffectStep.TargetScope.SINGLE_RANDOM_ANY:
			# Enemy minions + enemy hero (sentinel string). Untyped Array so we can mix types.
			var pool_any: Array = []
			for m in scene._opponent_board(ctx.owner):
				pool_any.append(m)
			pool_any.append("enemy_hero")
			return pool_any
		EffectStep.TargetScope.ALL_FRIENDLY:
			return scene._friendly_board(ctx.owner).duplicate()
		EffectStep.TargetScope.SINGLE_CHOSEN:
			# Both boards — spells like Arcane Strike ("any_minion") can target friendlies.
			# The chosen_target check in resolve() ensures only the picked minion is hit.
			return (scene._friendly_board(ctx.owner) + scene._opponent_board(ctx.owner)).duplicate()
		EffectStep.TargetScope.SINGLE_CHOSEN_FRIENDLY:
			return scene._friendly_board(ctx.owner).duplicate()
		EffectStep.TargetScope.ALL_BOARD:
			return (scene.player_board + scene.enemy_board).duplicate()
		EffectStep.TargetScope.TRIGGER_MINION:
			return [ctx.trigger_minion] if ctx.trigger_minion != null else []
		EffectStep.TargetScope.DEAD_MINION:
			return [ctx.dead_minion] if ctx.dead_minion != null else []
		EffectStep.TargetScope.SINGLE_RANDOM_TRAP, EffectStep.TargetScope.ALL_TRAPS:
			return scene.active_traps.duplicate()
		EffectStep.TargetScope.SINGLE_CHOSEN_TRAP_OR_ENV:
			# Must be set by the AI before casting — no fallback.
			if ctx.chosen_object == null:
				return []
			return [ctx.chosen_object]
		_:
			return []

# ---------------------------------------------------------------------------
# Filter
# ---------------------------------------------------------------------------

static func _passes_filter(filter: EffectStep.MinionFilter, target, ctx: EffectContext) -> bool:
	# Non-minion targets (TrapCardData etc.) only match IS_RUNE
	if not target is MinionInstance:
		return filter == EffectStep.MinionFilter.IS_RUNE and target is TrapCardData and target.is_rune
	match filter:
		EffectStep.MinionFilter.DEMON:     return target.card_data.minion_type == Enums.MinionType.DEMON
		EffectStep.MinionFilter.HUMAN:     return target.card_data.minion_type == Enums.MinionType.HUMAN
		EffectStep.MinionFilter.SPIRIT:    return target.card_data.minion_type == Enums.MinionType.SPIRIT
		EffectStep.MinionFilter.BEAST:     return target.card_data.minion_type == Enums.MinionType.BEAST
		EffectStep.MinionFilter.VOID_IMP:   return ctx.scene._minion_has_tag(target, "void_imp")
		EffectStep.MinionFilter.FERAL_IMP:  return ctx.scene._minion_has_tag(target, "feral_imp")
		EffectStep.MinionFilter.CORRUPTED: return BuffSystem.has_type(target, Enums.BuffType.CORRUPTION)
		_: return true

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _random_one(pool: Array) -> Array:
	if pool.is_empty():
		return []
	return [pool[randi() % pool.size()]]
