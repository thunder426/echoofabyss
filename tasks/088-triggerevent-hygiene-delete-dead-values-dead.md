---
id: "088"
title: TriggerEvent hygiene: delete dead values and the dead TurnPhase enum, fix stale trigger comments, document trap vs rune conventions
status: backlog
area: combat
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item A5 (a new candidate from grooming, `design/refactors/ARCHITECTURE_ROADMAP.md` §A). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The trigger enum and the comments around it mislead whoever adds the next trigger or trap. This task is behaviour-free and is the first step of task 086 (side-neutral trigger events): its shim tables should cover only live values, and the two trap/rune conventions should be written down before 086 replaces them.

### Dead values

`grep -rnw --include='*.gd' <name> .` outside Enums.gd finds nothing for:
- `ON_PLAYER_ENVIRONMENT_PLACED` (Enums.gd:75);
- `ON_COMBAT_START` (:112) and `ON_COMBAT_END` (:113);
- `enum TurnPhase` (:155-161).

design/master_doc/DESIGN_DOCUMENT.md:447, :466 and :467 still list the three values. The same list says `ON_HERO_DAMAGED` fires when "Any hero takes damage" (:458); it is the player hero only (Enums.gd:93; the enemy's is `ON_ENEMY_HERO_DAMAGED`, :94).

No trigger int is persisted: no `.tres`, `.tscn` or `.json` in the repo stores `trigger` / `aura_trigger`, and nothing compares TriggerEvent values by order. Deleting a value shifts the ids after it; `TriggerManager.dump_order` sorts by id but prints names (TriggerManager.gd:91-102), and none of the deleted values has a registration, so debug/tests/snapshots/handler_order.txt doesn't change.

### Fired with no production listener

- `ON_PLAYER_SPARK_CONSUMED`: fired at CombatState.gd:2226-2227 and :3079; nothing registers on it (it isn't in handler_order.txt). Its enemy twin has four registry listeners (CombatSetup.gd:371, :394, :439, :477).
- `ON_ENEMY_HERO_DAMAGED`: fired at CombatState.gd:2049; listeners only in DamageTypeTests.gd:533 and :567.
- `ON_PLAYER_TRAP_PLACED` / `ON_ENEMY_TRAP_PLACED`: fired at CombatState.gd:2697-2698; listeners only in CommandTests.gd:349-352 ("play_trap fires ON_*_TRAP_PLACED on both sides (B6)").

Harmless, but a reader assumes they are wired.

### Stale comments

- Enums.gd:52-57: "Add a new value here when a new trigger point is needed, fire it from CombatScene, and register handlers in _setup_triggers()."
- Enums.gd:89: `ON_ENEMY_TRAP_PLACED, # Enemy plays a trap (stub — enemy traps not yet implemented)`. It fires for every enemy trap or rune placement (CombatState.gd:2697-2698), and the enemy places runes in f2_c, f4_b and f5_a.
- TriggerManager.gd:1-27: "CombatScene owns one instance, created in _ready() and populated by _setup_triggers()", and the how-to steps "Fire it from CombatScene" / "Register handlers in CombatScene._setup_triggers()" / "Write a method … in CombatScene". Registration lives in `CombatSetup.setup` and its `_REGISTRY`; firing is in CombatState and CombatManager.
- CombatManager.gd:83-84: "ON_ENEMY_ATTACK stays single-phase pre-damage (fired from CombatScene's enemy attack path)". It is fired by `CombatState._fire_enemy_attack_declared` (:3086-3097).
- CombatState.gd:1613-1614: "live's EnemyAI.active_traps / active_environment forward here". EnemyAI was renamed EnemyTurnRunner in Phase 4 and holds no trap state.

### Two trigger conventions, documented nowhere

- Rune aura triggers (`aura_trigger`, `aura_extra_trigger`, `aura_secondary_trigger`) are written from the owner's point of view and mirrored for an enemy owner: `rune.aura_trigger if owner == "player" else Enums.mirror_trigger(…)` (CombatState.gd:787, :799, :804).
- Trap triggers are absolute and matched exactly: `if not trap.is_rune and trap.trigger == trigger` (:1041; the route comment at :1005-1006 says "no mirroring").
- TrapCardData.gd says neither (:3-4 "activate automatically when their trigger condition is met during the enemy's turn", :8-10, :32-47).

All four trap cards use player-view triggers: `hidden_ambush` and `smoke_veil` `ON_ENEMY_ATTACK` (CardDatabase.gd:2117, :2128), `silence_trap` `ON_ENEMY_SPELL_CAST` (:2139), `death_trap` `ON_ENEMY_MINION_SUMMONED` (:2150). An enemy-held copy therefore never springs. Task 086 phase 5 fixes that; until then the convention has to be documented so nobody authors an enemy trap the same way and expects it to work.

### Ownership of the comment fixes

Task 082 (roadmap A0) assigns these trigger-system comments here: Enums.gd:89, CombatManager.gd:82-84, the TriggerManager.gd header and Enums.gd:56-57. Task 086 owns CombatHandlers.gd:443-445 and Enums.gd:134-136 (both change meaning there). This task doesn't touch task 055's list of stale comments. Task 114 (roadmap F1, step 7) and task 131 (roadmap I3, step 5) also list the TriggerManager.gd header because they edit that file; it is this task's per 082's assignment, and whichever of the three lands first rewrites it while the others skip it.

## Proposed fix

1. Delete `ON_PLAYER_ENVIRONMENT_PLACED`, `ON_COMBAT_START`, `ON_COMBAT_END` and `enum TurnPhase` from Enums.gd. Remove them from DESIGN_DOCUMENT.md's trigger list (:447, :466-467) and correct its `ON_HERO_DAMAGED` line (:458).
2. Rewrite Enums.gd:89, and mark `ON_PLAYER_SPARK_CONSUMED`, `ON_ENEMY_HERO_DAMAGED` and both TRAP_PLACED values "fired; no production listener today".
3. Rewrite the Enums.gd:52-57 header and the TriggerManager.gd header (:1-27): add a value to `TriggerEvent`, fire it from CombatState (or CombatManager for attack resolution), register handlers in `CombatSetup.setup` or its `_REGISTRY`. Point at ARCHITECTURE.md's "Trigger event system" section.
4. Fix CombatManager.gd:83-84 (fired by `CombatState._fire_enemy_attack_declared`) and CombatState.gd:1613-1614 (the enemy's trap and environment fields live here; nothing forwards to them).
5. TrapCardData: document that `trigger` is an absolute event matched exactly through `TRAP_ROUTES`, so an enemy-owned standard trap needs an `ON_PLAYER_*` trigger; and that the `aura_*` triggers are written from the owner's view and mirrored for an enemy owner. Fix :3-4 to say traps spring on the opponent's actions.
6. ARCHITECTURE.md "Trigger event system" (:151-153): one sentence on the two conventions, noting that task 086 replaces them with one.

## Verification

- `tools/run_checks.sh` green.
- debug/tests/snapshots/handler_order.txt unchanged (the snapshot test, TriggerHandlerTests.gd:3474-3504, passes without regeneration).
- Grep check recorded in the task: `grep -rnw --include='*.gd' -e ON_PLAYER_ENVIRONMENT_PLACED -e ON_COMBAT_START -e ON_COMBAT_END -e TurnPhase .` finds nothing, and neither does the same grep over `design/`.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, `--act 1` through `--act 4`; the enum renumbering reaches every trigger dispatch) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Related: task 086 (roadmap A3): depends on this task; its shim maps only live values, and its phases 3 and 5 replace the two conventions documented here.
- Related: task 082 (roadmap A0): assigned these comment fixes here; its verdict-table row 23 (dead or unheard events) closes with this task.
- Related: task 132 (roadmap I4): deletes dead signals and buses; the TriggerManager.gd header is fixed here, not there.
- Related: task 114 (roadmap F1) and task 131 (roadmap I3): both edit TriggerManager.gd and list its header; the first of 088 / 114 / 131 to land fixes it.
- Related: task 055: the other stale-comment list (CombatState talents, EffectStep, CombatUI headers); no overlap.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item A5 (new). Added the DESIGN_DOCUMENT.md trigger list, which names the dead values and mislabels `ON_HERO_DAMAGED`.

## Summary

_(filled in at /task-done)_
