---
id: "130"
title: Per-state talent flags and a per-state corruption-removed channel (no MinionInstance statics, no global bus subscription)
status: backlog
area: combat
priority: high
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item I2 (`design/refactors/ARCHITECTURE_ROADMAP.md` §I). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Two pieces of combat state are process-wide instead of per fight.

### 1. Talent flags are statics on MinionInstance

- MinionInstance.gd:14 `static var corruption_inverts_on_friendly_demons: bool = false` (Seris Corrupt Flesh) and :19 `static var iron_resolve_active: bool = false` (Korrath Iron Resolve). The comment at :10-13 says it is static "so effective_atk() can read it without a scene reference".
- Every `CombatSetup.setup` overwrites them from *its own* state's talents (CombatSetup.gd:609-610):
  ```gdscript
  MinionInstance.corruption_inverts_on_friendly_demons = "corrupt_flesh" in talents
  MinionInstance.iron_resolve_active = "iron_resolve" in talents
  ```
- Every `teardown()` resets both to false, whichever state owns them (CombatState.gd:2396-2397).
- Readers: `effective_atk` (MinionInstance.gd:140-149) and `BoardSlot.flash_atk_debuff` (BoardSlot.gd:894). Both are hard-gated to `owner == "player"`.

### 2. The corruption-removed channel is a global bus

- BuffSystem.gd:40 `static var _bus: Object`. `_emit_corruption_removed` (:64-67) emits `corruption_removed` on it for any target.
- Each state connects its own `_on_corruption_removed_bus` to that one bus (CombatSetup.gd:535-541).
- `_on_corruption_removed_bus` (CombatState.gd:2372-2387) has no ownership check:
  - for a HeroState target it journals HERO_BUFF_CHANGED into its own journal (:2375-2379);
  - for a minion it fires ON_CORRUPTION_REMOVED on its own TriggerManager and journals MINION_STATS_CHANGED (:2383-2387).

### What goes wrong with two live states

- **Building** a second state switches off the first state's Corrupt Flesh / Iron Resolve whenever the second lacks the talent, because setup overwrites the statics.
- **Tearing down** any state switches them off for every other state.
- **A corruption removal in one state reaches all connected states.** Each one fires its own ON_CORRUPTION_REMOVED with the foreign minion. With Seris's Corrupt Detonation (CombatHandlers.gd:884-905) that means `rng_pick` on its own enemy board, real damage there and a LOG line, all in the wrong fight.
- **Both flags are player-only.** An enemy or PvP opponent with these talents gets nothing. That contradicts Q2.

### Reachable today?

- Two states are alive at once only in tests that skip `teardown()`, which task 049 fixes.
- Live play has one state. Parity runs the engine fight to completion (`CombatSim.run` tears down) before it builds the live scene (ParityTests.gd:96-123).
- So nothing breaks in a shipped fight today. It becomes reachable with the AI look-ahead the owner confirmed in Q7b. A look-ahead state's build or teardown would turn off the live fight's Corrupt Flesh and Iron Resolve for the rest of the fight. Its corruption removals would fire the live fight's Corrupt Detonation, consume live RNG and journal live events.
- After task 049 the sharing is still there: 049 makes `teardown()` idempotent but still resets the statics and disconnects the global bus.

### Other process-wide state (checked; not in scope)

- `CardInstance._next_id` (shared/scripts/CardInstance.gd:15): unique ids used only for UI identity (HandDisplay.gd:194, CombatPresenter.gd:129-136). Sharing it is harmless.
- `CardDatabase._override_cache` (cards/data/CardDatabase.gd:19): cleared by every `setup_combat` (CombatState.gd:2342). It is keyed by id, side and the relevant overrides / rules (:128), so a clear only costs a rebuild. Note it for the look-ahead fork design.
- `BuffSystem` `buff_applied` and the `SacrificeSystem` bus (SacrificeSystem.gd:18) have no listeners; task 132 (roadmap I4) deletes them.

## Decision (owner, 2026-10-01)

- Q7b: AI look-ahead is planned. Task 049, this task and task 129 (roadmap I1) are prerequisites, so this one is urgent.
- Q2: talents and hero passives must work for either side; who has them is decided by config, never by `owner == "player"` in rules code.

## Proposed fix

1. **Add `combat/board/CombatRules.gd`** (`class_name CombatRules`, RefCounted). It holds no reference to CombatState, so it adds no cycle (049).
   - Per-side flags with typed accessors: `inverts_corruption(side) -> bool`, `iron_resolve(side) -> bool`, and a setter used by setup.
   - `signal corruption_removed(target: Object, stacks: int)`.
   - CombatState gets `var rules: CombatRules`, created in `setup_combat`.
2. **Fill the flags in `CombatSetup.setup`** from each side's talents. Today that is the player's talents only; the enemy's flags stay false until task 090 gives the enemy talents. Delete the static writes at :609-610, the "Reset per-combat globals" comment above them and the registry comment at :142-144.
3. **Give minions and heroes the rules object.**
   - Add `var rules: CombatRules = null` to MinionInstance and HeroState.
   - Set it at the three MinionInstance.create sites in CombatState (:608, :2142, :2579). At :2579 set it before the MINION_PLAYED stat payload (:2581), which reads `effective_atk`.
   - Set it on `player_hero` / `enemy_hero` (:1237-1238) in `setup_combat`.
   - Set it in `TestHarness._spawn`, `_spawn_resolved` and `_spawn_at` (TestHarness.gd:94-150).
   - Backstop: CombatState sets `rules` on each SlotState when it makes the slots (:1315-1318), and `SlotState.place` stamps `m.rules` when the minion has none. That covers tests that create a minion and place it by hand.
4. **`effective_atk` reads per side.** `rules != null and rules.inverts_corruption(owner)` and `rules != null and rules.iron_resolve(owner)` replace the statics and the `owner == "player"` gates (MinionInstance.gd:140-149). Owner changes (Void Unraveling, CombatHandlers.gd:1345) keep working, since the flag is read for the current owner.
5. **Per-state corruption channel.**
   - `BuffSystem._emit_corruption_removed` emits on the target's `rules.corruption_removed` when `rules != null`. Get `rules` by explicit cast to MinionInstance / HeroState, or through `Buffable` if task 134 phase c has landed. No duck typing (L9).
   - Delete the `corruption_removed` user signal from the bus.
   - CombatState connects its own `rules.corruption_removed` to `_on_corruption_removed` (renamed from `_on_corruption_removed_bus`) in setup, replacing the global connect at CombatSetup.gd:535-541. A bound method holds only an ObjectID, so no cycle.
6. **Teardown** (on top of 049's rewrite): drop the bus disconnect and the static resets, and null `rules`.
7. **BoardSlot.gd:894** reads `minion.rules != null and minion.rules.inverts_corruption(minion.owner)` instead of the static and the `"player"` literal.
8. **Delete** both static declarations and their doc comment (MinionInstance.gd:10-19).
9. **Tests:**
   - Delete the static writes at TriggerHandlerTests.gd:408, :422, :441 and :3502-3503; they are no longer needed.
   - `_iron_resolve_does_not_apply_to_enemies_or_demons` (:2495-2506) asserts "player-side only". Reword it to "enemy without the talent". It still holds, since the enemy's flag is false.
10. **Docs:** ARCHITECTURE.md:74 (`teardown()` "drops the BuffSystem bus subscription"), :103 (BuffSystem "Lazy-inits a buff signal bus"), :153 and :162 (CombatSetup "bridges the BuffSystem `corruption_removed` bus"). Say that teardown no longer touches globals.

`BuffSystem.bus()` still holds `buff_applied` until task 132 deletes it. Whichever of the two tasks lands second deletes `bus()` and `_bus`.

## Verification

New probes in `debug/tests/TriggerHandlerTests.gd`:
- **Talent flags are per state.**
  - `a := TestHarness.seris_state(["corrupt_flesh"])`, `fiend := TestHarness.spawn_friendly(a, "grafted_fiend")`, `BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)`. Record `fiend.effective_atk()` (inverted, +100).
  - `b := TestHarness.build_state({})`. Assert the Fiend's ATK is unchanged; today B's setup clears the static and it drops by 200.
  - `b.teardown()`, then assert again.
  - Repeat for Iron Resolve with `TestHarness.korrath_state(["iron_formation", "commanders_reach", "iron_resolve"])` and `_place_korrath_human` with `armour = 300`, as `_iron_resolve_adds_armour_to_human_atk` (:2485-2493) does.
- **The corruption channel is per state.**
  - `a := TestHarness.seris_state(["corrupt_flesh", "corrupt_detonation"])` with `spawn_enemy(a, "rabid_imp")`. Record `a.journal.size()`, `a.enemy_hp` and the imp's HP.
  - `b := TestHarness.build_state({})`, `d := TestHarness.spawn_friendly(b, "grafted_fiend")`, two CORRUPTION applies on `d`, then `BuffSystem.remove_type(d, Enums.BuffType.CORRUPTION)`.
  - Assert A's journal size, enemy HP and imp HP are unchanged (today A's Detonation fires on A's board and journals into A), and that B journaled a MINION_STATS_CHANGED for `d`.
- **Either side.** In `build_state({})`, turn on Corrupt Flesh for `"enemy"` through the `CombatRules` setter, `imp := TestHarness.spawn_enemy(state, "void_imp")` (a Demon), then apply CORRUPTION 100: its ATK goes up by 100. The player's flag stays off. This proves the gate is per side, not `"player"`.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the flags have the same values per fight, now per state, and the enemy's are false. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, Acts 1-4) diffs empty (design/TESTING.md 'Refactor / extraction work'). The `seris_corruption_engine` preset (BalanceSimBatch.gd:79-88, `corrupt_flesh` from Act 1) exercises the inversion.

## Related

- Depends on: task 049 — rewrites `teardown()` and adds TestHarness auto-teardown; doing this after it avoids editing teardown twice.
- Related: task 132 (roadmap I4) — deletes `buff_applied` and the SacrificeSystem bus; together with this task, `BuffSystem.bus()` goes.
- Related: task 090 (per-side talents) — gives the enemy talents; CombatSetup then fills the enemy's flags from them.
- Related: task 097 (roadmap B3) and task 098 (roadmap B4) — the Seris and Korrath modules later own these flags per side; this task gives them a per-state home first.
- Related: task 134 (roadmap I6) — phase c's `Buffable` base is the natural place for `rules`.
- Related: task 110 (roadmap E3) — BoardSlot status visuals from the journal; `flash_atk_debuff`'s inversion read (step 7) is a live engine read it can move onto the payload.
- Related: task 120 (roadmap G4) — the look-ahead evaluation this unblocks.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item I2. Re-checked at `404b51c`. Corrected the roadmap's framing: the statics don't carry between sequential tests (setup rewrites them), but building or tearing down any second live state changes the first, and the bus has no ownership check. Not reachable in a shipped fight today; urgent because of Q7b. Added the per-side requirement (Q2) and the list of other process-wide state checked.

## Summary

_(filled in at /task-done)_
