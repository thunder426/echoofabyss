---
id: "142"
title: VFX wiring: one table per dispatch, typed CombatScene handles, delete the scene forwarders
status: backlog
area: tooling
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item J6 (`design/refactors/ARCHITECTURE_ROADMAP.md` §J). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Nothing is broken today: every emitted VFX name has a handler, and the two token-summon lists agree. The problem is that every link in the chain is a string or an untyped handle, so a rename or a drift fails only at runtime.

### String-keyed VFX dispatch

- **One rules VFX passes through 4–5 hops.** Example:
  1. HardcodedEffects.gd:103 emits `{name = "grafted_butcher", …}`;
  2. the `"grafted_butcher":` arm of `CombatPresenter._play_vfx` (:592-652) handles it;
  3. it calls the scene forwarder `_play_grafted_butcher_vfx` (CombatScene.gd:1222);
  4. that calls `vfx_bridge.play_grafted_butcher_vfx`;
  5. which plays the `*VFX.gd`.

  Four arms call the bridge directly (lifedrain_pulse, pack_chain, pack_instinct, ritual_sacrifice).
- **Today it's in sync.** The match has 14 names, not the 16 the roadmap says. The 15 emit sites (HardcodedEffects 6, CombatHandlers 9) use exactly those 14. An unknown name would fall into `_: pass` (:651) silently.
- **Spell VFX are called by method-name string.** VfxController.gd:21-27 `const _SPELL_DISPATCH := {"arcane_strike": "_play_arcane_strike", …}` (5 entries), dispatched at :63-64 `await call(_SPELL_DISPATCH[spell_id], caster_side, target, resolve_damage)`. A renamed method fails only when the spell is cast.
- **Token summons keep two copies of the same ids.**
  - `CardVfxRegistry.has_token_summon` (CardVfxRegistry.gd:46-47, `return card_id in ["void_spark", "void_demon", "brood_imp"]`) duplicates `play_token_summon`'s match (:55-61).
  - The presenter freezes the slot and awaits the animation that reveals it (CombatPresenter.gd:323-326, `node.freeze_visuals = true` … `await CardVfxRegistry.play_token_summon(...)`). An id in the list with no match arm leaves the slot frozen.
- **Dead code.**
  - `CardVfxRegistry.try_play_token_summon` (:63-77) has no callers; only its own header usage comment (:12) and a doc comment (:44) mention it.
  - `CombatVFXBridge._dmg_color` (:719-720) is unused; callers use `_dmg_colors` (:703).
  - `play_demon_ascendant_tail_for` (:507) is task 048's to delete.

### Untyped scene handles

- CombatScene.gd:8 is `extends Node2D` with no `class_name`.
- 16 helpers hold the scene as `Node`, `Node2D` or `Object`, and FeralReinforcementVFX.gd:40 holds `_scene_ref: Node`. Examples: CombatInputHandler.gd:24 `var _scene: Node = null`, CombatPresenter.gd:25 `var scene: Node = null`, SerisResourceBar.gd:22 `var _scene: Object = null`, VfxController.gd:31 `var _combat: Node2D = null`. The 16: CombatInputHandler, CombatPresenter, CombatUI, Targeting, TrapEnvDisplay, LargePreview, CounterWarning, CombatUiStyle, PipBar, PlayerHeroPanel, EnemyHeroPanel, SerisResourceBar, CheatPanel, CombatVFXBridge, VfxController, EnemyTurnRunner.
- So the compiler never checks `_scene.x`. Lint L11 (lint_engine.py:377-392) only checks by regex that the name exists.
- About 275 accesses to underscore-private scene members sit outside debug/tests: CombatInputHandler 103, CombatPresenter 66, CombatUI 37, CombatVFXBridge 33, Targeting 21. The most used are `_find_slot_for` (29), `_enemy_hero_panel` (24) and `_pip_bar` (20).
- ARCHITECTURE.md:96 says "The UI helpers hold `_scene: CombatScene`", which is wrong.

### Forwarders

- CombatScene.gd (1,922 lines, 129 funcs) has 62 one-to-three-line functions that only forward to a helper, e.g. :1222 `_play_grafted_butcher_vfx`. `_input` (:1210) is among them and must stay.
- Many are signal targets connected in the scene, e.g. :337 `player_slots[i].slot_clicked_empty.connect(_on_player_slot_clicked_empty)`, :356 `hand_display.card_selected.connect(_on_hand_card_selected)`, :367, :1133.
- ParityTests drives some of them directly (:233 `scene._on_hand_card_selected(inst)`, :236, …).

### Consequence

- A renamed bridge or VFX method, or drift between a list and its match, fails at runtime as a frozen slot, a silently skipped VFX, or an "Invalid call".
- Every new card VFX touches 4–5 files.
- The forwarders double the surface that tasks 109, 110 and 115 (roadmap E2, E3, F2) have to change.

### Scope

- **Card ids in the VFX registries.** Checking them against CardDatabase is task 104's (roadmap D1, lint L14).
- **Unknown VFX names.** The runtime warning is task 116's (roadmap F3).
- **No new lint number.** The roadmap's "registry checked at load" becomes a test probe (phase b), not a new rule; L20 is already taken provisionally by task 131.

## Proposed fix

Four phases, listed below; phase d is deferred.

## Phases

Each phase is independently shippable and gated on its own run. Open a sub-task per phase when starting, as LIVE_SIM_UNIFICATION_PLAN did.

### Phase a (S): dead code and one token-summon table

1. Delete `CardVfxRegistry.try_play_token_summon` (:63-77), and fix the header usage block (:10-17) and the doc comment at :40-45.
2. Delete `CombatVFXBridge._dmg_color` (:719-720).
3. **One lookup for token summons.** Replace `has_token_summon` and `play_token_summon` with `static func token_summon_for(bridge: CombatVFXBridge, card_id: String) -> Callable`.
   - It returns the bridge method as a typed Callable (`bridge.summon_spark_with_sigil`, `bridge.summon_demon_with_sigil`, `bridge.summon_brood_imp_with_sigil`), or an invalid Callable.
   - The presenter (:323-326) freezes the slot only when the Callable is valid, then awaits `play.call(m, card, node, ev.side)`.
   - One table, so the list can't drift from the match.

### Phase b (M): Callable tables instead of string dispatch

4. **Presenter.** Turn `_play_vfx`'s match into `_vfx_handlers: Dictionary` (name → Callable on presenter methods `_vfx_grafted_butcher(ev)`, …).
   - Build it in `_init()`, so it needs no scene and the compiler checks every method name.
   - `_play_vfx` looks the name up and awaits the handler. Task 116 adds the warning for a missing key.
   - Expose `vfx_names() -> Array[String]`.
5. **VfxController.** Replace `_SPELL_DISPATCH` with a table of method references (`{"arcane_strike": _play_arcane_strike, …}`) built in `_init()`, and drop `call(String)`. Task 115 changes `play_spell`'s signature; rebase on whichever lands first.
6. **Coverage probe** in ContentTests (task 104) if it has landed, otherwise CommandTests:
   - instantiate `CombatPresenter.new()`, read `vfx_names()`, then free it;
   - read every `.gd` under `res://combat` and `res://relics` with FileAccess and collect the literal `name = "x"` of each `CombatEvent.Kind.VFX` emit;
   - assert the two sets are equal: no emitted name without a handler, no handler nothing emits.

### Phase c (M): typed handles, no forwarders

7. **Type the handles.**
   - Add `class_name CombatScene` to CombatScene.gd, and type the 16 helper handles plus FeralReinforcementVFX's `_scene_ref` as `CombatScene`.
   - `load_all_scripts` then compile-checks the names L11 checks by regex. Keep L11 for debug/tests, whose handles stay untyped, or type those too.
   - Check that the cyclic class references (the scene creates the helpers, the helpers name the scene) compile in Godot 4.6.
8. **Delete the forwarders**, except `_input`.
   - Connect the HandDisplay, BoardSlot, trap-panel and relic-bar signals straight to `input_handler` methods.
   - Callers use `scene.vfx_bridge.*`, `scene.targeting.*` and so on directly.
9. **Parity input.** ParityTests (:228-276) emits the nodes' signals instead of calling forwarders (`scene.hand_display.card_selected.emit(inst)`, `slot.slot_clicked_empty.emit(slot)`), so it still enters through the real input path.
10. **Docs.** Fix ARCHITECTURE.md:96 and the scene / sub-system tables, and the CardVfxRegistry and VfxController header comments.

### Phase d (deferred): public names

11. Give the most-used private scene members (`_find_slot_for`, `_enemy_hero_panel`, `_pip_bar`, …) public names, opportunistically or with task 099 (roadmap B7). Once the handles are typed the compiler checks these accesses, so this is cosmetic.

## Verification

- **Every phase:** `tools/run_checks.sh` green, including LiveSmoke's animated scenarios and task 048's animated full fight.
- **Phase b:** the coverage probe fails when one name is removed from the table, and when an emit is renamed (temporary local edits, recorded in the summary, then reverted).
- **Phase c:**
  - `load_all_scripts` compiles with the typed handles;
  - L11 stays at 0;
  - `lint_engine.py --report-pairs` still reports 0;
  - Parity green through the signal-driven input path.
- **Manual pass in TestLaunchScene, after phases a and b:** the 14 VFX names, the 3 token summons and the 5 spell VFX all play, and every summoned slot unfreezes.
- Behaviour-neutral: presentation only. No rules, AI or sim code changes and the sim never loads CombatScene, so the balance fingerprint can't move; no BalanceSimBatch run needed.

## Related

- Depends on: task 048 — edits the same presenter and bridge waits, deletes `play_demon_ascendant_tail_for`, and adds the animated full fight this task relies on.
- Related: task 116 (roadmap F3) — the unknown-VFX warning becomes the missing-key branch of phase b's table.
- Related: task 104 (roadmap D1) — the card-id check for the VFX registries. After phases a and b the ids are Dictionary keys, not `match` arms; L14's card-id positions must cover them.
- Related: task 115 (roadmap F2) — changes `VfxController.play_spell`'s signature.
- Related: tasks 109 and 110 (roadmap E2, E3) — presenter and BoardSlot changes; fewer forwarders to route through.
- Related: task 111 (roadmap E4, L17) — counts engine reads in UI files; typed handles make them visible to the compiler too.
- Related: task 099 (roadmap B7) — public engine API; phase d pairs with it.
- Related: task 127 (roadmap H6) — splits EnemyHeroPanel, one of the 16 typed handles.
- Related: task 053 — CheatPanel is one of the typed handles; `_apply_test_config` leaves the scene.
- Related: task 140 (roadmap J4) — brings CombatScene and the VFX registries into lint L8 / L10.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item J6. Re-checked at `404b51c`:
  - corrected the VFX name count (14, not 16);
  - re-counted 62 forwarders and about 275 private scene accesses;
  - excluded the card-id check (task 104), the unknown-name warning (task 116) and the demon-ascendant loop (task 048);
  - the name-coverage check is a test probe, not a new lint number.

## Summary

_(filled in at /task-done)_
