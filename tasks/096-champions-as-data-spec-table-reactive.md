---
id: "096"
title: Champions as a data spec table with a reactive aura column; small modules for ACP and VC
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item B2 (`design/refactors/ARCHITECTURE_ROADMAP.md` §B), plus roadmap I7c (the player-champion summon log text). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Each of the 15 enemy champions is hand-written code: one or more handlers in `CombatHandlers.gd` (spread across :1428-2290, between the other encounter passives), a `CombatSetup._REGISTRY` entry (:285-427), constants, and a summon call. Its player-facing description is copied by hand into the card text, `EnemyHeroPanel.CHAMPION_INFO` (:768) and `CombatUiStyle.PASSIVE_INFO` (:241). Those copies had drifted for 4 of 15 champions, and 3 had no tooltip at all. Task 068 fixes the text once; this task makes the numbers live in one place so it can't drift again.

### The handlers share one shape

The summon side of 14 champions is "count a qualifying event, show pips, summon at a threshold, grant crit stacks". For example Void Ritualist Prime (CombatHandlers.gd:1739-1756):
```gdscript
func on_enemy_spell_champion_vrp(_ctx: EventContext) -> void:
	if state._champion_vrp_summoned:
		return
	state._champion_vrp_spells_cast += 1
	var total: int = state._champion_vrp_spells_cast
	var pips: int = mini(total, _VRP_PIPS)
	_show_champion_progress(pips, _VRP_PIPS)
	_log("  Champion progress: %d / %d spells cast." % [mini(total, _VRP_THRESHOLD), _VRP_THRESHOLD], _LOG_ENEMY)
	if total >= _VRP_THRESHOLD:
		_summon_enemy_champion("champion_void_ritualist_prime")
		# Grant 2 Critical Strike on summon and activate aura
		...
		state.enemy_spell_cost_aura = -1
```
Void Captain (:1694-1712), Avatar of the Abyss (:1854-1871) and the others differ only in the event, the filter, the amount counted and the numbers.

Precedent: player champions are already data on the card. `nyx_ael.auto_summon_condition = "board_tag_count"`, `auto_summon_tag = "void_imp"`, `auto_summon_threshold = 3` (CardDatabase.gd:2070-2072), read by `_check_champion_condition` (CombatState.gd:2127-2135). Every enemy champion passive id is also the champion's card id (all 15 match; the 16th registry entry, `champion_duel`, has no card and task 081 deletes it).

### How the 15 fit a table (unit B's classification, re-checked)

| Champion | Progress source | Aura | Fits |
|---|---|---|---|
| F1 RIP | ON_ENEMY_ATTACK, `rabid_imp`, distinct attackers, 4 | static: +100 ATK on `feral_imp` | row |
| F2 CB | enemy minion deaths, 3 | none; on death summons `void_touched_imp` 200/300 | row |
| F3 IM | ON_ENEMY_SPELL_CAST `pack_frenzy`, 2 | reactive: on Pack Frenzy, +200 current HP to feral imps | row (see the IM note) |
| F4 ACP | fed by `on_enemy_summon_corrupt_authority_imp` with a stack count (:1201), 5 | instant detonation with a VFX pulse and DETONATION events (:2158-2186) | module |
| F5 VR | fed by `on_enemy_summon_ritual_sacrifice` (:1280), 1 | none after task 068 | row (`feed`) |
| F6 CH | enemy `void_spark` summons, 3 | reactive: each spark summon deals 200 to the player hero | row |
| F7 RS | `void_spark` attacks, amount = attacker ATK, 1000 (5 pips) | static: GRANT_IMMUNE on `void_spark` | row |
| F8 VA | ON_ENEMY_SPARK_CONSUMED, amount = spark value, 5 | queried by `void_detonation` (:1390) | row |
| F9 VH | spell cast or minion summon with `void_spark_cost > 0`, 6 | queried by `spark_cost_of` (CombatState.gd:2991-2993) and `void_rift` (:1359-1361) | row |
| F10 VS | polls `_enemy_crits_consumed` at enemy turn end, 5 | field: `enemy_crit_multiplier` 2.5, reverted on death | row (`poll`) |
| F11 VW | consumed Spirits, 2 | reactive: a dying friendly Spirit gives a random friendly 1 Critical Strike | row |
| F12 VC | `thrones_command` casts, 2 | hook inside `CombatManager._post_crit` (:430), which has no trigger event | module |
| F13 VRP | any enemy spell, 5 | field: `enemy_spell_cost_aura` -1, reverted on death | row |
| F14 VCH | player minion killed by an enemy crit (predicate), 3 | reactive: +1 max Mana and +1 max Essence at enemy turn end | row (needs GROW_ESSENCE_MAX) |
| F15 AS | player minion played or spell cast, 12, phase-2 gate | queried by `abyss_awakened` (:1834-1835) | row |

A static table alone fits 9 of 15 (60%). With a reactive `{event, filter, effect_steps}` aura column it fits 13 of 15 (87%); ACP and VC need code.

## Decision (owner, 2026-10-01)

- **Q4:** "Data spec table if at least 80% of champions fit it; the outliers get a small module." With the reactive aura column 13 of 15 fit, so: a spec table with a reactive aura column, and small modules for ACP and VC.
- **QN1** (via task 068): code wins on every champion number, and the Void Ritualist has no aura.
- **Q6:** CardDatabase.gd is the card source of truth.

## Proposed fix

Build on task 095's `ChampionTracker`. Every phase is behaviour-neutral and lands as its own commit with its own gate run.

### Phase 1 — summon side from the spec

1. Add a `ChampionSpec` (a typed RefCounted or Resource) and attach one to each enemy champion card in `cards/data/CardDatabase.gd`, next to the card, as the player champions do. Fields:
   - progress: `events` (TriggerEvent + priority per event, copied from today's registry so handler order is unchanged), `filter` (card id / tag / race / `spark_cost > 0` / crit-kill predicate), `amount` (1, attacker ATK, spark value), `distinct_by_instance` (RIP), `gate` (AS: phase 2);
   - or `source: feed` (VR, ACP: called by another handler) / `source: poll` (VS: a counter read at enemy turn end);
   - `threshold`, `pips` (RS has 1000 / 5), `progress_noun` for the log line ("rabid imp attacks", "Throne's Command cast", …), `on_summon_crit`, `on_death_steps` (CB).
2. One generic handler, registered by `CombatSetup` for every enemy passive whose id is a champion card with a spec. It feeds the tracker, journals CHAMPION_PROGRESS, logs the same line as today, summons, grants the crit stacks.
3. Delete the per-champion progress handlers and the champion entries' `triggers` in `_REGISTRY`. Keep each death handler only while its aura still needs it (phase 2).
4. Keep RNG call order and log text identical; both feed the fingerprint and the journal.

### Phase 2 — auras from the spec

1. An `aura` column with four kinds:
   - **static**: a buff on every friendly minion matching a filter while the champion is on the board, stripped when it leaves (RIP +100 ATK on `feral_imp`; RS GRANT_IMMUNE on `void_spark`);
   - **field**: set an engine field on summon, restore it when the champion leaves (VS `enemy_crit_multiplier`, VRP `enemy_spell_cost_aura`);
   - **reactive**: a list of `{event, filter, effect_steps}`, run only while the champion is on the board (IM, CH, VW, VCH);
   - **query**: nothing to run; other code asks `champions.is_alive(card_id)` (VA, VH, AS).

   Every aura is gated on "champion on the board", never on "was summoned", so task 066's bug can't return.
2. Add `GROW_ESSENCE_MAX` to `EffectStep` / `EffectResolver`, mirroring `GROW_MANA_MAX` (EffectResolver.gd:139-144), for VCH. Coordinate with task 069, which journals max-resource growth.
3. Check each reactive row's steps against today's code before switching:
   - **IM** does a raw `m.current_health += 200` (CombatHandlers.gd:2118). `BUFF_HP` adds a buff entry and journals BUFF_APPLIED (EffectResolver.gd:485-495), which is not the same state. Use a step that reproduces the raw add, or keep IM's effect as a Callable row. Don't change the semantics in this task. (Even with IM as an outlier, 12 of 15 is still 80%.)
   - **CH**: `DAMAGE_HERO` also runs `_dark_channeling_dmg` and Path of Corruption (EffectResolver.gd:37-50). Both are no-ops in F6; keep the damage source label `"champion_corrupted_handler_aura"`, which task 094's counter fold reads.
   - **VW** picks its target with `state.rng_pick` over the enemy board (:1666-1673). The step's random pick must make the same RNG call on the same array.
4. **Modules for ACP and VC** (`combat/board/champions/AbyssCultistPatrolModule.gd`, `VoidCaptainModule.gd`, or one file each under the tracker): ACP keeps its detonation code (VFX pulse, DETONATION events, `_spell_dmg`); VC is called from `CombatManager._post_crit` through the tracker (`state.champions.on_crit_consumed(attacker)`) instead of the inline `_champion_vc_is_alive()` block.

### Phase 3 — text from the spec, content checks, I7c

1. Each spec can describe itself: `describe_condition()`, `describe_aura()`. Reactive and module rows carry a short text template whose numbers are filled from the row (`{threshold}`, `{amount}`), so each number is written once.
2. Generate from it: the champion card's `description` in CardDatabase, the `CHAMPION_INFO` entries (task 068 moves the table to class level) and the champion entries of `PASSIVE_INFO`. Delete the hand-written champion entries. The generated text follows `design/master_doc/CARD_DESCRIPTION_STYLE.md` and should read the same as task 068's hand-fixed text.
3. Content checks in task 104's ContentTests layer: every `champion_*` passive in `EncounterTable` (and `PhaseTransition.SOVEREIGN_P2_PASSIVES`, or EncounterTable's phase-2 list once task 125 deletes that constant) has a spec; every spec's card exists; every spec belongs to some encounter.
4. **I7c:** `_summon_champion_card` logs `"⚡ 3 Void Imps on board — %s emerges!"` for any player champion (CombatState.gd:2153). Build the line from `auto_summon_threshold` and a display name for `auto_summon_tag`. Nyx'ael, the only player champion, keeps the same text.

### Not in scope

- The full-board case (task 095, Latent): the generic summon keeps today's behaviour (flag set before the summon, nothing retries). Changing it to retry on the next qualifying event is a behaviour change; file it separately if the owner wants it.
- Player-champion auto-summon for either side (`_check_champion_triggers` reads only the player's hand, deck and board, CombatState.gd:2108-2124). That is A6d in the A-paths grooming; task 089 (roadmap A8, step 8) owns it.

## Verification

- Extend task 095's `_champion_tracker_lifecycle` probe in `debug/tests/TriggerHandlerTests.gd` into one table-driven probe per spec row:
  - fire threshold - 1 qualifying events: not summoned, pips at threshold - 1;
  - one more: summoned, on-summon crit stacks granted;
  - the aura is on while the champion is on the board and off after `kill_minion`.
- `_champion_text_matches_spec` (ContentTests, task 104): the champion card description and its CHAMPION_INFO entry contain the spec's threshold.
- `debug/tests/snapshots/handler_order.txt` changes: the per-champion method names become the generic handler's. Update it deliberately and check in the diff that, per event, the priorities and the relative order are unchanged.
- `tools/run_checks.sh` green after each phase.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after each phase, for Acts 1, 2, 3 and 4) diffs empty (design/TESTING.md 'Refactor / extraction work'). Request Acts 3-4 explicitly. Phase 3 changes only text.
- Manual (editor): hover the champion pips and the passive icon in F1, F7, F11 and F15; the text matches the card.

## Related

- Depends on: task 095 (roadmap B2a) — the ChampionTracker, one alive query and one summon path this table drives.
- Depends on: task 104 (roadmap D1) — its ContentTests layer and lint L14 hold the spec checks (phase 3, step 3).
- Depends on: task 068 — fixes the champion text and moves CHAMPION_INFO / PASSIVE_INFO to class level; phase 3 then generates what 068 corrected by hand.
- Related: task 066 — gating every aura on "on the board" keeps its bug from returning.
- Related: task 069 — journals max-resource growth; VCH's GROW_ESSENCE_MAX should use the same path.
- Related: task 081 (roadmap DL1) — deletes `champion_duel`, the one registry champion with no card.
- Related: task 086 (roadmap A3) — side-neutral trigger events; the spec's `events` column should use them once they exist. If this task lands before 086 phase 3, the `events` and reactive columns use legacy TriggerEvent values and 086 phase 3 migrates them.
- Related: task 085 (roadmap A6) — renames `enemy_crit_multiplier` to a per-side `crit_multiplier_override` (VS's field aura) and moves the enemy cost auras (VRP's `enemy_spell_cost_aura`) onto SideState; the field-aura rows write whichever names exist.
- Related: task 125 (roadmap H3) — moves the F15 phase-2 spec into EncounterTable.
- Related: task 107 (roadmap D4) — the effect handler registry; GROW_ESSENCE_MAX lands in whichever dispatch exists at the time.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item B2 and I7c. Re-checked unit B's 15-row classification at `404b51c`. Added the IM, CH and VW step caveats and the passive-id = card-id observation (spec on the card, per Q6). VR's aura is gone after task 068, so VR fits as a `feed` row.

## Summary

_(filled in at /task-done)_
