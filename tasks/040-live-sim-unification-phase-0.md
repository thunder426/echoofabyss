---
id: "040"
title: Live/sim unification — Phase 0 (foundations + hotfixes)
status: active
area: combat
priority: normal
started: 2026-09-23
finished:
---

## Description

Execute Phase 0 of `design/refactors/LIVE_SIM_UNIFICATION_PLAN.md`: fix the live-only handler crashes and dead talent flags (B1, B8–B11), fire turn-end events in live (D7 = fire), and add the foundations — engine lint, engine-owned seeded RNG, state digest + determinism probes, a headless live smoke test, and the Korrath unlock pools. One commit per green step.

## Work log

- 2026-09-23: opened. D7 = fire turn-end events. Commit per step approved. Baseline suite 784/784.
- 2026-09-23: prerequisites committed — 0.605 (task 009 shop korrath wiring), 0.606 (revised plan).
- 2026-09-23: lint v1 (L1) written first to record the baseline: **39 errors** (plan estimated ~25). 9 were the sim-only `enemy_essence_max/enemy_mana_max` fallback branches → `tools/lint/l1_allow.txt` (4 entries); 30 real. Beyond the plan's list, L1 also found unforwarded diagnostic counters (`_detonation_count`, `_spark_spawned_count`, `_spark_transfer_count`, `_rift_lord_plays`, `_immune_dmg_prevented` — silent no-ops live, no crash) and the `enemy_active_environment` fallback in `CombatHandlers._opponent_env`.
- 2026-09-23: 0.1 — all 30 rewritten to `.state.X`; `MinionInstance.add_armour(amount, state: CombatState)` now typed (callers pass `.state`); `CombatSetup._set_stat` writes registry stats to `scene.state` with an assert (checked: no registry key has an unforwarded scene-local copy); `_summon_enemy_champion` sets the `_summoned` flag + count before the death-anim await (B11). Lint 0, 789/789 (+2 probes: VRP summons exactly once over 8 spells; registry stats land on state).

## Summary

_(filled in at /task-done)_
