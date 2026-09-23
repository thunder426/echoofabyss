---
id: "007"
title: Hero Armour and Armour Break — extend Korrath stats to player/enemy heroes
status: done
area: combat
priority: normal
started: 2026-05-29
finished: 2026-05-29
---

## Description

Today Armour and Armour Break only exist on minions. Korrath talents that target heroes (`commanders_reach`, `abyssal_strike`, `path_of_destruction`) all early-return when the defender is the hero sentinel. This task extends both stats to heroes: state fields on `CombatState`, hero-side armour math in `apply_hero_damage` for `DamageSource.MINION`, hero-defender code paths in the three handlers, and Armour / AB badges on `PlayerHeroPanel` / `EnemyHeroPanel`. Open design questions to settle first: starting hero armour (probably 0), whether enemy bosses can ship with armour as a balance lever, AB cap on heroes, and whether AB on heroes should decay or persist.

## Work log

- 2026-05-08: opened.
- 2026-05-29: activated; beginning implementation.
- 2026-05-29: investigated current code — feature was already shipped end-to-end across v0.600–0.604 (tasks 023–025, 034–038). The talents this task named (`abyssal_strike`, `path_of_destruction`) never existed; the Korrath tree was redesigned (`commanders_reach`, `iron_resolve`, `path_of_shattering`, `corrupting_presence`, etc.). Closing as already-done. Full suite 784/784 green.
- 2026-05-29: closed.

## Summary

No code shipped — the feature was already fully implemented and tested. Hero Armour and Armour Break landed incrementally across v0.600–0.604 (tasks 023–025, 034–038) rather than as a single task: `HeroState.armour` (starts 0) + `add_armour()`, AB via `HeroState.buffs`, `CombatManager.apply_hero_damage` routing heroes through the shared signed-net `_apply_armour_math` (school-gated), grant/strip paths (`add_hero_armour` from EffectResolver GRANT_ARMOUR, `apply_hero_buff` for AB, `corrupting_presence` armour-strip), hero-sentinel handling in `corrupting_strike` / `path_of_shattering` / the attack-rider dispatcher, and Armour/AB/Corruption badges on both hero panels via `CombatUI.update_korrath_debuffs`. Shipped cards already exercise it (Lord Commander grants +200 hero armour; Shield Bash scales off friendly+hero armour). This task's description and the talents it named (`abyssal_strike`, `path_of_destruction`) were stale — predating the Korrath tree redesign. Full suite 784/784 green.

Follow-ups: the original open design questions were left as deliberate non-features and not pursued — enemy bosses do not currently ship with starting armour as a balance lever, and hero AB neither caps nor decays (persists like minion AB). Revisit only if balance work wants them.
