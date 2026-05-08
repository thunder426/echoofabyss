---
id: "005"
title: Korrath Branch 2 — Runic Knight talents (T3 deferred)
status: done
area: combat
priority: normal
started: 2026-05-06
finished: 2026-05-06
---

## Description

Most complex branch. T0 `runic_transcendence` gives the knight both Human and Demon race tags and places a random Rune on attack — needs an architectural decision on whether `MinionInstance.minion_type` becomes a flag-set / array (audit every `== MinionType.X` read site) or we add a parallel `extra_types` field. T1 `runic_absorption` destroys a random rune when board is full and grants its aura permanently to a random Abyssal Knight (reuses Seris's `aura_tags` accumulator pattern). T2 sibling talents: `path_of_demons` (Demon summon → 50 dmg × X repeated X times) and `path_of_humans` (Human summon → +50 ATK × X repeated X times) where X = active rune slots + total absorbed aura stacks across knights.

T3 `grand_ritual_chaos` is **deferred** — needs a new `RitualVariance` resource type with min/max ranges per effect and post-resolution Enhanced selection. Will spin out into its own task.

## Work log

- 2026-05-06: opened. Gated on Phases 1, 2, and ideally task 004 (sibling-talent T2 pattern). Dual-race tagging is the architectural hinge — flag scope to user before committing.
- 2026-05-06: closed.

## Summary

T0/T1/T2 of Branch 2 shipped; T3 grand_ritual_chaos still deferred. The architectural hinge — dual-race tagging — was resolved by adding `extra_minion_types: Array[int]` and an `is_race(type)` / `shares_race(other)` helper to `MinionCardData`, then migrating ~60 `minion_type ==`/`!=` call sites across combat, effects, sim, AI profiles, and CardModRules to use `is_race()`. The migration ran clean with zero regressions in the existing 592-assertion suite, which validates that the helper is the right primitive. T0 `runic_transcendence` is two halves: declarative `talent_overrides` add DEMON to the knight's `extra_minion_types`, and an `ON_PLAYER_ATTACK` handler places a random rune via the new `CombatState._korrath_place_random_rune()`. T1 `runic_absorption` plugs into that helper — when the rune board is full it picks a random active rune, removes it (full aura cleanup via existing `_remove_rune_aura`), and appends its rune id to a random friendly knight's `aura_tags` (Seris's accumulator pattern). T2 sibling talents `path_of_demons` and `path_of_humans` listen on `ON_PLAYER_MINION_SUMMONED` and fire 50 dmg / +50 ATK in a loop scaled by X = active rune slots + total absorbed-aura stacks across friendly knights. 17 new test assertions, all green; 592 pre-existing unchanged.

Follow-ups: T3 `grand_ritual_chaos` capstone needs a new `RitualVariance` resource type with min/max ranges per effect and post-resolution Enhanced selection — open a fresh task when ready. Branch icon art is also still empty across all four talents. Hero-target rune placement / hero corruption gaps from earlier branches still apply.
