---
id: "040"
title: Live/sim unification — Phase 0 (foundations + hotfixes)
status: done
area: combat
priority: normal
started: 2026-09-23
finished: 2026-09-23
---

## Description

Execute Phase 0 of `design/refactors/LIVE_SIM_UNIFICATION_PLAN.md`: fix the live-only handler crashes and dead talent flags (B1, B8–B11), fire turn-end events in live (D7 = fire), and add the foundations — engine lint, engine-owned seeded RNG, state digest + determinism probes, a headless live smoke test, and the Korrath unlock pools. One commit per green step.

## Work log

- 2026-09-23: opened. D7 = fire turn-end events. Commit per step approved. Baseline suite 784/784.
- 2026-09-23: prerequisites committed — 0.605 (task 009 shop korrath wiring), 0.606 (revised plan).
- 2026-09-23: lint v1 (L1) written first to record the baseline: **39 errors** (plan estimated ~25). 9 were the sim-only `enemy_essence_max/enemy_mana_max` fallback branches → `tools/lint/l1_allow.txt` (4 entries); 30 real. Beyond the plan's list, L1 also found unforwarded diagnostic counters (`_detonation_count`, `_spark_spawned_count`, `_spark_transfer_count`, `_rift_lord_plays`, `_immune_dmg_prevented` — silent no-ops live, no crash) and the `enemy_active_environment` fallback in `CombatHandlers._opponent_env`.
- 2026-09-23: 0.1 — all 30 rewritten to `.state.X`; `MinionInstance.add_armour(amount, state: CombatState)` now typed (callers pass `.state`); `CombatSetup._set_stat` writes registry stats to `scene.state` with an assert (checked: no registry key has an unforwarded scene-local copy); `_summon_enemy_champion` sets the `_summoned` flag + count before the death-anim await (B11). Lint 0, 789/789 (+2 probes: VRP summons exactly once over 8 spells; registry stats land on state).
- 2026-09-23: 0.2 (D7 = fire) — `CombatScene._on_turn_ended` fires ON_PLAYER_TURN_END / ON_ENEMY_TURN_END before the side's cleanup (and bails if combat ended); `SimState.end_player_turn` now fires ON_PLAYER_TURN_END too. Probe: Altar Thrall's "end of your turn, sacrifice" (a shipped Seris card that had never worked, live or sim). **Balance delta: none** — `BalanceSimBatch --runs 100 --seed 7` (Acts 1+2, 150 rows) is byte-identical before/after: the enemy-side events already fired in sim and no preset deck uses a player-side turn-end effect. So D7 brings live in line with what the sim already modelled (void_unraveling, captain_orders, abyssal_mandate, champion_vs/vch, hollow_sentinel, pack_frenzy revert now run in the real game).
- 2026-09-23: 0.6 — `debug/tests/LiveSmoke.tscn` (separate process in run_checks.sh): F1 boots with a 4-card hand and completes an enemy turn; F13 fires 6 enemy spells and gets exactly one VRP champion. ~8 s. Verified it catches B1: against the pre-0.1 handlers it prints `SCRIPT ERROR: Invalid access to property '_champion_vrp_spells_cast' on CombatScene`. `UserProfile.saving_disabled` keeps tests off the dev profile. Teardown waits for hand-draw / VFX coroutines to drain (freeing mid-await printed a HandDisplay SCRIPT ERROR). 3/3 stable runs.
- 2026-09-23: 0.7 — korrath_common / korrath_iron_vanguard added to `GameManager.grant_boss_unlocks` and `UserProfile._ensure_default_unlocks`.
- 2026-09-23: 0.4 — engine RNG on CombatState; 43 call sites migrated; seeded before any shuffle (sim: `run(…, rng_seed)`; live: `GameManager.next_combat_seed` / rolled, logged as `Seed: N`). Lint L2 (43 hits on old code → 0).
- 2026-09-23: 0.5 — `SimState.digest_text()` (on SimState, not CombatState, until 1.3 hoists hands/decks/resources) + two determinism probes; runs start from different global seeds, and mutation-checked (a global shuffle on either deck fails them). 797/797.
- 2026-09-23: phase gates — lint 0 (L1, L2); run_checks green (797/797 + LiveSmoke); `BalanceSimBatch --act 1 --runs 50 --seed 7` identical on two consecutive runs. Docs: TESTING.md (run_checks, lint, LiveSmoke, seeds), ARCHITECTURE.md (invariants 11–12, tooling), CLAUDE.md (refactor gate), plan header progress.
- 2026-09-23: closed.

## Summary

Shipped Phase 0 of the live/sim unification plan (0.605–0.614): fixed ~30 rules-code accesses that crashed or silently no-oped only in live combat (VRP/Abyss Sovereign champion crashes, Korrath rune talents, dead talent stat flags, champion re-summon and double-summon race), fired turn-end events in live (D7 — ~10 dead handlers incl. Altar Thrall now run; sim balance output byte-identical), moved all gameplay randomness onto a seeded engine RNG with seed + state digest returned from every sim run, and added the Korrath permanent-unlock pools. Added `tools/run_checks.sh` (import → lint L1/L2 → RunAllTests → headless live CombatScene smoke, failing on any SCRIPT ERROR); the smoke test was verified to reproduce B1 on the old code. 784 → 797 tests.
Follow-ups: Phase 1 (rules code addresses `state`; empty `tools/lint/l1_allow.txt`; move `digest_text` to CombatState). B12 (Smoke Veil cancels the wrong attack) and B13 remain open until Phase 3.0.
