## CombatAgent.gd
## Perspective-agnostic interface between a CombatProfile and the underlying game state.
## "Friendly" = the side this agent controls.  "Opponent" = the other side.
##
## Subclasses: StateAgent (a side of a CombatState, via state commands — sim
## and tests) and EnemyAgent (the live EnemyAI node, until Phase 3.4).
## All default method implementations are no-ops or sensible defaults so that the
## base class compiles cleanly; override what you need.
class_name CombatAgent
extends RefCounted

## The side this agent plays ("player" / "enemy").
var side: String = "player"

## Randomness for AI *decisions* (e.g. which enemy rune to target). Kept off the
## engine's `state.rng` so a replay of the command log — which runs no profiles —
## draws the same engine randoms as the original fight (plan 2A.8).
var decision_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## A random element of a non-empty `arr`, drawn from decision_rng.
func decision_pick(arr: Array) -> Variant:
	return arr[decision_rng.randi() % arr.size()]

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

## The combat state — read gameplay fields through this (typed).
var state: CombatState:
	get: return _get_state()


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

## Returns the first empty friendly board slot (engine SlotState), or null if
## the board is full.
func find_empty_slot() -> SlotState:
	return null

## Returns the number of empty friendly board slots.
## Default returns a large sentinel — override in concrete agents with direct slot access.
func empty_slot_count() -> int:
	return 9999

# ---------------------------------------------------------------------------
# Actions — return false if the action could not complete or env is gone
# ---------------------------------------------------------------------------

## Place a minion on a slot (slot already found). The engine pays the cost —
## profiles only check affordability; spark fuel they consume first is credited.
## inst is the CardInstance being played from hand.
func commit_play_minion(inst: CardInstance, slot: SlotState, chosen_target = null) -> bool:
	return false

## Cast a spell. extra: pre-resolved cast choices (e.g. rally_race).
## inst is the CardInstance being played from hand.
func commit_play_spell(inst: CardInstance, chosen_target = null, extra: Dictionary = {}) -> bool:
	return false

## Place a trap or rune.
## inst is the CardInstance being played from hand.
func commit_play_trap(inst: CardInstance) -> bool:
	return false

## Play an environment card.
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

## Use a hero activated ability ("seris_corrupt" with a friendly target,
## "soul_forge"). Returns true if it fired.
func hero_skill(_skill_id: String, _target = null) -> bool:
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

## Effective essence cost of a minion. Accounts for the side's per-card essence
## discounts plus its flat minion essence aura (e.g. F15 Abyssal Mandate after
## the player grew Essence last turn).
func effective_minion_essence_cost(mc: MinionCardData) -> int:
	var cost: int = mc.essence_cost - (_essence_cost_discounts().get(mc.id, 0) as int)
	cost += _minion_essence_cost_aura()
	return maxi(0, cost)

## Per-card essence discounts keyed by card id. Enemy agents override.
func _essence_cost_discounts() -> Dictionary:
	return {}

## Flat essence adjustment on every minion (negative = cheaper). Enemy agents override.
func _minion_essence_cost_aura() -> int:
	return 0

## Effective mana cost of a minion. Subclasses override for additional modifiers.
## Talent-driven cost changes (e.g. piercing_void's +1 Mana on base Void Imp) are
## baked into mc.mana_cost via talent_overrides in CardDatabase, so no special
## cases are needed here.
func effective_minion_mana_cost(mc: MinionCardData) -> int:
	return mc.mana_cost

## True if the engine would let this side set `trap` now (a free trap slot and
## no copy of the same non-rune trap already set).
func can_place_trap(trap: TrapCardData) -> bool:
	return state != null and state.trap_placement_refusal(side, trap).is_empty()

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
func _get_state() -> CombatState: return null
func _get_friendly_hp() -> int: return 0
func _get_opponent_hp() -> int: return 0
