---
id: "089"
title: Retire legacy passive_effect_id dispatch; make the card-driven board-passive dispatchers side-neutral
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item A8 (`design/refactors/ARCHITECTURE_ROADMAP.md` §A; the A-paths unit's "A5"). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Minion passives have two dispatch systems:
- **Declarative fields** that work for either side: `on_turn_end_effect_steps`, `on_death_effect_steps`, `on_kill_effect_steps`, `presence_aura_steps`, `on_friendly_summon_aura_steps`, `on_formation_triggered_aura_steps`.
- **String ids** matched in CombatHandlers: `passive_effect_id` (MinionCardData.gd:100-102) and `on_spell_cast_passive_effect_id` (:104-106). Most of these dispatchers walk `state.player_board` and listen to player events only.

Task 062 moves the three on-death cards (`void_spawner`, `abyssal_tide`, `soul_taskmaster`) to a new `on_friendly_death_aura_steps` field. Six legacy cards remain after it:

| Card | Id (CardDatabase.gd) | Dispatcher | Side |
|---|---|---|---|
| `forge_acolyte` | :1263 `"forge_acolyte_flesh_on_sacrifice"` | `on_player_minion_sacrificed_board_passives` (CombatHandlers.gd:747-759), ON_PLAYER_MINION_SACRIFICED only (CombatSetup.gd:579); the arm calls `state._gain_flesh(1)` | player only |
| `void_amplifier` | :2267 `"void_amplifier_buff_demon"` | `on_summon_board_synergies` (CombatHandlers.gd:186-194) walks `state.player_board`, ON_PLAYER_MINION_SUMMONED only, priority 30 (CombatSetup.gd:549); arm :609-615: `BuffSystem.apply(... ATK_BONUS, 100 ...)` and `summoned.current_health += 100` | player only |
| `rune_warden` | :2576 `"rune_warden"` | `on_player_minion_died_rune_warden` (misnamed; CombatHandlers.gd:681-686) on ON_RUNE_PLACED (CombatSetup.gd:586), walks `state.player_board`, TEMP_ATK 200 | player only |
| `void_archmagus` | :2223 `on_spell_cast_passive_effect_id = "add_void_bolt_on_spell"`, :2222 `mana_cost_discount = 1` | `on_void_archmagus_spell` (CombatHandlers.gd:101-107), ON_PLAYER_SPELL_CAST only (CombatSetup.gd:547), once per distinct id (`fired` list); `_apply_spell_cast_passive` adds `_card_for("player", "void_bolt")` (:109-116). The discount is read only in the player branch of `spell_cost` (CombatState.gd:2975-2980) and in its UI copy `CombatScene._spell_mana_discount` (CombatScene.gd:1290-1295) | player only |
| `hollow_sentinel` | :3378 `"hollow_sentinel_spark_buff"` | `on_turn_end_hollow_sentinel` (CombatHandlers.gd:1401-1425), both turn ends (CombatSetup.gd:587-588) | symmetric |
| `rift_warden` | :3435 `"rift_warden_siphon"` | `CombatManager._rift_warden_siphon` (CombatManager.gd:379-395) walks the defender's board | symmetric |

The two symmetric ids are also read by AI code: RiftStalkerProfile.gd:72, :130, :296, :320 compare `passive_effect_id == "hollow_sentinel_spark_buff"`. BoardEvaluator.gd:291 scores `on_spell_cast_passive_effect_id != ""`.

Two more card-driven dispatchers are player-only:
- **Turn-start steps.** `on_minion_turn_start_passives` (CombatHandlers.gd:38-43) walks `state.player_board` with owner `"player"`. It is registered only on ON_PLAYER_TURN_START (CombatSetup.gd:545). Its sibling `on_minion_turn_end_passives` (:49-63) already picks board and owner from the event and is registered on both turn ends (:591-592).
- **Player-champion auto-summon.** `on_summon_board_synergies` also calls `state._check_champion_triggers()` after a Void Imp summon (:192-194). That reads `player_hand + player_deck` and `player_board` (CombatState.gd:2108-2136). `_summon_champion_card` places on `player_slots` and fires ON_PLAYER_MINION_SUMMONED (:2138-2157). The A-paths unit filed this as "A6d"; no other task owns it, and it lives in the handler this task rewrites.

Also dead: `_apply_board_passive_on_death`'s `void_mark_on_void_imp_death` arm (CombatHandlers.gd:794-797) has no card. Task 062 deletes it.

### Reachable today

Nothing reachable. No enemy deck holds `forge_acolyte`, `void_amplifier`, `rune_warden`, `void_archmagus` or `soul_taskmaster`. No preset deck holds them either (`grep -c` over PresetDecks.gd → 0). The only card with `on_turn_start_effect_steps` is `nyx_ael` (CardDatabase.gd:2073), a player champion that is in no preset. f7_a's `hollow_sentinel` and f12_a's `rift_warden` already work for the enemy.

The risk is the next card: an enemy minion with one of these passives silently does nothing, and the string ids are a second dispatch system beside the declarative fields.

## Decision (owner, 2026-10-01)

- Q2: no mechanic is one-sided by design. None of these card passives is player-only; who has the card decides.
- Q3: one mechanic per task; record the BalanceSimBatch result in the summary. Expected here: no change.

## Proposed fix

Follow task 062's pattern: one declarative field per trigger, one side-neutral dispatcher registered on both sides' events, walking `state._friendly_board(<owner of the event>)` (copy it first when a step can summon), with `EffectContext.make(state, src.owner)`, `source = src`, `source_card_id = mc.id`.

1. **Turn start.** Register `on_minion_turn_start_passives` on ON_ENEMY_TURN_START at priority 21 too. Pick board and owner from the event, as `on_minion_turn_end_passives` does, and set `ectx.source_card_id`.
2. **`void_amplifier` → `on_friendly_summon_aura_steps`** (the existing dispatcher, CombatHandlers.gd:632-650):
   `[{"type": "BUFF_ATK", "scope": "TRIGGER_MINION", "filter": "DEMON", "amount": 100, "permanent": true, "source_tag": "void_amplifier"}, {"type": "BUFF_HP", "scope": "TRIGGER_MINION", "filter": "DEMON", "amount": 100, "source_tag": "void_amplifier"}]`.
   - The dispatcher runs at priority 6 instead of 30, so the buff now lands after formation (8) and presence auras (7) instead of before them. Check that no number changes for a Demon summoned next to a Formation partner.
   - BUFF_HP goes through `BuffSystem.apply_hp_gain`, which records an HP_BONUS entry; today's arm adds raw `current_health`. Note it in the summary.
   - The card text says "Whenever you play a Demon"; the code fires on any summon. Keep the code's behaviour (QN1: code wins) and leave the text alone.
3. **`forge_acolyte` → new `on_friendly_sacrifice_aura_steps`**, dispatched on both ON_*_MINION_SACRIFICED with `ectx.dead_minion` = the sacrificed minion: `[{"type": "GAIN_FLESH", "amount": 1, "conditions": ["dead_is_demon"]}]` (ConditionResolver.gd:132). GAIN_FLESH stays player-gated until task 097 (roadmap B3) makes Flesh per side; the dispatcher itself is side-neutral now.
4. **`void_archmagus` → new `on_friendly_spell_cast_aura_steps`**: `[{"type": "ADD_CARD", "card_id": "void_bolt"}]`, dispatched on both ON_*_SPELL_CAST. Keep today's de-dup: each distinct card id fires once per cast, so two Archmagi still add one bolt (CombatHandlers.gd:102-107). ADD_CARD already uses `_card_for(ctx.owner, …)` (EffectResolver.gd:73).
5. **`mana_cost_discount` for either side.** `spell_cost(side, …)` subtracts the discount from `_friendly_board(side)` for both branches. `CombatScene._spell_mana_discount` calls the engine instead of re-summing. Task 085 (roadmap A6) restructures the rest of `spell_cost` (enemy aura, per-card discounts); whichever lands second rebases.
6. **`rune_warden` → new `on_friendly_rune_placed_aura_steps`**: `[{"type": "BUFF_ATK", "scope": "SELF", "amount": 200, "permanent": false, "source_tag": "rune_warden"}]`, dispatched on ON_RUNE_PLACED for `_friendly_board(ctx.owner)`. ON_RUNE_PLACED stays player-only until task 093 (roadmap PS-rituals) fires it for both sides; this dispatcher then works for the enemy with no further change.
7. **`hollow_sentinel`, `rift_warden`: drop only the id.** Give them a minion tag (`"hollow_sentinel"`, `"rift_warden"`) and read it with `state._minion_has_tag` in `on_turn_end_hollow_sentinel`, `_rift_warden_siphon`, RiftStalkerProfile.gd:72, :130, :296, :320. Keep the handlers:
   - Hollow Sentinel buffs once per board (two Sentinels give +100, not +200) and feeds `_hollow_sentinel_buffs`, which BalanceSimBatch prints as "Snt". A per-source declarative step would change both. Changing the rule is a design call, not this task.
   - BoardEvaluator.gd:291 checks `not mc.on_friendly_spell_cast_aura_steps.is_empty()` instead.
8. **Player-champion auto-summon for either side** (A6d). Register the remaining `on_summon_board_synergies` body (the Void Imp `_refresh_slot_for` and the champion check) on both summon events. `_check_champion_triggers(side)`, `_check_champion_condition(champion, side)` and `_summon_champion_card(side, …)` read `hand_of(side)`, `deck_of(side)`, `_friendly_board(side)`, `_friendly_slots(side)`, and fire the side's MINION_SUMMONED event. The "3 Void Imps on board" log text is task 096's (roadmap B2, I7c).
9. **Delete** `passive_effect_id`, `on_spell_cast_passive_effect_id`, `on_player_minion_sacrificed_board_passives`, `on_void_archmagus_spell`, `_apply_spell_cast_passive`, `on_player_minion_died_rune_warden`, `_apply_board_passive_on_summon` and the passive loop in `on_summon_board_synergies`. Fix the CardDatabase.gd:1252-1253 comment that describes the old pattern. Document the new fields in MinionCardData next to `on_friendly_summon_aura_steps`.
10. Update task 104's (roadmap D1) content check: the passive-id vocabulary is gone, so delete its `BOARD_PASSIVE_IDS` / `SPELL_CAST_PASSIVE_IDS` consts and their L14(a) dispatch checks (the arms at CombatHandlers.gd:109, :609, :747-758, :785 and the `passive_effect_id == "x"` literals at CombatHandlers.gd:683, :1413, CombatManager.gd:390, RiftStalkerProfile.gd:72, :296, :320); the two new tags join its tag list.

## Verification

- New probes in `debug/tests/TriggerHandlerTests.gd`, one player-side and one enemy-side per migrated card, using `TestHarness.build_state()`, `spawn_friendly` / `spawn_enemy`:
  - `void_amplifier`: `spawn_enemy(st, "void_amplifier")`, then `st._summon_token("rabid_imp", "enemy")`. The imp has `effective_atk() == 300` and 100 more HP than base. A Human summon is not buffed. Same on the player side.
  - `forge_acolyte` (player side, while Flesh is player-only): with a friendly Acolyte, sacrificing a friendly Demon (`SacrificeSystem.sacrifice(st, demon, "test")`) gives `player_flesh` +1; a Human gives nothing. Enemy side: an enemy Acolyte and an enemy Demon sacrifice leave `player_flesh` unchanged.
  - `void_archmagus`: with an enemy Archmagus on board, `TestHarness.fire(st, Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "enemy", {"card": spell})` adds one `void_bolt` to `hand_of("enemy")`. Two Archmagi still add one. `st.spell_cost("enemy", spell)` is one lower with an enemy Archmagus on board.
  - Turn start: an enemy minion carrying `on_turn_start_effect_steps` (copy `nyx_ael`'s data onto a test card) runs its steps when `st.cmd_end_turn("player")` starts the enemy turn, with `ctx.owner == "enemy"` (it damages player minions, not enemy ones).
  - `rune_warden`: the player places a rune → a friendly Warden gains 200 TEMP_ATK. After task 093 lands, add the enemy-side case.
  - Champion auto-summon: an enemy hand holding `nyx_ael` plus 3 enemy Void Imps on board summons it on the enemy board; the player's case is unchanged.
  - Hollow Sentinel / Rift Warden (no probe exists today): two enemy Sentinels and two enemy Void Sparks, enemy turn end → each spark gains +100 ATK once, not +200. An enemy Rift Warden next to an ETHEREAL enemy minion that is attacked → the prevented damage hits the player hero once.
- `debug/tests/snapshots/handler_order.txt` updated on purpose: the removed handlers disappear, the new dispatchers appear on both sides' events.
- `tools/run_checks.sh` green.
- Behaviour-neutral for the sim: no preset or enemy deck holds the migrated cards, and `hollow_sentinel` / `rift_warden` keep their handlers. The seeded balance fingerprint (`BalanceSimBatch -- --act N --runs 200 --seed 7`, before and after, for N = 1, 2, 3, 4; request 3 and 4 explicitly, f7_a and f12_a are there) diffs empty (design/TESTING.md "Refactor / extraction work"). A non-empty diff is a regression to explain.

## Related

- Depends on: task 062 — it introduces the `on_friendly_death_aura_steps` dispatcher this task copies, and takes the three on-death cards.
- Depends on: task 104 (roadmap D1) — its content check covers the passive ids and tags this task renames; landing after it means the new tag literals in RiftStalkerProfile / BoardEvaluator are checked, and this task removes the passive-id vocabulary from it.
- Depends on: task 054 — it rewrites the `_log(..., _LOG_PLAYER)` lines in the handlers deleted here.
- Depends on: task 055 — it edits the same CombatHandlers lines (Ritual Surge, the GameManager read); land after it to avoid conflicts.
- Related: task 082 (roadmap A0) — rows 1, 5–9 and 21 of its table point here.
- Related: task 093 (roadmap PS-rituals) — fires ON_RUNE_PLACED for both sides, which completes Rune Warden.
- Related: task 097 (roadmap B3) — makes GAIN_FLESH per side, which completes Forge Acolyte.
- Related: task 085 (roadmap A6) — the rest of `spell_cost`'s per-side modifiers.
- Related: task 096 (roadmap B2) — enemy champions as a spec table; this task only touches player-champion auto-summon.
- Related: task 120 (roadmap G4) — keeps BoardEvaluator, which this task edits.
- Related: task 086 (roadmap A3) — if this task lands before 086 phase 2, 086 migrates the new both-sides registrations 1:1; both tasks update handler_order.txt, so coordinate the landing order.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item A8 (the A-paths unit's A5). Added the player-champion auto-summon (A-paths "A6d"), which no other task owned and which lives in `on_summon_board_synergies`.

## Summary

_(filled in at /task-done)_
