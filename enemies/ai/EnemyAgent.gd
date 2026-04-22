## EnemyAgent.gd
## CombatAgent implementation that wraps the EnemyAI node.
## Friendly side = enemy.  Opponent side = player.
class_name EnemyAgent
extends CombatAgent

## Reference to the owning EnemyAI node (untyped to avoid circular load order).
var _ai  ## EnemyAI

func setup(enemy_ai) -> void:
	_ai = enemy_ai

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

func find_empty_slot() -> BoardSlot:
	return _ai.find_empty_slot()

func empty_slot_count() -> int:
	var count := 0
	for slot in _ai.enemy_slots:
		if slot.is_empty():
			count += 1
	return count

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func commit_play_minion(inst: CardInstance, slot: BoardSlot, chosen_target = null) -> bool:
	return await _ai.commit_minion_play(inst, slot, chosen_target)

func commit_play_spell(inst: CardInstance, chosen_target = null) -> bool:
	return await _ai.commit_spell_cast(inst, chosen_target)

func commit_play_trap(inst: CardInstance) -> bool:
	return await _ai.commit_play_trap(inst)

func commit_play_environment(inst: CardInstance) -> bool:
	return await _ai.commit_play_environment(inst)

func do_attack_minion(attacker: MinionInstance, target: MinionInstance) -> bool:
	return await _ai.do_attack_minion(attacker, target)

func do_attack_hero(attacker: MinionInstance) -> bool:
	return await _ai.do_attack_hero(attacker)

func consume_minion(minion: MinionInstance) -> void:
	_ai.consume_minion(minion)

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

## Duck-type essence_cost_discounts so CombatAgent.effective_minion_essence_cost() sees the discount.
var essence_cost_discounts: Dictionary:
	get: return _ai.essence_cost_discounts

## Duck-type minion_essence_cost_aura so CombatAgent sees F15 Abyssal Mandate.
var minion_essence_cost_aura: int:
	get: return _ai.minion_essence_cost_aura
	set(v): _ai.minion_essence_cost_aura = v

func effective_spell_cost(spell: SpellCardData) -> int:
	return _ai.effective_spell_cost(spell)

func opponent_has_rune_or_environment() -> bool:
	return _ai.player_has_rune_or_environment()
