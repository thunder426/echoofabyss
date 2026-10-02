---
id: "094"
title: Move balance-diagnostic counters off CombatState into one sim-side counter sink
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item B1 (`design/refactors/ARCHITECTURE_ROADMAP.md` §B). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

CombatState carries 33 fields that only the balance sim reads. Rules code writes them, live combat increments them and never reads them, and each one costs four files: the engine field, a `CombatSim.run` result key, a `run_many` accumulator and a print in BalanceSimBatch. 8 of the 33 are dead.

The section header says so itself (CombatState.gd:1955-1957):
```gdscript
# Diagnostic counters — sim collects these for end-of-run reports. Live combat
# also increments them but never reads (ignored). Always-on per Phase 0 decision.
```
ARCHITECTURE.md:250 records the same choice: "The per-mechanic counters (`_smoke_veil_fires`, `_debug_soul_forge_fires`, …) stay on the state." This task reverses it.

### The 33 diagnostic-only fields

Method: for every `^var` in CombatState, list the files outside CombatState that name it on comment-stripped lines. A field is diagnostic-only when its only reader is `sim/CombatSim.gd` (or a test).

| Group | Fields | Written at |
|---|---|---|
| Void Warband (F11) | `_vw_behemoth_plays`, `_vw_bastion_plays`, `_vw_behemoth_lost`, `_vw_bastion_lost`, `_vw_death_crit_grants` | CombatState.gd:2576/:2578 (`cmd_play_minion`), :3066/:3068 (`_consume_minion`); CombatManager.gd:291-298 (`# F11 debug: track Behemoth/Bastion death cause`); CombatHandlers.gd:1676 |
| Act 1-2 passives | `_corruption_detonation_times`, `_detonation_count`, `_ritual_invoke_times`, `_ritual_sacrifice_count`, `_spark_spawned_count`, `_spark_transfer_count`, `_champion_ch_aura_dmg`, `_handler_spark_buff_times` | CombatHandlers.gd:1172-1173, :1250-1251, :1293, :1324, :2243-2244 |
| Cards / traps | `_smoke_veil_fires`, `_smoke_veil_damage_prevented`, `_void_bolt_total_dmg`, `_player_ritual_count` | HardcodedEffects.gd:215-218; CombatState.gd:981, :854 |
| Act 3-4 | `_rift_lord_plays`, `_hollow_sentinel_buffs`, `_immune_dmg_prevented`, `_dark_channeling_amp_count`, `_dark_channeling_amp_by_spell`, `_dark_channeling_dmg_by_spell`, `_sovereign_transition_turn` | EffectResolver.gd:326, :751-753; CombatHandlers.gd:1425, :1989-1992; CombatManager.gd:251; PhaseTransition.gd:47 |
| Seris | `_debug_soul_forge_fires`, `_debug_corrupt_flesh_fires` | CombatState.gd:774, :1099 |
| Crits | `_player_crits_consumed` | CombatManager.gd:358 |
| AI-written (task 051) | `_rift_collapse_casts`, `_rift_collapse_kills`, `_void_bolt_spell_casts`, `_void_imp_dmg`, `_abyssal_plague_fires`, `_abyssal_plague_kills` | RiftStalkerProfile.gd:224/:226; SpellBurnPlayerProfile.gd:381, :406-416. Task 051 moves these writes into the engine first. |

Some writes sit in hot paths, for example:
```gdscript
if side == "enemy":                       # CombatState.gd:2574-2578, cmd_play_minion
	if mc.id == "bastion_colossus":
		_vw_bastion_plays += 1
	elif mc.id == "void_behemoth":
		_vw_behemoth_plays += 1
```
and `state._immune_dmg_prevented += damage` (CombatManager.gd:251), which returns before anything is journaled. The cost per call is a few compares; the case for this task is engine clutter and boilerplate, not speed. The sim speed claim in the roadmap can't be measured without running Godot.

Four more fields look like counters but are gameplay. Leave them alone here:
- `_enemy_crits_consumed`: Void Scout's threshold (CombatHandlers.gd:1575) and `captain_orders` (:1965).
- `_champion_summon_count`: read by the AI (CombatProfile.gd:550). Task 095 moves it.
- `_champion_rs_spark_dmg`: Rift Stalker's threshold (:1444) and the AI (RiftStalkerProfile.gd:260). Task 095 moves it.
- `_sovereign_phase`: gates the F15 Avatar (CombatHandlers.gd:1864).

### 8 are dead

- `_handler_spark_buff_times` (:1821) is never written. CombatSim.gd:327 reads it, and it reaches `avg_spark_buff`, which BalanceSimBatch prints only when > 0 (`if sb > 0: extras.append("SpkB:%.1f" % sb)`, BalanceSimBatch.gd:395). It is always 0. SimRunner.gd:89-93 prints it as "SparkBuffs".
- `_player_crits_consumed` is written (CombatManager.gd:358) and never read.
- `_ritual_sacrifice_count`, `_detonation_count`, `_spark_spawned_count`, `_spark_transfer_count` become `avg_ritual_sac`, `avg_detonation`, `avg_spark_spawned`, `avg_spark_transfer` (CombatSim.gd:518-522). Nothing reads those keys.
- `_debug_soul_forge_fires` and `_debug_corrupt_flesh_fires` become `seris_sf` / `seris_cf` (CombatSim.gd:299-300, :312-313). Nothing reads them.

Two pairs count the same fact at the same site: `_detonation_count` / `_corruption_detonation_times` (CombatHandlers.gd:1172-1173) and `_ritual_sacrifice_count` / `_ritual_invoke_times` (:1250-1251).

### Who reads them

- `CombatSim.run` copies each into a result key (CombatSim.gd:301-351). It does so after `state.teardown()` (:298); task 049 reorders that.
- `run_many` (:364-555) keeps about 40 hand-written `total_*` accumulators and `avg_*` keys.
- Readers of the averages: `BalanceSimBatch._print_row` (:356-435), `SimRunner.gd:80-93`, `DebugSingleSim.gd:35-37` (`champion_summon_count`, `vw_*_plays`) and `ScenarioTests.gd:669` (`void_bolt_total_dmg`).
- Tests read the fields directly: CardEffectTests.gd:363-370 (Smoke Veil), TriggerHandlerTests.gd:1425 (`state.get("_champion_ch_aura_dmg")`).

### Why the roadmap's "counters on `diagnostics`" doesn't work as written

`state.diagnostics` is null in every batch run. CombatSim attaches it only for damage-log or debug runs:
```gdscript
if dmg_log or debug:                                        # CombatSim.gd:58-59
	state.diagnostics = CombatDiagnostics.new(state, dmg_log, debug)
```
and BalanceSimBatch goes through `run_many`, which passes neither. So the counters need a sink that every sim run attaches, or a fold over the journal after the fight.

## Proposed fix

1. **Delete the 8 dead counters and their plumbing:** the fields, the `seris_sf` / `seris_cf` result keys, the `avg_ritual_sac` / `avg_detonation` / `avg_spark_spawned` / `avg_spark_transfer` / `avg_spark_buff` keys, BalanceSimBatch's `SpkB` extra and SimRunner's `SparkBuffs` column. Keep one of each duplicate pair (`_corruption_detonation_times`, `_ritual_invoke_times`).
2. **Add a counter sink**, e.g. `sim/CombatCounters.gd` (RefCounted, no reference back to the state):
   - `count(key: StringName, n := 1)` and `count_in(key, sub_key, n := 1)` for the dictionary counters (`vw_*_lost`, `dc_*_by_spell`);
   - `to_dict() -> Dictionary`.

   The engine gets one entry point, e.g. `state.diag_count(key, n)` / `diag_count_in(key, sub_key, n)`, which forwards to `state.counters` and does nothing when it is null. `CombatSim._build` always attaches one; live never does; `TestHarness.build_state` attaches one when asked (`opts.counters = true`).
3. **Fold the journal where it already records the fact.** `CombatSim.run` calls `CombatCounters.fold(state.journal)` after the loop. Candidate sources:
   - `CARD_PLAYED` side enemy, card id `void_behemoth` / `bastion_colossus` (emitted at :2571, before today's counter);
   - `MINION_CONSUMED` (Behemoth / Bastion "consumed");
   - `RITUAL_FIRED` side player (`_player_ritual_count`; emitted at :891 in the same function as the counter);
   - `PHASE_TRANSITION` (its `turn` replaces `_sovereign_transition_turn`);
   - `SPELL_CAST` spell id (the Rift Collapse / Void Bolt / Abyssal Plague casts that task 051 counts);
   - `DAMAGE_DEALT` `source_card` (Corrupted Handler aura damage, `"champion_corrupted_handler_aura"`).

   Audit each one against the current counter before switching. The folded number must equal today's for the fingerprint below to stay empty. Where it doesn't (an event emitted on a path the counter skipped, or the reverse), keep an explicit `diag_count` call instead.
4. **Keep explicit `diag_count` calls only where the journal lacks the fact:** immune damage prevented (CombatManager.gd:251 returns before journaling), Smoke Veil's prevented amount, Dark Channeling amp count and extra damage per spell, the Behemoth / Bastion death cause, Void Warband crit grants, Hollow Sentinel buffs.
   - Key `_void_bolt_total_dmg` (`VB:`) and `_player_ritual_count` (`PRit`) by side in the sink: tasks 092 and 093 make Void Bolts and rituals work for either side but keep these counters player-only so the fingerprint holds. BalanceSimBatch keeps printing the player's value.
5. **`CombatSim.run` returns `counters: Dictionary`** next to the gameplay keys, and `run_many` sums every counter generically (ints add, dictionaries add per sub-key). Keep the `avg_*` names that BalanceSimBatch, SimRunner and DebugSingleSim read by deriving them from the summed dictionary, or update those readers in the same commit. Either way BalanceSimBatch's printed lines must not change. SimRunner's line loses its always-zero "SparkBuffs" column (step 1).
6. **Delete the 33 fields** and the section header at :1955-1957, and the "Sim-only Act 3/4 counters" block (:1947-1952). Leave the four gameplay fields listed above.
7. **Tests:** CardEffectTests.gd:363-370 and TriggerHandlerTests.gd:1425 build their state with the sink and read `state.counters`; ScenarioTests.gd:669 reads the new result shape.
8. **Docs:** ARCHITECTURE.md:250 (the CombatDiagnostics row: counters now live in the sim's sink, fed from the journal) and the BalanceSimBatch output section of `design/TESTING.md`.

Note for the implementer: task 051 lands first and moves the AI-written counters into the engine. If both land in one release, 051's counters can come from the `SPELL_CAST` fold instead of new engine fields. That is a shortcut, not a change to 051's scope.

## Verification

- New probe in `debug/tests/ScenarioTests.gd`, `_counter_fold_matches_journal`: run a seeded F11 (`void_warband`) `CombatSim.run`, keep its journal through `CombatSim.state_observer` (:33), and assert `counters.vw_behemoth_plays` equals the number of enemy `CARD_PLAYED` events whose card id is `void_behemoth`.
- New probe in `debug/tests/CommandTests.gd`: on a state with no sink (live-like), `state.diag_count(&"x")` is a no-op and pushes no error.
- Grep gate: `grep -cE '^var _(debug_|vw_|rift_|smoke_veil|abyssal_plague|void_bolt|void_imp_dmg|dark_channeling_(amp|dmg)|hollow_sentinel|immune_dmg|ritual_|detonation|spark_spawned|spark_transfer|player_crits|player_ritual|corruption_detonation|handler_spark|sovereign_transition|champion_ch_aura_dmg)' combat/board/CombatState.gd` → 0 (33 at `404b51c`, and it matches no gameplay field).
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4) diffs empty, including every extras line (design/TESTING.md 'Refactor / extraction work'). Request Acts 3-4 explicitly; BalanceSimBatch defaults to Acts 1-2. The deleted keys were never printed, and `SpkB` was always 0.

## Related

- Depends on: task 051 — it moves the AI profiles' counter writes into the engine and adds lint L12; this task then migrates every engine counter, 051's included.
- Related: task 049 — `CombatSim.run` reads the counters after `teardown()`. 049 builds the result before teardown; whichever lands second keeps that order.
- Related: task 095 (roadmap B2a) — owns the two dual-use champion fields (`_champion_summon_count`, `_champion_rs_spark_dmg`) and the rest of `_champion_*`. `_champion_ch_aura_dmg` is diagnostic and moves here.
- Related: task 097 (roadmap B3) — depends on this task so the Seris module doesn't inherit `_debug_soul_forge_fires` / `_debug_corrupt_flesh_fires`.
- Related: task 141 (roadmap J5) — retires the stale debug sims (VoidboltDmgDebug, DebugF13LossAnalysis) that read `run` results.
- Related: task 099 (roadmap B7) — lower its `state._x` baseline when these fields go.
- Related: task 132 (roadmap I4) — keeps the `damage_dealt` and `combat_log` signals only for CombatDiagnostics. If this task's sink reads DAMAGE_DEALT / LOG from the journal instead, delete both signals here.
- Related: task 136 (roadmap I7d) — its optional `journal_logs` switch may drop only LOG events; the fold in step 3 reads CARD_PLAYED, SPELL_CAST, RITUAL_FIRED, MINION_CONSUMED, PHASE_TRANSITION and DAMAGE_DEALT.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item B1. Re-counted at `404b51c`: 33 diagnostic-only fields (the review said ~30), 8 of them dead. Every write site re-checked. The batch path has no `diagnostics` object, so the sink must be attached in every sim run.

## Summary

_(filled in at /task-done)_
