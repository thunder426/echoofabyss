---
id: "124"
title: Derive act sizes, fight count and boss indices from EncounterTable; every act boss shows the BOSS label
status: backlog
area: meta
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item H2 (`design/refactors/ARCHITECTURE_ROADMAP.md` §H), plus the BOSS-label question the verification raised (QN6). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The run is 15 fights in 4 acts. `EncounterTable` defines the 15 encounters, but it has no act or boss data. The structure is written by hand in several other places, and nothing checks that they agree.

### The copies

- **GameManager.gd** has four constants, not three:
  - :7 `const ACT_SIZES: Array[int] = [3, 3, 3, 6]`
  - :8 `const TOTAL_ACTS  := 4` (only reader: MapScene.gd:24, a dead scene)
  - :9 `const TOTAL_FIGHTS := 15` (not derived from `ACT_SIZES`)
  - :11 `const BOSS_INDICES: Array[int] = [3, 6, 9, 15]`
  - Comments repeat the values: :6, :10, :111 (`# Detect act boss BEFORE incrementing (boss indices: 3, 6, 9, 15).`) and :237 (`# Encounters — 4 acts (3 + 3 + 3 + 6 = 15 fights)`).
  - Readers inside GameManager: `advance_node` (:110-120), `is_run_complete` (:122-123), `is_act_complete` (:127-133), `get_current_act` / `get_completed_act` (:136-141), `is_boss_fight` (:144-145) and the private `_act_for_index` (:148-154).
- **CombatScene.gd:206** `fight_label.text = "Fight %d / %d" % [GameManager.run_node_index, GameManager.TOTAL_FIGHTS]`, and **:1596** `var _shard_amount := 3 if GameManager.run_node_index in GameManager.BOSS_INDICES else 1`.
- **RewardScene.gd:45** picks the boss card pool with `prev_fight in GameManager.BOSS_INDICES`, and **:140** routes to the shop with `elif GameManager.run_node_index in GameManager.BOSS_INDICES:`.
- **EncounterLoadingScene.gd:126** calls the private `GameManager._act_for_index(idx)`, and **:129-130** re-sum `GameManager.ACT_SIZES[i]` to get the fight number within the act.
- **CheatPanel.gd:352** `const ACT_SIZES := [3, 3, 3, 6]`, **:353** `for i in range(1, 16):`, and **:357-363** re-implement `_act_for_index`.
- **debug/BalanceSimBatch.gd:92-97** `const _ACT_FIGHTS: Dictionary = { 1: [1, 2, 3], 2: [4, 5, 6], 3: [7, 8, 9], 4: [10, 11, 12, 13, 14, 15] }`, read at :189-200.
- **debug/BalanceSim.gd:13-22** `_FIGHT_OPTIONS` carries `"act": 1` / `"act": 2` per fight (debug only, Acts 1–2).
- **map/MapScene.gd:24, :47, :50, :71** (dead; task 080 deletes the scene).

EncounterTable.gd:12-148 has `"index"` on every entry, so the fight count can be derived. Acts and bosses can't: there are no `act` or `boss` keys, and the titles are no substitute (entries 12–14 also have name titles, e.g. :116 `"title": "VOID CAPTAIN"`).

### What depends on them

Shards (CombatScene.gd:1596), the shop before each boss (RewardScene.gd:140), the relic reward after each act (`is_act_complete`, RewardScene.gd:138), the boss card pool (RewardScene.gd:45) and the boss unlock roll (`advance_node`, GameManager.gd:112-120) all key off `BOSS_INDICES` and `ACT_SIZES`. Moving or adding a fight means editing every copy; a missed one silently mis-routes the run. The balance batch's act lists can drift from the live run.

### The BOSS label

GameManager.gd:143-145:

```gdscript
## True when the current encounter is the final boss.
func is_boss_fight() -> bool:
	return run_node_index == TOTAL_FIGHTS
```

Its only caller is EnemyHeroPanel.gd:180, `var prefix: String = "⚔ BOSS  " if GameManager.is_boss_fight() else ""`. So only the Abyss Sovereign gets the prefix. Imp Matriarch (3), Corrupted Handler (6) and Void Herald (9) show none, although every other boss rule treats them as bosses.

## Decision (owner, 2026-10-01)

QN6: "**Act bosses too.** Every act boss (fights 3, 6, 9 and 15) shows the BOSS prefix; is_boss_fight() covers all boss indices (derive from EncounterTable, H2)."

**Note on fight 12.** The grooming question listed fight 12 as an act boss by mistake. Fight 12 (Void Captain) is not one: it isn't in `BOSS_INDICES` (GameManager.gd:11) or in DESIGN_DOCUMENT.md §17's act table, where Act 4's boss is 15. The owner's answer was "act bosses too", which means exactly the boss indices 3, 6, 9 and 15. Settled on 2026-10-01; nothing left to confirm.

## Proposed fix

1. **EncounterTable data.** Add `"act": n` to all 15 entries, and `"boss": true` to entries 3, 6, 9 and 15 (absent means false).
2. **EncounterTable helpers** (static, typed reads from the untyped entries, e.g. `var a: int = e["act"]`):
   - `fight_count() -> int`, `act_count() -> int`;
   - `act_of(index: int) -> int`, with the same fallbacks as `_act_for_index`: below 1 → 1, past the last fight → the last act (`get_current_act` runs at index 16 after the final win);
   - `fights_in_act(act: int) -> Array[int]`, `first_index_of_act(act: int) -> int`, `is_last_fight_of_act(index: int) -> bool`;
   - `is_act_boss(index: int) -> bool`, `boss_indices() -> Array[int]`.
3. **GameManager.**
   - Delete `ACT_SIZES`, `TOTAL_FIGHTS`, `BOSS_INDICES`, and `TOTAL_ACTS` unless task 080 already removed it.
   - `advance_node`: `EncounterTable.is_act_boss(run_node_index)`, `EncounterTable.act_of(run_node_index)`, `run_node_index <= EncounterTable.fight_count()`.
   - `is_run_complete`: `run_node_index > EncounterTable.fight_count()`.
   - `is_act_complete`: `EncounterTable.is_last_fight_of_act(run_node_index - 1)` (true at 4, 7, 10 and 16, as today). Keep acts and bosses as separate data; the content probe below checks they agree.
   - `get_current_act` / `get_completed_act` call `EncounterTable.act_of`. Delete `_act_for_index`.
   - `is_boss_fight()` returns `EncounterTable.is_act_boss(run_node_index)`; its doc comment says "an act boss (3, 6, 9, 15)". Keep the name: task 103 copies it into `CombatConfig.enemy_is_boss`. EnemyHeroPanel.gd:180 needs no change.
   - Fix the comments at :6, :10, :111 and :237.
4. **Callers.**
   - CombatScene.gd:206 → `EncounterTable.fight_count()`. :1596 → `GameManager.is_boss_fight()` (it runs before `advance_node` at :1598, so `run_node_index` is still the fight just won).
   - RewardScene.gd:45 → `EncounterTable.is_act_boss(GameManager.run_node_index - 1)`; :140 → `EncounterTable.is_act_boss(GameManager.run_node_index)`.
   - EncounterLoadingScene.gd:125-131 → `act_of(idx)` and `idx - first_index_of_act(act) + 1`.
   - CheatPanel.gd:352-363: delete the local const, loop `range(1, EncounterTable.fight_count() + 1)`, label with `EncounterTable.act_of(i)`.
   - MapScene, if task 080 hasn't deleted it yet.
5. **Balance tooling.** Replace BalanceSimBatch.gd's `const _ACT_FIGHTS` (:92-97) with `static func _act_fights() -> Dictionary` built from `fights_in_act(a)` for each act, and update the reads at :189-200 (a const can't call EncounterTable). BalanceSim.gd's `_FIGHT_OPTIONS` `"act"` field can stay (debug, Acts 1–2) or use `act_of`.
6. **Docs.** ARCHITECTURE.md:241 (EncounterTable paragraph): entries carry `act` and `boss`; GameManager derives the run structure from the table. DESIGN_DOCUMENT.md §17's act table (:643-649) already matches.

## Verification

- **Content probe** (ContentTests if task 104 has landed, otherwise ScenarioTests):
  - `fight_count() == 15`, `act_count() == 4`;
  - `fights_in_act(1..4)` equal `[1, 2, 3]`, `[4, 5, 6]`, `[7, 8, 9]`, `[10, 11, 12, 13, 14, 15]`;
  - `boss_indices() == [3, 6, 9, 15]`; every act has exactly one boss, and it is the act's last fight;
  - indices run 1..15 without gaps, and `act` never decreases;
  - for i in 0..16, `act_of(i)` equals the old `_act_for_index(i)`. Inline the old `ACT_SIZES` loop in the test as the oracle.
- **GameManager walk probe** (MetaTests if task 052 has landed, otherwise ScenarioTests). Save and restore `run_node_index`, `current_enemy`, `current_deck_id`, `permanent_unlocks` and `last_boss_unlocks` (`advance_node` rolls boss unlocks).
  - `is_boss_fight()` is true exactly at `run_node_index` 3, 6, 9 and 15.
  - From `run_node_index = 1`, call `advance_node()` 15 times. `is_act_complete()` is true exactly at 4, 7, 10 and 16, with `get_completed_act()` 1, 2, 3 and 4 there; `is_run_complete()` only at 16.
- **Manual:** fight 3 shows "⚔ BOSS  IMP MATRIARCH" and "Fight 3 / 15"; the shop opens before fight 3 and the relic screen after it; fight 4 has no prefix. The cheat panel lists "A1-1: Rogue Imp Pack" through "A4-15: Abyss Sovereign".
- `tools/run_checks.sh` green.
- Behaviour-neutral for combat and the sim: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` and `--act 4`, which exercise the derived act lists) diffs empty (design/TESTING.md "Refactor / extraction work"). The only visible change is the BOSS prefix on fights 3, 6 and 9.

## Related

- Related: task 080 (roadmap H4) — deletes MapScene and `TOTAL_ACTS`; either task deletes the constant.
- Related: task 103 (roadmap C5) — copies `is_boss_fight()` into `CombatConfig.enemy_is_boss`, so the label follows this task whichever lands first.
- Related: task 053 — edits other CheatPanel lines (the F12 / C label); whichever lands second rebases.
- Related: task 123 (roadmap H1) — RunService reads these helpers instead of the constants; it depends on this task.
- Related: task 125 (roadmap H3) — adds a `phase2` spec to EncounterTable entry 15; independent edits to the same table.
- Related: task 078 — its DESIGN_DOCUMENT §17 boss-drop text says "every boss in `BOSS_INDICES`"; after this task, `EncounterTable.boss_indices()`.
- Related: task 104 (roadmap D1) — adds the ContentTests layer the content probe belongs in.
- Related: task 138 (roadmap J2) — MetaTests for run progression; the walk probe moves there.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item H2 and owner decision QN6. Re-checked at `404b51c`: four constants, not three; added the BalanceSimBatch, BalanceSim and EncounterLoadingScene copies; `is_boss_fight()` keeps its name and covers every boss index. Flagged the "12" in the QN6 wording for the owner.

## Summary

_(filled in at /task-done)_
