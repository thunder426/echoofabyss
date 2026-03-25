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
func _get_hand()           -> Array[CardData]:        return _ai.hand
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

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func commit_play_minion(mc: MinionCardData, slot: BoardSlot, chosen_target = null) -> bool:
	return await _ai.commit_minion_play(mc, slot, chosen_target)

func commit_play_spell(spell: SpellCardData, chosen_target = null) -> bool:
	return await _ai.commit_spell_cast(spell, chosen_target)

func commit_play_trap(trap: TrapCardData) -> bool:
	return await _ai.commit_play_trap(trap)

func commit_play_environment(env: EnvironmentCardData) -> bool:
	return await _ai.commit_play_environment(env)

func do_attack_minion(attacker: MinionInstance, target: MinionInstance) -> bool:
	return await _ai.do_attack_minion(attacker, target)

func do_attack_hero(attacker: MinionInstance) -> bool:
	return await _ai.do_attack_hero(attacker)

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func effective_spell_cost(spell: SpellCardData) -> int:
	return _ai.effective_spell_cost(spell)

func opponent_has_rune_or_environment() -> bool:
	return _ai.player_has_rune_or_environment()
