---
id: "004"
title: Korrath Branch 3 — Abyssal Breaker talents
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

Implement all four tiers of Branch 3 (Demon knight / corruption strips Armour / Armour Break stacking / spell explosion capstone). T0 `corrupting_presence` retags the knight Demon and makes each corruption stack reduce target Armour by 100. T1 `abyssal_strike` applies 1 Corruption per knight attack (incl. enemy hero). T2 forks into sibling talents — `path_of_ruination` (spells apply Corruption + corruption amplifies spell damage by 100 per stack) and `path_of_destruction` (friendly Demon attacks apply 50 Armour Break). T3 `armour_explosion` capstone: on enemy minion death, deal spell damage equal to that minion's accumulated Armour Break to all enemies.

## Work log

- 2026-05-06: opened. Built before Branch 2 because corruption + AB are direct extensions of Phase 1, no new infra. T2 sibling-talent pattern (two IDs, only one selectable) is the model for Branch 2 T2 as well. T3 needs to snapshot dead minion's AB stacks before BuffSystem clears them.

## Summary

_(filled in at /task-done)_
