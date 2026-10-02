---
id: "062"
title: Enemy Void Spawner and Abyssal Tide passives never fire (legacy on-death board passives are player-only)
status: backlog
area: combat
priority: high
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §A). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Void Spawner ("PASSIVE: Whenever a friendly Demon dies, summon a 100/100 Void Spark.") and Abyssal Tide ("PASSIVE: Whenever a friendly minion dies, deal 200 damage to enemy hero.") only work for the player. Their passive is a `passive_effect_id` string (CardDatabase.gd:2023 `void_spawner.passive_effect_id = "void_spark_on_friendly_death"`, :2036 `abyssal_tide.passive_effect_id = "deal_200_hero_on_friendly_death"`), and the one handler that reads it is player-only.

### The path

- `CombatState._on_minion_vanished` erases the dead minion from its board (CombatState.gd:1990), then fires `ON_PLAYER_MINION_DIED` or `ON_ENEMY_MINION_DIED` by owner (:2004-2009).
- The board-passive dispatcher listens to the player event only. CombatSetup.gd:576:
  ```gdscript
  tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED,    h.on_player_minion_died_board_passives,  0)
  ```
  `debug/tests/snapshots/handler_order.txt` line 12 confirms that `ON_ENEMY_MINION_DIED` has no board-passive listener.
- It walks the player's board only: CombatHandlers.gd:763 `for m in state.player_board.duplicate():`.
- The arms in `_apply_board_passive_on_death` (CombatHandlers.gd:785-802) name the player side, so dispatching them for the enemy would still be wrong:
  - Void Spawner calls `state._summon_void_spark()`, which is `_summon_token("void_spark", "player")` (CombatState.gd:2086-2087). The spark lands on the player's board.
  - Abyssal Tide calls `state.combat_manager.apply_hero_damage("enemy", ...)` (CombatHandlers.gd:792-793). An enemy Tide would hit its own hero.

### Reachable today

Enemy decks are from the local `user://encounter_decks.json`; task 047 moves that file into the repo.

- **F6 Corrupted Handler (Act 2 boss).**
  - `f6_a`, the only F6 deck, holds `void_spawner` ×2.
  - `CorruptedHandlerProfile` plays it first, on purpose (CorruptedHandlerProfile.gd:23-25: "These need to be on board BEFORE humans die so their death triggers create sparks").
  - When an enemy Demon dies (brood_imp, void_stalker, the other Spawner, or a feral imp from the `feral_reinforcement` passive), no spark appears.
  - The F6 champion counts enemy Void Spark summons: 3 sparks summon it (CombatHandlers.gd:2226-2238), and while it lives each spark deals 200 to the player (:2240-2242). Without the Spawner's sparks the champion arrives later and its aura fires less often than designed.
- **F3 Imp Matriarch, deck `f3_b`** (`ai_profile` `matriarch_aggro`).
  - It holds `abyssal_tide` ×1.
  - `MatriarchAggroProfile` grows Essence to 7 ("4E → 2M → 6E → 4M → 7E", MatriarchAggroProfile.gd:8) and plays its minions, so the 5-Essence Tide comes down.
  - After that, enemy minion deaths deal no damage to the player.

### The rest of the same dispatcher

- `soul_taskmaster_gain_atk` (CardDatabase.gd:2254, `vael_common` pool) is player-only for the same reason. No enemy deck holds it today.
- `void_mark_on_void_imp_death` (CombatHandlers.gd:794-797) is a dead arm: no card sets that id.
- The Soul Taskmaster check `dead != passive_owner` (:799) is always true. The dead minion has left the board before the event fires (CombatState.gd:1990).

The swarm preset holds the player's own `void_spawner` (PresetDecks.gd:20). The player side must not change.

## Decision (owner, 2026-10-01)

- Q2: no mechanic is one-sided by design. Who has what is decided by data and config, "never by `if owner == "player"` in rules code".
- Q3: accept the balance shift, one mechanic per task, and record the BalanceSimBatch delta in the summary.

## Proposed fix

1. **New declarative field.** Add `on_friendly_death_aura_steps: Array` to `MinionCardData` (shared/resources/MinionCardData.gd), next to `on_friendly_summon_aura_steps` (:167). Document it like that field.
2. **One side-neutral dispatcher.** Add `on_minion_died_friendly_auras(ctx)` to CombatHandlers, modelled on `on_minion_summoned_friendly_aura` (CombatHandlers.gd:632-650):
   - `dead := ctx.minion`; walk `state._friendly_board(dead.owner).duplicate()`. Copy the board, because a SUMMON step appends to it.
   - For each source with non-empty steps: `EffectContext.make(state, src.owner)`, with `source = src`, `source_card_id = mc.id` and `dead_minion = dead`. Then `EffectResolver.run(mc.on_friendly_death_aura_steps, ectx)`.
3. **Register it on both death events at priority 0**, on the line that registers today's dispatcher (CombatSetup.gd:576), so the equal-priority order on the player event is unchanged. On the enemy event it becomes the first priority-0 listener, ahead of `on_minion_died_environment`.
4. **Migrate the three cards** and clear their `passive_effect_id`:
   - `void_spawner`: `[{"type": "SUMMON", "card_id": "void_spark", "conditions": ["dead_is_demon"]}]`. The condition exists (ConditionResolver.gd:132) and reads `ctx.dead_minion`.
   - `abyssal_tide`: `[{"type": "DAMAGE_HERO", "amount": 200}]`. DAMAGE_HERO targets the opponent of `ctx.owner` (EffectResolver.gd:40).
   - `soul_taskmaster`: `[{"type": "BUFF_ATK", "scope": "SELF", "amount": 50, "permanent": true, "source_tag": "soul_taskmaster_stack", "conditions": ["dead_is_demon"]}]`.
5. **Delete** `on_player_minion_died_board_passives`, `_apply_board_passive_on_death` (with the dead `void_mark_on_void_imp_death` arm), `CombatState._summon_void_spark` and the CombatSetup.gd:576 registration. Leave the other `passive_effect_id` cards to task 089 (roadmap A8).
6. **Expected side effects.** All are cosmetic; write them in the summary.
   - Abyssal Tide's hit becomes source MINION with the Tide as `attacker` (`_build_damage_info`, EffectResolver.gd:683-685). Today it is SPELL with no attacker. For hero damage the source only feeds the sim damage-log label, and `source_card` `"abyssal_tide"` still wins there (CombatState.gd:2041-2045). The `DAMAGE_DEALT` payload gains a `source_minion`.
   - Soul Taskmaster's buff now journals `BUFF_APPLIED` with before and after values. The old arm applied it with `emit_vfx = false` (:800). The buff VFX now plays.
   - The three `_log(..., _LOG_PLAYER)` lines go away.
   - Latent: an enemy Tide's DAMAGE_HERO passes through `_dark_channeling_dmg` (EffectResolver.gd:739-754, enemy-only, the F13 / F15 passive). It amplifies only while the side-channel flag `_dark_channeling_active` is set by an enemy spell cast; the next `EffectResolver.run` to finish clears it (:27-28). So a Tide trigger nested inside such a spell would take ×1.5 and clear the flag early. That is task 129's (roadmap I1) side-channel problem. No F13 or F15 deck holds the Tide.

## Verification

- New probes in `debug/tests/TriggerHandlerTests.gd`, using `TestHarness.build_state()`, `spawn_enemy` / `spawn_friendly` and `state.combat_manager.kill_minion(m)`:
  - An enemy `void_spawner` next to an enemy `rabid_imp` (Demon). Kill the imp. Expect `TestHarness.count_on_board(st, "enemy", "void_spark") == 1` and `count_on_board(st, "player", "void_spark") == 0`.
  - The same with an enemy `abyssal_tide`: `player_hp` drops by 200 and `enemy_hp` is unchanged.
  - A non-Demon death (`abyss_cultist`) next to an enemy `void_spawner` summons nothing.
  - Two enemy Spawners and one Demon death give two sparks. Sources stack, as on the player side today.
  - Player-side regressions for all three cards: the spark lands on the player's board, `enemy_hp` drops by 200, and a friendly Soul Taskmaster gains +50 ATK per friendly Demon death.
  - F6 cross-check: `build_state({"enemy_passives": ["champion_corrupted_handler"]})`, an enemy Spawner, and one enemy Demon death leave `state._champion_ch_spark_count == 1`.
- `debug/tests/snapshots/handler_order.txt` updated on purpose: the new dispatcher appears on both death events, and `on_player_minion_died_board_passives` is removed.
- `tools/run_checks.sh` green. Parity's "F6 korrath" case fights `f6_a`, so it exercises the enemy Spawner.
- Behaviour change: record the BalanceSimBatch delta in the task summary. Run `BalanceSimBatch -- --act 1 --runs 200 --seed 7` and `-- --act 2 --runs 200 --seed 7` before and after.
  - Expect F6 to get harder for every preset (more enemy sparks, an earlier champion, more aura damage, more spark transfers).
  - Expect F3 variant 1 (`f3_b`) to get harder. `-- --fight 3 --variant 1` isolates it.
  - Every other row should be identical. In particular the swarm preset's own Void Spawner must not move it outside F3 `f3_b` and F6.
  - Request `--act 3` and `--act 4` explicitly: no enemy deck there holds these cards, so they should diff empty.

## Related

- Related: task 089 (roadmap A8). It retires the rest of the `passive_effect_id` dispatch (void_amplifier, forge_acolyte, rune_warden, void_archmagus, hollow_sentinel, rift_warden) and deletes the field. It depends on this task, which takes the three death-passive cards.
- Related: task 082 (roadmap A0). Its verdict-table row "on-death board passives" points here.
- Related: task 054. The arms deleted here use `_LOG_PLAYER`. Whichever task lands second rebases those lines.
- Related: task 104 (roadmap D1). Its list of board-passive ids loses the four ids deleted here.
- Related: task 047. The deck facts above come from the local `user://` copy that task moves into the repo.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from the A-paths unit's straight-to-task bug 1 (roadmap §A).

## Summary

_(filled in at /task-done)_
