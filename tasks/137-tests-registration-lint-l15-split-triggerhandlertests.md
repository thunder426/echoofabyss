---
id: "137"
title: Tests: registration lint (L15) and split TriggerHandlerTests by subsystem; refresh TESTING.md
status: backlog
area: tooling
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item J1, plus the test-doc drift found while verifying it (J8) (`design/refactors/ARCHITECTURE_ROADMAP.md` §J). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### Tests are registered by hand

- Each test file lists its tests by hand in `static func run_all()`. Calls per run_all (excluding the `print` headers): DamageTypeTests 46, CardEffectTests 92, TriggerHandlerTests 188, CommandTests 30, ScenarioTests 41 = 397.
- RunAllTests.gd preloads the five files (:10-15) and calls each run_all by hand (:27-31, `DamageTypeTestsScript.run_all()` … `await ScenarioTestsScript.run_all()`).
- The only test marker is `TestHarness.begin_test` (TestHarness.gd:28 `static func begin_test(label: String, state: CombatState = null) -> bool:`). It only filters by label. Nothing checks that a new test function, or a new `*Tests.gd` file, is wired in.
- So a forgotten line silently drops a probe and the suite stays green. That gives false confidence on exactly the card or handler the probe was written for.
- **Latent today.** A call-graph check from each run_all over every function that calls `begin_test(` finds 0 unregistered tests (46 / 92 / 188 / 30 / 41). LiveSmoke's `_ready` (LiveSmokeTests.gd:18-28) calls all 5 of its scenarios.
- More test files are coming: ContentTests (task 104), MetaTests (task 052), AiBehaviourTests (task 139).

### TriggerHandlerTests.gd is one 3,504-line file

- 205 static funcs: `run_all` (:8-211), 188 tests and 16 helpers.
- CLAUDE.md:30 tells every new handler to ship a probe "in `CardEffectTests.gd` or `TriggerHandlerTests.gd`", so the file grows with every hero and champion.
- Its section comments already mark the subsystems:
  - Seris: Fleshbind (:213), Fleshcraft (:227), Demon Forge (:309), Corruption (:394);
  - Act 3 relics (:521);
  - Lord Vael talents and hero passive (:589), with the shared `_fire_*` helpers (:594-626);
  - Act 1–2 enemy passives (:890-1130);
  - champions: Act 1–2 (:1131-1441), Act 3–4 plus `champion_duel` (:1442-1868), with more `_fire_*` helpers (:1134, :1140, :1445, :1453, :1458);
  - Act 3–4 non-champion enemy passives (:1869-2092);
  - Korrath: Formation (:2093), Phase 2 (:2302), Iron Vanguard (:2357), Abyssal Breaker (:2547), Runic Knight (:2800), Armour (:3027), hero corruption (:3179);
  - engine state API (:3288), trap routing (:3414), the handler-order snapshot (:3472 `_HANDLER_ORDER_SNAPSHOT`, :3474).

### What changes from the roadmap

- **No auto-discovery of `test_*` methods.** Only DamageTypeTests' 46 tests use a `test_` prefix. The other 351 would need renaming, and a test missing the prefix would silently never run, which is the same failure mode. The lint below checks the real marker (a `begin_test(` call) instead.
- **Auto-teardown is task 049's** (step 3). This task doesn't duplicate it.

### Doc drift (J8)

- design/TESTING.md:
  - :8-9: Windows `GODOT` / `PROJECT` paths; the project is developed on macOS now.
  - :25: "Layered correctness tests (4 layers, ~500 assertions)".
  - :155-159: per-layer test counts 33 / 53 / 110 / 30 / 37; actual 46 / 92 / 188 / 30 / 41.
  - :172 "Full suite (all four layers)" and :460 "For all four, …". CommandTests is missing from the "Adding a new test" table (:451-458).
  - 18 links use `../echoofabyss/…`, but the repo root is the Godot root.
  - :80-85: the LiveSmoke section describes 2 of its 5 scenarios.
- CLAUDE.md:30: "~500 assertions across 4 layers". The 0.647 commit (`3009a60`) reports 1109.

## Proposed fix

### Part 1: registration lint L15

L15 is provisional; take the next free number if the landing order differs (L12 task 051, L13 task 050, L14 task 104).

1. Add rule L15 to `tools/lint/lint_engine.py`:
   - (a) Every `debug/tests/*Tests.gd` except LiveSmokeTests.gd and ParityTests.gd (they have their own scenes in run_checks.sh) is preloaded by RunAllTests.gd, and its `run_all()` is called from `_ready`.
   - (b) In each such file, every `static func` whose body calls `TestHarness.begin_test(` is reachable from `run_all` through same-file calls. Count a bare reference to the function name (a Callable) as a call too, so task 049's per-test runner shape (`_run(_fleshbind)` or similar) passes. The error names the function and its file:line.
   - (c) In LiveSmokeTests.gd, every func that calls `_check(` is reachable from `_ready`.
   - Use `strip_comment` so commented-out calls don't count.
2. Add L15 to the module docstring and to TESTING.md's lint table.

### Part 2: split TriggerHandlerTests.gd

3. Split along the section comments into files of at most about 800 lines. A pure move: test labels stay byte-identical, so `--filter` keeps working.

   | New file | From TriggerHandlerTests.gd |
   |---|---|
   | `SerisHandlerTests.gd` | :213-520 (Fleshbind … Corruption branch) |
   | `RelicHandlerTests.gd` | :521-588 |
   | `VaelHandlerTests.gd` | :589-889 (`void_echo` … mid-combat talent unlock) |
   | `EnemyPassiveHandlerTests.gd` | :890-1130 and :1869-2092 |
   | `ChampionHandlerTests.gd` | :1131-1868 (all champions, `champion_duel`) |
   | `KorrathHandlerTests.gd` | :2093-2799 (Formation, Phase 2, Iron Vanguard, Abyssal Breaker) |
   | `KorrathHeroTests.gd` | :2800-3287 (Runic Knight, Armour, hero corruption) |
   | `EngineStateTests.gd` | :3288-3504 (`_state_*`, `_sim_enemy_agent_sees_essence_discounts`, trap routing, the handler-order snapshot; keep the snapshot path unchanged) |

4. Move the shared helpers into a new `debug/tests/HandlerTestKit.gd` (or TestHarness): the `_fire_*` helpers, `_make_formation_card` (:2102), `_place_at` (:2123), `_make_korrath_test_human` (:2366), `_place_korrath_human` (:2375) and `_probe_trap` (:3416). Move the header comment (:1-4, the skipped handlers) to the kit.
5. Each new file has its own `run_all()` and prints its own header (`=== Layer 2: Trigger Handlers — Seris ===`, …).
6. Wrap each test in the per-test runner and teardown hook from task 049 step 3.
7. In RunAllTests.gd, preload and call the new files in the old order, so tests run in the same sequence as before. L15 enforces the wiring.
8. Delete TriggerHandlerTests.gd.

If task 081 (DL1) lands first, its four deleted probes (`spirit_conscription`, `champion_duel`) aren't moved.

### Part 3: docs

9. TESTING.md:
   - :8-9 → the macOS binary and project paths;
   - :25 → the real layer count and the current assertion count;
   - the layer table (:153-159) → one row per file with actual counts;
   - :172 and :460 → no "four";
   - "Adding a new test" (:451-458) → add CommandTests and the new handler files;
   - fix the 18 `../echoofabyss/` links;
   - LiveSmoke (:80-85) → all 5 scenarios.
10. CLAUDE.md:30: point the probe hint at the new handler files. Task 052 also updates the layer count on this line. Whichever lands second makes the line match RunAllTests.
11. `design/master_doc/ARCHITECTURE.md:317`: the test-suite row lists `{CardEffect,DamageType,TriggerHandler,Scenario}Tests.gd` and misses CommandTests; list the real files (the split handler files, CommandTests, and ContentTests / MetaTests / AiBehaviourTests where they exist).

Tasks 052, 104, 139 and 141 also edit TESTING.md's layer and tool tables. Whichever lands later makes the rows match RunAllTests.

## Verification

- RunAllTests' summary (pass / fail / skip) is identical before and after the split; record both. `--filter korrath`, `--filter champion` and `--filter fleshbind` also return the same counts.
- L15 negative checks (temporary local edits, recorded in the summary, then reverted). The lint must fail and name each one:
  - delete one call from a split file's run_all;
  - add an unwired `FooTests.gd` with one `begin_test` function;
  - remove one scenario call from LiveSmoke's `_ready`.
- `tools/run_checks.sh` green, including L15.
- Behaviour-neutral: tests, lint and docs only. No engine, AI, sim or content code changes, so the balance fingerprint can't move; no BalanceSimBatch run needed.

## Related

- Depends on: task 049 — step 3 adds the per-test runner and teardown hook the split files use. The split also changes which states are alive next to each other, which is only safe once each test tears its own state down.
- Related: task 052 — creates the MetaTests layer (L15 checks that it is registered) and updates CLAUDE.md's layer count.
- Related: task 104 (roadmap D1) — adds ContentTests and lint L14; until L15 lands, ContentTests is registered by hand.
- Related: task 139 (roadmap J3) — adds AiBehaviourTests, which L15 checks too.
- Related: task 081 (roadmap DL1) — deletes four probes; land it first and there are fewer to move.
- Related: task 086 (roadmap A3) — new trigger-system probes go into the split files.
- Related: task 140 (roadmap J4) — edits the same lint file (`strip_comment` escapes, L6–L10); rebase on whichever lands first.
- Related: tasks 050 (L13), 051 (L12), 087 (roadmap A4, L16), 111 (roadmap E4, L17), 122 (roadmap G7, L18), 099 (roadmap B7, L19), 131 (roadmap I3, L20), 058 (L21) — the other new lint rules; keep the numbering consistent.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item J1, with the J8 doc drift folded in. Re-checked at `404b51c`: counts 46 / 92 / 188 / 30 / 41, 0 unregistered tests today, `begin_test` at TestHarness.gd:28. Scope narrowed: no auto-discovery (351 renames), auto-teardown stays with task 049.

## Summary

_(filled in at /task-done)_
