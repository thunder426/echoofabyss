---
id: "060"
title: An attack's crit flag leaks onto every damage event nested inside it (crit popups on non-crit hits)
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §I, item 1; unit I bug 4). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

`_apply_crit` (CombatManager.gd:348-371) spends a Critical Strike stack and sets `state._last_attack_was_crit = true` (:363). The flag is cleared only when the whole attack ends (:154, :187), and every damage event journaled in between reads it:
- each minion DAMAGE_DEALT: `source_card = str(info.get("source_card", "")), is_crit = state._last_attack_was_crit})` (:277);
- each hero hit: `var is_crit: bool = _last_attack_was_crit` (CombatState.gd:2020). It goes into the DAMAGE_DEALT payload (:2062) and the `damage_dealt` signal (:2028, :2046).

So the counter-attack, the death and POST triggers, and the post-crit effects inside a crit attack are all journaled as crits. The presenter shows `is_crit` literally: `_play_damage` passes it to `_flash_hero` (CombatPresenter.gd:358) and to `_spawn_damage_popup` (:365). CombatVFXBridge then formats the hit as `"-%d!"` in the large crit font (:678, :725, :750).

### Reachable today

1. **F12 Void Captain.**
   - The fight (EncounterTable.gd:113-115) has the passive `champion_void_captain`. While the champion is on the board, every enemy crit runs `_post_crit` after the strike, still inside the attack (`_check_post_crit`, CombatManager.gd:150 → :423-445).
   - `_post_crit` deals 2 × 100 SPELL damage to random player minions or the hero (:430-445). Both hits are journaled with `is_crit = true` and pop as "-100!".
   - Enemy crit sources in those decks: Throne's Command, "Give all friendly minions +1 Critical Strike." (f12_a ×2, f14_a), and Bastion Colossus, which gains 2 stacks on play (f11_a, f12_a, f14_a, f15_a, f15_p2). Sovereign's Herald, "ON PLAY: Give a friendly minion +1 Critical Strike.", is in every deck from f10_a to f15_p2.
2. **Lord Vael with `death_bolt`, Act 4 (F10–F15).** An enemy crit kills a Void Imp. Its on-death Void Bolt (CardModRules.gd:71-79) hits the enemy hero during the enemy's attack, and the hero flash shows a crit.
3. **The counter-attack** on the attacker carries `is_crit = true`. The lunge ignores it (CombatScene.gd:1829 passes `false` for the counter popup). But when a slot can't be found, `_play_attack` falls back to `_play_damage(hit_a)` (CombatPresenter.gd:575-577), which shows it as a crit.

### Not changed here

`on_player_died_champion_vch` (CombatHandlers.gd:1773-1781, the F14 Void Champion summon counter) reads `state._last_attack_was_crit` to count "crit kills". It still counts any player death during an enemy crit attack. Task 129 (roadmap I1) moves that check to the killing damage and deletes the flag; this task keeps the flag set and cleared exactly as today, so F14 doesn't change.

## Proposed fix

Carry crit on the strike's own damage info.

1. `CombatManager._attack_damage_info(amount, attacker, is_crit: bool = false)` (:322-330) adds `"is_crit": is_crit` to the dict that `make_damage_info` returns.
2. In `resolve_minion_attack` and `resolve_minion_attack_hero`, record whether `_apply_crit` spent a stack. For example, read `state._last_attack_was_crit` into a local right after the call at :90 / :168, or have `_apply_crit` report it. Pass it to:
   - the strike: :100 and :170;
   - the Pierce carry (:125), since that is the strike's own overkill.

   The counter (:138) passes `false`.
3. `_deal_damage` journals `is_crit = info.get("is_crit", false)` instead of the state flag (:277).
4. `CombatState._on_hero_damaged` reads `var is_crit: bool = info.get("is_crit", false)` (:2020).
5. Leave `_last_attack_was_crit`'s set (:363) and clears (:154, :187) in place for the F14 handler.

`apply_damage_to_minion` (:310-313) and `_spell_dmg` (CombatState.gd:647-648) copy the dict and keep the key. Every other damage source builds its info with `make_damage_info`, which has no `is_crit` key, so it reads `false`.

## Verification

- New probe in `debug/tests/TriggerHandlerTests.gd`: **crit only on the strike.**
  - Setup: `TestHarness.build_state({"enemy_passives": ["champion_void_captain"]})`, then `spawn_enemy(state, "champion_void_captain")`.
  - The attacker is `spawn_enemy(state, "void_imp")` with `BuffSystem.apply(attacker, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike", false, false)` and `current_health = 5000`, so it survives the counter and `_check_post_crit` runs the aura.
  - The defender is `spawn_friendly(state, "void_imp")` with `current_health = 5000`.
  - Record the journal size, then `resolve_minion_attack(attacker, defender)`.
  - Among the new DAMAGE_DEALT events: the first one (on the defender) has `is_crit == true`; there are at least 3 more (the counter and two aura hits); every one after the first has `is_crit == false`. Today all of them are true.
- Second probe: **hero strike.** `build_state({})`, an enemy `void_imp` with 1 Critical Strike, then `resolve_minion_attack_hero(attacker, "player")`. The hero DAMAGE_DEALT has `is_crit == true`; without the stack it is false.
- The F14 probe helper `_fire_player_died_by_crit` (TriggerHandlerTests.gd:1457-1463) sets the flag directly and stays as it is.
- `tools/run_checks.sh` green.
- Behaviour-neutral: only journal payloads change, and the one `damage_dealt` listener ignores the crit argument (CombatDiagnostics.gd:32, `_was_crit`). The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, Acts 1–4) diffs empty (design/TESTING.md 'Refactor / extraction work').

## Related

- Related: task 129 (roadmap I1) — depends on this task; deletes `_last_attack_was_crit` and moves the F14 check to `ctx.damage_info`.
- Related: task 134 (roadmap I6) — the typed `DamageInfo` gets `is_crit` as a real field; until then it is a dict key read with a default.
- Related: task 115 (roadmap F2) — presenter matching by cause; it reads the same `is_crit` payloads.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from unit I's straight-to-task bug 4 (roadmap §I item 1). Re-checked at `404b51c`: the flag is read at CombatManager.gd:277 and CombatState.gd:2020 and cleared only at :154 / :187. Narrowed the fix to "crit rides on the strike's DamageInfo"; deleting the flag and moving the F14 counter stay with task 129. The probe gives the attacker high HP, because `_post_crit` skips a dead attacker (:418).

## Summary

_(filled in at /task-done)_
