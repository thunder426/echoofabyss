---
id: "107"
title: Effect handler registry — EffectType → handler, migrated one family at a time
status: backlog
area: combat
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item D4 (`design/refactors/ARCHITECTURE_ROADMAP.md` §D). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### One central file for every effect type

- EffectResolver.gd is 754 lines. Its 45 EffectTypes are dispatched by two matches:
  - `_execute` (`match step.effect_type:` at :36, 29 arms through :425) for hero / global effects, each of which checks its conditions once with `target = null` and returns;
  - `_apply` (:449, 17 arms through :617) for per-target effects, reached through `TargetResolver.resolve` and a per-target condition check (:428-432).
- DESTROY has an arm in both (:407 and :601). APPLY_ARMOUR_BREAK has an extra `include_hero` step after the target loop (:437-441).
- Shared helpers sit in the same file: `_amount` (:622), `_race_from_string` (:670), `_build_damage_info` (:683), `_path_of_corruption_amplify` (:696), `_path_of_corruption_apply_corruption` (:722), `_dark_channeling_dmg` (:739).

### The vocabulary grows per card and per hero

- 10 types are hero-tagged in the enum comments (EffectStep.gd:12-58). Korrath has 4: BUFF_ARMOUR, APPLY_ARMOUR_BREAK, GRANT_ATTACK_RIDER, ADD_HERO_ARMOUR. Seris has 6: GAIN_FLESH, SPEND_FLESH, SPEND_FLESH_UP_TO, GRANT_KILL_STACKS, GAIN_FORGE_COUNTER, COPY_LAST_TURN_SPELLS_FROM_GRAVEYARD.
- 19 types are used by exactly one card or rule (e.g. CANCEL_OPPONENT_SPELL for Silence Trap, TAX_OPPONENT_SPELLS_NEXT_TURN for Spell Taxer, ADD_HERO_ARMOUR for Lord Commander). 2 are used by no content: GRANT_MANA and GRANT_ESSENCE; only EffectResolver.gd:123 / :128 and BoardEvaluator.gd:166 name them. So 21 of 45 types serve at most one card.
- Every new type edits the same file that tasks 050, 063, 065, 092, 097 and the SideState work (083, 084) also edit.

### Effect metadata is re-derived elsewhere

Callers outside the resolver re-derive what a step does:
- `CombatHandlers._spell_deals_damage` (:1997-2006), for Dark Channeling: DAMAGE_HERO or DAMAGE_MINION only, not VOID_BOLT.
- `CombatProfile._spell_needs_board_slot` (:360-368): SUMMON, or HARDCODED with a hardcoded-id list.
- `BoardEvaluator._estimate_step_value` (:142-173): values 15 types and returns 0.0 for the rest.

Nothing guarantees that every EffectType has a handler. A type with no arm in either match falls through `_execute` into target resolution and `_apply`, where nothing matches, so it silently does nothing.

### Why it's low priority

It changes no behaviour and fixes no bug. It pays off when the next hero adds effect types. Schedule it before that, and after task 105 (handlers take a typed EffectStep only) and task 050 (rewrites the DESTROY, trap and environment arms).

## Decision (owner, 2026-10-01)

Q7a: "Keep BoardEvaluator + ScoringWeights as the seed of the look-ahead evaluation function; delete ScoredCombatProfile and the 4 scored profiles" (task 120). So any AI value metadata on handlers is limited to what BoardEvaluator needs. No scoring hooks for the deleted profiles.

## Proposed fix

1. **Handler base classes** in `combat/effects/handlers/`:
   - `EffectHandler` (RefCounted): `func execute(step: EffectStep, ctx: EffectContext) -> void`. Global handlers check `step.conditions` with `target = null` themselves, as the `_execute` arms do today.
   - `TargetedEffectHandler`: its default `execute` runs `TargetResolver.resolve(step, ctx)`, then per target `ConditionResolver.check_all(step.conditions, ctx, t)`, then `apply(step, t, EffectResolver._amount(step, ctx), ctx)`. That keeps today's order, including evaluating `_amount` per target (:428-432).
   - Handlers hold no state and no reference to a CombatState, so one shared instance per type is safe for parallel states (task 049, task 130).
2. **`EffectRegistry`**: a static Dictionary EffectType → handler, built once. `_execute` looks a type up there first and falls back to the existing matches for unmigrated types. `run()` keeps the per-run resets (:16-17) and the Dark Channeling consume (:27-28).
3. **Helpers.** Give the shared helpers public names (`amount_for`, `build_damage_info`, …) as statics on EffectResolver or a small `EffectMath`, so handlers in other files don't call underscore-private functions.
4. **Migrate one family per phase** (below). Move each arm verbatim and delete it from the match in the same commit. Owner gates (`ctx.owner == "player"` at :147, :335, :344, :350, :358, :399) move as they are. Tasks 063, 092 and 097 remove them; whichever lands second rebases.
5. **Finish.** Delete the fallback matches and add a completeness probe. If content still doesn't use GRANT_MANA / GRANT_ESSENCE then, delete those two types and BoardEvaluator.gd:166's arm instead of migrating them. If task 092 has fixed GRANT_ESSENCE's side gate by then, the deletion takes that fix with it; check first that no new content uses them.

## Phases

Each phase is independently shippable, behaviour-neutral and gated on its own run (verification below). Open a sub-task per phase when starting, as LIVE_SIM_UNIFICATION_PLAN did.

1. **Registry and disruption family (M).** Steps 1–3, then COUNTER_SPELL, CANCEL_OPPONENT_SPELL, BLOCK_OPPONENT_TRAPS_THIS_TURN, TAX_OPPONENT_SPELLS_NEXT_TURN, QUEUE_OPPONENT_MANA_DRAIN_NEXT_TURN.
2. **Cards and resources (S).** DRAW, ADD_CARD, TUTOR, MOD_LAST_ADDED_COST, MOD_HAND_CARDS_COST, COPY_OWNER_RUNES_TO_HAND, GRANT_MANA, GRANT_ESSENCE (or delete, step 5), GROW_MANA_MAX, CONVERT_RESOURCE, VOID_MARK, HEAL_HERO, ADD_HERO_ARMOUR, HARDCODED.
3. **Hero families (S).**
   - A Seris file: GAIN_FLESH, SPEND_FLESH, SPEND_FLESH_UP_TO, GAIN_FORGE_COUNTER, GRANT_KILL_STACKS, COPY_LAST_TURN_SPELLS_FROM_GRAVEYARD. If task 097 (SerisModule) has landed, these call the owner's module.
   - A Korrath file: BUFF_ARMOUR, APPLY_ARMOUR_BREAK (its handler overrides `execute` to add the `include_hero` step after the target loop), GRANT_ATTACK_RIDER.
4. **Stats and damage (S).** BUFF_ATK, BUFF_HP, GRANT_KEYWORD, GRANT_CRITICAL_STRIKE, PURGE, CORRUPTION, GRANT_ON_DEATH_SUMMON, HEAL_MINION, HEAL_MINION_FULL, DAMAGE_HERO, DAMAGE_MINION, VOID_BOLT.
5. **Board family and cleanup (S, after task 050).** SUMMON, SACRIFICE, KILL_MINION, DESTROY (one handler covering both today's scope arms, on 050's `remove_trap` / `destroy_environment`), PLACE_RUNE_ON_OPPONENT (on 050's `place_trap` if it added one). Delete the fallback matches; add the completeness probe.
6. **Metadata queries (S).**
   - Handlers expose `deals_damage(step) -> bool` and `needs_board_slot(step) -> bool` (default false). `CombatHandlers._spell_deals_damage` and `CombatProfile._spell_needs_board_slot` read them.
   - Keep today's answers exactly: `deals_damage` is true for DAMAGE_HERO and DAMAGE_MINION only. Whether VOID_BOLT should consume Dark Channeling crits is a design question, not part of this refactor.
   - BoardEvaluator: either keep `_estimate_step_value`'s own match or read a `value_estimate(step, friendly, opponent, w)` hook on the 15 types it values today, whichever is smaller. Nothing beyond what BoardEvaluator reads (Q7a).

## Verification

Per phase:
- Before moving a family, list its types and find a probe for each (CardEffectTests has 92 probe functions). Add a probe for any type without one first, and see it pass before the move. Before phase 5, task 050's Cyclone / Hurricane / Flesh Rune / PhaseTransition probes must exist.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1–4) diffs empty (design/TESTING.md 'Refactor / extraction work').

Final phase:
- New probe in `debug/tests/CardEffectTests.gd`, `_effect_registry_complete`: every value in `EffectStep.EffectType.values()` has exactly one handler in `EffectRegistry`.
- `grep -n 'match step.effect_type' combat/effects/EffectResolver.gd` finds nothing.
- Phase 6: a probe that `_spell_deals_damage` gives the same answer as before for every spell in the database (compare against a list captured before the change).

## Related

- Depends on: task 105 (roadmap D2) — handlers take a typed EffectStep; with dict steps still around, every handler would need the dual-shape reads this task is meant to remove.
- Depends on: task 050 — rewrites the DESTROY / trap / environment arms (EffectResolver :407-425, :601-617) on a new engine API; phase 5 moves those arms after it.
- Related: task 063, task 065, task 092 (roadmap PS-void-marks), task 097 (roadmap B3) — remove owner gates in arms this task moves; whichever lands second rebases.
- Related: task 083 and task 084 (roadmap A1, A2) — SideState accessors replace the `player_*` / `enemy_*` reads inside the arms.
- Related: task 104 (roadmap D1) — its `EffectStep.DICT_KEYS` and vocabulary consts; the completeness probe is the EffectType counterpart of its checks.
- Related: task 106 (roadmap D3) — fail-loud defaults for the string dispatches; this task removes the silent fall-through for EffectTypes.
- Related: task 120 (roadmap G4) — keeps BoardEvaluator, whose `_estimate_step_value` is the only AI consumer of per-type metadata.
- Related: task 134 (roadmap I6) — a typed DamageInfo replaces the Dictionary `_build_damage_info` returns.
- Related: task 114 and task 129 (roadmap F1, I1) — the resolution stack wraps `EffectResolver.run`; coordinate the `run()` edits.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item D4.
  - Re-check: the "754-line match" is the whole file; dispatch is two matches (29 + 17 arms). 21 of 45 types serve at most one card (roadmap: ~6).
  - The AI metadata phase is no longer blocked: Q7a keeps BoardEvaluator only, so it shrinks to two boolean queries plus whatever BoardEvaluator reads.

## Summary

_(filled in at /task-done)_
