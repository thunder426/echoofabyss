# Architecture Overview

Reference for the Echo of Abyss codebase. Lives at `design/master_doc/ARCHITECTURE.md`.
All paths in this doc are relative to `echoofabyss/` (the Godot project root).

## Quick file-finder

| Looking for… | Look in… |
|---|---|
| All card definitions | `cards/data/CardDatabase.gd` |
| Card data resource shapes | `shared/resources/{Card,Minion,Spell,Trap,Environment,Ritual}*.gd` |
| Live combat root (presenter + input + wiring) | `combat/board/CombatScene.gd` |
| The combat engine (all gameplay data + rules, shared by live / sim / tests) | `combat/board/CombatState.gd` |
| A fight's inputs / the one setup path | `combat/board/CombatConfig.gd` → `CombatState.setup_combat(config)` |
| Turn cycle / resources / draw | `CombatState.gd` (turn engine: `start_combat`, `begin_turn`, `end_turn`, `cmd_end_turn`) |
| Event journal → animations | `combat/board/CombatEvent.gd`, `CombatPresenter.gd`, `ViewState.gd` |
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
| Handler registration (every shell) | `combat/events/CombatSetup.gd` (`CombatSetup.setup(state)`) |
| Headless simulator | `sim/CombatSim.gd` (+ `CombatDiagnostics.gd`, `SimRelicPolicy.gd`) |
| Live enemy turn | `combat/board/EnemyTurnRunner.gd` |
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
| `EscMenu` | `shared/scripts/EscMenu.gd` | Escape / pause menu overlay |

Main scene: `res://ui/MainMenu.tscn`. Engine: Godot 4.6, GL Compatibility, 1920×1080.

## Scene flow

```
MainMenu → HeroSelectScene → DeckBuilderScene → TalentSelectScene
       → MapScene → EncounterLoadingScene → CombatScene
       → RewardScene (→ RelicRewardScene / ShopScene) → MapScene → …
```

`GameManager.go_to_scene()` handles every transition and auto-saves.

## Combat architecture

One engine, two drivers, one presenter (the live/sim unification, plan Phases 0–4):

1. **Engine — `CombatState.gd`** (RefCounted, no Node refs, never awaits — lint L6). Every gameplay field and rule: board occupancy (`player_slots / enemy_slots: Array[SlotState]`, `slot_of(side, i)`, `slot_for(minion)`), HP / `HeroState`s, traps, environments, buffs, relic flags + `relic_runtime`, talent and passive state, both sides' turn counter, resources, decks, hands and graveyards (`hand_of/deck_of/graveyard_of/traps_of(side)`, `draw_cards`, `add_to_hand`, `pay_card_cost`, `pay_sparks`, …), the CombatManager signal handlers, the **turn engine** (`start_combat`, `begin_turn`, `end_turn`, `growth_hooks`), **trap routing** (`TRAP_ROUTES` → `_fire_traps_for`) and the **command surface** — `cmd_play_minion / play_spell / play_trap / play_environment / attack / attack_hero / consume_minion / activate_relic / hero_skill / end_turn`: synchronous, validate-then-mutate (`CommandResult`), pay their own costs (`plan_cost`), recorded in `command_log`; each defined once (L7). Built by **`setup_combat(CombatConfig)`** — seed, heroes and passives, HP, both decks and opening hands, CombatManager, HardcodedEffects, `CombatSetup.setup(self)` (triggers), relics — on every shell; `teardown()` drops the BuffSystem bus subscription. Every mutation appends a `CombatEvent` to the ordered **journal** (`emit_event(kind, side, payload)`); the gameplay signals (hp_changed, damage_dealt, turn_started, …) still fire for listeners like CombatDiagnostics. Nothing extends CombatState (L5).
2. **Drivers.** *Sim and tests:* `CombatSim` builds a CombatState, one `StateAgent` + `ProfileRegistry` profile per side, and loops `start_combat` → profile phases → `cmd_end_turn` (relic use via `SimRelicPolicy` → `cmd_activate_relic`); `CombatSim.replay` / `ReplayRunner` replay a `command_log`. Tests call `TestHarness.build_state` (a `CombatConfig` through `setup_combat`) and the commands or handlers directly. *Live:* `CombatScene._ready` calls `state.setup_combat(CombatConfig.from_game_manager())`, then `state.start_combat()`; player input goes through the same commands (`CombatInputHandler` / `CombatScene._command_play_*` pick the target or choice, pop the hand visual for the flight and call `cmd_*`; a refusal leaves the card in hand; end turn is `cmd_end_turn("player", growth)`, the Seris skills `cmd_hero_skill`); the enemy is `EnemyTurnRunner.run_turn` — a `StateAgent` paced by `LivePacer` — ending with `cmd_end_turn("enemy")`. Resource growth is each side's `CombatProfile.grow_resources(state, side, turn)` behind `state.growth_hooks`.
3. **Presentation — `CombatPresenter.gd`** (live only). Drains the journal one event at a time, awaits the animation for it, then applies it to the lagging `ViewState` and refreshes the UI (plan 3.2, D4 hybrid — hero HP / resources / marks / flesh / forge / armour / traps / environments / turn on the view; board slots render the `MinionInstance` handed to them at playback, stat labels driven by event before/after values). Card-specific animation is a `VFX` event; UI resync points (`HAND_COSTS_CHANGED`, `SPELL_COUNTER_CHANGED`, `CHAMPION_PROGRESS`, …) are events too. The enemy waits for `presenter.pump_and_wait_idle()` between actions; the player's end turn waits for it before the turn passes.

Rules code (CombatState, CombatSetup, CombatHandlers, HardcodedEffects, RelicEffects, EffectResolver, Condition/TargetResolver, EffectContext, CombatManager, MinionInstance, PhaseTransition) reaches combat only through the typed `state` / `ctx.state`: it holds no shell (`_scene`, `ctx.scene` — L1), never calls presentation (`presenter` — L3), never duck-types (L4), and presentation never mutates gameplay (L8).

### Combat root — `CombatScene.gd`

The live shell (≤ 2,000 lines, plan 4.8): presenter + input + wiring. Owns:

- `state: CombatState` (the engine — every gameplay read and write, from the scene and its helpers alike)
- `presenter: CombatPresenter`, `enemy_turn: EnemyTurnRunner`
- `vfx_controller: VfxController`, `vfx_bridge: CombatVFXBridge`
- `combat_ui: CombatUI`, `input_handler: CombatInputHandler`, `targeting`, `large_preview`, `counter_warning`, `ui_style: CombatUiStyle`
- UI nodes: `player_slots / enemy_slots` (the `BoardSlot` views), `hand_display`, `_enemy_hero_panel`, `_player_hero_panel`, `_pip_bar`, `combat_log`, `trap_env_display`, `_relic_bar`, `_cheat`
- transient selection state (`selected_attacker`, `pending_play_card`, `pending_minion_target`, `_pending_relic_*`, …) and `_end_turn_in_progress`
- the animation bodies the presenter awaits (attack lunges, card flight, cast animation, death ghost, buff batching, ritual capture / merge)

It no longer forwards any state field or delegates to state methods (`lint_engine.py --report-pairs` → 0).

### Sub-systems orbiting CombatScene

These are separate `Node`/class objects, each instantiated once per combat. The UI helpers hold `_scene: CombatScene` and read `_scene.state` directly.

| File | Responsibility |
|---|---|
| `combat/board/CombatConfig.gd` | A fight's inputs as data (decks, HP, hero, talents, hero / enemy passives, profile ids, limited cards, relics, seed). `from_game_manager()` (live — consumes `GameManager.next_combat_seed`), `from_dict(d, seed)` (CombatSim's JSON-safe config / replay records). |
| `combat/board/CombatManager.gd` | Resolves attack math, simultaneous strike, hero damage/heal, shield. Signals: `attack_resolved`, `minion_vanished`, `hero_damaged`, `hero_healed`. No visuals. |
| `combat/board/MinionInstance.gd` | Per-board-slot RefCounted (HP, ATK, buffs, attack count, states EXHAUSTED/SWIFT/NORMAL). All stat changes go through `BuffSystem`. `card_data` is never mutated. |
| `combat/board/BuffSystem.gd` | Static helpers for apply/remove/query buffs. Lazy-inits a buff signal bus. Reads buff entries off `MinionInstance.buffs`. |
| `combat/board/BuffEntry.gd` | Single buff (type, value, source, expiry). |
| `combat/board/EnemyTurnRunner.gd` | Runs the live enemy turn (was EnemyAI): builds the profile from `ProfileRegistry` on a `StateAgent("enemy", LivePacer)`, `run_turn` = play phase → pacer beat → attack phase → `state.cmd_end_turn("enemy")`; the enemy's `growth_hooks` entry. Rebuilds its profile on `state.enemy_profile_changed` (F15). Holds no enemy-side state. |
| `combat/board/CombatInputHandler.gd` | Player input: card selection, target picking, placement, attack routing. Keeps CombatScene.gd lean. |
| `combat/board/CombatUI.gd` | UI refresh bodies the presenter calls as it plays events (hero panels, pip bar, combat log, trap display, hand costs, end-turn mode). |
| `combat/board/CombatPresenter.gd` | Node child of CombatScene (plan 3.2). Drains `state.journal` from a deferred start (so a synchronous resolution is fully journaled before its first event plays), `await`s one animation per event (`_play`), then applies the event to `ViewState` and refreshes the UI (`_emit_ui`). Look-ahead: `ATTACK_STARTED` consumes the following damage events and shows them at the lunge's hit; `SPELL_CAST` consumes its damage / corruption / heal events up to `SPELL_RESOLVED` and shows them at the spell VFX impact (`play_captured_all`, `play_captured_for_slot` for wave spells); `VOID_BOLT` consumes the hero hit for its projectile; consecutive `BUFF_APPLIED` / `DETONATION` events batch. `pump_and_wait_idle()` / `is_idle()` / `idle` are what the enemy turn, end-turn and tests wait on; `instant` skips animations. |
| `combat/board/ViewState.gd` | The lagging copy of the state the panels render (hero HP / resources / marks / flesh / forge / armour / traps / environments / turn), updated only by the presenter. |
| `combat/board/LivePacer.gd` | The live enemy's `Pacer`: after every command, `await presenter.pump_and_wait_idle()` then a 0.55 s beat. |
| `combat/board/CombatEvent.gd` | One journal entry (plan 3.1): `seq`, `kind` (TURN_STARTED … COMBAT_ENDED, see the enum), `side`, `turn`, `payload` (slot indices, ids, before/after values, minion refs — never Nodes). `CombatState.emit_event` appends them in mutation order; `DAMAGE_DEALT` (minion via `CombatManager._deal_damage`, hero via `_on_hero_damaged`), `BUFF_APPLIED` (before/after stats), `SPELL_CAST` … `SPELL_RESOLVED` bracket a spell's events. |
| `combat/board/SlotState.gd` | Engine-owned board slot (plan 3.1a, D11): `side`, `index`, `minion`, `is_empty()`, `place(m)` (stamps `slot_index`), `clear()`; both emit `changed`. Rules code and the AI agents hold these, never the view (lint L6). |
| `combat/board/BoardSlot.gd` | One minion position (view of a `SlotState`). `show_minion` / `show_empty` set what it displays — never gameplay occupancy; `freeze_visuals` holds the current look through an animation. Signals: `slot_clicked_empty`, `slot_clicked_occupied`. |
| `combat/board/CombatLog.gd` | In-memory event log + scrollable label. |
| `combat/board/Targeting.gd` | Prompt label + target validation + slot highlighting for on-play targeted cards. |
| `combat/board/LargePreview.gd` | Bottom-left hover preview (art, stats, keywords). |
| `combat/board/CounterWarning.gd` | Persistent label warning that next spell is countered. |
| `combat/board/PhaseTransition.gd` | Abyss Sovereign P1→P2 transition (typed on `CombatState`, runs inside the engine): refill, silent board wipe, passive swap (`CombatSetup.apply_passive`), P2 deck, `enemy_profile_id` + `enemy_profile_changed`. |
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
| `CheatPanel.gd` | Debug panel (test config, quick damage, instant-win). The one UI file allowed to mutate state (L8 exempt). |
| `ChoiceModal.gd` | Modal choice prompt (e.g. Rally the Ranks' race pick). |
| `CombatUiStyle.gd` | Panel styleboxes and the faction empty-slot look (static), and the hero panels' hover tooltips (`scene.ui_style`). |

## Effect system (data-driven)

Cards declare an `Array[EffectStep]` resolved by `EffectResolver`. Imperative-only effects fall through to `HardcodedEffects.gd` (legacy + irreducible logic). Both run against the typed `ctx.state`, so live, sim and tests execute the same code.

| File | Role |
|---|---|
| `combat/effects/EffectResolver.gd` | Executes `effect_steps` arrays. Walks steps, gates on conditions, resolves targets, applies. |
| `combat/effects/EffectStep.gd` | Resource. Fields: `effect_type`, `scope` (SINGLE_CHOSEN, ALL_ENEMY, ALL_FRIENDLY, SELF, …), `amount`, `conditions`, `filter`, `permanent`, `multiplier_key`. Serializable from dict. |
| `combat/effects/EffectContext.gd` | Per-resolution context: `state` (typed CombatState), owner, source, chosen target / object, flesh spent, extra cast data. `EffectContext.make(state, owner)`. |
| `combat/effects/ConditionResolver.gd` | Evaluates conditional steps (`IF minion has X keyword, THEN apply Y`). |
| `combat/effects/TargetResolver.gd` | Resolves scope+filter into actual minion targets. |
| `combat/effects/HardcodedEffects.gd` | String-dispatch imperative card effects. Symmetric (player/enemy via `ctx.owner`). Used only when `effect_steps` is empty. |
| `combat/effects/SacrificeSystem.gd` | Sacrifice mechanic + tracking. |

When adding a new card, prefer declarative `effect_steps`. Add to HardcodedEffects only when truly necessary.

## Trigger event system

Every passive, relic, talent, trap, and on-play hook registers as a handler on `TriggerManager` with an event type and priority. One registration for every shell: `CombatState.setup_combat` calls `CombatSetup.setup(state)`, which creates the TriggerManager + `CombatHandlers`, registers the trap routes first, bridges the BuffSystem `corruption_removed` bus to ON_CORRUPTION_REMOVED, then the always-on handlers, then the registry-driven talents / passives. Equal priorities dispatch in registration order (ordered insert); `debug/tests/snapshots/handler_order.txt` pins the full order.

**Traps** spring through `CombatState.TRAP_ROUTES` → `_fire_traps_for(owner, trigger, minion)`: exact trigger match (no mirroring), skipped while the side's traps are blocked, consumed before resolving, the player's friendly-death route only on the enemy's turn. Each trap resolves inline; the presenter plays its reveal from TRAP_FIRED (B12 fixed in Phase 3.0).

| File | Role |
|---|---|
| `combat/events/TriggerManager.gd` | Per-combat event bus. `register(event, callable, priority)` (ordered insert), `fire(ctx)`, `dump_order()`. Safe for handlers that mutate during iteration. |
| `combat/events/EventContext.gd` | Event payload (event type, source, targets, extra dict). |
| `combat/events/CombatHandlers.gd` | All handler implementations. Symmetric — uses `ctx.owner` and `_opponent_of()`, never hardcodes "player"/"enemy". |
| `combat/events/CombatSetup.gd` | The one handler registration, for every shell (`static setup(state)`): TriggerManager + handlers, trap routes, the BuffSystem bus bridge, always-on handlers, registry-driven talents / hero passives / enemy passives and their stat overrides; `apply_passive` / `unapply_passive` for the F15 swap. |

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

Buff flow: EffectResolver's `BUFF_ATK` / `BUFF_HP` cases apply through `BuffSystem` at once and journal `BUFF_APPLIED` with before / after stats (`silent` while `state._silent_buff_apply` — presence-aura recompute). The presenter batches consecutive buffs into `CombatScene._show_buff_apply`, which merges requests per minion + source, holds the slot labels at the pre-buff values (`BoardSlot.hold_stats`) and spawns one `BuffApplyVFX` per bucket with `set_stat_snapshot`; the VFX tweens pre → live at its pulse beat and owns no mutation.

Shaders sit alongside as `.gdshader` files: `plague_flood`, `crescent_shockwave`, `sonic_wave`, `casting_glyph_glow`, `card_summon_wave`, `void_execution_wipe`, `void_netter_net_mask`, `blessing_shaft`.

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
| Agent interface | `enemies/ai/CombatAgent.gd` | What a profile acts through: boards/hand/resources, typed `state`, `side`, `commit_play_*`, `do_attack_*`, `consume_minion`, `hero_skill`, `can_place_trap`, cost queries. Profiles only check affordability — the engine pays; spark fuel a profile consumes is credited to its next play (`sparks_prepaid`). |
| Agent | `enemies/ai/StateAgent.gd` (+ `Pacer.gd`, live `LivePacer.gd`) | One side of a CombatState: every action is a `state.cmd_*`, then `pacer.after_action`. Both sim sides, the tests and the live enemy (`EnemyTurnRunner`) run on it. |
| Profile registry | `enemies/ai/ProfileRegistry.gd` | The one id → profile table, by side (`make(side, id)`); EnemyTurnRunner and CombatSim both use it. |
| Base profile | `enemies/ai/CombatProfile.gd` | `play_phase()` / `attack_phase()`, `grow_resources(state, side, turn)` (resource curve, run from `begin_turn`), targeting helpers. |
| Scoring helpers | `enemies/ai/ScoringWeights.gd`, `enemies/ai/ScoredCombatProfile.gd`, `enemies/ai/BoardEvaluator.gd` | Weighted-random decision support. |
| Player sim profiles | `enemies/ai/profiles/*PlayerProfile.gd` | Player decks for balance sims (Default, Fleshcraft, Seris, SpellBurn, Swarm, RuneTempo). |
| Encounter profiles | `enemies/ai/profiles/*Profile.gd` | One per encounter family: Feral Pack, Matriarch, Corrupted Brood, Void faction (Aberration, Captain, Champion, Herald, Ritualist, Scout, Warband), Cultist Patrol, Rift Stalker, Corrupted Handler, etc. |

Encounter definitions: `enemies/data/EncounterTable.gd` — the one table of the 15 encounters (HP, passives, default AI profile + the variant profiles that share its passives, story text); `GameManager.get_encounter(i)` builds `EnemyData` from it and picks a deck from `enemies/data/EncounterDecks.gd`; the sim reads HP / passives from it (`passives_for_profile`). `EnemyData.gd` resource fields: `enemy_name`, `hp`, `deck`, `ai_profile`, `passives`, `limited_cards`, `portrait_path`, story/background.

## Headless simulation (`sim/`)

Used for balance testing — no UI, no scene tree, no animations.

| File | Role |
|---|---|
| `sim/CombatSim.gd` | Entry point. `run(deck, profile_id, …)` → win/loss + diagnostic counters. Builds a plain `CombatState` through `setup_combat(CombatConfig.from_dict(config, seed))`, a `StateAgent` + `ProfileRegistry` profile per side, installs their `grow_resources` as `growth_hooks` (the enemy's follows `enemy_profile_changed` at the F15 transition), and loops `start_combat` → phases → `cmd_end_turn`. `replay(record)` replays a `command_log`. |
| `sim/CombatDiagnostics.gd` | Optional reporting attached as `state.diagnostics`: the damage-to-enemy-hero log by source (incl. Void Bolt's split base / mark log) and the debug print of every combat-log line. The per-mechanic counters (`_smoke_veil_fires`, `_debug_soul_forge_fires`, …) stay on the state. |
| `sim/SimRelicPolicy.gd` | When the sim player activates each relic (`cmd_activate_relic`). |

Determinism: every gameplay random draws from `CombatState.rng`, seeded by `setup_combat` from the config (`CombatSim.run(…, rng_seed)` in sim, `GameManager.next_combat_seed` or a fresh roll in live — lint L2). `CombatSim.run` returns `seed` + `digest` so any run replays exactly.

Sim defaults: always reach for `BalanceSimBatch` first; `DebugSingleSim` only for step-by-step debug logs (memory: `feedback_sim_defaults.md`).

## Talents

| File | Role |
|---|---|
| `talents/TalentData.gd` | Resource. id, name, description, branch, tier, effect (handler or passive flag). |
| `talents/TalentDatabase.gd` | Autoload registry, grouped by hero/branch. |
| `talents/TalentSelectScene.gd` (+ `.tscn`) | Pick-1-of-3 selection scene during a run. |

Talents implement effects by registering handlers in `CombatSetup`. Per the damage-type system, talents retag at the call site rather than auto-tagging by faction.

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
| `debug/tests/LiveSmokeTests.gd` + `LiveSmoke.tscn` | Headless boot of the live `CombatScene` (the only live-shell test). |
| `tools/run_checks.sh` | The gate: import → `tools/lint/lint_engine.py` (L1–L9; `--report-pairs` lists scene/state func pairs) → `tools/lint/load_all_scripts.gd` (every script compiles) → RunAllTests → LiveSmoke; fails on any `SCRIPT ERROR`; per-run timeout `RUN_CHECKS_TIMEOUT` (300 s). |

## Key enums

All in `shared/scripts/Enums.gd`:

`CardType`, `CostType`, `MinionType`, `Keyword`, `MinionState`, `BuffType`, `TriggerEvent`, `RuneType`, `DamageType`, `DamageSchool`.

## Architectural patterns to preserve

These rules are the load-bearing invariants of the codebase. Breaking them tends to break sim, PvP-readiness, or both.

1. **One engine.** Every gameplay field and rule lives on `CombatState`, built by `setup_combat(CombatConfig)`. `CombatScene` is presenter + input + wiring; the sim and the tests drive a plain CombatState. Never put gameplay data on the scene; never let rules code reach the scene or UI nodes.
2. **Symmetric handlers.** Every trigger handler uses `ctx.owner` and `_opponent_of()` — never hardcoded `"player"` / `"enemy"`. Future-proofs for PvP.
3. **Symmetric effects.** Every card effect must work for either side as owner.
4. **Sim parity.** Both sides act only through `state.cmd_*` (live input, the live enemy, the sim agents, the tests), so a fight replays from its `command_log`. Rules code mutates only `state` and never calls presentation; a gameplay method has one body, on CombatState, which nothing extends (lint L5).
5. **Declarative first.** New cards use `effect_steps` (`EffectStep` resources). Add to `HardcodedEffects.gd` only when imperative logic is unavoidable.
6. **Damage tagging is opt-in.** Set `damage_school` only when the card has deliberate flavor. `NONE` is correct for generic spells. Talents retag at the call site.
7. **Presentation plays the journal.** Nothing on screen changes before the presenter plays the event that explains it, and nothing in presentation mutates gameplay: rules code journals (`state.emit_event`, incl. `VFX` events for card-specific animation) and `CombatPresenter` plays. Anything that must wait for the screen (the enemy's next action, the end of the player's turn, a test) waits for `presenter.pump_and_wait_idle()`.
8. **Type from untyped collections.** Always `var x: Type = arr[i]`, never `var x := arr[i]`. GDScript's `:=` from an untyped Array/Dictionary infers `Variant` and causes silent errors.
9. **Trigger registration in one place.** Register handlers in `CombatSetup.gd` only — `setup_combat` calls `CombatSetup.setup(state)` for every shell.
10. **Card data lives in CardDatabase.gd.** Single source of truth. Never duplicate card stats elsewhere.
11. **Typed access, no duck typing.** In handlers/effects gameplay is `state.x` / `ctx.state.x` — no shell handle (L1), no presenter (L3), never by string (`has_method`, `.get("x")`, `"x" in obj` — L4 in rules code, L9 across combat/board, combat/events, non-VFX combat/effects, relics, sim and enemies/ai).
12. **Engine-owned RNG.** Gameplay randomness uses `state.rng_pick / rng_shuffle / rng_range / rng_index`, never global `randi()/shuffle()/pick_random()`. VFX may use the global RNG. Lint L2 enforces it.

The live/sim unification refactor ([LIVE_SIM_UNIFICATION_PLAN.md](../refactors/LIVE_SIM_UNIFICATION_PLAN.md)) is through Phase 4: one engine (`CombatState`, one `setup_combat` path, one `CombatSetup`), commands for both drivers, the journal + presenter, and no shell / presenter access from rules code; SimState, SimTriggerSetup, TurnManager and the scene's state forwarders are gone. Left: the owner's visual QA (3.6), the Phase 5 parity test and live smoke matrix, the D6 file split (4.5, after the parity test), a ChoiceModal cancel, and the F15 forced end of the player's turn (still triggered by the presenter at PHASE_TRANSITION; the sim does not end the turn).
