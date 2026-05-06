---
id: "003"
title: Korrath Branch 1 — Infernal Bulwark talents
status: done
area: combat
priority: normal
started: 2026-05-06
finished: 2026-05-06
---

## Description

Implement all four tiers of Branch 1 (Human formation / armour stacking / Guard capstone). T0 `iron_formation` makes the knight Human and grants Formation +200 Armour/+200 HP on first Human pair. T1 `commanders_reach` aura applies 100 Armour Break to attack targets via adjacent friendly Humans. T2 `iron_resolve` is a live passive — friendly Humans gain ATK = current Armour (derived in `MinionInstance.effective_atk`). T3 `unbreakable` capstone grants Guard and doubles all knight Armour gains.

## Work log

- 2026-05-06: opened. Gated on Phases 1 and 2. Mostly declarative via `talent_overrides` and `CardModRules`. T2 needs a scene flag pattern mirroring `corruption_inverts_on_friendly_demons`. T3 doubling needs a single `MinionInstance.add_armour()` helper to centralize armour mutations.
- 2026-05-06: closed.

## Summary

All four Infernal Bulwark talents shipped. T0 `iron_formation` and T3 `unbreakable` are pure declarative — `talent_overrides` on the Abyssal Knight set `minion_type=HUMAN`, FORMATION (and GUARD on T3) keywords, and `formation_effect_steps` (BUFF_ARMOUR +200 + BUFF_HP +200 SELF). T1 `commanders_reach` is a `ON_PLAYER_ATTACK` handler that applies 100 Armour Break to the defender when the attacker is a friendly Human adjacent to a friendly Abyssal Knight; T2 `iron_resolve` is a static flag on `MinionInstance` (mirroring Seris's corruption-inversion pattern) that adds the minion's current armour to its `effective_atk()` for friendly Humans. Three pieces of new infrastructure were needed: `EffectStep.BUFF_ARMOUR` (routes through the existing `add_armour()` helper so T3's doubling check stays centralized), `ON_PLAYER_ATTACK` is now actually fired from `CombatManager.resolve_minion_attack` / `resolve_minion_attack_hero` with a new `EventContext.defender` field, and `talent_overrides` keyword/array assignment now goes through the typed-array path (Godot 4 silently rejects untyped Array → Array[int] via `set()`). 15 new test assertions, all green; pre-existing 543 unchanged.

Follow-ups: branch icon art (`icon_path` empty on all four talents). The `ON_PLAYER_ATTACK` infrastructure paves the way for Branch 3 T1 `abyssal_strike` (Corruption-on-attack) and T2 `path_of_destruction` (Demon-attacks-apply-AB) in task 004.
