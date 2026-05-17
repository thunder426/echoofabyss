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
	# Reset per-run state so chained reads (flesh, last-added card) only see this run's writes.
	ctx.flesh_spent_this_cast = 0
	ctx.last_added_instance = null
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
				# Korrath B3 T2 Path of Corruption — symmetric with DAMAGE_MINION:
				# amplify by per-stack corruption on the targeted hero, then apply
				# 1 Corruption stack post-damage. The string sentinel matches the
				# DAMAGE_MINION enemy_hero branch's contract.
				var hero_target: String = "%s_hero" % opponent
				dmg = _path_of_corruption_amplify(dmg, hero_target, ctx, step.damage_school)
				var info := _build_damage_info(step, ctx, dmg)
				ctx.scene.combat_manager.apply_hero_damage(opponent, info)
				_path_of_corruption_apply_corruption(hero_target, ctx)
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
				# _card_for so clan rules / overrides apply to the added copy.
				var card: CardData = ctx.scene._card_for(ctx.owner, step.card_id)
				if card:
					# Build the CardInstance up-front so we can stash it on ctx.
					# _add_to_owner_hand silently burns when the hand is full; in that
					# case the instance still exists but isn't in any hand — downstream
					# MOD_LAST_ADDED_COST etc. will operate on a detached object harmlessly.
					var inst: CardInstance = CardInstance.create(card)
					ctx.scene._add_to_owner_hand(ctx.owner, inst)
					ctx.last_added_instance = inst
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
					ctx.scene.last_player_growth = "mana"
				else:
					# Real combat: enemy_ai owns the caps. Sim: scene (SimState) owns them.
					var ai = ctx.scene.enemy_ai
					if ai != null and ai.get("mana_max") != null and ai.get("COMBINED_RESOURCE_CAP") != null:
						for _i in amt:
							if ai.essence_max + ai.mana_max >= ai.COMBINED_RESOURCE_CAP:
								break
							ai.mana_max += 1
					else:
						for _i in amt:
							if ctx.scene.enemy_essence_max + ctx.scene.enemy_mana_max >= 11:
								break
							ctx.scene.enemy_mana_max += 1
			return

		EffectStep.EffectType.VOID_MARK:
			if ConditionResolver.check_all(step.conditions, ctx, null) and ctx.owner == "player":
				ctx.scene._apply_void_mark(step.amount)
			return

		EffectStep.EffectType.VOID_BOLT:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var dmg := _amount(step, ctx)
				# Same source rule as _build_damage_info: ctx.source non-null means a
				# minion is emitting (e.g. void_imp_wizard on-play). Null = spell card.
				var is_min_emitted: bool = ctx.source != null
				if ctx.owner == "player":
					ctx.scene._deal_void_bolt_damage(dmg, ctx.source, ctx.from_rune, is_min_emitted)
				else:
					ctx.scene._deal_enemy_void_bolt_damage(dmg, ctx.source, is_min_emitted)
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
						# Stash for chained steps (e.g. MOD_LAST_ADDED_COST). When TUTOR
						# pulls multiple cards (count > 1), the LAST one tutored wins.
						ctx.last_added_instance = inst
						found += 1
					else:
						i += 1
			return

		EffectStep.EffectType.MOD_LAST_ADDED_COST:
			# Adjust the cost delta on the CardInstance most recently added to a hand
			# in this run (TUTOR or ADD_CARD). step.amount is the delta — negative
			# means cheaper. step.resource picks the axis: "mana" → mana_delta,
			# "essence" → essence_delta. Silent no-op if no prior step added a card
			# (TUTOR legitimately no-ops when the deck has no matching cards left,
			# e.g. rune_caller after all runes are tutored).
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var inst_to_mod: CardInstance = ctx.last_added_instance
				if inst_to_mod != null:
					match step.resource:
						"mana":
							inst_to_mod.mana_delta += step.amount
						"essence":
							inst_to_mod.essence_delta += step.amount
						_:
							push_warning("MOD_LAST_ADDED_COST: unknown or empty 'resource' '%s' (expected 'mana' or 'essence')" % step.resource)
					if ctx.scene.has_method("_refresh_hand_spell_costs"):
						ctx.scene._refresh_hand_spell_costs()
			return

		EffectStep.EffectType.MOD_HAND_CARDS_COST:
			# Adjust the cost delta on every CardInstance in the caster's hand matching
			# ALL set filters (card_id, card_tag, card_race — AND across populated ones;
			# empty fields = no filter on that axis). step.amount is signed (negative =
			# discount). step.resource picks the axis: "mana" → mana_delta, "essence" →
			# essence_delta. Cost floor (cards never below 0) is enforced at play time
			# by the cost-resolution code, not here — essence_delta is allowed to go
			# arbitrarily negative so multiple discounts stack cleanly.
			if not ConditionResolver.check_all(step.conditions, ctx, null):
				return
			if step.resource != "mana" and step.resource != "essence":
				push_warning("MOD_HAND_CARDS_COST: unknown or empty 'resource' '%s' (expected 'mana' or 'essence')" % step.resource)
				return
			if step.card_id == "" and step.card_tag == "" and step.card_race == "":
				push_warning("MOD_HAND_CARDS_COST: no filter set (card_id / card_tag / card_race all empty) — refusing to mutate every card in hand")
				return
			var race_id: int = -1
			if step.card_race != "":
				if not (step.card_race in Enums.MinionType):
					push_warning("MOD_HAND_CARDS_COST: unknown card_race '%s'" % step.card_race)
					return
				race_id = Enums.MinionType[step.card_race]
			var hand: Array = ctx.scene._friendly_hand(ctx.owner)
			for inst in hand:
				if inst == null or inst.card_data == null:
					continue
				if step.card_id != "" and inst.card_data.id != step.card_id:
					continue
				var mc := inst.card_data as MinionCardData
				if step.card_tag != "":
					if mc == null or not (step.card_tag in mc.minion_tags):
						continue
				if race_id >= 0:
					if mc == null or not mc.is_race(race_id):
						continue
				if step.resource == "mana":
					inst.mana_delta += step.amount
				else:
					inst.essence_delta += step.amount
			if ctx.scene.has_method("_refresh_hand_spell_costs"):
				ctx.scene._refresh_hand_spell_costs()
			return

		EffectStep.EffectType.COUNTER_SPELL:
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var opponent := "player" if ctx.owner == "enemy" else "enemy"
				var key := "_player_spell_counter" if opponent == "player" else "_enemy_spell_counter"
				var current: int = ctx.scene.get(key) if ctx.scene.get(key) != null else 0
				ctx.scene.set(key, current + 1)
			return

		EffectStep.EffectType.CANCEL_OPPONENT_SPELL:
			# Silence Trap — sets the flag the spell-cast pipeline checks to short-circuit
			# the in-flight opponent spell. There's a single global _spell_cancelled flag.
			if ConditionResolver.check_all(step.conditions, ctx, null):
				ctx.scene.set("_spell_cancelled", true)
			return

		EffectStep.EffectType.BLOCK_OPPONENT_TRAPS_THIS_TURN:
			# Saboteur Adept — gates the opponent's traps from firing for the rest of
			# this turn. Per-side flags exist on the scene; pick by who's the opponent.
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var opponent: String = ctx.scene._opponent_of(ctx.owner)
				if opponent == "enemy":
					ctx.scene.set("_enemy_traps_blocked", true)
				else:
					ctx.scene.set("_player_traps_blocked", true)
			return

		EffectStep.EffectType.TAX_OPPONENT_SPELLS_NEXT_TURN:
			# Spell Taxer — increments the opponent-side spell-tax counter. Each stack
			# adds +1 Mana to the opponent's spells on their next turn.
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var opponent: String = ctx.scene._opponent_of(ctx.owner)
				var tax_key: String = "_spell_tax_for_%s_turn" % opponent
				var cur = ctx.scene.get(tax_key)
				ctx.scene.set(tax_key, (cur if cur != null else 0) + 1)
			return

		EffectStep.EffectType.COPY_OWNER_RUNES_TO_HAND:
			# Runic Echo — copy every rune currently in the owner's active_traps into
			# the owner's hand. Each copy is a fresh CardInstance pointing at the same
			# TrapCardData; placing it later goes through the normal play pipeline.
			if ConditionResolver.check_all(step.conditions, ctx, null):
				for trap in (ctx.scene._friendly_traps(ctx.owner) as Array):
					if (trap as TrapCardData).is_rune:
						ctx.scene._add_to_owner_hand(ctx.owner, CardInstance.create(trap))
			return

		EffectStep.EffectType.PLACE_RUNE_ON_OPPONENT:
			# Voidshaped Acolyte — append a rune (step.card_id) to the OPPONENT's
			# active_traps and register its aura handlers on the opponent side. The
			# opponent owns the rune, so its aura triggers fire from the opponent's
			# perspective (corruption-on-summon hits minions entering the opponent's
			# board, etc.). _opponent_traps returns the live array (mutates state).
			if ConditionResolver.check_all(step.conditions, ctx, null):
				# Rune lands on the opponent's side — fetch via that side's overrides.
				var opponent: String = ctx.scene._opponent_of(ctx.owner)
				var rune_data: TrapCardData = ctx.scene._card_for(opponent, step.card_id) as TrapCardData
				if rune_data != null:
					var traps: Array = ctx.scene._opponent_traps(ctx.owner)
					traps.append(rune_data)
					ctx.scene._apply_rune_aura(rune_data, opponent)
					if ctx.scene.has_method("_update_trap_display_for"):
						ctx.scene._update_trap_display_for(opponent)
			return

		EffectStep.EffectType.QUEUE_OPPONENT_MANA_DRAIN_NEXT_TURN:
			# Void Rift Lord — drains the opponent's Mana to 0 at the start of their
			# next turn. Symmetric: caster's opponent gets the pending flag (player-side
			# field for the player, enemy-side field for the enemy), consumed at that
			# side's next turn start.
			if ConditionResolver.check_all(step.conditions, ctx, null):
				var opponent: String = ctx.scene._opponent_of(ctx.owner)
				if opponent == "player":
					ctx.scene.set("_void_mana_drain_pending", true)
				else:
					ctx.scene.set("_enemy_void_mana_drain_pending", true)
				if ctx.scene.get("_rift_lord_plays") != null:
					ctx.scene._rift_lord_plays += 1
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

		EffectStep.EffectType.GAIN_FLESH:
			# Seris — player-only. Enemy Seris is not supported.
			if ConditionResolver.check_all(step.conditions, ctx, null) and ctx.owner == "player":
				ctx.scene._gain_flesh(maxi(1, step.amount))
			return

		EffectStep.EffectType.SPEND_FLESH:
			# All-or-nothing. _spend_flesh returns false without deducting if short.
			if ConditionResolver.check_all(step.conditions, ctx, null) and ctx.owner == "player":
				var amt := maxi(1, step.amount)
				if ctx.scene._spend_flesh(amt):
					ctx.flesh_spent_this_cast += amt
			return

		EffectStep.EffectType.GAIN_FORGE_COUNTER:
			# Seris — player-only. Soul Forge gate is enforced inside _gain_forge_counter.
			if ConditionResolver.check_all(step.conditions, ctx, null) and ctx.owner == "player":
				ctx.scene._gain_forge_counter(maxi(1, step.amount))
			return

		EffectStep.EffectType.COPY_LAST_TURN_SPELLS_FROM_GRAVEYARD:
			# Seris — Recursive Hex. Copy each spell the caster cast last turn into hand
			# (excluding step.exclude_card_id). Then deal step.amount damage to opponent
			# hero per spell COPIED (count is taken from the graveyard query, not the hand-
			# add result, so hand-cap burns do not reduce the damage).
			if ConditionResolver.check_all(step.conditions, ctx, null):
				# The casting card is the most recent graveyard entry — its resolved_on_turn
				# is the current turn. "Last turn" = current_turn - 1.
				var graveyard: Array = ctx.scene._friendly_graveyard(ctx.owner)
				if graveyard.is_empty():
					return
				var current_turn: int = (graveyard[graveyard.size() - 1] as CardInstance).resolved_on_turn
				var target_turn := current_turn - 1
				if target_turn < 1:
					return  # Turn 1 cast: no prior turn to copy from. (Recursive Hex costs 5M, also impossible.)
				var copied: Array[String] = []
				for entry in graveyard:
					var inst: CardInstance = entry
					if inst.resolved_on_turn != target_turn:
						continue
					if not (inst.card_data is SpellCardData):
						continue
					if step.exclude_card_id != "" and inst.card_data.id == step.exclude_card_id:
						continue
					# Add a fresh copy (new instance_id) — base cost, not modified.
					if ctx.owner == "player":
						ctx.scene.turn_manager.add_to_hand(inst.card_data)
					else:
						ctx.scene.enemy_ai.add_to_hand(inst.card_data)
					copied.append(inst.card_data.card_name)
				# Per-copy hero damage — count uses graveyard query result, not hand-add success.
				if not copied.is_empty():
					var dmg := step.amount * copied.size()
					var opponent := "enemy" if ctx.owner == "player" else "player"
					var info := _build_damage_info(step, ctx, dmg)
					ctx.scene.combat_manager.apply_hero_damage(opponent, info)
			return

		EffectStep.EffectType.SPEND_FLESH_UP_TO:
			# Partial allowed — spend min(current, amount). Never fails; may spend 0.
			if ConditionResolver.check_all(step.conditions, ctx, null) and ctx.owner == "player":
				var cap := maxi(1, step.amount)
				var cur: int = ctx.scene.player_flesh if ctx.scene.get("player_flesh") != null else 0
				var to_spend := mini(cap, cur)
				if to_spend > 0 and ctx.scene._spend_flesh(to_spend):
					ctx.flesh_spent_this_cast += to_spend
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
			# Self-destruct the rune that owns this aura (Flesh Rune upkeep failure).
			if step.scope == EffectStep.TargetScope.SOURCE_RUNE:
				if ConditionResolver.check_all(step.conditions, ctx, null):
					var r: TrapCardData = ctx.source_rune
					if r != null and r in ctx.scene.active_traps:
						if r.is_rune:
							ctx.scene._remove_rune_aura(r, ctx.owner)
						ctx.scene.active_traps.erase(r)
						ctx.scene._update_trap_display()
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
			var dmg: int = _dark_channeling_dmg(amount, ctx)
			if target is String and target == "enemy_hero":
				# Hero-target branch (e.g. void_devourer, AOE that hits hero).
				# Korrath B3 T2 Path of Corruption amplifier and post-application
				# also fire here so the talent reads symmetric with the minion path.
				dmg = _path_of_corruption_amplify(dmg, target, ctx, step.damage_school)
				var info := _build_damage_info(step, ctx, dmg)
				scene.combat_manager.apply_hero_damage(scene._opponent_of(ctx.owner), info)
				_path_of_corruption_apply_corruption(target, ctx)
			else:
				# Korrath B3 T2 Path of Corruption — pre-damage amplification (read
				# corruption stacks BEFORE we apply our own) + post-damage corruption
				# application. Per-target, per-step, so AOE spells naturally hit each
				# target once and single-target spells get +100 / stack on this hit.
				dmg = _path_of_corruption_amplify(dmg, target, ctx, step.damage_school)
				scene._spell_dmg(target, dmg, _build_damage_info(step, ctx, dmg))
				_path_of_corruption_apply_corruption(target, ctx)

		EffectStep.EffectType.BUFF_ATK:
			var buff_type := Enums.BuffType.ATK_BONUS if step.permanent else Enums.BuffType.TEMP_ATK
			var tag_atk: String = step.source_tag if step.source_tag != "" else ctx.source_card_id
			# Defer state mutation to BuffApplyVFX's chevron beat in live combat
			# so the visible value tween, chevron, and state mutation all align.
			# Sim has no VFX → mutate immediately as before.
			# Presence-aura recompute sets _silent_buff_apply to skip the VFX queue
			# entirely; the caller spawns its own cosmetic VFX only on real deltas.
			var _sv = scene.get("_silent_buff_apply")
			var silent: bool = _sv if _sv is bool else false
			if scene.has_method("_request_buff_apply") and scene.vfx_controller != null and not silent:
				scene._request_buff_apply(target, buff_type, amount, tag_atk, false)
			else:
				BuffSystem.apply(target, buff_type, amount, tag_atk, false, not silent)
				scene._refresh_slot_for(target)

		EffectStep.EffectType.BUFF_HP:
			var tag_hp: String = step.source_tag if step.source_tag != "" else ctx.source_card_id
			var _sv_hp = scene.get("_silent_buff_apply")
			var silent_hp: bool = _sv_hp if _sv_hp is bool else false
			if scene.has_method("_request_buff_apply") and scene.vfx_controller != null and not silent_hp:
				scene._request_buff_apply(target, Enums.BuffType.HP_BONUS, amount, tag_hp, true)
			else:
				BuffSystem.apply_hp_gain(target, amount, tag_hp, not silent_hp)
				scene._refresh_slot_for(target)

		EffectStep.EffectType.BUFF_ARMOUR:
			# Korrath — armour is a stat on MinionInstance, not a BuffSystem entry.
			# Route through add_armour() so Branch 1 T3 Unbreakable's "all armour
			# gains on the knight are doubled" check stays in one place.
			if target is MinionInstance:
				(target as MinionInstance).add_armour(amount, scene)
				scene._refresh_slot_for(target)

		EffectStep.EffectType.HEAL_MINION:
			if target is MinionInstance:
				scene._heal_minion(target, amount)

		EffectStep.EffectType.HEAL_MINION_FULL:
			if target is MinionInstance:
				scene._heal_minion_full(target)

		EffectStep.EffectType.GRANT_KILL_STACKS:
			if target is MinionInstance:
				scene._add_kill_stacks(target, maxi(1, amount))

		EffectStep.EffectType.CORRUPTION:
			var stacks := maxi(1, amount)
			for _i in stacks:
				scene._corrupt_minion(target)

		EffectStep.EffectType.SACRIFICE:
			# SacrificeSystem.sacrifice handles the full flow — ON LEAVE steps,
			# ON_*_MINION_SACRIFICED trigger, corruption removal, silent board cleanup.
			# Strict rule: sacrifice is NOT death — does not fire ON_*_MINION_DIED.
			SacrificeSystem.sacrifice(scene, target, ctx.source_card_id)

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
				# Locate the trap on whichever side actually owns it. Caller-side
				# (player traps) is the common case; opponent-side covers
				# SINGLE_RANDOM_OPPONENT_TRAP and any future cross-side destroys.
				var owner_side: String = ctx.owner
				if not target in scene._friendly_traps(owner_side):
					owner_side = scene._opponent_of(ctx.owner)
				if target.is_rune:
					scene._remove_rune_aura(target, owner_side)
				scene._friendly_traps(owner_side).erase(target)
				if scene.has_method("_update_trap_display_for"):
					scene._update_trap_display_for(owner_side)
				else:
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
		"flesh_spent": base = step.amount * ctx.flesh_spent_this_cast
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
	# base_amount is a flat addend that lets a single step express "X + Y per Z"
	# (see EffectStep.base_amount). Defaults to 0 so existing call sites are unchanged.
	return step.base_amount + base

static func _race_from_string(name: String) -> int:
	match name:
		"demon":  return Enums.MinionType.DEMON
		"human":  return Enums.MinionType.HUMAN
		"spirit": return Enums.MinionType.SPIRIT
		"beast":  return Enums.MinionType.BEAST
	return -1

## Build a DamageInfo for a damage-dealing EffectStep emission.
## Source is inferred: ctx.source != null → MINION (minion-emitted effect),
##                     ctx.source == null → SPELL (spell card, trap, environment, DoT).
## School comes from step.damage_school. Faction/talent overrides happen in Phase 4.
## See design/DAMAGE_TYPE_SYSTEM.md.
static func _build_damage_info(step: EffectStep, ctx: EffectContext, amount: int) -> Dictionary:
	var source: Enums.DamageSource = Enums.DamageSource.MINION if ctx.source != null else Enums.DamageSource.SPELL
	return CombatManager.make_damage_info(amount, source, step.damage_school, ctx.source, ctx.source_card_id)

## Korrath B3 T2 Path of Corruption — pre-damage amplification half. Player-side only.
## Reads the target's current CORRUPTION buff stack count and adds 100 damage per
## stack to the spell hit. Reads BEFORE the talent's own corruption application so a
## newly-corrupted target doesn't double-amplify on the same hit.
## Target may be a MinionInstance or the "enemy_hero" / "player_hero" string sentinel
## used by hero-targeted spell paths (DAMAGE_HERO / DAMAGE_MINION enemy_hero / VOID_BOLT).
## `school` is the damage step's damage_school — the amp only fires when the school
## satisfies VOID_CORRUPTION (corruption-flavored spells), so neutral/PHYSICAL/VOID_BOLT
## spells are unaffected even when the talent is active.
static func _path_of_corruption_amplify(base: int, target, ctx: EffectContext, school: int = Enums.DamageSchool.VOID_CORRUPTION) -> int:
	if ctx.owner != "player":
		return base
	if ctx.scene == null or ctx.scene.get("_path_of_corruption_active") != true:
		return base
	if not Enums.has_school(school, Enums.DamageSchool.VOID_CORRUPTION):
		return base
	var buff_holder: Object = null
	if target is MinionInstance:
		buff_holder = target
	elif target is String:
		var state: CombatState = ctx.scene.state if ctx.scene.get("state") != null else ctx.scene
		if target == "enemy_hero":
			buff_holder = state.enemy_hero
		elif target == "player_hero":
			buff_holder = state.player_hero
	if buff_holder == null:
		return base
	# count_type, not sum_type — Corruption entries store the per-stack ATK penalty
	# as `amount` (100 base, 200 w/ talent). We want stack COUNT.
	var stacks: int = BuffSystem.count_type(buff_holder, Enums.BuffType.CORRUPTION)
	return base + stacks * 100

## Korrath B3 T2 Path of Corruption — post-damage corruption application half.
## Adds 1 Corruption stack to the target after the spell hit lands. Skipped when
## the minion target died from the hit so we don't corrupt a vanishing minion.
## Hero targets always receive the stack (no death-snapshot ambiguity).
static func _path_of_corruption_apply_corruption(target, ctx: EffectContext) -> void:
	if ctx.owner != "player":
		return
	if ctx.scene == null or ctx.scene.get("_path_of_corruption_active") != true:
		return
	if target is MinionInstance:
		var m: MinionInstance = target
		if m.current_health <= 0:
			return
		ctx.scene._corrupt_minion(m)
	elif target is String:
		var state: CombatState = ctx.scene.state if ctx.scene.get("state") != null else ctx.scene
		if target == "enemy_hero":
			state._corrupt_hero("enemy")
		elif target == "player_hero":
			state._corrupt_hero("player")

## Apply dark_channeling spell damage multiplier (enemy-only, flag set by handler).
static func _dark_channeling_dmg(base: int, ctx: EffectContext) -> int:
	if ctx.owner != "enemy":
		return base
	if ctx.scene.get("_dark_channeling_active") != true:
		return base
	var mult: float = ctx.scene.get("_dark_channeling_multiplier")
	if mult == null:
		mult = 1.5
	var amplified: int = int(base * mult)
	# Telemetry: track extra damage dealt by dark_channeling per spell id.
	var extra: int = amplified - base
	if extra > 0 and ctx.source_card_id != "":
		var dmg_map: Dictionary = ctx.scene.get("_dark_channeling_dmg_by_spell")
		if dmg_map != null:
			dmg_map[ctx.source_card_id] = int(dmg_map.get(ctx.source_card_id, 0)) + extra
	return amplified
