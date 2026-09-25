# Live / Sim Unification — Executable Refactor Plan

**Status:** revised after code verification. **Done: Phases 0–5** (Phase 4 started 2026-09-25 with 3.6 visual QA still open, at the owner's call). Left: 3.6 visual QA and the optional 4.5 (the D6 split — the parity test it waited for now exists).
**Written:** 2026-09-22 (task 039) · **Revised:** 2026-09-23 (verification pass against `1c9aa30`, see Appendix C)
**Progress:** Phase 0 **done** 2026-09-23 (task 040, commits 0.605–0.614). Deviations: lint baseline was 39 not ~25 (extra unforwarded diagnostic counters); `digest_text()` lives on `SimState` until 1.3 hoists hands/decks/resources; D7 turned out to be balance-neutral in sim (byte-identical batch). Phase 1 **done** 2026-09-23 (task 041, commits 0.615–0.620). Deviations: a third seam route, `[facade]`, for the 8 CombatScene overrides whose live body is still VFX-bound (kept on the shell until 3.0 — routing them to `state` would drop VFX); L4 is receiver-based (Dictionary `.get` is fine) and also bans `"x" in obj`; `is_player_turn`, `turn_number` (replacing `_current_turn`, which live never set) and `CombatHandlers` moved onto state in 1.3/1.4; `EnemyHeroPanel.update` had 10 call sites, not 14; `_temp_imps` (Imp Overload) and the void-bolt passive were dead and deleted; `tools/lint/load_all_scripts.gd` + a timeout watchdog joined `run_checks.sh`. Sim now follows live on draw-burn, generated-card ON_PLAYER_CARD_DRAWN, the turn flag, Void Devourer, Void Spawner Sparks, player champion auto-summon and heal clamping — batch Δ vs Phase 0: mean +1.2 pts, S.Forge +7.9 (Void Devourer). Phase 2A **done** 2026-09-23 (task 042, commits 0.621–0.629). Deviations: `cmd_end_turn` landed with the turn engine (2A.3); spark costs — profiles consume their fuel before playing, so agents credit it to the next play as `extra.sparks_prepaid` (commands also take `spark_fuel` or pick themselves); targeted spells accept a null target (SINGLE_CHOSEN's AI fallback); `void_manifestation` follows live (no Void Mark bonus); profiles check `can_place_trap` (3-slot cap now binds both sides); AI decision randomness moved to a per-agent `decision_rng` so replays reproduce; EncounterTable carries each encounter's variant profiles (EncounterDecks' variant→profile map lives in user data); L7 omits `start_combat` (TurnManager's façade keeps one until Phase 4). Owner decisions: D1 port, D2 live, D9 symmetric, D8 before, D10 next turn (pick recorded at once for Abyssal Mandate), D5 façade. Balance vs pre-2A (Acts 1–2, 200 runs, seed 7): mean +0.3 pts per act; F5 +1.8 (3-slot rune cap); F15 Swarm −7.3 (champion passive now in sim). Checkpoint closed 2026-09-24 (D11 SlotState, D3 inline, D4 hybrid — section 4). **Phase 3 in progress** (task 043): 3.1a (SlotState) landed first — 0.630; 3.0 done in five commits 0.631–0.635 (on-death, buffs, corruption/Void Mark/Void Bolt/traps/sacrifice, token summons/rituals, HardcodedEffects awaits + detonation) — every gameplay mutation is synchronous inside the engine, `[facade]` is empty, the VFX bridge only animates; B12 and B13 fixed. Deviations: the player's Demon Ascendant ritual runs the ritual's `effect_steps` (its projectile tail returns with 3.2); the ritual demon's sigil and other entrance animations play fire-and-forget until 3.2 sequences them. 3.1 done — 0.636: `CombatEvent` + `CombatState.journal` / `emit_event`, ~45 emit sites, old signals and hooks still firing. Deviations: kinds `TRAPS_CHANGED`, `SLOT_CHANGED`, `HERO_HP_CHANGED`, `HERO_BUFF_CHANGED`, `HERO_SKILL` added (view resync points), `TRAP_REMOVED` / `CORRUPTION_REMOVED` folded into `TRAPS_CHANGED` / `DETONATION`; `SPELL_CAST` is emitted inside the `cast_*` bodies (so live's pre-3.4 spell path journals too) and therefore after the ON_*_SPELL_CAST trigger; live minion plays and enemy plays journal `MINION_PLAYED` only from 3.4. 3.2 + 3.4 done together — 0.637: `CombatPresenter` (deferred-start drain, one awaited animation per event, look-ahead consumption for attacks / spells / Void Bolt, batched buffs and detonations, `VFX` events for card-specific animation), `ViewState`, `LivePacer`; semantic events are journaled *before* their slot mutation so the presenter can animate the departing / arriving minion; player input and the enemy turn are on the commands (`EnemyAgent` and EnemyAI's executors deleted); the scene's capture / deferred-death / immediate-mirroring machinery is gone. Deviations: 3.4 landed with 3.2 (the presenter needs the journal events only commands produce); the old gate variables remain set by the bridge until 3.3; the Seris skills stay direct state calls; no ChoiceModal cancel yet; the Demon Ascendant player ritual has no projectile tail (restore in 3.6 QA if wanted). 3.3 done — 0.638: every gate flag / signal and `VfxGate` deleted, the bridge's VFX are awaitables, play adapters renamed (`_command_play_*`). 3.5 done — 0.639: lint L8 (presentation never mutates), the AI-vs-AI live smoke in the real scene (`presenter.instant`), Cyclone through `cmd_play_spell` with the chosen trap / environment (its DESTROY step). 3.7 gates green. 3.6 (owner visual QA) still open. Phase 4 **done** 2026-09-25 (task 044, commits 0.640–0.643): `CombatConfig` + `CombatState.setup_combat` are the one setup path for live, sim, replays and tests; `CombatSetup.setup(state)` owns all trigger setup; `CombatDiagnostics` replaced SimState's reporting and `SimState` / `SimTriggerSetup` are deleted (lint L5 = nothing extends CombatState); rules code holds no shell and no presenter (the last presenter calls became journal events — `HAND_COSTS_CHANGED`, `SPELL_COUNTER_CHANGED`, `CHAMPION_PROGRESS`, `CHAMPION_KILLED`; `RITUAL_FIRED` carries its slots / runes; `EffectContext.state` is a typed field; the allowlists are deleted); CombatScene's 102 forwarders and 38 state delegates are gone, `TurnManager` is deleted, `EnemyAI` is `EnemyTurnRunner` with no enemy-side state; CombatScene 3,400 → 1,936 lines; lint L9 (no duck typing across the combat layer, relics, sim, AI). Deviations: 4.1–4.3 landed as one commit; `CombatConfig.from_encounter` is `from_dict` (CombatSim's JSON config, already keyed by encounter profile); the `_debug_*` counters stay with the other diagnostic counters on the state; L9 is receiver-based like L4 (a literal `.get("` ban would flag every Dictionary read); `PhaseTransition` swaps the enemy profile through a new `enemy_profile_changed` signal; the Seris skill buttons now issue `cmd_hero_skill`; end turn is `cmd_end_turn("player", growth)`. Behaviour changes: live registers triggers and relics before turn 1 (sim order); the player deck shuffles before the enemy's; the sim gets ancient_frenzy's opening Pack Frenzy (F3 −3 to −19 pts; every other Act 1 row and all of Act 2 byte-identical). Open: the F15 forced end of the player's turn is still issued by the presenter at PHASE_TRANSITION (the sim doesn't end the turn) — a Phase 5 parity item. Phase 5 **done** 2026-09-25 (task 045, commits 0.644–0.646). Verification of Phases 0–4 at `be36a94`: run_checks green (1109/1109), every 3.3 / 3.7 / 4.x grep gate held; leftovers were stale comments naming deleted gate flags, and plan 3.3's input gate had never been implemented. 5.0 (new): engine and live fixes the parity test surfaced — the F15 forced end turn is engine-side (`_finish_command` after every command; F15 batch mean −1.0 pt, Acts 1–2 byte-identical); the live input handler had called a scene helper deleted in 0.617 on every spell / minion selection (every such play errored live); the F15 banish left the slot views full; `cmd_play_minion` re-added a minion its own on-play had banished / killed; EnemyTurnRunner reseeded `decision_rng` on the profile swap. 5.1 / 5.2: `debug/tests/Parity.tscn` — 8 cases × 3 seeds, player commands through the scene's input entry points, enemy the live EnemyTurnRunner, records + digests compared per command, winner and fully played journal asserted (F1–F3 = every Act 1 encounter, so 5.2 lives in the parity test); LiveSmoke's AI fight is seeded. 5.3: L10 is enforced against a baseline (20) rather than a warning; new **L11** — names reached through an untyped scene handle must exist (the 0.617 crash class). 5.4 as planned, plus `/task-done` and CLAUDE.md. **Deviation (owner decision 2026-09-25):** the live enemy no longer awaits a `LivePacer` — with a pacer that really waited, GDScript occasionally skipped the rest of a profile's action loop on resume (the enemy stopped attacking mid-turn; ~1 in 18 loaded F6 runs; the same predicate evaluated true and false within one iteration). The enemy's turn now resolves synchronously on the base `Pacer`, exactly as in the sim; every command journals a `COMMAND` marker and the presenter plays the 0.55 s beats; `LivePacer` is deleted; input is accepted only once the presenter has shown the player's turn start (`CombatScene.player_can_act()` — lighter than 3.3's "presenter idle", so the player can still act during their own animations). Parity: 12 / 12 full runs green under 6× parallel load.
**Supersedes:** `COMBAT_STATE_MANIFEST.md` (the 0.54/0.55 state extraction — this plan finishes what that one started)
**Audience:** a coding agent executing one phase per session, plus the owner answering the decisions in 3.3. Every step names the file, the anchor, the change, and the check that proves it landed. Line anchors were verified at `1c9aa30`; expect drift of a few lines — match on the quoted code, not the number.

---

## 0. Why this plan exists

The architecture doc says "one CombatState, two shells (CombatScene / SimState)". The code has two rule engines held together by hand-maintained forwarding and duck-typing. Two costs follow:

1. **Live-only bugs that the suite cannot see.** Tests run on `SimState`; handler code written against `_scene.<x>` works in sim and crashes or silently no-ops on `CombatScene` when `<x>` isn't forwarded. Every new card/talent adds more of these (the Korrath batch added three).
2. **The balance sim does not simulate the game.** It runs enemy resource curves, turn-event ordering and turn-end handlers that live never runs. Every balance conclusion drawn from `BalanceSimBatch` carries that error.

### 0.1 Live bugs (verified; fixed in Phase 0 unless noted)

| # | Bug | Evidence | Effect |
|---|---|---|---|
| B1 | Unforwarded champion counters | `CombatHandlers.gd:1844,1969` do `_scene._champion_vrp_spells_cast += 1` / `_scene._champion_as_cards_played += 1`; fields exist only on `CombatState.gd:1554,1558`; no forwarder, no `_get/_set` on CombatScene. Handlers are registered live via `CombatSetup` for F13 / F15. | Script error on every spell (F13) / card (F15) |
| B7 | **Turn-end events never fire in live** | No fire site for `ON_PLAYER_TURN_END` anywhere (live or sim). `ON_ENEMY_TURN_END` is fired only by `SimState.end_enemy_turn` (`SimState.gd:590-593`). ~10 registered handlers: `CombatSetup.gd:124` (forge auras), `:329` (void_unraveling), `:387` (champion_vs), `:410` (champion_vch aura), `:489` (captain_orders), `:509` (abyssal_mandate), `:567-572` (hollow_sentinel, minion `on_turn_end_effect_steps`). | Those passives are dead in the real game; enemy-side ones are live in sim only → balance sim overstates those enemies. **Needs D7** |
| B8 | Korrath rune methods not on the scene | `CombatHandlers.gd:279` `_scene._korrath_place_random_rune()`, `:331` `_scene._korrath_absorbed_aura_count()`; defined only at `CombatState.gd:1501,1537`. | Script error for Runeforge Strike / Path of Demons / Path of Humans |
| B9 | Talent/passive stat flags written to the scene no-op | `CombatSetup._apply` / `apply_passive` (`:623`, `:635`) do `scene.set(stat, v)`; unforwarded keys (`_path_of_corruption_active`, `_armour_doubled_on_knight`, `_corrupting_presence_active`) are silently dropped. All 39 registry stat keys exist on CombatState. | Those talents are dead live (read at `EffectResolver.gd:728,755`, `MinionInstance.gd:239`, `CombatState.gd:905,1048`) |
| B10 | Unforwarded one-shot flags via `_scene.set/get` | `_champion_vrp_summoned`, `_champion_as_summoned` (written `CombatHandlers.gd:2416,2420`, read `:1842,1967`); `_imp_caller_fired` (`:1184-1194`); `_enemy_void_mana_drain_pending` (`EffectResolver.gd:347` writes via `ctx.scene.set`, `EnemyAI.gd:253` reads `scene.state.…`). The other five `_champion_*_summoned` flags **are** forwarded. | After a naive B1 fix, VRP / Abyss Sovereign would re-summon on every spell past the threshold; Imp Caller once-per-turn guard never engages; player-cast Void Rift Lord drain on the enemy is dead |
| B11 | Champion summon race | `CombatHandlers._summon_enemy_champion` (`:2380-2420`) `await`s `death_anims_done` **before** setting the `_summoned` flag. | A second qualifying death during the wait (AoE) can queue a second champion |
| B12 | Smoke Veil cancels the wrong attack | Live `_fire_traps_for` (`CombatScene.gd:3486-3497`) resolves the trap inside the card-anim callback ~1 s later; `HardcodedEffects._smoke_veil` (`:214`) sets `attack_cancelled` **after** `EnemyAI.do_attack_minion` checked it (`:503`). | The triggering attack lands; the stale flag cancels the *next* attack. **Fixed in Phase 3.0 (de-async)** — logged, not hotfixed |
| B13 | Corruption applied inside a VFX drain | During captured spells, corruption is deferred (`CombatScene.gd:2063`) and applied in the popup drains (`:4769, :4800`). | Gameplay mutation in presentation; live/sim can disagree within one spell. **Phase 3.0** |

### 0.2 Live ↔ sim divergences (verified)

| # | Divergence | Evidence | Gameplay impact today |
|---|---|---|---|
| B2 | Enemy resource growth | Sim: `CombatSim.gd:167` → `setup_resource_growth(state)` installs a `Callable(turn)` on `SimState.enemy_growth_override` (`SimState.gd:542-575`). Live: `EnemyAI.gd:287` → `grow_resources(enemy_ai) -> bool`. 24 files override `setup_resource_growth`: **17 enemy profiles**, `ScoredCombatProfile`, **6 player profiles** (sim-only by nature). `grow_resources` is overridden only by `MatriarchProfile:40`. 16 of 17 enemy curves are pure functions of `(max, turn)`; **VoidWarband** (`:176-206`) reads hand + opponent board. Latent bug: enemy `scored*` profiles inherit `ScoredCombatProfile.setup_resource_growth`, which writes `player_growth_override`. | **High** — 17 encounters have different curves in sim vs live. D1 |
| B3 | Trap routing | Live: 9 routes (`CombatScene.gd:4917-4926`), absolute trigger match, consume-before-resolve, friendly-death route only during enemy turn (`:4957-4960`). Sim: 4 routes (`SimTriggerSetup.gd:22-29`) + `CombatState._check_and_fire_traps` (`:947`) with `mirror_trigger`, consume-after-resolve. | **None today** — only 4 non-rune traps exist (hidden_ambush, smoke_veil, silence_trap, death_trap) and sim routes all 4; no enemy deck holds a non-rune trap. Latent: new trap triggers would silently not fire in sim; mirroring would fire an enemy ON_PLAYER_* trap on the enemy's own action |
| B4 | Void-bolt passive only called live | `_handlers._apply_void_bolt_passives()` only at `CombatScene.gd:3259`. | **None** — no card sets `on_void_bolt_passive_effect_id`. **Delete the path** (Phase 1.4), do not port |
| B5 | Guard enforcement | Live `EnemyAI.do_attack_minion` (`:493-501`) redirects to a **random** Guard (extra `randi()`), `do_attack_hero` (`:518-520`) refuses with a Guard up. Sim agents (`SimEnemyAgent:189,204`, `SimPlayerAgent:159`) enforce neither; `CombatManager.resolve_minion_attack` doesn't check. | Narrow: most profiles pick Guards themselves; `CorruptedHandlerProfile` pass 1 (`:72-84`) and sim player profiles (e.g. RuneTempo `:313-323`) ignore Guard |
| B6 | `ON_ENEMY_TRAP_PLACED` fired only in sim | `SimEnemyAgent.gd:162-166`. | **None** — no listener (`Enums.gd:89` calls it a stub) |
| B14 | Turn-start ordering, player | Live: refill → draw → unexhaust → `turn_started` → `ON_PLAYER_TURN_START` (`TurnManager.gd:92-101` → `CombatScene.gd:983`). Sim fires the event **first** (`SimState.gd:562-565`). | Medium — any turn-start handler that reads hand/exhaust state. D2 |
| B15 | Turn-start ordering, enemy | Live: unexhaust (`TurnManager:108-110`) → `ON_ENEMY_TURN_START` (`CombatScene:988`) → 0.4 s → growth, refill, Void Rift Lord drain, draw (`EnemyAI.run_turn:236-248`). Sim: growth/refill/drain **before** the event (`SimState:574-585`), then draw, unexhaust. | Medium. D9 |
| B16 | Player growth timing | Live grows at the end-turn click (`CombatScene:1073-1078`); sim at next `begin_player_turn` (`SimState:547-550`). | Low; shifts F15 `abyssal_mandate` reads. D10 |
| B17 | Spell-cast event ordering, player | Live fires `ON_PLAYER_SPELL_CAST` **after** resolution (`CombatScene:1186-1189`, `:3377-3380`, `CombatInputHandler:481-485`); sim **before** (`SimPlayerAgent:104-109`). Enemy side fires before in both. | Medium — silence_trap / spell-count passives. D8 |

### 0.3 Structural causes

| # | Cause | Evidence |
|---|---|---|
| S1 | 46 of 151 CombatState fields are not forwarded on CombatScene | 105 `get: return state.X` forwarders — 100 in `CombatScene.gd:19-636` **interleaved** with Node refs, signals and gate flags, 5 elsewhere (`:1688, 1702, 2999, 4374`, …). Handlers use `_scene.` 387× (78 distinct direct names + 58 via `.get/.set/has_method`) |
| S2 | ~330 lines of duplicated executor logic | `EnemyAI.commit_*`/`do_attack_*` ↔ `SimEnemyAgent.*`; `SimPlayerAgent.*` ↔ `CombatScene._try_play_*`; `SimState.begin_*_turn` ↔ `TurnManager` + `CombatScene._on_turn_started` |
| S3 | Gameplay mutation deferred into VFX / awaited behind VFX | `_request_buff_apply/_flush_buff_requests` (`CombatScene:1876-1946`), `BuffApplyVFX._apply_intents` (`:137`), `CombatVFXBridge._apply_ritual_damage` (`:741`), trigger fires inside the bridge (`:804`, `:1439`), `_pending_on_death_vfx`, rules-code `await`s (full list in 3.0) |
| S4 | Duck typing | `has_method`: CombatHandlers 24, HardcodedEffects 9, EffectResolver 8, RelicEffects 4, CombatManager 3; `.get("…")`: CombatHandlers 60, CombatManager 20, EffectResolver 14 |
| S5 | Zero live-shell tests | `TestHarness.build_state` returns SimState (`:61`); nothing in `debug/tests/` instantiates CombatScene |
| S6 | Global RNG | 43 gameplay call sites use `randi()/shuffle()/pick_random()`; seeded only by `seed(base_seed + _i)` at `CombatSim.gd:406` |
| S7 | Profiles act on the shell, not through the agent | 110 `agent.essence/mana -=` cost deductions in 26 profile files (e.g. `CombatProfile:547, 599-600`); 111 `agent.scene` refs; `SerisPlayerProfile:108,129` / `FleshcraftPlayerProfile:89,190` call hero skills on `agent.sim` directly; `agent.scene.set(...)` writes (`SpellBurnPlayerProfile:391-427`, `VoidWarbandProfile:493-496`) |

## 1. Target architecture

```
                 ┌────────────────────────────────────────────┐
  input          │  CombatState  (RefCounted, no await)         │
  (human /       │  ─ all data, both sides                      │
   AI agent)     │  ─ commands: play_minion / play_spell /      │
   ──────────▶   │       play_trap / play_environment / attack /│
   state.cmd()   │       end_turn / activate_relic / hero_skill │
                 │  ─ turn engine, trap routing, cost payment   │
                 │  ─ TriggerManager + CombatHandlers (typed)   │
                 │  ─ rng: RandomNumberGenerator (seeded)       │
                 │  ─ journal: Array[CombatEvent]   (Phase 3)   │
                 │  ─ command_log: Array[Dictionary] (replay)   │
                 └───────────────┬────────────────────────────┘
                                 │ events (append-only)
             ┌───────────────────┴──────────────────┐
             ▼                                      ▼
   CombatPresenter (live, Node, Phase 3)     (sim: nothing)
   ─ drains journal one event at a time      CombatSim just loops
   ─ plays the animation for each event       agents over commands
   ─ updates ViewState (lagging copy)
   ─ `idle` signal when queue empty
```

Rules that make it hold (fully true only after Phase 4; the committed phases make 1, 5, 6 true and 2 true for sim):

1. **One rules engine.** `CombatState` is the only place gameplay data mutates.
2. **Commands are the only way in.** Human input, live enemy agent and sim agents call the same `state.cmd_*`. (Planned: the only live/sim difference is a `Pacer` the agent awaits between commands. Since Phase 5 no agent waits — the presenter paces the live enemy's journaled commands.)
3. **Choices are inputs.** Anything a player decides is resolved before the command is issued and passed in `extra` (the `extra_cast_data` pattern from rally_the_ranks). Verified: the only mid-play choice today is Rally's `ChoiceModal` (`CombatScene:3408-3432`); nothing awaits a choice inside EffectResolver / CombatHandlers / HardcodedEffects.
4. **Presentation consumes events and never mutates** (Phase 3).
5. **Engine-owned RNG.** Every gameplay random goes through `state.rng`.
6. **Tripwires in the suite.** Lint from Phase 0; live smoke from Phase 0; parity test in Phase 5.

**Board slots.** `BoardSlot extends Panel` and currently holds gameplay occupancy. Until D11 is decided, the engine is allowed to hold `Array[BoardSlot]` and call only their data methods (`is_empty`, `place_minion`, `remove_minion`, `minion`); lint L6 forbids `await`/`get_tree`/`create_timer` in CombatState but **not** `BoardSlot` typed vars.

## 2. Phase evaluation

| Phase | Value | Risk | Size (est.) | Depends on | Status |
|---|---|---|---|---|---|
| 0 Foundations + hotfixes | **Highest**: fixes B1, B8–B11 (and B7 per D7); lint + live smoke catch the whole bug class going forward; determinism | Low | ~700 lines, 1 session | — | **Committed — do now** |
| 1 State ownership | High: removes the root cause of B1-class bugs (rules code addressing the scene); kills most of S1/S4 | Medium: wide mechanical rename | ~1,500 lines, 2 sessions | 0 | **Committed** |
| 2A Engine commands for sim + shared turn engine + trap routing | High: fixes B2, B3, B5, B6, B14–B17; balance sim becomes trustworthy; deletes the sim agents | Medium: behaviour decisions D1, D2, D7–D10 move balance numbers | ~2,000 lines, 2 sessions | 1 | **Committed** |
| — Checkpoint | Re-run the balance matrix, retune if needed, decide whether/when to continue | — | — | 2A | **Stop here** |
| 3 De-async rules + journal + presenter + live switch | High for correctness (S3, B12, B13), but invisible to players; the only phase with visual risk | High: presentation rewrite, owner visual QA | ~3,000 lines, 4 sessions | 2A | Deferred |
| 4 Collapse | Medium: deletions + docs | Low once 3 lands | ~-3,000 lines net, 1–2 sessions | 3 | Deferred |
| 5 Parity tripwires | High long-term | Low | ~800 lines, 1 session | 3, 4 | Deferred (lint and smoke parts already live from Phase 0) |

**Why the original Phase 2 was split.** The original plan made every `cmd_*` synchronous in Phase 2 and removed the rules-code `await`s / VFX-deferred mutations only in Phase 3. Today live mutation is asynchronous in many places (list in 3.0): battlecries resolve at card-flight landing, spells inside the cast-anim tween callback (~1.07 s after click), traps in a card-anim callback, several HardcodedEffects/CombatHandlers bodies after awaited VFX. Routing live input through synchronous commands before those are removed would (a) make `CommandResult`, `command_log` replays and digests wrong in live, and (b) show results ~1 s before their animations for ~3 sessions. So: **2A** moves sim and tests onto commands and shares only the parts of the turn/trap engine that are not animation-bound; **the live switch** (old 2.4-live / 2.5) moves into Phase 3, after the de-async step.

**When to resume Phase 3.** When async-timing bugs (B12-class) start costing real time, or before combat-feel polish, whichever comes first.

## 3. Ground rules for the executing agent

### 3.1 Cadence
- Run `tools/run_checks.sh` (from 0.2 on; before that `godot --headless --path . --import && godot --headless --path . res://debug/tests/RunAllTests.tscn`) before the first edit of a phase (record the count — **784** at `1c9aa30`) and after every numbered step. A step is not done while the suite is red.
- One commit per numbered step where the step leaves the tree green; message `Version 0.6NN: <phase>.<step> — <what shipped>`. Do not batch a whole phase into one commit.
- Open each phase as its own task (`/task-start Live/sim unification — Phase N | combat`), log deviations and every moved test in its work log, close with `/task-done`.

### 3.2 Coding rules
- `var x: Type = untyped[i]`, never `:=` from an untyped Array/Dictionary (CLAUDE.md).
- New engine code has **no** `await`, no `get_tree()`, no `create_timer`. Grep-checked by lint L6.
- When live and sim disagree, **live is the spec** unless a decision below says otherwise — **except** where live behaviour is a bug listed in 0.1 (then the fixed behaviour is the spec). Record every behaviour change in the task log with the test that moved.
- Do not restyle VFX or UI while migrating.
- Keep `design/master_doc/ARCHITECTURE.md` in sync at the end of each phase.

### 3.3 Decisions the owner must make before the step that needs them

| ID | Needed by | Question | Recommendation |
|---|---|---|---|
| D7 | **Phase 0.2** | Turn-end events (B7): fire `ON_PLAYER_TURN_END` / `ON_ENEMY_TURN_END` in live (enables ~10 dead passives — forge auras, void_unraveling, captain_orders, abyssal_mandate, hollow_sentinel, champion_vs/vch, minion turn-end steps) or delete the handlers? | **Fire them.** They were designed and tested in sim; live is the bug. Run `BalanceSimBatch` before/after (sim already fires the enemy side, so the delta is mostly the player side). Play-test F15 and one Seris fight. |
| D1 | Phase 2A.4 | Enemy resource growth: port the 17 sim enemy curves to the shared hook (changes difficulty of 17 encounters in live), or delete them and keep live's default? | **Port them.** They were tuned per encounter; live never ran them by accident. VoidWarband's curve needs `(state, side, turn)` with read access to hand/board — allowed. Attach the before/after balance batch to the task. |
| D2 | Phase 2A.3 | Player turn start ordering (B14). | Live order: refill → draw → unexhaust → `ON_PLAYER_TURN_START`. |
| D9 | Phase 2A.3 | Enemy turn start ordering (B15). | Mirror the player: growth → refill → drain → draw → unexhaust → `ON_ENEMY_TURN_START`. This changes live slightly (event currently fires before draw) — a symmetric order is easier to reason about. Alternative: live order as-is. |
| D10 | Phase 2A.3 | Player resource growth timing (B16): at end-turn click (live) or at next turn start (sim)? | Engine stores the choice at `cmd_end_turn` and **applies it at `begin_turn("player")`** (sim behaviour). The UI still asks at end-turn. Only observable difference: enemy-turn effects reading `player_*_max` see the pre-growth value. |
| D8 | Phase 2A.1 | Player spell-cast event ordering (B17): `ON_PLAYER_SPELL_CAST` before or after resolution? | **Before**, matching the enemy side and sim (a silence/counter trap must see the cast before it resolves). Live changes. |
| D5 | Phase 2A.3 | Delete `TurnManager` or keep as façade? | **Façade in 2A** (UI signals re-emitted from state), delete in Phase 4. |
| D11 | Phase 3.1 | Engine owns plain slot data (`SlotState`) with `BoardSlot` as a view, or engine keeps `BoardSlot` references? | **Decided 2026-09-24: `SlotState`.** Engine owns `Array[SlotState]` (RefCounted: `side`, `index`, `minion`); `BoardSlot` is a view the presenter refreshes. See "Checkpoint decisions". |
| D3 | Phase 3.0 | On-death effects: live defers until after the death animation; sim resolves inline. | **Decided 2026-09-24: inline.** The presenter plays the death animation (and on-death icon) before the events that follow `MINION_DIED`. |
| D4 | Phase 3.2 | ViewState scope: full per-slot view model or hybrid? | **Decided 2026-09-24: hybrid.** ViewState holds hero/resource/hand/trap/env scalars; slots render the `MinionInstance` at playback with stat labels driven by event `before`/`after`. |
| D6 | Phase 4.5 | Split `CombatState.gd` into `combat/engine/{CombatState,CombatEngine}.gd`? | Yes, pure move, only after the parity test exists. |

---

## 4. Phases

Conventions: `[C]` create, `[M]` modify, `[D]` delete, `[T]` test. "Gate" = a command whose expected output is stated; the step is done only when the gate holds.

### Phase 0 — Foundations and hotfixes (committed)

**Goal.** Stop the live-only crashes and dead talents, make combat deterministic, add the first live-shell test and the first lint. No architectural change.

**Prerequisite.** Task 009's uncommitted `shop/ShopScene.gd` korrath wiring must be committed (or folded into 0.7) — 0.7 depends on it.

#### 0.1 Hotfix the unforwarded handler accesses (B1, B8, B9, B10, B11)
- [M] `combat/events/CombatHandlers.gd`:
  - `:1844-1845`, `:1969-1970` — `_scene._champion_vrp_spells_cast` / `_scene._champion_as_cards_played` → `_scene.state.<same>`. `SimState.state` returns `self` (`SimState.gd:24-25`), `CombatScene.state` is the CombatState (created at field init, `CombatScene.gd:19`), so the expression is valid in both shells.
  - `:1526-1527` — `_hollow_sentinel_buffs`: same rewrite, drop the `.get() != null` guard.
  - `:1842`, `:1967`, `:2410-2420` — every `_scene.get/set("_champion_*_summoned")` → `_scene.state._champion_*_summoned` (all seven, for uniformity; five are forwarded today, two are not).
  - `:1184-1194` — `_imp_caller_fired` → `_scene.state._imp_caller_fired`.
  - `:279`, `:331` — `_scene._korrath_place_random_rune()` / `_scene._korrath_absorbed_aura_count()` → `_scene.state.…`.
  - `:2380-2420` (`_summon_enemy_champion`) — set the `_summoned` flag **before** the `await death_anims_done`, not after (B11). The flag write moves above the await; the rest of the body is unchanged.
- [M] `combat/events/CombatSetup.gd:623`, `:635` — `scene.set(stat, v)` → `scene.state.set(stat, v)` (both `_apply` and `apply_passive`). Add an `assert(stat in scene.state, …)` so a typo fails loudly.
- [M] `combat/effects/EffectResolver.gd:347` — `ctx.scene.set("_enemy_void_mana_drain_pending", …)` → `ctx.scene.state._enemy_void_mana_drain_pending = …`.
- [T] `TriggerHandlerTests`: a probe per fixed handler that asserts the state field changed (VRP counter, AS counter, VRP summons exactly once across 8 spells, Imp Caller fires once per turn, Path of Corruption flag set after `CombatSetup.setup`).
- Gate: `grep -nE '_scene\.(_champion_|_hollow_sentinel|_imp_caller|_korrath_)|_scene\.(get|set)\("_champion_' combat/events/CombatHandlers.gd` → 0 lines; `grep -n 'scene.set(stat' combat/events/CombatSetup.gd` → 0 lines.

#### 0.2 Turn-end events (B7, requires D7)
- If D7 = fire:
  - [M] `combat/board/CombatScene.gd:_on_turn_ended` (`:~1000-1021`): fire `ON_PLAYER_TURN_END` / `ON_ENEMY_TURN_END` (`EventContext.make(event, side)`) **before** the existing cleanup (spell-tax reset, traps-blocked reset, `_temp_imps` kill), matching `SimState.end_enemy_turn`.
  - [M] `sim/SimState.gd`: add the missing `end_player_turn` fire of `ON_PLAYER_TURN_END` at the equivalent point.
  - [T] `TriggerHandlerTests`: one probe that `on_minion_turn_end_passives` runs on player turn end.
  - Run `BalanceSimBatch --act 1` and `--act 2` before/after; attach both to the task.
- If D7 = delete: remove the ~10 handler registrations listed in B7 and their handler bodies; log them in the task.
- Gate (fire): `grep -rnE 'make\(Enums\.TriggerEvent\.ON_(PLAYER|ENEMY)_TURN_END' --include='*.gd' combat/board sim | wc -l` → ≥ 3 (both events in CombatScene, player event added in SimState). Gate (delete): `grep -rn 'TURN_END' combat/events/CombatSetup.gd` → 0.

#### 0.3 Lint script v1
- [C] `tools/lint/lint_engine.py` (Python 3, stdlib only).
  - Declared names: parse `^var (\w+)`, `^func (\w+)`, `^signal (\w+)` from `combat/board/CombatScene.gd`, `combat/board/CombatState.gd`, and `sim/SimState.gd`.
  - Scanned references: every `_scene\.(\w+)` and `_scene\.(get|set|has_method)\("(\w+)"` in `combat/events/CombatHandlers.gd`, `combat/effects/HardcodedEffects.gd`, `relics/RelicEffects.gd`; every `scene\.` / `ctx\.scene\.` form in `combat/effects/EffectResolver.gd`, `ConditionResolver.gd`, `TargetResolver.gd`, `combat/board/CombatManager.gd`, `combat/board/MinionInstance.gd`; every `"stats"` key in `CombatSetup._REGISTRY`.
  - **L1**: a name declared on CombatState or SimState but **not** on CombatScene is an error (the B1 class). A name declared nowhere is an error. Sim-only fallback branches that intentionally read SimState-only names (`enemy_essence_max` / `enemy_mana_max` at `CombatHandlers.gd:1923-1926`, `EffectResolver.gd:162-164`) go in `tools/lint/l1_allow.txt` with a comment; that file must shrink to empty by the end of Phase 1.
  - Registry stat keys must exist on CombatState.
  - Output `L1 file:line: name`; exit code = error count.
- [C] `tools/run_checks.sh`: `godot --headless --path . --import` (the class cache goes stale — at `1c9aa30` CombatScene fails to parse with `Identifier "ChoiceModal" not declared` without it), then the lint, then `RunAllTests`, then `LiveSmoke` (0.6); captures Godot stderr and fails on any `SCRIPT ERROR`; exits non-zero on any failure. This is what "the suite" means from here on.
- Gate: record the lint count **before** 0.1 in the task log (expected ≈ 25). After 0.1: `python3 tools/lint/lint_engine.py` → `0 errors`.

#### 0.4 Engine-owned RNG
- [M] `combat/board/CombatState.gd`: add
  ```gdscript
  var rng: RandomNumberGenerator = RandomNumberGenerator.new()
  var rng_seed: int = 0
  func seed_rng(seed_value: int) -> void: rng_seed = seed_value; rng.seed = seed_value
  func rng_pick(arr: Array) -> Variant: return arr[rng.randi() % arr.size()]   # caller guarantees non-empty
  func rng_shuffle(arr: Array) -> void: # Fisher–Yates using rng
  func rng_range(lo: int, hi: int) -> int: return rng.randi_range(lo, hi)
  ```
- [M] Replace the 43 gameplay call sites with `state.rng_*`. The list (verified complete; VFX files are **excluded** on purpose — cosmetic randomness stays global):
  - `combat/board/CombatState.gd:234, 644, 1508, 1511, 1532`
  - `combat/board/CombatManager.gd:432` (via `scene.state`)
  - `combat/board/TurnManager.gd:77` (`player_deck.shuffle()` → `scene.state.rng_shuffle`; add `var state: CombatState` set in `CombatScene._connect_turn_manager`)
  - `combat/board/EnemyAI.gd:214, 314, 355, 356, 501` (via `scene.state`)
  - `combat/board/CombatScene.gd:2211, 2221, 2236`
  - `combat/effects/TargetResolver.gd:131, 143` (via `ctx.scene.state`)
  - `combat/effects/HardcodedEffects.gd:286`
  - `combat/events/CombatHandlers.gd:299, 321, 360-363, 374, 395, 936, 1202, 1216, 1300, 1421, 1774, 1938, 2099`
  - `enemies/ai/CombatProfile.gd:950, 954` (via `agent.scene.state`)
  - `relics/RelicEffects.gd:112, 133, 166`
  - `sim/SimState.gd:150, 156, 520, 534`
  - Leave alone (meta-game): `RelicDatabase.gd:26`, `RelicRewardScene.gd:99`, `GameManager.gd:192`, `EncounterDecks.gd:134,142`, `RewardScene.gd:46`, `ShopScene.gd:164,252,342,361`. Cosmetic: `EnemyHeroPanel.gd:723`, `ScreenShakeEffect.gd:39`, VFX files.
- [M] **Seed ordering matters** — both shells shuffle decks during setup.
  - Sim: `CombatSim.run()` gains a trailing `rng_seed: int = -1` parameter (don't name it `seed`, it shadows the global). `seed_rng` is called **before** `state.setup(...)` (`CombatSim.gd:141`; `SimState.setup` shuffles at `:150,156`). When `rng_seed < 0`, derive `var s: int = randi()` once, seed with it. Result dict gains `"seed"` and `"digest"` (computed **before** `state.teardown()` at `:275`). `run_many` (`:405-406`) replaces the global `seed(base_seed + _i)` with passing `base_seed + _i` into `run()`.
  - Live: `CombatScene._ready` calls `state.seed_rng(GameManager.combat_seed)` right after `state._scene_facade = self` (`:652`) — before `_setup_enemy_ai()` (`:728`, which shuffles via `EnemyAI.gd:214`) and `turn_manager.start_combat` (`:754`). `GameManager.combat_seed` is a new `int` set to `randi()` when entering combat and printed as the first combat-log line (`Seed: N`). Do **not** persist it in `UserProfile` — resume never re-enters mid-combat, so it would be dead data.
- Gate: `grep -rnE '\b(randi|randf|randi_range|randf_range|shuffle|pick_random)\(' --include='*.gd' combat/board combat/events combat/effects/EffectResolver.gd combat/effects/TargetResolver.gd combat/effects/HardcodedEffects.gd sim enemies/ai relics/RelicEffects.gd | grep -v 'rng'` → 0 lines. Lint rule **L2** encodes this.

#### 0.5 State digest + determinism probes
- [M] `CombatState.gd`: `func digest_text() -> String` (canonical, newline-separated, stable order: turn number, winner, both HP/max, both resources, void marks, flesh/forge/armour, per-slot `idx:card_id:atk:hp:shield:state:sorted buff tags` both sides, hand card ids in order both sides, deck sizes, graveyard sizes, trap ids in order both sides, environment ids, relic charges/cooldowns if present) and `func digest() -> int: return digest_text().hash()`. Read resources via the shell-agnostic path that exists at this point (SimState fields in sim) — Phase 1.3 moves them onto CombatState.
- [T] `debug/tests/ScenarioTests.gd`: `_determinism_same_seed_same_digest()` — `CombatSim.run(...)` twice with `rng_seed = 12345` on the `_baseline_swarm_vs_feral_pack` config (`:74`; `run()` has 14 positional params — pass them all); assert equal `winner`, `turns`, `digest`. `_determinism_seed_recorded()` — run with `-1`, assert `result.seed >= 0`, rerun with it, assert equal digest.
- Gate: both probes pass 3 runs in a row (`--filter determinism`).

#### 0.6 Live smoke test (headless CombatScene)
Feasibility verified: a headless CombatScene added as a child reaches `hand = 4`, `is_player_turn`, and turn 2 after `_do_end_turn("essence")` in ~4 s with no script errors.
- [C] `debug/tests/LiveSmokeTests.gd` + `debug/tests/LiveSmoke.tscn` (own scene; `RunAllTests` ends with `get_tree().quit(fail_count)` at `RunAllTests.gd:25-31`, so the smoke runs as a separate process from `run_checks.sh`):
  - Setup: `GameManager.start_new_run()` (sets `current_enemy`), **set `GameManager.player_deck`** to a fixed starter list (`start_new_run` leaves it empty → 0-card hand), set a flag that makes `GameManager.go_to_scene` / `UserProfile.save` a no-op for the test (victory/defeat would otherwise overwrite the developer's `user://profile.json`), `BaseVfx.time_scale = 0.05`. **Not 0**: at 0 `VfxSequence.run` completes synchronously and drops mid-phase beats (`VfxSequence.gd:156`), which skips `BuffApplyVFX`'s state mutation and `impact_hit` beats.
  - `var scene: CombatScene = load("res://combat/board/CombatScene.tscn").instantiate()`; `add_child(scene)`; await 5 frames.
  - Assert `scene.state.player_hp > 0`, hand has 4 cards, `scene.turn_manager.is_player_turn`.
  - `scene._do_end_turn("essence")`; await until `scene.turn_manager.is_player_turn` again or 20 s timeout; assert `turn_number == 2`; print `LiveSmoke: enemy turn completed`.
  - Second scenario: F13 (Void Ritualist Prime) — play 6 spells via cheat/direct state setup across turns and assert no `SCRIPT ERROR` (this is the B1 repro).
- Gate: `tools/run_checks.sh` passes, its log contains `LiveSmoke: enemy turn completed`, and stderr has zero `SCRIPT ERROR` lines.

#### 0.7 Korrath unlock hotfix
- [M] `shared/scripts/GameManager.gd:159-181` and `shared/scripts/UserProfile.gd:119-127` (`_ensure_default_unlocks`): add the `korrath_*` pools using the ids RewardScene (`:109-113`) and ShopScene (`:459-465`, uncommitted from task 009) use. The shop filters by `permanent_unlocks`, so task 009 has no effect without this.
- Consolidating the five copies of the talent→pool mapping is a separate task (section 6).

#### 0.8 Phase gates
```
tools/run_checks.sh     → exit 0; lint 0 errors (L1, L2); "784+N passed, 0 failed"; LiveSmoke line present; 0 SCRIPT ERROR
godot --headless --path . res://debug/BalanceSimBatch.tscn -- --act 1 --runs 50 --seed 7   → identical output on two consecutive runs
```
Rollback: every step is additive except 0.4's call-site rewrite and 0.2; revert per commit.

---

### Phase 1 — Rules code addresses `state`; enemy-side state and relics move onto CombatState (committed)

**Goal.** `CombatHandlers`, `EffectResolver`, `ConditionResolver`, `TargetResolver`, `HardcodedEffects`, `RelicEffects`, `CombatManager` read and write gameplay data through a typed `CombatState` and call presentation only through a nullable `presenter`. Enemy hand/deck/graveyard/resources/cost modifiers and `RelicRuntime` live on `CombatState`. `SimEnemyAgent` loses its duck-type block.

**Order inside the phase:** 1.1 → 1.3 → 1.4 → 1.2 → 1.5. The handler rewrite (1.2) can only reach a zero-error gate once the names it rewrites to exist on state (1.3, 1.4); doing 1.2 first leaves ~20 sites (`enemy_ai`, `_check_champion_triggers`, `_resolve_on_death_effect`, `_summon_void_spark`, `_resolve_void_devourer_sacrifice`, …) with nothing to point at.

**Done when.** Lint L1–L5 hold, suite green, live smoke green.

#### 1.1 Presenter seam + classification
- [M] `CombatState.gd:105-109`: rename `_scene_facade` → `presenter: Object`. Keep `_get_scene_facade()` as an alias **with its current fallback to `self`** in sim (it does not return null today; handlers rely on that) until Phase 4. New code tests `presenter != null`.
- [C] `tools/lint/presentation_allowlist.txt`: names rules code may call on `presenter` during Phases 1–2A. Build by classifying every `_scene.` name (78 direct + 58 via `.get/.set/has_method`). Starting classification (verified):
  - **Presentation (allowlist):** `_refresh_slot_for`, `_find_slot_for`, `_play_void_netter_on_play_vfx`, `_spawn_presence_aura_buff_vfx`, `_spawn_pack_chain_vfx_for_new_imp`, `_spawn_pack_instinct_buff_vfx`, `_play_feral_reinforcement_vfx`, `_play_corruption_detonations`, `_play_ritual_sacrifice_sequence`, `_play_champion_acp_aura_pulse`, `_play_corruption_apply_visual`, `_play_brood_call_vfx`, `_play_grafted_butcher_vfx`, `_play_pack_frenzy_vfx`, `_play_frenzied_imp_vfx`, `_spawn_atk_chevron`, `_spawn_void_imp_claw_vfx_at`, `_pulse_lifedrain_icon`, `_update_champion_progress`, `_on_champion_killed`, `_flash_trap_slot_for`, `_update_counter_warning`, `_update_enemy_trap_display`, `_refresh_hand_spell_costs`, `_on_minion_siphon_healed`, `hand_display`, `trap_slot_panels`, `enemy_trap_slot_panels`, `vfx_controller`, `is_inside_tree`, `death_anims_done`, `_active_death_anims`, `_pending_on_death_vfx`, `_request_buff_apply`, `_silent_buff_apply`.
  - **Gameplay (must resolve to `state`):** `_spell_dmg` (`CombatScene.gd:4710` just forwards to `state._spell_dmg` — wrapping it in a presenter-null check would zero damage in sim), `_log` (CombatState has its own; SimState overrides it), everything else not listed above.
  - Direct label writes at `CombatHandlers.gd:1176-1178` → move into a presenter method (`_update_<x>_label`) and allowlist that.
- [M] Lint **L3**: in the rules files, `_scene.` / `scene.` / `ctx.scene.` may only be followed by `state` or an allowlisted name. **L4**: `has_method(` and `.get("` are errors in the rules files. The lint output is the work list for 1.3/1.4/1.2.

#### 1.3 Enemy-side state onto CombatState
The "Resources" and "Decks / hands / graveyards" batches of `COMBAT_STATE_MANIFEST.md` that never landed.
- [M] `CombatState.gd`: hoist from `SimState.gd:35-73`: `player_essence`, `_player_essence_max` **and its property setter that writes `last_player_growth`** (keep that side effect), `player_mana`, `_player_mana_max`, `enemy_essence/_max`, `enemy_mana/_max`, `player_deck/hand/graveyard`, `enemy_deck/hand/graveyard`, `enemy_limited_cards`, `turn_number`. None are on CombatState today. Already on CombatState (keep; currently **shadowed** live by EnemyAI's own vars): `enemy_active_traps`, `enemy_active_environment`, `enemy_spell_cost_penalty/aura/discounts`, `enemy_essence_cost_discounts`, `enemy_minion_essence_cost_aura`.
- Add side-agnostic accessors: `hand_of(side)`, `deck_of(side)`, `graveyard_of(side)`, `essence_of(side)`, `mana_of(side)`, `set_essence(side, v)`, `set_mana(side, v)`, `send_to_graveyard(side, inst)` (stamps `resolved_on_turn` from `turn_number`), `add_to_hand(side, card_or_inst)` (hand cap 10 both sides), `draw_cards(side, count)` (player: finite deck, burn on full hand, emits `card_drawn(side, inst)`, fires `ON_PLAYER_CARD_DRAWN`; enemy: infinite-deck replacement + `enemy_limited_cards`, exactly `SimState._draw_enemy` / `EnemyAI._draw_cards`), `setup_deck(side, ids)`.
- [M] `combat/board/TurnManager.gd`: delete its `essence/essence_max/mana/mana_max/player_deck/player_hand/player_board/enemy_board/player_graveyard` vars; every method calls into `state` and re-emits its UI signals (`resources_changed`, `card_drawn`, `card_generated`) from state signals.
- [M] `combat/board/EnemyAI.gd:91-179`: delete the vars; `essence`, `mana`, `hand`, `deck`, `graveyard`, `active_environment`, `spell_cost_*`, `essence_cost_discounts`, `minion_essence_cost_aura` become getters/setters onto `scene.state` (pattern at `:139-150`). `setup_deck`, `_draw_cards`, `add_to_hand`, `_send_to_graveyard` delegate. `attack_cancelled` moves to `state.attack_cancelled` (Smoke Veil writes it via `_scene.get("enemy_ai")` today — `HardcodedEffects.gd:208-214`).
- [M] `combat/ui/EnemyHeroPanel.gd:421`: `update(hp, hp_max, enemy_ai, marks)` → `update(hp, hp_max, state, marks)`. **14 call sites**, not 4 — find them with `grep -rn '_enemy_hero_panel.update\|enemy_hero_panel.update'`.
- [M] `sim/SimState.gd`: delete the hoisted vars, `_draw_player`, `_draw_enemy`, `setup_enemy_deck`, `_friendly_hand/_friendly_deck/_add_to_owner_hand/_friendly_graveyard` (now inherited).
- [M] `sim/SimEnemyAgent.gd:38-77`: delete the duck-type property block (read/write state directly). `sim/SimTurnManager.gd`: reduce to a façade over state.
- [M] `combat/effects/EffectResolver.gd`: every `ctx.scene.enemy_ai.<x>` / `ctx.scene.turn_manager.<x>` → side-agnostic state accessors. **Includes local aliases** (`var ai = ctx.scene.enemy_ai` at `:154`, `var tm = ctx.scene.turn_manager` at `:359`) that the gate grep won't see by pattern.
- [M] `combat/events/CombatSetup.gd:601-604` (`corrupted_death` discount via `scene.get("enemy_ai")`) → `state.enemy_essence_cost_discounts["void_touched_imp"] = 1`.
- Gate: `grep -rnE 'enemy_ai|turn_manager' combat/effects/EffectResolver.gd combat/effects/HardcodedEffects.gd combat/events/CombatHandlers.gd combat/events/CombatSetup.gd` → 0. Suite green. Live smoke green (it exercises EnemyAI draw/play).

#### 1.4 Gameplay-only scene methods move to CombatState
`CombatScene ∩ SimState` is exactly 24 functions (21 not on CombatState); `CombatScene ∩ CombatState` is 50; SimState overrides 3 CombatState funcs (`_fire_ritual`, `_log`, `_soul_forge_activate`). For each pair below produce **one** CombatState implementation with presenter hooks; delete the SimState copy; leave a one-line delegate on CombatScene only where signal wiring needs it (deleted in Phase 4).
- `_on_minion_vanished` (`CombatScene.gd:3112` / `SimState.gd:208`): state removes from board+slot, emits `minion_died`, fires `ON_CORRUPTION_REMOVED` then death trigger. Presenter hook `presenter._on_minion_vanished_visual(minion, slot_idx, was_frozen)` handles the death anim. The `_pending_on_death_vfx` deferral stays live-only until D3 (Phase 3) — implement as `if presenter != null and presenter.wants_deferred_on_death(minion)`, allowlisted.
- `_on_hero_damaged` (`:3218` / `:244`): one body; presenter hooks `flash_hero`, popup capture. **Delete** the `_handlers._apply_void_bolt_passives()` call (`:3259`) and `CombatHandlers._apply_void_bolt_passives` (`:126`), `MinionCardData.on_void_bolt_passive_effect_id` (`:110`) and its `BoardEvaluator.gd:294` read — no card uses it (B4).
- `_on_hero_healed` (`:3279` / `:282`): one body with the max-HP clamp on both sides.
- `_consume_fiendish_pact_discount`, `_register_env_rituals`, `_unregister_env_aura`, `_resolve_void_devourer_sacrifice` (`:2243`; SimState `:439` is `pass` — the live body becomes the spec), `_summon_void_imp`, `_summon_void_spark`, `_check_champion_triggers/_check_champion_condition/_summon_champion_card` (`:2681-2733`; presenter hook for `champion_summon_sequence`), `_resolve_on_death_effect`, `_count_type_on_board`, `_find_random_minion` (already on state; delete scene copies), `_rune_aura_multiplier`, `_summon_token`, `_summon_token_at_slot` (keep `_summon_delegate` until Phase 3).
- `_seris_corrupt_activate`, `_soul_forge_activate`: remove the SimState overrides; one CombatState body.
- Cost payment: `_pay_card_cost` (`:3068`), `_player_pay_sparks` (`:3036`), `_player_available_sparks`, `_player_can_afford_sparks` → `state.can_afford(side, essence, mana, sparks)` / `state.pay(side, essence, mana, sparks)`. (`CombatProfile._pay_sparks` at `:1099` already routes through `agent.consume_minion`; leave it.) Imp Overload `_temp_imps` expiry moves into the turn-end path on state.
- [M] `sim/SimState.gd`: delete every method now inherited.
- Gate: `python3 tools/lint/lint_engine.py --report-pairs` (new flag: lists `func` names defined on both CombatScene and SimState, and SimState overrides of CombatState funcs) → 0 pairs. Lint **L5** encodes this. `wc -l sim/SimState.gd` → **≤ 250** (setup ~58 lines and the turn engine ~80 lines survive until 2A).

#### 1.2 Handlers take `state`
- [M] `combat/events/CombatHandlers.gd:13-21`: `var state: CombatState` + `var presenter: Object` set in `setup(scene_or_state)`: if the argument has a `state` property use it (CombatScene/SimState), else it is the state. `presenter = state.presenter`.
- [M] Mechanical rewrite of the 387 `_scene.` sites (~255 → `state.<x>`, ~90 → `if presenter != null: presenter.<x>(...)`, ~40 other — resolve each against the 1.1 classification). File-section by file-section, `--filter handler` between sections.
- [M] Same for `HardcodedEffects.gd` (61 sites), `RelicEffects.gd`, `CombatManager.gd` (`var scene` → `var state: CombatState`, delete the 20 `scene.get(`), `EffectResolver.gd`/`ConditionResolver.gd`/`TargetResolver.gd` (`ctx.scene` → `ctx.scene.state` for gameplay; `ctx.scene` stays the presenter for allowlisted calls until Phase 4).
- Gate: lint L3+L4 → 0 errors for CombatHandlers, HardcodedEffects, RelicEffects, CombatManager. `tools/lint/l1_allow.txt` empty. (EffectResolver may still carry the `vfx_controller != null` buff branch; that is Phase 3.)

#### 1.5 RelicRuntime onto state
- [M] `CombatState.gd`: `var relic_runtime: RelicRuntime = null`. `CombatScene._setup_relics` (`:2427-2459`) builds it on state; `_relic_bar.setup(state.relic_runtime)`; the turn-start tick (`:979-980`) stays in `_on_turn_started` until 2A.3 moves it.
- [M] `sim/CombatSim.gd:173-179`: use `state.relic_runtime` (delete the local `relic_rt`; `relic_fx.setup(state)`).
- Gate: `grep -rnE '_relic_runtime|relic_rt\b' --include='*.gd' combat sim relics` → only `state.relic_runtime` forms.

#### 1.6 Phase gates
```
tools/run_checks.sh    → green, lint 0 errors with L1–L5 active (record which TriggerHandlerTests moved and why)
wc -l sim/SimState.gd  → ≤ 250
grep -c 'has_method(' combat/events/CombatHandlers.gd combat/effects/HardcodedEffects.gd relics/RelicEffects.gd combat/board/CombatManager.gd → 0 each
```
Rollback: per step. 1.3 and 1.4 are the two large commits; if 1.4 has to be split, split by pair, never by file.

---

### Phase 2A — Engine commands for sim and tests; shared turn engine and trap routing (committed)

**Goal.** Every gameplay action has a synchronous `CombatState` command, used by **sim and tests**. The turn engine and trap routing — which are not animation-bound — are shared by both shells. Resource growth, Guard enforcement, the profile registry and encounter data exist once. `SimPlayerAgent`, `SimEnemyAgent`, `SimTurnManager` are deleted. **Live input and the live enemy turn are not rerouted** (that is Phase 3.4); `EnemyAI`, `EnemyAgent`, `CombatScene._try_play_*` keep working as today.

**Done when.** Gates in 2A.9 hold; D1, D2, D5, D8, D9, D10 applied and logged; before/after balance batches attached.

#### 2A.1 Command surface on CombatState
- [C] `combat/board/CommandResult.gd` (`class_name CommandResult`, RefCounted): `ok: bool`, `reason: String`.
- [M] `CombatState.gd`, new section `# ── Commands ──`. All synchronous, all return `CommandResult`, all append to `command_log`:
  ```gdscript
  func cmd_play_minion(side: String, inst: CardInstance, slot_index: int, target: MinionInstance = null, extra: Dictionary = {}) -> CommandResult
  func cmd_play_spell(side: String, inst: CardInstance, target = null, extra: Dictionary = {}) -> CommandResult   # target: MinionInstance | "enemy_hero" | "player_hero" | TrapCardData | EnvironmentCardData | null
  func cmd_play_trap(side: String, inst: CardInstance) -> CommandResult
  func cmd_play_environment(side: String, inst: CardInstance) -> CommandResult
  func cmd_attack(side: String, attacker: MinionInstance, target: MinionInstance) -> CommandResult
  func cmd_attack_hero(side: String, attacker: MinionInstance) -> CommandResult
  func cmd_consume_minion(side: String, minion: MinionInstance) -> CommandResult
  func cmd_end_turn(side: String, growth: String = "") -> CommandResult
  func cmd_activate_relic(index: int, target = null) -> CommandResult
  func cmd_hero_skill(side: String, skill_id: String, target = null) -> CommandResult   # seris_corrupt, soul_forge
  ```
  Reference bodies: `SimPlayerAgent.commit_*` / `SimEnemyAgent.commit_*` (already synchronous) as the skeleton; fold in the rules they lack:
  - Fiendish Pact discount (`CombatScene.gd:1353-1358`), spark costs (`:1150-1155`), Phase Disruptor counter (`:1167-1172` / `SimPlayerAgent.gd:101-103`), `void_manifestation` on hero attack (`SimPlayerAgent.gd:169-176`).
  - **Guard enforcement for both sides** as validation (B5): `cmd_attack` on a non-Guard target with a Guard up → `ok=false, reason="guard"`; `cmd_attack_hero` with a Guard up → `ok=false`. No random redirect — the caller must pick a legal target; `CorruptedHandlerProfile` pass 1 and sim player profiles must be fixed to filter Guards (their probes will move).
  - `attack_cancelled` (Smoke Veil) is a state field checked by `cmd_attack*`.
  - Imp Barricade `redirect_attack_target` is dead (nothing writes it) — delete `EnemyAI.gd:124, 494-496, 524-531`.
  - Trap-slot cap and duplicate-trap rule (`:1203-1213`), rune aura registration + `ON_RUNE_PLACED`, environment replace teardown (both `on_replace_effect_steps` and `_unregister_env_rituals/_unregister_env_aura` — live and sim do different halves today; do both).
  - `ON_*_TRAP_PLACED` for both sides (B6 — harmless, but symmetric).
  - Gameplay currently living in EnemyAI signal handlers on CombatScene — ON_ENEMY_ATTACK fire (`:4861, 4869`), Null Seal `_spell_cancelled` + Phase Disruptor (`:3589-3626`), `_apply_rune_aura` (`:3644`), `place_minion` + ON_ENEMY_MINION_PLAYED/SUMMONED (`:3538-3574`) — is the spec for the enemy side of the commands.
  - Spell-cast ordering per **D8**.
  - Validation happens **before** any mutation: wrong turn, not affordable, slot occupied, inst not in hand, attacker exhausted, Guard violation → `ok=false` with reason; nothing changes.
  - `cmd_play_minion` event order follows live: place in slot → `ON_*_MINION_PLAYED` (minion not yet in board array) → append to board → `minion_summoned` → `ON_*_MINION_SUMMONED`.
  - Choices: `extra` carries pre-resolved choices (`rally_race`). Cost is paid **inside** the command, so a cancelled choice issues no command.
- [M] `command_log: Array[Dictionary]` on state: `{turn, side, cmd, card_id, inst_id, slot, target: {kind, side, slot} | null, extra}`. Targets are recorded by slot index / hero sentinel so a log replays against a fresh state. **Valid for sim-generated fights only until Phase 3.4.**
- [T] `debug/tests/CommandTests.gd` (new layer in RunAllTests): one probe per command for validation failures (no mutation, `ok=false`) and the happy path; Guard validation both sides; `ON_ENEMY_TRAP_PLACED` fires; **no double payment**: a profile-driven play deducts exactly the card cost once.

#### 2A.2 Trap routing in the engine (both shells)
- [M] `CombatState.gd`: `_fire_traps_for(owner, trigger, triggering_minion)` with live semantics: absolute trigger match; skip if `<owner>_traps_blocked`; consume non-reusable **before** resolving; friendly-death route only during the opponent's turn (`CombatScene.gd:4957-4960`). Resolution: `if presenter != null and presenter.has_trap_reveal(): presenter.play_trap_reveal(owner, trap, slot_idx, resolve_callable)` (live keeps today's card-anim-then-resolve timing until Phase 3.0 makes it inline — B12 stays open until then); else resolve inline. Emits `trap_fired(owner, trap, slot_idx)`.
- [M] `combat/events/CombatSetup.gd:setup`: register the 9 routes from `CombatScene.gd:4917-4926` as lambdas over `state._fire_traps_for`. **Keep live's registration order** — today the trap routes are registered *before* `CombatSetup` runs, and handlers at equal priority resolve by insertion order. Register the routes first inside `CombatSetup.setup`.
- [D] `CombatState._check_and_fire_traps` (`:947-975`), the 4 sim routes (`SimTriggerSetup.gd:22-29`), the 9 scene stubs (`CombatScene.gd:4954-4981`) and their registrations.
- [T] `TriggerHandlerTests`: a player trap on `ON_PLAYER_MINION_DIED` during the enemy turn and on `ON_ENEMY_TURN_START`; an enemy trap on `ON_PLAYER_TURN_START`. Expect probes that relied on `mirror_trigger` to move; log each.
- [T] Handler-order snapshot: for each `TriggerEvent`, dump the registered callables in dispatch order after `CombatSetup.setup` on a fixed config; assert equal to a checked-in snapshot. Catches accidental reordering in this and every later step.
- [M] `TriggerManager.register` (`:52-58`): replace re-sort-on-register with an ordered insert (priority, then insertion order). Godot's `sort_custom` happens to be stable for ≤ 16 entries (insertion sort) and not above; this makes it explicit.
- Gate: `grep -rn '_check_and_fire_traps\|_trap_check_\|_enemy_trap_check_' --include='*.gd' .` → 0.

#### 2A.3 Turn engine on CombatState (both shells; D2, D5, D9, D10)
The turn engine is not animation-bound (draw animations are driven by the `card_drawn` signal), so both shells can share it now.
- [M] `CombatState.gd`: `is_player_turn`, `begin_turn(side)`, `end_turn(side)`; `start_combat()` draws opening hands (3 player / 5 enemy) and begins turn 1. Body = union of:
  - `TurnManager.begin_player_turn/begin_enemy_turn` (`:92-110`),
  - the gameplay lines of `CombatScene._on_turn_started/_on_turn_ended` (`:939-1021`): player spell-tax penalty + tax reset, Void Rift Lord mana drain (`EnemyAI.run_turn:236-248` for the enemy side), `_relic_hero_immune = false`, `_relic_cost_reduction = 0` (sim does these at `CombatSim:206-207`), hand `reset_deltas`, `_fiendish_pact_pending = 0` / `_enemy_fiendish_pact_pending = 0`, `_once_per_turn_used.clear()`, `relic_runtime.on_turn_start()`, `_temp_imps` expiry, penalty resets, traps-blocked resets, `_sweep_dead_minions` (`:4506`),
  - `SimState.begin_*_turn/end_*_turn` (`:536-617`), including the turn-end events from 0.2.
  - Ordering per D2 / D9. Emits `turn_started(side, turn_number)`, `turn_ended(side)`, `resources_changed(side, e, e_max, m, m_max)`.
  - **Delete, don't port:** Void Hourglass extra turn (`_relic_extra_turn` is never set true — the relic is now +1/+1, `RelicDatabase:101` — and `CombatScene:1016` calls `turn_manager.start_player_turn()`, which doesn't exist).
- [M] `combat/board/TurnManager.gd` (D5 façade): `begin_*`/`end_*` call `state.begin_turn/end_turn` and re-emit their UI signals. `CombatScene._on_turn_started/_on_turn_ended` keep only UI lines (log, end-turn button, labels, `_enemy_hero_panel.update`, slot refresh, `_refresh_hand_spell_costs`, `_relic_bar.refresh`, highlight/selection clear) and the `enemy_ai.run_turn()` kick-off. `EnemyAI.run_turn` loses growth/refill/drain/draw (now in `begin_turn("enemy")`).
- [M] `sim/SimTurnManager.gd` → [D]; `CombatSim` calls `state.begin_turn/end_turn`.
- Gate: `grep -rn 'class_name SimTurnManager\|_relic_extra_turn' --include='*.gd' .` → 0. `grep -cE '\bawait\b|get_tree\(\)|create_timer' combat/board/CombatState.gd` → 0. Live smoke green.

#### 2A.4 Resource growth (D1, D10)
- [M] Single hook: `CombatProfile.grow_resources(state: CombatState, side: String, turn: int) -> void`, called from `begin_turn(side)` for the enemy (live and sim) and for the player in sim (live player growth comes from the end-turn choice stored by `cmd_end_turn`, applied at `begin_turn` per D10).
- Port the 17 enemy `setup_resource_growth` overrides into `grow_resources` (16 pure; VoidWarband reads `state.hand_of(side)` / opponent board — fine). `MatriarchProfile.grow_resources` (`:40`) is rewritten to the new signature. Port the 6 player-profile overrides likewise (sim-only callers). Fix `ScoredCombatProfile` so it grows the side it's playing, not always the player.
- [D] `CombatProfile.setup_resource_growth`, `SimState.player_growth_override/enemy_growth_override`, `EnemyAI._choose_resource_growth` (`:283-287`).
- [T] One probe per ported enemy curve: turns 1–8 of `grow_resources` produce the same maxima the old sim callable did (capture the old values in the test before deleting).
- Gate: `grep -rn 'setup_resource_growth\|growth_override\|_choose_resource_growth' --include='*.gd' .` → 0.

#### 2A.5 One agent for sim, one profile registry
- [C] `enemies/ai/Pacer.gd` (`class_name Pacer`, RefCounted): `func after_action(kind: String) -> void: pass`.
- [C] `enemies/ai/StateAgent.gd` extends `CombatAgent`: `setup(state: CombatState, side: String, pacer: Pacer)`. Every `commit_*`/`do_attack_*` = `var r: CommandResult = state.cmd_*(side, ...)`; `await pacer.after_action(kind)`; `return r.ok and state.winner.is_empty()`. Utilities (`effective_spell_cost`, `opponent_has_rune_or_environment`, `consume_minion` → `state.cmd_consume_minion`) read state. `CombatAgent.commit_play_spell` gains `extra: Dictionary = {}`.
- [M] **Profiles stop paying costs (blocker if skipped).** Remove all 110 `agent.essence/mana -=` deductions in the 26 profile files (`grep -rnE 'agent\.(essence|mana) *-=' enemies`) in the **same commit** that switches sim to `StateAgent` — commands pay. Live `EnemyAgent → EnemyAI.commit_*` must then pay inside `EnemyAI.commit_*` (move the deduction there; it currently relies on the profile) so live behaviour is unchanged. The `CommandTests` double-pay probe guards this.
- [M] Hero skills: `SerisPlayerProfile:108,129`, `FleshcraftPlayerProfile:89,190` → `agent.hero_skill(skill_id, target)` → `state.cmd_hero_skill`. Delete the `agent.sim` field.
- [M] Profile writes via `agent.scene.set(...)` (`SpellBurnPlayerProfile:391-427`, `VoidWarbandProfile:493-496`): if diagnostic → `state.diagnostics` counters (plain dict on state for now); if gameplay → a command or a typed state field.
- [M] Profiles reading `agent.scene.<x>` (111 refs) → `agent.state.<x>`. `CombatProfile.gd:945-954` (`s.active_traps` / `s.active_environment`) → `state.traps_of(opponent)` / `state.environment_of(opponent)`. `EnemyAgent` exposes `state` as `scene.state` so profiles work in both shells.
- [C] `enemies/ai/ProfileRegistry.gd`: the single table, **namespaced by side** — `"default"` is `DefaultProfile` for enemy and `DefaultPlayerProfile` for player. `static func make(side: String, id: String) -> CombatProfile`. Union of `EnemyAI._PROFILES` (`:15-38`, 23 entries), `CombatSim._ENEMY_PROFILES` (`:20-49`, same 23 + 4 `scored*`), `_PLAYER_PROFILES` (`:84`, 8 entries). `EnemyAI` and `CombatSim` both read it.
- [M] `sim/CombatSim.gd:run`: two `StateAgent`s with a base `Pacer`; loop = `state.start_combat()`; while no winner: `await p_profile.play_phase(); SimRelicPolicy; await p_profile.attack_phase(); state.cmd_end_turn("player", growth)`; enemy likewise (`begin_turn` fires inside `cmd_end_turn` of the previous side).
- [D] `sim/SimPlayerAgent.gd`, `sim/SimEnemyAgent.gd`, `enemies/ai/EnemyAIProfile.gd` (dead alias, no references by name or uid). **Keep** `enemies/ai/EnemyAgent.gd` and `EnemyAI` executor bodies for live until Phase 3.4.
- Gate: `grep -rn 'class_name SimPlayerAgent\|class_name SimEnemyAgent\|class_name EnemyAIProfile\|_ENEMY_PROFILES\|_PLAYER_PROFILES\|const _PROFILES\|agent\.sim\b' --include='*.gd' .` → 0. `grep -rnE 'agent\.(essence|mana) *-=' enemies | wc -l` → 0.

#### 2A.6 Relic policy for sim
- [C] `sim/SimRelicPolicy.gd`: the bodies of `CombatSim._try_relic_start_of_turn/_mana_shard/_bone_shield/_dark_mirror/_void_lens/_blood_chalice` (`:540-633`), each ending in `state.cmd_activate_relic(index, target)`. Called by CombatSim exactly where the old calls were. Live `_on_relic_activated` (`CombatScene:2472`) → `state.cmd_activate_relic` too (relic activation has no card-flight animation; safe to switch now).

#### 2A.7 Encounter data in one place
- [C] `enemies/data/EncounterTable.gd`: the 15-encounter table from `GameManager._build_encounter` (`:251-380`: hp, deck source, ai_profile, passives, limited_cards, story text) as data. `GameManager._build_encounter` reads it; `CombatSim._ENEMY_PASSIVES` (`:53-81`), `BalanceSim._FIGHTS` (`:13-25`) and `ScoredAITest`'s HP constants read it. Fixes the `champion_abyss_sovereign` passive missing from sim (`GameManager.gd:363` vs `CombatSim.gd:77`) and the HP mismatches (F2: live 2100 / BalanceSim 2400 / ScoredAITest 2400; F3: 2200 / 2600 / 3000). **Live is the spec.** `BalanceSimBatch` already reads GameManager and is unaffected.
- Gate: `grep -rn '_ENEMY_PASSIVES\|const _FIGHTS' --include='*.gd' .` → 0.

#### 2A.8 Sim replay
- [C] `debug/ReplayRunner.gd` + `.tscn`: loads `{seed, config, command_log}` JSON, builds a state with the same config and seed, applies `command_log` through `cmd_*`, prints `digest_text()` and the first command whose result is `ok=false`. `CombatSim` gets a `--dump-replay <path>` flag. **Sim-generated logs only**; the CheatPanel "Dump replay" button for live fights waits for Phase 3.4, when live goes through commands.

#### 2A.9 Phase gates
```
tools/run_checks.sh     → green; CommandTests layer present; handler-order snapshot present; moved probes logged
python3 tools/lint/lint_engine.py   → 0 (adds L6: no await/get_tree/create_timer in CombatState.gd; L7: func begin_turn, func _fire_traps_for, each func cmd_*, ProfileRegistry table defined exactly once repo-wide)
godot --headless --path . res://debug/BalanceSimBatch.tscn -- --act 1 --runs 200 --seed 7   → run before 2A.2 and after 2A.9; same for --act 2; attach all four outputs to the task
```
Rollback: 2A.1 is additive. 2A.2 and 2A.3 each touch both shells — revert per commit. 2A.4 and 2A.5 must land together with their profile edits.

---

### Checkpoint (after 2A)

Stop and review with the owner:
1. Balance batch deltas from 0.2 (D7) and 2A (D1, D2, D8–D10, encounter-table fixes). Retune encounters if needed — that's a content task, not part of this plan.
2. Count of live-only bugs found since Phase 0's live smoke went in. If async-timing bugs (B12-class) keep appearing, schedule Phase 3.
3. Decide D11 (slot model) and D3/D4 before starting Phase 3.
4. Update `ARCHITECTURE.md` "Combat architecture" and "Headless simulation" to describe the 2A state: sim on commands, live still on `EnemyAI`/`_try_play_*`, shared turn engine and trap routing.

**Checkpoint closed 2026-09-24.** Item 4 landed in 2A.9. Items 1–2 (owner play-test of the D1/D8/D9/D10 live changes, encounter retuning) stay open as content work outside this plan; no B12-class bug was logged between 2A and the checkpoint, Phase 3 starts by owner request.

**Checkpoint decisions (verified against the code at `5454e70`):**

- **D11 — `SlotState`.** `combat/board/SlotState.gd` (`class_name SlotState`, RefCounted): `side: String`, `index: int`, `minion: MinionInstance`, `is_empty()`, `place(m)` (sets `m.slot_index`), `clear()`. `CombatState.player_slots / enemy_slots: Array[SlotState]`, allocated by the engine (today `SimState.setup` news up 10 `BoardSlot` Panels per fight and never frees them). `BoardSlot` keeps its `minion` field as the **displayed** occupant, set only by the presenter (`show_minion(m)` / `show_empty()`, replacing `place_minion` / `remove_minion`); `CombatScene` maps `(side, index)` → `BoardSlot` for VFX, which keep taking `BoardSlot` (they are presentation). Why: `BoardSlot.place_minion` refreshes visuals synchronously, which is exactly the "mutation shows before its animation" problem 3.2 has to solve (`freeze_visuals` is the workaround for it); events already carry slot indices, so the presenter needs the index → node map anyway; and once the engine holds no Node, L6 can ban Node-typed vars in `CombatState`. Lands as **3.1a**, before the journal, with a transitional `state.slot_changed(side, index)` signal that `CombatScene` answers with an immediate `BoardSlot` refresh until 3.2 takes over (visually identical to today).
- **D3 — inline.** `CombatState._on_minion_vanished` fires the death triggers at once for every minion; `_pending_on_death_vfx`, `_defer_on_death_vfx`, `wants_deferred_on_death`, `CombatVFXBridge.resolve_deferred_on_death` and the `pending` check in `CombatHandlers.on_minion_died_death_effect` are deleted in 3.0. The journal order is `MINION_DIED` → the on-death events; the presenter awaits the death animation and the on-death icon before playing what follows, so the player sees the same order as today. Live gameplay change: on-death effects now resolve before the killing effect continues (an AoE that kills three minions summons their tokens mid-resolution, not after) — this is what the sim has always done and what the balance numbers were tuned on. Probe: 3.5's journal-order test; visual QA: Void-Touched Imp (icon VFX then on-death damage).
- **D4 — hybrid.** `ViewState` holds only what the panels render: hero HP/max, Essence/Mana (both sides), Void Marks, Flesh, Forge, armour, hand, traps, environments, `turn_number`, `is_player_turn`. Board slots are not modelled per slot: the presenter hands `BoardSlot` the `MinionInstance` on playback, stat labels take `before` / `after` from the event payload (`DAMAGE_DEALT`, `BUFF_APPLIED`, `MINION_STATS_CHANGED`, `MINION_HEALED`), and the full refresh (art, keywords, status icons) reads the `MinionInstance` at playback. Upgrade trigger: if 3.6 QA shows a status icon or keyword appearing before its animation (e.g. the corruption icon before the apply VFX), add a per-slot `SlotView` snapshot then — not before.

---

### Phase 3 — De-async rules, journal, presenter, live switch (deferred)

**Goal.** Gameplay mutation happens only in the engine and synchronously. The engine records an ordered journal of `CombatEvent`s; a `CombatPresenter` drains it and plays one animation per event against a lagging `ViewState`. Then live input and the live enemy turn move onto commands.

**Entry condition.** Checkpoint done; D3, D4, D11 decided (all three decided 2026-09-24 — see "Checkpoint decisions").

#### 3.0 De-async rules (new; entry condition for the live switch)
Make every one of these mutate state inline and hand the VFX a callback-free "play this" request (or, once 3.1 exists, an event). Until 3.2 lands, the presenter hooks are fire-and-forget; the visual order may briefly regress — land 3.0 and 3.1/3.2 in the same session if possible.
- `HardcodedEffects.gd:109` (grafted butcher: AoE after VFX), `:280` (frenzied imp: damage inside VFX via `apply_damage`), `:289` (brood call: summon after portal), `:311` (pack frenzy: buffs + SWIFT after warcry).
- `CombatHandlers.gd:1358` (ritual sacrifice: kill, rune removal, damage, 500/500 demon, champion inside `vfx_bridge` callbacks), `:2387` (champion summon waits for `death_anims_done`), `:1255` (corruption detonation damage in `on_impact`).
- `CombatVFXBridge.gd`: `:532-539` (champion summon), `:690-696` (board append + `minion_summoned.emit`), `:741-761` (`_apply_ritual_damage`), `:804` and `:1439` (ON_*_MINION_SUMMONED fired after banner/sigil awaits), `:1206-1213` (`resolve_deferred_on_death`), `:1234` (`remove_minion`), `place_minion` at `:49, 66, 91, 790/793`.
- `CombatScene.gd`: `:2063` + `:4769, 4800` (corruption applied in popup drains — B13), `:2970, 2988` (Void Bolt damage at projectile impact), `:3486-3497` (trap resolution in card-anim callback — B12; `presenter.play_trap_reveal` becomes reveal-only), `_request_buff_apply` / `_flush_buff_requests` (`:1876-1946`, callers `EffectResolver.gd:507,517`, `HardcodedEffects.gd:167,177`), `_pending_on_death_vfx` (`:3145`, `CombatHandlers.gd:734`) per D3.
- `CombatInputHandler.gd:546-554` (hero Void Bolt attack awaits impact before damage).
- `BuffApplyVFX._apply_intents` (`:137`) → animates `pre → post` only.
- Gate: `grep -cE '\bawait\b' combat/events/CombatHandlers.gd combat/effects/EffectResolver.gd combat/effects/HardcodedEffects.gd relics/RelicEffects.gd combat/board/CombatManager.gd combat/board/CombatState.gd` → 0 each; no `BuffSystem.apply`, `place_minion`, `remove_minion`, `apply_*damage`, `trigger_manager.fire` in `CombatVFXBridge.gd` or `*VFX.gd`. Suite green; B12 probe (Smoke Veil cancels the triggering attack) passes.

#### 3.1a SlotState (D11)
- [C] `combat/board/SlotState.gd` as decided. [M] `CombatState`: `player_slots / enemy_slots: Array[SlotState]`, allocated in `setup` (SimState stops newing `BoardSlot`); `slot_of(side, index)`, `slot_for(minion)`; every engine `slot.place_minion / remove_minion` → `slot.place / clear` followed by `slot_changed.emit(side, index)`. [M] `BoardSlot`: `place_minion` → `show_minion`, `remove_minion` → `show_empty` (view only); `CombatScene.slot_node(side, index) -> BoardSlot` and `_find_slot_for(minion)` map through the state. Until 3.2, `CombatScene._on_slot_changed` refreshes the node immediately. [M] `CombatHandlers.gd:602, 1394-1408, 2413` and `TargetResolver.gd:70` read `SlotState`; the `global_position` read at `CombatHandlers:2413` moves to the presenter hook. Lint L6 gains "no `BoardSlot`/`Node`/`Control` typed vars in CombatState".
- Gate: `grep -n 'BoardSlot' combat/board/CombatState.gd sim/SimState.gd combat/events/CombatHandlers.gd combat/effects/TargetResolver.gd` → 0; suite green; batch byte-identical.

#### 3.1 CombatEvent and journal
- [C] `combat/board/CombatEvent.gd` (`class_name CombatEvent`, RefCounted): `kind: Kind`, `side: String`, `payload: Dictionary` (slot indices, card ids, `before`/`after`, hero sentinels; MinionInstance refs allowed; no Node refs), `seq: int`.
  Kinds: `TURN_STARTED, TURN_ENDED, RESOURCES_CHANGED, CARD_DRAWN, CARD_GENERATED, CARD_PLAYED, MINION_PLAYED, MINION_SUMMONED, TOKEN_SUMMONED, CHAMPION_SUMMONED, MINION_STATS_CHANGED, BUFF_APPLIED, ARMOUR_CHANGED, DAMAGE_DEALT, HERO_HEALED, MINION_HEALED, MINION_DIED, MINION_SACRIFICED, MINION_CONSUMED, SPELL_CAST, SPELL_RESOLVED, SPELL_COUNTERED, TRAP_PLACED, TRAP_FIRED, TRAP_REMOVED, RUNE_PLACED, ENVIRONMENT_CHANGED, RITUAL_FIRED, VOID_BOLT, VOID_MARKS_CHANGED, CORRUPTION_APPLIED, CORRUPTION_REMOVED, DETONATION, FLESH_CHANGED, FORGE_CHANGED, RELIC_ACTIVATED, ATTACK_STARTED, LOG, PHASE_TRANSITION, COMBAT_ENDED`.
  - `MINION_PLAYED` (hand play → card flight / enemy reveal) is distinct from `MINION_SUMMONED` / `TOKEN_SUMMONED`. Today `state.minion_summoned` fires for tokens too (`CombatState:555`, bridge `:696`); wiring card flight to it would animate every token as a hand play.
  - `SPELL_CAST` before resolution and `SPELL_RESOLVED` after bracket the spell's events so the presenter can freeze slots and capture popups (replaces the `_capturing_spell_popups` window).
- [M] `CombatState.gd`: `journal: Array[CombatEvent]`, `func emit_event(kind, side, payload)`; the presenter owns the cursor. Existing state signals are emitted from `emit_event`; every allowlisted presenter call from Phase 1 becomes an `emit_event`. `_summon_delegate` deleted.
- [M] `EffectResolver.gd:497-518`: `BUFF_ATK/BUFF_HP` → `BuffSystem.apply*` immediately, then `emit_event(BUFF_APPLIED, {minion, atk_before, atk_after, hp_before, hp_after, source_tag, silent})`.
- Land 3.1 with journal **and** old hooks both firing, so the presenter can be built against a working game.

#### 3.2 ViewState and CombatPresenter (D4)
- [C] `combat/board/ViewState.gd`: `player_hp/max, enemy_hp/max, essence/mana both sides, void_marks, flesh/flesh_max, forge/threshold, armour both sides, hand: Array[CardInstance], traps both sides, environment both sides, turn_number, is_player_turn`. Updated **only** by the presenter as it consumes events.
- [C] `combat/board/CombatPresenter.gd` (Node, child of CombatScene): `setup(scene, state, vfx_controller, vfx_bridge)`, `pump()`, `_drain()` coroutine: while `cursor < state.journal.size()`: `var ev: CombatEvent = state.journal[cursor]; cursor += 1; await _play(ev); _apply_to_view(ev); _emit_ui(ev)`. `signal idle`, `func is_idle() -> bool`, `func pump_and_wait_idle()`. `var instant: bool` for tests.
  `_play` table: `MINION_PLAYED("player")` → card flight + landing punch; `MINION_PLAYED("enemy")` → `show_enemy_summon_reveal` then landing; `TOKEN_SUMMONED` → sigil; `DAMAGE_DEALT` → `flash_hero`/popup; `SPELL_CAST` → `show_card_cast_anim` then `VfxController.play_spell`; `TRAP_FIRED` → flash + cast anim; `MINION_DIED` → `animate_minion_death`; `BUFF_APPLIED` → `BuffApplyVFX(pre, post)`; `VOID_BOLT` → projectile then popup; `RITUAL_FIRED` → ritual sequence; `CHAMPION_SUMMONED` → `champion_summon_sequence`; `ATTACK_STARTED` → lunge; `PHASE_TRANSITION` → `PhaseTransition`; `COMBAT_ENDED` → `_on_victory/_on_defeat`.
- [M] UI reads from `ViewState` (`CombatUI`, `EnemyHeroPanel.update(view)`, `PlayerHeroPanel`, `PipBar`, `TrapEnvDisplay`, `HandDisplay` via `CARD_DRAWN/CARD_PLAYED`). Board slots keep reading `MinionInstance`, but `_refresh_visuals` is called only from `_apply_to_view` and slots are frozen (`freeze_visuals`) between a mutation and its playback.
- [D] `_capturing_spell_popups`, `_pending_hero_popups`, `_drain_pending_spell_popups*` (`:4747-4827`), `_pending_spell_popups`, `_deferred_death_slots`/`_flush_deferred_deaths`.

#### 3.3 Gates and pacing
- [D] `_enemy_summon_reveal_active`, `_enemy_spell_cast_active`, `_on_play_vfx_active`, `_play_vfx_gate_count`, `acquire/release_play_vfx_gate`, `_active_death_anims`, the four signals (`:100-158`), `VfxGate` (`combat/effects/vfx/VfxGate.gd` — zero `begin`/`end` callers today, already dead) and every write site: `CombatVFXBridge.gd:161,183,207,212,257,267,317,321,443,776, 1106-1110, 1379-1416`; `CombatScene.gd:1934, 1958, 3585-3636, 3818-3927, 4491-4495`.
- [M] `CombatInputHandler`: commands accepted only when `state.is_player_turn and presenter.is_idle() and not _end_turn_in_progress`.
- Gate: `grep -rnE '_on_play_vfx_active|_active_death_anims|_enemy_summon_reveal_active|_enemy_spell_cast_active|enemy_summon_reveal_done|enemy_spell_cast_done|on_play_vfx_done|death_anims_done|VfxGate' --include='*.gd' .` → 0.

#### 3.4 Live switch (was 2.4-live / 2.5)
- [C] `combat/board/LivePacer.gd` extends Pacer: `after_action` → `await presenter.pump_and_wait_idle(); await get_tree().create_timer(ACTION_DELAY).timeout` (0.55 s, `EnemyAI.gd:193`).
- [M] `combat/board/EnemyAI.gd` → `EnemyTurnRunner` (≤ 80 lines): owns `StateAgent("enemy", LivePacer)`; `run_turn()` = `await profile.play_phase(); await pacer.after_action("phase"); await profile.attack_phase(); state.cmd_end_turn("enemy")`. Its 7 signals are deleted; the gameplay those CombatScene handlers carried already moved into commands in 2A.1; their presentation moved into the presenter in 3.2.
- [D] `enemies/ai/EnemyAgent.gd`, `EnemyAI` executor bodies, `presenter.reserved_slots` / `EnemyAI._pending_slots` (engine occupancy is authoritative; slots are filled synchronously).
- [M] `CombatInputHandler` — every player action through `state.cmd_*`. Full coverage list: minion play (`:82-93`), targeted minion play, spell play incl. hero-target spells (`:457-491`), **Cyclone** (`:403-439`, custom inline removal — make it a normal spell with an effect step), trap/environment/rune (`:177-190, 261-282`), minion attack (`:348-360`), hero attack incl. Void Bolt (`:528-560`), relic targeting, Seris corrupt / Soul Forge (`cmd_hero_skill`). Choices resolved first (`_resolve_spell_extra_cast_data` moves here from `CombatScene.gd:3408-3432`); **add a cancel path to `ChoiceModal`** (none exists) — cancel issues no command and the card stays in hand. On `ok=false` show the reason in the combat log and deselect.
- [D] `CombatScene._try_play_minion` (`:1343`, already dead — no callers), `_try_play_minion_animated`, `_try_play_spell/_trap/_environment`, `_apply_targeted_spell` (mutation half), `_pay_card_cost`, `_player_pay_sparks`, `_player_available_sparks`, `_player_can_afford_sparks`.
- [M] `_do_end_turn` (`:1065`) → `await presenter.pump_and_wait_idle()` then `state.cmd_end_turn("player", growth)`.
- [M] `combat/ui/CheatPanel.gd`: "Dump replay" → `user://replays/<unix>.json` `{seed, config, command_log}`; `ReplayRunner` (2A.8) now accepts live logs.

#### 3.5 Tests
- [T] `LiveSmokeTests`: full AI-vs-AI fight inside `CombatScene` with `presenter.instant = true` (player driven by `StateAgent("player", LivePacer)` with `DefaultPlayerProfile`); assert `state.winner != ""` within 60 s, `presenter.is_idle()`, `state.journal.size() == presenter.cursor`.
- [T] `CommandTests`: `BUFF_APPLIED` before/after; journal order for a spell that kills a minion with an on-death summon is `[SPELL_CAST, DAMAGE_DEALT, MINION_DIED, TOKEN_SUMMONED, SPELL_RESOLVED]`.
- [T] Lint **L8**: in `combat/effects/*VFX.gd`, `combat/effects/vfx/*.gd`, `combat/effects/CombatVFXBridge.gd`, `combat/ui/*.gd`, `combat/board/{BoardSlot,CombatPresenter,CombatUI,CombatInputHandler,TrapEnvDisplay,LargePreview,Targeting,CounterWarning}.gd`: `BuffSystem.apply`, `BuffSystem.apply_hp_gain`, `.place_minion(`, `.remove_minion(`, `combat_manager.`, `trigger_manager.fire`, `EffectResolver.run`, `state.<field> =`, `player_board.append/erase`, `enemy_board.append/erase`, `current_health =` are errors.

#### 3.6 Owner visual QA (blocks Phase 4)
Play and watch: (1) F1 Feral Pack — card flight, enemy reveal, attack lunge, death anim, buff pulse; (2) a Seris fight — sacrifice sequence, flesh counter lag, corruption detonation; (3) F15 — phase transition; (4) any ritual (rune placement then ritual fire); (5) Void Bolt projectile then HP drop; (6) Smoke Veil cancels the attack that triggered it; (7) a Korrath fight — Rally modal + cancel. Visual regressions are fixed in the presenter table, never by re-introducing mutation in VFX.

#### 3.7 Phase gates
```
tools/run_checks.sh     → green incl. full-fight live smoke, lint 0 with L8 active
grep -rnE 'class_name EnemyAgent|func _try_play_' --include='*.gd' . → 0
```

---

### Phase 4 — Collapse the duplicates (done 2026-09-25, task 044)

**Goal.** Delete everything that now has one implementation elsewhere. `CombatState` is used directly by tests and sim. `CombatScene` is presenter + input + wiring only.

#### 4.1 CombatConfig and one setup path
- [C] `combat/board/CombatConfig.gd`: `player_deck_ids, enemy_deck_ids, player_hp, enemy_hp, player_hero_id, talents, hero_passives, enemy_passives, enemy_profile_id, enemy_limited_cards, relic_ids, relic_bonus_charges, seed, diagnostics_enabled`. `static func from_game_manager()` (what `CombatScene._ready:642-762` reads) and `static func from_encounter(id, player_profile…)` (from `EncounterTable`).
- [M] `CombatState.setup_combat(config)`: body = `SimState.setup` + the `_ready` gameplay lines. Slots per D11 (engine-owned `SlotState`, or `bind_slots(player_slots, enemy_slots)` before `setup_combat`).
- [M] `CombatScene._ready` → `state.setup_combat(CombatConfig.from_game_manager()); CombatSetup.setup(state); presenter.setup(...)`.

#### 4.2 Diagnostics off SimState
- [C] `sim/CombatDiagnostics.gd`: `dmg_log`, `_capture_damage_for_dmg_log`, `turn_snapshot_callback`, `debug_log_enabled`, `_debug_soul_forge_fires`, `_debug_corrupt_flesh_fires`, the profile counters from 2A.5; subscribes to state signals/journal. `state.diagnostics: CombatDiagnostics = null`.
- [D] `sim/SimState.gd`. Update `CombatSim`, `TestHarness.build_state` (`:61` → `CombatState.new()` + `setup_combat`), `PhaseTransition`, `BalanceSim`, `DebugSingleSim`, `SimRunner`, `ScoredAITest`, `DebugF13LossAnalysis`, `VoidboltDmgDebug`.
- Gate: `grep -rn 'SimState' --include='*.gd' .` → 0.

#### 4.3 One CombatSetup
- [M] `CombatSetup.setup(state: CombatState)`: creates `TriggerManager` + `CombatHandlers`, registers trap routes (first) + always-on + the BuffSystem bus bridge (`SimTriggerSetup.gd:32-40`) + registry-driven talents/passives; `_apply` "stats" → `state.set`.
- [D] `sim/SimTriggerSetup.gd`, `CombatScene._setup_triggers` (`:4902-4952`; the `ancient_frenzy` hand injection at `:4928-4934` moves into `setup_combat`), `CombatState._active_enemy_passives`.
- Gate: handler-order snapshot (2A.2) unchanged.

#### 4.4 Delete the forwarders and scene delegates
- [D] All 105 `get: return state.X` forwarders **wherever they are** (100 in `CombatScene.gd:19-636`, interleaved with Node refs/signals/UI state that stay; 5 elsewhere — find with `grep -n 'return state\.' combat/board/CombatScene.gd`). Every remaining read in CombatScene/CombatUI/CombatInputHandler/Targeting/TrapEnvDisplay becomes `state.<x>` or `view.<x>`.
- [D] The one-line scene delegates to state (`lint --report-pairs` against CombatScene ∩ CombatState — 50 at `1c9aa30`).
- [M] `EffectContext.scene: Object` → `state: CombatState`; every `ctx.scene.` → `ctx.state.`. `HardcodedEffects.setup(state)`, `RelicEffects.setup(state)`, `CombatHandlers.setup(state)`; delete `presenter` members from all rules classes.
- [D] `CombatState.presenter`, `_get_scene_facade`, `_scene_facade`; `TurnManager.gd` (D5).
- Gate: `grep -rn 'ctx\.scene\|_scene_facade\|_get_scene_facade\|\.presenter' --include='*.gd' combat/effects combat/events relics` → 0. `--report-pairs` → 0.

#### 4.5 Optional split (D6)
Pure move into `combat/engine/`. No behaviour change; parity test (Phase 5) must exist first.

#### 4.6 Deletions checklist
`sim/SimState.gd`, `sim/SimTriggerSetup.gd`, `combat/board/TurnManager.gd`, `combat/effects/BroodCallVFX.gd`, `combat/effects/corruption_bloom.gdshader`, `plague_cloud.gdshader` (all three unreferenced by name or uid — can be deleted any time), `design/refactors/COMBAT_STATE_MANIFEST.md` → `design/refactors/archive/`. (Already gone by now: SimTurnManager, SimPlayerAgent, SimEnemyAgent, EnemyAIProfile — 2A; EnemyAgent, VfxGate — 3.)

#### 4.7 Docs
- `ARCHITECTURE.md`: rewrite "Combat architecture", "Headless simulation", "Trigger event system"; replace invariants 1, 4, 7, 9 with the rules in section 1; add `EscMenu` to the autoload table.
- `CLAUDE.md` "Adding New Trigger Handlers": register in `CombatSetup.setup(state)`; no mirroring.
- `design/TESTING.md`: fix paths, counts, remove the `tools/baseline` reference, add `tools/run_checks.sh`, CommandTests, LiveSmoke, Parity, ReplayRunner.

#### 4.8 Phase gates
```
tools/run_checks.sh   → green; lint 0 with L1–L9 (L9: no `.get("` / `has_method(` under combat/board, combat/events, combat/effects (non-VFX), relics, sim, enemies/ai)
wc -l combat/board/CombatScene.gd   → ≤ 2,000
ls sim/   → CombatSim.gd, CombatDiagnostics.gd, SimRelicPolicy.gd only
```

---

### Phase 5 — Parity tripwires (done 2026-09-25, task 045 — see the Progress note for deviations)

#### 5.1 Parity test
- [T] `debug/tests/ParityTests.gd`: for each of N ≥ 8 configs (ScenarioTests configs incl. Seris, Korrath, F15, relics) × 3 seeds:
  1. **Engine run:** `setup_combat(config)`; both sides `StateAgent` + base `Pacer`; capture `command_log` and `digest_text()` after every command.
  2. **Live replay:** headless `CombatScene.tscn`, same config/seed, `presenter.instant = true`; player commands replayed through `CombatInputHandler` entry points (`ReplayInputDriver`), enemy driven by the same profile. After each command `await presenter.pump_and_wait_idle()` and record `digest_text()`.
  3. Assert the digest arrays are equal; on mismatch print the first differing index, the command, and a line diff.
- Runtime budget ≤ 60 s; reduce configs, never seeds. Gate: `--filter parity` green 3 runs in a row.

#### 5.2 Live smoke matrix
- [T] AI-vs-AI full fights for every Act-1 encounter (from `EncounterTable`) with instant presenter; winner set, presenter idle, journal consumed, zero `SCRIPT ERROR`.

#### 5.3 Lint rules (final set, `tools/lint/lint_engine.py`)
| Rule | Introduced | Scope | Fails on |
|---|---|---|---|
| L1 | 0.3 | rules files, CombatSetup stats, MinionInstance | name declared on CombatState/SimState but not CombatScene, or declared nowhere — after Phase 4: any `_scene`/`scene.` reference |
| L2 | 0.4 | engine + rules + agents | `randi(`, `randf(`, `shuffle(`, `pick_random(` not via `rng` |
| L3 | 1.1 | rules files | presenter calls outside the allowlist; after Phase 4: any presenter call |
| L4 | 1.1 | rules files, agents, CombatManager | `has_method(`, `.get("` |
| L5 | 1.4 | — | `func` defined on both CombatScene and SimState; SimState overriding a CombatState func |
| L6 | 2A.9 | CombatState / engine | `await`, `get_tree(`, `create_timer(` (BoardSlot typed vars allowed until D11) |
| L7 | 2A.9 | repo | `func cmd_*`, `func begin_turn`, `func _fire_traps_for`, profile registry table defined more than once |
| L8 | 3.5 | presentation files | any mutation call (list in 3.5) |
| L9 | 4.8 | combat/board, combat/events, combat/effects (non-VFX), relics, sim, enemies/ai | `has_method(`, `.get("` |
| L10 | 5 | `*VFX.gd` | `await get_tree().create_timer` — count must not exceed `L10_BASELINE` (20 at 5.3) |
| L11 | 5 | combat/, relics/, debug/tests/ | a name reached through an untyped scene handle (`_scene.` / `scene.` / `_combat.` / `combat.`, and `<handle>.state.`) not declared on CombatScene (or a Node member) / CombatState |

Output `rule file:line: text`; exit code = error count.

#### 5.4 Wiring
- `tools/run_checks.sh` gains Parity; add `tools/hooks/pre-push` sample; document in TESTING.md.
- `/task-done` and `CLAUDE.md`: "`tools/run_checks.sh` must be green before a version commit."

---

## 5. Cross-phase gate summary (copy into each phase's task file)

```
# before / after every step
tools/run_checks.sh          # import → lint → RunAllTests → LiveSmoke; fails on SCRIPT ERROR

# phase end
git diff --stat HEAD~N       # confirm only the phase's files moved
```

## 6. Out of scope (log, do not do)

- Consolidating the five copies of the talent→support-pool mapping (`GameManager`, `RewardScene`, `ShopScene`×2, `UserProfile`) into `HeroDatabase.support_pools_for(hero_id, talents)` — separate task after 0.7's minimal fix.
- Encounter retuning after the balance deltas — content task at the checkpoint.
- Splitting `CardDatabase._register_wanderer_cards`, card-id constants, `EffectStep.from_dict` strictness.
- UI theme extraction, PipBar Flesh/Forge widget dedupe, VFX runner migration (L10 tracks it).
- AI profile deduplication beyond the registry and growth hook.

## Appendix A — duplicate pairs to be eliminated (with the step that removes each)

| Live | Sim | Step |
|---|---|---|
| `EnemyAI.commit_minion_play` :394 | `SimEnemyAgent.commit_play_minion` :105 | 2A.5 (sim) / 3.4 (live) |
| `EnemyAI.commit_spell_cast` :421 + `CombatScene._on_enemy_spell_cast` :3584 | `SimEnemyAgent.commit_play_spell` :139 | 2A.5 / 3.4 |
| `EnemyAI.commit_play_trap` :445 + `_on_enemy_trap_placed` :3641 | `SimEnemyAgent.commit_play_trap` :156 | 2A.5 / 3.4 |
| `EnemyAI.commit_play_environment` :463 | `SimEnemyAgent.commit_play_environment` :172 | 2A.5 / 3.4 |
| `EnemyAI.do_attack_minion/hero` :493/:517 | `SimEnemyAgent.do_attack_*` :189/:204 | 2A.1 / 3.4 |
| `EnemyAI._draw_cards` :302, `consume_minion` :322 | `SimState._draw_enemy` :523, `SimEnemyAgent.consume_minion` :219 | 1.3 / 2A.1 |
| `TurnManager.begin_player_turn` :92 + `CombatScene._on_turn_started` :939 | `SimState.begin_player_turn` :545 | 2A.3 |
| `CombatScene._try_play_minion[_animated]` :1343/:1391 | `SimPlayerAgent.commit_play_minion` :64 | 2A.1 / 3.4 |
| `CombatScene._try_play_spell/_apply_targeted_spell` :1149/:3348 | `SimPlayerAgent.commit_play_spell` :95 | 2A.1 / 3.4 |
| `CombatScene._try_play_trap/_environment` :1202/:1258 | `SimPlayerAgent.commit_play_trap/_environment` :116/:135 | 2A.1 / 3.4 |
| `CombatScene._on_minion_vanished` :3112 | `SimState._on_minion_vanished` :208 | 1.4 |
| `CombatScene._on_hero_damaged/_healed` :3218/:3279 | `SimState._on_hero_damaged/_healed` :244/:282 | 1.4 |
| `CombatScene._fire_traps_for` :3463 + 9 stubs | `CombatState._check_and_fire_traps` :947 + 4 lambdas | 2A.2 |
| `EnemyAI._PROFILES` :15 | `CombatSim._ENEMY_PROFILES` :20, `_PLAYER_PROFILES` :84 | 2A.5 |
| `GameManager._build_encounter` :251 | `CombatSim._ENEMY_PASSIVES` :53, `BalanceSim._FIGHTS` :13 | 2A.7 |
| `CombatProfile.grow_resources` (1 override) | `CombatProfile.setup_resource_growth` (24 overrides) | 2A.4 (D1) |
| `CombatScene._relic_runtime` :210 | `CombatSim` local `relic_rt` :173 | 1.5 |
| 105 forwarders on CombatScene | `SimState.state` self-alias :24 | 4.4 |

## Appendix B — what stays on CombatScene after Phase 4

Node refs (Tier C of the manifest), `presenter`, `input_handler`, `combat_ui`, `targeting`, `large_preview`, `counter_warning`, `_cheat`, transient selection state (`selected_attacker`, `pending_play_card`, `pending_minion_target`, `_awaiting_minion_target`, `_pending_relic_*`, `_hovered_hand_visual`), `_end_turn_in_progress`, scene wiring (`_find_nodes`, `_connect_*`), and the tooltip/style builders (`:3957-4308`, candidates for a later `UiStyle` extraction).

## Appendix C — verification log (2026-09-23)

Three read-only passes against `1c9aa30` checked every factual claim in the 2026-09-22 draft. Suite baseline confirmed at 784/784. Changes from the draft:

- **New live bugs added:** B7 (turn-end events never fire), B8 (Korrath rune methods), B9 (CombatSetup stats writes), B10 (`_scene.set/get` one-shot flags, incl. the VRP/AS re-summon a naive B1 fix would cause), B11 (champion summon race), B12 (Smoke Veil), B13 (corruption in VFX drain).
- **New divergences / decisions:** B14–B17 → D7, D8, D9, D10; D11 (slot model).
- **Downgraded:** B3 and B6 have no gameplay effect today; B4 is dead code (delete, not port); B5 is narrower (CorruptedHandler pass 1 + sim player profiles).
- **Corrected numbers:** RNG sites 43 (list was complete); growth overrides = 17 enemy + 6 player + Scored; `EnemyHeroPanel.update` has 14 call sites; `_build_encounter` at `:251`; ON_PLAYER_TURN_START at `CombatScene:983`; lint L1 initial count ≈ 25, not 3.
- **Structural change:** original Phase 2 split into 2A (sim/tests + shared turn/trap engine) and a Phase 3 that starts with an explicit de-async step (3.0) and ends with the live switch (3.4). Reason: live mutation is asynchronous in ~20 places today; synchronous commands in live before those are removed would make command results/replays wrong and visibly regress animation order.
- **Blockers added to steps:** profile cost double-payment (2A.5), profile hero-skill calls via `agent.sim` (2A.5), `"default"` profile-id collision (2A.5), handler registration order (2A.2), Phase 1 internal order (1.2 after 1.3/1.4), `_spell_dmg`/`_log` misclassified as presentation (1.1), `--import` + `player_deck` + `time_scale > 0` + profile-save guard for the live smoke (0.6), seed-before-shuffle ordering (0.4), task 009 commit prerequisite (0.7).
- **Dead code to delete, not port:** Void Hourglass extra turn (calls a nonexistent `turn_manager.start_player_turn()`), Imp Barricade redirect, void-bolt passive, `_try_play_minion` (no callers), `VfxGate` (no callers), `EnemyAIProfile`, `BroodCallVFX`, two shaders.
