---
id: "067"
title: F15 Avatar of the Abyss: its card counter resets to 0 at the phase 1 → 2 transition, against its documented intent
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §B, unit B bug 2). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### What happens

- F15 lists `champion_abyss_sovereign` among phase 1's passives (EncounterTable.gd:142).
- During phase 1, every player minion or spell runs `on_player_card_champion_as` (CombatHandlers.gd:1854-1871).
  - It increments `_champion_as_cards_played` and journals CHAMPION_PROGRESS, up to 12/12 pips.
  - The summon waits for phase 2: `if total >= _AS_THRESHOLD and state._sovereign_phase == 2:` (:1864).
- When phase 1's HP reaches 0, `PhaseTransition._do_transition` calls `_swap_passives` (PhaseTransition.gd:101-109):
  ```gdscript
  for p in SOVEREIGN_P1_PASSIVES:
      CombatSetup.unapply_passive(p, st.trigger_manager, st._handlers)
  for p in SOVEREIGN_P2_PASSIVES:
      CombatSetup.apply_passive(p, st)
  ```
- Both lists contain `champion_abyss_sovereign` and `void_might` (:24-25).
- `apply_passive` always re-runs the registry's `stats` (CombatSetup.gd:643-645, `st.set(stat, entry["stats"][stat])`). For this passive that is `{ "_champion_as_cards_played": 0, "_champion_as_summoned": false }` (:427).

So every card played in phase 1 is thrown away. The player needs 12 more cards in phase 2, and the pips fall from up to 12/12 back to 1/12 on the first card of phase 2.

The reset has been there since the champion was added (v0.596, `1f1364b`): `apply_passive` already set the registry stats then.

### Intended behaviour

The code says the counter should carry over, in four places:
- PhaseTransition.gd:21-23: "champion_abyss_sovereign is registered on the base encounter (P1 list) so the card-played counter ticks from the first turn. The handler itself gates the actual summon on _sovereign_phase == 2."
- CombatHandlers.gd:1846: "Summon condition: player has played 12 cards (minions + spells, total fight)."
- CombatHandlers.gd:1862-1863: "Gate the summon on Phase 2 so the avatar can never appear during P1, even if the player burns through 12 cards before the Sovereign's HP drops."
- TriggerHandlerTests.gd:1767: "Counter ticks across both phases, but summon is gated on _sovereign_phase == 2."

The card text says "Summoned after the player plays 12 cards." (CardDatabase.gd:3045).

The one exception is the v0.596 commit message, which says "summons after 12 player cards played in P2". That describes what the code does, not the comments' intent.

**Grooming ruling (task 056, 2026-10-01):** fix the code to the documented intent, so the counter carries over. Record the F15 delta.

### Why no test caught it

The AS probes at TriggerHandlerTests.gd:1771-1807 set `state._sovereign_phase = 2` directly (:1798). They never run `PhaseTransition`. `ScenarioTests._f15_abyss_sovereign_phase_transition` (:300) runs an F15 sim, but it accepts phase 1 or 2 at the end and never looks at the counter.

### The mechanism is general

`apply_passive` resets a passive's registry `stats` every time it is applied. So any passive kept across a mid-fight swap loses its state. Today only `champion_abyss_sovereign` has stats among the kept passives (`void_might` has `"stats": {}`, :462). This belongs to the B finding "registry stats re-application". Task 095 (roadmap B2a) should make champion state reset only at setup.

## Proposed fix

1. Make `PhaseTransition._swap_passives` diff the lists against what is registered now (`st.enemy_passives`, which is the P1 list at this point):
   - Unapply only the passives not in the P2 list (`abyssal_mandate`, `dark_channeling`).
   - Apply only the passives not already registered (`abyss_awakened`).
   - Then `st.enemy_passives.assign(SOVEREIGN_P2_PASSIVES)` as today.

   Kept passives (`void_might`, `champion_abyss_sovereign`) keep their trigger registrations and their stats.
2. Handler order: `void_might` and `abyss_awakened` both run on ON_ENEMY_TURN_START at priority 5 (CombatSetup.gd:461, :465). Today the swap re-registers `void_might` and then adds `abyss_awakened`. With the diff, `void_might` keeps its setup slot and `abyss_awakened` is still added after it, so their order is unchanged. Check that the AS handlers (priorities 91 / 95) don't share a priority with any other F15 handler registered after setup. If one does, its order changes; say so in the summary.
3. Leave the summon gate as it is. If the player played 12 or more cards in phase 1, the Avatar arrives on the first card played in phase 2, and the pips stay at 12/12 until then. Summoning at the transition itself would be a design change; don't make it here.
4. Fix the stale tuning comment at CombatState.gd:1943-1944 ("threshold tuned so the champion lands in Phase 2 in the average run"). That tuning was done with the reset in place. Say what the BalanceSimBatch delta shows, and note any retune as a follow-up rather than doing it in this task.

## Verification

- New probe in `debug/tests/TriggerHandlerTests.gd`, `_as_counter_carries_over_phase_transition`:
  - Setup: `TestHarness.build_state({"enemy_passives": PhaseTransition.SOVEREIGN_P1_PASSIVES})`, then `state.enemy_profile_id = "abyss_sovereign"` (`_sovereign_phase` defaults to 1). Fire `_fire_player_played` 8 times.
  - Call `PhaseTransition.attempt(state)` and assert it returns true.
  - Assert `_champion_as_cards_played == 8`.
  - In `state.trigger_manager.dump_order()`, assert:
    - `on_player_card_champion_as` appears once under ON_PLAYER_MINION_PLAYED, and `on_enemy_turn_void_might` once under ON_ENEMY_TURN_START;
    - `on_enemy_turn_abyss_awakened` is present;
    - `on_enemy_turn_start_abyssal_mandate` and `on_enemy_spell_dark_channeling` are gone.
  - Three more plays: not summoned. The 4th: the champion is on the board with 2 Critical Strike stacks.
  - The probe doesn't need the `f15_p2` deck; an empty deck from a missing `user://encounter_decks.json` is fine.
- Second probe: play 13 cards in phase 1 and transition. The first card in phase 2 summons the Avatar.
- The existing AS probes (:1771-1807) still pass. The handler-order snapshot (`debug/tests/snapshots/handler_order.txt`) is built at setup and doesn't cover the swap, so it stays unchanged.
- `tools/run_checks.sh` green.
- Behaviour change: record the BalanceSimBatch delta in the task summary.
  - Run `BalanceSimBatch -- --fight 15 --runs 200 --seed 7` before and after. Add `-- --act 4 --runs 200 --seed 7` to confirm F10-F14 don't move.
  - Expect the Champ column (average champion summons) to rise and the player's F15 win rate to fall.

## Related

- Related: task 095 (roadmap B2a). It depends on this task. It owns the general fix: champion state resets at setup (module `reset()`), not on every `apply_passive`.
- Related: task 125 (roadmap H3). PhaseTransition will read its phase-2 spec from EncounterTable; the diff-based swap must keep working when the lists come from data. Task 125 also deletes `SOVEREIGN_P1_PASSIVES` and keys the transition on `state.enemy_phase2` instead of `enemy_profile_id`, so whichever of 067 / 125 lands later updates this task's probe setup.
- Related: task 050. It reworks `PhaseTransition._clear_combat_state` (trap and environment removal) in the same file; `_swap_passives` doesn't overlap.
- Related: task 066. The other champion bug (F1/F3/F4 auras); independent.
- Related: task 068. Adds the missing Avatar tooltip; its text should say the count runs from the first turn.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from unit B's straight-to-task bug B-bug2 (roadmap §B). Re-checked at `404b51c`. The reset has existed since `1f1364b` (v0.596). Handler line ranges corrected (`_swap_passives` is :101-109).

## Summary

_(filled in at /task-done)_
