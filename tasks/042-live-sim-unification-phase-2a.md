---
id: "042"
title: Live/sim unification — Phase 2A (engine commands, shared turn engine, trap routing)
status: active
area: combat
priority: normal
started: 2026-09-23
finished:
---

## Description

Execute Phase 2A of `design/refactors/LIVE_SIM_UNIFICATION_PLAN.md`: give CombatState a synchronous `cmd_*` surface used by sim and tests, share trap routing and the turn engine between both shells, unify enemy resource growth on one hook, move sim onto a single StateAgent + ProfileRegistry (deleting SimPlayerAgent / SimEnemyAgent / SimTurnManager), put encounter data in one table, and add sim replay. Live input and the live enemy turn stay on EnemyAI / `_try_play_*` until Phase 3.4.

## Work log

- 2026-09-23: opened. Owner decisions: **D1 = port** the 17 enemy growth curves to the shared hook; **D2 = live player order** (refill → draw → unexhaust → ON_PLAYER_TURN_START); **D9 = symmetric enemy order** (growth → refill → Void Rift Lord drain → draw → unexhaust → ON_ENEMY_TURN_START); **D8 = before** (ON_PLAYER_SPELL_CAST fires before resolution, live changes); **D10 = next turn start** (player growth choice stored at end-turn, applied in begin_turn("player")); **D5 = façade** (TurnManager stays as a façade in 2A, default). Pre-2A balance baseline captured at e4293d9: `BalanceSimBatch --act 1|2 --runs 200 --seed 7`, 0 SCRIPT ERROR. Outputs in `tasks/042-balance/`. Suite baseline 818/818 + LiveSmoke.
- 2026-09-23: 2A.1 — `CommandResult` + a `# Commands` section on CombatState: `cmd_play_minion / cmd_play_spell / cmd_play_trap / cmd_play_environment / cmd_attack / cmd_attack_hero / cmd_consume_minion / cmd_activate_relic / cmd_hero_skill`, one body per command for both sides, validate-then-mutate (refusals leave digest + log untouched), costs paid inside (`card_cost`, `minion_essence_cost`, `spell_cost`, `spark_cost_of`, Dark Mirror via `pay_card_cost`, Fiendish Pact consumption), `command_log` with targets by slot / hero sentinel. Rules folded in: player spell board discount (Void Archmagus `mana_cost_discount` — sim profiles never applied it), Phase Disruptor counter both sides, **Null Seal / Silence Trap `_spell_cancelled` now checked for both sides** (sim never checked it for enemy spells), Guard as validation both sides (no random redirect), Smoke Veil `attack_cancelled` + attacker-died-to-trap on enemy attacks, trap cap + duplicate rule both sides, `ON_*_TRAP_PLACED` both sides (B6), environment replace runs both halves (on_replace for its owner — `_unregister_env_aura` gained `owner`; player ritual handlers), minion event order = live's (slot → PLAYED → board → SUMMONED) for both sides, D8 spell-cast event before resolution. **Spark costs:** fuel is an input (`extra.spark_fuel`, the caller's pick; shortfall paid in Mana under `mana_for_spark`) or the engine's `pay_sparks` pick when absent — so profiles that plan fuel won't double-pay at 2A.5. Blood Chalice takes its target as input (resolves via `_spell_dmg` like live; sim's auto-pick moves to SimRelicPolicy in 2A.6). Imp Barricade `redirect_attack_target` deleted from EnemyAI (nothing wrote it). New `CommandTests` layer (+127 assertions → 945). **Deviations:** `cmd_end_turn` lands with the turn engine in 2A.3; `void_manifestation` follows live (plain attack tagged VOID_BOLT — crit/lifedrain/attack triggers, no Void Mark bonus; CardModRules documents that as the intended migration) — sim's `_deal_void_bolt_damage` bypass goes when sim moves onto commands (2A.5; DESIGN_DOCUMENT still says "with Void Mark bonus"). **Found, not fixed (out of scope):** Squire of the Order's "Abyssal Knights cost 2 less Essence" writes `essence_delta`, which the hand displays but no payment path (live or sim) reads — the discount never applies; enemy Fiendish Pact (`_enemy_fiendish_pact_pending`) is set but never consumed.

## Summary

_(filled in at /task-done)_
