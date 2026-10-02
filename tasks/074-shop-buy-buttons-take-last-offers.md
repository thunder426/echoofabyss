---
id: "074"
title: Shop: Buy buttons take the last offer's state after a purchase; Expand Core Unit at the 6-copy limit takes 3 shards and does nothing
status: backlog
area: meta
priority: high
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §H, the shop part of H1). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Two defects in `shop/ShopScene.gd`. Both are meta-only; no combat code is involved.

### 1. Every Buy button takes the last offer's state

`_update_remaining_buy_buttons` (:536-551) runs after every card purchase (:234), after every service purchase including Refresh (:333-334), and after the Card Removal cancel (:428). For each card wrapper it loops over all of `_card_offers` and writes the button on every pass. Nothing matches a wrapper to its own offer, and there is no `break`:

```gdscript
# Find matching offer
for offer in _card_offers:
	...
	btn.disabled = GameManager.void_shards < offer.cost or GameManager.player_deck.count(offer.card_id) >= _copy_cap(offer.card_id, card)
```

The last write wins, so every button gets the state of the last offer, which is the rightmost slot (slots are added in `_card_offers` order, :159-160). `_on_buy_card` (:227-234) frees the slot but never removes the bought offer from `_card_offers`, so a bought card still counts.

Reachable outcomes (any hero, shop 2 or later; a shop opens before each act boss, RewardScene.gd:140-142):
- **Buttons disabled for no reason.** The deck holds 1 copy of the rightmost card D. It is offered because 1 < `COPY_CAP` 2 (:14, :185). Buying D brings it to the cap, and the other three Buy buttons are disabled although the player can afford them.
- **A champion in the last slot.** Nyx'ael is a champion (CardDatabase.gd:2069 `nyx_ael.is_champion = true`) in `abyss_core` (:3462 `"nyx_ael": ["abyss_core"]`), so non-first shops offer it at `CHAMPION_COST` 4 (ShopScene.gd:13). Any purchase that leaves 2–3 shards disables every 2-shard card.
- **Over-cap purchase.** The deck holds 1 copy of card X in slot 1. Random Card (:340-349) can grant X, which reaches the cap. The refresh then enables X's button from the last offer's state. `_on_buy_card` checks only `spend_shards(cost)` (:228), not the cap, so X can be bought to 3 copies.
- **Right after Refresh.** `_populate_card_slots` builds four correct buttons (:221-223); :334 then overwrites all four with the last new offer's state.

The shop can't be re-entered (`_on_leave` :557-558), so nothing repairs the display. Two smaller gaps:
- removing a card through the Card Removal overlay (:409-415) never refreshes the buttons;
- service buttons are set once (:296) and never refreshed when the shard count changes.

### 2. Services that can't apply still take shards

`_on_buy_service` (:300-334) spends first and checks afterwards.

- **Expand Core Unit at the limit** (:323-328):
  ```gdscript
  if not GameManager.spend_shards(svc.cost): return
  if GameManager.core_unit_limit < 6:
  ```
  `core_unit_limit` starts at 4 (GameManager.gd:28, :86). After two purchases a third spends 3 shards and adds nothing. `_populate_service_slots` (:240-256) never filters on the limit, and Refresh (:306-309) re-rolls the services, so it can come up again in the same visit.
- **Core Unit Variant already owned** (:329-332 → `_grant_core_unit_variant` :351-364). A Vael with Endless Tide always gets `senior_void_imp` (:353-354). The add is skipped when it is already in the deck (`if GameManager.player_deck.count(variant_id) == 0:`, :363), so a second purchase after a Refresh or at a later shop spends 4 shards for nothing.
- **Second Wind while one is held** (:302-305). `has_revive` is a bool (GameManager.gd:30), consumed only on defeat (CombatScene.gd:1662). Buying it again while it's held spends 4 shards and changes nothing. It stays eligible in later shops and after a Refresh.

The last two are the same defect as Expand Core Unit (the shop offers and charges for a service that can't apply), so this task fixes them as well.

## Proposed fix

1. **Bind each Buy button to its offer.** In `_add_card_slot` (:191-225) store the button in the offer dictionary (`offer.btn = btn`; offers are `{card_id, cost}`, :53, :188). Bind the offer itself to `_on_buy_card` instead of `card_id, cost, wrapper`.
2. **One buyability rule.** Add `static func offer_buyable(cost: int, shards: int, deck_count: int, cap: int) -> bool` (`shards >= cost and deck_count < cap`). Use it in `_add_card_slot`, in the refresh and in `_on_buy_card`.
3. **`_on_buy_card`** re-checks `offer_buyable` before `spend_shards`, so a stale button can't buy over the cap. After the purchase it erases the offer from `_card_offers`.
4. **Replace `_update_remaining_buy_buttons`** with `_refresh_buy_buttons()`:
   - loop over `_card_offers` and set each offer's own button, skipping a freed one (`is_instance_valid(offer.btn)`);
   - refresh the service buttons in the same pass (keep `{svc, btn, bought}` per service slot; a bought one stays disabled);
   - call it after a Card Removal pick too (:409-415).
5. **Service availability.** Add `static func service_available(svc_id: String) -> bool`, reading GameManager:
   - `expand_core_unit`: false at `core_unit_limit >= 6`;
   - `core_unit_variant`: false when the variant it would grant is already in the deck. Split the choice out of `_grant_core_unit_variant` into `static func core_unit_variant_id() -> String`, which returns "" when the variant is owned and, in the no-talent fallback (:359-362), picks only among unowned variants. The check and the grant then agree;
   - `revive`: false while `has_revive` is true.

   Use it to filter `eligible` in `_populate_service_slots` (next to the first-shop check), in `_on_buy_service` before `spend_shards`, and in the button refresh.
6. **Out of scope:**
   - the service weights, Second Wind's first-shop flag and Max HP's price are task 128 (roadmap H7);
   - which core unit Expand Core Unit adds, and hiding the variant for Seris and Korrath, are task 075.

## Verification

- **`offer_buyable` table probe.** Put it in MetaTests if task 052 has landed, otherwise in TriggerHandlerTests.gd beside `_korrath_hero_registered` (:2304). Reach the static through `preload("res://shop/ShopScene.gd")`.
  - `(2, 5, 1, 2)` → true; `(2, 5, 2, 2)` → false; `(4, 3, 0, 1)` → false; `(2, 2, 0, 2)` → true.
- **`service_available` probe** (same layer; save and restore the GameManager fields it sets):
  - `core_unit_limit = 6` → `expand_core_unit` false; `5` → true;
  - `has_revive = true` → `revive` false;
  - a Vael with `imp_evolution` who owns `senior_void_imp` → `core_unit_variant` false.
- **Scene probe.** It needs an awaited layer: MetaTests, or ScenarioTests.gd, which RunAllTests awaits.
  - Setup: set `UserProfile.saving_disabled = true`. Seed GameManager with Vael, 6 shards, a deck with 1× D and the default `permanent_unlocks`. Add `shop/ShopScene.tscn` to the tree and await a frame for the deferred `_build_ui`.
  - Replace the offers with [A, B, C, D] (cost 2 each) through `_card_offers` + `_add_card_slot`, and buy D. Expect: A, B and C's buttons are enabled, and D's offer is gone.
  - With a 4-cost champion offer last and 3 shards, the 2-cost buttons stay enabled and the champion's is disabled.
  - Append X to the deck up to its cap (what Random Card can do), refresh, then call the buy for X's offer. Expect: shards and deck unchanged.
  - With `core_unit_limit = 6`, `expand_core_unit` is never in `_service_offers` across 50 `_populate_service_slots` calls, and `_on_buy_service` for it leaves shards and deck unchanged.
- **Manual:** play to shop 2 without buying in shop 1 (7 shards; the cheat panel can't grant shards, and saves don't keep them until task 052). Buy cards, use Refresh and cancel a Card Removal: after each step every button matches its own card (enabled when affordable and under the cap).
- `tools/run_checks.sh` green.
- Behaviour-neutral for combat: shop UI only, no combat, sim or AI file changes. BalanceSimBatch never runs the shop, so the balance fingerprint can't move.

## Related

- Related: task 075 (shop core-unit services) — makes Expand Core Unit hero-aware and hides the variant for Seris and Korrath; it builds on `service_available` and depends on this task.
- Related: task 128 (roadmap H7) — the weighted service draw, no Second Wind in the first shop, Max HP at 4, first shop from run position. It depends on this task and should weight the `eligible` list that `service_available` filters.
- Related: task 123 (roadmap H1) — H1b moves `offer_buyable` and `service_available` into `RunService` (`can_buy`).
- Related: task 101 (roadmap C2) — one copy-cap rule replaces `_copy_cap` (:520-525).
- Related: task 138 (roadmap J2) — MetaTests for shop pools and purchases.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from the straight-to-task bugs of units H and C (H bugs 1 and 3, C bug 1). Re-checked every line at `404b51c`. Added two cases of the same "charges for a service that can't apply" defect: an owned Core Unit Variant and a second Second Wind.

## Summary

_(filled in at /task-done)_
