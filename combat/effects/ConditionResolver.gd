## ConditionResolver.gd
## Evaluates boolean conditions that gate EffectStep execution.
## All methods are static — no instance needed.
##
## Conditions are short string IDs stored in EffectStep.conditions.
## check_all() must return true for a step to execute.
## For minion-targeting steps, target is the specific minion being evaluated.
## For hero/global steps, target is null.
class_name ConditionResolver
extends RefCounted

static func check_all(conditions: Array[String], ctx: EffectContext, target) -> bool:
	for cond in conditions:
		if not check(cond, ctx, target):
			return false
	return true

static func check(cond: String, ctx: EffectContext, target) -> bool:
	var scene = ctx.scene
	match cond:
		# --- Target type conditions ---
		"is_demon":
			return target is MinionInstance and target.card_data.minion_type == Enums.MinionType.DEMON
		"is_human":
			return target is MinionInstance and target.card_data.minion_type == Enums.MinionType.HUMAN
		"is_spirit":
			return target is MinionInstance and target.card_data.minion_type == Enums.MinionType.SPIRIT
		"is_beast":
			return target is MinionInstance and target.card_data.minion_type == Enums.MinionType.BEAST
		"is_void_imp":
			return target is MinionInstance and scene._minion_has_tag(target, "void_imp")
		"is_corrupted":
			return target is MinionInstance and BuffSystem.has_type(target, Enums.BuffType.CORRUPTION)
		"not_self":
			return target != ctx.source

		# --- Board state conditions ---
		"board_not_full":
			return scene._has_empty_player_slot()
		"board_empty":
			return scene.player_board.is_empty()
		"no_active_traps":
			return scene.active_traps.is_empty()
		"has_active_environment":
			return scene.active_environment != null
		"has_friendly_demon":
			return scene._count_type_on_board(Enums.MinionType.DEMON, ctx.owner) > 0
		"has_friendly_human":
			return scene._count_type_on_board(Enums.MinionType.HUMAN, ctx.owner) > 0
		"not_has_friendly_human":
			return scene._count_type_on_board(Enums.MinionType.HUMAN, ctx.owner) == 0

		# --- Resource conditions ---
		"void_marks_5plus":
			return scene.enemy_void_marks >= 5
		"has_void_marks":
			return scene.enemy_void_marks > 0

		# --- Talent conditions ---
		"no_piercing_void":
			return not (ctx.owner == "player" and ctx.scene._has_talent("piercing_void"))
		"has_piercing_void":
			return ctx.owner == "player" and ctx.scene._has_talent("piercing_void")

		# --- Dead minion conditions (on_player_minion_died_steps context) ---
		"dead_is_demon":
			return ctx.dead_minion != null and ctx.dead_minion.card_data.minion_type == Enums.MinionType.DEMON
		"dead_is_human":
			return ctx.dead_minion != null and ctx.dead_minion.card_data.minion_type == Enums.MinionType.HUMAN
		"dead_is_void_imp":
			return ctx.dead_minion != null and scene._minion_has_tag(ctx.dead_minion, "void_imp")

		# --- Turn timing conditions ---
		"enemy_turn":
			return not scene.turn_manager.is_player_turn
		"player_turn":
			return scene.turn_manager.is_player_turn

		_:
			push_warning("ConditionResolver: unknown condition '%s'" % cond)
			return true
