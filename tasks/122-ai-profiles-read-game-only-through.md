---
id: "122"
title: AI profiles read the game only through a side-aware CombatAgent API (lint L18)
status: backlog
area: ai
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item G7 (new; `design/refactors/ARCHITECTURE_ROADMAP.md` §G, direction 4). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The roadmap's direction 4 ("Profiles read through `CombatAgent` only; lint (with task 051's L12) against `agent.state.` reads") had no candidate id. Task 051's step 6 points this follow-up at the wrong item: "Banning `state._private` reads would hit about 42 sites; leave that as a follow-up (roadmap G4)." G4 is the scored-AI decision (task 120). The follow-up is this task.

### Profiles reach into CombatState

- `agent.state` is a typed getter on the agent (CombatAgent.gd:50-52). `rg -o 'agent\.state' enemies/ai` gives 96 occurrences on 81 lines in 23 files. 17 of those lines are in CombatProfile.gd (:349, :550, :553, :624, :645, :881, :926, :954, :961, :1001, :1011, :1032, :1038, :1047, :1052, :1166, :1167). The heaviest profiles are SpellBurnPlayer (16 lines, mostly task 051's writes), VoidWarband (10) and RiftStalker (5).
- Private members: `rg -o '\b(state|st)\._\w+' enemies/ai` gives 37 uses; 11 are the writes task 051 removes. The reads are:
  - `_minion_has_tag` ×7, `_opponent_board` ×3, `_has_talent` ×3 plus `st._has_talent` (SerisPlayerProfile.gd:107);
  - `_opponent_of` (SpellBurnPlayerProfile.gd:160, :179; CombatProfile.gd:927 through `st`);
  - champion state: `_champion_summon_count` (CombatProfile.gd:550), `_champion_vh_summoned` (:954, deleted by task 051), `_champion_vr_summoned` (VoidRitualistProfile.gd:126), `_champion_rs_summoned` and `_champion_rs_spark_dmg` (RiftStalkerProfile.gd:260-261);
  - Seris state: `_fiendish_pact_pending` (FleshcraftPlayerProfile.gd:89), `_seris_corrupt_used_this_turn` (SerisPlayerProfile.gd:109);
  - `_runes_satisfy` (RuneTempoPlayerProfile.gd:279).
- By string: VoidHeraldProfile.gd:349-351 `_scene_has(field)` reads `agent.state.get(field)`. Task 095 deletes it. Its three callers (:141, :286, :322) read `_champion_vh_summoned` as "Herald alive", but the flag stays true after the Herald dies; `CombatProfile._effective_spark_cost` (:954-959) gets this right by also checking the board. Port them to `champion_summoned(...)` unchanged here (behaviour-neutral); switching them to an on-board check is a behaviour change for its own commit or bug task, with a recorded BalanceSimBatch delta.
- Through an untyped handle: the player-bot growth helpers take `state: Object` and read `state.player_hand` / `state.player_board` (DefaultPlayerProfile.gd:68-95, SwarmPlayerProfile.gd:185-197, RuneTempoPlayerProfile.gd:219-248). Task 117 moves them onto `agent`.
- The sim player's relic AI, `sim/SimRelicPolicy.gd`, reads `state.player_mana`, `player_mana_max`, `player_hand`, `enemy_board` and `player_hp` directly (:28-65). Task 083 (step 8) points those reads at this task.

### Side-blind reads

The agent knows its side (`agent.side`), but many reads name a side or an enemy-only field:
- `agent.state.enemy_passives`:
  - CombatProfile.gd:553 (`_reserved_slots`);
  - :961 (task 051 deletes it);
  - :1001 and :1052 (mana_for_spark; task 118 replaces them);
  - MatriarchProfile.gd:68 (`ancient_frenzy`);
  - VoidChampionProfile.gd:212 (task 118);
  - ScoredMatriarchProfile.gd:33 (task 120 deletes it).
- `agent.state.enemy_void_marks`: CombatProfile.gd:1167, a spell kill estimate. Right for a player caster, wrong for an enemy one.
- `traps_of("player")`: VoidScoutProfile.gd:51, VoidHeraldProfile.gd:60, VoidAberrationProfile.gd:81.
- `_opponent_board("enemy")`: VoidScoutProfile.gd:187, VoidCaptainProfile.gd:99, VoidRitualistPrimeProfile.gd:69. Task 072 rewrites the first two.
- `_has_talent(id)` reads the player's talents whatever the side (CombatState.gd:218-219 `return id in talents`). `player_flesh` too (SerisPlayerProfile.gd:84, :109).

Reachable today: `_reserved_slots` makes the player bots keep a slot free for the enemy's champion (task 073). The rest are latent, because each of those profiles plays only one side today.

### Copied rules and dead plumbing

- `effective_minion_mana_cost` returns raw `mc.mana_cost` (CombatAgent.gd:189-190). The engine's `card_cost` (CombatState.gd:2954-2958) also uses raw `mc.mana_cost`, so they agree only because no minion Mana modifier exists.
- `CombatAgent._essence_cost_discounts` and `_minion_essence_cost_aura` (:177-183) are never reached: StateAgent overrides `effective_minion_essence_cost` (StateAgent.gd:104-105).
- Stale headers, not covered by task 055:
  - CombatAgent.gd:5-6 "EnemyAgent (the live EnemyAI node, until Phase 3.4)";
  - StateAgent.gd:4-5 "live's enemy moves onto it in Phase 3.4 (until then: EnemyAgent → EnemyAI)";
  - ProfileRegistry.gd:4 "Live's EnemyAI and the sim's CombatSim both build from it".

### Why it matters

- **Look-ahead (Q7b).** A look-ahead sets a profile up on a StateAgent over a cloned state. Profiles hold no state besides `agent` (CombatProfile.gd:36 is the only member variable in CombatProfile and `profiles/`). So once every read goes through the agent, any profile can run on any state and either side. A read like `agent.state.enemy_passives` breaks that.
- **PvP and mirror matches (Q1, Q2).** An AI must be able to play either side.
- **Coupling.** 23 profile files depend on CombatState internals that workstream B (tasks 094–099) and SideState (tasks 083–085) are moving.

## Decision (owner, 2026-10-01)

- Q7b: look-ahead is planned, so "profiles must be synchronous and read only through `CombatAgent`". Task 121 does the first half; this task the second.
- Q1/Q2: PvP is planned and no mechanic is one-sided by design. The agent answers for its own side from data, never by assuming it plays the enemy.

## Proposed fix

1. **Read API on CombatAgent** (base defaults), implemented in StateAgent from `side`. Fold in what earlier tasks added, if they have landed: `effective_spark_cost` (task 051), `has_tag` and `spark_mana_shortfall` (task 118), `has_pending_champion` (task 073), `champion_summoned` / `champion_summon_count` (task 095), `flesh()` / `skill_ready(id)` (task 097).

   | Read today | Agent query |
   |---|---|
   | `enemy_passives` | `has_passive(id)`, `passive_with_prefix(prefix)`: the agent's own side's passives (`enemy_passives` for the enemy, `hero_passives` (CombatState.gd:1651) for the player) |
   | `_champion_*` | `has_pending_champion()`, `champion_summoned(card_id)`, `champion_summon_count()`, plus a progress read for RiftStalker's `_champion_rs_spark_dmg` (on task 095's tracker) |
   | `traps_of("player")`, `environment_of(...)` | `opponent_traps()`, `own_environment()`, `opponent_environment()` (StateAgent already has `opponent_has_rune_or_environment`, :107-114) |
   | `_opponent_board("enemy")` | `agent.opponent_board` (exists) |
   | `enemy_void_marks` | `opponent_void_marks()` |
   | `mana_of(_opponent_of(side))` | `opponent_mana()` |
   | `_has_talent(id)` | `has_talent(id)`: the side's talents (the player's `talents` today, false for the enemy; per side after task 090) |
   | `player_flesh`, `_seris_corrupt_used_this_turn`, `_fiendish_pact_pending` | `flesh()`, `skill_ready(id)`, `fiendish_pact_pending()` |
   | `_runes_satisfy(runes, required)` | `runes_satisfy(runes, required)`; the engine helper reads no state (CombatState.gd:1207), so make it public or static |
   | `m.effective_spark_value(agent.state)` | `spark_value(m)` |
   | raw `mc.mana_cost` | `effective_minion_mana_cost` via a new `CombatState.minion_mana_cost(side, mc)`, which `card_cost` also uses |

2. **Replace every profile read** with the agent query: all side-blind sites listed above, the private reads, `agent.state` in CombatProfile, and the `agent.state` null-guards (dead: StateAgent always has a state).
3. **SimRelicPolicy takes the player agent** instead of the state. It reads `agent.mana`, `agent.hand`, `agent.opponent_board`, `agent.friendly_hp` and a new `agent.mana_max`, and activates through a new `agent.activate_relic(idx, target)` (`state.cmd_activate_relic`, so the command log is unchanged). The relic runtime stays a single state read until task 091 makes relics per side.
4. **Delete** the dead CombatAgent virtuals `_essence_cost_discounts` and `_minion_essence_cost_aura`. Fix the three stale headers.
5. **Lint L18** (provisional; take the next free number if the landing order differs).
   - Scope: `enemies/ai/CombatProfile.gd`, `enemies/ai/profiles/**`, task 119's `enemies/ai/archetypes/**`, and `sim/SimRelicPolicy.gd`.
   - Flag: `agent.state`; `\b(state|st|_state)\._\w+`; `state.player_*` / `state.enemy_*`; `"player"` / `"enemy"` literals; untyped `: Object` handles.
   - Allow: inside `grow_resources`, the `state` parameter may call `grow_essence_max`, `grow_mana_max`, `essence_max_of`, `mana_max_of`, and `_default_growth` in the base only (task 117 leaves just the base and RuneTempo there).
   - Exempt: the adapter (`CombatAgent.gd`, `StateAgent.gd`) and `ProfileRegistry.gd`.
   - The count reaches 0 in this task, so no ratchet is needed.
6. **Docs.**
   - ARCHITECTURE.md: the CombatAgent row (profiles no longer read its typed `state`) and invariant #11 (add L18 next to L9).
   - TESTING.md's lint list.
   - If task 051's file still points its private-read follow-up at "roadmap G4", correct it to this task.

## Verification

- New probe `_agent_reads_are_side_aware`, in task 139's `debug/tests/AiBehaviourTests.gd` (or CommandTests.gd):
  - `build_state({"enemy_passives": ["champion_rogue_imp_pack", "mana_for_spark"]})`, and the enemy places a rune.
  - Player agent: `has_passive("mana_for_spark") == false`, `has_pending_champion() == false`, and `opponent_traps()` is the enemy's traps.
  - Enemy agent: the reverse.
- Mirror probe: `ProfileRegistry.make("enemy", "void_herald")` set up on a **player** agent. The enemy has a Void Rune set, the player has none, and the player holds `void_wind` with Mana for it. After `play_phase()`, Void Wind has left the player's hand. Before the fix `_try_void_wind` (VoidHeraldProfile.gd:59-60) reads `traps_of("player")`, its own side, finds no rune and holds the card.
- Grep gate: `rg -n 'agent\.state|\b(st|state)\._' enemies/ai/CombatProfile.gd enemies/ai/profiles sim/SimRelicPolicy.gd` → only the allowed growth calls.
- L18 negative check: add `agent.state.enemy_passives` to a profile, confirm the lint fails, revert.
- `tools/run_checks.sh` green, including L18.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4; request 3 and 4 explicitly) diffs empty (design/TESTING.md 'Refactor / extraction work'). This holds only after task 073; without it, `_reserved_slots` changes for the player bots.

## Related

- Depends on: task 051 — removes the AI's state writes (11 of the 37 private uses), routes spark cost through the agent and adds L12. This task is its step-6 follow-up.
- Depends on: task 118 (roadmap G2) — removes many read sites (the `_is_feral_imp` and mana_for_spark copies) and adds `agent.has_tag` / `agent.spark_mana_shortfall`.
- Depends on: task 073 — fixes the reachable side-blind `_reserved_slots` first, so this task stays behaviour-neutral. Added on re-check.
- Related: task 072 — rewrites two of the `_opponent_board("enemy")` reads.
- Related: task 095 (roadmap B2a) — champion queries on the agent; deletes `_scene_has`.
- Related: task 097 (roadmap B3) — `agent.flesh()` / `agent.skill_ready(id)`.
- Related: task 101 (roadmap C2) — the hero skill list; agents list skills through this API.
- Related: task 090 — per-side talents and hero passives give `has_talent` / `has_passive` real per-side data.
- Related: task 091 — per-side relics; SimRelicPolicy then reads the side's relic runtime.
- Related: task 083 / task 084 (roadmap A1 / A2) — SideState. AI trap and hand reads go through this API, so they change only the agent.
- Related: task 117 (roadmap G1) — moves the growth push helpers onto `agent`.
- Related: task 099 (roadmap B7, L19), task 087 (roadmap A4, L16), task 111 (roadmap E4, L17) — the other new lint rules; share a counting helper.
- Related: task 121 (roadmap G5) — synchronous profiles, the other half of Q7b.
- Related: tasks 049, 129 and 130 — the other look-ahead prerequisites from Q7b.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) as new roadmap item G7 (direction 4).
  - Re-checked at `404b51c`: 96 `agent.state` uses on 81 lines in 23 files, 37 private uses, the side-blind sites, the dead virtuals and the stale headers.
  - Added: SimRelicPolicy (task 083 points its reads here), the player-bot `state: Object` helpers, `hero_passives` as the player's side of `has_passive`, and task 073 as a dependency.

## Summary

_(filled in at /task-done)_
