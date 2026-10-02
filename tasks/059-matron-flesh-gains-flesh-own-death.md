---
id: "059"
title: Matron of Flesh gains Flesh for its own death and for friendly deaths during its attack
status: done
area: combat
priority: normal
started: 2026-10-02
finished: 2026-10-02
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §I, item 1; unit F bug 4 and unit I bug 3). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Matron of Flesh (CardDatabase.gd:1200-1224) is a 5E 400/600 Demon, Grafted Fiend, in the `seris_fleshcraft` pool with act gate 3 (:3515, :3626). Its text (:1208) ends "Whenever this minion kills an enemy minion, gain 1 Flesh." The code is `on_kill_effect_steps = [{"type": "GAIN_FLESH", "amount": 1}]` (:1219-1221). It is the only card with on-kill steps (`grep -n "on_kill_effect_steps *=" cards/data/CardDatabase.gd` → :1219).

Kill credit goes to whoever is attacking, not to whoever killed:
- `resolve_minion_attack` sets `state._last_attacker = attacker` (CombatManager.gd:76) and clears it only when the attack ends (:152-153).
- Every death in between gets `ctx.attacker = _last_attacker` (CombatState.gd:2008), whoever died and whatever killed it.
- `on_minion_killed_on_kill_steps` (CombatHandlers.gd:729-742) is registered on both ON_PLAYER_MINION_DIED and ON_ENEMY_MINION_DIED (CombatSetup.gd:584-585). It never compares the dead minion with the attacker:
  ```gdscript
  var attacker: MinionInstance = ctx.attacker
  if attacker == null or attacker.card_data == null:
      return
  ...
  var eff_ctx         := EffectContext.make(state, attacker.owner)
  ...
  EffectResolver.run(steps, eff_ctx)
  ```
  GAIN_FLESH then runs for `attacker.owner` (EffectResolver.gd:342-345).

### Reachable today (Seris, Fleshcraft branch)

1. **Matron dies to the counter-attack: +1 Flesh.** Matron attacks a minion that survives and hits back for at least her HP. The counter (CombatManager.gd:138) kills her → ON_PLAYER_MINION_DIED with `ctx.attacker` = Matron → GAIN_FLESH. She is credited with killing herself.
2. **Friendly deaths during her attack: +1 Flesh each.** Example: she kills a Void-Touched Imp (`"ON DEATH: Deal 100 damage to all enemy minions."`, CardDatabase.gd:2657-2667; all three fight-2 decks). Each friendly minion the AoE kills fires ON_PLAYER_MINION_DIED with `ctx.attacker` = Matron, for +1 Flesh each. The kill of the VTI itself (+1) is correct.

No BalanceSimBatch deck holds `matron_of_flesh`: it isn't in `PresetDecks.gd` or `BalanceSimBatch.gd`, and only `CardDatabase.gd` names it.

### Not fixed here (kill credit, task 129 / roadmap I1)

- Enemy deaths caused by effects nested inside her attack (not by her strike or counter) still credit her after this fix.
- A counter-attack kill never credits the defender: `ctx.attacker` is always the attacker. Whether a counter-kill counts as "this minion kills" is an open owner question raised in grooming (unit I).
- Both go to task 129 (roadmap I1), which takes kill credit from the killing damage.

## Proposed fix

1. In `on_minion_killed_on_kill_steps`, after the null checks, add:
   ```gdscript
   if ctx.minion == null or ctx.minion.owner == attacker.owner:
       return
   ```
   It compares owners, with no side literal, so it holds for an enemy Matron once Flesh works for either side (owner decision Q2; task 097). The same-owner check also excludes her own death, since her owner is her own side.
2. Fix the stale doc comment above the handler (:725-728). It says "ctx.attacker is populated by CombatScene during attack resolution"; it is set by `CombatState._on_minion_vanished` from `_last_attacker`.

## Verification

New probes in `debug/tests/TriggerHandlerTests.gd`. Use `TestHarness.build_state({"hero_id": "seris"})` with no hero passives, so Fleshbind adds no Flesh.
- **No Flesh for her own death.**
  - Setup: `matron = spawn_friendly(state, "matron_of_flesh")`, `matron.current_health = 100`. `colossus = spawn_enemy(state, "bastion_colossus")`: 600/800 with Ethereal, so Matron's strike lands for 200 and the Colossus survives. Then `state.combat_manager.resolve_minion_attack(matron, colossus)`.
  - Assert Matron is off the board and `player_flesh == 0` (today 1).
- **No Flesh for friendly deaths; +1 for the real kill.**
  - Setup: full-HP Matron, plus `spark = spawn_friendly(state, "void_spark")` (100/100). `vti = spawn_enemy(state, "void_touched_imp")`. Then `resolve_minion_attack(matron, vti)`.
  - Assert the spark died and `player_flesh == 1` (today 2).
- `tools/run_checks.sh` green.
- Behaviour change for runs with Matron, but no sim deck holds her. The seeded fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, Acts 1–4) should diff empty. Record the result in the task summary.

## Related

- Related: task 129 (roadmap I1) — depends on this task; replaces `_last_attacker` kill credit with the Resolution stack and settles counter-kill credit.
- Related: task 057 — the same VTI trace. A minion that dies twice also fires this handler twice.
- Related: task 097 (roadmap B3) — moves GAIN_FLESH (player-only today, EffectResolver.gd:343-344) to the owning side's Seris module.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1); merges unit F bug 4 and unit I bug 3. Re-checked at `404b51c`: `_last_attacker` lives for the whole attack, and the handler has no owner check. Confirmed that no sim deck holds Matron, so no balance delta is expected.
- 2026-10-02: started (P2 ticket 2), on top of task 057.
  - Fix as proposed: `on_minion_killed_on_kill_steps` returns when `ctx.minion` is null or shares the attacker's owner (no side literal); the stale "populated by CombatScene" doc comment now names `CombatState._on_minion_vanished` / `_last_attacker`.
  - Probes: TriggerHandlerTests `matron_of_flesh /` ×2 (her own death to a Bastion Colossus counter → 0 Flesh; VTI kill + spark killed by the VTI's AoE → 1 Flesh). On the old handler they fail with exactly the task's "today" values (1 and 2).
  - Gate: the first run_checks (under the parallel BalanceSimBatch load) failed on a LiveSmoke SCRIPT ERROR, `ScreenShakeEffect.shake` calling `is_inside_tree` on a node freed during its timer await. Unrelated to this task; fixed in its own commit (`5498c48`). Re-run green: lint 0, 197 scripts, 1152 tests, LiveSmoke OK, Parity 24/24.
  - Fingerprint (`--runs 200 --seed 7`, Acts 1–4) vs `cf58558`: byte-identical, as expected (no sim deck holds Matron). The probes are the only cover.
- 2026-10-02: closed.

## Summary

Matron of Flesh's on-kill Flesh now needs an opposing minion's death: `on_minion_killed_on_kill_steps` skips deaths on the attacker's own side, so her own death to the counter and friendly deaths during her attack no longer give Flesh. Two probes cover it; the seeded fingerprint is byte-identical (no sim deck holds her).
Follow-ups: task 129 takes kill credit from the killing damage (nested effects, counter-kills).
