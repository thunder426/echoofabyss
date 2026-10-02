---
id: "121"
title: Synchronous AI profiles: guard against real awaits now, then strip the ~360 no-op awaits
status: backlog
area: ai
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item G5 (`design/refactors/ARCHITECTURE_ROADMAP.md` §G). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### Every AI action is a coroutine that never waits

- `rg -o '\bawait\b' enemies/ai | wc -l` gives 360: 359 in code and 1 in a doc comment (CombatProfile.gd:17). The most are in CombatProfile (36), RiftStalker (30), VoidWarband (25), VoidHerald (23) and SpellBurnPlayer (23). 30 are in the scored stack, which task 120 deletes.
- The only thing they wait on returns at once:
  - Pacer.gd:9-10 `func after_action(_kind: String) -> void:` / `pass`;
  - StateAgent.gd:93-95 `func _done(r: CommandResult, kind: String) -> bool:` / `await pacer.after_action(kind)`, which every `commit_*` and `do_attack_*` goes through.
- `StateAgent.setup` takes an optional pacer (:16-19, `p_pacer: Pacer = null`). None of its 6 callers passes one: CombatSim.gd:65 and :67, EnemyTurnRunner.gd:57, ParityTests.gd:129, LiveSmokeTests.gd:208, TestHarness.gd:358.
- The drivers await the phases:
  - EnemyTurnRunner.gd:38 `await _profile().play_phase()` and :42;
  - CombatSim.gd:245, :249, :255, :265, :273, and :435 (`run_many` awaits `run`);
  - tests: LiveSmokeTests.gd:219 and :221, CommandTests.gd:707, :727 and :732.
- CombatSim's header has to explain that the awaits resolve at once (CombatSim.gd:8-12).

### Why it matters

- **Task 045.** With a pacer that really waited (LivePacer), the live enemy sometimes skipped the rest of a profile loop on resume. F6 parity failed in 4 of 18 loaded runs at `Engine.time_scale` 10, 1 of 18 at 1.0, and 0 of 18 with the base Pacer. The root cause was never isolated: a 1,600-iteration minimal script didn't reproduce it. So it isn't proven that one new await brings the bug back, but nothing stops one being added.
- **No guard.** Lint L6 checks only CombatState.gd: tools/lint/lint_engine.py:272-273 `wait_re = re.compile(r"\bawait\b|get_tree\(|create_timer\(")` / `for i, raw in enumerate(read(STATE), start=1):`. Today `enemies/ai` and EnemyTurnRunner.gd have no real wait: no `get_tree(`, `create_timer(`, `process_frame`, `.timeout`, `Engine.` or signal await (0 hits).
- **Look-ahead (Q7b).** A look-ahead runs a profile on a cloned state inside one decision. That needs plain synchronous calls.

## Decision (owner, 2026-10-01)

Q7b: look-ahead is planned, so "profiles must be synchronous and read only through `CombatAgent`". This task does the first half; task 122 does the second.

## Proposed fix

### Phase 1: guard (S; no dependencies, can land first)

1. In `scan_engine_waits` (L6, lint_engine.py:270-276), add a scan over `enemies/ai/**/*.gd` and `combat/board/EnemyTurnRunner.gd`. Flag:
   - `get_tree(`, `create_timer(`, `process_frame`, `.timeout`, `Engine.`;
   - an `await` whose operand isn't a call, i.e. a signal (`\bawait\s+(?![\w.]+\s*\()`);
   - any `await` in `enemies/ai/Pacer.gd`.

   0 hits today, so the rule lands green.
2. Drop StateAgent.setup's unused `p_pacer` parameter (`pacer = Pacer.new()`), so a waiting pacer can't be injected from outside `enemies/ai`.
3. Document the rule in the lint header (lint_engine.py:30-34) and design/TESTING.md.

### Phase 2: strip the awaits (M; after tasks 118, 120 and 139)

Bottom-up in one commit, callee before caller, so the analyzer never sees a coroutine called without `await`. `load_all_scripts` in run_checks catches leftovers.

4. StateAgent: delete the `pacer` field; `_done` becomes `return r.ok and _state.winner.is_empty()`; `commit_*` and `do_attack_*` become plain functions. Delete `enemies/ai/Pacer.gd` and its `.uid`.
5. CombatProfile and `enemies/ai/profiles/`: remove every `await`.
6. Drivers and tests:
   - EnemyTurnRunner.run_turn calls the phases plainly (CombatScene.gd:404 already calls `enemy_turn.run_turn()` without await);
   - CombatSim.run, run_many and replay become synchronous;
   - LiveSmokeTests :219/:221 and CommandTests :707, :727, :732 drop their awaits.
7. Optional, same phase: sweep the now-redundant `await`s on `sim.run` / `run_many` in `debug/` and the tests (about 55 sites, 43 in ScenarioTests). A redundant await is only an analyzer warning, and the gate greps `SCRIPT ERROR`.
8. L6 becomes "no `await` in `enemies/ai/**` or EnemyTurnRunner.gd".
9. Docs:
   - ARCHITECTURE.md invariant #4: "agents run on the base `Pacer`" becomes "profiles are synchronous (lint L6)";
   - the AI-table row "`enemies/ai/StateAgent.gd` (+ `Pacer.gd`)", the EnemyTurnRunner row and the drivers paragraph (:75, :105 and :234 at `404b51c`);
   - CombatSim's header (:8-12), EnemyTurnRunner's header (:8-12), and the `await play_phase_two_pass()` example in CombatProfile's header (:17).

## Verification

- Phase 1, negative check: temporarily add `await get_tree().process_frame` to a profile, confirm L6 fails, revert. Record it in the summary.
- Phase 2, grep gate: `rg -n '\bawait\b' enemies/ai combat/board/EnemyTurnRunner.gd` → nothing.
- Phase 2: run LiveSmoke three times; its seeded fight gives the same event count each time (task 045: 551 events × 3).
- `tools/run_checks.sh` green after each phase. Parity's live enemy already resolves synchronously.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4; request 3 and 4 explicitly) diffs empty (design/TESTING.md 'Refactor / extraction work'). Every await already completes synchronously.

## Related

- Depends on: task 118 (roadmap G2) — fewer helper copies to strip (Phase 2).
- Depends on: task 120 (roadmap G4) — deletes the scored stack and its 30 awaits (Phase 2).
- Depends on: task 139 (roadmap J3) — per-profile decision probes catch a loop broken while stripping (Phase 2).
- Related: task 140 (roadmap J4) — extends L6's ban from CombatState.gd to all `RULES_FILES`. This task extends it to `enemies/ai`; share one rule function.
- Related: task 122 (roadmap G7) — the other half of Q7b: profiles read only through CombatAgent.
- Related: task 045 — measured the resume bug and made the live enemy synchronous.
- Related: task 141 (roadmap J5) — gives CombatSim.run a config. Both edit `run`'s body; land in either order.
- Related: task 072 — uses the current `await agent.commit_*` pattern; Phase 2 strips it.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item G5.
  - Re-checked at `404b51c`: 360 awaits (359 code), the no-op Pacer, 6 `StateAgent.setup` callers with no pacer, L6 scanning only CombatState.gd, 0 real waits in `enemies/ai`.
  - The roadmap's "brings back the task-045 bug" is softened: 045 never isolated the cause.
  - Added: dropping `p_pacer` in Phase 1.

## Summary

_(filled in at /task-done)_
