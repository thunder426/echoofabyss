---
id: "025"
title: Implement korrath_iron_vanguard cards in CardDatabase
status: done
area: content
priority: normal
started: 2026-05-18
finished: 2026-05-18
---

## Description

Implement the 5 talent-gated cards + 1 token designed in `design/KORRATH_HERO_DESIGN` §12 into `cards/data/CardDatabase.gd` and add `korrath_iron_vanguard` to `_card_pools` with talent gating on `iron_formation` (B1 T0). Cards: `shield_squire` (1E Human FORMATION self-Armour), `vanguard_marshal` (3E Human, draws a card per Formation event — listens on `ON_FORMATION_TRIGGERED`), `shield_bash` (1M spell, damage = sum of friendly minion + hero Armour), `lord_commander` (5E Human, +200 hero Armour on play), `oath_of_iron` (3M spell, fills empty slots with Iron Footmen and triggers Formation cascade). Token: `iron_footman` (200/200 Human, vanilla; distinct from `order_footman` in core). Reward eligibility must check both pool tag and `iron_formation` in the active talent set. Add probes in `TriggerHandlerTests.gd` for Marshal's per-Formation card draw and Oath's board-fill + Formation-cascade behavior; verify Shield Bash damage scaling against varied friendly Armour states.

Engine prerequisites:
- Per-talent pool gating in the reward filter (mirrors `vael_piercing_void` precedent).
- Card-driven `on_attack`-style hook for Marshal if not already in place.

## Work log

- 2026-05-12: opened.
- 2026-05-18: activated — starting implementation.
- 2026-05-18: closed.

## Summary

Shipped the 5-card `korrath_iron_vanguard` pool (Shield Squire, Vanguard Marshal, Shield Bash, Lord Commander, Oath of Iron) + `iron_footman` token per `design/KORRATH_HERO_DESIGN` §12, plus four reusable infra pieces: (1) `ADD_HERO_ARMOUR` EffectStep routing through `state.add_hero_armour` — first consumer Lord Commander; (2) `armour_sum` multiplier_key that sums minion Armour across a chosen board with optional `include_hero` — first consumer Shield Bash; (3) `fill_empty_slots: true` SUMMON variant that iterates the caster's slots left→right and summons one token per empty (each spawn fires standard summon/Formation triggers) — first consumer Oath of Iron; (4) `on_formation_triggered_aura_steps` MinionCardData field + always-on `on_formation_triggered_card_auras` dispatcher in CombatHandlers (registered at priority 20 in CombatSetup) — symmetric to the existing `on_friendly_summon_aura_steps` pattern, first consumer Vanguard Marshal.

Pool wired in `_card_pools` (5 entries) with per-card act gates per §12 (3 Common = Act 1, 1 Rare = Act 2, 1 Epic = Act 3). Talent gate added to `RewardScene._get_active_support_pool_ids` — Korrath branch was previously stubbed-out; this lights up `korrath_common` (no prereq) and `korrath_iron_vanguard` (when `iron_formation` is in the active talent set). Per spec NOT added to `DECK_BUILDER_POOLS_BY_HERO` — rewards-only visibility. 9 new probes in `CardEffectTests.gd` cover each card's signature ruling: Squire's self-Armour FORMATION, Marshal's per-trigger card draw + N-source stacking, Shield Bash's combined minion+hero Armour damage scaling (and Armour-as-counter non-consumption), Lord Commander's hero-Armour grant, Oath's empty-slot fill (5-slot, occupied-skip, and the Iron-Footman-sandwich Formation cascade on neighbors). 784/784 tests pass.

Edits: `combat/effects/EffectStep.gd`, `combat/effects/EffectResolver.gd`, `shared/resources/MinionCardData.gd`, `combat/events/CombatHandlers.gd`, `combat/events/CombatSetup.gd`, `cards/data/CardDatabase.gd`, `rewards/RewardScene.gd`, `debug/tests/CardEffectTests.gd`.

Follow-ups: art pass (task 031 — korrath_iron_vanguard), description audit (task 033). Balance-sim coverage for Shield Bash late-game damage and Oath turn-spike (the design-doc flagged "power-level for monitoring" cards) belongs in the next Korrath balance pass.
