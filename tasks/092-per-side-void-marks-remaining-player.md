---
id: "092"
title: Per-side Void Marks and the remaining player-gated EffectResolver steps
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap §A, owner decision Q2 ("Void Marks"; the A-paths unit's "A6a" without Flesh / Forge) and the EffectResolver side gates. Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### Void Marks live on the enemy hero only

- **Storage.** One property, `enemy_void_marks` (CombatState.gd:1630-1638). Its setter journals VOID_MARKS_CHANGED with side `"enemy"`. The signal comment says "Currently only enemy_void_marks is tracked; player-side stays at 0" (:20-21).
- **Apply.** `_apply_void_mark(amount)` adds to the enemy's marks (:287-291). The VOID_MARK step only runs for the player (EffectResolver.gd:146-148):
  ```gdscript
  EffectStep.EffectType.VOID_MARK:
  	if ConditionResolver.check_all(step.conditions, ctx, null) and ctx.owner == "player":
  		ctx.state._apply_void_mark(step.amount)
  ```
- **Read.**
  - The `void_marks` multiplier reads `enemy_void_marks` for any caster (EffectResolver.gd:626). An enemy Void Detonation would scale with the marks on its own hero.
  - The conditions `void_marks_5plus` and `has_void_marks` read `enemy_void_marks` (ConditionResolver.gd:96-99).
  - The AI's lethal estimate reads `agent.state.enemy_void_marks` (CombatProfile.gd:1165-1167).
- **Void Bolt.** Two functions, picked by `ctx.owner == "player"` (EffectResolver.gd:151-161):
  - `_deal_void_bolt_damage` (CombatState.gd:952-985) adds `enemy_void_marks * void_mark_damage_per_stack`, applies Path of Corruption's hero corruption, and always hits `"enemy"`.
  - `_deal_enemy_void_bolt_damage` (:988-1001) "Does not participate in Void Marks".
- **Elsewhere.** PhaseTransition resets the enemy's marks (PhaseTransition.gd:99). `digest_text` prints the enemy's count only (CombatState.gd:2249-2251).
- **Presentation.** A "player" VOID_MARKS_CHANGED event would corrupt the enemy display:
  - ViewState writes `enemy_void_marks` whatever the event's side (ViewState.gd:91-92);
  - CombatPresenter plays the enemy mark VFX when the value exceeds the enemy view count, whatever the side (CombatPresenter.gd:218-220);
  - only CombatUI filters on `side == "enemy"` (CombatUI.gd:54-58).
- **Test.** `_void_detonation_enemy_symmetric` (CardEffectTests.gd:329-343) still carries "KNOWN BUG … no player_void_marks field exists yet" comments.

### The other player- or enemy-gated steps in EffectResolver

- **GRANT_ESSENCE** (EffectResolver.gd:128-136). The player's branch calls `gain_essence("player", …)`: not capped by `essence_max`, journaled through `emit_resources`. The enemy's branch caps at `essence_max` and writes `st.enemy_essence` directly, so no RESOURCES_CHANGED is journaled.
- **Path of Corruption** (Korrath talent). `_path_of_corruption_amplify` and `_path_of_corruption_apply_corruption` return early with `if ctx.owner != "player"` (:697, :723). The flag `_path_of_corruption_active` is one field (CombatState.gd:1869), also read by the player's Void Bolt (:962).
- **Dark Channeling** (F13 and F15 encounter passive, EncounterTable.gd:124, :142). `_dark_channeling_dmg` returns early with `if ctx.owner != "enemy"` (:739-742). The flag `_dark_channeling_active` (CombatState.gd:1792) is set by `on_enemy_spell_dark_channeling` on ON_ENEMY_SPELL_CAST (CombatHandlers.gd:1970-1993). It is cleared at the end of every `EffectResolver.run` (EffectResolver.gd:26-28). Its registry stats are at CombatSetup.gd:492-494.

Not in this task:
- GAIN_FLESH, SPEND_FLESH, GAIN_FORGE_COUNTER, SPEND_FLESH_UP_TO: task 097 (roadmap B3) moves Flesh and Forge per side.
- CONVERT_RESOURCE: task 063.
- GROW_MANA_MAX's `last_player_growth` (EffectResolver.gd:142-143): a player UI record, not a gate.

### Reachable today

Nothing changes in today's fights.
- VOID_MARK appears only in `void_bolt`'s `piercing_void` override (CardDatabase.gd:2095-2104), a player talent. The enemy's `void_bolt` (f13_a, f15_a, f15_p2) has no base VOID_MARK, so the player hero never has marks.
- `void_detonation` is not enemy content. No card uses GRANT_ESSENCE.
- Path of Corruption is a player talent. Dark Channeling is enemy-only by config, and stays so.

## Decision (owner, 2026-10-01)

- Q2: "hero resources (Flesh, Forge, Void Marks) … must all work for either side in the engine". Who has what is decided by data and config, never by `if owner == "player"` in rules code.
- Q3: record the BalanceSimBatch result. Expected: none.

## Proposed fix

1. **Marks per side.** Put `void_marks` on task 083's `SideState`, journaling VOID_MARKS_CHANGED with that hero's side on change. Add `void_marks_of(side)` and `set_void_marks(side, v)`. Keep `enemy_void_marks` as a property forwarder (getter and setter) while callers migrate. Fix the signal comment (:20-21).
2. **Apply.** `_apply_void_mark(target_side, amount)`; the log line uses the caster's log type. The VOID_MARK step drops `and ctx.owner == "player"` and marks the caster's opponent: `_apply_void_mark(_opponent_of(ctx.owner), step.amount)`.
3. **Reads are relative to the caster.**
   - The `void_marks` multiplier reads `void_marks_of(_opponent_of(ctx.owner))`.
   - So do the conditions `void_marks_5plus` and `has_void_marks`. Task 108 (roadmap D7) later parameterises the names.
   - The AI estimate reads the opponent of `agent.side`.
4. **One Void Bolt.** Merge the two functions into `_deal_void_bolt_damage(caster, base, source_minion, from_rune, is_minion_emitted)`:
   - Target: `_opponent_of(caster)`.
   - Bonus: `void_marks_of(target) * side(caster).void_mark_damage_per_stack`. The per-side stat comes from task 090.
   - Path of Corruption's hero corruption: when `side(caster).path_of_corruption_active` and not minion-emitted.
   - The VOID_BOLT journal event and the log type use the caster.
   - Keep each side's damage-log labels as today: `void_rune` / `void_bolt_spell` for the player, `enemy_void_bolt` for the enemy.
   - Keep `_void_bolt_total_dmg` counting the player's bolts only. It feeds BalanceSimBatch's `VB:` column; task 094 (roadmap B1) moves the counter off the engine.
   - The VOID_BOLT step calls it with `ctx.owner` and `ctx.from_rune`.
5. **GRANT_ESSENCE**: `ctx.state.gain_essence(ctx.owner, step.amount)` for both sides. That is the player's documented rule ("Bonus Essence this turn — not capped by essence_max", CombatState.gd:1483-1486), and it journals. It is the same rule as task 065's conversion helper (temporary excess above the max, `emit_resources`). If task 107 (roadmap D4) deletes the unused type first, skip this step.
6. **Path of Corruption**: drop the two `ctx.owner != "player"` returns and read `ctx.state.side(ctx.owner).path_of_corruption_active` (task 090's per-side stat). The hero branches already handle both `"enemy_hero"` and `"player_hero"` (:706-710, :732-736). Task 098 (roadmap B4) later moves the flag into KorrathModule.
7. **Dark Channeling**: store the caster's side with the flag. The handler records `ctx.owner` of the spell-cast event, e.g. `_dark_channeling_side: String` (`""` = inactive) instead of the bool. `_dark_channeling_dmg` amplifies when `ctx.owner == state._dark_channeling_side`.
   - Keep the clear at the end of every `EffectResolver.run` (EffectResolver.gd:26-28) exactly as it is. A nested run consuming the flag early is task 129's (roadmap I1) side-channel problem; don't change it here.
   - Update the registry stats (CombatSetup.gd:494) and the two Dark Channeling probes (TriggerHandlerTests.gd:2019, :2036).
8. **Presentation.**
   - ViewState tracks marks per side from `ev.side`.
   - CombatPresenter plays the enemy-panel mark VFX only for side "enemy".
   - Showing marks on the player hero panel waits until content gives the enemy a VOID_MARK; note it for task 127 (roadmap H6), which shares hero-panel parts.
9. **Digest.** Print both sides' marks. Parity compares live and engine within one run, so the format change is safe.
10. **PhaseTransition** keeps resetting the enemy hero's marks (`set_void_marks("enemy", 0)`).

## Verification

- New probes in `debug/tests/CardEffectTests.gd`:
  - Enemy VOID_MARK: run `[{"type": "VOID_MARK", "amount": 1}]` with `TestHarness.make_ctx(state, "enemy")`. Expect `void_marks_of("player") == 1`, `void_marks_of("enemy") == 0`, and a VOID_MARKS_CHANGED event with side `"player"` in the journal.
  - Rewrite `_void_detonation_enemy_symmetric`: `set_void_marks("player", 2)`, cast with an enemy ctx. The player hero takes 650 (500 + 50×2 + 25×2), the enemy hero takes nothing. Remove the stale "KNOWN BUG" comments.
  - `_void_detonation_with_marks` (the player cast, 650) passes unchanged.
  - GRANT_ESSENCE with an enemy ctx: `essence_of("enemy")` rises past `essence_max_of("enemy")`, and the journal has RESOURCES_CHANGED for `"enemy"`.
  - Conditions: with `set_void_marks("player", 5)`, `ConditionResolver.check_all(["void_marks_5plus"], enemy_ctx, null)` is true and with a player ctx it is false.
- New probes in `debug/tests/TriggerHandlerTests.gd`:
  - Path of Corruption for an enemy owner: `side("enemy").path_of_corruption_active = true`, an enemy corruption-school damage step on a corrupted player minion is amplified, and the same step with a player ctx is not.
  - Dark Channeling: the existing probes pass with the side-tagged flag. A player-owned DAMAGE_HERO run while the enemy's flag is set is not amplified.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the player hero never has marks today, so the merged Void Bolt adds 0 for the enemy; Dark Channeling keeps its semantics. The seeded balance fingerprint (`BalanceSimBatch -- --act N --runs 200 --seed 7`, before and after, for N = 1, 2, 3, 4; request 3 and 4 explicitly, F13 and F15 run Dark Channeling and enemy Void Bolts) diffs empty (design/TESTING.md "Refactor / extraction work"). Check the `VB:` and `DC:` columns in particular.

## Related

- Depends on: task 083 (roadmap A1) — `SideState`, where the per-side marks live.
- Depends on: task 063 — removes the CONVERT_RESOURCE gate in the same resolver block; this task removes the rest.
- Depends on: task 090 (roadmap PS-talents) — the per-side `void_mark_damage_per_stack` and `path_of_corruption_active` this task reads. (Added by the writer of this task; the plan listed only 083 and 063.)
- Related: task 097 (roadmap B3) — the Flesh and Forge step gates.
- Related: task 098 (roadmap B4) — moves the Path of Corruption flag into KorrathModule.
- Related: task 108 (roadmap D7) — parameterised conditions; the two Void Mark conditions are already owner-relative after this task.
- Related: task 107 (roadmap D4) — may delete the unused GRANT_ESSENCE / GRANT_MANA types.
- Related: task 129 (roadmap I1) — the Dark Channeling flag is one of the side-channel fields it replaces.
- Related: task 071 (roadmap E1b) — the enemy hero panel renders the view's mark count. Task 127 (roadmap H6) — hero panels.
- Related: task 094 (roadmap B1) — the `_void_bolt_total_dmg` counter.
- Related: task 082 (roadmap A0) — rows 15, 17 and 18 of its table point here.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from owner decision Q2 (the A-paths unit's A6a minus Flesh / Forge) and the D-effects unit's owner-blind reads. Added the dependency on task 090 for the per-side talent stats.

## Summary

_(filled in at /task-done)_
