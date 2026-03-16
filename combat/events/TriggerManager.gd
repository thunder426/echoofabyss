## TriggerManager.gd
## Per-combat event dispatcher.  CombatScene owns one instance, created in _ready()
## and populated by _setup_triggers().  All game events flow through here.
##
## Usage:
##   # Register a handler (priority: lower fires first)
##   trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TURN_START, _my_handler, 10)
##
##   # Fire an event — all registered handlers are called in priority order
##   var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_TURN_START)
##   trigger_manager.fire(ctx)
##
##   # Unregister (e.g. a one-shot effect)
##   trigger_manager.unregister(Enums.TriggerEvent.ON_PLAYER_TURN_START, _my_handler)
##
##   # Clear all listeners between combats
##   trigger_manager.clear()
##
## Adding a new event type:
##   1. Add a value to Enums.TriggerEvent.
##   2. Fire it from CombatScene at the correct moment.
##   3. Register handlers in CombatScene._setup_triggers().
##
## Adding a new handler (e.g. a new talent):
##   1. Write a method func _handler_my_talent(ctx: EventContext) -> void in CombatScene.
##   2. In _setup_triggers(): if _has_talent("my_talent"): trigger_manager.register(EVENT, _handler, priority)
##   No other files need to change.
class_name TriggerManager
extends RefCounted

# ---------------------------------------------------------------------------
# Internal listener entry
# ---------------------------------------------------------------------------

class _Entry:
	var handler:  Callable
	var priority: int
	func _init(h: Callable, p: int) -> void:
		handler  = h
		priority = p

# event_type (int) → Array[_Entry] sorted ascending by priority
var _listeners: Dictionary = {}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Register a handler for an event.
## Handlers with lower priority values fire first (0 = highest priority).
## Safe to call during fire() — new handlers won't receive the current event.
func register(event: int, handler: Callable, priority: int = 0) -> void:
	if not _listeners.has(event):
		_listeners[event] = []
	var entries: Array = _listeners[event]
	entries.append(_Entry.new(handler, priority))
	entries.sort_custom(func(a: _Entry, b: _Entry) -> bool:
		return a.priority < b.priority)

## Unregister a specific handler.  Safe to call during fire().
func unregister(event: int, handler: Callable) -> void:
	if not _listeners.has(event):
		return
	var entries: Array = _listeners[event]
	for i in entries.size():
		if entries[i].handler == handler:
			entries.remove_at(i)
			return

## Fire an event.  Calls every registered handler in priority order.
## Iterates a snapshot so handlers may register / unregister safely.
## If ctx.cancelled is set by a handler, remaining handlers still run
## unless you break out in the caller (see _on_enemy_spell_cast for example).
func fire(ctx: EventContext) -> void:
	if not _listeners.has(ctx.event_type):
		return
	# Snapshot so mutations during iteration are safe
	var snapshot: Array = _listeners[ctx.event_type].duplicate()
	for entry in snapshot:
		if entry.handler.is_valid():
			entry.handler.call(ctx)

## Remove all registered listeners.  Call between combats if reusing the instance.
func clear() -> void:
	_listeners.clear()
