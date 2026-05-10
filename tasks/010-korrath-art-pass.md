---
id: "010"
title: Korrath art pass — portraits, passive/talent icons, card art
status: backlog
area: art
priority: normal
started:
finished:
---

## Description

Every art slot for Korrath is currently empty. The hero is fully playable but visually blank. Generate, process, and wire art for:

- **Hero select portrait** — [HeroDatabase.gd:147](heroes/HeroDatabase.gd#L147) `portrait_path = ""`. Place under `assets/art/hero_selection/hero_portrait/`.
- **Combat portrait** — same line, `combat_portrait_path = ""`. Place under `assets/art/heroes/combat_portraits/`.
- **Hero passive icons (2)** — `abyssal_commander`, `iron_legion` at [HeroDatabase.gd:154,159](heroes/HeroDatabase.gd#L154). Create `assets/art/passives/korrath/` to mirror the Vael folder.
- **Talent icons (13)** — every `_make()` call in [TalentDatabase.gd:296-376](talents/TalentDatabase.gd#L296-L376) ends with `""`. Create `assets/art/talents/korrath/` mirroring the Vael / Seris folders. (Branch 2 T3 `grand_ritual_chaos` is deferred per task 005, so 12 icons + 1 placeholder, or skip the capstone until that task ships.)
- **Abyssal Knight card art + battlefield art** — [CardDatabase.gd:406](cards/data/CardDatabase.gd#L406) `art_path = ""`. Use `/add-art` skill to wire once the PNGs land.

Use the existing `/add-champion-art` and `/add-art` skills for processing where applicable.

## Work log

- 2026-05-08: opened.

## Summary

_(filled in at /task-done)_
