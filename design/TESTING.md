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
| [tools/run_checks.sh](#run_checkssh--the-refactor-gate) | **The gate**: import → engine lint → compile every script → RunAllTests → LiveSmoke; fails on any `SCRIPT ERROR` | Yes | Yes | ~40s |
| [Engine lint](#engine-lint--toolslintlint_enginepy) | Static checks: live-shell name drift (L1), global RNG (L2), presentation seam (L3), duck typing (L4), duplicated gameplay bodies (L5) | Yes (Python) | Yes | <1s |
| [LiveSmoke](#livesmoke--headless-combatscene) | Boots the real `CombatScene` headless and plays an enemy turn | Yes | Yes | ~8s |
| [RunAllTests](#runalltests--layered-test-suite) | Layered correctness tests (4 layers, ~500 assertions) | Yes | Yes | ~10s |
| [BalanceSimBatch](#balancesimbatch--full-balance-matrix) | Full balance matrix across acts/decks/relics | Yes | No (prints stats) | 5–15 min |
| [Baseline tool](#baseline-tool--regression-fingerprint) | Bit-exact regression detection across refactors | Yes (Python wrapper) | Yes (diff vs prior capture) | Same as BalanceSimBatch |
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
through), `RunAllTests`, then `LiveSmoke`. Exits non-zero on any lint error,
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
| L1 | Rules code (`CombatHandlers`, `HardcodedEffects`, `RelicEffects`, `EffectResolver`, `ConditionResolver`, `TargetResolver`, `CombatManager`, `MinionInstance`) reaching a name through the combat shell (`_scene.x`, `ctx.scene.x`, `.get/.set("x")`) that the **live** `CombatScene` doesn't declare. Such code works in tests (which run on `SimState`) and crashes or silently no-ops in the real game. Also: `.state.x` must exist on `CombatState`; `CombatSetup` registry stat keys must exist on `CombatState`. `tools/lint/l1_allow.txt` is empty and should stay that way. |
| L2 | Global `randi/randf/shuffle/pick_random` in engine, rules, sim or AI code. Gameplay randomness goes through `state.rng_pick / rng_shuffle / rng_range / rng_index` so a seed reproduces a fight. Opt out per line with `# lint: allow-rng (<reason>)` (only the two seed rolls do). |
| L3 | Presentation seam. In rules files the shell (`_scene.`, `ctx.scene.`, `scene.`) may be followed only by `state` or a `[facade]` name, and `presenter.` / `ctx.presenter.` only by a `[presenter]` name (also checked inside CombatState) — both lists in `tools/lint/presentation_allowlist.txt`, which the lint validates against the classes. |
| L4 | Duck typing in rules files: `has_method(`, and `.get("x")` / `.set("x", …)` / `"x" in obj` on an object handle. Dictionary `.get("key")` is fine. |
| L5 | A gameplay func defined on both CombatScene and SimState, or a SimState override of a CombatState func — one CombatState body per method. `--report-pairs` lists them. |
| L6 | `await`, `get_tree(` or `create_timer(` in `CombatState.gd` — the engine never waits (animations hang off its signals); `BoardSlot` named in `CombatState.gd`, `SimState.gd`, `CombatHandlers.gd`, `EffectResolver.gd` or `TargetResolver.gd` — the engine holds `SlotState`, the node is a view (plan 3.1a). |
| L7 | A second definition, anywhere in the repo, of a state command (`func cmd_*`), the turn engine (`begin_turn` / `end_turn`), trap routing (`_fire_traps_for`), or an AI profile table (a script preloading the `enemies/ai/profiles/` scripts — only `ProfileRegistry` may). |

## LiveSmoke — headless CombatScene

**Path:** [debug/tests/LiveSmokeTests.gd](../debug/tests/LiveSmokeTests.gd) · **Scene:** `res://debug/tests/LiveSmoke.tscn`

The only test that instantiates the live `CombatScene` (everything else runs on
`SimState`). Separate process because `RunAllTests` quits the tree. Scenarios:
F1 boots with a 4-card hand and completes a full enemy turn; F13 fires 6 enemy
spells and gets exactly one Void Ritualist Prime champion. Sets
`UserProfile.saving_disabled` so scene changes never touch `user://profile.json`,
and `BaseVfx.time_scale = 0.05` (not 0 — at 0 VfxSequence drops mid-phase beats).

## Determinism and seeds

All gameplay randomness uses the engine RNG on `CombatState` (`rng`, seeded via
`seed_rng`). `CombatSim.run(…, rng_seed)` returns `result.seed` (rolled when
`rng_seed < 0`), `result.digest` and `result.digest_text` (`SimState.digest_text()`),
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
accepted). Probe: `--filter replay`. Live fights can't be replayed until Phase
3.4 moves live input onto commands.

## RunAllTests — layered test suite

**Path:** [debug/tests/RunAllTests.gd](../echoofabyss/debug/tests/RunAllTests.gd)
**Scene:** `res://debug/tests/RunAllTests.tscn`
**Source of truth for assertions:** the four Layer N files described below.

This is the project's correctness gate. It runs five layers of probes against
`SimState` / `EffectResolver` / `TriggerManager` / `CombatState` commands /
`CombatSim`, and exits with the count of failed assertions (0 = green).

### Layers

| Layer | File | What it probes | Test funcs |
|---|---|---|---|
| Damage type | [DamageTypeTests.gd](../echoofabyss/debug/tests/DamageTypeTests.gd) | Phase invariants of the source+school damage system | 33 |
| L1 Card effects | [CardEffectTests.gd](../echoofabyss/debug/tests/CardEffectTests.gd) | Per-card `effect_steps` via `EffectResolver.run()` | 53 |
| L2 Trigger handlers | [TriggerHandlerTests.gd](../echoofabyss/debug/tests/TriggerHandlerTests.gd) | One probe per handler registered by CombatSetup; trap routes; the handler-order snapshot (`snapshots/handler_order.txt` — delete it to regenerate after an intended reorder) | 110 |
| L5 Commands | [CommandTests.gd](../echoofabyss/debug/tests/CommandTests.gd) | `CombatState.cmd_*` refusals (no mutation) and happy paths, the turn engine, resource-growth curves, agents paying once, EncounterTable | 30 |
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

# Deterministic mode (added for the baseline tool — see below)
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

## Baseline tool — regression fingerprint

**Paths:**
[tools/baseline/capture.py](../tools/baseline/capture.py),
[tools/baseline/diff.py](../tools/baseline/diff.py),
[tools/baseline/README.md](../tools/baseline/README.md)

Wraps `BalanceSimBatch` with deterministic seeding and bit-exact diffing.
Built specifically for the CombatScene.gd refactor: capture before, capture
after, diff to confirm nothing moved.

Sim is bit-deterministic when `--seed >= 0` is passed (each run inside the
batch uses `base_seed + run_index`). Two captures with the same seed and same
`--runs` are byte-identical if no code changed.

### Run

```bash
# Baseline before changes (default --seed 42)
python tools/baseline/capture.py pre_refactor --runs 200

# After changes
python tools/baseline/capture.py post_champion --runs 200

# Diff — auto-detects matching seeds and uses ZERO tolerance
python tools/baseline/diff.py \
    tools/baseline/baselines/pre_refactor.json \
    tools/baseline/baselines/post_champion.json
```

Exit codes: `0` clean, `1` behavioural diff, `2` rows added/removed (a sim
API surface change — investigate).

### Fast iteration

```bash
# Spotcheck a single preset/act/fight while iterating
python tools/baseline/capture.py spotcheck --preset swarm --runs 50 --act 1
```

### Tolerance modes

The diff picks one of three modes automatically:

- **SEEDED EXACT** — both baselines used the same seed and same `--runs`.
  Tolerance = 0. Any divergence is a code regression.
- **STRICT** (`--strict`) — for unseeded captures with `runs >= 500`.
- **DEFAULT** — for unseeded captures with `runs = 200`. ±3.5pp win rate,
  ±0.6 turns, ±20% on extras.

### What it compares

Per row (preset × relic × fight × variant × deck): win%, loss%, avg turns,
avg final HP, champion-summon rate, **plus every extras stat**
(`Det`, `Rit`, `SV`, `Plg`, `VB`, `Imp`, `RC`, `Crt`, `DC`, `VW`,
`BehL`, `BasL`, `P2`, …). Win-rate alone is too coarse — most refactor
regressions show first in the extras.

### Limits

- Won't catch VFX / signal-order / banner-Z visual issues — sim is headless.
  Pair with manual smoke testing in the editor.
- Console errors (`push_error`/`push_warning`) aren't currently captured.
- Renaming a preset or relic display name will make every row look
  added+removed. Avoid display renames during a refactor commit.

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
(VFX, UI, signals) — everything else above runs against `SimState`.

---

## EnemyDeckBuilder — encounter deck editor

**Path:** [debug/EnemyDeckBuilder.gd](../echoofabyss/debug/EnemyDeckBuilder.gd)
**Scene:** `res://debug/EnemyDeckBuilder.tscn`

Editor UI for building/editing the per-encounter deck variants stored in
`EncounterDecks`. Each encounter has a pool of deck IDs; one is picked at
combat start. Navigate from `BalanceSim`.

### Run

Open in editor and play, or click Decks from `BalanceSim`.

---

## Recommended workflow per situation

### Refactor / extraction work

1. `python tools/baseline/capture.py pre_refactor --runs 200` (one-time, before starting)
2. Capture pre-state failure list:
   `$GODOT --headless --path $PROJECT res://debug/tests/RunAllTests.tscn 2>&1 | grep "^  FAIL:" > pre_fails.txt`
3. Make the change
4. Re-run RunAllTests, grep failures, diff against `pre_fails.txt` — must be empty
5. `python tools/baseline/capture.py post_step1 --runs 200` then diff vs `pre_refactor.json`
6. Manual smoke in editor for VFX/UI extractions

If new test failures appear OR baseline diff is non-empty: investigate before
committing. The suite is fully green; any failure is a regression.

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

# Slow but thorough: 5–15 min
python tools/baseline/capture.py prepush_$(date +%s) --runs 200
# (then diff against your last known-good baseline)
```

---

## Adding a new test

| Where to add | Use when |
|---|---|
| `CardEffectTests.gd` | A card's `effect_steps` produce a specific delta on `SimState` |
| `TriggerHandlerTests.gd` | A handler registered in `SimTriggerSetup` should fire on a specific event |
| `DamageTypeTests.gd` | A new invariant of the source/school damage system |
| `ScenarioTests.gd` | A multi-turn interaction that spans multiple handlers/cards |

For all four, follow the patterns already in the file. Use `TestHarness.build_state()`
or one of the per-hero presets (`vael_state()`, `seris_state()`). Use lenient
assertions for outcome (`winner`, `turns`) and strict assertions for
structural invariants (no crash, expected counters ticked).
