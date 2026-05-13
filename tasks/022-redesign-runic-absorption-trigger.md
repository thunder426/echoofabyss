---
id: "022"
title: Korrath Runic Absorption redesign — trigger on any rune destroy/consume
status: done
area: combat
priority: normal
started: 2026-05-11
finished: 2026-05-12
---

## Description

Rewrite Korrath B2 T1 `runic_absorption` so it fires whenever a friendly rune is destroyed or consumed (ritual fire, Grand Ritual: Chaos, overflow, Runic Substitution, Cyclone-style removal) — not only on full-board overflow. Centralize the absorption hook in `CombatState._remove_rune_aura` so every rune-removal path inherits the behavior, then strip the now-redundant inline absorption blocks in `_korrath_place_random_rune` and `on_rune_placed_grand_ritual_chaos`.

## Work log

- 2026-05-11: opened.
- 2026-05-12: closed.

## Summary

Centralized Korrath B2 T1 `runic_absorption` in `CombatState._remove_rune_aura`: any player-side rune destruction or consumption now grants an absorbed-aura stack to a random friendly Abyssal Knight via `_korrath_grant_absorbed_aura`. `_korrath_place_random_rune` was simplified to route overflow through `_remove_rune_aura` instead of inlining the grant, and `on_rune_placed_grand_ritual_chaos` consumes the three runes through the same chokepoint with no bespoke absorption logic — so ritual fire, Grand Ritual: Chaos, Runic Substitution, and any future rune-removal path inherit the behavior for free.
