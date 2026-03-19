## EffectResolver.gd
## Executes an Array[EffectStep] against an EffectContext.
## Each step is evaluated independently: conditions checked, targets resolved, effect applied.
##
## CombatScene is accessed via ctx.scene — no direct dependency on CombatScene's class name,
## so this file compiles independently.
class_name EffectResolver
extends RefCounted

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

static func run(steps: Array, ctx: EffectContext) -> void:
	for raw in steps:
		var step: EffectStep
		if raw is Dictionary:
			step = EffectStep.from_dict(raw)
		elif raw is EffectStep:
			step = raw
		if step:
			_execute(step, ctx)

# ---------------------------------------------------------------------------
# Step dispatcher
# ---------------------------------------------------------------------------

static func _execute(step: EffectStep, ctx: EffectContext) -> void:
	# Hero / global effects — no minion target needed
	match step.effect_type:
		EffectStep.EffectType.DAMAGE_HERO:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var dmg      := _amount(step, ctx)
				var opponent := "enemy" if ctx.owner == "player" else "player"
				ctx.scene._on_hero_damaged(opponent, dmg)
			return

		EffectStep.EffectType.HEAL_HERO:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				ctx.scene._on_hero_healed(ctx.owner, _amount(step, ctx))
			return

		EffectStep.EffectType.DRAW:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var count := maxi(1, step.amount)
				for _i in count:
					if ctx.owner == "player":
						ctx.scene.turn_manager.draw_card()
					else:
						ctx.scene.enemy_ai._draw_cards(1)
			return

		EffectStep.EffectType.ADD_CARD:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var card := CardDatabase.get_card(step.card_id)
				if card:
					if ctx.owner == "player":
						ctx.scene.turn_manager.add_to_hand(card)
					else:
						ctx.scene.enemy_ai.add_to_hand(card)
			return

		EffectStep.EffectType.SUMMON:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				ctx.scene._summon_token(step.card_id, ctx.owner, step.token_atk, step.token_hp, step.token_shield)
			return

		EffectStep.EffectType.GRANT_MANA:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				ctx.scene.turn_manager.gain_mana(step.amount)
			return

		EffectStep.EffectType.GRANT_ESSENCE:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				ctx.scene.turn_manager.gain_essence(step.amount)
			return

		EffectStep.EffectType.VOID_MARK:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				ctx.scene._apply_void_mark(step.amount)
			return

		EffectStep.EffectType.VOID_BOLT:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				ctx.scene._deal_void_bolt_damage(_amount(step, ctx))
			return

		EffectStep.EffectType.HARDCODED:
			ctx.scene._resolve_hardcoded(step.hardcoded_id, ctx)
			return

		EffectStep.EffectType.CONVERT_RESOURCE:
			if ConditionResolver.check_all(step.conditions, ctx, null) and ctx.owner == "player":
				var tm = ctx.scene.turn_manager
				if step.convert_from == "mana" and step.convert_to == "essence":
					tm.convert_mana_to_essence()
				elif step.convert_from == "essence" and step.convert_to == "mana":
					tm.convert_essence_to_mana()
			return

		EffectStep.EffectType.DESTROY:
			# Environment destruction — no minion pool needed
			if step.scope == EffectStep.TargetScope.ACTIVE_ENVIRONMENT:
				if ConditionResolver.check_all(step.conditions, ctx, null):
					if ctx.scene.active_environment != null:
						ctx.scene._unregister_env_rituals()
						ctx.scene.active_environment = null
						ctx.scene._update_environment_display()
				return

	# Minion / trap targeting effects — resolve pool then apply per target
	var targets := TargetResolver.resolve(step, ctx)
	for t in targets:
		if not ConditionResolver.check_all(step.conditions, ctx, t):
			continue
		_apply(step, t, _amount(step, ctx), ctx)

# ---------------------------------------------------------------------------
# Per-target application
# ---------------------------------------------------------------------------

static func _apply(step: EffectStep, target, amount: int, ctx: EffectContext) -> void:
	var scene = ctx.scene
	match step.effect_type:
		EffectStep.EffectType.DAMAGE_MINION:
			scene.combat_manager.apply_spell_damage(target, amount)

		EffectStep.EffectType.BUFF_ATK:
			var buff_type := Enums.BuffType.ATK_BONUS if step.permanent else Enums.BuffType.TEMP_ATK
			BuffSystem.apply(target, buff_type, amount, step.source_tag)
			scene._refresh_slot_for(target)

		EffectStep.EffectType.BUFF_HP:
			target.current_health += amount
			scene._refresh_slot_for(target)

		EffectStep.EffectType.CORRUPTION:
			var stacks := maxi(1, amount)
			for _i in stacks:
				scene._corrupt_minion(target)

		EffectStep.EffectType.SACRIFICE:
			scene.combat_manager.kill_minion(target)

		EffectStep.EffectType.GRANT_KEYWORD:
			match step.keyword:
				Enums.Keyword.GUARD:
					BuffSystem.apply(target, Enums.BuffType.GRANT_GUARD, 1, step.source_tag)
					scene._refresh_slot_for(target)
				Enums.Keyword.LIFEDRAIN:
					BuffSystem.apply(target, Enums.BuffType.GRANT_LIFEDRAIN, 1, step.source_tag)
					scene._refresh_slot_for(target)

		EffectStep.EffectType.PURGE:
			if step.purge_filter.is_empty():
				if target.owner == scene._opponent_of(ctx.owner):
					BuffSystem.dispel(target)
				else:
					BuffSystem.cleanse(target)
			else:
				BuffSystem.remove_type(target, Enums.BuffType[step.purge_filter])
			scene._refresh_slot_for(target)

		EffectStep.EffectType.DESTROY:
			# Trap/rune destruction
			if target is TrapCardData:
				if target.is_rune:
					scene._remove_rune_aura(target)
				scene.active_traps.erase(target)
				scene._update_trap_display()

# ---------------------------------------------------------------------------
# Amount resolution
# ---------------------------------------------------------------------------

static func _amount(step: EffectStep, ctx: EffectContext) -> int:
	match step.multiplier_key:
		"rune_aura":  return step.amount * ctx.scene._rune_aura_multiplier()
		"void_marks": return step.amount * ctx.scene.enemy_void_marks
		"other_friendly_demon_count":
			var count := 0
			for m in ctx.scene._friendly_board(ctx.owner):
				if m != ctx.source and m.card_data.minion_type == Enums.MinionType.DEMON:
					count += 1
			return step.amount * count
		_:            return step.amount
