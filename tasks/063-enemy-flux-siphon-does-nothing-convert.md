---
id: "063"
title: Enemy Flux Siphon does nothing: CONVERT_RESOURCE runs only for the player
status: backlog
area: combat
priority: high
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §A). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Flux Siphon ("Convert up to 3 of your remaining Mana into Essence.", 0 Mana) has the step `{"type": "CONVERT_RESOURCE", "convert_from": "mana", "convert_to": "essence", "amount": 3}` (CardDatabase.gd:1599). The resolver arm only runs for the player. EffectResolver.gd:333-339:

```gdscript
EffectStep.EffectType.CONVERT_RESOURCE:
	# Player-only by design — enemy AI has no resource conversion mechanic.
	if ConditionResolver.check_all(step.conditions, ctx, null) and ctx.owner == "player":
		if step.convert_from == "mana" and step.convert_to == "essence":
			ctx.state.convert_mana_to_essence("player", step.amount if step.amount > 0 else -1)
		elif step.convert_from == "essence" and step.convert_to == "mana":
			ctx.state.convert_essence_to_mana("player")
```

The comment is wrong: an enemy profile casts the card on purpose. The engine helpers already take a side: `convert_essence_to_mana(side)` (CombatState.gd:1514) and `convert_mana_to_essence(side, max_convert)` (:1522). Both call `emit_resources(side)`.

### Reachable today

- F2 Corrupted Broodlings has three decks. `f2_c` (`ai_profile` `corrupted_brood_rune`) holds `flux_siphon` ×1. The deck is in the local `user://encounter_decks.json`; task 047 moves it into the repo.
- `CorruptedBroodRuneProfile.play_phase` casts it first (:19-21) when `_should_flux()` (:100-116) finds a minion that the conversion would make affordable:
  ```gdscript
  if mc.essence_cost > agent.essence and mc.essence_cost <= agent.essence + mini(agent.mana, 3):
  ```
  (:114). For example: 2 Essence and 2 Mana, with `matriarchs_broodling` (4 Essence) in hand.
- The cast goes `_play_spell_by_id` (:154-165) → `agent.commit_play_spell` → `CombatState._cmd_play_spell` → `cast_enemy_spell(spell, target, cast_data)` (CombatState.gd:2657-2658) → `EffectResolver.run` with `ctx.owner = "enemy"` (CombatState.gd:1063-1073). The owner check fails.
- Result: the card is spent, the enemy's Mana and Essence don't change, and the minion the AI planned for stays unaffordable.

The player side is unaffected by the fix. No preset deck holds `flux_siphon` (`grep -c flux_siphon cards/data/PresetDecks.gd` → 0), although four player profiles cast it by id when they have it (SwarmPlayerProfile.gd:38, SerisPlayerProfile.gd:29, FleshcraftPlayerProfile.gd:21, KorrathPlayerProfile.gd:33). No test covers conversion (`grep -rn "flux_siphon\|convert_" debug/` → nothing).

## Decision (owner, 2026-10-01)

- Q2: no mechanic is one-sided by design. Who has what is decided by data and config, "never by `if owner == "player"` in rules code". So no step type is player-only, and the "Player-only by design" comment contradicts the ruling.
- Q3: accept the balance shift and record the BalanceSimBatch delta in the summary.

## Proposed fix

1. In the CONVERT_RESOURCE arm (EffectResolver.gd:333-339), drop `and ctx.owner == "player"` and pass `ctx.owner` to both helpers.
2. Delete the "Player-only by design" comment.
3. Both sides then follow the rule Flux Siphon already has for the player: Essence may go above `essence_max`, and only `ESSENCE_HARD_CAP` (10, CombatState.gd:1360) applies (:1520-1525).
4. Don't change the conversion rule here. Task 065 changes the Energy Conversion direction and the cap arithmetic in the same arm.

## Verification

- New probes in `debug/tests/CardEffectTests.gd`:
  - Enemy cast: `TestHarness.build_state()`, `state.set_mana("enemy", 3)`, `state.set_essence("enemy", 0)`, then `state.cast_enemy_spell(CardDatabase.get_card("flux_siphon") as SpellCardData, null)`. Expect `essence_of("enemy") == 3` and `mana_of("enemy") == 0`. The journal holds a `RESOURCES_CHANGED` event with side `"enemy"` and `essence = 3`. The player's resources are unchanged.
  - The amount cap holds for the enemy: with 5 Mana, 3 convert and 2 Mana remain.
  - Player regression: run the card's steps with `TestHarness.make_ctx(state, "player")` and the same numbers. The result matches today's behaviour.
- `tools/run_checks.sh` green. Parity's "F2 voidbolt" case reaches `f2_c` when the seeded deck pick lands on it.
- Behaviour change: record the BalanceSimBatch delta in the task summary.
  - Run `BalanceSimBatch -- --act 1 --runs 200 --seed 7` before and after. `-- --fight 2 --variant 2` isolates `f2_c`.
  - Expect only the F2 variant 2 rows to move: the enemy curves out a little faster, so `f2_c` gets slightly harder.
  - No other enemy deck holds the card, so `--act 2` should diff empty.

## Related

- Related: task 065. It edits the same CONVERT_RESOURCE arm (Energy Conversion's "up to 3" and one cap rule for both directions). Land in either order; the second one rebases. If 065 lands first, `ESSENCE_HARD_CAP` is `RESOURCE_HARD_CAP` and the two helpers are one `convert_resource(side, from, to, max)`, so steps 1 and 3 pass `ctx.owner` to that. Doing both tasks in one session is cheapest.
- Related: task 092 (roadmap PS-void-marks). It removes the remaining side gates in EffectResolver (VOID_MARK, the GRANT_ESSENCE enemy cap, Path of Corruption / Dark Channeling) and depends on this task.
- Related: task 097 (roadmap B3). It makes the Flesh / Forge step gates (GAIN_FLESH, SPEND_FLESH, GAIN_FORGE_COUNTER, SPEND_FLESH_UP_TO) per side.
- Related: task 082 (roadmap A0). Its verdict-table row for CONVERT_RESOURCE points here.
- Related: task 047. The deck facts above come from the local `user://` copy.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from the A-paths unit's bug 2 and the D-effects unit's bug 1 (roadmap §A).

## Summary

_(filled in at /task-done)_
