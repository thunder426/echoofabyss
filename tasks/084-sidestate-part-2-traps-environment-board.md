---
id: "084"
title: SideState part 2: traps, environment, board, slots and hero; per-copy TrapInstance
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item A2 (`design/refactors/ARCHITECTURE_ROADMAP.md` §A), plus the trap half of item I6 (`TargetRef`, `TrapInstance per placed copy`, §I direction 6), which grooming moved here. Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Task 083 puts hand, deck, graveyard and resources on a per-side `SideState`. This task moves the rest of the board state there, and gives every placed trap or rune its own identity.

### Part 1: the remaining field pairs

- Traps and environment: `active_traps` / `enemy_active_traps`, `active_environment` / `enemy_active_environment` (CombatState.gd:1609-1616). The unprefixed names are the player's, so player-only code looks neutral.
- Boards and slots: `player_board` / `enemy_board` (:1296-1297), `player_slots` / `enemy_slots` (:1302-1303, allocated in `_alloc_slots`, :1311-1320).
- Heroes: `player_hero` / `enemy_hero` (:1237-1238), with the `player_hp` / `enemy_hp` / `*_hp_max` forwarders (:1240-1266).

There is no public per-side accessor for board, slots or hero:
- The board is reached through underscore helpers: `_friendly_board` (33 calls), `_opponent_board` (21), `_friendly_slots` (12; returns an untyped `Array`, :170-171). They are called from 11 files besides CombatState.
- The hero is picked by a ternary copied into five places: CombatState.gd:298 and :310 (`var hero: HeroState = player_hero if side == "player" else enemy_hero`), CombatManager.gd:204, EffectResolver.gd:658, CombatUI.gd:67.
- TargetResolver.gd:62: `var slots: Array = ctx.state.player_slots if src.owner == "player" else ctx.state.enemy_slots`.
- `has_empty_slot` (:175), `slot_of` (:1328) and `digest_text` (:2254, :2266) carry their own ternaries.

Raw references to these 14 fields (comments stripped): CombatState 141; other rules code 112 (CombatHandlers 74, PhaseTransition 10, EffectResolver 9, CombatManager 6, TargetResolver 6, RelicEffects 4, ConditionResolver 3); presentation, sim and AI about 75; debug and tests about 350.

Only the environment fields are ever assigned whole (CombatState.gd:1427/:1429, PhaseTransition.gd:90-91, EffectResolver.gd:413/:615, CommandTests.gd:392). Task 050 routes the non-test writes through `set_environment` / `destroy_environment`. No code reassigns a board, slot, trap array or hero.

### Part 2: traps have no per-copy identity

A placed trap is the shared `TrapCardData` resource itself. `cmd_play_trap` appends `inst.card_data as TrapCardData` (CombatState.gd:2684, :2692). `CardDatabase.get_card_for_combat` returns the base object when no override applies (CardDatabase.gd:125-126), and a cached clone per (id, side, overrides) when one does. So two Dominion Runes on one side are the same object, and so are a player's and an enemy's copy without overrides. Code that needs a specific copy can't name it:
- **Owner lookup by identity.** The trap DESTROY branch (EffectResolver.gd:606-608) tests `if not target in ctx.state.traps_of(owner_side)` to find the side. `_encode_target` does the same (CombatState.gd:3131-3135: `var p_idx: int = active_traps.find(target)`), and so does its environment branch (:3137, `target == active_environment`). Task 050 fixes the reachable case (Cyclone on the enemy's rune while holding the same rune) by making chosen trap and environment targets carry their side.
- **Removal by value.** `traps.erase(trap)` removes the first equal element, not the chosen copy. With two copies of one rune on a side, the wrong slot is removed and the order of the remaining traps changes (digest_text prints that order, :2273-2279). Sites: `_korrath_place_random_rune` picks a victim with `rng_pick(runes)` and then `active_traps.erase(victim)` (:1895-1897); the Flesh Rune upkeep failure (`ctx.source_rune`, EffectResolver.gd:419-423); trap DESTROY (:611).
- **Rune aura bookkeeping by id.** `_rune_aura_handlers` entries are matched on `(rune_id, owner)` and the first match is removed (CombatState.gd:332-338). Harmless today because the handlers of two same-id copies are equivalent, but nothing ties an entry to its copy.
- **Targets are Variant.** A command or effect target is a `MinionInstance`, the String `"enemy_hero"` / `"player_hero"`, a `TrapCardData` or an `EnvironmentCardData`. `EffectContext.chosen_object` is untyped (EffectContext.gd:22-24). `_encode_target` (:3123-3138) and `CombatSim.decode_target` (CombatSim.gd:150-168) translate to and from a `{kind, side, slot}` dictionary by hand.

Trap placement is copied in four places: `cmd_play_trap` (:2692), Oblivion Seal (RelicEffects.gd:129), Korrath (CombatState.gd:1902) and Voidshaped Acolyte's PLACE_RUNE_ON_OPPONENT (EffectResolver.gd:310). Task 050 lists the first three for its optional `place_trap`. Debug seeding in CombatScene.gd:1063/:1071 (TestConfig) and about 50 test sites append to the arrays directly.

### Consequence

Per-side board and hero logic keeps being written as `if owner == "player"` ternaries, the pattern behind task 050's one-sided bugs. The hero modules (tasks 097, 098) have no per-side home for hero state. Any rule that must act on one specific trap copy (removal, upkeep, per-copy counters) has to fall back on value equality.

## Proposed fix

Two commits, each with its own gate run. Land after task 083 (SideState exists) and task 050 (`remove_trap` / `destroy_environment` / `place_trap` and lint L13). Part 2 touches about 25 files plus about 50 test seeding sites; if it grows, split it into its own sub-task when starting.

### Part 1: SideState gets traps, environment, board, slots, hero

1. Add to SideState: `traps`, `environment: EnvironmentCardData`, `board: Array[MinionInstance]`, `slots: Array[SlotState]`, `hero: HeroState`. `_alloc_slots` fills `side(s).slots`.
2. Legacy names become forwarders, as in task 083: getter-only properties for the arrays and heroes; a get/set property for the two environment names until task 050's routing leaves only `set_environment` writing them (CommandTests.gd:392 seeds one directly). Re-point `player_hp` / `enemy_hp` / `*_hp_max` (:1240-1266) at `side(s).hero`.
3. Public typed accessors: `board_of(side) -> Array[MinionInstance]`, `slots_of(side) -> Array[SlotState]`, `hero_of(side) -> HeroState`. `_friendly_board` / `_opponent_board` / `_friendly_slots` stay as one-line forwarders (task 099, roadmap B7, decides later whether to rename them).
4. Replace the five hero ternaries, the TargetResolver slot ternary, `has_empty_slot`, `slot_of` and the `digest_text` loops with the accessors. Collapse the remaining `X if side == "player" else Y` ternaries on these fields inside CombatState.
5. Task 050's `remove_trap` / `destroy_environment` / `place_trap` read and write `side(s).traps` / `side(s).environment`. Lint L13 keeps naming the legacy fields while they exist, plus the SideState names.
6. Leave champion and encounter-passive handlers' `state.enemy_board` reads alone. Task 096 (roadmap B2) rewrites champions, and task 086 (roadmap A3) binds registry entries to an owner.

### Part 2: TrapInstance and TargetRef

7. **`TrapInstance`** (RefCounted, no back-reference to the state): `card: TrapCardData`, `side: String`, `uid: int` (a per-state counter). `SideState.traps` becomes `Array[TrapInstance]`. `traps_of(side)` returns the live instances. Add `trap_cards_of(side) -> Array[TrapCardData]` for readers that only need card data.
8. **One placement path.** Every placement goes through `place_trap(side, card) -> TrapInstance` (add it if task 050 left it optional): `cmd_play_trap`, Oblivion Seal, Korrath and PLACE_RUNE_ON_OPPONENT. The TestConfig seeding and the tests use it too (or a `TestHarness.place_trap` helper).
9. **Removal by identity.** `remove_trap(ti: TrapInstance)` reads the side from the instance and uses `remove_at(traps.find(ti))`. Korrath's victim, the Flesh Rune upkeep failure and trap DESTROY remove the exact copy. `ctx.source_rune` becomes the TrapInstance, and `_rune_aura_handlers` entries key on the instance, not on `(rune_id, owner)`.
10. **Journal payloads keep card data.** TRAP_PLACED / RUNE_PLACED / TRAPS_CHANGED / TRAP_FIRED keep carrying `TrapCardData` (`ti.card`, and `trap_cards_of(side)` for the `traps` snapshot that task 070 adds), so presentation needs no change. Add the `uid` to the payload only if a presenter needs it.
11. **`TargetRef`** (RefCounted): `kind` (MINION / HERO / TRAP / ENV), `side`, `slot`, with `static func of(state, target) -> TargetRef`, `resolve(state) -> Variant`, `to_dict()` and `from_dict()`. `_encode_target` and `CombatSim.decode_target` delegate to it. The dictionary shape stays `{kind, side, slot}`, so `command_log` and the replay JSON are unchanged. A trap target is the TrapInstance, so its side and slot are exact. An environment target carries the side that task 050 adds. `EffectContext.chosen_object` becomes typed (a `TargetRef`, or a typed TrapInstance / environment-side pair) instead of Variant. Minion and hero targets keep their current types at the command surface; they are already unambiguous, and changing every command signature is not needed for correctness.
12. **Readers.** Engine readers of trap arrays move to `.card` or `trap_cards_of`: ConditionResolver, TargetResolver, HardcodedEffects (Soul Rune count, :229), CombatHandlers rituals, PhaseTransition. AI profiles, StateAgent, TrapEnvDisplay, CombatVFXBridge and ViewState read `trap_cards_of(side)` or the journal payload. If task 122 (roadmap G7) has landed, change only the CombatAgent API.
13. **Docs.** ARCHITECTURE.md engine paragraph: `board_of`, `slots_of`, `hero_of`, `TrapInstance`, `TargetRef`.

## Verification

- New probe in debug/tests/CommandTests.gd, "side model / board, slots and hero via SideState":
  - Setup: `build_state({})`, spawn one minion on each side.
  - Assert `is_same(state.board_of("enemy"), state.enemy_board)`, `state.slots_of("player")[0] == state.slot_of("player", 0)`, `state.hero_of("enemy") == state.enemy_hero`.
  - `state.add_hero_armour("enemy", 50)` → `state.side("enemy").hero.armour == 50`.
- New probe in CommandTests.gd, "traps / removal hits the chosen copy":
  - Setup: place `dominion_rune`, `blood_rune`, `dominion_rune` on the player side.
  - Remove the third trap by instance: the remaining order is `[dominion, blood]`, and the removed instance's aura entry is the one unregistered (count `_rune_aura_handlers` entries per uid).
- New probe in CardEffectTests.gd, "cyclone / same rune on both sides": the player and the enemy each hold a `dominion_rune` (the same `TrapCardData` object). The player's DESTROY on the enemy's TrapInstance removes the enemy's copy and strips the enemy board's Dominion buff, and the player's copy and buffs stay.
- New probe in CommandTests.gd, "target ref / round-trip": for a minion, a hero, a trap and an environment target, `TargetRef.from_dict(TargetRef.of(st, t).to_dict()).resolve(st)` returns the same target, and the dict equals what `_encode_target` produced before this task.
- Task 050's trap and environment probes (enemy-owned rune Cyclone, Hurricane on both sides, Flesh Rune upkeep, F15 phase clear) pass unchanged through SideState.
- `tools/run_checks.sh` green after each part. Parity replays `command_log` through `decode_target`, so it covers the TargetRef boundary.
- Part 1 is behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` through `--act 4`) diffs empty (design/TESTING.md "Refactor / extraction work"). Time the `--act 1` run; if the board forwarders make the sim more than ~3% slower, alias the arrays instead of forwarding.
- Part 2 is expected neutral too, with one known exception: removal by identity changes the trap order when a non-first copy of a duplicated trap is removed (Korrath's runic_absorption victim with two copies of one rune, a second Flesh Rune failing its upkeep). Run the same fingerprint for Acts 1–4. If it moves, check that every moved row involves such a case and record the delta in the task summary (Q3).

## Related

- Depends on: task 083 — SideState and `side(s)` exist.
- Depends on: task 050 — `remove_trap` / `destroy_environment` / `place_trap`, lint L13, and trap and environment targets that carry their side. This task builds on that API instead of re-scoping it.
- Related: task 085 (roadmap A6): SideState part 3, per-turn counters and cost modifiers.
- Related: task 070 (roadmap E1a): adds the `traps` snapshot to placement payloads. With TrapInstance the snapshot is built from `trap_cards_of(side)`, so its element type stays `TrapCardData`.
- Related: task 093 (roadmap PS-rituals): depends on this task; per-side ritual handler storage goes on SideState.
- Related: task 134 (roadmap I6): the rest of I6 (DamageInfo, CostPlan, typed buff containers). TargetRef and TrapInstance moved here from it.
- Related: task 122 (roadmap G7): the AI reads traps through CombatAgent once it lands.
- Related: task 099 (roadmap B7): public engine API; may rename the `_friendly_board` family after this task.
- Related: tasks 097 / 098 (roadmap B3 / B4): hero modules hang per-side hero state on `SideState.hero`.
- Related: task 133 (roadmap I5): extends `digest_text` on purpose. Step 4 rewrites its loops; whichever lands second keeps the other's output identical.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item A2, merged with I6's TargetRef / TrapInstance half. Found a fourth trap-placement site (PLACE_RUNE_ON_OPPONENT, EffectResolver.gd:310) that task 050's `place_trap` list misses, and that removal by identity can reorder duplicated traps.

## Summary

_(filled in at /task-done)_
