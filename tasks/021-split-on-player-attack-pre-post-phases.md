---
id: "021"
title: Split ON_PLAYER_ATTACK into PRE/POST phases; move path_of_shattering to POST
status: done
area: combat
priority: normal
started: 2026-05-11
finished: 2026-05-12
---

## Description

The `ON_PLAYER_ATTACK` trigger currently fires once, before damage resolves, in `combat/board/CombatManager.gd`. Per the new AB-on-attack timing convention codified in `design/KORRATH_HERO_DESIGN` §11 (Banner of the Order + AB-residual ruling note), Path of Shattering should apply its 50 AB *after* the attack's damage resolves, so AB accumulates on targets across attacks and feeds Shattering Doom rather than being consumed each strike. Split the trigger into `ON_PLAYER_ATTACK_PRE` and `ON_PLAYER_ATTACK_POST` phases, move `path_of_shattering` to POST, leave `corrupting_strike` and `runeforge_strike` on PRE (their existing semantics don't change). Mirror the split to `sim/SimTriggerSetup.gd` for sim parity, update `Enums.gd`, and verify tests still pass.

## Work log

- 2026-05-11: opened.
- 2026-05-11: implemented. Enums split (`ON_PLAYER_ATTACK` → `ON_PLAYER_ATTACK_PRE` + `ON_PLAYER_ATTACK_POST`), mirror table updated (both player phases mirror to single `ON_ENEMY_ATTACK`). `CombatManager.resolve_minion_attack` and `resolve_minion_attack_hero` now fire PRE before damage and POST after defender's damage but before counter-attack/pierce. Handler reassignment in `CombatSetup`: `corrupting_strike` + `runeforge_strike` stay PRE, `path_of_shattering` moves to POST. Sim parity is automatic — `SimTriggerSetup` delegates to the same `CombatSetup.setup()`. Added new assertion `_path_of_shattering_ab_applied_after_damage` that proves defender keeps its pre-strike armour after the attack (would be stripped if PRE timing). Full suite: 674 passed / 3 pre-existing KNOWN BUG failures unchanged.
- 2026-05-12: closed.

## Summary

Split `ON_PLAYER_ATTACK` into `ON_PLAYER_ATTACK_PRE` and `ON_PLAYER_ATTACK_POST` phases so AB-residual handlers can apply armour after damage resolves instead of having it consumed by the same strike. `CombatManager` fires PRE before damage and POST after defender damage (before counter-attack/pierce) in both minion-vs-minion and minion-vs-hero paths; `corrupting_strike` and `runeforge_strike` stay on PRE, `path_of_shattering` moves to POST. Sim parity is automatic via `SimTriggerSetup` → `CombatSetup.setup()`; new assertion proves AB persists on the defender after the attack.
