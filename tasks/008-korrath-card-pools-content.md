---
id: "008"
title: Korrath card pools — content design and authoring
status: backlog
area: content
priority: normal
started:
finished:
---

## Description

Korrath has no support card pools yet. Both starter decks (`korrath_iron_legion`, `korrath_abyssal_vanguard`) draw entirely from `abyss_core` + `neutral_core`, which works but leaves Korrath thin on synergy. Author four pools mirroring the Vael/Seris pattern in [CardDatabase.gd:3056-3076](cards/data/CardDatabase.gd#L3056-L3076):

- **`korrath_common`** — branch-agnostic Korrath support: generic Armour appliers, Human/Demon utility, Korrath-flavored runes/spells. ~5–7 cards.
- **`korrath_infernal_bulwark`** — Branch 1 talent pool: extra Humans, Armour generators, Formation enablers. ~5 cards.
- **`korrath_runic_knight`** — Branch 2: rune generators that don't depend on the knight attacking, rune-aura amplifiers, hybrid Human/Demon bodies. ~5 cards.
- **`korrath_abyssal_breaker`** — Branch 3: corruption applicators, AB sources, demon spell-burst, on-death damage scalers. ~5 cards.

Also decide on `hero_reward_pool` (boss-drop unlock pool) — Vael has 6, Seris is empty. Korrath currently empty too; pick one model and stick to it.

Pre-work: extend [`design/KORRATH_HERO_DESIGN`](design/KORRATH_HERO_DESIGN) with a §10 "Support card pool" section listing each card's role, cost, race tags, and which branch it serves. Settle the design before implementing in `CardDatabase.gd`. Pool wiring into rewards/shop is a separate task (see 009).

## Work log

- 2026-05-08: opened.

## Summary

_(filled in at /task-done)_
