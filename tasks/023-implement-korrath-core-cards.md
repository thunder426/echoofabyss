---
id: "023"
title: Implement korrath_core cards in CardDatabase
status: done
area: content
priority: normal
started: 2026-05-16
finished: 2026-05-16
---

## Description

Implement the deck-builder cards + tokens designed in `design/KORRATH_HERO_DESIGN` §10 into `cards/data/CardDatabase.gd` and wire the `korrath_core` pool into `_card_pools` + `DeckBuilderScene.DECK_BUILDER_POOLS_BY_HERO`. Cards shipped in this task: `squire_of_the_order` (2E Human/Demon FORMATION Knight-discount), `order_conscript` (1E Human + adds Footman to hand), `quartermaster` (3E Human + per-summon Armour aura), `shatterstrike` (2M physical removal). Tokens shipped: `order_footman` (1E 100/200 Human, hand-only) and the two `rank_and_file` tokens (consumed later by Rally). Supporting infra: add `essence_cost` support to `_TOKEN_DEFS` (Footman is 1E), add a generic `on_friendly_summon_aura_steps` field on `MinionCardData` + a dispatcher handler `on_minion_summoned_friendly_aura` registered in `CombatSetup` so Quartermaster (and future on-summon auras) declare effect steps instead of bespoke handlers. Add probes in `CardEffectTests.gd` for each card's primary effect. **`rally_the_ranks` is split to task 038** because it needs three additional new mechanics (dual-race target_type, adjacent-to-target summon step, dual-tag race-picker UI with sim parity).

## Work log

- 2026-05-12: opened.
- 2026-05-16: started.
- 2026-05-16: split rally_the_ranks to task 038 (needs new target_type + adjacent-summon step + dual-tag picker UI).
- 2026-05-16: closed.

## Summary

Shipped 4 of 5 Korrath Core Pool cards (squire_of_the_order, order_conscript, quartermaster, shatterstrike) + 3 tokens (order_footman 1E Human, rank_and_file_h/d 0E race-matched), wired the `korrath_core` pool into `_card_pools` and `DeckBuilderScene.DECK_BUILDER_POOLS_BY_HERO["korrath"]`, and added 7 probes in `CardEffectTests.gd` covering each card's primary effect. 710/710 tests pass. Two reusable infra pieces landed alongside the cards: (1) generic `MinionCardData.on_friendly_summon_aura_steps` field + `CombatHandlers.on_minion_summoned_friendly_aura` dispatcher registered in `CombatSetup` for declarative "fire on every friendly summon" auras (Quartermaster is the first consumer, skips self, stacks across multiple sources); (2) declarative `MOD_HAND_CARDS_COST` EffectStep that mutates `essence_delta` / `mana_delta` on every CardInstance in the caster's hand matching AND-combined `card_id` / `card_tag` / `card_race` filters — Squire's "discount Abyssal Knights in hand by 2" formation effect uses it and any future "broadcast cost change" effect can drop in without new code. Also added `essence_cost` support to `_TOKEN_DEFS` (default 0) so hand-only tokens like Footman can carry real costs.

Follow-ups: task 038 covers Rally the Ranks + its three infra prerequisites (dual-race `target_type`, adjacent-to-target SUMMON step, dual-tag race-picker UI with sim parity). The two rank_and_file tokens are pre-staged for it.
