---
id: "011"
title: Korrath mechanic gaps — Branch 2 capstone, talent prereqs, polish VFX
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

Three mechanic-level gaps left over from the Korrath build-out. Hero Armour/AB is tracked separately as task 007.

- **Branch 2 T3 `grand_ritual_chaos` deferred** — needs the RitualVariance system (3 volatile effects with one randomly enhanced post-resolution). Documented in [TalentDatabase.gd:286-287,353-354](talents/TalentDatabase.gd#L286-L287). Branch 2 currently sub-power vs Branches 1 and 3 because of this missing capstone.
- **`TalentData.requires` schema accepts only one prereq** — Branch 3 T3 `armour_explosion` requires `abyssal_strike` (T1) instead of either of its T2 siblings (`path_of_ruination` / `path_of_destruction`) because the field is a single string. Acknowledged with a code comment in [TalentDatabase.gd:316-325](talents/TalentDatabase.gd#L316-L325). A player could theoretically skip T2 and grab T3 with 4 picks. Refactor `requires` to `Array[String]` (or "any of these") and update the talent-tree validation. Korrath is the second hero hitting this — same shape on Runic Knight T3.
- **Korrath-specific VFX** — Branch 3 capstone "Armour Explosion" is currently a silent damage tick across the enemy board; it deserves a visual. Branch 1 "Iron Resolve" could use a chevron-style ATK-from-Armour pulse. Branch 2 rune-on-attack is also flat. Use `/create-vfx` skill and the VfxSequence DSL.

## Work log

- 2026-05-08: opened.

## Summary

_(filled in at /task-done)_
