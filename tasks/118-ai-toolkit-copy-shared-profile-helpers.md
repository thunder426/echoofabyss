---
id: "118"
title: AI toolkit: one copy of the shared profile helpers
status: backlog
area: ai
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item G2 (`design/refactors/ARCHITECTURE_ROADMAP.md` §G). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Profiles copy play-loop and query helpers from each other and then tune them. Some copies are identical, some differ by one constant, and the spark and minion loops have split into 3–6 variants each. Groups below come from `rg -n '^(static )?func NAME\b' enemies/ai` plus a comparison of comment-stripped bodies.

### Identical or trivially different copies

- `_empty_slot_count` ×5 (RiftStalker:256, VoidAberration:72, VoidHerald:111, VoidScout:95, VoidWarband:206). All are `return agent.empty_slot_count()`. 24 call sites.
- `_play_spell_by_id` ×3, identical (CorruptedBroodRune:154, CultistPatrolTempo:219, MatriarchSac:101).
- `_find_pack_frenzy` ×3, identical (FeralPack:144, ScoredCorruptedBrood:67, ScoredFeralPack:178). VoidChampion:205 `_find_in_hand(id)` is the general form.
- `_play_spells_by_id` ×5. Korrath:113, RuneTempo:165, Seris:182 and Swarm:227 are identical; SpellBurn:387 differs only by task 051's counter and `_pending_dmg_source` writes.
- `_is_feral_imp` ×5 with two signatures:
  - `(mc: MinionCardData)`: CorruptedHandler:263, VoidRitualist:153 `return "feral_imp" in mc.minion_tags`;
  - `(m: MinionInstance)`: FeralPack:150, FeralPackScreech:82, ScoredFeralPack:184 `return agent.state != null and agent.state._minion_has_tag(m, "feral_imp")`;
  - plus CultistPatrol:118 `_card_is_feral_imp`. All mean the same: `_minion_has_tag` is the card-tag check (CombatState.gd:201-206). The base also calls `agent.state._minion_has_tag` directly (CombatProfile.gd:349, :881).
- `_play_minions_by_id` ×6, 4 bodies (Korrath:91 = Seris:160 = Swarm:204; CorruptedHandler:157; RuneTempo:143; SpellBurn:360). They differ only in the cost check:
  - effective Essence + raw Mana (CorruptedHandler);
  - effective Essence + effective Mana (Korrath, Seris, Swarm);
  - raw `mc.essence_cost` + effective Mana (RuneTempo, SpellBurn).

  Unifying on effective costs is byte-identical today. `effective_minion_mana_cost` returns raw `mc.mana_cost` (CombatAgent.gd:189-190; StateAgent doesn't override it). The only player Essence discount, Fiendish Pact (`minion_essence_cost`, CombatState.gd:2967-2969), is only in the Seris presets (PresetDecks.gd:75, :94, :112), which the `fleshcraft` and `seris` bots play.
- `_should_cast_pack_frenzy` ×6, 4 bodies. FeralPack:45 = ScoredFeralPack:84, and MatriarchAggro:66 = MatriarchSac:65; those two pairs differ only in the threshold (`_FERAL_IMP_THRESHOLD := 3`, FeralPackProfile.gd:20, vs `MATRIARCH_FERAL_THRESHOLD := 2`). Matriarch:39 adds a low-HP survival clause; ScoredMatriarch:11 calls super, then its own clause.
- `_spark_spell_priority` ×8, 4 distinct tables (AbyssSovereign:23 = AbyssSovereignPhase2:19 = VoidRitualistPrime:48; VoidCaptain:155 = VoidChampion:28; VoidHerald:336 = VoidAberration:192; RiftStalker:447). Only 4 copies are called (VoidHerald:255, VoidRitualistPrime:73, VoidAberration:146, RiftStalker:400). The VoidCaptain, VoidChampion, AbyssSovereign and AbyssSovereignPhase2 tables are dead, although their headers describe them as the bosses' spark order. Task 072 makes the F14 and F15 ones live.

### Tuned loop variants

- `_play_spark_spells` ×6, all different (VoidHerald:242, VoidRitualistPrime:58, VoidWarband:479, VoidScout:186, VoidAberration:133, RiftStalker:387), plus a 7th copy under another name, VoidCaptain's `_play_spark_spells_aoe` (:98, with its own copy of the 2+ gate at :99-100; task 072 narrows it to Rift Collapse). They differ in:
  - the gate: VoidScoutProfile.gd:187 `if agent.state._opponent_board("enemy").size() < 2:` / `return`;
  - ordering: priority table vs hand order;
  - the fuel planner: the base `_plan_spark_payment`, VoidScout's `_plan_spark_payment_no_crit` (:250), or VoidWarband's (:504, which calls its own `_plan_spark_payment_warband`);
  - the `DeckType` passed to `_pay_sparks_smart` (TEMPO vs AGGRO);
  - zero-spark-cost handling: VoidHerald and VoidRitualistPrime skip payment `if sc > 0:`.
- `_play_regular_minions` ×5 (VoidHerald:307, VoidChampion:226, VoidScout:275, VoidAberration:104, RiftStalker:341), `_play_spark_minions` ×3 (VoidAberration:163, VoidScout:215, RiftStalker:416), `_play_spark_minion_by_id` ×3 (VoidHerald:272, VoidWarband:453, VoidCaptain:130): all different.
- `_try_void_wind` ×3, 2 bodies (VoidHerald:59 = VoidAberration:80; VoidScout:50).

### The copied mana_for_spark rule

Not covered by task 051, which only moves the spark *cost* to the engine.
- AI copies: CombatProfile.gd:995-1004 `_mana_for_spark_shortfall`, the shortfall branch of `_plan_spark_payment` (:1049-1055), and VoidChampionProfile.gd:211-213 `_has_mana_for_spark`. All read `agent.state.enemy_passives`, whatever side the agent plays.
- Engine: `plan_cost` checks it twice, CombatState.gd:3028 and :3035 `if side == "enemy" and "mana_for_spark" in enemy_passives:`.
- Consistent today: only F14 has the passive (EncounterTable.gd:133).

### Consequence

A fix to one copy has to be found and repeated in 3–6 files. Copies drift silently: VoidRitualistPrime re-implemented VoidScout's spark loop to dodge its gate (VoidRitualistPrimeProfile.gd:55-56 `## Override parent gate: parent skips all spark spells when opponent board < 2.` / `## We want Void Pulse (draw) to fire regardless, ...`), and task 072's F12/F14/F15 bug is that same gate, inherited.

## Proposed fix

Two parts, each its own commit with its own gate run. Every merge must be byte-identical. A copy that can't be merged without a behaviour change stays as an override, with a one-line comment saying why.

### Part 1: identical copies (S)

1. Delete the five `_empty_slot_count` aliases; callers use `agent.empty_slot_count()`.
2. Add one tag query to the agent: `has_tag(card_or_minion, tag) -> bool` (base in CombatAgent; StateAgent delegates to `_card_has_tag` / `_minion_has_tag`). Replace the 5 `_is_feral_imp` copies, CultistPatrol's `_card_is_feral_imp`, and the base's `agent.state._minion_has_tag` (CombatProfile.gd:349, :881). Drop the dead `agent.state` null-guards there and at :645 and :1166; StateAgent always has a state.
3. Move `_play_spells_by_id`, `_play_spell_by_id` and `_find_in_hand(id)` into CombatProfile. `_find_in_hand("pack_frenzy")` replaces the `_find_pack_frenzy` copies, and VoidChampion's copy goes.
4. One `_play_minions_by_id(ids)` in CombatProfile on `agent.effective_minion_essence_cost` and `agent.effective_minion_mana_cost`.
5. `_spark_spell_priority(id)` lives once in the base and reads a per-profile `_spark_priority() -> Dictionary`. Delete VoidCaptain's table (:155): its `_play_spark_spells_aoe` never reads it, before or after task 072. Keep VoidChampion's and the two AbyssSovereign tables as data, because task 072 makes them live (if 072 hasn't landed yet, they are still dead but must not be deleted).
6. `_should_cast_pack_frenzy` once on FeralPackProfile, with `_pack_frenzy_threshold()` and `_pack_frenzy_survival()` hooks for FeralPack, MatriarchAggro / MatriarchSac and Matriarch.
7. One mana_for_spark rule:
   - Extract the engine's into a public `CombatState.spark_shortfall_mana(side, sparks, paid) -> int` (−1 when refused) and use it in both `plan_cost` branches.
   - Add `agent.spark_mana_shortfall(spark_cost, paid) -> int` (StateAgent delegates).
   - Use it in `_mana_for_spark_shortfall`, `_plan_spark_payment` and VoidChampion's `_has_mana_for_spark`.

### Part 2: tuned loop variants (M)

8. One `_play_spark_spells(opts)` in the base, or on task 119's archetype base if that has landed. Options: ordering (priority table or hand order; best pick, or first fit then break), gate (none, opponent board ≥ N, or a per-id predicate), zero-spark-cost handling, fuel planner and `DeckType`. Each of the 7 copies (VoidCaptain's `_play_spark_spells_aoe` included) passes the options that reproduce its current body, as fixed by task 072 where it has landed.
9. The same for `_play_regular_minions`, `_play_spark_minions`, `_play_spark_minion_by_id` and `_try_void_wind`.

### Not in this task

- The stale `"void_summoning"` id in `_spell_needs_board_slot` (CombatProfile.gd:366): task 081.
- Validating `cast_if` values and spell-rule keys: task 104.
- The scored copies (ScoredFeralPack, ScoredCorruptedBrood, ScoredMatriarch): task 120 deletes them. If it hasn't landed, leave them alone.
- CorruptedHandlerProfile's header (:8, :16-17) and attack-phase comment (:54) say feral imps are played after the attacks; the code plays them at the end of `play_phase` (:44-46). That is an owner / balance call: keep the code's behaviour (task 139 pins it) and don't "fix" it while merging helpers.

## Verification

- New probe `_ai_toolkit_uses_engine_costs`, in task 139's `debug/tests/AiBehaviourTests.gd` if it has landed, otherwise `debug/tests/CommandTests.gd`:
  - An enemy state with `enemy_essence_cost_discounts[id] = 1` and Essence equal to the discounted cost. `_play_minions_by_id([id])` places the minion.
  - `agent.has_tag` agrees for a `MinionCardData` and a MinionInstance of it.
- New probe `_mana_for_spark_one_rule`: `build_state({"enemy_passives": ["mana_for_spark"]})`. On the enemy agent `spark_mana_shortfall(3, 1) == 2`; on the player agent it is −1. (The engine rule is enemy-only today; task 090 makes passives per side.)
- Task 139's per-profile probes pass unchanged after each part.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4; request 3 and 4 explicitly) diffs empty (design/TESTING.md 'Refactor / extraction work'). Any diff means a copy was merged wrongly.

## Related

- Depends on: task 051 — removes SpellBurn's writes, the only difference between the `_play_spells_by_id` copies, and deletes `_effective_spark_cost`.
- Depends on: task 047 — enemy decks in the repo, so the fingerprint is stable.
- Depends on: task 139 (roadmap J3) — per-profile decision probes catch a wrongly merged rare branch that aggregate win rates miss.
- Related: task 072 — fixes the F12/F14/F15 spark gate and makes the F14/F15 priority tables live.
- Related: task 119 (roadmap G3) — depends on this task; its archetype bases host the Act-4 and feral helpers.
- Related: task 121 (roadmap G5) — depends on this task; fewer copies to strip awaits from.
- Related: task 122 (roadmap G7) — depends on this task; `agent.has_tag` and `agent.spark_mana_shortfall` become part of its side-aware API.
- Related: task 120 (roadmap G4) — deletes the scored copies.
- Related: task 081 (roadmap DL1) — removes `"void_summoning"`.
- Related: task 104 (roadmap D1) — validates `cast_if` values and spell-rule keys.
- Related: task 090 — per-side passives; the engine's mana_for_spark rule is enemy-only today.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item G2.
  - Re-checked the copy counts and grouped bodies at `404b51c`.
  - Corrected: `_spark_spell_priority` has 4 distinct tables, not 5. Most other "copies" are tuned variants.
  - Added the copied mana_for_spark rule (plan note) and the 5 extra helper families the review missed.
  - The `"void_summoning"` cleanup moved to task 081.

## Summary

_(filled in at /task-done)_
