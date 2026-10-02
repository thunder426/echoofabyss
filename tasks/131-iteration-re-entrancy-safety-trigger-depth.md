---
id: "131"
title: Iteration and re-entrancy safety: trigger depth guard, skip handlers unregistered mid-fire, board snapshots, minion zone
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item I3 (`design/refactors/ARCHITECTURE_ROADMAP.md` §I). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The engine dispatches triggers and walks boards with no protection against the work changing what it is walking. One case is reachable today (the F15 phase change in the middle of an attack); the rest is latent.

### 1. TriggerManager.fire: no depth guard, and unregistered handlers still run

- `fire()` (TriggerManager.gd:79-86) copies the listener list (`var snapshot: Array = _listeners[ctx.event_type].duplicate()`, :83) and calls each entry that passes `if entry.handler.is_valid():` (:85). There is no depth counter, so a handler that re-fires its own event recurses until the stack overflows. None does today.
- `unregister()` (:66-73) removes the entry from the live list, but the snapshot still holds it, so the removed handler still gets the event being dispatched. The doc comments say otherwise: "Safe to call during fire()" (:65) and "Iterates a snapshot so handlers may register / unregister safely" (:76).
- Unregister sites: rune aura removal (CombatState.gd:336), env rituals (:391-392), `CombatSetup.unapply_passive` (CombatSetup.gd:652), which the F15 passive swap uses (PhaseTransition.gd:101-109). No reachable case was found where the removed handler listens to the event being dispatched.
- The header (TriggerManager.gd:1-27) still says "CombatScene owns one instance … populated by _setup_triggers()". Handlers are registered in `CombatSetup.setup(state)`.

### 2. Board loops iterate the live array

- In lint's RULES_FILES (tools/lint/lint_engine.py:91-103) there are 64 `for … in` loops over `player_board`, `enemy_board`, `_friendly_board(` or `_opponent_board(`. 12 copy first; 52 iterate the live array: CombatState 13, CombatHandlers 31, HardcodedEffects 2, RelicEffects 2, ConditionResolver 2, TargetResolver 1, CombatManager 1. Counting loops over any local `board` alias as well gives 94 loops, 14 of them copies. (The roadmap said 57 / 11.)
- Live loops whose bodies call mutating code:
  - CombatState.gd:351 (`remove_one_source` + refresh);
  - :827 (rune backfill runs `aura_effect_steps`);
  - CombatHandlers.gd:639 (on-friendly-summon auras run effect steps);
  - :664 (Formation auras; Vanguard Marshal draws);
  - :1954 (Captain's Orders deals hero damage);
  - HardcodedEffects.gd:150, :194 (Dark Covenant).
- With current content none of them can erase from or append to the board it walks. The roadmap's example (the `_remove_rune_aura` loop → Corrupt Detonation → a board erase) can't happen. Only Dominion Rune's aura has a `source_tag`, and `remove_one_source` emits corruption-removed only when a CORRUPTION entry goes (BuffSystem.gd:136-145).
- Latent: the first on-remove or on-summon effect that kills or summons on the board being walked will skip or double-visit a minion.

### 3. "Alive" means HP > 0; there is no zone

- MinionInstance has no zone field (:22-102).
- Liveness is `current_health > 0` at 10 code sites: CombatState.gd:502; CombatManager.gd:418, :436; CombatHandlers.gd:273, :295, :349, :360, :370, :899; RelicEffects.gd:144. (`grep -rnE 'current_health\s*>\s*0' combat relics` finds 11; :1109 is a comment.)
- PhaseTransition banishes both boards without a death (`_wipe_boards_silently`, PhaseTransition.gd:80-86). Banished minions keep HP > 0 and look alive to anything still holding a reference.
- Task 057 adds `CombatState.is_on_board(m)` (slot or board membership) as the interim guard against hitting a dead minion. A zone replaces it.

### 4. PhaseTransition runs inside an in-flight resolution, which then carries on

- `_on_hero_damaged` calls `PhaseTransition.attempt(self)` (CombatState.gd:2055) inside whatever dealt the lethal hit.
- **Reachable today (F15).** A minion's lethal attack on the Phase-1 Sovereign: `resolve_minion_attack_hero` → `apply_hero_damage` (CombatManager.gd:170) → the transition wipes both boards. The attack then continues:
  - Siphon heals the banished attacker and journals MINION_HEALED for it (:173-174 → `_siphon_self_heal`, :400-409);
  - ON_PLAYER_ATTACK_POST fires (:177-181). With Korrath's Path of Shattering, `on_player_attack_path_of_shattering` (CombatHandlers.gd:401-412) puts 50 Armour Break on the **Phase-2** hero. The attack riders (CombatSetup.gd:603) run too;
  - `attack_count`, `_check_post_crit` and EXHAUSTED are applied to the banished attacker (:182-184).
- **Minion-vs-minion:** a Pierce carry (:120-125) or the Rift Warden siphon (:129) can trigger the transition mid-attack. The counter then hits a banished attacker; task 057's guard stops that damage.
- Mid-AoE is not reachable with F15 content.
- **Same class: the engine keeps resolving after `winner` is set.**
  - `_combat_ended` is documented as the engine's re-entrancy guard (CombatState.gd:1272-1275), but only CombatScene sets it (CombatScene.gd:1590, :1614), during playback, after the engine has finished.
  - Example: F12's Captain's Orders (CombatHandlers.gd:1953-1966) keeps damaging a dead player hero. Each extra hit journals DAMAGE_DEALT and fires ON_HERO_DAMAGED after COMBAT_ENDED.

## Decision (owner, 2026-10-01)

- Q3: accept balance shifts and record the deltas. Phase b changes F15 (and possibly F12).
- Q2: everything here is side-neutral (no `owner == "player"`).
- **Open (raised in grooming, unit I):** should the Phase-2 Sovereign start clean of Phase-1 hero debuffs? `_clear_combat_state` (PhaseTransition.gd:88-99) clears environments, traps, cost auras and Void Marks, but not `enemy_hero.buffs` or `armour`. This task keeps today's carry-over. If the owner says "clean", do it as its own commit with its own F15 delta.
- Grooming default for the abort (the owner may override): **after a phase transition or the lethal hit, the in-flight attack or effect stops.** No further steps run: no Lifedrain, Siphon, POST triggers, riders, post-crit, counter or remaining AoE targets.

## Proposed fix

Two phases, each its own commit and gate run. Phase a doesn't need task 129 and can land first.

### Phase a — guards (behaviour-neutral)

1. **Depth guard.**
   - TriggerManager counts nesting: `_depth` goes up on entry to `fire()` and down on exit; keep `max_depth_seen`.
   - Measure first: have CombatSim report `max_depth_seen` and run one BalanceSimBatch matrix. Set `MAX_DEPTH` to about 4× the real maximum.
   - Past it: `depth_limit_hits += 1`, `push_warning` once per fight, and return without dispatching. CombatSim reports `depth_limit_hits` so a batch shows any hit.
   - Task 114 (roadmap F1) wraps each handler call in `fire()` in a `trigger` resolution; land the two in either order, but edit the same loop once.
2. **Skip handlers unregistered mid-fire.** Add `removed: bool` to `_Entry`. `unregister()` and `clear()` set it on the entries they drop, and `fire()` skips removed entries. Correct the doc comments at :49-51, :65 and :75-78. The `ctx.cancelled` note goes with task 129.
3. **Board snapshots.**
   - Add `CombatState.board_snapshot(side) -> Array[MinionInstance]` (a typed copy).
   - Convert the 52 live loops in RULES_FILES, plus the alias loops (e.g. CombatHandlers.gd:636-639 `var board: Array = state._friendly_board(...)` then `for raw in board`).
   - In loops whose body runs effects, skip a minion that has left the board (`is_on_board` from task 057, `is_alive()` after phase b). This is equivalent today, since no loop's board changes.
4. **Lint L20** (provisional; take the next free number if the landing order differs).
   - In RULES_FILES, a `for … in` whose expression names `player_board`, `enemy_board`, `_friendly_board(` or `_opponent_board(` without `.duplicate(` or `board_snapshot(` is an error.
   - Land it as a ratchet at the current count and lower it to 0 in the same phase. A `# lint: live-board` comment may exempt a read-only loop if the copies show up in BalanceSimBatch wall time.
   - The regex can't follow local aliases; step 3 converts those by hand.
5. **TriggerManager's header** (:1-27): CombatState and the handlers fire events; handlers are registered in `CombatSetup.setup(state)` (CLAUDE.md, "Adding New Trigger Handlers"). Task 082 assigns this header to task 088; tasks 114 and 131 also edit the file. Whichever of 088 / 114 / 131 lands first rewrites it, and the others skip this step.

### Phase b — zone and abort (behaviour change; needs task 129)

6. **Zone.** Add `MinionInstance.zone` (enum BOARD / GRAVEYARD / BANISHED, plus NONE before placement). Minions in hand are CardInstances, so there is no HAND value.
   - BOARD: `SlotState.place`. A played minion sits in its slot before it joins the board array, which is why task 057 checks the slot too.
   - GRAVEYARD: `_on_minion_vanished`, `_sacrifice_minion` (:908), `_consume_minion` (:3063).
   - BANISHED: `PhaseTransition._wipe_boards_silently`.
   - An owner transfer (Void Unraveling, CombatHandlers.gd:1335-1349) stays BOARD.
7. **`MinionInstance.is_alive()`** returns `zone == BOARD and current_health > 0`.
   - Use it at the 10 HP sites and in place of task 057's `is_on_board`.
   - `_deal_damage`, `kill_minion`, `_siphon_self_heal` and the heal paths do nothing for a minion that isn't on the BOARD.
8. **Abort the in-flight resolution.** Add `aborted: bool` to Resolution (task 129).
   - `PhaseTransition._do_transition`, and `_on_hero_damaged` where it sets `winner` (:2036, :2060), mark every open resolution aborted.
   - Each loop that resolves more work checks `state.resolution_aborted()` and stops: `resolve_minion_attack(_hero)` after each damage call and trigger fire, `EffectResolver.run` between steps and between targets, `TriggerManager.fire` between handlers, and the Captain's Orders-style handler loops (through `board_snapshot` plus the check).
   - `_transition_ends_player_turn` runs in `_finish_command` (:2920-2928), after the command's resolutions have popped, so the turn still ends.
9. **`_combat_ended` is task 140's** (roadmap J4 / J7): it deletes the engine field, drops its terms from the `winner` checks and moves CombatScene's readers (:396-402, :474, :1588-1614, plus EnemyTurnRunner.gd:62 and LiveSmokeTests.gd:217) to a scene-owned flag, behaviour-neutral. This phase's abort keys on `winner` only (step 8). If 140 hasn't landed, leave the field alone.

Out of scope: clearing Phase-1 hero debuffs (open question above); PhaseTransition reading its phase-2 spec from EncounterTable (task 125, roadmap H3); routing PhaseTransition's trap / environment clear through the engine API (task 050).

## Verification

**Phase a** (new probes in `debug/tests/TriggerHandlerTests.gd`):
- *Depth guard:* in `TestHarness.build_state({})`, register a test handler on ON_RITUAL_FIRED (no default handler; only the `ritual_surge` talent registers one) that re-fires ON_RITUAL_FIRED, then fire it once. Assert the handler ran `MAX_DEPTH` times, `depth_limit_hits == 1`, and the test returns.
- *Unregistered mid-fire:* handler A (priority 0) unregisters handler B (priority 1) on the same event. Fire once. Assert B was not called (today it is).
- The handler-order snapshot (`debug/tests/snapshots/handler_order.txt`) is unchanged: no registration changes.
- `tools/run_checks.sh` green, including L20.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, Acts 1-4) diffs empty (design/TESTING.md 'Refactor / extraction work'). Record `max_depth_seen` and the wall time in the task summary.

**Phase b:**
- *Transition stops the attack* (TriggerHandlerTests):
  - Setup: `TestHarness.korrath_state(["path_of_shattering"])`, `state.enemy_profile_id = "abyss_sovereign"` (after task 125: `state.enemy_phase2` from `EncounterTable.phase2_for_profile("abyss_sovereign")`), `state._sovereign_phase = 1`, `state.enemy_hp = 100`. `knight := TestHarness.spawn_friendly(state, "abyssal_knight")` (a Demon) with `BuffSystem.apply(knight, Enums.BuffType.GRANT_SIPHON, 1, "test", false, false)`. Then `state.combat_manager.resolve_minion_attack_hero(knight, "enemy")`.
  - Assert `_sovereign_phase == 2` and `knight.zone == BANISHED`.
  - Assert `enemy_hero` has no ARMOUR_BREAK entry with source `"path_of_shattering"`, and no MINION_HEALED for the knight after PHASE_TRANSITION in the journal.
- *Lethal stops the loop:*
  - Setup: `TestHarness.build_state({"enemy_passives": ["captain_orders"]})`, `state.player_hp = 100`, two enemy `void_imp`s each with one CRITICAL_STRIKE stack, then fire ON_ENEMY_TURN_END.
  - Assert `winner == "enemy"`, one hero DAMAGE_DEALT before COMBAT_ENDED, and no DAMAGE_DEALT after it (today two).
- *Zone:* `kill_minion(m)` → `m.zone == GRAVEYARD`; a later `_deal_damage(m, …)` journals nothing. Re-point task 057's guard probe at the zone.
- `tools/run_checks.sh` green.
- Behaviour change: record the BalanceSimBatch delta in the task summary. Request Act 4 explicitly (F15; F12 for the lethal abort), since BalanceSimBatch defaults to Acts 1-2. Expected to be small.

## Related

- Depends on: task 129 (roadmap I1) — phase b's abort lives on the Resolution stack.
- Depends on: task 057 — adds the interim `is_on_board` guard that phase b's zone replaces.
- Related: task 114 (roadmap F1) — edits the same `TriggerManager.fire` loop (per-handler `trigger` resolution).
- Related: task 088 (roadmap A5) — owns the TriggerManager.gd header (task 082's assignment); step 5 only applies if this task lands first.
- Related: task 140 (roadmap J4) — deletes `_combat_ended` and moves its readers to the scene (step 9); it also hardens the lint, so share the ratchet mechanism.
- Related: task 050 — routes PhaseTransition's trap / environment clear through `remove_trap` / `destroy_environment`.
- Related: task 125 (roadmap H3) — PhaseTransition's phase-2 spec from EncounterTable; the debuff carry-over question sits next to it.
- Related: task 087 (roadmap A4, L16) — another ratchet lint; share the mechanism.
- Related: task 135 (roadmap I8) — the idle-consistency probe is the safety net for phase b's journaling changes.
- Related: task 133 (roadmap I5) — once `zone` exists, add it to the digest.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item I3. Re-checked at `404b51c`. Corrected the loop count (64 / 12 copied, not 57 / 11) and the `_remove_rune_aura` example (can't happen). Found the reachable F15 case: an attack keeps resolving after the phase change (Siphon on a banished minion, Path of Shattering AB on the Phase-2 hero). Added the engine-never-sets-`_combat_ended` finding to phase b. Split into phase a (guards, neutral) and phase b (zone + abort, behaviour change).

## Summary

_(filled in at /task-done)_
