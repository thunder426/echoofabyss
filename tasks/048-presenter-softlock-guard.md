---
id: "048"
title: Stop the presenter from soft-locking combat on a stuck animation
status: backlog
area: ui
priority: normal
started:
finished:
---

## Description

Found in the 2026-09-25 architecture review (issue 2 of 9). Re-verified 2026-09-30 at `3009a60`. Line numbers are from that commit.

**Nothing here hangs in normal play today.** This is a guard against the next VFX bug, which would otherwise soft-lock the game.

`CombatPresenter._drain` (:99-118) does `await _play(ev)` (:111) with no deadline. If an animation's signal never fires:
- `_draining` stays true, `idle` never emits, and `pump_and_wait_idle()` (:93-96) never returns.
- `_do_end_turn` leaves `_end_turn_in_progress = true` (CombatScene.gd:470; the await is at :472).
- The enemy turn never starts (`_on_turn_started` awaits at :398).
- `player_can_act()` (:427-428) needs both the turn shown and `not _end_turn_in_progress`, so all player input is blocked too.

### Waits that can block a drain

**38 signal awaits:**

| File | Count | Where |
|---|---|---|
| CombatPresenter | 3 | :398 `buff_vfx_batch_done`; :427 and :551 `bolt.impact_hit` |
| CombatScene | 10 | 8 tweens; `vfx.finished` at :1559 and :1710 |
| VfxController | 7 | :83, :85, :112, :140, :142, :166, :176 |
| CombatVFXBridge | 18 | 14 VFX signals, 4 tweens |

The tweens are low risk.

**5 polling loops with no limit:**
- CombatScene :1484-1485 (`play_trap_reveals`, waits for `shown[0]`);
- bridge :170-173 (detonations);
- bridge :435-438 (`tail_done_ref`, set only through the BEAT_MERGE_COMPLETE listener at :427-431);
- bridge :490-494 and :497-501 (RitualProjectile `finished`).

A sixth, bridge :511-514, is in `play_demon_ascendant_tail_for`, which has no callers.

**One existing deadline:** only `_cast_anim` (:660-665) has one. It is 4 s of wall-clock time (`Time.get_ticks_msec`), so it ignores time scale and keeps counting while the ESC menu pauses the game.

### Latent ways to hang (none reachable today)

1. **A signal fires before anyone awaits it.**
   - `BaseVfx._ready()` calls `_play()` synchronously (BaseVfx.gd:39-40).
   - `VfxController.spawn` adds the VFX to `$VfxLayer`, which is in the tree (:48), so `_play` runs inside `add_child`.
   - 22 of the 29 BaseVfx subclasses have a guard that emits `finished` (and `impact_hit`) immediately, e.g. SummonSigilVFX :106-110.
   - `CombatVFXBridge.summon_spark_with_sigil` spawns first and only then awaits (:51-53).
   - Every caller checked validates the guard condition first (e.g. `_play_summon` null-checks the slot at CombatPresenter :314-315). BuffApplyVFX and CorruptionDetonation connect before spawning.
2. **A spawn is silently skipped.**
   - `VfxController.spawn` skips `add_child` when `_vfx_layer` is null (:44-48).
   - Bridge sites spawn only `if vfx_controller != null` but await regardless (:947-950, :958-961).
   - The void-bolt spawners can return an unspawned bolt (:835-838, :865-868) whose `impact_hit` the presenter awaits.
   - `play_trap_reveals` waits forever if `vfx_bridge` is null (:1883) or the bridge returns early (:987-991).
3. **A VFX is freed, or its host leaves the tree, before emitting.** VfxSequence's abort (:111-113, :141-143) emits `finished` but not `impact_hit` or the scheduled mid-phase beats (:155). Today this only happens at teardown.
4. **A stuck BuffApplyVFX prelude** (`await _prelude.call()`, BuffApplyVFX.gd:140) stalls `buff_vfx_batch_done`.

### Not issues (corrects the original task)

- **The VfxSequence watchdog** (debug builds only, :203) is effectively dead code. Phases run on SceneTreeTimers and nothing inside a sequence is awaited, so a sequence can't stall. Running it in release builds gains nothing.
- **`VoidBoltProjectile.gd:299`** returns without emitting `finished`, but nobody awaits the bolt's `finished`; the presenter awaits `impact_hit`, which fires at :274. RitualProjectile :303-306 has the same pattern and is polled, but only matters at teardown. Both are hygiene only.

### Test coverage

LiveSmoke already runs four scenarios with animations on, at `BaseVfx.time_scale = 0.05` (:22):
- the F1 enemy turn;
- F13;
- live rules paths;
- HP labels (exercises the look-ahead).

`run_checks.sh` kills any run after 300 s, so a hang in those paths already fails the gate.

The gap: Parity (ParityTests:124) and LiveSmoke's AI-vs-AI fight (:206) set `presenter.instant = true`, so no full fight ever plays with real animations.

## Proposed fix

Work in this order. Step 3 carries the design risk and can be split out as 048b.

1. **Make hangs visible first.** Add one full fight with animations on (not the whole Parity matrix). Run it with `Engine.time_scale = 10`, as Parity does, because many waits ignore `BaseVfx.time_scale`. Put a wall-clock limit on it.
2. **Fix the root causes.**
   - **Connect before spawning.** Add `VfxController.spawn_and_await(vfx, signal_name, budget)`: it connects first, then calls `add_child`, and returns at once with a warning if the layer is missing.
     - Alternative: `BaseVfx._ready` → `_play.call_deferred()`. No subclass overrides `_ready`, and no caller reads state that `_play` creates right after `spawn()`.
     - Either way, visually check the 8 VFX that have `_process` / `_draw` (VoidBolt, RitualProjectile, SummonSigil, …).
   - **Limit the 5 polling loops** with a timer that pauses with the game, and `push_warning` when one expires. Delete the unused loop at :511-514.
   - **Fail loudly** (warning plus early return, never an await) when a VFX can't spawn.
   - **Backfill missing impacts on abort.** Emit any `impact_hit`s not yet fired, then `finished`.
     - Count emissions in BaseVfx, not VfxSequence. VfxSequence counts only RESERVED beats (:160-162), while VoidScreech (:76-77) and PackFrenzy (:231) emit `impact_hit` directly, so a VfxSequence-level backfill would double-emit.
     - `impact_count` defaults to 1, and many VFX don't set it.
   - **Hygiene:** emit `finished` in VoidBoltProjectile :299 and RitualProjectile :303-306.
3. **Presenter deadline** around each `_play(ev)`.
   - **Racing helper.** GDScript can't await two signals, and no helper exists yet. Write a small one-shot RefCounted that races the signal against a timer; use `.unbind(n)` for signals that carry arguments.
   - **Budget per event kind**, default about 8 s. Reference durations at scale 1: ritual sacrifice about 6 s (1.75 s timer + RitualFiring 3.4 s + about 0.85 s tail), a champion summon about 3.9 s.
   - **Scaling:** `max(base, base * BaseVfx.time_scale)`, never below scale 1, because many waits ignore time_scale (cast preview about 1.1 s, bolt 0.8 s, reveal 1.34 s).
   - **Pause-aware timer:** `get_tree().create_timer(t, false)`. The default keeps counting while the EscMenu pause is on (EscMenu.gd:40). Don't use wall-clock time: Parity runs at `Engine.time_scale = 10`. Fix `_cast_anim`'s deadline the same way.
   - **Generation guard.** A timed-out `_play` can't be cancelled, and it resumes if its signal fires late. Bump a generation counter on timeout, and make every continuation after an await in `_play_*` stop if it changed. Without this:
     - a late `on_impact` in `_play_spell` calls `play_captured_all()` on the member `_spell_pending` (:474-480, :485-489), showing or stealing the *next* spell's events;
     - a late `_play_damage`, `show_minion` or `animate_hp_change` rewinds labels (the task-046 bug class);
     - a late `clear_highlight()` wipes the player's selection.
   - **Resync after a timeout:**
     - clear `freeze_visuals` (`_play_summon` :319 / :324, bridge :48) and `hold_stats`;
     - reset `_active_buff_vfx_count`;
     - refresh the slots and re-apply the view.
   - **On timeout:** `push_warning` with the event kind and seq, and increment a `timeouts` counter (or emit `timed_out(ev)`).
4. **Gate.** The step 1 fight asserts `presenter.timeouts == 0`; a `push_warning` alone never fails run_checks, which greps for `SCRIPT ERROR`. Test the deadline itself with a test-only VFX event that never finishes. SummonSigil with a bad slot won't hang once step 2 lands.
5. **Lint L10** caps `await get_tree().create_timer` in `combat/effects/*VFX.gd` at a baseline of 20 (lint_engine.py:110). Put the new timers in the helper or the presenter, not in `*VFX.gd` files.

## Verification

- The full animated fight passes with zero presenter timeouts.
- The never-finishing test VFX: the presenter times out once, warns, resyncs and drains to idle, and the player can act afterwards.
- Pausing with ESC during a long animation doesn't trigger a timeout.
- `tools/run_checks.sh` green, including the new run.

## Related

- Roadmap E (presentation reads only the journal) and F (look-ahead matched by cause) come after this.

## Work log

- 2026-09-25: opened from the architecture review. Verified `_drain` has no timeout, `BaseVfx._ready → _play()` is synchronous, and `summon_spark_with_sigil` awaits `finished` after `spawn()`.
- 2026-09-30: re-verified at `3009a60` and rewritten.
  - Priority high → normal: no hang is reachable today.
  - Path 1 is latent, because callers validate first.
  - Dropped the "watchdog in release" step.
  - VoidBolt :299 is not a hang.
  - Await count corrected to 38 plus 5 polling loops (was "about 31"). Added the trap-reveal and detonation polls and the silent spawn skip.
  - LiveSmoke already covers four animated scenarios.
  - The deadline now needs a generation guard, a pause-aware timer, budgets of at least 6 s, a resync and a zero-timeout assertion.
