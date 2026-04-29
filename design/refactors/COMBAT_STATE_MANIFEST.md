# CombatState Field Manifest

Working artifact for the Phase 0–5 refactor extracting `CombatState` (RefCounted, pure data) out of `combat/board/CombatScene.gd` so headless `sim/CombatSim.gd` can share the exact same data layer used in live combat. Replaces the current SimState ↔ CombatScene byte-for-byte duplication.

## Tiers

Every field in `CombatScene.gd` and `SimState.gd` is classified into one of four tiers:

- **A — pure data.** Moves to `CombatState` in Phase 1. No `Node` deps, no UI coupling.
- **B — input / animation transient.** Stays on `CombatScene`. Either an in-flight UI selection (`pending_play_card`) or animation-coordination state (`_anim_pre_hp`, `_deferred_death_slots`) that only the scene needs.
- **C — Node refs.** Stays on `CombatScene`. UI panels, labels, VFX controllers.
- **D — sim-only diagnostic.** Currently lives on SimState only. Decision: move to `CombatState` as opt-in (gated by `dmg_log_enabled`-style flags) so both runtimes can collect telemetry uniformly. Cost is ~30 unused fields in live combat; benefit is a single `damage_dealt(...)` signal that both `dmg_log` (sim) and `_spawn_damage_popup` (scene) subscribe to.

## Tier A — moves to CombatState

### Hero state
| Field | Type | Notes |
|---|---|---|
| `player_hp` | int | scene default 30 (cosmetic), sim default 3000 — unify on `GameManager.player_hp_max` at construction |
| `enemy_hp` | int | scene default 30, sim default 2000 — same fix |
| `enemy_hp_max` | int | set from `GameManager.current_enemy.hp` |
| `_sovereign_phase` | int | F15 P1/P2 marker |
| `_sovereign_transition_turn` | int | turn the P1→P2 transition fired |

### Resources
| Field | Type | Notes |
|---|---|---|
| `player_essence` / `_player_essence_max` | int | currently lives in `TurnManager` for live, in `SimState` for sim. CombatState owns the values; `TurnManager` becomes a thin facade that mutates state and emits scene-side animation hooks |
| `player_mana` / `_player_mana_max` | int | same |
| `enemy_essence` / `enemy_essence_max` | int | currently `EnemyAI` for live, `SimState` for sim |
| `enemy_mana` / `enemy_mana_max` | int | same |
| `last_player_growth` | String | "" / "essence" / "mana" — read by abyssal_mandate; setter in SimState already triggers off the property; CombatState formalizes this |

### Boards
| Field | Type | Notes |
|---|---|---|
| `player_board` / `enemy_board` | `Array[MinionInstance]` | |
| `player_slots` / `enemy_slots` | `Array[BoardSlot]` | sim pre-allocates plain `BoardSlot.new()`; live binds to scene-tree nodes. CombatState owns the array reference but doesn't construct slots — CombatScene/CombatSim each provide their own |

### Decks / hands / graveyards
| Field | Type | Notes |
|---|---|---|
| `player_deck` / `player_hand` / `player_graveyard` | `Array[CardInstance]` | currently TurnManager-owned for live, SimState-owned for sim |
| `enemy_deck` / `enemy_hand` / `enemy_graveyard` | `Array[CardInstance]` | EnemyAI-owned vs SimState-owned |
| `enemy_limited_cards` | `Array[String]` | |

### Traps / environments / runes
| Field | Type | Notes |
|---|---|---|
| `active_traps` | `Array[TrapCardData]` | player side |
| `active_environment` | `EnvironmentCardData` | player side |
| `enemy_active_traps` | `Array[TrapCardData]` | sim has this; live has it implicitly inside EnemyAI — unify |
| `enemy_active_environment` | `EnvironmentCardData` | same |
| `_rune_aura_handlers` | `Array[Dict]` | rune_id + entries — registered with TriggerManager |
| `_env_ritual_handlers` | `Array[Callable]` | |
| `enemy_void_marks` | int | |

### Talent / hero state
| Field | Type | Notes |
|---|---|---|
| `player_flesh` / `player_flesh_max` | int | Seris |
| `_fiendish_pact_pending` | int | Seris |
| `forge_counter` / `forge_counter_threshold` | int | Seris |
| `_player_spell_damage_bonus` | int | Seris (transient during spell cast) |
| `imp_evolution_used_this_turn` | bool | Vael |
| `_temp_imps` | `Array[MinionInstance]` | Imp Overload — die at end of turn |
| `talents` | `Array[String]` | sim has this; live reads `GameManager.player_talents` — unify on a `talents` field set by setup |
| `hero_passives` | `Array[String]` | sim has it; live reads `GameManager.current_hero` — unify |
| `player_hero_id` | String | sim has it for branching; live reads `GameManager.current_hero.id` |

### Cost penalties / spell counters
| Field | Type | Notes |
|---|---|---|
| `enemy_spell_cost_penalty` | int | sim only; live has it on EnemyAI — move to state |
| `enemy_spell_cost_aura` | int | same |
| `enemy_spell_cost_discounts` | Dict | per-card-id |
| `enemy_essence_cost_discounts` | Dict | per-card-id |
| `enemy_minion_essence_cost_aura` | int | F15 |
| `_spell_tax_for_enemy_turn` | int | |
| `_spell_tax_for_player_turn` | int | |
| `player_spell_cost_penalty` | int | |
| `_player_spell_counter` / `_enemy_spell_counter` | int | |
| `_enemy_traps_blocked` / `_player_traps_blocked` | bool | |
| `_soul_rune_fires_this_turn` | int | |
| `_void_mana_drain_pending` | bool | |
| `_spell_cancelled` | bool | gated by Silence Trap during enemy spell resolve |

### Crit / Dark Channeling
| Field | Type | Notes |
|---|---|---|
| `crit_multiplier` | float | global |
| `enemy_crit_multiplier` | float | per-side override |
| `_vp_pre_crit_stacks` | int | Vault Pre-Crit passive |
| `_spirit_conscription_fired` | bool | |
| `_enemy_crits_consumed` / `_player_crits_consumed` | int | |
| `_last_crit_attacker` | `MinionInstance` | |
| `_last_attack_was_crit` | bool | transient |
| `_last_attacker` | `MinionInstance` | populated during attack resolution |
| `_dark_channeling_active` | bool | |
| `_dark_channeling_multiplier` | float | |
| `_dark_channeling_amp_count` | int | |
| `_dark_channeling_amp_by_spell` | Dict | spell_id → count |
| `_dark_channeling_dmg_by_spell` | Dict | spell_id → bonus dmg |

### Champion counters (~30)
All `_champion_*` fields — RIP, CB, IM, ACP, VR, CH, RS, VA, VH, VS, VC, VCH, VW, VRP. Plus the support counters: `_vw_behemoth_plays`, `_vw_bastion_plays`, `_vw_behemoth_lost`, `_vw_bastion_lost`, `_vw_death_crit_grants`, `_void_echo_fired_this_turn`. Pure data — straight move.

### Encounter passive config
| Field | Type | Notes |
|---|---|---|
| `_active_enemy_passives` | `Array[String]` | populated from `GameManager.current_enemy.passives` |
| `void_mark_damage_per_stack` | int | 25 default, 40 with deepened_curse |
| `rune_aura_multiplier` | int | 1 default, 2 with runic_attunement |

### Relic flags
| Field | Type | Notes |
|---|---|---|
| `_relic_hero_immune` | bool | Bone Shield |
| `_relic_cost_reduction` | int | Dark Mirror |
| `_relic_extra_turn` | bool | Void Hourglass |

### Combat lifecycle
| Field | Type | Notes |
|---|---|---|
| `_combat_ended` | bool | re-entrancy guard — both sides need it |

### Sub-systems owned by CombatState
| Field | Type | Notes |
|---|---|---|
| `combat_manager` | `CombatManager` | already pure data. State owns it; scene reads `state.combat_manager` |
| `trigger_manager` | `TriggerManager` | event bus. State owns it; CombatSetup and SimTriggerSetup register handlers against it |
| `turn_manager` | `TurnManager` | scene-side; sim has its own `SimTurnManager`. **Decision:** keep both for now; in Phase 4 fold them into a single `TurnLogic` that lives on CombatState and emits signals. Until then `state.turn_manager` is the live one and `state.sim_turn_manager` is the sim one (scene/sim respectively assigns the appropriate ref). |
| `enemy_ai` | `EnemyAI` / `SimEnemyAgent` | same shape. Profile-driven. Stays on scene/sim respectively until Phase 4 — they encapsulate AI input, not state. |
| `_hardcoded` | `HardcodedEffects` | already mode-agnostic — moves to state |
| `_handlers` | `CombatHandlers` | scene-side handler bundle — moves to state once unified with SimTriggerSetup |

## Tier B — stays on CombatScene (input + animation transient)

### In-flight UI selection
- `selected_attacker: MinionInstance` — clicked-to-attack
- `pending_play_card: CardInstance` — card being played
- `pending_minion_target: MinionInstance` — pre-placement target
- `_awaiting_minion_target: bool`
- `_pending_relic_target: String`
- `_pending_relic_index: int`
- `_hovered_hand_visual: CardVisual`

### Animation transient
- `_anim_pre_hp: int`
- `_anim_atk_slot: BoardSlot`
- `_anim_def_slot: BoardSlot`
- `_deferred_death_slots: Array` — visuals waiting on lunge unfreeze
- `_pending_on_death_vfx: Array[MinionInstance]` — on-death effects waiting on icon VFX
- `_recent_popups: Array` — popup stacking
- `_enemy_summon_reveal_active: bool` + `enemy_summon_reveal_done` signal
- `_enemy_spell_cast_active: bool` + `enemy_spell_cast_done` signal
- `_on_play_vfx_active: bool` + `on_play_vfx_done` signal
- `_active_death_anims: int` + `death_anims_done` signal

These four signals stay scene-side — they coordinate animation, not state. EnemyAI still awaits them.

## Tier C — stays on CombatScene (Node references)

All UI labels, panels, controllers (~45 fields). No further classification needed:
`essence_label`, `mana_label`, `end_turn_*_button`, `fight_label`, `hand_display`, `trap_env_display`, `trap_slot_panels`, `enemy_trap_slot_panels`, `turn_label`, `deck_count_label`, `game_over_panel`, `game_over_label`, `restart_button`, `combat_log`, `_enemy_hero_panel`, `_enemy_status_panel`, `_enemy_panel_bg`, `_player_hero_panel`, `_player_status_panel`, `_pip_bar`, `_prev_essence`, `_prev_mana`, `vfx_controller`, `_vfx_layer`, `_vfx_shake_root`, `flesh`, `forge`, `targeting`, `large_preview`, `counter_warning`, `_relic_runtime`, `_relic_effects`, `_relic_bar`, `_cheat`.

## Tier D — sim-only diagnostics → move to CombatState as opt-in

These currently live only in SimState but every one of them counts events that ALSO happen in live combat. Moving them keeps both runtimes uniform. Live combat ignores the values; sim reads them at end-of-run.

| Field | Trigger event |
|---|---|
| `_ritual_sacrifice_count` | enemy ritual_sacrifice passive fires |
| `_detonation_count` | corrupt_authority detonation |
| `_player_ritual_count` | player ritual fires |
| `_spark_spawned_count` | Void Spark spawn |
| `_spark_transfer_count` | Void Spark transfer |
| `_champion_summon_count` | duplicate of scene's `_champion_summon_count` — already Tier A |
| `_corruption_detonation_times` | Tier A duplicate |
| `_ritual_invoke_times` | Tier A duplicate |
| `_handler_spark_buff_times` | Tier A duplicate |
| `_smoke_veil_fires` / `_smoke_veil_damage_prevented` | Tier A duplicates |
| `_abyssal_plague_fires` / `_abyssal_plague_kills` | Tier A duplicates |
| `_void_bolt_spell_casts` | new on state |
| `_void_bolt_total_dmg` | new on state |
| `_void_imp_dmg` | new on state |
| `_rift_lord_plays` / `_hollow_sentinel_buffs` / `_immune_dmg_prevented` / `_rift_collapse_casts` / `_rift_collapse_kills` | new on state |
| `dmg_log_enabled` / `dmg_log` / `_current_turn` / `_pending_dmg_source` | toggle + diagnostic stream |
| `turn_snapshot_callback` | sim hook for per-turn snapshots — keep but generalise to a list of subscribers |
| `winner` | end-of-combat result — already implicit in live (game_over_panel state) but explicit on state is cleaner |

Several "Tier D" entries are already duplicated in scene Tier A — those are wins from this consolidation.

## Phase 1 ordering inside Tier A

To keep PRs reviewable, move Tier A in batches roughly matching this order. Each batch is one PR; sim baseline regression-checked at the end of each.

1. **Skeleton.** Create `CombatState.gd` extending `RefCounted`. Move HP, sovereign, `_combat_ended`, board arrays, decks/hands/graveyards. Live scene gets a `state: CombatState` field; existing `var player_hp: int` etc. become forwarders (`var player_hp: int: get = func(): return state.player_hp; set = ...`). No behavior change.
2. **Resources.** Move essence/mana fields. TurnManager becomes a facade that calls into state.
3. **Traps / environments / runes / void marks.**
4. **Talent state.** Flesh, Forge, Fiendish Pact, spell damage bonus, temp imps, imp evolution flag.
5. **Cost penalties + spell counters + once-per-turn flags.**
6. **Crit + Dark Channeling.**
7. **Champion counters** — large but mechanical.
8. **Passive config + relic flags + sub-system pointers** (combat_manager, trigger_manager).
9. **Tier D diagnostics + `damage_dealt` signal.**

After step 9, SimState shrinks to a thin shell; Phase 3 can replace it entirely.

## Open questions (flagged for the user)

1. **TurnManager / EnemyAI ownership.** Live owns these on scene; sim has parallel `SimTurnManager` / `SimEnemyAgent`. The cleanest end-state is one `TurnLogic` owned by CombatState that emits `turn_started/ended/resources_changed`, with scene-side animation gating in subscribers. Recommend doing this in Phase 4. Confirm.
2. **Diagnostic counters in live.** Always-on, or guarded by a `diagnostics_enabled` flag? Always-on costs a few `int += 1` per event; flag adds a branch. Recommend always-on (simpler, drift-proof).
3. **`_combat_ended`.** Lives on state? Sim doesn't currently track it (`winner` plays that role). Recommend state owns both — `winner: String` and `_combat_ended: bool` are equivalent gates. Drop one in Phase 5.
4. **Behavior modules `Flesh` / `Forge`.** They take `self` (the scene) today. They become `Flesh.new(state)` after Phase 1. Confirm — minor refactor either way.

## Drift risks called out

- `_check_and_fire_traps()` (sim) vs `_fire_traps_for()` (scene) — same logic, different names. Phase 4 unifies.
- Spell VFX `await vfx_controller.play_spell(callable)` interleaves state mutation with animation timing. Phase 4 emits `spell_cast_resolved` immediately and lets scene animate independently.
- 11 sim-only no-op stubs (`_refresh_slot_for`, `_update_trap_display_for`, `_on_flesh_changed`, …) exist purely to satisfy duck-typing. Phase 3 deletes all of them — handlers stop calling scene methods and instead emit signals state-side that scene subscribers consume.
