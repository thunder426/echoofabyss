---
id: "016"
title: PR3 — hero corruption + corrupting_presence one-shot AB rewrite + UI badges
status: done
area: combat
priority: normal
started: 2026-05-09
finished: 2026-05-09
---

## Description

Closes the audit-flagged hero-corruption gap and rewrites corrupting_presence to a one-shot model. Today abyssal_strike, path_of_ruination's spell half, and corrupting_presence all early-return on hero targets, and corrupting_presence's armour-strip is a live read at damage time (cleansing corruption silently restores armour). Under the new model, corrupting_presence emits a permanent +100 ARMOUR_BREAK stack at the moment a corruption stack is applied to an **enemy** target (any source while the talent is active — abyssal_strike, path_of_ruination, future); cleansing the corruption later does not unwind the AB. Damage math returns to the simple two-bucket form (armour vs AB), dropping the corrupt_strip parameter from `_apply_armour_math`. Hero corruption logic lands: abyssal_strike applies corruption to the enemy hero, path_of_ruination amplifies hero-targeting spell damage by 100×stacks and applies a stack post-hit (DAMAGE_HERO + the DAMAGE_MINION enemy_hero string branch + VOID_BOLT all hook in), and `state._corrupt_hero(side)` parallels `_corrupt_minion`. UI: replace the separate Armour and Armour Break badges on PlayerHeroPanel + EnemyHeroPanel with a single icon driven by signed net = `armour - sum(AB)` — positive → green Armour icon, negative → red Armour Break icon, zero hides. Add a Corrupt ×N row alongside (separate stat). Mirror the merged display on BoardSlot's minion status bar.

## Work log

- 2026-05-09: opened.
- 2026-05-09: closed.

## Summary

Rewrote corrupting_presence from a live damage-time armour-strip to a one-shot AB emission: when a Corruption stack is applied to an enemy target (via `_corrupt_minion` or new `_corrupt_hero`) while the talent is active, BuffSystem also drops a permanent +100 ARMOUR_BREAK stack tagged `"corrupting_presence"`; cleansing the corruption later does not unwind the AB (separate debuffs after creation). Damage math returned to the simple two-bucket form — `_apply_armour_math` lost its `corrupt_strip` parameter and the corruption-read branch in `_deal_damage` is gone. Hero-corruption logic landed end-to-end: `state._corrupt_hero(side)` parallels `_corrupt_minion`; abyssal_strike now corrupts the enemy hero on attack; path_of_ruination amplifies DAMAGE_HERO / DAMAGE_MINION enemy_hero / VOID_BOLT spell paths by 100×stacks on the enemy hero and applies a stack post-hit. UI consolidation: PlayerHeroPanel / EnemyHeroPanel / BoardSlot status bar now show a single net-armour icon (positive → green Armour, negative → red Armour Break, zero hides) plus a separate `Corrupt ×N` badge row. CombatScene + SimState corruption_removed listeners loosened to `Object` and skip non-minion targets (heroes refresh via hero_buff_changed). 14 new tests + 2 rewritten minion tests; RunAllTests 644 pass / 3 pre-existing KNOWN BUGs failing. Balance-sim act 1 slice clean (no Korrath presets in act 1 today, so no Branch 3 win-rate delta to read).

Follow-ups: hero-corruption VFX (panel flash on apply / on cleanse) is intentionally not in this PR — ship as polish later. Cleanse / dispel still strip both CORRUPTION and ARMOUR_BREAK as DEBUFF_TYPES; if a future card needs to scrub corruption only, add a targeted `BuffSystem.remove_type(target, CORRUPTION)` call rather than a generic cleanse. When Korrath presets ship in BalanceSimBatch, run a full matrix to baseline the Branch 3 win-rate change.
