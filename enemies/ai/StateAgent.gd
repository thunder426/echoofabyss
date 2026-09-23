## StateAgent.gd
## CombatAgent for one side of a CombatState (LIVE_SIM_UNIFICATION_PLAN.md
## 2A.5). Every action is a state command (cmd_*) — the engine validates it
## and pays its cost — followed by the pacer. The sim runs both sides on this;
## live's enemy moves onto it in Phase 3.4 (until then: EnemyAgent → EnemyAI).
class_name StateAgent
extends CombatAgent

var _state: CombatState
var pacer: Pacer

## Spark value this side consumed as fuel since its last card play. Profiles
## pick and consume their spark fuel, then play; the play is credited with it.
var _sparks_prepaid: int = 0

func setup(s: CombatState, p_side: String, p_pacer: Pacer = null) -> void:
	_state = s
	side = p_side
	pacer = p_pacer if p_pacer != null else Pacer.new()
	decision_rng.seed = hash("%d:%s" % [s.rng_seed, p_side])

# ---------------------------------------------------------------------------
# Boards / hand / resources
# ---------------------------------------------------------------------------

func _get_state() -> CombatState: return _state
func _get_scene() -> Object: return _state
func _get_friendly_board() -> Array[MinionInstance]: return _state._friendly_board(side)
func _get_opponent_board() -> Array[MinionInstance]: return _state._opponent_board(side)
func _get_hand() -> Array[CardInstance]: return _state.hand_of(side)
func _get_essence() -> int: return _state.essence_of(side)
func _set_essence(v: int) -> void: _state.set_essence(side, v)
func _get_mana() -> int: return _state.mana_of(side)
func _set_mana(v: int) -> void: _state.set_mana(side, v)
func _get_friendly_hp() -> int: return _state.player_hp if side == "player" else _state.enemy_hp
func _get_opponent_hp() -> int: return _state.enemy_hp if side == "player" else _state.player_hp

func is_alive() -> bool:
	return _state.winner.is_empty()

func find_empty_slot() -> BoardSlot:
	for slot: BoardSlot in _state._friendly_slots(side):
		if slot.is_empty():
			return slot
	return null

func empty_slot_count() -> int:
	var count := 0
	for slot: BoardSlot in _state._friendly_slots(side):
		if slot.is_empty():
			count += 1
	return count

# ---------------------------------------------------------------------------
# Actions — state commands
# ---------------------------------------------------------------------------

func commit_play_minion(inst: CardInstance, slot: BoardSlot, chosen_target = null) -> bool:
	if slot == null:
		return false
	return await _done(_state.cmd_play_minion(side, inst, slot.index, chosen_target, _with_prepaid({})), "play_minion")

func commit_play_spell(inst: CardInstance, chosen_target = null, extra: Dictionary = {}) -> bool:
	return await _done(_state.cmd_play_spell(side, inst, chosen_target, _with_prepaid(extra)), "play_spell")

func commit_play_trap(inst: CardInstance) -> bool:
	_sparks_prepaid = 0
	return await _done(_state.cmd_play_trap(side, inst), "play_trap")

func commit_play_environment(inst: CardInstance) -> bool:
	_sparks_prepaid = 0
	return await _done(_state.cmd_play_environment(side, inst), "play_environment")

func do_attack_minion(attacker: MinionInstance, target: MinionInstance) -> bool:
	return await _done(_state.cmd_attack(side, attacker, target), "attack")

func do_attack_hero(attacker: MinionInstance) -> bool:
	return await _done(_state.cmd_attack_hero(side, attacker), "attack")

func consume_minion(minion: MinionInstance) -> void:
	var value: int = minion.effective_spark_value(_state)
	if _state.cmd_consume_minion(side, minion).ok:
		_sparks_prepaid += value

func hero_skill(skill_id: String, target = null) -> bool:
	return _state.cmd_hero_skill(side, skill_id, target).ok

func _with_prepaid(extra: Dictionary) -> Dictionary:
	var out: Dictionary = extra.duplicate()
	out["sparks_prepaid"] = _sparks_prepaid
	_sparks_prepaid = 0
	return out

func _done(r: CommandResult, kind: String) -> bool:
	await pacer.after_action(kind)
	return r.ok and _state.winner.is_empty()

# ---------------------------------------------------------------------------
# Costs — the engine's own numbers
# ---------------------------------------------------------------------------

func effective_spell_cost(spell: SpellCardData) -> int:
	return _state.spell_cost(side, spell)

func effective_minion_essence_cost(mc: MinionCardData) -> int:
	return _state.minion_essence_cost(side, mc)

func opponent_has_rune_or_environment() -> bool:
	var opp: String = _state._opponent_of(side)
	if _state.environment_of(opp) != null:
		return true
	for trap: TrapCardData in _state.traps_of(opp):
		if trap.is_rune:
			return true
	return false
