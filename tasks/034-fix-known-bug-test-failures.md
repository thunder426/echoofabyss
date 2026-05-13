---
id: "034"
title: Fix the 3 KNOWN BUG test failures
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

Three tests in the test suite have been intentionally failing since they were written, each labeled `KNOWN BUG` in-test. Each represents a real symmetric-handling gap in the combat code — a player-side effect that has no enemy-side mirror, or an enemy-passive whose state flag is never set. Resolving them gets the suite to 100% green and closes long-standing parity holes.

The 3 failures:

1. **`fiendish_pact / enemy cast arms discount on enemy side`** — [debug/tests/CardEffectTests.gd:191](debug/tests/CardEffectTests.gd#L191). `HardcodedEffects._fiendish_pact` early-returns when `ctx.owner != "player"`, so an enemy-cast Fiendish Pact arms no discount on the enemy side. **Fix:** add a symmetric enemy-side field (`_enemy_fiendish_pact_pending` or similar) and mirror the discount-on-next-Demon logic for the enemy. Confirm the cost-display hint on Demons in enemy hand updates too.

2. **`void_rift_lord / player cast drains enemy mana next turn`** — [debug/tests/CardEffectTests.gd:455](debug/tests/CardEffectTests.gd#L455). The player-cast path for `void_rift_lord`'s mana-drain effect has no enemy-side flag, so the drain never lands. **Fix:** add a symmetric enemy-side mana-drain flag and the start-of-turn handler that consumes it. Same pattern as the existing player-side drain.

3. **`champion_vch / 3 crit-kills summon champion (flag not set)`** — [debug/tests/TriggerHandlerTests.gd:1676](debug/tests/TriggerHandlerTests.gd#L1676). `_summon_enemy_champion`'s match block in `combat/events/CombatHandlers.gd` (lines ~1634-1660) is missing the `"champion_void_champion"` case, so `_champion_vch_summoned` never flips to true after summoning. The Void Champion minion is still placed on the board (the aura works by accident via enemy_board scan), but re-summon guards never engage. **Fix:** add `"champion_void_champion": _scene.set("_champion_vch_summoned", true)` to the match (per the in-test fix hint at TriggerHandlerTests.gd:1682).

Verification: after each fix, run `godot --headless --path . res://debug/tests/RunAllTests.tscn` and confirm the relevant test now passes without breaking any other test. Final state should be a fully green suite.

## Work log

- 2026-05-12: opened.

## Summary

_(filled in at /task-done)_
