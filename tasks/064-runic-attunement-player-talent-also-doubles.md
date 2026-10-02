---
id: "064"
title: Runic Attunement (player talent) also doubles the enemy's rune auras
status: backlog
area: combat
priority: high
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §A). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Runic Attunement is Lord Vael's Rune Master T1 talent: "All Rune aura effects are doubled." (TalentDatabase.gd:153-156). It sets one global multiplier, and every rune aura reads that global, whoever owns the rune. So the player's talent also doubles the enemy's runes.

### The path

- The talent's registry entry is a stat: CombatSetup.gd:69-71 `"runic_attunement": { "triggers": [], "stats": { "rune_aura_multiplier": 2 } }`. `apply_passive` writes it with `st.set(stat, ...)` (:643-645).
- The field is global: CombatState.gd:1803 `var rune_aura_multiplier: int = 1         ## runic_attunement sets this to 2`.
- The getter takes no side: CombatState.gd:396-397 `func _rune_aura_multiplier() -> int: return rune_aura_multiplier`.
- Readers:
  - EffectResolver.gd:625 `"rune_aura":  base = step.amount * ctx.state._rune_aura_multiplier()`;
  - HardcodedEffects.gd:241 (Soul Rune) `var mult: int = state._rune_aura_multiplier()`.
- When the enemy places a rune, `cmd_play_trap` calls `_apply_rune_aura(trap, side)` with `side = "enemy"` (CombatState.gd:2701-2702). The aura handlers build `EffectContext.make(self, owner)` with the enemy as owner (:789, :806; the placement backfill :828). `_amount` then doubles the enemy's rune.

### Reachable today

- **When the player has the talent.** It requires `rune_caller` (T0). The first talent point is given at run start (GameManager.gd:89) and the second after the Act 1 relic reward (RelicRewardScene.gd:157-158). So a Rune Master run has it from Act 2. BalanceSimBatch's death_circle preset also gets it from Act 2 (BalanceSimBatch.gd:51).
- **Enemy runes in Act 2.** Decks are from the local `user://encounter_decks.json`; task 047 moves that file into the repo.
  - F4 deck `f4_b` (`cultist_patrol_tempo`) places `shadow_rune` first (CultistPatrolTempoProfile.gd:23-25). The player's new minions get 2 Corruption instead of 1, because the CORRUPTION step applies `maxi(1, amount)` stacks (EffectResolver.gd:553-556).
  - F5 deck `f5_a`, the only F5 deck, holds `dominion_rune` ×2 and `blood_rune` ×2. `VoidRitualistProfile` places runes first (:22-23).
    - Dominion Rune gives enemy Demons +200 ATK instead of +100. This includes the backfill on placement (CombatState.gd:816-832).
    - Blood Rune heals the enemy 200 instead of 100 per enemy minion death.
- F2 deck `f2_c` (Act 1) also holds Dominion and Blood Runes, but an Act 1 run cannot have the talent yet.

No test sees this. Parity's "F3 death_circle" case has the talent, but no F3 deck holds a rune. The only probe (TriggerHandlerTests.gd:833-838) checks that the stat equals 2.

## Decision (owner, 2026-10-01)

- Q2: talents must work for either side, and who has what is decided by data and config, "never by `if owner == "player"` in rules code". That rules out the quick fix `return rune_aura_multiplier if owner == "player" else 1`. Store the multiplier per side.
- Q3: accept the balance shift and record the BalanceSimBatch delta in the summary.

## Proposed fix

1. Replace the global with a per-side pair, `player_rune_aura_multiplier` and `enemy_rune_aura_multiplier` (both default 1). Add `rune_aura_multiplier_of(side: String) -> int`, following `essence_of` / `mana_of` (CombatState.gd:1432-1442).
2. Rename the talent's stat key at CombatSetup.gd:71 to `player_rune_aura_multiplier`. Talents apply to the player today. Task 090 (roadmap PS-talents) gives `apply_passive` a side and moves the pair into SideState with the other talent stats.
3. `_amount` (EffectResolver.gd:625) uses `ctx.state.rune_aura_multiplier_of(ctx.owner)`. For a rune aura, `ctx.owner` is the rune's owner (CombatState.gd:789, :806, :828).
4. Soul Rune (HardcodedEffects.gd:241) uses `state.rune_aura_multiplier_of(ctx.owner)`.
5. Delete `_rune_aura_multiplier()` and its comment (CombatState.gd:395-397), and update the field comment at :1803.
6. The fields are not in `digest_text`, so Parity compares the same state as before.

## Verification

- New probes in `debug/tests/TriggerHandlerTests.gd`:
  - Enemy rune, player talent: `st := TestHarness.vael_state(["runic_attunement"])`, `imp := TestHarness.spawn_enemy(st, "rabid_imp")` (Demon, 200 ATK). Then `rune := CardDatabase.get_card("dominion_rune") as TrapCardData`, `st.enemy_active_traps.append(rune)`, `st._apply_rune_aura(rune, "enemy")`. The backfill buffs the imp: expect `imp.effective_atk() == 300`, not 400.
  - Player rune, player talent: the same rune on the player side with a friendly `rabid_imp` gives 400.
  - Enemy Blood Rune with the talent active: set `st.enemy_hp = 1500`, place an enemy `blood_rune`, and kill an enemy minion. The enemy heals 100, not 200.
  - Update `_runic_attunement_stat` (:833-838): `rune_aura_multiplier_of("player") == 2` and `rune_aura_multiplier_of("enemy") == 1`.
- `tools/run_checks.sh` green. Parity does not exercise this fix, because no Parity fight has both the talent and enemy runes.
- Behaviour change: record the BalanceSimBatch delta in the task summary.
  - Run `BalanceSimBatch -- --act 2 --runs 200 --seed 7` before and after.
  - Direction: today the leak strengthens enemy runes against Rune Master runs, so the fix makes the fights easier for the player. Expect only death_circle's F4 variant 1 (`f4_b`) and F5 rows to move, with the win rate up.
  - Every other preset should be identical.
  - Request `--act 1`, `--act 3` and `--act 4` explicitly. They should diff empty: there is no talent in Act 1 and no enemy rune deck in Acts 3–4.

## Related

- Related: task 090 (roadmap PS-talents). It makes talents and hero passives per side; the multiplier pair moves into SideState there.
- Related: task 083 (roadmap A1). It introduces SideState.
- Related: task 082 (roadmap A0). Its verdict-table row for `rune_aura_multiplier` points here.
- Related: task 093 (roadmap PS-rituals). It makes the rune events (`ON_RUNE_PLACED`, rituals) work for either side.
- Related: task 050. It routes rune removal through one API and touches `_apply_rune_aura` / `_remove_rune_aura` callers, not the multiplier. No ordering constraint.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from the A-paths unit's bug 3 and the D-effects unit's bug 2 (roadmap §A).

## Summary

_(filled in at /task-done)_
