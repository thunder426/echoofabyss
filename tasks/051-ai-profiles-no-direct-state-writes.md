---
id: "051"
title: Stop AI profiles writing CombatState outside cmd_* (and de-duplicate spark cost)
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

Found in the 2026-09-25 architecture review (issue 5 of 9). Re-verified 2026-09-30 at `3009a60`. Line numbers are from that commit.

This breaks invariant #4: both sides act only through `state.cmd_*`, so a fight replays from its `command_log`.

### Direct state writes in `enemies/ai/**` (all 7)

- `RiftStalkerProfile.gd:224` and `:226`: `_rift_collapse_casts`, `_rift_collapse_kills`. This is an enemy profile (F7) and runs in live play too.
- `SpellBurnPlayerProfile.gd`:
  - `:381`: `_void_imp_dmg = prev + 100`;
  - `:405-416`: `_void_bolt_spell_casts`, `_abyssal_plague_fires`, `_abyssal_plague_kills` and `_pending_dmg_source = "void_bolt_spell"`.

  This is a player-side **sim** bot (ProfileRegistry player table :44). It is used by BalanceSimBatch, BalanceSim, ScoredAITest, VoidboltDmgDebug, ScenarioTests S25 and Parity F2, never by the live player.

### Other mutation outside cmd_*

- **`DefaultProfile.gd:14` does `agent.hand.sort_custom(...)`, which sorts the engine's own hand.** This is the real replay hazard.
  - `agent.hand` is `state.hand_of(side)` by reference (CombatAgent.gd:37 → StateAgent.gd:29).
  - `_log_command` records `hand_index = hand_of(side).find(inst)` (CombatState.gd:3116) in sorted order.
  - `CombatSim.replay` refuses with `replay_hand_mismatch` when `hand[hand_index]` doesn't match (CombatSim.gd:128-133), and replay's hand was never sorted.
  - So replaying a fight with a "default"-profile side should fail. Traced in the code, not run.
  - "default" is CombatSim.run's default enemy profile and `ProfileRegistry.make`'s fallback for unknown ids.
  - Live and Parity don't see it, because both run the profile.
- **`CombatAgent.mana` / `essence` setters** (CombatAgent.gd:41-48 → StateAgent `set_mana` / `set_essence`): a write path with no callers.

### Why the counter writes matter less than first stated

- **`_pending_dmg_source` only sets a label.**
  - It feeds `base_source` in the Void Bolt functions (CombatState.gd:967-997) and `src_label` in hero damage (:2041-2047).
  - From there it reaches DamageInfo's `source_card`, the `damage_dealt` signal (CombatDiagnostics) and the DAMAGE_DEALT payload. No rule, handler or presenter reads `source_card`.
  - It is also redundant: the Void Bolt spell path (EffectResolver:158) already defaults the label to `"void_bolt_spell"`.
- **Replay can't observe the counters.** `CombatSim.replay` (:92-112) applies only the command log, so the counters stay 0 on replay. But replay returns only the winner and digest, and `digest_text` (CombatState.gd:2242+) excludes both counters and labels. Parity F2 is green for the same reason.
- **They still violate the rules boundary,** and the counter values reflect what the AI did, not what happened in the fight.

### Lint

- L2 (RNG) and L9 (duck typing) already scan `enemies/ai`, but no rule covers state writes there.
- L8's regex `\bstate\.\w+\s*=[^=]` misses `+=`, so don't copy it.
- L9 misses `agent.state.get(field)` with a variable key (VoidHeraldProfile.gd:349-351, `_scene_has`).

### Who reads the counters

`CombatSim.run`'s result (:332-346) → `run_many` averages (:469-478, :537-546) → BalanceSimBatch :377-386 and SimRunner :82-83. CombatDiagnostics isn't attached in batch runs (`run_many` passes false/false, :437), so it can't own the counters.

### Spark cost

`CombatProfile._effective_spark_cost` (:949-971) copies `CombatState.spark_cost_of` (:2987-3003), and the text has drifted:
- it reads `enemy_passives` whatever `agent.side` is, while the engine returns the base cost for any non-enemy side;
- it also requires `_champion_vh_summoned`.

In practice it doesn't drift: all 7 callers are enemy profiles, and the flag is always set when the champion is summoned (CombatHandlers.gd:2273). So the replacement should leave balance unchanged.

## Proposed fix

1. **Count in the engine.** Count where the spell resolves, like the existing `_vw_behemoth_plays`, and delete the profile writes.

   This changes what the counters mean:
   - rift_collapse is also in the f9, f10, f12 and f13 decks under other profiles;
   - void_bolt is cast by other player profiles;
   - `_void_imp_dmg` is currently a hardcoded +100 per play.

   Engine counting will give those rows values they didn't have before.
2. **Delete the `_pending_dmg_source` write.**
3. **`DefaultProfile`:** sort `agent.hand.duplicate()`. Consider making `CombatAgent.hand` return a copy; check first for callers that rely on identity.
4. **Delete the unused `mana` / `essence` setters,** or make them assert.
5. **Spark cost from the engine.** Add `StateAgent.effective_spark_cost(card)` → `state.spark_cost_of(...)` in StateAgent's "Costs — the engine's own numbers" section (:97-105), with a base in CombatAgent. Delete `_effective_spark_cost`.
6. **Lint L12** for `enemies/ai/**`:
   - no assignment (`=`, `+=`, `-=`, …) through `agent.state.` / `state.`;
   - no in-place mutation of `agent.hand` or the boards (`sort_custom`, `append`, `erase`, `clear`, `remove_at`);
   - no `agent.mana =` / `agent.essence =`.

   Banning `state._private` reads would hit about 42 sites; leave that as a follow-up (roadmap G4).
7. **Optional, while touching this code:** the dmg-log `__logged__` sentinel is dead, because `source_card` is never empty. As a result `_capture_damage` logs Void Bolt again after the split log at CombatState.gd:972-977.

## Verification

- **Replay probe:** `CombatSim.run` a fight with a "default" enemy, then `CombatSim.replay` its command log. The winner and digest must match. This should fail before step 3.
- **BalanceSimBatch counters:** the spell_burn and rift_stalker rows match before and after. Other rows may gain values; that's expected from step 1.
- **Win rates:** byte-identical, since the spark-cost change should be neutral. Record any shift in the task summary.
- `tools/run_checks.sh` green, including L12.

## Related

- Roadmap G (AI consolidation): profiles read through `CombatAgent` only.

## Work log

- 2026-09-25: opened from the architecture review. Verified the writes at RiftStalkerProfile :224/:226 and SpellBurnPlayerProfile :405-416.
- 2026-09-30: re-verified at `3009a60` and rewritten.
  - Added the missed `_void_imp_dmg` write and the DefaultProfile in-place hand sort (the real replay hazard).
  - `_pending_dmg_source` is label-only and redundant.
  - The counters aren't in the digest, so replay doesn't visibly diverge.
  - Corrected "no lint covers enemies/ai".
  - The counters go into the engine, not CombatDiagnostics, and the before/after check is relaxed.
  - The spark-cost change is expected to be balance-neutral.
