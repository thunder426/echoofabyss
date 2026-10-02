---
id: "081"
title: Delete unreachable passive content (spirit_conscription, champion_duel, dead passive arm, stale AI hardcoded-id check)
status: backlog
area: content
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item DL1 (a new candidate from the §D content-validation pass, `design/refactors/ARCHITECTURE_ROADMAP.md` §D). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Two enemy passives, their handlers, a state field, four probes and two tooltip entries are maintained, but no encounter applies them. There is also a dead `passive_effect_id` arm and a stale AI check. All of it looks live to a reader, and task 104 (roadmap D1)'s registry-reachability check would flag the two passives on day one.

### Two passives no encounter applies

- Registry entries: `combat/events/CombatSetup.gd:481-487` `"spirit_conscription": {` and `:496-502` `"champion_duel": {`.
- Neither id is in any `"passives"` list in `enemies/data/EncounterTable.gd` (:16-142), in `PhaseTransition.SOVEREIGN_P2_PASSIVES` (PhaseTransition.gd:25), in TalentDatabase or in HeroDatabase. A repo-wide grep finds them only in the files listed here.
- When they went:
  - `spirit_conscription` left F11 in `35989e6` (Version 0.39, 2026-04-13): `["void_might", "spirit_conscription"]` → `["void_might", "spirit_resonance", "champion_void_warband"]`.
  - `champion_duel` left F14 in `d89baee` (Version 0.44, 2026-04-22): `["void_might", "champion_duel"]` → `["void_might", "mana_for_spark", "champion_void_champion"]`.
- `spirit_conscription` is doubly dead. Its handler gates on a tag no card has: CombatHandlers.gd:1941 `if not _has_tag(minion, "void_spirit"):`. The only other `"void_spirit"` strings are in its own test.

Everything attached to them:
- Handlers:
  - CombatHandlers.gd:1932-1947 (`on_enemy_turn_reset_spirit_conscription`, `on_enemy_summon_spirit_conscription`);
  - :2009-2029 (`on_enemy_turn_champion_duel_refresh`, `on_enemy_attack_champion_duel_refresh`, `_refresh_champion_duel_immunity`).
- State: CombatState.gd:1782 `var _spirit_conscription_fired: bool = false`. Only the registry's `"stats"` (CombatSetup.gd:486) and the handlers touch it. Lint L1 checks that every registry stat key is declared on CombatState (`scan_setup_stats`, tools/lint/lint_engine.py:224-240), so the field and the registry entry go together.
- Probes in `debug/tests/TriggerHandlerTests.gd`:
  - calls at :111-112 and :118-119;
  - sections at :1838-1865 (`_champion_duel_sync_on_turn_start`, `_champion_duel_revokes_when_crit_lost`) and :1946-1981 (`_spirit_conscription_summons_spark`, `_spirit_conscription_once_per_turn`).
  - The spirit_conscription pair is already marked "KNOWN BUG (double dead-code)" (:1951) and "probe parked" (:1980). `_spirit_conscription_summons_spark` also never calls `state.teardown()`.
  - The section header at :1441 says "Act 3–4 champions + champion_duel".
- Handler-order snapshot: `debug/tests/snapshots/handler_order.txt` holds four of these handlers: line 3 `0:on_enemy_turn_reset_spirit_conscription` and `10:on_enemy_turn_champion_duel_refresh`, line 16 `6:on_enemy_summon_spirit_conscription`, line 18 `98:on_enemy_attack_champion_duel_refresh`. The probe registers every `_REGISTRY` key at once (TriggerHandlerTests.gd:3474-3478).
- Tooltips: `combat/ui/EnemyHeroPanel.gd:811` `"champion_duel": {` ("Void Duel") and `combat/ui/CombatUiStyle.gd:270` `"champion_duel": {` ("Champion: Void Duel").
- Comments and docs:
  - `debug/tests/ScenarioTests.gd:406`: `# S16 — Act 4: void_warband encounter (spirit_resonance + spirit_conscription + champion_vw).`
  - `enemies/ai/profiles/VoidChampionProfile.gd:4-6` describes `champion_duel` as F14's passive.
  - `design/master_doc/DESIGN_DOCUMENT.md:755` `| 14 | Void Champion | 7800 | void_champion | void_might, champion_duel |` and :767 `| champion_duel | Enemy minions with Critical Strike have Spell Immune |`.

### Dead passive arm

CombatHandlers.gd:794-797, inside `_apply_board_passive_on_death`:
```
"void_mark_on_void_imp_death":
    if _is_void_imp(dead):
        _log("  Abyssal Sacrificer: %s died → 1 Void Mark." % dead.card_data.card_name, _LOG_PLAYER)
        state._apply_void_mark(1)
```
No card sets this `passive_effect_id`. Cards set 8 other ids (CardDatabase.gd:1263, :2023, :2036, :2254, :2267, :2576, :3378, :3435), and each has its own arm or check. Abyssal Sacrificer is not in CardDatabase. DESIGN_DOCUMENT.md:408 still lists "Abyssal Sacrificer passive: +1 Mark when a Void Imp dies" as a Void Mark source.

### Stale AI check

`enemies/ai/CombatProfile.gd:366`, in `_spell_needs_board_slot`:
```
if hid in ["brood_call", "void_summoning"]:
```
`void_summoning` is not a HARDCODED id. HardcodedEffects.resolve (:36-70) has no such arm, and the card uses SUMMON steps (CardDatabase.gd:1572-1575). The SUMMON check at :362 already returns true for it, so removing the literal changes nothing.

### Also stale: DESIGN_DOCUMENT.md's Act 4 tables

The F14 row is wrong because of `champion_duel`, and the rows around it drifted too. EncounterTable.gd is the truth:
- F12-F14 HP are 5000 (EncounterTable.gd:113, :122, :131). The doc has 6200 / 7000 / 7800 (:753-755). F12 has been 5000 since v0.39.
- The doc is missing passives from these rows:
  - F12: `champion_void_captain` (:115);
  - F13: `ritualist_spark_free` and `champion_void_ritualist_prime` (:124);
  - F14: `mana_for_spark` and `champion_void_champion` (:133);
  - F15: `champion_abyss_sovereign` (:142).
- The passive table (:758-767) has a wrong row: `captain_orders` "Crit multiplier is 2.5× instead of 2×" (:764). In the code, Throne's Command costs 1 less spark (CombatState.gd:2999-3000). At the end of the enemy turn, each friendly minion with Critical Strike spends one stack to deal its ATK to the player's hero (CombatHandlers.gd:1949-1965).
- It has no row for:
  - `ritualist_spark_free`: enemy spells cost 0 sparks (CombatState.gd:2996).
  - `mana_for_spark`: a spark shortfall is paid in Mana, 1 per missing spark (CombatState.gd:3028, :3035).
  - `abyss_awakened`: F15 phase 2. At enemy turn start every enemy minion gains 1 Critical Strike, or 2 while Avatar of the Abyss lives (CombatHandlers.gd:1834-1843).
- Task 068 records this table as stale but edits only the champion tables (:783-809).

## Proposed fix

1. **Passives.** Delete:
   - the two registry entries (CombatSetup.gd:481-487, :496-502);
   - the five handler functions and their doc comments (CombatHandlers.gd:1932-1947, :2009-2029);
   - `_spirit_conscription_fired` (CombatState.gd:1782);
   - the four probes, their four calls (TriggerHandlerTests.gd:111-112, :118-119) and their section comments. Rename the :1441 header to "Act 3–4 champions".
   - the two `champion_duel` tooltip entries (EnemyHeroPanel.gd:811-817, CombatUiStyle.gd:270-273; class-level `EnemyHeroPanel.CHAMPION_INFO` / `CombatUiStyle.PASSIVE_INFO` once task 068 lands).
2. **Snapshot.** Edit `debug/tests/snapshots/handler_order.txt` by hand and remove exactly the four entries listed above. Or delete the file and run the suite twice: the first run writes it and fails by design (TriggerHandlerTests.gd:3483-3488). Either way, `git diff` on the file shows only those four entries removed.
3. **Dead arm.** Delete the `void_mark_on_void_imp_death` arm (CombatHandlers.gd:794-797).
   - Task 062 step 5 deletes the whole `_apply_board_passive_on_death`, arm included. Whichever lands second skips this step.
   - Remove the "Abyssal Sacrificer" line from DESIGN_DOCUMENT.md:408. It is a source of Void Marks that doesn't exist.
4. **AI check.** CombatProfile.gd:366 → `if hid == "brood_call":`.
5. **Comments:**
   - ScenarioTests.gd:406 → `(void_might + spirit_resonance + champion_void_warband)`, matching EncounterTable.gd:106.
   - VoidChampionProfile.gd:4-6: task 072 step 4 rewrites this header. If this task lands first, fix it here and note it in 072.
   - CombatHandlers.gd:1950 says captain_orders' Throne's Command discount is "handled in CombatProfile._effective_spark_cost"; it is in `CombatState.spark_cost_of` (:2999). Fix it with the `captain_orders` doc row in step 6.
6. **DESIGN_DOCUMENT.md Act 4 tables:**
   - Rewrite rows :753-756 from EncounterTable.gd:113-142 (HP and passives). Add a phase-2 note for F15: `void_might, abyss_awakened, champion_abyss_sovereign` (PhaseTransition.gd:25).
   - Delete the `champion_duel` row (:767), fix `captain_orders` (:764), and add rows for `ritualist_spark_free`, `mana_for_spark` and `abyss_awakened`. Write each from the code cited above.
   - Leave the champion tables (:783-809) to task 068.

## Verification

- `grep -rn 'spirit_conscription\|champion_duel\|void_mark_on_void_imp_death\|"void_summoning"\]' --include='*.gd' --include='*.txt' --include='*.md' . | grep -v '^./tasks/\|^./.godot\|/archive/'` → 0 hits.
- `debug/tests/snapshots/handler_order.txt`: the diff is exactly the four removed handler entries.
- No new probe is needed. The handler-order snapshot covers the registry. Once it exists, task 104's reachability check keeps this from coming back and needs no allowlist for these two ids.
- `tools/run_checks.sh` green, with lint L1 clean on the registry stats.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4) diffs empty (design/TESTING.md "Refactor / extraction work").
  - Request `--act 3` and `--act 4` explicitly; F11 and F14 are the fights these passives once belonged to.
  - Run Acts 1–2 because `_spell_needs_board_slot` is in the base `CombatProfile` that every enemy and player-bot profile extends.

## Related

- Related: task 104 (roadmap D1) — depends on this task. Its registry-reachability check flags `spirit_conscription` and `champion_duel` today. Once this lands, its allowlist for them is empty.
- Related: task 062 — deletes `_apply_board_passive_on_death`, including the dead arm in step 3. Whichever lands second skips that part.
- Related: task 068 — fixes champion and passive tooltips, and leaves the `champion_duel` entries (EnemyHeroPanel.gd:811, CombatUiStyle.gd:270) to this task. Both edit the same two dicts.
- Related: task 072 — rewrites the VoidChampionProfile.gd:4-6 header that describes `champion_duel`.
- Related: task 089 (roadmap A8) — retires the legacy `passive_effect_id` dispatch that holds the dead arm.
- Related: task 137 (roadmap J1) — splits TriggerHandlerTests by subsystem. Landing this first means four fewer probes to move.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item DL1. Re-checked at `404b51c`.
  - Every site was confirmed by grep. The handler-order snapshot has four entries to remove, on three lines (3, 16, 18).
  - The snapshot is easier to edit by hand than to regenerate: a regenerating run fails once by design.
  - Corrected the history: `champion_duel` left F14 in v0.44 (`d89baee`), not v0.39. `spirit_conscription` left F11 in v0.39 (`35989e6`).
  - Added the stale Act 4 HP and passive rows in DESIGN_DOCUMENT.md, and the Abyssal Sacrificer line (:408).

## Summary

_(filled in at /task-done)_
