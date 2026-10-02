---
id: "054"
title: Fix CombatHandlers log-type constants (off by one vs CombatLog.LogType)
status: done
area: combat
priority: normal
started: 2026-10-02
finished: 2026-10-02
---

## Description

Found in the 2026-09-25 architecture review (issue 8 of 9). Re-verified 2026-09-30 at `3009a60`. Line numbers are from that commit.

Do this together with 055. Both edit the same lines of CombatHandlers.gd: :16-18, :156-174, and `_log` at :2301.

`combat/events/CombatHandlers.gd:16-18`:
```gdscript
## Log-side constants matching CombatScene._LogType enum values.
const _LOG_PLAYER := 0
const _LOG_ENEMY  := 1
```

`CombatLog.LogType` is `{ TURN, PLAYER, ENEMY, DAMAGE, HEAL, TRAP, DEATH }` (CombatLog.gd:14), so TURN=0, PLAYER=1, ENEMY=2. `CombatScene._LogType` does exist (CombatScene.gd:1916, an alias of that enum); what's wrong is the constants' values, not the name in the comment.

The value reaches the screen unchanged:

`CombatHandlers._log` (:2301-2302) → `CombatState._log` (:114-116, a `LOG` journal event carrying `log_type`) → CombatPresenter :684-686 → `CombatUI.on_state_combat_log` (:87-90) → `CombatLog.write` → `_color_for(type)` (:42-50)

So handler lines tagged `_LOG_PLAYER` render in the grey TURN colour, and `_LOG_ENEMY` lines in the blue PLAYER colour. Only the colour is affected. `CombatDiagnostics._print_log` ignores the type and `digest_text` excludes logs, so parity and balance are unaffected.

Affected in CombatHandlers:
- 19 `_LOG_PLAYER` and 42 `_LOG_ENEMY` uses;
- 4 `side` values picked from the owner (:1389, :1426, :1506, :1543);
- one inline conditional (:723);
- `_log`'s default parameter (:2301).

The rest of the rules code is already correct:
- HardcodedEffects.gd:21-24 has `_LOG_PLAYER=1`, `_LOG_ENEMY=2`, `_LOG_TRAP=5` and a `_log_side(owner)` helper (:29-30).
- CombatState, RelicEffects (:159), PhaseTransition (:74) and CombatInputHandler (:457) pass correct bare integers.
- EffectResolver, CombatManager, CombatSetup and the resolvers don't log.

## Proposed fix

1. **Use the enum.** Preferred: move `LogType` into `Enums.gd` and alias it in CombatLog. CombatLog is a UI node helper (its `setup` touches nodes), and rules code shouldn't depend on it. Otherwise, use `CombatLog.LogType.PLAYER` / `.ENEMY` directly.
2. **Add a `_log_side(owner)` helper** to CombatHandlers, like HardcodedEffects', and use it wherever the handler knows the owner.
3. **Replace the bare integers** in CombatState, RelicEffects, PhaseTransition and CombatInputHandler, and HardcodedEffects' constants, with the enum. Clean-up only; no behaviour change.
4. **Fix the stale comments:** CombatLog.gd:5-10, CombatScene.gd:1913-1915, HardcodedEffects.gd:21.

## Verification

- Extend the Swarm Discipline test (TriggerHandlerTests.gd:666; the handler logs at CombatHandlers:167-170): the journal's `LOG` event has `log_type == PLAYER`. Add a check on one enemy-side handler log.
- Visual: in a live fight, handler lines show the player and enemy colours.
- `tools/run_checks.sh` green; Parity digests unchanged.

## Work log

- 2026-09-25: opened from the architecture review. Verified the constants against `CombatLog.LogType`.
- 2026-09-30: re-verified at `3009a60` and rewritten.
  - Traced the value end to end: the bug is real, and it affects colour only.
  - `CombatScene._LogType` does exist.
  - Other rules code is already correct, so step 3 is clean-up, not a bug hunt.
  - Bundled with 055.
- 2026-10-02: implemented, steps 1–4.
  - `LogType` moved to `Enums.LogType`; CombatLog keeps `const LogType := Enums.LogType` (and matches on `Enums.LogType.*`), so CombatScene's `_LogType` alias and CheatPanel are unchanged.
  - CombatHandlers: `_LOG_PLAYER` / `_LOG_ENEMY` are `Enums.LogType.PLAYER` / `.ENEMY` (were 0 / 1), plus `_log_side(owner)`, used at the inline conditional and the four owner-picked sides.
  - The 52 bare-integer log types in CombatState (46), CombatInputHandler (4), PhaseTransition and RelicEffects are enum names, as are `CombatState._log`'s default, the presenter's LOG default and HardcodedEffects' constants. Stale comments fixed: CombatLog header, CombatScene `_LogType`, HardcodedEffects, CombatState:43.
  - Probes: Swarm Discipline's handler line journals as PLAYER, Captain's Orders' as ENEMY (`_log_type_of` helper in TriggerHandlerTests). With the old constants restored both fail (got 0 and 1).
  - Gate green: lint 0, 1121 tests, LiveSmoke OK, Parity 24/24. Fingerprint Acts 1–4 identical to `9c3603f`.
  - Visual check in a live fight (handler lines in the player / enemy colours) is left to the owner.
- 2026-10-02: closed.

## Summary

CombatHandlers' log lines now journal the right type (its constants were 0 / 1 against `CombatLog.LogType`'s PLAYER = 1 / ENEMY = 2, so player lines showed in the TURN colour and enemy lines in the PLAYER colour). `LogType` lives in `Enums`, and rules code names it everywhere instead of bare integers; two journal probes guard it. Colour only: BalanceSimBatch Acts 1–4 identical.
Follow-ups: the owner's visual check in a live fight.
