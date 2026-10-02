---
id: "066"
title: Champion auras keep working after the champion dies (F1 Rogue Imp Pack, F3 Imp Matriarch, F4 Abyss Cultist Patrol)
status: backlog
area: combat
priority: high
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §B, unit B bug 1). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

An aura is an effect that lasts while its source is alive:
- `design/master_doc/CARD_DESCRIPTION_STYLE.md:19`: "## Auras (continuous effects while source is alive)".
- `DESIGN_DOCUMENT.md:771` says a champion's threat is "purely the aura/on-board effect they project while alive".
- The handlers say the same: `CombatHandlers.gd:2114` "If champion is alive, apply +200 HP", and `:2155` "Aura: while champion alive, corruption application instantly detonates."

Three champions check `_champion_<x>_summoned` instead. That flag is set once at summon (`_summon_enemy_champion`, CombatHandlers.gd:2265 / :2267 / :2268). It is reset only by the registry at setup (CombatSetup.gd:291 / :304 / :344). So the aura keeps working after the champion dies.

### Reachable today

1. **F1 Rogue Imp Pack: +100 ATK stays on the feral imps, and new imps still get it.**
   - The champion's summon applies the aura (`:2284-2285`). `_refresh_champion_rip_aura` (:2075-2080) strips and re-applies `champion_rip_aura` (+100 ATK) on every `feral_imp`-tagged enemy except the champion. It never checks that the champion is on the board.
   - When the champion dies, `on_enemy_died_champion_rip` (:2061-2073) does only this:
     ```gdscript
     # Champion died — deal 20% max HP to enemy hero
     if minion.card_data.id == "champion_rogue_imp_pack":
         _on_enemy_champion_killed()
     ```
     No buff is removed, so the surviving imps keep +100 ATK.
   - The next enemy summon runs `on_enemy_summon_champion_rip_aura` (:2056-2059). Its guard `if not state._champion_rip_summoned: return` passes, so it re-applies +100 to every feral imp. A death of another imp does the same (:2068-2069).
   - `rabid_imp`, `imp_brawler` and `rogue_imp_elder` are all tagged `feral_imp` (CardDatabase.gd:2619, :2651, :2719), and every minion in the F1 decks (f1_a/b/c) is one of them.
2. **F3 Imp Matriarch: Pack Frenzy keeps giving +200 HP.**
   - `on_enemy_spell_champion_im` (:2111-2121):
     ```gdscript
     if state._champion_im_summoned:
         for m in state.enemy_board:
             if _has_tag(m, "feral_imp"):
                 m.current_health += 200
     ```
   - The aura applies from the 3rd Pack Frenzy on. F3 has `ancient_frenzy` (EncounterTable.gd:34), which puts a Pack Frenzy in the opening hand (CombatState.gd:2360-2363). Every F3 deck holds 2 more (f3_a/b/c), so a 3rd cast after the Matriarch dies is reachable.
3. **F4 Abyss Cultist Patrol: corruption on player minions keeps detonating instantly.**
   - `on_enemy_summon_champion_acp_corrupt` (:2158-2160) starts with `if not state._champion_acp_summoned: return`, then detonates every corruption stack on the player's board for 100 damage per stack, on every enemy summon.
   - F4's `corrupt_authority` corrupts a random player minion whenever a Human is summoned (`on_enemy_summon_corrupt_authority_human`, :1157-1165). Both F4 decks run 3-5 `abyss_cultist` and 2 `corruption_weaver`, which corrupt on play (CardDatabase.gd:1925, :1963). So after the Patrol dies, every Human summon still corrupts and detonates at once instead of waiting for a feral imp.

(The deck contents come from `user://encounter_decks.json`; task 047 moves them into the repo.)

### Every other champion already checks the board

- CH: `if state._champion_ch_summoned and self._champion_ch_is_alive():` (:2240).
- RS: `_champion_rs_is_alive()` (:1460, :1477), and immunity is removed on death (:1468-1473).
- VA (:1390), VH (:1360), VW (:1661), VCH (:1806-1812), AS (:1835), and VC (CombatManager.gd:430) all check the board.
- VS (:1596-1598) and VRP (:1762-1763) revert their field when the champion dies.

The board check is reliable: `_on_minion_vanished` erases the minion from the board (CombatState.gd:1990) before it fires ON_ENEMY_MINION_DIED (:2009).

### Tests

TriggerHandlerTests covers only the alive case: `_rip_aura_grants_100_atk` (:1173-1188, "while alive"), `_rip_aura_refreshes_on_death` (:1190-1206; another imp dies, not the champion), `_im_aura_adds_200hp_on_frenzy` (:1291-1302) and `_acp_aura_instant_detonate` (:1346-1361).

`_acp_aura_instant_detonate` fakes the summon with `state.set("_champion_acp_summoned", true)` (:1351) and puts no champion on the board, so it will fail once the aura checks the board.

## Proposed fix

1. Add one private helper to CombatHandlers, `_enemy_champion_on_board(card_id: String) -> bool`, which scans `state.enemy_board`. Task 095 (roadmap B2a) later folds the seven existing `_champion_*_is_alive` copies into it, or into its ChampionTracker.
2. **RIP:**
   - `_refresh_champion_rip_aura()` always strips `champion_rip_aura` from every enemy minion, and re-applies it only if `champion_rogue_imp_pack` is on the board. Call `state._refresh_slot_for(m)` for each changed minion; that journals MINION_STATS_CHANGED, so the slot labels follow.
   - In `on_enemy_died_champion_rip`, call `_refresh_champion_rip_aura()` when the champion itself dies, before `_on_enemy_champion_killed()`.
   - Keep the `_champion_rip_summoned` early-return in `on_enemy_attack_champion_rip` (:2041). The champion must not come back.
3. **IM:** inside the `if state._champion_im_summoned:` branch, apply the +200 HP only if `champion_imp_matriarch` is on the board. Still `return` either way, so a dead Matriarch does not restart the frenzy count.
4. **ACP:** `on_enemy_summon_champion_acp_corrupt` returns unless `champion_abyss_cultist_patrol` is on the board. Keep the `_summoned` early-return in `on_champion_acp_track_stacks` (:2146) so the Patrol is not summoned again.
5. Update `_acp_aura_instant_detonate` to put the champion on the board (`TestHarness.spawn_enemy(state, "champion_abyss_cultist_patrol")`) instead of only setting the flag.
6. Fix the comment at :2071 ("deal 20% max HP"). Task 068 sweeps the other stale champion comments.

Latent, not in scope: a champion that leaves the board without dying (sacrifice, consume) fires no ON_ENEMY_MINION_DIED. With steps 2-4 the IM and ACP auras still stop, but RIP's +100 stays on the imps until the next refresh. No F1 card removes an enemy champion that way today. Task 095 should key the aura on "left the board", not on "died".

## Verification

- New probes in `debug/tests/TriggerHandlerTests.gd`, next to the existing champion probes:
  - `_rip_aura_removed_on_champion_death`:
    - Summon the champion with 4 distinct `rabid_imp` attacks, plus a 5th imp that gets the aura.
    - Kill the champion with `state.combat_manager.kill_minion(champion)`. Assert the 5th imp's `effective_atk()` is back to its base.
    - Spawn another `rabid_imp` and fire `_fire_enemy_summon`. Assert it gets no +100.
  - `_im_aura_inactive_after_death`:
    - Two Pack Frenzy casts summon the Matriarch. Spawn a `rabid_imp`, then kill the Matriarch.
    - A 3rd cast leaves the imp's `current_health` unchanged, and `_champion_im_frenzy_count` stays at 2.
  - `_acp_aura_inactive_after_death`:
    - Put the champion on the board, corrupt a player minion twice, then kill the champion.
    - An enemy summon leaves both corruption stacks and the minion's HP unchanged.
  - The existing alive-case probes still pass (`_acp_aura_instant_detonate` after step 5).
- `tools/run_checks.sh` green.
- Behaviour change: record the BalanceSimBatch delta in the task summary.
  - Run `BalanceSimBatch -- --act 1 --runs 200 --seed 7` (F1, F3) and `-- --act 2 --runs 200 --seed 7` (F4), before and after.
  - Expect the player's win rate in F1, F3 and F4 to rise.
  - F2, F5 and F6 should not move. If they do, investigate before committing.

## Related

- Related: task 095 (roadmap B2a). It depends on this task and folds the per-champion alive checks into one ChampionTracker.
- Related: task 096 (roadmap B2). The spec table's aura column should be gated on "champion on board", so this bug can't come back.
- Related: task 067. The other champion bug (F15 Avatar counter); independent.
- Related: task 068. Champion text and tooltip fixes; text only, independent.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from unit B's straight-to-task bug B-bug1 (roadmap §B). Re-checked the trace end to end at `404b51c`. Also found that `_acp_aura_instant_detonate` (:1351) fakes the summon and must be updated with the fix.

## Summary

_(filled in at /task-done)_
