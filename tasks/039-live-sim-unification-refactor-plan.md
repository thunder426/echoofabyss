---
id: "039"
title: Live/sim unification refactor plan (design/refactors)
status: done
area: combat
priority: normal
started: 2026-09-22
finished: 2026-09-22
---

## Description

Write an executable, phase-by-phase refactor plan under `design/refactors/` that removes live-vs-sim drift for good: one rules engine on CombatState, a command API, an event journal consumed by presentation, engine-owned RNG, and parity/lint tripwires in the test suite. Each phase must be runnable by a coding agent with concrete file anchors, acceptance checks and rollback notes.

## Work log

- 2026-09-22: opened.
- 2026-09-22: closed.
- 2026-09-23: revised after a 3-agent verification pass against 1c9aa30. Added live bugs B7–B13 (turn-end events never fire live, Korrath rune crashes, CombatSetup stats no-op, unforwarded one-shot flags, champion race, Smoke Veil, corruption in VFX drain) and divergences B14–B17 with decisions D7–D11. Split Phase 2 into 2A (sim/tests + shared turn/trap engine), then moved the live switch into Phase 3 behind a new de-async step 3.0. Committed scope is now Phase 0 → 2A (~5 sessions), with a checkpoint before 3–5. Appendix C lists every correction.

## Summary

Wrote `design/refactors/LIVE_SIM_UNIFICATION_PLAN.md`: a six-phase, step-numbered plan (0 foundations/hotfixes, 1 state ownership, 2 command API + single agent + trap routing, 3 event journal + ViewState, 4 collapse duplicates, 5 parity test + lint tripwires) with file:line anchors, create/modify/delete lists, grep gates per step, a phase evaluation table and six owner decisions (D1–D6). Verified during review: two live-only handler crashes, sim-only enemy resource curves, divergent trap routing, missing Guard enforcement in sim, and a dead Imp Barricade redirect path; all are addressed by named steps.
Follow-ups: owner must answer D1–D6 before Phases 2–4; each phase should be opened as its own task; the Korrath unlock hotfix and the talent→pool mapping consolidation are noted as separate work.
