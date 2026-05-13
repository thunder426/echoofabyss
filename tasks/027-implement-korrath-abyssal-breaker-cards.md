---
id: "027"
title: Implement korrath_abyssal_breaker cards in CardDatabase
status: backlog
area: content
priority: normal
started:
finished:
---

## Description

Implement the 7 cards + 1 token designed in `design/KORRATH_HERO_DESIGN` §14 into `cards/data/CardDatabase.gd` and add `korrath_abyssal_breaker` to `_card_pools` with talent gating on `corrupting_presence` (B3 T0). Cards: `shatterclaw_fiend` (3E Demon, on-attack 100 AB residual via `ON_PLAYER_ATTACK_POST` per task 021), `font_of_the_depths` (existing card — **triple-pool**; add `"korrath_abyssal_breaker"` to its existing `["vael_piercing_void", "seris_corruption_engine"]` tag), `decree_of_ruin` (3M spell, consume hero AB and deal 700 + consumed-AB VOID_CORRUPTION to hero), `tide_of_corruption` (3M spell, summon 200/200 Corruption Spawn per corrupted enemy minion), `abyssal_sentence` (4M spell, destroy enemy minion + 1 Corruption to enemy hero), `herald_of_decay` (3E Demon, on-play and turn-start hero corruption +1/turn), `maw_of_the_abyss` (6E Demon, AoE 2 Corruption on play + per-attack AB residual). Token: `corruption_spawn` (200/200 Demon, vanilla). Reward eligibility checks pool tag + `corrupting_presence` in active talents.

Engine prerequisites (new effect-step patterns this task introduces):
- `CONSUME_HERO_AB` (or generalized `CONSUME_HERO_BUFF`) effect step — reads the hero's AB total, removes all of it, exposes the value for the following damage step.
- Damage step that reads the consumed-buff value from EffectContext and adds it to base damage. Required for Decree of Ruin's "700 + consumed AB" math; Path of Corruption amp applies to the combined total.
- Hero-corruption support (already exists from task 016 PR3) — Herald's recurring effect and Sentence's rider both route through `state.apply_hero_buff("enemy", BuffType.CORRUPTION, 100, ...)`.
- Counting helper for Tide: `enemy_minions_with_corruption_count()` reading `BuffSystem.count_type(minion, BuffType.CORRUPTION) >= 1`.

Add probes in `TriggerHandlerTests.gd` and `CardEffectTests.gd` for every card; especially verify Decree's AB-consumption math (basic case, 0 AB, with Path of Corruption amp, with negative pre-existing AB clamped to 0) and Tide's empty-slot fill behavior.

## Work log

- 2026-05-12: opened.

## Summary

_(filled in at /task-done)_
