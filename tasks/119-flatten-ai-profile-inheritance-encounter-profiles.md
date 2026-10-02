---
id: "119"
title: Flatten AI profile inheritance: encounter profiles extend CombatProfile or an archetype base
status: backlog
area: ai
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item G3 (`design/refactors/ARCHITECTURE_ROADMAP.md` §G). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Encounter profiles are used as base classes. Tuning one encounter silently retunes others.

### The tree today

From `grep -m1 '^extends'` over `enemies/ai/` and `enemies/ai/profiles/`:

```
CombatProfile
├─ VoidScoutProfile (F10)
│  ├─ VoidCaptainProfile (F12)              VoidCaptainProfile.gd:22
│  ├─ VoidRitualistPrimeProfile (F13)       VoidRitualistPrimeProfile.gd:23
│  ├─ VoidChampionProfile (F14)             VoidChampionProfile.gd:24
│  ├─ AbyssSovereignProfile (F15 P1)        AbyssSovereignProfile.gd:20
│  └─ AbyssSovereignPhase2Profile (F15 P2)  AbyssSovereignPhase2Profile.gd:16
├─ FeralPackProfile (F1)
│  ├─ MatriarchProfile (F3)                 MatriarchProfile.gd:20
│  ├─ MatriarchAggroProfile (F3, deck f3_b) MatriarchAggroProfile.gd:12
│  └─ MatriarchSacProfile (F3, deck f3_c)   MatriarchSacProfile.gd:9
├─ SerisPlayerProfile (player bot)
│  └─ FleshcraftPlayerProfile               FleshcraftPlayerProfile.gd:14
├─ ScoredCombatProfile (+ 4 scored profiles; task 120 deletes them)
└─ 18 other profiles extend CombatProfile directly
```

The review named only the VoidScout family; the Matriarch profiles extending F1's FeralPackProfile were missed.

### What is inherited

- **AbyssSovereign P1** defines only `_spark_spell_priority`, `can_cast_spell` and `_board_crit_count`; **P2** only `_spark_spell_priority`. Both run VoidScout's `play_phase` (VoidScoutProfile.gd:22-39), its `_get_spell_rules` (`void_wind: never`, :44-47) and its growth curve. CommandTests' `abyss_sovereign` and `abyss_sovereign_p2` rows equal the `void_scout` row.
- **VoidCaptain, VoidRitualistPrime, VoidChampion** override `play_phase` but call VoidScout's helpers: `_play_heralds`, `_play_regular_minions`, `_plan_spark_payment_no_crit`, `_try_void_wind`, `_play_spark_spells`, `pick_on_play_target`, `_pick_highest_atk_friendly`.
- **The Matriarch profiles** inherit FeralPack's `attack_phase`, `_calc_lethal_with_pack_frenzy`, `_find_pack_frenzy` and `_is_feral_imp`. MatriarchProfile also inherits F1's `play_phase` and `_get_spell_rules`.

### Consequence

- Tuning F10 changes 4 more encounters (F12–F15, 5 profiles); tuning F1 changes F3.
- The leak has already shipped bugs. F14 and F15 hold their spark spells unless the player has 2+ minions, because they inherit F10's Rift Collapse gate (VoidScoutProfile.gd:187). That is task 072.
- VoidRitualistPrime had to re-implement the loop to escape the gate (VoidRitualistPrimeProfile.gd:55-58).

## Proposed fix

Do this after tasks 117 and 118. Curves are then data and the spark loop takes options, so the change is mostly re-parenting.

1. **`VoidCastleProfile`** (extends CombatProfile), the generic Act-4 crit/spark archetype. Put archetypes in `enemies/ai/archetypes/` so that `profiles/` holds only registered ids.
   - It holds the helpers VoidScout's children use: `_pick_crit_target`, `_pick_highest_atk_friendly`, `pick_on_play_target`, `_play_heralds`, `_play_regular_minions`, `_plan_spark_payment_no_crit`, `_play_spark_minions`, `_play_spark_spells` (gate as an option, task 118), `_try_void_wind`, `_is_tempo() -> true`, and the `void_wind: never` rule.
   - It has no play order and no curve. Each encounter declares its own.
2. **VoidScoutProfile** (F10) extends VoidCastleProfile and keeps only F10: its play order, its curve (E5 M2, else E) and its Rift Collapse gate.
3. **Re-parent** VoidCaptain, VoidRitualistPrime, VoidChampion, AbyssSovereign and AbyssSovereignPhase2 onto VoidCastleProfile. Each declares its own play order, growth curve (task 117's hooks) and spark gate. AbyssSovereign P1/P2 copy today's VoidScout `play_phase` and curve explicitly, as fixed by task 072. The `abyss_sovereign` / `abyss_sovereign_p2` growth rows must not change.
4. **`FeralImpPackProfile`**, extracted from FeralPackProfile: `attack_phase`, `_calc_lethal_with_pack_frenzy`, `_sim_face_damage_with_swift_guards`, `_min_overkill_idx` and the pack-frenzy helpers with task 118's threshold / survival hooks.
   - FeralPackProfile (F1) and the three Matriarch profiles (F3) extend it.
   - F1's play order and `_get_spell_rules` stay in FeralPackProfile. MatriarchProfile states the play order and spell rules it inherits today.
5. **SerisPlayerProfile** stays a base for FleshcraftPlayerProfile: same hero, two decks. Allowlist it as an archetype.
6. **Guard, as a test rather than a new lint number.** Probe `_profiles_extend_an_archetype`, in task 139's `debug/tests/AiBehaviourTests.gd` (or CommandTests.gd): for every script in `ProfileRegistry.ENEMY` and `ProfileRegistry.PLAYER`, `get_base_script()` is CombatProfile, VoidCastleProfile, FeralImpPackProfile or SerisPlayerProfile.
   - If a lint is preferred, extend L7 (the AI profile table rule, `tools/lint/lint_engine.py`), which task 140 also widens, rather than taking a new number.
7. **ARCHITECTURE.md AI table:** add an "Archetype bases" row, and state that an encounter profile never extends another encounter.

## Verification

- `_profiles_extend_an_archetype` passes, and fails when an encounter profile is pointed at another encounter (check once locally, revert).
- Task 139's per-profile probes and task 072's F12/F14/F15 probes pass unchanged.
- CommandTests `_GROWTH_CURVES` rows unchanged.
- `tools/run_checks.sh` green. Parity's F13 and F15 cases cover Act 4; F1 and F3 cover the feral family.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4) diffs empty (design/TESTING.md 'Refactor / extraction work'). Request Acts 3 and 4 explicitly; Act 1 covers F1/F3 and Act 4 covers F10–F15. Any diff is a regression.

## Related

- Depends on: task 117 (roadmap G1) — curves as data; each re-parented profile declares a curve instead of copying a grow function.
- Depends on: task 118 (roadmap G2) — the option-driven spark loop and the pack-frenzy hooks; after them the archetypes are small.
- Depends on: task 047 — enemy decks in the repo, so the fingerprint is stable.
- Depends on: task 072 — fixes the inherited spark gate first, so this task doesn't have to preserve a known-wrong behaviour.
- Depends on: task 139 (roadmap J3) — per-profile decision probes pin each re-parented profile.
- Related: task 120 (roadmap G4) — deletes the ScoredCombatProfile chain, the other base-class chain.
- Related: task 140 (roadmap J4) — widens L7; the place for this guard if it becomes a lint.
- Related: task 121 (roadmap G5), task 122 (roadmap G7) — the other AI-structure tasks; order-independent with this one.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item G3.
  - Re-checked the tree at `404b51c`: 5 VoidScout children over 4 encounters (the review said "five bosses").
  - Added the missed FeralPack → Matriarch chain, and SerisPlayer → Fleshcraft as an allowed player archetype.
  - The inheritance guard is a test, so it doesn't take a lint number.

## Summary

_(filled in at /task-done)_
