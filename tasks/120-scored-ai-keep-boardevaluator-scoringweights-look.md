---
id: "120"
title: Scored AI: keep BoardEvaluator + ScoringWeights for look-ahead, delete the rest
status: backlog
area: ai
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item G4 (`design/refactors/ARCHITECTURE_ROADMAP.md` §G). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### What the scored stack is

1,129 lines in 7 files (`wc -l`):

| File | Lines |
|---|---|
| `enemies/ai/ScoredCombatProfile.gd` | 411 |
| `enemies/ai/BoardEvaluator.gd` | 293 |
| `enemies/ai/ScoringWeights.gd` | 124 |
| `enemies/ai/profiles/ScoredFeralPackProfile.gd` | 185 |
| `enemies/ai/profiles/ScoredCorruptedBroodProfile.gd` | 71 |
| `enemies/ai/profiles/ScoredMatriarchProfile.gd` | 36 |
| `enemies/ai/profiles/ScoredDefaultProfile.gd` | 9 |

- ScoredCombatProfile is a greedy one-step action scorer ("uses scoring to decide all actions", :2). Its "1-turn lookahead" is a formula for the opponent's best reply (`_estimate_opponent_response`, called at :218-222, defined at :250). It doesn't simulate a state.
- It can't play Acts 3–4. It refuses every spark-cost card (:126-127 `if mc.void_spark_cost > 0:` / `return -1.0`, and :144-145 for spells) and checks raw minion costs (:128 `if mc.essence_cost > agent.essence or mc.mana_cost > agent.mana:`). Profiles exist only for F1–F3 and a generic one.
- BoardEvaluator is pure static scoring over minion arrays and a ScoringWeights: `score_minion`, `score_board`, `predict_survives`, `predict_value_after_damage`, `estimate_effect_steps_value`. It holds no agent or state. Its header says "Works with any CombatAgent" (:3), but it takes no agent.

### Who uses it

- **Nothing that plays.** No encounter deck selects a scored profile: the 23 decks' `ai_profile` overrides are `feral_pack_screech`, `corrupted_brood_aggro`, `corrupted_brood_rune`, `matriarch_aggro`, `matriarch_sac`, `cultist_patrol_tempo` and `abyss_sovereign_p2` (machine-local `encounter_decks.json`, task 047). BalanceSimBatch takes the encounter's `ai_profile` (BalanceSimBatch.gd:253) or the deck's override (:277-279).
- **Registered anyway:**
  - ProfileRegistry.gd:33-37 (`scored`, `scored_feral_pack`, `scored_corrupted_brood`, `scored_matriarch` for the enemy) and :46 (`scored` for the player);
  - EncounterTable.gd:15, :24 and :33 list the scored ids as F1–F3 `variant_profiles`, and the comments at :4-5 and :10-11 mention them.
- **Tests:**
  - ScenarioTests S19 `_scored_ai_profile_smoke` (ScenarioTests.gd:453-467, called at :38) only asserts a clean finish.
  - CommandTests growth rows :658-661 and :666.
  - The `"scored"` skip in `_encounter_table_is_the_one_source` (:744).
- **`CombatProfile.get_weights()`** (:296-299) exists only for it; ScoredCombatProfile.gd:16-18 overrides it.
- **Awaits:** 30 of the 360 `await`s in `enemies/ai` are here (ScoredCombatProfile 12, ScoredFeralPack 9, ScoredCorruptedBrood 9).
- **`debug/ScoredAITest.gd` doesn't run it.** ScoredAITest.gd:1 `## ScoredAITest.gd — Voidbolt full run: ...`; it runs scripted profiles (:11-35) with the `spell_burn` player bot (:67-69, :79-81, :92-94).
- **The docs misdescribe it:**
  - ARCHITECTURE.md:237 (at `404b51c`) `| Scoring helpers | ... | Weighted-random decision support. |`;
  - ARCHITECTURE.md:312 `| debug/ScoredAITest.gd | Tests weighted-scoring AI profiles. |`;
  - DESIGN_DOCUMENT.md:933 `| Scoring-based AI | Infrastructure built (ScoredCombatProfile, BoardEvaluator, ScoringWeights) but not used in production encounters. Available for future use. |`.

Every engine migration has to keep this compiling and S19 green. It inflates the copy count task 118 dedupes and the await count task 121 strips.

### ScoringWeights after the deletion

BoardEvaluator reads 15 of the 21 weight fields. Six are read only by ScoredCombatProfile: `board_fill_bonus`, `lethal_bonus`, `overkill_penalty`, `lookahead_discount`, `resource_unlock_weight` and `action_threshold`. `duplicate_weights()` (:101) has no caller.

## Decision (owner, 2026-10-01)

Q7a: "Keep `BoardEvaluator` + `ScoringWeights` as the seed of the look-ahead evaluation function (give them a test); delete `ScoredCombatProfile` and the 4 scored profiles." Q7b: look-ahead is planned.

## Proposed fix

1. Delete `enemies/ai/ScoredCombatProfile.gd` and `enemies/ai/profiles/Scored{Default,FeralPack,CorruptedBrood,Matriarch}Profile.gd`, with their `.uid` files.
2. ProfileRegistry: drop the "Scored variants" block (:33-37) and the player `"scored"` entry (:46).
3. EncounterTable: drop the scored ids from F1–F3 `variant_profiles` (:15, :24, :33). Fix the comments at :4-5 and :10-11.
4. CombatProfile: delete `get_weights()` and its comment (:296-299).
5. Tests:
   - delete ScenarioTests S19 (:453-467) and its call (:38);
   - delete CommandTests rows :658-661 and :666;
   - drop `"scored"` from the skip list at :744.
6. Keep BoardEvaluator.gd and ScoringWeights.gd.
   - Fix BoardEvaluator's header: it scores minion arrays with a weights object, with no agent.
   - Keep all ScoringWeights fields: the owner keeps it as the seed. Say in its header which fields BoardEvaluator reads and that the other six are reserved for a policy.
7. Give BoardEvaluator its test (Verification, first bullet).
8. Rename `debug/ScoredAITest.gd` / `.tscn` to `debug/VoidboltFullRun.gd` / `.tscn`, which is what it is. Update design/TESTING.md :31 and :311-323. Task 141 (roadmap J5) later decides whether to delete it; if 141 has already deleted it, skip this step.
9. Docs:
   - ARCHITECTURE.md's "Scoring helpers" row: BoardEvaluator + ScoringWeights, static board / minion evaluation kept as the seed of the planned look-ahead (Q7); no profile uses them yet.
   - Its `debug/ScoredAITest.gd` row: the renamed tool.
   - DESIGN_DOCUMENT.md:933: the same, per Q7.

## Verification

- New probe `_board_evaluator_pins_scores`, in task 139's `debug/tests/AiBehaviourTests.gd` if it has landed, otherwise `debug/tests/CommandTests.gd`. Use `ScoringWeights.new()` and minions from `TestHarness.spawn_friendly` / `spawn_enemy` on a `build_state({})`.
  - Characterise: pin `score_minion` for three cards (a plain body, one with Guard, one with an on-death SUMMON), and `score_board` for one fixed pair of boards.
  - Side symmetry, which a look-ahead needs to score either side: with both boards non-empty, `score_board(A, B, hpA, hpB, hA, hB, w) == -score_board(B, A, hpB, hpA, hB, hA, w)`. The empty-board penalty (:66-67) is the one asymmetric term; pin it separately.
  - `predict_survives`: shield absorbs first, and a lethal hit on a Deathless minion survives. `predict_value_after_damage` returns 0.0 for a kill.
  - Pure: `state.digest_text()` is the same before and after scoring.
- Grep gate: `rg -n 'ScoredCombatProfile|Scored\w+Profile|get_weights|"scored' --glob '*.gd' --glob '*.tscn' .` → nothing.
- `tools/run_checks.sh` green. `load_all_scripts` compiles with no dangling reference.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1 and 2; the scored variants belong to F1–F3) diffs empty (design/TESTING.md 'Refactor / extraction work'). Nothing that runs selects these profiles, so any diff means something did.

## Related

- Related: task 139 (roadmap J3) — writes no probes for the scored profiles; the BoardEvaluator test goes in its file if it has landed.
- Related: task 141 (roadmap J5) — retires the stale debug sims, including the renamed Voidbolt full run.
- Related: task 104 (roadmap D1) — checks that every EncounterTable `variant_profiles` id exists in ProfileRegistry. A leftover scored id would otherwise fall back to `"default"` silently (ProfileRegistry.gd:58).
- Related: task 105 (roadmap D2) — migrates BoardEvaluator's three `EffectStep.from_dict` sites (:136, :252, :278) instead of deleting them.
- Related: task 089 (roadmap A8) — edits BoardEvaluator's `on_spell_cast_passive_effect_id` read (:291).
- Related: task 107 (roadmap D4) — limits any per-type value metadata to what BoardEvaluator reads.
- Related: tasks 117, 118 and 121 (roadmap G1, G2, G5) — one growth override, three helper copies and 30 awaits fewer once this lands.
- Related: tasks 049, 129 and 130 — the look-ahead prerequisites from Q7b.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item G4.
  - The owner's Q7a decision replaces the review's "delete or promote".
  - Re-checked at `404b51c`: line counts, registrations, tests, and the 23 decks (no scored override).
  - Added: the stale BoardEvaluator header, the six ScoringWeights fields only the deleted profile reads, and the ScoredAITest rename (plan note).

## Summary

_(filled in at /task-done)_
