---
id: "013"
title: Remove dead hero_reward_pool field from HeroData
status: done
area: meta
priority: normal
started: 2026-05-09
finished: 2026-05-12
---

## Description

`HeroData.hero_reward_pool` ([HeroData.gd:43](heroes/HeroData.gd#L43)) is a stale field — `RewardScene._get_active_support_pool_ids()` ([RewardScene.gd:86-106](rewards/RewardScene.gd#L86-L106)) hardcodes pool-name lookups (`vael_common`, `seris_common`, talent-gated unlocks) and never reads it. Vael still carries a 6-card list that mirrors `vael_common` exactly; Seris and Korrath are empty. Decide between two cleanups and apply one:

1. **Delete the field** — strip `hero_reward_pool` from `HeroData.gd`, drop the assignments in `HeroDatabase.gd`, fix the stale docstring on line 42.
2. **Wire it up** — make `RewardScene._get_active_support_pool_ids()` consult `hero.hero_reward_pool` instead of hardcoding pool names per hero. Then populate Seris/Korrath lists and remove the per-hero `if`/`elif` branches.

Recommendation: option 1. The pool-name pipeline is already the source of truth and works for talent-gated unlocks (which the field can't express). If we ever want a per-hero override, re-add it then.

Out of scope: any change to actual pool contents or to talent-gated unlock logic — this is a pure dead-code/refactor pass.

## Work log

- 2026-05-09: opened.
- 2026-05-12: closed.

## Summary

Took option 1 (delete the field). Removed `hero_reward_pool` declaration + docstring from `HeroData.gd`, dropped the three assignments in `HeroDatabase.gd` (Vael's 6-card mirror of `vael_common`, Seris's empty list, Korrath's empty list), and pruned the stale field doc line from `design/master_doc/DESIGN_DOCUMENT.md`. `RewardScene._get_active_support_pool_ids()` remains the single source of truth via hardcoded pool-name lookups. Full test suite passes (678/681; the 3 remaining failures are pre-existing `KNOWN BUG` entries unrelated to this change).
