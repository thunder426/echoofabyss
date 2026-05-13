---
id: "017"
title: Talent tree sibling-tier layout
status: done
area: ui
priority: normal
started: 2026-05-11
finished: 2026-05-11
---

## Description

Korrath branches 2 and 3 have sibling T2 talents (Path of Demons / Path of Humans, Path of Corruption / Path of Shattering) that are mutually exclusive picks, but the talent select screen currently renders them as a flat vertical list of 5 buttons, giving no visual indication that the player should choose 1 of 2. Restructure each branch column into tier rows so single-talent tiers center one button and sibling tiers show two side-by-side, forming a proper tree shape.

## Work log

- 2026-05-11: opened.
- 2026-05-11: closed.

## Summary

Refactored `TalentSelectScene._make_branch_column` to group talents by tier and render each tier as its own row. Single-talent tiers keep the original wide button; sibling tiers (Korrath B2/B3 T2) show a "— CHOOSE ONE —" label above two narrower 224-wide buttons side-by-side, communicating the mutually-exclusive pick visually and turning the column into a proper tree shape. Lord Vael and Seris columns are unchanged since every tier has exactly one talent.
