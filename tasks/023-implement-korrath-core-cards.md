---
id: "023"
title: Implement korrath_core cards in CardDatabase
status: backlog
area: content
priority: normal
started:
finished:
---

## Description

Implement the 5 deck-builder cards + 3 tokens designed in `design/KORRATH_HERO_DESIGN` §10 into `cards/data/CardDatabase.gd` and wire the pool into `_card_pools`. Cards: `squire_of_the_order` (2E Human/Demon FORMATION Knight-discount), `order_conscript` (1E Human + adds Footman to hand), `rally_the_ranks` (2M targeted-adjacent token spawn), `quartermaster` (3E Human + per-summon Armour aura), `shatterstrike` (2M physical removal). Tokens: `order_footman` (1E 100/200 Human, hand-only), `rank_and_file_h` and `rank_and_file_d` (0E 200/100 race-matched, spawned by Rally). Pool visibility: gated to Korrath in `DeckBuilderScene._deck_builder_pools_for_hero`. Add probes in `CardEffectTests.gd` for each card's primary effect.

## Work log

- 2026-05-12: opened.

## Summary

_(filled in at /task-done)_
