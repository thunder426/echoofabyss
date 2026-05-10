---
id: "015"
title: PR2 — hero AB handlers + Armour/AB badges + tests
status: done
area: combat
priority: normal
started: 2026-05-09
finished: 2026-05-09
---

## Description

Second of two PRs implementing task 007 (hero Armour and Armour Break). Builds on PR1 (task 014) which already extracted HeroState, loosened BuffSystem to accept hero targets, and added the shared armour-math helper. This PR removes the early-returns in commanders_reach and path_of_destruction so they apply Armour Break to enemy hero targets, adds Armour and Armour Break badges to PlayerHeroPanel and EnemyHeroPanel (icons already in assets/art/icons), wires hero-armour-changed and hero-buff-changed signals on CombatState so the badges update live, and adds unit tests covering hero AB application + the hero side of the shared armour math (reduction, AB-strip, 100-floor, AB-overflow-as-bonus, spell-bypass).

## Work log

- 2026-05-09: opened.
- 2026-05-09: closed.

## Summary

Wired commanders_reach (100 AB) and path_of_destruction (50 AB) to apply Armour Break to the enemy hero on attack, replacing their early-returns with hero-target branches that route through new `CombatState.apply_hero_buff(side, type, amount, source)` and `CombatState.add_hero_armour(side, amount)` wrappers. Added `hero_armour_changed(side, value)` and `hero_buff_changed(side)` signals on CombatState; CombatScene forwards them into a new `CombatUI._refresh_hero_korrath_badges()` subscriber that reads HeroState + BuffSystem totals and pushes them to a new `update_korrath_debuffs(armour, armour_break)` method on PlayerHeroPanel and EnemyHeroPanel — both panels now show hidden-when-zero Armour and Armour Break badge rows mirroring the void-mark pattern. Added 8 unit tests in TriggerHandlerTests covering hero AB application from both handlers, hero armour reduction of MINION-source damage, spell bypass, AB overflow → bonus damage, the 100-damage floor, and signal emission for both new wrappers. RunAllTests: 630 pass / 3 pre-existing KNOWN BUGs failing (no new regressions, +13 over PR1 baseline). Balance-sim act 1 slice ran clean.

Follow-ups: abyssal_strike's hero-target gap (corruption-on-hero, [CombatHandlers.gd:344](combat/events/CombatHandlers.gd#L344)) remains open per the audit — it's a corruption issue, not armour, and is its own task.
