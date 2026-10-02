---
id: "135"
title: Idle-consistency probe: every board slot shows the engine's stats when the presenter is idle
status: backlog
area: tooling
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item I8 (`design/refactors/ARCHITECTURE_ROADMAP.md` §I). I8 is new: unit I proposed it during task 056 pass 1, and the roadmap text doesn't have it yet. Re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Since task 046, the screen is a lagging copy of the engine that only journal events move:
- **Board slots** render `shown_atk` / `shown_hp` / `shown_shield` (BoardSlot.gd:119-121), never the live minion. The presenter moves them only on DAMAGE_DEALT `hp_after` / `shield_after`, MINION_HEALED `hp_after` and MINION_STATS_CHANGED `atk` / `hp` / `shield` (CombatPresenter.gd:730-743, `_apply_minion_stats` :775-783), plus the summon / slot snapshot (`_apply_slot` :789-799).
- **`ViewState`** (ViewState.gd:13-37) is the lagging copy the hero and resource panels render. Task 071 (roadmap E1b) and task 109 (roadmap E2) move the panels' remaining live reads onto it. It is filled once by `sync_from` (CombatPresenter.gd:60) and then only by `ViewState.apply(ev)` (:70-119).

So a state change with no event leaves a wrong number on screen until some later event happens to carry it. Nothing checks for that:
- Parity compares engine digests (`digest_text`), never the view.
- ParityTests compares view slot *occupancy* only, and only in a failure message (`_slots_text`, ParityTests.gd:368-379).
- LiveSmoke's `_hp_labels_lag_the_engine` (LiveSmokeTests.gd:161-189) checks one hand-built strike.

### Known cases this would have caught

- **Deathless save** (task 061): DAMAGE_DEALT journals `hp_after` ≤ 0, then the save sets HP to 50 with no event. The slot shows "-100" on a living minion.
- **Shield Regen at turn start** (task 110, Phase E3b step 1): `MinionInstance.on_turn_start` regenerates `current_shield` (MinionInstance.gd:252-255) inside `_ready_board` (CombatState.gd:2507-2510) and journals nothing.
- **Max-mana / max-essence growth outside the turn flow** (task 069): `grow_mana_max` / `grow_essence_max` emit no RESOURCES_CHANGED, so `ViewState.player_mana_max` stays behind.
- **Trap / environment changes that journal nothing** (task 050, items 2 and 5): `ViewState.player_traps` / `player_environment` stay behind.

Today most stale slot labels are hidden by an accident: every summon, death or sacrifice re-journals every minion on both boards (the presence-aura recompute, CombatHandlers.gd:1076-1081). Task 136 (roadmap I7d) removes that. Task 129 (roadmap I1), task 131 (roadmap I3) and task 110 (roadmap E3) also change what gets journaled. This probe is their safety net.

## Proposed fix

1. **Add a test-side helper** `debug/tests/ViewProbe.gd` with `static func mismatches(scene: Node) -> PackedStringArray`. Keep it out of the presenter, so it adds nothing to the engine-read count that lint L17 (task 111, roadmap E4; provisional, take the next free number if the landing order differs) ratchets in UI files.
   - For each side and slot index 0–4, compare `scene.slot_node(side, i)` with `scene.state.slot_of(side, i)`:
     - `node.minion == slot.minion` (occupancy and identity);
     - if occupied: `node.shown_atk == m.effective_atk()`, `node.shown_hp == m.current_health`, `node.shown_shield == m.current_shield`.
   - Compare every `scene.presenter.view` field with its engine source, in the field list `ViewState.sync_from` uses (ViewState.gd:41-66): HP and max, essence / mana and max, Void Marks, Flesh, Forge, both armours, both trap lists (by id, in order), both environments, `turn_number`, `is_player_turn`.
   - Each mismatch is one line, e.g. `"player[2] void_imp shown_hp 300 engine 50"`.
2. **Known open bugs go in an allowlist** in ViewProbe.gd. Each entry names its task (for example `{field = "player_mana_max", task = "069"}`) and is deleted when that task lands. Only the cases listed above go in. Anything new found while landing this becomes its own bug task first (plan ruling), then an entry.
3. **Call it in ParityTests** at the points where the presenter is already idle:
   - before each player command, after the existing wait (ParityTests.gd:140-142: `st.is_player_turn and scene.presenter.is_idle() and not scene._end_turn_in_progress`);
   - at fight end, after the final wait (:163-164).

   A non-empty result fails the case with the mismatch lines and the kinds of the last 20 journal events.
4. **Call it in LiveSmokeTests** at the end of `_drain` (LiveSmokeTests.gd:246-249) and once more at the end of `_ai_vs_ai_fight`. Every scenario then checks the view when its presenter goes idle, including task 061's new Deathless probe.
5. Compare the `shown_*` fields, not the label text. A label's value tween can still be running when the presenter goes idle (`animate_hp_change` sets `shown_hp` at once and tweens the text, BoardSlot.gd:405-419).
6. Document the probe in `design/TESTING.md` (Parity and LiveSmoke sections): what it compares, the allowlist, and that each new mismatch is filed as a bug.

## Verification

- **Positive control** in `debug/tests/LiveSmokeTests.gd`, new `_view_probe_catches_a_silent_change`:
  - Setup: `_launch(1, "swarm")`, summon a token with `st._summon_token("void_imp", "player")`, `await _drain(scene)`. Assert `ViewProbe.mismatches(scene)` is empty.
  - Action: `imp.current_health -= 50` with no event.
  - Assert: the result has exactly one line, naming that slot's `shown_hp`.
- **Regression check while developing:** with task 061's fix reverted locally, its LiveSmoke Deathless scenario (Bulwark Automaton struck by a Bastion Colossus) fails through this probe. Note the result in the work log; don't commit the revert.
- `tools/run_checks.sh` green with the probe on in Parity (8 cases × 3 seeds) and LiveSmoke, with only allowlisted entries.
- Behaviour-neutral: a test-only change. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, Acts 1–2) diffs empty (design/TESTING.md 'Refactor / extraction work').

## Related

- Depends on: task 061 — the Deathless save is the known slot mismatch reachable in any fight with Bulwark Automaton, Imp Idol or Seris `deathless_flesh`. Land 061 first so the probe starts with no slot allowlist entry for it.
- Related: task 136 (roadmap I7d) — depends on this task. It removes the presence-aura re-journal that masks stale labels, and should land only once this probe runs with no slot allowlist entries.
- Related: task 110 (roadmap E3) — Phase E3b step 1 fixes the Shield Regen case; its Related list plans to extend this probe to `shown_status`.
- Related: task 069 and task 050 — the open ViewState mismatches (max resources; trap and environment changes). Their allowlist entries go when they land.
- Related: task 113 (roadmap E7) — input during playback; this probe checks only idle points, so it agrees with QN5 (input is not gated on the presenter).
- Related: task 133 (roadmap I5) — the same idea on the engine side: more state in the digest Parity compares.
- Related: task 129 (roadmap I1) and task 131 (roadmap I3) — change what is journaled around attacks and deaths. This probe should be green before they land.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item I8 (new; unit I).
  - Re-check at `404b51c`: slots and ViewState move only on events.
  - The only existing view check is ParityTests' occupancy string, printed only on failure.
  - Listed the known open mismatches (tasks 061, 110, 069, 050) so they are handled by dependency or allowlist, not discovered as noise.

## Summary

_(filled in at /task-done)_
