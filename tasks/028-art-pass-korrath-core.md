---
id: "028"
title: Art pass — korrath_core
status: backlog
area: art
priority: normal
started:
finished:
---

## Description

Generate and wire art for the `korrath_core` pool cards (designed in §10). Five deck-buildable cards need card-face art; three of them are minions and also need battlefield art. Tokens (Order Footman, Rank-and-File ×2) are vanilla but still need card-face art so they render properly when added to hand or summoned.

Cards needing art:
- `squire_of_the_order` — Human/Demon FORMATION minion. Card art + battlefield art.
- `order_conscript` — Human minion. Card art + battlefield art.
- `rally_the_ranks` — Spell. Card art only.
- `quartermaster` — Human minion. Card art + battlefield art.
- `shatterstrike` — Spell. Card art only.

Tokens:
- `order_footman` — Human, card-face only (hand display).
- `rank_and_file_h` — Human, card-face only (summon flash).
- `rank_and_file_d` — Demon, card-face only (summon flash).

Workflow: use the `missing-art` skill to scan for gaps, then `add-art` to wire each PNG. Art style follows `design/master_doc/CARD_FRAME_DESIGN_REGULATION.md`. Order pool flavor is "imperial dark knight order" — disciplined humans-and-demons in armor, Korrath's banner motif.

## Work log

- 2026-05-12: opened.

## Summary

_(filled in at /task-done)_
