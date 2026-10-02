---
id: "080"
title: Delete the unreachable MapScene and the dead GameManager resource fields; fix ARCHITECTURE.md's scene flow
status: backlog
area: meta
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item H4 (`design/refactors/ARCHITECTURE_ROADMAP.md` §H). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### MapScene is unreachable

- Nothing navigates to `map/MapScene.tscn`. No `go_to_scene`, `change_scene_*`, `preload` or `load` names it, and neither does `project.godot`. Its uid `uid://cv5ilpkj38hi3` appears only in `map/MapScene.gd.uid`.
- The only references outside the scene's own files:
  - `shared/scripts/AudioManager.gd:12`, a `SCENE_MUSIC` entry: `"res://map/MapScene.tscn": "res://assets/audio/ost/deck_build_screen.mp3",`
  - `talents/TalentSelectScene.gd:4`, a comment: `## Player spends all pending talent_points then returns to MapScene.`
- Last changed in `1a8a6ae` (Version 0.26, 2026-03-28).
- It draws a fixed linear column per act from `GameManager.TOTAL_ACTS`, `ACT_SIZES` and `BOSS_INDICES` (MapScene.gd:24, :47, :50, :71). It has no branching. A future branching map would be a rewrite either way.
- It still reads EncounterDecks through `GameManager.get_encounter` (MapScene.gd:63, :136), so it sits in task 047's reader list. It also holds 7 of the 209 theme overrides counted for roadmap H5.
- `map/` stays: it also holds `EncounterLoadingScene`.

### Dead GameManager fields

- `shared/scripts/GameManager.gd:36-40`:
  ```
  # --- Resources (in-combat, reset each combat) ---
  var abyss_essence: int = 0
  var abyss_essence_max: int = 1
  var mana: int = 0
  var mana_max: int = 1
  ```
  They are written only by `start_new_run` (:82 `abyss_essence_max = 1`, :83 `mana_max = 1`) and read nowhere. `grep -rnE 'GameManager\.(abyss_essence|abyss_essence_max|mana|mana_max)\b' --include='*.gd' .` finds nothing. Combat resources live on CombatState. These fields suggest GameManager owns them.
- `GameManager.gd:8` `const TOTAL_ACTS  := 4` has one reader, MapScene.gd:24.

### Fields that are not part of this task

- `current_faction` (:34): task 052 step 4.
- `player_hp` (:25): task 052 step 8.
- `last_boss_unlocks` (:47) is not dead. Task 078 gives it a reader (owner decision QN4).

### ARCHITECTURE.md's scene flow is wrong

`design/master_doc/ARCHITECTURE.md:62-66`:
```
MainMenu → HeroSelectScene → DeckBuilderScene → TalentSelectScene
       → MapScene → EncounterLoadingScene → CombatScene
       → RewardScene (→ RelicRewardScene / ShopScene) → MapScene → …
```
- MapScene appears twice. The file table also has `| Map / encounter selection | map/MapScene.gd |` (:296).
- The order is wrong. HeroSelectScene goes to TalentSelectScene (HeroSelectScene.gd:469). TalentSelectScene goes to DeckBuilderScene only while `not GameManager.deck_built`, and otherwise to EncounterLoadingScene (TalentSelectScene.gd:415-418).
- It omits RelicRewardScene → TalentSelectScene (RelicRewardScene.gd:157-159) and the rule that the shop comes only before an act boss (RewardScene.gd:137-144).
- :68 says "`GameManager.go_to_scene()` handles every transition and auto-saves". EncounterLoadingScene → CombatScene doesn't use it: it loads threaded, then calls `UserProfile.save()` and `change_scene_to_packed` itself (EncounterLoadingScene.gd:236-253).

The real flow, from every `go_to_scene` call in game code:
- MainMenu → HeroSelectScene (New Run, MainMenu.gd:69) or CollectionScene (:82).
- MainMenu Continue (MainMenu.gd:71-79) → DeckBuilderScene if `not deck_built`, else TalentSelectScene if `talent_points > 0`, else EncounterLoadingScene.
- HeroSelectScene → TalentSelectScene → DeckBuilderScene (first visit) → EncounterLoadingScene (DeckBuilderScene.gd:676-679).
- EncounterLoadingScene → TalentSelectScene when points are unspent (:19-21); ↔ DeckViewerScene (:256, DeckViewerScene.gd:116); → CombatScene.
- CombatScene win (CombatScene.gd:1595-1609): shards, `advance_node()`, then RewardScene. On the last fight, a "RUN COMPLETE" panel instead, whose button returns to MainMenu.
- RewardScene `_finish` (:137-144) → RelicRewardScene if the act is complete; else ShopScene if the next fight is an act boss; else EncounterLoadingScene.
- ShopScene → EncounterLoadingScene (:558). RelicRewardScene → TalentSelectScene (:159), which then → EncounterLoadingScene.
- CombatScene loss (:1611-1631, :1659-1666) → MainMenu, or with Second Wind (`has_revive`) the same CombatScene once more.
- EscMenu → MainMenu from any scene (EscMenu.gd:58).

## Decision (owner, 2026-10-01)

Q8: "**Delete it now.** The run stays linear (git history keeps the file). Fix ARCHITECTURE.md's scene flow."

## Proposed fix

1. Delete `map/MapScene.gd`, `map/MapScene.gd.uid` and `map/MapScene.tscn`.
2. Remove the MapScene entry from `AudioManager.SCENE_MUSIC` (AudioManager.gd:12).
3. Reword TalentSelectScene.gd:4: "then continues to DeckBuilderScene (first visit) or EncounterLoadingScene."
4. GameManager.gd:
   - delete :36-40 (the "Resources (in-combat…)" header and the four fields) and the two writes at :82-83;
   - delete `TOTAL_ACTS` (:8). If task 124 (roadmap H2) has landed first, it is already gone.
   - Leave `current_faction`, `player_hp` and `last_boss_unlocks` alone (see above).
5. Rewrite ARCHITECTURE.md's scene flow (:60-68) from the list above. A small block diagram plus three lines for the branches (reward routing, defeat, Continue) is enough.
   - Fix the :68 sentence to name the EncounterLoadingScene → CombatScene exception.
   - Delete the :296 `Map / encounter selection` row.
   - If task 077 has landed, Continue also resumes a pending RewardScene, ShopScene or RelicRewardScene. Describe that.
   - If task 078 has landed with a new post-boss screen, include it.
6. When this lands, add a one-line work-log note to task 047 that its MapScene readers (MapScene.gd:63, :136) are gone. That note doesn't change 047's scope.

## Verification

- `grep -rn "MapScene" --include='*.gd' --include='*.tscn' --include='*.tres' --include='*.godot' --include='*.cfg' .` → 0 hits (excluding `.godot/`).
- `grep -rnE 'GameManager\.(abyss_essence|abyss_essence_max|mana|mana_max)\b|TOTAL_ACTS' --include='*.gd' .` → 0 hits.
- `tools/run_checks.sh` green. Its Godot import step reports any dangling `ext_resource`, preload or uid.
- Manual run in the editor: New Run → hero → talents → deck → fights 1–3 (shop before fight 3) → boss → card reward → relic → talents → fight 4. Then ESC → Main Menu → Continue → the right screen. No map at any point, and the talent / deck-builder screens keep their music.
- Behaviour-neutral: no rules, sim or AI code changes, so no act can move. If in doubt, the seeded balance fingerprint (`BalanceSimBatch -- --act 1 --runs 200 --seed 7`, before and after) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Related: task 052 — owns `current_faction` (step 4) and `player_hp` (step 8). This task leaves both.
- Related: task 078 — gives `last_boss_unlocks` a reader. Keep the field. If 078 adds a post-boss screen, the new scene flow shows it.
- Related: task 077 — makes Continue resume a pending reward, shop or relic screen. Whichever lands second updates the scene-flow text.
- Related: task 047 — its EncounterDecks reader list names MapScene.gd:63 / :136. Deleting MapScene first shrinks that list.
- Related: task 124 (roadmap H2) — derives act sizes, fight count and boss indices from EncounterTable. MapScene's reads of `ACT_SIZES`, `BOSS_INDICES` and `TOTAL_ACTS` drop out of its site list. Either task deletes `TOTAL_ACTS`.
- Related: task 126 (roadmap H5) — 7 of the 209 theme overrides it counts are in MapScene.gd and go away here.
- Related: task 123 (roadmap H1) — RunService takes over the post-combat routing later. Update the scene-flow text again then.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item H4, with owner decision Q8. Re-checked at `404b51c`.
  - Confirmed that nothing references MapScene and that the four resource fields have no readers.
  - Traced every `go_to_scene` in game code for the new scene flow.
  - Added the EncounterLoadingScene → CombatScene save exception.
  - `last_boss_unlocks` stays (QN4, task 078).

## Summary

_(filled in at /task-done)_
