---
id: "037"
title: Tighten Formation to require same-race minions on BOTH sides
status: done
area: combat
priority: normal
started: 2026-05-16
finished: 2026-05-16
---

## Description

Strengthen the Formation trigger condition from "at least one same-race adjacent neighbor" to "same-race minions present on BOTH the left and the right adjacent slots." The actor's race is checked independently against each side via `shares_race`, so dual-tag minions (e.g. Runebound Initiate, Squire of the Order) can have either tag satisfy each side. Edge-slot minions (slots 0 and N-1) become permanently unable to fire Formation normally — Battle Drillmaster becomes the only path to fire an edge-slot Formation. Trigger remains summon-event-keyed (same as task 036). This is a meaningful balance nerf to Knight T0 / Shield Bearer / Rank Breaker / Shield Squire / Squire of the Order / Initiate, doubling the positional setup required for any Formation effect. Update engine handler, design doc §2, all card design notes referencing the old single-neighbor rule, and add probes for the both-sides gate (one-side fail, edge-slot fail, dual-tag-mixed-races pass).

## Work log

- 2026-05-16: opened.
- 2026-05-16: closed.

## Summary

Tightened Formation trigger from "at least one same-race adjacent neighbor" to "same-race partners on BOTH left and right adjacent slots." Added `_formation_both_sides_satisfied(actor, card)` helper in CombatHandlers.gd that checks `slot_index − 1` AND `slot_index + 1` are filled with race-matching partners via `shares_race` (so dual-tag actors can have either tag satisfy each side independently). Edge-slot minions (slot 0 or last slot) can never fire Formation normally — Battle Drillmaster bypass becomes the sole rescue path for edge Formations. Trigger remains summon-event-keyed (combined with task 036 one-shot consumption: an actor needs a summon event near it AND both-sides sandwich AND its own `formation_fired == false`). Rewrote 7 Formation tests to sandwich setups and migrated 4 B1 talent tests (iron_formation / commanders_reach / unbreakable variants) to pre-place a Human on both sides of the Knight; added 4 new probes (only-one-neighbor blocked, edge-slot impossibility, one-side-wrong-race blocked, dual-tag mixed-race-flanking passes). Revised §2 + the Knight T0 talent row + §10 Squire/Shield Bearer matrix rows + §11 Shield Bearer / Rank Breaker / Drillmaster notes + §12 Shield Squire + §13 Initiate notes to use sandwich language. Net balance: significantly harder to set up Formation triggers (roughly halved trigger frequency), Drillmaster becomes substantially more valuable. 695/695 tests pass.
