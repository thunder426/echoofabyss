---
id: "117"
title: AI resource growth as data: one generic grow_resources, no literal 11
status: backlog
area: ai
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item G1 (`design/refactors/ARCHITECTURE_ROADMAP.md` §G). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### Growth is code, copied 24 times

`rg -n '^func grow_resources' enemies/ai` gives 25 definitions: the base (CombatProfile.gd:293, which calls the engine's `_default_growth`) and 24 overrides (ScoredCombatProfile.gd:329 and 23 files in `enemies/ai/profiles/`).

Every override starts with the same prelude:

```
if turn <= 1:
	return
var e: int = state.essence_max_of(side)
var m: int = state.mana_max_of(side)
if e + m >= 11:
	return
```

- 10 overrides inline it. 14 are one-line delegations to a `_xxx_growth` helper that holds it, left over from the plan-2A.4 port (e.g. VoidScoutProfile.gd:74-75 → `_void_scout_growth` :77).
- `rg -n '>= 11' enemies/ai --glob '*.gd'` gives 24 code hits, one per override. The engine has `const COMBINED_RESOURCE_CAP := 11` (CombatState.gd:1358).
- The cap check is redundant. `grow_essence_max` and `grow_mana_max` already stop at the cap: CombatState.gd:1496 and :1506 `if essence_max_of(side) + mana_max_of(side) >= COMBINED_RESOURCE_CAP:` / `break`. Deleting the prelude changes nothing.

### What the 24 curves are

17 are plain ladders: the first step whose target isn't reached grows by 1; past the ladder, the fallback grows.

| Profile (growth func) | Ladder | Else |
|---|---|---|
| CorruptedBroodRune :66 | E2 M2 E6 M4 | E |
| CorruptedHandler :134 | E4 M2 E7 | M |
| CultistPatrol :17 | E2 M2 (written as `if m < 2 and e >= 2`, same result) | E |
| CultistPatrolTempo :79 | E2 M2 E5 M3 E7 | M |
| FeralPackScreech :57 | E4 M2 E6 M3 | E |
| Matriarch :28 | — | M |
| MatriarchAggro :48, MatriarchSac :47 (identical) | E4 M2 E6 M4 | E |
| RiftStalker :238, VoidCaptain :56 (identical) | E5 M3 | E |
| VoidAberration :52 | E4 M3 E6 | M |
| VoidChampion :257 | E4 M4 E5 M5 | E |
| VoidHerald :87 | E4 M2 E6 M3 E8 | M |
| VoidRitualistPrime :139 | M4 E3 M6 E4 | M |
| VoidRitualist :52 | E2 M2 E4 M4 | E |
| VoidScout :77 (inherited by AbyssSovereign P1/P2) | E5 M2 | E |
| SpellBurnPlayer :43 | M3 E2 | M |

7 depend on the hand or board:
- DefaultPlayer `_grow_aggro` (:42): a Mana push (`m_max < 2 and _needs_mana_push(state)`), an Essence push (a hand minion's `essence_cost > e_max`), then the engine's default rule (`m_max < e_max - 2` → Mana, else Essence).
- Korrath `_grow_korrath` (:66) and Seris `_grow_seris` (:138), identical: the Essence push, then the default rule.
- Swarm `_grow_swarm` (:149): two Mana pushes (`dominion_rune` in hand with 3+ Demons on board; `abyssal_sacrifice` with hand ≤ 3 and a cheap token), the Essence push, then the default rule.
- VoidWarband `_warband_growth` (:166): a Mana push (`m == 1 and _needs_mana_for_lance()`), then E4 M2 E7, else M.
- RuneTempo `_grow_rune_tempo` (:40): two flex rules sit in the middle of the ladder (after M2, before E4). Not a plain ladder.
- ScoredCombatProfile (:329): scores Essence against Mana from the hand. Task 120 deletes it.

### Consequences

- Raising `COMBINED_RESOURCE_CAP` would leave all 24 profiles stopping at 11, with no error.
- A new curve means copying about 15 lines.
- The prose curves in profile headers have drifted. VoidChampionProfile.gd:21-22 `## Resource growth:` / `##   Essence to 5 → Mana to 3 → Essence to 7`, but the code (:257-275) and CommandTests' `void_champion` row give E4 → M4 → E5 → M5 → E6.
- The player-bot push helpers read the player's fields whatever `side` is, through an untyped handle: DefaultPlayerProfile.gd:68-69 `func _needs_mana_push(state: Object) -> bool:` / `for inst in state.player_hand:`, also :84 and :92 (`state.player_board`); SwarmPlayerProfile.gd:185-197; RuneTempoPlayerProfile.gd:219-248. Correct today, because these profiles only play the player side, but side-blind (owner Q1/Q2) and outside invariant #11's typed access.

### What pins the behaviour today

CommandTests `_GROWTH_CURVES` (CommandTests.gd:634-670, 35 rows), run by `_growth_curves_match_the_ported_sim_curves` (:672), checks every registered profile from 1/1 over turns 1–10. It runs on an empty hand (:683-684 clear both hands), so none of the pushes above is pinned.

## Proposed fix

1. **Characterise first (own commit).** Add a probe `_growth_hand_pushes` to task 139's AiBehaviourTests.gd (this task depends on 139). One row per push, each with a hand / board setup and the expected resource:
   - `default` (player): `e_max 4, m_max 1`, a 5-Essence minion in hand → Essence (the default rule alone would pick Mana). `m_max 1`, `abyssal_sacrifice` in hand, hand size ≤ 3, a `void_imp` on board → Mana.
   - `korrath`, `seris`: the same Essence-push row.
   - `swarm`: `dominion_rune` in hand and 3 Demons on board at `m_max 1` → Mana; the `abyssal_sacrifice` row → Mana; the Essence-push row.
   - `rune_tempo`: `e 2, m 2`, no minion in hand → Mana; a minion costing more than `e` and no castable spell → Essence.
   - `void_warband` (enemy): `m 1`, `void_lance` in hand, a player minion with ≥ 600 HP → Mana (the ladder alone says Essence while `e < 4`).

   It must pass on today's code before step 2 starts.
2. **Data hooks on CombatProfile.**
   - `growth_curve() -> Array`: ordered `[resource, target]` pairs, e.g. `[["essence", 4], ["mana", 2]]`. Default `[]`.
   - `growth_fallback() -> String`: `"essence"`, `"mana"` or `"default"` (the engine's `_default_growth` rule). Default `"default"`.
   - `growth_push() -> String`: `"essence"`, `"mana"` or `""`. Default `""`. It reads through `agent`, which every caller sets up before growth runs (CombatSim._build :64-72, EnemyTurnRunner._profile :52-59, ParityTests :127-132, LiveSmokeTests :207-214, CommandTests :681-682).
   - The base `grow_resources(state, side, turn)`: return when `turn <= 1`; grow the push if there is one; otherwise grow the first ladder step below its target; otherwise apply the fallback. No cap check.
   - Each profile returns its own `const` from these methods, so the data sits next to the profile it tunes.
3. **Replace the 17 ladders** with `growth_curve()` / `growth_fallback()`. CultistPatrol becomes `[["essence", 2], ["mana", 2]]`, else Essence. The identical pairs (MatriarchAggro / MatriarchSac, RiftStalker / VoidCaptain) keep separate constants: they are separate encounters and should be tunable apart (task 119's point).
4. **Pushes.** DefaultPlayer, Korrath, Seris, Swarm and VoidWarband become `growth_push()` plus a curve or fallback. Their pushes all run before the ladder today, so the order is kept.
   - One shared base helper for the Essence push (a hand minion's `essence_cost > e_max`), used by DefaultPlayer, Korrath, Seris and Swarm.
   - The push helpers read `agent.hand` / `agent.friendly_board` instead of `state.player_hand` / `state.player_board`, and lose their `state: Object` parameters. That is identical for the player table.
5. **RuneTempo** keeps its own `grow_resources`, because its flex rules sit mid-ladder. It drops the cap prelude and reads through `agent`. **ScoredCombatProfile:** if task 120 has landed it is gone; otherwise leave it untouched.
6. **Delete** the 14 `_xxx_growth` helpers, all 24 `>= 11` preludes, and the prose growth blocks in the profile headers (e.g. VoidChampionProfile.gd:21-22, VoidScoutProfile.gd:17-18, DefaultPlayerProfile.gd:10-18). The curve constant is the documentation. Update the base-profile row of ARCHITECTURE.md's AI table to name the hooks.
7. **Optional guard:** a CommandTests probe that fails when a `ProfileRegistry` script other than RuneTempoPlayerProfile (and ScoredCombatProfile while it exists) declares `func grow_resources` (read the script's `source_code`). A new profile then adds a curve, not a copy.

## Verification

- `_GROWTH_CURVES` unchanged (35 rows, or 30 after task 120) and the new `_growth_hand_pushes` unchanged between step 1 and the end.
- Grep gates: `rg -n '>= 11' enemies/ai --glob '*.gd'` → nothing. `rg -n '^func grow_resources' enemies/ai` → the base and RuneTempo (plus ScoredCombatProfile if task 120 hasn't landed).
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4: every act has a rewritten curve) diffs empty (design/TESTING.md 'Refactor / extraction work'). Request Acts 3 and 4 explicitly; BalanceSimBatch defaults to Acts 1–2 (BalanceSimBatch.gd:456).

## Related

- Depends on: task 047 — enemy decks in the repo, so the before/after fingerprint is stable and reproducible.
- Depends on: task 139 (roadmap J3) — one fixed-board decision probe per profile; a mis-ported push shows as a named failure instead of an aggregate shift.
- Related: task 120 (roadmap G4) — deletes ScoredCombatProfile, its custom growth and its 5 `_GROWTH_CURVES` rows.
- Related: task 119 (roadmap G3) — depends on this task. After flattening, AbyssSovereign P1/P2 declare VoidScout's curve themselves.
- Related: task 122 (roadmap G7) — profiles read only through CombatAgent; the push helpers already do after step 4.
- Related: task 121 (roadmap G5) — synchronous profiles; growth is already synchronous.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item G1.
  - Re-checked at `404b51c`: 25 definitions, 24 `>= 11` hits, the cap enforced in `grow_essence_max` / `grow_mana_max`, 17 ladders and 7 hand-dependent overrides, the identical pairs, the stale VoidChampion header.
  - `_GROWTH_CURVES` has 35 rows (the unit report said 34).
  - Added: the push helpers' side-blind `state.player_*` reads through `state: Object`; identical pairs stay separate for task 119.

## Summary

_(filled in at /task-done)_
