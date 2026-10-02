---
id: "109"
title: Player resource widgets, Korrath badges, counter warning and environment panel render journal payloads; ViewState cleanup
status: backlog
area: ui
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item E2 with E5 (ViewState cleanup) folded in as the last phase (`design/refactors/ARCHITECTURE_ROADMAP.md` §E). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Grooming split the roadmap's E2: the enemy hero panel went to task 071 (roadmap E1b) and the trap panels to task 070 (roadmap E1a). This task owns the rest.

The presenter plays an event, applies it to the lagging `ViewState`, then refreshes the UI (CombatPresenter.gd:111-115: `await _play(ev)`, `view.apply(ev)`, `_emit_ui(ev)`). The widgets below ignore the payload and the view and re-read the live `CombatState` instead. The engine is usually ahead of the screen:
- the whole enemy turn is decided at once (EnemyTurnRunner.gd:8-12), and `cmd_end_turn` begins the player's next turn in the same call (CombatState.gd:2894-2896);
- player input is not gated on the presenter (`player_can_act`, CombatScene.gd:427-428), so the player can queue commands while earlier ones still animate.

### Live reads, by widget

| Widget | Live read | When it refreshes |
|---|---|---|
| Flesh counter | PipBar.gd:517-518 `var flesh: int = _scene.state.player_flesh` / `player_flesh_max` | FLESH_CHANGED {value, max} (CombatState.gd:1669). `CombatUI.on_state_flesh_changed(_value, _max_value)` (:94-98) drops the payload. |
| Forge counter | PipBar.gd:707-708 `_scene.state.forge_counter` / `forge_counter_threshold` | FORGE_CHANGED {value, threshold} (:1692), dropped at CombatUI.gd:104-108. |
| Seris skill buttons | SerisResourceBar.gd:222, :226-227 `_scene.state.player_flesh`, `_scene.state._seris_corrupt_used_this_turn` | Same two events (CombatUI.gd:99-100, :109-110). The Corrupt Flesh flag has no event at all. |
| Pip blink | PipBar.gd:293-294 (`stop_blink`) and :343-350 (`_refresh_blink_pips`) read live essence / mana | Hand-card hover and unhover (CombatInputHandler.gd:119-120, :128-129). Hover starts the blink when `_scene.state.is_player_turn` (:119), the engine's turn, not the shown one. |
| End-turn buttons | CombatUI.gd:174 `(_scene.state.player_essence_max + _scene.state.player_mana_max) >= CombatState.COMBINED_RESOURCE_CAP` | Every player RESOURCES_CHANGED (CombatPresenter.gd:714) and `show_turn_started` (CombatScene.gd:415). |
| Hand playability, condition glows, cost text | CombatUI.gd:189-190, :199-200, :206-207 (live essence, mana, `_relic_cost_reduction`, `player_spell_cost_penalty`); LargePreview.gd:42-43 (`_relic_cost_reduction`); board discount `CombatScene._spell_mana_discount()` sums over live `state.player_board` (:1291-1295) | RESOURCES_CHANGED, CARD_PLAYED, MINION_DIED / SACRIFICED / CONSUMED, HAND_COSTS_CHANGED, turn start. |
| Deck count | CombatScene.gd:417, :419 `state.player_deck.size()` | `show_turn_started`. |
| Korrath hero badges | CombatUI.gd:64-77 `hero.armour`, `BuffSystem.sum_type(hero, Enums.BuffType.ARMOUR_BREAK)`, `count_type(hero, CORRUPTION)` | ARMOUR_CHANGED and HERO_BUFF_CHANGED. HERO_BUFF_CHANGED carries an empty payload: `emit_event(CombatEvent.Kind.HERO_BUFF_CHANGED, side, {})` (CombatState.gd:313, :2378). |
| Counter warning | CounterWarning.gd:44 `var should_show: bool = _scene.state._player_spell_counter > 0` | SPELL_COUNTER_CHANGED, which has no payload (EffectResolver.gd:257), and SPELL_COUNTERED, whose refresh runs inside `_play` before the view applies the event (CombatPresenter.gd:230-233). The spend (CombatState.gd:2635-2644) journals no remaining count. |
| Environment panel | TrapEnvDisplay.gd:109 `var active = _scene.state.active_environment` | ENVIRONMENT_CHANGED; `CombatUI.on_state_environment_changed(_env)` (:120-122) drops the env and the presenter passes no side (CombatPresenter.gd:708-710). There is one slot (`UI/EnvironmentSlot`, TrapEnvDisplay.gd:59), and it only ever shows the player's environment. |

Two places pass the right value and then overwrite it with a live one in the same call:
- `on_resources_changed` passes the payload's essence / mana to `refresh_playability` (CombatUI.gd:156), then calls `refresh_hand_spell_costs` (:157), which runs `refresh_playability` again with live values (:206-207).
- MINION_DIED playback passes `view.player_essence` / `view.player_mana` to `refresh_condition_glows` (CombatPresenter.gd:746), then calls `refresh_hand_spell_costs` (:748), which repeats it with live values.

### Reachable today

1. **Seris: the Flesh counter jumps ahead.** Fleshbind gains 1 Flesh per friendly Demon death (CombatSetup.gd:257-260 → CombatHandlers.gd:812 → `_gain_flesh`, CombatState.gd:406-414), and each gain journals FLESH_CHANGED. When two of Seris's Demons die in one enemy turn, the counter shows the final value when the first FLESH_CHANGED plays.
2. **Seris: the Corrupt Flesh button lights up during the enemy's turn.** The once-per-turn flag is reset by an ON_PLAYER_TURN_START handler (CombatSetup.gd:231 → `_seris_corrupt_reset_turn`, CombatState.gd:1105-1106), which the engine has already run when the enemy's events play. Any FLESH_CHANGED / FORGE_CHANGED during that playback calls `refresh()`, which reads the reset flag and shows the button castable. Clicking it is refused by `player_can_act()` (CombatScene.gd:1307), so only the glow is wrong.
3. **Any hero: hovering a hand card during the enemy's turn shows next turn's pips.** `state.is_player_turn` is already true (step above), so hover starts the blink. The blink, and `stop_blink` on unhover, repaint the pip bar from live essence and mana: next turn's refilled values, while the enemy's turn is still playing.
4. **Queued player commands** (owner decision QN5 keeps input responsive). Examples:
   - Play an environment, then a second one during the first's cast animation (`_cast_anim`, CombatPresenter.gd:225-227). When the first ENVIRONMENT_CHANGED plays, the panel already shows the second.
   - Spend Flesh twice in quick succession: the first FLESH_CHANGED shows the final count.

### Latent or invisible today

- **Enemy environment.** `update_environment` shows only the player's environment and ignores the event's side. No enemy content owns an environment (task 050).
- **Counter warning.** The counter is armed on the enemy's turn (Phase Disruptor) and spent by the player's own cast, so no traced case shows a wrong value. It still re-reads live state, so it can't be checked against the journal.
- **Korrath badges.** `_corrupt_hero` with Corrupting Presence journals two HERO_BUFF_CHANGED in one call (CombatState.gd:1147-1149); the first already shows both debuffs. Path of Shattering adds 50 Armour Break per Demon attack on the enemy hero (CombatHandlers.gd:411-413), so two queued attacks show 100 at the first.
- **Deck count.** TURN_STARTED is journaled last in `begin_turn` (CombatState.gd:2454) and the player can't act before it plays, so the live read equals the snapshot. Listed so the lint (task 111) can reach zero.
- **Max-resource growth outside the turn flow** (Font of the Depths, Void Hourglass) isn't journaled yet. The end-turn buttons are right after Font of the Depths only because they read live maxima. Task 069 adds the events; this task's end-turn step must land after it.

### ViewState (roadmap E5)

`ViewState` has 25 fields (ViewState.gd:13-37). Six are read today: `enemy_hp`, `enemy_hp_max` and `enemy_void_marks` (CombatPresenter.gd:219, :754), `player_essence` and `player_mana` (:746), and `is_player_turn` (CombatScene.gd:428). Tasks 070 and 071 start reading the trap lists and the enemy's resources, and phases E2a-E2c below add the rest. What would still be unread after that:
- `player_hp` / `player_hp_max`: the player panel takes the HERO_HP_CHANGED payload directly (CombatUI.gd:46), and its setup sync reads live state (CombatScene.gd:222);
- `turn_number`: `show_turn_started` takes the payload's turn (CombatPresenter.gd:750).

## Decision (owner, 2026-10-01)

- QN5: "Keep player input responsive (do NOT gate on presenter idle). The display fixes (E1–E3, E7) make the UI correct during playback instead." So cases 3 and 4 are fixed by rendering the view, not by blocking input.
- Q2: Flesh, Forge, rituals and environments must work for either side. View fields added here are keyed by side, and each side's environment needs a place on screen.

## Proposed fix

Four phases, each its own commit with its own gate run. E2a, E2b and E2d don't depend on task 050; only E2c does.

### Phase E2a: player resources (after task 069)

1. **Flesh and Forge from the payload.** `CombatUI.on_state_flesh_changed(value, max)` / `on_state_forge_changed(value, threshold)` pass their arguments on: `PipBar.update_flesh(value, max)` and `update_forge(value, threshold)` render what they are given. The setup call (PipBar.gd:203-204) passes `_scene.presenter.view` values; the view is synced at CombatScene.gd:189, before PipBar is built (:225-226).
2. **Seris skill buttons from the view.**
   - Journal the Corrupt Flesh flag. `_seris_corrupt_apply` (CombatState.gd:1098) and `_seris_corrupt_reset_turn` (:1106) emit a new `SKILL_STATE_CHANGED` event {skill = "seris_corrupt", used = bool}, side = owner. Classify the new kind in the presenter (task 116).
   - In `_seris_corrupt_apply`, set the flag and journal it before the Flesh spend (move :1098 above :1094; every check has already passed). Otherwise the spend's FLESH_CHANGED plays while the view still says "unused".
   - ViewState keeps `skill_used[side][skill]` and the Flesh value per side.
   - `SerisResourceBar.refresh()` reads the view. The click handlers (`_on_forge_btn_pressed`, :233-237) keep issuing engine commands; the engine still validates.
3. **Pip blink.** PipBar stores the last values passed to `update()` (`_shown_essence`, `_shown_mana` and their maxima). `stop_blink` and `_refresh_blink_pips` use those, not `_scene.state`. Hover starts the blink only when `_scene.presenter.view.is_player_turn` (CombatInputHandler.gd:119). The affordability checks at :169, :180 and :199 stay on the engine: they decide what the click may do.
4. **End-turn buttons.** `refresh_end_turn_mode` reads `presenter.view.player_essence_max` / `player_mana_max`. This needs task 069; without it, the view keeps the old maximum after Font of the Depths and the buttons would regress. Journaling the resource changes that emit nothing today is task 069's (Font of the Depths, Void Hourglass, Void Architect, the VCH aura) and task 092's (the enemy GRANT_ESSENCE branch), not this task's. Fix the stale CombatUI comments at :143-147 and :168-170 ("call refresh_end_turn_mode only after grow_*"): the presenter already calls it on every player RESOURCES_CHANGED (CombatPresenter.gd:714).
5. **Hand playability and costs.**
   - `on_card_anim_finished` and `refresh_hand_spell_costs` read `view.player_essence` / `view.player_mana`. That also removes the two overwrites listed above.
   - Cost modifiers in the journal. HAND_COSTS_CHANGED carries `{relic_cost_reduction, spell_cost_penalty}` for its side. Journal it where they change: Dark Mirror (RelicEffects.gd:64), its use in `pay_card_cost` (CombatState.gd:2169-2171), the turn-start set and reset (:2425, :2432) and the turn-end clear (:2464). ViewState keeps both per side. `refresh_hand_spell_costs` and LargePreview.gd:42-43 read the view.
   - Board discount: `_spell_mana_discount()` sums `mana_cost_discount` over the shown slots (`player_slots[i].minion`) instead of `state.player_board`.
   - If task 085 (roadmap A6) has landed, the payload reads its `side(s)` fields; 085's step 9 (presentation calls the engine cost formula) is then skipped for these display reads, as 085 already notes.
   - Out of scope: per-card cost deltas on `CardInstance` (`mana_delta` / `essence_delta`), which HandDisplay reads from the instance.
6. **Deck count.** The TURN_STARTED payload gains `deck_size = deck_of(side).size()` (CombatState.gd:2454); `show_turn_started` takes it as an argument. No visible change today.

### Phase E2b: hero badges and the counter warning

1. **Hero debuffs in the payload.** Both HERO_BUFF_CHANGED emitters (CombatState.gd:313, :2378) send `{armour_break = BuffSystem.sum_type(hero, ARMOUR_BREAK), corruption = BuffSystem.count_type(hero, CORRUPTION)}`. ViewState keeps both per side; armour is already there (ARMOUR_CHANGED, ViewState.gd:99-103). `_refresh_hero_korrath_badges(side)` renders the view. Drop CombatUI's `state` field (:26) once nothing reads it.
2. **Spell counter in the payload.**
   - SPELL_COUNTER_CHANGED carries `{value}`: the counter of the side it names, after the increment (EffectResolver.gd:252-257).
   - SPELL_COUNTERED with reason "countered" carries `{counter}`: what is left after the spend (CombatState.gd:2636-2638, :2641-2643).
   - ViewState keeps `spell_counter` per side. `CounterWarning.update(value: int)` renders the player's view value.
   - Move the refresh for SPELL_COUNTERED out of `_play` (CombatPresenter.gd:232) into `_emit_ui`, after `view.apply`.
   - If task 085 has moved the counter onto SideState, the payload reads it there.

### Phase E2c: environment panel (after task 050)

1. `TrapEnvDisplay.update_environment(side: String, env: EnvironmentCardData)` renders the env it is given and reads no `_scene.state`.
2. `CombatUI.on_state_environment_changed(side)` passes `presenter.view.player_environment` / `enemy_environment`; CombatPresenter.gd:710 passes `ev.side`.
3. Initial render: CombatScene.gd:202 calls `state._update_environment_display()`, which only emits the `environment_changed` signal, and nothing listens to it (CombatState.gd:150-151). Render both sides from `presenter.view` there instead.
4. **The enemy's environment.** At minimum, an enemy ENVIRONMENT_CHANGED must never repaint the player's slot. Q2 means the enemy's environment needs its own slot: add one here, hidden while empty, so today's screen doesn't change. If the owner wants the layout to wait, record it on task 093 (per-side rituals) instead.
5. Why after task 050: destroying an environment (Cyclone, Hurricane) and the F15 phase change don't journal ENVIRONMENT_CHANGED until 050 lands. Rendering from the journal before then would keep a destroyed environment on screen.

### Phase E2d: ViewState cleanup (roadmap E5)

1. **The player panel renders the view**, like task 071's enemy panel: `on_state_hp_changed` passes `presenter.view` for both sides, and the setup sync (CombatScene.gd:222) reads the view. `player_hp` / `player_hp_max` gain readers.
2. `show_turn_started` reads `view.turn_number` (the presenter applies TURN_STARTED before `_emit_ui`), or delete the field.
3. Delete any field still unread. Re-run the per-field grep from this task's evidence (`grep -rn --include='*.gd' -E 'view\.<field>\b' .`, excluding ViewState.gd).
4. Docs:
   - the ViewState header (ViewState.gd:1-9);
   - `design/master_doc/ARCHITECTURE.md`: the ViewState and CombatPresenter rows, and the list of view-driven panels in "Combat architecture" item 3;
   - CombatUI's header (:17-18, "State is accessed directly via `state` or `_scene.state`").

In every phase, if task 111 (roadmap E4, lint L17, provisional; take the next free number if the landing order differs) has landed, lower its baseline for the touched files in the same commit.

## Verification

New probes in debug/tests/LiveSmokeTests.gd, next to `_hp_labels_lag_the_engine` (:161). Each watches `scene.presenter.event_played` and runs its engine calls synchronously, with no await, so the whole batch is journaled before the first event plays.

- **E2a, Flesh** (`_flesh_follows_the_journal`).
  - Setup: launch with `GameManager.current_hero = "seris"` (the Flesh widget is built only for Fleshbind, PipBar.gd:194).
  - Action: `st._gain_flesh(1)` twice.
  - Expect: at the first FLESH_CHANGED, `scene._pip_bar._flesh_count_lbl.text` starts with "1/" (today "2/"). After drain it starts with "2/".
- **E2a, pip blink.** Give the player at least 2 Mana and drain, then synchronously `st.spend_mana("player", 1)` twice. At the first player RESOURCES_CHANGED, call `scene._pip_bar.stop_blink()`: the PipBar's shown mana equals that event's `mana` payload (today: the live value, one lower).
- **E2a, Corrupt Flesh.**
  - Setup: Seris with the `corrupt_flesh` talent, one friendly Demon, 2 Flesh.
  - Action, synchronously: `st.cmd_hero_skill("player", "seris_corrupt", demon)`, then `st._seris_corrupt_reset_turn()` (what the next turn start does), then `st._gain_flesh(1)`.
  - Expect: at the skill's FLESH_CHANGED (Flesh 1) the Corrupt Flesh button is not castable. Today it is castable, because it reads the live flag (already reset) and the live Flesh (2). At the gain's FLESH_CHANGED it is castable.
- **E2b, badges.** Two synchronous `st.apply_hero_buff("enemy", Enums.BuffType.ARMOUR_BREAK, 50)`. At the first HERO_BUFF_CHANGED, `scene._enemy_hero_panel._enemy_armour_net_label.text == "Armour Break 50"` (today "Armour Break 100").
- **E2b, counter warning.**
  - Action: arm the player's counter from the enemy side (`EffectResolver.run([{"type": "COUNTER_SPELL"}], EffectContext.make(st, "enemy"))`), then have the player cast an untargeted spell, all synchronously.
  - Expect: at SPELL_COUNTER_CHANGED, `scene.counter_warning.label.visible` is true (today false: the live counter is already spent). After drain it is hidden again.
- **E2c, environment.** Give the player Mana and two different environments, and play both synchronously with `cmd_play_environment`. At the first ENVIRONMENT_CHANGED, the slot's art is the first environment's (today the second's).
- **Engine payloads.** New probe in debug/tests/CommandTests.gd:
  - HERO_BUFF_CHANGED carries `armour_break` and `corruption` equal to the hero's buffs at emit time.
  - SPELL_COUNTER_CHANGED and SPELL_COUNTERED carry the counter value.
  - HAND_COSTS_CHANGED carries the cost modifiers after Dark Mirror and after the card that uses it.
  - SKILL_STATE_CHANGED is journaled on Corrupt Flesh use and at the player's next turn start.
- **E2d:** the per-field grep shows a reader for every remaining ViewState field.
- `tools/run_checks.sh` green after each phase.
- Behaviour-neutral: the engine changes only add payload fields and journal events (HAND_COSTS_CHANGED at more sites, SKILL_STATE_CHANGED). `digest_text` excludes the journal (CombatState.gd:2242-2288), and nothing outside the presenter and the tests reads it. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` through `--act 4`; Seris, Korrath and the relics appear in every act) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Depends on: task 048 — both rewrite CombatPresenter `_play` / `_emit_ui` (048 adds the deadline, generation guard and resync). Ordering only.
- Depends on: task 050 — phase E2c: environment destroy and the F15 clear are journaled only after 050.
- Depends on: task 069 — phase E2a step 4: the end-turn buttons can read the view only once max-resource growth outside the turn flow is journaled. Added during this re-check; the grooming plan didn't list it.
- Related: task 070 (roadmap E1a) and task 071 (roadmap E1b) — the trap-panel and enemy-panel halves of the roadmap's E2.
- Related: task 085 (roadmap A6) — moves the spell counter and cost penalties onto SideState; whichever lands second sources the payloads from the other's fields.
- Related: task 097 (roadmap B3) — Flesh, Forge and Corrupt Flesh per side; it keeps the payloads and the SKILL_STATE_CHANGED event added here.
- Related: task 098 (roadmap B4) — the Korrath module; the badges keep reading the view.
- Related: task 093 (roadmap PS-rituals) — enemy environments and rituals; owns the enemy environment slot if E2c defers it.
- Related: task 127 (roadmap H6) — shares the hero HP bar and Korrath badges between the two panels, after this task.
- Related: task 103 (roadmap C5) — same widgets' setup paths (GameManager reads); different lines.
- Related: task 116 (roadmap F3) — the presenter classifies every event kind, including SKILL_STATE_CHANGED.
- Related: task 132 (roadmap I4) — deletes unheard signals such as `environment_changed`.
- Related: task 111 (roadmap E4, lint L17) — each phase lowers its baseline.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item E2, with E5 folded in as phase E2d. The enemy-panel and trap parts of E2 went to tasks 071 and 070.
  - Re-check added: the hover blink during enemy playback (case 3), the Corrupt Flesh glow (case 2), the two live overwrites, and the HAND_COSTS_CHANGED cost modifiers.
  - Added a dependency on task 069 (step E2a.4).
  - The counter warning and Korrath badges have no traced visible bug; they are kept for the journal rule and the lint.

## Summary

_(filled in at /task-done)_
