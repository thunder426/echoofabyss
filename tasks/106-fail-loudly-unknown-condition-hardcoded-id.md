---
id: "106"
title: Fail loudly on unknown condition / hardcoded id / multiplier key / passive id / handler; fix _validate_spell_damage_schools
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item D3 (`design/refactors/ARCHITECTURE_ROADMAP.md` §D). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The engine's string dispatches fail open. A content typo changes gameplay without an error, or with a warning the gate ignores (`tools/run_checks.sh` fails only on `SCRIPT ERROR`, :46 and :60).

### Fail-open sites

- **Conditions.** ConditionResolver.gd:154-156:
  ```gdscript
  _:
  	push_warning("ConditionResolver: unknown condition '%s'" % cond)
  	return true
  ```
  A misspelled condition makes the gated effect always fire, which is worse than never firing. A `once_per_turn:` with no flag id only warns (:27).
- **Hardcoded ids.** `HardcodedEffects.resolve` (:36-70) has 13 arms and no `_:`; the match ends on the comment `# --- Seris Corruption Engine ---` (:70). An unknown id does nothing, silently.
- **Multiplier keys.** `EffectResolver._amount` (:622-668) ends in `_: base = step.amount` (:661). The empty key (no scaling) and an unknown key share that arm, so a typo silently drops the scaling.
- **Passive ids.** `CombatSetup.apply_passive` (:636-645) and `unapply_passive` (:647-652) start with `if not _REGISTRY.has(id):` / `return`. Five ids reach this legitimately, because GameManager, CardModRules or DeckBuilderScene handle them: talents `abyss_convergence` and `void_manifestation`, hero passives `void_imp_extra_copy`, `abyssal_commander` and `iron_legion`.
- **Handler names.** `apply_passive` binds `Callable(st._handlers, t["method"])` (:642). `TriggerManager.register` (:52-63) accepts any Callable, and `fire` skips it silently (:85 `if entry.handler.is_valid():`). A misspelled `"method"` registers a dead handler. The handler-order snapshot (`dump_order`, :91) would record the misspelled name rather than catch it.
- **Spell-cast passive.** `CombatHandlers._apply_spell_cast_passive` (:109-115) has one arm and no `_:`.
- **AI cast rules.** `CombatProfile.can_cast_spell`'s match ends in `_:` / `return true` (:356-357): an unknown `cast_if` kind always casts. Task 104 fixes the one unknown kind in content (MatriarchAggroProfile.gd:24).

### The spell damage-school validator

`_validate_spell_damage_schools` (CardDatabase.gd:3670-3698) is the only load-time content check:
- `var damaging_types := {"DAMAGE_MINION": true, "DAMAGE_HERO": true, "DAMAGE_ANY": true}` (:3671). There is no DAMAGE_ANY among the 45 EffectType values. The stale name is also in CLAUDE.md:43, design/DAMAGE_TYPE_SYSTEM.md:203 and the doc comment at CardDatabase.gd:3667.
- It walks only `c.effect_steps` (:3676), not the spell's `talent_overrides` steps. Latent: no spell override has a DAMAGE_* step today (void_bolt's `piercing_void` override, :2095-2103, is VOID_BOLT + VOID_MARK).
- It ignores VOID_BOLT and nested `attack_rider_steps`. Both are correct and only need a comment:
  - the VOID_BOLT arm never reads `step.damage_school`; CombatState hardcodes `Enums.DamageSchool.VOID_BOLT` (:980, :1000);
  - rider steps resolve with `ectx.source = attacker` (CombatHandlers.gd:462), so they are minion-emitted, where CLAUDE.md allows `NONE`.

### What stays silent

The board-passive dispatchers can't take a `_:` arm. `on_summon_board_synergies` (:186-191) and `on_player_minion_died_board_passives` (:761-765) pass every non-empty `passive_effect_id` on the board to `_apply_board_passive_on_summon` (:609) or `_apply_board_passive_on_death` (:785). Each of those sees the other's ids, so a `push_error` default would fire on valid content. Task 104's `BOARD_PASSIVE_IDS` check covers them statically, and task 089 retires that dispatch.

### Reach

Today's content reaches none of the new error arms. Task 104's prototype found 0 unknown conditions, multiplier keys, hardcoded ids, registry methods or passive ids. This task is behaviour-neutral; it turns the next typo into an error.

## Proposed fix

1. **ConditionResolver.** The `_:` arm calls `push_error("ConditionResolver: unknown condition '%s'" % cond)` and returns `false`. The empty `once_per_turn:` id also uses `push_error`. If task 108 has landed, this is the unknown-name arm of its condition table; keep one arm.
2. **HardcodedEffects.resolve.** Add `_: push_error("HardcodedEffects: unknown id '%s'" % id)`.
3. **EffectResolver._amount.** Add an explicit `"": base = step.amount` arm. The `_:` arm calls `push_error` with the key and keeps `base = step.amount`.
4. **TriggerManager.register.** `if not handler.is_valid():` → `push_error` naming the method and the event, and `return` without registering. Keep the `is_valid()` skip in `fire()`, which protects against freed objects.
5. **CombatSetup.** `apply_passive` and `unapply_passive`: an id with no registry entry calls `push_error`, unless it is in task 104's `CombatSetup.DATA_ONLY_PASSIVES` (the 5 ids above).
6. **CombatHandlers._apply_spell_cast_passive.** Add `_:` with `push_error`. It is a single-namespace dispatcher. Do not add `_:` to `_apply_board_passive_on_summon` or `_apply_board_passive_on_death` (see above).
7. **CombatProfile.can_cast_spell.** The `_:` arm calls `push_error` with the profile, spell id and kind, and keeps `return true`.
8. **`_validate_spell_damage_schools`.**
   - Drop `DAMAGE_ANY`.
   - Also walk each spell's `talent_overrides` `effect_steps`, and name the override's `talent_id` in the offender text.
   - Comment why VOID_BOLT and `attack_rider_steps` are exempt (the reasons above).
   - Extract `_spell_damage_school_offenders(cards: Array) -> Array[String]` so a test can call it; the caller keeps the `push_error` + `assert`.
   - If task 105 has landed, the validator already reads EffectStep fields; keep that.
9. **Docs.** Remove DAMAGE_ANY from CLAUDE.md:43 (step 6 of "Adding New Cards"), design/DAMAGE_TYPE_SYSTEM.md:203 and the comment at CardDatabase.gd:3667.

## Verification

- New probes in `debug/tests/TriggerHandlerTests.gd` (engine behaviour, not content, so not ContentTests):
  1. `ConditionResolver.check("no_such_condition", EffectContext.make(state, "player"), null) == false`.
  2. `state._hardcoded.resolve("no_such_id", ctx)` leaves `state.digest_text()` unchanged.
  3. An EffectStep built directly (`EffectStep.make(EffectStep.EffectType.DAMAGE_HERO, EffectStep.TargetScope.NONE, 100)` with `multiplier_key = "no_such_key"` and an ARCANE school) lowers the enemy hero's HP by exactly 100. Build the step object, not a dict: after task 105 a dict with that key fails at parse.
  4. `CombatSetup.apply_passive("no_such_passive", state)` leaves `state.trigger_manager.dump_order()` unchanged.
  5. `state.trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TURN_START, Callable(state._handlers, "no_such_method"), 0)` adds no entry (`dump_order()` unchanged).
  6. `_spell_damage_school_offenders` on a synthetic SpellCardData whose `talent_overrides` hold a DAMAGE_MINION step without a school returns 1 offender. On the real database it returns 0.
  7. Build one state per DATA_ONLY id (passed as a talent or hero passive to `TestHarness.build_state`). The probe can't assert on printed output, so check the RunAllTests log for the new `CombatSetup` unknown-passive error: it must not appear.
- Read the RunAllTests log: the negative probes print `ERROR:` lines from `push_error`, and no `SCRIPT ERROR`, so the gate stays green. If Godot 4.6 prints them differently, adjust the probes (or the gate's grep) before landing.
- The handler-order snapshot (`debug/tests/snapshots/handler_order.txt`) is unchanged.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1–4) diffs empty (design/TESTING.md 'Refactor / extraction work').

## Related

- Depends on: task 104 (roadmap D1) — proves today's content reaches no new error arm, and adds `DATA_ONLY_PASSIVES` and the MatriarchAggro `cast_if` fix this task relies on.
- Related: task 105 (roadmap D2) — its load-time validator makes these arms unreachable for content and migrates `_validate_spell_damage_schools` to EffectStep fields.
- Related: task 108 (roadmap D7) — its condition table owns the unknown-condition arm; whichever lands second keeps `push_error` + `false`.
- Related: task 089 (roadmap A8) — retires the board-passive dispatch that can't take a `_:` arm.
- Related: task 081 (roadmap DL1) — deletes the unreachable `spirit_conscription` / `champion_duel` entries and the dead `void_mark_on_void_imp_death` arm.
- Related: task 079 — edits CLAUDE.md "Adding New Cards" step 1; this task edits step 6. Whichever lands second rebases.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item D3.
  - Re-check: the roadmap's "ignores VOID_BOLT and nested attack_rider_steps" is by design; only the DAMAGE_ANY name and the override steps need fixing.
  - The board-passive dispatchers can't fail loudly; added the spell-cast passive dispatcher, `TriggerManager.register` and the AI `cast_if` default.

## Summary

_(filled in at /task-done)_
