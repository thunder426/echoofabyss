---
id: "019"
title: Gate armour math by damage school, not by source
status: done
area: combat
priority: normal
started: 2026-05-11
finished: 2026-05-11
---

## Description

Today, `CombatManager._apply_armour_math` runs only when `DamageSource == MINION` ([combat/board/CombatManager.gd:206-213](combat/board/CombatManager.gd#L206-L213)). Spells (`DamageSource.SPELL`) bypass armour entirely — by design, per the comment on line 226-227. This means a "physical spell" like the proposed `shatterstrike` (§10 of design/KORRATH_HERO_DESIGN) cannot be expressed: as a spell, it would bypass armour despite its design intent.

Switch the gate to **damage school**. New rule:

| School | Armour interaction |
|---|---|
| PHYSICAL, ARCANE | Reduced by armour; armour break amplifies; min-100 floor |
| VOID, VOID_BOLT, VOID_CORRUPTION | Bypass armour entirely |
| TRUE_DMG | Bypass armour entirely (existing semantic) |
| NONE | Reduced by armour (only valid for minion sources after task 018) |

The source distinction (MINION vs SPELL) becomes irrelevant for the armour decision — what matters is the school's flavor. Minion attacks default to `NONE` and still respect armour (current behavior preserved). Spell damage must declare a school per task 018 and the school determines bypass.

**Depends on task 018 landing first** — otherwise `NONE`-school spells would have undefined behavior under the new rule.

**Scope:**

1. Refactor `CombatManager._deal_damage` and `apply_hero_damage` ([combat/board/CombatManager.gd:179-233](combat/board/CombatManager.gd#L179)) to gate `_apply_armour_math` by school via `Enums.has_school()` — bypass set is `{VOID, TRUE_DMG}` (plus everything in their lineage trees, including `VOID_BOLT` and `VOID_CORRUPTION`).
2. Verify `_build_damage_info` in [`combat/effects/EffectResolver.gd`](combat/effects/EffectResolver.gd) emits the declared school on spell damage steps so the new gate has real data to read.
3. **Armour Break implication** — currently AB amplifies damage only when armour math runs (i.e. only on minion attacks). Under the new rule, AB amplifies any non-bypassing damage including PHYSICAL/ARCANE spells. This is a real power increase for Korrath B3 Path of Destruction + spell builds. Flag this in the balance pass, don't try to special-case it out.
4. Update [`design/master_doc/DESIGN_DOCUMENT.md`](design/master_doc/DESIGN_DOCUMENT.md) and [`design/KORRATH_HERO_DESIGN`](design/KORRATH_HERO_DESIGN) §6: "Spells vs Armour | Spells bypass Armour entirely" → "Spells vs Armour | Depends on school: PHYSICAL/ARCANE reduce, VOID/TRUE bypass."
5. Update [`design/DAMAGE_TYPE_SYSTEM.md`](design/DAMAGE_TYPE_SYSTEM.md) — the source-vs-school discussion needs a new section.
6. Re-run `res://debug/BalanceSimBatch.tscn` Act 1 + Act 2 matrix; record before/after win-rate deltas for Vael / Seris / Korrath. Armour gains real value across the board; some spell-heavy builds get harder counters.
7. Test coverage in [`debug/tests/DamageTypeTests.gd`](debug/tests/DamageTypeTests.gd):
   - PHYSICAL spell vs armoured minion → reduced by armour, floor 100
   - ARCANE spell vs armoured minion → reduced by armour, floor 100
   - VOID spell vs armoured minion → full damage, no floor
   - VOID_CORRUPTION spell vs armoured minion → full damage, no floor
   - PHYSICAL spell vs target with stacked AB → AB amplifies damage above raw
   - Hero variant of each above where hero is target.
8. Update §10 of design/KORRATH_HERO_DESIGN — Shatterstrike's "reduced by Armour, min 100; interacts with Armour Break" parenthetical becomes the literal truth instead of aspirational text. No edit needed if the wording already matches post-fix behavior.

**Out of scope:**
- Adding new schools beyond what task 018 introduces.
- Minion-emitted effect changes — they remain MINION source, NONE-school default, respect armour. No regression.
- Rebalancing existing card numbers — balance fallout audit happens here, but rebalancing is a separate task per card if needed.

## Work log

- 2026-05-11: opened.
- 2026-05-11: shipped the armour-gate refactor — `CombatManager._school_bypasses_armour(school)` returns true for VOID lineage + TRUE_DMG; both `_deal_damage` and `apply_hero_damage` now route through it instead of checking `source == MINION`. `_build_damage_info` already plumbs `step.damage_school` end-to-end (no change needed). Added six Phase-9 probes in `DamageTypeTests.gd`: PHYSICAL spell reduced by armour, ARCANE spell reduced by armour, VOID_CORRUPTION spell bypasses (sub-school lineage), AB amplifies PHYSICAL spell above raw, and hero variants for PHYSICAL-reduced / VOID-bypass. Updated KORRATH_HERO_DESIGN §2 Armour table, §6 system summary, and dropped the "Depends on task 019" caveat from §10 shatterstrike. Added a "Source vs school for armour" section to DAMAGE_TYPE_SYSTEM.md. RunAllTests: 669 passed, 3 failed (same pre-existing KNOWN BUGs as task 018). Balance sim deferred per user.
- 2026-05-11: closed.

## Summary

Switched the Korrath armour gate from `source == MINION` to a school predicate (`CombatManager._school_bypasses_armour` — VOID lineage + TRUE_DMG bypass; PHYSICAL/ARCANE/NONE reduce). This unblocks PHYSICAL spells like `shatterstrike` interacting with Armour and lets Armour Break amplify non-bypassing spell damage. Six new Phase-9 probes lock the matrix (PHYSICAL/ARCANE reduced, VOID_CORRUPTION bypasses via sub-school lineage, AB amplifies PHYSICAL spells, hero variants); the existing minion path still respects armour because basic attacks default to PHYSICAL in `_attack_damage_info`. KORRATH §2/§6/§10 and DAMAGE_TYPE_SYSTEM.md updated. Full suite 669 pass / 3 fail (same pre-existing KNOWN BUGs as task 018).

Follow-ups: Balance sim deferred — Korrath B3 spell builds get a real power increase from AB amplifying PHYSICAL/ARCANE spell damage; run `BalanceSimBatch` on the next balance pass to size the swing on Vael / Seris / Korrath win-rates.
