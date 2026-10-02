---
id: "123"
title: RunService: run rules (victory/defeat bookkeeping, rewards, relics, shop purchases) out of UI scenes into a headless-testable service
status: backlog
area: meta
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item H1 (`design/refactors/ARCHITECTURE_ROADMAP.md` §H). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Run rules live in UI scenes and in the GameManager autoload, and the scenes write GameManager directly. No run rule can be tested without a scene, and every new reward, service, hero or route edits a scene.

### Where the rules are

- **72 direct GameManager writes in 12 non-debug files.** Regex over `*.gd`, excluding GameManager.gd, `debug/` and comment lines: assignments, `.append` / `.remove_at` / `.erase` / `.clear` / `.assign` on GameManager fields, and calls to `spend_shards`, `earn_shards`, `advance_node`, `end_run`, `start_new_run`, `add_talent_point` and `unlock_talent`. UserProfile 26 (save/load, task 052), ShopScene 18, CombatScene 7, CheatPanel 5, HeroSelectScene 3, RelicRewardScene 3, TalentSelectScene 3, DeckBuilderScene 2, CombatConfig 2, MainMenu 1, RewardScene 1, MapScene 1.
- **Victory** (`CombatScene._on_victory`, :1587-1609):
  ```gdscript
  var _shard_amount := 3 if GameManager.run_node_index in GameManager.BOSS_INDICES else 1
  GameManager.earn_shards(_shard_amount)
  GameManager.advance_node()
  if GameManager.is_run_complete():
  	GameManager.end_run(true)
  ```
  then `GameManager.go_to_scene.call_deferred("res://rewards/RewardScene.tscn")` (:1609).
- **Defeat and revive.** `_on_defeat` (:1611-1630) checks `GameManager.has_revive` and sets `state._pending_revive` (:1623), or calls `GameManager.end_run(false)` (:1625). `_on_restart_pressed` (:1659-1665) consumes it (`GameManager.has_revive = false`, :1662).
- **Routing after a card reward** (`RewardScene._finish`, :137-144): RelicRewardScene if `is_act_complete()`, ShopScene if `run_node_index in GameManager.BOSS_INDICES`, otherwise EncounterLoadingScene.
- **Relic reward** (RelicRewardScene.gd:148-159): a relic pick appends to `player_relics` (:149), an upgrade writes `relic_bonus_charges` (:153-154), and `_proceed` grants the talent point and changes scene (:157-159).
- **Boss unlocks** (`GameManager.grant_boss_unlocks`, :164-205): its own hero → pool mapping (:168-192) and a global `randf()` roll (:203).
- **Shop** (shop/ShopScene.gd): offers (:147-225 cards, :240-298 services), purchases inline (`_on_buy_card` :227-234, `_on_buy_service` :300-334), the Card Removal refund as a literal (`GameManager.earn_shards(3)  # card_removal cost is 3`, :424), the copy cap (`_copy_cap`, :520-525) and two more pool mappings (`_get_branch_pool` :437, `_get_full_pool` :473).
- **Card rewards** (RewardScene.gd:42-112): boss or normal pool, the copy cap and a fourth pool mapping (`_get_active_support_pool_ids`, :86-112).
- **Rule constants copied** between the two scenes: `COPY_CAP` (RewardScene.gd:12, ShopScene.gd:14), `VARIANT_CORE_UNITS` (RewardScene.gd:15-19, ShopScene.gd:23-25), `CORE_POOL_NAMES` (RewardScene.gd:22, ShopScene.gd:28).
- **Global RNG** in run rules: GameManager.gd:203 `randf()`; RewardScene.gd:46, ShopScene.gd:164, :252, :342, :361 and RelicDatabase.gd:26 `shuffle()`.

### Consequence

- Nothing tests `advance_node`, `is_act_complete`, `grant_boss_unlocks`, the shop or the reward rules (roadmap J lists them as zero coverage). Grooming found meta bugs nobody had noticed: the shop's Buy buttons (task 074), Second Wind in the first shop (task 128), Vael's core unit sold to Seris and Korrath (task 075), Continue skipping a pending reward (task 077) and boss unlocks never shown (task 078).
- A fourth hero or a new service adds more scene-level copies.
- The run's random choices can't be reproduced from a seed, so they can't be tested deterministically.

## Proposed fix

1. **`shared/scripts/RunService.gd`**: `class_name RunService extends RefCounted`, static functions over task 052's `RunState`.
   - Every random choice takes an injected `RandomNumberGenerator`. Live seeds it from task 047's `run_seed` with a stateless mix per use, e.g. `hash([run_seed, run_node_index, "shop", refresh_count])`, the same scheme 047 uses for the deck pick, so a display call can't advance it.
   - Permanent unlocks come in as a parameter; they are profile state, not run state.
   - No scene, node or autoload access. Functions return what happened (a small result dictionary or typed class), and the scene presents it.
   - Add RunService.gd to lint L2's `RNG_FILES` (tools/lint/lint_engine.py:142-148), so a global `randf()` or `shuffle()` can't come back. Shuffle with a small rng-driven helper.
2. **GameManager** keeps thin wrappers (`advance_node`, `grant_boss_unlocks`, `is_act_complete`, …) that call RunService on its RunState until every caller has moved; then delete them. Update the `GameManager.start_new_run()` calls in LiveSmokeTests.gd:235 and ParityTests.gd:188 if it moves.
3. **Scenes keep layout and input only.** They call RunService and present its result.
4. **Out of scope:** hero select, the deck builder and talent picks (task 076 adds talent snapshot / revert helpers), and the save format (task 052).
5. **Docs:** ARCHITECTURE.md file finder (:37) and GameManager row (:48) name RunService; the Shop row (:299) points at both files; the scene flow (task 080 rewrites it) says routing is RunService's. TESTING.md lists the MetaTests probes.

## Phases

Each phase is independently shippable with its own gate run. Open a sub-task per phase when starting, as LIVE_SIM_UNIFICATION_PLAN did.

### H1a — progression bookkeeping and routing (about 1–2 days)

- `record_victory(run, rng, unlocks)`: shards (3 for an act boss through task 124's `EncounterTable.is_act_boss`, otherwise 1), advance the node, roll the boss unlocks (moved from `grant_boss_unlocks`, pools from task 100's `HeroDatabase.support_pools`), and report run complete.
- `record_defeat(run)` → revive offered or run over; `consume_revive(run)`.
- `next_scene_after_reward(run) -> String`: the routing in `RewardScene._finish`.
- `complete_relic_reward(run, choice)`: a relic pick or +1 charge, then +1 talent point.
- If tasks 077 and 078 have landed, move `continue_route` / the resume-screen bookkeeping and `take_boss_unlocks` here too; `record_victory`'s result carries the new unlocks.
- Post-combat routing has one transition outside `GameManager.go_to_scene`: EncounterLoadingScene loads CombatScene threaded and calls `change_scene_to_packed` itself (EncounterLoadingScene.gd:236-253). Routing that hooks only `go_to_scene` never sees it.
- Callers: CombatScene.gd:1595-1609, :1611-1630, :1659-1665; `RewardScene._finish`; RelicRewardScene.gd:148-159; MainMenu's Continue.

### H1b — shop (about 2 days)

- `shop_offers(run, rng, unlocks)` → card and service offers; `can_buy(run, offer)`; `buy_card`; `buy_service`, which refuses a service that can't apply; `refund(run, svc_id)` from the service's own cost, replacing the literal 3 at :424; one copy-cap call (task 101's rule if it has landed).
- It moves task 074's `offer_buyable` / `service_available`, task 075's core-unit table (or task 101's HeroData fields) and task 128's `draw_services` / `is_first_shop`. Land this phase after tasks 074, 075 and 128, so it moves fixed code instead of re-fixing it.
- ShopScene binds each button to its offer and asks `RunService.can_buy`.

### H1c — card rewards (about 1 day)

- `card_reward_offers(run, rng, unlocks) -> Array[String]` and `pick_reward(run, card_id)`. The boss pool after an act boss, otherwise the normal pool; never a card at its cap, a variant core unit or a champion.
- `COPY_CAP`, `VARIANT_CORE_UNITS` and `CORE_POOL_NAMES` exist once (or in task 101's deck rules). `RelicDatabase.get_offer_for_act` takes the rng too.

## Verification

- **MetaTests** (the layer task 052 creates, with its temp save path):
  - **Walk.** A fresh run and 15 `record_victory` calls with no spending: 23 shards in total (11 × 1 + 4 × 3). `next_scene_after_reward` is ShopScene after fights 2, 5, 8 and 14, RelicRewardScene after 3, 6 and 9, and EncounterLoadingScene otherwise. Run complete after fight 15 only. Boss unlocks are rolled for acts 1–4, after fights 3, 6, 9 and 15.
  - **Defeat.** With `has_revive`: revive is offered once, and after `consume_revive` it is false. Without it: run over, run inactive.
  - **Relic.** A relic pick appends the relic and adds a talent point; an upgrade adds one charge and a talent point.
  - **Shop.** Buying at the cap is refused; buying with too few shards is refused; Expand Core Unit at `core_unit_limit` 6 is refused without a charge; cancelling Card Removal refunds exactly its cost; the first-shop rules apply at the first shop only, whatever the shard count.
  - **Rewards.** Offers never include a card at its cap, a variant core unit or a champion.
  - **Determinism.** The same `run_seed` and run state give the same shop offers, reward offers, relic offers and boss unlocks.
- LiveSmoke reaches `_on_victory` / `_on_defeat` through the presenter (CombatPresenter.gd:242-246), so it covers the CombatScene hooks.
- **Manual:** New Run → fights 1–2 → shop → fight 3 → card reward → relic → talents → fight 4; a defeat with Second Wind; ESC → Main Menu → Continue from each post-combat screen.
- `tools/run_checks.sh` green, with RunService.gd in L2's scope.
- Behaviour-neutral for combat and the sim: no engine, sim or AI code changes, and BalanceSimBatch never runs the run layer, so the seeded balance fingerprint (`BalanceSimBatch -- --act 1 --runs 200 --seed 7`, before and after) diffs empty (design/TESTING.md "Refactor / extraction work"). The meta layer's random choices change source (a seeded rng instead of the global one): same distributions, different sequences. Note it in each phase's summary.

## Related

- Depends on: task 052 — `RunState`, the object RunService operates on, and the MetaTests layer its tests go in.
- Depends on: task 124 (roadmap H2) — `EncounterTable.is_act_boss` / `act_of` replace `BOSS_INDICES` / `ACT_SIZES` in the rules this task moves.
- Depends on: task 100 (roadmap C1) — `HeroDatabase.support_pools` replaces the four pool-mapping copies (GameManager, RewardScene, ShopScene ×2) the unlock, shop and reward rules read.
- Related: task 047 — adds `run_seed`, which seeds RunService's rng. With the stateless mix, a run resumed through Continue repeats its shop and reward offers instead of re-rolling them for free (task 077 notes today's free re-roll); whether that is wanted is task 052's save-scum question.
- Related: task 074, task 075 and task 128 (roadmap H7) — shop fixes that H1b moves; land them first.
- Related: task 077 — `continue_route` moves here in H1a.
- Related: task 078 — the boss-unlock reveal; `record_victory` returns the unlocks it shows.
- Related: task 101 (roadmap C2) — one copy-cap rule for the deck builder, shop and reward.
- Related: task 080 (roadmap H4) — rewrites ARCHITECTURE.md's scene flow; update it again after H1a.
- Related: task 138 (roadmap J2) — MetaTests for run progression, boss unlocks and relic offers; its probes target RunService once this lands. If 138 lands first, its phase b extracts the reward / shop / deck-builder pool builders into static functions; H1b / H1c then move those functions instead of rewriting them.
- Related: task 076 — talent undo; talent picks stay outside RunService for now.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item H1. Re-checked at `404b51c`: the 72 writes in 12 files, every cited range, and the global RNG sites (added RelicDatabase.gd:26). The shop's rule differences from REWARD_SYSTEM_DESIGN went to task 128 (H7); the meta bugs grooming found went to tasks 074, 075, 077 and 078.

## Summary

_(filled in at /task-done)_
