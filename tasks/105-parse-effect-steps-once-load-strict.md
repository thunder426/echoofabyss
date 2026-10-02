---
id: "105"
title: Parse effect steps once at load with a strict validator; EffectStep everywhere
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item D2 (`design/refactors/ARCHITECTURE_ROADMAP.md` §D). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### Steps are dictionaries, parsed on every use

- Step fields are untyped arrays of dict literals, e.g. SpellCardData.gd:19 `@export var effect_steps: Array = []`. All 225 content steps are dicts: 215 in CardDatabase, 7 in CardModRules, 3 in TalentDatabase. No content builds EffectStep objects.
- `EffectResolver.run` builds a new EffectStep Resource for every step on every resolution (EffectResolver.gd:18-24):
  ```gdscript
  for raw in steps:
  	var step: EffectStep
  	if raw is Dictionary:
  		step = EffectStep.from_dict(raw)
  	elif raw is EffectStep:
  		step = raw
  ```
  That is an allocation per step on the sim's hottest path.
- 10 more sites parse with `EffectStep.from_dict(raw) if raw is Dictionary else raw as EffectStep`: CombatState.gd:552 (`cast_player_hero_spell`), HandDisplay.gd:267 (hand glow), BoardEvaluator.gd:136, :252, :278, CombatProfile.gd:390, :483, :706, :766, :1156.
- `from_dict` (EffectStep.gd:261-315) has 37 `if "x" in d:` checks and no branch for unknown keys, so a misspelled key is silently dropped. A misspelled enum name (`EffectType[d["type"]]`, :263) errors, but only the first time that step resolves. `attack_rider_steps` stay raw dicts (:303-306).
- Steps also come from outside the card fields: `CardModRules.RULES` append payloads (a const; 5 rules, 7 steps), `talent_overrides` `*_steps` payloads, the Abyss Convergence grand ritual (TalentDatabase.gd:175-179), nested `attack_rider_steps`, and test-built cards (`TestHarness.make_test_spell`, TestHarness.gd:235, 18 call sites, plus direct assignments in the tests).

Nothing mutates steps at runtime:
- no writes to step-dict keys outside content (the only hits are deck dicts in EncounterDecks.gd);
- no writes to EffectStep fields outside EffectStep.gd and tests;
- `digest_text` serializes no steps.

So parsing once at load is byte-identical with a fixed seed, provided the readers below move in the same change.

### Readers that handle only Dictionaries

A naive parse-once breaks these:

1. **CombatInputHandler.gd:143** `for step: Dictionary in spell.effect_steps:`, in `start_pip_blink_for_card`, which runs on every spell hover. An EffectStep element in a typed loop variable is a runtime error, so every spell hover would print a SCRIPT ERROR.
2. **CombatProfile.gd:362 / :364** `if (step as Dictionary).get("type", "") == "SUMMON":`, in `_spell_needs_board_slot`. Base `can_cast_spell` calls it first (:305), for every AI spell, so every AI cast check would error.
3. **CombatHandlers.gd:477** `var d: Dictionary = raw if raw is Dictionary else {}`, in the attack-rider hero-defender path. With an EffectStep, `t` is `""`, the arm push_warnings, and Banner of the Order's 100 Armour Break on a hero silently stops. The existing probe `_banner_rider_fires_on_attack_post` (CardEffectTests.gd:1440) uses a minion defender only, and Parity's Korrath preset has no Banner.
4. **BoardSlot.gd:932** `var step_type: String = raw.get("type", "") if raw is Dictionary else ""`, in the on-death tooltip fallback. An EffectStep reads as `""`, which is not `"HARDCODED"`, so a HARDCODED-only on-death step would gain a "Triggers an effect on death." line. Latent: no card has one today.
5. **CardDatabase.gd:3678** `var step: Dictionary = steps[i]`, in `_validate_spell_damage_schools`. It errors if it runs after parsing.

Three more readers handle both shapes and can drop the dict branch: `_harvest_aura_source_tags` (CombatState.gd:360-370), `_step_source_tag` (CombatHandlers.gd:1085-1090) and `_spell_deals_damage` (CombatHandlers.gd:1997-2006).

### Latent gaps a validator would close

- `GRANT_KEYWORD` handles only GUARD, LIFEDRAIN and DEATHLESS (EffectResolver.gd:567-578, no default arm). Any other keyword silently does nothing. Content uses GUARD twice and DEATHLESS once.
- Four EffectStep fields are set by no content (`card_race`, `card_tag`, `purge_filter`, `token_shield`), and 4 TargetScopes are unused (`FILTERED_RANDOM`, `ALL_BOARD`, `DEAD_MINION`, `SINGLE_RANDOM_TRAP`). Nothing to fix; the validator still checks them if content starts using them.

## Proposed fix

Two commits.

### Commit 1: parse once (behaviour-neutral)

1. Add `static func parse_steps(arr: Array, where: String) -> Array` to EffectStep. A Dictionary goes through `from_dict` (and `attack_rider_steps` are parsed recursively); an EffectStep passes through.
2. **CardDatabase.** After `all` is complete and pools are assigned (CardDatabase.gd:3646-3658), and before `_register` and `_validate_spell_damage_schools`, replace every step array with its parsed form. Use an explicit per-class field list in CardDatabase, not property reflection:
   - MinionCardData: the 10 `*_steps` fields (MinionCardData.gd:91-179);
   - SpellCardData: `effect_steps`;
   - TrapCardData: `effect_steps`, `aura_effect_steps`, `aura_secondary_steps`, `aura_on_place_steps`, `aura_on_remove_steps`;
   - EnvironmentCardData: `passive_effect_steps`, `on_enter_effect_steps`, `on_replace_effect_steps`, `on_player_minion_died_steps`, and each `rituals[].effect_steps`;
   - every `talent_overrides` entry field whose name ends in `_steps`.

   Keep the fields typed `Array` for now. `get_card_for_combat`'s override copy is safe: `_deep_copy` (:241-252) returns Resources unchanged, and nothing mutates a parsed step, so base and clone can share them.
3. **CardModRules.** `RULES` is a const, so keep a static cache of each rule's parsed `append_*_steps` (and any `set_*_steps`) payload. Append those in `get_card_for_combat`'s append path (CardDatabase.gd:218-221) instead of `_deep_copy`'d dicts.
4. **TalentDatabase.** Parse `grand_r.effect_steps` at registration (TalentDatabase.gd:175).
5. **Tests.** Test-built cards hold dict steps that bypass CardDatabase: `TestHarness.make_test_spell` (18 callers) and direct field assignments such as TriggerHandlerTests.gd:2033 `utility.effect_steps = [{"type": "DRAW", "amount": 1}]`, :3421, CommandTests.gd:391 and :396, LiveSmokeTests.gd:128 (21 literals in all). Once readers are reduced to `raw as EffectStep` (step 7), those dicts would break them; :2033 is the `_spell_deals_damage` probe itself. `make_test_spell` parses its steps, and the direct assignments go through `EffectStep.parse_steps` (or a small `TestHarness.steps([...])` helper). `EffectResolver.run` keeps its Dictionary branch as a test-only fallback, routed through `parse_steps`. DamageTypeTests already builds EffectStep objects (`EffectStep.make`, :254).
6. **Migrate the 5 Dictionary-only readers** to EffectStep fields:
   - CombatInputHandler.gd:143-148: `effect_type == CONVERT_RESOURCE`, `step.amount`, `step.convert_from`, `step.convert_to`. Task 065 rewrites the same preview arithmetic; whichever lands second rebases.
   - CombatProfile `_spell_needs_board_slot` (:360-368): `effect_type` SUMMON, or HARDCODED with `hardcoded_id == "brood_call"` (task 081 drops the stale `void_summoning` id; keep whatever list is there).
   - CombatHandlers.gd:476-485: read `(raw as EffectStep)`; the tag is `step.source_tag` when non-empty, else the rider's `source_tag`.
   - BoardSlot.gd:932: `(raw as EffectStep).effect_type != EffectStep.EffectType.HARDCODED`.
   - `_validate_spell_damage_schools`: read `effect_type` and the int `damage_school` from the EffectStep. Task 106 owns its coverage changes (drop DAMAGE_ANY, walk override steps).
7. Reduce the 3 dual readers and the 10 parse sites above to `raw as EffectStep`. BoardEvaluator's three sites stay in scope: task 120 keeps BoardEvaluator (owner decision Q7a).

### Commit 2: strict validator

8. Add `static func validate_dict(d: Dictionary, where: String) -> PackedStringArray` to EffectStep. It reports:
   - unknown keys (against `EffectStep.DICT_KEYS`; task 104 adds that const, add it here if 104 hasn't landed);
   - unknown enum names: `type`, `scope`, `filter`, `keyword`, a string `damage_school`, `purge_filter` (Enums.BuffType), `card_race` (Enums.MinionType);
   - wrong value types (`amount` int, `permanent` bool, `conditions` an array of strings, …);
   - closed-set strings: `multiplier_key` ∈ {"", rune_aura, void_marks, flesh_spent, board_count, armour_sum}; `multiplier_board` ∈ {"", friendly, enemy}; `multiplier_filter` ∈ {"", tag, race}; `tutor_filter` ∈ {spark_cost, rune}; `resource`, `convert_from`, `convert_to` ∈ {mana, essence}; `adjacent_side` ∈ {left, right}; `attack_rider_scope` == attack_target;
   - a GRANT_KEYWORD `keyword` other than GUARD, LIFEDRAIN or DEATHLESS;
   - unknown condition names, through ConditionResolver's declared set (task 104's `KNOWN_CONDITIONS`, or task 108's `validate()` once it exists);
   - `card_id` / `exclude_card_id` not in CardDatabase's own `_cards` (same autoload, so no load-order problem);
   - per-type required fields, starting with the ones all content already satisfies (SUMMON / ADD_CARD need `card_id`, HARDCODED needs `hardcoded_id`, GRANT_KEYWORD needs `keyword`). CONVERT_RESOURCE's `amount` becomes required once task 065 has given Energy Conversion one.

   Where task 104's consts exist (`EffectResolver.MULTIPLIER_KEYS`, `HardcodedEffects.IDS`), use them instead of a second copy. Recurse into `attack_rider_steps`.
9. `parse_steps` calls `validate_dict`. On errors it calls `push_error` with the card id, field and step index, then `assert(false, msg)`, the same pattern as `_validate_spell_damage_schools` (CardDatabase.gd:3696-3698). Every scene the gate runs (RunAllTests, LiveSmoke, Parity) then prints a SCRIPT ERROR at load.
10. If task 104 has landed, delete its ContentTests step-shape checks (keys, enum values, closed-set strings), which this validator now covers at load. Keep its cross-database checks (talent ids, tags, AI rules).
11. Docs: ARCHITECTURE.md's `EffectStep.gd` row ("Serializable from dict." → "parsed and validated once at load"); CLAUDE.md "Adding New Cards" (steps are validated at load).

## Verification

- New probes in `debug/tests/CardEffectTests.gd`. Add them in commit 1 and make sure they pass before the parse change:
  - `_banner_rider_hits_hero`: `TestHarness.korrath_state()`, `spawn_friendly(state, "void_imp")`, run `banner_of_the_order`'s `effect_steps`, then `TestHarness.fire(state, ON_PLAYER_ATTACK_POST, "player", {"minion": demon, "attacker": demon, "defender": "enemy_hero"})`. Assert `BuffSystem.sum_type(state.enemy_hero, Enums.BuffType.ARMOUR_BREAK) == 100`.
  - `_ai_summon_spell_needs_slot`: an enemy profile (`ProfileRegistry.make("enemy", "default")` on `TestHarness.agent_for(state, "enemy")`) with a full enemy board: `can_cast_spell` on `void_summoning` (SUMMON steps) is false. With two empty slots it is true (the champion reservation holds at most one slot).
  - `_all_content_steps_are_parsed` (commit 1): for every card id, every step-array field, every env ritual, nested `attack_rider_steps` and `talent_overrides` `*_steps` payload holds only EffectStep. The same for `get_card_for_combat("void_imp", {"talents": ["imp_evolution", "rune_caller"]}).on_play_effect_steps` (CardModRules appends) and for `abyss_convergence`'s grand ritual.
  - `_strict_step_validation` (commit 2): `validate_dict` reports errors for `{"type": "DAMAGE_HERO", "amout": 100}` (naming `amout`), an unknown type name, `multiplier_key` `"void_mark"` and GRANT_KEYWORD with keyword SWIFT. It reports none for any content step.
- LiveSmoke: call `input_handler.start_pip_blink_for_card` on `flux_siphon` and on a damage spell. No SCRIPT ERROR.
- Mutation (local, reverted): misspell one key in a CardDatabase step; `tools/run_checks.sh` fails at load with the card id and step index.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1–4) diffs empty (design/TESTING.md 'Refactor / extraction work'). Also record the batch wall time before and after (fewer allocations).

## Related

- Related: task 104 (roadmap D1) — whichever lands first, this task's load-time validator owns the step-shape checks and 104's ContentTests keeps the cross-database checks. 104 adds `EffectStep.DICT_KEYS` and the vocabulary consts this validator reuses.
- Related: task 106 (roadmap D3) — makes the runtime dispatchers fail loudly. This validator makes those arms unreachable for content; 106 also rewrites `_validate_spell_damage_schools`' coverage.
- Related: task 107 (roadmap D4) — depends on this task; its handlers take a typed EffectStep only.
- Related: task 108 (roadmap D7) — its `ConditionResolver.validate()` is what this validator calls for condition names.
- Related: task 065 — rewrites the CombatInputHandler conversion preview (reader 1) and gives Energy Conversion an `amount`; whichever lands second rebases.
- Related: task 081 (roadmap DL1) — removes the stale `void_summoning` id from `_spell_needs_board_slot` (reader 2).
- Related: task 079, task 106 (roadmap D3) and task 102 (roadmap C3) — also edit CLAUDE.md's "Adding New Cards" list that step 11 touches (079 step 1, 106 step 6, 102 step 2). Whichever lands later rebases.
- Related: task 120 (roadmap G4) — keeps BoardEvaluator, so its three parse sites are migrated here, not deleted.
- Related: task 102 (roadmap C3) — splits CardDatabase per pool; the parse pass must run over every pool file's cards. After 102, `abyssal_knight`'s `unbreakable` override is built with `merged()` and shares its `formation_effect_steps` array with `iron_formation`: step 2 must assign new parsed arrays, never convert a step array in place.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item D2.
  - The unit found 5 Dictionary-only readers and 3 dual readers the roadmap didn't list; a parse-once without migrating them changes behaviour (spell-hover errors, AI cast-check errors, Banner's hero Armour Break dropped).
  - Parse sites: 1 resolver + 10 others (2 non-AI: CombatState, HandDisplay), not "8 in AI scoring" only.

## Summary

_(filled in at /task-done)_
