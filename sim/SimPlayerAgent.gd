## SimPlayerAgent.gd
## CombatAgent for the player side in a headless simulation.
## No timers — all commits resolve instantly.
class_name SimPlayerAgent
extends CombatAgent

var sim: SimState

func setup(s: SimState) -> void:
	sim = s

# ---------------------------------------------------------------------------
# Boards / hand / resources
# ---------------------------------------------------------------------------

func _get_friendly_board() -> Array[MinionInstance]: return sim.player_board
func _get_opponent_board() -> Array[MinionInstance]: return sim.enemy_board
func _get_hand()           -> Array[CardInstance]:     return sim.player_hand
func _get_essence()        -> int: return sim.player_essence
func _set_essence(v: int)  -> void: sim.player_essence = v
func _get_mana()           -> int: return sim.player_mana
func _set_mana(v: int)     -> void: sim.player_mana = v
func _get_scene()          -> Object: return sim

func _get_friendly_hp() -> int: return sim.player_hp
func _get_opponent_hp() -> int: return sim.enemy_hp

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func is_alive() -> bool:
	return sim.winner.is_empty()

# ---------------------------------------------------------------------------
# Board slots
# ---------------------------------------------------------------------------

func find_empty_slot() -> BoardSlot:
	for slot in sim.player_slots:
		if slot.is_empty():
			return slot
	return null

func empty_slot_count() -> int:
	var count := 0
	for slot in sim.player_slots:
		if slot.is_empty():
			count += 1
	return count

# ---------------------------------------------------------------------------
# Actions — instant (no timers)
# ---------------------------------------------------------------------------

func commit_play_minion(inst: CardInstance, slot: BoardSlot, chosen_target = null) -> bool:
	var mc := inst.card_data as MinionCardData
	var instance := MinionInstance.create(mc, "player")
	instance.card_instance = inst
	sim.player_board.append(instance)
	slot.place_minion(instance)
	sim.player_hand.erase(inst)
	sim.player_discard.append(inst)
	if sim.trigger_manager != null:
		# ON_PLAYER_MINION_PLAYED — triggers on-play effects and rune_caller
		var played_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, "player")
		played_ctx.minion = instance
		played_ctx.card   = mc
		if chosen_target is MinionInstance:
			played_ctx.target = chosen_target
		sim.trigger_manager.fire(played_ctx)
		if not sim.winner.is_empty(): return false
		# ON_PLAYER_MINION_SUMMONED — triggers board synergies and passive buffs
		var summon_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
		summon_ctx.minion = instance
		summon_ctx.card   = mc
		sim.trigger_manager.fire(summon_ctx)
	else:
		_resolve_on_play(mc, instance, chosen_target)
	return sim.winner.is_empty()

func commit_play_spell(inst: CardInstance, chosen_target = null) -> bool:
	var spell := inst.card_data as SpellCardData
	sim.player_hand.erase(inst)
	sim.player_discard.append(inst)
	_resolve_spell(spell, chosen_target)
	return sim.winner.is_empty()

func commit_play_trap(inst: CardInstance) -> bool:
	var trap := inst.card_data as TrapCardData
	sim.player_hand.erase(inst)
	sim.player_discard.append(inst)
	sim.active_traps.append(trap)
	# Fire ON_PLAYER_TRAP_PLACED
	if sim.trigger_manager != null:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_TRAP_PLACED, "player")
		ctx.card = trap
		sim.trigger_manager.fire(ctx)
	# Runes: register aura handlers and fire ON_RUNE_PLACED for ritual checks
	if trap.is_rune and sim.trigger_manager != null:
		sim._apply_rune_aura(trap)
		var rune_ctx := EventContext.make(Enums.TriggerEvent.ON_RUNE_PLACED, "player")
		rune_ctx.card = trap
		sim.trigger_manager.fire(rune_ctx)
	return sim.winner.is_empty()

func commit_play_environment(inst: CardInstance) -> bool:
	var env := inst.card_data as EnvironmentCardData
	sim.player_hand.erase(inst)
	sim.player_discard.append(inst)
	# Tear down previous environment before replacing
	if sim.active_environment != null and sim.trigger_manager != null:
		sim._unregister_env_rituals()
		sim._unregister_env_aura(sim.active_environment)
	sim.active_environment = env
	if sim.trigger_manager != null:
		sim._register_env_rituals(env)
		# Fire ON_RITUAL_ENVIRONMENT_PLAYED for ritual checks
		if not env.rituals.is_empty():
			var env_ctx := EventContext.make(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, "player")
			env_ctx.card = env
			sim.trigger_manager.fire(env_ctx)
	# Run on-enter and immediate passive effects
	if not env.on_enter_effect_steps.is_empty():
		EffectResolver.run(env.on_enter_effect_steps, EffectContext.make(sim, "player"))
	if not env.passive_effect_steps.is_empty():
		EffectResolver.run(env.passive_effect_steps, EffectContext.make(sim, "player"))
	return sim.winner.is_empty()

func do_attack_minion(attacker: MinionInstance, target: MinionInstance) -> bool:
	if not sim.player_board.has(attacker):
		return false
	sim.combat_manager.resolve_minion_attack(attacker, target)
	return sim.winner.is_empty()

func do_attack_hero(attacker: MinionInstance) -> bool:
	if not sim.player_board.has(attacker):
		return false
	sim.combat_manager.resolve_minion_attack_hero(attacker, "enemy")
	return sim.winner.is_empty()

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func opponent_has_rune_or_environment() -> bool:
	if sim.active_environment != null:
		return true
	for trap in sim.active_traps:
		if (trap as TrapCardData).is_rune:
			return true
	return false

# ---------------------------------------------------------------------------
# Effect resolution helpers
# ---------------------------------------------------------------------------

func _resolve_on_play(mc: MinionCardData, instance: MinionInstance, chosen_target) -> void:
	if mc.on_play_effect_steps.is_empty():
		return
	var ctx := _make_ctx("player", instance, chosen_target)
	EffectResolver.run(mc.on_play_effect_steps, ctx)

func _resolve_spell(spell: SpellCardData, chosen_target) -> void:
	var ctx := _make_ctx("player", null, chosen_target)
	EffectResolver.run(spell.effect_steps, ctx)

func _make_ctx(owner: String, source: MinionInstance, chosen_target) -> EffectContext:
	var ctx        := EffectContext.new()
	ctx.scene       = sim
	ctx.owner       = owner
	ctx.source      = source
	if chosen_target is MinionInstance:
		ctx.chosen_target = chosen_target
	else:
		ctx.chosen_object = chosen_target
	return ctx
