---
id: "097"
title: Extract Seris into a per-side SerisModule (Flesh, Forge, skills, deathless save); hero skills dispatched from the hero
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item B3 (`design/refactors/ARCHITECTURE_ROADMAP.md` §B), with B6 (hero skills looked up from the hero) and the Flesh / Forge part of owner decision Q2. Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### Seris lives in the engine core

`CombatState.gd:399-401` opens a "Seris ability suite" section. Seris owns 14 engine fields and 17 functions, plus hooks inside the generic spell-cast path.

- **Fields:** `_player_flesh_value` / `player_flesh` (:1661-1669, a property that journals FLESH_CHANGED), `player_flesh_max` :1670, `_forge_counter_value` / `forge_counter` (:1684-1692, journals FORGE_CHANGED), `forge_counter_threshold` :1693, `_player_spell_damage_bonus` :1698, `_spell_cast_depth` :1752, `_double_cast_in_progress` :1754, `_seris_corrupt_used_this_turn` :1757, the Fiendish Pact pair `_fiendish_pact_pending` :1674 / `_enemy_fiendish_pact_pending` :1677, and two debug counters (`_debug_soul_forge_fires`, `_debug_corrupt_flesh_fires`) that task 094 deletes.
- **Functions:** `_gain_flesh` :406, `_spend_flesh` :418, `_on_flesh_spent` :428, `_peek_fiendish_pact_discount` :442, `_consume_fiendish_pact_discount` :451, `_pre_player_spell_cast` :466, `_post_player_spell_cast` :493, `_forge_counter_tick` :661, `_forge_counter_reset` :669, `_gain_forge_counter` :676, `_grant_forged_demon_auras` :698, `_summon_forged_demon` :711, `_on_demon_sacrificed` :730, `_soul_forge_activate` :756, `_seris_corrupt_apply` :1081, `_seris_corrupt_reset_turn` :1105, `_try_save_from_death` :1111.
- **Hooks in generic code:** `cast_player_targeted_spell` (:523) and `cast_player_hero_spell` (:546) call the pre/post hooks; `_spell_dmg` (:636) adds `_player_spell_damage_bonus` to any VOID_FLESH damage; `CombatManager.gd:288` and `:336` call `state._try_save_from_death(minion)`; `SacrificeSystem.gd:53` calls `state._on_demon_sacrificed`.
- **Outside readers:** ViewState (:26-29, :55-58, :93-98), EffectResolver, ConditionResolver, CombatHandlers, PipBar (:517-518, :707-708), SerisResourceBar (:222, :226), CombatScene (:1309-1312), SerisPlayerProfile (:82-84, :106-109), FleshcraftPlayerProfile, CombatSetup, and the tests (TriggerHandlerTests, CardEffectTests, CommandTests).

A fourth hero would add the same again to a 3,159-line engine.

### Hero skills are a hardcoded list, and player-only

```gdscript
var why: String = _check_can_act(side)                         # CombatState.gd:2865-2875
if why.is_empty() and side != "player":
	why = "no_skill"
if why.is_empty() and skill_id == "seris_corrupt" and not (target is MinionInstance):
	why = "no_target"
if why.is_empty() and not (skill_id in ["seris_corrupt", "soul_forge"]):
	why = "no_skill"
...
var done: bool = _seris_corrupt_apply(target) if skill_id == "seris_corrupt" else _soul_forge_activate()
```
`HeroData` (heroes/HeroData.gd) has no skills field.

### Flesh and Forge work for the player only

- `_gain_flesh(amount)` takes no side and writes `player_flesh`.
- EffectResolver gates four step types on the player: GAIN_FLESH (:343-345, with the comment `# Seris — player-only. Enemy Seris is not supported.`), SPEND_FLESH (:350), GAIN_FORGE_COUNTER (:358) and SPEND_FLESH_UP_TO (:399).
- ConditionResolver's `flesh_gte_1` … `flesh_lt_3` return 0 Flesh for anyone but the player (:100-114).
- `_on_demon_sacrificed` and `_try_save_from_death` return early when `minion.owner != "player"` (:731, :1112).
- `cast_enemy_spell` skips the hooks on purpose: "The pre/post-cast hooks (Seris Void Amplification / Void Resonance) are player-only and not invoked here." (:1059-1060).
- The view is side-blind. ViewState applies FLESH_CHANGED and FORGE_CHANGED whatever the event's side (:93-98), and so does the presenter (CombatPresenter.gd:699-704). An enemy-side Flesh event would overwrite the player's bar.
- The Fleshbind comment claims a side check that the body doesn't have (CombatHandlers.gd:809-811: "the ctx.owner check lets the handler stay symmetric").

No enemy content uses Flesh or Forge today (no GAIN_FLESH / SPEND_FLESH / GAIN_FORGE_COUNTER in any encounter deck), so every change here is latent and should leave the batch unchanged.

## Decision (owner, 2026-10-01)

- **Q2:** "Relics, talents and hero passives, hero resources (Flesh, Forge, Void Marks) and rituals must all work for either side in the engine. … Who has what is decided by data and config, never by `if owner == "player"` in rules code."
- **Q1:** PvP and mirror matches are planned.

So the module carries a side from day one, and the enemy gets one exactly when its config says its hero is Seris.

## Proposed fix

1. **`combat/modules/CombatModule.gd`** (RefCounted), a typed base with no-op defaults, so the engine calls hooks without `has_method` (lint L4 / L9):
   - `side: String`; `setup(state, talents: Array[String], hero_passives: Array[String])`; `teardown()` (nulls its back-reference, task 049);
   - `skills() -> Dictionary` (skill id → `{needs_target: bool, run: Callable}`);
   - hooks: `pre_spell_cast(spell)`, `post_spell_cast(spell, target)`, `spell_damage_bonus(school) -> int`, `try_save_from_death(minion) -> bool`, `on_minion_sacrificed(minion, tag)`, `on_turn_start()`, `on_rune_removed(rune)` (used by task 098);
   - `digest_fragment() -> String`.

   CombatState gets `hero_module(side) -> CombatModule` (null when the side has none). Keep module state plain data, so a future state clone for AI look-ahead (Q7b) can copy it.
2. **`SerisModule`** owns Flesh and its max, the Forge counter and threshold, the spell-damage bonus, cast depth, the double-cast guard and the Corrupt-used flag, and takes over the 15 Seris functions above (not Fiendish Pact). It journals FLESH_CHANGED / FORGE_CHANGED with its own side, and keeps task 109's SKILL_STATE_CHANGED event for the Corrupt-used flag if that has landed. `forge_counter_threshold` is also in task 090's list: whichever lands first makes it per side. It reads `forge_momentum` from its talent list, replacing the registry `stats` write `{ "forge_counter_threshold": 2 }` (CombatSetup.gd:119).
3. **Who gets one:** `setup_combat` creates a SerisModule for each side whose hero is `seris`. Today that is `config.player_hero_id`; task 090 adds the enemy's hero id and talents. The module gets that side's talents and hero passives (the player's `talents` / `hero_passives` today, none for the enemy). If task 090 has landed, remove the Seris ids from its `PLAYER_SIDE_ONLY_UNTIL_MODULES` guard list (`side_supported`).
   - Add a setup check that every talent in a side's list belongs to that side's hero (`TalentData.hero_id`), with `push_error`. A sim or test config that passes Seris talents with the default `lord_vael` hero would otherwise lose its Flesh silently. Fix what it catches in the same commit. Known today:
     - `TriggerHandlerTests._setup_stats_land_on_state` (:1690-1696) passes Korrath talents to a default (Vael) state; task 098 rewrites it, so here give it `"hero_id": "korrath"`.
     - `debug/SimRunner.gd` takes `--talents` but no hero (:12, :104), so Seris talents run as Vael. Give it a `--hero` flag (or leave it to task 141, which retires the stale sims).
4. **Side-taking engine API** in place of the player-only primitives: `gain_flesh(side, n)`, `spend_flesh(side, n)`, `flesh_of(side)`, `flesh_max_of(side)`, `gain_forge(side, n)`. Task 108 (roadmap D7) may add `flesh_of(side)` first (player Flesh, 0 for the enemy); then route it to the module. A side without a SerisModule gains nothing and has 0 Flesh, which is what the enemy gets today.
   - EffectResolver: the four steps call these with `ctx.owner`. Delete the four `and ctx.owner == "player"` gates and the comments at :343 and :357.
   - ConditionResolver: the `flesh_*` conditions read `flesh_of(ctx.owner)`.
   - CombatHandlers: Fleshbind (:817), Void Resonance (:921) and the forge_acolyte arm (:759; a GAIN_FLESH step once task 089 lands) pass the side from their context, which makes the comment at :809-811 true.
5. **Engine hook points call the side's module:**
   - All three cast paths run `pre_spell_cast` / `post_spell_cast` on the caster's module: `cast_player_targeted_spell`, `cast_player_hero_spell` and `cast_enemy_spell`. Fix the comment at :1059-1060. Merging the three paths into one `cast_spell(side, …)` is not part of this task; task 082 step 3 files it (its row 20).
   - `_spell_dmg` adds the bonus of the module whose cast is open (one side casts at a time today). Once task 129 (roadmap I1) lands, read the caster from the Resolution instead.
   - `CombatManager` (:288, :336) calls `state.try_save_from_death(minion)`, which asks the module of `minion.owner`. Keep task 061's `_refresh_slot_for` after the save and task 057's off-board guard before it (in `_deal_damage` / `kill_minion`) if they have landed.
   - `SacrificeSystem.sacrifice` (:53) calls `state.on_minion_sacrificed(minion, tag)`, which asks the module of `minion.owner`.
   - The Corrupt Flesh turn reset (`on_turn_start_corrupt_flesh_reset`, CombatHandlers.gd:914-915) calls the module.
6. **B6, skills from the hero:** `_cmd_hero_skill` drops the `side != "player"` refusal and the id list, and looks the skill up in `hero_module(side).skills()`.
   - Unknown skill or no module: `"no_skill"`. A targeted skill without a minion target: `"no_target"`. The body returns false: `"unavailable"`.
   - A non-Seris player asking for `soul_forge` now gets `"no_skill"` instead of `"unavailable"` (the enemy already gets `"no_skill"`). CommandTests' `_hero_skill` (:512-523) uses a Seris state, so its expectations stay.
   - Declaring skill ids on `HeroData` for the UI and agents is task 101 (roadmap C2). If it has landed, also check the id against `HeroDatabase.skills_for(hero_id, talents)`.
   - Keep `_log_command` after the skill body (:2878), as task 114 does: the body can still refuse.
7. **Readers.** Keep read-only forwarders `player_flesh`, `player_flesh_max`, `forge_counter`, `forge_counter_threshold` (the player module's values, or 0 / 5 and 0 / 3 when there is none) while ViewState, PipBar, SerisResourceBar, CombatScene, SerisPlayerProfile and FleshcraftPlayerProfile migrate; then delete them.
   - AI profiles read through the agent (`agent.flesh()`, `agent.skill_ready(id)`), not `agent.state` (Q7b, task 122).
   - Tests write Flesh directly (`state.player_flesh = 3`, 18 sites). Give TestHarness a `set_flesh(state, side, n)` helper.
8. **The view keys on side.** ViewState and the presenter apply FLESH_CHANGED / FORGE_CHANGED only for `ev.side == "player"` until an enemy Seris display exists.
9. **digest_text** keeps `marks %d flesh %d/%d forge %d/%d armour %d/%d` (:2249-2251) byte-identical for the player, with the defaults above when the player has no module. Append an enemy fragment only when the enemy has a module (never today). Replays dumped before the change (ReplayRunner) still verify.
10. **Left where it is:**
    - Fiendish Pact is a per-side card mechanic and already has an enemy field; task 085 (roadmap A6) moves it to SideState and makes the enemy's discount work.
    - The static `MinionInstance.corruption_inverts_on_friendly_demons` (set at CombatSetup.gd:609) becomes per-state in task 130 (roadmap I2). Whichever of 130 and this task lands second moves it into the module.
11. **Docs:** ARCHITECTURE.md gets a short "hero modules" paragraph (`CombatModule`, `hero_module(side)`), and the Flesh / Forge gates come off invariant #3's exception list.

## Verification

- `debug/tests/CommandTests.gd`, `_hero_skill_from_module`:
  - A Vael state has no SerisModule. `cmd_hero_skill("player", "soul_forge")` is refused with `"no_skill"` and the snapshot is unchanged. `cmd_hero_skill("enemy", "soul_forge")` is refused with `"no_skill"`.
  - A Seris state with `corrupt_flesh`, 1 Flesh and a friendly Demon: `cmd_hero_skill("player", "seris_corrupt", demon)` is accepted, journals HERO_SKILL and adds 1 Corruption. A second call the same turn is refused with `"unavailable"`.
- `debug/tests/TriggerHandlerTests.gd`, `_enemy_seris_module_flesh`: attach an enemy SerisModule directly (until task 090 adds an enemy hero id to CombatConfig). An enemy-owned GAIN_FLESH step raises the enemy's Flesh; the player's Flesh and ViewState's `player_flesh` are unchanged; the journal has FLESH_CHANGED with side `"enemy"`.
- Same file, `_enemy_seris_module_forge`: an enemy module with `soul_forge` and threshold 3; an enemy-owned GAIN_FORGE_COUNTER of 3 summons a `forged_demon` on the enemy board, not the player's.
- The existing Seris probes in CardEffectTests and TriggerHandlerTests pass with their accessors updated.
- Grep gates: `grep -n 'ctx.owner == "player"' combat/effects/EffectResolver.gd` no longer lists GAIN_FLESH, SPEND_FLESH, GAIN_FORGE_COUNTER or SPEND_FLESH_UP_TO; after the forwarders go, `grep -cE '^var .*(flesh|forge|seris)|^var _(spell_cast_depth|double_cast|player_spell_damage_bonus)' combat/board/CombatState.gd` → 0 (Fiendish Pact excepted).
- `tools/run_checks.sh` green. Parity's Seris cases (F4, F5) replay through `cmd_hero_skill`.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4: the Seris presets run in every act, and the cast path changes for every hero) diffs empty (design/TESTING.md 'Refactor / extraction work'). Request Acts 3-4 explicitly.

## Related

- Depends on: task 094 (roadmap B1) — deletes the two Seris debug counters first, so the module doesn't inherit them.
- Related: task 083 (roadmap A1) — SideState; modules can hang on it later. Task 085 (roadmap A6) moves Fiendish Pact there.
- Related: task 090 (per-side talents, owner Q2) — per-side talents and hero passives and an enemy hero id; the module takes its side's lists, and 090 makes their trigger registration per side.
- Related: task 092 (per-side Void Marks, owner Q2) — the other player-gated EffectResolver steps (Void Marks, GRANT_ESSENCE, Path of Corruption, Dark Channeling); the Flesh / Forge gates are this task's.
- Related: task 098 (roadmap B4) — reuses `CombatModule` for Korrath.
- Related: task 099 (roadmap B7) — lower its `state._x` baseline when these members leave.
- Related: task 101 (roadmap C2) — declares hero skill ids on HeroData for the UI.
- Related: task 129 (roadmap I1) — the Resolution's caster replaces "the module whose cast is open".
- Related: task 130 (roadmap I2) — per-state talent statics.
- Related: tasks 057, 059 and 061 — bugs on the save-from-death and Flesh-gain paths this task moves; land them first or carry their fixes over.
- Related: task 108 (roadmap D7) — parameterised conditions would fold the five `flesh_*` conditions into one.
- Related: task 049 — module back-references must be nulled in `teardown()`.
- Related: task 141 (roadmap J5) — retires the stale debug sims; SimRunner has no hero flag (step 3).
- Related: task 133 (roadmap I5) — extends `digest_text` on purpose. If it lands first, step 9 keeps its extended lines identical too.
- Related: task 109 (roadmap E2) — adds SKILL_STATE_CHANGED for the Corrupt-used flag that step 2 moves.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap items B3 and B6 and owner decision Q2 (Flesh / Forge for either side). Re-checked every field, function and hook at `404b51c`. Found the side-blind FLESH_CHANGED / FORGE_CHANGED handling in ViewState and the presenter, which an enemy module would trip, and two configs that pass talents with the wrong hero (a TriggerHandlerTests probe, SimRunner).

## Summary

_(filled in at /task-done)_
