---
id: "085"
title: SideState part 3: per-side turn counters and cost modifiers
status: backlog
area: combat
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item A6 (a new candidate from grooming; the roadmap's `SideState` direction lists "cost modifiers … and per-side counters", `design/refactors/ARCHITECTURE_ROADMAP.md` §A). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Tasks 083 and 084 move hand, deck, resources, traps, board and hero onto `SideState`. Neither owns the per-turn counters and cost modifiers. Each is a separate field, or a field pair with inconsistent names, read through `if side == "player"` branches. The unprefixed names are the player's.

### Per-side counter pairs (CombatState.gd)

| Pair | Lines | Written by | Read / cleared |
|---|---|---|---|
| `_enemy_traps_blocked` / `_player_traps_blocked` | :1731-1733 | Saboteur Adept, `BLOCK_OPPONENT_TRAPS_THIS_TURN` (EffectResolver.gd:267-276) | `_fire_traps_for` (:1034-1036); `end_turn` (:2465, :2468) |
| `_player_spell_counter` / `_enemy_spell_counter` | :1736-1737 | `COUNTER_SPELL` (EffectResolver.gd:250-257) | `_cmd_play_spell` (:2635-2644); CounterWarning.gd:44 |
| `_spell_tax_for_player_turn` / `_spell_tax_for_enemy_turn` | :1713-1714 | `TAX_OPPONENT_SPELLS_NEXT_TURN` (EffectResolver.gd:278-286) | `begin_turn` (:2425-2426, :2440-2441) |
| `player_spell_cost_penalty` / `enemy_spell_cost_penalty` | :1717-1720 | `begin_turn` | `spell_cost` (:2980-2981); `end_turn` (:2464, :2467); PhaseTransition.gd:97 |
| `_void_mana_drain_pending` / `_enemy_void_mana_drain_pending` | :1742-1744 | `QUEUE_OPPONENT_MANA_DRAIN_NEXT_TURN` (EffectResolver.gd:315-327) | `begin_turn` (:2427-2430, :2443-2446) |
| `_fiendish_pact_pending` / `_enemy_fiendish_pact_pending` | :1674-1677 | Fiendish Pact (HardcodedEffects.gd:115-120) | see below |

Every writer already computes the opponent and then picks a field with an `if`, e.g. EffectResolver.gd:271-275:

```gdscript
var opponent: String = ctx.state._opponent_of(ctx.owner)
if opponent == "enemy":
	ctx.state._enemy_traps_blocked = true
else:
	ctx.state._player_traps_blocked = true
```

### Cost modifiers that exist for one side only

- Enemy only: `enemy_spell_cost_aura` (:1723), `enemy_spell_cost_discounts` (:1724), `enemy_essence_cost_discounts` (:1725), `enemy_minion_essence_cost_aura` (:1728). Writers: the Void Ritualist Prime champion aura (CombatHandlers.gd:1755, :1763), F15 Abyssal Mandate (:1896-1907), the `corrupted_death` passive (CombatSetup.gd:622), and PhaseTransition's reset (:95-97).
- The cost functions branch on the side and apply different terms (CombatState.gd:2967-2982):

```gdscript
func minion_essence_cost(side: String, mc: MinionCardData) -> int:
	if side == "player":
		return maxi(0, mc.essence_cost - _peek_fiendish_pact_discount(mc))
	var cost: int = mc.essence_cost - (enemy_essence_cost_discounts.get(mc.id, 0) as int)
	return maxi(0, cost + enemy_minion_essence_cost_aura)
```

`spell_cost` does the same: the player gets the board's `mana_cost_discount` and the penalty; the enemy gets the penalty, the aura and the per-card discounts.

### Latent bug: an enemy Fiendish Pact does nothing

`_fiendish_pact` arms `state._enemy_fiendish_pact_pending = 2` when the enemy casts it (HardcodedEffects.gd:119-120), but nothing reads that field. `minion_essence_cost`'s enemy branch (above) ignores it, `_cmd_play_minion` takes `_peek_fiendish_pact_discount(mc) if side == "player" else 0` (:2554), and `_peek_fiendish_pact_discount` / `_consume_fiendish_pact_discount` read only the player's field and walk only `player_hand` (:442-458). `begin_turn` clears it (:2442). No enemy deck holds `fiendish_pact` (encounter_decks.json scan), so nothing reaches it today.

### Per-turn gates shared by both sides

- `_once_per_turn_used` (:1705) is cleared only at the player's turn start (:2436). ConditionResolver's `once_per_turn:<flag>` gate reads it (ConditionResolver.gd:24-29). Its only user is the `imp_evolution` talent rule (CardModRules.gd:104).
- `_soul_rune_fires_this_turn` (:1747) is one counter for both sides. `_soul_rune_death` caps it by the owner's Soul Rune count (HardcodedEffects.gd:226-240), and `soul_rune_reset` zeroes it (:58-59). A player's and an enemy's Soul Runes would share one budget. No enemy deck holds a Soul Rune.
- `last_player_growth` (:1764) records only the player's growth (the setter hooks at :1371-1384, and :2479). F15 Abyssal Mandate reads it (CombatHandlers.gd:1894).

### Crit multiplier override

`enemy_crit_multiplier` (:1784, "Per-side override; 0 = use global") is read as `if attacker.owner == "enemy" and state.enemy_crit_multiplier > 0.0` (CombatManager.gd:367-370) and written by the Void Scout champion aura (CombatHandlers.gd:1590, :1598).

### Presentation copies of the cost formula

`CombatScene._effective_spell_cost` (CombatScene.gd:1279-1280) re-implements the player's spell cost (`spell.cost - _spell_mana_discount() + state.player_spell_cost_penalty`), `CombatUI.refresh_hand_spell_costs` (CombatUI.gd:199) rebuilds the same discount and penalty for the hand display, and CombatInputHandler.gd:159 and :198 re-implement the Fiendish Pact essence cost. A per-side formula change would have to be made four times.

### Consequence

Each new per-turn, per-side flag adds another pair and another branch. The unprefixed player names hide that a rule is one-sided. The enemy-only cost terms make cost rules depend on the side, so a mechanic written for one side (Fiendish Pact) silently fails for the other.

## Decision (owner, 2026-10-01)

Q2: no mechanic is one-sided by design; who has what is data and config, never `if owner == "player"`. The plan's note for this task applies it: "the one-sided modifiers (enemy cost auras, discounts) also move per side — none is intentionally one-sided."

## Proposed fix

1. **SideState fields** (on task 083's class): `traps_blocked: bool`, `spell_counter: int`, `spell_tax_next_turn: int`, `spell_cost_penalty: int`, `void_mana_drain_pending: bool`, `fiendish_pact_pending: int`, `spell_cost_aura: int`, `spell_cost_discounts: Dictionary`, `essence_cost_discounts: Dictionary`, `minion_essence_cost_aura: int`, `once_per_turn_used: Dictionary`, `soul_rune_fires_this_turn: int`, `crit_multiplier_override: float` (0 = use the global `crit_multiplier`), `last_growth: String`.
2. **Legacy names become forwarders** (get/set properties), so tests, the champion handlers and CounterWarning keep compiling. `last_player_growth` forwards to `side("player").last_growth`; the growth hook moves into SideState's max setters so both sides record their growth.
3. **Writers address the side directly**: `ctx.state.side(opponent).traps_blocked = true`, and the same for COUNTER_SPELL, TAX_OPPONENT_SPELLS_NEXT_TURN, QUEUE_OPPONENT_MANA_DRAIN_NEXT_TURN and Fiendish Pact (`side(ctx.owner).fiendish_pact_pending = 2`). The Void Ritualist Prime, Abyssal Mandate and `corrupted_death` writers use `side("enemy")` for now; task 096 (roadmap B2) binds champions to their owner and task 086 binds registry entries.
4. **`begin_turn` / `end_turn`**: one helper for the counters instead of two copies. At `begin_turn(s)`: penalty = tax, tax = 0, drain mana if pending, clear Fiendish Pact (and clear `once_per_turn_used` if step 7 moved it). At `end_turn(s)`: clear `s`'s penalty and the opponent's `traps_blocked`. Call the helper where each branch handles its counters today: the player draws and readies its board before them (:2423-2436), the enemy after them (:2440-2448). Unifying that order would reorder journal events; it is not part of this task. Keep the two "Void Rift Lord" log lines and their log types.
5. **One cost formula per kind**, every term read from `side(s)`:
   - `minion_essence_cost(s, mc) = maxi(0, mc.essence_cost - fiendish_discount(s, mc) - essence_cost_discounts[mc.id] + minion_essence_cost_aura)`;
   - `spell_cost(s, spell) = maxi(0, spell.cost - board_discount + spell_cost_penalty + spell_cost_aura - spell_cost_discounts[spell.id])`.
   With zeros for the terms a side doesn't use today, both sides get the numbers they get now. The board `mana_cost_discount` term is task 089's (roadmap A8): if 089 hasn't landed, keep that term player-only with `# lint: allow-side (task 089)`.
6. **Fiendish Pact for either side** (the latent fix): `_peek_fiendish_pact_discount(side, mc)` and `_consume_fiendish_pact_discount(side)` read that side's pending discount and walk `hand_of(side)`; `_cmd_play_minion` (:2554) drops its `if side == "player" else 0`.
7. **Soul Rune and once-per-turn gates per side**: `_soul_rune_death` reads and writes `side(ctx.owner).soul_rune_fires_this_turn`, and `soul_rune_reset` resets the owner's counter. The `once_per_turn:` gate is task 108's (roadmap D7, step 4: key the flags by side and clear each side's at its own turn start). If 108 has landed, only move its per-side flags onto `side(s).once_per_turn_used` here and have ConditionResolver read `ctx.state.side(ctx.owner).once_per_turn_used`; if not, leave `_once_per_turn_used` to 108.
8. **Crit**: CombatManager.gd:367-370 reads `state.side(attacker.owner).crit_multiplier_override`. The Void Scout aura writes `side("enemy")` until task 096 moves it.
9. **Presentation calls the engine formula.** `CombatScene._effective_spell_cost` calls `state.spell_cost("player", spell)`, `CombatUI.refresh_hand_spell_costs` (:199) uses it per hand card, and CombatInputHandler.gd:159/:198 call `state.minion_essence_cost("player", mc)`. If task 109 (roadmap E2) has moved these displays to journal payloads, skip this step.
10. **Out of scope, owned elsewhere**:
    - `_player_crits_consumed` is dead (task 094, roadmap B1, deletes it); `_enemy_crits_consumed` is the Void Scout champion counter (task 095, roadmap B2a, moves it).
    - Seris state (`player_flesh`, `forge_counter`, `_player_spell_damage_bonus`, `_seris_corrupt_used_this_turn`, `_spell_cast_depth`, `_double_cast_in_progress`): task 097 (roadmap B3) and task 090.
    - Relic flags (`_relic_hero_immune`, `_relic_cost_reduction`): task 091.
    - `enemy_void_marks`, `void_mark_damage_per_stack`: task 092; `rune_aura_multiplier`: task 064, then task 090.
    - `attack_cancelled`, `_spell_cancelled`, `enemy_play_target`: task 129 (roadmap I1).
    - Encounter-passive gates (`_imp_caller_fired`) and champion counters: task 095.

## Verification

- New probe in debug/tests/CommandTests.gd, "side model / per-side counters":
  - `state.side("enemy").traps_blocked = true` → `state._enemy_traps_blocked` is true; `cmd_end_turn("player")` clears it.
  - The existing Saboteur probe in `_trap_route_enemy_trap_on_player_turn_start` (TriggerHandlerTests.gd:3463-3466) still passes.
- New probe in debug/tests/CardEffectTests.gd, "fiendish_pact / enemy caster":
  - Setup: enemy hand with `fiendish_pact` and two Demons; cast it for the enemy.
  - `minion_essence_cost("enemy", demon)` is 2 less (capped at the Demon's cost); after the enemy plays one Demon, the next costs full price; the player's pending discount is unchanged throughout.
  - Keep the existing player-side Fiendish Pact assertions.
- New probe in CommandTests.gd, "cost formula / same terms both sides": for each side, set `spell_cost_aura`, `spell_cost_discounts[id]`, `spell_cost_penalty`, `essence_cost_discounts[id]` and `minion_essence_cost_aura` on `side(s)`; `spell_cost` and `minion_essence_cost` apply them identically for both sides.
- New probe in debug/tests/TriggerHandlerTests.gd, "soul_rune / budgets per side": a player and an enemy Soul Rune; a player Demon dies on the enemy's turn and an enemy Demon dies on the player's turn; each side gets its own spark, and neither side's firing uses the other's budget.
- `tools/run_checks.sh` green.
- Behaviour change, latent only (enemy Fiendish Pact, per-side Soul Rune and once-per-turn budgets): no enemy deck holds `fiendish_pact` or a Soul Rune, so the seeded fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, `--act 1` through `--act 4`) should diff empty. Record the result in the task summary (Q3); any moved row is a regression to explain.

## Related

- Depends on: task 083 — SideState and `side(s)`.
- Related: task 084 (roadmap A2): SideState part 2 (traps, board, hero).
- Related: task 089 (roadmap A8): makes the board `mana_cost_discount` term side-neutral.
- Related: tasks 094 / 095 (roadmap B1 / B2a): own the crit-consumed counters and the champion cost-aura state.
- Related: task 096 (roadmap B2): champion auras write their owner's side.
- Related: tasks 090, 091, 092, 097: per-side talents, relics, Void Marks and Seris state, listed under step 10.
- Related: task 109 (roadmap E2): the counter warning and cost displays render journal payloads.
- Related: task 108 (roadmap D7): owns the per-side `once_per_turn:` gate (step 7 above only moves its storage onto SideState).
- Related: task 087 (roadmap A4, lint L16, provisional; take the next free number if the landing order differs): lower its baseline in this task's commit.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item A6 (new). Q2 widened it to the enemy-only cost modifiers. Found while re-checking: an enemy Fiendish Pact arms a discount nothing reads (latent), Soul Rune's counter is shared by both sides, and the scene re-implements the spell-cost formula.

## Summary

_(filled in at /task-done)_
