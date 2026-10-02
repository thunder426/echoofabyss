---
id: "099"
title: Public engine API for members used outside CombatState, with a ratchet lint on state._x (L19)
status: backlog
area: combat
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item B7 (`design/refactors/ARCHITECTURE_ROADMAP.md` §B, direction 4). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The `_` prefix on CombatState members no longer means private. Code outside the engine reaches underscore members all the time, so a reader can't tell which members are the engine's real API, and a refactor can't tell which members it may change freely.

### Counts at `404b51c`

Method: `\bstate\._(\w+)` on comment-stripped lines of every tracked `.gd` file except `combat/board/CombatState.gd` and `debug/` (it also matches `ctx.state._x` and `agent.state._x`).

- **All non-test code:** 144 distinct members, 486 accesses.
- **`st._` aliases** add 28 more accesses in 5 files: CombatHandlers (the `_summon_enemy_champion` match arm), CombatSetup, PhaseTransition, CombatProfile, SerisPlayerProfile.
- **CombatHandlers.gd alone:** 73 distinct, 170 accesses.
- **Presentation:** 14 distinct, 66 accesses. CombatScene 36, CombatInputHandler 11, CombatUI 5, Targeting 5, CheatPanel 5, LargePreview 3, SerisResourceBar 1.
- **AI (`enemies/`):** 19 distinct, 34 accesses.
- **Most used:** `_refresh_slot_for` 58, `_log` 26, `_minion_has_tag` 22, `_summon_token` 15, `_friendly_board` 15, `_opponent_board` 15, `_opponent_of` 14, `_relic_cost_reduction` 12, `_spell_dmg` 10, `_combat_ended` 9, `_card_for` 8, `_has_talent` 8.

(The review's 74 / 172 for CombatHandlers counted comment lines too.)

### Nothing stops it growing

The lint has no rule on private access. The closest are:
- L11 checks that `<handle>.state.X` names resolve on CombatState (in `combat/`, `relics/`, `debug/tests/`). It doesn't care whether `X` is private.
- L10 is a ratchet: a count with a committed baseline (`L10_BASELINE = 20`, tools/lint/lint_engine.py:110) that each migration lowers. This task copies that pattern.

### Why now, and why in two phases

A ratchet is cheap and stops growth today. Renaming is not worth doing yet: tasks 094 (B1), 095 (B2a), 097 (B3), 098 (B4) and 084 (A2) move or delete a large share of these members, and renaming first would rename things that are about to move.

## Proposed fix

### Phase 1 — the ratchet lint (L19; provisional, take the next free number if the landing order differs)

1. Add L19 to `tools/lint/lint_engine.py`. Count `\bstate\._\w+` and `\bst\._\w+` on comment-stripped lines (`strip_comment`) in every `.gd` file except `combat/board/CombatState.gd` and `debug/`. Fail when the total exceeds `L19_BASELINE` or the distinct count exceeds `L19_DISTINCT_BASELINE`. Set both to the numbers on the day it lands (486 + 28 / 144 at `404b51c`; tasks 050, 051, 054 and 055 will have moved them).
2. Add `--report-private`: per-file and per-member counts, so a task can see what it removed.
3. Document L19 in the lint's header and in `design/TESTING.md`. Every task that removes external private reads lowers the baselines in the same commit, as L10 does.
4. Known blind spot: aliases (`var s := state`) escape every regex rule. Task 140 (roadmap J4) owns lint hardening.

### Phase 2 — public names (after tasks 094, 095, 097, 098 and 084)

1. Re-run `--report-private` and list the members still used outside the engine.
2. Give them public names, starting with the helpers: `refresh_slot_for`, `minion_has_tag`, `summon_token`, `friendly_board`, `opponent_board`, `opponent_of`, `spell_dmg`, `card_for`, `combat_ended`, …
   - Don't shadow GDScript built-ins or existing signals: `log` is the natural-log function and `combat_log` is a signal, so `_log` needs another name (e.g. `log_line`).
   - `_has_talent` gets a side parameter in task 090; rename it there, not here.
   - `_relic_cost_reduction` becomes per side in task 091.
3. Rename in CombatState, every caller and the tests in one commit per group. The import step and L11 in `tools/run_checks.sh` catch a missed caller through a typed or untyped handle.
4. Bring presentation and `enemies/` to zero first, then add per-directory baselines of 0 for them. Tasks 111 (L17, presentation reads the journal) and 122 (L18, AI reads only through CombatAgent) remove most of those reads anyway.

## Verification

- Phase 1:
  - `python3 tools/lint/lint_engine.py --report-private` prints the table; the totals match the committed baselines.
  - Self-check: add one `state._x` read to a scratch copy of a rules file and confirm L19 fails; remove it.
  - `tools/run_checks.sh` green with L19 enforced.
- Phase 2:
  - `--report-private` shows 0 for presentation and `enemies/`; the baselines are lowered to the new totals.
  - `tools/run_checks.sh` green.
  - Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4) diffs empty (design/TESTING.md 'Refactor / extraction work'). Renames shouldn't move it; this catches a rename that hit the wrong member.

## Related

- Depends on: task 094 (roadmap B1) — deletes the 33 diagnostic counters, some written from outside the engine.
- Depends on: task 095 (roadmap B2a) — removes the `_champion_*` reads from handlers and AI.
- Depends on: task 097 (roadmap B3) — moves Seris's members into a module.
- Depends on: task 098 (roadmap B4) — moves Korrath's members into a module.
- Related: task 084 (roadmap A2) — SideState part 2 moves traps, board and slots; phase 2 waits for it too.
- Related: task 087 (roadmap A4, L16), task 111 (roadmap E4, L17), task 122 (roadmap G7, L18) — the other new lint rules from this grooming pass; share the counting helper where they count.
- Related: task 140 (roadmap J4) — lint hardening, including aliases.
- Related: tasks 090 and 091 — give `_has_talent` and `_relic_cost_reduction` their per-side shape.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item B7. Re-counted at `404b51c` with comment stripping: 144 distinct / 486 accesses outside the engine (plus 28 `st._`), CombatHandlers 73 / 170, presentation 14 / 66, AI 19 / 34. Lint number L19 is provisional (L12 = 051, L13 = 050, L14 = 104, L15 = 137, L16 = 087, L17 = 111, L18 = 122).

## Summary

_(filled in at /task-done)_
