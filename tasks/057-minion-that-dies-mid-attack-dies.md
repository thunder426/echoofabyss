---
id: "057"
title: A minion that dies mid-attack dies twice (on-death effects and death triggers run again)
status: done
area: combat
priority: high
started: 2026-10-02
finished: 2026-10-02
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §F and §I, unit F bug 3). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Nothing on the damage or death path checks that a minion is still on the board:
- `CombatManager._deal_damage` (CombatManager.gd:244-300) returns early only for `damage <= 0` and `has_immune()`. On a minion already at 0 HP it subtracts again, journals DAMAGE_DEALT (:273-277), and at :279-300 reaches `minion_vanished.emit(minion)` a second time.
- `kill_minion` (:335-339) has no check either. These are the only two `minion_vanished.emit` sites.
- `CombatState._on_minion_vanished` (CombatState.gd:1985-2009) has no guard. For a minion already off the board `slot_for` returns null (slot -1), and it still journals MINION_DIED (:1989), fires ON_CORRUPTION_REMOVED if the minion still holds Corruption (:1998-2003), and fires ON_*_MINION_DIED (:2004-2009).
- `resolve_minion_attack` (CombatManager.gd:74-154) never re-checks the defender after the ON_PLAYER_ATTACK_PRE triggers (:85-89), and never re-checks the attacker before the counter (:132-138).

So every death listener runs twice: the minion's own on-death steps (`_resolve_on_death`, CombatHandlers.gd:712-723), on-kill steps (:729-742), Seris's Fleshbind (+1 Flesh per Demon death, :812-817), the presence-aura recompute, and the champion death counters.

### Reachable today

1. **Fight 2: a minion that kills a Void-Touched Imp and dies to its on-death AoE dies again to the counter.**
   - Void-Touched Imp (200/300, CardDatabase.gd:2657-2667): `"ON DEATH: Deal 100 damage to all enemy minions."` It is in all three fight-2 decks (f2_a ×3, f2_b ×4, f2_c ×4).
   - A player minion with ≤ 100 HP left kills a VTI with its strike (:100). `_on_minion_vanished` → ON_ENEMY_MINION_DIED → the AoE kills the attacker: MINION_DIED #1, ON_PLAYER_MINION_DIED #1.
   - Back in `resolve_minion_attack`, the counter `_deal_damage(attacker, _attack_damage_info(counter_damage, defender))` (:138) hits the dead attacker: HP 0 → -200, a DAMAGE_DEALT, then MINION_DIED #2 and ON_PLAYER_MINION_DIED #2.
   - Seris's `seris_fleshcraft` preset runs two 100/100 Void Imps, so a full-HP imp is enough, and Fleshbind gives +2 Flesh for the one death. Lord Vael's imps are 200/200 (`void_imp_boost`, CardModRules.gd:50-56), so for Vael it takes a damaged minion.
2. **Korrath Runic Knight: a PRE trigger kills the defender; the strike hits the corpse and the corpse counter-attacks.**
   - Runeforge Strike (T0) places a rune from ON_PLAYER_ATTACK_PRE (CombatHandlers.gd:250-256 → `_korrath_place_random_rune`, CombatState.gd:1888-1907). With 2 runes up, the 3rd fires ON_RUNE_PLACED → Grand Ritual: Chaos (T3, CombatHandlers.gd:318-366): Burst 200–400 to a random enemy minion and Sweep 100–250 to every enemy minion; one of its three effects is ×3.
   - If that kills the defender, `resolve_minion_attack` carries on:
     - `_apply_crit` (:90) spends a Critical Strike stack on a strike that has no target;
     - the strike hits the corpse: a second MINION_DIED, so a Brood Imp summons a second pair of Void Sparks and a VTI's AoE fires twice;
     - POST fires on a dead defender;
     - with Pierce, the whole strike carries to the hero, because `pre_hp` is 0 (:120-125);
     - `counter_damage = defender.effective_atk()` (:133) lets a minion that died before the strike hit the Knight.
   - BalanceSimBatch has no Korrath preset (`_PRESET_CONFIG`, BalanceSimBatch.gd:22-90), so no sim covers this path.

(Deck contents: `EncounterDecks` in the repo since task 047.)

### Same class, smaller

- **Deathless Flesh on a corpse (latent).** The second death calls `_try_save_from_death` (CombatState.gd:1111-1122) on a minion that is already off the board. With `deathless_flesh` and ≥ 2 Flesh it spends 2 Flesh and sets HP 50 on the corpse.
- **Siphon heals a dead attacker.** `_siphon_self_heal` (CombatManager.gd:400-409) runs after the counter (:145-146). If the counter killed the attacker, it raises the off-board corpse's HP above 0 and journals MINION_HEALED. Siphon is reachable through Predatory Surge (CombatState.gd:1199-1200). Nothing reads the healed corpse today.
- **Mid-AoE (latent).** EffectResolver resolves its targets once (EffectResolver.gd:428-432). If a death trigger in the same resolution kills a later target, the next `_apply` hits a corpse. No current card was traced doing this; the same guard covers it.

## Decision (owner, 2026-10-01)

- Q2: no mechanic is one-sided by design. Task 086 (roadmap A3, phase A3a) gives enemy attacks PRE/POST triggers, so every guard here is side-neutral, with no `owner == "player"`.
- Q3: accept balance shifts and record the deltas.

## Proposed fix

Grooming default for a defender that leaves the board during the PRE triggers (the owner may override it): **the attack is spent.** The `attack_count` / EXHAUSTED bookkeeping is kept, and there is no strike, no POST, no pierce and no counter.

1. Add `CombatState.is_on_board(m: MinionInstance) -> bool`: `m != null and (slot_for(m) != null or _friendly_board(m.owner).has(m))`.
   - It checks the slot as well as the board array because a minion being played sits in its slot before it joins the array: ON_*_MINION_PLAYED fires in between (CommandTests `_play_minion_event_order`).
   - Task 131 (roadmap I3, phase b) later replaces this with `MinionInstance.zone`.
2. `CombatManager._deal_damage`: right after `last_post_armour_damage = 0` (:245), return when `state != null` and (`minion.current_health <= 0` or `not state.is_on_board(minion)`). Do the same at the top of `kill_minion` (:335). Bare CombatManager tests (`state == null`) keep today's behaviour.
3. `CombatState._on_minion_vanished`: return at the top when `not is_on_board(minion)`. This is defence in depth; with step 2 it should never trigger. Don't use the HP check here: HP is already 0 on the first, legitimate call.
4. `resolve_minion_attack`, after the PRE fire (:89): if the defender or the attacker is no longer on the board:
   - `attacker.attack_count += 1` and `attacker.state = Enums.MinionState.EXHAUSTED`;
   - clear `_last_attacker` and `_last_attack_was_crit` as the normal exit does (:152-154);
   - optionally `_log` that the attack was spent;
   - return.

   `_apply_crit` runs after PRE, so a spent attack keeps its Critical Strike stack. The presenter already copes with an attack that has no strike event: `damage` is 0 and no popup is shown (CombatPresenter.gd:575-584).
5. Before the counter (:132): skip the counter and `_siphon_self_heal` when `not state.is_on_board(attacker)`. Lifedrain (:142-143) heals the hero and stays as it is.
6. `resolve_minion_attack_hero`: the same early exit after PRE (:167) when the attacker left the board.
7. Update the stale POST comment at :106-109 ("if defender died, AB lands on a dead minion harmlessly"). It is still true when the strike kills; it no longer applies when PRE does. The "fired from CombatScene's enemy attack path" wording at :83-84 is task 088's, and task 086 phase 4 rewrites the rest of :78-84.

## Verification

New probes in `debug/tests/TriggerHandlerTests.gd`. Count events from `state.journal` after a recorded start index, as `CommandTests._journal_order_spell_kill_on_death_summon` does.
- **Death trigger kills the attacker once.**
  - Setup: `TestHarness.seris_state()`. `imp = spawn_friendly(state, "void_imp")` (100/100 Demon), `vti = spawn_enemy(state, "void_touched_imp")`, `vti.current_health = 100`. Record `player_flesh`, then `state.combat_manager.resolve_minion_attack(imp, vti)`.
  - Assert exactly one MINION_DIED whose `payload.minion == imp`, and no DAMAGE_DEALT on `imp` after it.
  - Assert Flesh +1 from Fleshbind (today +2).
- **PRE kills the defender: the attack is spent.**
  - Setup: `TestHarness.korrath_state(["runeforge_strike", "runic_absorption", "grand_ritual_chaos"])`, with `void_rune` and `blood_rune` appended to `active_traps` (as `_grand_ritual_chaos_consumes_three_runes` does, :2983). `knight = spawn_friendly(state, "abyssal_knight")` with 1 Critical Strike stack. `brood = spawn_enemy(state, "brood_imp")`, `brood.current_health = 50`. Then `resolve_minion_attack(knight, brood)`.
  - Assert exactly one MINION_DIED for `brood`, and no DAMAGE_DEALT on `knight` (no counter).
  - Assert `knight.attack_count == 1`, the knight is EXHAUSTED, and it still has its Critical Strike stack.
- **A minion being played still takes damage** (`debug/tests/CommandTests.gd`, next to `_play_minion_event_order`).
  - Setup: register a test handler on ON_PLAYER_MINION_PLAYED that deals 100 to `ctx.minion` through `combat_manager.apply_damage_to_minion`. The player then plays a minion with `cmd_play_minion` (helpers `_hand_card`, `_set_res`); use one with more than 100 HP.
  - Assert its HP dropped by 100. This guards the slot half of `is_on_board`.
- **Guard unit check.** `kill_minion(m)`, then `_deal_damage(m, …)` and `kill_minion(m)` again: no new DAMAGE_DEALT or MINION_DIED.
- `tools/run_checks.sh` green.
- Behaviour change: record the BalanceSimBatch delta in the task summary. Request Acts 3–4 explicitly (`-- --act 3`, `-- --act 4`), since BalanceSimBatch defaults to Acts 1–2. Expect movement in fight 2 (VTI decks), mostly in the Seris rows. The Korrath half has no sim preset; the probe is its only cover.

## Related

- Related: task 131 (roadmap I3) — depends on this task; its `zone` field replaces `is_on_board`, and its phase b aborts an in-flight attack after the F15 phase change.
- Related: task 086 (roadmap A3) — phase A3a adds enemy attack PRE/POST; it must keep this task's defender/attacker check after PRE.
- Related: task 115 (roadmap F2) — the same VTI and Grand Ritual traces also show the wrong numbers on the attack lunge (the AoE shown as the counter, the sweep shown as the strike). This task removes the second death; task 115 fixes the pairing. After this task a spent attack journals ATTACK_STARTED with no strike event (the lunge plays with no popup); task 115 decides whether F2 shows anything for it.
- Related: task 059 (Matron of Flesh) — same VTI trace, different bug (kill credit).
- Related: task 061 (Deathless label) — the other `_try_save_from_death` path.
- Related: task 097 (roadmap B3) — moves `_try_save_from_death` into the per-side Seris module.
- Related: task 114 (roadmap F1) — edits the same lines of `resolve_minion_attack` (:89-138); whichever lands second keeps F1's STRIKE / COUNTER pushes around the strike and counter calls that remain after this task's board checks.
- Related: task 129 (roadmap I1) — replaces this task's `_last_attacker` / `_last_attack_was_crit` clearing in the spent-attack exit with popping the ATTACK resolution.
- Related: task 110 (roadmap E3, phase E3b) — adds `state._refresh_slot_for(attacker)` at the end of `resolve_minion_attack(_hero)`, guarded by "still on the board"; it should use this task's `is_on_board`.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from unit F's straight-to-task bug 3 (roadmap §F/§I). Re-checked the trace at `404b51c`: no alive or board check in `_deal_damage`, `kill_minion` or `_on_minion_vanished`. Added the Siphon-heals-a-corpse case. `is_on_board` is defined on slot or board because played minions sit in their slot before joining the board array.
- 2026-10-02: started (P2 ticket 1). Owner confirmed the default: a PRE trigger that removes the defender or the attacker spends the attack.
  - Checked first: nothing outside `_deal_damage` / `kill_minion` drives a board minion's HP to ≤ 0 (no negative HP content; HP-buff removal doesn't lower `current_health`), so the HP half of the `_deal_damage` guard can't strand a live minion. `_transfer_to_player_board` updates `owner`, so `is_on_board` holds for a transferred spark.
  - Fix as proposed (steps 1–7). `kill_minion` checks only `is_on_board`, not HP: a kill bypasses health checks. The spent-attack exit is `CombatManager._spend_attack` (attack_count, EXHAUSTED, a LOG line, clear `_last_attacker` / `_last_attack_was_crit`); it doesn't emit the unheard `attack_resolved` (task 132 deletes it). The counter block resets `last_counter_*` to 0 when skipped (no readers outside CombatManager).
  - Probes: TriggerHandlerTests `attack /` ×4 (VTI death trigger, PRE kills the defender, PRE removes a hero attacker, dead-minion guard) and CommandTests `_play_minion_played_handler_can_damage_it`. All four TriggerHandler probes fail on the old engine (10 assertions: 2 MINION_DIED, +2 Flesh, a counter on the Knight, the crit stack spent, 100 hero damage from a dead attacker).
  - `_fiend_offering` asserted the bug: it sacrificed a Grafted Fiend and then called `kill_minion` on the off-board corpse, expecting a second Fleshbind tick (3 → 3). Sacrifice is not death; the probe now expects 3 − 2 + 1 = 2.
  - Not changed, noted for task 086: the enemy path (`_cmd_attack`) returns `target_gone` / `attacker_gone` after ON_ENEMY_ATTACK without spending the attack, while the player's PRE path now spends it.
  - Gate: run_checks green (lint 0, 197 scripts, 1146 tests, LiveSmoke OK, Parity 24/24).
  - Fingerprint (`--runs 200 --seed 7`) vs `6d58afb`, saved in `.fingerprints/057/`:
    - Act 1: two f2_c rows (DeathCircle win 74.0 → 73.5%; S.Forge HP −2).
    - Act 2: the biggest mover is F4 (the Patrol detonating corruption was another double-death source): DeathCircle f4_a/f4_b win −0.5 to −1.5 pts, S.Forge f4_b ±0.5, S.Corr f4_b unchanged; F5 S.Corr ±1 pt, S.Forge +0.5; F6 within 0.5 pt.
    - Act 3: one diagnostic counter (BehL b255 → b254).
    - Act 4: S.Corr rows only. F11 win within ±1 pt (MS+BC 75.0 → 74.0%), F12 HP +4, F15 HP within ±7; the Behemoth / Bastion death-cause counters and DCrit drop slightly (no death counted twice).
    - Less movement in the F2 Seris rows than the grooming expected: the VTI-kills-the-attacker trace is rare in the sim.
- 2026-10-02: closed.

## Summary

A minion now dies once. Damage and `kill_minion` skip a minion that is dead or off the board (`CombatState.is_on_board`: slot or board array), `_on_minion_vanished` guards too, and an attack whose defender or attacker leaves the board during PRE is spent (attack_count, EXHAUSTED, crit stack kept; no strike, POST, pierce or counter). The counter and Siphon skip an attacker the strike's death triggers already killed. Balance delta is small (≤ 1.5 pts, mostly F4 and Act 4 S.Corr rows). The stale `_fiend_offering` probe, which asserted a sacrificed Fiend could still die, now expects one Fleshbind tick.
Follow-ups: task 086 should make the enemy path spend an attack whose target is gone after ON_ENEMY_ATTACK (today it returns `target_gone` without spending); task 131 replaces `is_on_board` with `MinionInstance.zone`.
