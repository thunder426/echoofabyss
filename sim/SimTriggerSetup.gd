## SimTriggerSetup.gd
## Wires TriggerManager handlers for headless simulation.
## Bridges the BuffSystem bus, then delegates every registration (trap routes,
## talents, hero passives, enemy passives, always-on handlers) to CombatSetup.
class_name SimTriggerSetup
extends RefCounted

func setup(sim: SimState) -> void:
	var h := CombatHandlers.new()
	h.setup(sim)
	sim._handlers = h

	# Mirror the sim-side `enemy_passives` array into the live-side
	# `_active_enemy_passives` field that CombatProfile reads via
	# `agent.scene.get("_active_enemy_passives")`. Phase 5 collapses the two.
	sim._active_enemy_passives.assign(sim.enemy_passives)

	var tm := TriggerManager.new()
	sim.trigger_manager = tm

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
