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

## Cards currently in this agent's hand (as CardInstances).
var hand: Array[CardInstance]:
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

## Returns the number of empty friendly board slots.
## Default returns a large sentinel — override in concrete agents with direct slot access.
func empty_slot_count() -> int:
	return 9999

# ---------------------------------------------------------------------------
# Actions — return false if the action could not complete or env is gone
# ---------------------------------------------------------------------------

## Place a minion on a slot (slot already found, resources already deducted).
## inst is the CardInstance being played from hand.
func commit_play_minion(inst: CardInstance, slot: BoardSlot, chosen_target = null) -> bool:
	return false

## Cast a spell (resources already deducted).
## inst is the CardInstance being played from hand.
func commit_play_spell(inst: CardInstance, chosen_target = null) -> bool:
	return false

## Place a trap or rune (resources already deducted).
## inst is the CardInstance being played from hand.
func commit_play_trap(inst: CardInstance) -> bool:
	return false

## Play an environment card (resources already deducted).
## inst is the CardInstance being played from hand.
func commit_play_environment(inst: CardInstance) -> bool:
	return false

## Execute a friendly minion vs opponent minion attack.
func do_attack_minion(attacker: MinionInstance, target: MinionInstance) -> bool:
	return false

## Execute a friendly minion vs opponent hero attack.
func do_attack_hero(attacker: MinionInstance) -> bool:
	return false

## Remove a friendly minion from the board without triggering ON DEATH effects.
## Used for spark consumption (Void Spirits sacrificed as fuel).
func consume_minion(_minion: MinionInstance) -> void:
	pass

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

## Sort comparator — cheapest total cost first (operates on CardInstances).
func sort_by_total_cost(a: CardInstance, b: CardInstance) -> bool:
	var ac: int
	var bc: int
	if a.card_data is MinionCardData:
		var ma := a.card_data as MinionCardData
		ac = ma.essence_cost + ma.mana_cost
	else:
		ac = a.card_data.cost
	if b.card_data is MinionCardData:
		var mb := b.card_data as MinionCardData
		bc = mb.essence_cost + mb.mana_cost
	else:
		bc = b.card_data.cost
	return ac < bc

## Effective mana cost of a spell after any penalties / discounts.
## Base: no modifications.  Override in subclasses that track cost modifiers.
func effective_spell_cost(spell: SpellCardData) -> int:
	return spell.cost

## Effective essence cost of a minion. Accounts for essence_cost_discounts on subclasses.
func effective_minion_essence_cost(mc: MinionCardData) -> int:
	var discounts = get("essence_cost_discounts")
	if discounts is Dictionary and not discounts.is_empty():
		var discount: int = (discounts.get(mc.id, 0) as int)
		return maxi(0, mc.essence_cost - discount)
	return mc.essence_cost

## Effective mana cost of a minion. Accounts for piercing_void (+1 Mana on base Void Imp).
## Override in subclasses for additional modifiers.
func effective_minion_mana_cost(mc: MinionCardData) -> int:
	var extra := 0
	if scene != null and mc.mana_cost == 0:
		# Check piercing_void talent: base Void Imp costs +1 Mana
		var talents = scene.get("talents")
		if talents is Array and "piercing_void" in talents:
			if "base_void_imp" in mc.minion_tags:
				extra = 1
	return mc.mana_cost + extra

## Returns true if the opponent has an active Rune or Environment card.
func opponent_has_rune_or_environment() -> bool:
	return false

# ---------------------------------------------------------------------------
# Private virtual — override in subclass to wire game state
# ---------------------------------------------------------------------------

func _get_friendly_board() -> Array[MinionInstance]: return []
func _get_opponent_board() -> Array[MinionInstance]: return []
func _get_hand() -> Array[CardInstance]: return []
func _get_essence() -> int: return 0
func _set_essence(_v: int) -> void: pass
func _get_mana() -> int: return 0
func _set_mana(_v: int) -> void: pass
func _get_scene() -> Object: return null
func _get_friendly_hp() -> int: return 0
func _get_opponent_hp() -> int: return 0
