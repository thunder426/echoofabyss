---
id: "098"
title: Extract Korrath talent state into a per-side KorrathModule
status: backlog
area: combat
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item B4 (`design/refactors/ARCHITECTURE_ROADMAP.md` §B). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

The roadmap says Korrath has 6 fields and 5 functions on the engine. The count is smaller: 3 vars and 2 consts, plus 3 Korrath-only functions and a hook inside the generic rune-removal path. Armour itself lives on `HeroState` and `MinionInstance`.

### What sits on CombatState

- **Three talent flags, set by registry `stats` strings** (`st.set(...)` in `CombatSetup.apply_passive`, :645):
  - `_armour_doubled_on_knight` (:1857), from `unbreakable` (CombatSetup.gd:153);
  - `_corrupting_presence_active` (:1863), from `corrupting_presence` (:162);
  - `_path_of_corruption_active` (:1869), from `path_of_corruption` (:174).
- **Two consts:** `KORRATH_RUNE_IDS` (:1873) and `KORRATH_RUNE_BOARD_CAP` (:1880).
- **Three Runic Knight functions:** `_korrath_place_random_rune` (:1888), `_korrath_grant_absorbed_aura` (:1914), `_korrath_absorbed_aura_count` (:1924).
- **A Korrath hook in generic code**, `_remove_rune_aura` (:319-327):
  ```gdscript
  if owner == "player" and rune != null and rune.is_rune \
  		and "runic_absorption" in talents:
  	_korrath_grant_absorbed_aura(rune.id)
  ```

`add_hero_armour` (:295) and `apply_hero_buff` (:308) are not Korrath-specific: the generic ADD_HERO_ARMOUR step uses them. They stay.

### Readers

- `MinionInstance.add_armour` (MinionInstance.gd:235-238): `if amount > 0 and state != null and state._armour_doubled_on_knight and card_data != null and card_data.id == "abyssal_knight": amount *= 2`.
- `_corrupt_minion` (CombatState.gd:1136) and `_corrupt_hero` (:1148): `if _corrupting_presence_active and target.owner == "enemy"` / `side == "enemy"`.
- Path of Corruption: EffectResolver.gd:697-699 and :723-725 (`if ctx.owner != "player": return`, then the flag), and the Void Bolt ruination check at CombatState.gd:962. The review missed the last one.
- CombatHandlers: Runeforge Strike calls `state._korrath_place_random_rune()` (:256); `_korrath_x_count` (:303-308) counts runes in `state.active_traps` (the player's) plus `state._korrath_absorbed_aura_count()`.
- Tests: TriggerHandlerTests.gd:1694-1695 (flags set by talents), :2834, :2869, :2911, :3001, :3017 (rune placement and absorption).

### Player-only by construction

Every one of these assumes Korrath is the player: the rune functions read `active_traps`, `player_board` and `talents`, fire ON_RUNE_PLACED as `"player"` (:1904-1907), and the flags are single engine fields.

One of them would leak today if an enemy fielded the card. `add_armour` has no owner check, so with the player's Unbreakable an **enemy** `abyssal_knight` would also gain double Armour. No encounter deck has `abyssal_knight`, so this is latent.

`_korrath_place_random_rune` also writes `active_traps` directly (:1897, :1902) and looks the rune up with `CardDatabase.get_card(rune_id)` (:1899). Task 050 routes the first through its trap API; task 058 routes the second through `_card_for`.

## Decision (owner, 2026-10-01)

**Q2:** talents and hero passives "must all work for either side in the engine. … Who has what is decided by data and config, never by `if owner == "player"` in rules code."

Scope (task 056 grooming ruling): Armour, Armour Break and Formation are generic engine keywords that any card can use. They stay in the engine; only Korrath's talent state moves.

## Proposed fix

1. **`KorrathModule`** (a `CombatModule` from task 097), created by `setup_combat` for each side whose hero is `korrath`, with that side's talent list. It owns:
   - the three flags, set from its talents in `setup` (delete the three registry `stats` blocks at CombatSetup.gd:153, :162, :174);
   - the rune id list and board cap;
   - `place_random_rune()`, `grant_absorbed_aura(rune_id)`, `absorbed_aura_count()`, for its own side;
   - Grand Ritual: Chaos (CombatHandlers.gd:318-381) and `_korrath_x_count`, once task 093 has made their rune and board reads per side (093 hands the handler to this task).

   If task 090 has landed, remove the Korrath ids from its `PLAYER_SIDE_ONLY_UNTIL_MODULES` guard list (`side_supported`).
2. **Rune removal notifies the owner's module.** `_remove_rune_aura(rune, owner)` calls `hero_module(owner).on_rune_removed(rune)` instead of the inline `owner == "player"` and talent check.
3. **Readers ask the module of the side the talent belongs to:**
   - `MinionInstance.add_armour`: the module of the minion's `owner`. This also closes the latent leak above.
   - `_corrupt_minion` / `_corrupt_hero`: Corrupting Presence belongs to the corrupted side's opponent, so ask `hero_module(_opponent_of(target.owner))`. For a player Korrath this is exactly today's `target.owner == "enemy"`.
   - Path of Corruption (EffectResolver.gd:697-725, CombatState.gd:962): the module of the caster (`ctx.owner`). The `ctx.owner != "player"` gates themselves are task 092's; with the module lookup they become redundant, and whichever task lands second deletes them.
   - Runeforge Strike (CombatHandlers.gd:256): `hero_module(attacker.owner).place_random_rune()`.
   - `_korrath_x_count` (:303-308): the module counts runes in `traps_of(side)` plus its own knights' absorbed auras.
4. **`place_random_rune` uses the shared APIs:** task 050's `place_trap` / `remove_trap` (no direct `active_traps` writes; lint L13) and task 058's `_card_for(side, rune_id)`. It fires ON_RUNE_PLACED for its own side once task 093 makes that event per side; until then it fires the player event, as today.
5. **Statics:** `MinionInstance.iron_resolve_active` (set at CombatSetup.gd:610) becomes per-state in task 130 (roadmap I2). Whichever of 130 and this task lands second moves it into the module.
6. **Stale comments:** EffectStep.gd:18 and CardDatabase.gd:427 say `scene._armour_doubled_on_knight`; CombatSetup.gd:150 and :158 call the flags "the scene flag". Point them at the module.

## Verification

- The existing Korrath probes pass with their accessors updated: TriggerHandlerTests.gd:1694-1695, :2834, :2869, :2911, :3001, :3017.
- New probe in `debug/tests/TriggerHandlerTests.gd`, `_unbreakable_is_per_side`:
  - A Korrath player with `unbreakable`; spawn a player and an enemy `abyssal_knight`.
  - `add_armour(100, state)` gives the player's knight 200 and the enemy's 100 (today the enemy's gets 200).
- New probe, `_runic_absorption_per_side`: attach an enemy KorrathModule with `runic_absorption` (until task 090 adds an enemy hero id). Removing an enemy rune grants the absorbed aura to an enemy `abyssal_knight`; the player's knights are unchanged.
- Grep gate: `grep -cE '_korrath_|_armour_doubled_on_knight|_corrupting_presence_active|_path_of_corruption_active|KORRATH_RUNE' combat/board/CombatState.gd` → 0.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4: `_remove_rune_aura`, `_corrupt_minion` and `add_armour` run for every hero) diffs empty (design/TESTING.md 'Refactor / extraction work').
- BalanceSimBatch has no Korrath preset, and Parity's F6 Korrath case uses only `iron_formation` / `commanders_reach`, so neither exercises the moved state. Add a Korrath digest check: before the first edit, record `CombatSim.run(...)["digest"]` for seeds 1-50 with each branch's full talent list (`iron_vanguard` on `korrath_iron_legion`, `abyssal_breaker` on `korrath_abyssal_vanguard`, `runic_knight` T0-T3 on either deck), as ScenarioTests' Korrath cases (:838-870) do but seeded. After the change the digests are identical.

## Related

- Depends on: task 097 (roadmap B3) — introduces `CombatModule` and `hero_module(side)`, which this task reuses.
- Depends on: task 050 — routes `_korrath_place_random_rune`'s trap erase / append through `remove_trap` / `place_trap`, which the module then calls.
- Related: task 058 — fixes the `_card_for` bypass in `_korrath_place_random_rune`; keep its fix when the function moves.
- Related: task 090 (per-side talents, owner Q2) — per-side talents and an enemy hero id. Its A6b scope lists the same three flags; whichever task lands first makes them per side, and the other skips them.
- Related: task 092 (per-side Void Marks, owner Q2) — removes Path of Corruption's `ctx.owner != "player"` gate.
- Related: task 093 (per-side rituals, owner Q2) — ON_RUNE_PLACED for either side.
- Related: task 064 — Runic Attunement's per-side rune multiplier; the same rune-aura code path.
- Related: task 130 (roadmap I2) — per-state `iron_resolve_active`.
- Related: task 099 (roadmap B7) — lower its `state._x` baseline when these members leave.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item B4. Re-checked at `404b51c`: 3 vars and 2 consts (not 6 fields), 3 Korrath functions plus the `_remove_rune_aura` hook. Added the Void Bolt ruination reader (CombatState.gd:962) and the latent `add_armour` leak to an enemy knight. BalanceSimBatch has no Korrath preset, so the verification adds a seeded Korrath digest check.

## Summary

_(filled in at /task-done)_
