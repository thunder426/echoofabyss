---
id: "143"
title: Per-copy cost discounts are shown but not charged for minions and spells (Squire of the Order → Abyssal Knight)
status: backlog
area: combat
priority: high
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §A/§D; raised by the task 056 pass-1 consistency check). Re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Cost effects write a per-copy delta on the `CardInstance` in hand:
- `MOD_HAND_CARDS_COST` / `MOD_LAST_ADDED_COST` (`EffectResolver.gd:188-216`): `inst_to_mod.essence_delta += step.amount` / `mana_delta += step.amount`, then journal HAND_COSTS_CHANGED.
- The hand shows the discount: `HandDisplay.gd:281`, `:296-299` (`var inst_ess_bonus: int = -inst.essence_delta`).

The engine never charges it for minions or spells:
- `card_cost` (`CombatState.gd:2953-2962`): a minion costs `Vector2i(minion_essence_cost(side, mc), maxi(0, mc.mana_cost))`, and a spell costs `spell_cost(side, card as SpellCardData)`. Both take the card data, not the instance, so neither `essence_delta` nor `mana_delta` is read. Only traps use `inst.effective_cost()`, which applies `mana_delta`.
- `minion_essence_cost` (`:2967-2971`) subtracts only the Fiendish Pact discount and the enemy's per-card discounts and aura.
- The live input handler repeats the same formula: `CombatInputHandler.gd:159` and `:198`, `maxi(0, mc.essence_cost - _scene.state._peek_fiendish_pact_discount(mc))`.
- In `combat/board/`, `essence_delta` is only ever cleared (`CombatState.gd:459`).

### Reachable today

Korrath core: Squire of the Order (`CardDatabase.gd:559-567`, "FORMATION: Abyssal Knights in your hand cost 2 less Essence") runs `{"type": "MOD_HAND_CARDS_COST", "card_id": "abyssal_knight", "resource": "essence", "amount": -2}`. After a Formation, the hand shows each Abyssal Knight 2 Essence cheaper, but the engine still charges full price:
- With exactly the shown Essence, the play is refused.
- With enough Essence, the player pays 2 more than shown.

The AI and the sim are affected the same way, since they plan through `plan_cost` → `card_cost`.

### Latent

Any future minion or spell `MOD_*_COST` step, and any `mana_delta` on a minion or spell, has the same gap.

## Proposed fix

1. **One cost formula.** `card_cost(side, inst)` applies the instance deltas for every card type:
   - minion: `minion_essence_cost(side, mc) + inst.essence_delta` and `mc.mana_cost + inst.mana_delta`;
   - spell: `spell_cost(side, spell) + inst.mana_delta`.
   
   Clamp each axis at 0 after the deltas; `EffectResolver.gd:213` already says the floor is enforced at play time.
2. **Live input and display go through it.** `CombatInputHandler.gd:159` and `:198` call `state.card_cost("player", inst)` instead of re-deriving the cost. Check the other copies of the formula that task 085 lists (CombatUI.gd:199, HandDisplay, LargePreview), so the display reads the same number.
3. **Clear deltas when they expire.** Confirm when a Squire discount ends (turn end? on play?) against KORRATH_HERO_DESIGN, and make sure the delta is reset on that boundary (`CardInstance.gd:63-64` resets both).

## Verification

- **New probe** in `debug/tests/TriggerHandlerTests.gd`, beside the Korrath Formation probes:
  1. Put Squire of the Order and a Formation partner on the board so Formation fires, with an Abyssal Knight in hand and Essence equal to the knight's cost − 2.
  2. Assert `card_cost("player", knight_inst).x == essence_cost - 2`.
  3. Assert `cmd_play_minion` succeeds and leaves Essence at 0.
- Add a spell `mana_delta` probe with a test-built `MOD_LAST_ADDED_COST` step.
- `tools/run_checks.sh` green.
- **Behaviour change:** record the BalanceSimBatch delta in the task summary. BalanceSimBatch has no Korrath preset, so expect the fingerprint for Acts 1–4 to diff empty. If it doesn't, an existing card also writes a delta: find it before landing.

## Related

- Related: task 085 (roadmap A6) — moves the cost formula per side and lists its four copies; land this first or fold this fix into its single formula.
- Related: task 104 (roadmap D1) — the content check could flag cost-delta steps on card types the engine doesn't charge.
- Related: task 011 (Korrath mechanic gaps), task 012 (Korrath balance and AI).

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from the consistency check's open issues; the trace was re-checked at `404b51c`.

## Summary

_(filled in at /task-done)_
