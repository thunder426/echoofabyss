---
id: "002"
title: Korrath Phase 2 — hero registration and Abyssal Knight card
status: done
area: combat
priority: normal
started: 2026-05-06
finished: 2026-05-06
---

## Description

Register Korrath in `HeroDatabase` with the `abyssal_commander` (knight costs 1 less) and `iron_legion` (up to 4 copies in deck) passives, plus the three branch IDs. Add the textless `abyssal_knight` card (4E / 400 / 500) to `CardDatabase` — base stats only, all behavior driven by talent overrides. Wire `iron_legion` into the deck-builder copy-cap rules and `abyssal_commander` into `CardModRules` cost_delta.

## Work log

- 2026-05-06: opened. Gated on Phase 1 (task 001). Files: `HeroDatabase.gd`, `DeckBuilderScene.gd:_EXTRA_COPY_RULES`, `CardModRules.gd`, `CardDatabase.gd`.
- 2026-05-06: closed.

## Summary

Korrath is now a selectable hero. Registered `_register_korrath()` in `HeroDatabase` with `abyssal_commander` and `iron_legion` passives, plus the three branch IDs (`infernal_bulwark`, `runic_knight`, `abyssal_breaker`) — each branch gets a display name and one-line description in `TalentDatabase`. Added the textless `abyssal_knight` card (4E / 400 ATK / 500 HP, abyss_core pool, "abyssal_knight" tag) — `minion_type` defaults to DEMON since the field is required, but each branch's T0 talent override will replace it with the branch-appropriate race in Phase 3+. Wired `iron_legion` into `DeckBuilderScene._EXTRA_COPY_RULES` so the knight's deck cap is 4 instead of 2, and `abyssal_commander` into `CardModRules` as a tag-filtered `cost_delta: -1` rule (knight resolves at 3E in combat). 17 new test assertions added, all green; 543 pre-existing assertions unchanged.

Follow-ups: art assets (portrait, combat portrait, knight art) — `art_path` is empty everywhere and the hero-select scene will fall back to placeholder rendering. Phase 3 (task 003) wires Branch 1 — Infernal Bulwark talents on top of this scaffolding.
