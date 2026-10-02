---
id: "125"
title: PhaseTransition reads its phase-2 spec from EncounterTable instead of the profile id and constants
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item H3 (`design/refactors/ARCHITECTURE_ROADMAP.md` §H). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The F15 two-phase boss is special-cased in rules code. The trigger is a profile-id string, the phase-1 passive list copies EncounterTable, and phase 2's HP, deck, profile and passives are constants.

- **Trigger.** PhaseTransition.gd:29-30:
  ```gdscript
  static func should_transition(st: CombatState) -> bool:
  	return st._sovereign_phase == 1 and st.enemy_profile_id == "abyss_sovereign"
  ```
  CombatConfig.gd:27-28 documents the same coupling: "Also marks the encounter for PhaseTransition (abyss_sovereign)."
- **Phase-1 passives.** PhaseTransition.gd:24 `const SOVEREIGN_P1_PASSIVES: Array[String] = ["void_might", "abyssal_mandate", "dark_channeling", "champion_abyss_sovereign"]` is a copy of EncounterTable.gd:142. `_swap_passives` unapplies the constant (:105-106 `for p in SOVEREIGN_P1_PASSIVES: CombatSetup.unapply_passive(...)`), not `st.enemy_passives`, which is what setup registered (CombatState.gd:2338).
- **Phase-2 spec.** :18 `SOVEREIGN_P2_HP: int = 3000`, :19 `SOVEREIGN_P2_DECK_ID: String = "f15_p2"`, :20 `SOVEREIGN_P2_PROFILE: String = "abyss_sovereign_p2"`, :25 `SOVEREIGN_P2_PASSIVES`. Used at :50-51 (HP), :70-72 (deck and profile) and :107-109 (passives).
- **Two sources for the phase-2 profile.** The deck file's `f15_p2` entry carries `"ai_profile": "abyss_sovereign_p2"`, but PhaseTransition loads the cards with `EncounterDecks.get_deck` (:70) and never reads `get_deck_profile`. Task 047 records the same.

Today the copies agree, so nothing is broken. The F15 pool is `[f15_a]`, which has no `ai_profile` override, so live and sim both play `"abyss_sovereign"` and the transition fires.

### Latent

- **Edit entry 15's passives** and phase 2 silently keeps a newly added phase-1 passive registered, because the unapply loop reads the constant.
- **A variant profile for F15** (the mechanism fights 1–4 use: EncounterTable `variant_profiles` plus per-deck `ai_profile` overrides) never transitions, because the check compares one exact id. Its fight would end at phase 1's 0 HP as a win.
- **A second multi-phase encounter** needs new code in PhaseTransition.
- **A typo in a phase-2 passive id registers nothing, silently.** `apply_passive` returns on an unknown id (CombatSetup.gd:637-638). Once the list is data, a content test can catch it.

## Proposed fix

1. **EncounterTable entry 15** gets `"phase2": {"hp": 3000, "deck_id": "f15_p2", "ai_profile": "abyss_sovereign_p2", "passives": ["void_might", "abyss_awakened", "champion_abyss_sovereign"]}`. Move the PhaseTransition.gd:21-23 comment (why `champion_abyss_sovereign` sits in the phase-1 list) next to it.
   - Add `static func phase2_for_profile(profile_id: String) -> Dictionary` through `entry_for_profile` (:177), which already covers `variant_profiles`. Return `{}` when there is none.
2. **Carry the spec into the fight**, the same way the passives travel today (live from EnemyData, sim and replay from the profile):
   - EnemyData gains `@export var phase2: Dictionary = {}`; `EncounterTable.make_enemy` copies it (`duplicate(true)`).
   - CombatConfig gains `var enemy_phase2: Dictionary = {}`. `from_game_manager` copies `enemy.phase2` next to the passives (:56). `from_dict` uses `EncounterTable.phase2_for_profile(c.enemy_profile_id)` next to :85.
   - `CombatState.setup_combat` stores it as `enemy_phase2`, next to `enemy_passives` (:2338).
   - `TestHarness.build_state` accepts `enemy_phase2` and `enemy_profile` keys; list them in its header comment (:52-60).
3. **PhaseTransition.**
   - `should_transition`: `st._sovereign_phase == 1 and not st.enemy_phase2.is_empty()`.
   - `_do_transition` reads `hp`, `deck_id`, `ai_profile` and `passives` from `st.enemy_phase2`, with typed reads (`var hp: int = spec["hp"]`, `var passives: Array[String] = []` then `assign`).
   - `_swap_passives`: the old list is `st.enemy_passives`, the new list is the spec's. If task 067 has landed, keep its diff (unapply only old-not-in-new, apply only new-not-in-old). Otherwise unapply all of the old list and apply all of the new, as today.
   - Delete the five `SOVEREIGN_*` constants and the "Phase 2 configuration" block (:14-25). Don't touch `_clear_combat_state`; task 050 rewrites it.
4. **One source for the phase-2 profile:** the spec's `ai_profile`. In 047's content test, assert that `EncounterDecks.get_deck_profile(spec.deck_id)` is either "" or equal to the spec's `ai_profile`, so the two can't disagree.
5. **Content test.** Task 047 step 6 checks `PhaseTransition.SOVEREIGN_P2_DECK_ID`. Replace that with a loop over every EncounterTable entry that has a `phase2`:
   - `EncounterDecks.get_deck(deck_id)` is non-empty;
   - `ProfileRegistry.has_profile("enemy", ai_profile)`;
   - every passive id has a CombatSetup registry entry (or, once task 104 lands, is in its `DATA_ONLY_PASSIVES`);
   - `hp > 0`.

   If task 104 has landed, put this in ContentTests, and point 104's "a passive PhaseTransition swaps in" reachability rule at the `phase2` lists.
6. **Probes that key F15 on the profile id:** update task 050's F15 probe and task 067's `_as_counter_carries_over_phase_transition` (built from `PhaseTransition.SOVEREIGN_P1_PASSIVES`). They set `enemy_phase2` and read the phase-1 list from `EncounterTable.entry(15)["passives"]`.
7. **Docs.** ARCHITECTURE.md:117 (PhaseTransition row: reads the encounter's `phase2` spec through `state.enemy_phase2`), :100 (CombatConfig row: `enemy_phase2`) and :241 (EncounterTable paragraph). CombatConfig.gd:27-28 and the PhaseTransition header (:1-10). Renaming `_sovereign_phase` (read at CombatHandlers.gd:1864 and CombatSim.gd:349) is out of scope.

## Verification

- **Transition probe** in `debug/tests/TriggerHandlerTests.gd`, next to the Avatar probes (:1771):
  - Setup: `build_state` with `enemy_passives` = `EncounterTable.entry(15)["passives"]`, `enemy_phase2` = `EncounterTable.phase2_for_profile("abyss_sovereign")`, `enemy_profile` = `"abyss_sovereign"`. Call `PhaseTransition.attempt(state)`.
  - Assert it returns true; `enemy_hp == enemy_hp_max == spec.hp`; `enemy_passives == spec.passives`; `enemy_profile_id == spec.ai_profile`; `enemy_hand.size() == 5`, and every card in `enemy_hand` and `enemy_deck` has an id in `EncounterDecks.get_deck(spec.deck_id)`.
  - `trigger_manager.dump_order()` lists `on_enemy_turn_abyss_awakened` and no longer lists the abyssal_mandate or dark_channeling handlers. A second `attempt` returns false.
- **Unapplies what was registered.** A state with `enemy_passives = ["void_might", "abyssal_mandate"]` and a test spec `{"hp": 1000, "deck_id": "f15_p2", "ai_profile": "abyss_sovereign_p2", "passives": ["void_might"]}`. After the transition the abyssal_mandate handler is gone. Today's code can't express this case.
- **Negative.** A `feral_pack` state (no `phase2`): `attempt` returns false, and `enemy_hp`, `enemy_passives` and `enemy_profile_id` are unchanged.
- **Config.** `CombatConfig.from_dict(...)` for `"abyss_sovereign"` has a non-empty `enemy_phase2`, and for `"feral_pack"` an empty one. `EncounterTable.make_enemy(15).phase2 == EncounterTable.entry(15)["phase2"]`.
- The existing ScenarioTests `_f15_abyss_sovereign_phase_transition` (:300) still passes.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the same values move from constants into data. The seeded balance fingerprint (`BalanceSimBatch -- --act 4 --runs 200 --seed 7`, before and after; F15 is in Act 4) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Depends on: task 047 — moves `encounter_decks.json` into the repo, so `f15_p2` is readable in tests, and adds the content test this task rewrites (its step 6 names `PhaseTransition.SOVEREIGN_P2_DECK_ID`).
- Depends on: task 050 — rewrites `PhaseTransition._clear_combat_state` in the same file and adds an F15 probe keyed on `enemy_profile_id`, which this task updates.
- Related: task 067 — makes `_swap_passives` a diff of the two lists. Land it first if possible; its probe reads `SOVEREIGN_P1_PASSIVES`, which this task deletes.
- Related: task 071 (roadmap E1b) — swaps the `enemy_hp` / `enemy_hp_max` assignment order in `_do_transition` (:50-51); same lines, trivial rebase.
- Related: task 124 (roadmap H2) — adds `act` and `boss` keys to the same EncounterTable entries; independent.
- Related: task 104 (roadmap D1) — ContentTests and the passive reachability rule, which should read the `phase2` lists after this task.
- Related: task 095 (roadmap B2a) — owns the champion state reset that keeps `champion_abyss_sovereign` working across the swap.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item H3. Re-checked at `404b51c`. Added the deck file's ignored `ai_profile`, the silent unknown-passive return in `apply_passive`, and the probes in tasks 050 and 067 that must follow the change.

## Summary

_(filled in at /task-done)_
