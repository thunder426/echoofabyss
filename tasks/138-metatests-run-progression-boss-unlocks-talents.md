---
id: "138"
title: MetaTests: run progression, boss unlocks, talents, relic offers; then reward/shop pools and deck-builder rules
status: backlog
area: tooling
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item J2 (`design/refactors/ARCHITECTURE_ROADMAP.md` §J). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Run rules have no tests. `grep -rlE 'advance_node|is_act_complete|grant_boss_unlocks|unlock_talent|get_offer_for_act|RelicDatabase|SavedDecks|DeckBuilder|RewardScene|ShopScene' debug/tests/*.gd` finds nothing. The only GameManager calls in tests are CommandTests.gd:748 (`GameManager._build_encounter`) and the LiveSmoke / Parity fight setup.

### What is untested

**Run progression** (shared/scripts/GameManager.gd):
- :7 `const ACT_SIZES: Array[int] = [3, 3, 3, 6]`, :9 `const TOTAL_FIGHTS := 15`, :11 `const BOSS_INDICES: Array[int] = [3, 6, 9, 15]`.
- `advance_node` (:110-120) detects the act boss before incrementing (:112 `var act_boss_completed: bool = run_node_index in BOSS_INDICES`) and calls `grant_boss_unlocks` after (:119-120).
- `is_run_complete` (:122-123), `is_act_complete` (:127-133, true at 4, 7, 10 and 16), `get_current_act` / `get_completed_act` (:136-141), `is_boss_fight` (:144-145, true only at 15).

**Boss unlocks** (`grant_boss_unlocks`, :164-205):
- candidates per hero: the common pool plus the branch pools of taken T0 talents (:168-192);
- skips ids already in `permanent_unlocks` (:197-198) and cards with `act_gate == 0` or above the act (:200-201);
- rolls `if randf() < chance:` (:203) with the per-gate chances at :14-19, and fills `last_boss_unlocks`.

**Talents** (`unlock_talent`, :214-226): refuses with no points (:215-217) or a duplicate (:218-220), spends a point, and `abyss_convergence` appends 2 `echo_rune` to the deck (:224-226).

**Relic offers** (relics/RelicDatabase.gd:21-30, `get_offer_for_act`): filters `r.act == act`, `pool.shuffle()` (:26, global RNG), returns the first 2. Each act registers 4 relics (:61).

**Reward, shop and deck-builder rules**, all scene instance methods that read GameManager directly:
- rewards/RewardScene.gd: `_pick_card_rewards` (:42; copy cap `COPY_CAP := 2`, :12, applied at :51), `_build_normal_pool` (:58), `_build_boss_pool` (:70, falls back to the core pools), `_get_active_support_pool_ids` (:86);
- shop/ShopScene.gd: `_get_branch_pool` (:437, slots 1–2, :152-157), `_get_full_pool` (:473), `_copy_cap` (:520);
- ui/DeckBuilderScene.gd: `MAX_DECK_SIZE := 15` (:8), the copy caps (:9-11), `_copy_limit_for` (:25), `_deck_builder_pools` (:67), `_on_add_card` (:652-656).

### Why now

Task 124 (roadmap H2) derives the act constants, task 123 (roadmap H1) moves the run rules into a RunService, task 100 (roadmap C1) rewrites the pool lookups, and task 128 (roadmap H7) changes the shop rules. All of them rewrite this logic with no safety net. An off-by-one in an act boundary or a wrong pool would only show up in a manual run.

### Who owns what

- **Task 052** owns the save/load tests (round-trip, corrupt files, migration, SavedDecks). It also creates the MetaTests layer, `RunState` and the overridable `SAVE_PATH`.
- **Tasks 100 and 101** own the table-level probes: the `support_pools` golden table and the Collection groups (100), and the `DeckRules.copy_cap` table (101).
- **This task** covers the run rules themselves, plus the consumers of those tables (reward, shop, deck builder).

## Decision (owner, 2026-10-01)

- Q5: "the hero's common pool (vael / seris / korrath) is offered alongside the unlocked branch pools", and the Collection shows every hero's cards. Phase b's shop probe encodes the first half; the Collection probe is task 100's.
- QN6: "is_boss_fight() covers all boss indices". Task 124 makes that change.

## Proposed fix

### Phase a (after task 052)

1. **Test fixture.** A MetaTests helper that:
   - snapshots every run field (052's `RunState.to_dict()`), plus `permanent_unlocks`, `last_boss_unlocks` and `current_hero`, and restores them afterwards;
   - sets `UserProfile.saving_disabled = true`;
   - calls `seed(n)` for the paths that still use the global RNG (the relic shuffle, and the deck pick until task 047's run seed lands).
2. **Injectable unlock roll.** Replace `randf()` at GameManager.gd:203 with `unlock_roll.call()`, where `var unlock_roll: Callable = func() -> float: return randf()`. The calls happen in the same order, so this is behaviour-neutral. Tests set the roll to return 1.0 (nothing unlocks) or 0.0 (every eligible card unlocks), and can count calls. Tasks 078 and 100 also edit `grant_boss_unlocks`; rebase on whichever lands first. If task 123 (roadmap H1) has moved the roll into RunService with an injected rng, use that instead of adding the Callable.
3. **Progression probe.** `start_new_run()`, roll returning 1.0 with a call counter, then `advance_node()` 15 times. Assert:
   - `is_act_complete()` is true exactly at `run_node_index` 4, 7, 10 and 16, with `get_completed_act()` 1, 2, 3 and 4 there;
   - `get_current_act()` for each index;
   - `is_run_complete()` only at 16;
   - the roll is called (so `grant_boss_unlocks` ran) exactly when leaving fights 3, 6, 9 and 15;
   - `is_boss_fight()`: true only at 15 today, and at every boss index once task 124 lands (QN6). Whichever of the two lands second updates the assertion.

   Task 124's GameManager walk probe is the same probe. If it landed in ScenarioTests, move it here with its labels unchanged.
4. **Boss-unlock probes.** Roll returns 0.0; `permanent_unlocks` cleared.
   - For each hero (`lord_vael`, `seris`, `korrath`) with no talents, `last_boss_unlocks` equals the hero's common-pool cards with `1 <= act_gate <= act`, for act 1 and act 4.
   - One T0 talent (`rune_caller`, `corrupt_flesh`, `iron_formation`) adds that branch's pool; another hero's T0 talent adds nothing.
   - Ids already in `permanent_unlocks` are skipped and not added twice. `act_gate == 0` cards never roll.
   - Compute the expected sets in the test from `CardDatabase.get_card_ids_in_pools` and `act_gate`, not from literal lists. After task 100, use `HeroDatabase.support_pools`.
5. **Talent probes.**
   - `unlock_talent` spends a point and appends the id.
   - With 0 points, or with a duplicate, it changes nothing. These paths call `push_error`; run_checks.sh fails only on `SCRIPT ERROR`.
   - `abyss_convergence` appends 2 `echo_rune` to `player_deck`.
   - Task 076's undo probe moves here if it landed elsewhere.
6. **Relic offer probe.** For acts 1–4 (seeded): 2 distinct relics, all with `r.act == act`. Acts 0 and 5: empty.

### Phase b (after tasks 100 and 101)

If task 123 (roadmap H1) has landed, target its RunService instead of the scenes in this phase.

7. **Make the pool builders callable without a scene.** If task 123 hasn't landed, extract `RewardScene._build_normal_pool` / `_build_boss_pool`, `ShopScene._get_branch_pool` / `_get_full_pool` and DeckBuilderScene's add rule into static functions that take `(hero_id, talents, permanent_unlocks, deck)`. The scene methods become one-line wrappers, which keeps this behaviour-neutral. Task 123 later moves the functions; it doesn't rewrite them.
8. **Reward probes.**
   - The normal pool is the core pools (minus the variant core units and champions) plus the unlocked cards of `support_pools(hero, talents)`.
   - The boss pool is the unlocked support cards only, and falls back to the core pools when there are none.
   - A card already at the cap (2) in the deck is never offered.
9. **Shop probes (Q5).**
   - Slots 1–2 draw from the hero's common pool plus the unlocked branch pools, after task 100 drops the fallback-only rule.
   - The full pool is core plus unlocked support cards. Variant core units are excluded.
10. **Deck-builder probes.**
    - Adding a card beyond `DeckRules.copy_cap(hero, card, BUILDER, …)` (task 101) is refused, and so is a 16th card.
    - A card outside the hero's `deck_pool_ids` isn't in the builder inventory.
11. **Collect the meta probes** that tasks 074, 075, 077, 078 and 128 file elsewhere, most of them beside `_korrath_hero_registered` in TriggerHandlerTests.gd (shop buttons and `offer_buyable` / `service_available`, `core_unit_id` / `_copy_cap`, continue-run routing, the boss-unlock reveal, the shop rules). Move them here with their labels unchanged.
12. **Docs:** a MetaTests section in TESTING.md listing these probes.

## Verification

- `tools/run_checks.sh` green with the new MetaTests probes.
- The tests don't touch `user://`: `profile.json`'s mtime is unchanged after a run.
- Each probe fails when its rule is flipped locally, e.g. `BOSS_INDICES = [3, 6, 10, 15]`, or `card.act_gate > act_number` changed to `>=`. Record this in the summary, then revert.
- Manual: the first card reward and the first shop of a new Vael run look as before (phase b's extraction).
- Behaviour-neutral: tests, the injectable roll and a wrapper extraction. No combat, sim or AI code changes, and BalanceSimBatch reads neither pools nor GameManager's run fields, so the balance fingerprint can't move; no BalanceSimBatch run needed.

## Related

- Depends on: task 052 — creates the MetaTests layer, `RunState` (the fixture's snapshot) and the overridable `SAVE_PATH`, and owns the save/load tests.
- Depends on: task 100 (roadmap C1) — `HeroDatabase.support_pools` and the Q5 shop change, which phase b's pool probes target.
- Depends on: task 101 (roadmap C2) — `DeckRules.copy_cap` and `HeroData.deck_pool_ids`, which the deck-builder probes use.
- Related: task 124 (roadmap H2) — derives the act constants and changes `is_boss_fight()` (QN6); its walk probe moves here.
- Related: task 123 (roadmap H1) — RunService; once it lands, the probes target it.
- Related: task 047 — `advance_node` calls `get_encounter`, whose deck pick moves to a run seed.
- Related: tasks 074, 075, 076, 077, 078 and 128 (roadmap H7) — meta bug fixes whose probes move here.
- Related: task 137 (roadmap J1) — lint L15 checks that MetaTests is registered in RunAllTests.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item J2. Re-checked at `404b51c`: no test references the run rules; the reward, shop and deck-builder rules are scene instance methods. Save/load stays with task 052, and the table probes stay with tasks 100 and 101.

## Summary

_(filled in at /task-done)_
