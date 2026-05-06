---
id: "005"
title: Korrath Branch 2 — Runic Knight talents (T3 deferred)
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

Most complex branch. T0 `runic_transcendence` gives the knight both Human and Demon race tags and places a random Rune on attack — needs an architectural decision on whether `MinionInstance.minion_type` becomes a flag-set / array (audit every `== MinionType.X` read site) or we add a parallel `extra_types` field. T1 `runic_absorption` destroys a random rune when board is full and grants its aura permanently to a random Abyssal Knight (reuses Seris's `aura_tags` accumulator pattern). T2 sibling talents: `path_of_demons` (Demon summon → 50 dmg × X repeated X times) and `path_of_humans` (Human summon → +50 ATK × X repeated X times) where X = active rune slots + total absorbed aura stacks across knights.

T3 `grand_ritual_chaos` is **deferred** — needs a new `RitualVariance` resource type with min/max ranges per effect and post-resolution Enhanced selection. Will spin out into its own task.

## Work log

- 2026-05-06: opened. Gated on Phases 1, 2, and ideally task 004 (sibling-talent T2 pattern). Dual-race tagging is the architectural hinge — flag scope to user before committing.

## Summary

_(filled in at /task-done)_
