---
id: "101"
title: HeroData carries deck rules: core unit, extra-copy rules, base pools, hero skills; one copy-cap rule for deck builder / shop / reward
status: backlog
area: meta
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item C2 (`design/refactors/ARCHITECTURE_ROADMAP.md` §C, direction 2: "HeroData gains core unit, copy rules, deck-builder pools, hero skills and the resource-bar widget id"). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Per-hero deck rules are constants in three scenes. Each channel (deck builder, shop, reward) has its own copy, and they disagree.

### Copy caps

- **Deck builder** (ui/DeckBuilderScene.gd): `_EXTRA_COPY_RULES` (:18-22) maps a hero passive to a card, and `_copy_limit_for` (:25-40) gives that card `MAX_COPIES_EXTRA` 4:
  ```gdscript
  {"passive_id": "void_imp_extra_copy", "match": {"kind": "card_id", "id": "void_imp"}},
  {"passive_id": "grafted_affinity",    "match": {"kind": "card_id", "id": "grafted_fiend"}},
  {"passive_id": "iron_legion",         "match": {"kind": "card_id", "id": "abyssal_knight"}},
  ```
  The `"tag"` match kind (:37-39) has no user (all three rules match by card id).
- **Shop** (shop/ShopScene.gd:520-525): `_copy_cap` gives `void_imp` the `GameManager.core_unit_limit` cap (4–6) for every hero. Task 075 changes this to the hero's own core unit, from a table it keeps in ShopScene.
- **Reward** (rewards/RewardScene.gd:12, :51): `COPY_CAP := 2` for every card, so a reward never offers a 3rd copy of any core unit.

The three passives that grant 4 copies (`void_imp_extra_copy` HeroDatabase.gd:94, `grafted_affinity` :129, `iron_legion` :161) say what they grant only in their description text.

### Base pools

Every hero gets Abyss Order cards, from three constants:
- `DECK_BUILDER_POOLS_BASE: Array[String] = ["abyss_core", "neutral_core"]` (DeckBuilderScene.gd:57), plus `DECK_BUILDER_POOLS_BY_HERO` (:61-64: `seris_core`, `korrath_core`);
- `CORE_POOL_NAMES: Array[String] = ["abyss_core", "neutral_core"]` in RewardScene (:22) and ShopScene (:28).

The designed 4th hero can't be expressed: "Dagan can only use **neutral cards**. He cannot access Abyss Order cards." (design/DAGAN_HERO_DESIGN.md:37).

### Core-unit variants

- The three Vael imp variants are listed twice: `VARIANT_CORE_UNITS` in RewardScene (:15-19) and ShopScene (:23-25).
- They are in no pool (`sed -n 3459,3594p cards/data/CardDatabase.gd | grep -c 'senior_void_imp\|runic_void_imp\|void_imp_wizard'` → 0). So the seven `not in VARIANT_CORE_UNITS` checks can never match: RewardScene :61, :64, :73, :77 and ShopScene :467, :479, :511.
- The one live use is the Core Unit Variant fallback (ShopScene.gd:360). Task 075 replaces it with its own table.

### Hero skills

Seris has two activated skills. Nothing lists which skills a hero has:
- the engine hard-codes the ids: `_cmd_hero_skill` (combat/board/CombatState.gd:2870) `not (skill_id in ["seris_corrupt", "soul_forge"])`;
- the UI hard-codes the buttons, their costs and texts: SerisResourceBar.gd:31 `_FORGE_BTN_FLESH_COST := 3`, :70-80 (`"Spend %d Flesh: Summon a Grafted Fiend."`, `"Spend 1 Flesh: Apply Corruption to a friendly Demon. Once per turn."`);
- the sim profile uses literals: SerisPlayerProfile.gd:119 `agent.hero_skill("seris_corrupt", best)`, :128.

Both skills are granted by talents, not by the hero: `_soul_forge_activate` (:757 `if not _has_talent("soul_forge")`) and `_seris_corrupt_apply` (:1082 `if not _has_talent("corrupt_flesh")`).

### Not needed: a resource-bar widget id

The roadmap also lists a "resource-bar widget id". The widgets are already picked by data ids: PipBar.gd:194 (`fleshbind` passive), :198 and SerisResourceBar.gd:47-48 (`soul_forge` / `corrupt_flesh` talents). That is what owner decision Q2 asks for. Their only defect is that they read GameManager, which is task 103.

### Consequence

- Adding a hero means editing constants in three scenes, and the channels drift: before task 075, a Seris deck could buy Void Imps up to 4–6 in the shop while its deck builder capped them at 2.
- Dagan would be offered Abyss Order cards in the deck builder, rewards and shop.
- A UI or agent that wants "this hero's skills" has to copy the literals again.

## Decision (owner, 2026-10-01)

- QN2, "hero's own core unit": Expand Core Unit adds Grafted Fiend (Seris) or Abyssal Knight (Korrath) and raises that hero's core-unit cap; Core Unit Variant is hidden for heroes other than Vael until variants are designed. Task 075 ships this with tables local to ShopScene. This task moves the data onto HeroData.
- Q2: who has what is decided by data and config. So the extra-copy rule sits on the passive, and skills sit in a data table, not in `if hero == ...` code.

## Proposed fix

1. **New HeroData fields**, set in each `_register_*` of HeroDatabase.gd:
   - `core_unit_id: String`: `void_imp`, `grafted_fiend`, `abyssal_knight`.
   - `core_unit_variants: Dictionary` (branch id → card id). Vael: `{"swarm": "senior_void_imp", "void_bolt": "void_imp_wizard", "rune_master": "runic_void_imp"}`. Seris and Korrath: `{}`, which keeps Core Unit Variant hidden (QN2).
   - `deck_pool_ids: Array[String]`: Vael `[abyss_core, neutral_core]`, Seris `[abyss_core, neutral_core, seris_core]`, Korrath `[abyss_core, neutral_core, korrath_core]`.
   - `acquire_core_pool_ids: Array[String]`: `[abyss_core, neutral_core]` for all three (the reward and shop core pool).
   - `skills: Array[HeroSkill]` (step 5).
2. **Replace task 075's ShopScene tables** (`CORE_UNIT_BY_HERO`, `CORE_UNIT_VARIANTS_BY_HERO`) with HeroData reads. With a committed branch (`HeroDatabase.branch_for_talents(hero_id, talents)`, task 100, not null), the variant is `hero.core_unit_variants.get(branch.id, "")`. With none, keep task 075's fallback: a random variant from the hero's table that the deck doesn't hold yet. A player commits to one branch, so today's talent precedence (ShopScene.gd:353-358) no longer matters. Task 074's `service_available` / `core_unit_variant_id` read the same fields.
3. **The extra-copy rule moves onto the passive.** Add `HeroPassive.extra_copy_card: String` and set it on `void_imp_extra_copy`, `grafted_affinity` and `iron_legion`. Delete `_EXTRA_COPY_RULES` (DeckBuilderScene.gd:18-22) and its unused tag match.
4. **One copy-cap rule.** Add `heroes/DeckRules.gd` with `static func copy_cap(hero_id: String, card: CardData, channel: int, core_unit_limit: int) -> int`, with channel constants BUILDER, SHOP and REWARD. It keeps today's values (after task 075):

   | Card | Builder | Shop | Reward |
   |---|---|---|---|
   | champion | 1 | 1 | 1 |
   | the hero's core unit | 4 | `core_unit_limit` | 2 |
   | anything else | 2 | 2 | 2 |

   The builder column keys on the passives' `extra_copy_card`, the shop column on `core_unit_id`. Both name the same card for all three heroes today; keep them separate so a hero can have a core unit without a 4-copy passive.
   It replaces `DeckBuilderScene._copy_limit_for` (:25-40), `ShopScene._copy_cap` (:520-525) and RewardScene's `COPY_CAP` (:12, :51). Rewards already filter out champions (`_is_champion`, :81-83), so the reward row changes nothing.
5. **Hero skills as data.** Add `heroes/HeroSkill.gd` (Resource): `id` (the engine skill id), `talent_id` (the talent that grants it; "" = always), `description`, `target` ("" or "friendly_demon"). Seris gets `soul_forge` (talent `soul_forge`, "Spend 3 Flesh: Summon a Grafted Fiend.") and `seris_corrupt` (talent `corrupt_flesh`, target `friendly_demon`, "Spend 1 Flesh: Apply Corruption to a friendly Demon. Once per turn."). Add `HeroDatabase.skills_for(hero_id: String, talents: Array[String]) -> Array[HeroSkill]`.
   - SerisResourceBar builds its buttons from `skills_for(...)` and takes the tooltip text from the records. The per-skill press handlers stay as they are. Task 103 makes `maybe_create` take the fight's talents; whichever lands second passes the skill list instead.
   - The engine stays as it is here. Task 097 (roadmap B3) makes `cmd_hero_skill` look skills up from the side's hero module; it can check ids against this table. Agents listing skills through CombatAgent is task 122 (roadmap G7).
6. **Base pools.** `DeckBuilderScene._deck_builder_pools()` (:67) returns `hero.deck_pool_ids`; delete `DECK_BUILDER_POOLS_BASE` and `DECK_BUILDER_POOLS_BY_HERO`. RewardScene and ShopScene read `hero.acquire_core_pool_ids`; delete both `CORE_POOL_NAMES`. `CORE_FILL_POOL` (:46-52) stays: the fill loop already skips cards outside the hero's pools (`_card_in_builder_pools`, :221). Fix its comment to say so.
7. **Delete both `VARIANT_CORE_UNITS` constants and the seven dead checks.** Task 100's structural probe already asserts the variants stay pool-less; add that every value of every `core_unit_variants` is pool-less too.
8. **Docs.**
   - `design/REWARD_SYSTEM_DESIGN.md` §2 "Max Copy Limit" (:59-63): add the core-unit rows from the table in step 4.
   - `design/master_doc/ARCHITECTURE.md` :282 (the HeroData row is stale: "deck (starter card ids), passive_talents"): list the deck-rule fields; add `DeckRules.gd` and `HeroSkill.gd` rows.
   - `GameManager.core_unit_limit`'s comment is task 075's; task 052 moves the field into `RunState`.

## Verification

- **Copy-cap table probe.** In MetaTests if task 052 has landed, otherwise in debug/tests/TriggerHandlerTests.gd next to `_korrath_hero_registered` (:2304):
  - `(lord_vael, void_imp, BUILDER)` → 4; `(seris, grafted_fiend, BUILDER)` → 4; `(korrath, abyssal_knight, BUILDER)` → 4;
  - `(seris, void_imp, BUILDER)` → 2;
  - `(any hero, nyx_ael, any channel)` → 1;
  - `(lord_vael, void_imp, REWARD)` → 2;
  - `(lord_vael, void_imp, SHOP, limit 5)` → 5; `(seris, grafted_fiend, SHOP, limit 5)` → 5; `(seris, void_imp, SHOP, limit 5)` → 2.
- **Data probe:**
  - `get_hero(h).deck_pool_ids` equals today's `DECK_BUILDER_POOLS_BASE` + `DECK_BUILDER_POOLS_BY_HERO` result for all three heroes (write the expected arrays out);
  - `core_unit_id` and `core_unit_variants` match the values in step 1; every id in them resolves through `CardDatabase.get_card`; every `core_unit_variants` key is one of the hero's `talent_branch_ids`;
  - each extra-copy passive's `extra_copy_card` resolves.
- **Skills probe:** `skills_for("seris", [])` is empty; `skills_for("seris", ["soul_forge"])` ids == `["soul_forge"]`; `skills_for("seris", ["corrupt_flesh"])` ids == `["seris_corrupt"]`; `skills_for("lord_vael", ["soul_forge"])` is empty. Every `HeroSkill.talent_id` resolves in TalentDatabase with the same `hero_id`.
- Task 075's probe keeps passing once it reads HeroData instead of the ShopScene tables.
- **Manual:** the Seris deck builder still allows 4 Grafted Fiends and Korrath's 4 Abyssal Knights; a Seris shop never offers a 3rd Void Imp; the Seris skill buttons show the same icons and tooltips.
- `tools/run_checks.sh` green.
- Behaviour-neutral for combat: deck builder, shop, reward and one UI bar; no combat, sim or AI file changes, so the balance fingerprint can't move. Parity builds its decks with `PresetDecks.get_cards` (ParityTests.gd:190), not the deck builder.

## Related

- Depends on: task 100 — `HeroDatabase.branch_for_talents` picks the variant by committed branch, and its structural probe covers the variants' pools.
- Depends on: task 075 — applies QN2 with tables local to ShopScene; this task moves them onto HeroData.
- Related: task 074 — its `service_available` and `core_unit_variant_id` read the new fields.
- Related: task 097 (roadmap B3) — engine dispatch of hero skills from the side's hero module; can validate against `HeroData.skills`.
- Related: task 103 (roadmap C5) — changes `SerisResourceBar.maybe_create` to take the fight's talents; coordinate the signature.
- Related: task 122 (roadmap G7) — agents read the game only through CombatAgent; a skill list belongs there.
- Related: task 076 — `TalentData.grants_deck_cards` is the talent-side counterpart of these hero deck rules.
- Related: task 138 (roadmap J2) — MetaTests for deck-builder rules build on `DeckRules.copy_cap`.
- Related: task 052 — moves `core_unit_limit` into `RunState` and adds the MetaTests layer.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item C2. Re-checked every line at `404b51c`. Added per-hero base pools (roadmap direction 2's "deck-builder pools"; Dagan is neutral-only) and the dead `VARIANT_CORE_UNITS` filters. The resource-bar widget id is dropped: widgets already key on passive and talent ids. Hero skills get a data table here for UI and agents; engine dispatch is task 097. Owner decisions QN2 and Q2 applied.

## Summary

_(filled in at /task-done)_
