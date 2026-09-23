## SimEnemyAgent.gd
## CombatAgent for the enemy side in a headless simulation.
## No timers — all commits resolve instantly. Reads and writes the enemy side of
## the CombatState directly (plan 1.3); rules code no longer reaches through it.
class_name SimEnemyAgent
extends CombatAgent

var sim: SimState

func setup(s: SimState) -> void:
	sim = s
	sim.enemy_ai = self

# ---------------------------------------------------------------------------
# Boards / hand / resources
# ---------------------------------------------------------------------------

func _get_friendly_board() -> Array[MinionInstance]: return sim.enemy_board
func _get_opponent_board() -> Array[MinionInstance]: return sim.player_board
func _get_hand()           -> Array[CardInstance]:     return sim.enemy_hand
func _get_essence()        -> int: return sim.enemy_essence
func _set_essence(v: int)  -> void: sim.enemy_essence = v
func _get_mana()           -> int: return sim.enemy_mana
func _set_mana(v: int)     -> void: sim.enemy_mana = v
func _get_scene()          -> Object: return sim

func _get_friendly_hp() -> int: return sim.enemy_hp
func _get_opponent_hp() -> int: return sim.player_hp

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func is_alive() -> bool:
	return sim.winner.is_empty()

# ---------------------------------------------------------------------------
# Board slots
# ---------------------------------------------------------------------------

func find_empty_slot() -> BoardSlot:
	for slot in sim.enemy_slots:
		if slot.is_empty():
			return slot
	return null

func empty_slot_count() -> int:
	var count := 0
	for slot in sim.enemy_slots:
		if slot.is_empty():
			count += 1
	return count

# ---------------------------------------------------------------------------
# Actions — instant (no timers)
# ---------------------------------------------------------------------------

func commit_play_minion(inst: CardInstance, slot: BoardSlot, chosen_target = null) -> bool:
	var mc := inst.card_data as MinionCardData
	var instance := MinionInstance.create(mc, "enemy")
	instance.card_instance = inst
	sim.enemy_board.append(instance)
	slot.place_minion(instance)
	sim.minion_summoned.emit("enemy", instance, slot.index)
	sim.remove_from_hand("enemy", inst)
	# Track per-fight big-body plays
	if mc.id == "bastion_colossus":
		sim._vw_bastion_plays += 1
	elif mc.id == "void_behemoth":
		sim._vw_behemoth_plays += 1
	# Set target so on_enemy_minion_played_effect (always-on handler) can read it.
	sim.enemy_play_target = chosen_target
	if sim.trigger_manager != null:
		# ON_ENEMY_MINION_PLAYED — gates on-play battlecries to hand plays only
		# (mirrors player side; token summons via _summon_token must not retrigger).
		var played_ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_MINION_PLAYED, "enemy")
		played_ctx.minion = instance
		played_ctx.card   = mc
		sim.trigger_manager.fire(played_ctx)
		if not sim.winner.is_empty(): return false
		# ON_ENEMY_MINION_SUMMONED — board synergies / passive buffs / trap routing
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "enemy")
		ctx.minion = instance
		ctx.card   = mc
		sim.trigger_manager.fire(ctx)
	else:
		_resolve_on_play(mc, instance, chosen_target)
	return sim.winner.is_empty()

func commit_play_spell(inst: CardInstance, chosen_target = null, extra_cast_data: Dictionary = {}) -> bool:
	var spell := inst.card_data as SpellCardData
	sim.remove_from_hand("enemy", inst)
	# Phase Disruptor counter: player counters enemy spell
	if sim._enemy_spell_counter > 0:
		sim._enemy_spell_counter -= 1
		return sim.winner.is_empty()
	# Fire ON_ENEMY_SPELL_CAST before resolving (matches CombatScene behavior)
	if sim.trigger_manager:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "enemy")
		ctx.card = spell
		sim.trigger_manager.fire(ctx)
	_resolve_spell(spell, chosen_target, extra_cast_data)
	return sim.winner.is_empty()

func commit_play_trap(inst: CardInstance) -> bool:
	var trap := inst.card_data as TrapCardData
	sim.remove_from_hand("enemy", inst)
	sim.enemy_active_traps.append(trap)
	# Fire ON_ENEMY_TRAP_PLACED
	if sim.trigger_manager != null:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_TRAP_PLACED, "enemy")
		ctx.card = trap
		sim.trigger_manager.fire(ctx)
	# Runes: register aura handlers with mirrored triggers
	if trap.is_rune and sim.trigger_manager != null:
		sim._apply_rune_aura(trap, "enemy")
	return sim.winner.is_empty()

func commit_play_environment(inst: CardInstance) -> bool:
	var env := inst.card_data as EnvironmentCardData
	sim.remove_from_hand("enemy", inst)
	# Tear down outgoing env's persistent aura with owner="enemy" (mirror of
	# SimPlayerAgent.commit_play_environment for the player side).
	var prev_env: EnvironmentCardData = sim.enemy_active_environment
	if prev_env != null and not prev_env.on_replace_effect_steps.is_empty():
		EffectResolver.run(prev_env.on_replace_effect_steps, EffectContext.make(sim, "enemy"))
	sim.enemy_active_environment = env
	if not env.on_enter_effect_steps.is_empty():
		EffectResolver.run(env.on_enter_effect_steps, EffectContext.make(sim, "enemy"))
	if not env.passive_effect_steps.is_empty():
		EffectResolver.run(env.passive_effect_steps, EffectContext.make(sim, "enemy"))
	return sim.winner.is_empty()

func do_attack_minion(attacker: MinionInstance, target: MinionInstance) -> bool:
	if not sim.enemy_board.has(attacker):
		return false
	# Fire ON_ENEMY_ATTACK before resolving (matches CombatScene behavior)
	if sim.trigger_manager:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_ATTACK, "enemy")
		ctx.minion = attacker
		sim.trigger_manager.fire(ctx)
	# Check if a trap (e.g. Smoke Veil) cancelled this attack
	if sim.attack_cancelled:
		sim.attack_cancelled = false
		return sim.winner.is_empty()
	sim.combat_manager.resolve_minion_attack(attacker, target)
	return sim.winner.is_empty()

func do_attack_hero(attacker: MinionInstance) -> bool:
	if not sim.enemy_board.has(attacker):
		return false
	# Fire ON_ENEMY_ATTACK before resolving (matches CombatScene behavior)
	if sim.trigger_manager:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_ATTACK, "enemy")
		ctx.minion = attacker
		sim.trigger_manager.fire(ctx)
	# Check if a trap (e.g. Smoke Veil) cancelled this attack
	if sim.attack_cancelled:
		sim.attack_cancelled = false
		return sim.winner.is_empty()
	sim.combat_manager.resolve_minion_attack_hero(attacker, "player")
	return sim.winner.is_empty()

func consume_minion(minion: MinionInstance) -> void:
	var spark_val: int = minion.effective_spark_value(sim)
	# Track if Behemoth or Bastion is being consumed (should never happen by design)
	if minion.card_data.id == "void_behemoth":
		sim._vw_behemoth_lost["consumed"] += 1
	elif minion.card_data.id == "bastion_colossus":
		sim._vw_bastion_lost["consumed"] += 1
	sim.enemy_board.erase(minion)
	for slot in sim.enemy_slots:
		if slot.minion == minion:
			slot.minion = null
			break
	# Fire spark consumed event for passives (void_detonation, champion_vw, etc.)
	# Use effective value so spirit_resonance-boosted Spirits still fire.
	if spark_val > 0 and sim.trigger_manager:
		var event := Enums.TriggerEvent.ON_ENEMY_SPARK_CONSUMED if minion.owner == "enemy" \
			else Enums.TriggerEvent.ON_PLAYER_SPARK_CONSUMED
		var ctx := EventContext.make(event, minion.owner)
		ctx.minion = minion
		ctx.damage = spark_val
		sim.trigger_manager.fire(ctx)

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func _essence_cost_discounts() -> Dictionary:
	return sim.enemy_essence_cost_discounts

func _minion_essence_cost_aura() -> int:
	return sim.enemy_minion_essence_cost_aura

func effective_spell_cost(spell: SpellCardData) -> int:
	return max(0, spell.cost + sim.enemy_spell_cost_penalty + sim.enemy_spell_cost_aura \
		- (sim.enemy_spell_cost_discounts.get(spell.id, 0) as int))

func opponent_has_rune_or_environment() -> bool:
	if sim.active_environment != null:
		return true
	for trap in sim.active_traps:
		if (trap as TrapCardData).is_rune:
			return true
	return false

func draw_cards(count: int) -> void:
	sim.draw_cards("enemy", count)

# ---------------------------------------------------------------------------
# Effect resolution helpers
# ---------------------------------------------------------------------------

func _resolve_on_play(mc: MinionCardData, instance: MinionInstance, chosen_target) -> void:
	if mc.on_play_effect_steps.is_empty():
		return
	var ctx := _make_ctx("enemy", instance, chosen_target)
	EffectResolver.run(mc.on_play_effect_steps, ctx)

func _resolve_spell(spell: SpellCardData, chosen_target, extra_cast_data: Dictionary = {}) -> void:
	var ctx := _make_ctx("enemy", null, chosen_target, extra_cast_data)
	ctx.source_card_id = spell.id
	EffectResolver.run(spell.effect_steps, ctx)

func _make_ctx(owner: String, source: MinionInstance, chosen_target, extra_cast_data: Dictionary = {}) -> EffectContext:
	var ctx        := EffectContext.new()
	ctx.scene       = sim
	ctx.owner       = owner
	ctx.source      = source
	if chosen_target is MinionInstance:
		ctx.chosen_target = chosen_target
	else:
		ctx.chosen_object = chosen_target
	ctx.extra_cast_data = extra_cast_data
	return ctx
