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

## Duck-types EnemyAI.minion_play_chosen_target so on_enemy_minion_played_effect
## can read the target after the trigger fires.
var minion_play_chosen_target = null

func setup(s: SimState) -> void:
	sim = s
	sim.enemy_ai = self  # register as the scene's enemy_ai duck-type

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
# EnemyAI duck-type properties (read by EffectResolver)
# ---------------------------------------------------------------------------

var mana_max: int:
	get: return sim.enemy_mana_max
var essence_max: int:
	get: return sim.enemy_essence_max

## Duck-type active_traps so HardcodedEffects._destroy_random_enemy_trap() can read/erase.
var active_traps: Array:
	get: return sim.enemy_active_traps

## Duck-type active_environment for parity with EnemyAI.
var active_environment:
	get: return sim.enemy_active_environment
	set(v): sim.enemy_active_environment = v

## Duck-type spell_cost_discounts so CombatSetup can write pack_frenzy discount.
var spell_cost_discounts: Dictionary:
	get: return sim.enemy_spell_cost_discounts

## Duck-type essence_cost_discounts so CombatSetup can write minion essence discounts.
var essence_cost_discounts: Dictionary:
	get: return sim.enemy_essence_cost_discounts

## Duck-type attack_cancelled so Smoke Veil can cancel attacks.
var attack_cancelled: bool = false

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

func commit_play_minion(inst: CardInstance, slot: BoardSlot, chosen_target = null) -> bool:
	var mc := inst.card_data as MinionCardData
	var instance := MinionInstance.create(mc, "enemy")
	instance.card_instance = inst
	sim.enemy_board.append(instance)
	slot.place_minion(instance)
	sim.enemy_hand.erase(inst)
	sim.enemy_discard.append(inst)
	# Set target so on_enemy_minion_played_effect (always-on handler) can read it.
	minion_play_chosen_target = chosen_target
	if sim.trigger_manager != null:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "enemy")
		ctx.minion = instance
		ctx.card   = mc
		sim.trigger_manager.fire(ctx)
	else:
		_resolve_on_play(mc, instance, chosen_target)
	return sim.winner.is_empty()

func commit_play_spell(inst: CardInstance, chosen_target = null) -> bool:
	var spell := inst.card_data as SpellCardData
	sim.enemy_hand.erase(inst)
	sim.enemy_discard.append(inst)
	# Phase Disruptor counter: player counters enemy spell
	if sim._enemy_spell_counter > 0:
		sim._enemy_spell_counter -= 1
		return sim.winner.is_empty()
	# Fire ON_ENEMY_SPELL_CAST before resolving (matches CombatScene behavior)
	if sim.trigger_manager:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "enemy")
		ctx.card = spell
		sim.trigger_manager.fire(ctx)
	_resolve_spell(spell, chosen_target)
	return sim.winner.is_empty()

func commit_play_trap(inst: CardInstance) -> bool:
	var trap := inst.card_data as TrapCardData
	sim.enemy_hand.erase(inst)
	sim.enemy_discard.append(inst)
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
	sim.enemy_hand.erase(inst)
	sim.enemy_discard.append(inst)
	sim.enemy_active_environment = env
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
	if attack_cancelled:
		attack_cancelled = false
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
	if attack_cancelled:
		attack_cancelled = false
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
		sim.enemy_hand.append(CardInstance.create(card))

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
