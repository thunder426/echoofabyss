---
id: "020"
title: Redesign Commander's Reach — +50 Armour to all friendly Humans on any Formation trigger
status: done
area: combat
priority: normal
started: 2026-05-11
finished: 2026-05-12
---

## Description

Replace Korrath Branch 1 T1 (`commanders_reach`) effect. Old: aura that gave adjacent friendly Humans 100 Armour Break on attack. New: whenever any friendly minion's FORMATION effect triggers, all friendly Human minions on board permanently gain +50 Armour. Aligns the talent with Branch 1's Armour-stacking identity (T0 Formation → T1 board Armour → T2 Armour→ATK → T3 doubling) and removes redundancy with Branch 3's Armour Break role. Requires a new `ON_FORMATION_TRIGGERED` trigger event, handler swap, sim parity, design doc updates, and test rewrite.

## Work log

- 2026-05-11: opened.
- 2026-05-12: closed.

## Summary

Replaced Commander's Reach with the Formation-listener design: added `ON_FORMATION_TRIGGERED` trigger event (fired from `CombatHandlers._try_fire_formation` whenever any friendly Formation resolves), wired `on_formation_triggered_commanders_reach` in `CombatSetup` to grant +50 Armour to every friendly Human on the board, updated `design/KORRATH_HERO_DESIGN` to the new text, and added four TriggerHandlerTests probes (buff, race filter, stacking, Unbreakable doubling). Sim parity is automatic — `SimTriggerSetup` delegates to `CombatSetup.setup()` and `SimState extends CombatState`, so no duplicate registration was needed; updated `CLAUDE.md`'s "Adding New Trigger Handlers" section to reflect this and stop instructing duplicate sim registrations.
