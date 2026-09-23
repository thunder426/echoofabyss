---
id: "041"
title: Live/sim unification — Phase 1 (rules code addresses state)
status: active
area: combat
priority: normal
started: 2026-09-23
finished:
---

## Description

Execute Phase 1 of `design/refactors/LIVE_SIM_UNIFICATION_PLAN.md` in the plan's order (1.1 → 1.3 → 1.4 → 1.2 → 1.5): add the presenter seam and lint L3/L4, hoist enemy-side and player resource/deck/hand state onto CombatState, move the gameplay-only scene/SimState method pairs onto CombatState, rewrite the rules code to address a typed `state` (presentation only through a nullable `presenter`), and put RelicRuntime on state. One commit per green step; `tools/run_checks.sh` gates every step.

## Work log

- 2026-09-23: opened. Reviewed Phase 0 (0.605–0.614) against the plan — no defects found; baseline `tools/run_checks.sh` green: lint 0, 797/797, LiveSmoke OK.
- 2026-09-23: 1.1 — `CombatState._scene_facade` → `presenter` (null in sim); `_get_scene_facade()` kept (presenter-or-self). `tools/lint/presentation_allowlist.txt` + lint L3/L4, computed but not enforced until 1.2 (baseline L3 477, L4 163 — the 1.2 work list). **Deviation:** a third route besides `state.` / `presenter.`: `[facade]` for the 8 CombatScene overrides whose live body is still VFX-bound (`_apply_void_mark`, `_corrupt_minion`, `_deal_void_bolt_damage`, `_deal_enemy_void_bolt_damage`, `_fire_ritual`, `_sacrifice_minion`, `_summon_token`, `_summon_token_at_slot`) — routing them to `state` would drop the projectile/sigil/ritual VFX or change B13 timing; they stay on the facade (scene live, state in sim) until Phase 3.0, and L3 requires each to be a func on both classes. L4 is receiver-based (object handles only) — a blanket `.get("` ban would hit Dictionary reads. Pack Instinct's ATK-label hold moved from the handler into `_spawn_pack_instinct_buff_vfx(minion, old_atk)`.

## Summary

_(filled in at /task-done)_
