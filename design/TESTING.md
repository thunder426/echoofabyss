# Testing & Debug Tools

Inventory of every test harness, simulator, and debug tool in the project,
what each one is for, and how to run it.

All commands assume the Godot console binary at the path saved in memory:

```
GODOT="C:\Thunder\work\Projects\Godot\Godot_v4.6.1-stable_win64_console.exe"
PROJECT="C:\Thunder\work\Projects\EchoOfAbyss\echoofabyss"
```

Project-relative paths in the table below are clickable.

---

## Quick reference

| Tool | Purpose | Headless? | Asserts? | Time |
|---|---|---|---|---|
| [tools/run_checks.sh](#run_checkssh--the-refactor-gate) | **The gate**: import → engine lint → compile every script → RunAllTests → LiveSmoke → Parity; fails on any `SCRIPT ERROR` | Yes | Yes | ~90s |
| [Engine lint](#engine-lint--toolslintlint_enginepy) | Static checks: no shell (L1) or presenter (L3) in rules code, global RNG (L2), duck typing (L4 / L9), nothing extends CombatState (L5), the engine never waits (L6), one engine body (L7), presentation never mutates (L8), VFX timer count (L10), scene-handle names resolve (L11) | Yes (Python) | Yes | <1s |
| [LiveSmoke](#livesmoke--headless-combatscene) | Boots the real `CombatScene` headless: an enemy turn, the F13 champion, the live rules paths and a whole AI-vs-AI fight through the presenter | Yes | Yes | ~30s |
| [Parity](#parity--engine-vs-live-scene) | 8 fights × 3 seeds run on the bare engine, then replayed through the live `CombatScene`'s input handlers; state compared after every command | Yes | Yes | ~40s |
| [RunAllTests](#runalltests--layered-test-suite) | Layered correctness tests (4 layers, ~500 assertions) | Yes | Yes | ~10s |
| [BalanceSimBatch](#balancesimbatch--full-balance-matrix) | Full balance matrix across acts/decks/relics | Yes | No (prints stats) | 5–15 min |
| [BalanceSim](#balancesim--interactive-balance-ui) | Editor UI to tweak settings + run sims | No (editor) | No | Interactive |
| [DebugSingleSim](#debugsinglesim--single-fight-with-full-logging) | One F11 sim with full debug logging | Yes | No | <5s |
| [SimRunner](#simrunner--general-cli-sim) | Generic sim CLI for ad-hoc deck/profile combos; `--dump-replay <path>` records a fight | Yes | No | Varies |
| [ReplayRunner](#determinism-and-seeds) | Plays a recorded sim fight back through its command log; reports digest match / first refused command | Yes | Yes (exit code) | <5s |
| [ScoredAITest](#scoredaitest--voidbolt-full-run) | Voidbolt full-run tuning report | Yes | No | ~1 min |
| [DebugF13LossAnalysis](#debugf13lossanalysis--per-turn-loss-diagnosis) | Per-turn snapshots of F13 losses | Yes | No | ~10s |
| [VoidboltDmgDebug](#voidboltdmgdebug--damage-source-trace) | Per-source enemy damage trace, 5 runs | Yes | No | <10s |
| [TestLaunchScene + TestConfig](#testlaunchscene--testconfig--scripted-combat-launcher) | Hand-built combat scenarios in editor | No (editor) | No (manual) | Interactive |
| [EnemyDeckBuilder](#enemydeckbuilder--encounter-deck-editor) | Edit per-encounter deck pools | No (editor) | No | Interactive |

---

## run_checks.sh — the refactor gate

**Path:** [tools/run_checks.sh](../tools/run_checks.sh)

```bash
tools/run_checks.sh            # uses $GODOT, else `godot` on PATH, else /Applications/Godot.app
```

Runs, in order: `godot --headless --import` (refreshes `.godot/global_script_class_cache.cfg`,
which goes stale and makes CombatScene fail to parse), the engine lint,
`tools/lint/load_all_scripts.gd` (compiles every `.gd` — tests only load the
scripts they reach, so a parse error in UI or debug code would otherwise slip
through), `RunAllTests`, `LiveSmoke`, then `Parity`. Exits non-zero on any lint error,
compile failure, test failure, or `SCRIPT ERROR` line in Godot's output (handler
errors don't fail an assertion, they only print — this is how live-only crashes
surface). Each Godot run is killed after `RUN_CHECKS_TIMEOUT` seconds (default
300) so a hung suite fails instead of wedging. Logs land in a temp dir printed
on failure. Introduced by the live/sim unification refactor
([LIVE_SIM_UNIFICATION_PLAN.md](refactors/LIVE_SIM_UNIFICATION_PLAN.md)); every
step of that refactor must leave it green.

## Engine lint — tools/lint/lint_engine.py

| Rule | Fails on |
|---|---|
| L1 | Rules code (`CombatState`, `CombatSetup`, `CombatHandlers`, `HardcodedEffects`, `RelicEffects`, `EffectResolver`, `ConditionResolver`, `TargetResolver`, `EffectContext`, `CombatManager`, `MinionInstance`, `PhaseTransition`) holding a combat shell at all: `_scene`, `ctx.scene`, `_fx` or `scene.` (plan 4.4 — the B1 class of "a name the live shell lacks" can no longer arise). Also: `CombatSetup` registry stat keys must exist on `CombatState`. |
| L2 | Global `randi/randf/shuffle/pick_random` in engine, rules, sim or AI code, and in the enemy deck pick (`EncounterDecks.gd`). Gameplay randomness goes through `state.rng_pick / rng_shuffle / rng_range / rng_index` so a seed reproduces a fight. Opt out per line with `# lint: allow-rng (<reason>)` (only the two seed rolls do). |
| L3 | Presentation from rules code: any `presenter` / `ctx.presenter` in the rules files. Anything the screen must show is a journal event (`state.emit_event`) the presenter plays (plan 4.4). |
| L4 | Duck typing in rules files: `has_method(`, and `.get("x")` / `.set("x", …)` / `"x" in obj` on an object handle. Dictionary `.get("key")` is fine. |
| L5 | Anything that `extends CombatState` — the engine has one body per method (SimState, the last subclass, was deleted in 4.2). `lint_engine.py --report-pairs` separately lists funcs defined on both CombatScene and CombatState (should be 0). |
| L6 | `await`, `get_tree(` or `create_timer(` in `CombatState.gd` — the engine never waits (animations hang off its signals); `BoardSlot` named in `CombatState.gd`, `CombatHandlers.gd`, `EffectResolver.gd` or `TargetResolver.gd` — the engine holds `SlotState`, the node is a view (plan 3.1a). |
| L7 | A second definition, anywhere in the repo, of a state command (`func cmd_*`), the turn engine (`begin_turn` / `end_turn`), trap routing (`_fire_traps_for`), or an AI profile table (a script preloading the `enemies/ai/profiles/` scripts — only `ProfileRegistry` may). |
| L8 | Gameplay mutation in presentation code (`combat/effects/*VFX.gd`, `combat/effects/vfx/*.gd`, `combat/ui/*.gd` except `CheatPanel`, and `BoardSlot` / `CombatPresenter` / `CombatUI` / `CombatInputHandler` / `TrapEnvDisplay` / `LargePreview` / `Targeting` / `CounterWarning`): `BuffSystem.apply*`, `SlotState.place(`, `combat_manager.`, `trigger_manager.fire`, `EffectResolver.run`, `state.<field> =`, board `append` / `erase`, `current_health` writes. Rules code journals an event; the presenter plays it (plan 3.5). |
| L9 | Duck typing anywhere in `combat/board`, `combat/events`, `combat/effects` (VFX files exempt), `relics`, `sim`, `enemies/ai`: `has_method(`, and `.get("x")` / `.set("x", …)` / `"x" in obj` on an object handle. Dictionary `.get("key")` is fine (plan 4.8). |
| L10 | More `await get_tree().create_timer` in `combat/effects/*VFX.gd` than `L10_BASELINE` (20 when the rule landed) — new VFX sequence with `VfxSequence`; lower the baseline as old ones migrate (plan 5.3). |
| L11 | A name reached through an untyped scene handle that doesn't exist: in `combat/`, `relics/` and `debug/tests/`, `_scene.X` / `scene.X` / `_combat.X` / `combat.X` must be declared on `CombatScene` (or be a Node / CanvasItem member) and `<handle>.state.X` on `CombatState`. The compiler never checks these, so a deleted scene helper otherwise fails only when a player clicks — 0.617 deleted `_player_can_afford_sparks` and every spell / minion selection errored live until Phase 5 (plan 5.3). |

## LiveSmoke — headless CombatScene

**Path:** [debug/tests/LiveSmokeTests.gd](../debug/tests/LiveSmokeTests.gd) · **Scene:** `res://debug/tests/LiveSmoke.tscn`

The only test that instantiates the live `CombatScene` (everything else runs on
a bare `CombatState` built by `setup_combat`). Separate process because `RunAllTests` quits the tree. Scenarios:
F1 boots with a 4-card hand and completes a full enemy turn; F13 fires 6 enemy
spells and gets exactly one Void Ritualist Prime champion. Sets
`UserProfile.saving_disabled` so scene changes never touch `user://profile.json`,
and `BaseVfx.time_scale = 0.05` (not 0 — at 0 VfxSequence drops mid-phase beats).

## Parity — engine vs live scene

**Path:** [debug/tests/ParityTests.gd](../debug/tests/ParityTests.gd) · **Scene:** `res://debug/tests/Parity.tscn`

```bash
godot --headless --path . res://debug/tests/Parity.tscn [-- --filter F15]
```

Plan 5.1 / 5.2. For each of 8 cases (F1–F3 on the three Vael decks, Seris
Corrupt Flesh and Soul Forge, Korrath, F13, F15; four carry relic pairs) × 3
seeds. The seeds also walk the encounter's deck pool (seed *i* plays variant
*i* mod pool size, via a run seed that picks it), so every F1–F4 variant and its
AI profile is replayed; each case line names the deck it played (e.g.
`F1 swarm seed 11 [f1_a]`):

1. **Engine run:** `CombatSim.run` on a bare `CombatState`; every accepted
   command's record and `digest_text()` are captured through
   `state.command_recorded` (hooked in with `CombatSim.state_observer`).
2. **Live replay:** the same run state in `GameManager` → a headless
   `CombatScene` (`CombatConfig.from_game_manager`, same seed,
   `presenter.instant`). The player's commands are replayed through the
   scene's input entry points — hand-card select, slot and hero clicks, the
   relic bar, the Seris skill buttons, end turn; the enemy is the scene's own
   `EnemyTurnRunner`. The player grows by the same profile curve the sim uses.
3. Records and digests must match at every index, the final digests too; the
   fight must end with a winner and the presenter must have played the whole
   journal (5.2's live smoke matrix — F1–F3 are every Act 1 encounter).

A mismatch prints the index, the command, and the differing digest lines (or,
when the input layer issued nothing, engine vs view slot occupancy). Moves the
AI makes that a player can't (a skipped mandatory target, a target the UI
doesn't offer, a random-target spell, spark fuel) are issued straight to the
engine and tallied by `reason:card` in the last line — a sim-fidelity signal,
not a failure. Budget ≤ 60 s: trim cases, never seeds.

## Determinism and seeds

All gameplay randomness uses the engine RNG on `CombatState` (`rng`, seeded via
`seed_rng`). `CombatSim.run(…, rng_seed)` returns `result.seed` (rolled when
`rng_seed < 0`), `result.digest` and `result.digest_text` (`CombatState.digest_text()`),
so any sim result can be replayed exactly. Live combat logs `Seed: N` as the
first combat-log line; set `GameManager.next_combat_seed = N` before entering
combat to replay it. `ScenarioTests` has two determinism probes (`--filter determinism`).

**Command replay (sim).** Every sim action is a `CombatState.cmd_*` recorded in
`state.command_log` (targets by slot / hero sentinel). `CombatSim.record_replay`
(or `dump_replay_path`) returns / writes `{seed, config, command_log, digest}`;
`CombatSim.replay(record)` rebuilds the same state and re-issues the commands
(profiles are built only for their resource curves; AI decision randomness uses
the agents' own `decision_rng`, so the engine RNG stream matches). Record with
`SimRunner.tscn -- --runs 1 --dump-replay /tmp/f.json`, replay with
`ReplayRunner.tscn -- /tmp/f.json` (exit 0 = digest matches, every command
accepted). Probe: `--filter replay`. Live input goes through the same commands
since Phase 3.4 (end turn included since 4.4), so `state.command_log` records a
live fight too. The [parity test](#parity--engine-vs-live-scene) replays sim
fights through the live scene's input handlers.

## RunAllTests — layered test suite

**Path:** [debug/tests/RunAllTests.gd](../echoofabyss/debug/tests/RunAllTests.gd)
**Scene:** `res://debug/tests/RunAllTests.tscn`
**Source of truth for assertions:** the four Layer N files described below.

This is the project's correctness gate. It runs five layers of probes against
`CombatState` (built by `TestHarness.build_state` → `setup_combat`) / `EffectResolver` / `TriggerManager` / commands /
`CombatSim`, and exits with the count of failed assertions (0 = green).
TestHarness tears down every `build_state` state once the test after the one
that built it begins (never the state passed to `begin_test`), and the rest at
the end of the suite, so a probe that skips `teardown()` can't leak its fight
or leave it listening on the BuffSystem bus.

### Layers

| Layer | File | What it probes | Test funcs |
|---|---|---|---|
| Damage type | [DamageTypeTests.gd](../echoofabyss/debug/tests/DamageTypeTests.gd) | Phase invariants of the source+school damage system | 33 |
| L1 Card effects | [CardEffectTests.gd](../echoofabyss/debug/tests/CardEffectTests.gd) | Per-card `effect_steps` via `EffectResolver.run()` | 53 |
| L2 Trigger handlers | [TriggerHandlerTests.gd](../echoofabyss/debug/tests/TriggerHandlerTests.gd) | One probe per handler registered by CombatSetup; trap routes; the handler-order snapshot (`snapshots/handler_order.txt` — delete it to regenerate after an intended reorder) | 110 |
| L5 Commands | [CommandTests.gd](../echoofabyss/debug/tests/CommandTests.gd) | `CombatState.cmd_*` refusals (no mutation) and happy paths, the turn engine, resource-growth curves, agents paying once, EncounterTable; `lifecycle /`: `teardown()` and `CombatSim.run` free the fight (weakref probes, task 049) | 32 |
| L3 Scenarios | [ScenarioTests.gd](../echoofabyss/debug/tests/ScenarioTests.gd) | Full `CombatSim.run()` matches with structural invariants | 37 |

Each test function fires multiple `assert_*` calls — total assertion count is
~1100 (last verified run: 1084 passed, 0 failed, 0 skipped — 2026-09-23). The suite is
fully green; any new failure represents a genuine regression.

Shared infrastructure: [TestHarness.gd](../echoofabyss/debug/tests/TestHarness.gd)
provides `build_state()`, `assert_eq/ne/true/false/approx/board()`,
state dump on failure, and label/filter plumbing.

### Run

```bash
# Full suite (all four layers)
$GODOT --headless --path $PROJECT res://debug/tests/RunAllTests.tscn

# Verbose — print each PASS, dump board state on FAIL
$GODOT --headless --path $PROJECT res://debug/tests/RunAllTests.tscn -- --verbose

# Filter to tests whose label contains a substring
$GODOT --headless --path $PROJECT res://debug/tests/RunAllTests.tscn -- --filter corrupt
$GODOT --headless --path $PROJECT res://debug/tests/RunAllTests.tscn -- --filter "scenario / swarm"
```

### Reading results

```
=== EchoOfAbyss Test Suite ===
=== Layer 1: Card Effect Tests ===
=== Layer 2: Trigger Handler Tests ===
=== Layer 3: Scenario Tests ===
=== 681 passed, 0 failed, 0 skipped ===
```

Exit code = number of failed assertions. The suite should be exit 0 on a
clean run; any non-zero exit means a regression.

### When to run

- Before every commit during a refactor
- After adding a new card / handler (write the matching L1 or L2 probe alongside)
- When chasing "did this still work" questions during feature dev

---

## BalanceSimBatch — full balance matrix

**Path:** [debug/BalanceSimBatch.gd](../echoofabyss/debug/BalanceSimBatch.gd)
**Scene:** `res://debug/BalanceSimBatch.tscn`

Runs the full preset × relic × fight × variant matrix headless and prints
one row per combination. The most-used balance tool in the project.

Per [feedback_sim_defaults](C:/Users/thund/.claude/projects/c--Thunder-work-Projects-EchoOfAbyss/memory/feedback_sim_defaults.md):
**always reach for this first** when a balance question comes up. Use
`DebugSingleSim` only for step-by-step debugging.

### Run

```bash
# Full Act 1 + Act 2 (default), 200 runs per combo
$GODOT --headless --path $PROJECT res://debug/BalanceSimBatch.tscn

# Filtered runs
$GODOT --headless --path $PROJECT res://debug/BalanceSimBatch.tscn -- --act 1
$GODOT --headless --path $PROJECT res://debug/BalanceSimBatch.tscn -- --fight 6
$GODOT --headless --path $PROJECT res://debug/BalanceSimBatch.tscn -- --preset swarm
$GODOT --headless --path $PROJECT res://debug/BalanceSimBatch.tscn -- --hero seris
$GODOT --headless --path $PROJECT res://debug/BalanceSimBatch.tscn -- --variant 0
$GODOT --headless --path $PROJECT res://debug/BalanceSimBatch.tscn -- --runs 50

# Deterministic mode (per-run seeds base+i; diff two outputs for a bit-exact check)
$GODOT --headless --path $PROJECT res://debug/BalanceSimBatch.tscn -- --seed 42
```

### Output

```
Swarm      | none | F1 Rogue Imp Pack       | Win  72.5% | Loss  27.5% | T 12.3 | HP   +18 | Champ 0.20 [f1_a]
             Det:1.2 | SV:1.2/45 | VB:1.1x/45dmg | Imp:120 | VW:Beh0.30/Bas0.20
```

Main row: win/loss %, average turns, average final HP delta, average champion
summons. Indented extras line: per-card / per-system stats (corruption
detonation, smoke veil, void bolt damage, etc. — all the metrics tracked in
[CombatSim.run_many](../echoofabyss/sim/CombatSim.gd)).

---

## BalanceSim — interactive balance UI

**Path:** [debug/BalanceSim.gd](../echoofabyss/debug/BalanceSim.gd)
**Scene:** `res://debug/BalanceSim.tscn`

Editor-only UI for tweaking decks, talents, hero passives, encounter, and
run count, then clicking Run. Useful when you want to explore a specific
matchup without writing a CLI invocation.

### Run

Open `res://debug/BalanceSim.tscn` in the Godot editor and play the scene
(F6), or navigate from `TestLaunchScene`.

For batch / scripted use, prefer `BalanceSimBatch`.

---

## DebugSingleSim — single fight with full logging

**Path:** [debug/DebugSingleSim.gd](../echoofabyss/debug/DebugSingleSim.gd)
**Scene:** `res://debug/DebugSingleSim.tscn`

Runs a single hard-coded F11 sim (Swarm vs Void Warband, full talents,
SL+SA relics) with verbose per-turn logging. The deck/talents/relics are
constants in the script — edit the file to point it at a different matchup.

Per [feedback_sim_defaults](C:/Users/thund/.claude/projects/c--Thunder-work-Projects-EchoOfAbyss/memory/feedback_sim_defaults.md):
use this only when you need step-by-step logs to trace a specific bug.
For balance questions, use BalanceSimBatch instead.

### Run

```bash
$GODOT --headless --path $PROJECT res://debug/DebugSingleSim.tscn
```

---

## SimRunner — general CLI sim

**Path:** [debug/SimRunner.gd](../echoofabyss/debug/SimRunner.gd)
**Scene:** `res://debug/SimRunner.tscn`

Generic CLI front-end for `CombatSim.run_many()`. More flexible than
BalanceSimBatch (arbitrary deck strings, arbitrary HP) but no preset matrix.

### Run

```bash
$GODOT --headless --path $PROJECT res://debug/SimRunner.tscn -- \
    --deck "void_imp,void_imp,shadow_hound,void_bolt" \
    --profile feral_pack --runs 200

# Run against every registered profile
$GODOT --headless --path $PROJECT res://debug/SimRunner.tscn -- --all-profiles
```

Args: `--deck`, `--profile`, `--runs`, `--player-hp`, `--enemy-hp`,
`--talents`, `--hero-passives`, `--all-profiles`.

---

## ScoredAITest — Voidbolt full run

**Path:** [debug/ScoredAITest.gd](../echoofabyss/debug/ScoredAITest.gd)
**Scene:** `res://debug/ScoredAITest.tscn`

500-run Voidbolt-burst tuning report across Act 1 + Act 2, with per-fight
deck variants and 1-relic combos. Output is a hand-formatted balance table.
Configurable via constants in the file.

### Run

```bash
$GODOT --headless --path $PROJECT res://debug/ScoredAITest.tscn
```

---

## DebugF13LossAnalysis — per-turn loss diagnosis

**Path:** [debug/DebugF13LossAnalysis.gd](../echoofabyss/debug/DebugF13LossAnalysis.gd)
**Scene:** `res://debug/DebugF13LossAnalysis.tscn`

Runs N games of Swarm vs F13 (Void Ritualist Prime) with the
historically-weak `MS+DM` relic combo, captures per-turn snapshots, and
prints both per-game tables and aggregate summary. Used for diagnosing
*why* the boss loses, not just the win rate.

Tracks: enemy board pressure, hand bloat, mana/essence usage, player
pressure faced, damage to enemy hero by source.

### Run

```bash
$GODOT --headless --path $PROJECT res://debug/DebugF13LossAnalysis.tscn
$GODOT --headless --path $PROJECT res://debug/DebugF13LossAnalysis.tscn -- --games 20
```

---

## VoidboltDmgDebug — damage source trace

**Path:** [debug/VoidboltDmgDebug.gd](../echoofabyss/debug/VoidboltDmgDebug.gd)
**Scene:** `res://debug/VoidboltDmgDebug.tscn`

5 Voidbolt vs F6 games. Prints every point of enemy hero damage, labelled
by source, turn by turn. Specialised for diagnosing where Voidbolt's damage
actually comes from.

### Run

```bash
$GODOT --headless --path $PROJECT res://debug/VoidboltDmgDebug.tscn
```

---

## TestLaunchScene + TestConfig — scripted combat launcher

**Paths:**
[debug/TestLaunchScene.gd](../echoofabyss/debug/TestLaunchScene.gd) (UI),
[debug/TestConfig.gd](../echoofabyss/debug/TestConfig.gd) (autoload state).

Editor scene to set up a custom combat: hand cards, board state, traps,
HP, infinite resources, AI profile, enemy passives — then click Launch
to enter the real `CombatScene`. The matching `add-art`/`test-card`
skill workflow uses this.

### Run

Open `res://debug/TestLaunchScene.tscn` in the editor and play.
Settings persist in the `TestConfig` autoload while combat runs.

This is the **only** test path that exercises the full `CombatScene`
(VFX, UI, signals) by hand — LiveSmoke drives it headless; everything else runs against a bare `CombatState`.

---

## EnemyDeckBuilder — encounter deck editor

**Path:** [debug/EnemyDeckBuilder.gd](../echoofabyss/debug/EnemyDeckBuilder.gd)
**Scene:** `res://debug/EnemyDeckBuilder.tscn`

Editor UI for building/editing the per-encounter deck variants in
`res://enemies/data/encounter_decks.json` (through `EncounterDecks`). Each
encounter has a pool of deck IDs; the run seed picks one per fight
(`EncounterDecks.pick_for_run`). Navigate from `BalanceSim`. It writes the
committed file in place, so an edit shows up in `git diff` and moves the
balance fingerprint — commit it like any content change. Saving works in
editor runs only (res:// is read-only in an export).

### Run

Open in editor and play, or click Decks from `BalanceSim`.

---

## Recommended workflow per situation

### Refactor / extraction work

1. `tools/run_checks.sh` before the first edit (record the count) and after every step
2. Balance fingerprint: `BalanceSimBatch -- --act 1 --runs 200 --seed 7 > before.txt`
   once before starting, again after each step, and `diff` — a sim-neutral step is byte-identical
3. Manual smoke in editor for VFX/UI extractions

If run_checks fails or the batch diff is non-empty for a step meant to be
neutral: investigate before committing. The suite is fully green; any failure
is a regression.

### New card or handler

1. Add the card/handler
2. Write the matching probe in `CardEffectTests.gd` (L1) or `TriggerHandlerTests.gd` (L2)
3. `RunAllTests --filter <new_card_id>` — confirm new probe passes
4. `RunAllTests` — confirm nothing else broke
5. `BalanceSimBatch --preset <relevant>` — confirm it doesn't tank balance

### Balance question

1. Default to `BalanceSimBatch` filtered to the preset/fight you care about
2. If a specific run looks weird, `DebugSingleSim` (edit constants to your case)
3. For per-turn forensics, follow the `DebugF13LossAnalysis` pattern

### Bug in a specific card flow

1. Reproduce manually in `TestLaunchScene` (set up exact board state)
2. Once reproduced, write a permanent regression probe in L1 or L2

### CI-style pre-push gate (suggested)

```bash
# Fast: ~10s. Should exit 0 (no failures expected).
$GODOT --headless --path $PROJECT res://debug/tests/RunAllTests.tscn 2>&1 | tee test.log
grep -q "^=== [0-9]* passed, 0 failed" test.log || exit 1

# The full gate (lint, compile, tests, LiveSmoke, Parity): ~90s
tools/run_checks.sh || exit 1
```

A ready-made hook: `ln -s ../../tools/hooks/pre-push .git/hooks/pre-push`
(`git push --no-verify` skips it once).

---

## Adding a new test

| Where to add | Use when |
|---|---|
| `CardEffectTests.gd` | A card's `effect_steps` produce a specific delta on the state |
| `TriggerHandlerTests.gd` | A handler registered in `CombatSetup` should fire on a specific event |
| `DamageTypeTests.gd` | A new invariant of the source/school damage system |
| `ScenarioTests.gd` | A multi-turn interaction that spans multiple handlers/cards |

For all four, follow the patterns already in the file. Use `TestHarness.build_state()`
or one of the per-hero presets (`vael_state()`, `seris_state()`). Use lenient
assertions for outcome (`winner`, `turns`) and strict assertions for
structural invariants (no crash, expected counters ticked).
