---
id: "132"
title: Delete dead signals and buses (14 unheard CombatState signals, BuffSystem buff_applied, SacrificeSystem bus, attack_resolved)
status: backlog
area: combat
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item I4 (`design/refactors/ARCHITECTURE_ROADMAP.md` §I), merged with B8 (§B, "delete CombatState signals with no listener"). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Since Phase 4 the screen follows the journal (`emit_event` → presenter). The gameplay signals from before that are still declared and emitted next to their journal events, but most have no listener. Two notification paths drift, and the next contributor may wire UI to a signal that never reaches the screen.

### CombatState's 24 signals

`grep -cE '^\s*signal ' combat/board/CombatState.gd` → 24. Listeners, found with `grep -rnE '\b<sig>\.(connect|is_connected|disconnect)\(|"<sig>"' --include='*.gd'` for each name:

| Listeners | Signals |
|---|---|
| **none** (14) | `hp_changed` :18, `void_marks_changed` :22, `minion_stats_changed` :49, `minion_summoned` :57, `flesh_changed` :61, `forge_changed` :65, `traps_changed` :70, `environment_changed` :74, `spell_damage_dealt` :82, `minion_died` :89, `trap_fired` :1003, `resources_changed` :1350, `card_drawn` :1352, `card_generated` :1354 |
| tests only (4) | `hero_armour_changed` :27 (TriggerHandlerTests.gd:3167), `hero_buff_changed` :33 (TriggerHandlerTests.gd:3152), `slot_changed` :1306 (CommandTests.gd:123), `command_recorded` :3103 (ParityTests.gd:102, :121) |
| sim diagnostics only (2) | `damage_dealt` :39, `combat_log` :44 (sim/CombatDiagnostics.gd:23-24) |
| production (4) | `journaled` :97 (presenter), `enemy_profile_changed` :1811 (CombatScene, CombatSim), `turn_started` :2315 (CombatScene.gd:330), `turn_ended` :2317 (CombatScene.gd:331, CombatSim.gd:216) |

The roadmap said 3 test-only signals; it is 4 (`command_recorded` is the Parity hook and stays).

Emit sites of the 14 unheard signals:
- CombatState.gd:122, :138, :151, :614, :654, :1052, :1247, :1257, :1457, :1568, :1579, :1591, :1637, :1668, :1691, :1993, :2147, :2598;
- CombatHandlers.gd:136 (`card_generated`), :333 (`traps_changed`), :1349 (`minion_summoned`).

The three test-only signals that go are emitted at CombatState.gd:300 (`hero_armour_changed`), :312 and :2377 (`hero_buff_changed`) and :1323 (`slot_changed`).

Most emits sit right next to the journal event that replaced them. For example, `_refresh_slot_for` (:120-123) emits `minion_stats_changed` and then journals MINION_STATS_CHANGED. The exceptions are where they have already drifted:
- `_update_environment_display` (:150-151) only emits `environment_changed` and journals nothing. It is called from `cmd_play_environment` (:2741, after `set_environment` has already journaled), EffectResolver.gd:414 and :616 (environment destroy; task 050 replaces these) and CombatScene.gd:202, whose comment says "the initial display refresh calls below journal their events".
- Grand Ritual: Chaos emits `traps_changed` instead of journaling (CombatHandlers.gd:333; task 050 item 5).

### Dead buses

- **BuffSystem `buff_applied`.** It is emitted at BuffSystem.gd:111 and nothing listens. `apply()` still snapshots `effective_atk`, the HP cap and the shield cap before and after every apply with `emit_vfx = true` (:86-110) just to compute it. The header (:32-37, "CombatScene connects to `buff_applied` on _ready") and BuffApplyVFX.gd:20 are stale. The presenter drives buff VFX from the BUFF_APPLIED journal event.
- **SacrificeSystem bus.** `sacrifice_occurred` is emitted at SacrificeSystem.gd:35 (`emit`) and :50 (`sacrifice`), and nothing listens. `SacrificeSystem.emit(imp, "ritual_sacrifice")` at CombatHandlers.gd:1248 is a pure no-op. The header (:2-3, "CombatScene subscribes on _ready to drive SacrificeVFX") and SacrificeVFX.gd:15-17 are stale. The scene's `_on_sacrifice_occurred` (CombatScene.gd:801) is called by the presenter from the MINION_SACRIFICED event (CombatPresenter.gd:340), not by the bus.
- **`CombatManager.attack_resolved`.** Declared at CombatManager.gd:13, emitted at :151, no listener. ARCHITECTURE.md:101 still lists it.

## Proposed fix

1. **Delete the 14 unheard signals**, their emit sites, and the doc comments that name them. Grep each name; the hits include CombatState.gd:119, :133-136, :285, :404, :628-629, :649-653, :660, :852, :1233, :1345, :1556, :1583, :1628, :1659, :1683, :1983, :2311, :2533, HeroState.gd:18, CombatScene.gd:1298, CombatHandlers.gd:1194 and TrapEnvDisplay.gd:14. (The CombatUI "Subscriber to CombatState.…" headers are task 055's.)
2. **Delete `_update_environment_display`** once task 050 has replaced its EffectResolver callers. `cmd_play_environment` already journals through `set_environment` (:2739). If the scene needs an initial environment refresh, journal it rather than calling the hook from CombatScene.gd:202.
3. **Test-only signals:**
   - `_apply_hero_buff_emits_hero_buff_changed` (TriggerHandlerTests.gd:3146-3159) asserts one HERO_BUFF_CHANGED event with side `"enemy"` in `state.journal`.
   - `_add_hero_armour_emits_hero_armour_changed` (:3161-3175) asserts one ARMOUR_CHANGED event with `payload.value == 250`.
   - `_slots_are_engine_slot_states` (CommandTests.gd:118+) asserts SLOT_CHANGED events instead of `slot_changed`.
   - Then delete `hero_armour_changed`, `hero_buff_changed` and `slot_changed`. Keep `command_recorded`.
4. **BuffSystem:**
   - Delete the `buff_applied` user signal and the before / after snapshot in `apply()` (:86-111).
   - Delete the `emit_vfx` parameter from `apply`, `apply_hp_gain` and `CombatState.apply_hero_buff` (:308-312). BuffSystem's funcs are static, so a leftover extra argument is a parse error; `load_all_scripts` lists every call site to fix (about 50 outside tests, 89 in all). The probes planned in tasks 110, 130 and 131 call `BuffSystem.apply(..., false, false)`; whichever of those lands after this task drops the last argument.
   - EffectResolver.gd:479 / :491 keep `silent` for the BUFF_APPLIED payload.
   - Fix the header (:32-37) and BuffApplyVFX.gd:20.
   - If task 130 (roadmap I2) has already removed `corruption_removed`, also delete `BuffSystem.bus()` and `_bus`; otherwise task 130 does.
5. **SacrificeSystem:**
   - Delete `_bus`, `bus()`, `emit()` and the bus emit inside `sacrifice()` (:50).
   - Delete the call at CombatHandlers.gd:1248.
   - Fix the header (:1-14), `sacrifice()`'s doc (:37-46) and SacrificeVFX.gd:15-17.
   - `SacrificeSystem.sacrifice()` stays: it is the sacrifice flow.
6. **Delete `CombatManager.attack_resolved`** (:13, :151).
7. **Keep `damage_dealt` and `combat_log`** for CombatDiagnostics. Task 094 (roadmap B1) decides whether diagnostics moves to reading the journal (DAMAGE_DEALT, LOG); then both go.
   - CombatManager's `minion_vanished` / `hero_damaged` / `hero_healed` are connected by the state itself (and `hero_damaged` by DamageTypeTests.gd:179-308). They are not dead.
   - Task 129 (roadmap I1) may change `minion_vanished`'s arguments or turn it into a direct call; leave them to it.
8. **Docs:** ARCHITECTURE.md:74 ("the gameplay signals (hp_changed, damage_dealt, turn_started, …) still fire for listeners like CombatDiagnostics"), :101 (CombatManager signals) and :103 (BuffSystem bus). List the signals that remain and who hears each.

## Verification

- The rewritten TriggerHandlerTests and CommandTests assertions on HERO_BUFF_CHANGED, ARMOUR_CHANGED and SLOT_CHANGED pass.
- After the change, `grep -nE '^\s*signal ' combat/board/CombatState.gd` lists only `damage_dealt`, `combat_log`, `journaled`, `enemy_profile_changed`, `turn_started`, `turn_ended` and `command_recorded`. Each has a listener.
- `grep -rn 'buff_applied\|sacrifice_occurred\|attack_resolved' --include='*.gd' .` finds only the CommandTests probe name `_journal_buff_applied_before_after` (it tests the BUFF_APPLIED journal event, which stays).
- `tools/run_checks.sh` green. Its `load_all_scripts` step catches any dangling reference or extra `emit_vfx` argument.
- Behaviour-neutral: no rule reads any of these. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, Acts 1-4) diffs empty (design/TESTING.md 'Refactor / extraction work'). Spot-check wall time: `apply()` no longer snapshots stats twice per buff.

## Related

- Depends on: task 050 — replaces the environment-destroy and Grand Ritual Chaos paths that today only emit `environment_changed` / `traps_changed` with journaled events, so deleting the signals loses nothing.
- Related: task 130 (roadmap I2) — removes `corruption_removed` from the BuffSystem bus; with this task, the bus is gone.
- Related: task 049 — its teardown disconnects every connection on the state's own signals; fewer signals make that loop smaller.
- Related: task 094 (roadmap B1) — the sim counter sink decides the fate of `damage_dealt` / `combat_log`.
- Related: task 055 — fixes the CombatUI "Subscriber to CombatState.…" headers and ARCHITECTURE.md:21.
- Related: task 129 (roadmap I1) — owns any change to CombatManager's `minion_vanished`.
- Related: task 109 (roadmap E2) — phase E2c replaces CombatScene.gd:202's `_update_environment_display()` call with a render of both sides from `presenter.view`; if it lands first, step 2 has one caller fewer.
- Related: task 088 (roadmap A5) — owns the stale TriggerManager.gd header; this task doesn't edit it.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap items I4 and B8. Re-checked every listener at `404b51c`: 14 unheard, 4 test-only (not 3), 2 diagnostics-only, 4 production. Confirmed the BuffSystem, SacrificeSystem and `attack_resolved` buses have no listener, and `_update_environment_display` emits without journaling.

## Summary

_(filled in at /task-done)_
