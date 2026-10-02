---
id: "076"
title: Talent 'Undo Last Choice' after Abyss Convergence keeps its 2 Echo Runes; re-picking adds 2 more
status: backlog
area: meta
priority: normal
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §C, the hero/talent data model; this is C2 territory). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Picking the Rune Master capstone adds two cards to the run deck, and the talent screen's Undo doesn't take them back.

1. **The grant is hard-coded in `unlock_talent`** (GameManager.gd:223-226):
   ```gdscript
   # Capstone rewards: add cards to player deck
   if id == "abyss_convergence":
   	player_deck.append("echo_rune")
   	player_deck.append("echo_rune")
   ```
2. **The talent screen snapshots only talents and points.** `TalentSelectScene._ready` (:49-51) stores `_entry_talents` and `_entry_points`. `_on_revert_pressed` (:409-412) restores those two and nothing else:
   ```gdscript
   GameManager.unlocked_talents = _entry_talents.duplicate()
   GameManager.talent_points    = _entry_points
   ```
3. **The Undo button is shown** whenever a talent was picked on this screen (:332). Its label is "<- Undo Last Choice" (:108).

### Reachable today

- A Lord Vael Rune Master run gets 1 talent point at the start (GameManager.gd:89) and 1 more after each act's relic reward (RelicRewardScene.gd:157-158 `GameManager.add_talent_point()`). The 4th point arrives after the Act 3 boss. `abyss_convergence` is tier 3 and requires `ritual_surge` (TalentDatabase.gd:163-166), so it becomes clickable then.
- Pick it: the deck gains 2 Echo Runes. Press Undo: the talent and the point come back, but both Echo Runes stay. Pick it again: the deck has 4, twice the designed grant. Or pick another talent and keep 2 Echo Runes without the capstone.
- `echo_rune` is in no pool (CardDatabase.gd:3567 `# echo_rune: removed from pool — granted as capstone reward (abyss_convergence)`), so these are the only Echo Runes a player can get.

### Smaller issues found on the way

- The talent text (TalentDatabase.gd:165) doesn't mention the 2 Echo Runes, so the player isn't told about the grant.
- BalanceSimBatch copies the grant (debug/BalanceSimBatch.gd:231-233 `if "abyss_convergence" in talents: deck.append("echo_rune")` ×2), so sim and game can drift apart.
- The act gate `"echo_rune": 4` (CardDatabase.gd:3615) is dead: the card is in no pool, so nothing reads it. Task 100 (roadmap C1) deletes it in its phase 1.

## Proposed fix

1. **Make the grant data.** Add `grants_deck_cards: Array[String] = []` to TalentData (talents/TalentData.gd) and set it to `["echo_rune", "echo_rune"]` on `abyss_convergence` (TalentDatabase.gd:163-181). `unlock_talent` appends `TalentDatabase.get_talent(id).grants_deck_cards` instead of testing the id. This follows "who has what is decided by data" (owner decision Q2).
2. **One snapshot and revert on GameManager**, so it is testable without the scene:
   - `snapshot_talent_picks() -> Dictionary` returns `{talents, points, deck}` (duplicates);
   - `revert_talent_picks(snap: Dictionary)` restores all three.

   TalentSelectScene calls them in `_ready` and `_on_revert_pressed`. The talent screen changes nothing else in the deck, so restoring the whole deck is safe. At run start the deck is still empty (the deck builder comes after), and an empty deck restores to empty.
3. **BalanceSimBatch** (:231-233) reads `grants_deck_cards` for each talent in its config instead of the literal. Same cards, same order.
4. **Talent text.** Add the grant to the description, for example "Add 2 Echo Runes to your deck." Follow CARD_DESCRIPTION_STYLE.md. Card and talent text should say what the code does (as in owner decision QN1 for champions).
5. **The dead `echo_rune` act gate:** covered by task 100 (roadmap C1). Delete it here only if this task lands first.

## Verification

- **Probe.** Put it in MetaTests if task 052 has landed, otherwise in TriggerHandlerTests.gd beside `_korrath_hero_registered` (:2304). Save and restore `unlocked_talents`, `talent_points` and `player_deck` around it.
  - Setup: `unlocked_talents = ["rune_caller", "runic_attunement", "ritual_surge"]`, `talent_points = 1`, a 15-card deck with no `echo_rune`. Take `snap = GameManager.snapshot_talent_picks()`.
  - `unlock_talent("abyss_convergence")`: `player_deck.count("echo_rune") == 2`, and `talent_points == 0`.
  - `revert_talent_picks(snap)`: the count is 0, `talent_points == 1`, and `abyss_convergence` isn't unlocked.
  - Unlock it again: the count is exactly 2.
  - Data: `TalentDatabase.get_talent("abyss_convergence").grants_deck_cards == ["echo_rune", "echo_rune"]`, and every id in any talent's `grants_deck_cards` resolves through `CardDatabase.get_card`.
- **Manual:** edit `user://profile.json` to a Vael run at `run_node_index` 10 with `deck_built` true, `talent_points` 1 and `unlocked_talents` [rune_caller, runic_attunement, ritual_surge]. Continue opens the talent screen. Pick Abyss Convergence, press Undo, pick it again, then Continue and open the deck viewer from the encounter screen: exactly 2 Echo Runes (4 today). An unspent point sends EncounterLoadingScene back to the talent screen (:19-21), so the "Undo and keep nothing" case is covered by the probe.
- `tools/run_checks.sh` green.
- Behaviour-neutral. Step 3 moves BalanceSimBatch's grant to the data field with the same result: the seeded balance fingerprint (`BalanceSimBatch -- --act 4 --runs 200 --seed 7`, before and after; the capstone is in the Act 4 talent set, BalanceSimBatch.gd:53) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Related: task 100 (roadmap C1) — deletes the dead `echo_rune` act gate in its phase 1.
- Related: task 101 (roadmap C2) — hero and talent deck rules. `grants_deck_cards` is the talent-side counterpart of its HeroData deck rules.
- Related: task 138 (roadmap J2) — MetaTests for talents. Move this probe there if it landed in TriggerHandlerTests.
- Related: task 052 — creates the MetaTests layer.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from unit C's straight-to-task bug "Undo Last Choice after Abyss Convergence keeps its 2 Echo Runes". Re-checked the trace at `404b51c`, including reachability (4 points by Act 4) and that `echo_rune` is in no pool. Added the BalanceSimBatch copy and the missing talent text.

## Summary

_(filled in at /task-done)_
