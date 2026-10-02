---
id: "113"
title: Target highlights agree with the engine when the view lags (input during playback)
status: backlog
area: ui
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item E7, new in grooming (`design/refactors/ARCHITECTURE_ROADMAP.md` §E, the "Input vs. view" bullet, which had no candidate task). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The player may act whenever their turn has been shown, even while earlier events still play:

```gdscript
func player_can_act() -> bool:   # CombatScene.gd:427-428
	return state.is_player_turn and presenter.view.is_player_turn and not _end_turn_in_progress
```

So the board slots on screen (the view) can lag the engine by a whole command: a minion the engine has already killed is still shown, or one it has summoned isn't shown yet. Targeting mixes the two.

### Where view and engine are mixed

- **Attack targets**, `highlight_valid_attack_targets` (Targeting.gd:74-88):
  - `var has_taunt := CombatManager.board_has_taunt(_scene.state.enemy_board)` (:82) is the engine's Guard state;
  - the loop runs over the shown `_scene.enemy_slots` and calls `has_guard()` on the shown slot's minion (:83-87);
  - the hero is attackable from `has_taunt` and the attacker's live `can_attack_hero()` (:88).
- **On-play and spell targets** test the shown slots: `s.is_empty()` / `s.minion` (Targeting.gd:96, :98, :112, :115). `has_valid_minion_on_play_targets_for` (:150-163) decides from the shown slots whether a minion play enters the targeting flow (CombatInputHandler.gd:210).
- **Placement**: `highlight_empty_player_slots` (Targeting.gd:70-72) and the board-space check in `begin_minion_select` (CombatInputHandler.gd:206) use the shown `is_empty()`.
- **Blood Chalice** targets (CombatScene.gd:1170) and **Corrupt Flesh** targets (:1325-1328) highlight the shown slots.
- **Trap / environment targets** (Cyclone, `target_type == "trap_or_env"`): the click maps the clicked panel's index to the live `_scene.state.active_traps[trap_idx]` (CombatInputHandler.gd:411-412). Today the panels also render live traps, so the two agree. Once task 070 renders the panels from the view, a lagging panel can name a different live trap at that index.
- **Clicks** pass the shown slot's minion. `on_enemy_slot_clicked` (CombatInputHandler.gd:322-360) checks Guard against the engine board (:352), logs the narration (:354), then calls `cmd_attack`. A minion the engine has already removed is refused with "no_target" (CombatState.gd:2765-2766), and the player sees "Attack refused: no_target." (:357).

### Reachable today

**F2, Matriarch's Broodling.** Decks f2_a and f2_c hold Matriarch's Broodling, which has Guard (CardDatabase.gd:2699).
1. The player kills the Broodling, the enemy's only Guard, with a spell. The engine removes it at once.
2. During the spell's animation the player selects an attacker (`on_player_slot_clicked_occupied` only checks `player_can_act()`, CombatInputHandler.gd:287-288).
3. `has_taunt` is false in the engine, so every shown enemy slot is highlighted VALID, including the Broodling still on screen.
4. Clicking the Broodling logs "Your X attacks enemy Matriarch's Broodling" and "Attack refused: no_target.".

The reverse can happen too. If a reaction to the player's command puts an enemy Guard into the engine before it is shown, every shown target is marked INVALID with no visible reason. Reachability with today's content is not traced: no enemy deck holds a non-rune trap.

## Decision (owner, 2026-10-01)

QN5: "Keep player input responsive (do NOT gate on presenter idle). The display fixes (E1–E3, E7) make the UI correct during playback instead; E7 is needed." So `player_can_act()` stays as it is, and the highlights are fixed instead.

## Proposed fix

1. **One rule: a shown slot is targetable only if it shows what the engine has there.** Add `Targeting.in_sync(slot: BoardSlot) -> bool`: `_scene.state.slot_of(slot.slot_owner, slot.index).minion == slot.minion`. Both empty counts as in sync. BoardSlot already has `slot_owner` and `index` (BoardSlot.gd:27-28).
2. **Attack targets.** Decide validity from the engine slot's minion: `board_has_taunt(state.enemy_board)` and that minion's `has_guard()`. Draw a shown slot VALID only when it is in sync and valid, and INVALID otherwise. The hero stays as today: it has no occupant to disagree about.
3. **The other highlighters use the same rule:**
   - `highlight_minion_on_play_targets`, `highlight_spell_targets`, `has_valid_minion_on_play_targets_for` (Targeting.gd:90-120, :150-163);
   - `highlight_empty_player_slots` (:70-72) and the board-space check (CombatInputHandler.gd:206): a slot is free only if the engine slot is empty and the view shows it empty;
   - Blood Chalice (CombatScene.gd:1170) and Corrupt Flesh (:1325-1328);
   - trap / environment targets: `on_trap_env_input` accepts a panel only when the trap the view shows there is the live trap at that index. Task 050 step 2 gives these targets a side; keep that.
4. **Clicks follow the highlight.** `on_enemy_slot_clicked`, `on_player_slot_clicked_occupied` and the empty-slot click ignore a click on an out-of-sync slot: no command and no "refused" line. The engine still validates every command it gets.
5. **Re-highlight as the view catches up.** Targeting remembers the last highlighter it ran (a Callable); `clear_all_highlights` forgets it. When the presenter changes a shown slot (SLOT_CHANGED via `_apply_slot`, CombatPresenter.gd:789-799; deaths; summons) while a selection is active, it calls `scene.targeting.refresh_active()`, which re-runs it. Without this, a slot marked INVALID keeps that mark after the view catches up (`_show_empty_state` still draws `_highlight_mode`, BoardSlot.gd:555-560).
6. **Validity comes from the engine, display from the view.** Targeting keeps reading `_scene.state` for validity; that is its job, and task 111 (roadmap E4, lint L17, provisional; take the next free number if the landing order differs) excludes it for that reason. Write that down in Targeting.gd's header (:1-13).

## Verification

- **New LiveSmoke probe `_targets_follow_the_engine`** (debug/tests/LiveSmokeTests.gd):
  - Setup: launch F1. `var guard := st._summon_token("matriarchs_broodling", "enemy")`, `var other := st._summon_token("void_imp", "enemy")`, `var atk := st._summon_token("void_imp", "player")`, then `atk.state = Enums.MinionState.NORMAL` (test setup). Drain.
  - Action: `st.combat_manager.kill_minion(guard)` with no await, so the engine slot is empty while the view still shows the Broodling. Then `scene.selected_attacker = atk` and `scene.targeting.highlight_valid_attack_targets()`.
  - Expect: the Broodling's slot is INVALID (today VALID); the other imp's slot is VALID; the enemy hero is attackable.
  - Clicking the Broodling's slot (`scene._on_enemy_slot_clicked(node, guard)`) journals no COMMAND event and no "Attack refused" line.
  - Then drain. The ignored click left the attacker selected. The Broodling's ON DEATH summoned a Brood Imp (no Guard) into its emptied slot (`_summon_token` fills the first empty slot, CombatState.gd:582-586). Expect: that slot now shows the Brood Imp and is VALID, the other imp's slot is still VALID, and the hero is still attackable (step 5).
- Parity stays green. It waits for `presenter.is_idle()` before each player command (ParityTests.gd:139-142), so every slot is in sync and its click paths (`_click_minion`, :314-319) are accepted as before.
- `tools/run_checks.sh` green.
- Behaviour-neutral: input and highlight code only; no engine, sim or AI change, so the balance fingerprint (design/TESTING.md "Refactor / extraction work") can't move and needs no run.

## Related

- Related: task 070 (roadmap E1a) and task 071 (roadmap E1b) — the other display fixes QN5 calls for. After 070 the trap panels render the view, which makes the trap-target check in step 3 necessary.
- Related: task 050 — trap and environment targets carry their side (its step 2).
- Related: task 110 (roadmap E3) — slots draw their status from journal snapshots; validity here stays with the engine.
- Related: task 111 (roadmap E4, lint L17) — excludes Targeting and CombatInputHandler, whose engine reads are deliberate.
- Related: task 112 (roadmap E6) — moves refusal lines off the journal; this task removes the refusals that out-of-sync clicks cause.
- Related: task 048 — the presenter soft-lock guard. Not needed here, since input isn't gated on the presenter.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) as new roadmap item E7, from §E's "Input vs. view" bullet. Owner decision QN5 (input stays responsive) makes it needed.
  - Re-check widened the scope from attack targets to on-play, spell, placement, Blood Chalice and Corrupt Flesh highlights and the matching click handlers.

## Summary

_(filled in at /task-done)_
