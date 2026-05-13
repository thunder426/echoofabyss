---
id: "024"
title: Implement korrath_common cards in CardDatabase
status: backlog
area: content
priority: normal
started:
finished:
---

## Description

Implement the 9 cards designed in `design/KORRATH_HERO_DESIGN` §11 into `cards/data/CardDatabase.gd` and add `korrath_common` to `_card_pools`. Cards: `armoured_recruit`, `shield_bearer` (FORMATION, outward GUARD+Armour), `bonebreaker` (Demon, damage-first-then-AB), `shattering_volley` (AoE AB+PHYSICAL, supports negative Armour), `battle_drillmaster` (FORMATION cascade ignoring adjacency), `rank_breaker` (FORMATION AoE AB), `bastion_rune` (start-of-turn Armour drip), `creeping_blight` (single-target VOID_CORRUPTION + corruption), `banner_of_the_order` (per-minion Human Armour grant + per-Demon AB-on-attack rider). Pool wires into combat-rewards eligibility via existing reward filter — gated to Korrath only, no talent prereq. Add probes in `CardEffectTests.gd` and `TriggerHandlerTests.gd` for each card; especially verify Banner's rider scope (current-Demons-only, idempotent, dies with the minion) and Battle Drillmaster's cascade behavior.

Engine prerequisites that may need to ship alongside or before this task:
- Negative Armour state support (Shattering Volley / Bonebreaker can drive Armour below zero — verify `MinionInstance.armour` allows negative values and the flat-bonus-damage math from §2 fires correctly).
- Rider-as-per-minion-flag (Banner of the Order) versus aura (Quartermaster) distinction codified in `MinionInstance`.

## Work log

- 2026-05-12: opened.

## Summary

_(filled in at /task-done)_
