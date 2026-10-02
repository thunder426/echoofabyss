---
id: "095"
title: Consolidate the 15 enemy champions' state and shared helpers (ChampionTracker), no behaviour change
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item B2a (`design/refactors/ARCHITECTURE_ROADMAP.md` §B). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

B2a is the part of B2 that doesn't depend on the table-vs-module choice. A tracker, one alive query and one summon path are needed either way. Task 096 then builds the spec table on top of it.

### Champion state is 31 loose engine fields

`grep -cE '^var _champion_' combat/board/CombatState.gd` → 31 (CombatState.gd:1818-1850 and :1937-1946). Each champion has a counter and a `_summoned` flag; RIP also keeps `_champion_rip_attack_ids`, CH keeps `_champion_ch_aura_dmg` (diagnostic, task 094), and `_champion_summon_count` spans all of them.

They are set in three different ways:
- `_summon_enemy_champion` (CombatHandlers.gd:2260-2285) flips the flag through a 15-arm match on an alias:
  ```gdscript
  var st: CombatState = state
  match card_id:
  	"champion_rogue_imp_pack":       st._champion_rip_summoned = true
  	...
  	"champion_abyss_sovereign":      st._champion_as_summoned = true
  st._champion_summon_count += 1
  state._summon_token(card_id, "enemy")
  ```
- The registry resets them through strings: each champion entry in `CombatSetup._REGISTRY` (:285-427) has a `stats` block such as `{ "_champion_as_cards_played": 0, "_champion_as_summoned": false }`, written by `st.set(stat, …)` in `apply_passive` (:645). Lint L1 checks the keys exist; nothing checks they are right.
- Each handler increments its own counter (e.g. `state._champion_rs_spark_dmg += dmg`, :1444).

### Copy-pasted liveness checks

Nine board scans answer "is this champion on the board":
- CombatHandlers.gd: `_champion_rs_is_alive` :1484, `_champion_va_is_alive` :1518, `_champion_vh_is_alive` :1555, `_champion_vs_is_alive` :1601, `_champion_vw_is_alive` :1679, `_champion_vc_is_alive` :1721, `_champion_as_is_alive` :1880, `_champion_ch_is_alive` :2295.
- CombatManager.gd:449: a second `_champion_vc_is_alive`, used by the Void Captain aura in `_post_crit` (:430).
- Two of them are never called: `_champion_vs_is_alive` (:1601) and CombatHandlers' own `_champion_vc_is_alive` (:1721). Only CombatManager's copy is used.
- VCH inlines the same scan (:1806-1811), and task 066 adds one more helper (`_enemy_champion_on_board`) for RIP, IM and ACP.

### Dead code

- `_champion_vs_crits_consumed` is touched only by its registry reset (CombatSetup.gd:390). Void Scout reads `_enemy_crits_consumed` (CombatHandlers.gd:1575).
- `on_enemy_summon_champion_vr` (:2201-2203) is a `pass` registered on every enemy summon in F5 (CombatSetup.gd:348). It appears in `debug/tests/snapshots/handler_order.txt` (ON_ENEMY_MINION_SUMMONED, priority 82).
- `champion_duel` (registry :496-500, its handlers and tooltip entries) is listed by no encounter. Task 081 deletes it; not in scope here.

### Constants

Act 3-4 champions have `_XX_THRESHOLD` / `_XX_PIPS` consts (e.g. `const _RS_THRESHOLD := 1000`, `const _RS_PIPS := 5`, :1434-1435). Act 1-2 hardcode them inline: RIP 4 (:2051-2053), CB 3, IM 2, ACP 5, VR 1, CH 3.

### AI readers

- `CombatProfile.gd:550`: `if agent.state._champion_summon_count > 0:` (`_reserved_slots`). Task 073 replaces this with `StateAgent.has_pending_champion()`, which still reads the field.
- `CombatProfile.gd:954`: `agent.state._champion_vh_summoned` in `_effective_spark_cost`, which task 051 deletes.
- `RiftStalkerProfile.gd:260-261`: `_champion_rs_spark_dmg`, `_champion_rs_summoned`.
- `VoidRitualistProfile.gd:126`: `_champion_vr_summoned`.
- `VoidHeraldProfile.gd:141`, `:286`, `:322`: `_scene_has("_champion_vh_summoned")`, which is duck typing by a variable key (:349-351):
  ```gdscript
  func _scene_has(field: String) -> bool:
  	var val = agent.state.get(field)
  	return val != null and val == true
  ```
  A renamed field makes this return false silently. Lint L9 can't see a variable key.

### Consequence

A 16th champion means another field pair, another match arm, another registry `stats` block and another `_is_alive` copy, plus the UI and text copies task 096 deals with. A wrong string in `stats` or `_scene_has` fails silently in release. Flags that never clear on death caused task 066's bug, and the registry `stats` re-application caused task 067's.

### Latent (not changed here)

- **A champion can be lost for the whole fight if the enemy board is full when its threshold is reached.** `_summon_enemy_champion` sets the flag and `_champion_summon_count` before `_summon_token(card_id, "enemy")`, which returns null on a full board (CombatState.gd:582-586). Nothing retries, yet the log still says "★ … champion has arrived!" (:2282). The base AI reserves one slot (`CombatProfile._reserved_slots`, :548-556), but passive token summons (`void_rift` sparks, `feral_reinforcement`, `spirit_resonance`) ignore it. Not traced to a concrete sequence. This task keeps today's order so the fingerprint stays empty; the tracker gives a later fix one place to live (see task 096).
- **Leaving the board without dying.** Auras are cleaned up on ON_ENEMY_MINION_DIED. A champion that is consumed or sacrificed fires no death event (sacrifice is not death, EffectResolver.gd:559-562), so its aura cleanup, CB's on-death summon and CHAMPION_KILLED never run.
  - Consume: no champion card sets `spark_value`, so `pay_sparks` and `cmd_consume_minion` never pick one.
  - Sacrifice: enemy decks f2_c (F2, Corrupted Broodlings) and f3_c (F3, Imp Matriarch) run `abyssal_sacrifice` (SACRIFICE, SINGLE_CHOSEN_FRIENDLY). Their profiles target only `void_spark` or `brood_imp` (MatriarchSacProfile.gd:92-99, CorruptedBroodRuneProfile.gd:132-141), so today they never sacrifice the champion. The base picker would: `CombatProfile.pick_spell_target` sends `"friendly_minion"` spells to `_pick_cheapest_friendly` (:463-464, :895-907), and champions cost 0 (`champion_corrupted_broodlings.essence_cost = 0`, CardDatabase.gd:2757; Imp Matriarch :2773).
  - So this is one profile change away from reachable.

## Proposed fix

1. **Add `combat/board/ChampionTracker.gd`** (RefCounted, created in `setup_combat`, reachable as `state.champions`). It holds no reference back to the state (task 049); methods that need the board take it as an argument or go through a small engine query.
   - Per champion card id: `progress: int`, `summoned: bool`, and `seen_ids: Array[int]` for RIP's distinct attackers.
   - `summon_count() -> int`, `is_summoned(card_id) -> bool`, `progress(card_id) -> int`, `add_progress(card_id, n) -> int`, `mark_summoned(card_id)`.
   - `is_alive(card_id) -> bool`, one board scan, through the engine (`state.champion_on_board(side, card_id)` or similar).
   - Keep it per side or keyed by side, so a player-side champion passive needs no new storage (owner decisions Q1/Q2). Every caller passes the enemy side today; use `ctx.owner` where the handler has a context.
2. **Replace the 31 fields, the match arm and the alive helpers** with tracker calls. Delete both unused helpers and CombatManager's copy; the VC aura in `_post_crit` asks the tracker. Fold task 066's `_enemy_champion_on_board` into `is_alive`.
   - `_enemy_crits_consumed` is Void Scout's progress under another name (written by `_apply_crit`, CombatManager.gd:356, and by `captain_orders`, CombatHandlers.gd:1965; read at :1575 and as the sim result key at CombatSim.gd:341). It becomes the tracker's `champion_void_scout` progress, incremented at both sites. Task 085 leaves it to this task; task 094 treats it as gameplay.
3. **Champion state resets at setup only.** Delete the champion `stats` blocks from `_REGISTRY`; a new tracker starts empty with each state. `apply_passive` then never touches champion state, so a passive kept across F15's phase swap keeps its count whatever `_swap_passives` does (task 067 owns the swap fix).
4. **One threshold table.** Move the `_XX_THRESHOLD` / `_XX_PIPS` consts into one dictionary keyed by champion card id, including the Act 1-2 numbers that are inline today. Task 096 replaces it with spec rows.
5. **Aura cleanup on leaving the board** (task 066's request). Put each champion's leave-the-board cleanup (RIP's aura strip, the VS / VRP field reverts, RS's immune strip) in one tracker method, `on_champion_left(card_id)`.
   - Deaths keep calling it from the same ON_ENEMY_MINION_DIED handler and priority as today, so the journal order doesn't change.
   - The silent removal paths (`_consume_minion`, `pay_sparks`' consume branch, and sacrifice) call it too when the removed minion is a champion. CHAMPION_KILLED stays death-only.
   - The new calls are unreachable with today's profiles (see Latent), so this is fingerprint-neutral.
6. **AI readers go through the agent.** Add `champion_summoned(card_id) -> bool` and `champion_summon_count() -> int` to `CombatAgent` (base) and `StateAgent`, and use them in CombatProfile, RiftStalkerProfile, VoidRitualistProfile and VoidHeraldProfile. Delete `_scene_has`. Update task 073's `has_pending_champion()` if it has landed. VoidHeraldProfile reads the flag as "Herald alive" (:141, :286, :322), which is wrong once the Herald dies; keep the same `champion_summoned` semantics here (behaviour-neutral) and leave the alive fix to task 118 / 122. Task 122 (roadmap G7) later folds these into its side-aware agent API.
7. **Delete the dead code:** `_champion_vs_crits_consumed`, `_champion_vs_is_alive`, CombatHandlers' `_champion_vc_is_alive`, the no-op `on_enemy_summon_champion_vr` and its registration (CombatSetup.gd:348).
8. **Keep every other handler method name and priority**, so `debug/tests/snapshots/handler_order.txt` changes only by losing `82:on_enemy_summon_champion_vr`. Update the snapshot deliberately in the same commit.
9. **Sim reads:** `CombatSim.run` reads `champion_summon_count` and `spark_atk_dmg` (CombatSim.gd:321, :337) from the tracker. `_champion_ch_aura_dmg` is diagnostic: if task 094 has landed it is already gone; if not, keep it as a tracker counter and let 094 move it.

## Verification

- New table-driven probe in `debug/tests/TriggerHandlerTests.gd`, `_champion_tracker_lifecycle`: for each of the 15 `champion_*` passives in `EncounterTable`:
  - `TestHarness.build_state({"enemy_passives": [passive_id]})`; assert `is_alive(card)` is false and `summon_count() == 0`.
  - Call `state._handlers._summon_enemy_champion(card)`; assert `summon_count() == 1`, `is_summoned(card)` and `is_alive(card)`.
  - Kill it with `state.combat_manager.kill_minion(...)`; assert `is_alive(card)` is false and `is_summoned(card)` stays true.
- The existing champion probes in TriggerHandlerTests (RIP :1173-1206, CH :1425, RS :1478, AS :1771-1836, VS :1558 and :1571, `_champion_summon_count` :1684 and the others) pass with their accessors updated.
- Grep gates: `grep -cE '^var _champion_' combat/board/CombatState.gd` → 0; `grep -cE '_champion_\w+_is_alive' combat/events/CombatHandlers.gd combat/board/CombatManager.gd` → 0; `grep -rn '_scene_has' enemies/` → nothing.
- `tools/run_checks.sh` green (handler-order snapshot updated as in step 8).
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4: every act has a champion) diffs empty (design/TESTING.md 'Refactor / extraction work'). Request Acts 3-4 explicitly.

## Related

- Depends on: task 066 — fixes the F1/F3/F4 auras that outlive their champion. Landing it first keeps this refactor behaviour-neutral, and its `_enemy_champion_on_board` helper folds into the tracker here.
- Depends on: task 067 — fixes the F15 Avatar counter reset. After it, dropping the champion `stats` blocks (step 3) changes nothing.
- Related: task 096 (roadmap B2) — builds the champion spec table on this tracker.
- Related: task 094 (roadmap B1) — owns the diagnostic `_champion_ch_aura_dmg`; leaves `_champion_summon_count` and `_champion_rs_spark_dmg` to this task.
- Related: task 073 — adds `StateAgent.has_pending_champion()` over `_champion_summon_count`; this task repoints it.
- Related: task 051 — deletes `CombatProfile._effective_spark_cost`, one of the AI readers above.
- Related: task 081 (roadmap DL1) — deletes `champion_duel`.
- Related: task 133 (roadmap I5) — extends `digest_text`. The champion line comes from this task's tracker: whichever of 095 / 133 lands second writes it from the tracker.
- Related: task 085 (roadmap A6) — moves `enemy_crit_multiplier` to a per-side `crit_multiplier_override`, so the Void Scout aura's writer (CombatHandlers.gd:1590, :1598) changes there; expect that if it lands first.
- Related: task 122 (roadmap G7) — the side-aware agent API absorbs step 6's agent methods.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item B2a. Re-checked at `404b51c`: 31 `_champion_*` fields, 9 alive helpers (two never called: `_champion_vs_is_alive` and CombatHandlers' `_champion_vc_is_alive`; the VC aura uses CombatManager's copy), the match arm at :2264-2279, and the AI readers. Added steps 3 and 5 from tasks 067 and 066. Checked the leave-without-dying paths: no champion has a `spark_value`, and the only enemy sacrifice card (`abyssal_sacrifice` in f2_c / f3_c) is aimed by profiles that never pick the champion; the base `_pick_cheapest_friendly` would pick it (champions cost 0).

## Summary

_(filled in at /task-done)_
