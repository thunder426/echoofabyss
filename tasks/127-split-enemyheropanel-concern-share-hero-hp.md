---
id: "127"
title: Split EnemyHeroPanel by concern; share the hero HP bar and Korrath badges with PlayerHeroPanel
status: backlog
area: ui
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item H6 (`design/refactors/ARCHITECTURE_ROADMAP.md` §H), narrowed by grooming to the two hero panels. Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### EnemyHeroPanel is one 979-line file built in code

`combat/ui/EnemyHeroPanel.gd` (979 lines, no .tscn) has 52 `.new(` calls and 70 `add_theme_*_override` calls. It mixes:

| Concern | Lines |
|---|---|
| Panel setup: background, portrait layer, margins, highlight sibling | :62-159 |
| Name header and passive icon row | :166-185 |
| HP bar: build, drain, heal, flash, gradient | :193-307 |
| Stats columns (HP, essence, mana, hand, Void Marks), Korrath badges, champion row | :314-414 |
| `update` | :421-454 |
| Korrath badges: update and row builder | :460-507 |
| Attack-target pulse | :513-579 |
| Spell-target pulse | :585-632 |
| Champion progress: pips, shake, killed | :639-746 |
| Champion tooltip, including the `CHAMPION_INFO` text table (:768) | :753-975 |

### PlayerHeroPanel carries a second copy

Function bodies compared line by line (EnemyHeroPanel.gd / PlayerHeroPanel.gd):
- identical: `_build_korrath_badge_row` (:487 / :198), `_update_hp_bar_gradient` (:302 / :317), `_animate_hp_heal` (:279 / :297), `_spawn_bar_flash` (:284 / :300);
- the same code with different comments or field names: `_build_hp_bar` (:193 / :224; only comments differ), `_animate_hp_drain` (:263 / :288; comments and the tween field name), `update_korrath_debuffs` (:460 / :173; field names);
- the HP-label-and-bar block of `update` (EnemyHeroPanel.gd:422-432 / PlayerHeroPanel.gd:158-168) and the badge-row wiring (:379-390 / :134-145) are also copies.

The review reported the drain animation as "diverged" (16 vs 8 lines). Re-checked: the extra lines are comments; both hold 0.35 s, then drain over 0.45 s. So nothing is visibly different today. The cost is that every HP-bar or badge fix has to land twice, and the next one may not.

### Why now matters less than order

Three tasks rewrite parts of this file first:
- task 071 (roadmap E1b) changes `update` to render a `ViewState` instead of the live `CombatState`;
- task 109 (roadmap E2) makes the Korrath badges render journal payloads;
- task 103 (roadmap C5) replaces the GameManager reads at :86 (portrait) and :179-181 (name and BOSS prefix) with `_scene.config`.

Doing this split after them means the panel is rewritten once. PvP is planned (owner decision Q1), and a PvP opponent's panel will need the player panel's widgets; shared components are the first step toward that, but building a mirrored panel is not part of this task.

### Constraints the split must keep

- **The panel node is a VFX anchor and an input target.** `CombatScene._enemy_status_panel` is an alias of the panel (CombatScene.gd:57, :213). VFX place effects on its rect (CombatPresenter.gd:475, :553; CombatScene.gd:978-979, :1681; CombatVFXBridge.gd:537, :658, :685, :830; VfxController.gd:116, :156). Targeting connects its `gui_input` and flips its `mouse_filter` (Targeting.gd:62-67, :116-118; CombatScene.gd:1171-1173). The root stays an `EnemyHeroPanel` Control with today's minimum size, anchors and offsets (:65-75).
- **The highlight border is a sibling in `ui_root`** (:139-157), not a child, so it draws on top.
- **The public API callers use:** `setup`, `update` (in whatever form task 071 leaves it), `update_korrath_debuffs` (as task 109 leaves it), `show_attackable`, `start_spell_pulse`, `stop_spell_pulse`, `update_champion_progress`, `on_champion_killed` and the `hero_pressed` signal (callers: CombatScene, CombatUI, CombatPresenter, CombatInputHandler, Targeting).

## Proposed fix

1. **`combat/ui/HeroHpBar.gd`** (a Control): build (from `_build_hp_bar`), `show_hp(current: int, maximum: int)` (the ratio, gradient, drain and heal logic from `update`), `_animate_hp_drain`, `_animate_hp_heal`, `_spawn_bar_flash`, `_update_hp_bar_gradient`. The fill colour is a setup argument (enemy `Color(0.85, 0.25, 0.30)`, player `Color(0.30, 0.75, 0.35)`). Both panels use it; the "❤ HP" label stays in each panel's layout.
2. **`combat/ui/KorrathBadgeRow.gd`**: builds the Armour / Armour Break row and the Corruption row into a given parent, and owns `show_debuffs(armour, armour_break, corruption_stacks)` (today's `update_korrath_debuffs` body, in the form task 109 leaves it). Both panels use it; their `update_korrath_debuffs` forward to it.
3. **`combat/ui/ChampionProgress.gd`**: the champion row, pips, shake, killed state and hover tooltip (:392-414, :639-975). EnemyHeroPanel forwards `update_champion_progress` and `on_champion_killed`. Move `CHAMPION_INFO` with it unchanged (task 068 edits its text and makes it the class-level const `EnemyHeroPanel.CHAMPION_INFO`; if it moves, update 068's coverage probes `_enemy_tooltips_cover_every_encounter` / `_champion_tooltip_stats_match_cards` to the new owner), or, if task 096 (roadmap B2) has landed, read the tooltip text from its champion spec table.
4. **`combat/ui/EnemyHeroPanel.tscn`** for the static layout: background, portrait clip and overlay, margin, header row, stats columns, and slots for the three components. Move the static overrides into the scene, or into `global_theme.tres` type variations if task 126 has landed. CombatScene.gd:209 instantiates the scene instead of `EnemyHeroPanel.new()`. Keep `setup(scene, ui_root)` for the parts that need the scene (portrait path, passive icons, highlight sibling).
5. **Keep the target pulses in EnemyHeroPanel** (:513-632). PlayerHeroPanel has none, so there's nothing to share yet.
6. After the split EnemyHeroPanel should hold setup, `update`, the pulses and forwarders: roughly a third of today's size.
7. **Docs:** ARCHITECTURE.md:126-127 (the PlayerHeroPanel / EnemyHeroPanel rows) list the new components.

## Verification

- **LiveSmoke probe** (debug/tests/LiveSmokeTests.gd, next to `_hp_labels_lag_the_engine`; if task 071's `_enemy_panel_follows_the_journal` exists, extend it instead and update its field paths):
  - after setup, the enemy panel's HP label reads `"❤ HP: %d / %d"` of the view's enemy HP and max, and the player panel's reads the player's;
  - deal 300 to the enemy hero through `combat_manager.apply_hero_damage`; after its DAMAGE_DEALT plays, the enemy HP label shows the payload's after value and the `HeroHpBar` fill ratio equals after / max;
  - the same for a heal on the player hero (the heal path through `show_hp`).
- **Korrath badges:** in a LiveSmoke fight, call each panel's `update_korrath_debuffs(0, 100, 2)`; the armour row shows "Armour Break 100" and the corruption row "Corrupt ×2". `(0, 0, 0)` hides both.
- **Champion progress:** the existing `_f13_vrp_champion_progress` (LiveSmokeTests.gd:71) still passes; once the presenter is idle, add a check that ChampionProgress shows 5 filled pips ("◆") and the label "SUMMONING..." (today's `update_champion_progress`, :660-691).
- **Manual visual QA:** before/after screenshots of both panels: HP drain and heal, Korrath badges (a Korrath fight), champion pips and tooltip (F1), the attack and spell highlights, and Void Mark VFX landing on the enemy panel.
- `tools/run_checks.sh` green. LiveSmoke instantiates CombatScene, which builds both panels.
- Behaviour-neutral: UI only, no rules, sim or AI code changes, so the balance fingerprint can't move.

## Related

- Depends on: task 071 (roadmap E1b) — changes `EnemyHeroPanel.update` to render a ViewState; split after it so `update` is rewritten once.
- Depends on: task 109 (roadmap E2) — makes the Korrath badges render journal payloads; `KorrathBadgeRow` takes the shape it leaves.
- Depends on: task 103 (roadmap C5) — replaces the GameManager reads at :86 and :179-181 with `_scene.config`; the header and portrait move into the scene after that.
- Related: task 068 — edits `CHAMPION_INFO` text in this file, moves it to class level, and adds a `passives` payload to PHASE_TRANSITION so the passive icon row can rebuild after F15's phase change (`CombatUiStyle.add_enemy_passive_hover_icon` takes the passive list as a parameter). Whichever lands second rebases; keep the header's passive row rebuildable.
- Related: task 096 (roadmap B2) — the champion spec table; the tooltip text can come from it.
- Related: task 126 (roadmap H5) — puts shared styles into `global_theme.tres`; this task can add type variations there.
- Related: task 111 (roadmap E4, lint L17, provisional; take the next free number if the landing order differs) — ratchets engine reads in UI files; update its baseline for the moved lines (the tooltip reads `_scene.state.enemy_passives`, :760).
- Related: task 113 (roadmap E7) — target highlights; touches `show_attackable` callers, not the pulse code.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item H6, narrowed to the hero panels. PipBar's layout went to task 103 (H6b); the CardVisual part was dropped (it already has CardVisual.tscn, and its 55 layout rects are per-frame data in `_FRAME_CONFIG`, which one scene can't express). Re-checked at `404b51c`: 52 `.new(`, not 48; the shared functions differ only in comments and field names, so the "diverged drain animation" is not a real difference; added the VFX-anchor and input constraints.

## Summary

_(filled in at /task-done)_
