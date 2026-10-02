---
id: "075"
title: Shop core-unit services give Seris and Korrath Vael's Void Imp
status: backlog
area: meta
priority: normal
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §C; the C problem list names ShopScene's "expand_core_unit" adding `"void_imp"` for any hero). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Every hero is selectable (HeroSelectScene.gd:323 `if true:  # all heroes in HeroDatabase are selectable`). Two of the seven shop services were written for Lord Vael and are offered to every hero:

- **Expand Core Unit** (ShopScene.gd:37, cost 3, "Increase max Void Imp copies by 1 and add one to deck.") runs :323-328:
  ```gdscript
  GameManager.core_unit_limit += 1
  GameManager.player_deck.append("void_imp")
  ```
- **Core Unit Variant** (:38, cost 4, "Add the branch-appropriate Void Imp variant to deck.") runs `_grant_core_unit_variant` (:351-364). It checks three Vael talents (`imp_evolution`, `piercing_void`, `rune_caller`). Seris and Korrath own none of them, so the `else` branch (:359-362) adds a random `senior_void_imp`, `runic_void_imp` or `void_imp_wizard`.

Each hero has its own core unit: Void Imp, Grafted Fiend and Abyssal Knight (KORRATH_HERO_DESIGN:223, "Core unit" row). Each has a matching 4-copy passive: `void_imp_extra_copy` (HeroDatabase.gd:94), `grafted_affinity` (:129) and `iron_legion` (:161).

### Reachable today

Both services have `first_shop=false`, so they appear from shop 2 on (ShopScene.gd:65, :248-249). Each is one of the two drawn services with probability 2/7 per visit, and Refresh re-rolls.
- A Seris or Korrath player pays 3 shards for a Void Imp plus a cap raise on the wrong card, or 4 shards for a Vael-only imp variant.
- `_copy_cap` (:520-525) gives `void_imp` the `core_unit_limit` cap (4–6) for every hero (`if card_id == "void_imp": return GameManager.core_unit_limit`). So a Seris or Korrath deck can buy Void Imps up to 4–6 in the shop, while their deck builder caps Void Imp at 2: `_EXTRA_COPY_RULES` (DeckBuilderScene.gd:18-22) raises it only for `void_imp_extra_copy`.
- Their own core units stay at `COPY_CAP` 2 in the shop, although their deck builder allows 4. The shop does offer them: `grafted_fiend` and `abyssal_knight` are in `abyss_core` (CardDatabase.gd:3473).
- REWARD_SYSTEM_DESIGN.md:255-256 and the "Core Unit Variant per Branch" table (:258) describe both services with Vael's Void Imp only.

## Decision (owner, 2026-10-01)

QN2, "hero's own core unit": Expand Core Unit adds Grafted Fiend (Seris) or Abyssal Knight (Korrath) and raises that hero's core-unit cap. The Core Unit Variant service is hidden for heroes other than Vael until variants are designed. Roadmap C2 (task 101) later moves the core unit onto HeroData, so this task keeps the data local to the shop.

## Proposed fix

1. **Core-unit tables in ShopScene**, marked "moves to HeroData in task 101":
   ```gdscript
   const CORE_UNIT_BY_HERO := {"lord_vael": "void_imp", "seris": "grafted_fiend", "korrath": "abyssal_knight"}
   ## Branch T0 talent → imp variant. Only Vael has variants so far.
   const CORE_UNIT_VARIANTS_BY_HERO := {
   	"lord_vael": {"imp_evolution": "senior_void_imp", "piercing_void": "void_imp_wizard", "rune_caller": "runic_void_imp"},
   }
   ```
   Add `static func core_unit_id() -> String`, which returns `CORE_UNIT_BY_HERO.get(GameManager.current_hero, "")`. Keep today's talent precedence (imp_evolution, then piercing_void, then rune_caller, :353-358). Dictionaries keep insertion order, so iterate the inner table in that order.
2. **Expand Core Unit** appends `core_unit_id()` instead of `"void_imp"` (:327). Task 074's `service_available` also returns false when `core_unit_id()` is "" (a future hero with no core unit).
3. **`_copy_cap`** (:523) keys on `core_unit_id()` instead of `"void_imp"`. The hero's own core unit gets `core_unit_limit`. Void Imp for Seris and Korrath falls back to `COPY_CAP` 2, which matches their deck builder.
4. **Core Unit Variant.** `service_available` returns false when the hero has no entry in `CORE_UNIT_VARIANTS_BY_HERO`, which hides it for Seris and Korrath. Task 074's `core_unit_variant_id()` reads the table. Its no-talent fallback picks among the hero's variants that the deck doesn't hold yet.
5. **Service text names the hero's core unit.** Turn the two descriptions in `ALL_SERVICES` into templates and format them in `_add_service_slot` with the core unit's `card_name` (for example "Increase max Grafted Fiend copies by 1 and add one to deck.").
6. **Comment.** GameManager.gd:26-27 says `## Max copies of the core unit allowed in deck; starts at 4 for Lord Vael.` / `## Increased by special reward #4 (up to 6).` Change it to: the shop's copy cap for the current hero's core unit; starts at 4; Expand Core Unit raises it to at most 6.
7. **Docs.** Update REWARD_SYSTEM_DESIGN.md:255-256 and :258:
   - Expand Core Unit: raises the cap of the hero's core unit (Void Imp / Grafted Fiend / Abyssal Knight) by 1 and adds one copy;
   - Core Unit Variant: Lord Vael only, until other heroes have variants.
8. **Existing saves:** leave them as they are. A Seris or Korrath run that already holds extra Void Imps or a Vael variant keeps them; the cards still work.

## Verification

- **Probe.** Put it in MetaTests if task 052 has landed, otherwise in TriggerHandlerTests.gd beside `_korrath_hero_registered` (:2304). Save and restore the GameManager fields it sets.
  - For each of `lord_vael`, `seris` and `korrath` at `core_unit_limit = 4`: `service_available("expand_core_unit")` is true. After the grant the deck gains `CORE_UNIT_BY_HERO[hero]` and `core_unit_limit` is 5.
  - Seris and Korrath: `service_available("core_unit_variant")` is false. Vael with `rune_caller`: true, and the grant adds `runic_void_imp`.
  - `_copy_cap` (through a shop instance or a static wrapper): Seris `grafted_fiend` → `core_unit_limit`; Seris `void_imp` → 2; Vael `void_imp` → `core_unit_limit`.
  - Every card id in both tables resolves through `CardDatabase.get_card`.
- **Scene check** (task 074's awaited shop probe): for Seris, `core_unit_variant` is never in `_service_offers` across 50 `_populate_service_slots` calls.
- **Manual:** a Seris run through shops 2–4 with Refresh never offers Core Unit Variant. Expand Core Unit says Grafted Fiend and adds one.
- `tools/run_checks.sh` green.
- Behaviour-neutral for combat: shop only, no combat, sim or AI file changes, so the balance fingerprint can't move.

## Related

- Depends on: task 074 — this task extends its `service_available` and `core_unit_variant_id`, and both edit `_on_buy_service` and `_populate_service_slots`.
- Related: task 101 (roadmap C2) — moves `CORE_UNIT_BY_HERO` and the variant table onto HeroData, and replaces `_copy_cap` with one copy-cap rule for deck builder, shop and reward. It depends on this task.
- Related: task 100 (roadmap C1) — its `branch_for_talents()` can replace the talent-keyed variant lookup.
- Related: task 128 (roadmap H7) — the service weights (Expand Core Unit and Core Unit Variant both weigh 1).

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from unit C's straight-to-task bug "Shop core-unit services give Seris/Korrath Vael's Void Imp content". Re-checked at `404b51c`. The shard-wasting cases from the same report (Expand at the limit, an owned variant) are in task 074. Owner decision QN2 applied.

## Summary

_(filled in at /task-done)_
