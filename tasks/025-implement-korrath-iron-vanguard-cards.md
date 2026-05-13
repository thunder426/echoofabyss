---
id: "025"
title: Implement korrath_iron_vanguard cards in CardDatabase
status: backlog
area: content
priority: normal
started:
finished:
---

## Description

Implement the 5 talent-gated cards + 1 token designed in `design/KORRATH_HERO_DESIGN` §12 into `cards/data/CardDatabase.gd` and add `korrath_iron_vanguard` to `_card_pools` with talent gating on `iron_formation` (B1 T0). Cards: `shield_squire` (1E Human FORMATION self-Armour), `vanguard_marshal` (3E Human, draws a card per Formation event — listens on `ON_FORMATION_TRIGGERED`), `shield_bash` (1M spell, damage = sum of friendly minion + hero Armour), `lord_commander` (5E Human, +200 hero Armour on play), `oath_of_iron` (3M spell, fills empty slots with Iron Footmen and triggers Formation cascade). Token: `iron_footman` (200/200 Human, vanilla; distinct from `order_footman` in core). Reward eligibility must check both pool tag and `iron_formation` in the active talent set. Add probes in `TriggerHandlerTests.gd` for Marshal's per-Formation card draw and Oath's board-fill + Formation-cascade behavior; verify Shield Bash damage scaling against varied friendly Armour states.

Engine prerequisites:
- Per-talent pool gating in the reward filter (mirrors `vael_piercing_void` precedent).
- Card-driven `on_attack`-style hook for Marshal if not already in place.

## Work log

- 2026-05-12: opened.

## Summary

_(filled in at /task-done)_
