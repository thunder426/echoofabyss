---
id: "102"
title: Declare pool and act gate on the card; split CardDatabase per pool
status: backlog
area: content
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap items C3, D5 and D8 (`design/refactors/ARCHITECTURE_ROADMAP.md` §C direction 4; §D direction 8 and candidate D5). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

C3 and D5 are the same edit to the same file, so they are one task. D8 is reduced to a clean-up done while the card moves.

### Pools and act gates sit far from their cards

`cards/data/CardDatabase.gd` is 3,698 lines. One function, `_register_wanderer_cards` (:311-3663), defines 183 cards; 8 more tokens come from `_TOKEN_DEFS` (:28-41). Two tables at the end of that function say where each card is offered:
- `var _card_pools := {` (:3459-3594): 163 entries in 18 pools. Two cards are in two pools (`soul_shatter`, `font_of_the_depths`).
- `var _card_act_gates := {` (:3596): 61 entries.
- A loop copies them onto the cards (:3653-3658): `var p: Array = _card_pools.get(c.id, [])` … `c.act_gate = _card_act_gates.get(c.id, 0)`.

From a card's definition to its pool entry is a median of 1,574 lines and at most 3,142 (each card's `.id =` line against `:3459`). Card blocks point at the far table, e.g. :481 and :547 `# assignment lives in the _card_pools dict at the bottom of this file.` `CardData.pools` and `CardData.act_gate` already exist (shared/resources/CardData.gd:46, :50); only the tables keep them away from the card.

Consequence: adding or moving a card is three edits in three places, and a forgotten pool or gate fails silently. The card isn't offered, or is offered in Act 1. Task 100's structural probe catches a missing gate on a support card, but not a gate copied onto the wrong card.

### One file for every pool

The file mixes every hero, the neutral set and four enemy acts. Sections don't follow pools: the 26 `abyss_core` cards are spread over the function, from :317 (`void_imp`) through the spells at :1524-1581, the environment at :1904, the minions at :1922-2044, the runes at :2325-2373, to :2410 (`abyssal_summoning_circle`). Tasks 026 and 027 will add 12 more cards and a token to the same function. The file was last changed on 2026-05-19 (`1c9aa30`), so a split now conflicts with nothing open.

### Registration order is gameplay-relevant

`CardDatabase._cards` keeps insertion order, and one engine path depends on it. `on_enemy_summon_feral_reinforcement` (combat/events/CombatHandlers.gd:1144-1151) builds its candidate list from `CardDatabase.get_all_card_ids()` and picks with the seeded `state.rng_pick(feral_imps)`. It runs in Act 2: `feral_reinforcement` is a passive of encounters 4, 5 and 6 (EncounterTable.gd:43, :52, :61). The candidates are the seven non-champion `feral_imp` cards (`rabid_imp` … `rogue_imp_elder`, :2619-2719). As long as they keep their relative order, the seeded pick doesn't change.

Every other reader of the order is meta and either sorts (`DeckBuilderScene._load_inventory`, CollectionScene) or uses the unseeded global RNG (reward and shop shuffles, `grant_boss_unlocks` rolls).

### Tier overrides repeat data (roadmap D8)

`talent_overrides` replace whole fields, last write wins (CardDatabase.gd:138-163). Only one card repeats a lower tier: `abyssal_knight`'s `unbreakable` entry (:442-451) copies the whole `iron_formation` entry (:428-437) — `minion_type`, `FORMATION` in `keywords`, both `formation_effect_steps` dicts — and adds `GUARD` and one sentence. The other 5 cards with overrides (`void_imp`, `abyss_cultist`, `corruption_weaver`, `void_bolt`, `pack_frenzy`) have one entry each. `void_bolt`'s `piercing_void` override (:2095-2104) repeats the base `{"type": "VOID_BOLT", "amount": 500}` step (:2089-2091). A general inheritance mechanism would need `get_card_for_combat` to know talent tiers to save one copy, so it is dropped.

## Decision (owner, 2026-10-01)

- Q6: "**CardDatabase.gd is the source of truth; delete CARD_LIBRARY.md.**" Task 079 deletes the doc. After this task the source of truth is `cards/data/` (CardDatabase.gd plus the per-pool files), and every pool and gate is written on its card.
- Grooming ruling on D8 (task 056): no override-inheritance mechanism. Build the higher tier with `Dictionary.merged()` when the card moves.

## Proposed fix

Two commits, each with its own gate run. Take the "before" dumps (Verification) first.

### Commit 1 — pool and act gate on the card

1. Add `x.pools = [...]` and, where non-zero, `x.act_gate = N` to every card block, just before its `all.append(x)`. Generate the lines once with a throwaway script from the two tables (map variable → id through the `.id =` line; `void_bolt_spell` is `"void_bolt"`). Don't commit the script.
   - Keep each card's pool order as the table has it: `card.pools[0]` decides the Collection's sort and colour (CollectionScene.gd:176-179, :228).
   - `x.pools = [...]` works on the typed `Array[String]` field, as `minion_tags` already does (:342).
2. Delete `_card_pools`, `_card_act_gates` and the copy loop (:3653-3658), and the "lives in the _card_pools dict" comments (:481, :547 and the like).
3. Fix the comments that name the table: CardData.gd:40-45 ("entries follow the order written in CardDatabase._card_pools"), CollectionScene.gd:173-174, RewardScene.gd:101 and :104.

### Commit 2 — split per pool

4. **New `cards/data/pools/` with one script per pool**, named after the pool id: `abyss_core.gd`, `neutral_core.gd`, `seris_core.gd`, `korrath_core.gd`, `vael_common.gd`, `vael_piercing_void.gd`, `vael_endless_tide.gd`, `vael_rune_master.gd`, `seris_common.gd`, `seris_fleshcraft.gd`, `seris_demon_forge.gd`, `seris_corruption.gd`, `korrath_common.gd`, `korrath_iron_vanguard.gd`, `feral_imp_clan.gd`, `abyss_cultist_clan.gd`, `void_rift.gd`, `void_castle.gd`.
   - Each is `extends RefCounted` with `static func register(all: Array) -> void` holding that pool's card blocks verbatim. The blocks use only `all`, global classes and `Enums`, so they move without edits.
   - A dual-pool card lives in the file of its first pool (`soul_shatter` → `vael_common.gd`, `font_of_the_depths` → `vael_piercing_void.gd`).
   - The 20 pool-less cards live with what hands them out: `senior_void_imp` → `vael_endless_tide.gd`, `void_imp_wizard` → `vael_piercing_void.gd`, `runic_void_imp` and `echo_rune` → `vael_rune_master.gd`; each act's champions → that act's enemy file; `void_lance` → `void_rift.gd`.
   - Keep each file's cards in today's relative order. The feral imps must stay in order (see Description).
5. **CardDatabase.gd keeps** the API, `get_card_for_combat`, the override cache, `_TOKEN_DEFS` / `_make_token`, `_validate_spell_damage_schools`, and one `_register_all_cards()` that calls each pool file through a `const` preload, in a fixed order. Write the order down in a comment and don't sort it.
6. **D8, while `abyssal_knight` moves:** build the T3 entry from the T0 one:
   ```gdscript
   var iron_formation_ovr := {"talent_id": "iron_formation", ...}
   var unbreakable_ovr := iron_formation_ovr.merged({
   	"talent_id": "unbreakable",
   	"keywords": [Enums.Keyword.FORMATION, Enums.Keyword.GUARD],
   	"description": "GUARD\nFORMATION: ...",
   }, true)
   ```
   `merged()` keeps the original key order, so the resulting dicts are identical to today's. It is a shallow copy, so both entries share one `formation_effect_steps` array. That is safe: `get_card_for_combat` deep-copies every Array / Dictionary it applies (CardDatabase.gd:149-150), and nothing writes step data at runtime. Task 105 (parse-once) must build new arrays rather than convert shared ones in place. Optionally share `void_bolt`'s base `VOID_BOLT` step dict between `effect_steps` and its override the same way.
7. **Docs and tooling that name the file:**
   - CLAUDE.md "Adding New Cards" step 2 (:39): "add the card to its pool's file under `cards/data/pools/` and set `pools` / `act_gate` on it". Task 079 rewrites step 1 of the same list; whichever lands second rebases.
   - `design/master_doc/ARCHITECTURE.md`: file-finder row :10, autoload row :50, invariant #10 (:342, "Card data lives in CardDatabase.gd") → `cards/data/` (CardDatabase.gd + `pools/*.gd`).
   - `.claude/commands/add-art.md`, `add-champion-art.md`, `missing-art.md` and `test-card.md` (it reads `_card_pools`): search `cards/data/pools/*.gd`.
   - Tasks 026 and 027: their cards go into new `korrath_runic_knight.gd` / `korrath_abyssal_breaker.gd` files, wired like the others.

## Verification

- **Neutral move, checked by dump.** Before commit 1, dump every registered card with a throwaway probe (a `--filter card_dump` test that prints, deleted afterwards): one line per card, sorted by id, with every stored property from `get_property_list()` (`PROPERTY_USAGE_STORAGE`) and its `str()` value, `talent_overrides` included. Dump again after each commit and `diff`: it must be empty. This covers pools, gates and the `merged()` rewrite.
- **Permanent probe** in TriggerHandlerTests.gd next to `_handler_order_snapshot` (:3474), or in task 104's ContentTests layer if it has landed:
  - `CardDatabase.get_all_card_ids().size() == 191` (183 cards + 8 tokens at `404b51c`; update deliberately when cards are added);
  - the non-champion `feral_imp` cards, in `get_all_card_ids()` order, are exactly `[rabid_imp, brood_imp, imp_brawler, void_touched_imp, frenzied_imp, matriarchs_broodling, rogue_imp_elder]`;
  - `abyssal_knight`'s `unbreakable` override equals its `iron_formation` override except `talent_id`, `keywords` and `description`.
- Task 100's structural probe (pools resolve, support cards gated, no gate without a pool) stays green.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4; every card moves) diffs empty (design/TESTING.md 'Refactor / extraction work'). Act 2 is the one that would catch a feral-imp reorder.

## Related

- Depends on: task 100 — deletes the stale `echo_rune` act gate and adds the structural probe that keeps pools and gates honest during the move.
- Related: task 079 — deletes CARD_LIBRARY.md and edits CLAUDE.md's "Adding New Cards" list.
- Related: task 104 (roadmap D1) — its content check scans card-id literals in content files; add `cards/data/pools/` to its file list.
- Related: task 105 (roadmap D2) — parse-once converts step dicts at load; it must not convert the shared `formation_effect_steps` array in place. Don't run both moves at the same time.
- Related: task 068 — edits champion card text in the same function; rebase onto whichever lands first.
- Related: tasks 026 and 027 — Korrath B2/B3 cards; if they land after this task, they add their own pool files.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap items C3, D5 and D8. Re-checked at `404b51c`: the table parse (163 pool entries, 18 pools, 61 gates; distance median 1,574 / max 3,142), the card count (183 + 8 tokens), the one order-dependent engine read (feral reinforcement), and the override repeat (only `abyssal_knight`). D8's inheritance mechanism dropped per the grooming ruling. Q6 applied.

## Summary

_(filled in at /task-done)_
