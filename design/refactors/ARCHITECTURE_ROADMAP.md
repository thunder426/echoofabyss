# Architecture Roadmap — longer-term structural work

**Status:** groomed (pass 1, 2026-10-01, task 056): every candidate is filed as a backlog task (057–142), merged, deferred or dropped; see §13.
**Written:** 2026-09-25, from a four-part architecture review (engine core; content & effects; presentation & VFX; AI, meta-game, tests & tooling) at `e66f13e` plus the uncommitted task 046 diff.
**Audience:** the owner deciding what to do and when, and a coding agent grooming this into tasks. Each item says what's wrong, the evidence, why it matters as the game grows, a proposed direction, candidate tasks and decisions for the owner.
**Companion:** the short-term fixes from the same review are already tasks **047–055** (enemy decks in repo, presenter soft-lock, reference-cycle leak, EffectResolver side bugs, AI state writes, save robustness, debug gating, log constants, GameManager read). This doc does not repeat them; it notes where they overlap.

> **How far to trust the evidence.** Items marked **(verified)** were checked by hand against the code during the review. Grooming pass 1 (task 056) re-verified all of the evidence on 2026-10-01 at `404b51c`: 12 unit reports, with adversarial re-checks of units A-paths and C. Most of it held. The original text below is left as written, and each section's **Evidence corrections (2026-10-01)** list records what was wrong: counts, file claims, and whether a problem is reachable today or latent. The task files carry the current evidence. Line numbers will drift, so match on the quoted code, not the number.

---

## 0. Summary

The core architecture is sound, and the live/sim unification (Phases 0–5) worked:
- one engine behind a validated command surface, with a journal and a presenter;
- seeded, replayable fights;
- lint L1–L11, a parity test and a live smoke test.

The debts below are about **growth**. Each new hero, champion, card or mechanic currently costs more than it should, and several failure modes are silent (a misspelled id, a one-sided effect, UI showing values before the animation that explains them).

| ID | Workstream | Size | Payoff | Depends on | Tasks (groomed 2026-10-01) |
|---|---|---|---|---|---|
| **A** | Side model: `Side` + `SideState`, real symmetry | L | Highest. Removes a whole class of silent one-sided bugs; required for enemy heroes, mirror matches or PvP | 050 (small version first) | 082–093; bugs 062–064 |
| **B** | Break up CombatState: hero/champion modules, diagnostics, command processor | L | New hero or champion becomes one module instead of 6–10 files | A (ideally), D1 | 094–099; bugs 066–068 |
| **C** | Hero / branch / pool data model | M | A 4th hero touches ~6 files instead of ~18; kills 4–5 diverged copies | — | 100–103; bugs 075, 076 |
| **D** | Content validation and effect-system extensibility | M | Typos fail at load, not in play; new effect types without editing a central match | — (D1 first, it's cheap) | 104–108, 079, 081; bug 065 |
| **E** | Presentation reads only the journal (single display source) | M | UI never runs ahead of animations; one place for display state | 048 | 070, 071, 109–113; bug 069 |
| **F** | Look-ahead matched by cause, not by kind | S–M | New cards can't show damage at the wrong moment | E (shares payloads) | 114–116; bugs 057, 059 |
| **G** | AI consolidation | M | Less copy-paste; boss tuning stops leaking across encounters; one AI style | 051 | 117–122; bugs 072, 073 |
| **H** | Meta / run layer | M | Testable run logic; constants derived from EncounterTable | 047, 052, C | 080, 123–128; bugs 074, 077, 078 |
| **I** | Engine robustness (side-channel flags, statics, re-entrancy, digest) | M | Fewer subtle interaction bugs; parity sees more state | 049 | 129–136; bugs 058, 060, 061 |
| **J** | Tests & tooling at scale | M | Tests auto-discovered, isolated, covering meta; sturdier lint | 049 | 137–142 |

Each bug is listed once, under the section whose report filed it; the per-section "Groomed" lists give the full mapping.

Suggested order after grooming: the straight-to-task bugs (057–078), then 047–055 with the cheap cleanups (079–081) and D1, then the look-ahead prerequisites, then **C → A → B**, with **E/F**, **G**, **H**, **I** and **J** interleaved as capacity allows. The reasoning is in section 11.

---

## A. Side model — make "symmetric" true

**Problem.** Sides are the strings `"player"` / `"enemy"`, and most per-side data exists as a pair of fields behind ternary accessors.

- **(verified)** Lines containing a side literal: CombatState ~216, CombatHandlers ~78, EffectResolver ~26, CombatManager ~19, HardcodedEffects ~5. The reviewer counted ~400 occurrences across rules code.
- Paired fields: `player_hand/enemy_hand`, `active_traps/enemy_active_traps`, `active_environment` (player) vs. the enemy equivalent, essence/mana pairs, etc., accessed via `hand_of`, `traps_of`, `deck_of`, …
- 24 of the 32 `Enums.TriggerEvent` values are `ON_PLAYER_*` / `ON_ENEMY_*` duplicates. The pairs have gaps: no enemy ATTACK_POST; `ON_ENEMY_TRAP_PLACED` is a stub; `ON_RUNE_PLACED` is player-only.

**Invariant #2 ("symmetric handlers") is not true today.** Player-only paths reported by the review:
- `on_minion_turn_start_passives` walks only `player_board` and is registered only on `ON_PLAYER_TURN_START` (CombatHandlers ~:38-44, CombatSetup ~:545). So enemy minions' `on_turn_start_effect_steps` never run.
- Attack PRE/POST triggers fire only for the player (CombatManager ~:85, :110).
- `TRAP_ROUTES` (CombatState ~:1010-1020) has no enemy routes for the player's attack, a friendly death or hero damage.
- Board passives on death, summon and sacrifice are player-only. So are rituals, talents (`_card_ctx` gives the enemy `[]`), Flesh/Forge, and Void Marks (enemy hero only).
- EffectResolver gates VOID_MARK, GAIN_FLESH and CONVERT_RESOURCE on `ctx.owner == "player"`.
- **(verified)** `talents` / `_has_talent` are player-only (CombatState ~:215, ~:1647).
- Legacy `passive_effect_id` / `on_spell_cast_passive_effect_id` cards (10 cards) are dispatched only on ON_PLAYER_* events and loop `player_board` (CombatHandlers ~:109, :189, :756-764).
- Relics are player-only (acceptable by design, but should be explicit).
- The concrete bugs this produced are task 050 (verified) and task 055 item 2 (verified).

**Why it matters.** Every card that works for one side and silently does nothing for the other is a latent bug. An enemy Seris, enemy rituals, mirror matches or PvP would each need an audit of ~400 sites. The architecture doc advertises a property the code doesn't have, so new code is written assuming it.

**Direction.**
1. `enum Side { PLAYER, ENEMY }` plus `opponent(side)`. Keep string conversion only at the JSON and log boundaries (command log, digests, config).
2. `SideState` (RefCounted) per side holding hand, deck, graveyard, essence/mana (and max), traps, environment, board slots, hero state, cost modifiers, talents, hero passives and per-side counters. `CombatState.sides[Side]`, with `state.side(s)` / `state.me(ctx)` / `state.opp(ctx)`.
3. Collapse trigger events to side-neutral kinds (`ON_TURN_START`, `ON_MINION_DIED`, …) with `ctx.side`. Handlers filter on `ctx.side == ctx.owner` (or its opponent) explicitly. Keep a compatibility shim during migration.
4. Decide per mechanic whether it is **intentionally one-sided** (e.g. relics, Void Marks on the enemy hero) and write that into the data (`owner_sides`), not into an `if owner == "player"`.

**Candidate tasks.**
- A0 (S): **audit only.** List every player-only path with a verdict: bug / intended / N/A. Output a table in this doc. Fix the clear bugs as small tasks.
- A1 (M): introduce `Side` + `SideState`, move hand/deck/graveyard/resources, keep the old accessors as thin forwarders. Behaviour-neutral: the seeded balance fingerprint diffs empty (see §11).
- A2 (M): move traps, environment, board and hero into `SideState`; single `remove_trap` / `set_environment` (extends task 050).
- A3 (L): side-neutral trigger events, migrate CombatSetup registrations and handlers, update the `handler_order.txt` snapshot deliberately.
- A4 (S): lint rule: no `"player"` / `"enemy"` literals in rules code outside a small allowlist (serialization, logs).

**Groomed 2026-10-01 → tasks.**
- A0 → task 082: the verdict table plus an enemy-content guard test. Under Q2, every player-only path is an asymmetry to fix; reachable or latent only sets priority.
- A1 → task 083: `CombatSide.PLAYER` / `ENEMY` string constants, not an int enum.
- A2 → task 084: also takes I6-traps (a per-copy `TrapInstance`). The `remove_trap` / `destroy_environment` / `place_trap` API is task 050's.
- A3 → task 086: the wide (PvP-ready) variant per Q1, in phases. It also covers enemy attack PRE/POST, enemy `TRAP_ROUTES`, an enemy CARD_DRAWN, enemy standard traps springing, and the attack context's defender and rider timing.
- A4 → task 087: lint L16, a ratchet whose baseline is set when it lands.
- New A5 (TriggerEvent hygiene: dead values, the dead `TurnPhase` enum, stale comments, trap vs rune conventions) → task 088.
- New A6 (per-side turn counters and cost modifiers) → task 085.
- New A8 (retire legacy `passive_effect_id` dispatch; side-neutral board-passive dispatchers) → task 089. The A-paths report numbers it A5.
- New per-side mechanics from Q2, one task each (the A-paths report's A6):
  - talents and hero passives, plus an enemy hero id → task 090;
  - relics → task 091;
  - Void Marks and the remaining player-gated EffectResolver steps → task 092;
  - rituals and rune events → task 093;
  - Flesh / Forge → task 097 (B3).
- A7 (integer `Side` enum) → deferred. The strings cross every boundary: journal, contexts, signals, presentation and AI, with 1,090 literals and 240 `String` side declarations. A1 uses constants instead.
- Straight-to-task bugs:
  - enemy Void Spawner (F6) and Abyssal Tide (F3 f3_b) passives never fire → task 062;
  - enemy Flux Siphon (F2 f2_c) does nothing → task 063;
  - the player's Runic Attunement doubles the enemy's rune auras → task 064.
- The decisions below are answered (Q1–Q3, §12).

**Evidence corrections (2026-10-01).**
- Accessors exist for only 9 per-side fields, and raw reads dominate (board: 222 raw refs vs 51 helper calls). Board, slots and hero have no public accessor.
- Only 9 of the 24 prefixed TriggerEvent values are full player/enemy pairs. The rest are ATTACK_PRE/POST vs ENEMY_ATTACK, a player-only CARD_DRAWN, a dead ENVIRONMENT_PLACED, and ENEMY_HERO_DAMAGED vs an unprefixed ON_HERO_DAMAGED.
- `ON_ENEMY_TRAP_PLACED` is not a stub. It fires (CombatState ~:2698) and is tested; only its Enums comment is stale. Neither TRAP_PLACED value has a production listener.
- Six EffectResolver steps are gated on `ctx.owner == "player"`, not three: VOID_MARK, CONVERT_RESOURCE, GAIN_FLESH, SPEND_FLESH, GAIN_FORGE_COUNTER and SPEND_FLESH_UP_TO. Path of Corruption is player-only, and Dark Channeling is enemy-only.
- There are 9 legacy passive cards, not 10. 7 dispatch player-only; hollow_sentinel and rift_warden are already symmetric.
- "Latent" is wrong for three cases that are broken today: Void Spawner, Abyssal Tide and Flux Siphon in enemy decks, plus Runic Attunement leaking into enemy runes (F4 f4_b, F5 f5_a).
- The balance example gives no shift: no enemy-reachable card has `on_turn_start_effect_steps`. The real deltas come from tasks 062–064.
- Non-rune traps never mirror their trigger, so the existing enemy trap routes are dead. This is latent: enemy decks hold only runes.
- Direction 1: the strings are the runtime side type everywhere, not only at boundaries (see A7). Avoid a bare `class_name Side`, because Godot already has a global `Side` enum.
- `set_environment` already exists and journals, so A2 is only the SideState move.
- HardcodedEffects isn't fully symmetric: Soul Rune reads the global rune-aura multiplier, and pack_frenzy reads `enemy_passives` for either caster. Both are latent.
- "Relics are acceptable by design" is overruled by Q2.

**Decisions for the owner.**
- Is PvP or enemy-hero play a real goal, or is symmetry only about hygiene? This sets how far A3 goes.
- Which one-sided mechanics are intended (relics? Void Marks? talents?)
- Accept balance changes when enemy-side triggers start firing (e.g. enemy turn-start minion effects)? Expect BalanceSimBatch shifts.

---

## B. Break up CombatState (god object)

**Problem (reported).** `CombatState.gd` has ~3,160 lines, 176 vars, 174 funcs and 24 signals, in about 12 clusters: journal/log, board and slots, RNG, resources/deck/hand, turn engine, commands and cost planning (~30 funcs), traps/runes/rituals, damage and heal glue, champion and spark rules, digest, setup, and hero mechanics.
- ~61 fields are specific to a hero, champion or card: 31 `_champion_*` fields; Seris 14 fields and ~19 funcs; Korrath 6 fields and 5 funcs.
- ~30 balance-diagnostic counters (`_debug_*`, `_vw_*`, `_rift_*`, `_abyssal_plague_*`, …) live on the engine, some updated in hot paths (`cmd_play_minion` ~:2574, `_consume_minion` ~:3065, `CombatManager._deal_damage` ~:291).
- `CombatHandlers.gd` is 2,345 lines and 137 funcs; about half (~:1096-2300) is per-encounter code. Each of the 15 champions repeats the same pattern: fields on the state, a registry entry, 2–3 handlers, an `_is_alive` helper, a match arm (~:2263-2278), constants. That's 6–7 touch points in 3 files per champion.
- The `_` prefix has stopped meaning private: CombatHandlers touches 74 distinct `state._x` members (172 accesses); effects, relics, AI and sim touch ~99 more; presentation ~69.
- A new hero talent tree touches ~9–10 files: CombatSetup, CombatHandlers, CombatState (fields, signals, digest), CombatEvent.Kind, EffectStep/EffectResolver, CombatManager, MinionInstance, the hardcoded skill ids in `cmd_hero_skill` (~:2870, only `"seris_corrupt"` / `"soul_forge"`), and ViewState/CombatUI.

**Why it matters.** Every new hero, champion or encounter makes the engine bigger and harder to reason about. Merge conflicts and "which of the 176 fields does this touch" grow with content. Diagnostic code in hot paths slows the sim.

**Direction.**
1. **Content modules.** A small interface `CombatModule` with `register(state, tm)`, its own state, `digest()` and `reset()`. One module per hero (`SerisModule`, `KorrathModule`, `VaelModule`) and one per champion, or a single **data-driven champion spec table** (threshold event, count, card to summon, aura), since the 15 champions share the pattern. `CombatSetup._REGISTRY` points at modules, not method-name strings.
2. **Diagnostics off the engine.** Counters become a `Dictionary[StringName, int]` on the existing `diagnostics` object, fed from journal events where possible. No counter code in `cmd_*` or `_deal_damage`.
3. **CommandProcessor.** Move `cmd_*`, `plan_cost` and `CommandResult` out of CombatState; they call the engine's public API.
4. **Public API.** Give the members other classes actually use a public name; lint "no `state._x` from outside combat/board" once the count is low.
5. `cmd_hero_skill` looks up skills declared on `HeroData` / the hero module, not a hardcoded id list.

This is the optional "D6 file split" (4.5) left over from `LIVE_SIM_UNIFICATION_PLAN.md`; this item replaces that note.

**Candidate tasks.** B1 (M) diagnostics map. B2 (M) champion spec table + module. B3 (M) Seris module. B4 (S) Korrath module. B5 (M) CommandProcessor extraction. B6 (S) hero skills from data. B7 (S) public accessors + lint.

**Groomed 2026-10-01 → tasks.**
- B1 → task 094: one sim-side counter sink, after task 051. The 8 dead counters are deleted.
- B2 → two tasks:
  - task 095 (B2a): a ChampionTracker plus shared helpers, with no behaviour change;
  - task 096: the spec table with a reactive `{event, effect_steps}` aura column (Q4: 13 of 15 champions fit, 87%), small modules for ACP and VC, and text generated from the spec. It also takes I7c.
- B3 → task 097: a per-side SerisModule (Flesh, Forge, skills, deathless save).
- B4 → task 098: a per-side KorrathModule. Armour, Armour Break and Formation stay generic.
- B5 (CommandProcessor) → deferred. The command section uses 72 engine members, 27 of them private, so revisit it after B7 phase 2. It supersedes LIVE_SIM_UNIFICATION_PLAN D6 / 4.5.
- B6 → task 097: `cmd_hero_skill` looks skills up from the side's hero module.
- B7 → task 099: a ratchet lint on `state._x` (L19) first, then the renames after B1, B2a, B3, B4 and A2 have moved members.
- New B8 (delete the 14 CombatState signals with no listener) → task 132 (I4).
- Straight-to-task bugs:
  - champion auras keep working after the champion dies (F1, F3, F4) → task 066;
  - the F15 Avatar's card counter resets at the phase change → task 067;
  - champion text and tooltips have drifted from the code, and the F5 Void Ritualist's rune-cost aura was never implemented → task 068. Per QN1 the code wins and the aura text is deleted. The same task adds the missing F13–F15 and Act 3–4 tooltips.
- The decision below is answered (Q4, §12).

**Evidence corrections (2026-10-01).**
- Korrath has 3 vars and 2 consts, not 6 fields.
- No single definition gives "~61 fields": hero and champion vars alone are 48, or ~76 with the encounter- and card-specific vars.
- A champion is ~8 touch points in 6–8 files, not 6–7 in 3. The extra ones are card text, CHAMPION_INFO, PASSIVE_INFO, EncounterTable and AI profiles. Only 8 of the 15 champions have an `_is_alive` helper.
- A new hero talent tree touches 12–19 files, not 9–10: Seris talent ids appear in 19 non-debug files and Korrath's in 12.
- Effects, relics, AI and sim touch 99 distinct `state._x` members, but only 68 are new beyond CombatHandlers' set. Across all non-test code it is 144.
- "Diagnostics slow the sim" was not measured and looks negligible. The case for B1 is clutter. There are 33 diagnostic counters, 8 of them dead.
- `diagnostics` is null in every batch run, so B1 needs a sink in every sim run or a fold over the journal.
- B1 should follow task 051. B3 and B4 depend on A1 only softly.

**Decisions.** A module per champion vs. a spec table (the table is recommended if ≥80% of champions fit it). Should B wait for A? Recommended: B1 and B2 can go first, the hero modules after A1.

---

## C. Hero / branch / card-pool data model

**Problem (reported).** The hero → talent-branch → card-pool mapping is copied **4–5 times** and the copies already disagree:
- the copies: `GameManager.gd` ~:168-192, `RewardScene.gd` ~:86-111, `ShopScene.gd` ~:441-466 **and** ~:485-507, `UserProfile.gd` ~:126-130;
- ShopScene's `_get_branch_pool` uses `vael_common` only when no branch pool applies; the others always include it;
- Korrath's B2/B3 pools are missing from every copy;
- `CollectionScene.gd` (~:106, :145, :175) lists Vael pools only, so Seris and Korrath cards don't appear;
- ShopScene's "expand_core_unit" adds `"void_imp"` for any hero (~:323-327).

Branch metadata is also split across `HeroData.talent_branch_ids`, `TalentDatabase` DISPLAY_NAMES / DESCRIPTIONS (~:65-92) and `DeckBuilderScene.DECK_BUILDER_POOLS_BY_HERO` / `_EXTRA_COPY_RULES` (~:18-22, :60-64). Pools (`_card_pools`, CardDatabase ~:3459) and act gates (~:3596) sit ~3,000 lines from the cards they gate.

**Adding a 4th hero touches about 18 files:** HeroDatabase, TalentDatabase (3 places), CardDatabase (cards, pools, act gates), CardModRules, CombatSetup `_REGISTRY`, CombatHandlers, CombatState (fields plus the `cmd_hero_skill` list), PresetDecks, DeckBuilderScene (2), RewardScene, ShopScene (2), GameManager, ProfileRegistry plus a player profile, PipBar/resource-bar UI, BalanceSimBatch configs, VFX registries and CARD_LIBRARY.md.

**Direction.**
1. `BranchData` resource/record `{id, hero_id, display_name, description, t0_talent, pool_ids}`, owned by `TalentDatabase` (or `HeroData.branches`).
2. `HeroData` gains core unit, copy rules, deck-builder pools, hero skills and the resource-bar widget id.
3. One query: `GameManager.active_pools()` (or `HeroDatabase.pools_for(hero, talents)`). Reward, shop, collection, deck builder and GameManager call it; all copies are deleted.
4. Card pool and act gate declared on the card (or in a per-pool file next to its cards) instead of in far-away tables.
5. `PipBar` picks widgets from the combat config / HeroData, not from `GameManager` (~:194-198). The same applies to the other combat UI that reads hero / talent info from `GameManager` (verified 2026-09-30; moved here from task 055):
   - SerisResourceBar ~:47-48
   - CombatUiStyle ~:32, :173, :206, :214
   - PlayerHeroPanel ~:64, :98
   - EnemyHeroPanel ~:86, :179-181
   - BoardSlot ~:547

**Candidate tasks.** C1 (M) BranchData + `active_pools()` + delete copies (fixes the Korrath/Shop/Collection divergence). C2 (S) HeroData carries core unit, copy rules and skills. C3 (M) pool/gate on the card, CardDatabase split per pool (see D5). C4 (S) test: every hero has ≥1 branch; every branch's pools are non-empty and resolve.

**Groomed 2026-10-01 → tasks.**
- C1 → task 100, which follows Q5:
  - the shop always offers the hero's common pool;
  - the Collection shows every hero's cards, and gets its own fixes (inert Status filter, enemy cards always locked, raw dual-pool labels).
- C2 → task 101: HeroData carries the core unit, extra-copy rules and one copy-cap rule. It lands after the core-unit bug fix (075).
- C3 = D5 = D8 → task 102. D8's inheritance mechanism is dropped; the higher tier is built with `.merged()` when the card moves.
- C4 → task 100, as its acceptance tests. The assertion becomes "every declared pool resolves", because Korrath B2/B3 have no pools until tasks 026/027.
- New C5 (direction 5: combat UI reads hero, talent and enemy info from the fight, not GameManager) → task 103. It also takes H6b (PipBar's hero widgets) and the missed CombatVFXBridge site.
- Straight-to-task bugs:
  - after any purchase, every shop Buy button takes the last offer's state → task 074 (filed with H's Expand Core Unit bug);
  - the core-unit services give Seris and Korrath Vael's Void Imp → task 075 (QN2: each hero's own core unit);
  - Undo after Abyss Convergence keeps its 2 Echo Runes → task 076;
  - the first shop offers an unbuyable Second Wind → task 128 (H7, QN3).
- The decisions below are answered (Q5, §12).

**Evidence corrections (2026-10-01).**
- Three of the copies (GameManager, RewardScene, `ShopScene._get_full_pool`) agree today. Only `_get_branch_pool` (the 2 guaranteed slots) and the Collection diverge from the intent recorded in Q5.
- `_get_branch_pool`'s fallback rule covers all three heroes' common pools, not only `vael_common`.
- Korrath's B2/B3 pools aren't missing from the copies; they don't exist yet (unshipped content, tasks 026/027).
- The Collection shows 61 cards (21 Vael support, 40 enemy-only) and hides 39 of the 60 player cards.
- Pools sit a median 1,574 lines from their cards (max 3,142), so "~3,000" is the worst case. `echo_rune` keeps an act gate but has no pool.
- Hero skills are talent-granted and validated in the engine. They belong to B6 / B3 (task 097), not to HeroData.
- The resource-bar widgets are already keyed on passive and talent ids, as Q2 wants. The only defect is that they read GameManager (C5).
- After C alone, a 4th hero touches ~11–12 sites, not ~6. Getting to ~6 also needs B's hero modules.
- The C5 list misses CombatVFXBridge ~:1026 (the enemy casting-glyph faction): 16 sites in all.

**Decisions.** What is the intended Shop behaviour for `vael_common`: always included, or only as a fallback? Should the Collection show all heroes' cards?

---

## D. Content validation and effect-system extensibility

**Problem (reported).** Content is looked up by name, and nothing checks the names at load. Typos fail silently or only when the card is played:
- Steps are stored as Dictionaries and re-parsed by `EffectStep.from_dict` on every resolution (EffectResolver ~:18-22), plus 8 parse sites in AI scoring. `from_dict` uses 37 `if "x" in d` checks, so misspelled keys are dropped.
- **An unknown condition name evaluates to `true`** (ConditionResolver ~:154-156).
- An unknown `multiplier_key` falls back to `amount` (EffectResolver ~:664).
- `HardcodedEffects.resolve` has no `_:` arm. `CombatSetup.apply_passive` returns silently for an unknown id (~:638).
- Registry `"method"` strings are bound with `Callable(h, name)`, and `TriggerManager.fire` skips invalid Callables (~:88). A misspelled method never fires and nothing reports it. The lint checks only `stats` keys.
- A misspelled field in `talent_overrides` warns only when that talent is active; a misspelled `talent_id` never warns.
- The only load-time check is `_validate_spell_damage_schools` (CardDatabase ~:3670). It lists `"DAMAGE_ANY"`, which is not an EffectType, and ignores VOID_BOLT, nested `attack_rider_steps` and override steps.
- ~560 card-id string literals in logic (~280 in `combat/`, ~275 across 33 files in `enemies/ai/`); ~217 `.id ==` comparisons. Renaming a card silently disables its rules and AI branches.
- **The effect vocabulary grows by one entry per card or hero.** 45 `EffectType` values, ~10 hero-tagged and ~6 used by a single card; `EffectStep` is a 37-field union. A new type means editing the enum, a field, `from_dict`, the 754-line resolver match and AI scoring. ~35 condition names bake a threshold into the name (`flesh_gte_1/2/3`, `flesh_lt_2/3`), mostly used once.
- `CARD_LIBRARY.md` (the "source of truth") is missing 24 of the database's cards: Avatar of the Abyss plus 23 Korrath cards. Nothing checks that the two agree.
- `talent_overrides` replace whole fields, so higher tiers repeat the lower tiers' data (e.g. abyssal_knight ~:428-451). Editing T0 means updating every copy.

**Direction.**
1. **D1 content-lint test (do first — cheap, high value).** One test that checks:
   - every quoted card id in `combat/`, `enemies/`, `relics/`, `talents/`, `heroes/` and PresetDecks exists;
   - every `condition` is in a declared set;
   - every `multiplier_key`, `hardcoded_id`, `talent_id` and passive id resolves;
   - every `_REGISTRY` method exists on `CombatHandlers` (`has_method` is fine in a test);
   - every pool and act-gate id resolves;
   - every `EffectStep` dict has only known keys.
2. **Parse once.** Convert step dicts to `EffectStep` at CardDatabase load. Assert on unknown keys, types and scopes. AI scoring reads the parsed steps.
3. **Fail loudly.** Unknown condition → `push_error` + `false`. Add `_:` arms with `push_error` to the string-dispatch matches.
4. **Effect handler registry.** `EffectType → Callable` table (one small function per effect type, grouped by family in separate files) instead of the 754-line match. New types register themselves.
5. **Parameterised conditions** (`{"flesh_gte": 2}`) instead of one name per threshold.
6. **Ids as data, not literals.** Where logic branches on a card id, prefer a tag or flag on the card (`is_champion_trigger`, `minion_tags`) so renames are safe; keep literals only in content definitions.
7. **Doc drift.** Generate the CARD_LIBRARY tables from CardDatabase, or add a test that every CardDatabase card appears in CARD_LIBRARY.md (and name KORRATH_HERO_DESIGN as a co-source).
8. **Override inheritance.** `talent_overrides` tiers inherit from the lower tier and override only the fields they change.

**Candidate tasks.** D1 (S–M) content-lint test. D2 (M) parse-once + strict `from_dict`. D3 (S) loud failures. D4 (L) effect handler registry. D5 (M) CardDatabase split per pool (locality; not `.tres`, which isn't worth it for a solo dev). D6 (S) CARD_LIBRARY sync check. D7 (S) parameterised conditions. D8 (S) override inheritance.

**Groomed 2026-10-01 → tasks.**
- D1 → task 104: a ContentTests layer for loaded data plus lint L14 for source text (card-id literals, dispatch vocabularies). It also takes G6.
- D2 → task 105. It migrates the 5 Dictionary-only step readers first, so it stays byte-identical.
- D3 → task 106: fail loudly on unknown names, and fix `_validate_spell_damage_schools`. Board-passive dispatchers can't take a `_:` arm, so D1 covers them.
- D4 → task 107: one family per phase, after D2 and task 050.
- D5 → task 102 (C3).
- D6 → replaced by task 079 (owner Q6): delete CARD_LIBRARY.md, since CardDatabase.gd is the source of truth. There is no sync test.
- D7 → task 108: a declared condition table; the 19 unused arms are deleted or kept per that table.
- D8 → task 102. The inheritance mechanism is dropped: only abyssal_knight repeats tier data, so it uses `.merged()` when the card moves.
- New DL1 → task 081: delete passive content unreachable since v0.39 (spirit_conscription, champion_duel, a dead match arm, a stale AI id check).
- Straight-to-task bugs:
  - Energy Conversion converts all Essence instead of "up to 3" → task 065;
  - Flux Siphon → task 063 and Runic Attunement → task 064 (filed under A);
  - the default sim bot never casts Void Execution (it checks a `human` tag no card has) → task 073, filed with G's sim-bot bug.
- The decision below is answered (Q6, §12). Card text that disagrees with code inside CardDatabase is task 068.

**Evidence corrections (2026-10-01).**
- There are 280 card-id literals in 31 of the 42 `enemies/ai` files (not ~275 across 33), and 178 `.id ==` comparisons (214 counting `!=`), not ~217.
- ConditionResolver has 33 named conditions. Only 10 bake in a threshold (7 used once, 3 never), and 19 of the 33 are unused by content.
- 21 of the 45 EffectTypes serve one card or none, not ~6.
- "The 754-line match" is the whole file. Dispatch is two matches: `_execute` (29 arms) and `_apply` (17).
- Of the 8 AI parse sites, 3 are in the scored stack and 5 are base-profile heuristics. The doc missed 2 non-AI parse sites and 5 Dictionary-only readers.
- Nothing mutates step dicts or EffectStep fields at runtime, so parse-once can be byte-identical.
- The validator skipping VOID_BOLT and rider steps is harmless or by design. A second load-time check already exists: the duplicate-id warning.
- Only 1 card (abyssal_knight) repeats tier data in `talent_overrides`.
- CARD_LIBRARY.md is missing 24 names (25 ids).
- A D1 prototype found 0 typos or dangling ids today, so D1 guards future renames rather than fixing current ones.

**Decisions.** Is CARD_LIBRARY.md still the source of truth, or does CardDatabase become the source with the doc generated from it?

---

## E. Presentation reads only the journal (single display source)

**Problem (reported; the rune-slot and live-HP items are concrete bugs).** Display state lives in four places: `ViewState`, `BoardSlot.shown_*` (task 046), reads of the live engine, and event payloads.
- Only 6 of `ViewState`'s 25 fields are read (enemy_hp/max, enemy_void_marks, is_player_turn, player_essence, player_mana). Traps, environment, flesh, forge, armour and enemy resources are written and never read.
- UI that reads the live engine and so runs **ahead** of the animations:
  - `EnemyHeroPanel.update(st)` reads enemy essence, mana and hand size live (~:434-443). A whole enemy turn resolves at once, so these show end-of-turn values during playback.
  - `CombatUI.on_state_void_marks_changed` ignores the payload and pushes live `state.enemy_hp` (~:58), so the HP bar jumps ahead of pending damage. PHASE_TRANSITION does the same (CombatPresenter ~:241).
  - Flesh, forge, traps and environment handlers discard the payload and re-read live state (CombatUI ~:94-110 → PipBar ~:517, :707; TrapEnvDisplay ~:109, :137). Korrath badges and CounterWarning read live.
  - BoardSlot keyword icons, shield, corruption colour, can_attack and buff glow read the live minion (~:583, :652-739). Task 046's follow-up already notes this.
- The rune placement VFX targets `traps.size()-1` live (CombatVFXBridge ~:260) and ignores `TRAP_PLACED.payload.slot`. It hits the wrong slot when the enemy places two runes in one turn.
- Input vs. view: Targeting validates against the engine's taunt state but highlights view slots (~:82-86).
- UI prompts go through `state._log` into the gameplay journal (CombatScene ~:1175, :1310-1329).

**Direction.**
1. Every UI refresh reads **the event payload or ViewState**, never `state.`.
2. Widen the snapshots: `minion_stat_payload` gains keywords, shield, corruption and can_attack; the hero events carry resources and hand size.
3. Delete the unread ViewState fields, or start reading them. There should be one place per displayed value.
4. Lint: no `state.` reads in `combat/ui/`, BoardSlot, TrapEnvDisplay or CombatUI outside setup and a small allowlist.
5. UI prompts go to a UI-only log channel, not the gameplay journal.

**Candidate tasks.** E1 (S) rune-slot bug + the live-HP push (bugs; could go straight to tasks). E2 (M) enemy panel, pip bar and trap/env displays from payloads. E3 (M) BoardSlot status visuals from snapshots (task 046 follow-up). E4 (S) lint. E5 (S) ViewState cleanup. E6 (S) prompt channel.

**Groomed 2026-10-01 → tasks.**
- E1 → tasks 070 and 071:
  - 070 (E1a): the rune VFX and trap panels follow the journal. Step 1 (use `payload.slot`) can ship at once; the panels wait for task 050.
  - 071 (E1b): the enemy hero panel renders the view, never live state. It also takes E2's enemy-panel part.
- E2 → task 109: player resource widgets, Korrath badges, counter warning and environment panel.
- E3 → task 110, coordinated with F1, which also widens payloads.
- E4 → task 111: lint L17, as a ratchet.
- E5 → task 109, as its last phase.
- E6 → task 112. Attack narration moves into the engine.
- New E7 (target highlights agree with the engine when the view lags) → task 113. It is needed because QN5 keeps input responsive.
- Straight-to-task bugs:
  - the rune placement VFX hits the wrong slot → task 070;
  - the enemy HP bar drains early on a Void Mark → task 071;
  - max-mana / max-essence growth outside the turn flow is not journaled (Font of the Depths, Void Hourglass) → task 069;
  - the Void Bolt hit pops twice → task 115 (F2).

**Evidence corrections (2026-10-01).**
- The enemy panel's essence, mana and hand labels lag rather than run ahead. They stay frozen at turn-start values, then jump when an enemy HP event or the player's TURN_STARTED plays.
- The live-HP push is reachable only through queued player input, because no single command does it with today's content. The PHASE_TRANSITION push is invisible today.
- The rune-slot bug is reachable on every F5 Void Ritualist main line: the second rune's VFX is skipped and the first rune vanishes early. F2c/F5 double placements and player ritual completion hit it too.
- UI prompts reach the journal through `state._log` from 23 sites (CombatScene 15, CombatInputHandler 6, CheatPanel 2), not 4. They include attack narration that exists only in live.
- `minion_stat_payload` already carries the shield amount. Keywords, has-shield, corruption, crit, armour and can_attack are missing.
- E depends on 048 for sequencing only (E2 and E3 share presenter code with it). E1a, E1b, E4 and E6 don't need it, and E overlaps F only in E3 and F1.
- Korrath and Oblivion Seal rune placements journal no RUNE_PLACED. HERO_BUFF_CHANGED and SPELL_COUNTER_CHANGED carry no payload.

---

## F. Look-ahead matched by cause, not by kind

**Problem (reported).** The presenter pairs damage events with animations by kind, taking the first match:
- `_play_attack` treats the first damage to the attacker as the counter-hit (CombatPresenter ~:568-574). But ON_*_ATTACK_PRE triggers and death triggers inside `_deal_damage(defender)` journal events *before* the counter. A death trigger that hits the attacker shows as the counter at the lunge, and the real counter pops afterwards.
- The spell capture (~:454-469) takes every DAMAGE, HEAL and CORRUPTION up to SPELL_RESOLVED, including damage from traps the spell set off. That damage shows at the spell's impact, before the TRAP_FIRED reveal.
- `_ahead` only tracks HP.
- Unknown VFX names and unknown event kinds just `pass` (~:651, :255).

**Direction.** The engine stamps a **cause id** on each event: a counter pushed and popped around each attack, spell, trap or trigger resolution, carried as `payload.cause` plus `payload.parent_cause`. The presenter consumes by cause id, not by kind and position. Unknown VFX names and kinds → `push_warning`.

**Candidate tasks.** F1 (M) cause-id stamping in the engine (digest-neutral). F2 (M) presenter consumes by cause. F3 (S) warnings. A LiveSmoke probe covering the death-trigger-hits-attacker and the spell-triggers-trap cases.

**Groomed 2026-10-01 → tasks.**
- F1 → task 114: it creates the Resolution class and stack, and I1 (task 129) extends it, so there is one stack, not two. Q7b raises its priority.
- F2 → task 115, after 114 and 048. It fixes the two reachable presenter bugs by cause, with no interim presenter hacks.
- F3 → task 116: classify every event kind, and warn on unknown VFX names and unclassified kinds.
- F-probe → task 115, as its acceptance probes. It uses Void-Touched Imp (VTI) under an attack, VTI under Arcane Strike, and a Void Bolt spell, because the trap variant has no real content.
- Straight-to-task bugs:
  - the Void Bolt hit pops twice → task 115;
  - the attack lunge shows the wrong strike or counter number → task 115;
  - a minion that dies mid-attack dies twice → task 057;
  - Matron of Flesh gains Flesh for its own death → task 059.

**Evidence corrections (2026-10-01).**
- Only the player's ATTACK_PRE/POST fire inside the attack window; the enemy's ON_ENEMY_ATTACK fires before ATTACK_STARTED.
- PRE damage to the attacker is latent. PRE damage to the defender is reachable (runeforge_strike → Grand Ritual: Chaos) and is taken as the strike.
- Spell-cast traps fire before SPELL_CAST is journaled, so the trap case is latent. The capture does swallow other trigger-caused events, and that is reachable: VTI's on-death AoE under Arcane Strike, and the enemy Blood Rune heal.
- The spell capture takes every match, not the first, and `_peek_window` doesn't skip consumed events.
- F doesn't depend on E: the cause id is stamped in `emit_event` whatever the payload. F2 depends on F1 (hard) and on 048 (soft).
- F3 needs a per-kind classification, because 21 of the 49 kinds have no `_play` case by design. All 14 VFX names have a case; HERO_SKILL is handled nowhere.

---

## G. AI consolidation

**Problem (reported).**
- `CombatProfile.gd` (1,170 lines, 45 funcs) mixes generic policy with encounter knowledge (`champion_void_herald` ~:958, `thrones_command` / `captain_orders` ~:966, `brood_call` ~:366, the `champion_` passive scan ~:553). Its spark cost copies the engine's rule and has drifted (task 051 fixes that).
- `grow_resources` is overridden **24 times**, each repeating the `turn<=1` / `e+m >= 11` prelude with the literal `11` although `COMBINED_RESOURCE_CAP` exists (CombatState ~:1358).
- Helper copies: `_play_minions_by_id` ×6, `_play_spark_spells` ×6, `_should_cast_pack_frenzy` ×6, `_spark_spell_priority` ×8, `_play_spells_by_id` ×5, `_is_feral_imp` ×5 (two signatures), `_empty_slot_count` ×5 (the agent already has `empty_slot_count`).
- Encounter profiles are used as base classes: Captain, Champion, RitualistPrime and Sovereign P1/P2 all extend VoidScoutProfile, so tuning F10 changes five bosses.
- Profiles read state directly: 17 `agent.state` reads in the base class, plus private members (`_minion_has_tag`, `_opponent_board`, `_has_talent`).
- **The scored AI stack is dead code** (~1,130 lines: ScoredCombatProfile, BoardEvaluator, ScoringWeights, 4 profiles). No deck selects a `scored_*` profile, BalanceSimBatch doesn't use it, `ScoredAITest.gd` doesn't exercise it, and the base class still carries `get_weights()` for it.
- There are 360 `await` sites in `enemies/ai`, and the drivers await the phases, but `Pacer` is a no-op. Adding one real await later brings back the task-045 loop-skipping bug.

**Direction.**
1. Growth curves as data: `{turn → (essence, mana)}` or a small curve spec, one generic `grow_resources`.
2. An AI toolkit (static helpers or `CombatAgent` methods) for the copied helpers. Profiles become thin policy.
3. Flatten inheritance: encounter profiles extend `CombatProfile` (or a *generic* faction base), never another encounter.
4. Profiles read through `CombatAgent` only; lint (with task 051's L12) against `agent.state.` reads.
5. Decide the scored stack: benchmark it once against the scripted profiles, then **delete or promote**. Don't maintain both.
6. Make profiles synchronous (drop `await`), and extend lint L6 (no await) to `enemies/ai`.

**Candidate tasks.** G1 (M) data growth curves. G2 (M) AI toolkit + dedupe. G3 (M) flatten inheritance (balance-neutral: verify with BalanceSimBatch byte-identical). G4 (S) scored stack decision. G5 (M) synchronous profiles + L6 extension. G6 (S) test that every card id quoted in `enemies/ai` exists (folds into D1).

**Groomed 2026-10-01 → tasks.**
- G1 → task 117, after J3 (139).
- G2 → task 118, after 051 and J3. It also covers the copied `mana_for_spark` rule.
- G3 → task 119, after G1, G2 and task 072. Its BalanceSimBatch gate requests Acts 1–4 explicitly.
- G4 → task 120, per Q7a:
  - keep `BoardEvaluator` + `ScoringWeights` with a test, as the seed of the look-ahead's evaluation function;
  - delete `ScoredCombatProfile` and the 4 scored profiles, and unregister them.
- G5 → task 121: the L6 extension first, then strip the no-op awaits.
- G6 → task 104 (D1).
- New G7 (direction 4: profiles read only through a side-aware `CombatAgent`, lint L18) → task 122. Task 051 step 6 calls this "G4" by mistake.
- Straight-to-task bugs:
  - F14/F15 hold their AoE spells unless the player has 2+ minions, and F15's lethal check ignores Sovereign's Decree's spark cost → task 072;
  - the player sim bots keep a slot free for the enemy's champion (sim only) → task 073.
- The decision below is answered (Q7, §12).

**Evidence corrections (2026-10-01).**
- The scored stack (1,129 lines) is still registered: ProfileRegistry and EncounterTable F1–F3 `variant_profiles` list it, and ScenarioTests S19 and CommandTests growth rows run it. Nothing in live play or BalanceSimBatch selects it.
- Extending VoidScout covers 5 profiles across 4 encounters (F12–F15), and it has already caused reachable AI bugs (task 072). F3's Matriarch profiles also extend F1's FeralPack.
- Most "helper copies" are tuned variants, not duplicates, and 4 of the 8 `_spark_spell_priority` copies are never called.
- The literal `11` is redundant, because the engine already enforces the cap.
- "One real await brings back the 045 bug" is unproven, since the root cause was never isolated. The risk is real and unguarded, though: L6 checks only CombatState.gd.
- BalanceSimBatch defaults to Acts 1–2, so a balance-neutral gate for G must request Acts 3–4 explicitly.

**Decisions.** Scored AI: delete or promote? Should the AI ever look ahead (clone a state and simulate)? If yes, task 049 and section I's static-flag fixes become prerequisites.

---

## H. Meta / run layer

**Problem (reported).**
- Run rules live in UI scenes. ShopScene has 59 `GameManager.` references and does purchases inline. Victory handling (shards, `advance_node`) lives in `CombatScene.gd` (~:1587-1609).
- The fight structure is three hand-synced constants (`GameManager.gd` ~:7-11: `ACT_SIZES`, `TOTAL_FIGHTS`, `BOSS_INDICES`). `BOSS_INDICES` isn't derived, and `CheatPanel.gd` ~:352 re-declares `ACT_SIZES`.
- The F15 phase swap is keyed on the profile id `"abyss_sovereign"` and repeats its passive list (PhaseTransition ~:24-30).
- `MapScene.gd` is unreachable (nothing navigates to it; last touched ~v0.26), but ARCHITECTURE.md's scene flow still lists it.
- Dead fields: `abyss_essence`, `abyss_essence_max`, `mana`, `mana_max` (0 references); `current_faction` is written but never read.
- `_make_btn_style` exists as 4 byte-identical copies plus 1 variant, and there are ~209 theme overrides across 11 scenes, even though `ui/theme/global_theme.tres` exists.
- Large UI files build their UI in code: EnemyHeroPanel (48 `X.new()`, 70 theme overrides; mixes HP bar, stats, Korrath badges, targeting pulses, champion pips and tooltip), PipBar (22/42), CardVisual (17/37 plus ~50 frame-layout consts).

**Direction.**
1. `RunService` (plain RefCounted, testable headless) owning purchases, rewards, `advance_node`, `grant_boss_unlocks` and victory/defeat bookkeeping. Scenes call it. It pairs with task 052's `RunState`.
2. Derive act sizes, total fights and boss indices from `EncounterTable`. Delete the CheatPanel copy.
3. PhaseTransition reads its phase-2 spec (passives, deck, profile) from EncounterTable.
4. Delete MapScene (or revive it deliberately) and the dead fields; fix ARCHITECTURE.md's scene flow.
5. Move shared button and panel styles into `global_theme.tres`; move static layout of EnemyHeroPanel / PipBar / CardVisual into `.tscn`; split EnemyHeroPanel by concern.

**Candidate tasks.** H1 (M) RunService. H2 (S) derived act constants. H3 (S) PhaseTransition from data. H4 (S) dead code removal + doc fix. H5 (M) theme consolidation. H6 (M) EnemyHeroPanel split / scene-based layout.

**Groomed 2026-10-01 → tasks.**
- H1 → task 123: size L, in phases (bookkeeping/routing, shop, rewards), after 052, H2 and C1.
- H2 → task 124. Every act boss now shows the BOSS label (QN6).
- H3 → task 125, after 047 and 050.
- H4 → task 080 (Q8: delete MapScene now). `current_faction` and `player_hp` stay with task 052. `last_boss_unlocks` is not dead: task 078 gives it a reader.
- H5 → task 126, narrowed to the textured button style.
- H5b (consolidate the remaining theme overrides) → deferred, to be done with the next UI or art pass.
- H6 → task 127, narrowed to the hero panels, after 071, 109 and 103.
- H6b (PipBar) → task 103 (C5).
- H6c (CardVisual consts to .tscn) → dropped: CardVisual already has a .tscn, and its table is per-frame data.
- New H7 (shop rules follow REWARD_SYSTEM_DESIGN, QN3) → task 128.
- Straight-to-task bugs:
  - after a purchase, every Buy button takes the last offer's state; Expand Core Unit at the 6-copy limit takes 3 shards for nothing → task 074;
  - Continue skips a pending card reward, shop or relic reward → task 077;
  - boss unlocks have been silent since v0.20 → task 078, which brings the reveal back (QN4).
- The decision below is answered (Q8, §12).

**Evidence corrections (2026-10-01).**
- There are four fight-structure constants, not three: `TOTAL_ACTS` too, which only MapScene reads. Copies the doc missed: BalanceSimBatch, BalanceSim and EncounterLoadingScene.
- EncounterTable entries have no `act` or `boss` key, so H2 has to add them before anything can be derived.
- The four "dead" resource fields have no readers, but `start_new_run` still writes two of them.
- EnemyHeroPanel has 52 `.new()` calls and PipBar 24, not 48 and 22.
- CardVisual's "~50 consts" are 55 rects in one per-frame `_FRAME_CONFIG` table, and the file already has a .tscn.
- `is_boss_fight()` is true only for fight 15, so act bosses show no BOSS label.
- ARCHITECTURE.md's scene flow is wrong beyond MapScene.
- The dependencies are per candidate: H2, H4 and H5 need nothing, H3 needs 047 and 050, and H1 needs 052 and C1.

**Decisions.** Is MapScene coming back (a branching map is common in roguelikes), or is the linear run final?

---

## I. Engine robustness

**Problem (reported).**
1. **Values passed between resolutions through state fields.** `_last_attacker`, `_last_attack_was_crit`, `_pending_dmg_source` (with a `"__logged__"` sentinel ~:977), `attack_cancelled`, `_spell_cancelled`, `enemy_play_target` and `_silent_buff_apply` all live on the state. A nested resolution (a trap or spell firing inside an attack) reads another resolution's values. For example, a spell kill during an attack is credited to the attacker and inherits its crit flag.
2. **Process-wide statics.** `MinionInstance.corruption_inverts_on_friendly_demons` and `iron_resolve_active` (MinionInstance ~:14, :19) are set from talents in CombatSetup, not per state. The BuffSystem signal bus is global: each state's `_on_corruption_removed_bus` accepts *any* minion, including another state's. Two live states (a sim during live play, AI look-ahead, tests) cross-talk, and one state's `teardown()` resets the other's flags.
3. **Iteration and re-entrancy.** 57 board loops iterate the live array; only 11 use `.duplicate()`. Their inner calls can kill or summon. Example: the `_remove_rune_aura` loop (~:351) → `remove_one_source` → corruption_removed → Corrupt Detonation damage → a board erase mid-loop. `TriggerManager.fire()` has no recursion depth guard, and a handler unregistered mid-fire still receives the current event. PhaseTransition runs inside `_on_hero_damaged`, possibly mid-AoE, then clears the board. "Alive" means `current_health > 0` with no zone flag, so banished minions look alive to anything still holding a ref.
4. **Signals and journal duplicate each other.** Of 24 signals, ~14 have no listener and 3 are test-only. There are dead buses: BuffSystem `buff_applied` (still computing before/after stats on every apply), the SacrificeSystem bus and `attack_resolved`. They have already drifted: `_update_environment_display` emits a signal but journals nothing.
5. **Digest blind spots.** `digest_text` omits `kill_stacks`, `aura_tags`, `attack_riders`, `formation_fired`, graveyard contents, spell counters, cost auras and champion counters, so Parity can't see divergence there.
6. **Dictionaries used as structs.** DamageInfo is mutated in place (CombatManager ~:207) and aliases the caller's dict. `plan_cost` returns a dict. Event payloads are read with `p.get(k, 0)` defaults that hide missing keys. `MinionInstance.buffs` is untyped, and BuffSystem duck-types `target.buffs` / `target.armour`. Targets are Variant (a minion, the String `"enemy_hero"`, trap or environment data). Traps are shared `TrapCardData` resources with no per-copy identity.
7. Smaller: the deathless-save paths (CombatManager ~:280-289, CombatState ~:1119) set HP to 50 after DAMAGE_DEALT journaled `hp_after ≤ 0`, with no stats event after it, so the label may stay at ≤0 (**likely display bug**). `_check_champion_triggers` logs "3 Void Imps on board" for any champion (~:2153). `_korrath_place_random_rune` bypasses `_card_for`, so card overrides don't apply. The sim builds full LOG and stats events on every mutation, and the presence-aura recompute re-journals every minion on each summon or death.

**Direction.**
1. A `Resolution` context (typed class: source, attacker, crit, damage source, cancelled) pushed and popped per attack, spell or trap. It pairs with F's cause id; they are the same stack.
2. Move the statics onto CombatState; make the corruption-removed bus per state (or pass the state in the signal).
3. Iterate `.duplicate()` snapshots, lint board loops without it, add a depth guard in `fire()`, give minions a `zone` field (BOARD / GRAVEYARD / BANISHED / HAND) and let "alive" check the zone.
4. Delete signals with no listeners and the dead buses. Keep only what CombatDiagnostics or tests need, fed from the journal.
5. Extend `digest_text` to cover the omitted fields (expect Parity to find something).
6. Typed `DamageInfo`, `CostPlan`, `TargetRef` classes; `TrapInstance` per placed copy.
7. The small items can go straight to tasks after grooming (the deathless-save label is a likely bug).

**Candidate tasks.** I1 (M) Resolution context. I2 (S) statics per state. I3 (M) iteration safety + zone. I4 (S) signal/bus cleanup. I5 (S–M) digest extension. I6 (M) typed structs. I7 (S) deathless-save label, champion log message, Korrath rune override, sim journaling cost.

**Groomed 2026-10-01 → tasks.**
- I1 → task 129: it extends F1's Resolution class (task 114) and deletes the seven side-channel fields. It comes after 114, 134, 059, 060 and 051, and is a look-ahead prerequisite (Q7b).
- I2 → task 130, after 049. It is urgent under Q7b: 049 alone leaves the statics and the global bus shared between states.
- I3 → task 131, after I1 and 057. Its zone field replaces 057's board-membership check.
- I4 → task 132. It also takes B8.
- I5 → task 133, after 051.
- I6 → task 134. Its typed DamageInfo is a prerequisite for I1.
- I6-traps (TargetRef, per-copy TrapInstance) → task 084 (A2).
- I7 → split:
  - I7a (deathless label) → task 061;
  - I7b (`_card_for` bypass) → task 058;
  - I7c (champion log text) is folded into task 096, which builds the text from the spec;
  - I7d (journal noise) → task 136, after 061 and 135.
- New I8 (idle-consistency probe: every board slot shows the engine's stats once the presenter is idle) → task 135.
- Straight-to-task bugs:
  - Imp Talisman gives Lord Vael an un-boosted Void Imp → task 058 (with three latent sibling sites);
  - Matron of Flesh's kill credit → task 059;
  - an attack's crit flag leaks onto nested damage → task 060;
  - the deathless-save HP label stays at ≤0 → task 061.

**Evidence corrections (2026-10-01).**
- No trap or spell resolves inside an attack today. What does nest is on-death, corruption and champion effects, which inherit the attacker and its crit flag; that part is reachable (tasks 059, 060).
- Two live states exist at once today only in tests that skip teardown. Statics cross-talk becomes reachable with the look-ahead (Q7).
- There are 64 board loops and 12 of them copy the board first (doc: 57 and 11). With current content none can erase from or append to the board it iterates: latent.
- The `_remove_rune_aura` example can't happen: only Dominion Rune has a tagged aura, and it never strips Corruption.
- PhaseTransition firing mid-AoE isn't reachable with F15 content. What is reachable is a lethal hero attack running its POST triggers on the Phase-2 hero.
- 4 signals have only test listeners, not 3.
- DamageInfo aliasing is latent, because every caller builds a fresh dict.
- The champion log text is right for all current content (Nyx'ael is the only auto-summon champion): latent. Imp Talisman's `_card_for` bypass is reachable; its three siblings are latent.
- The digest omits more than the section lists.

---

## J. Tests & tooling at scale

**Problem (reported).**
- `TriggerHandlerTests.gd` is a single 3,504-line file. Tests are registered by hand in each `run_all` (188 calls there), so a new test that isn't listed never runs.
- Isolation: CardEffectTests builds 92 states and calls `teardown()` once; DamageTypeTests builds 39 and calls it 0 times. Given the static flags (I2) and the leak (task 049), results can depend on run order.
- Zero coverage: save/load round-trip, `advance_node` / `is_act_complete` / `grant_boss_unlocks`, reward and shop pools, talent unlocks, relic offers, SavedDecks, DeckBuilder. The AI is tested only through growth curves and "clean finish" scenarios.
- Parity and LiveSmoke run with `presenter.instant = true`, so the look-ahead and animation paths never run over a full fight (task 048 adds a non-instant run).
- The lint is regex-based:
  - L8's `\bstate\.\w+\s*=[^=]` misses `+=` / `-=`, and its file list is hand-maintained and excludes CombatScene;
  - aliasing (`var s := state`) escapes every rule;
  - L7 detects a profile table by counting more than 3 preloads;
  - `strip_comment` ignores escaped quotes;
  - `ENFORCED` holds every rule, so the "not yet enforced" path is dead, and `RNG_ALLOW` is declared twice;
  - L10's `*VFX.gd` glob misses `*Projectile.gd`, CombatVFXBridge (9 timers) and CombatScene, and 16 VFX files still hand-roll timers.
- Stale debug scripts: `VoidboltDmgDebug.gd` (hardcodes F6 HP 4000, calls `CombatSim.run` with 11 positional args) and `DebugF13LossAnalysis.gd` (reads `"f13_a"` from the user file). They compile but nothing runs them.
- VFX wiring is string-keyed across 4–5 files: rules emit `{name}` → `_play_vfx` match (16 names) → scene forwarder → bridge method → `*VFX.gd`. `_SPELL_DISPATCH` is called via `call(method_name)`. `CardVfxRegistry.has_token_summon` duplicates the `play_token_summon` match, and if they drift a slot stays frozen. There's dead VFX code (`try_play_token_summon`, `play_demon_ascendant_tail_for`, `_dmg_color`). CombatScene still has 62 one-to-three-line forwarders and ~270 dynamic accesses to underscore-private scene members through `Node`-typed handles.

**Direction.**
1. Auto-discover `test_*` methods in the harness; split test files by subsystem; auto-`teardown()` after each test.
2. A MetaTests layer with a temp save path (pairs with task 052 and H1).
3. An AI behaviour test per encounter profile: decisions on a fixed board, not only "the fight finishes".
4. Lint: fix L8 compound assignment; widen the L10 glob; consider an AST-based linter (gdtoolkit) for L8 and L12. Delete the dead `ENFORCED` path and the duplicate `RNG_ALLOW`.
5. Fold the stale debug scripts into BalanceSimBatch flags or delete them; `CombatSim.run` takes a `CombatConfig`, not 11 positional args.
6. VFX: one card-id → Callable registry checked at load against CardDatabase; type the scene handles as `CombatScene`; delete the forwarders and dead VFX code.

**Candidate tasks.** J1 (M) harness auto-discovery + auto-teardown + file split. J2 (M) MetaTests. J3 (M) AI behaviour tests. J4 (S) lint fixes. J5 (S) debug script cleanup + `CombatSim.run(config)`. J6 (M) VFX registry + scene handle typing + forwarder removal.

**Groomed 2026-10-01 → tasks.**
- J1 → task 137, narrowed to a registration lint (L15) and a split of TriggerHandlerTests:
  - auto-teardown is task 049's (step 3);
  - auto-discovery is not proposed: it would need 351 renames, and a test missing the prefix would silently never run, which is the same failure.
- J2 → task 138. The save/load tests and the MetaTests layer are task 052's; the pool phase waits for C1/C2.
- J3 → task 139: one fixed-board probe per encounter profile, none for the scored profiles (Q7a). It lands before G1–G3 and G5.
- J4 → task 140.
  - Kept: L8 compound writes, a derived file list including CombatScene, a wider L10, escaped quotes, and the L7/L6 gaps.
  - Dropped: deleting `ENFORCED`, which is the staging path for new rules, and the "duplicate `RNG_ALLOW`", which doesn't exist.
- J5 → task 141. It also covers ScoredAITest, which the review missed.
- J6 → task 142, in phases. The card-id registry check folds into D1 (task 104), and the unknown-VFX warning is F3's (task 116).
- New J7 (CombatScene stops writing the engine flags `_combat_ended` / `_pending_revive`) → task 140.
- New J8 (test and tool doc drift in TESTING.md, CLAUDE.md and ARCHITECTURE.md) → task 137.
- No straight-to-task bugs: every unit-J problem is latent.

**Evidence corrections (2026-10-01).**
- `_play_vfx` has 14 names, not 16. The 15 emit sites use exactly those 14.
- `RNG_ALLOW` is declared once, not twice.
- Run-order dependence is a hazard, not an observed failure. CombatSetup resets the statics on every build; the real cross-talk is stale states left on the BuffSystem bus (049, I2).
- AI coverage also includes 35 growth rows and a few agent probes. What's missing is a decision probe per encounter.
- LiveSmoke's other 4 scenarios already run animated (time scale 0.05). Only the AI-vs-AI fight and Parity run instant.
- Aliasing escapes L4, L8, L9 and L11, but there is no state alias in presentation code today: latent.
- L8's exclusion of CombatScene hides real engine-flag writes (J7). L10 counts only one spelling of the timer call.
- The stale debug sims also include ScoredAITest, and DebugF13LossAnalysis has a lambda-capture bug that makes its per-turn damage cumulative.

---

## 11. Sequencing rationale

This is the order after grooming pass 1 (2026-10-01). The hard dependencies are each task's `depends_on`; this list is the order to pick work in.

**The ticket-by-ticket order is in [IMPLEMENTATION_ORDER.md](IMPLEMENTATION_ORDER.md):** 14 phases covering all 96 open tasks (047–143), with parallel lanes, a retune checkpoint after P3, and the decisions to make before each phase. It supersedes the coarse list below where they differ.

1. **Straight-to-task bugs first (057–078).** They are reachable today and small. Each fix that changes behaviour records its BalanceSimBatch delta (Q3). Two have a hard dependency:
   - 070's panel half waits for task 050 (its step 1 can ship at once);
   - 075 follows 074.
2. **Tasks 047–055, then the cheap cleanups 079–081 and D1 (task 104).**
   - 047–055 fix live bugs and remove noise (leaks, statics resets, unstable decks) that would muddy the refactors' parity and balance checks.
   - 079–081 delete CARD_LIBRARY.md, MapScene with the dead GameManager fields, and unreachable passive content.
   - D1 comes after 081. It makes every later rename or migration safe.
3. **Look-ahead prerequisites (owner Q7b).**
   - 049 → I2 (130).
   - F1 (114) → I6 (134) → I1 (129). I1 also waits for 059, 060 and 051.
   - The profile half of the look-ahead (synchronous profiles, and reads only through `CombatAgent`: tasks 121 and 122) comes with G in step 8.
4. **C (100–103) before the next hero is designed.** 100 goes first, then 101 (after 075) and 102. 103 follows 055. C is mostly outside combat.
5. **A (Side model)**, the foundational engine change.
   - First A0 (082, after 047) and A5 (088).
   - Then A1 (083) → A2 (084, after 050) and A6 (085).
   - Then the per-side mechanics 089–093, one mechanic per task, each recording its delta. 089 needs only 062 and D1, 090–092 need A1, and 093 needs A2.
   - Then A3 (086), the wide PvP-ready variant, in phases.
   - A4 (087) lands early as a ratchet, with its baseline set once 050/051/054/055 are in.
6. **B after A1**, because the modules hang their per-side data on `SideState`.
   - B1 (094, after 051) and B2a (095, after 066/067) don't need A1 and can go as soon as their dependencies land.
   - Then B2 (096, after 104 and 068) and B3 (097) → B4 (098).
   - B7 (099) comes last. B5 is deferred.
7. **E/F after 048.**
   - E1's two halves are bugs (070, 071) and go in step 1.
   - F2 (115) follows F1 (114) and 048; E2 (109) and E3 (110) follow 048.
   - E4, E6, E7 and F3 (111–113, 116) can go any time.
8. **G, H, I and J interleave** as capacity allows.
   - J3 (139) lands before G1–G3 and G5 (117–119, 121), which are meant to be balance-neutral. G4 (120) can go any time.
   - H2 (124) comes before H1 (123), which also waits for 052 and 100.
   - I3 (131) follows I1, and I8 (135) comes before I7d (136).
   - J1 (137) follows 049.

Every engine step keeps the existing gates: `tools/run_checks.sh` green (it includes Parity). A step meant to be behaviour-neutral must also leave the seeded balance fingerprint unchanged: run `BalanceSimBatch -- --act <N> --runs 200 --seed 7` before and after, for every act it can touch, and the diff must be empty (design/TESTING.md, "Refactor / extraction work"). A step meant to change behaviour records its BalanceSimBatch delta in the task summary, as the unification plan did. Parity stores no golden digests; it compares live and engine within one run. So "Parity byte-identical" is not a neutrality check (corrected 2026-10-01).

BalanceSimBatch defaults to Acts 1–2, so a task that touches Act 3–4 content (fights 7–15 and their profiles) must request those acts explicitly in its gate.

## 12. Owner decisions (collected)

All eight were answered by the owner on 2026-10-01 (grooming pass 1).

| # | Question | Blocks | Answer (owner, 2026-10-01) |
|---|---|---|---|
| Q1 | Is PvP / enemy-hero play a real goal, or is symmetry hygiene only? | A3 scope | **PvP / mirror matches are planned.** Full symmetry is a product goal: A1–A4 in full, and A3 is a priority. |
| Q2 | Which one-sided mechanics are intended (relics, Void Marks, talents)? | A0 verdicts | **None.** Relics, talents and hero passives, hero resources (Flesh, Forge, Void Marks) and rituals must all work for either side in the engine. The enemy doesn't have to use them today, but an enemy or a PvP opponent may one day. Who has what is decided by data and config, never by `if owner == "player"` in rules code. |
| Q3 | Accept balance shifts when enemy-side triggers start firing? | A, 050 | **Yes.** One mechanic per task; each task records its BalanceSimBatch delta in its summary; retune afterwards if needed. |
| Q4 | Champions: a module each, or a data spec table? | B2 | **A data spec table if at least 80% of champions fit it;** the outliers get a small module. |
| Q5 | Shop `vael_common`: always, or only as a fallback? Collection shows all heroes? | C1 | **Always:** the hero's common pool (vael / seris / korrath) is offered alongside the unlocked branch pools. **The Collection shows every hero's cards,** grouped by hero, then pool. |
| Q6 | CARD_LIBRARY.md vs CardDatabase: which is the source of truth, and generate the other? | D6 | **CardDatabase.gd is the source of truth; delete CARD_LIBRARY.md.** The file has had one commit (the 2026-04-28 import) and is missing all of Korrath and the Avatar. Every column it has is a CardData field, and nobody noticed the gap for five months. Design intent stays in the hero and faction design docs; browsing is the Collection's job (Q5). The deletion also fixes CLAUDE.md, CARD_DESCRIPTION_STYLE.md and CARD_POOL_ARCHITECTORE.md, which point at it. ARCHITECTURE.md invariant #10 already says this. |
| Q7 | Scored AI: delete or promote? Will the AI ever look ahead? | G4, I2 | **Look-ahead is planned.** Keep `BoardEvaluator` + `ScoringWeights` as the seed of its evaluation function (with a test); delete `ScoredCombatProfile` and the 4 scored profiles. Task 049, I1 and I2 become prerequisites, and profiles must be synchronous and read only through `CombatAgent`. |
| Q8 | MapScene: revive (branching map) or delete? | H4 | **Delete it now.** The run stays linear (git history keeps the file). Fix ARCHITECTURE.md's scene flow. |

### Decisions raised by grooming pass 1 (owner, 2026-10-01)

The re-verification turned up six new questions. The owner answered all of them.

| # | Question | Answer (owner, 2026-10-01) | Shapes |
|---|---|---|---|
| QN1 | Champion card text and tooltips disagree with the code, and the F5 Void Ritualist's rune-cost aura was never implemented. Which wins? | **Code wins; drop the Void Ritualist aura.** Card text, CHAMPION_INFO and PASSIVE_INFO change to match the code: Rift Stalker 1000, ACP 5, Void Wraith 2 Spirits plus its crit-on-death aura, RIP 300/400. The VR "rune placement costs 1 less Mana" text is deleted everywhere. Balance-neutral. The missing tooltips are added (F13–F15 champions, Act 3–4 passives). | task 068; task 096 later generates the text from the spec |
| QN2 | What should the shop's core-unit services give Seris and Korrath? | **The hero's own core unit.** Expand Core Unit adds Grafted Fiend (Seris) or Abyssal Knight (Korrath) and raises that hero's core-unit cap. Core Unit Variant is hidden for non-Vael heroes until variants are designed. | task 075, then 101 |
| QN3 | The shop's rules differ from REWARD_SYSTEM_DESIGN.md (service weights, first-shop services, Max HP price, first-shop detection). Which wins? | **The design doc.** A weighted service draw of 3/3/3/3/2/1/1, no Second Wind in the first shop, Max HP Increase costs 4, and the first shop is derived from run position, not shards. | task 128 |
| QN4 | Boss card unlocks have been silent since v0.20 (`last_boss_unlocks` is write-only). Bring a reveal back? | **Yes.** Show the cards a boss kill permanently unlocked, in RelicRewardScene or a short screen after the boss. `last_boss_unlocks` gets a reader. | task 078 (080 keeps the field) |
| QN5 | Player input isn't gated on the presenter. Gate it on presenter idle, or make the UI correct during playback? | **Keep player input responsive** (no gating on presenter idle). The display fixes (E1–E3, E7) make the UI correct during playback instead, so E7 is needed. | tasks 070, 071, 109, 110, 113 |
| QN6 | The BOSS label shows only on fight 15. Should act bosses show it too? | **Yes, act bosses too.** Every act boss (fights 3, 6, 9 and 15, the `BOSS_INDICES`) shows the BOSS prefix, and `is_boss_fight()` covers all boss indices, derived from EncounterTable (H2). | task 124 |

### Open questions and unowned findings after pass 1 (2026-10-01)

The pass-1 consistency check raised these. The tasks named below record a default; confirm or override it when the task starts. Items with no task are for the next grooming pass.

**Owner questions (default recorded in the task):**
- Task 057: if the defender (or the attacker) leaves the board during PRE triggers, the attack is spent, with no strike and no counter.
- Task 065: Energy Conversion overflow is kept as temporary excess (DESIGN_DOCUMENT.md:151), not capped at `mana_max`.
- Task 067: the Avatar's counter carries over into phase 2. This is a grooming ruling from the in-code intent, not an owner decision.
- Task 068: once the text is fixed, the Void Ritualist has no aura, although DESIGN_DOCUMENT.md:773 says champions have an aura or keyword.
- Task 129: kill credit for counter-kills and nested kills; also its step 10 (Dark Channeling amplifies only the spell's own damage steps), which is a behaviour change.
- Task 131: does the phase-2 Sovereign inherit phase-1 hero debuffs?
- No task: `kill_minion` ignores DEATHLESS, so Death Trap's KILL_MINION destroys a Deathless minion. Should "destroy" bypass Deathless?
- No task: the Act 1 boss can never unlock a card (`_UNLOCK_CHANCE[1]` is dead), and Nyx'ael's unlock condition (REWARD_SYSTEM_DESIGN §3) is not implemented.
- Tasks 077 / 052: resuming a run re-rolls shop and reward offers for free (save-scumming).

**Unowned findings (no task yet):**
- A draw into a full hand burns the card with no event or log (`CombatState.gd:1564-1566`).
- Merging the three spell-cast paths into one `cast_spell(side, …)`: task 082's row 20 has no owner, and task 097 declines it.
- Void Herald's `_champion_vh_summoned` is used to mean "Herald alive" but stays true after its death (task 122 ports it unchanged).
- CorruptedHandler's header and code disagree on the feral-imp play order (an owner/balance call; tasks 118 and 139 pin the code).
- Roadmap I6's `p.get(k, 0)` payload defaults have no owning task.
- Task 050's optional `place_trap` list misses Voidshaped Acolyte's PLACE_RUNE_ON_OPPONENT and the journaling of Korrath's rune append (tasks 070, 084 and 093 cover these conditionally).
- Tasks 104 and 106 assume Godot 4.6 prints `push_error` as `ERROR:`, not `SCRIPT ERROR:`. Check this before landing them.

**Filed from the check:** task 143. Per-copy cost discounts (`essence_delta` / `mana_delta`) are shown in hand but never charged for minions or spells. Reachable today through Squire of the Order → Abyssal Knight.

## 13. Grooming log

Grooming passes append here: date, what was re-verified, which items became which tasks, what was dropped.

| Date | Task | Result |
|---|---|---|
| 2026-09-25 | — | Doc written from the architecture review. Short-term fixes filed as tasks 047–055. Grooming task 056 opened. |
| 2026-10-01 | 056 | Pass 1. Re-verified all of A–J at `404b51c`: 12 unit reports, plus adversarial re-checks where they finished (A-paths, C); the corrections are listed per section. Filed 87 backlog tasks, 057–143 (143 came from the consistency check): 22 straight-to-task tasks (057–078: 19 bugs, E1's two halves and the boss-unlock reveal), 3 cleanups (079–081) and 61 roadmap tasks (082–142, including 4 new per-side mechanic tasks from Q2, 090–093). Merged: C3 = D5 = D8 → 102, C4 → 100, B6 → 097, B8 → 132, G6 → 104, E5 → 109, F-probe → 115, I6-traps → 084, I7c → 096, H6b → 103, J7 → 140, J8 → 137. D6 was replaced by 079 (delete CARD_LIBRARY.md). Deferred: A7, B5 and H5b. Dropped: H6c, and D8's inheritance mechanism. The owner answered Q1–Q8 and QN1–QN6 (§12). Task 056 closes; the next pass re-checks the deferred items after 047–055 land. |
