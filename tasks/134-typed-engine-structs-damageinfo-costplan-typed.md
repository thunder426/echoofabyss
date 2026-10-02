---
id: "134"
title: Typed engine structs: DamageInfo, CostPlan, typed buff containers
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item I6 (`design/refactors/ARCHITECTURE_ROADMAP.md` §I). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Three engine structs are Dictionaries or duck-typed Objects. A misspelled or missing key silently reads as `0` / `""` / `null`, and the compiler can't help.

### DamageInfo is a Dictionary

- `CombatManager.make_damage_info` (CombatManager.gd:32-45) returns `{amount, source, school, attacker, source_card}`.
  - There are 34 call sites in `combat/`, `relics/` and `enemies/`: CombatHandlers 15, CombatManager 5, CombatState 5, HardcodedEffects 3, CheatPanel 3, RelicEffects 2, EffectResolver 1. Tests add 38 more: DamageTypeTests 27, TriggerHandlerTests 9, LiveSmokeTests 2.
- It is read with defaulted `.get()`: `var amount: int = info.get("amount", 0)` (:200, :246), `info.get("school", Enums.DamageSchool.NONE)` (:203), `info.get("source", Enums.DamageSource.SPELL)` (:306), and `CombatState._on_hero_damaged` (CombatState.gd:2018-2019, :2041-2043, :2063-2064).
- **It is mutated in place.** `apply_hero_damage` writes the post-armour amount into the caller's dict, then emits it:
  ```gdscript
  amount = _apply_armour_math(hero, amount)
  info["amount"] = amount                    # CombatManager.gd:206-207
  ```
  Harmless today. Every hero-damage call builds a fresh dict, `apply_damage_to_minion` copies before the Ethereal bonus (:312), and `_spell_dmg` copies (CombatState.gd:647). Soul Shatter and Grafted Butcher already reuse one info across an AoE loop (HardcodedEffects.gd:88-90, :106-108) and are safe only because `_spell_dmg` copies. The first hero-damage caller that reuses an info gets the previous target's post-armour amount.
- `EventContext.damage_info` is `Dictionary` (EventContext.gd:42), and its doc tells handlers to read it "via Dictionary keys" (:38-41). No production handler reads it yet. Task 060 and task 129 (roadmap I1) start reading it for crit and kill credit.
- Task 060 adds an `is_crit` key. Task 129 needs a typed home for the killing hit's crit flag and attacker.

### Cost plans are Dictionaries

- `plan_cost(side, inst, extra) -> Dictionary` (CombatState.gd:3012) returns `{why}` on refusal, else `{essence, mana, sparks, fuel, auto_sparks}`.
- The four `_cmd_play_*` bodies read `cost.get("why", "")` (:2548-2549, :2623, :2679, :2723). `pay_planned_cost` (:3053-3060) reads `cost.get("auto_sparks", false)`, `cost.get("fuel", [])`, `cost.get("essence", 0)` and `cost.get("mana", 0)`.
- One caller outside the engine: `CombatScene._command_play_minion` (CombatScene.gd:607-608, `plan.get("why", "")`).

### Buff containers are untyped and duck-typed

- `MinionInstance.buffs` is `var buffs: Array = []` (MinionInstance.gd:74). `HeroState.buffs` is `var buffs: Array[BuffEntry] = []` (HeroState.gd:31).
- Every BuffSystem entry point takes `target: Object`: `apply` (BuffSystem.gd:82), `remove_source` (:125), `sum_type` (:196), `net_armour` (:222), and so on. They then reach the fields dynamically: `target.buffs.append(entry)` (:100), `return int(target.armour) - sum_type(...)` (:225).
- Lint L4 bans `has_method` and `.get("x")` on objects. It can't see a dynamic property access through an `Object`-typed parameter, so this is the duck typing the invariant forbids.

### Not in this task

- `TargetRef` and per-copy `TrapInstance` (also in roadmap I6) belong to task 084 (roadmap A2).
- Event payload reads with defaults (`p.get(k, 0)`: about 91 lines in CombatPresenter.gd, 23 in ViewState.gd) stay. That is a journal-schema change, not an engine struct.

## Proposed fix

Three parts. Each is its own commit with its own gate run. Part a goes first, because task 129 (roadmap I1) builds on it.

### a. `DamageInfo` class

1. Add `combat/board/DamageInfo.gd`: `class_name DamageInfo extends RefCounted`.
   - Typed fields `amount: int`, `source: Enums.DamageSource`, `school: int` (keep it `int`: schools are tested with `Enums.has_school`), `attacker: MinionInstance`, `source_card: String`, `is_crit: bool`.
   - `static func make(...)` with the same parameters as `make_damage_info`, and `func copy() -> DamageInfo`.
   - It holds no reference to CombatState (task 049).
2. `CombatManager.make_damage_info` returns `DamageInfo`. Keep the name so the 72 call sites change only where they read keys. `_attack_damage_info` (:322-330) and `EffectResolver._build_damage_info` (:683-685) return it too.
3. Convert the readers: `apply_hero_damage`, `_deal_damage`, `apply_damage_to_minion` (copy for Ethereal), `_rift_warden_siphon` / `_post_crit` (:393, :441-445), `CombatState._spell_dmg` (:636-648), `_on_hero_damaged` (:2015-2065), the relic_execute branch (:2841-2849, which today sets `info["amount"] = 500` after building it), and the HardcodedEffects sites that build a 0-amount info and let `_spell_dmg` fill the amount (:88, :106, :266).
4. **`apply_hero_damage` stops writing into the caller's info.** It computes the landed amount, emits `hero_damaged(target, landed)` with `landed = info.copy()` and `landed.amount` = the post-armour value, and returns that amount (`-> int`, 0 when nothing landed). Type the signal (CombatManager.gd:20) as `(target: String, info: DamageInfo)`.
5. `EventContext.damage_info: DamageInfo = null`. Update its comment, and handlers test for `null` instead of `is_empty()`.
6. If task 060 has landed, its `is_crit` key becomes the field. If not, the field defaults to `false` and task 060 sets it.
7. Tests: DamageTypeTests (27 builders, plus the `.get("amount")` / `.get("school")` reads at :168-172, :184-185, :424-426, :520-561) and the `HeroDmgCapture` buffer read fields instead of keys. Update TriggerHandlerTests and LiveSmokeTests where the compiler flags them.
8. Update `design/DAMAGE_TYPE_SYSTEM.md` §DamageInfo (:100-141) and its file table (:220-223).

### b. `CostPlan` class

1. Add `CostPlan` (RefCounted): `why: String`, `essence: int`, `mana: int`, `sparks: int`, `fuel: Array[MinionInstance]`, `auto_sparks: bool`, plus `ok() -> bool` and `static func refused(why) -> CostPlan`.
2. `plan_cost` returns it. `pay_planned_cost(side, plan: CostPlan)` reads fields.
3. Convert the five callers: the four `_cmd_play_*` bodies and `CombatScene._command_play_minion`.

### c. Typed buff containers

1. Add `Buffable` (RefCounted) with `buffs: Array[BuffEntry] = []` and `armour: int = 0`. `MinionInstance` and `HeroState` extend it. Each keeps its own `add_armour()`: the minion's has the Unbreakable doubling.
2. Every BuffSystem entry point takes `target: Buffable`. Keep `target as MinionInstance` where minion-only work follows (`apply`'s stat snapshot, `_clamp_shield`).
3. `filter()` keeps the element type, which HeroState's typed `buffs` already relies on (TriggerHandlerTests.gd:3204 runs `remove_type` on a hero), so the six `target.buffs = target.buffs.filter(...)` lines (:129-189) stay. `CombatHandlers.gd:863` (`target.buffs = []`) is fine with a typed array.
4. Fix whatever else the compiler flags: the `for e in minion.buffs` loops (HardcodedEffects.gd:187; CombatHandlers.gd:1178, :2167) can become typed loops.

## Verification

- New DamageTypeTests probe `_apply_hero_damage_leaves_caller_info`:
  - Setup: `TestHarness.build_state()`, `state.enemy_hero.armour = 200`, `info = CombatManager.make_damage_info(500, Enums.DamageSource.MINION, Enums.DamageSchool.PHYSICAL)`.
  - Action: `var landed: int = state.combat_manager.apply_hero_damage("enemy", info)`.
  - Assert: `info.amount == 500` (today 300), `landed == 300`, and `state.enemy_hp == 1700`.
- Existing `_test_apply_hero_damage_emits_signal` (DamageTypeTests.gd:174-185) still sees one emission with amount 300 and school VOID, now as fields.
- New CommandTests probe: on a card the side can't afford, `plan_cost` returns `ok() == false` and `why == "cost"`; on an affordable one it returns `ok()` and the card's essence / mana.
- `tools/run_checks.sh` green after each part. Lint L4 and L9 must stay at 0.
- Behaviour-neutral (a typing refactor): the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after each part, for Acts 1–4) diffs empty (design/TESTING.md 'Refactor / extraction work').

## Related

- Related: task 129 (roadmap I1) — depends on part a. It replaces the side channels with the typed Resolution stack and takes crit and kill credit from `DamageInfo`.
- Related: task 060 — adds `is_crit` to the damage info; part a gives it a typed field. Either order works.
- Related: task 084 (roadmap A2) — owns `TargetRef` and per-copy `TrapInstance`, the rest of roadmap I6.
- Related: task 091 (roadmap PS-relics) — `plan_cost` applies the Dark Mirror discount only `if side == "player"` (CombatState.gd:3045). That task owns the side; this one only types the result.
- Related: task 130 (roadmap I2) — also edits BuffSystem (the global `bus()`, BuffSystem.gd:42). Coordinate the signature change in part c.
- Related: task 105 (roadmap D2) — the same "typed objects, not dictionaries" direction for effect steps.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item I6.
  - Re-check at `404b51c`: the DamageInfo aliasing is latent (every caller builds a fresh dict).
  - `plan_cost` has 5 callers, not 6.
  - TargetRef / TrapInstance moved to task 084. Event payload `.get` defaults left out.
  - Plan priority (normal) kept over the unit report's low, because task 129 depends on part a.

## Summary

_(filled in at /task-done)_
