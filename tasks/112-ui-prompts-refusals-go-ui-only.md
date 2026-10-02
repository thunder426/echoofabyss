---
id: "112"
title: UI prompts and refusals go to a UI-only log channel; attack narration moves into the engine
status: backlog
area: ui
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item E6 (`design/refactors/ARCHITECTURE_ROADMAP.md` §E, direction 5). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

`CombatState._log` journals a LOG event (CombatState.gd:114-116):

```gdscript
func _log(msg: String, log_type: int = 1) -> void:
	combat_log.emit(msg, log_type)
	emit_event(CombatEvent.Kind.LOG, "", {msg = msg, log_type = log_type})
```

The line reaches the screen only when the presenter plays it: `_emit_ui` LOG (CombatPresenter.gd:684-686) → `CombatUI.on_state_combat_log` (CombatUI.gd:87-90) → `combat_log.write`.

Input and UI code uses the same call for prompts, refusals and cancels. `grep -n 'state\._log(' combat/board/CombatScene.gd combat/board/CombatInputHandler.gd combat/ui/*.gd` finds 23 lines:

| File | Lines | What |
|---|---|---|
| CombatScene.gd | :558, :575, :589, :600, :625 | "  <card>: <reason>." after a refused play command |
| | :587 | "Trap slots are full." |
| | :1175, :1198 | Blood Chalice prompt "choose a target (right-click to cancel)", "Relic cancelled." |
| | :1310, :1321, :1329, :1338, :1347 | Corrupt Flesh: already used, no Demon, "pick a friendly Demon", wrong target, cancelled |
| | :228, :1094 | "Seed: %d", "[TEST] Test config applied." |
| CombatInputHandler.gd | :354, :508 | attack narration "Your %s attacks enemy %s" / "Your %s attacks Enemy Hero" |
| | :357, :511 | "  Attack refused: %s." |
| | :424, :458 | refused targeted spell (trap / environment target, enemy hero target) |
| combat/ui/CheatPanel.gd | :322, :348 | "[CHEAT] Talent unlocked", "[CHEAT] Relic granted" |

### What goes wrong

1. **Prompts and refusals show late.** Player input isn't gated on the presenter (CombatScene.gd:427-428; owner decision QN5 keeps it that way), so a prompt is often journaled behind events still playing. Example: during a spell's cast animation, the player clicks Blood Chalice. "Blood Chalice: choose a target" appears only after the spell has finished playing, while the game is already waiting for the pick. The same goes for the Corrupt Flesh prompts and for "Trap slots are full.".
2. **The gameplay journal carries UI chatter in live fights only.** The sim never journals these lines, so a live journal and a sim journal of the same fight differ by them. Parity compares digests, not journals. But its failure report prints the LOG lines on both sides (`_log_between`, ParityTests.gd:359-366), so the live side shows extra lines.
3. **Attacks are narrated only for live player attacks, and before validation.**
   - CombatInputHandler.gd:354 and :508 log the narration before calling `cmd_attack` / `cmd_attack_hero`. A refused attack therefore logs "Your X attacks enemy Y" followed by "Attack refused: ..." (:357, :511).
   - The engine never narrates an attack: `_cmd_attack` (CombatState.gd:2761-2781) and `_cmd_attack_hero` (:2788-2805) journal a COMMAND and the damage, but no LOG. So enemy attacks, and every attack in the sim log, have no narration line.

## Proposed fix

1. **A UI-only log channel.** Add `CombatScene.ui_log(msg: String, type: int = CombatLog.LogType.PLAYER)`, which calls `combat_log.write(msg, type)` (CombatLog.gd:27) at once, with no journal event.
2. **Route the lines above through it.**
   - CombatScene :228, :558, :575, :587, :589, :600, :625, :1094, :1175, :1198, :1310, :1321, :1329, :1338, :1347.
   - CombatInputHandler :357, :424, :458, :511 (`_scene.ui_log(...)`).
   - CheatPanel :322, :348.
   - A refusal now shows at once, even while earlier events are still playing. That's intended: it answers the click the player just made.
3. **Attack narration moves into the engine, for both sides.**
   - `_cmd_attack` logs one narration line once the attack is accepted: after `_log_command` (:2774), before `_fire_enemy_attack_declared` (:2775). `_cmd_attack_hero` likewise after :2798.
   - Wording by side: "Your X attacks enemy Y" / "Enemy X attacks your Y", "... attacks Enemy Hero" / "... attacks you". Log type PLAYER or ENEMY from the side, using task 054's constants if it has landed.
   - Delete CombatInputHandler.gd:354 and :508.
   - When Smoke Veil cancels an enemy attack, the narration comes first, then the trap's own lines. That order is right: the attack was declared.
4. **Lint.** Extend L8's pattern (tools/lint/lint_engine.py:293-295) with `\bstate\._log\(`: presentation and input code may not journal log lines.
   - L8 already scans CombatInputHandler and combat/ui (CheatPanel is exempt; its lines move anyway).
   - CombatScene joins L8's file set when task 140 (roadmap J4) derives the list. If this task lands first, add a one-off check for CombatScene.gd in the same scan.
5. **Docs.** CombatLog.gd:5-10 describes a `_scene._log` facade that no longer exists (CombatScene has no `_log`). Task 054 step 4 rewrites that comment; whichever lands second makes it name `ui_log` (UI lines) and `state._log` (rules lines).

## Verification

- **New LiveSmoke probe `_ui_log_is_immediate`** (debug/tests/LiveSmokeTests.gd):
  - Setup: launch F1.
  - Action: journal a long animation (play an untargeted spell with `cmd_play_spell`), then, with no await, call `scene._cancel_seris_corrupt_targeting()`, which writes "  Corrupt Flesh cancelled." unconditionally.
  - Expect: the last Label in `scene.combat_log._container` reads that line at once, before any drain, and no LOG event in `st.journal` carries it.
- **New CommandTests probe** (debug/tests/CommandTests.gd):
  - `cmd_attack("player", a, t)` journals exactly one LOG whose `msg` contains a's name and "attacks"; `cmd_attack("enemy", ...)` likewise; `cmd_attack_hero` for both sides likewise.
  - A refused attack (exhausted attacker) journals no narration.
- Parity stays green. The live replay drives attacks through the input handler (ParityTests.gd:278-287), which no longer logs; the engine logs once in both runs.
- `tools/run_checks.sh` green, including L8 with the new pattern.
- Behaviour-neutral: only LOG events move. `digest_text` excludes the journal (CombatState.gd:2242-2288), and nothing outside the presenter and the tests reads it. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` through `--act 4`; attacks happen in every fight) diffs empty (design/TESTING.md "Refactor / extraction work"). The sim now journals one extra LOG per attack; note the wall-time change in the summary (task 136 measures the sim's LOG cost).

## Related

- Related: task 054 — log-type constants (and possibly `LogType` moved to Enums.gd), which the new engine narration uses; it also rewrites the stale CombatLog.gd header.
- Related: task 140 (roadmap J4) — derives L8's file list, which brings CombatScene into the new `state._log(` check.
- Related: task 136 (roadmap I7d) — measures the sim's LOG cost; the narration adds one LOG per attack.
- Related: task 053 — gates the debug tools: the test-config line (:1094) and CheatPanel.
- Related: task 111 (roadmap E4, lint L17) — the read-side presentation lint; this task adds a write-side check to L8.
- Related: task 113 (roadmap E7) — out-of-sync clicks are ignored there instead of producing "Attack refused" lines.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item E6.
  - Re-check: 23 sites, not the 4 the roadmap named.
  - The attack narration exists only in live and is logged before validation; it moves into the engine for both sides instead of to the UI channel.

## Summary

_(filled in at /task-done)_
