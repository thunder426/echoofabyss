---
id: "078"
title: Show the cards a boss kill permanently unlocked
status: backlog
area: ui
priority: normal
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §H, the run layer; a new finding of unit H). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Boss kills permanently unlock support cards, but since v0.20 the game never tells the player which ones.

### What the code does

- `advance_node` (GameManager.gd:110-120) calls `grant_boss_unlocks(completed_act)` after every fight in `BOSS_INDICES` (:11, `[3, 6, 9, 15]`).
- `grant_boss_unlocks` (:164-205) rolls each eligible support-pool card for this hero and talents with `_UNLOCK_CHANCE` (:14-19). Each hit goes into `permanent_unlocks` and `last_boss_unlocks` (:204-205).
- The Act 1 boss can never unlock anything. `UserProfile._ensure_default_unlocks` (:125-134) unlocks every support card with `act_gate == 1` on every load, and the roll skips gates above the completed act (:200). So `_UNLOCK_CHANCE[1]` (0.60) never applies, and unlocks come only from the bosses at fights 6, 9 and 15.
- `last_boss_unlocks` is declared as "cards unlocked by the most recent boss kill; cleared after display" (:47), but nothing displays it. It is only cleared: by `grant_boss_unlocks` (:195), RelicRewardScene `_ready` (:15) and `UserProfile.reset_all` (:111).
- `git show 7c16a61` (Version 0.20) removed `_build_unlock_panel()` from RelicRewardScene. That panel listed `last_boss_unlocks` under "★  NEW CARDS PERMANENTLY UNLOCKED  ★". The clear was kept and the reveal was lost.

### Consequence

- After the bosses at fights 6 and 9 the screens are: RewardScene (CombatScene.gd:1609), then RelicRewardScene (RewardScene.gd:138-139). The boss card reward already draws from the new unlocks: `_build_boss_pool` filters on `permanent_unlocks` (RewardScene.gd:44-45, :72-73). So a newly unlocked card can be offered with nothing marking it as new.
- After the final boss (fight 15) the run ends in place. `_on_victory` calls `end_run(true)` and shows the "RUN COMPLETE!" panel (CombatScene.gd:1599-1607). RelicRewardScene is never shown, so Act 4 unlocks have no screen to appear on even if the old panel came back.
- The design doc is stale too. DESIGN_DOCUMENT.md §17 "Boss Drops (Permanent Unlocks)" (:651) describes rarity tiers, while the code rolls by `act_gate`. §20 (:915) says "If final boss (index 14): permanent unlock cards offered".

## Decision (owner, 2026-10-01)

QN4, "bring back a reveal": show the cards a boss kill permanently unlocked, on RelicRewardScene or on a short screen after the boss. `last_boss_unlocks` gets a reader (task 080 keeps the field).

## Proposed fix

1. **Reader.** Add `GameManager.take_boss_unlocks() -> Array[String]`. It returns a copy of `last_boss_unlocks` and clears the list, so each unlock is shown once.
2. **Reveal panel.** Add `ui/UnlockRevealPanel.gd`, a full-screen overlay Control built in code like the other meta screens:
   - `setup(card_ids: Array[String])` builds the header "New cards unlocked", one CardVisual per id (`apply_size_mode("reward")`; unknown ids are skipped) and a Continue button;
   - Continue frees the overlay and emits `closed`.
3. **Act bosses (fights 6 and 9; 3 has nothing to show today): show it on RewardScene entry.** This is the "short screen after the boss": it is the first screen after the kill, and the boss card reward drawn there already includes the new cards.
   - In `RewardScene._ready`, call `take_boss_unlocks()`. If the result isn't empty, add the overlay above the card row.
   - When `_reward_ids` is empty, `_build_card_phase_ui` calls `_finish()` at once (:119-121), which would skip the overlay. Defer that call until the overlay closes.
   - If the owner prefers RelicRewardScene (the pre-v0.20 location), use the same panel there instead; it then follows the boss card reward.
4. **Final boss (fight 15).** In the run-complete branch of `_on_victory` (CombatScene.gd:1599-1607), call `take_boss_unlocks()` and add the panel above `game_over_panel` when the result isn't empty. `end_run` has already saved `permanent_unlocks` through `clear_run()` (GameManager.gd:99), so only the display is missing.
5. **Delete the bare clear** in RelicRewardScene `_ready` (:15). The list is consumed in step 3, so the clear has nothing left to do.
6. **Not persisted.** `last_boss_unlocks` isn't saved. If the player quits between the boss and the reveal, the reveal is skipped but the cards stay unlocked. That is accepted; task 077 resumes the screen, not the list.
7. **Docs.** Rewrite DESIGN_DOCUMENT.md §17 "Boss Drops" (:651-658) to match the code: every boss in `BOSS_INDICES`, an `act_gate` ≤ the completed act, the chance per gate from `_UNLOCK_CHANCE`, act-1 cards unlocked by default, and the reveal. Fix §20's "index 14" line (:915).

## Verification

- **Reader probe.** Put it in MetaTests if task 052 has landed, otherwise in TriggerHandlerTests.gd beside `_korrath_hero_registered` (:2304). Save and restore the GameManager fields it sets.
  - Setup: `last_boss_unlocks = ["a", "b"]`.
  - `take_boss_unlocks()` returns both, and a second call returns `[]`.
- **Panel probe** (same layer; RunAllTests runs inside a SceneTree):
  - `UnlockRevealPanel.new()`, `setup([<two act-1 support card ids>, "no_such_card"])`: two CardVisuals are built, and the unknown id is skipped.
  - Pressing Continue emits `closed`.
- **Manual:**
  - After Reset All Progress (only the act-1 defaults unlocked), take a run to fight 6 (cheat panel) and win. The overlay lists the cards `grant_boss_unlocks` added, Continue reveals the card reward, and the fight-9 boss shows only its own unlocks.
  - Win fight 15 with locked act-4 cards for the hero: the run-complete panel shows the overlay.
  - A boss kill that unlocks nothing (fight 3) shows no overlay.
- `tools/run_checks.sh` green.
- Behaviour-neutral for combat: meta UI only. `grant_boss_unlocks` is unchanged, and BalanceSimBatch doesn't run it, so the balance fingerprint can't move.

## Related

- Related: task 080 (roadmap H4) — deletes dead GameManager fields but keeps `last_boss_unlocks`, which this task gives a reader.
- Related: task 123 (roadmap H1) — H1a's `RunService` victory bookkeeping can return the unlock list instead of keeping it in a GameManager field.
- Related: task 124 (roadmap H2) — derives `BOSS_INDICES` from EncounterTable. The reveal follows whatever list `advance_node` uses.
- Related: task 077 (continue a run) — resumes RewardScene. The unlock list isn't saved, so a resumed reward screen shows no reveal (step 6).
- Related: task 138 (roadmap J2) — MetaTests for boss unlocks; the reader probe moves there.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from unit H's new finding "last_boss_unlocks has been write-only since v0.20", with owner decision QN4. Re-checked at `404b51c`, including the v0.20 diff. Added the final-boss case (no RelicRewardScene after fight 15), that the Act 1 boss never unlocks anything (act-1 cards are unlocked by default), and the stale DESIGN_DOCUMENT boss-drop text.

## Summary

_(filled in at /task-done)_
