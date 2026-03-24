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
func _get_hand()           -> Array[CardData]:        return sim.player_hand
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

# ---------------------------------------------------------------------------
# Actions — instant (no timers)
# ---------------------------------------------------------------------------

func commit_play_minion(mc: MinionCardData, slot: BoardSlot, chosen_target = null) -> bool:
	var instance := MinionInstance.create(mc, "player")
	sim.player_board.append(instance)
	slot.place_minion(instance)
	sim.player_hand.erase(mc)
	sim.player_discard.append(mc)
	_resolve_on_play(mc, instance, chosen_target)
	if sim.trigger_manager != null:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
		ctx.minion = instance
		ctx.card   = mc
		sim.trigger_manager.fire(ctx)
	return sim.winner.is_empty()

func commit_play_spell(spell: SpellCardData, chosen_target = null) -> bool:
	sim.player_hand.erase(spell)
	sim.player_discard.append(spell)
	_resolve_spell(spell, chosen_target)
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
