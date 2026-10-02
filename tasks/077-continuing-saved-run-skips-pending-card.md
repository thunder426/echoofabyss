---
id: "077"
title: Continuing a saved run skips a pending card reward, shop or relic reward (and loses the act's talent point)
status: backlog
area: meta
priority: high
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §H, the run layer; H1 later owns this routing). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The save stores no "where was the player" field, and Main Menu → Continue routes only on `deck_built` and `talent_points`. A player who leaves during a post-combat screen comes back at the next fight. The reward they hadn't taken yet is gone.

### Trace (Act 1 boss)

1. Beat fight 3 (Imp Matriarch). `CombatScene._on_victory` grants the shards and calls `advance_node()` (CombatScene.gd:1596-1598), so `run_node_index` becomes 4. It then calls `go_to_scene("res://rewards/RewardScene.tscn")` (:1609), and `GameManager.go_to_scene` saves before every change (GameManager.gd:69-71 `UserProfile.save()`).
2. Pick a card. `RewardScene._finish` (:137-139) sees `is_act_complete()` and goes to RelicRewardScene; `go_to_scene` saves again, with `talent_points` 0.
3. On RelicRewardScene, press ESC → Main Menu (EscMenu.gd:56-58, which saves the same state through `go_to_scene`), or just close the game.
4. MainMenu `_ready` calls `UserProfile.load_profile()` (:20). Continue (MainMenu.gd:71-79) routes like this:
   ```gdscript
   if not GameManager.deck_built:
   	GameManager.go_to_scene("res://ui/DeckBuilderScene.tscn")
   elif GameManager.talent_points > 0:
   	GameManager.go_to_scene("res://talents/TalentSelectScene.tscn")
   else:
   	GameManager.go_to_scene("res://map/EncounterLoadingScene.tscn")
   ```
5. Fight 4 loads. The relic offer never shows, and `RelicRewardScene._proceed` (:157-159, `GameManager.add_talent_point()`) never runs. The player has permanently lost the Act 1 relic and a talent point.

The run dict (UserProfile.gd:26-38) has `current_hero`, `player_deck`, `player_relics`, `run_node_index`, `player_hp_max`, `player_hp`, `core_unit_limit`, `has_revive`, `talent_points`, `unlocked_talents` and `deck_built`. There is no pending-screen field.

### Every case

- **RewardScene** (after any won fight): the card reward is lost. If the next fight is an act boss, the shop is skipped too, because the shop is reached only from `RewardScene._finish` (:140-142).
- **ShopScene**: the shop is skipped.
- **RelicRewardScene** (after fights 3, 6 and 9): the relic or Empower pick and the act's talent point are lost.
- **Not affected:** TalentSelectScene, because unspent points route there (and EncounterLoadingScene redirects there, :19-21), and a fight in progress, which restarts from EncounterLoadingScene.

## Proposed fix

1. **Record the run screen.** Add `GameManager.resume_scene: String = ""` and a list of resumable run screens: TalentSelectScene, DeckBuilderScene, EncounterLoadingScene, RewardScene, ShopScene and RelicRewardScene.
   - `go_to_scene` calls `note_run_screen(path)` before `UserProfile.save()`. When `path` is in the list, it sets `resume_scene = path`. Other targets leave it alone: MainMenu, Collection, DeckViewer (which returns to EncounterLoadingScene) and CombatScene (a fight resumes at its loading screen).
   - It must be set before the save on entry. Closing the window doesn't save, so a value set in the target scene's `_ready` would be too late.
   - Reset it in `start_new_run` (GameManager.gd:77-92) and `UserProfile.reset_all` (:108-121).
2. **Save and load it.** Add `"resume_scene"` to the run dict (UserProfile.gd:26-38), and read it in `load_profile` (:72-85) with `str(run.get("resume_scene", ""))`. A save without the key loads as "" and keeps today's routing.
3. **One routing function.** Add `GameManager.continue_route() -> String`. It returns `resume_scene` when that is set and `ResourceLoader.exists(resume_scene)`, otherwise today's rule. `MainMenu._on_continue_pressed` becomes `GameManager.go_to_scene(GameManager.continue_route())`.
4. **Re-rolled offers are accepted.** A resumed RewardScene, ShopScene or RelicRewardScene rolls its offers again. Persisting them is out of scope. Note for the owner and task 052: quit and Continue then re-rolls a shop for free (Refresh costs 1 shard), which is the same save-scum question as the combat seed in task 052.
5. **Docs.** ARCHITECTURE.md:68 says "`GameManager.go_to_scene()` handles every transition and auto-saves". Add "and records the run screen that Continue resumes".

### Interaction with task 052

- If task 052 has landed, put `resume_scene` in `RunState` and the v2 schema instead of the v1 dict. A v1 save migrates with `resume_scene = ""`.
- Until 052 saves `void_shards`, a resumed shop opens with 0 shards. ShopScene then also treats it as the first shop (`_is_first_shop = GameManager.void_shards <= 2`, ShopScene.gd:65), which task 128 (roadmap H7) replaces with a check on run position. That isn't worse than today, where the shop is skipped and the shards are lost anyway.

## Verification

- **Routing probe.** Put it in MetaTests if task 052 has landed, otherwise in TriggerHandlerTests.gd beside `_korrath_hero_registered` (:2304). Save and restore the GameManager fields it sets, and don't call `go_to_scene`, which changes the scene.
  - `deck_built = true`, `talent_points = 0`, `note_run_screen("res://relics/RelicRewardScene.tscn")`: `continue_route()` is the RelicRewardScene path.
  - Then `note_run_screen("res://ui/MainMenu.tscn")`: still RelicRewardScene.
  - Then `note_run_screen("res://map/EncounterLoadingScene.tscn")`: EncounterLoadingScene.
  - `resume_scene = ""` with `deck_built = false`: DeckBuilderScene, today's fallback.
  - `start_new_run()` clears `resume_scene`.
- **Round trip** (needs 052's overridable save path; until then a manual check): save with `resume_scene` set to the RewardScene path, `load_profile()`, and assert the field survives. A run dict without the key loads as "".
- **Manual:**
  - Beat fight 3, take the card, then ESC → Main Menu → Continue. The relic screen appears, and Empower or a relic pick grants the talent point.
  - The same from RewardScene after fight 2 lands on the card reward, and the shop follows.
  - Quitting the game (not ESC) on each screen gives the same results.
- `tools/run_checks.sh` green. LiveSmoke and Parity set `saving_disabled`, so the new save key doesn't touch them.
- Behaviour-neutral for combat: meta flow only, no combat, sim or AI file changes, so the balance fingerprint can't move.

## Related

- Related: task 052 — `RunState` and the v2 schema (where `resume_scene` belongs if 052 lands first), `void_shards` persistence, the overridable save path and the MetaTests layer.
- Related: task 123 (roadmap H1) — H1a moves `continue_route` and the run-screen bookkeeping into `RunService`.
- Related: task 128 (roadmap H7) — the first shop is derived from run position, so a resumed shop isn't mistaken for the first.
- Related: task 080 (roadmap H4) — fixes ARCHITECTURE.md's scene flow. Mention Continue there if this task lands first.
- Related: task 138 (roadmap J2) — MetaTests for run progression; the routing probe moves there.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from unit H's straight-to-task bug "Continuing a run skips a pending card reward, shop or relic reward". Re-checked the trace end to end at `404b51c` (MainMenu, UserProfile, GameManager.go_to_scene, EscMenu, RewardScene, RelicRewardScene, EncounterLoadingScene). The fix records every run screen, not only the three reward screens, so Continue needs one rule.

## Summary

_(filled in at /task-done)_
