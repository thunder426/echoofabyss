---
id: "018"
title: Require school on spell damage; add ARCANE; lint-enforce
status: done
area: combat
priority: normal
started: 2026-05-11
finished: 2026-05-11
---

## Description

Make `damage_school` a required field on every damage step emitted by a spell card (`SpellCardData`). Today, `NONE` is the implicit default — per CLAUDE.md, "Default `NONE` is correct for generic spells and minion-emitted effects." The user wants to flip that for **spells specifically**: every damaging spell must declare a flavor (PHYSICAL, ARCANE, VOID, VOID_BOLT, VOID_CORRUPTION, …). Minions can keep `NONE` as the default for basic attacks and minion-emitted effects.

This task is a prerequisite for task 019 (armour math gates by school) — otherwise NONE-school spells under the new armour rule have undefined behavior.

**Scope:**

1. Add `Enums.DamageSchool.ARCANE` and its `SCHOOL_LINEAGE` entry (`[ARCANE]`, no parent). Reserve numerically next to existing schools in [shared/scripts/Enums.gd:171](shared/scripts/Enums.gd#L171).
2. Update [`design/DAMAGE_TYPE_SYSTEM.md`](design/DAMAGE_TYPE_SYSTEM.md): enum table, lineage example, and the "Default school" section — flip the spell rule from "default NONE" to "must declare; load-time validation enforces."
3. Audit every `SpellCardData` in [`cards/data/CardDatabase.gd`](cards/data/CardDatabase.gd) that has a damage-dealing `effect_steps` entry (DAMAGE_MINION / DAMAGE_HERO / DAMAGE_ANY) — currently ~30 spells. Assign a school to each. Suggested mapping:
   - Abyss faction default → `VOID` (already mostly tagged).
   - Corruption-themed Abyss spells → `VOID_CORRUPTION` (after task 014 lands).
   - Neutral spells (`arcane_strike`, `purge`, `cyclone`, `precision_strike`, `hurricane`, `flux_siphon`, etc.) → `ARCANE` or `PHYSICAL` based on flavor.
   - New Korrath spell `shatterstrike` → `PHYSICAL`.
4. Add load-time validation: extend `CardDatabase`'s post-load pass to assert that every `SpellCardData` with a DAMAGE_* step has a non-NONE `damage_school`. Fail fast with a clear error pointing at the offending card. This is the "rule sticky long-term" enforcement — without it, the convention will rot.
5. Update [`design/master_doc/CARD_DESCRIPTION_STYLE.md`](design/master_doc/CARD_DESCRIPTION_STYLE.md) if it needs to reflect school being on every spell.
6. Update CLAUDE.md's "Default `NONE` is correct" note to reflect that the rule now only applies to minion-emitted effects, not spells.

**Out of scope:**
- Armour math changes (that's task 019).
- Minion audit — `NONE` remains valid for minion attacks and minion-emitted effects.
- UI surfacing of school on the card visual (separate UI pass).

## Work log

- 2026-05-11: opened.
- 2026-05-11: closed.

## Summary

Added `DamageSchool.ARCANE` (and its `SCHOOL_LINEAGE` entry) and flipped the spell convention from "NONE default" to "school required, lint-enforced." The 5 previously-untagged spells got schools (`arcane_strike`→ARCANE, `precision_strike`→PHYSICAL, `runic_blast`/`void_screech`/`sovereigns_decree`→VOID); `CardDatabase._validate_spell_damage_schools()` runs after registration and asserts on any `SpellCardData` DAMAGE_* step still on NONE, fail-fast at load. Updated [`design/DAMAGE_TYPE_SYSTEM.md`](design/DAMAGE_TYPE_SYSTEM.md), [`CLAUDE.md`](CLAUDE.md), and the Phase 7 damage-type probe (`arcane_strike` now asserts ARCANE instead of NONE). 661 tests pass; the 3 remaining failures are pre-existing KNOWN BUGs unrelated to this task. Minion-emitted effects, traps, rituals, and environments keep `NONE` as the default — only spells are gated.

Follow-ups: task 019 (armour math gates by school) can now safely assume every spell declares a non-NONE school.
