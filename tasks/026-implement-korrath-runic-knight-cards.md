---
id: "026"
title: Implement korrath_runic_knight cards in CardDatabase
status: backlog
area: content
priority: normal
started:
finished:
---

## Description

Implement the 5 cards designed in `design/KORRATH_HERO_DESIGN` §13 into `cards/data/CardDatabase.gd` and add `korrath_runic_knight` to `_card_pools` with talent gating on `runeforge_strike` (B2 T0). Cards: `runebound_initiate` (2E dual-tag FORMATION places a random Rune; up to 2× if flanked, per §13 dual-tag-Formation ruling), `runic_substitution` (1M spell, destroy targeted Rune, place random basic Rune, triggers redesigned T1), `runic_blast` (existing `vael_rune_master` card — **dual-pool** only; add `"korrath_runic_knight"` to its pool tag in the dict), `runic_apparition` (3M spell, conditional Knight summon with SWIFT and −200/−200 stat override), `rune_conclave` (4E dual-tag minion 200/500, ON PLAY places 2 random Runes). Reward eligibility checks pool tag + `runeforge_strike` in active talents. Depends on task 022 (T1 redesign) being implemented first so Substitution's destruction correctly feeds absorption.

Engine prerequisites:
- Targeted-Rune spell flow (Substitution needs to let the player pick a friendly Rune — existing spells target minions/heroes, not runes). May require a new target type or UI flow.
- Runtime stat-override at summon time (Runic Apparition's −200/−200) that composes with talent_overrides on the Knight.
- Dual-tag Formation behavior matches §13 ruling notes: pair-keyed-on-partner means a flanked dual-tag minion fires Formation twice. May also affect Squire of the Order (`korrath_core`) and Battle Drillmaster cascade (`korrath_common`) — audit those alongside.

## Work log

- 2026-05-12: opened.

## Summary

_(filled in at /task-done)_
