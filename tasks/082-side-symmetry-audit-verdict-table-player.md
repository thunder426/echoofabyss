---
id: "082"
title: Side-symmetry audit: verdict table for every player-only rules path, plus an enemy-content guard test
status: backlog
area: architecture
priority: high
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item A0 (`design/refactors/ARCHITECTURE_ROADMAP.md` §A). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

ARCHITECTURE.md invariants #2 ("symmetric handlers") and #3 ("symmetric effects") say every handler and every card effect works for either side. Many rules paths still act only for the player, and one player talent leaks into the enemy side.

- Grooming pass 1 added a "**Not yet true (2026-10-01)**" caveat under the invariants (ARCHITECTURE.md:335, working tree). It points at this task's table.
- The roadmap's §A still lists the player-only paths as review bullets (ARCHITECTURE_ROADMAP.md:46-55), with no verdict or owner per path.

The consequence: enemy content that uses a player-only path does nothing, and nothing reports it. Today that is Void Spawner and Abyssal Tide (task 062) and Flux Siphon (task 063). Runic Attunement leaks the other way (task 064). New code is also written assuming the symmetry the doc advertises.

### The verdict table (pre-filled by grooming, verified at `404b51c`)

Enemy content means the 23 decks in `user://encounter_decks.json` (60 distinct card ids; task 047 moves the file into the repo). Add the cards they summon (SUMMON `card_id`s), the tokens encounter passives summon (`void_demon`, `void_spark`, `void_touched_imp`, CombatHandlers.gd:1278, :1294, :2092), the champion cards (:2281) and the `feral_imp`-tagged cards that `feral_reinforcement` deals. Enemy runes: `dominion_rune` and `blood_rune` in f2_c and f5_a, `shadow_rune` in f4_b.

Under Q2 no verdict is "intended". Each row is **reachable** (a bug now), **latent** (no enemy content reaches it yet) or **symmetric**.

| # | Path | Evidence | Enemy content reaching it | Verdict | Fix |
|---|---|---|---|---|---|
| 1 | Turn-start minion steps | CombatHandlers.gd:38-43 `for m in state.player_board.duplicate():`; registered only on ON_PLAYER_TURN_START (CombatSetup.gd:545) | none (only `nyx_ael` has the field, CardDatabase.gd:2073) | latent | 089 |
| 2 | Attack PRE / POST | CombatManager.gd:85, :110 (minion target), :163, :177 (hero target): `if attacker.owner == "player" ...`. The enemy gets one pre-damage ON_ENEMY_ATTACK that sets only `ctx.minion`, no defender (CombatState.gd:3086-3097) | none (listeners: Korrath talents CombatSetup.gd:167, :181, :197; riders :603-604) | latent | 086 (A3a) |
| 3 | Trap triggers | Non-rune traps match exactly, no mirroring (CombatState.gd:1041 `if not trap.is_rune and trap.trigger == trigger`). All 4 trap cards use ON_ENEMY_* triggers (CardDatabase.gd:2117, :2128, :2139, :2150), so the 3 enemy routes (CombatState.gd:1017-1019) can spring none of them | none (enemy decks hold runes only) | latent | 086 (A3b) |
| 4 | Legacy on-death board passives | CombatHandlers.gd:761-765 walks `state.player_board`; registered only on ON_PLAYER_MINION_DIED (CombatSetup.gd:576); the arms name the player (:787-793) | `void_spawner` f6_a ×2, `abyssal_tide` f3_b ×1 | **reachable** | 062 |
| 5 | Legacy on-summon board passive (`void_amplifier`) | CombatHandlers.gd:186-194, :609-615; CombatSetup.gd:549 | none | latent | 089 |
| 6 | Legacy on-sacrifice board passive (`forge_acolyte`) | CombatHandlers.gd:747-759; CombatSetup.gd:579 | none | latent | 089 (Flesh itself: 097) |
| 7 | Rune Warden | CombatHandlers.gd:681-686 walks `state.player_board`; CombatSetup.gd:586 | none | latent | 089 (the event: 093) |
| 8 | Spell-cast passive and `mana_cost_discount` (`void_archmagus`) | CombatHandlers.gd:101-107; CombatSetup.gd:547; `spell_cost` reads the discount in its player branch only (CombatState.gd:2976-2980) | none | latent | 089 |
| 9 | Hollow Sentinel, Rift Warden | CombatHandlers.gd:1401-1425 (both turn ends, CombatSetup.gd:587-588); CombatManager.gd:379-395 | `hollow_sentinel` f7_a, `rift_warden` f12_a | symmetric | 089 retires only the id |
| 10 | ON_RUNE_PLACED, environment and grand rituals | Fired with "player" only (CombatState.gd:2703-2707, :1905; RelicEffects.gd:136). `on_grand_ritual` / `on_env_ritual` read `state.active_traps` (CombatHandlers.gd:688-696). One global `_env_ritual_handlers` (CombatState.gd:373-393). ON_RITUAL_FIRED owner is "player" (:896; CombatHandlers.gd:380) | enemy runes, but no enemy environment or ritual talent | latent | 093 (removal: 050) |
| 11 | Talents, hero passives, hero id | `_has_talent` (CombatState.gd:218-219); `_card_ctx` gives the enemy `[]` (:236-237); `apply_passive(id, st)` takes no side (CombatSetup.gd:636); only `player_hero_id` (CombatState.gd:1655) | none | latent | 090 |
| 12 | `rune_aura_multiplier` is one global | CombatState.gd:396-397, :1803; EffectResolver.gd:625; HardcodedEffects.gd:241 | enemy runes in f4_b, f5_a vs a Rune Master run (Act 2) | **reachable** (leak) | 064 |
| 13 | Other talent stats and statics | `void_mark_damage_per_stack` (:1802), `forge_counter_threshold` (:1693), `_void_echo_fired_this_turn` (:1853), `_armour_doubled_on_knight` (MinionInstance.gd:236, no owner check), `_corrupting_presence_active` (CombatState.gd:1136, :1148), `_path_of_corruption_active` (:1869), the MinionInstance statics (MinionInstance.gd:14, :19; owner-guarded :140-149) | none | latent | 090 (statics with 130; Seris and Korrath state with 097 / 098) |
| 14 | Flesh, Forge | EffectResolver.gd:344, :350, :358, :399 `and ctx.owner == "player"`; `_gain_flesh(amount)` has no side (CombatState.gd:406); `fleshbind` registers on player events only (CombatSetup.gd:257-260) | none | latent | 097 |
| 15 | Void Marks | `_apply_void_mark` writes `enemy_void_marks` only (CombatState.gd:287-291); the VOID_MARK step is gated (EffectResolver.gd:146-148); the `void_marks` multiplier reads `enemy_void_marks` for any caster (:626); the enemy's Void Bolt path has no mark bonus (CombatState.gd:988-1001) | none (the enemy's `void_bolt` has no base VOID_MARK) | latent | 092 |
| 16 | CONVERT_RESOURCE | EffectResolver.gd:333-339 | `flux_siphon` f2_c | **reachable** | 063 |
| 17 | GRANT_ESSENCE | EffectResolver.gd:128-136: the enemy branch caps at `essence_max` and writes `enemy_essence` directly, with no RESOURCES_CHANGED | none (no card uses the type) | latent | 092 |
| 18 | Path of Corruption, Dark Channeling | EffectResolver.gd:697, :723 `if ctx.owner != "player"`; :740 `if ctx.owner != "enemy"` | Dark Channeling is the F13 / F15 enemy passive | latent | 092 |
| 19 | Relics | `cmd_activate_relic(index, target)` takes no side and checks `_check_can_act("player")` (CombatState.gd:2824-2828); 11 side literals in RelicEffects.gd; Bone Shield / Dark Mirror flags are single fields (CombatState.gd:1774-1775) | n/a (config) | latent | 091 |
| 20 | Spell-cast composition | Player casts run `_pre_player_spell_cast` / `_post_player_spell_cast` (CombatState.gd:523-575); `cast_enemy_spell` skips them (:1059-1076) | none | latent | 097 for the Seris hooks; merging the three cast paths has no task (step 3) |
| 21 | Player-champion auto-summon | `_check_champion_triggers()` reads `player_hand + player_deck` and `player_board` (CombatState.gd:2108-2136); `_summon_champion_card` uses player slots (:2138-2157); called only from the player summon handler (CombatHandlers.gd:192-194) | none (enemy champions come from encounter passives) | latent | 089 |
| 22 | Card-drawn event | `_fire_card_drawn` fires ON_PLAYER_CARD_DRAWN only (CombatState.gd:1597-1602); there is no enemy event | none | latent | 086 (A3c) |
| 23 | Dead or unheard events | ON_PLAYER_ENVIRONMENT_PLACED is never fired; ON_*_TRAP_PLACED fire (:2697-2700) with no production listener | n/a | clean-up | 088 |
| 24 | Trap / environment removal and owner lookup | task 050's list | Cyclone, Hurricane vs enemy runes | covered | 050 |
| 25 | Ritual Surge side literal | CombatHandlers.gd:172-173 | none | no behaviour change | 055 |
| 26 | On-play target channel | Player handler takes `ctx.target` at priority 10 (CombatHandlers.gd:951-970); the enemy's reads `state.enemy_play_target` at priority 5 (:976-996) | every enemy on-play card | equivalent today | 086 (A3c); 129 deletes `enemy_play_target` |
| 27 | Overrides and Pack Frenzy read `enemy_passives` for any side | `_card_ctx` passes `enemy_passives` for both sides (CombatState.gd:238) and CardDatabase.gd:114 matches them; HardcodedEffects.gd:278 | `pack_frenzy` (enemy-only pool) | latent | 090 |
| 28 | Hero skill | `_cmd_hero_skill` refuses `side != "player"` (CombatState.gd:2865-2866) | n/a | latent | 097 |
| 29 | One-sided cost modifiers and counters | `enemy_spell_cost_aura`, `enemy_spell_cost_discounts`, `enemy_essence_cost_discounts`, `enemy_minion_essence_cost_aura` (CombatState.gd:1723-1728); seven per-side counter pairs | enemy passives | latent | 085 |
| 30 | Side-fixed conditions | ConditionResolver.gd:53, :55, :57, :59 (`has_empty_slot("player")`, `player_board`, `active_traps`, `active_environment`); :97, :99 (`enemy_void_marks`); the five Flesh arms read `player_flesh if ctx.owner == "player" else 0` (:100-114) | none (Flesh conditions: player content only) | latent | 108 (the two Void Mark conditions: 092; `flesh_of(side)` per side: 097) |
| 31 | Draw model | `draw_cards` branches on `side == "player"` (CombatState.gd:1559-1583): the enemy deck regenerates, the player's is finite | every fight | needs per-side config | 083 |
| 32 | Side parameters that default to "player" | `owner: String = "player"` at CombatState.gd:318, :384, :482, :781, :2090 | n/a | hygiene | 087 (L16) |
| 33 | Encounter passives | handlers registered on ON_ENEMY_* with "enemy" literals | F1–F15 | enemy config by design (Q2: data decides) | literals only: 086 (A3c), 087 |
| 34 | `once_per_turn:` gate | one `_once_per_turn_used` dict for both sides (CombatState.gd:1705), cleared only at the player's turn start (:2436); consumed inside `ConditionResolver.check` (:24-33) | none (only `imp_evolution`, a player talent) | latent | 108 (085 moves the per-side flags onto SideState) |

## Decision (owner, 2026-10-01)

- Q1: "PvP / mirror matches are planned." Full symmetry is a product goal.
- Q2: no mechanic is intentionally one-sided. "Who has what is decided by data/config (e.g. the enemy's config lists no relics), never by `if owner == "player"` in rules code." Every player-only path is an engine asymmetry to fix. Reachable today vs latent only sets priority.
- Q3: accept balance shifts, one mechanic per task, and record the BalanceSimBatch delta in each task's summary.

## Proposed fix

1. **Publish the table.** In ARCHITECTURE_ROADMAP.md §A, replace the "Player-only paths reported by the review" bullets (:46-55) with the table above, re-checked at the commit you work on. Mark it "(verified <date>)" and give every row its task id.
2. **Keep it current.** Add one line under the table: the task that fixes a row marks the row done when it lands. Tighten the ARCHITECTURE.md caveat (:335) so it names only the open rows, and word it as "the tasks in 082's table" rather than "tasks 082–093": rows also go to 097, 098, 108, 129 and 130. Delete the caveat when the last row closes.
3. **Rows without a task.** Row 20's merge of `cast_player_targeted_spell`, `cast_player_hero_spell` and `cast_enemy_spell` into one `cast_spell(side, …)` has no owner. Either task 097 (roadmap B3) takes it, since it rewires the Seris hooks in those paths, or file a small task. Do the same for any row that loses its owner.
4. **Stale comments that claim a symmetry the code lacks.** Fix the one no other task owns: CombatHandlers.gd:808-811. It says "the ctx.owner check lets the handler stay symmetric", but `on_minion_died_fleshbind` (:812-817) has no such check. The rest are owned elsewhere:
   - Enums.gd:89 ("enemy traps not yet implemented"), CombatManager.gd:82-84 ("fired from CombatScene's enemy attack path"), the TriggerManager.gd header and Enums.gd:56-57 ("fire it from CombatScene, and register handlers in _setup_triggers()"): task 088.
   - CombatHandlers.gd:443-445 (riders "match every other attack-driven effect") and Enums.gd:134-136: task 086.
   - Enums.gd:97-99 ("Player places a Rune", `ctx.owner = "player"`): task 093.
   - MinionCardData.gd:100-106: task 089 deletes the fields.
   - EffectResolver.gd:334: task 063. CombatState.gd:395: task 064. EffectResolver.gd:343, :357 and CombatState.gd:1059-1060: task 097.
5. **Guard probe** (after task 047): see Verification. Each fix task deletes its line from the probe's exception list in the same commit.

## Verification

- New probe `_enemy_content_avoids_player_only_paths` in `debug/tests/ScenarioTests.gd`, next to task 047's content test:
  - Setup: every deck id in the res:// encounter file, their SUMMON `card_id` closure (walk every `*_steps` array on each card, plus `talent_overrides` steps), `void_demon`, `void_spark`, `void_touched_imp`, every `champion_*` card and every card tagged `feral_imp`. A test may walk properties by name; this one is not rules code.
  - Assert, for each card:
    - no non-empty `on_turn_start_effect_steps`, no `on_spell_cast_passive_effect_id`, no `mana_cost_discount` (rows 1, 8);
    - no `passive_effect_id` outside `{"hollow_sentinel_spark_buff", "rift_warden_siphon"}` (rows 4–7);
    - not a non-rune `TrapCardData`, not an `EnvironmentCardData` (rows 3, 10);
    - no step of type VOID_MARK, CONVERT_RESOURCE, GAIN_FLESH, SPEND_FLESH, SPEND_FLESH_UP_TO, GAIN_FORGE_COUNTER, GRANT_ESSENCE or GRANT_ATTACK_RIDER, and no `multiplier_key` `"void_marks"` (rows 2, 14–17).
  - Known exceptions, each tagged with its task: `void_spawner`, `abyssal_tide` (062), `flux_siphon` (063). Confirm the probe fails on today's content without them and passes with them.
- `tools/run_checks.sh` green.
- Behaviour-neutral (docs, comments, one test): the seeded balance fingerprint (`BalanceSimBatch -- --act 1 --runs 200 --seed 7` and `-- --act 2 --runs 200 --seed 7`, before and after) diffs empty (design/TESTING.md "Refactor / extraction work").
- Roadmap §A has a verdict and a task for every row; §13 gets a grooming-log row.

## Related

- Depends on: task 047 — the guard probe reads the res:// encounter file that task creates. The table, the roadmap edit and the comment fix can land before it.
- Related: tasks 062, 063, 064 — the three reachable rows.
- Related: task 083 (roadmap A1), task 084 (roadmap A2), task 085 (roadmap A6), task 086 (roadmap A3), task 087 (roadmap A4), task 088 (roadmap A5), task 089 (roadmap A8), task 090 (roadmap PS-talents), task 091 (roadmap PS-relics), task 092 (roadmap PS-void-marks), task 093 (roadmap PS-rituals) — the workstream-A row owners.
- Related: task 097 (roadmap B3), task 098 (roadmap B4), task 108 (roadmap D7), task 129 (roadmap I1), task 130 (roadmap I2) — owners of rows 13, 14, 20, 26, 28, 30 and 34 outside workstream A.
- Related: task 050 (row 24), task 055 (row 25).

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item A0. Table pre-filled from the A-paths and A-core unit reports and re-checked at `404b51c`; the ARCHITECTURE.md caveat was already written by the grooming pass.

## Summary

_(filled in at /task-done)_
