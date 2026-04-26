## Forge.gd
## Seris's Forge Counter — primitives only (tick, reset, gated gain, UI hook).
##
## State (forge_counter, forge_counter_threshold) lives on CombatScene because
## SimState mirrors those vars and several files read them directly. The class
## mutates the scene's vars via the injected _scene reference.
##
## Scope: primitives only. The actual Forged Demon summon (board lookup,
## Abyssal Forge aura grants) stays on CombatScene as _summon_forged_demon —
## it orchestrates board state plus aura logic, not just the counter.
##
## Mirrors Flesh.gd's method shape by convention (gain/spend, on_changed).
## No shared interface declared yet — Rule of Three.
class_name Forge
extends RefCounted

var _scene: Node2D = null

func _init(scene: Node2D) -> void:
	_scene = scene

## Tick the Forge Counter. Returns true if it hit threshold (caller summons
## the Forged Demon and calls reset()). UI refreshes via the
## CombatState.forge_changed signal that fires from the property setter.
func tick(amount: int = 1) -> bool:
	if amount <= 0:
		return false
	_scene.forge_counter += amount
	_scene._log("  Forge Counter +%d (%d/%d)" % [amount, _scene.forge_counter, _scene.forge_counter_threshold], CombatLog.LogType.PLAYER)
	return _scene.forge_counter >= _scene.forge_counter_threshold

## Reset to 0 (after a Forged Demon summon).
func reset() -> void:
	_scene.forge_counter = 0

## Public Forge Counter gain for declarative GAIN_FORGE_COUNTER steps and any
## future passive sources. Wraps tick + auto-summon + reset so callers don't
## have to repeat the threshold logic. No-op if Soul Forge is not active
## (Demon Forge branch gate). Returns true if a Forged Demon was summoned.
func gain(amount: int = 1) -> bool:
	if amount <= 0 or not _scene._has_talent("soul_forge"):
		return false
	var summoned := false
	# Loop in case amount > threshold (e.g. Forgeborn Tyrant's +3 with threshold 2 → multi-summon).
	while amount > 0:
		var step := mini(amount, _scene.forge_counter_threshold)
		amount -= step
		if tick(step):
			_scene._log("  Soul Forge: threshold reached.", CombatLog.LogType.PLAYER)
			_scene._summon_forged_demon()
			reset()
			summoned = true
	return summoned

## UI hook — refresh the resource bar after any Forge change.
func on_changed() -> void:
	if _scene._player_hero_panel != null and _scene._player_hero_panel.resource_bar != null:
		_scene._player_hero_panel.resource_bar.refresh()
