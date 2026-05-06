---
id: "001"
title: Korrath Phase 1 — Armour, Armour Break, Formation core mechanics
status: done
area: combat
priority: normal
started: 2026-05-06
finished: 2026-05-06
---

## Description

Foundation work for the Korrath hero: introduce the Armour stat (physical damage reduction with min-100 floor, spells bypass), the Armour Break stackable debuff (strips Armour first, overflow becomes flat physical damage), and the Formation keyword (one-time trigger per same-race adjacent pair). All three need full sim parity and test coverage in `CardEffectTests.gd` before any Korrath content is wired up.

## Work log

- 2026-05-06: opened. Plan derived from `design/KORRATH_HERO_DESIGN`. Touches `MinionInstance.gd`, `MinionCardData.gd`, `CombatManager._deal_damage`, `Enums.gd` (new `BuffType.ARMOUR_BREAK`, `Keyword.FORMATION`), `BuffSystem.gd`, plus symmetric handler registration in `CombatSetup.gd` and `SimTriggerSetup.gd`.
- 2026-05-06: closed.

## Summary

Shipped the three Korrath foundations: `armour: int` field on `MinionInstance` (with `add_armour()` helper that pre-wires Phase 3 T3 doubling via `scene._armour_doubled_on_knight`), `BuffType.ARMOUR_BREAK` as a stackable debuff routed through `BuffSystem` (also added to `DEBUFF_TYPES` for cleanse), and a keyword-driven `FORMATION` trigger in `CombatHandlers.on_minion_summoned_formation` registered as a shared always-on handler in `CombatSetup` (sim parity inherits via `SimTriggerSetup` delegation). `CombatManager._deal_damage` now applies the armour math (AB strips armour first, overflow becomes flat bonus damage, min-100 floor only when armour or AB is present, spells bypass entirely) and exposes `last_post_armour_damage` so PIERCE overkill carries the *landed* damage to the hero, not the raw atk value. 22 new test assertions in `DamageTypeTests` (Phase 8 — Korrath Armour) and `TriggerHandlerTests` (Formation section) all pass; pre-existing 543 assertions unchanged (3 KNOWN BUG failures predate this work).

Follow-ups: Phase 2 (task 002) — register Korrath in `HeroDatabase`, add textless Abyssal Knight card, wire `iron_legion` 4-copy cap and `abyssal_commander` cost discount.
