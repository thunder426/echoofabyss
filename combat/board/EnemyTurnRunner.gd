## EnemyTurnRunner.gd
## Runs the live enemy's turn (plan 3.4; renamed from EnemyAI in 4.4). The enemy
## is a StateAgent on the CombatState — every action a state command — driven by
## its CombatProfile (ProfileRegistry) and paced by the presenter (LivePacer).
## All enemy-side state (resources, deck, hand, traps) lives on the state.
## CombatScene calls run_turn() once the player's turn has been shown.
class_name EnemyTurnRunner
extends Node

## AI behaviour profile id. Setting this resets the active profile object (the
## F15 phase transition swaps it through state.enemy_profile_changed).
var ai_profile: String = "default":
	set(value):
		ai_profile = value
		_active_profile = null

## The CombatScene — its state and presenter.
var scene: Node = null

var state: CombatState:
	get: return scene.state

var _active_profile: CombatProfile = null
var _pacer: LivePacer = null
## One agent for the whole fight: a profile swap (F15) keeps it, so the AI's
## decision_rng runs on as it does in the sim.
var _agent: StateAgent = null

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

## state.growth_hooks["enemy"] — run by state.begin_turn("enemy"): the active
## profile's curve (CombatProfile.grow_resources; the base is the default curve).
func grow_at_turn_start(side: String, turn: int) -> void:
	if _active_profile == null:
		_setup_profile()
	_active_profile.grow_resources(state, side, turn)

func _setup_profile() -> void:
	_active_profile = ProfileRegistry.make("enemy", ai_profile)
	if _agent == null:
		_pacer = LivePacer.new()
		_pacer.setup(scene)
		_agent = StateAgent.new()
		_agent.setup(state, "enemy", _pacer)
	_active_profile.setup(_agent)
