---
id: "140"
title: Harden the engine lint: L8 compound writes and a derived file list incl. CombatScene; L10 widened; escaped quotes; L7/L6 gaps
status: backlog
area: tooling
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item J4, plus a new finding from verifying it (J7: CombatScene writes engine flags) (`design/refactors/ARCHITECTURE_ROADMAP.md` §J). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The gate relies on `tools/lint/lint_engine.py`, and the lint is only as strong as its regexes. Most gaps are latent: no file in today's scan sets has a compound write, a mutator call on state, a state alias or a problem escaped quote. But L8's file list already hides real engine writes in CombatScene.

### L8: presentation never mutates

- **The pattern** (lint_engine.py:293-295) is `\bstate\.\w+\s*=[^=]` plus the board / `current_health` alternatives. It misses:
  - compound writes (`state.player_essence += 1`);
  - nested and indexed writes (`state.x.y =`, `state.x[i] =`);
  - mutator calls on any state array other than the two boards (`state.player_hand.append(…)`).
- **The file list** (:286-292) is three globs plus 8 hand-named board files. Not scanned: CombatScene.gd, CombatLog.gd, ViewState.gd, VoidBoltProjectile.gd, RitualProjectile.gd, ScreenShakeEffect.gd, AbyssalPlagueParticles.gd, BuffVfxRegistry.gd and SacrificeVfxRegistry.gd.
- **The widened pattern on CombatScene.gd finds:**
  - `_apply_test_config` (:1031-1095): 11 field writes and 2 trap appends (:1063, :1071). Debug-only; task 053 moves it out of the scene.
  - :327 `state.growth_hooks["enemy"] = enemy_turn.grow_at_turn_start`: shell wiring.
  - `_refresh_override_context` (:1261-1270): `state.talents.assign(…)`, `state.hero_passives.clear()` / `.append(…)`, `state.enemy_passives.assign(…)`. Its only caller is CheatPanel.gd:316.
  - :1590 and :1614 `state._combat_ended = true`, and :1623 `state._pending_revive = true` (J7, next section).

### CombatScene writes two engine flags (J7)

- **Where the scene sets them.** `_on_victory` / `_on_defeat` (:1587-1631) set `state._combat_ended`. The presenter calls them when it plays COMBAT_ENDED (CombatPresenter.gd:242-246). `_on_defeat` also sets `state._pending_revive` (:1623), which `_on_restart_pressed` reads (:1660).
- **`_combat_ended` is now a shadow of `winner`.**
  - CombatState.gd:1272-1275 says: "Live uses this directly; sim uses `winner` and currently ignores `_combat_ended` (Phase 5 unifies them)". Phase 5 is done, and nothing in the engine sets the flag.
  - The engine emits COMBAT_ENDED only right after it sets `winner` (:2034-2036, :2058-2067). So by the time the scene sets the flag, `winner` is already set, and each `winner.is_empty() and not _combat_ended` check (:2462, :2895, :2924, :2926, :2932) reduces to the `winner` check.
  - :2016 (`_on_hero_damaged`: `if _combat_ended: return`) can only matter for damage that arrives after the presenter has played COMBAT_ENDED. Commands are refused by then (:2932-2933 `"combat_over"`), so only the cheat panel's direct damage reaches it.
  - The sim never sets the flag.
- **Other readers:** CombatScene.gd :396, :399, :402, :474, :1588, :1612; EnemyTurnRunner.gd:62; LiveSmokeTests.gd:217.
- **`_pending_revive`** (CombatState.gd:1759-1760, "Live-only revive gate (Bone Phoenix etc)") is stale: the revive is Second Wind (`GameManager.has_revive`), and only the scene uses the flag.

### L10: VFX timer count

- :363-374 counts only the literal `"await get_tree().create_timer"`, only in `combat/effects/*VFX.gd`. `L10_BASELINE = 20` (:110) equals today's count, so there's no headroom, and nothing lowers the baseline.
- **Missed:**
  - CombatVFXBridge.gd has 9 `create_timer(` calls: :403, :438, :494, :501 and :514 go through `scene.get_tree()` / `_scene.get_tree()`; the others are :900, :1142, :1224 and :1272.
  - CombatScene.gd has 5 (:401, :841, :851, :1488, :1592).
  - CombatPresenter.gd:671, VoidBoltProjectile.gd:298, RitualProjectile.gd:303, ScreenShakeEffect.gd:40, and 2 in HandDisplay.gd (:79, :130).
  - Four VFX files have calls the literal doesn't match: BuffApplyVFX.gd:289 (not awaited), PackFrenzyVFX.gd:224 and VoidScreechVFX.gd:129 (`tree.create_timer(…).timeout.connect`), and VoidTouchedImpDeathVFX.gd:262.

### strip_comment and string blanking

- `strip_comment` (:171-186) toggles on every quote and ignores backslashes. L11's string blanking (:386, `re.sub(r'"[^"]*"', '""', …)`) has the same gap.
- Latent: 11 lines in the repo contain escaped quotes, and an escape-aware stripper changes 0 lint results today.

### L7, L6 and aliases

- **L7** (:315) spots a second AI profile table only when a file has more than 3 profile preloads. A table with 3 or fewer, one using `load(`, or one calling `XProfile.new()` passes; all 34 profile scripts have a `class_name`. Today only ProfileRegistry.gd has any (35 preloads), and no `*Profile.new(` appears outside it.
- **L6** (:271-276) checks only CombatState.gd. The other 11 RULES_FILES (:91-104) have 0 `await` / `get_tree(` / `create_timer(` today, but nothing stops one.
- **Aliases.** L4, L8, L9 and L11 match handle names, so `var s := state` escapes them. Today:
  - no presentation file aliases `state`;
  - CombatVFXBridge.gd:239 / :395 / :451 `var scene := _scene` and VfxController.gd:157 `var combat := _combat` reuse names L11 already checks;
  - rules-file aliases are typed (`var st: CombatState = state`, CombatHandlers.gd:2263), so the compiler checks them.

### Not done (corrects the roadmap)

- **Keep ENFORCED.** It holds every rule (:107), so the "(not yet enforced …)" tail (:434-435) never prints. But it is the staging path new rules can use.
- **`RNG_ALLOW` is declared once** (:150) and used once, not twice.
- **No gdtoolkit AST linter for now.** No regex false negative bites today, and it would add a pip dependency to the gate.

## Proposed fix

1. **L8 pattern.** Keep the current alternatives and add:
   - `\bstate\.\w+(?:\.\w+|\[[^\]]*\])*\s*(?:[-+*/%|&^]|<<|>>)?=(?!=)` for compound, nested and indexed writes;
   - `\bstate\.\w+\.(append|append_array|assign|erase|clear|remove_at|insert|push_back|push_front|pop_back|pop_front|sort|sort_custom|shuffle|resize|fill)\(` for mutators on any state field.
2. **Derive L8's file set:** every `.gd` under `combat/`, minus RULES_FILES, minus an explicit engine-side list, minus CheatPanel.gd.
   - Engine-side list: CombatState, CombatConfig, CombatEvent, CommandResult, SlotState, HeroState, BuffEntry, BuffSystem, EventContext, TriggerManager, EffectStep, SacrificeSystem, EnemyTurnRunner.
   - Today that is 68 files: the current 59 plus the 9 listed above.
3. **Make CombatScene pass (J7).**
   - **Scene-owned flags.** The scene gets `_combat_over: bool` and `_revive_pending: bool`, set where the state flags are set today (:1590, :1614, :1623). The readers at :396, :399, :402, :474, :1588, :1612 and :1660, and LiveSmokeTests.gd:217, read the scene flag. The flag is set at the same moment as before, so live behaviour doesn't change.
   - **Delete the engine fields.** Delete `CombatState._combat_ended` (:1272-1275) and `_pending_revive` (:1759-1760).
   - **Drop the `_combat_ended` terms** at :2462, :2895, :2924, :2926 and :2932, keeping the `winner` checks. Delete the early return at :2016 outright. Don't replace it with a `winner` check: that would stop damage after lethal within the same resolution, which the sim applies today.
   - **EnemyTurnRunner.gd:62** drops the term; it already checks `winner`.
   - **Move `_refresh_override_context`** (:1261-1270) into CheatPanel.gd, its only caller and already exempt. Task 053 then gates it with the panel.
   - **Allowlist** :327 (`growth_hooks[...] =`) by file and matched text, not by line number.
   - **Skip `_apply_test_config`'s body** (from its `func` line to the next top-level `func`) until task 053 moves it.
4. **L10: per-file baselines.**
   - Count every `create_timer(` (any receiver, awaited or not) per file across the L8 file set, against a per-file baseline dict.
   - Fail when a file goes over its baseline, or a new file appears with timers. Print "lower the baseline" when a count drops.
   - Exempt VfxSequence.gd (the sanctioned runner, 3 calls) and task 048's pause-aware timer helper.
   - Take the baselines after task 048 lands: it deletes the loop at CombatVFXBridge.gd:511-514 and adds its own timers.
5. **Escapes.** `strip_comment` honours backslash escapes, and L11's string blanking uses `"(?:\\.|[^"\\])*"`.
6. **L7.** Flag:
   - any `preload(` / `load(` of `res://enemies/ai/profiles/` outside enemies/ai/ProfileRegistry.gd;
   - `<ProfileClass>.new(` outside it, for every `class_name` declared under enemies/ai/profiles/.

   `extends <ProfileClass>` stays legal. Keep the "exactly one table" check.
7. **L6.** Extend the `await` / `get_tree(` / `create_timer(` ban from CombatState.gd to all RULES_FILES. Task 121 (roadmap G5) extends it to `enemies/ai`; share one helper.
8. **Aliases.** Per file, collect locals assigned from a handle (`var x(: T)? :?= (_scene\.|scene\.|ctx\.)?state\b`, or from a scene handle) and treat them as handles for L4, L8, L9 and L11 in that file.
9. **Docs.**
   - The module docstring (:1-68) lists L1–L11; add the rules added since (L12 onwards) and the new scopes.
   - Fix the ENFORCED comment.
   - Update TESTING.md's lint table rows for L6, L7, L8 and L10.

## Verification

- `python3 tools/lint/lint_engine.py` reports 0 errors after step 3.
- Seeded negatives. Make each temporary local edit, confirm the lint flags it (or correctly doesn't strip it), record the result in the summary, then revert:
  - `state.player_essence += 1` in CombatUI.gd;
  - `state.player_hand.append(x)` in a `*VFX.gd`;
  - `state.enemy_hp = 0` in CombatScene.gd, outside `_apply_test_config`;
  - `await` in CombatHandlers.gd;
  - a new `scene.get_tree().create_timer(0.1)` in CombatVFXBridge.gd;
  - `FeralPackProfile.new()` in sim/CombatSim.gd;
  - a string containing `\"#\"` followed by real code;
  - `var s := state` then `s.player_hp = 0` in CombatUI.gd.
- Manual (editor):
  - a won fight goes to the reward scene;
  - a lost fight with Second Wind shows "Revive & Retry" and restarts the fight;
  - a lost fight without it shows "DEFEAT".
- `tools/run_checks.sh` green. LiveSmoke's AI-vs-AI fight ends on the scene flag.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` through `--act 4`; the deleted terms sit in every fight's turn loop) diffs empty (design/TESTING.md "Refactor / extraction work"). The sim never set `_combat_ended`, so the deleted terms never changed a result.

## Related

- Depends on: task 048 — take the L10 baselines after it deletes the bridge polling loop and adds its timer helper.
- Related: task 050 (lint L13) and task 051 (lint L12) — edit the same file; rebase on whichever lands first.
- Related: task 053 — moves `_apply_test_config` out of CombatScene and gates CheatPanel (where `_refresh_override_context` goes).
- Related: task 112 (roadmap E6) — its `state._log(` check covers CombatScene once this task derives the file list.
- Related: task 103 (roadmap C5) — adds a GameManager-read pattern to L8 over the same file set. CombatScene (the shell) builds the fight's config from GameManager, so that pattern must keep excluding CombatScene.gd once this task brings the file into L8's set.
- Related: task 131 (roadmap I3) — its phase b abort keys on `winner` and leaves `_combat_ended` to this task.
- Related: task 111 (roadmap E4, L17) — reuses the derived file list and the per-file baseline shape.
- Related: task 121 (roadmap G5) — extends L6 to `enemies/ai`.
- Related: task 119 (roadmap G3) — L7 is where its guard goes if it becomes a lint.
- Related: task 099 (roadmap B7, L19) — names aliases as a known blind spot; step 8 closes it.
- Related: tasks 087 (roadmap A4, L16), 104 (roadmap D1, L14), 122 (roadmap G7, L18), 131 (roadmap I3, L20), 137 (roadmap J1, L15) and 058 (L21) — other rules in the same file. L14 and L16 rely on `strip_comment`; recompute any baseline step 5 shifts.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item J4, with J7 (CombatScene stops writing engine flags) folded in. Re-checked at `404b51c`:
  - found more `_combat_ended` readers than first listed (CombatScene :396-474, LiveSmokeTests :217);
  - added `_refresh_override_context` and the `assign` mutator, which the widened pattern also catches;
  - VfxSequence's timers need an exemption under the per-file L10;
  - dropped "delete ENFORCED" and "duplicate RNG_ALLOW" (declared once).

## Summary

_(filled in at /task-done)_
