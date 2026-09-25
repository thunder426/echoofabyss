## ViewState.gd
## The lagging copy of the combat state the UI panels render (plan 3.2, D4
## hybrid). Updated only by CombatPresenter as it consumes journal events, so
## a panel never shows a value before the animation that explains it. Board
## slots are not modelled here: they render the MinionInstance the presenter
## hands them at playback, with stat labels driven by event before/after values.
class_name ViewState
extends RefCounted

var player_hp: int = 0
var player_hp_max: int = 0
var enemy_hp: int = 0
var enemy_hp_max: int = 0
var player_essence: int = 0
var player_essence_max: int = 0
var player_mana: int = 0
var player_mana_max: int = 0
var enemy_essence: int = 0
var enemy_essence_max: int = 0
var enemy_mana: int = 0
var enemy_mana_max: int = 0
var enemy_void_marks: int = 0
var player_flesh: int = 0
var player_flesh_max: int = 0
var forge_counter: int = 0
var forge_counter_threshold: int = 0
var player_armour: int = 0
var enemy_armour: int = 0
var player_traps: Array[TrapCardData] = []
var enemy_traps: Array[TrapCardData] = []
var player_environment: EnvironmentCardData = null
var enemy_environment: EnvironmentCardData = null
var turn_number: int = 0
var is_player_turn: bool = true


## Full copy from the engine — used once at setup, before any event plays.
func sync_from(state: CombatState) -> void:
	player_hp = state.player_hp
	player_hp_max = state.player_hp_max
	enemy_hp = state.enemy_hp
	enemy_hp_max = state.enemy_hp_max
	player_essence = state.player_essence
	player_essence_max = state.player_essence_max
	player_mana = state.player_mana
	player_mana_max = state.player_mana_max
	enemy_essence = state.enemy_essence
	enemy_essence_max = state.enemy_essence_max
	enemy_mana = state.enemy_mana
	enemy_mana_max = state.enemy_mana_max
	enemy_void_marks = state.enemy_void_marks
	player_flesh = state.player_flesh
	player_flesh_max = state.player_flesh_max
	forge_counter = state.forge_counter
	forge_counter_threshold = state.forge_counter_threshold
	player_armour = state.player_hero.armour
	enemy_armour = state.enemy_hero.armour
	player_traps = state.active_traps.duplicate()
	enemy_traps = state.enemy_active_traps.duplicate()
	player_environment = state.active_environment
	enemy_environment = state.enemy_active_environment
	turn_number = state.turn_number
	is_player_turn = state.is_player_turn


## Apply one journal event's payload.
func apply(ev: CombatEvent) -> void:
	var p: Dictionary = ev.payload
	match ev.kind:
		CombatEvent.Kind.HERO_HP_CHANGED:
			if ev.side == "player":
				player_hp = p.get("hp", player_hp)
				player_hp_max = p.get("hp_max", player_hp_max)
			else:
				enemy_hp = p.get("hp", enemy_hp)
				enemy_hp_max = p.get("hp_max", enemy_hp_max)
		CombatEvent.Kind.RESOURCES_CHANGED:
			if ev.side == "player":
				player_essence = p.get("essence", player_essence)
				player_essence_max = p.get("essence_max", player_essence_max)
				player_mana = p.get("mana", player_mana)
				player_mana_max = p.get("mana_max", player_mana_max)
			else:
				enemy_essence = p.get("essence", enemy_essence)
				enemy_essence_max = p.get("essence_max", enemy_essence_max)
				enemy_mana = p.get("mana", enemy_mana)
				enemy_mana_max = p.get("mana_max", enemy_mana_max)
		CombatEvent.Kind.VOID_MARKS_CHANGED:
			enemy_void_marks = p.get("value", enemy_void_marks)
		CombatEvent.Kind.FLESH_CHANGED:
			player_flesh = p.get("value", player_flesh)
			player_flesh_max = p.get("max", player_flesh_max)
		CombatEvent.Kind.FORGE_CHANGED:
			forge_counter = p.get("value", forge_counter)
			forge_counter_threshold = p.get("threshold", forge_counter_threshold)
		CombatEvent.Kind.ARMOUR_CHANGED:
			if ev.side == "player":
				player_armour = p.get("value", player_armour)
			else:
				enemy_armour = p.get("value", enemy_armour)
		CombatEvent.Kind.TRAPS_CHANGED:
			var traps: Array = p.get("traps", [])
			if ev.side == "player":
				player_traps.assign(traps)
			else:
				enemy_traps.assign(traps)
		CombatEvent.Kind.ENVIRONMENT_CHANGED:
			if ev.side == "player":
				player_environment = p.get("env", null)
			else:
				enemy_environment = p.get("env", null)
		CombatEvent.Kind.TURN_STARTED:
			turn_number = p.get("turn", turn_number)
			is_player_turn = ev.side == "player"
		CombatEvent.Kind.TURN_ENDED:
			is_player_turn = ev.side != "player"
