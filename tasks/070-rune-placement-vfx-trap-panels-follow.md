---
id: "070"
title: Rune placement VFX and trap panels follow the journal (payload slot + trap snapshot)
status: backlog
area: ui
priority: high
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item E1 (`design/refactors/ARCHITECTURE_ROADMAP.md` §E). Grooming split E1 in two: E1a (this task, runes and trap panels) and E1b (task 071, enemy hero panel). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The engine journals each placement with its slot, then the new trap list (CombatState.gd:2692-2694):

```gdscript
traps.append(trap)
emit_event(CombatEvent.Kind.RUNE_PLACED if trap.is_rune else CombatEvent.Kind.TRAP_PLACED, side, {trap = trap, slot = traps.size() - 1})
_update_trap_display_for(side)   # TRAPS_CHANGED {traps = traps_of(side).duplicate()}, :137-139
```

The presentation ignores both payloads and reads the live trap arrays:
- `CombatPresenter._play_trap_placed` (:432-440) passes only `(trap, ev.side)`.
- `CombatVFXBridge._resolve_rune_slot_idx` (:252-266) takes `traps.size() - 1` over live `_scene.state.active_traps` / `enemy_active_traps` (:260, :262, :263). Both `hide_rune_slot_for_placement` (:209) and `play_rune_placement_vfx` (:228) use it.
- TRAPS_CHANGED playback passes only the side (CombatPresenter.gd:705-707 → `CombatUI.on_state_traps_changed`, :114-116). `TrapEnvDisplay.update_traps_for` (:134) then reads live traps (:137).
- `reveal_slot_after_placement` (:239) and `flash_slot`'s tween callback (:260) re-render from live state too.
- ViewState applies TRAPS_CHANGED to `player_traps` / `enemy_traps` (ViewState.gd:104-109), but nothing reads them.

The presenter starts draining at the end of the frame (`pump`, CombatPresenter.gd:74-78), and the whole enemy turn is decided at once (EnemyTurnRunner.gd:8-12). By playback, the live arrays hold the end-of-batch traps, not the ones the event describes.

### Reachable today

1. **F5 Void Ritualist, every fight where its ritual fires** (deck f5_a: 2 Dominion, 2 Blood Rune; profile `void_ritualist`). Enemy turn N, with a Blood Rune already in enemy slot 0:
   - `play_phase` places the Dominion Rune (`_play_traps_pass`, VoidRitualistProfile.gd:23): RUNE_PLACED {slot 1}, TRAPS_CHANGED {[blood, dominion]}.
   - It plays a Human (:30). feral_reinforcement adds a feral imp to the hand (CombatHandlers.gd:1134-1152). Then it plays the imp (:38).
   - `on_enemy_summon_ritual_sacrifice` (CombatHandlers.gd:1210) removes both runes (:1264-1266): TRAPS_CHANGED {[]}.
   - Playback: at RUNE_PLACED the live list is already empty, so `_resolve_rune_slot_idx` returns -1: no hide and no placement VFX. At the first TRAPS_CHANGED the panel renders the live `[]`. The Blood Rune vanishes and the Dominion Rune is never shown. The Human and the imp then play, and the ritual VFX plays over empty slots.
2. **Two rune placements in one enemy turn.**
   - F5 at 4+ Mana (VoidRitualistProfile.gd:68: `# Mana to 4 (double rune or rune + dark_command)`; `_play_traps_pass` loops, CombatProfile.gd:616-637).
   - F2 rune variant (deck f2_c): CorruptedBroodRuneProfile.gd:27-29 places Dominion then Blood. Both runes cost 2 (CardDatabase.gd:2342, :2358).
   - The first RUNE_PLACED resolves index 1, so the first rune's VFX plays on slot 1. `reveal_slot_after_placement` re-renders live (both runes), so slot 0 pops in with no VFX. The second RUNE_PLACED plays on slot 1 again.
3. **Player ritual completion.** Abyssal Summoning Circle (pool `abyss_core`; ritual Blood + Dominion → Demon Ascendant, CardDatabase.gd:2400-2420) with `active_traps = [hidden_ambush, blood_rune]`.
   - Playing a Dominion Rune journals RUNE_PLACED {slot 2}. ON_RUNE_PLACED (CombatState.gd:2701-2707) → `on_env_ritual` (CombatHandlers.gd:693-696) → `_fire_ritual` removes slots 1 and 2 (CombatState.gd:885-889), all in the same command.
   - At playback the live traps are `[hidden_ambush]`, so the index is 0: the placement VFX hides the trap's slot and plays over it.
4. **Two quick player rune clicks.** `player_can_act()` doesn't wait for the presenter (CombatScene.gd:427-428). A second rune placed during the first one's cast animation (`await _cast_anim(trap, false)`, CombatPresenter.gd:438) moves the live index, so the first rune's VFX lands on the second rune's slot.

Enemy rune decks are f2_c, f4_b (one Shadow Rune, not affected) and f5_a, in `encounter_decks.json` (user data dir until task 047 lands).

### Korrath and Oblivion Seal journal no RUNE_PLACED

- `_korrath_place_random_rune` (CombatState.gd:1888-1907; Korrath B2 T0, on every Abyssal Knight attack, CombatHandlers.gd:250-256) appends the rune, applies its aura and fires ON_RUNE_PLACED. It journals nothing, not even TRAPS_CHANGED.
- `_relic_place_random_rune` (Oblivion Seal, RelicEffects.gd:120-138) journals TRAPS_CHANGED (:133) but no RUNE_PLACED.
- Voidshaped Acolyte's PLACE_RUNE_ON_OPPONENT (EffectResolver.gd:298-313; `seris_corruption` pool, reachable) appends a Shadow Rune to the opponent's traps and journals TRAPS_CHANGED, but no RUNE_PLACED, and fires no ON_RUNE_PLACED. Task 050's optional `place_trap` list doesn't name this site either.

These runes never play the placement VFX. Their append also shifts the live index that a still-pending player RUNE_PLACED reads (case 4).

### Why the panel rendering waits for task 050

Rendering the panels from the journal is only right if every trap mutation is journaled. Two aren't today:
- Grand Ritual Chaos emits only the `traps_changed` signal (CombatHandlers.gd:333), and nothing connects to it.
- Korrath's placement journals nothing (above).

Task 050 (fix step 3) routes every trap removal through `remove_trap`, which journals TRAPS_CHANGED. Without it, panels rendered from the journal would keep Grand Ritual Chaos' three consumed runes on screen. Step 1 below doesn't need 050.

## Decision (owner, 2026-10-01)

QN5: "Keep player input responsive (do NOT gate on presenter idle). The display fixes (E1–E3, E7) make the UI correct during playback instead." So case 4 is fixed by reading the journal, not by blocking input.

## Proposed fix

1. **Slot from the payload. No dependency; ship it first.**
   - `_play_trap_placed(ev)` passes `ev.payload["slot"]` to `hide_rune_slot_for_placement(trap, owner, slot)` and `play_rune_placement_vfx(trap, owner, slot)`.
   - Keep a bounds check against the panel count.
   - Delete `_resolve_rune_slot_idx` (CombatVFXBridge.gd:250-266) and fix the doc comment at :218-219.
2. **Snapshot on the placement event.** The RUNE_PLACED / TRAP_PLACED payload gains `traps = traps.duplicate()` (CombatState.gd:2693), the same snapshot TRAPS_CHANGED carries (:139).
3. **Panels render what they are given (after task 050).**
   - `TrapEnvDisplay.update_traps_for(owner, traps: Array)` renders the list it is passed and reads no `_scene.state`.
   - `CombatUI.on_state_traps_changed(side)` passes `presenter.view.player_traps` / `enemy_traps`. The presenter applies the event to the view before `_emit_ui` (CombatPresenter.gd:114-115).
   - `reveal_slot_after_placement` renders the RUNE_PLACED snapshot. The view doesn't have the new rune yet: its TRAPS_CHANGED is the next event.
   - `flash_slot`'s tween callback renders the view.
4. **Korrath, Oblivion Seal and Voidshaped Acolyte journal RUNE_PLACED** {trap, slot, traps}.
   - If task 050 shipped its optional `place_trap(side, t)`, journal the event there and route `cmd_play_trap`, Korrath, Oblivion Seal and PLACE_RUNE_ON_OPPONENT through it.
   - Otherwise add the event at the three sites, plus a TRAPS_CHANGED after Korrath's append if 050 left the append unjournaled (050 lists only its removal).
5. Optional: the VOID_BOLT payload carries the firing rune's slot (CombatState.gd:970), so `find_void_rune_slot_position` (CombatVFXBridge.gd:1352-1366) stops reading live `state.active_traps`. Low risk today: the rune's bolt is journaled at turn start, before the player can act.
6. If task 111 (roadmap E4, lint L17, provisional; take the next free number if the landing order differs) has landed, remove the trap reads in CombatVFXBridge and TrapEnvDisplay from its baseline in the same commit.

## Verification

- New LiveSmoke probe `_rune_vfx_follows_payload_slot` (debug/tests/LiveSmokeTests.gd, modelled on `_hp_labels_lag_the_engine`, :161):
  - Setup: launch F1, set player Mana to 4, `st.add_to_hand` two runes.
  - Action: `st.cmd_play_trap("player", a)` then `st.cmd_play_trap("player", b)`, with no await between them.
  - Record each RunePlacementVFX's `_panel` (RunePlacementVFX.gd:100) through the VfxLayer's `child_entered_tree`.
  - Expect `[trap_slot_panels[0], trap_slot_panels[1]]` (today both land on slot 1), and slot 1's art container hidden at the first RUNE_PLACED `event_played`.
- New LiveSmoke ritual probe:
  - Setup: abyssal_summoning_circle as the player environment with its rituals registered (`_register_env_rituals`, CombatState.gd:373), `active_traps = [hidden_ambush, blood_rune]`.
  - Action: play a Dominion Rune.
  - Expect: the VFX panel is `trap_slot_panels[2]`, slot 0's art is never hidden, and after drain the panels show only Hidden Ambush.
- New CommandTests probe: `cmd_play_trap` journals RUNE_PLACED whose `slot` is the rune's index and whose `traps` ids equal `traps_of(side)` right after the append.
- Extend `_relic_oblivion_seal` (TriggerHandlerTests.gd:538) and the Korrath rune-placement probes (TriggerHandlerTests.gd:3001, :3017): a RUNE_PLACED with the right slot is journaled.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the engine changes only add payload fields and journal events. `digest_text` excludes the journal (CombatState.gd:2242-2288), and nothing connects to `traps_changed`. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` through `--act 4`: enemy runes in Acts 1–2, Korrath and Oblivion Seal in any later act) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Depends on: task 050 — journals the Grand Ritual Chaos and Korrath trap removals through `remove_trap` (and maybe `place_trap`). Steps 3–4 need it; step 1 doesn't.
- Related: task 071 (roadmap E1b): the other half of E1, the enemy hero panel. Same pattern: the panel renders the view.
- Related: task 109 (roadmap E2): its phase E2c renders the environment panel from ENVIRONMENT_CHANGED the same way.
- Related: task 084 (roadmap A2): a per-copy TrapInstance changes the element type of the `traps` snapshots added here.
- Related: task 093 (roadmap PS-rituals): ON_RUNE_PLACED and rituals for either side. Enemy rituals will rely on the same RUNE_PLACED / TRAPS_CHANGED rendering.
- Related: task 111 (roadmap E4, lint L17): baseline entries for the files touched here.
- Related: task 113 (roadmap E7): once the panels render the view, Cyclone's trap targeting (CombatInputHandler.gd:411-412 maps the panel index to live `active_traps[idx]`) can name the wrong trap while the view lags; task 113 step 3 fixes that.
- Related: task 047: enemy decks f2_c / f5_a move into the repo.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item E1 (split: E1a), with unit E's straight-to-task bug 1 (rune VFX on the wrong slot) and its new finding on Korrath / Oblivion Seal.

## Summary

_(filled in at /task-done)_
