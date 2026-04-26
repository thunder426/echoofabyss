## Flesh.gd
## Seris's Flesh counter — primitives only (gain, spend, post-spend hook, UI hook).
##
## State (player_flesh, player_flesh_max) lives on CombatScene because SimState
## mirrors those vars and ~15 files read scene.player_flesh directly. The class
## mutates the scene's vars via the injected _scene reference; it's the
## behavior, not the data.
##
## Scope: primitives only. Higher-level Seris abilities (Soul Forge activate,
## Corrupt Flesh activate, Forged Demon summoning, Fiend Offering) stay on
## CombatScene — they orchestrate multiple primitives plus board logic.
##
## Forge follows the same shape — see Forge.gd. They share method names by
## convention, no shared interface declared (Rule of Three: 2 instances isn't
## enough evidence to extract an abstraction).
class_name Flesh
extends RefCounted

var _scene: Node2D = null

func _init(scene: Node2D) -> void:
	_scene = scene

## Gain Flesh, clamped to player_flesh_max. Logs; UI refreshes via the
## CombatState.flesh_changed signal that fires from the property setter.
func gain(amount: int = 1) -> void:
	if amount <= 0:
		return
	var before: int = _scene.player_flesh
	_scene.player_flesh = min(_scene.player_flesh + amount, _scene.player_flesh_max)
	if _scene.player_flesh == before:
		return
	_scene._log("  Flesh +%d (%d/%d)" % [_scene.player_flesh - before, _scene.player_flesh, _scene.player_flesh_max], CombatLog.LogType.PLAYER)

## Try to spend Flesh. Returns true on success. Callers must check the result.
func spend(amount: int) -> bool:
	if amount <= 0 or _scene.player_flesh < amount:
		return false
	_scene.player_flesh -= amount
	_scene._log("  Flesh -%d (%d/%d)" % [amount, _scene.player_flesh, _scene.player_flesh_max], CombatLog.LogType.PLAYER)
	on_spent(amount)
	return true

## Post-spend hook — Flesh Bond aura (Abyssal Forge talent) draws a card per
## spend. Per design: one draw per spend event, not scaled by the amount —
## hence `_amount` is intentionally unused.
func on_spent(_amount: int) -> void:
	var has_flesh_bond := false
	for m in _scene.player_board:
		if "flesh_bond" in m.aura_tags:
			has_flesh_bond = true
			break
	if not has_flesh_bond:
		return
	if _scene.turn_manager != null:
		_scene.turn_manager.draw_card()
		_scene._log("  Flesh Bond: drew a card.", CombatLog.LogType.PLAYER)

## (UI refresh on Flesh change is now handled by CombatScene._on_state_flesh_changed,
## a subscriber to CombatState.flesh_changed. The old Flesh.on_changed() hook
## is gone — this comment marks where it used to live.)
