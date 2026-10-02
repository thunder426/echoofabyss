---
id: "100"
title: One hero/branch/pool table: BranchData + HeroDatabase pool queries; delete the pool-mapping copies; Collection shows every hero
status: backlog
area: meta
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item C1, with C4 folded in as its acceptance test (`design/refactors/ARCHITECTURE_ROADMAP.md` §C). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Meta-only: no combat, sim or AI file is involved.

### The hero → branch → pool mapping is hand-written four times

Each copy maps a hero and its talents to support pools with its own `if current_hero == ... / has_talent(<T0>)` chain:
- `GameManager.grant_boss_unlocks` (shared/scripts/GameManager.gd:164), mapping at :168-192 (`if current_hero == "lord_vael": candidates.append_array(CardDatabase.get_card_ids_in_pools(["vael_common"]))` … `if has_talent("iron_formation"): … ["korrath_iron_vanguard"]`).
- `RewardScene._get_active_support_pool_ids` (rewards/RewardScene.gd:86-112).
- `ShopScene._get_branch_pool` (shop/ShopScene.gd:437, mapping at :440-465). It feeds card slots 1–2 only (:152, :156).
- `ShopScene._get_full_pool` (:473, mapping at :484-507). It feeds slots 3–4 (:157) and the Random Card service (:341).

Two more lists sit beside them:
- `UserProfile._ensure_default_unlocks` (shared/scripts/UserProfile.gd:125) lists all 10 support pools by hand (:126-130).
- `CollectionScene` lists Vael and enemy pools only: the Pool dropdown (ui/CollectionScene.gd:103-106), the card query (:145), the sort order (:175), and the label and colour tables (`_pool_display_name` :276, `_pool_color` :288).

Debug copies: `EnemyDeckBuilder.gd:43` (a "Vael" pool group) and `BalanceSim.gd:32-36` (`_BRANCH_DISPLAY`, Vael only).

Branch metadata is split too:
- branch ids on `HeroData.talent_branch_ids` (heroes/HeroData.gd:39; HeroDatabase.gd:102, :135, :167);
- display names and descriptions in two const dictionaries in TalentDatabase (`get_branch_display_name` talents/TalentDatabase.gd:65-77, `get_branch_description` :80-92);
- the T0 talent that commits a branch exists only inside the four if-chains.

The Vael `void_bolt` branch goes by five names: branch `void_bolt`, T0 talent `piercing_void`, display "Void Resonance", pool `vael_piercing_void`, Collection label "Void Bolt Pool".

### Reachable today

The three "all support pools" copies (GameManager, RewardScene, `_get_full_pool`) agree. Two places differ from what the owner wants (Q5, below):

1. **Shop slots 1–2 use the hero's common pool only as a fallback.** `_get_branch_pool` adds it only when no branch T0 is owned:
   ```gdscript
   if branch_pool_names.is_empty():
   	branch_pool_names.append("vael_common")
   ```
   (:448-449; the same for `seris_common` :457-458 and `korrath_common` :464-465). `_get_full_pool` always adds it (:487, :496, :505).
2. **The Collection hides 39 of the 60 player support cards.** The query at :145 names 4 Vael pools plus 4 enemy pools, so it shows 61 cards: 21 Vael support cards and 40 enemy-only cards. Every Seris and Korrath support card is missing except the two dual-pooled ones (`soul_shatter`, `font_of_the_depths`). The header comment (:2) says "Shows all support cards".
3. **The Collection's Status filter is inert.** :149 is `var is_unlocked := true`. It read `card_id in unlocked` until v0.40 (`git show 9ac4518 -- ui/CollectionScene.gd`). So "Locked" always shows "No cards match the current filters.", while the rows still dim by the real value (:213, :219).
4. **Enemy rows always show 🔒.** The 40 enemy-only cards can never be in `permanent_unlocks`, so they always render locked and dimmed (:213, :229).
5. **Dual-pool labels show raw ids.** `_pool_display_name` has no Seris or Korrath arms, so `soul_shatter` reads "Vael Pool, seris_demon_forge" and `font_of_the_depths` reads "Void Bolt Pool, seris_corruption".

### Latent

- **Korrath B2/B3 pools don't exist yet.** `runic_knight` and `abyssal_breaker` have T0 talents (`runeforge_strike` TalentDatabase.gd:360, `corrupting_presence` :328) but no pool; their content is tasks 026 and 027. Wiring a pool today takes edits in six places (the four copies, UserProfile, Collection). Task 009's summary names three of them.
- **A wrong pool id is already written down.** Task 027 and `design/KORRATH_HERO_DESIGN` (:551, :573, :583) call the Seris pool `seris_corruption_engine`. The real id is `seris_corruption` (`"font_of_the_depths": ["vael_piercing_void", "seris_corruption"]`, CardDatabase.gd:3548). Copying that id into a mapping would silently drop the card from Seris's pool.
- **A card in two pools of the same hero would be listed twice.** GameManager and RewardScene call `get_card_ids_in_pools` once per pool and `append_array` the results. That call de-duplicates only within one call (CardDatabase.gd:269-277). In `grant_boss_unlocks` a duplicate gets a second unlock roll. Today's dual-pool cards span two heroes, so this can't happen yet.
- **A stale act gate.** `"echo_rune": 4` (CardDatabase.gd:3615) gates a card that is in no pool (:3567 `# echo_rune: removed from pool — granted as capstone reward (abyss_convergence)`). It is the only gate on a pool-less card.

## Decision (owner, 2026-10-01)

Q5:
- "**Always:** the hero's common pool (vael / seris / korrath) is offered alongside the unlocked branch pools." This is a deliberate change to shop slots 1–2.
- "**The Collection shows every hero's cards,** grouped by hero, then pool."

Two defaults this task keeps unless the owner says otherwise:
- the four enemy pools stay, as a trailing "Enemies" group;
- the always-unlocked core pools (`abyss_core`, `neutral_core`, `seris_core`, `korrath_core`) stay out, as today. The Collection is the unlock browser; core cards are in the deck builder.

## Proposed fix

Three parts. Each can ship as its own commit with its own gate run.

### Part 1 — data, queries and probes (no caller changes)

1. **Add `talents/BranchData.gd`** (RefCounted): `id`, `hero_id`, `display_name`, `description`, `t0_talent`, `pool_ids: Array[String]`.
2. **TalentDatabase registers the 9 branches** next to each hero's talents. Move the text of the two const dictionaries (:66-76, :81-91) into the records:

   | Branch | Hero | T0 talent | Pools |
   |---|---|---|---|
   | `swarm` | lord_vael | `imp_evolution` | `vael_endless_tide` |
   | `rune_master` | lord_vael | `rune_caller` | `vael_rune_master` |
   | `void_bolt` | lord_vael | `piercing_void` | `vael_piercing_void` |
   | `fleshcraft` | seris | `flesh_infusion` | `seris_fleshcraft` |
   | `demon_forge` | seris | `soul_forge` | `seris_demon_forge` |
   | `corruption_engine` | seris | `corrupt_flesh` | `seris_corruption` |
   | `iron_vanguard` | korrath | `iron_formation` | `korrath_iron_vanguard` |
   | `runic_knight` | korrath | `runeforge_strike` | none yet (task 026) |
   | `abyssal_breaker` | korrath | `corrupting_presence` | none yet (task 027) |

   - Add `get_branch_data(id) -> BranchData`.
   - `get_branch_display_name` and `get_branch_description` become thin accessors, so HeroSelectScene (:294, :303) and TalentSelectScene (:203) don't change.
   - Don't rename any id. BranchData is where the id ↔ pool ↔ name mapping gets written down.
3. **Add `common_pool_id: String` to HeroData:** `vael_common`, `seris_common`, `korrath_common`.
4. **Pure queries on HeroDatabase.** They take ids and never read GameManager, so they also work for an enemy or PvP hero (owner decisions Q1 / Q2).
   - `support_pools(hero_id: String, talents: Array[String]) -> Array[String]`: the hero's common pool, then the pools of each of the hero's branches whose `t0_talent` is in `talents`, in `talent_branch_ids` order.
   - `all_support_pools() -> Array[String]`: every hero's common and branch pools, in `get_all_heroes()` order (HeroDatabase.gd:27).
   - `branch_for_talents(hero_id: String, talents: Array[String]) -> BranchData`: the committed branch, or null. Task 101 uses it for the core-unit variant.
5. **Delete the `"echo_rune": 4` act gate** (CardDatabase.gd:3615). If task 076 lands first and already did, skip.

### Part 2 — callers

6. **One query per caller:** `CardDatabase.get_card_ids_in_pools(HeroDatabase.support_pools(GameManager.current_hero, GameManager.unlocked_talents))`. One call also de-duplicates a card that sits in two of the pools.
   - `GameManager.grant_boss_unlocks` (:168-192);
   - `RewardScene._get_active_support_pool_ids` (:86-112);
   - `ShopScene._get_full_pool` (:484-507; the core part, :477-481, stays).
7. **Shop slots 1–2 (Q5).** `_get_branch_pool` uses the same `support_pools(...)` list and loses its three `is_empty()` fallbacks. Slots 1–2 then draw from the common pool plus the unlocked branch pool. Keep its `permanent_unlocks` filter; task 101 deletes the dead `VARIANT_CORE_UNITS` check.
8. **`UserProfile._ensure_default_unlocks`** (:126-130) uses `HeroDatabase.all_support_pools()`. Task 052 rewrites the code around this function; whichever lands second rebases.
9. **Debug copies (optional):** point `EnemyDeckBuilder.gd:43` (its "Vael" pool group) and `BalanceSim.gd:32-36` (`_BRANCH_DISPLAY`) at the same data, so they cover Seris and Korrath too.

Candidate order changes (one call returns cards in registration order, not pool order). Every consumer either shuffles or rolls each card with the unseeded global `randf()`, so this changes nothing a player can see.

### Part 3 — Collection (Q5)

10. **Groups come from the table.** Replace the hard-coded lists at :103-106, :145, :175 and :276-298 with groups built from `HeroDatabase.get_all_heroes()`:
    - per hero: the common pool, then each branch's pools in `talent_branch_ids` order;
    - labels `<hero_name> — Common` and `<hero_name> — <BranchData.display_name>`; one colour per hero;
    - then a trailing "Enemies" group with today's four enemy pools and labels;
    - the Pool dropdown and the sort order are built from the same group list.

    A dual-pool card stays one row, sorted by its first pool, with both pools labelled properly.
11. **Status filter and lock state.**
    - :149 becomes `var is_unlocked := card_id in unlocked`, and that one value drives the filter (:155-158), the dimming (:219) and the icon (:229).
    - Enemy-pool rows can never be unlocked: no lock icon, no dimming, and they show only under the "All" status.
12. Update the header comment (:2).

### Docs

13. Update:
    - `design/REWARD_SYSTEM_DESIGN.md`: §3's support-pool table (:81-86; "None → Core pool only" becomes core plus the hero's common pool, and Seris and Korrath rows are added) and §5's card slots (:211-216: slots 1–2 draw from the hero's common pool plus the active branch pool; drop the "If no talent taken" note).
    - `design/CARD_POOL_ARCHITECTORE.md` §6 (:129-176, "as of v0.6", Seris and Korrath "to be designed"): point it at BranchData and `HeroDatabase.support_pools` instead of a hand list. Task 079 edits the same file's CARD_LIBRARY pointers.
    - `design/master_doc/ARCHITECTURE.md` file-finder rows (:33-34): "hero → branch → pool data: BranchData in TalentDatabase + `HeroDatabase.support_pools`".
    - `design/KORRATH_HERO_DESIGN` :551, :573, :583 and task 027: `seris_corruption_engine` → `seris_corruption`.
    - Tasks 026 and 027: wiring their pool is now one `pool_ids` entry on the branch.

## Verification

- **Golden-table probe.** In MetaTests if task 052 has landed, otherwise in debug/tests/TriggerHandlerTests.gd next to `_korrath_hero_registered` (:2304):
  - `support_pools("lord_vael", []) == ["vael_common"]`;
  - `support_pools("lord_vael", ["rune_caller"]) == ["vael_common", "vael_rune_master"]`;
  - `support_pools("seris", ["corrupt_flesh"]) == ["seris_common", "seris_corruption"]`;
  - `support_pools("korrath", ["iron_formation"]) == ["korrath_common", "korrath_iron_vanguard"]`;
  - `support_pools("korrath", ["runeforge_strike"]) == ["korrath_common"]`;
  - `support_pools("seris", ["rune_caller"]) == ["seris_common"]` (another hero's talent adds nothing);
  - `all_support_pools()` equals, as a set, the 10 ids in UserProfile.gd:127-129;
  - `branch_for_talents("lord_vael", ["imp_evolution", "swarm_discipline"]).id == "swarm"`, and `branch_for_talents("lord_vael", [])` is null.
- **Structural probe (roadmap C4).** In task 104's ContentTests layer if it has landed, otherwise beside the golden table:
  - every `HeroData.talent_branch_ids` entry has a BranchData with the same `hero_id`, and every BranchData is listed by its hero;
  - each `t0_talent` exists in TalentDatabase with `tier == 0`, `branch == id` and the same `hero_id`;
  - `display_name` and `description` are non-empty;
  - every pool id on a HeroData or BranchData resolves to at least one card (empty `pool_ids` is allowed until 026/027);
  - every support pool in CardDatabase (every pool except the four `*_core` and the four enemy pools) is claimed by exactly one hero common pool or branch. This catches an unwired `korrath_runic_knight` or the `seris_corruption_engine` typo;
  - every support-pool card has `act_gate` in 1..4, and no card with empty `pools` has `act_gate != 0` (fails today on `echo_rune`; step 5 fixes it);
  - `senior_void_imp`, `runic_void_imp` and `void_imp_wizard` are in no pool.
- **Collection probe** (pure helper, no scene): extract the group builder as `static func build_groups() -> Array` and assert 3 hero groups in `get_all_heroes()` order plus "Enemies" last, and that the groups' pools cover all 60 player support cards.
- **Manual:**
  - a Vael Rune Master run at shop 2: slots 1–2 can show `vael_common` cards (the Q5 change);
  - a Korrath Iron Vanguard run: slots 1–2 draw from `korrath_common` and `korrath_iron_vanguard`;
  - the Collection shows Lord Vael, Seris and Korrath groups (60 support cards) and the Enemies group; on a fresh profile "Locked" lists cards and "Unlocked" hides the dimmed rows.
- `tools/run_checks.sh` green.
- Behaviour-neutral for combat: no combat, sim or AI file changes, and BalanceSimBatch never reads pools (`grep -rln 'get_card_ids_in_pools\|permanent_unlocks' --include='*.gd'` lists only CardDatabase, GameManager, UserProfile, RewardScene, ShopScene, CollectionScene and DeckBuilderScene). The balance fingerprint can't move. The shop change in step 7 is a deliberate meta change; note it in the summary.

## Related

- Related: task 101 (roadmap C2) — moves the hero's deck rules (core unit, variants, copy caps, base pools) onto HeroData; depends on this task for `branch_for_talents`.
- Related: task 102 (roadmap C3) — declares pool and act gate on each card and splits CardDatabase; depends on this task's structural probe and the echo_rune gate removal.
- Related: task 123 (roadmap H1) — RunService calls `support_pools` instead of reading GameManager in scenes; depends on this task.
- Related: task 138 (roadmap J2) — MetaTests for reward and shop pools build on these queries.
- Related: task 104 (roadmap D1) — its content check covers pool and act-gate ids; the structural checks here can live in its ContentTests layer.
- Related: task 052 — rewrites UserProfile load/save around `_ensure_default_unlocks` and adds the MetaTests layer.
- Related: tasks 074, 075 and 128 (roadmap H7) — the other open ShopScene changes; rebase onto whichever lands first.
- Related: task 076 — may delete the echo_rune gate first.
- Related: task 078 — reads `last_boss_unlocks`, which `grant_boss_unlocks` fills.
- Related: task 079 — deletes CARD_LIBRARY.md and edits CARD_POOL_ARCHITECTORE.md's pointers.
- Related: tasks 026 and 027 — Korrath B2/B3 content; their pool wiring becomes one BranchData entry.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap items C1 and C4 (C4 is the structural probe). Re-checked every line at `404b51c`, re-ran the pool parse (163 pool entries in 18 pools, 61 act gates, 60 player support cards; `echo_rune` the only gate without a pool). Owner decision Q5 applied. Folded in the Collection defects (inert Status filter, enemy rows locked, raw dual-pool labels). Korrath B2/B3 is unshipped content, not a divergence.

## Summary

_(filled in at /task-done)_
