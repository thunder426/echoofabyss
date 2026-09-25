## EnemyTurnRunner.gd
## Runs the live enemy's turn (plan 3.4; renamed from EnemyAI in 4.4). The enemy
## is a StateAgent on the CombatState — every action a state command — driven by
## its CombatProfile (ProfileRegistry). All enemy-side state (resources, deck,
## hand, traps) lives on the state. CombatScene calls run_turn() once the
## player's turn has been shown.
##
## The turn is decided synchronously, exactly as the sim runs it (the agent's
## Pacer is the base no-op one): the presenter paces the enemy's actions as it
## plays the journal (a beat before each COMMAND). Awaiting a real pacer inside
## the profiles' action loops made GDScript occasionally skip the rest of a loop
## on resume — the enemy stopped attacking mid-turn (task 045).
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
## One agent for the whole fight: a profile swap (F15) keeps it, so the AI's
## decision_rng runs on as it does in the sim.
var _agent: StateAgent = null

## The enemy's whole turn: play phase, attack phase, end turn — the same
## sequence as CombatSim's enemy half. Growth, refill, the Void Rift Lord drain
## and the draw already ran in state.begin_turn("enemy").
func run_turn() -> void:
	await _profile().play_phase()
	if _combat_over():
		return
	# Re-read the profile: a phase transition during the play phase swaps it.
	await _profile().attack_phase()
	if _combat_over():
		return
	state.cmd_end_turn("enemy")

## state.growth_hooks["enemy"] — run by state.begin_turn("enemy"): the active
## profile's curve (CombatProfile.grow_resources; the base is the default curve).
func grow_at_turn_start(side: String, turn: int) -> void:
	_profile().grow_resources(state, side, turn)

func _profile() -> CombatProfile:
	if _active_profile == null:
		_active_profile = ProfileRegistry.make("enemy", ai_profile)
		if _agent == null:
			_agent = StateAgent.new()
			_agent.setup(state, "enemy")
		_active_profile.setup(_agent)
	return _active_profile

func _combat_over() -> bool:
	return not is_inside_tree() or state._combat_ended or not state.winner.is_empty()
