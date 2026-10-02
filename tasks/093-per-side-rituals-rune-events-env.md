---
id: "093"
title: Per-side rituals and rune events (environment rituals, ON_RUNE_PLACED / ON_RITUAL_FIRED for either side)
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap §A, owner decision Q2 ("rituals"; the ritual half of the A-paths unit's "A3b"). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Runes work for both sides: `cmd_play_trap` applies the rune aura for either side (CombatState.gd:2701-2702), and the aura triggers are mirrored for enemy owners. Everything built on rune placement is player-only.

### ON_RUNE_PLACED is fired for the player only

- `cmd_play_trap` (CombatState.gd:2701-2707):
  ```gdscript
  if trap.is_rune:
  	_apply_rune_aura(trap, side)
  	# Rituals consume the player's runes only.
  	if side == "player":
  		var rune_ctx := EventContext.make(Enums.TriggerEvent.ON_RUNE_PLACED, "player")
  ```
- Korrath's random rune (:1904-1907) and Oblivion Seal (RelicEffects.gd:134-138) also fire it with "player". Those placements are player-only today (tasks 098 and 091).

### Its listeners don't know whose rune it was

| Listener | Registered | Reads |
|---|---|---|
| Rune Warden, `on_player_minion_died_rune_warden` | CombatSetup.gd:586, priority 5 | `state.player_board` (CombatHandlers.gd:681-686) |
| Grand Ritual: Chaos (Korrath talent) | registry, CombatSetup.gd:221-223, priority 10 | `state.active_traps`, `state.enemy_board`, `state.player_board`; fires ON_RITUAL_FIRED as "player" (CombatHandlers.gd:318-381) |
| Talent grand rituals (Abyss Convergence) | lambdas in CombatSetup.gd:625-632, priority 0 | `state.active_traps` via `on_grand_ritual` (CombatHandlers.gd:688-691) |
| Environment rituals | lambdas in `_register_env_rituals` (CombatState.gd:373-379), priority 5 | `state.active_traps` via `on_env_ritual` (CombatHandlers.gd:693-696) |

If ON_RUNE_PLACED simply fired for the enemy, a player Rune Warden would gain 200 ATK whenever the enemy places a rune. Every listener needs the placing side.

### Rituals resolve as the player

- `_fire_ritual(ritual)` (CombatState.gd:853-897) does everything as the player:
  - it increments `_player_ritual_count`;
  - it consumes runes from `active_traps` and calls `_remove_rune_aura(trap)` with the default owner "player";
  - it calls `_update_trap_display_for("player")` and journals RITUAL_FIRED as "player";
  - it runs the ritual's steps with `EffectContext.make(self, "player")` and fires ON_RITUAL_FIRED as "player".
- ON_RITUAL_FIRED's one listener is Ritual Surge (CombatSetup.gd:73-75). It summons for "player" (CombatHandlers.gd:172-173; task 055 switches it to `ctx.owner`).

### Environment rituals are one global list

- `_env_ritual_handlers: Array[Callable]` (CombatState.gd:1620) is filled by `_register_env_rituals(env)` (:373-379) and cleared by `_unregister_env_rituals()` (:389-393).
- `cmd_play_environment` registers and unregisters rituals, and fires ON_RITUAL_ENVIRONMENT_PLAYED, only `if side == "player"` (:2734-2747).
- Task 050's `destroy_environment(side)` calls `_unregister_env_rituals()` for the player side only, for the same reason.
- The handlers are lambdas capturing `_handlers`. Task 049 lists them (and the grand-ritual lambdas, CombatSetup.gd:630, :632) as reference-cycle holders.

### Presentation and docs

- `_capture_ritual_visual` (CombatScene.gd:1527-1549) always reads the player's `trap_slot_panels`, whatever RITUAL_FIRED's side (CombatPresenter.gd:234-237).
- The comments say player-only: Enums.gd:97-99 ("Player places a Rune", `ctx.owner = "player"`), TrapCardData.gd:25, CombatState.gd:849-852 and :2703.
- `_player_ritual_count` feeds CombatSim.gd:318, which BalanceSimBatch prints as `PRit`.

### Out of scope

F5's enemy "ritual" (`on_enemy_summon_ritual_sacrifice`, CombatHandlers.gd:1210-1280) is an encounter passive. It consumes the enemy's Blood + Dominion runes on a feral imp summon and doesn't use RitualData, `_fire_ritual` or ON_RITUAL_FIRED. Under Q2, encounter passives are enemy config. Leave it as it is.

### Reachable today

Enemy decks place runes: f2_c (`dominion_rune`, `blood_rune`), f4_b (`shadow_rune`), f5_a (`dominion_rune` ×2, `blood_rune` ×2). After this task those placements fire ON_RUNE_PLACED. No enemy has an environment, a ritual talent or a Rune Warden, so with correct side filters nothing should change. A balance delta would mean a listener is missing its filter.

## Decision (owner, 2026-10-01)

- Q2: "rituals must all work for either side in the engine. The enemy doesn't have to use them today." Who has what is decided by data and config, never by `if owner == "player"` in rules code.
- Q3: accept and record any BalanceSimBatch delta. Enemy runes exist in f2_c, f4_b and f5_a, so record Acts 1–2.

## Proposed fix

1. **Fire ON_RUNE_PLACED for the placing side.** In `cmd_play_trap`, drop `if side == "player"` and build the context with `side`. Korrath's random rune and Oblivion Seal pass their owner's side (still "player" until tasks 098 / 091 make them per side). Voidshaped Acolyte's PLACE_RUNE_ON_OPPONENT (EffectResolver.gd:298-313) is a fourth placement site and fires no ON_RUNE_PLACED today. Decide at task start whether a rune placed onto a side counts as that side placing it; if so, fire it there with the rune owner's side (the opponent of the caster). With correct side filters no listener reacts today. Task 084 routes all four sites through `place_trap`.
2. **Every listener acts for its owner only, and reads its owner's runes.**
   - Environment rituals: register `_handlers.on_env_ritual.bind(ritual, side)` (a bound method callable, no lambda). The handler returns unless `ctx.owner == side`, then checks `traps_of(side)`.
   - Talent grand rituals: register `h.on_grand_ritual.bind(ritual, side)` for each talent owner. Task 090 makes the CombatSetup loop iterate both sides' talents; the handler applies the same filter and reads `traps_of(side)`.
   - Grand Ritual: Chaos: task 090 registers it per talent owner with a side filter. Its body uses `traps_of(ctx.owner)`, `_friendly_board(ctx.owner)`, `_opponent_board(ctx.owner)` and `_remove_rune_aura(rune, ctx.owner)`, and fires ON_RITUAL_FIRED with `ctx.owner`. Rune removal goes through task 050's `remove_trap`. Task 098 later moves the handler into KorrathModule.
   - Rune Warden: walk `_friendly_board(ctx.owner)`. If task 089 has landed, its `on_friendly_rune_placed_aura_steps` dispatcher already does.
3. **`_fire_ritual(owner, ritual)`.**
   - Consume from `traps_of(owner)`, removing through task 050's `remove_trap(owner, trap)`.
   - Journal RITUAL_FIRED and the trap display with `owner`.
   - Run the steps with `EffectContext.make(self, owner)` and fire ON_RITUAL_FIRED with `owner`.
   - Count rituals per side, and keep `_player_ritual_count` reading the player's count so the `PRit` column doesn't move.
4. **Environment rituals per side.**
   - Move the handler list onto task 084's `SideState`, with `_register_env_rituals(side, env)` / `_unregister_env_rituals(side)`.
   - `cmd_play_environment` registers, unregisters and fires ON_RITUAL_ENVIRONMENT_PLAYED (with `side`) for either side.
   - Task 050's `destroy_environment(side)` unregisters for any side. The F15 phase clear (PhaseTransition, routed by task 050) unregisters both.
5. **ON_RITUAL_FIRED listeners** read the owner from `ctx.owner` (Ritual Surge, task 055), and task 090 registers them per talent owner.
6. **Presentation.** `_capture_ritual_visual` takes the event's side and reads `trap_slot_panels` or `enemy_trap_slot_panels`.
7. **Docs.** Fix Enums.gd:97-99, TrapCardData.gd:25, CombatState.gd:849-852 and :2703, and the ritual lines in ARCHITECTURE.md if any.

## Verification

- New probes in `debug/tests/TriggerHandlerTests.gd`:
  - Event side: register a probe handler on ON_RUNE_PLACED. On the enemy's turn, `cmd_play_trap("enemy", <dominion_rune instance>)` fires it once with `ctx.owner == "enemy"`.
  - Player listeners ignore enemy runes: a friendly `rune_warden` on board, the enemy places a rune; the Warden's ATK is unchanged. A player rune placement still gives it +200.
  - Enemy environment ritual: on the enemy's turn, `cmd_play_environment("enemy", abyssal_summoning_circle)`, then the enemy places `blood_rune` and `dominion_rune`. Demon Ascendant fires for the enemy:
    - both enemy runes leave `traps_of("enemy")`;
    - RITUAL_FIRED is journaled with side "enemy";
    - a 500/500 `void_demon` lands on the enemy board;
    - the 200-damage hits land on player minions;
    - the player's traps are untouched.
  - Replacing the enemy's environment unregisters only the enemy's ritual handlers; a player environment ritual still fires afterwards.
  - Grand Ritual: Chaos on a Korrath player: the enemy reaching 3 runes does not trigger it, and the player's own third rune still does (the existing probe, TriggerHandlerTests.gd:2985-3000).
  - Ritual Surge (TriggerHandlerTests.gd:807-815) passes.
- BalanceSimBatch has no Korrath preset and Parity's F6 Korrath case runs only `iron_formation` / `commanders_reach`, so the fingerprint says nothing about the Korrath paths this task touches (Grand Ritual: Chaos and Korrath's random rune). Compare seeded `CombatSim.run` digests for them as task 098's verification describes.
- `debug/tests/snapshots/handler_order.txt`: update on purpose only if a static registration changes (Rune Warden's, if task 089 hasn't moved it). The snapshot doesn't cover the dynamic ritual registrations, so the probes above do.
- `tools/run_checks.sh` green.
- Behaviour change (expected empty): record the BalanceSimBatch delta in the task summary. Run `BalanceSimBatch -- --act 1 --runs 200 --seed 7` and `-- --act 2 --runs 200 --seed 7` before and after (f2_c, f4_b, f5_a place enemy runes). Also request `--act 3` and `--act 4`. Every row, including the `PRit` column, should be identical; a difference means a listener reacts to enemy runes.

## Related

- Depends on: task 084 (roadmap A2) — `SideState` part 2 holds traps and environment, and the per-side ritual handler list goes with them.
- Depends on: task 050 — `remove_trap` / `destroy_environment`, which `_fire_ritual`, Grand Ritual: Chaos and environment replacement must use.
- Depends on: task 090 (roadmap PS-talents) — talent-owned listeners (grand rituals, Chaos, Ritual Surge) are registered per owner with a side filter. Without it, a player talent can't ignore an enemy rune. (Added by the writer of this task; the plan listed only 084 and 050.)
- Related: task 089 (roadmap A8) — Rune Warden's dispatcher. Task 091 (roadmap PS-relics) — Oblivion Seal's placement. Task 098 (roadmap B4) — Korrath's random rune and Chaos.
- Related: task 055 — Ritual Surge's `ctx.owner`. Task 049 — the ritual lambdas are cycle holders; bound method callables remove them.
- Related: task 070 (roadmap E1a) — rune placement VFX and trap panels from the journal, on the same panels the ritual VFX captures.
- Related: task 064 — the per-side rune aura multiplier.
- Related: task 086 (roadmap A3) — turns ON_RUNE_PLACED / ON_RITUAL_* into side-neutral kinds later.
- Related: task 082 (roadmap A0) — row 10 of its table points here.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from owner decision Q2 (the ritual half of the A-paths unit's A3b; the trap half is task 086). Added the dependency on task 090 for owner-aware talent listeners.

## Summary

_(filled in at /task-done)_
