---
id: "035"
title: Refactor Armour/AB damage math to a single signed net_armour value
status: done
area: combat
priority: normal
started: 2026-05-16
finished: 2026-05-16
---

## Description

Collapse the two-bucket Armour / Armour Break damage model in CombatManager into a single derived signed `net_armour = armour - sum(ARMOUR_BREAK)`. Positive net reduces incoming damage (capped so armour never reduces a hit below its raw value; 100 floor only when net actually reduced damage); negative net adds as flat bonus damage; zero passes raw through. Storage stays split (stat + buff stacks) so card triggers can still distinguish "apply Armour" from "apply AB" events. Wire damage math, Shield Bash, Decree of Ruin, and design doc §2 to the unified model. Minion status bar already renders the signed net via BoardSlot — confirm hero panels match, add probes for the small-damage-vs-armour case that currently inflates 50 ATK to 100.

## Work log

- 2026-05-16: opened.
- 2026-05-16: closed.

## Summary

Collapsed Armour / Armour Break damage math into a unified signed-net model. Added `BuffSystem.net_armour(target)` helper; rewrote `CombatManager._apply_armour_math` to use `net = armour - sum(AB)` with three branches (positive net reduces damage but never below raw; negative net adds |net| as flat bonus; zero passes raw). Fixed a real bug: 50 ATK vs 200 Armour previously dealt 100 (floor inflated below-raw damage), now correctly deals 50. The 100 floor only applies when armour math reduces damage *above* the raw hit. Storage stays split (armour stat + ARMOUR_BREAK buff stacks) so card triggers can distinguish "apply Armour" vs "apply AB" events. Updated BoardSlot status bar to use the helper, added 4 new test probes (all 686 tests pass, +4 from 682), and rewrote design/KORRATH_HERO_DESIGN §2 with a worked-examples table and the canonical engine formula. Hero panels and minion status bar already render the signed-net display correctly.
