---
id: "033"
title: Audit description style for all new Korrath cards
status: backlog
area: content
priority: normal
started:
finished:
---

## Description

After implementation tasks 023–027 ship, audit every new Korrath card's in-game description text against `design/master_doc/CARD_DESCRIPTION_STYLE.md`. Scope: all cards from `korrath_core`, `korrath_common`, `korrath_iron_vanguard`, `korrath_runic_knight`, and `korrath_abyssal_breaker` (≈31 cards). Existing cards in those pools that are dual/triple-pooled (Runic Blast, Font of the Depths) are out of scope — their descriptions were written by their original pools.

Audit checklist per card:
- Description uses the standard keyword casing (FORMATION, GUARD, SWIFT, ON PLAY, ON DEATH, ON LEAVE, ON ATTACK, etc.) per the style guide.
- Numeric values are bare integers, not spelled out (100, not "one hundred").
- Trigger timing language is consistent ("ON PLAY:", "FORMATION:", "Whenever ...", "At the start of your turn:", etc.).
- Damage school is named where relevant (VOID_CORRUPTION, PHYSICAL) so the player knows which Armour interaction applies.
- Card text is parseable without referring to the design doc — any non-obvious interaction (Banner's per-minion rider scope, Drillmaster's adjacency bypass, Shield Bash's Armour-sum-not-spent rule, Decree's AB-consumption-then-damage order) is either clear from the text or accompanied by a UI tooltip.
- Cards that introduce or reference new mechanics (hero Armour, negative Armour, post-damage AB residual, AB consumption, rider-vs-aura) have description language consistent with the §2 / §6 / §11 ruling notes in the design doc.

Output: a punch list of cards-with-issues + suggested rewrites. Apply the rewrites in the same task.

## Work log

- 2026-05-12: opened.

## Summary

_(filled in at /task-done)_
