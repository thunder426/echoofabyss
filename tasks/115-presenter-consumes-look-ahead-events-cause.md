---
id: "115"
title: Presenter consumes look-ahead events by cause; fixes the Void Bolt double popup and the wrong attack-lunge numbers
status: backlog
area: ui
priority: high
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item F2 (`design/refactors/ARCHITECTURE_ROADMAP.md` §F). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

This task also absorbs roadmap F's LiveSmoke probe and two reachable presenter bugs found while grooming: unit F bugs 1–2, and unit E bug 3, which is the same Void Bolt bug.

The presenter looks ahead in the journal and pairs events with animations by kind and position:
- **Minion attack.** `_play_attack` (CombatPresenter.gd:568-574) takes the first DAMAGE_DEALT on the defender as the strike and the first on the attacker as the counter: `elif hit_a == null and _is_minion_damage(e, attacker):`.
- **Hero attack.** The hero-attack path (:539-543) takes the first hero damage in the window.
- **Spell.** `_play_spell` (:452-469) captures every DAMAGE_DEALT / CORRUPTION_APPLIED / HERO_HEALED / MINION_HEALED up to SPELL_RESOLVED. It skips a DAMAGE_DEALT only when it comes right after a VOID_BOLT: `capture = prev_kind != CombatEvent.Kind.VOID_BOLT` (:463), with `prev_kind = e.kind` set on every event (:469).
- **Void bolt.** `_play_void_bolt` (:413-429) takes the first hero damage within `_peek_window(8)`.
- **Double claims.** `_peek_window` (:145-154) doesn't skip seqs already in `_consumed`, so two look-aheads can claim the same event.
- **Shared capture.** `_spell_pending` (:39, :476-489) is one member shared by every spell.

### Reachable today

1. **Void Bolt's hit pops twice** (unit F bug 1, unit E bug 3).
   - Void Bolt is `{"type": "VOID_BOLT", "amount": 500}` (CardDatabase.gd:2084-2091). A player cast journals, in order:
     - SPELL_CAST (CombatState.gd:525);
     - LOG "Void Bolt: 500 damage." (:966), then VOID_BOLT (:970);
     - `apply_hero_damage` → `_on_hero_damaged`: the `enemy_hp` setter journals HERO_HP_CHANGED (:1258), then LOG "Enemy takes …" (:2048), then the ON_ENEMY_HERO_DAMAGED triggers (:2052), then DAMAGE_DEALT (:2061);
     - SPELL_RESOLVED (:539).
   - The rule at :463 sees `prev_kind` = LOG (or a trigger's event), never VOID_BOLT, so it captures and consumes the hit. The rule has never matched.
   - `void_bolt` has no `_SPELL_DISPATCH` entry (VfxController.gd:21-27), so `play_spell` calls `resolve_damage.call(0)` at once (:65-66). The hero flashes and "-500" pops right after the cast preview, before any projectile.
   - VOID_BOLT then plays. `_play_void_bolt`'s window finds the same hit (it is consumed but not skipped), fires the projectile, and calls `_play_damage(hit)` again at impact (:428-429): a second "-500" and a second flash.
   - Who sees it:
     - Lord Vael with Void Bolt (`voidbolt_burst` preset, PresetDecks.gd:34, 2 copies) or Void Detonation (CardDatabase.gd:2188-2195, also a VOID_BOLT step);
     - enemy casts: `cast_enemy_spell` → `_deal_enemy_void_bolt_damage` (:988-1000) gives the same order on the player hero (HERO_HP_CHANGED :1248, LOG :2029). Void Bolt is in decks f13_a (×2), f15_a and f15_p2.
2. **The attack lunge shows a death-trigger hit as the counter** (unit F bug 2a).
   - Void-Touched Imp (200/300, CardDatabase.gd:2657-2667, "ON DEATH: Deal 100 damage to all enemy minions.") is in all three fight-2 decks (f2_a ×3, f2_b ×4, f2_c ×4).
   - When a player minion kills a VTI with its strike, the journal holds:
     - ATTACK_STARTED (CombatManager.gd:77);
     - the strike (:100);
     - VTI's MINION_DIED and its on-death AoE, which includes 100 on the attacker;
     - the real counter (:138).
   - `_play_attack` takes the AoE hit as `hit_a`. `_play_attack_anim` pops "-100" at the lunge in VTI's attack-school colour and tweens the AoE's before / after values (CombatScene.gd:1824-1832).
   - VTI's ghost, on-death icon and death explosion play next. The bridge says the explosion plays "before damage resolves" (CombatVFXBridge.gd:951), but the attacker has already shown the AoE.
   - The real "-200" counter pops last, as a standalone hit.
3. **The attack lunge shows a PRE-trigger hit as the strike** (unit F bug 2b).
   - Setup: Korrath Runic Knight with Runeforge Strike (T0) and Grand Ritual: Chaos (T3). The Abyssal Knight attacks with 2 runes up.
   - The chain: ON_PLAYER_ATTACK_PRE (CombatManager.gd:85-89) → `on_player_attack_runeforge_strike` (CombatHandlers.gd:250-256) → `_korrath_place_random_rune` (CombatState.gd:1888-1907), which fires ON_RUNE_PLACED → `on_rune_placed_grand_ritual_chaos` (CombatHandlers.gd:318-366).
   - Chaos deals Burst 200–400 to a random enemy minion and Sweep 100–250 to all of them; one of its three effects is ×3. Both are journaled before the strike.
   - `_play_attack` takes the Burst or Sweep hit on the defender as `hit_d`. The lunge shows that number, with that hit's non-crit flag, and the Knight's real strike pops afterwards.
4. **A spell's impact shows hits that its kill set off** (unit F new finding).
   - Arcane Strike (CardDatabase.gd:1823-1834: 300 ARCANE to a minion; in `voidbolt_burst`) kills a full-HP VTI. The capture swallows VTI's on-death 100 AoE on the caster's minions. That AoE shows at Arcane Strike's impact, before VTI's death ghost and explosion.
   - An enemy Blood Rune (CardDatabase.gd:2339-2353; decks f2_c and f5_a) heals the enemy hero whenever an enemy minion dies; `_apply_rune_aura` mirrors the trigger to the enemy side (CombatState.gd:787). A player spell that kills an enemy minion shows that HERO_HEALED at the spell's impact, before the death.
   - No narrow fix exists. Stopping the capture at the first MINION_DIED would drop the later AoE targets' own hits.
5. **F15: a bolt's hit falls outside the 8-event window.** Cosmetic and F15 only; the event count was read from the code, not run.
   - The hero DAMAGE_DEALT is journaled last in `_on_hero_damaged` (:2061), after the triggers and after `PhaseTransition.attempt` (:2055).
   - On the hit that would kill Phase 1, `_do_transition` (PhaseTransition.gd:45-74) journals the HP refill, one SLOT_CHANGED per occupied slot, 5 enemy CARD_DRAWN (`setup_deck` → `draw_cards("enemy", 5)`, CombatState.gd:1553) and a LOG first.
   - So a void-rune or minion bolt (one outside a spell capture) finds no hit in `_peek_window(8)`. The projectile lands with no popup, and the hit pops after the board wipe.

(Deck contents come from `user://encounter_decks.json`; task 047 moves them into the repo.)

### Latent

- **Damaging traps set off by a spell.** The roadmap's example is latent. The ON_*_SPELL_CAST trap routes fire in `_cmd_play_spell` (:2645-2649) before `cast_*` journals SPELL_CAST, so trap events fall outside the capture. No current trap deals damage on a route a spell can reach.
- **`_spell_pending` is one member.** Task 048 adds a presenter deadline. A timed-out `_play_spell` whose impact fires late would flush the next spell's capture.
- **`_ahead` tracks only HP** (:33-36, :157-169). Shield is half-handled (`shield = -1`, :780-782). No visible ATK rewind was found today.

## Decision (owner, 2026-10-01)

- **Standing owner preference: proper refactor over ad-hoc fixes.** The grooming plan applies it here. The bugs above are fixed by matching on cause, not by interim presenter rules such as a pending-bolt counter or an `attack_role` payload tag. Both bugs are acceptance probes for this task.
- **QN5: player input stays responsive during playback.** So the journal can grow while a look-ahead runs. A window bounded by cause never reaches into a later command's events.

## Proposed fix

Prerequisite: task 114 (`CombatEvent.cause`, Resolution kinds).

1. **One window per resolution.**
   - In `_play_attack`, `_play_spell` and `_play_void_bolt`, replace the `_peek_window(limit)` scans with "the events after the cursor whose cause is the anchor's cause or has it as an ancestor". The window ends at the first event outside that resolution.
   - Delete the 60- and 8-event limits for these three.
   - Keep `_peek_window` for the BUFF_APPLIED and DETONATION batches.
2. **Attack.**
   - The strike is the DAMAGE_DEALT whose cause is the `STRIKE` child of the ATTACK_STARTED's cause.
   - The counter is the DAMAGE_DEALT under `COUNTER`.
   - For a hero attack, the hit is the hero DAMAGE_DEALT under that attack's `STRIKE`.
   - Events under nested `TRIGGER`, `TRAP` or `RITUAL` causes (PRE / POST handlers, death triggers) are not consumed. They play in journal order.
   - Optional, same task: anchor the lunge on the strike event instead of ATTACK_STARTED. PRE-trigger events (journaled between the two, case 3) then play before the lunge, in rules order. If the attack has no strike event (0 damage, Immune), the lunge plays at ATTACK_STARTED as it does today.
3. **Spell.**
   - Capture DAMAGE_DEALT / CORRUPTION_APPLIED / HERO_HEALED / MINION_HEALED whose cause is the spell's own resolution (`e.cause == spell_ev.cause`).
   - Leave events under `VOID_BOLT`: the bolt plays them.
   - Leave events under `TRIGGER`, `TRAP` or `RITUAL`: they play after their anchor (MINION_DIED, TRAP_FIRED, RITUAL_FIRED).
   - Delete the `prev_kind` rule.
4. **Void bolt.** The hit is the hero DAMAGE_DEALT whose cause is the VOID_BOLT event's cause. No window limit.
5. **Show each event once.**
   - `_peek_window` and every capture skip seqs already in `_consumed`.
   - Add `signal damage_shown(ev: CombatEvent)`, emitted once for each DAMAGE_DEALT shown: from `_play_damage`, and for the strike and the counter at the lunge.
6. **Out-of-order HP on the same minion.**
   - Matching by cause shows the counter at the lunge, while the death trigger's hit on the same attacker comes later in the journal (case 2: HP 1000, then the AoE to 900, then the counter to 700).
   - Tweening each event's absolute `hp_before → hp_after` would jump the label to 900 at the lunge, then rewind it to 1000 when the AoE plays.
   - Rule: an HP event played out of journal order moves the label by its own delta from `shown_hp`. In case 2 the counter takes it 1000 → 800, and the AoE later takes it 800 → 700. The popup still shows the event's `amount`.
   - When the cursor passes the last of these events, `_apply_minion_stats` lands on the engine's `hp_after` (700), as it does today.
   - Generalise `_ahead` (:33-36, :157-169) to track this.
   - `_play_attack_anim` (CombatScene.gd:1788-1840) takes its from / to values from the presenter instead of `hit_a.payload`.
   - Coordinate with task 110 (roadmap E3) if it has added ATK / shield / keyword snapshots by then.
7. **One capture per spell call.**
   - Replace the `_spell_pending` member with a capture local to each `_play_spell` call.
   - Give `VfxController.play_spell` a per-slot callable, built by the presenter and closing over this spell's capture. It replaces the wave's reach-back `combat.presenter.play_captured_for_slot(slot)` (VfxController.gd:163).
   - A late impact then can't flush the next spell's events (task 048's hazard).
8. **Matchers as static functions** on CombatPresenter:
   - `attack_hits(journal, from, ev) -> Dictionary` (`strike`, `counter`);
   - `spell_capture(journal, from, ev) -> Array`;
   - `bolt_hit(journal, from, ev) -> CombatEvent`.

   The `_play_*` functions call them, and tests run them on a bare CombatState.
9. **Keep task 048's guards.** If 048 has landed, keep its generation guard after every await in the rewritten `_play_*` functions. If not, carry its hazard list over.
10. **Docs.** Update ARCHITECTURE.md's CombatPresenter row: look-ahead by cause, each event shown once, and the delta rule.

## Verification

New unit tests on the static matchers in `debug/tests/CommandTests.gd` (bare CombatState, no scene):
- **The counter is the counter.**
  - Setup: a VTI at 100 HP and a friendly `void_imp` with `current_health = 1000`; call `resolve_minion_attack(imp, vti)`.
  - Assert `attack_hits(...)` returns the hit with cause `COUNTER` (amount = VTI's ATK) as `counter`, not the 100 AoE.
- **The strike is the strike.**
  - Setup: `TestHarness.korrath_state(["runeforge_strike", "runic_absorption", "grand_ritual_chaos"])` with 2 runes in `active_traps`. An `abyssal_knight` attacks an enemy minion with enough HP to survive the Chaos hits.
  - Assert the chosen strike has cause `STRIKE` and `source_minion == knight`, and that no Burst or Sweep hit is consumed.
- **The bolt's hit belongs to the bolt.** Cast `void_bolt`. Assert `spell_capture(...)` excludes the hero hit and `bolt_hit(...)` returns it.
- **The spell capture keeps only the spell's own hits.** Cast `arcane_strike` on a full-HP VTI with a friendly minion on the board. Assert `spell_capture(...)` holds only the spell's hit on the VTI.
- **F15 window.**
  - Setup: an F15 state (`enemy_profile_id = "abyss_sovereign"`, `_sovereign_phase = 1`; after task 125, set `enemy_phase2` from `EncounterTable.phase2_for_profile("abyss_sovereign")` instead) with 3 minions on each board, then a lethal `_deal_void_bolt_damage`.
  - Assert `bolt_hit(...)` still finds the hero hit after the transition's events.

New LiveSmoke scenario `_lookahead_matches_by_cause` in `debug/tests/LiveSmokeTests.gd`, following `_hp_labels_lag_the_engine` (:161-195):
- **Setup.** `_launch(1, "swarm")`. Then, with no awaits in between: `vti = st._summon_token("void_touched_imp", "enemy", 0, 100)`, `imp = st._summon_token("void_imp", "player", 0, 1000)`, and `st.combat_manager.resolve_minion_attack(imp, vti)`.
- **Record** `presenter.damage_shown` per seq, and the imp slot's `shown_hp` at the first `damage_shown` on the imp.
- **Assert:**
  - the first hit shown on the imp is the counter (cause `COUNTER`);
  - at that moment `shown_hp` is 1000 minus the counter's amount. Read the amount from the engine's counter event rather than hard-coding 200;
  - every DAMAGE_DEALT seq is shown exactly once;
  - after `_drain` and the 0.3 s tween tail, the imp's `_hp_label.text == str(imp.current_health)`.
- **Void Bolt.** On the player's turn, `st.set_mana("player", 2)`, `inst = st.add_to_hand("player", CardDatabase.get_card("void_bolt"))`, `st.cmd_play_spell("player", inst, null)`, then drain. The hero DAMAGE_DEALT seq reaches `damage_shown` exactly once. Today it reaches it twice.

Both probes fail today and pass after the fix.

Also:
- `tools/run_checks.sh` green. Parity runs with `presenter.instant = true` (ParityTests.gd:124), so it never runs the look-ahead. The probes above are the real gate, together with task 048's animated full fight once it exists.
- **Behaviour-neutral.** Only presenter and VFX code changes. The seeded balance fingerprint (`BalanceSimBatch -- --act 1 --runs 200 --seed 7`, before and after) diffs empty (design/TESTING.md 'Refactor / extraction work'). The sim never loads the presenter, so one act is enough.
- **Manual check.**
  - Vael casts Void Bolt: one popup, at impact.
  - Fight 2, a VTI killed by an attack: the lunge shows the counter, and the AoE shows after the explosion.

## Related

- Depends on: task 114 — the `cause` field and the Resolution kinds this task matches on.
- Depends on: task 048 — it adds generation guards and resyncs to the same `_play_attack` / `_play_spell` / `_play_void_bolt` continuations, and names `_spell_pending` as a late-impact hazard. Land after it, or carry its guards over.
- Related: task 116 (roadmap F3) — classifies event kinds in the same `match` statements. Land it together with this task or after it.
- Related: task 110 (roadmap E3) — widens the BoardSlot snapshots and shares `_ahead`. Its Phase E3b step 2 journals a MINION_STATS_CHANGED for the attacker at the end of the attack; the attack matcher must not take it as part of the strike.
- Related: task 135 (roadmap I8) — its idle-consistency probe catches any label this task leaves out of step.
- Related: task 136 (roadmap I7d) — presence-aura noise can exhaust today's 60-event attack window. Windows bounded by cause remove that limit.
- Related: task 142 (roadmap J6) — VFX wiring tables. This task changes the signature of `VfxController.play_spell`.
- Related: task 057 (BUG-double-death) — the VTI scenario with an attacker at ≤ 100 HP. The probes here use 1000 HP to stay clear of it. In 057's spent-attack case ATTACK_STARTED has no STRIKE child, so step 2's no-strike rule plays a lunge with no popup; decide here whether a spent attack shows anything more.
- Related: task 060 (BUG-crit-leak) — until it lands, unconsumed trigger hits inside a crit attack pop as crits.
- Related: task 129 (roadmap I1) — extends the same Resolution.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item F2. Absorbs roadmap F's LiveSmoke probe, unit F bugs 1–2 and unit E bug 3 (the Void Bolt double popup).

## Summary

_(filled in at /task-done)_
