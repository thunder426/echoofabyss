# Architecture Overview

Reference for the Echo of Abyss codebase. Lives at `design/master_doc/ARCHITECTURE.md`.
All paths in this doc are relative to `echoofabyss/` (the Godot project root).

## Quick file-finder

| Looking for… | Look in… |
|---|---|
| All card definitions | `cards/data/CardDatabase.gd` |
| Card data resource shapes | `shared/resources/{Card,Minion,Spell,Trap,Environment,Ritual}*.gd` |
| Live combat root | `combat/board/CombatScene.gd` |
| Pure combat data (shared with sim) | `combat/board/CombatState.gd` |
| Turn cycle / resources / draw | `combat/board/TurnManager.gd` |
| Attack math, hero damage, healing | `combat/board/CombatManager.gd` |
| Per-minion runtime state | `combat/board/MinionInstance.gd` |
| Buffs / debuffs (apply, tick, query) | `combat/board/BuffSystem.gd` |
| Player input (clicks, target prompts) | `combat/board/CombatInputHandler.gd` |
| "Signal X → refresh UI Y" wiring | `combat/board/CombatUI.gd` |
| Compound VFX (deaths, summons, projectiles) | `combat/effects/vfx/CombatVFXBridge.gd` |
| Spell/buff VFX dispatch | `combat/effects/vfx/VfxController.gd` |
| Declarative effect engine | `combat/effects/EffectResolver.gd` + `EffectStep.gd` + `EffectContext.gd` |
| Imperative card effects | `combat/effects/HardcodedEffects.gd` |
| Trigger event bus | `combat/events/TriggerManager.gd` |
| All trigger handler bodies | `combat/events/CombatHandlers.gd` |
| Live combat handler registration | `combat/events/CombatSetup.gd` |
| Sim handler registration | `sim/SimTriggerSetup.gd` |
| Headless simulator | `sim/CombatSim.gd`, `sim/SimState.gd` |
| Enemy turn execution | `combat/board/EnemyAI.gd` |
| Enemy decision logic | `enemies/ai/profiles/*.gd` |
| Encounter definitions (HP, deck, AI) | `enemies/data/EncounterDecks.gd` |
| Hero definitions / starter decks | `heroes/HeroDatabase.gd` |
| Talent definitions | `talents/TalentDatabase.gd` |
| Relic definitions | `relics/RelicDatabase.gd` |
| Relic effect implementations | `relics/RelicEffects.gd`, `relics/RelicRuntime.gd` |
| Run state, scene transitions, save | `shared/scripts/GameManager.gd`, `UserProfile.gd` |
| All shared enums | `shared/scripts/Enums.gd` |
| Balance simulation runners | `debug/BalanceSimBatch.gd`, `debug/DebugSingleSim.gd` |
| Test harness | `debug/tests/TestHarness.gd` |

## Autoloads

Declared in `project.godot` `[autoload]`. All accessible globally by name.

| Singleton | File | Role |
|-----------|------|------|
| `GameManager` | `shared/scripts/GameManager.gd` | Run state (acts, fights, void shards), player HP persistence, `go_to_scene()` transitions + auto-save |
| `UserProfile` | `shared/scripts/UserProfile.gd` | Profile load/save (decks, unlocks, high scores) |
| `CardDatabase` | `cards/data/CardDatabase.gd` | All card definitions + token cards, `get_card(id)` |
| `RelicDatabase` | `relics/RelicDatabase.gd` | All relic definitions, `get_offer_for_act(act)` |
| `TalentDatabase` | `talents/TalentDatabase.gd` | All talent definitions by hero/branch |
| `HeroDatabase` | `heroes/HeroDatabase.gd` | Hero definitions, starter decks, passives |
| `TestConfig` | `debug/TestConfig.gd` | Debug/test flags, drives `TestLaunchScene` |
| `AudioManager` | `shared/scripts/AudioManager.gd` | SFX + music playback |

Main scene: `res://ui/MainMenu.tscn`. Engine: Godot 4.6, GL Compatibility, 1920×1080.

## Scene flow

```
MainMenu → HeroSelectScene → DeckBuilderScene → TalentSelectScene
       → MapScene → EncounterLoadingScene → CombatScene
       → RewardScene (→ RelicRewardScene / ShopScene) → MapScene → …
```

`GameManager.go_to_scene()` handles every transition and auto-saves.

## Combat architecture

Combat is split across three orthogonal layers:

1. **State (data only)** — `CombatState.gd`, RefCounted, no Node refs. Holds board, HP, traps, environments, buffs, relic flags, talent state. Emits **all gameplay signals** (hp_changed, minion_summoned, minion_died, damage_dealt, traps_changed, environment_changed, flesh_changed, forge_changed, void_marks_changed, combat_log, minion_stats_changed, spell_damage_dealt). Shared between live combat and sim.
2. **Live shell** — `CombatScene.gd`, Node2D. Composes `CombatState`, owns UI nodes, handles input + animation/VFX gating. Forwards state fields via property getters/setters so handlers can write `scene.player_slots = …` and hit the same instance live or sim.
3. **Headless shell** — `SimState.gd extends CombatState`. No Node tree. Used by `CombatSim.gd` to run full matches with no UI for balance testing.

Handlers, effects, profiles, and the trigger system access combat through a duck-typed `_scene` reference. They never touch `CombatScene` UI nodes directly — see "Sim/CombatScene handler symmetry" feedback memory.

### Combat root — `CombatScene.gd`

Root script. Wires together every sub-system. Owns:

- `state: CombatState` (data layer)
- `turn_manager: TurnManager` (forwarded onto `state.turn_manager`)
- `enemy_ai: EnemyAI`
- `combat_manager: CombatManager`
- `trigger_manager: TriggerManager`
- `vfx_controller: VfxController`, `vfx_bridge: CombatVFXBridge`
- `combat_ui: CombatUI`, `input_handler: CombatInputHandler`
- UI nodes: `hand_display`, `_enemy_hero_panel`, `_player_hero_panel`, `pip_bar`, `combat_log`, `trap_env_display`, `large_preview`, `targeting`, `relic_bar`, `cheat_panel`, `phase_transition`, `counter_warning`

Declares the four **animation-gating signals** that EnemyAI and consecutive actions await on so VFX never overlap:

| Signal | Fired when |
|---|---|
| `enemy_summon_reveal_done` | Enemy summon-card reveal animation finished |
| `enemy_spell_cast_done` | Enemy spell cast + VFX finished |
| `on_play_vfx_done` | A minion's on-play VFX (e.g. Frenzied Imp hurl) finished |
| `death_anims_done` | Last in-flight `_animate_minion_death` completed |

These exist because EnemyAI runs as a coroutine; it `await`s on these signals between actions.

### Sub-systems orbiting CombatScene

These are separate `Node`/class objects, each instantiated once per combat. They all hold `_scene: CombatScene` and `state: CombatState` references and communicate via signals.

| File | Responsibility |
|---|---|
| `combat/board/TurnManager.gd` | Turn cycle; resource refill/growth; draw cards (hand cap 10). Signals: `turn_started`, `turn_ended`, `resources_changed`, `card_drawn`, `card_generated`, `player_turn_cleanup`. |
| `combat/board/CombatManager.gd` | Resolves attack math, simultaneous strike, hero damage/heal, shield. Signals: `attack_resolved`, `minion_vanished`, `hero_damaged`, `hero_healed`. No visuals. |
| `combat/board/MinionInstance.gd` | Per-board-slot RefCounted (HP, ATK, buffs, attack count, states EXHAUSTED/SWIFT/NORMAL). All stat changes go through `BuffSystem`. `card_data` is never mutated. |
| `combat/board/BuffSystem.gd` | Static helpers for apply/remove/query buffs. Lazy-inits a buff signal bus. Reads buff entries off `MinionInstance.buffs`. |
| `combat/board/BuffEntry.gd` | Single buff (type, value, source, expiry). |
| `combat/board/EnemyAI.gd` | Runs the enemy turn. Plays cards, attacks; awaits CombatScene gating signals. Profile registry maps profile-id strings → `EnemyAIProfile` subclass. Signals: `ai_turn_finished`, `minion_summoned`, `enemy_spell_cast`, `enemy_about_to_attack`, `enemy_attacking_hero`, `trap_placed`, `environment_placed`. |
| `combat/board/CombatInputHandler.gd` | Player input: card selection, target picking, placement, attack routing. Keeps CombatScene.gd lean. |
| `combat/board/CombatUI.gd` | "X mutated → refresh Y" subscriber layer. Listens to `CombatState` / `CombatManager` / `TurnManager` / `BuffSystem` signals and pushes changes into hero panels, pip bar, combat log, trap display, slots. The migration target for what used to be inline UI refresh on CombatScene. |
| `combat/board/BoardSlot.gd` | One minion position (visual). Signals: `slot_clicked_empty`, `slot_clicked_occupied`. |
| `combat/board/CombatLog.gd` | In-memory event log + scrollable label. |
| `combat/board/Targeting.gd` | Prompt label + target validation + slot highlighting for on-play targeted cards. |
| `combat/board/LargePreview.gd` | Bottom-left hover preview (art, stats, keywords). |
| `combat/board/CounterWarning.gd` | Persistent label warning that next spell is countered. |
| `combat/board/PhaseTransition.gd` | Abyss Sovereign P1→P2 transition orchestration. |
| `combat/board/TrapEnvDisplay.gd` | Active traps + environment slot panels. `trap_slot_panels.size()` is the cap RelicEffects checks. |

### Combat UI nodes (`combat/ui/`)

| File | Role |
|---|---|
| `CardVisual.gd` (+ `.tscn`) | One card in hand. Signals: `card_clicked`, `card_hovered`, `card_unhovered`. |
| `HandDisplay.gd` (+ `.tscn`) | Hand container. Signals: `card_selected`, `card_deselected`, `card_hovered`, `card_unhovered`, `card_anim_finished`. |
| `PlayerHeroPanel.gd` | Player HP bar, essence/mana display. |
| `EnemyHeroPanel.gd` | Enemy HP bar, void mark display. Signal: `hero_pressed`. |
| `PipBar.gd` | Essence + Mana resource pip columns. |
| `CostBadge.gd` | Card cost widget. |
| `SerisResourceBar.gd` | Seris-specific Flesh counter. |
| `CheatPanel.gd` | Debug panel (test config, quick damage, instant-win). |

## Effect system (data-driven)

Cards declare an `Array[EffectStep]` resolved by `EffectResolver`. Imperative-only effects fall through to `HardcodedEffects.gd` (legacy + irreducible logic). Both paths are duck-typed so they work in CombatScene and SimState identically.

| File | Role |
|---|---|
| `combat/effects/EffectResolver.gd` | Executes `effect_steps` arrays. Walks steps, gates on conditions, resolves targets, applies. |
| `combat/effects/EffectStep.gd` | Resource. Fields: `effect_type`, `scope` (SINGLE_CHOSEN, ALL_ENEMY, ALL_FRIENDLY, SELF, …), `amount`, `conditions`, `filter`, `permanent`, `multiplier_key`. Serializable from dict. |
| `combat/effects/EffectContext.gd` | Per-resolution context: scene, owner, targets, damage info, flesh/resource state. |
| `combat/effects/ConditionResolver.gd` | Evaluates conditional steps (`IF minion has X keyword, THEN apply Y`). |
| `combat/effects/TargetResolver.gd` | Resolves scope+filter into actual minion targets. |
| `combat/effects/HardcodedEffects.gd` | String-dispatch imperative card effects. Symmetric (player/enemy via `ctx.owner`). Used only when `effect_steps` is empty. |
| `combat/effects/SacrificeSystem.gd` | Sacrifice mechanic + tracking. |

When adding a new card, prefer declarative `effect_steps`. Add to HardcodedEffects only when truly necessary.

## Trigger event system

Every passive, relic, talent, trap, and on-play hook registers as a handler on `TriggerManager` with an event type and priority. Same code runs live and in sim — only the registration site differs.

| File | Role |
|---|---|
| `combat/events/TriggerManager.gd` | Per-combat event bus. `register_handler(event, callable, priority)`. Safe for handlers that mutate during iteration. |
| `combat/events/EventContext.gd` | Event payload (event type, source, targets, extra dict). |
| `combat/events/CombatHandlers.gd` | All handler implementations. Symmetric — uses `ctx.owner` and `_opponent_of()`, never hardcodes "player"/"enemy". |
| `combat/events/CombatSetup.gd` | Live-combat handler registration. Loads hero stats, deck, talents, relics, passives. |
| `sim/SimTriggerSetup.gd` | Sim handler registration. **Must stay in sync with CombatSetup** when registering new handlers. |

Event types are `Enums.TriggerEvent` values (ON_PLAYER_TURN_START, ON_MINION_DIED, ON_DAMAGE_DEALT, …).

## VFX system

VFX use a declarative phase-list runner (`VfxSequence`). Every VFX extends `BaseVfx`, overrides `_play()`, and calls `sequence().run([VfxPhase.new(...), ...])`. The runner owns the await/tree-check/finished/queue_free state machine. **Do not hand-roll** `await timer / is_inside_tree() / finished.emit / queue_free` glue — that's what the runner replaces.

| File | Role |
|---|---|
| `combat/effects/vfx/BaseVfx.gd` | Convention base for every VFX. Extends Node2D, parented to `VfxLayer` (CanvasLayer layer=2). Provides `impact_hit(index)` and `finished` signals, `sequence()` accessor for the lazy `VfxSequence`, `static var time_scale` global multiplier (debug knob), and `shake()` helper. |
| `combat/effects/vfx/VfxPhase.gd` | One phase descriptor — `name`, `duration`, builder Callable, scheduled beats. Chainable: `.emits(beat, t_norm)`, `.emits_at_start(beat)`, `.emits_at_end(beat)`, `.time_scale(s)`. |
| `combat/effects/vfx/VfxSequence.gd` | Per-VFX timeline runner. `run(phases)` walks each phase, calls builder, awaits duration, fires beats, emits `impact_hit` / `finished`, queue_frees. `seq.on(beat, cb)` subscribes listeners; `seq.emit_beat(beat)` fires geometric beats from inside builders. `seq.time_scale` for per-VFX slow-mo, composes with `BaseVfx.time_scale`. Debug watchdog warns on stuck sequences. |
| `combat/effects/vfx/VfxController.gd` | Central spell VFX dispatcher. `_SPELL_DISPATCH` table maps `spell_id → _play_<spell>` method. Spawns VFX, gates damage on `impact_hit`, tracks Pack Frenzy state. |
| `combat/effects/vfx/CombatVFXBridge.gd` | Compound orchestration — sigil summons, death animations, summon reveals, projectiles, hero flashes, popups, buff request aggregation. |
| `combat/effects/BuffVfxRegistry.gd` | `source_tag` → BuffApplyVFX prelude/palette lookup. |
| `combat/effects/SacrificeVfxRegistry.gd` | Sacrifice source_tag → SacrificeVFX prelude lookup. |

Sequence template:
```gdscript
class_name MyVFX
extends BaseVfx

func _play() -> void:
    var seq := sequence()
    seq.on("impact", _spawn_flash)
    seq.run([
        VfxPhase.new("windup", 0.20, _build_windup),
        VfxPhase.new("impact", 0.40, _build_impact) \
            .emits_at_start("impact") \
            .emits_at_start(VfxSequence.RESERVED_IMPACT_HIT),
        VfxPhase.new("fade",   0.30, _build_fade),
    ])

func _build_windup(duration: float) -> void: ...
```

Specific VFX scripts (one per spell/buff/event) live flat in `combat/effects/`. The VFX quality bar (shader-based distortion, composed phases, damage synced to impact beat) is documented in the `feedback_vfx_quality.md` memory.

Buff state mutation flow: EffectResolver's `BUFF_ATK` / `BUFF_HP` cases call `_scene._request_buff_apply(...)` which queues intents into `_pending_buff_requests`. `_flush_buff_requests` (deferred) spawns `BuffApplyVFX` with the intents; the VFX calls `BuffSystem.apply` at its chevron beat so state mutation is visibly aligned with the value tween. Sim falls through to immediate `BuffSystem.apply` via the `vfx_controller != null` guard.

Shaders sit alongside as `.gdshader` files: `plague_cloud`, `plague_flood`, `crescent_shockwave`, `sonic_wave`, `casting_glyph_glow`, `corruption_bloom`, `card_summon_wave`, `void_execution_wipe`, `void_netter_net_mask`, `blessing_shaft`.

## Card data model

Base `CardData` and subclasses live in `shared/resources/` and are pure `Resource` (no nodes).

| Resource | Adds |
|---|---|
| `CardData.gd` | id, card_name, cost, description, art_path, card_type |
| `MinionCardData.gd` | atk, hp, keywords, tags, faction, minion_type, effect_steps, on_play_target_prompt, battlefield_art_path |
| `SpellCardData.gd` | effect_steps, target requirements, is_piercing_void |
| `TrapCardData.gd` | trigger event, effect_steps, reusable flag, rune aura |
| `EnvironmentCardData.gd` | passive aura buff, ritual definitions |
| `RitualData.gd` | 2-rune consumption + effect_steps |

Per-copy runtime wrapper:

- `shared/scripts/CardInstance.gd` — unique `instance_id`, holds `CardData` ref, `cost_delta` for temporary cost changes, `resolved_on_turn`.

## Resource economy

- **Essence** — summons minions; refills + grows each turn.
- **Mana** — spells/traps/environments; refills + grows each turn.
- Combined cap: `essence_max + mana_max ≤ 11`. Essence hard cap: 10.
- Stats are face value. No ×100 conversion.

## AI & profiles

| Layer | File | Role |
|---|---|---|
| Live executor | `combat/board/EnemyAI.gd` | Coroutine that runs the enemy turn. Reads decisions from a profile. |
| Sim executor | `sim/SimEnemyAgent.gd`, `sim/SimPlayerAgent.gd` | Same role for headless sim. |
| Base profile | `enemies/ai/EnemyAIProfile.gd`, `enemies/ai/CombatProfile.gd` | Subclass interface. Override `decide_next_action()` → `ACTION_PLAY_CARD` / `ACTION_ATTACK` / `ACTION_END_TURN`. |
| Scoring helpers | `enemies/ai/ScoringWeights.gd`, `enemies/ai/ScoredCombatProfile.gd`, `enemies/ai/BoardEvaluator.gd` | Weighted-random decision support. |
| Player sim profiles | `enemies/ai/profiles/*PlayerProfile.gd` | Player decks for balance sims (Default, Fleshcraft, Seris, SpellBurn, Swarm, RuneTempo). |
| Encounter profiles | `enemies/ai/profiles/*Profile.gd` | One per encounter family: Feral Pack, Matriarch, Corrupted Brood, Void faction (Aberration, Captain, Champion, Herald, Ritualist, Scout, Warband), Cultist Patrol, Rift Stalker, Corrupted Handler, etc. |

Encounter definitions: `enemies/data/EncounterDecks.gd` (`get_encounter(id)` → `EnemyData`). `EnemyData.gd` resource fields: `enemy_name`, `hp`, `deck`, `ai_profile`, `passives`, `limited_cards`, `portrait_path`, story/background.

## Headless simulation (`sim/`)

Used for balance testing — no UI, no scene tree, no animations.

| File | Role |
|---|---|
| `sim/CombatSim.gd` | Entry point. `run(deck, profile_id, …)` → win/loss + diagnostic counters. |
| `sim/SimState.gd` | Extends `CombatState`. Pure data. |
| `sim/SimTurnManager.gd` | Extends `TurnManager`. Direct property mutations instead of node-bound signals where the live one needs nodes. |
| `sim/SimPlayerAgent.gd`, `sim/SimEnemyAgent.gd` | Per-side action runners. Use the same `CombatProfile` subclasses as live combat. |
| `sim/SimTriggerSetup.gd` | Sim's `CombatSetup` analogue. Mirror of live registration. |

Sim defaults: always reach for `BalanceSimBatch` first; `DebugSingleSim` only for step-by-step debug logs (memory: `feedback_sim_defaults.md`).

## Talents

| File | Role |
|---|---|
| `talents/TalentData.gd` | Resource. id, name, description, branch, tier, effect (handler or passive flag). |
| `talents/TalentDatabase.gd` | Autoload registry, grouped by hero/branch. |
| `talents/TalentSelectScene.gd` (+ `.tscn`) | Pick-1-of-3 selection scene during a run. |

Talents implement effects by registering handlers in `CombatSetup` / `SimTriggerSetup`. Per the damage-type system, talents retag at the call site rather than auto-tagging by faction.

## Relics

| File | Role |
|---|---|
| `relics/RelicData.gd` | Resource. id, name, charges, cooldown, act, effect refs. |
| `relics/RelicDatabase.gd` | Autoload registry. `get_offer_for_act(act)` returns 2 random. |
| `relics/RelicRuntime.gd` | Per-combat charge/cooldown tracker, `activated_this_turn` flag. |
| `relics/RelicEffects.gd` | Imperative relic effect implementations. Pattern: register triggers in `CombatSetup`, handlers check active relics and apply effects. |
| `relics/RelicBar.gd` | UI for active relic display (charges, cooldown). |
| `relics/RelicRewardScene.gd` (+ `.tscn`) | End-of-boss relic offer. |

## Heroes

| File | Role |
|---|---|
| `heroes/HeroData.gd` | Resource. id, name, portrait_path, deck (starter card ids), passive_talents. |
| `heroes/HeroDatabase.gd` | Autoload. `get_hero(id)` → `HeroData`. |
| `heroes/HeroPassive.gd` | Hero-attached passive ability data. |
| `heroes/wanderer/` | Per-hero asset folder. |

## Other systems

| Area | File(s) |
|---|---|
| Title screen | `ui/MainMenu.gd` (+ `.tscn`) |
| Hero select | `ui/HeroSelectScene.gd` |
| Deck builder | `ui/DeckBuilderScene.gd` |
| Card collection viewer | `ui/CollectionScene.gd` |
| Read-only deck preview | `ui/DeckViewerScene.gd` |
| Map / encounter selection | `map/MapScene.gd` |
| Pre-fight loading screen | `map/EncounterLoadingScene.gd` |
| Card reward selection | `rewards/RewardScene.gd` |
| Shop | `shop/ShopScene.gd` |

## Debug & simulation tooling (`debug/`)

| File | Role |
|---|---|
| `debug/TestConfig.gd` | Autoload. Debug flags (TestLaunchScene, TestCardID, TestEncounterID). |
| `debug/TestLaunchScene.gd` | Loads a debug combat or sim run from `TestConfig`. |
| `debug/BalanceSim.gd` | Single-encounter balance test (N iters vs one profile). |
| `debug/BalanceSimBatch.gd` | **Default sim entry point.** Full Act × profile matrix, spreadsheet-friendly output. |
| `debug/DebugSingleSim.gd` | Single sim with verbose turn-by-turn log. |
| `debug/SimRunner.gd` | Generic CombatSim wrapper. |
| `debug/DebugF13LossAnalysis.gd` | Abyss Sovereign (F13) loss-pattern diagnostic. |
| `debug/ScoredAITest.gd` | Tests weighted-scoring AI profiles. |
| `debug/EnemyDeckBuilder.gd` | Hand-built enemy decks for testing. |
| `debug/VoidboltDmgDebug.gd` | Void Bolt damage diagnostic. |
| `debug/tests/TestHarness.gd` | Base test framework (assert, run, report). |
| `debug/tests/RunAllTests.gd` | Aggregate test runner. |
| `debug/tests/{CardEffect,DamageType,TriggerHandler,Scenario}Tests.gd` | Test suites. |

## Key enums

All in `shared/scripts/Enums.gd`:

`CardType`, `CostType`, `MinionType`, `Keyword`, `MinionState`, `BuffType`, `TriggerEvent`, `RuneType`, `DamageType`, `DamageSchool`.

## Architectural patterns to preserve

These rules are the load-bearing invariants of the codebase. Breaking them tends to break sim, PvP-readiness, or both.

1. **State / shell separation.** Game data lives on `CombatState`. `CombatScene` is the live shell with UI; `SimState` is the headless shell. Never put gameplay data on the scene; never let handlers reach into UI nodes.
2. **Symmetric handlers.** Every trigger handler uses `ctx.owner` and `_opponent_of()` — never hardcoded `"player"` / `"enemy"`. Future-proofs for PvP.
3. **Symmetric effects.** Every card effect must work for either side as owner.
4. **Sim parity.** Handlers and effects call wrapper methods on `_scene`, not direct UI nodes. SimState has no UI; direct access spams 19k errors and chokes the balance sim.
5. **Declarative first.** New cards use `effect_steps` (`EffectStep` resources). Add to `HardcodedEffects.gd` only when imperative logic is unavoidable.
6. **Damage tagging is opt-in.** Set `damage_school` only when the card has deliberate flavor. `NONE` is correct for generic spells. Talents retag at the call site.
7. **Animation gating via signals.** EnemyAI and consecutive actions await the four CombatScene gating signals (`enemy_summon_reveal_done`, `enemy_spell_cast_done`, `on_play_vfx_done`, `death_anims_done`) so VFX never overlap.
8. **Type from untyped collections.** Always `var x: Type = arr[i]`, never `var x := arr[i]`. GDScript's `:=` from an untyped Array/Dictionary infers `Variant` and causes silent errors.
9. **Trigger registration mirroring.** When you add a handler in `CombatSetup.gd`, mirror it in `SimTriggerSetup.gd`. They must stay in sync.
10. **Card data lives in CardDatabase.gd.** Single source of truth. Never duplicate card stats elsewhere.
