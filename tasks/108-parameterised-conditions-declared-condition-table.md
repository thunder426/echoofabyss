---
id: "108"
title: Parameterised conditions with a declared condition table
status: backlog
area: combat
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item D7 (`design/refactors/ARCHITECTURE_ROADMAP.md` §D). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### One name per threshold, race and side

`ConditionResolver.check` (:18-156) is one flat `match cond:` with 33 named arms, plus the `once_per_turn:<id>` prefix (:24-33). An unknown name warns and returns `true` (:154-156; task 106 makes it fail loudly).
- **10 names bake in a threshold:** `flesh_gte_1/2/3` and `flesh_lt_2/3` (:101-115), `owner_runes_gte_2` / `not_owner_runes_gte_2` (:66-83), `feral_imp_count_gte_3` (:84-93), `void_marks_5plus` (:96), `friendly_grafted_fiend_kill_stacks_gte_3` (:122-129).
- **Races repeat per name:** `is_demon` / `is_human` / `is_spirit` / `is_beast` (:36-43), `dead_is_demon` / `dead_is_human` (:132-135), `rally_race_human` / `rally_race_demon` (:149-152).
- **Negation pairs:** `has_friendly_human` / `not_has_friendly_human`, `owner_runes_gte_2` / `not_owner_runes_gte_2`, and Flesh Rune's `flesh_gte_2` / `flesh_lt_2` (CardDatabase.gd:1098, :1100).

Each new threshold, race or tag needs a new arm.

### What content uses

Non-test content uses 14 of the 33 arms, 31 times, plus `once_per_turn:imp_evolution` (CardModRules.gd:104):

| Condition | Uses | Cards |
|---|---|---|
| `flesh_spent_this_cast` | 14 | Seris "Spend N" cards |
| `rally_race_human`, `rally_race_demon` | 2 + 2 | rally_the_ranks (:622-625) |
| `has_friendly_human` | 2 | void_summoning (:1574), void_execution (:1588) |
| `not_has_friendly_human` | 1 | void_summoning (:1573) |
| `flesh_gte_3` | 1 | flesh_rend (:537) |
| `flesh_gte_2`, `flesh_lt_2` | 1 + 1 | flesh_rune (:1100, :1098) |
| `friendly_grafted_fiend_kill_stacks_gte_3` | 1 | flesh_scout (:1149) |
| `is_demon` | 1 | dark_empowerment (:1532) |
| `dead_is_demon` | 1 | abyssal_summoning_circle (:2415) |
| `owner_runes_gte_2`, `not_owner_runes_gte_2` | 1 + 1 | runic_blast (:2550, :2552) |
| `feral_imp_count_gte_3` | 1 | void_screech (:2809) |

The other 19 arms are unused by content: `is_human`, `is_spirit`, `is_beast`, `is_void_imp`, `is_corrupted`, `not_self`, `board_not_full`, `board_empty`, `no_active_traps`, `has_active_environment`, `has_friendly_demon`, `void_marks_5plus`, `has_void_marks`, `flesh_gte_1`, `flesh_lt_3`, `dead_is_human`, `dead_is_void_imp`, `enemy_turn`, `player_turn`. The last two appear only in TriggerHandlerTests.gd:3329 and :3332. (`board_not_full` in `enemies/ai/` is an AI `cast_if` kind, a different vocabulary.)

### Side-fixed arms

Several arms read one side's fields whatever `ctx.owner` is:
- :53 `return ctx.state.has_empty_slot("player")` (`board_not_full`);
- :55 `ctx.state.player_board.is_empty()`, :57 `ctx.state.active_traps.is_empty()`, :59 `ctx.state.active_environment != null`;
- :97 and :99 `ctx.state.enemy_void_marks`;
- the five Flesh arms: `var f2 = ctx.state.player_flesh if ctx.owner == "player" else 0` (:102-114), so an enemy-owned Flesh condition always sees 0.

All but the Flesh arms are unused by content, so this is latent. Under the owner's ruling it is still an engine asymmetry: an enemy- or PvP-owned card using them would read the wrong side.

### once_per_turn is shared and consumed inside `check`

- The flags live in one dict, `_once_per_turn_used` (CombatState.gd:1705), not keyed by side, and cleared only at the player's turn start (:2436).
- `check` consumes the flag itself (:29-32), so every caller that checks a `once_per_turn:` condition consumes it:
  - HandDisplay.gd:270 checks `bonus_conditions` for the hand glow;
  - EffectResolver checks `conditions` once per target (:430) and `bonus_conditions` once per target through `_amount` (:432 → :664).
- Latent: the only use is an ADD_CARD step's `conditions` (a global arm, checked once). On a multi-target step only the first target would pass; in `bonus_conditions`, hovering the card would use up the gate.

## Decision (owner, 2026-10-01)

Q2: no mechanic is one-sided by design. "Who has what is decided by data and config, never by `if owner == "player"` in rules code." So every condition is relative to `ctx.owner`, and no arm names a side.

## Proposed fix

1. **Syntax.** Conditions stay strings in the existing `Array[String]` fields (`conditions`, `bonus_conditions`), in the form `name[:arg[:arg]]`, the way `once_per_turn:<id>` already works. A `not:` prefix negates. (The roadmap sketched `{"flesh_gte": 2}` dicts; strings keep the field type and the existing form.)
2. **Declared table.** `const SPECS := {name: [arg kinds]}` in ConditionResolver, with arg kinds `int`, `race` (lower-case MinionType name), `tag` (a minion tag) and `id`. Each generic arm keeps the body of the arm it replaces, made owner-relative:

   | Spec | True when (relative to `ctx.owner`) | Replaces |
   |---|---|---|
   | `flesh_spent_this_cast` | a SPEND_FLESH step in this run spent ≥1 | itself |
   | `flesh_gte:N` | the owner's Flesh ≥ N | `flesh_gte_1/2/3`; `flesh_lt_2/3` become `not:flesh_gte:N` |
   | `has_friendly_race:R` | the owner's board has a minion of race R | `has_friendly_human`, `not_has_friendly_human`, `has_friendly_demon` |
   | `is_race:R` | the target minion is race R | `is_demon`, `is_human`, `is_spirit`, `is_beast` |
   | `dead_is_race:R` | the dead minion is race R | `dead_is_demon`, `dead_is_human` |
   | `owner_runes_gte:N` | the owner has ≥ N runes | `owner_runes_gte_2` and its `not_` twin |
   | `friendly_tag_count_gte:T:N` | ≥ N of the owner's minions have tag T | `feral_imp_count_gte_3` |
   | `friendly_tag_kill_stacks_gte:T:N` | the owner's minions with tag T have ≥ N kill stacks in total | `friendly_grafted_fiend_kill_stacks_gte_3` |
   | `rally_race:R` | the cast-time rally race pick is R | `rally_race_human`, `rally_race_demon` |
   | `opponent_void_marks_gte:N` | the owner's opponent has ≥ N Void Marks | `void_marks_5plus` (N = 5), `has_void_marks` (N = 1) |
   | `once_per_turn:ID` | the first check this turn of the owner's flag ID | itself, now per side |

   Deleted, because no content uses them and no generic form covers them: `is_void_imp`, `is_corrupted`, `not_self`, `board_not_full`, `board_empty`, `no_active_traps`, `has_active_environment`, `dead_is_void_imp`, `player_turn`, `enemy_turn`. Re-adding one later is one owner-relative table row.

   The two Void Mark conditions are kept (parameterised, not deleted) because task 092 makes them owner-relative and probes them; this task only renames them.
3. **Dispatch.** `check(cond, ctx, target)` strips a leading `not:`, splits on `:`, looks the name up in SPECS and dispatches with typed args. The parse is a pure function of the string, so a static cache keyed by the string is safe across states. Once task 105 has landed, conditions can be parsed at load instead.
4. **Owner-relative reads.**
   - Flesh goes through one engine accessor, e.g. `CombatState.flesh_of(side)`: `player_flesh` for the player, 0 for the enemy until task 097 gives each side its Flesh. The side branch then lives in the engine accessor, not in ConditionResolver.
   - Rune, board and tag counts already use `traps_of(ctx.owner)` and `_friendly_board(ctx.owner)`; keep them.
   - Void Marks read task 092's `void_marks_of(opponent of ctx.owner)`. If 092 hasn't landed, add that accessor the way `flesh_of` is added (`enemy_void_marks` for the enemy side, 0 for the player); 092 then moves it onto SideState.
   - `once_per_turn`: key the flags by side (`_once_per_turn_used[side][id]`) and clear a side's flags at that side's turn start, not only the player's (CombatState.gd:2436). Only player content uses the gate today, so this is neutral.
5. **Validation.** `static func validate(cond: String) -> String` returns `""` or an error: unknown name, wrong arity, a non-int threshold, an unknown race or tag. At runtime an unknown name calls `push_error` and returns `false` (the arm task 106 adds; whichever lands second keeps one arm). Task 105's step validator and task 104's ContentTests call `validate()` instead of keeping a name list; task 104's L14 compares `SPECS` keys with the dispatch arms instead of `KNOWN_CONDITIONS`.
6. **Migrate content** (14 names, 31 uses in CardDatabase.gd):
   - `flesh_gte_3` → `flesh_gte:3`; `flesh_gte_2` → `flesh_gte:2`; `flesh_lt_2` → `not:flesh_gte:2`;
   - `has_friendly_human` → `has_friendly_race:human`; `not_has_friendly_human` → `not:has_friendly_race:human`;
   - `is_demon` → `is_race:demon`; `dead_is_demon` → `dead_is_race:demon`;
   - `owner_runes_gte_2` → `owner_runes_gte:2`; `not_owner_runes_gte_2` → `not:owner_runes_gte:2`;
   - `feral_imp_count_gte_3` → `friendly_tag_count_gte:feral_imp:3`;
   - `friendly_grafted_fiend_kill_stacks_gte_3` → `friendly_tag_kill_stacks_gte:grafted_fiend:3`;
   - `rally_race_human` / `rally_race_demon` → `rally_race:human` / `rally_race:demon`;
   - `flesh_spent_this_cast` and `once_per_turn:imp_evolution` are unchanged.
7. **Delete the 33 old arms.** TriggerHandlerTests `_state_turn_flag_drives_turn_conditions` (:3322-3333) keeps its `is_player_turn` asserts and drops the two `player_turn` / `enemy_turn` condition asserts.
8. **Pure `check` (latent; neutral today).** `check` no longer consumes. The resolver consumes a step's `once_per_turn:` gates once per step, before target resolution, on both the global and the targeted path. HandDisplay's glow check (:270) and `_amount`'s per-target bonus check (:664) never consume.
9. **Docs.** The ConditionResolver header, ARCHITECTURE.md's ConditionResolver row, and the `once_per_turn` comments in CombatState (:1700-1705) and CardModRules.

## Verification

- Existing probes cover both branches of runic_blast, void_screech, dark_empowerment, void_summoning and flesh_rend (CardEffectTests.gd:36-62), rally_the_ranks, and the imp_evolution once-per-turn gate (TriggerHandlerTests). They stay green.
- New probes in `debug/tests/CardEffectTests.gd`, added first and passing before the migration:
  - `_flesh_rune_upkeep`: put `flesh_rune` in `state.active_traps`. Run its `aura_effect_steps` with `EffectContext.make(state, "player")`, `from_rune = true` and `source_rune = rune`. With 1 Flesh: the rune is gone, Flesh is still 1, no Void Spark. With 2 Flesh: Flesh is 0, a 300/300 Void Spark is on the player board, the rune stays.
  - `_flesh_scout_kill_stacks`: friendly Grafted Fiends with 2 vs 3 total kill stacks; run `flesh_scout`'s `on_play_effect_steps`; the hand grows by 0 vs 2.
  - `_abyssal_summoning_circle_dead_race`: run its `on_player_minion_died_steps` with `ctx.dead_minion` a Demon vs a Human; the enemy hero loses 200 vs 0.
  - `_void_execution_human_bonus`: 500 vs 700 damage to the chosen enemy minion without / with a friendly Human.
- New unit probes in `debug/tests/TriggerHandlerTests.gd`:
  - `validate("flesh_gte:2")` and `validate("not:has_friendly_race:human")` return `""`. `flesh_gte:x`, `flesh_gtee:2`, `has_friendly_race:dragon` and `friendly_tag_count_gte:feral_imp` (missing arg) return errors.
  - `check("flesh_gte:1", ...)` with an enemy ctx is false (enemy Flesh is 0 today).
  - `once_per_turn:x` consumed by an enemy ctx doesn't block a player ctx's `once_per_turn:x`.
  - With 5 enemy Void Marks, `check("opponent_void_marks_gte:5", ...)` is true for a player ctx and false with 4. If task 092 has landed, its `void_marks_5plus` / `has_void_marks` probe switches to the new names.
- Every condition string in content passes `validate()`: in ContentTests if task 104 has landed, otherwise a CardEffectTests probe over `get_all_card_ids()` and `CardModRules.RULES`.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1–4) diffs empty (design/TESTING.md 'Refactor / extraction work').

## Related

- Related: task 106 (roadmap D3) — the unknown-condition arm (`push_error` + `false`); whichever lands second keeps one arm.
- Related: task 104 (roadmap D1) — its `KNOWN_CONDITIONS` const and L14 const-vs-arms check switch to `SPECS`.
- Related: task 105 (roadmap D2) — its step validator calls `validate()`; with it, conditions can be parsed at load.
- Related: task 097 (roadmap B3) — per-side Flesh; `flesh_of(side)` then reads the side's module.
- Related: task 082 (roadmap A0) — its verdict table lists the side-fixed condition arms (row 30); this task removes them, except the two Void Mark conditions, which task 092 fixes and this task renames.
- Related: task 092 (roadmap PS-void-marks) — makes `void_marks_5plus` / `has_void_marks` read the caster's opponent through `void_marks_of`; this task parameterises them as `opponent_void_marks_gte:N` on that accessor.
- Related: task 087 (roadmap A4) — the side-literal lint ratchet (L16) loses ConditionResolver's literals.
- Related: task 050 — fixes Flesh Rune's SOURCE_RUNE destroy for the enemy side; the new Flesh Rune probe is player-side and passes either way.
- Related: task 102 (roadmap C3) — moves the cards into per-pool files; the migrated strings move with them.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item D7.
  - Re-check: 33 named conditions, not ~35; only 10 bake a threshold; 19 are unused by content.
  - Added from the Q2 ruling: owner-relative Flesh, per-side `once_per_turn`, and the side-fixed arms deleted rather than kept.

## Summary

_(filled in at /task-done)_
