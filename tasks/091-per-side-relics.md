---
id: "091"
title: Per-side relics
status: backlog
area: combat
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap §A, owner decision Q2 ("relics"; the A-paths unit's "A6c"). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The roadmap called relics "player-only (acceptable by design, but should be explicit)" (ARCHITECTURE_ROADMAP.md:54). The owner overruled that under Q2. Today the relic engine has no side anywhere:

- **Runtime.** One `relic_runtime: RelicRuntime` (CombatState.gd:1772), built from `config.relic_ids` / `config.relic_bonus_charges` (:2364-2366; CombatConfig.gd:33-34). Its `on_turn_start()` runs in the player branch of the turn start (CombatState.gd:2437-2438).
- **Command.** `cmd_activate_relic(index, target)` takes no side (:2824-2828):
  ```gdscript
  func _cmd_activate_relic(index: int, target = null) -> CommandResult:
  	var why: String = _check_can_act("player")
  ```
  It logs the command as `"player"`, journals RELIC_ACTIVATED as `"player"`, and resolves Blood Chalice against `enemy_board` / `"enemy_hero"` (:2830-2850).
- **Effects.** RelicEffects.gd has 11 side literals: draws, hand adds, mana, summons and board reads all name "player"; damage names "enemy". `resolve(effect_id)` takes no side (:14).
- **Relic state flags.** `_relic_hero_immune` (Bone Shield) and `_relic_cost_reduction` (Dark Mirror) are single fields (CombatState.gd:1774-1775). They are read as the player's at :2024 (hero damage), :2169 and :3045 (costs) and reset at the player's turn start (:2431-2432). UI reads them as the player's: CombatInputHandler.gd:166-168, LargePreview.gd:42-43, CombatUI.gd:156, :189, :200.
- **Callers.** CombatScene.gd:1157, :1191 (relic bar), SimRelicPolicy.gd:16, :43, :73 (sim), the command replay in CombatSim.gd:145, ParityTests.gd:288, CommandTests.gd:487-508, LiveSmokeTests.gd:138-149.
- **Digest.** `digest_text` prints one `relics …` line from `relic_runtime` (CombatState.gd:2283-2287).

The command-log record already carries a side (`_log_command` writes `side = side`, CombatState.gd:3113-3118). So adding a side to the command doesn't change the replay format; CombatSim.gd:145 only has to pass `side` instead of dropping it.

### Reachable today

Nothing. No enemy config lists relics, and Q2 keeps it that way ("the enemy's config lists no relics"). This is engine work for a future enemy hero or a PvP opponent.

## Decision (owner, 2026-10-01)

- Q2: "relics … must all work for either side in the engine. The enemy doesn't have to use them today." Who has what is decided by data and config, "e.g. the enemy's config lists no relics", never by `if owner == "player"` in rules code.
- Q3: record the BalanceSimBatch result. With no enemy relics, expect none.

## Proposed fix

1. **Per-side runtime.** Put the `RelicRuntime`, Bone Shield's immunity flag and Dark Mirror's pending reduction on task 083's `SideState`. Keep `relic_runtime`, `_relic_hero_immune` and `_relic_cost_reduction` as forwarders to the player's while the UI migrates.
2. **Config.** CombatConfig gains `enemy_relic_ids` and `enemy_relic_bonus_charges`, empty by default; the replay dict reads them with defaults. `setup_combat` builds a runtime for each side that has relics.
3. **Command.** `cmd_activate_relic(side, index, target)`: `_check_can_act(side)`; the runtime is `side(side)`'s; Blood Chalice's target must be on `_opponent_board(side)` or the opponent's hero; `_log_command` and RELIC_ACTIVATED use `side`. Update every caller listed above. The live relic bar and SimRelicPolicy pass `"player"` (SimRelicPolicy could take the agent's side). If task 122 (roadmap G7) has landed, SimRelicPolicy goes through `agent.activate_relic` / `agent.relic_runtime`: make those side-aware instead of editing SimRelicPolicy again.
4. **Effects.** `RelicEffects.resolve(effect_id, side)` uses `side` and `_opponent_of(side)` for all 11 literals, plus the ones added by task 058 (`_card_for("player", …)` at :23, :122) and task 069 (`emit_resources("player")` in `relic_extra_turn`) if they have landed. Its `_log` picks the log type from the side (task 054's `_log_side` helper).
   - Imp Talisman's `CardDatabase.get_card("void_imp")` is task 058's bug (it should be `_card_for`).
   - Oblivion Seal's rune placement goes through task 050's `place_trap(side, …)` and fires ON_RUNE_PLACED with that side (task 093).
5. **Turn hooks.** Each side's `RelicRuntime.on_turn_start()` and flag resets run at that side's turn start. Hero damage checks the target side's Bone Shield. `pay_card_cost` and the cost preview (:2169, :3045) use the paying side's Dark Mirror reduction instead of `side == "player" and …`.
6. **Digest.** Print one `relics` line per side that has a runtime. Parity compares live and engine within one run, so the extra line is safe.
7. **Presenter.** RELIC_ACTIVATED refreshes the relic bar only for side "player" (CombatPresenter.gd:755-757). An enemy relic bar is UI work for when an enemy gets relics.
8. **Teardown.** `relic_effects` is one of the reference-cycle holders in task 049. If this task keeps one `RelicEffects` per state (with a side argument), 049's teardown already covers it; don't add a second holder.

## Verification

- New probes in `debug/tests/CommandTests.gd`, next to `_activate_relic` (:487):
  - Enemy relic: `build_state` with `enemy_relic_ids: ["dark_mirror", "blood_chalice"]` (new TestHarness option). On the enemy's turn, `cmd_activate_relic("enemy", mirror)` is accepted and the enemy's next card costs 2 less; the player's costs are unchanged. `cmd_activate_relic("enemy", chalice, player_minion)` deals 500 to the player minion; targeting an enemy minion is refused with `"no_target"`.
  - Turn check: `cmd_activate_relic("enemy", 0)` on the player's turn is refused with `"not_your_turn"`.
  - Bone Shield: an enemy `relic_hero_immune` makes the enemy hero ignore damage this turn; the player hero still takes damage.
  - Existing player probes pass with the new signature.
- Replay: a recorded player fight with relic activations (ParityTests' relic case) still replays; the record format is unchanged.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the enemy has no relics. The seeded balance fingerprint (`BalanceSimBatch -- --act N --runs 200 --seed 7`, before and after, for N = 1, 2, 3, 4; request 3 and 4 explicitly, Act 4 runs relic-upgrade variants) diffs empty (design/TESTING.md "Refactor / extraction work").

## Related

- Depends on: task 083 (roadmap A1) — `SideState`, where the per-side runtime and flags live.
- Related: task 050 — `place_trap` for Oblivion Seal's rune. Task 058 — Imp Talisman's `_card_for` fix, in the same function.
- Related: task 093 (roadmap PS-rituals) — the relic's ON_RUNE_PLACED carries the relic owner's side.
- Related: task 054 — log types in RelicEffects (:159). Task 049 — `relic_effects` is a cycle holder.
- Related: task 123 (roadmap H1) — run-layer relic rewards; this task changes only the combat side.
- Related: task 082 (roadmap A0) — row 19 of its table points here.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from owner decision Q2 (the A-paths unit's A6c). Corrected the unit report: the command-log record already has a side field, so the replay format does not change.

## Summary

_(filled in at /task-done)_
