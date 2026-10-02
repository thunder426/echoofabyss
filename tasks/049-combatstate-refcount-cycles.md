---
id: "049"
title: Break CombatState reference cycles so each fight is freed
status: done
area: combat
priority: high
started: 2026-10-02
finished: 2026-10-02
---

## Description

Found in the 2026-09-25 architecture review (issue 3 of 9). Re-verified 2026-09-30 at `3009a60`. Line numbers are from that commit.

How Godot 4 frees RefCounted objects:
- By reference count only; there is no cycle collector.
- A typed field holding an object is a strong reference.
- A lambda keeps its captured locals alive, and keeps `self` alive if it uses it.
- Plain method callables (`h.on_x`, `Callable(obj, "m")`, `.bind(...)`) hold only an ObjectID, so they form no cycle.

### Cycles through `CombatState`

| Holder → state | Where |
|---|---|
| `combat_manager` (CombatManager) | Created at CombatState.gd:2349; back-ref assigned directly at :2350; field at CombatManager.gd:54 |
| `_hardcoded` (HardcodedEffects) | Created at :2354, `setup(self)` at :2355; field at HardcodedEffects.gd:19 |
| `_handlers` (CombatHandlers) | Created at CombatSetup.gd:524; field at CombatHandlers.gd:14 |
| `relic_effects` (RelicEffects) | Created lazily in `_cmd_activate_relic` (:2827, :2853) when a relic other than `relic_execute` is used; field at RelicEffects.gd:8 |
| Trigger lambdas capturing `h` / `self` | CombatSetup.gd:630, :632; CombatState.gd:376, :788, :805 |
| The same lambdas in `_env_ritual_handlers` (:1620) and `_rune_aura_handlers` (:1625) | So `trigger_manager.clear()` alone doesn't break them |
| **CombatSim lambdas, in every sim fight** | In `_build`: `growth_hooks["player"/"enemy"]` capture `state` and the profiles (→ agent → `StateAgent._state`) (CombatSim.gd:81-84). `enemy_profile_changed` connects to a lambda capturing `e_agent` and `enemy` (:76). With a snapshot callback, `run` adds a `turn_ended` lambda capturing `state` (:216). |
| `diagnostics` ↔ `CombatDiagnostics._state` | CombatState :1972, CombatDiagnostics.gd:17. Only with `dmg_log` / `debug` (DebugSingleSim, VoidboltDmgDebug); BalanceSimBatch doesn't attach diagnostics. |
| Test lambdas | `growth_hooks` (ParityTests.gd:131, LiveSmokeTests.gd:213); `command_recorded` (ParityTests :100-103, :121). CommandTests and DamageTypeTests register lambdas on the trigger manager. |

These are **not** cycles:
- MinionInstance (its `state` field is an enum), SlotState, HeroState, CardInstance, CombatEvent payloads, RelicRuntime, ViewState;
- EnemyTurnRunner (owned by a Node), and the scene's Nodes and their lambdas;
- `journal`, `command_log` and the boards. They hold no reference back to the state, so they are freed with it once the cycles are broken.

### teardown() and the drivers

`teardown()` (:2391-2397) only disconnects from the `BuffSystem` bus and resets the two `MinionInstance` statics. It nulls nothing. So every CombatState leaks, along with its journal, boards and decks, and BalanceSimBatch runs thousands of fights.

The drivers already call `teardown()`:
- `CombatSim.replay` (:111)
- `CombatScene._exit_tree` (:771-772)
- `CombatSim.run` (:298), but **before** it builds its result: :299-350 still read `player_board`, `_vw_*`, `diagnostics.dmg_log` and `relic_runtime`. That's harmless today and breaks once teardown nulls things.

### Tests

- There are 218 `build_state(` call sites. TriggerHandlerTests (187) and CommandTests (30) call `teardown()`. CardEffectTests calls it once (:448), and DamageTypeTests never does.
- **Bus cross-talk.** A state that skips teardown stays connected to the `BuffSystem` bus. Every later `corruption_removed` reaches `_on_corruption_removed_bus` (:2374) on each stale state, which fires its own trigger manager with a foreign minion.
- **The statics** don't carry over between tests: `CombatSetup.gd:609-610` sets them on every build. The real hazard is that tearing down one state resets the flags of any other state that is still alive.

## Proposed fix

1. **Rewrite `teardown()`** so it is idempotent, with null guards everywhere (tests already call it, and auto-teardown would call it again). It should:
   - disconnect the bus and reset the statics, as it does now;
   - null each helper's `state`, and the state's `combat_manager`, `_hardcoded`, `_handlers` and `relic_effects`;
   - call `trigger_manager.clear()`, and clear `_env_ritual_handlers`, `_rune_aura_handlers` and `growth_hooks`;
   - null `diagnostics._state` and `diagnostics`;
   - disconnect every connection on the state's own signals (loop `get_signal_list()` → `get_signal_connection_list()`), which drops the CombatSim and test lambdas.

   **Don't** clear `journal`, `command_log` or the boards. It isn't needed, and ParityTests.gd:160 reads `eng_state[0].journal` after `sim.run` has torn down.
2. **`CombatSim.run`:** build the result into a local `out`, then call `teardown()`, then return `out`.
3. **TestHarness auto-teardown.**
   - Track every state `build_state` creates.
   - Tear them down at the end of each test, never lazily at the next `begin_test`: doing it later would reset the statics the new state has just set.
   - Some tests build states after `begin_test(label, null)` (CardEffectTests.gd:436), so tracking can't rely on `begin_test`.
4. **Optional: weakref back-refs** through a property getter: `var state: CombatState: get: return _state_ref.get_ref()`, plus a setter so `combat_manager.state = self` keeps working. This needs no call-site changes. But it covers only the four helpers, not the lambdas in containers, and adds a `get_ref()` on the hottest sim path. Treat it as extra insurance, not a replacement for step 1.
5. **Docs:** ARCHITECTURE.md:74 says `teardown()` only drops the bus subscription.

## Verification

- **Leak probe** (TestHarness layer):
  - Build a state that exercises every cycle: place a rune, play an environment with rituals, take a grand-ritual talent, activate a non-execute relic.
  - Take `weakref()` of the state, `_handlers`, `combat_manager`, `_hardcoded` and `trigger_manager`.
  - Call `teardown()`, drop the local, and assert every `get_ref() == null`. RefCounted objects free immediately, so no frame wait is needed.
  - Don't pass the state to `begin_test`: `TestHarness._current_state` (static, :25) would keep it alive.
- **Sim probe:** a `state_observer` that stores only `weakref(st)`. After `await sim.run(...)` it resolves to null. This covers the `_build` lambdas.
- **BalanceSimBatch memory stays flat** across a matrix run. Measure with `OS.get_static_memory_usage()`, or with `Performance.OBJECT_COUNT` and a tolerance after warm-up. OBJECT_COUNT is noisy because `CardDatabase.clear_override_cache()` runs on every setup.
- `tools/run_checks.sh` green; Parity digests unchanged.

## Related

- Roadmap I (engine robustness) and J (test isolation) build on this.
- Roadmap G's "should the AI look ahead" decision lists 049 as a prerequisite.

## Work log

- 2026-09-25: opened from the architecture review. Verified all four back-refs and that `teardown()` doesn't clear them.
- 2026-09-30: re-verified at `3009a60` and rewritten.
  - Added the cycles the first version missed: the CombatSim, test and diagnostics lambdas, and the handler arrays. The four-helper fix alone would still leak every sim fight.
  - The drivers already call teardown, but `CombatSim.run` calls it before building its result.
  - Dropped clearing `journal` / `command_log`.
  - Corrected the test counts and the claim about the statics.
  - Weakref demoted to optional.
- 2026-10-02: pulled forward into P1. A seeded `BalanceSimBatch -- --act 2 --runs 200 --seed 7` reached a 19 GB footprint in 87 s, and four acts in parallel ran the 16 GB dev Mac out of memory, so the plan's full-size fingerprints couldn't run until this landed. Owner: "find why it leaks and fix it".
  - Probes first (CommandTests `lifecycle /`): both failed before the fix (state + all five helpers alive after teardown; every sim fight alive after `run`).
  - Fix: steps 1–3 and 5 as proposed. Step 4 (weakref back-refs) skipped. Added `MinionInstance.flags_owner_id` so a late teardown of an older state can't clear a newer fight's flags, which is what makes harness auto-teardown safe.
  - Harness: `_teardown_finished` at each `begin_test` tears down states built before the previous `begin_test` (a test builds its state just before or just after its `begin_test`), never the state passed in; `teardown_all` at the end of RunAllTests. Tracked by weakref.
  - Test gotcha: a lambda built inside the probe function keeps its capture alive until the function returns (VM stack temporaries), so the probe builds its driver lambdas in a helper, as CombatSim.`_build` does.
  - Results: BalanceSimBatch peak footprint 77–78 MB per act (Act 4: 349 s); RunAllTests' "15 resources still in use at exit" error is gone. Gate green: lint 0, 197 scripts, 1117 tests, LiveSmoke OK (same seeded fight: enemy wins, turn 8, 551 events), Parity 24/24.
  - Fingerprint (`--runs 200 --seed 7`) vs `989a9cd`: Act 1 byte-identical except the `Clog:` extra on the nine S.Corr rows, which drops below the 0.1 print threshold. Cause: `run` used to call `teardown()` before building its result, so `_count_clogged_slots` ran after the Corrupt Flesh flag was reset and counted corrupted friendly Demons as 0 ATK. Proof: the old code with the count moved before teardown matches the new output exactly. Acts 2–4: every row the cut-off old runs completed matches (57 / 79 / 90 rows), Clog included.
- 2026-10-02: closed.
