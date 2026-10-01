# Architecture Roadmap — longer-term structural work

**Status:** ungroomed backlog. Grooming is task 056. Nothing here is scheduled yet.
**Written:** 2026-09-25, from a four-part architecture review (engine core; content & effects; presentation & VFX; AI, meta-game, tests & tooling) at `e66f13e` plus the uncommitted task 046 diff.
**Audience:** the owner deciding what to do and when, and a coding agent grooming this into tasks. Each item says what's wrong, the evidence, why it matters as the game grows, a proposed direction, candidate tasks and decisions for the owner.
**Companion:** the short-term fixes from the same review are already tasks **047–055** (enemy decks in repo, presenter soft-lock, reference-cycle leak, EffectResolver side bugs, AI state writes, save robustness, debug gating, log constants, GameManager read). This doc does not repeat them; it notes where they overlap.

> **How far to trust the evidence.** Items marked **(verified)** were checked by hand against the code during the review. Everything else comes from the review agents' reports: specific and file-anchored, but not re-checked. Line numbers will drift, so match on the quoted code, not the number. Grooming (task 056) re-verifies each item before turning it into a task.

---

## 0. Summary

The core architecture is sound, and the live/sim unification (Phases 0–5) worked:
- one engine behind a validated command surface, with a journal and a presenter;
- seeded, replayable fights;
- lint L1–L11, a parity test and a live smoke test.

The debts below are about **growth**. Each new hero, champion, card or mechanic currently costs more than it should, and several failure modes are silent (a misspelled id, a one-sided effect, UI showing values before the animation that explains them).

| ID | Workstream | Size | Payoff | Depends on |
|---|---|---|---|---|
| **A** | Side model: `Side` + `SideState`, real symmetry | L | Highest. Removes a whole class of silent one-sided bugs; required for enemy heroes, mirror matches or PvP | 050 (small version first) |
| **B** | Break up CombatState: hero/champion modules, diagnostics, command processor | L | New hero or champion becomes one module instead of 6–10 files | A (ideally), D1 |
| **C** | Hero / branch / pool data model | M | A 4th hero touches ~6 files instead of ~18; kills 4–5 diverged copies | — |
| **D** | Content validation and effect-system extensibility | M | Typos fail at load, not in play; new effect types without editing a central match | — (D1 first, it's cheap) |
| **E** | Presentation reads only the journal (single display source) | M | UI never runs ahead of animations; one place for display state | 048 |
| **F** | Look-ahead matched by cause, not by kind | S–M | New cards can't show damage at the wrong moment | E (shares payloads) |
| **G** | AI consolidation | M | Less copy-paste; boss tuning stops leaking across encounters; one AI style | 051 |
| **H** | Meta / run layer | M | Testable run logic; constants derived from EncounterTable | 047, 052, C |
| **I** | Engine robustness (side-channel flags, statics, re-entrancy, digest) | M | Fewer subtle interaction bugs; parity sees more state | 049 |
| **J** | Tests & tooling at scale | M | Tests auto-discovered, isolated, covering meta; sturdier lint | 049 |

Suggested order: **D1 → C → A → B**, with **E/F**, **G**, **I** and **J** interleaved as capacity allows. The reasoning is in section 11.

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
- A1 (M): introduce `Side` + `SideState`, move hand/deck/graveyard/resources, keep the old accessors as thin forwarders. Parity and digests must be byte-identical.
- A2 (M): move traps, environment, board and hero into `SideState`; single `remove_trap` / `set_environment` (extends task 050).
- A3 (L): side-neutral trigger events, migrate CombatSetup registrations and handlers, update the `handler_order.txt` snapshot deliberately.
- A4 (S): lint rule: no `"player"` / `"enemy"` literals in rules code outside a small allowlist (serialization, logs).

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
5. `PipBar` picks widgets from the combat config / HeroData, not from `GameManager` (~:194-198).

**Candidate tasks.** C1 (M) BranchData + `active_pools()` + delete copies (fixes the Korrath/Shop/Collection divergence). C2 (S) HeroData carries core unit, copy rules and skills. C3 (M) pool/gate on the card, CardDatabase split per pool (see D5). C4 (S) test: every hero has ≥1 branch; every branch's pools are non-empty and resolve.

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

---

## F. Look-ahead matched by cause, not by kind

**Problem (reported).** The presenter pairs damage events with animations by kind, taking the first match:
- `_play_attack` treats the first damage to the attacker as the counter-hit (CombatPresenter ~:568-574). But ON_*_ATTACK_PRE triggers and death triggers inside `_deal_damage(defender)` journal events *before* the counter. A death trigger that hits the attacker shows as the counter at the lunge, and the real counter pops afterwards.
- The spell capture (~:454-469) takes every DAMAGE, HEAL and CORRUPTION up to SPELL_RESOLVED, including damage from traps the spell set off. That damage shows at the spell's impact, before the TRAP_FIRED reveal.
- `_ahead` only tracks HP.
- Unknown VFX names and unknown event kinds just `pass` (~:651, :255).

**Direction.** The engine stamps a **cause id** on each event: a counter pushed and popped around each attack, spell, trap or trigger resolution, carried as `payload.cause` plus `payload.parent_cause`. The presenter consumes by cause id, not by kind and position. Unknown VFX names and kinds → `push_warning`.

**Candidate tasks.** F1 (M) cause-id stamping in the engine (digest-neutral). F2 (M) presenter consumes by cause. F3 (S) warnings. A LiveSmoke probe covering the death-trigger-hits-attacker and the spell-triggers-trap cases.

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

---

## 11. Sequencing rationale

1. **Tasks 047–055 first.** They fix live bugs and remove noise (leaks, statics resets, unstable decks) that would muddy the refactors' parity and balance checks.
2. **D1 (content-lint test)** next: cheap, and it makes every later rename or migration safe.
3. **C (hero/pool data)** before the next hero is designed. It's medium-sized, mostly outside combat, and fixes live divergence.
4. **A (Side model)** is the foundational engine change. Do A0 (audit) early even if A1–A3 wait, because the audit decides how much of A is bug-fixing and how much is refactoring.
5. **B (CombatState breakup)** after A1. Modules want `SideState` to hang their per-side data on. B1 (diagnostics) and B2 (champion table) don't depend on A and can go any time.
6. **E/F** share the payload and cause-id work; do them together, after task 048.
7. **G, H, I, J** interleave as capacity allows. I2 (statics) and J1 (auto-teardown) are cheap and should come early.

Every engine step keeps the existing gates: `tools/run_checks.sh` green, Parity digests byte-identical unless the change is meant to alter behaviour (then record the BalanceSimBatch delta in the task summary, as the unification plan did).

## 12. Owner decisions (collected)

| # | Question | Blocks |
|---|---|---|
| Q1 | Is PvP / enemy-hero play a real goal, or is symmetry hygiene only? | A3 scope |
| Q2 | Which one-sided mechanics are intended (relics, Void Marks, talents)? | A0 verdicts |
| Q3 | Accept balance shifts when enemy-side triggers start firing? | A, 050 |
| Q4 | Champions: a module each, or a data spec table? | B2 |
| Q5 | Shop `vael_common`: always, or only as a fallback? Collection shows all heroes? | C1 |
| Q6 | CARD_LIBRARY.md vs CardDatabase: which is the source of truth, and generate the other? | D6 |
| Q7 | Scored AI: delete or promote? Will the AI ever look ahead? | G4, I2 |
| Q8 | MapScene: revive (branching map) or delete? | H4 |

## 13. Grooming log

Grooming passes append here: date, what was re-verified, which items became which tasks, what was dropped.

| Date | Task | Result |
|---|---|---|
| 2026-09-25 | — | Doc written from the architecture review. Short-term fixes filed as tasks 047–055. Grooming task 056 opened. |
