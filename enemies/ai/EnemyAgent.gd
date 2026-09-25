## EnemyAgent.gd
## CombatAgent implementation that wraps the EnemyAI node.
## Friendly side = enemy.  Opponent side = player.
class_name EnemyAgent
extends CombatAgent

## Reference to the owning EnemyAI node (untyped to avoid circular load order).
var _ai  ## EnemyAI

## Spark value consumed as fuel since the last card play — credited to the next
## play's spark cost (same contract as StateAgent).
var _sparks_prepaid: int = 0

func setup(enemy_ai) -> void:
	_ai = enemy_ai
	side = "enemy"
	decision_rng.seed = hash("%d:enemy" % enemy_ai.state.rng_seed)

# ---------------------------------------------------------------------------
# Boards / hand / resources
# ---------------------------------------------------------------------------

func _get_friendly_board() -> Array[MinionInstance]: return _ai.enemy_board
func _get_opponent_board() -> Array[MinionInstance]: return _ai.player_board
func _get_hand()           -> Array[CardInstance]:   return _ai.hand
func _get_essence()        -> int: return _ai.essence
func _set_essence(v: int)  -> void: _ai.essence = v
func _get_mana()           -> int: return _ai.mana
func _set_mana(v: int)     -> void: _ai.mana = v
func _get_scene()          -> Object: return _ai.scene
func _get_state()          -> CombatState: return _ai.state

func _get_friendly_hp() -> int:
	if _ai.scene == null: return 0
	return _ai.scene.enemy_hp

func _get_opponent_hp() -> int:
	if _ai.scene == null: return 0
	return _ai.scene.player_hp

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func is_alive() -> bool:
	return _ai.is_inside_tree()

# ---------------------------------------------------------------------------
# Board slots
# ---------------------------------------------------------------------------

## Engine slots (plan 3.1a): EnemyAI.commit_minion_play takes the engine slot
## at once, so occupancy alone tells which slots are free.
func find_empty_slot() -> SlotState:
	for slot: SlotState in _ai.state._friendly_slots("enemy"):
		if slot.is_empty():
			return slot
	return null

func empty_slot_count() -> int:
	var count := 0
	for slot: SlotState in _ai.state._friendly_slots("enemy"):
		if slot.is_empty():
			count += 1
	return count

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func commit_play_minion(inst: CardInstance, slot: SlotState, chosen_target = null) -> bool:
	if slot == null:
		return false
	var node: BoardSlot = _ai.enemy_slots[slot.index]
	return await _ai.commit_minion_play(inst, node, chosen_target, _take_prepaid())

func commit_play_spell(inst: CardInstance, chosen_target = null, _extra: Dictionary = {}) -> bool:
	return await _ai.commit_spell_cast(inst, chosen_target, _take_prepaid())

func commit_play_trap(inst: CardInstance) -> bool:
	_sparks_prepaid = 0
	return await _ai.commit_play_trap(inst)

func commit_play_environment(inst: CardInstance) -> bool:
	_sparks_prepaid = 0
	return await _ai.commit_play_environment(inst)

func do_attack_minion(attacker: MinionInstance, target: MinionInstance) -> bool:
	return await _ai.do_attack_minion(attacker, target)

func do_attack_hero(attacker: MinionInstance) -> bool:
	return await _ai.do_attack_hero(attacker)

func consume_minion(minion: MinionInstance) -> void:
	_sparks_prepaid += minion.effective_spark_value(_ai.state)
	_ai.consume_minion(minion)

func _take_prepaid() -> int:
	var v: int = _sparks_prepaid
	_sparks_prepaid = 0
	return v

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func effective_minion_essence_cost(mc: MinionCardData) -> int:
	return _ai.state.minion_essence_cost("enemy", mc)

func effective_spell_cost(spell: SpellCardData) -> int:
	return _ai.state.spell_cost("enemy", spell)

func opponent_has_rune_or_environment() -> bool:
	return _ai.player_has_rune_or_environment()
