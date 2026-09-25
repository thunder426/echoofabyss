## EnemyAI.gd
## Enemy AI using the same dual-resource (Essence + Mana) system as the player.
## CombatScene calls run_turn() when the enemy turn starts.
## The AI plays cards from a real shuffled deck, then attacks, then emits ai_turn_finished.
##
## All decision logic lives in CombatProfile subclasses (enemies/ai/profiles/,
## built from ProfileRegistry).
## This file owns game state, signals, and public action helpers that profiles call.
class_name EnemyAI
extends Node

var _active_profile: CombatProfile = null
var _pacer: LivePacer = null

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------








# ---------------------------------------------------------------------------
# References — set by CombatScene before run_turn()
# ---------------------------------------------------------------------------


## AI behaviour profile ID.  Setting this resets the active profile object.
var ai_profile: String = "default":
	set(value):
		ai_profile = value
		_active_profile = null

## Reference to CombatScene — used by profiles to inspect player board state.
var scene: Node = null

# ---------------------------------------------------------------------------
# Enemy-side state — façade over CombatState (LIVE_SIM_UNIFICATION_PLAN.md 1.3).
# Resources, deck, hand, graveyard, traps, environment and cost modifiers live
# on `scene.state` (the enemy_* fields); these forward so profiles and the UI
# keep reading `enemy_ai.essence` etc.
# ---------------------------------------------------------------------------

var state: CombatState:
	get: return scene.state

var essence: int:
	get: return state.enemy_essence
	set(v): state.enemy_essence = v
var essence_max: int:
	get: return state.enemy_essence_max
	set(v): state.enemy_essence_max = v
var mana: int:
	get: return state.enemy_mana
	set(v): state.enemy_mana = v
var mana_max: int:
	get: return state.enemy_mana_max
	set(v): state.enemy_mana_max = v

## Shared combined cap with the player (essence_max + mana_max ≤ this).
const COMBINED_RESOURCE_CAP := CombatState.COMBINED_RESOURCE_CAP

## Extra mana cost added to enemy spells this turn (from Spell Taxer).
var spell_cost_penalty: int:
	get: return state.enemy_spell_cost_penalty
	set(v): state.enemy_spell_cost_penalty = v

## Persistent flat mana-cost adjustment from an active aura (e.g. Void Ritualist
## Prime champion reduces by 1). Negative = discount. Not reset per turn.
var spell_cost_aura: int:
	get: return state.enemy_spell_cost_aura
	set(v): state.enemy_spell_cost_aura = v

## Per-card mana cost discounts keyed by card ID (e.g. {"pack_frenzy": 1}).
var spell_cost_discounts: Dictionary:
	get: return state.enemy_spell_cost_discounts

## Per-card essence cost discounts keyed by card ID (e.g. {"void_touched_imp": 1}).
var essence_cost_discounts: Dictionary:
	get: return state.enemy_essence_cost_discounts

## Flat essence-cost discount applied to every enemy minion this turn (e.g. F15
## Abyssal Mandate grants -2 after the player grows Essence). Negative = cheaper.
## Reset by whichever system sets it (mandate clears at end of enemy turn).
var minion_essence_cost_aura: int:
	get: return state.enemy_minion_essence_cost_aura
	set(v): state.enemy_minion_essence_cost_aura = v

## Set by Smoke Veil (via state) to cancel the attack being declared.
var attack_cancelled: bool:
	get: return state.attack_cancelled
	set(v): state.attack_cancelled = v



## Active traps and runes placed by the enemy.
var active_traps: Array[TrapCardData]:
	get: return state.enemy_active_traps
	set(v): state.enemy_active_traps = v


## Active environment card played by the enemy (mirrors the player's active_environment).
var active_environment: EnvironmentCardData:
	get: return state.enemy_active_environment
	set(v): state.enemy_active_environment = v

## Enemy deck — never runs out (see CombatState.draw_cards).
var deck: Array[CardInstance]:
	get: return state.enemy_deck
## Card IDs flagged as limited — drawn once per copy, not re-added to deck.
var _limited_cards: Array[String]:
	get: return state.enemy_limited_cards
	set(v): state.enemy_limited_cards = v
## Unified enemy graveyard (see CombatState.send_to_graveyard).
var graveyard: Array[CardInstance]:
	get: return state.enemy_graveyard
var hand: Array[CardInstance]:
	get: return state.enemy_hand
const HAND_MAX := CombatState.HAND_MAX

# ---------------------------------------------------------------------------
# Timing
# ---------------------------------------------------------------------------

const ACTION_DELAY := 0.55

# ---------------------------------------------------------------------------
# Setup — called by CombatScene before the first turn
# ---------------------------------------------------------------------------

## Played when an encounter has no deck configured.
const FALLBACK_DECK: Array[String] = [
	"void_imp", "void_imp", "void_imp",
	"shadow_hound", "shadow_hound",
	"abyssal_brute",
	"void_bolt", "void_bolt",
]

## Load, shuffle and draw the opening 5 from a list of card IDs (combat-time
## lookup, so enemy-side overrides like ancient_frenzy apply). Empty → fallback deck.
func setup_deck(card_ids: Array[String]) -> void:
	state.setup_deck("enemy", card_ids if not card_ids.is_empty() else FALLBACK_DECK)

## Add a CardData directly to the enemy's hand (used by ON_PLAY effects).
func add_to_hand(card: CardData) -> void:
	state.add_to_hand("enemy", card)

## Add an existing CardInstance directly to the enemy hand (used by symmetric effects).
func add_instance_to_hand(inst: CardInstance) -> void:
	state.add_to_hand("enemy", inst)

## Stamp `resolved_on_turn` and append to the unified graveyard.
## Called from every commit_play_* path the moment a card leaves hand.
func _send_to_graveyard(inst: CardInstance) -> void:
	state.send_to_graveyard("enemy", inst)

## Public wrapper — draw count cards from the enemy deck (used by passives).
func draw_cards(count: int) -> void:
	_draw_cards(count)

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

## The enemy's actions. Growth, refill, the Void Rift Lord drain and the draw
## already ran in state.begin_turn("enemy").
func run_turn() -> void:
	if _active_profile == null:
		_setup_profile()
	await _active_profile.play_phase()
	if not is_inside_tree(): return
	# Everything the play phase did is shown, plus a beat, before the attacks.
	await _pacer.after_action("phase")
	if not is_inside_tree(): return
	await _active_profile.attack_phase()
	if not is_inside_tree(): return
	await scene.presenter.pump_and_wait_idle()
	if not is_inside_tree() or state._combat_ended or not state.winner.is_empty():
		return
	state.cmd_end_turn("enemy")

# ---------------------------------------------------------------------------
# Private — profile setup
# ---------------------------------------------------------------------------

## The live enemy is a StateAgent on the engine (plan 3.4): every action a
## state command, paced by the presenter (LivePacer).
func _setup_profile() -> void:
	_active_profile = ProfileRegistry.make("enemy", ai_profile)
	_pacer = LivePacer.new()
	_pacer.setup(scene)
	var agent := StateAgent.new()
	agent.setup(state, "enemy", _pacer)
	_active_profile.setup(agent)

# ---------------------------------------------------------------------------
# Private — resource growth
# ---------------------------------------------------------------------------

## state.growth_hooks["enemy"] — run by state.begin_turn("enemy"): the active
## profile's curve (CombatProfile.grow_resources; the base is the default curve).
func grow_at_turn_start(side: String, turn: int) -> void:
	if _active_profile == null:
		_setup_profile()
	_active_profile.grow_resources(state, side, turn)

# ---------------------------------------------------------------------------
# Private — card draw
# ---------------------------------------------------------------------------

## Draw count cards (see CombatState.draw_cards — the enemy deck never runs out).
func _draw_cards(count: int) -> void:
	state.draw_cards("enemy", count)
