---
id: "008"
title: Korrath card pools — content design and authoring
status: done
area: content
priority: normal
started: 2026-05-08
finished: 2026-05-12
---

## Description

Korrath has no support card pools yet. Both starter decks (`korrath_iron_legion`, `korrath_abyssal_vanguard`) draw entirely from `abyss_core` + `neutral_core`, which works but leaves Korrath thin on synergy. Author four pools mirroring the Vael/Seris pattern in [CardDatabase.gd:3056-3076](cards/data/CardDatabase.gd#L3056-L3076):

- **`korrath_core`** — Hero Core (deck-builder pool, branch-neutral). Designed in `KORRATH_HERO_DESIGN § 10`. Distinct from `korrath_common` per `CARD_POOL_ARCHITECTORE.md`.
- **`korrath_common`** — Hero Common Support (rewards-side, branch-agnostic): generic Armour appliers, Human/Demon utility, Korrath-flavored runes/spells. ~5–7 cards.
- **`korrath_iron_vanguard`** — Branch 1 talent pool (gated behind `iron_formation` T0): extra Humans, Armour generators, Formation enablers. ~5 cards.
- **`korrath_runic_knight`** — Branch 2 talent pool (gated behind `runeforge_strike` T0): rune generators that don't depend on the knight attacking, rune-aura amplifiers, hybrid Human/Demon bodies. ~5 cards.
- **`korrath_abyssal_breaker`** — Branch 3 talent pool (gated behind `corrupting_presence` T0): corruption applicators, AB sources, demon spell-burst, on-death damage scalers. ~5 cards.

Also decide on `hero_reward_pool` (boss-drop unlock pool) — Vael has 6, Seris is empty. Korrath currently empty too; pick one model and stick to it.

Pre-work: extend [`design/KORRATH_HERO_DESIGN`](design/KORRATH_HERO_DESIGN) with §10 (Hero Core — `korrath_core`, **done**) and §11–14 (Common + three branch pools, **pending**) listing each card's role, cost, race tags, and which branch it serves. Settle the design before implementing in `CardDatabase.gd`. Pool wiring into rewards/shop is a separate task (see 009).

## Work log

- 2026-05-08: opened.
- 2026-05-12: closed.

## Summary

Designed all five Korrath card pools in `design/KORRATH_HERO_DESIGN` §10–14: `korrath_core` (5 deck-builder cards + 3 tokens), `korrath_common` (9 cards), `korrath_iron_vanguard` (5 cards + 1 token), `korrath_runic_knight` (5 cards, including Runic Blast dual-pooled with `vael_rune_master`), and `korrath_abyssal_breaker` (7 cards, including Font of the Depths triple-pooled with `vael_piercing_void` and `seris_corruption_engine`, plus a new corruption-spawn token). Final inventory: 31 unique cards (29 new + 2 cross-pool reuses) and 5 tokens. Along the way, the design pass also revised B2 T1 `runic_absorption` to be a general rune-destruction listener (no longer overflow-only), formalized the AB-on-attack post-damage timing convention across `path_of_shattering`/Banner/Bonebreaker (which led to follow-up task 021 splitting `ON_PLAYER_ATTACK` into PRE/POST phases), and decided `hero_reward_pool` stays empty (matches Seris precedent).

Follow-ups: implementation of all designed cards in `CardDatabase.gd` is **not** part of this task — task 008 covered design only. Implementation will require: new EffectSteps (CONSUME_HERO_AB for Decree of Ruin, PLACE_RANDOM_RUNE for several B2 cards, summon-with-stat-override for Runic Apparition), engine support for negative Armour (Shattering Volley / Bonebreaker can drive Armour below zero), and the rider-vs-aura distinction codified in §11 ruling notes (Banner of the Order's per-Demon rider). Each branch pool will likely need its own implementation task. Balance sim flagged power-level concerns on: Vanguard Marshal (per-Formation card draw), Shield Bash (scales with total friendly Armour), Oath of Iron (board fill + Formation cascade), Decree of Ruin (700 + consumed AB at 5+ corruption stacks → 1500+ damage hero burst), Maw of the Abyss (6E hybrid Demon nuke), and Rune Conclave / Runic Apparition / Tide of Corruption.
