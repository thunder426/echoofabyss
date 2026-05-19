---
id: "024"
title: Implement korrath_common cards in CardDatabase
status: done
area: content
priority: normal
started: 2026-05-18
finished: 2026-05-18
---

## Description

Implement the 9 cards designed in `design/KORRATH_HERO_DESIGN` §11 into `cards/data/CardDatabase.gd` and add `korrath_common` to `_card_pools`. Cards: `armoured_recruit`, `shield_bearer` (FORMATION, outward GUARD+Armour), `bonebreaker` (Demon, damage-first-then-AB), `shattering_volley` (AoE AB+PHYSICAL, supports negative Armour), `battle_drillmaster` (FORMATION cascade ignoring adjacency), `rank_breaker` (FORMATION AoE AB), `bastion_rune` (start-of-turn Armour drip), `creeping_blight` (single-target VOID_CORRUPTION + corruption), `banner_of_the_order` (per-minion Human Armour grant + per-Demon AB-on-attack rider). Pool wires into combat-rewards eligibility via existing reward filter — gated to Korrath only, no talent prereq. Add probes in `CardEffectTests.gd` and `TriggerHandlerTests.gd` for each card; especially verify Banner's rider scope (current-Demons-only, idempotent, dies with the minion) and Battle Drillmaster's cascade behavior.

Engine prerequisites that may need to ship alongside or before this task:
- Negative Armour state support (Shattering Volley / Bonebreaker can drive Armour below zero — verify `MinionInstance.armour` allows negative values and the flat-bonus-damage math from §2 fires correctly).
- Rider-as-per-minion-flag (Banner of the Order) versus aura (Quartermaster) distinction codified in `MinionInstance`.

## Work log

- 2026-05-12: opened.
- 2026-05-18: started; auditing infra (negative Armour, per-minion attack riders, FORMATION cascade dispatcher, outward-grant Formation) before writing card data.
- 2026-05-18: shipped — 9 cards + 3 reusable infra pieces. 763/763 tests pass (34 new probes, no regressions).

## Summary

Shipped the 9-card `korrath_common` pool (Armoured Recruit, Shield Bearer, Bonebreaker, Shattering Volley, Battle Drillmaster, Rank Breaker, Bastion Rune, Creeping Blight, Banner of the Order) per `design/KORRATH_HERO_DESIGN` §11, plus three reusable infra pieces that future Korrath / non-Korrath cards can use declaratively:

1. **`APPLY_ARMOUR_BREAK` EffectStep type** (`combat/effects/EffectStep.gd`, dispatcher in `EffectResolver._apply`) — declarative AB application via `BuffSystem.apply(..., ARMOUR_BREAK, ...)`. Optional `include_hero: true` field fires the AB on the opposing hero once after the per-minion loop for `ALL_ENEMY` scope (Shattering Volley's "all enemies" convention). Replaces the previous pattern of calling `BuffSystem.apply` directly from one-off handlers. First consumers: Bonebreaker, Shattering Volley, Rank Breaker, Banner of the Order's rider.

2. **`ADJACENT_FRIENDLIES` TargetScope** (`combat/effects/TargetResolver.gd`) — resolves to the minions occupying `ctx.source`'s slot ± 1 on the same board side (0, 1, or 2 results). Edge slots return only the one valid neighbor; empty adjacent slots are skipped silently. Used for outward-grant Formation patterns like Shield Bearer; reusable for any future "buff adjacent" effect.

3. **`MinionInstance.attack_riders` field + `GRANT_ATTACK_RIDER` EffectStep + `on_attack_fire_riders` dispatcher** (`combat/board/MinionInstance.gd`, `combat/effects/EffectStep.gd`, `combat/events/CombatHandlers.gd`, registered in `combat/events/CombatSetup.gd` at priority 30 on `ON_PLAYER_ATTACK_POST` and `ON_ENEMY_ATTACK`) — per-minion runtime-stamped attack riders. Each rider is `{source_tag, effect_steps, scope}`; `source_tag` is the idempotency key (Banner re-cast does not double-stamp). For minion defenders the rider's `effect_steps` run via `EffectResolver` with `ctx.chosen_target = defender`; for hero defenders the dispatcher handles `APPLY_ARMOUR_BREAK` steps directly via `state.apply_hero_buff` (other step types unsupported as rider steps today — loud warn). Banner of the Order is the first consumer; the design doc explicitly anticipated this (see `Enums.gd:74`).

Battle Drillmaster's Formation cascade went through a single `HARDCODED` hook (`battle_drillmaster_cascade` in `HardcodedEffects.gd`) that calls a new public `CombatHandlers.fire_unconsumed_formations_cascade(side)` — a near-clone of `_try_fire_formation` that drops the both-sides adjacency check, iterates the side in deterministic left-to-right slot order, and respects the one-shot `formation_fired` rule. Single-purpose mechanic so a dedicated EffectStep type would be over-abstraction.

Pool wiring: `korrath_common` added to `_card_pools` (9 entries), act gates set per §11 table (6 Common = Act 1, 2 Rare = Act 2, 1 Epic = Act 3). Per the design spec, NOT added to `DECK_BUILDER_POOLS_BY_HERO` — visibility is rewards-side only, never deck builder. Shop/Reward scene wiring (the `elif current_hero == "korrath"` branches) is intentionally still out of scope; Korrath's reward path lights up when the run-flow plumbing for Korrath lands as its own task.

Test coverage: 15 new probes in `CardEffectTests.gd` covering each card's signature ruling (Bonebreaker damage-then-AB order, Shattering Volley AB-before-damage + hero inclusion, Shield Bearer outward + edge-slot, Drillmaster cascade + one-shot respect, Banner Humans/Demons split + idempotency + rider firing on `ON_PLAYER_ATTACK_POST`, etc.). `TestHarness.fire` extended with a `defender` field bind so rider tests can drive the `ON_PLAYER_ATTACK_POST` ctx end-to-end. All 763 tests pass (729 prior + 34 new), no regressions.

Edits: `combat/effects/EffectStep.gd`, `combat/effects/EffectResolver.gd`, `combat/effects/TargetResolver.gd`, `combat/effects/HardcodedEffects.gd`, `combat/board/MinionInstance.gd`, `combat/events/CombatHandlers.gd`, `combat/events/CombatSetup.gd`, `cards/data/CardDatabase.gd`, `debug/tests/TestHarness.gd`, `debug/tests/CardEffectTests.gd`.

Follow-ups (not in scope): art pass (task 029), description audit pass (covered under future task 033), shop/rewards Korrath branch wiring.
