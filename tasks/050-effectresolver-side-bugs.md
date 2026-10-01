---
id: "050"
title: Route trap / environment removal through one engine API (F15 leak, unjournaled destroy, owner lookup)
status: backlog
area: combat
priority: high
started:
finished:
---

## Description

Found in the 2026-09-25 architecture review (issue 4 of 9). Re-verified 2026-09-30 at `3009a60`. Line numbers are from that commit.

This breaks invariant #3 (symmetric effects) and the journal rule (the screen shows only what's journaled).

Removing a trap or an environment is copied inline instead of going through one API:
- **8 trap sites:** EffectResolver :420-424 and :608-612; CombatState `_fire_ritual` :885-889, `_korrath_place_random_rune` :1896-1897 and `_fire_traps_for` :1050-1051; CombatHandlers Grand Ritual Chaos :330-333 and enemy ritual sacrifice :1262-1266; PhaseTransition :92-93.
- **3 environment sites:** EffectResolver :410-414 and :613-616; PhaseTransition :90-91.

Doing a removal correctly takes four things:
1. remove it from the side's array or field;
2. remove the rune aura, or run the environment's `on_replace_effect_steps`;
3. unregister rituals (player side only);
4. journal the change.

Most copies skip at least one.

### Reachable today

1. **The F15 phase change leaks rune and ritual handlers.**
   - `PhaseTransition._clear_combat_state` (:88-93) nulls both environments and clears both trap arrays directly.
   - It doesn't call `_remove_rune_aura` or `_unregister_env_rituals`, and journals neither TRAPS_CHANGED nor ENVIRONMENT_CHANGED.
   - Rune closures don't check that the rune is still on the board (CombatState.gd:788-795), so the player's Void / Blood / Dominion rune effects keep firing in phase 2.
   - `on_env_ritual` (CombatHandlers.gd:693) doesn't check for an environment, so rituals can still fire.
   - The presenter's PHASE_TRANSITION playback (CombatPresenter.gd:240) only refreshes the enemy hero panel, so the live trap and environment panels go stale.
2. **Destroying an environment isn't journaled.**
   - Cyclone and Hurricane call `_update_environment_display()`, which only emits the `environment_changed` signal, and nothing connects to that signal.
   - The environment panel updates only on the ENVIRONMENT_CHANGED journal event (CombatPresenter :708).
   - So the live screen keeps showing the destroyed environment.
3. **Destroy skips the environment's removal steps.** Neither EffectResolver branch calls `_unregister_env_aura` (:384), which runs `on_replace_effect_steps`. Dark Covenant's `dark_covenant_remove` (CardDatabase.gd:1910) therefore never runs, and its buffs stay on minions for the rest of the fight.
4. **The owner is found by object identity.**
   - Traps and environments are shared CardData objects: `get_card_for_combat` returns the base object when no override applies.
   - The trap DESTROY branch (:602-612) checks `target in traps_of(ctx.owner)` first. So if the player Cyclones the enemy's rune while holding the same rune, the player's own copy is destroyed.
   - `_encode_target` (CombatState.gd:3131-3137) has the same ambiguity.
   - Enemy runes exist in f2_c, f4_b and f5_a (dominion, blood, shadow). This is reachable whenever the player holds the same rune id. Confirm it with the probe below.
5. **Possible stale trap panel:**
   - Grand Ritual Chaos emits the `traps_changed` signal instead of journaling (CombatHandlers:333).
   - `_korrath_place_random_rune` journals no TRAPS_CHANGED.

   Confirm whether the panel goes stale.

### Latent (no enemy content owns an environment or a Flesh Rune today)

- The DESTROY environment branch (:613-616) clears the player's environment, whoever was targeted.
- The ACTIVE_ENVIRONMENT step (:408-414), used only by Hurricane (CardDatabase.gd:1894), clears only `active_environment`. Hurricane's text is "Destroy all Traps and the active Environment on the battlefield, including your own". ALL_TRAPS already covers both sides; the environment step should too.
- The SOURCE_RUNE step (:415-425, Flesh Rune upkeep failure) checks only `active_traps`. `ctx.owner` is already the rune's owner (`_apply_rune_aura` builds the ctx with it, :788-793), so the fix is `traps_of(ctx.owner)`.
- `_unregister_env_rituals()` (:389) clears one global array. Rituals are player-only (`cmd_play_environment` :2736-2743), so any per-side API must call it only for the player side.

### What already exists

- `traps_of(side)`, `environment_of(side)` and `set_environment(side, env)` (CombatState.gd:1422-1430).
- `set_environment` journals ENVIRONMENT_CHANGED but doesn't unregister rituals or run on_replace steps.
- Missing: `remove_trap`, `destroy_environment`, `place_trap`.

## Proposed fix

1. **Engine API on CombatState:**
   - `remove_trap(side, t)`: erase it, call `_remove_rune_aura` if it is a rune, and journal TRAPS_CHANGED.
   - `destroy_environment(side)`: run `_unregister_env_aura` (the on_replace steps), call `_unregister_env_rituals()` if `side == "player"`, then `set_environment(side, null)`, which journals.
   - Optional `place_trap(side, t)`: placement is copied in `cmd_play_trap`, RelicEffects :120-138 and Korrath.
2. **Targets carry their side.** A chosen trap or environment target becomes a (side, slot) pair, or a ctx field set by the input handler, the AI and `_encode_target`. DESTROY reads it instead of testing `in traps_of(...)`.
3. **Route every site listed above through the API.**
   - SOURCE_RUNE uses `ctx.owner`.
   - ACTIVE_ENVIRONMENT (Hurricane) clears both sides.
4. **PhaseTransition** goes through the API, but keeps the current order: the boards are wiped before the clear, so `_remove_rune_aura` grants no Korrath runic_absorption stacks. Alternatively, add a "banish" flag that skips on-remove rewards.
5. **Lint L13** (051 takes L12): no `active_traps` / `enemy_active_traps` `.erase` / `.clear` / `.remove_at`, and no `active_environment =` / `enemy_active_environment =`, outside CombatState's API.
   - Exempt `debug/tests`, which seeds these fields (CommandTests:392, CardEffectTests:259, TriggerHandlerTests:2901-2932).
   - The rule can't see local aliases (`live_traps.remove_at`, `traps.erase`), so route those sites by hand.

## Verification

New probes in CardEffectTests / TriggerHandlerTests. None exist today for Cyclone, Hurricane, Void Wind, Dark Covenant, Flesh Rune or PhaseTransition.
- The player Cyclones their own environment: the journal has ENVIRONMENT_CHANGED with `env = null`, and the Dark Covenant buffs are removed.
- The player Cyclones the enemy's rune while holding the same rune: the enemy's copy is the one destroyed.
- Hurricane clears both sides' traps and environments.
- An enemy-owned Flesh Rune fails its upkeep and removes itself. Set it up by seeding the fields and calling `_apply_rune_aura(r, "enemy")`.
- F15:
  - Setup: set `enemy_profile_id = "abyss_sovereign"` and `_sovereign_phase = 1`, then call `PhaseTransition.attempt(state)`.
  - Expect: `_rune_aura_handlers` and `_env_ritual_handlers` are empty, and TRAPS_CHANGED / ENVIRONMENT_CHANGED are journaled.
- `tools/run_checks.sh` green.
- Balance: Acts 1–2 should be unchanged. F15 may shift, because player runes stop firing in phase 2. Record the shift.

## Related

- Roadmap A2 (`SideState`) extends this API.
- Roadmap Q3 (accept balance shifts when enemy-side triggers start firing).

## Work log

- 2026-09-25: opened from the architecture review. Verified :410-425 and :612-616 read and write the player-side fields.
- 2026-09-30: re-verified at `3009a60`, rewritten and retitled.
  - The three originally listed bugs are latent: no enemy content owns an environment or a Flesh Rune.
  - Added the reachable ones: the F15 rune/ritual leak, unjournaled environment destroy, skipped Dark Covenant removal, and owner lookup by shared object.
  - `environment_of` / `set_environment` already exist; the task now extends them.
  - Hurricane clears both sides.
  - Site count corrected to 8 trap and 3 environment sites (was "about 6").
  - The lint rule is L13, not an L8 extension.
