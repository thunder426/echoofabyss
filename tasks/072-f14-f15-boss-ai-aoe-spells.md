---
id: "072"
title: F12/F14/F15 AI — spark spells held unless the player has 2+ minions, and F15's lethal check ignores Sovereign's Decree's spark cost
status: backlog
area: ai
priority: high
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §G). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Two AI bugs in the Act 4 bosses. Both are reachable in every run that gets to F12, F14 or F15, in live play and in the sim. Fix them as two commits, each with its own BalanceSimBatch delta.

Deck contents below come from the machine-local `user://encounter_decks.json` (task 047 moves it into the repo).

### Bug 1: spark spells wait for 2+ player minions (F12, F14, F15)

`VoidScoutProfile._play_spark_spells` returns early unless the player has 2+ minions:
- `VoidScoutProfile.gd:184` `## Play spark-cost spells — only when opponent has 2+ minions (AoE value).`
- `:187-188` `if agent.state._opponent_board("enemy").size() < 2:` / `return`

The gate was meant for Rift Collapse (AoE). It blocks every spark spell. In the play phase these profiles cast spark spells only through this method: `_play_spells_pass` skips anything with `void_spark_cost > 0` (CombatProfile.gd:598).

Who inherits it:
- **F15 Abyss Sovereign, phases 1 and 2.** `AbyssSovereignProfile` and `AbyssSovereignPhase2Profile` don't override `play_phase`, so `VoidScoutProfile.play_phase` runs (VoidScoutProfile.gd:22, :30). Decks f15_a and f15_p2 hold `sovereigns_decree` ×1 (300 face damage + 2 Corruption) and `void_pulse` ×2 (draw 3). Their `_spark_spell_priority` tables (AbyssSovereignProfile.gd:22-28, "Sovereign's Decree is high priority"; AbyssSovereignPhase2Profile.gd:18-24) are never called.
- **F14 Void Champion.** `VoidChampionProfile.play_phase` ends with `await _play_spark_spells()              # Throne's Command, Void Pulse` (:42), the inherited method. Deck f14_a holds `thrones_command` ×1 (+1 Critical Strike to all friendly minions) and `void_pulse` ×2. Its "top spark priority" table (:26-33) is never called.
- **F12 Void Captain** (not in the original report; found on re-check). It has its own copy of the gate: `_play_spark_spells_aoe` (VoidCaptainProfile.gd:98-100) returns when the player has fewer than 2 minions. It skips only Throne's Command (:109-110, handled by `_play_thrones_command`). Deck f12_a holds `void_pulse` ×2, so F12's Void Pulse is held too. The header and the call site name only Rift Collapse (:34 `# Phase 4: Other spark-cost spells (Rift Collapse — AoE when opponent has 2+)`).

Result: while the player keeps 0–1 minions, these bosses never draw with Void Pulse, F15 never casts Decree, and F14 never casts Throne's Command. A minion-light player deck faces weaker bosses than intended.

F13 already fixed this in its own override: `VoidRitualistPrimeProfile.gd:55-57` `## Override parent gate: parent skips all spark spells when opponent board < 2.` / `## We want Void Pulse (draw) to fire regardless, ...`. It skips Rift Collapse only on an empty board (:69) and sorts by priority (:72-73).

Not affected: F10 Void Scout (deck f10_a has `rift_collapse` as its only spark spell, so the gate does what it should); F11 Void Warband (own `_play_spark_spells`, extends CombatProfile).

#### F14's Mana-for-spark path in the same loop

F14 has the `mana_for_spark` passive (EncounterTable.gd:133): the engine pays a spark shortfall in Mana (CombatState.gd:3035-3036). The loop doesn't use it:
- `VoidScoutProfile.gd:199` checks only the spell's Mana cost, not Mana + shortfall.
- `:201-203` skip the spell when `_plan_spark_payment_no_crit` returns an empty plan. With no fuel on board that plan is always empty (CombatProfile.gd:1049-1054 returns the empty partial plan), so F14 never casts a spark spell without fuel, even with Mana to spare. The comment at :206-207 says the engine covers the shortfall.
- With partial fuel and too little Mana for the shortfall, the fuel is consumed and then the cast is refused (`:208-209` returns).

`VoidChampionProfile._play_big_body` (:176-203) already does this correctly for minions.

### Bug 2: F15's lethal check counts Decree without its spark cost

The base `attack_phase` decides lethal at CombatProfile.gd:55 `var can_go_lethal  := _calc_lethal_damage() >= agent.opponent_hp`.
- `_calc_lethal_damage` (:694-750) adds every DAMAGE_HERO / VOID_BOLT spell in hand. It checks only Mana: `:701` `var cost  := agent.effective_spell_cost(spell)`, `:729` `if entry.cost > remaining_mana:`. Spark cost is never checked.
- When `can_go_lethal` is true, `_play_lethal_spells` (:754-781) casts the damage spells. It never consumes spark fuel.
- `StateAgent._with_prepaid` (:87-91) always sends `sparks_prepaid` (0 here). `CombatState.plan_cost` takes that branch (:3032) and refuses with `why = "sparks"` (:3037-3038), unless `mana_for_spark` is active (F14 only).
- On the refusal, `:780-781` `if not await agent.commit_play_spell(inst, pick_spell_target(spell)):` / `return` ends the whole pass. A `void_bolt` after Decree in hand order is never cast. f15_a and f15_p2 both hold `void_bolt` ×1.

Result in F15, when ready-board damage + 300 ≥ player HP but the real damage is less:
- the lethal pass casts nothing after Decree;
- `can_go_lethal` is wrongly true, so the AI skips tempo trades when behind (:65, VoidScout's `_is_tempo()` is true) and the lethal-threat trade branch (:86), and sends everything face (:73).

Only F15 is affected today. Decree is the only spark spell with DAMAGE_HERO or BUFF_ATK (the others are `void_pulse` DRAW, `rift_collapse` DAMAGE_MINION, `thrones_command` GRANT_CRITICAL_STRIKE). F13 also holds Decree, but `ritualist_spark_free` makes its spark cost 0 (CombatState.gd:2996-2997).

## Decision (owner, 2026-10-01)

- Q3: "Accept, record deltas." Both fixes make the bosses stronger. Record each delta; retune afterwards if needed.
- Q7b: profiles must "read only through CombatAgent". New code here reads `agent.opponent_board`, not `agent.state._opponent_board("enemy")`.

## Proposed fix

Commit 1 (bug 1):
1. Rewrite `VoidScoutProfile._play_spark_spells` as a priority loop, the shape of VRPrime's (:58-89):
   - drop the blanket gate;
   - add an overridable per-spell gate, default: skip `rift_collapse` while `agent.opponent_board.size() < 2`. F10 is unchanged;
   - pick the highest `_spark_spell_priority` first. Add a default `_spark_spell_priority(id) -> int` (returns 0) to VoidScoutProfile so the F14 / F15 / F15-P2 tables are used. Pick with a strict `>` scan, as VoidHeraldProfile.gd:246-258 does, so ties keep hand order (`sort_custom` isn't stable).
2. In the same loop, handle F14's `mana_for_spark`:
   - gate with `_can_afford_spark_card(spell)`, which adds the Mana shortfall (CombatProfile.gd:973-990);
   - pay only the fuel there is (`mini(_available_sparks(), sc)` through `_plan_spark_payment_no_crit` + `_pay_sparks_smart`), as `_play_big_body` does;
   - an empty plan is fine when the shortfall is payable in Mana.
3. F12: in `VoidCaptainProfile._play_spark_spells_aoe`, move the 2+ check inside the loop and apply it to `rift_collapse` only. Void Pulse then casts on any board. Keep the Throne's Command skip.
4. Fix the stale headers while there:
   - VoidChampionProfile.gd:4-6 describes `champion_duel`, which F14 doesn't have (task 081 deletes it);
   - AbyssSovereignPhase2Profile.gd:11-12 names Throne's Command, which f15_p2 doesn't hold.

Commit 2 (bug 2):
5. `_calc_lethal_damage`: count a spell with `void_spark_cost > 0` only when the side can pay it, and add any Mana shortfall to its cost.
   - Use `_can_afford_spark_card`. It reads the spark cost through `_effective_spark_cost`, the AI copy that task 051 replaces with the engine's `spark_cost_of`.
   - If 051 has landed, it goes through `agent.effective_spark_cost(card)`. If not, call `agent.state.spark_cost_of(agent.side, spell)` in the new code rather than adding a caller of the AI copy.
6. `_play_lethal_spells`: for a spark spell, plan and consume fuel first (`_plan_spark_payment_no_crit` + `_pay_sparks_smart`, as in step 2), or skip it when it can't be paid.
   - `_pay_sparks_smart` lets the fuel attack before it is consumed, so fuel ATK counted in the lethal pool is still delivered.
7. On a refused cast, `continue` instead of `return`.
   - This is the base class. A refused non-spark cast (e.g. no target) will also stop ending the pass for every profile that uses `_play_lethal_spells`, the `spell_burn` player bot included.

Follow the neighbouring `await agent.commit_*` pattern; task 121 strips the no-op awaits later. Add no state writes (task 051's L12).

## Verification

New probes in `debug/tests/CommandTests.gd`, next to the "agents /" probes (:695+). Setup: `TestHarness.build_state({})`, `_enemy_turn(state)`, `ProfileRegistry.make("enemy", <id>)` + `setup(TestHarness.agent_for(state, "enemy"))`, resources via `_set_res`, hand via `_hand_card`. Spawned minions aren't ready, so fuel doesn't attack unless the probe says so.

Bug 1:
- `abyss_sovereign`: enemy board 2 × `void_wisp`, Mana 2, hand [`sovereigns_decree`], empty player board. After `play_phase()`, the player has lost exactly 300 HP and Decree has left the enemy hand. Fails before.
- `abyss_sovereign`: hand [`void_pulse`, `sovereigns_decree`], 3 × `void_wisp`, Mana 2, empty player board. Decree is cast and Void Pulse stays in hand (priority 4 > 2). Hand order would cast Pulse first and leave too little Mana for Decree.
- `void_champion`: 2 × `void_wisp` plus one non-fuel friendly minion (no `spark_value`, e.g. `sovereigns_herald`), Mana 1, hand [`thrones_command`], 1 player minion. After `play_phase()`, Throne's Command has been cast and the remaining minion has a Critical Strike stack. Fails before.
- `void_champion` with `enemy_passives: ["mana_for_spark"]`, no fuel, Mana 3, hand [`thrones_command`]. It is cast and pays 3 Mana (1 + 2 shortfall). Fails before.
- `void_captain`: 1 `void_wisp`, Mana 1, hand [`void_pulse`], empty player board. Void Pulse is cast. Fails before.
- Regression, `void_scout`: fuel, Mana, hand [`rift_collapse`], 1 player minion. Rift Collapse is still held. With 2 player minions it is cast.

Bug 2:
- `abyss_sovereign`, no enemy passives (no dark_channeling 1.5×), no fuel. One ready non-fuel attacker with ATK `A` (`_ready_minion`). Mana 4, hand [`sovereigns_decree`, `void_bolt`] in that order, player HP `A + 500`.
  - Assert `_calc_lethal_damage() == A + 500` (`A + 800` before the fix).
  - After `attack_phase()`, `winner == "enemy"`: Void Bolt was cast and the attacker went face. Before the fix the pass stops at the refused Decree, and the player survives at 500.
- Same setup with 2 × `void_wisp` fuel on board: the lethal pass consumes the fuel and Decree resolves.

Gate:
- `tools/run_checks.sh` green. Parity's "F15 swarm" case plays the changed F15 AI; it must stay green.
- Behaviour change: record the BalanceSimBatch delta in the task summary, one per commit (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after).
  - Commit 1: `--act 4`. Expect F12, F14 and F15 rows to move and F10, F11 and F13 rows to stay byte-identical.
  - Commit 2: `--act 1` to `--act 4`, because the lethal helpers are shared by every profile. Expect only F15 rows to move. If other rows move, the `return` → `continue` change is the cause; record which rows.

## Related

- Related: task 051 — engine spark cost (`StateAgent.effective_spark_cost`) for step 5; L12 forbids state writes in `enemies/ai`.
- Related: task 119 (roadmap G3) — depends on this task. Flattening VoidScout's five children must keep the fixed behaviour; its "byte-identical" gate holds only after this lands.
- Related: task 118 (roadmap G2) — merges the `_play_spark_spells` / `_spark_spell_priority` copies (4 of 8 tables are dead today; this task makes the F14 and F15 ones live) and the copied `mana_for_spark` rule.
- Related: task 139 (roadmap J3) — one fixed-board decision probe per encounter profile. This task's probes cover void_scout, void_captain, void_champion and abyss_sovereign; move them into J3's file when it lands.
- Related: task 122 (roadmap G7) — side-aware CombatAgent reads. The code touched here stops using `agent.state._opponent_board("enemy")`.
- Related: task 121 (roadmap G5) — synchronous profiles.
- Related: task 081 (roadmap DL1) — deletes `champion_duel`, which VoidChampion's header still describes.
- Related: task 047 — enemy decks move into the repo; the deck facts above come from the local file.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap §G bugs BUG-G-1 and BUG-G-2.
  - Re-check added F12: VoidCaptain's `_play_spark_spells_aoe` has the same gate and holds Void Pulse.
  - Re-check added F14's `mana_for_spark` gap in the same loop.
  - Throne's Command grants no spell immunity: `champion_duel` isn't an F14 passive.
  - The draft bug-2 probe asserted Void Bolt is cast with lethal out of reach. It isn't, because the fixed check then skips the lethal pass. The probe now sets HP to exactly the reachable damage.
- 2026-10-02: task 081 landed first and rewrote VoidChampionProfile.gd's header (passives from EncounterTable, no spell-immunity claims) and the `_spark_spell_priority` comment. Step 4's first bullet is done; AbyssSovereignPhase2Profile.gd:11-12 is still stale.

## Summary

_(filled in at /task-done)_
