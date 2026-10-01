---
id: "047"
title: Move enemy decks from user:// into the repo
status: backlog
area: content
priority: high
started:
finished:
---

## Description

Found in the 2026-09-25 architecture review (issue 1 of 9). Re-verified 2026-09-30 at `3009a60`. Line numbers are from that commit.

All enemy deck data lives only in `user://encounter_decks.json` (`EncounterDecks.SAVE_PATH`, `enemies/data/EncounterDecks.gd:23`). **There is no copy in git.** On the dev Mac the file is `~/Library/Application Support/Godot/app_userdata/Echo of Abyss/encounter_decks.json` (8581 B, mtime 2026-04-29, CRLF line endings). It holds:
- 23 decks. Pools F1–F15: F1–F3 have 3 decks each, F4 has 2, F5–F15 have 1.
- 7 per-deck `ai_profile` overrides.
- `limited: ["void_wind"]` on f8_a–f11_a.
- `f15_p2`, the Sovereign phase-2 deck, which is in no pool.

Readers:
- **Live:** `GameManager.get_encounter` (`GameManager.gd:244-260`), called from `start_new_run` (:88), `advance_node` (:117), `UserProfile.gd:85` (load) and `CheatPanel.gd:354` / `:373`.
- **Rules code:** `PhaseTransition.gd:70` (`SOVEREIGN_P2_DECK_ID`, :19). The file's `ai_profile` for f15_p2 is ignored; phase 2 hard-codes its profile at :20.
- **Sim and balance:** `BalanceSimBatch.gd:256-278`, `BalanceSim.gd:267`, `:600`, `:603`, `DebugSingleSim.gd:13-14`, `DebugF13LossAnalysis.gd:34-35`.
- **Tests:** Parity (through `get_encounter`, `ParityTests.gd:195`), `ScenarioTests.gd:77-78` and `:127`, `LiveSmokeTests.gd:237`.
- **Legacy:** `MapScene.gd:63`, `:136`. MapScene is no longer in the scene flow.
- **Writer:** `debug/EnemyDeckBuilder` is a runtime debug scene opened from `BalanceSim.gd:256`, not an editor tool. It writes through `EncounterDecks.save_deck` / `add_to_pool` / `set_deck_profile` → `save_data`.

What breaks without the file (fresh clone, another machine, an exported build):
- **It fails silently.** `load_data()` returns `{"pools": {}, "decks": {}}` with no message when the file is missing (:30-31), won't open (:33-34), won't parse (:36-37) or isn't a dict (:46). `save_data` also fails silently (:49-51).
- **Live** falls back to `CombatConfig.FALLBACK_ENEMY_DECK` (`CombatConfig.gd:12`, applied at :60). The F15 phase-2 deck is empty, and the variant AI profiles can't be reached.
- **The sim has no fallback** and gets `[]`. BalanceSimBatch logs `push_warning` and skips every fight (:257-259).
- **The gate fails.** `ScenarioTests.gd:127-128` asserts that `f1_a` is non-empty. Parity's engine run gets `[]` while live gets the fallback deck, so the two diverge.
- **Balance numbers depend on one machine's file.**

Deck pick: `EncounterDecks.gd:134` and `:142` use the global `randi()`, not the engine RNG. Lint L2's scope (`tools/lint/lint_engine.py:140-147`) doesn't include `enemies/data/`, so it never flags these calls. Parity and LiveSmoke work around this by calling `seed()` before `get_encounter` (ParityTests:185-187, LiveSmokeTests:200-203).

Existing data-loss bug: `save_deck` (:160-174) and `set_deck_profile` (:177-186) drop a deck's `limited` field. Editing F8–F11 in the builder strips `void_wind`. Once the file is in git, that becomes a silent content regression.

## Decision (owner, 2026-09-30)

- **The Mac copy is canonical.** Every test and balance run on this machine has read it since April. A byte-identical backup, with the timestamp kept, is at `~/Documents/Personal/echoofabyss_backup/encounter_decks_2026-09-30.json`.

## Proposed fix

1. ~~Back up the current file.~~ Done 2026-09-30 (see Decision).
2. Commit the Mac copy as `res://enemies/data/encounter_decks.json` with LF endings, and make it the only source `EncounterDecks.load_data()` reads.
   - Drop the user:// layer. A stale local file would shadow the repo copy and keep results machine-dependent.
   - Delete the local file after the move.
3. Point EnemyDeckBuilder's writes at the res:// file. This works in editor runs only, because res:// is read-only in an export. Fix `save_deck` / `set_deck_profile` so they keep `limited`.
4. Make a missing or unparseable file loud with `push_error`. The gate greps only `SCRIPT ERROR`, so the step 6 test is what actually catches it.
5. Make the deck pick reproducible from a seed:
   - Add a run seed (`GameManager.run_seed`), set in `start_new_run` before its `get_encounter(1)`.
   - Pick without stored RNG state, e.g. index = `hash([run_seed, encounter_index]) % pool.size()`.
   - Don't use `next_combat_seed`: it is -1 until combat start (`CombatConfig.gd:63-66`), which is after the deck is picked.
   - Don't use a stateful run RNG either: `get_encounter` is also called for display (CheatPanel loops all 15 fights), which would advance it.
   - Parity and LiveSmoke set the run seed instead of calling `seed()`.
   - Replace `BalanceSim.gd:603`'s `pick_random`.
   - Add `EncounterDecks.gd` to L2's `RNG_FILES`.
6. Content test, in ScenarioTests or a new check:
   - every pool F1–F15 is non-empty;
   - every deck card id and every `limited` id is in `CardDatabase.get_all_card_ids()` (`get_card` calls `push_error` on unknown ids, so don't probe with it);
   - every `ai_profile` passes `ProfileRegistry.has_profile("enemy", id)` (`make()` silently falls back to "default");
   - `PhaseTransition.SOVEREIGN_P2_DECK_ID` resolves to a non-empty deck.
7. Optional: cache the parsed file. `load_data()` re-reads and parses it on every query: 4 times per `get_encounter`, plus once inside rules code at the F15 transition. `save_data` clears the cache.
8. Docs: `ARCHITECTURE.md:32` and `:241`, the `EncounterDecks.gd:6` header comment, `TESTING.md`.

## Verification

- With no user:// file present: live, sim, Parity, ScenarioTests and BalanceSimBatch all get real decks.
- `tools/run_checks.sh` green.
- BalanceSimBatch:
  - Steps 1–4 change nothing. On this machine the sim already reads this exact file, so a byte-identical move is neutral.
  - Step 5 changes which variant BalanceSim.gd and live play pick. BalanceSimBatch iterates every variant, so it should stay unchanged.
  - Parity and LiveSmoke stay green but may exercise different variants. Record that.
- First export: check the JSON is packed. Godot 4 should include `.json` files. No export preset exists yet; task 053 decides on one.

## Related

- 052 saves the chosen deck id and the run seed with the run. Do 047 first.
- Roadmap H3 would move the phase-2 deck spec into `EncounterTable`.

## Work log

- 2026-09-25: opened from the architecture review. Verified: no `encounter_decks.json` in `git ls-files`; `load_data()` returns empty pools when the file is missing.
- 2026-09-30: re-verified at `3009a60` and rewritten.
  - Without the file the gate fails (ScenarioTests, Parity) and the sim skips fights. It does not silently pass.
  - `next_combat_seed` can't seed the pick; replaced with a run seed and a stateless pick.
  - EnemyDeckBuilder is a runtime debug scene, not an editor tool.
  - Completed the reader list.
  - Added the `limited`-field data-loss bug.
  - Extended the test to `limited` ids and f15_p2.
- 2026-09-30: owner decision: the Mac copy is canonical. Backed it up outside user://.
