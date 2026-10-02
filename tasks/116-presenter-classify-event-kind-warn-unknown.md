---
id: "116"
title: Presenter: classify every event kind; warn on unknown VFX names and unclassified kinds
status: backlog
area: ui
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item F3 (`design/refactors/ARCHITECTURE_ROADMAP.md` §F). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The presenter silently ignores event kinds and VFX names it doesn't know:
- `_play` (CombatPresenter.gd:192-256) ends in `_:` / `pass` (:255-256).
- `_play_vfx` (:592-652) matches on `p.get("name", "")` and also ends in `_:` / `pass` (:651-652). If a rules-code VFX event misspells `name`, nothing shows.
- `_play_captured_event` (:508-525) and `_emit_ui` (:678-768) end the same way (:524-525, :767-768).

None of this fails a test or the gate. A `push_warning` wouldn't either: `run_checks.sh` fails only on lint errors, test failures and `SCRIPT ERROR` (tools/run_checks.sh:8, :60).

### Which kinds are handled today

A python scan of the `match` statements at `404b51c` found:
- `CombatEvent.Kind` has 49 kinds (CombatEvent.gd:15-34).
- `_play` handles 28, `_emit_ui` handles 26 and `ViewState.apply` (ViewState.gd:70) handles 10.
- 21 kinds have no `_play` case. 19 of those are display-only by design: `_emit_ui` or ViewState applies them (LOG, SLOT_CHANGED, RESOURCES_CHANGED, HERO_HP_CHANGED, …).
- 2 kinds are handled nowhere:
  - SPELL_RESOLVED is read only as the end of the spell capture (:457).
  - HERO_SKILL is journaled by `_cmd_hero_skill` (CombatState.gd:2879) and read by nothing. The skill's effects journal their own events, so nothing is missing on screen today.

So a blanket warning in `_play`'s default would fire on every LOG. Each kind needs an explicit classification.

### VFX names (latent)

There are 15 `Kind.VFX` emit sites, in CombatHandlers.gd and HardcodedEffects.gd. They use 14 distinct names (`void_netter` appears twice). `_play_vfx` has a case for each of the 14, so no emitted name is dropped today.

## Proposed fix

1. **Classify every kind.** Add `const KIND_ROLE: Dictionary` to CombatPresenter, with one entry per `CombatEvent.Kind`:
   - `"animated"`: the kind has a `_play` case. It may also update the UI in `_emit_ui`.
   - `"display"`: no animation; `_emit_ui` or ViewState applies it.
   - `"marker"`: deliberately shown by nothing (SPELL_RESOLVED, HERO_SKILL). Give each marker a one-line comment naming what reads it.

   HERO_SKILL stays a marker until a skill animation exists.
2. **`_play` default.** Call `push_warning` and increment `unclassified_events` only when the kind is missing from `KIND_ROLE` or is classified `"animated"` (which means its case was lost). `"display"` and `"marker"` kinds fall through silently, as today.
3. **`_play_vfx` default.** Call `push_warning("CombatPresenter: unknown VFX '%s'" % name)` and increment `unknown_vfx`.
4. **`_play_captured_event` default.** Same pattern, for a captured kind it can't show. This is unreachable while the capture takes only its 4 kinds.
5. **A gate for VFX names.**
   - LiveSmoke asserts `presenter.unknown_vfx == 0` and `presenter.unclassified_events == 0` at the end of each scenario. This catches any name emitted in those fights.
   - Task 142 (roadmap J6) turns VFX wiring into tables, and its phase b coverage probe (in ContentTests or CommandTests) checks that every literal `name` in a `Kind.VFX` emit is a key in the table. That probe is the static check; no lint rule is needed, and this task doesn't add one.
6. **Docs.** Add to ARCHITECTURE.md's CombatPresenter row: every new kind gets a `KIND_ROLE` entry.

## Verification

- New `debug/tests/CommandTests.gd` test `_presenter_kinds_classified`. It is static, so it needs no scene:
  - for each key in `CombatEvent.Kind.keys()`, assert that `CombatPresenter.KIND_ROLE` has `CombatEvent.Kind[key]`, with one of the three roles;
  - adding a kind without classifying it then fails RunAllTests.
- LiveSmoke test of the warning path:
  - journal `st.emit_event(CombatEvent.Kind.VFX, "player", {name = "_no_such_vfx"})` and drain;
  - assert `presenter.unknown_vfx == 1`, then reset it before that scenario's end-of-scenario check.
- `tools/run_checks.sh` green.
- **Behaviour-neutral:** the change is presenter-only. The seeded balance fingerprint (`BalanceSimBatch -- --act 1 --runs 200 --seed 7`, before and after) diffs empty (design/TESTING.md 'Refactor / extraction work'). The sim never loads the presenter, so one act is enough.

## Related

- Related: task 115 (roadmap F2) — rewrites the same `match` statements. Land this task with it or after it.
- Related: task 142 (roadmap J6) — owns the VFX wiring tables and their load-time check. The unknown-VFX warning stays here, as its plan note says.
- Related: task 109 (roadmap E2) — adds a new journal kind, SKILL_STATE_CHANGED (Corrupt Flesh used flag); `KIND_ROLE` must classify it (`display`).
- Related: task 112 (roadmap E6) — moves UI prompts off the gameplay LOG kind, and may add a kind to classify.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item F3.

## Summary

_(filled in at /task-done)_
