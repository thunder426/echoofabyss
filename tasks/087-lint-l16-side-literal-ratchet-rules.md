---
id: "087"
title: Lint L16: side-literal ratchet in rules code, and no "player" parameter defaults
status: backlog
area: tooling
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item A4 (`design/refactors/ARCHITECTURE_ROADMAP.md` §A). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The rule number is provisional: L16, after L12 (task 051), L13 (task 050), L14 (task 104) and L15 (task 137). Take the next free number if the landing order differs.

### Nothing stops new side literals

ARCHITECTURE.md invariant #2 says every handler uses `ctx.owner` / `_opponent_of()` and never a hardcoded `"player"` / `"enemy"`; the 2026-10-01 caveat under invariant #3 says that isn't true yet. Only documentation enforces it. The roadmap's A4 asks for a lint rule with an allowlist. With today's counts it can only be a ratchet.

Comment-stripped `"player"` / `"enemy"` occurrences in lint's `RULES_FILES` (tools/lint/lint_engine.py:91-103, using its own `strip_comment`, :171-187): 379 on 355 lines.

| File | Occurrences |
|---|---|
| combat/board/CombatState.gd | 212 |
| combat/events/CombatHandlers.gd | 83 |
| combat/effects/EffectResolver.gd | 34 |
| combat/board/CombatManager.gd | 22 |
| relics/RelicEffects.gd | 11 |
| combat/effects/ConditionResolver.gd | 6 |
| combat/effects/HardcodedEffects.gd | 4 |
| combat/board/MinionInstance.gd | 4 |
| combat/effects/TargetResolver.gd | 1 |
| combat/effects/EffectContext.gd | 1 |
| combat/board/PhaseTransition.gd | 1 |
| combat/events/CombatSetup.gd | 0 |

Some are legitimate boundaries: `digest_text` iterates `for side in ["player", "enemy"]` (CombatState.gd:2253, :2264), `_encode_target` writes side strings (:3130-3137), and the AI / replay boundary uses them. Most are rules deciding by side.

### Parameters that default to the player

Five rules functions default their side parameter to `"player"`, so a forgotten argument silently becomes player-side:
- CombatState.gd:318 `func _remove_rune_aura(rune: TrapCardData, owner: String = "player")`
- :384 `func _unregister_env_aura(env: EnvironmentCardData, owner: String = "player")`
- :482 `func _resolve_spell_effect(effect_id: String, target: MinionInstance, owner: String = "player")`
- :781 `func _apply_rune_aura(rune: TrapCardData, owner: String = "player")`
- :2090 `func _resolve_void_devourer_sacrifice(devourer: MinionInstance, owner: String = "player")`

Four callers rely on the default: CombatState.gd:509 and :537 (`_resolve_spell_effect(spell.effect_id, target)` in the player cast paths), :887 (`_remove_rune_aura(trap)` in `_fire_ritual`) and RelicEffects.gd:131 (`state._apply_rune_aura(rune)`, Oblivion Seal). All four are player-only paths today; tasks 090, 091 and 093 make them per side.

Field defaults with the same shape: `EffectContext.owner` (EffectContext.gd:12) and `MinionInstance.owner` (MinionInstance.gd:22) in `RULES_FILES`, and `SlotState.side` (SlotState.gd:15) outside it.

### The existing ratchet pattern

L10 (lint_engine.py:109-110 `L10_BASELINE = 20`, check at :362-374) fails when the count rises above its baseline. It prints nothing when the count falls, so its baseline goes stale silently. `ENFORCED` (:107) lists L1–L11.

### Consequence

New rules code keeps assuming a symmetry it doesn't get, the audit cost grows with every literal, and a default-to-player parameter can hide a one-sided bug. Tasks 083–093 lower the count; without a ratchet, other work can raise it again at the same time.

## Decision (owner, 2026-10-01)

Q1: PvP / mirror matches are planned; A1–A4 are in scope in full. Q2: who has what is data and config, never `if owner == "player"` in rules code.

## Proposed fix

1. **L16 count.** In tools/lint/lint_engine.py, for each `RULES_FILES` file count the comment-stripped occurrences of `"player"` / `"enemy"`, plus `CombatSide.PLAYER` / `CombatSide.ENEMY` once task 083 adds the constants. Respelling a literal as a constant doesn't lower the count, so the rule measures side decisions, not spelling.
2. **Per-file baseline.** `L16_BASELINE = {file: count}`, computed when the rule lands (after tasks 050, 051, 054 and 055, which shift the counts). Fail when a file is above its baseline. Unlike L10, print a note when a file is below it ("lower L16_BASELINE[<file>] to N"), so the task that removed literals lowers the baseline in the same commit.
3. **Opt-out per line**: `# lint: allow-side (<reason>)`, same shape as L2's `allow-rng` (lint_engine.py:150). A reason in parentheses is required. Opted-out lines don't count. Intended for the serialization and digest boundary (`digest_text`, `_encode_target`), `winner` bookkeeping, and temporary gates other tasks name explicitly (e.g. task 083's card-drawn gate, `# lint: allow-side (task 086)`).
4. **Hard rule, no baseline**: no side-string default on a function parameter in `RULES_FILES`: a `func` signature matching `\w+\s*:\s*String\s*=\s*"(player|enemy)"` is an error. Make the 5 parameters above required and pass `"player"` explicitly at the 4 callers. Compute the baseline after this step (the explicit arguments add 4 literals).
5. **Field defaults**: report `EffectContext.owner` and `MinionInstance.owner` under `--all` without failing. Changing them touches every `EffectContext.new()` / `MinionInstance` construction and belongs with the side model (tasks 083, 086).
6. Add L16 to `ENFORCED`. Document it in the lint docstring (:7-61), design/TESTING.md's lint row (:22) and rule table (:60-74), and the "Not yet true" caveat under ARCHITECTURE.md invariants #2–#3: new side literals in rules code are blocked by L16 and the count only goes down.
7. Out of scope: presentation defaults (TrapEnvDisplay.gd:271, :287, :299; CombatVFXBridge.gd:521, :1179). They are outside `RULES_FILES`.

## Verification

- `tools/run_checks.sh` green (lint 0 at the baseline).
- Manual self-test, recorded in the task's work log, then reverted:
  - add one `"enemy"` literal to CombatHandlers.gd → L16 reports the file and its count;
  - add `# lint: allow-side (test)` to that line → clean;
  - remove one existing literal → the "lower the baseline" note prints and the exit code stays 0;
  - give a rules function a `side: String = "player"` parameter → hard error.
- Behaviour-neutral: the only rules-code change is passing `"player"` explicitly where the default supplied it. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, `--act 1` through `--act 4`) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Related: task 083 (roadmap A1): adds `CombatSide`; L16 counts its constants too.
- Related: tasks 084, 085, 086, 089, 090, 091, 092, 093 (side model and per-side mechanics): each lowers the baselines in its own commit.
- Related: task 082 (roadmap A0): keeps the verdict table the invariants #2–#3 caveat points to; the caveat also points at this ratchet.
- Related: task 051 (lint L12), task 050 (lint L13), task 104 (roadmap D1, lint L14, provisional), task 137 (roadmap J1, lint L15, provisional): rule numbers taken before this one.
- Related: task 140 (roadmap J4): hardens `strip_comment` (escaped quotes); recompute the L16 baseline if that changes what counts as a comment.
- Related: task 111 (roadmap E4, L17), task 122 (roadmap G7, L18), task 099 (roadmap B7, L19) and task 140's L10 rewrite: the same per-file ratchet with a "lower the baseline" note; write the helper once and share it.
- Related: task 058: adds `_card_for("player", …)` / `_card_for("enemy", …)` literals (RelicEffects.gd:23, :122; CombatState.gd:1899; CombatHandlers.gd:1151, :2282). If 058 lands first, the baseline counts them; if this task lands first, 058 raises it.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item A4. Corrected the draft: L10 prints no note below its baseline, so this rule adds one.

## Summary

_(filled in at /task-done)_
