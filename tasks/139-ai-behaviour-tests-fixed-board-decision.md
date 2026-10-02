---
id: "139"
title: AI behaviour tests: one fixed-board decision probe per encounter profile
status: backlog
area: tooling
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item J3 (`design/refactors/ARCHITECTURE_ROADMAP.md` §J). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

No test sets up a fixed board and asserts what an encounter profile decides.

### What exists

- **Growth curves.** CommandTests.gd:634 `_GROWTH_CURVES` (35 rows, one per registered profile), checked by `_growth_curves_match_the_ported_sim_curves` (:672).
- **Agent and payment probes.**
  - CommandTests: `_profile_play_pays_once` (:698, the default player profile's play phase) and `_agent_spark_fuel_is_credited` (:712).
  - TriggerHandlerTests.gd:3352 `_sim_enemy_agent_sees_essence_discounts`.
- **Whole fights.** ScenarioTests has 36 `assert_clean_finish` calls: the fight ends, nothing asserts the choices.

### What is untested

The profiles: ProfileRegistry.gd `ENEMY` (:8-37) has 27 entries, 4 of them scored (:32-36). `PLAYER` (:40-49) has 8 entries, 1 scored (:45). That leaves 23 enemy and 7 player profiles.

Decision rules nothing pins, for example:
- **feral_pack.** FeralPackProfile.gd:20 `const _FERAL_IMP_THRESHOLD := 3`. `_should_cast_pack_frenzy()` (:45-55) casts on lethal or at 3+ feral imps, and `attack_phase` (:33-39) casts it before attacking.
- **matriarch_sac.** MatriarchSacProfile.gd:92-99 `_pick_sac_target()` picks void_spark, then brood_imp, otherwise null. `play_phase` (:25-35) casts abyssal_sacrifice only when there is a target. Its frenzy threshold is 2 (`MATRIARCH_FERAL_THRESHOLD`, :11).
- **void_herald.** VoidHeraldProfile.gd:59-78 `_try_void_wind()` casts only when the player has a Void Rune.
- **The shared base.** CombatProfile.gd:694 `_calc_lethal_damage()` and :786 `_pick_best_guard(...)`.
- **void_ritualist.** The play order is traps, humans, spells, then feral imps (VoidRitualistProfile.gd:21+ `play_phase`).
- **corrupted_handler.** The play order is spark generators, spells, humans, other minions, then feral imps (CorruptedHandlerProfile.gd:22-46).
  - **Comment and code disagree.** The header (:8, "Play feral imps AFTER attacks") and the comment at :54 say the imps are played after the attack phase. The code plays them at the end of `play_phase` (:44-46), and `attack_phase` (:57+) plays no cards.
  - The probe pins what the code does. Whether the comment or the code is right is a balance call; raise it when this task starts.

### Why it matters

Today only a BalanceSimBatch diff catches a changed decision, and that takes minutes and gives aggregate win rates. A rare branch (the lethal check, the guard pick, a sacrifice target, a conditional spell) can change with no visible shift in the aggregate.

Tasks 117, 118, 119 and 121 (roadmap G1, G2, G3, G5) and task 051 refactor these profiles and are meant to be balance-neutral. If no seed path happens to reach a branch, a mistake in it passes unseen.

## Decision (owner, 2026-10-01)

- Q7a: "Keep BoardEvaluator + ScoringWeights … (with a test); delete ScoredCombatProfile and the 4 scored profiles." So:
  - no probes for the scored profiles (task 120 deletes them);
  - task 120's BoardEvaluator test goes in this task's file if this lands first.
- Q1 / Q2: PvP is planned, so profiles should work on either side.
  - Three profiles hard-code the opponent as `"player"`: VoidAberrationProfile.gd:81, VoidScoutProfile.gd:51 and VoidHeraldProfile.gd:60 (`agent.state.traps_of("player")`).
  - Fixing that is task 122 (roadmap G7). After it lands, add a player-side run of the same probes.

## Proposed fix

1. **New layer.** Create `debug/tests/AiBehaviourTests.gd` with `static func run_all()`.
   - Labels start with `ai / <profile id> / `, so `--filter "ai /"` selects the layer.
   - RunAllTests.gd `await`s it, because profiles await their agent.
   - Register it in RunAllTests by hand; task 137's lint L15 checks the wiring once it lands.
2. **Shared helpers.** Move CommandTests' `_hand_card`, `_set_res`, `_ready_minion` and `_enemy_turn` (:45-58) into TestHarness, and make CommandTests call the moved copies.
3. **Add `TestHarness.ai_probe(side, profile_id, opts, setup: Callable) -> Dictionary`.** It:
   - calls `build_state(opts)`. `enemy_passives` defaults to `EncounterTable.passives_for_profile(profile_id)` (EncounterTable.gd:185) minus the `champion_*` ids, so a champion doesn't auto-summon mid-probe; an option keeps them;
   - clears both hands, then runs `setup.call(state)` for boards, hand, resources, traps and HP;
   - makes it that side's turn (`state.is_player_turn = side == "player"`);
   - creates the profile with `ProfileRegistry.make(side, profile_id)` and `setup(TestHarness.agent_for(state, side))`;
   - awaits `play_phase()`, records `state.command_log.size()`, then awaits `attack_phase()`;
   - returns `{log = state.command_log, attack_from = <recorded index>}`. Each log entry is `{turn, side, cmd, card_id, hand_index, slot, target {kind, side, slot}, extra}` (CombatState.gd:3113-3118).
4. **Determinism.** build_state's CombatConfig seed defaults to 0, and StateAgent seeds `decision_rng` from `hash("%d:%s" % [s.rng_seed, p_side])` (StateAgent.gd:20). Add an optional `seed` key to build_state for probes that need a different seed.
5. **At least one probe per non-scored profile** (23 enemy, 7 player). Pick each profile's distinctive rule from its header and code. Examples:
   - **feral_pack:** 3 NORMAL feral imps, pack_frenzy in hand, enough Mana, player HP above lethal → the play phase has no `play_spell`, and the first attack-phase command is `play_spell pack_frenzy`, before any attack. With 2 imps it is never cast.
   - **matriarch_sac:** void_spark + brood_imp + rabid_imp on board, abyssal_sacrifice in hand → the sacrifice targets the void_spark's slot. brood_imp + rabid_imp → the brood_imp's slot. Only rabid_imp → not cast.
   - **matriarch_sac and corrupted_brood_rune** (decks f3_c and f2_c run `abyssal_sacrifice`): with the act's champion on board (cost 0) and no void_spark or brood_imp → not cast. The base `CombatProfile.pick_spell_target` would send this `friendly_minion` spell to `_pick_cheapest_friendly` (CombatProfile.gd:463-464, :895-907) and sacrifice the champion, skipping its death handlers (task 066). The probe pins that both profiles keep their own `_pick_sac_target` (MatriarchSacProfile.gd:92-99, CorruptedBroodRuneProfile.gd:131-141).
   - **void_herald:** void_wind in hand and no player rune → not cast. With a player Void Rune → cast.
   - **default** (the base CombatProfile):
     - ready friendly ATK ≥ player HP and no player guard → only `attack_hero` commands;
     - with a player guard → the first attack targets the guard.
   - **void_ritualist:** Blood and Dominion Runes in hand, then a human and a feral imp → the runes, then the human, then the imp.
   - **corrupted_handler:** a feral imp in hand with spark generators and a human → the imp is the last card played in the play phase.
   - Task 072's probes (abyss_sovereign, void_champion, void_captain, void_scout) count toward this. Move them here from CommandTests with their labels unchanged.
6. **Pin today's decisions,** including ones a bug task changes on purpose (072, 073). That task updates the probe in the same commit.
7. **Docs:** add a TESTING.md row for the new layer, and a line in "Adding a new test".

## Verification

- `tools/run_checks.sh` green.
- Each probe fails when its rule is flipped locally. Examples: `_FERAL_IMP_THRESHOLD = 2`; swap the two loops in `_pick_sac_target`; invert the Void Rune check. Record this in the summary, then revert.
- Running `--filter "ai /"` twice gives identical command logs.
- Behaviour-neutral: test code only, plus four test helpers moved into TestHarness. No AI, engine or sim code changes, so the balance fingerprint can't move; no BalanceSimBatch run needed.

## Related

- Related: tasks 117, 118, 119 and 121 (roadmap G1, G2, G3, G5) — all depend on this task. These probes catch a rare branch a refactor breaks.
- Related: task 120 (roadmap G4) — deletes the scored profiles; its BoardEvaluator + ScoringWeights test goes in this file if this has landed.
- Related: task 122 (roadmap G7) — side-aware CombatAgent reads. Its `_agent_reads_are_side_aware` probe goes here, and once it lands the probes can also run on the player side.
- Related: task 072 — F14/F15 boss AI fixes; its probes move here.
- Related: task 073 — player sim-bot fixes; their probes go here if this has landed.
- Related: task 051 — stops `DefaultProfile` sorting the engine's hand in place; the default-profile probe sees the same hand either way.
- Related: task 137 (roadmap J1) — lint L15 checks that this file is registered.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item J3. Re-checked at `404b51c`: 23 enemy and 7 player non-scored profiles, no decision probes. The corrupted_handler example was corrected: the code plays feral imps at the end of the play phase, not after attacks as its header says.

## Summary

_(filled in at /task-done)_
