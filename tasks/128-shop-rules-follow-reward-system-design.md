---
id: "128"
title: Shop rules follow REWARD_SYSTEM_DESIGN: weighted services, no Second Wind in the first shop, Max HP costs 4, first shop from run position
status: backlog
area: meta
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item H7 (split out of H1 by grooming; `design/refactors/ARCHITECTURE_ROADMAP.md` §H), plus the straight-to-task bug "first shop offers Second Wind" found while grooming (unit C). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The shop code and `design/REWARD_SYSTEM_DESIGN.md` §5 disagree on four rules.

### 1. Second Wind in the first shop (reachable in every run)

- Fights 1 and 2 pay 1 shard each (CombatScene.gd:1596), so the player reaches the shop before fight 3 with exactly 2 shards.
- `_is_first_shop = GameManager.void_shards <= 2` (ShopScene.gd:65) is true, and `_populate_service_slots` keeps only services with `first_shop` set (:248-249). That leaves three:
  ```gdscript
  {id="revive",       name="Second Wind",  ... cost=4, first_shop=true },   # :32
  {id="refresh_shop", name="Refresh Shop", ... cost=1, first_shop=true },   # :33
  {id="random_card",  name="Random Card",  ... cost=1, first_shop=true },   # :34
  ```
- It shows two of them (`eligible.shuffle()` / `_service_offers = eligible.slice(0, 2)`, :252-253), so Second Wind is offered with probability 2/3. Its button is disabled (`btn.disabled = GameManager.void_shards < svc.cost`, :296; 2 < 4), so one of the two service slots is dead.
- The design: "Second Wind | 4 Shards | 3 | ❌" (REWARD_SYSTEM_DESIGN.md:237); "Items costing more than 2 Shards are removed from the first shop entirely" (:284); the first shop's services are Refresh Shop and Random Card (:290-292).
- History: v0.34 (`acccbf3`) replaced HP Restoration (cost 1, `first_shop=true`) with this service at cost 4 and kept `first_shop=true`.

### 2. The service draw is uniform

ShopScene.gd:252-253 shuffles the eligible list and takes the first two. The design weights the seven services (:234-244): Card Removal 3, Second Wind 3, Refresh Shop 3, Random Card 3, Max HP Increase 2, Expand Core Unit 1, Add Core Unit Variant 1, total 16, which gives the per-slot odds 19 / 19 / 19 / 19 / 12 / 6 / 6 % (:269-279).

### 3. Max HP Increase costs 2

ShopScene.gd:36 `{id="max_hp", ... cost=2, first_shop=false}`; the design says "Max HP Increase | 4 Shards" (:240). The same v0.34 commit lowered it from 4 to 2; the design doc (imported in v0.592) kept 4.

### 4. The first shop is detected by the shard count

ShopScene.gd:65 `_is_first_shop = GameManager.void_shards <= 2`. The design defines the first shop by position: "Shop 1 (before Act 1 boss) | 2" (:179); "Player arrives with exactly 2 Shards" (:284). The shard test matches only while the economy runs exactly as the table predicts:
- `void_shards` isn't saved (the run dict, UserProfile.gd:26-38, has no such key) and `load_profile` doesn't set it. After relaunching the game mid-run the count restarts at 0, so the next shop can be entered with 2 shards or fewer and is treated as the first: no champions (:182-183) and first-shop services only (:248-249).
- Once task 077 lets Continue resume a pending shop, a resumed shop opens with 0 shards (until task 052 saves them) and gets the first-shop rules.

## Decision (owner, 2026-10-01)

QN3: "**Design doc wins.** Weighted service draw 3/3/3/3/2/1/1, no Second Wind in the first shop, Max HP Increase costs 4; first shop derived from run position, not shards."

## Proposed fix

1. **Service data** (`ALL_SERVICES`, ShopScene.gd:31-39):
   - add `weight` to every entry: revive 3, refresh_shop 3, random_card 3, card_removal 3, max_hp 2, expand_core_unit 1, core_unit_variant 1;
   - `revive`: `first_shop=false`;
   - `max_hp`: `cost=4`. The button label reads `svc.cost` (:294), so it follows.
2. **Weighted draw.** Add `static func draw_services(eligible: Array[Dictionary], count: int, rng: RandomNumberGenerator) -> Array[Dictionary]`: for each slot, roll `rng.randi_range(1, total)` over the remaining services' weights, take the one hit and remove it, so the offers stay distinct. `_populate_service_slots` calls it on the list that the first-shop check, task 074's `service_available` and task 075's hero filter leave; their weights renormalise. ShopScene keeps one `RandomNumberGenerator` per visit (`randomize()` in `_ready`); task 123 later seeds it from the run seed.
3. **First shop from run position.** Add `static func is_first_shop(run_node_index: int) -> bool`, true when `run_node_index` is the first boss index: `GameManager.BOSS_INDICES[0]` today, `EncounterTable.boss_indices()[0]` once task 124 lands. The shop opens only when the next fight is an act boss (RewardScene.gd:140), and RewardScene has already advanced `run_node_index`, so the first shop is the one at index 3. `_ready` (:65) uses it instead of the shard count. The champion filter (:182-183) and the service filter (:248-249) follow.
4. **Guard against a repeat.** Keep `first_shop` explicit (the design table is the source), and add a probe that every `first_shop` service costs at most 2, the first shop's budget (:284).
5. **Docs.** REWARD_SYSTEM_DESIGN.md already describes the target. Add one line under "First Shop Restrictions" (:283): the first shop is the one before the Act 1 boss, detected by run position, not by the shard count.
6. **Existing runs:** a run that already bought Max HP at 2 keeps it.

## Verification

- **Draw probe.** In MetaTests if task 052 has landed, otherwise in TriggerHandlerTests.gd beside `_korrath_hero_registered` (:2304), reaching the statics through `preload("res://shop/ShopScene.gd")`:
  - with a seeded `RandomNumberGenerator`, 10,000 calls of `draw_services(ALL_SERVICES, 1, rng)` give each service within ±1.5 percentage points of weight / 16 (18.75 % ×4, 12.5 %, 6.25 % ×2);
  - with `count = 2`, the two offers are always different;
  - the same seed gives the same offers.
- **Rule probe:** `is_first_shop(3)` is true; `is_first_shop(6)`, `(9)` and `(15)` are false. The first-shop-eligible services are exactly `refresh_shop` and `random_card`, every `first_shop` service costs at most 2, `max_hp` costs 4 and `revive` is not `first_shop`.
- **Scene probe** (task 074's awaited shop probe): `run_node_index = 3`, `void_shards = 2` → `_service_offers` is {Refresh Shop, Random Card} across 50 `_populate_service_slots` calls. `run_node_index = 6`, `void_shards = 1` → `_is_first_shop` is false.
- **Manual:** start a run, win fights 1–2, open the first shop and use Refresh: the services are always Refresh Shop and Random Card. At shop 2, Max HP Increase costs 4 Shards.
- `tools/run_checks.sh` green.
- Behaviour change, meta layer only (service odds, one price, the first shop's services). BalanceSimBatch never runs the shop (CombatSim plays single fights from preset decks), so there is no sim delta to record; the summary lists the player-facing changes instead.

## Related

- Depends on: task 074 — adds `service_available` and the per-offer button refresh; this task weights the list `service_available` filters, and both edit `ALL_SERVICES` and `_populate_service_slots`.
- Related: task 075 — hides Core Unit Variant for Seris and Korrath and changes Expand Core Unit; both weigh 1 here.
- Related: task 123 (roadmap H1) — H1b moves `draw_services`, `is_first_shop` and the service table into RunService, with an rng seeded from the run seed.
- Related: task 077 — Continue resumes a pending shop; with this task a resumed shop isn't mistaken for the first.
- Related: task 052 — saves `void_shards`; no longer needed for first-shop detection.
- Related: task 124 (roadmap H2) — `EncounterTable.boss_indices()` replaces `GameManager.BOSS_INDICES[0]`.
- Related: task 138 (roadmap J2) — MetaTests for the shop; the probes move there.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item H7 and unit C's straight-to-task bug "first shop offers Second Wind". Re-checked at `404b51c`, including the v0.34 history of both the Second Wind flag and the Max HP price. Owner decision QN3 applied.

## Summary

_(filled in at /task-done)_
