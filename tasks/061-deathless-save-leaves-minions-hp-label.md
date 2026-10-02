---
id: "061"
title: Deathless save leaves the minion's HP label at ≤0
status: backlog
area: ui
priority: normal
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §I, item 7: "likely display bug"; unit I, candidate I7a). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Since task 046, a slot's labels move only with journal events:
- BoardSlot renders `shown_hp` (`_hp_text`, BoardSlot.gd:308-311).
- The presenter sets it from the DAMAGE_DEALT `hp_after`, the MINION_HEALED `hp_after` and the MINION_STATS_CHANGED `hp` (CombatPresenter.gd:730-743).

Both death saves change HP after DAMAGE_DEALT has been journaled, and journal no stats event:
- **DEATHLESS keyword** (CombatManager.gd:273-283). DAMAGE_DEALT goes out with `hp_after = minion.current_health` (≤ 0), then:
  ```gdscript
  if minion.has_deathless():
      BuffSystem.remove_type(minion, Enums.BuffType.GRANT_DEATHLESS)
      minion.current_health = 50
      return
  ```
- **Seris `deathless_flesh`** (:288 → `_try_save_from_death`, CombatState.gd:1111-1122). `player_flesh -= 2` journals FLESH_CHANGED through its setter, then `minion.current_health = 50` and a LOG line. Nothing carries the new HP. `kill_minion` (:335-338) reaches the same save.

So the slot shows the ≤ 0 value on a living 50-HP minion:
- In an attack, the lunge tweens to it (CombatScene.gd:1821-1823, `def_slot.animate_hp_change(hit_d.payload.get("hp_before", 0), hit_d.payload.get("hp_after", 0), …)`), and `_emit_ui` stores it (CombatPresenter.gd:730-732).
- It stays until the next event that carries this minion's HP. In practice that is the presence-aura recompute on the next summon or death anywhere, which re-journals every slot (CombatHandlers.gd:1076-1081). TURN_STARTED only re-renders the shown values (CombatPresenter.gd:749-752), so it doesn't fix the label.

### Reachable today

- **Bulwark Automaton** (300/500, DEATHLESS; CardDatabase.gd:1735-1742; `neutral_core` pool, :3537), for any hero.
  - Example: an enemy Bastion Colossus (600/800, in the f11_a, f12_a, f14_a, f15_a and f15_p2 decks) attacks it: 500 → -100, or -700 with one of the Colossus's Critical Strike stacks. Then the save sets 50.
  - The Automaton's counter doesn't kill the Colossus, so no death refreshes the board, and the slot keeps showing "-100".
- **Imp Idol** (Vael Endless Tide, CardDatabase.gd:2503-2511): "Give all friendly VOID IMP CLAN minions DEATHLESS."
- **Seris `deathless_flesh`** on Grafted Fiends (the Fleshcraft capstone, TalentDatabase.gd:233-235).

## Proposed fix

The plan's ruling is to journal a stats event after the save.

1. In `_deal_damage`'s DEATHLESS branch (CombatManager.gd:280-283), call `state._refresh_slot_for(minion)` (guarded by `state != null`) after `minion.current_health = 50`.
2. In `CombatState._try_save_from_death`, call `_refresh_slot_for(minion)` after `minion.current_health = 50` (:1119). That covers both `_deal_damage` (:288) and `kill_minion` (:336).
3. Optional: a LOG line for the keyword save (for example "%s survives (Deathless)"), like Deathless Flesh's (:1120), so the combat log explains the 50.

The journal then reads DAMAGE_DEALT (`hp_after` -100) → MINION_STATS_CHANGED (`hp` 50):
- The lunge tweens to -100, then the stats event moves the label to 50; a running tween is re-targeted (task 046).
- `_hp_shown_ahead` (CombatPresenter.gd:168-169) doesn't block it, because the stats event has the later `seq`.
- The stats event also re-renders the slot (`node._refresh_visuals()`, :743), so the spent DEATHLESS icon (read live, BoardSlot.gd:685) goes away at the same time.

Not taken: resolving the save before journaling and sending DAMAGE_DEALT with `hp_after = 50` and `saved = true`. It looks smoother (500 → 50), but `hp_after` would no longer mean the HP after the hit.

## Verification

- New probe in `debug/tests/CardEffectTests.gd`:
  - Setup: `TestHarness.build_state({})`; `auto = spawn_friendly(state, "bulwark_automaton")`; `col = spawn_enemy(state, "bastion_colossus")`. Record the journal size, then `state.combat_manager.resolve_minion_attack(col, auto)`.
  - Assert `auto.current_health == 50` and it is still on the board.
  - Assert the last new event for `auto` that carries HP (DAMAGE_DEALT `hp_after`, MINION_STATS_CHANGED `hp` or MINION_HEALED `hp_after`) says 50. Today it is DAMAGE_DEALT with -100.
- Extend `TriggerHandlerTests._deathless_flesh` (debug/tests/TriggerHandlerTests.gd:297-307) with the same last-HP assertion.
- New LiveSmoke probe (debug/tests/LiveSmokeTests.gd), in the style of `_hp_labels_lag_the_engine` (:161):
  - Setup: `_launch(1, "swarm")`; `st._summon_token("bulwark_automaton", "player")` and `st._summon_token("bastion_colossus", "enemy")`; `st.combat_manager.resolve_minion_attack(colossus, automaton)`; `await _drain(scene)`.
  - Assert the Automaton's slot (`scene._find_slot_for(automaton)`) has `shown_hp == 50` and `_hp_label.text == "50"`.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the change only adds journal events, and nothing connects to `minion_stats_changed` (only the presenter reads the journal). The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, Acts 1–4) diffs empty (design/TESTING.md 'Refactor / extraction work').

## Related

- Related: task 135 (roadmap I8) — depends on this task. Its idle-consistency probe (every slot shows the engine's stats when the presenter is idle) would catch this class; with this fix reverted, it should fail on the Automaton case.
- Related: task 136 (roadmap I7d) — depends on this task. Cutting the no-op presence-aura re-journal removes the refresh that currently masks this label after the next summon or death.
- Related: task 110 (roadmap E3) — BoardSlot status visuals, including the DEATHLESS icon, from the journal snapshot.
- Related: task 057 — stops `_try_save_from_death` from running on a minion that is already off the board.
- Related: task 097 (roadmap B3) — moves `_try_save_from_death` into the per-side Seris module. Today it returns false for any non-player minion (CombatState.gd:1112).

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item I7 (unit I candidate I7a / straight-to-task bug 1). Re-checked at `404b51c`: neither save journals the new HP, labels render `shown_hp`, and TURN_STARTED doesn't correct it. Followed the plan's fix (a stats event after the save), put in `_try_save_from_death` so the `kill_minion` path is covered too.

## Summary

_(filled in at /task-done)_
