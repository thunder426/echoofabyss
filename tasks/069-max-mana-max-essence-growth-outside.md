---
id: "069"
title: Max-mana / max-essence growth outside the turn flow is not journaled (pip bar, resource labels and end-turn buttons keep the old maximum)
status: backlog
area: ui
priority: normal
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §E). Re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The engine journals RESOURCES_CHANGED through `emit_resources(side)` (CombatState.gd:1456-1458). Spend, gain and convert call it. The two growth functions don't:
- `grow_essence_max` (:1494-1501), doc comment at :1493: `## +amount Essence max, one at a time, stopping at the combined cap. No emit.`
- `grow_mana_max` (:1504-1511), same comment at :1503.

That is fine inside the turn flow: `begin_turn` grows (:2420), refills (:2421) and emits once (:2449). Three callers grow outside the turn flow and journal nothing:

| Site | Content | Side |
|---|---|---|
| EffectResolver.gd:139-144, GROW_MANA_MAX: `ctx.state.grow_mana_max(ctx.owner, maxi(1, step.amount))` | Font of the Depths (CardDatabase.gd:2175-2186, 1 Mana, pools `vael_piercing_void` + `seris_corruption`, :3548); Void Architect's on-play (:3405, enemy deck f14_a ×2) | either |
| RelicEffects.gd:72-77, `relic_extra_turn`: `state.grow_essence_max("player", 1)` / `state.grow_mana_max("player", 1)` | Void Hourglass (RelicDatabase.gd:101-102, Act 3 relic) | player |
| CombatHandlers.gd:1802-1815, `on_enemy_turn_end_champion_vch_aura`: `state.grow_mana_max("enemy", 1)` / `state.grow_essence_max("enemy", 1)` | F14 Void Champion aura | enemy |

Nothing connects to the `resources_changed` signal (`grep -rn resources_changed`), so the journal event is the only way the screen learns about a resource change.

### Reachable today (player)

The pip bar and the `essence_label` / `mana_label` ("%d/%d") update only from player RESOURCES_CHANGED payloads: CombatPresenter.gd:711-714 → `CombatUI.on_resources_changed` (CombatUI.gd:148-166) → `PipBar.update` (PipBar.gd:206), which shows one pip per point of maximum.

1. **Font of the Depths** at 3/3 Mana.
   - Paying the cost journals RESOURCES_CHANGED {mana 2, mana_max 3} (`spend_mana`, :1476-1481).
   - GROW_MANA_MAX then raises the engine to 2/4 with no event.
   - The label reads "2/3" and the bar shows 3 Mana pips until the next player resource event: the next card paid for, or next turn's refill.
   - Hovering a card and moving off repaints the bar from live state (`PipBar.stop_blink`, :293-294), but not the labels.
   - The end-turn buttons happen to be right here. The presenter calls `refresh_end_turn_mode()` on every player RESOURCES_CHANGED (CombatPresenter.gd:714). That reads live maxima (CombatUI.gd:174), and the engine has already grown them before playback starts. Moving that read onto the view is task 109's job (below).
2. **Void Hourglass.**
   - `_cmd_activate_relic` (CombatState.gd:2827-2856) journals RELIC_ACTIVATED (:2840). Its playback only refreshes the relic bar (CombatPresenter.gd:755-757).
   - The click handler stops the pip blink *before* the command (CombatScene.gd:1151, :1157), then refreshes hand costs only (:1160).
   - So the bar, the labels **and** the end-turn mode keep the old maxima.
   - If the relic brings the combined maximum to 11 (`COMBINED_RESOURCE_CAP`, :1358), the two growth buttons stay on screen. The player's pick then does nothing at the next turn start, because `grow_*_max` stops at the cap (:1496, :1506).

### Latent (enemy)

Void Architect (F14, f14_a) and the F14 Void Champion aura grow the enemy's maxima with no event. Nothing shows it today, because the enemy panel reads `st.enemy_mana_max` / `st.enemy_essence_max` live (EnemyHeroPanel.gd:434-439). Task 071 (roadmap E1b) moves that panel onto the view. After that, the panel would keep the old maximum until the enemy's next resource event: after the Void Champion aura, that's the enemy's next turn start, so the whole player turn shows the old maximum.

### Out of scope

The enemy GRANT_ESSENCE branch (EffectResolver.gd:133-136) writes `st.enemy_essence` directly with no event. No content uses GRANT_ESSENCE. Task 092 (roadmap PS-void-marks) owns it: one rule for both sides through `gain_essence`.

## Proposed fix

1. Call `state.emit_resources(side)` once after the growth at each of the three sites:
   - EffectResolver.gd:141, after `grow_mana_max(ctx.owner, ...)`: `ctx.state.emit_resources(ctx.owner)`.
   - RelicEffects.gd:75, after both grows.
   - CombatHandlers.gd:1814, after both grows.
2. Don't emit inside `grow_*_max`. The turn flow grows before it refills (:2420-2421), so an emit there would journal the old current value with the new maximum, one event before the real one. `on_resources_changed` would also pulse the pip columns for it (CombatUI.gd:161-164).
3. Reword the doc comments at :1493 and :1503: "No emit: the turn flow emits after the refill; any other caller calls `emit_resources(side)`."

## Verification

- Extend the existing probes in `debug/tests/TriggerHandlerTests.gd`:
  - `_relic_void_hourglass` (:525): after `fx.resolve("relic_extra_turn")`, the last RESOURCES_CHANGED for "player" in `state.journal` has `essence_max == state.player_essence_max` and `mana_max == state.player_mana_max`. Add a second case at the cap (for example 6/5): nothing grows, and the last event still matches the state.
  - `_vch_aura_grows_resources` (:1751): the last RESOURCES_CHANGED for "enemy" carries the grown maxima (1 and 1).
- New probe in `debug/tests/CardEffectTests.gd`: Font of the Depths.
  - Setup: `build_state`, player at 3/3 Mana, the card added with `state.add_to_hand`.
  - Action: `cmd_play_spell("player", inst, null)`.
  - Expect: the last player RESOURCES_CHANGED has `mana == 2` and `mana_max == 4`.
- Same file, Void Architect for the enemy: run its `on_play_effect_steps` with `TestHarness.make_ctx(state, "enemy")`. The last enemy RESOURCES_CHANGED has `mana_max == state.enemy_mana_max`.
- `tools/run_checks.sh` green.
- Behaviour-neutral: this only adds journal events. `digest_text` excludes the journal (CombatState.gd:2242-2288), and nothing connects to `resources_changed`. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` through `--act 4`; Font of the Depths can appear in any act, Void Hourglass and F14 are Act 3–4) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Related: task 071 (roadmap E1b): once the enemy panel reads the view, the enemy-side growth must be journaled. 071 depends on this task.
- Related: task 109 (roadmap E2): its phase E2a moves `refresh_end_turn_mode`, `PipBar.stop_blink` and the hand refreshes off live state. This task only adds the missing events.
- Related: task 092 (roadmap PS-void-marks): owns the enemy GRANT_ESSENCE branch (cap and journal gap).
- Related: task 091 (roadmap PS-relics): relics per side. When RelicEffects takes a side, the emit added here uses it instead of "player".

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) as a straight-to-task bug found while verifying roadmap §E (unit E, bug 4).
  - Re-check: after Font of the Depths, only the pip bar and the labels are stale. The end-turn buttons are refreshed (early) by the live read in `refresh_end_turn_mode`. After Void Hourglass, all three are stale. Title adjusted to name the labels.

## Summary

_(filled in at /task-done)_
