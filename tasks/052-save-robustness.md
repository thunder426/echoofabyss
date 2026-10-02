---
id: "052"
title: Make saves versioned, atomic and complete
status: backlog
area: meta
priority: high
started:
finished:
---

## Description

Found in the 2026-09-25 architecture review (issue 6 of 9). Re-verified 2026-09-30 at `3009a60`. Line numbers are from that commit.

There are three unversioned JSON persisters:
- `shared/scripts/UserProfile.gd` (`user://profile.json`);
- `shared/scripts/SavedDecks.gd` (`user://saved_decks.json`);
- EncounterDecks, which moves into the repo in task 047.

### UserProfile

1. **No version field.** `save()` (:18-44) writes `{"permanent_unlocks", "run": {...}}`.
2. **Not atomic.** It opens with `FileAccess.open(SAVE_PATH, WRITE)` and then calls `store_string` (:39-44). A crash mid-write leaves a truncated file.
3. **A corrupt file loses every unlock.**
   - `load_profile()` reaches `push_error; return false` (:61-63) before `_ensure_default_unlocks()` (:68), so `permanent_unlocks` stays empty.
   - `has_active_run()` also fails to parse (:98-99), which disables Continue.
   - "New Run" calls `clear_run()`, which saves immediately (MainMenu.gd:67, UserProfile.gd:102-104) and overwrites the file.
   - Other auto-saves: `GameManager.go_to_scene()` (:69-71) and `EncounterLoadingScene.gd:252`.
4. **The run state is incomplete.** These aren't saved:
   - `void_shards` (GameManager.gd:23; earned at CombatScene.gd:1597, spent in ShopScene);
   - `relic_bonus_charges` (GameManager.gd:45; written at RelicRewardScene.gd:154);
   - `current_deck_id`. Load re-rolls the enemy deck (UserProfile.gd:85).
   - The combat seed. A reload reshuffles the fight; whether that matters (save-scumming) is a design call.
5. **Unknown card ids are never cleaned.** `CardDatabase.get_card_for_combat` calls `push_error` (:91-94) and `setup_deck` skips the null (CombatState.gd:1547-1550), but the id stays in the save forever. Shop, DeckViewer and DeckBuilder also hit `get_card` with it.
6. **`reset_all()` (:108-121) misses fields:** `void_shards`, `relic_bonus_charges`, `player_hp(_max)`, `core_unit_limit`, `has_revive`. `current_faction` is written (HeroSelectScene.gd:467) but never read.
7. **`player_hp` is saved but never used.**
   - Combat reads `player_hp_max` (CombatConfig.gd:45).
   - The only writers are ShopScene.gd:320-321 and the revive (CombatScene.gd:1663), and nothing writes HP back after a fight.
   - The design docs claimed HP persists between fights. They were corrected on 2026-09-30 (see Decision).

### SavedDecks is worse

On a parse error `load_all()` returns `{}` (:17-18). `save_deck()` (:32-35) then rewrites the file with only the new deck, and every saved deck is lost.

### Tests

- `SAVE_PATH` is a `const`, so tests can't point it at a temp file.
- RunAllTests has 5 layers (DamageType, CardEffect, TriggerHandler, Command, Scenario; RunAllTests.gd:11-31) and no meta layer.
- Only LiveSmoke (:19) and Parity (:60) set `saving_disabled`.

## Decision (owner, 2026-09-30)

- **HP does not carry between fights.** Every fight starts at full `player_hp_max`, which is what the code has done since v0.34 replaced the shop's HP Restoration with Second Wind.
  - The docs were updated on 2026-09-30: DESIGN_DOCUMENT.md §17 run state, ARCHITECTURE.md's GameManager row, and REWARD_SYSTEM_DESIGN.md's service tables.
  - This task deletes the `player_hp` field.

## Proposed fix

1. **Shared persistence helper** (e.g. `shared/scripts/JsonStore.gd`), used by UserProfile and SavedDecks:
   - **Atomic write:** write `<path>.tmp`, then `DirAccess.rename_absolute` over the real file, through `ProjectSettings.globalize_path` as `reset_all` does (:121). Keep `<path>.bak`. Check that the rename replaces an existing file on Windows as well.
   - **Versioning:** a top-level `"version"`. A file with no version is v1. Migrate through a chain (`_migrate_v1_to_v2`, …).
   - **Parse failure:** try `.bak`. Otherwise rename the file to `*.corrupt.json`, start from defaults, and don't write over it until a save succeeds.
2. **UserProfile:**
   - Always run `_ensure_default_unlocks()`, including on failure.
   - Route the saves in GameManager and EncounterLoadingScene through the helper.
3. **SavedDecks** (the most urgent part): never treat a parse failure as an empty file when saving.
4. **`RunState`** with `to_dict` / `from_dict` / `reset`, owning every run field. GameManager holds one.
   - It includes `void_shards`, `relic_bonus_charges`, `current_deck_id` and 047's `run_seed`.
   - Cast numbers to int in `from_dict`, because JSON loads them as floats (see CombatConfig.gd:88-89).
   - `reset()` covers the fields `reset_all()` misses.
   - Drop `current_faction`, or read it.
5. **Enemy on load.**
   - Rebuild it from the saved `current_deck_id` with `get_deck`, `get_deck_profile` and `get_deck_limited`.
   - If the id no longer exists, pick again with the run seed.
   - Saving the id, not only the seed, survives pool edits between versions.
6. **Validate ids on load:** drop unknown card, relic and talent ids with a warning, and write the cleaned save back.
7. **Make `SAVE_PATH` overridable** (a var or a setter) so tests can use a temp path.
8. **Delete `player_hp`** (see Decision):
   - remove it from GameManager (`:25`, including its "persists between fights" comment), `reset_all`, the save dict and `load_profile`;
   - remove the writes in ShopScene.gd:320-321 (Max HP Increase keeps raising `player_hp_max`) and CombatScene.gd:1663 (the revive restart);
   - the v1 → v2 migration drops the key.

## Verification

- New MetaTests layer in RunAllTests, with a temp save path:
  - round-trip save/load equals the run, including shards, relic charges and deck id;
  - a corrupt profile keeps the default unlocks and is preserved as `.corrupt.json`;
  - a corrupt saved_decks file isn't wiped by the next `save_deck`;
  - an unknown card id is dropped with a warning;
  - a v1 fixture migrates. Use this machine's current `profile.json`: no version, `permanent_unlocks` with 31 entries, `run: null`.
- Manual: quit mid-run and reload. Shards and the enemy deck are unchanged.
- `tools/run_checks.sh` green. CLAUDE.md says "4 layers"; update it to 6.

## Related

- Do after 047, which adds the run seed and the deck-pick scheme.
- Pairs with roadmap H1 (`RunService`).

## Work log

- 2026-09-25: opened from the architecture review. Verified that the save dict lacks `void_shards` and that the corrupt path returns before `_ensure_default_unlocks`.
- 2026-09-30: re-verified at `3009a60` and rewritten.
  - `player_hp` is now an open owner decision: the design doc says HP persists, the code doesn't.
  - Added the SavedDecks wipe-on-parse-error bug, the immediate New Run save, the missed `reset_all` fields, the float casts and the const `SAVE_PATH`.
  - The deck id is saved alongside 047's run seed.
- 2026-09-30: owner decision: no HP carry-over. The design docs are updated; step 8 deletes `player_hp`.
- 2026-10-02: task 047 landed. `GameManager.current_deck_id` is gone; the picked deck is `current_enemy.deck_id` (EnemyData). `GameManager.run_seed` exists but isn't saved: UserProfile's load rolls a fresh one, so resume still re-rolls the deck (the owner question in the implementation order, P4). Saving `run_seed` alone restores the same deck, because the pick is a stateless hash of the run seed and the fight.

