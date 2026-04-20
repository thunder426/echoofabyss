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
	# Consume dark_channeling flag after all steps of a spell resolve
	if ctx.scene.get("_dark_channeling_active") == true:
		ctx.scene.set("_dark_channeling_active", false)

# ---------------------------------------------------------------------------
# Step dispatcher
# ---------------------------------------------------------------------------

static func _execute(step: EffectStep, ctx: EffectContext) -> void:
	# Hero / global effects — no minion target needed
	match step.effect_type:
		EffectStep.EffectType.DAMAGE_HERO:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var dmg      := _dark_channeling_dmg(_amount(step, ctx), ctx)
				var opponent := "enemy" if ctx.owner == "player" else "player"
				ctx.scene.combat_manager.apply_hero_damage(opponent, dmg, Enums.DamageType.SPELL)
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
				if ctx.owner == "player":
					ctx.scene.turn_manager.gain_mana(step.amount)
				else:
					ctx.scene.enemy_ai.mana = mini(ctx.scene.enemy_ai.mana + step.amount, ctx.scene.enemy_ai.mana_max)
			return

		EffectStep.EffectType.GRANT_ESSENCE:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				if ctx.owner == "player":
					ctx.scene.turn_manager.gain_essence(step.amount)
				else:
					ctx.scene.enemy_ai.essence = mini(ctx.scene.enemy_ai.essence + step.amount, ctx.scene.enemy_ai.essence_max)
			return

		EffectStep.EffectType.GROW_MANA_MAX:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var amt := maxi(1, step.amount)
				if ctx.owner == "player":
					ctx.scene.turn_manager.grow_mana_max(amt)
				else:
					var ai = ctx.scene.enemy_ai
					for _i in amt:
						if ai.essence_max + ai.mana_max >= ai.COMBINED_RESOURCE_CAP:
							break
						ai.mana_max += 1
			return

		EffectStep.EffectType.VOID_MARK:
			if ConditionResolver.check_all(step.conditions, ctx, null) and ctx.owner == "player":
				ctx.scene._apply_void_mark(step.amount)
			return

		EffectStep.EffectType.VOID_BOLT:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var dmg := _amount(step, ctx)
				if ctx.owner == "player":
					ctx.scene._deal_void_bolt_damage(dmg, ctx.source, ctx.from_rune)
				else:
					var opponent := "player"
					ctx.scene.combat_manager.apply_hero_damage(opponent, dmg, Enums.DamageType.SPELL)
			return

		EffectStep.EffectType.TUTOR:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var count := maxi(1, step.amount)
				var found := 0
				var deck: Array = ctx.scene._friendly_deck(ctx.owner)
				var i := 0
				while i < deck.size() and found < count:
					var inst: CardInstance = deck[i]
					var match_found := false
					match step.tutor_filter:
						"spark_cost":
							match_found = inst.card_data.void_spark_cost > 0
						"rune":
							match_found = inst.card_data is TrapCardData and (inst.card_data as TrapCardData).is_rune
					if match_found:
						deck.remove_at(i)
						ctx.scene._add_to_owner_hand(ctx.owner, inst)
						found += 1
					else:
						i += 1
			return

		EffectStep.EffectType.COUNTER_SPELL:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var opponent := "player" if ctx.owner == "enemy" else "enemy"
				var key := "_player_spell_counter" if opponent == "player" else "_enemy_spell_counter"
				var current: int = ctx.scene.get(key) if ctx.scene.get(key) != null else 0
				ctx.scene.set(key, current + 1)
			return

		EffectStep.EffectType.HARDCODED:
			ctx.scene._resolve_hardcoded(step.hardcoded_id, ctx)
			return

		EffectStep.EffectType.CONVERT_RESOURCE:
			# Player-only by design — enemy AI has no resource conversion mechanic.
			if ConditionResolver.check_all(step.conditions, ctx, null) and ctx.owner == "player":
				var tm = ctx.scene.turn_manager
				if step.convert_from == "mana" and step.convert_to == "essence":
					tm.convert_mana_to_essence(step.amount if step.amount > 0 else -1)
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
			scene._spell_dmg(target, _dark_channeling_dmg(amount, ctx))

		EffectStep.EffectType.BUFF_ATK:
			var buff_type := Enums.BuffType.ATK_BONUS if step.permanent else Enums.BuffType.TEMP_ATK
			var tag_atk: String = step.source_tag if step.source_tag != "" else ctx.source_card_id
			BuffSystem.apply(target, buff_type, amount, tag_atk)
			scene._refresh_slot_for(target)

		EffectStep.EffectType.BUFF_HP:
			var tag_hp: String = step.source_tag if step.source_tag != "" else ctx.source_card_id
			BuffSystem.apply_hp_gain(target, amount, tag_hp)
			scene._refresh_slot_for(target)

		EffectStep.EffectType.CORRUPTION:
			var stacks := maxi(1, amount)
			for _i in stacks:
				scene._corrupt_minion(target)

		EffectStep.EffectType.SACRIFICE:
			SacrificeSystem.sacrifice(scene, target, ctx.source_card_id)
			scene.combat_manager.kill_minion(target)

		EffectStep.EffectType.KILL_MINION:
			scene.combat_manager.kill_minion(target)

		EffectStep.EffectType.GRANT_KEYWORD:
			match step.keyword:
				Enums.Keyword.GUARD:
					BuffSystem.apply(target, Enums.BuffType.GRANT_GUARD, 1, step.source_tag)
					scene._refresh_slot_for(target)
				Enums.Keyword.LIFEDRAIN:
					BuffSystem.apply(target, Enums.BuffType.GRANT_LIFEDRAIN, 1, step.source_tag)
					scene._refresh_slot_for(target)
				Enums.Keyword.DEATHLESS:
					BuffSystem.apply(target, Enums.BuffType.GRANT_DEATHLESS, 1, step.source_tag)
					scene._refresh_slot_for(target)

		EffectStep.EffectType.GRANT_CRITICAL_STRIKE:
			var stacks := maxi(1, amount)
			for _i in stacks:
				BuffSystem.apply(target, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike")
			scene._refresh_slot_for(target)

		EffectStep.EffectType.GRANT_ON_DEATH_SUMMON:
			if target is MinionInstance:
				target.granted_on_death_effects.append({
					"description": "ON DEATH: Summon a %s." % step.card_id,
					"source": "sovereigns_edict",
					"summon_id": step.card_id,
				})
				scene._refresh_slot_for(target)

		EffectStep.EffectType.PURGE:
			if step.purge_filter.is_empty():
				BuffSystem.purge_all(target)
			else:
				BuffSystem.remove_type(target, Enums.BuffType[step.purge_filter])
			scene._refresh_slot_for(target)

		EffectStep.EffectType.DESTROY:
			if target is TrapCardData:
				if target.is_rune:
					scene._remove_rune_aura(target)
				scene.active_traps.erase(target)
				scene._update_trap_display()
			elif target is EnvironmentCardData:
				scene._unregister_env_rituals()
				scene.active_environment = null
				scene._update_environment_display()

# ---------------------------------------------------------------------------
# Amount resolution
# ---------------------------------------------------------------------------

static func _amount(step: EffectStep, ctx: EffectContext) -> int:
	var base: int
	match step.multiplier_key:
		"rune_aura":  base = step.amount * ctx.scene._rune_aura_multiplier()
		"void_marks": base = step.amount * ctx.scene.enemy_void_marks
		"board_count":
			var board: Array = ctx.scene._friendly_board(ctx.owner) \
				if step.multiplier_board == "friendly" \
				else ctx.scene._opponent_board(ctx.owner)
			var count := 0
			for m in board:
				if step.exclude_self and m == ctx.source:
					continue
				match step.multiplier_filter:
					"tag":
						if not ctx.scene._minion_has_tag(m, step.multiplier_tag):
							continue
					"race":
						if _race_from_string(step.multiplier_tag) != m.card_data.minion_type:
							continue
				count += 1
			base = step.amount * count
		_: base = step.amount
	# Add conditional bonus if all bonus_conditions pass (board-state check, not per-target)
	if step.bonus_amount != 0 and not step.bonus_conditions.is_empty():
		if ConditionResolver.check_all(step.bonus_conditions, ctx, null):
			base += step.bonus_amount
	return base

static func _race_from_string(name: String) -> int:
	match name:
		"demon":  return Enums.MinionType.DEMON
		"human":  return Enums.MinionType.HUMAN
		"spirit": return Enums.MinionType.SPIRIT
		"beast":  return Enums.MinionType.BEAST
	return -1

## Apply dark_channeling spell damage multiplier (enemy-only, flag set by handler).
static func _dark_channeling_dmg(base: int, ctx: EffectContext) -> int:
	if ctx.owner != "enemy":
		return base
	if ctx.scene.get("_dark_channeling_active") != true:
		return base
	var mult: float = ctx.scene.get("_dark_channeling_multiplier")
	if mult == null:
		mult = 1.5
	return int(base * mult)
