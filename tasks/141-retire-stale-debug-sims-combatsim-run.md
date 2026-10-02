---
id: "141"
title: Retire the stale debug sims; CombatSim.run takes a config
status: backlog
area: tooling
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item J5 (`design/refactors/ARCHITECTURE_ROADMAP.md` §J). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Three standalone debug sims hard-code content that has drifted from the game, so their reports describe decks or numbers the game doesn't use. One also has a lambda-capture bug. Nothing runs them: only design/TESTING.md and ARCHITECTURE.md reference them, and `tools/lint/load_all_scripts.gd` just compiles them.

Debug tools only; no gameplay effect.

### VoidboltDmgDebug.gd

- **Wrong enemy deck.** :18-25 `ENEMY_DECK` has 14 cards (3 abyss_cultist, 2 cult_fanatic, 3 brood_imp, 2 void_stalker, 2 void_spawner, 2 dark_command). The real F6 deck `f6_a` has 11 (1 abyss_cultist, 1 brood_imp, 2 cult_fanatic, 1 dark_command, 2 void_screech, 2 void_spawner, 2 void_stalker).
- **Positional call.** :36-45 calls `sim.run(` with 11 positional arguments, ending `{}, true  # dmg_log enabled`.
- **Duplicated HP.** :38 `3000, 4000` copies F6's HP (EncounterTable.gd:59, `"hp": 4000`); it matches today.

### ScoredAITest.gd

- **No real decks.** :10-36 hard-code 6 encounter decks. None matches any deck in pools F1–F6 (sorted comparison against the deck file).
- **No scored AI.** It runs the scripted encounter profiles against `spell_burn` (:67-69), not the scored profiles. ARCHITECTURE.md:312 says "Tests weighted-scoring AI profiles".
- **Already covered.** BalanceSimBatch's `voidbolt_burst` preset (:34-44: `spell_burn`, the same hero passives, talents per act) plays the same matchup with the real decks: `BalanceSimBatch -- --preset voidbolt_burst --act 1` (and `--act 2`).

### DebugF13LossAnalysis.gd

- **Per-turn damage is cumulative.**
  - :42 `var prev_enemy_hp := 5000` is reassigned inside the `turn_snapshot_callback` lambda at :68 (`prev_enemy_hp = st.enemy_hp`).
  - GDScript lambdas capture locals by value, so the reassignment doesn't carry to the next call: every call starts from 5000.
  - So :57 `"dmg_this_turn": prev_enemy_hp - st.enemy_hp` is cumulative damage, and the `burst_dmg` tag (:228-229, `> 1500`) fires on every turn after the total passes 1500.
  - This is inferred from Godot 4's capture semantics, not executed.
- **Stale castability rule.** `_is_castable` (:88-106) reads the raw `sp.cost` and `mc.essence_cost` instead of the engine's effective costs (discounts, spark fuel).
- **Deck source.** It reads `f13_a` through EncounterDecks (:34-35), which is the user:// file until task 047.
- **Wrong name in the docs.** ARCHITECTURE.md:311 calls F13 "Abyss Sovereign". F13 is Void Ritualist Prime (EncounterTable.gd:122).

### DebugSingleSim.gd

:24-28 hard-codes the F11 enemy HP as 5000. It matches EncounterTable.gd:104 today.

### CombatSim's positional APIs

- `run(` (sim/CombatSim.gd:181-196) takes 15 parameters: `…, relic_bonus_charges, dmg_log, debug, enemy_limited, player_hero_id, rng_seed`.
- `run_many(` (:364-378) takes 14 in a different order: `count, …, relic_bonus_charges, enemy_limited, player_hero_id, base_seed`.
- Call sites:
  - `run`: 47 (ScenarioTests 43, ParityTests 1, the three debug sims);
  - `run_many`: 8 (BalanceSimBatch 3, ScoredAITest 3, BalanceSim 1, SimRunner 1).
- Calls with 11–15 positional arguments, in two different orders, are easy to get wrong.
- The named pieces already exist: `make_config(...)` (:36-48) builds the config dict, and `_build(config, rng_seed, dmg_log, debug)` (:56) builds the fight.

## Proposed fix

### Phase a (S): retire or fold the scripts

Recommendation per script: delete VoidboltDmgDebug and ScoredAITest; fold DebugF13LossAnalysis into SimRunner, then delete it; fix DebugSingleSim.

1. **SimRunner flags.**
   - `--encounter N`: read the enemy deck, profile, HP and `limited` list from EncounterTable and EncounterDecks, so no deck is hard-coded.
   - `--dmg-log`: run each game through `run` with `dmg_log = true`, and print the per-turn damage-by-source table from `result.dmg_log` (the loop at VoidboltDmgDebug.gd:55-90).
   - `--hero`: task 097 notes that SimRunner has no hero flag, so Seris talents run as Vael.
2. **Delete VoidboltDmgDebug.gd / .tscn / .uid.** Replacement: `SimRunner -- --encounter 6 --dmg-log …`.
3. **Delete ScoredAITest.gd / .tscn / .uid** (or `debug/VoidboltFullRun.*` if task 120 renamed it first). Replacement: the `voidbolt_burst` preset in BalanceSimBatch.
4. **DebugF13LossAnalysis: fold, then delete.**
   - Add its per-turn snapshot table and loss tags to SimRunner as `--snapshots`, for any encounter or profile.
   - Keep the previous HP in a mutable holder (`var prev := [hp]`, then `prev[0] = st.enemy_hp`).
   - Take castability from the engine: a StateAgent on the enemy side (`effective_spell_cost`, `effective_minion_essence_cost`, StateAgent.gd:101 / :104) and `state.spark_cost_of` (CombatState.gd:2987).
5. **DebugSingleSim:** read the enemy HP from EncounterTable instead of the 5000 literal.
6. **Docs.**
   - TESTING.md: the quick reference (:31-33), the tool sections (:311-362), and :428, which points per-turn forensics at `DebugF13LossAnalysis`. Point them at the SimRunner flags.
   - ARCHITECTURE.md:311-314: the debug rows.

### Phase b (M): `CombatSim` takes a config

Do this after task 049 step 2, which rebuilds `run`'s tail (result built before teardown).

7. **`sim/SimSpec.gd`**, a RefCounted with named fields: `player_deck`, `enemy_profile`, `enemy_deck`, `player_hp`, `enemy_hp`, `talents`, `player_profile`, `hero_passives`, `relics`, `relic_bonus_charges`, `enemy_limited`, `hero_id`. It has:
   - `to_config() -> Dictionary`, through `make_config`;
   - `static func for_encounter(index) -> SimSpec`, which fills the enemy fields from EncounterTable and EncounterDecks.
8. **New entry points:** `CombatSim.run_spec(spec, rng_seed := -1, dmg_log := false, debug := false)` and `run_many_spec(count, spec, base_seed := -1)`. Their bodies are today's `run` / `run_many` bodies from the config on.
9. **Migrate the call sites:** about 45 `run` and 5 `run_many` once phase a has deleted three scripts. Then delete the positional signatures, and update CombatSim's header example (:6).

## Verification

- `tools/run_checks.sh` green after each phase. ScenarioTests' determinism and replay probes (`--filter determinism`, `--filter replay`) stay green.
- **Phase a:**
  - `SimRunner -- --encounter 6 --dmg-log` with the old VoidboltDmgDebug player deck: the per-turn totals add up to the run's total enemy-hero damage (4000 minus the final enemy HP, for a fight without healing).
  - `--snapshots` on F13: the `dmg_this_turn` values sum to 5000 minus the final enemy HP.
  - Behaviour-neutral: only SimRunner and debug scripts change, and BalanceSimBatch uses neither, so no BalanceSimBatch run is needed.
- **Phase b:** behaviour-neutral. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` through `--act 4`: every batch run goes through `run_many`) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Depends on: task 049 — step 2 rebuilds `CombatSim.run`'s tail; phase b migrates after it.
- Depends on: task 047 — moves the enemy decks into the repo. SimRunner's `--encounter` and DebugSingleSim read them through that source.
- Related: task 120 (roadmap G4) — renames ScoredAITest to VoidboltFullRun unless this task has already deleted it.
- Related: task 094 (roadmap B1) — moves the balance counters off CombatState and changes what `run` returns.
- Related: task 121 (roadmap G5) — also edits `run`'s body; land in either order.
- Related: task 097 (roadmap B3) — asks for SimRunner's `--hero` flag (step 1).
- Related: task 073 — SimRunner and BalanceSim are the only paths that pair the `default` player profile with a Void Execution deck.
- Related: task 053 — keeps `debug/*` out of release builds.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item J5. Re-checked at `404b51c`:
  - VoidboltDmgDebug's F6 deck and ScoredAITest's 6 decks match no real deck;
  - added ScoredAITest (missed by the review) and DebugF13LossAnalysis's lambda-capture bug and raw-cost castability;
  - recommendation: delete two scripts and fold one into SimRunner.

## Summary

_(filled in at /task-done)_
