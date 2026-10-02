---
id: "103"
title: Combat UI reads hero / talent / enemy display info from the fight (state / CombatConfig), not GameManager
status: backlog
area: ui
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item C5, plus H6b (PipBar's hero widgets) merged in (`design/refactors/ARCHITECTURE_ROADMAP.md` §C direction 5, §H). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The owner moved these sites out of task 055 on 2026-09-30 ("Out of scope" in task 055).

### Seven presentation files read the run, not the fight

The regex `(?<![\w.])(GameManager|UserProfile|TestConfig)\.` (task 055's), run over lint L8's presentation file set (tools/lint/lint_engine.py:285-292), with comments stripped, finds 16 reads:

| File | Lines | Reads |
|---|---|---|
| combat/ui/PipBar.gd | :194, :198 | `HeroDatabase.has_passive(GameManager.current_hero, "fleshbind")`, `GameManager.has_talent("soul_forge")` |
| combat/ui/SerisResourceBar.gd | :47, :48 | `GameManager.has_talent("soul_forge")`, `("corrupt_flesh")` |
| combat/ui/CombatUiStyle.gd | :32, :173, :206, :214 | `empty_slot_bg_for_hero(GameManager.current_hero)` in the static `apply_empty_slot`; `get_hero(GameManager.current_hero)`; `GameManager.unlocked_talents` (×2) |
| combat/ui/PlayerHeroPanel.gd | :64, :98 | `HeroDatabase.get_hero(GameManager.current_hero)` |
| combat/ui/EnemyHeroPanel.gd | :86, :179, :180, :181 | `GameManager.current_enemy.portrait_path`, `if GameManager.current_enemy:`, `GameManager.is_boss_fight()`, `GameManager.current_enemy.enemy_name.to_upper()` |
| combat/board/BoardSlot.gd | :547 | `HeroDatabase.empty_slot_bg_for_hero(GameManager.current_hero)` |
| combat/effects/vfx/CombatVFXBridge.gd | :1026 | `GameManager.get_current_act() if GameManager else 3` (picks the enemy casting-glyph faction, :1027-1030) |

The last one was not in task 055's list. The CombatScene shell is outside the set and stays out of scope.

The fight already has the player-side values: `CombatState.talents` (combat/board/CombatState.gd:1647), `hero_passives` (:1651) and `player_hero_id` (:1655). The enemy's display name, portrait, boss flag and act are not in `CombatConfig` at all (combat/board/CombatConfig.gd:19-37). CombatScene doesn't keep the config it starts with: `state.setup_combat(CombatConfig.from_game_manager())` (combat/board/CombatScene.gd:185).

### Today the values match

`from_game_manager` copies hero, talents and passives from GameManager (CombatConfig.gd:43-51) before any panel is built. The cheat panel's talent unlock writes GameManager and then `_refresh_override_context` (CombatScene.gd:1261-1269) copies it into the state. No player sees a wrong value today.

### What breaks

Any live scene run from a config that isn't GameManager's: a replay, a mirror or PvP fight (owner decision Q1: planned), or a scene-level test. Then:
- the panels show GameManager's hero portrait, passives and talents instead of the fight's;
- PipBar and SerisResourceBar build (or skip) the Flesh / Forge widgets and the skill buttons for the wrong hero;
- the enemy panel shows GameManager's enemy name, portrait and boss label.

Already wrong today: BoardSlot serves both sides, so the enemy's empty slots are painted with the player hero's faction art (:547). Every hero is Abyss Order today, so nobody can see it.

### PipBar (roadmap H6b)

H6b asked to move PipBar's code-built layout (789 lines, no .tscn) into a scene. Its real structural problem is the hero-specific widgets chosen from GameManager (:192-199), which this task fixes. H6b was merged here so PipBar is reworked once.

## Decision (owner, 2026-10-01)

- 2026-09-30: these UI readers are out of task 055's scope and go to roadmap C5 (this task).
- 2026-10-01, Q1: PvP / mirror matches are planned, so a scene driven by a non-GameManager config is a real case. Priority normal.
- 2026-10-01, QN6: every act boss shows the BOSS label. Task 124 (roadmap H2) changes `GameManager.is_boss_fight()` to cover all boss fights. This task copies whatever it returns into the config, so the label follows task 124 whichever lands first.

## Proposed fix

1. **CombatScene keeps its config.** Add `var config: CombatConfig = null`. `_ready` uses it when it was set before the node entered the tree (tests, replays); otherwise it builds `CombatConfig.from_game_manager()` and stores it. The default path is unchanged.
   - `_refresh_override_context` (cheat panel, debug only) still copies GameManager into the state; leave it.
2. **Display fields on CombatConfig:** `enemy_display_name: String`, `enemy_portrait_path: String`, `enemy_is_boss: bool`, `act: int` (0 = unknown).
   - `from_game_manager` fills them from `GameManager.current_enemy`, `GameManager.is_boss_fight()` and `GameManager.get_current_act()`.
   - `from_dict` fills the name and portrait from `EncounterTable.entry_for_profile(c.enemy_profile_id)` (EncounterTable.gd:177), so a replay through the live scene shows the right enemy. The sim never reads these fields.
3. **PipBar** :194 → `_scene.state.hero_passives.has("fleshbind")`, :198 → `_scene.state.talents.has("soul_forge")`. :201 already reads `_scene.state`.
4. **SerisResourceBar** `maybe_create(scene: Object, talents: Array[String])`; PlayerHeroPanel.gd:147 passes `_scene.state.talents`. Passing the list keeps the bar side-ready. Task 101 later passes `HeroDatabase.skills_for(...)` instead; whichever lands second adapts.
5. **PlayerHeroPanel** :64, :98 and **CombatUiStyle** :173 → `HeroDatabase.get_hero(_scene.state.player_hero_id)`; CombatUiStyle :206, :214 → `_scene.state.talents`.
6. **Empty-slot art per side.**
   - Add `CombatScene.empty_slot_bg(side: String) -> String`. Today it returns `HeroDatabase.empty_slot_bg_for_hero(state.player_hero_id)` for both sides: the state has no enemy hero id yet (task 090 adds one and changes the enemy branch).
   - `CombatUiStyle.apply_empty_slot(panel, lbl, bg_path: String)`: callers TrapEnvDisplay.gd:125 (player environment slot), :204 and :229 pass `_scene.empty_slot_bg(owner)`.
   - BoardSlot has no scene handle. Add `set_empty_bg(path: String)`, which stores the path and re-renders if the slot is empty. CombatScene calls it in `_connect_board_slots` (:333-346) where it sets `slot_owner`. `_show_empty_state` (:532) reads the stored path instead of :547's GameManager read. (BoardSlot's `_ready` runs before CombatScene's, so the first render has no path; the call re-renders.)
7. **EnemyHeroPanel** :86 → `_scene.config.enemy_portrait_path`; :179-181 → `_scene.config.enemy_display_name` with the `"⚔ BOSS  "` prefix when `_scene.config.enemy_is_boss`. Make the name label a field (`_name_label`, today the local `name_lbl` at :172) so a test can read it.
8. **CombatVFXBridge** :1026 → `var act: int = _scene.config.act if _scene != null else 3` (:1031 already guards `_scene != null`). Keep today's mapping: 1 feral, 2 corrupted, anything else abyss.
9. **Lint.** Extend L8 (`scan_presentation_mutation`, lint_engine.py:285) with a second pattern over the same file set: task 055's regex `(?<![\w.])(GameManager|UserProfile|TestConfig)\.`, message "presentation reads the fight (`_scene.state` / `_scene.config`), never the run autoloads". Task 055 extends L1 the same way, so no new rule number. CheatPanel stays excluded; the CombatScene shell stays outside the set. Task 140 (roadmap J4) later derives L8's file set and brings CombatScene.gd in for the mutation patterns; keep CombatScene.gd excluded from this read pattern, since the shell builds the config from GameManager.
10. **PipBar layout (H6b), optional.** Moving the pip columns' static layout into a `PipBar.tscn` is visual-only. Do it as its own commit with before/after screenshots, or drop it. The Flesh / Forge widgets stay code-built and are chosen by step 3.
11. **Docs.** `design/master_doc/ARCHITECTURE.md`:
    - CombatConfig row (:100): the display fields;
    - the presentation rules: "combat UI reads `state` / `scene.config`, never GameManager";
    - the L8 description: the second pattern.

## Verification

- **New LiveSmoke probe `_ui_reads_fight_config`** (debug/tests/LiveSmokeTests.gd, next to `_hp_labels_lag_the_engine`):
  - Setup: `GameManager.start_new_run()`, `current_hero = "lord_vael"`, `unlocked_talents = []`, an encounter 3 enemy, as `_launch` does (:234-238). Build `var cfg := CombatConfig.from_game_manager()` (so the enemy deck, HP and profile are real), then switch it to Seris: `player_hero_id = "seris"`, `talents = ["soul_forge", "corrupt_flesh"]`, `hero_passives` from `HeroDatabase.get_hero("seris").passives`, `player_deck_ids` from the `seris_demon_forge` preset, a fixed `seed`, `enemy_display_name = "Probe Enemy"`, `enemy_is_boss = true`. Instantiate the scene and set `scene.config = cfg` before `add_child`.
  - Assert `scene._pip_bar._flesh_root != null`, `scene._pip_bar._forge_root != null` and `scene._player_hero_panel.resource_bar != null`.
  - Assert the enemy name label reads `"⚔ BOSS  PROBE ENEMY"`.
  - With only step 1 applied it fails (the UI still reads the Vael GameManager: no Flesh widget, no skill bar, the real enemy's name); with the whole change it passes.
  - Tear down with `_teardown` as the other scenarios do.
- **Lint:** the extended L8 reports 0 hits after the change, and 16 before it (run it once on the old tree, or temporarily re-add one read, to see the pattern fire).
- `tools/run_checks.sh` green.
- Behaviour-neutral: presentation only. With `config == null` the scene calls `from_game_manager()` exactly as today, and no engine, sim or AI code changes, so the balance fingerprint can't move. Parity (inside run_checks) stays green.

## Related

- Depends on: task 055 — shares its GameManager regex and edits the same lint file; ordering only, so both lint edits use one pattern.
- Related: task 124 (roadmap H2) — makes `is_boss_fight()` true for every act boss (QN6); `config.enemy_is_boss` follows it.
- Related: task 127 (roadmap H6) — splits EnemyHeroPanel; depends on this task so :86 and :179-181 are rewritten once.
- Related: task 090 — per-side talents, passives and an enemy hero id; it switches `empty_slot_bg("enemy")` and the resource widgets to the enemy's own data.
- Related: task 101 (roadmap C2) — hero skills as data; changes `SerisResourceBar.maybe_create` again.
- Related: task 071 (roadmap E1b) and task 109 (roadmap E2) — the enemy panel and the player resource widgets render journal payloads; they touch the same files' update paths, not their setup.
- Related: task 111 (roadmap E4) — lint L17 (provisional; take the next free number if the landing order differs) ratchets engine reads in UI files; this task's L8 pattern covers the autoloads.
- Related: task 053 — gates the cheat panel, whose `_refresh_override_context` still copies GameManager into the state (task 140 moves that function into CheatPanel.gd).
- Related: task 140 (roadmap J4) — derives L8's file set, which brings CombatScene.gd in; this task's GameManager-read pattern keeps it excluded.
- Related: task 068 — edits `CHAMPION_INFO` in EnemyHeroPanel and `PASSIVE_INFO` in CombatUiStyle; same files, different lines.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item C5, with H6b merged in. Re-ran the regex scan at `404b51c` (16 hits, including the missed CombatVFXBridge.gd:1026). Confirmed no path diverges today (the cheat panel re-syncs the state). Priority normal per owner decision Q1; the BOSS label follows task 124 (QN6). The probe injects a config so it fails before the change.

## Summary

_(filled in at /task-done)_
