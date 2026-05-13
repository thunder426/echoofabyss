---
id: "014"
title: Add VOID_CORRUPTION damage school
status: done
area: combat
priority: normal
started: 2026-05-09
finished: 2026-05-11
---

## Description

Add `VOID_CORRUPTION` as a sibling sub-school of `VOID` (parallel to existing `VOID_BOLT`) so corruption-themed damage can be amplified independently of generic Void damage. The motivating use case is restricting Seris Branch 3's `void_amplification` (T2) — currently "+50 spell damage per Corruption stack across all friendly Demons" applies to every spell school the player casts. After this change, only `VOID_CORRUPTION`-tagged spells benefit. Korrath Branch 3's `path_of_ruination` (T2) — "+100 spell damage per Corruption stack on the target" — has the same all-schools problem and inherits the same fix.

**Lineage:**

```
VOID (parent)
├── VOID_BOLT       — existing
└── VOID_CORRUPTION — new
```

`VOID_CORRUPTION` lineage entry: `[VOID_CORRUPTION, VOID]`. Existing `VOID_BOLT` damage does NOT auto-inherit `VOID_CORRUPTION` amps; future "+X to VOID damage" effects buff both siblings via `has_school()`.

**Scope:**

1. Add `Enums.DamageSchool.VOID_CORRUPTION` and its `SCHOOL_LINEAGE` entry ([shared/scripts/Enums.gd:171-188](shared/scripts/Enums.gd#L171)).
2. Update [`design/DAMAGE_TYPE_SYSTEM.md`](design/DAMAGE_TYPE_SYSTEM.md) — enum table, lineage example, "VOID-tagged today" inventory.
3. Retag corruption-themed spells from `VOID` to `VOID_CORRUPTION` in [`cards/data/CardDatabase.gd`](cards/data/CardDatabase.gd). Confirmed candidate: `abyssal_plague` (currently `VOID`). Audit: `flesh_rend`, `self_mutilation`, `resonant_outburst`, `recursive_hex`, `corruption_weaver`-related damage outputs, `font_of_the_depths`. Generic Void burst (`abyssal_plague` aside, also `void_execution`, `rift_collapse`, `void_lance`, `void_shatter`, `abyssal_summoning_circle` death effect, `_abyss_ritual_circle_passive`) stays `VOID`.
4. Update Seris `void_amplification` ([talents/TalentDatabase.gd:275-278](talents/TalentDatabase.gd#L275) + handler) so the +50/stack spell-damage amp checks `has_school(VOID_CORRUPTION, info.school)` instead of matching all spell schools. Update talent description text.
5. Same fix on Korrath `path_of_ruination` ([talents/TalentDatabase.gd:337-340](talents/TalentDatabase.gd#L337) + handler).
6. Sim parity — mirror any new handler logic into [`sim/SimTriggerSetup.gd`](sim/SimTriggerSetup.gd) if relevant.
7. Test coverage — extend [`debug/tests/DamageTypeTests.gd`](debug/tests/DamageTypeTests.gd) with: corruption-flavored spell amplified, generic VOID spell NOT amplified, VOID_BOLT NOT amplified, future-style "+VOID damage" hypothetical buffs both siblings.

**Out of scope:** UI surfacing of the school on cards (separate UI pass), and any rebalancing of corruption spell numbers — pure plumbing-and-tagging task.

## Work log

- 2026-05-09: opened.
- 2026-05-11: closed.

## Summary

Added `Enums.DamageSchool.VOID_CORRUPTION` as a sibling of `VOID_BOLT` under the `VOID` parent in `SCHOOL_LINEAGE`. Retagged four corruption-themed spells (`abyssal_plague`, `flesh_rend`, `flesh_eruption`, `resonant_outburst`) from VOID/NONE → VOID_CORRUPTION. Gated Seris's `void_amplification` amp (`CombatState._spell_dmg` and `cast_player_hero_spell`) and Korrath's `path_of_corruption` amp (`EffectResolver._path_of_corruption_amplify`) on `has_school(school, VOID_CORRUPTION)` so generic VOID and sibling VOID_BOLT damage no longer benefit. Talent descriptions updated to call out "VOID CORRUPTION" explicitly. Added lineage tests and end-to-end school-gate tests for both talents (including a "Void Bolt is no longer amplified but still applies corruption" test reflecting the deliberate scope reduction). Full suite: 655 passed, 3 failed (all pre-existing KNOWN BUGs unrelated to this change).

Follow-ups: tasks 018 (require school on every damaging spell + add ARCANE + lint) and 019 (gate armour math by school instead of source) are queued as backlog — both build on this taxonomy.
