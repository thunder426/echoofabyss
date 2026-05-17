---
id: "038"
title: Implement rally_the_ranks + adjacent-summon infra + dual-tag race picker
status: active
area: combat
priority: normal
started: 2026-05-16
finished:
---

## Description

Split out from task 023 because Rally the Ranks (Korrath core spell §10) needs three new pieces of generic infrastructure: a `target_type` that accepts "friendly Human OR Demon" minions, a SUMMON step variant that places tokens into the two slots adjacent to a chosen target minion (instead of any free slot), and a runtime race-picker modal so the player can choose Human or Demon when the chosen target carries both tags (e.g. Abyssal Knight under runeforge_strike, or Squire of the Order). All three pieces must also work on the sim side so enemy AI / balance sims can resolve the spell. Card body itself is trivial; the infra is the work.

## Work log

- 2026-05-16: opened.

## Summary

_(filled in at /task-done)_
