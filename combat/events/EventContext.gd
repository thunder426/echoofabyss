## EventContext.gd
## Payload passed to every trigger handler when an event fires.
## Only populate the fields relevant to the event; all others default to null / 0 / "".
## Handlers must never store a reference to ctx beyond their own stack frame.
class_name EventContext
extends RefCounted

## The event type (Enums.TriggerEvent value).
var event_type: int = -1

## Who owns the action: "player" | "enemy" | ""
var owner: String = ""

## The primary minion involved — summoned, dying, attacking, etc.
var minion: MinionInstance = null

## The player-chosen target for targeted on-play effects (void_netter, soul_collector, etc.)
## Null for untargeted effects or enemy-owned plays.
var target: MinionInstance = null

## The card played or drawn (for ON_PLAYER_CARD_DRAWN, ON_PLAYER_MINION_SUMMONED, etc.)
var card: CardData = null

## Damage amount (for ON_HERO_DAMAGED).
var damage: int = 0

## Set to true by a handler to cancel the triggering action (e.g. Null Seal cancels a spell).
## Callers must check ctx.cancelled after fire() returns.
var cancelled: bool = false

## Set to true by a talent/passive handler to suppress the card's default on-play effect.
## Used when a talent fully replaces the base effect (e.g. piercing_void replaces deal_1_enemy_hero).
var override_effect: bool = false

## Convenience constructor — creates a context with event_type set.
static func make(type: int, p_owner: String = "") -> EventContext:
	var ctx := EventContext.new()
	ctx.event_type = type
	ctx.owner      = p_owner
	return ctx
