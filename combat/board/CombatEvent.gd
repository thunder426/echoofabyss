## CombatEvent.gd
## One entry of CombatState's journal (LIVE_SIM_UNIFICATION_PLAN.md 3.1).
##
## The engine appends one event per gameplay mutation, in order, through
## `CombatState.emit_event`. The live presenter (3.2) drains the journal one
## event at a time and plays one animation per event against a lagging
## ViewState; sim and tests read it for ordering probes (or ignore it).
##
## `payload` holds slot indices, card ids, `before` / `after` values and hero
## sentinels; MinionInstance / CardInstance / card data refs are allowed, Node
## refs are not.
class_name CombatEvent
extends RefCounted

enum Kind {
	TURN_STARTED, TURN_ENDED, RESOURCES_CHANGED,
	CARD_DRAWN, CARD_GENERATED, CARD_PLAYED,
	MINION_PLAYED, MINION_SUMMONED, TOKEN_SUMMONED, CHAMPION_SUMMONED,
	MINION_STATS_CHANGED, BUFF_APPLIED, ARMOUR_CHANGED, HERO_BUFF_CHANGED,
	DAMAGE_DEALT, HERO_HP_CHANGED, HERO_HEALED, MINION_HEALED,
	MINION_DIED, MINION_SACRIFICED, MINION_CONSUMED, SLOT_CHANGED,
	SPELL_CAST, SPELL_RESOLVED, SPELL_COUNTERED,
	TRAP_PLACED, RUNE_PLACED, TRAP_FIRED, TRAPS_CHANGED, ENVIRONMENT_CHANGED,
	RITUAL_FIRED, VOID_BOLT, VOID_MARKS_CHANGED, CORRUPTION_APPLIED, DETONATION,
	FLESH_CHANGED, FORGE_CHANGED, RELIC_ACTIVATED, HERO_SKILL, ATTACK_STARTED,
	LOG, PHASE_TRANSITION, COMBAT_ENDED,
	VFX,  # card-specific animation requested by rules code: payload.name + args
	# UI resync points (plan 4.4 — rules code no longer calls the presenter):
	HAND_COSTS_CHANGED,     # a hand card's cost delta changed (side = hand owner)
	SPELL_COUNTER_CHANGED,  # a counter-spell charge was armed or spent
	CHAMPION_PROGRESS,      # payload.current / payload.total — enemy champion pips
	CHAMPION_KILLED,
}

var seq: int = 0
var kind: Kind = Kind.LOG
var side: String = ""
var turn: int = 0
var payload: Dictionary = {}


static func make(p_kind: int, p_side: String, p_turn: int, p_payload: Dictionary) -> CombatEvent:
	var ev := CombatEvent.new()
	ev.kind = p_kind as Kind
	ev.side = p_side
	ev.turn = p_turn
	ev.payload = p_payload
	return ev


func kind_name() -> String:
	return Kind.keys()[kind]


func _to_string() -> String:
	return "#%d T%d %s %s %s" % [seq, turn, kind_name(), side, payload]
