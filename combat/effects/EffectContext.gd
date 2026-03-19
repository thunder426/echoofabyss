## EffectContext.gd
## Carries all runtime state an effect resolver needs to execute a step.
## Created at the call site and passed through EffectResolver → TargetResolver → ConditionResolver.
class_name EffectContext
extends RefCounted

## The CombatScene node. Typed as Node to avoid circular preload issues;
## cast to CombatScene at the call site if direct method access is needed.
var scene: Node = null

## Who owns this effect — "player" or "enemy".
var owner: String = "player"

## The minion whose card defines this effect (on-play source, passive owner).
## Null for spells and traps.
var source: MinionInstance = null

## Player-chosen target for targeted battle cries / spells.
## Null for untargeted effects or AI paths (TargetResolver falls back to random).
var chosen_target: MinionInstance = null

## The minion that caused a trap or rune aura to fire (attacker, newly summoned enemy, etc.).
var trigger_minion: MinionInstance = null

## The minion that just died — populated in on-death passive contexts.
var dead_minion: MinionInstance = null

# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

static func make(scene: Node, owner: String) -> EffectContext:
	var ctx       := EffectContext.new()
	ctx.scene     = scene
	ctx.owner     = owner
	return ctx
