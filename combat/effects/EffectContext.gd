## EffectContext.gd
## Carries all runtime state an effect resolver needs to execute a step.
## Created at the call site and passed through EffectResolver → TargetResolver → ConditionResolver.
class_name EffectContext
extends RefCounted

## The CombatScene node (or SimState in headless sim). Typed as Object so that
## both Node subclasses and RefCounted subclasses can be assigned.
## Duck-type: EffectResolver and ConditionResolver call methods on it directly.
var scene: Object = null

## Who owns this effect — "player" or "enemy".
var owner: String = "player"

## The minion whose card defines this effect (on-play source, passive owner).
## Null for spells and traps.
var source: MinionInstance = null

## Player-chosen target for targeted battle cries / spells.
## Null for untargeted effects or AI paths (TargetResolver falls back to random).
var chosen_target: MinionInstance = null

## AI-chosen non-minion target (TrapCardData or EnvironmentCardData).
## Set by EnemyAI before emit; read by TargetResolver for SINGLE_CHOSEN_TRAP_OR_ENV scope.
var chosen_object = null

## The minion that caused a trap or rune aura to fire (attacker, newly summoned enemy, etc.).
var trigger_minion: MinionInstance = null

## The minion that just died — populated in on-death passive contexts.
var dead_minion: MinionInstance = null

## True when the effect was fired by a rune aura (used for Void Bolt projectile origin).
var from_rune: bool = false

## Card id that originated this effect run (e.g. "dark_empowerment" for a spell cast,
## or a minion's card id for on-play effects). Used as the default source_tag for
## buff steps that don't specify one, so BuffVfxRegistry can route per-card preludes.
var source_card_id: String = ""

## The rune that owns this effect run (set by _apply_rune_aura). Null for non-rune effects.
## Allows SOURCE_RUNE-scoped DESTROY steps to remove the rune that's firing (e.g. Flesh Rune
## self-destruct when upkeep Flesh is unavailable).
var source_rune: TrapCardData = null

## Seris — Flesh spent by the current effect run. Reset at the start of each EffectResolver.run().
## SPEND_FLESH and SPEND_FLESH_UP_TO steps accumulate into this; later steps read it via
## the "flesh_spent_this_cast" condition or the "flesh_spent" multiplier_key.
var flesh_spent_this_cast: int = 0

## The last CardInstance added to a hand by a step in the current run (TUTOR or ADD_CARD).
## Lets a follow-up step (e.g. MOD_LAST_ADDED_COST) operate on the just-added copy.
## Reset at the start of each EffectResolver.run() so it never leaks across cards.
## Null when no add-card step has run yet (or the add was burned by hand-cap).
var last_added_instance: CardInstance = null

## Free-form Dictionary carrying runtime parameters chosen at cast time but not
## expressible as a single chosen_target — e.g. Rally the Ranks's race pick when
## the target is dual-tag (HUMAN+DEMON). Caller (cast_player_targeted_spell, sim
## commit_play_spell) merges its `extra_cast_data` arg into this field. Conditions
## and steps read via ctx.extra_cast_data.get("key", default). Reserved keys so
## far: "rally_race" ("human" | "demon"). Future runtime-decided params land here.
var extra_cast_data: Dictionary = {}

# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

static func make(scene: Object, owner: String) -> EffectContext:
	var ctx       := EffectContext.new()
	ctx.scene     = scene
	ctx.owner     = owner
	return ctx
