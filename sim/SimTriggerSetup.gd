## SimTriggerSetup.gd
## Wires TriggerManager handlers for headless simulation.
## Registers sim-specific trap routing, then delegates all conditional
## handler registration (talents, hero passives, enemy passives) to CombatSetup.
class_name SimTriggerSetup
extends RefCounted

func setup(sim: SimState) -> void:
	var h := CombatHandlers.new()
	h.setup(sim)
	sim._handlers_ref = h

	var tm := TriggerManager.new()
	sim.trigger_manager = tm

	# ── Sim trap routing — lambdas using sim._check_and_fire_traps ───────────
	tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED,
		func(ctx: EventContext): sim._check_and_fire_traps(ctx.event_type, ctx.minion), 30)
	tm.register(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST,
		func(ctx: EventContext): sim._check_and_fire_traps(ctx.event_type), 30)
	tm.register(Enums.TriggerEvent.ON_ENEMY_ATTACK,
		func(ctx: EventContext): sim._check_and_fire_traps(ctx.event_type, ctx.minion), 30)
	tm.register(Enums.TriggerEvent.ON_HERO_DAMAGED,
		func(ctx: EventContext): sim._check_and_fire_traps(ctx.event_type), 10)

	# ── BuffSystem bus → TriggerManager bridge for corruption_removed ───────
	# Corrupt Detonation listens on ON_CORRUPTION_REMOVED; the bus is a global
	# singleton, so the sim subscribes (and unsubscribes on teardown).
	var buff_bus: Object = BuffSystem.bus()
	if buff_bus != null:
		var cb: Callable = Callable(sim, "_on_corruption_removed_bus")
		if not buff_bus.is_connected("corruption_removed", cb):
			buff_bus.connect("corruption_removed", cb)
		sim._buff_bus_callable = cb

	# ── Shared: talents, hero passives, enemy passives, always-on shared handlers
	CombatSetup.new().setup(
		tm, h, sim,
		sim.talents,
		sim.hero_passives,
		sim.enemy_passives
	)
