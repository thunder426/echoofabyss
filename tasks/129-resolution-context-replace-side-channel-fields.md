---
id: "129"
title: Resolution context: replace the side-channel fields with the typed resolution stack
status: backlog
area: combat
priority: high
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item I1 (`design/refactors/ARCHITECTURE_ROADMAP.md` §I). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Eight CombatState fields (plus `_last_crit_attacker`) carry data from one resolution to another instead of belonging to one. Each is set in one place and read later, often from inside a nested resolution:

| Field | Set | Read / cleared | What goes wrong |
|---|---|---|---|
| `_last_attacker` (CombatState.gd:1791) | CombatManager.gd:76, :158 `state._last_attacker = attacker` | cleared only at the end of the attack (:153, :186); read CombatState.gd:1989 (MINION_DIED payload) and :2008 `ctx.attacker = _last_attacker` | every death during the attack is credited to the attacker |
| `_last_attack_was_crit` (:1788) | `_apply_crit`, CombatManager.gd:363 | cleared :154, :187; read CombatManager.gd:277, CombatState.gd:2020, CombatHandlers.gd:1780 | every damage event inside a crit attack counts as a crit |
| `_last_crit_attacker` (:1787) | CombatManager.gd:360 | `_check_post_crit` :415-417 | same pattern; harmless today |
| `_pending_dmg_source` (:1973) | CombatState.gd:971 / :977, :994 / :997, :2803; SpellBurnPlayerProfile.gd:408 | read :967, :991; read and cleared only in the enemy-hero branch (:2044-2047) | leaks into later damage labels |
| `attack_cancelled` (:1405) | HardcodedEffects.gd:206-207 `if opponent == "enemy": state.attack_cancelled = true` | :3092-3093 in `_fire_enemy_attack_declared` | only enemy attacks can be cancelled; set outside an attack it cancels the next enemy attack |
| `_spell_cancelled` (:1740) | EffectResolver.gd:264 `ctx.state._spell_cancelled = true` | :2650-2651 | set outside a spell it cancels the next spell of either side |
| `enemy_play_target` (:1408) | :2583-2584 `if side == "enemy": enemy_play_target = target` | CombatHandlers.gd:981-982 | one-sided; the player path uses `played_ctx.target` (:2590-2591) |
| `_silent_buff_apply` (:109) | CombatHandlers.gd:1059-1071 save / set / restore | EffectResolver.gd:475, :487 | re-entrancy-safe, but state-wide |
| `_dark_channeling_active` (:1792) | CombatHandlers.gd:1987, the F13 / F15 Dark Channeling handler on an enemy damage spell's cast | read in `_dark_channeling_dmg` (EffectResolver.gd:739-754); cleared at the end of whichever `EffectResolver.run` finishes next (:27-28) | a nested run inside the spell (e.g. the on-death effect of a minion it kills) clears the flag before the spell's later steps; an enemy-owned nested damage step takes the ×1.5 itself |

No trap or spell resolves inside an attack today: ON_ENEMY_ATTACK traps fire in `_fire_enemy_attack_declared` (:2775) before `resolve_minion_attack` sets `_last_attacker`. What does nest inside an attack is on-death effects, corruption-removed triggers and champion effects, and those pick up the attacker and its crit flag.

### Reachable today

1. **Kill credit goes to whoever is attacking.**
   - Readers of `ctx.attacker`: `on_minion_killed_on_kill_steps` (Matron of Flesh, CombatHandlers.gd:729-742), `on_enemy_died_grafted_constitution` (Grafted Fiend kill stacks, :830-834) and `on_player_died_champion_vch` (F14 Void Champion, :1773-1781).
   - Matron gaining Flesh for her own death and for friendly deaths is fixed narrowly by task 059 (owner check).
   - After 059 a nested enemy death still credits the attacker. Example: a Grafted Fiend's attack sets off an effect that kills a second enemy minion (any on-death or corruption-removed chain, e.g. Seris's Corrupt Detonation, CombatHandlers.gd:884-905). The Fiend gets a kill stack (+100/+100) for a kill it didn't make.
   - A counter-attack kill credits nobody: `ctx.attacker` is the dying attacker itself, never the defender. A defending Grafted Fiend or Matron gets nothing for a counter-kill.
2. **F14 counts the wrong deaths.** `on_player_died_champion_vch` (:1780) checks `state._last_attack_was_crit`, so any player death during an enemy crit attack counts as a crit kill, not only the strike's. Task 060 fixes the journal's `is_crit` but leaves this handler on the flag.
3. **Damage labels leak.**
   - `_deal_enemy_void_bolt_damage` sets `_pending_dmg_source = base_source` (:994, or `"__logged__"` at :997 with diagnostics). The player-hero branch of `_on_hero_damaged` (:2023-2036) never clears it, so the next player Void Bolt is labelled `"enemy_void_bolt"` (:967 `var base_source: String = _pending_dmg_source`). The enemy casts Void Bolt in f13_a, f15_a and f15_p2.
   - `_cmd_attack_hero` sets `"%s_atk"` (:2803). When armour reduces the hit to 0, `apply_hero_damage` returns early (CombatManager.gd:207-209) and the label stays set for the next Void Bolt.
   - Label-only: it reaches DamageInfo `source_card`, the DAMAGE_DEALT payload and the sim damage log. No rule or presenter reads it.

### Latent

- A Smoke Veil or Silence Trap resolved outside an attack or spell leaves its flag set. `CardEffectTests._smoke_veil` (CardEffectTests.gd:351-370) already does this on its state.
- Both cancels are one-sided: Smoke Veil sets the flag only when its owner is the player, and only `_fire_enemy_attack_declared` reads it (side `"enemy"`, :3086-3093). PvP is planned (Q1), so the cancel API has to work for either side.
- Every new "when this kills" or "on crit" card inherits the leaks.
- AI look-ahead (Q7b) needs resolution state that lives inside one resolution, not on the state between commands.

### Stale comments and tests

- EventContext.gd:18: `ctx.attacker` is "Populated from scene._last_attacker".
- EffectStep.gd:47: "set scene._spell_cancelled" (task 055 rewords it; this task deletes the flag).
- CardEffectTests.gd:374-387: Silence Trap labelled "KNOWN BUG: `_spell_cancelled` is not a declared field" and read with `state.get("_spell_cancelled")`. The field is declared (:1740).
- EventContext.gd:44-46 declares `cancelled` ("Null Seal cancels a spell"); nothing sets or reads it.
- Tests that write the fields directly: TriggerHandlerTests.gd:258, :291 (`_last_attacker` + `kill_minion`), :1459 (`_last_attack_was_crit`); CommandTests.gd:224 (`enemy_play_target`), :283 / :290 (`_spell_cancelled`), :447 (`attack_cancelled`).

## Decision (owner, 2026-10-01)

- Q7b: AI look-ahead is planned. Task 049, task 130 (roadmap I2) and this task are prerequisites, so the priority is high.
- Q1 / Q2: PvP is planned and no mechanic is one-sided by design. The Resolution API is side-neutral from the start. The trap routes themselves stay with task 086 (roadmap A3, phase A3b).
- Q3: accept balance shifts; record the BalanceSimBatch delta.
- **Open (raised in grooming, unit I): kill credit.** Does a counter-attack kill count as "this minion kills"? Do kills by effects nested in an attack count for the attacker? Grooming default (the owner may override): **credit goes to the minion whose own strike or counter dealt the killing damage; nested kills credit nobody.** "Strike only" is a one-line change in step 9.

## Proposed fix

Task 114 (roadmap F1) creates `combat/board/Resolution.gd` and the stack (`state.resolutions`, a ResolutionStack with `push` / `pop` / `top`; kinds COMMAND / ATTACK / STRIKE / COUNTER / SPELL / TRAP / TRIGGER / VOID_BOLT / RITUAL). This task extends the same class; there is one stack, not two. Resolution holds no reference back to CombatState (049).

Land it as three commits: steps 1-8 are behaviour-neutral, step 9 changes the kill-credit rule, step 10 changes Dark Channeling's scope.

**Behaviour-neutral (one commit):**

1. **Fields on Resolution.** F1's Resolution already has `side`. Add typed `attacker: MinionInstance`, `crit_spent: bool`, `cancelled: bool`, `silent_buffs: bool`, `dark_channeling: bool`. Add `CombatState.open_resolution(kind) -> Resolution` (the innermost open one of that kind, or null).
2. **Open the ATTACK resolution at the declaration.** Push it in `_cmd_attack` / `_cmd_attack_hero` right after `_log_command` (:2774, :2798), before `_fire_enemy_attack_declared`, with `side` and `attacker` set. `resolve_minion_attack(_hero)` reuses an open ATTACK resolution, or pushes its own when called bare (tests). This moves F1's `attack` push up.
3. **Open the SPELL resolution before the cast trigger.** Push it in `_cmd_play_spell` before the ON_*_SPELL_CAST fire (:2645-2649) and pop it after resolution. `cast_player_targeted_spell` / `cast_player_hero_spell` / `cast_enemy_spell` are only called from there (:2658-2662), so F1's `spell` push moves here.
4. **Cancels.**
   - Add `cancel_open(kind, victim_side)`: it sets `cancelled` on the open resolution of that kind when its `side == victim_side`, and does nothing otherwise.
   - Smoke Veil (HardcodedEffects.gd:206-207) calls `cancel_open(ATTACK, _opponent_of(ctx.owner))`, with no `opponent == "enemy"` test.
   - CANCEL_OPPONENT_SPELL (EffectResolver.gd:260-265) calls `cancel_open(SPELL, opponent)`.
   - `_cmd_attack` / `_cmd_attack_hero` check the ATTACK resolution's `cancelled` after the declaration fire, for either side. The declaration event stays enemy-only until task 086 (A3a).
   - `_cmd_play_spell` checks the SPELL resolution's `cancelled` where it reads `_spell_cancelled` today (:2650).
   - Delete `attack_cancelled`, `_spell_cancelled` and the unused `EventContext.cancelled`.
5. **Crit.** Task 060 already carries crit on the strike's DamageInfo.
   - `_apply_crit` sets `crit_spent` on the ATTACK resolution instead of `_last_crit_attacker` / `_last_attack_was_crit`. `_check_post_crit` reads it.
   - `on_player_died_champion_vch` reads `ctx.damage_info.is_crit` (step 6 sets `damage_info` on death events).
   - Delete both fields.
6. **Kill credit, today's rule.**
   - Pass the killing DamageInfo with the death: a second argument on `minion_vanished` (null from `kill_minion`), or a direct `state._on_minion_vanished(minion, info)` call.
   - `_on_minion_vanished` sets `ctx.damage_info = info` on ON_*_MINION_DIED. It sets `ctx.attacker` to the attacker of the nearest enclosing ATTACK resolution, which is exactly today's `_last_attacker`.
   - MINION_DIED's `payload.attacker` comes from the same place; nothing reads it today.
   - Delete `_last_attacker`.
7. **On-play target.** Add `EventContext.play_target: Variant`. `_cmd_play_minion` sets it for both sides (:2585-2591). `on_enemy_minion_played_effect` reads `ctx.play_target` and maps it to `chosen_target` / `chosen_object` as today (:992-995). The player handler keeps `ctx.target`. Delete `enemy_play_target`. Task 086 (A3c) later merges the two on-play handlers.
8. **Silent buffs and damage labels.**
   - `_refresh_presence_auras_for_side` (CombatHandlers.gd:1020) pushes its own resolution with `silent_buffs = true` around the strip and re-apply, replacing the save / restore at :1059-1071.
   - EffectResolver (:475, :487) reads `state.buffs_silent()`, which is true when any open resolution sets it. That matches today's state-wide flag. Delete `_silent_buff_apply`.
   - Delete `_pending_dmg_source` and its uses (:967-977, :991-997, :2040-2047, :2803). `_deal_void_bolt_damage` labels the hit `"void_rune"` / `"void_bolt_spell"` (or a label its caller passes), and the enemy one `"enemy_void_bolt"`. `_on_hero_damaged` uses `info.source_card`, else the generic label.
   - Task 051 step 2 has already removed SpellBurnPlayerProfile's write. Its step 7 owns the `"__logged__"` double-log: keep one dmg-log entry per hit.

   Fix the stale comments listed above, and update ARCHITECTURE.md (CombatState field list, the CombatManager signal row if step 6 changes `minion_vanished`).

**Kill-credit rule (second commit, behaviour change):**

9. `_on_minion_vanished` credits the killer only when the innermost open resolution at the death is the `strike` or `counter` of an ATTACK. Then `ctx.attacker = info.attacker`: the attacker for a strike kill, the defender for a counter kill (`_attack_damage_info(counter_damage, defender)`, CombatManager.gd:138). Every other death gets `ctx.attacker = null`.
   - Matron's on-kill and Grafted Fiend's kill stacks then fire for counter-kills by a defending minion, and no longer for nested kills.
   - F14 is unaffected: a counter carries no crit.
   - If the owner picks "strike only", accept only `strike`.
   - Optional, same commit: rename `EventContext.attacker` to `killer`, since it no longer means "the minion that was attacking". Its readers are the three handlers above, plus `TestHarness.fire`'s `attacker` field (TestHarness.gd:190-210).

**Dark Channeling scope (third commit, behaviour change):**

10. The Dark Channeling handler (CombatHandlers.gd:1987) sets `dark_channeling` on the open SPELL resolution (step 3 opens it before the cast trigger). `_dark_channeling_dmg` amplifies only when the innermost SPELL / TRIGGER / TRAP resolution is that SPELL, so nested on-death and trap damage is never amplified and can't clear it. Delete `_dark_channeling_active` and the clear at EffectResolver.gd:27-28. If task 092 has landed, its caster-side tag becomes this field. Record the BalanceSimBatch delta (Act 4: F13 and F15 run Dark Channeling).

## Verification

- **Rewritten tests (neutral commit):**
  - TriggerHandlerTests.gd:247-263 (`_grafted_constitution`) and :284-295 (`_predatory_surge_siphon`) build the kill with `state.combat_manager.resolve_minion_attack(fiend, enemy)` instead of `_last_attacker` + `kill_minion`.
  - `_fire_player_died_by_crit` (:1457-1463) sets `ctx.damage_info` with `is_crit = true`.
  - CommandTests.gd:224 reads `ctx.play_target`.
  - `_play_spell_cancelled_by_silence` (:274-291) and `_attack_enemy_cancelled_by_smoke_veil` (:436-448) assert the reason and the outcome, not the flag.
  - CardEffectTests `_silence_trap` (:377-387) runs the trap inside an enemy `cmd_play_spell`, and the KNOWN BUG comment goes.
- **New CommandTests probe "cancel outside an attack is dropped":** `build_state({})`; run `smoke_veil`'s `effect_steps` with `TestHarness.make_ctx(state, "player")` and no attack in flight. Then `_enemy_turn(state)`, `e := _ready_minion(state, "enemy", "shadow_hound")` and `cmd_attack_hero("enemy", e)`. Assert the reason is not `"cancelled"` and `player_hp` dropped (today the leaked flag cancels it).
- **New CommandTests probe "silence outside a spell is dropped":** run `silence_trap`'s steps the same way, then the player casts the `_cmd_bolt` test spell from `_play_spell_cancelled_by_silence` on an `abyssal_brute`. Assert it resolved and dealt 200.
- **New CommandTests probe "label does not leak":** `build_state({})`; `state._deal_enemy_void_bolt_damage(100)`, then `state._deal_void_bolt_damage(100)` (the paths EffectResolver.gd:157-160 take for each side). The player bolt's hero DAMAGE_DEALT has `source_card == "void_bolt_spell"` (today `"enemy_void_bolt"`).
- **Stack hygiene:** F1's end-of-command check (the stack is empty after every `cmd_*`) stays silent across RunAllTests and Parity.
- **Dark Channeling probe (third commit),** in `debug/tests/TriggerHandlerTests.gd` next to the channeling probes (:2019, :2036): with the flag set by an enemy damage spell that kills a player minion whose on-death runs EffectResolver steps, every later damage step of that spell is still ×1.5 (today the nested run clears it), and the nested on-death damage is not.
- **Kill-credit probes (second commit),** in `debug/tests/TriggerHandlerTests.gd`, with `TestHarness.seris_state(["flesh_infusion"])`:
  - *Nested kill gets no credit.* `fiend = spawn_friendly(state, "grafted_fiend")`; `x = spawn_enemy(state, "rabid_imp")` with HP at or below the Fiend's ATK; `y = spawn_enemy(state, "rabid_imp")`. Register a one-shot test handler on ON_ENEMY_MINION_DIED (priority 99) that kills `y` with `combat_manager.apply_damage_to_minion(y, CombatManager.make_damage_info(5000, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "test"))`. `resolve_minion_attack(fiend, x)`. Assert `fiend.kill_stacks == 1` (today 2).
  - *Counter-kill credits the defender* (only if the owner keeps the default). `imp = spawn_enemy(state, "rabid_imp")` with HP at or below the Fiend's ATK, Fiend HP above the imp's ATK; `resolve_minion_attack(imp, fiend)`. Assert `fiend.kill_stacks == 1` (today 0).
- `tools/run_checks.sh` green.
- **Neutral commit:** behaviour-neutral. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, Acts 1-4) diffs empty (design/TESTING.md 'Refactor / extraction work').
- **Kill-credit commit:** behaviour change. Record the BalanceSimBatch delta in the task summary, requesting Acts 3-4 explicitly. Expect movement in the `seris_fleshcraft` rows (BalanceSimBatch.gd:57-66, Grafted Fiends with `flesh_infusion`). F14 is expected unchanged; record it if it shifts.

## Related

- Depends on: task 114 (roadmap F1) — creates the Resolution class, the stack and its push sites; this task extends them.
- Depends on: task 134 (roadmap I6) — phase a's typed DamageInfo carries `is_crit`, `attacker` and the kill info that steps 5-6 rely on.
- Depends on: task 059 — the narrow Matron owner check lands first, so the neutral commit stays neutral.
- Depends on: task 060 — crit on the strike's DamageInfo lands first; this task then deletes `_last_attack_was_crit` and moves the F14 check.
- Depends on: task 051 — step 2 removes SpellBurnPlayerProfile's `_pending_dmg_source` write (it would no longer compile); step 7 owns the dmg-log sentinel.
- Related: task 092 (roadmap PS-void-marks) — replaces the `_dark_channeling_active` bool with a caster-side tag but keeps the clear at the end of every `EffectResolver.run`; step 10 moves the tag onto the SPELL resolution.
- Related: task 062 — notes that an enemy Abyssal Tide trigger nested in a channeled spell would take ×1.5 and clear the flag; step 10 fixes that.
- Related: task 131 (roadmap I3) — phase b adds `aborted` to the same Resolution (PhaseTransition, lethal hit).
- Related: task 057 — its spent-attack exit clears `_last_attacker` / `_last_attack_was_crit`; after this task that exit just pops the ATTACK resolution.
- Related: task 086 (roadmap A3) — A3a adds enemy PRE/POST and a side-neutral attack declaration; A3b adds enemy trap routes (an enemy Smoke Veil then works through `cancel_open`); A3c merges the on-play handlers.
- Related: task 115 (roadmap F2) — consumes F1's cause ids; the strike / counter resolutions it matches on are the ones step 9 reads.
- Related: task 055 — rewords EffectStep.gd:47; this task removes what it describes.
- Related: task 133 (roadmap I5) — the digest extension; nothing in the stack is digest state.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item I1. Re-checked every set and read site at `404b51c`. Corrected the roadmap's example: no trap or spell resolves inside an attack today; the nesting is on-death, corruption and champion effects. Added `_last_crit_attacker`, the unused `EventContext.cancelled` and the `_pending_dmg_source` label leak. Split the work into a neutral commit and a kill-credit commit, because the credit rule is an open owner question.

## Summary

_(filled in at /task-done)_
