---
id: "136"
title: Cut journal noise: no-op presence-aura recompute, and measure the sim's LOG cost
status: backlog
area: combat
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item I7d, the "sim journaling cost" part of item I7 (`design/refactors/ARCHITECTURE_ROADMAP.md` §I). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### Presence-aura recompute re-journals every minion

- `on_minion_event_presence_auras` recomputes both sides (CombatHandlers.gd:1017-1018). It is registered on six events: summoned, died and sacrificed, for each side (CombatSetup.gd:570-575).
- `_refresh_presence_auras_for_side` ends with an unconditional loop:
  ```gdscript
  for m in board:                                   # CombatHandlers.gd:1076-1081
      ...
      state._refresh_slot_for(m)
      if atk_delta != 0 or hp_delta != 0:
          state.emit_event(CombatEvent.Kind.VFX, ...)
  ```
- There is no early return when the side has no aura source. Only one card has `presence_aura_steps`, Rogue Imp Elder (CardDatabase.gd:2720, a BUFF_ATK aura; enemy decks f1_c, f3_b and f3_c). Yet every summon, death or sacrifice anywhere journals one MINION_STATS_CHANGED per minion on both boards: up to 10.

### The sim journals every LOG line

`_log` (CombatState.gd:114-116) always emits `combat_log` and journals a LOG event. About 145 call sites in rules code use it: CombatHandlers 67, CombatState 55, RelicEffects 13, HardcodedEffects 11, PhaseTransition 1. The balance sim keeps the whole journal for every fight and never reads LOG. Nothing has measured what this costs.

### Consequences

- **Journal size and sim time** grow with board size × events. Unmeasured.
- **Presenter look-ahead budget.** `_peek_window` stops after 60 events (CombatPresenter.gd:145-154). `_play_attack` uses it to find the counter-hit (:568-574), and the buff and detonation batches use it too (:371-378, :401-407).
  - The counter's DAMAGE_DEALT is journaled after the defender's whole death cascade: the counter runs at CombatManager.gd:132-138, after `_deal_damage(defender, …)` at :100.
  - With full boards and an on-death AoE (Void-Touched Imp in f2_a/b/c), each death adds roughly MINION_DIED, SLOT_CHANGED, LOG and up to 10 MINION_STATS_CHANGED. The counter can fall outside the window and then plays after the cascade instead of with the lunge.
  - Plausible, but not traced in a real fight. Task 115 (roadmap F2, consume by cause) is the real fix. This task only removes noise.

### Why this waits for tasks 061 and 135

The unconditional refresh hides stale labels today. It re-journals every slot on the next summon or death, which corrects a label left wrong by an un-journaled change:
- the Deathless save (task 061);
- Shield Regen at turn start (task 110, Phase E3b step 1: `on_turn_start` sets `current_shield` with no event, MinionInstance.gd:252-255).

Removing the refresh first would leave those labels wrong until the next event for that minion. Task 135 (roadmap I8) is the probe that proves no such case is left.

## Proposed fix

1. **Measure first.** Add temporary instrumentation in `CombatSim.run`, reading `state.journal` before `teardown()`. Don't commit it, unless a `--journal-stats` flag on BalanceSimBatch turns out to be cheap to keep.
   - Per fight: total events, MINION_STATS_CHANGED count, LOG count.
   - Run `BalanceSimBatch -- --act <N> --runs 200 --seed 7` for Acts 1–4 and record each act's averages and wall time in the work log.
2. **No-op recompute.** In `_refresh_presence_auras_for_side` (CombatHandlers.gd:1020-1081):
   - Return before the snapshot when `groups.is_empty() and strip_tags.is_empty()`. Nothing is stripped or applied, so state is unchanged.
   - Otherwise, take `CombatState.minion_stat_payload(m)` (atk, hp, shield; CombatState.gd:128-131) for each minion before the strip, and call `_refresh_slot_for(m)` only for minions whose payload changed. Today's VFX test (atk delta / HP-cap delta) misses a change to current HP or shield.
   - Keep the VFX rule as it is.
3. **LOG in the sim, only if step 1 shows it matters.** Decide from the numbers; record the decision either way.
   - Add `CombatConfig.journal_logs: bool = true`. `setup_combat` copies it to the state, and `_log` journals LOG only when it is true. It always emits `combat_log`, which CombatDiagnostics prints (sim/CombatDiagnostics.gd:24).
   - BalanceSimBatch's path (`CombatSim.run_many`) sets it false.
   - Parity, LiveSmoke, replay, tests and live keep it true. Parity prints the engine's LOG lines on failure (`_log_between`, ParityTests.gd:358-366).
   - The message is still formatted at each call site (`"…" % [...]` runs before `_log` is called). The saving is the CombatEvent allocation and the journal append only.
4. Nothing else changes: other `_refresh_slot_for` callers keep journaling as they do.

### Latent, noticed while re-checking (not in scope)

A BUFF_HP presence aura would heal on every recompute. The strip (`BuffSystem.remove_source`, BuffSystem.gd:125-131) drops HP_BONUS without lowering `current_health`. The re-apply (`apply_hp_gain`, :116-121, via EffectResolver.gd:491) raises `current_health` again. No card has one today: Rogue Imp Elder's aura is BUFF_ATK. Task 104's content check (roadmap D1, step 2) rejects BUFF_HP in `presence_aura_steps`; the recompute has to learn to strip HP correctly before such a card ships.

## Verification

- New TriggerHandlerTests probe `_presence_recompute_is_silent_without_auras`:
  - Setup: `TestHarness.build_state()`, `spawn_friendly(state, "void_imp")`, `spawn_enemy(state, "void_imp")`. Record `state.journal.size()`.
  - Action: summon a third minion with `state._summon_token("void_imp", "player")`.
  - Assert: no MINION_STATS_CHANGED for the two pre-existing minions among the new events (today one each).
- Same file, `_presence_recompute_refreshes_only_changed`:
  - Setup:
    - Summon onto the enemy side with `state._summon_token(..., "enemy")`, so the summon trigger applies the aura: `rabid_imp`, `imp_brawler` (both tagged `feral_imp`), a non-Feral minion such as `void_imp`, then `rogue_imp_elder`.
    - Record each minion's `effective_atk()` and the journal size.
  - Action: summon a second `rogue_imp_elder`.
  - Assert:
    - The two imps and the first Elder (tagged `feral_imp` too) each get exactly one MINION_STATS_CHANGED, with `atk` 100 above the recorded value (the `board_count` multiplier goes from 1 to 2).
    - The non-Feral minion gets none.
- If step 3 lands: a ScenarioTests probe runs one seeded `CombatSim.run` fight with `journal_logs` true and false. The digests are equal, and the false run's journal has no LOG event.
- LiveSmoke `_hp_labels_lag_the_engine` stays green. Task 135's idle-consistency probe stays green in Parity and LiveSmoke with no slot allowlist entries.
- `tools/run_checks.sh` green.
- Behaviour-neutral: only journal events go, and engine state is unchanged. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, Acts 1–4) diffs empty (design/TESTING.md 'Refactor / extraction work'). Record the measured journal-size and wall-time reduction in the task summary.

## Related

- Depends on: task 061 — journals the Deathless save. Until then, the refresh this task removes is what corrects that label.
- Depends on: task 135 (roadmap I8) — the idle-consistency probe. Land this task only when it runs with no slot allowlist entries.
- Related: task 110 (roadmap E3) — Phase E3b step 1 journals turn-start stat changes (Shield Regen), and step 5 also cares about journal volume. Land after that step: until it lands, task 135 keeps a Shield Regen slot allowlist entry, and this task waits for it to go. (Not in plan.json's depends_on; an ordering constraint.)
- Related: task 115 (roadmap F2) — consuming look-ahead by cause removes the 60-event window problem for good.
- Related: task 094 (roadmap B1) — its counters fold over the journal (CARD_PLAYED, SPELL_CAST, RITUAL_FIRED, DAMAGE_DEALT, …), not LOG. If step 3 lands, the `journal_logs` switch must drop only LOG.
- Related: task 132 (roadmap I4) — deletes dead signals. `_refresh_slot_for` also emits `minion_stats_changed` (CombatState.gd:122), and nothing connects to it.
- Related: task 049 — the journal is freed with its state once the cycles are broken. This task makes each journal smaller; 049 makes sure it is freed at all.
- Related: task 104 (roadmap D1) — its content check rejects a BUFF_HP presence aura (the latent heal above).
- Related: task 112 (roadmap E6) — adds one engine narration LOG per attack; step 1's LOG count should be taken after it if it has landed.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item I7 (the "sim journaling cost" part, unit I's I7d).
  - Re-check at `404b51c`: confirmed the unconditional refresh and the six registrations. Only Rogue Imp Elder has a presence aura. `_log` journals in every shell.
  - Added the Shield Regen case (task 110) to the stale labels the refresh masks.
  - The refresh test now compares the full stat payload, not only the caps.
  - Noted the latent BUFF_HP presence-aura heal.

## Summary

_(filled in at /task-done)_
