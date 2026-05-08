---
id: "004"
title: Korrath Branch 3 — Abyssal Breaker talents
status: done
area: combat
priority: normal
started: 2026-05-06
finished: 2026-05-06
---

## Description

Implement all four tiers of Branch 3 (Demon knight / corruption strips Armour / Armour Break stacking / spell explosion capstone). T0 `corrupting_presence` retags the knight Demon and makes each corruption stack reduce target Armour by 100. T1 `abyssal_strike` applies 1 Corruption per knight attack (incl. enemy hero). T2 forks into sibling talents — `path_of_ruination` (spells apply Corruption + corruption amplifies spell damage by 100 per stack) and `path_of_destruction` (friendly Demon attacks apply 50 Armour Break). T3 `armour_explosion` capstone: on enemy minion death, deal spell damage equal to that minion's accumulated Armour Break to all enemies.

## Work log

- 2026-05-06: opened. Built before Branch 2 because corruption + AB are direct extensions of Phase 1, no new infra. T2 sibling-talent pattern (two IDs, only one selectable) is the model for Branch 2 T2 as well. T3 needs to snapshot dead minion's AB stacks before BuffSystem clears them.
- 2026-05-06: closed.

## Summary

All five Abyssal Breaker talents shipped. T0 `corrupting_presence` retags the knight Demon (declarative `talent_overrides`) and adds a corruption-as-armour-erosion path to `CombatManager._deal_damage` (gated by `_corrupting_presence_active`, player-side only — counts CORRUPTION buff entries via `count_type`, not `sum_type`, since each entry stores per-stack ATK penalty as `amount`). T1 `abyssal_strike` and T2 `path_of_destruction` are `ON_PLAYER_ATTACK` handlers that filter on attacker (knight / Demon) and apply Corruption / 50 AB to the defender. T2 `path_of_ruination` lives entirely in `EffectResolver._apply` for `DAMAGE_MINION` — pre-damage amplification reads target's pre-application Corruption stack count (+100/stack), post-damage application adds 1 stack (skipped if the target died); this also makes AOE spells naturally hit each target once. T3 `armour_explosion` snapshots the dead enemy's AB sum on `ON_ENEMY_MINION_DIED` and deals it as spell damage to the remaining enemy board. Sibling T2 talents (path_of_ruination + path_of_destruction) both require T1 and both belong to `abyssal_breaker` branch; the four-pick budget naturally limits the player to one. 14 new test assertions, all green; pre-existing 578 unchanged.

Follow-ups: branch icon art (all `icon_path` empty). Hero AB / Corruption is not modeled (handler no-ops on hero defenders) — design says abyssal_strike applies Corruption to the enemy hero too; revisit when hero-state expands. T3 prereq is `abyssal_strike` not either T2 sibling because `TalentData.requires` holds a single string — fragile if a player skips T2, but the four-pick budget makes it unlikely in practice.
