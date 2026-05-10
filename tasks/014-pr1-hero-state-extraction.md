---
id: "014"
title: PR1 — HeroState extraction + BuffSystem hero support + hero armour math
status: done
area: combat
priority: normal
started: 2026-05-09
finished: 2026-05-09
---

## Description

First of two PRs implementing task 007 (hero Armour and Armour Break). Pure refactor with no externally visible behavior change for non-Korrath play. Extracts a small `HeroState` (RefCounted) holding `hp`, `hp_max`, `armour`, `buffs`; routes the existing `player_hp` / `enemy_hp` / `player_hp_max` / `enemy_hp_max` properties through it so the `hp_changed` signal contract is preserved. Loosens `BuffSystem` so it accepts either a `MinionInstance` or a `HeroState` (duck-typed on `buffs`). Extracts the Armour / Armour Break / corruption-strip math from `_deal_damage` into a shared helper and calls it from `apply_hero_damage` for `DamageSource.MINION` damage. PR2 (separate) wires the three Korrath handlers, ships the UI badges, and adds tests.

## Work log

- 2026-05-09: opened.
- 2026-05-09: closed.

## Summary

Added `combat/board/HeroState.gd` (RefCounted: side, hp, hp_max, armour, buffs) and routed `CombatState.player_hp` / `enemy_hp` / `player_hp_max` / `enemy_hp_max` through `player_hero` / `enemy_hero` containers, preserving the `hp_changed` signal contract. Loosened `BuffSystem` parameters from `MinionInstance` to `Object` (duck-typed on `buffs`); minion-shaped reads (`effective_atk`, `card_data.health`, `shield_cap`, `current_shield`) gated behind `is MinionInstance` checks. Extracted shared `_apply_armour_math(target, damage, corrupt_strip)` from `_deal_damage` and called it from `apply_hero_damage` for `DamageSource.MINION`, mutating `info.amount` to the post-armour value before the signal fires. Added `player_hero` / `enemy_hero` forwarders on `CombatScene`. Verified zero behavior change: RunAllTests 617 pass / 3 pre-existing KNOWN BUGs failing; BalanceSimBatch act 1 swarm slice produced expected win-rate ranges.

Follow-ups: PR2 (task 007 phases 4-6) — wire commanders_reach / path_of_destruction handlers to apply AB to hero targets, ship Armour and AB badges on PlayerHeroPanel / EnemyHeroPanel, add unit tests covering hero-armour math.
