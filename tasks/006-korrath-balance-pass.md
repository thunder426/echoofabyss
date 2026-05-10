---
id: "006"
title: Korrath AI profile and starter decks
status: done
area: combat
priority: normal
started: 2026-05-06
finished: 2026-05-06
---

## Description

Narrowed scope (was: balance + AI + decks + art): build a `KorrathPlayerProfile.gd` so the sim can pilot a Korrath deck, and wire two starter-deck presets (Human-leaning for Infernal Bulwark / Runic Knight, Demon-leaning for Abyssal Breaker) into `PresetDecks.gd`. Balance pass and art split into separate tasks.

## Work log

- 2026-05-06: opened. Final polish phase, gated on all prior Korrath tasks.
- 2026-05-06: rescoped to AI profile + starter decks; balance pass + art moved to follow-up tasks.
- 2026-05-06: closed.

## Summary

Korrath is now fully playable end-to-end. `KorrathPlayerProfile.gd` (branch-agnostic baseline) plays the knight first as the centerpiece, runs essence-first resource growth (matches Vael's Swarm / Seris's Fleshcraft pattern), and is registered in `CombatSim._PLAYER_PROFILES` under the `"korrath"` id. Two starter decks land in `PresetDecks.gd`: **Iron Legion** (Human-heavy frame, Bulwark / Runic-Human path) and **Abyssal Vanguard** (Demon-heavy frame, Breaker path) — both 15 cards drawn from `abyss_core` + `neutral_core` pools, with 4× knight as the anchor (iron_legion passive raises the cap). Two `ScenarioTests` smoke probes pilot both decks through full matches vs feral_pack; total assertions now 617 (+8), pre-existing 3 KNOWN BUG failures unchanged.

Follow-ups: actual balance pass — run `BalanceSimBatch.tscn` across the Act 1/2 encounter matrix with Korrath profiles, identify outlier branches/talents (especially T2 sibling balance and T3 capstone power), tune numbers. Open as task 007. Branch-specific player profiles (Bulwark / Breaker / Runic subclasses, à la `FleshcraftPlayerProfile`) only when balance sim shows the baseline plays a branch poorly. Branch icon art + Korrath portrait (currently `art_path = ""` everywhere) — open as task 008. A Korrath-specific support card pool also stays out of scope; the existing pools work but synergy is thin.
