---
id: "043"
title: Live/sim unification — Phase 3
status: active
area: combat
priority: normal
started: 2026-09-24
finished:
---

## Description

Phase 3 of `design/refactors/LIVE_SIM_UNIFICATION_PLAN.md`: make every gameplay mutation synchronous inside the engine (3.0 de-async), give the engine plain slot data (3.1a SlotState, D11), add the `CombatEvent` journal (3.1), build `ViewState` + `CombatPresenter` that plays one animation per event (3.2, D4 hybrid), delete the VFX gates (3.3), and switch live input and the live enemy turn onto `state.cmd_*` (3.4). Checkpoint decisions taken at the start: D11 = SlotState, D3 = on-death inline, D4 = hybrid ViewState.

## Work log

- 2026-09-24: opened. Checkpoint decisions D11 (SlotState), D3 (inline on-death), D4 (hybrid ViewState) recorded in the plan (section 3.3 table + "Checkpoint decisions" + new step 3.1a). Baseline `tools/run_checks.sh` at `5454e70`: green, 1084/1084, lint 0, LiveSmoke OK.
- 2026-09-24: **3.1a — SlotState (D11), landed before 3.0** (deviation from the plan's order: taking occupancy off the view first removes the bridge's `place_minion`/`remove_minion` mutations from 3.0's list). New `combat/board/SlotState.gd` (RefCounted: `side`, `index`, `minion`, `is_empty`, `place` stamps `slot_index`, `clear`; both emit `changed`). `CombatState._init` allocates BOARD_MAX per side and relays `slot_changed(side, index)`; `slot_of`, `slot_for`. `BoardSlot` is a view: `place_minion`/`remove_minion` → `show_minion`/`show_empty` (no slot_index write); `CombatScene.player_slots/enemy_slots` are now the scene's own node arrays (the state forwarders are gone), `slot_node(side, i)`, `_find_slot_for` maps through the engine first, `_on_slot_changed` mirrors occupancy (a frozen node keeps a dead occupant's art until `_flush_deferred_death_for` plays its ghost — a placement into such a node flushes first). Engine occupancy is now taken **at once** on every live path: player card flight (`_try_play_minion_animated`), enemy reveal (`EnemyAI.commit_minion_play`), token/champion/sigil summons (`_spawn_token_into_slot_vfx`), the ritual demon (`_summon_void_demon_synced`); the node is frozen on its empty look until the entrance animation reveals it. Agents: `CombatAgent.find_empty_slot() -> SlotState` / `commit_play_minion(inst, slot: SlotState)` on both shells (EnemyAgent maps the index to the node for EnemyAI); 40 profile sites retyped. `_transfer_to_player_board`, Formation adjacency, `TargetResolver` ADJACENT, `EnemyAI.consume_minion`, PhaseTransition, TestHarness spawns read/write SlotState. Deleted: dead `CombatScene._try_play_minion` (no callers), `_clear_slot_for` (no callers), SimState's `BoardSlot.new()` loop (sim no longer leaks 10 Panels per fight — the batch's `108000 RIDs of type CanvasItem were leaked` warning is gone). Lint L6 extended: no `BoardSlot` in CombatState/SimState/CombatHandlers/EffectResolver/TargetResolver. Probe `CommandTests._slots_are_engine_slot_states` (14 assertions). **Live gameplay change:** a slot whose occupant died mid-animation is free for the engine immediately (a token summoned during the death animation can take it) — sim always did this. run_checks green (1084/1084 + probe, lint 0 with L6', LiveSmoke OK). **Balance:** Act 1 batch (200 runs, seed 7) byte-identical to `042-balance/bal_post2a_act1.txt`; Act 2 likewise vs `bal_post2a_act2.txt` (the only diff in both: the leaked-CanvasItem warning is gone). ARCHITECTURE (state layer, live shell, file table) and TESTING (L6) updated.

## Summary

_(filled in at /task-done)_
