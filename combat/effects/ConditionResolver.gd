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
		"owner_runes_gte_2":
			# True when the owner has at least 2 runes in their active_traps. Used by
			# Runic Blast to branch between "AoE all" and "2 random picks" damage modes.
			var rune_count := 0
			for t in scene._friendly_traps(ctx.owner):
				if (t as TrapCardData).is_rune:
					rune_count += 1
					if rune_count >= 2:
						return true
			return false
		"not_owner_runes_gte_2":
			var rune_count2 := 0
			for t in scene._friendly_traps(ctx.owner):
				if (t as TrapCardData).is_rune:
					rune_count2 += 1
					if rune_count2 >= 2:
						return false
			return true
		"feral_imp_count_gte_3":
			# Used by Void Screech: bonus damage when the caster has at least 3 Feral
			# Imps on their friendly board.
			var feral_count := 0
			for m in scene._friendly_board(ctx.owner):
				if m is MinionInstance and scene._minion_has_tag(m, "feral_imp"):
					feral_count += 1
					if feral_count >= 3:
						return true
			return false

		# --- Resource conditions ---
		"void_marks_5plus":
			return scene.enemy_void_marks >= 5
		"has_void_marks":
			return scene.enemy_void_marks > 0
		# Seris — Flesh thresholds (player-only; enemy Seris is not currently supported)
		"flesh_gte_1":
			var f1 = scene.get("player_flesh") if ctx.owner == "player" else 0
			return (f1 if f1 != null else 0) >= 1
		"flesh_gte_2":
			var f2 = scene.get("player_flesh") if ctx.owner == "player" else 0
			return (f2 if f2 != null else 0) >= 2
		"flesh_gte_3":
			var f3 = scene.get("player_flesh") if ctx.owner == "player" else 0
			return (f3 if f3 != null else 0) >= 3
		"flesh_lt_2":
			var fl2 = scene.get("player_flesh") if ctx.owner == "player" else 0
			return (fl2 if fl2 != null else 0) < 2
		"flesh_lt_3":
			var f4 = scene.get("player_flesh") if ctx.owner == "player" else 0
			return (f4 if f4 != null else 0) < 3
		# True after a SPEND_FLESH/SPEND_FLESH_UP_TO step successfully spent ≥1 Flesh this run.
		# Used to gate enhanced effects on "Spend N: <bonus>" cards.
		"flesh_spent_this_cast":
			return ctx.flesh_spent_this_cast > 0
		# True if the sum of kill_stacks across friendly Grafted Fiend minions is ≥3.
		# Used by Flesh Scout (seris_fleshcraft) to gate its draw condition.
		"friendly_grafted_fiend_kill_stacks_gte_3":
			var total_ks := 0
			for m in scene._friendly_board(ctx.owner):
				if m is MinionInstance and scene._minion_has_tag(m, "grafted_fiend"):
					total_ks += m.kill_stacks
					if total_ks >= 3:
						return true
			return false

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
