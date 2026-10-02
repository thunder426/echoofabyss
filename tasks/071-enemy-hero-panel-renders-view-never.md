---
id: "071"
title: Enemy hero panel renders the view, never live state (HP, Void Marks, essence, mana, hand)
status: backlog
area: ui
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item E1 (`design/refactors/ARCHITECTURE_ROADMAP.md` §E), plus the enemy-panel part of E2. Grooming split E1 in two: E1a (task 070, runes and trap panels) and E1b (this task). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

`EnemyHeroPanel.update(enemy_hp, enemy_hp_max, st, enemy_void_marks)` (EnemyHeroPanel.gd:421-450) takes HP and marks as arguments but reads essence, mana and hand size from the live `CombatState` (:434-442):

```gdscript
var ess_max: int = st.enemy_essence_max if st else 0
...
var hand_size: int = st.enemy_hand.size() if st else 0
```

Every caller also hands it some live values:

| Caller | When | What it passes |
|---|---|---|
| CombatUI.gd:49 | enemy HERO_HP_CHANGED | payload HP, live `_scene.state`, live `enemy_void_marks` |
| CombatUI.gd:58 | VOID_MARKS_CHANGED | all live: `update(_scene.state.enemy_hp, _scene.state.enemy_hp_max, _scene.state, _scene.state.enemy_void_marks)` |
| CombatPresenter.gd:241 | PHASE_TRANSITION | all live: `update(state.enemy_hp, state.enemy_hp_max, state, state.enemy_void_marks)` |
| CombatPresenter.gd:754 | TURN_STARTED | view HP and marks, live `state` |
| CombatScene.gd:223 | setup | live (equal to the view at that point) |

Enemy RESOURCES_CHANGED and enemy CARD_DRAWN / CARD_GENERATED / CARD_PLAYED never refresh the panel: `_emit_ui` handles them for the player only (CombatPresenter.gd:711-727). ViewState already tracks `enemy_essence` / `enemy_mana` and their maxima (ViewState.gd:86-90), but nothing reads them.

### Reachable today

1. **The enemy HP bar drains early when the player queues a command.** Lord Vael with Mark the Target (CardDatabase.gd:2160-2171: VOID_MARK 2, DRAW 1; pool `vael_piercing_void`) and Void Bolt (:2084-2091; 500 plus 25 per mark, CombatState.gd:1802):
   - Mark the Target is untargeted, so one click commits it (CombatInputHandler.gd:189-190 → `CombatScene._command_play_spell`, :548-557). The engine journals VOID_MARKS_CHANGED at once.
   - During its cast animation (`_play_spell` awaits `_cast_anim`, CombatPresenter.gd:470), the player clicks Void Bolt. `player_can_act()` (CombatScene.gd:427-428) doesn't wait for the presenter, so the engine deals the bolt now.
   - When VOID_MARKS_CHANGED plays, CombatUI.gd:58 pushes the live `enemy_hp`, which already includes the bolt. The bar drains (EnemyHeroPanel.gd:424-430) before the Void Bolt card is shown, and the bolt's own HERO_HP_CHANGED later shows no change.
   - Any queued command that hurts the enemy hero does the same, for example attacking the hero.
   - No single command reaches it with today's content: every VOID_MARK step comes after its damage step.
2. **The enemy's essence, mana and hand labels freeze, then jump, every enemy turn.**
   - The enemy's TURN_STARTED plays before its AI runs (CombatScene.gd:398, :404), so the labels show turn-start values.
   - The whole enemy turn, and the player's next turn start, are journaled at once. The labels never move with the enemy's spends or draws.
   - They jump to end-of-batch values at the first enemy HP or Void Mark event that plays (for example a Blood Rune heal; CombatUI.gd:49 passes live `state`), or at the player's TURN_STARTED (CombatPresenter.gd:754).

### Latent

- `PhaseTransition._do_transition` writes `st.enemy_hp = SOVEREIGN_P2_HP` before `st.enemy_hp_max = SOVEREIGN_P2_HP` (PhaseTransition.gd:50-51). The setter journals `hp_max = enemy_hero.hp_max` (CombatState.gd:1258), which is still the phase-1 max. It's harmless only because both are 3000 (EncounterTable.gd:140, PhaseTransition.gd:18). The live push at CombatPresenter.gd:241 hides it today, and this task removes that push.
- `ancient_frenzy` (F3 Imp Matriarch, EncounterTable.gd:34) appends the opening Pack Frenzy straight to `enemy_hand`, with no event (CombatState.gd:2360-2363). Once hand size travels in event payloads, the presenter replays setup's five enemy CARD_DRAWN events (it starts at cursor 0 after `view.sync_from`, CombatPresenter.gd:57-60) and would end at 5, not 6.
- Enemy max-resource growth outside the turn flow (Void Architect in f14_a, the F14 Void Champion aura) isn't journaled. Once the panel reads the view, it would show the old maximum. Task 069 fixes that first.

## Decision (owner, 2026-10-01)

QN5: "Keep player input responsive (do NOT gate on presenter idle). The display fixes (E1–E3, E7) make the UI correct during playback instead." So case 1 is fixed here by rendering the view, not by blocking input.

## Proposed fix

1. **The panel renders a ViewState.** `EnemyHeroPanel.update(v: ViewState)` reads HP, max HP, essence, mana, their maxima, hand size and Void Marks from `v`. The panel keeps no `CombatState`. `_update()` (:453-454) passes a fresh `ViewState.new()`.
2. **Callers pass the view.**
   - CombatUI.gd:49 and :58 pass `presenter.view`. The presenter applies the event to the view before `_emit_ui` (CombatPresenter.gd:114-115).
   - CombatPresenter.gd:241 and :754 pass `view`.
   - CombatScene.gd:223 passes `presenter.view`, synced by `presenter.setup` (:189 → CombatPresenter.gd:60).
3. **Refresh on the enemy's own events.** `_emit_ui` refreshes the enemy panel on enemy RESOURCES_CHANGED (:711-714) and on enemy CARD_DRAWN / CARD_GENERATED / CARD_PLAYED (:715-727).
4. **Hand size travels in the journal.**
   - Add `hand_size = hand_of(side).size()` to CARD_DRAWN (CombatState.gd:1569, :1580), CARD_GENERATED (:1592, CombatHandlers.gd:137) and CARD_PLAYED (CombatState.gd:2150, :2571, :2631, :2687, :2731).
   - ViewState gains `enemy_hand_size` and `player_hand_size`, set in `sync_from` and applied from those three kinds.
   - Route ancient_frenzy's Pack Frenzy through `add_to_hand("enemy", pf_card)` (CombatState.gd:2360-2363), so it journals CARD_GENERATED. Nothing connects to `card_generated`, so this only adds an event.
   - Edge path, reachability not traced: the board-full branch of `_cmd_play_minion` (CombatState.gd:2567-2569) removes the card from the hand with no CARD_PLAYED. Give it one, so the count can't drift.
5. **PhaseTransition** sets `enemy_hp_max` before `enemy_hp` (PhaseTransition.gd:50-51), so its HERO_HP_CHANGED carries the phase-2 max. The end state is the same.
6. **Docs.**
   - Fix the comments that describe the live push: CombatUI.gd:39-40, :51-53, CombatState.gd:1627-1629.
   - Update the ViewState header (ViewState.gd:1-9) and ARCHITECTURE.md's ViewState row (:109) for the hand-size fields.
7. If task 111 (roadmap E4, lint L17, provisional; take the next free number if the landing order differs) has landed, remove EnemyHeroPanel's and these CombatUI lines from its baseline in the same commit.

## Verification

- New LiveSmoke probe `_enemy_panel_follows_the_journal` (debug/tests/LiveSmokeTests.gd, next to `_hp_labels_lag_the_engine`, :161). Launch F1 and watch `scene.presenter.event_played`.
  - HP: synchronously `st._apply_void_mark(1)`, then `st.combat_manager.apply_hero_damage("enemy", CombatManager.make_damage_info(300, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE))`. At the VOID_MARKS_CHANGED event, `_enemy_hero_panel._enemy_status_hp_label.text` still shows the pre-damage HP (today it shows HP − 300). After drain it shows HP − 300.
  - Resources: synchronously deal 100 to the enemy hero, then `st.spend_mana("enemy", 1)` (F1, turn 1: the enemy has 1/1). At HERO_HP_CHANGED, `_enemy_status_mana_label` still reads 1/1. It changes only at the enemy RESOURCES_CHANGED.
  - Hand: `st.add_to_hand("enemy", card)`. `_enemy_status_hand_label` increments at CARD_GENERATED, not before.
- New CommandTests probe: CARD_DRAWN, CARD_GENERATED and CARD_PLAYED carry `hand_size == hand_of(side).size()` at emit time, for both sides. A build with `enemy_passives: ["ancient_frenzy"]` journals a CARD_GENERATED for the Pack Frenzy, and its `hand_size` is 6.
- `tools/run_checks.sh` green.
- Behaviour-neutral: payload fields and one extra journal event, an `add_to_hand` that builds the same instance in the same place, and an assignment swap with the same end state. `digest_text` excludes the journal (CombatState.gd:2242-2288). The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` through `--act 4`: F3 ancient_frenzy is Act 1, F15 is Act 4) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Depends on: task 069 — journals the enemy's max-resource growth outside the turn flow (Void Architect, F14 Void Champion aura). Without it, the view-driven panel shows the old maximum until the enemy's next resource event.
- Related: task 070 (roadmap E1a): the other half of E1, runes and trap panels.
- Related: task 109 (roadmap E2): player resource widgets, and the Korrath badges on this panel (`update_korrath_debuffs`, phase E2b). Its ViewState cleanup (E2d) keeps the fields this task starts reading.
- Related: task 127 (roadmap H6): splits EnemyHeroPanel by concern, after this task.
- Related: task 068: its step 5 adds a `passives` payload to PHASE_TRANSITION and rebuilds the enemy passive icon from it (the CombatPresenter.gd:241 branch this task also edits); coordinate the EnemyHeroPanel edits, whichever lands second rebases.
- Related: task 113 (roadmap E7): the other consequence of QN5 (target highlights while the view lags).
- Related: task 115 (roadmap F2): the Void Bolt double damage popup in the same Mark the Target → Void Bolt line is a separate presenter bug, owned there.
- Related: task 111 (roadmap E4, lint L17): baseline entries for the files touched here.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item E1 (split: E1b), with unit E's straight-to-task bug 2 (enemy HP drains early on a Void Mark event) and the enemy-panel part of E2.
  - Re-check: the essence / mana / hand labels mostly lag (frozen at turn start), then jump; they don't run ahead throughout.
  - Added: route ancient_frenzy's opening card through `add_to_hand`, which payload-driven hand size needs. Added a dependency on task 069 (enemy growth journaling).

## Summary

_(filled in at /task-done)_
