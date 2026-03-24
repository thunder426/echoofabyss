## SimEnemyAgent.gd
## CombatAgent for the enemy side in a headless simulation.
## No timers — all commits resolve instantly.
##
## Also duck-types as EnemyAI for EffectResolver calls like
##   ctx.scene.enemy_ai._draw_cards(count)
##   ctx.scene.enemy_ai.add_to_hand(card)
##   ctx.scene.enemy_ai.mana / mana_max / essence / essence_max
class_name SimEnemyAgent
extends CombatAgent

var sim: SimState

func setup(s: SimState) -> void:
	sim = s
	sim.enemy_ai = self  # register as the scene's enemy_ai duck-type

# ---------------------------------------------------------------------------
# Boards / hand / resources
# ---------------------------------------------------------------------------

func _get_friendly_board() -> Array[MinionInstance]: return sim.enemy_board
func _get_opponent_board() -> Array[MinionInstance]: return sim.player_board
func _get_hand()           -> Array[CardData]:        return sim.enemy_hand
func _get_essence()        -> int: return sim.enemy_essence
func _set_essence(v: int)  -> void: sim.enemy_essence = v
func _get_mana()           -> int: return sim.enemy_mana
func _set_mana(v: int)     -> void: sim.enemy_mana = v
func _get_scene()          -> Object: return sim

func _get_friendly_hp() -> int: return sim.enemy_hp
func _get_opponent_hp() -> int: return sim.player_hp

# ---------------------------------------------------------------------------
# EnemyAI duck-type properties (read by EffectResolver)
# ---------------------------------------------------------------------------

var mana_max: int:
	get: return sim.enemy_mana_max
var essence_max: int:
	get: return sim.enemy_essence_max

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

# ---------------------------------------------------------------------------
# Actions — instant (no timers)
# ---------------------------------------------------------------------------

func commit_play_minion(mc: MinionCardData, slot: BoardSlot, chosen_target = null) -> bool:
	var instance := MinionInstance.create(mc, "enemy")
	sim.enemy_board.append(instance)
	slot.place_minion(instance)
	sim.enemy_hand.erase(mc)
	sim.enemy_discard.append(mc)
	_resolve_on_play(mc, instance, chosen_target)
	if sim.trigger_manager != null:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "enemy")
		ctx.minion = instance
		ctx.card   = mc
		sim.trigger_manager.fire(ctx)
	return sim.winner.is_empty()

func commit_play_spell(spell: SpellCardData, chosen_target = null) -> bool:
	sim.enemy_hand.erase(spell)
	sim.enemy_discard.append(spell)
	_resolve_spell(spell, chosen_target)
	return sim.winner.is_empty()

func do_attack_minion(attacker: MinionInstance, target: MinionInstance) -> bool:
	if not sim.enemy_board.has(attacker):
		return false
	sim.combat_manager.resolve_minion_attack(attacker, target)
	return sim.winner.is_empty()

func do_attack_hero(attacker: MinionInstance) -> bool:
	if not sim.enemy_board.has(attacker):
		return false
	sim.combat_manager.resolve_minion_attack_hero(attacker, "player")
	return sim.winner.is_empty()

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func effective_spell_cost(spell: SpellCardData) -> int:
	return max(0, spell.cost + sim.enemy_spell_cost_penalty \
		- (sim.enemy_spell_cost_discounts.get(spell.id, 0) as int))

func opponent_has_rune_or_environment() -> bool:
	if sim.active_environment != null:
		return true
	for trap in sim.active_traps:
		if (trap as TrapCardData).is_rune:
			return true
	return false

# ---------------------------------------------------------------------------
# EnemyAI duck-type methods (called by EffectResolver)
# ---------------------------------------------------------------------------

func draw_cards(count: int) -> void:
	_draw_cards(count)

func _draw_cards(count: int) -> void:
	sim._draw_enemy(count)

func add_to_hand(card: CardData) -> void:
	if sim.enemy_hand.size() < SimState.ENEMY_HAND_MAX:
		sim.enemy_hand.append(card)

# ---------------------------------------------------------------------------
# Effect resolution helpers
# ---------------------------------------------------------------------------

func _resolve_on_play(mc: MinionCardData, instance: MinionInstance, chosen_target) -> void:
	if mc.on_play_effect_steps.is_empty():
		return
	var ctx := _make_ctx("enemy", instance, chosen_target)
	EffectResolver.run(mc.on_play_effect_steps, ctx)

func _resolve_spell(spell: SpellCardData, chosen_target) -> void:
	var ctx := _make_ctx("enemy", null, chosen_target)
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
