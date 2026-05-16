---
id: "036"
title: Convert Formation from per-pair to one-shot consumable status
status: done
area: combat
priority: normal
started: 2026-05-16
finished: 2026-05-16
---

## Description

Replace the existing pair-keyed Formation engine (`MinionInstance.formation_partners` dict, fires once per (actor, partner) pair) with a one-shot consumable model: Formation fires at most once per minion's lifetime — the first time a valid same-race adjacent partner is on board, it fires and the FORMATION status is consumed. Subsequent partners do nothing. Replace the dict with a single `formation_fired: bool`, update the handler to gate on it, hide the FORMATION keyword chip on the battlefield minion frame once consumed (big-card review view stays as-is), revise design doc §2 and the §10/§11/§12/§13 ruling-notes that currently lean on the per-pair model (Squire of the Order, Battle Drillmaster, Runebound Initiate dual-tag-flanked-twice ruling, Vanguard Marshal balance flag), and audit/extend the existing Formation tests for the new semantics.

## Work log

- 2026-05-16: opened.
- 2026-05-16: closed.

## Summary

Converted Formation from per-pair memory (`MinionInstance.formation_partners: Dictionary`) to a one-shot consumable flag (`formation_fired: bool`). Once a FORMATION minion fires its effect for the first time, the status is consumed for the rest of that minion's lifetime — subsequent same-race partners coming and going cannot retrigger. Updated `_try_fire_formation` in CombatHandlers.gd to gate on the flag and refresh slot UI on consume so the FORMATION chip disappears from the battlefield frame (big-card review tooltip still shows the keyword as static card text). Added a FORMATION status chip in BoardSlot.gd that renders only while unconsumed, using `icon_guard.png` as a placeholder pending an art pass for a dedicated `icon_formation.png`. Rewrote design §2 and revised §10/§11/§12/§13 ruling notes (Squire of the Order, Battle Drillmaster, Vanguard Marshal balance flag, Runebound Initiate dual-tag-flank). Migrated 5 Formation probes in TriggerHandlerTests to `formation_fired` assertions; added new probes `_formation_consumed_once_per_lifetime` and `_formation_flanked_by_two_formation_partners_fires_all_three`.

Follow-ups: dedicated `icon_formation.png` art asset (currently using `icon_guard.png` placeholder).
