---
id: "090"
title: Per-side talents and hero passives (+ an enemy hero id)
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap §A, owner decision Q2 ("talents & hero passives"; the A-paths unit's "A6b"). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Talents and hero passives exist only for the player. The enemy cannot have a hero, a talent or a hero passive, and a talent given to it would write player state.

### Storage and lookup

- One list each: CombatState.gd:1647 `var talents: Array[String] = []`, :1651 `var hero_passives`, :1655 `var player_hero_id: String = "lord_vael"`. There is no enemy hero id. `setup_combat` fills them from the config (:2334-2337).
- `_has_talent(id)` reads that list (:218-219). Its callers: CombatState.gd:470, :495, :677, :722, :739, :743, :757, :1082, :1114, :1194, :1198 (all Seris); Targeting.gd:202-216 and CombatScene.gd:1307 (player UI); CombatHandlers.gd:958 (`piercing_void`); FleshcraftPlayerProfile.gd:189 and SerisPlayerProfile.gd:82, :107, :125 (sim bots).
- `_card_ctx` gives the enemy no talents and gives both sides the enemy's encounter passives (CombatState.gd:233-239):
  ```gdscript
  "talents":        talents if side == "player" else [],
  "hero_passives":  hero_passives if side == "player" else [],
  "enemy_passives": enemy_passives,
  ```
  CardDatabase.gd:114 then activates a `talent_overrides` entry if its id is in any of the three lists, whatever the side. CardModRules `_condition_active` gates `talent` and `hero_passive` rules on `side == "player"` and `enemy_passive` rules on `side == "enemy"` (CardModRules.gd:222-233).
- HardcodedEffects.gd:278 (`_pack_frenzy`) reads `state.enemy_passives` for any caster.
- CombatConfig has `player_hero_id`, `talents`, `hero_passives` and no enemy equivalents (CombatConfig.gd:23-25). The replay dict has the same keys (:80-82).

### Registration

- CombatSetup.setup applies `for id in talents` and `for id in hero_passives` with `apply_passive(id, st)` (CombatSetup.gd:613-614). `apply_passive` (:636-645) takes no side:
  - it registers each entry's absolute events, written from the player's point of view: `fleshbind` on ON_PLAYER_MINION_DIED / SACRIFICED for friendly deaths (:257-260), `shattering_doom` on ON_ENEMY_MINION_DIED for the opponent's deaths (:187), `grand_ritual_chaos` on the unsided ON_RUNE_PLACED (:222);
  - it writes `stats` onto CombatState fields with `st.set(stat, value)`.
- The talent stats are single fields: `void_mark_damage_per_stack` (:1802, `deepened_curse`), `rune_aura_multiplier` (:1803, `runic_attunement`; task 064 splits it into a per-side pair), `forge_counter_threshold` (:1693, `forge_momentum`), `_void_echo_fired_this_turn` (:1853, `void_echo`), `_armour_doubled_on_knight` (:1857, `unbreakable`), `_corrupting_presence_active` (:1863), `_path_of_corruption_active` (:1869).
- Two talents set process-wide statics: CombatSetup.gd:609-610 (`corrupt_flesh`, `iron_resolve`). MinionInstance guards them with `owner == "player"` (MinionInstance.gd:140-149). `_armour_doubled_on_knight` has no owner check (MinionInstance.gd:236).
- The grand-ritual loop registers lambdas for the player's talents only (CombatSetup.gd:625-632).
- The PhaseTransition passive swap calls `apply_passive` / `unapply_passive` for enemy passives (PhaseTransition.gd:106-108).

### Reachable today

No enemy has a hero, talents or hero passives, so nothing is reachable through this path. The one leak in the other direction, Runic Attunement doubling enemy runes, is task 064. The `enemy_passives` override match is latent too: the only override keyed by an enemy passive is `pack_frenzy`'s `ancient_frenzy`, and `pack_frenzy` is in the enemy-only `feral_imp_clan` pool (CardDatabase.gd:3574).

## Decision (owner, 2026-10-01)

- Q2: "Relics, talents & hero passives, hero resources (Flesh, Forge, Void Marks) and rituals must all work for either side in the engine." Who has what is decided by data and config, never by `if owner == "player"` in rules code.
- Q1: PvP and mirror matches are planned.
- Q3: record the BalanceSimBatch delta. The enemy gets no talents in this task, so expect none.

## Proposed fix

1. **Per-side storage** on task 083's `SideState`: `hero_id` (enemy default `""` = no hero), `talents`, `hero_passives`, and one field per talent / hero-passive registry stat (`void_mark_damage_per_stack`, `rune_aura_multiplier` from task 064's pair, `forge_counter_threshold`, `void_echo_fired_this_turn`, `armour_doubled_on_knight`, `corrupting_presence_active`, `path_of_corruption_active`). Keep `talents`, `hero_passives`, `player_hero_id` and the old stat names as forwarders to the player's SideState while callers migrate, as task 083 does for hands and decks.
   - Overlap: `forge_counter_threshold` is also in task 097's (roadmap B3) list, and `armour_doubled_on_knight`, `corrupting_presence_active` and `path_of_corruption_active` in task 098's (roadmap B4). Whichever task lands first makes them per side; the other skips them.
2. **API.** `has_talent(side, id)`, `hero_id_of(side)`. Migrate the non-Seris `_has_talent` callers to pass their side (UI: "player"; sim bots: `agent.side`; CombatHandlers.gd:958: the played minion's owner). Leave the Seris callers in CombatState to task 097 (roadmap B3), which moves them into a per-side module; until then they go through the player forwarder.
3. **Config.** CombatConfig gains `enemy_hero_id`, `enemy_talents` and `enemy_hero_passives`, all empty by default. `from_game_manager` leaves them empty. The replay dict reads them with defaults, so old replays still load.
4. **Card overrides.** `_card_ctx(side)` returns that side's talents and hero passives, and the encounter passives only for the side that has them (the enemy). Drop the side checks in CardModRules `_condition_active` (:222-233): the lists are already per side. Fix its comments ("Player-side only — enemies have no talents today", :223, and the header at :25-27). `_pack_frenzy` reads the caster side's encounter passives. The engine's other `side == "enemy"`-gated encounter-passive reads do the same, so each is one rule for both sides: `spark_cost_of` (CombatState.gd:2994-3001: `ritualist_spark_free`, `captain_orders`, `void_mastery`) and `plan_cost`'s `mana_for_spark` (:3028, :3035; task 118, roadmap G2, extracts it as `spark_shortfall_mana(side, …)`).
5. **`apply_passive(id, st, side)`.** Task 086 phase 3 also moves registry entries to (kind, whose) bound to an owner, and adds this side argument if this task hasn't landed. Whichever lands second reuses the other's signature; once phase 3 is in, the mirroring below is its (kind, whose) binding and `Enums.mirror_trigger` is gone.
   - Each registry entry is authored for one side: talents and hero passives for "player", encounter passives for "enemy" (a field on the entry, or the section it sits in).
   - When `side` differs from the authored side, register the mirrored event, using the per-registration side filter task 086 (roadmap A3) adds in its P1 shim. Unsided events (ON_RUNE_PLACED, ON_RITUAL_FIRED, ON_RITUAL_ENVIRONMENT_PLAYED, ON_FORMATION_TRIGGERED, ON_CORRUPTION_REMOVED) get a side filter equal to `side`, so the same handler registered for both sides fires once per owner.
   - Attack events need task 086's A3a (enemy ATTACK_PRE / POST): `Enums.mirror_trigger` maps both player phases to the one pre-damage ON_ENEMY_ATTACK (Enums.gd:134-139).
   - Talent and hero-passive `stats` are written to `st.side(side)`; keep the `assert(stat in …)` check, against SideState. Encounter-passive stats (champion counters, Dark Channeling) stay CombatState fields: champion state is task 095's (roadmap B2a), and task 092 tags Dark Channeling with its caster side.
   - `unapply_passive` takes the same side. PhaseTransition passes "enemy".
6. **Setup.** CombatSetup.setup applies both sides' talents and hero passives with their side, and the encounter passives with "enemy". The grand-ritual loop (:625-632) iterates both sides' talents and passes the side to the registration; the handler's side filter and per-side rune reads are task 093's (roadmap PS-rituals).
7. **Handlers read the owner, not "player".**
   - Vael talents and hero passives: `void_echo` (CombatHandlers.gd:122-142 and its flag), `swarm_discipline`, `ritual_surge` (task 055 already switches it to `ctx.owner`), `void_imp_boost` (the hero name comes from `hero_id_of(ctx.owner)`; task 055 removes the GameManager read).
   - Readers of the moved stats: MinionInstance.add_armour uses `state.side(owner)`; `_corrupt_minion` / `_corrupt_hero` (CombatState.gd:1136, :1148) use the attacker side, `opponent(target side)`, instead of `== "enemy"`.
   - The Path of Corruption gates and the Void Mark per-stack damage are rewired by task 092 (roadmap PS-void-marks) on top of this storage.
8. **Seris and Korrath.** Their handler bodies touch Flesh, Forge and rune state that is still player-only. Tasks 097 (roadmap B3) and 098 (roadmap B4) move them into per-side modules. Until those land, keep a declared list of those ids (e.g. `CombatSetup.PLAYER_SIDE_ONLY_UNTIL_MODULES`, with a query `side_supported(id, side)`); `apply_passive(id, st, "enemy")` on one of them calls `push_error` and registers nothing, instead of silently writing player state. Tasks 097 / 098 empty the list.
9. **Statics.** `corruption_inverts_on_friendly_demons` and `iron_resolve_active` become per state in task 130 (roadmap I2). After both tasks, MinionInstance reads `state.side(owner)`'s flag and drops the `owner == "player"` guards (MinionInstance.gd:140-149). If this task lands first, leave the two statics to task 130 and say so in the summary.
10. **Docs.** Update ARCHITECTURE.md (CombatSetup row, the registry shape in CombatSetup.gd:11-15) and the stale comments at CombatState.gd:215-217, :1644-1654 if task 055 hasn't.

## Verification

- New probes in `debug/tests/TriggerHandlerTests.gd`. `TestHarness.build_state` gains `enemy_talents`, `enemy_hero_passives` and `enemy_hero_id` options.
  - Enemy talent stat: `build_state({"enemy_talents": ["deepened_curse"]})`: `side("enemy").void_mark_damage_per_stack == 40` and the player's is 25.
  - Enemy event talent: `build_state({"enemy_talents": ["void_echo"]})` (after task 086 fires card-drawn for the enemy). An enemy draw of `void_imp` adds one copy to `hand_of("enemy")`; the player's hand is unchanged.
  - Same talent on both sides: `build_state({"talents": ["swarm_discipline"], "enemy_talents": ["swarm_discipline"]})`. A player Void Imp summon logs one Swarm Discipline line, owner "player"; an enemy one logs one line, owner "enemy".
  - Overrides: `st._card_for("enemy", "void_imp")` with `enemy_talents: ["piercing_void"]` has the override's on-play steps; `st._card_for("player", "void_imp")` in the same state does not.
  - Guard: `CombatSetup.side_supported("fleshbind", "enemy") == false` and `side_supported("deepened_curse", "enemy") == true` (until task 097). Query the list rather than calling `apply_passive`, so the probe raises no push_error in the gate run.
  - Update the existing stat probes (`_runic_attunement_stat`, deepened_curse at TriggerHandlerTests.gd:828-838) to read `side("player")`.
- `debug/tests/snapshots/handler_order.txt` unchanged: the player's registrations keep their events, priorities and order.
- BalanceSimBatch has no Korrath preset and Parity's F6 Korrath case runs only `iron_formation` / `commanders_reach`, so the fingerprint says nothing about the Korrath paths this task touches (the Korrath talent registrations and the moved Korrath flags). Compare seeded `CombatSim.run` digests for them as task 098's verification describes.
- `tools/run_checks.sh` green.
- Behaviour-neutral: no config gives the enemy a hero, talent or hero passive. The seeded balance fingerprint (`BalanceSimBatch -- --act N --runs 200 --seed 7`, before and after, for N = 1, 2, 3, 4; request 3 and 4 explicitly) diffs empty (design/TESTING.md "Refactor / extraction work"). Any diff is a regression, most likely an override or stat now landing on the wrong side.

## Related

- Depends on: task 083 (roadmap A1) — `SideState` is where the per-side lists and stats live.
- Depends on: task 086 (roadmap A3) — its P1 shim's per-registration side filter, and its A3a enemy ATTACK_PRE / POST. Without them an enemy-owned talent on an unsided or attack event can't be told apart from the player's. (Added by the writer of this task; the plan listed only 083.)
- Related: task 064 — makes `rune_aura_multiplier` a per-side pair; this task folds the pair into SideState and lets the talent write its owner's value.
- Related: task 097 (roadmap B3), task 098 (roadmap B4) — Seris and Korrath handlers and state per side; their modules receive their side's talents from this task.
- Related: task 130 (roadmap I2) — the two MinionInstance statics.
- Related: task 095 (roadmap B2a) — owns the champion state that encounter-passive `stats` write; this task leaves it on CombatState.
- Related: task 092 (roadmap PS-void-marks) and task 093 (roadmap PS-rituals) — depend on this task's per-side talent stats and registration.
- Related: task 055 — fixes the `void_imp_boost` GameManager read and the Ritual Surge literal; task 103 (roadmap C5) — combat UI reads hero / talent info from the fight, which now has a per-side hero id. If 103 has landed, switch its `CombatScene.empty_slot_bg("enemy")` to the enemy hero's faction here.
- Related: task 082 (roadmap A0) — rows 11, 13 and 27 of its table point here.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from owner decision Q2 (the A-paths unit's A6b). Added the dependency on task 086 (side-filtered registration and enemy attack phases), which the plan did not list.

## Summary

_(filled in at /task-done)_
