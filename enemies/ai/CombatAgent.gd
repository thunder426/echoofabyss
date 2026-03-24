## CombatAgent.gd
## Perspective-agnostic interface between a CombatProfile and the underlying game state.
## "Friendly" = the side this agent controls.  "Opponent" = the other side.
##
## Subclass this to wrap a concrete game state (EnemyAI node, SimState, etc.).
## All default method implementations are no-ops or sensible defaults so that the
## base class compiles cleanly; override what you need.
class_name CombatAgent
extends RefCounted

# ---------------------------------------------------------------------------
# Boards / hand / resources — backed by virtual getters/setters
# ---------------------------------------------------------------------------

## Minions controlled by this agent.
var friendly_board: Array[MinionInstance]:
	get: return _get_friendly_board()

## Minions controlled by the opponent.
var opponent_board: Array[MinionInstance]:
	get: return _get_opponent_board()

## Cards currently in this agent's hand.
var hand: Array[CardData]:
	get: return _get_hand()

## Essence available this turn.
var essence: int:
	get: return _get_essence()
	set(v): _set_essence(v)

## Mana available this turn.
var mana: int:
	get: return _get_mana()
	set(v): _set_mana(v)

## Scene reference — passed to ConditionResolver / EffectResolver.
## Typed as Object so both Node (real game) and RefCounted (SimState) work.
var scene: Object:
	get: return _get_scene()

## Friendly hero HP — used for lethal-threat checks.
var friendly_hp: int:
	get: return _get_friendly_hp()

## Opponent hero HP.
var opponent_hp: int:
	get: return _get_opponent_hp()

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Returns false when the underlying environment is no longer valid
## (e.g. scene tree exited, simulation stopped).
func is_alive() -> bool:
	return true

# ---------------------------------------------------------------------------
# Board
# ---------------------------------------------------------------------------

## Returns the first empty friendly board slot, or null if the board is full.
func find_empty_slot() -> BoardSlot:
	return null

# ---------------------------------------------------------------------------
# Actions — return false if the action could not complete or env is gone
# ---------------------------------------------------------------------------

## Place a minion on a slot (slot already found, resources already deducted).
func commit_play_minion(mc: MinionCardData, slot: BoardSlot, chosen_target = null) -> bool:
	return false

## Cast a spell (resources already deducted).
func commit_play_spell(spell: SpellCardData, chosen_target = null) -> bool:
	return false

## Execute a friendly minion vs opponent minion attack.
func do_attack_minion(attacker: MinionInstance, target: MinionInstance) -> bool:
	return false

## Execute a friendly minion vs opponent hero attack.
func do_attack_hero(attacker: MinionInstance) -> bool:
	return false

# ---------------------------------------------------------------------------
# Utilities — default implementations shared by all agents
# ---------------------------------------------------------------------------

## Best SWIFT target on the opponent board: killable first, then highest ATK.
func pick_swift_target(attacker: MinionInstance) -> MinionInstance:
	if opponent_board.is_empty():
		return null
	var killable: Array[MinionInstance] = []
	for m in opponent_board:
		if attacker.effective_atk() >= m.current_health:
			killable.append(m)
	var pool := killable if not killable.is_empty() else opponent_board
	var best: MinionInstance = pool[0]
	for m in pool:
		if m.effective_atk() > best.effective_atk():
			best = m
	return best

## Sort comparator — cheapest total cost first.
func sort_by_total_cost(a: CardData, b: CardData) -> bool:
	var ac := (a as MinionCardData).essence_cost + (a as MinionCardData).mana_cost \
		if a is MinionCardData else (a as SpellCardData).cost
	var bc := (b as MinionCardData).essence_cost + (b as MinionCardData).mana_cost \
		if b is MinionCardData else (b as SpellCardData).cost
	return ac < bc

## Effective mana cost of a spell after any penalties / discounts.
## Base: no modifications.  Override in subclasses that track cost modifiers.
func effective_spell_cost(spell: SpellCardData) -> int:
	return spell.cost

## Returns true if the opponent has an active Rune or Environment card.
func opponent_has_rune_or_environment() -> bool:
	return false

# ---------------------------------------------------------------------------
# Private virtual — override in subclass to wire game state
# ---------------------------------------------------------------------------

func _get_friendly_board() -> Array[MinionInstance]: return []
func _get_opponent_board() -> Array[MinionInstance]: return []
func _get_hand() -> Array[CardData]: return []
func _get_essence() -> int: return 0
func _set_essence(_v: int) -> void: pass
func _get_mana() -> int: return 0
func _set_mana(_v: int) -> void: pass
func _get_scene() -> Object: return null
func _get_friendly_hp() -> int: return 0
func _get_opponent_hp() -> int: return 0
