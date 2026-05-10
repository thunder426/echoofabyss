---
id: "007"
title: Hero Armour and Armour Break — extend Korrath stats to player/enemy heroes
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

Today Armour and Armour Break only exist on minions. Korrath talents that target heroes (`commanders_reach`, `abyssal_strike`, `path_of_destruction`) all early-return when the defender is the hero sentinel. This task extends both stats to heroes: state fields on `CombatState`, hero-side armour math in `apply_hero_damage` for `DamageSource.MINION`, hero-defender code paths in the three handlers, and Armour / AB badges on `PlayerHeroPanel` / `EnemyHeroPanel`. Open design questions to settle first: starting hero armour (probably 0), whether enemy bosses can ship with armour as a balance lever, AB cap on heroes, and whether AB on heroes should decay or persist.

## Work log

- 2026-05-08: opened.

## Summary

_(filled in at /task-done)_
