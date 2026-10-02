---
id: "068"
title: Champion card text and tooltips match the code; drop the Void Ritualist aura; add the missing Act 3–4 tooltips
status: backlog
area: content
priority: normal
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §B, unit B bugs 3 and 4). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

A champion's rules text exists in up to five places, and nothing keeps them in sync:
- the card description (`cards/data/CardDatabase.gd`);
- `CHAMPION_INFO`, the champion-progress hover tooltip (`combat/ui/EnemyHeroPanel.gd:768`);
- `PASSIVE_INFO`, the enemy-passive hover tooltip (`combat/ui/CombatUiStyle.gd:241`);
- the champion tables in `design/master_doc/DESIGN_DOCUMENT.md:783-809`;
- `CARD_LIBRARY.md`, which task 079 deletes.

The handler header comments in `CombatHandlers.gd` are a sixth copy.

### Text that disagrees with the code

| Fight / champion | Code | Wrong text |
|---|---|---|
| F4 Abyss Cultist Patrol | `if total >= 5:` (CombatHandlers.gd:2152) | Card: "Summoned after 4 corruption stacks consumed." (CardDatabase.gd:2876). The tooltip and PASSIVE_INFO already say 5. |
| F5 Void Ritualist | No rune-cost aura. `card_cost` returns `Vector2i(0, inst.effective_cost())` for traps (CombatState.gd:2961-2962). `_champion_vr_summoned` is read only at CombatHandlers.gd:2206 and VoidRitualistProfile.gd:126. | "Rune placement costs 1 less Mana" in the card (CardDatabase.gd:2891), CHAMPION_INFO (EnemyHeroPanel.gd:801), PASSIVE_INFO (CombatUiStyle.gd:264), DESIGN_DOCUMENT.md:794 and the handler comment (CombatHandlers.gd:2197). |
| F7 Rift Stalker | `const _RS_THRESHOLD := 1000` (CombatHandlers.gd:1434) | "1500" in the card (CardDatabase.gd:2923), CHAMPION_INFO (EnemyHeroPanel.gd:820) and the comment at CombatHandlers.gd:1430. |
| F11 Void Warband | `const _VW_THRESHOLD := 2` (:1612). Aura: while the Warband is alive, a dying friendly Spirit gives a random friendly minion 1 Critical Strike (:1659-1677). | Card (CardDatabase.gd:2985) and CHAMPION_INFO (EnemyHeroPanel.gd:848, :850): "3 Spirits", and "When a friendly Spirit with Crit is consumed, summon a 100/100 Void Spark". That is the separate `spirit_resonance` passive (:1615-1627). The comment at :1610 says "Aura: (separate — to be defined)". |
| F1 Rogue Imp Pack | 300 ATK / 400 HP (CardDatabase.gd:2743-2744) | CHAMPION_INFO: `"stats": "200 ATK / 400 HP — SWIFT"` (EnemyHeroPanel.gd:772). |
| F10 Void Scout | Gains 1 Critical Strike on summon (CombatHandlers.gd:1583-1588) | Neither the card (CardDatabase.gd:2970) nor CHAMPION_INFO (EnemyHeroPanel.gd:842) mentions it. The Warband and Captain tooltips do mention theirs. |
| F12 Void Captain | Two independent random picks from the player's minions plus the hero, so one target can be hit twice (CombatManager.gd:431-445) | "deal 100 damage to each of 2 random enemies" (CardDatabase.gd:3000, EnemyHeroPanel.gd:857). Wording only. |
| F6 Corrupted Handler | `if count >= 3:` (CombatHandlers.gd:2237) | Comment :2220: "Summon condition: 4 void sparks summoned." The card text and tooltips say 3. |

Twelve handler comments also promise "On death: deal 20% (of enemy hero) max HP to enemy hero" (CombatHandlers.gd:1432, :1493, :1527, :1565, :2038, :2071, :2084, :2090, :2109, :2142, :2198, :2223). No code does this. `_on_enemy_champion_killed` (:2287-2289) only logs and journals CHAMPION_KILLED, and DESIGN_DOCUMENT.md:771 says "Killing the champion has no built-in HP-damage payoff".

### Missing tooltips

- **No champion tooltip in F13, F14 or F15.** CHAMPION_INFO has no entry for `champion_void_ritualist_prime`, `champion_void_champion` or `champion_abyss_sovereign`. `_setup_champion_progress_tooltip` then returns without building one:
  ```gdscript
  var info: Dictionary = CHAMPION_INFO.get(champ_id, {})
  if info.is_empty():
      return
  ```
  (EnemyHeroPanel.gd:862-864)
- **No passive descriptions from F7 on.** The enemy-passive tooltip falls back to the raw id with an empty description: `info.get("name", pid)` and `info.get("desc", "")` (CombatUiStyle.gd:324-325). 21 of the 34 passive ids in EncounterTable have no entry, all from F7-F15:
  - `void_rift`, `void_empowerment`, `void_detonation_passive`, `void_mastery`
  - `void_might`, `void_precision`, `spirit_resonance`, `captain_orders`
  - `dark_channeling`, `ritualist_spark_free`, `mana_for_spark`, `abyssal_mandate`
  - nine champion ids: `champion_rift_stalker`, `champion_void_aberration`, `champion_void_herald`, `champion_void_scout`, `champion_void_warband`, `champion_void_captain`, `champion_void_ritualist_prime`, `champion_void_champion`, `champion_abyss_sovereign`

  F15's phase 2 adds a 22nd, `abyss_awakened` (PhaseTransition.gd:25).
- **The F15 tooltip keeps phase 1's passives.**
  - The passive icon and its tooltip are built once, at panel setup, from `_scene.state.enemy_passives` (EnemyHeroPanel.gd:184-185 → CombatUiStyle.gd:322).
  - The presenter's PHASE_TRANSITION branch only calls `scene._enemy_hero_panel.update(...)` (CombatPresenter.gd:240-241), and the event has an empty payload (CombatState.gd:2065).
  - So in phase 2 the tooltip still lists `abyssal_mandate` and `dark_channeling`, and never shows `abyss_awakened`.
- Both tables are consts local to a function (`_setup_champion_progress_tooltip`, EnemyHeroPanel.gd:753; `add_enemy_passive_hover_icon`, CombatUiStyle.gd:240), so no test can read them.

### DESIGN_DOCUMENT.md's champion tables

DESIGN_DOCUMENT.md:783-809 copies the stats and effects once more:
- The Act 1-2 rows mostly match the code, apart from the Void Ritualist aura (:794).
- The Act 3-4 rows describe an older design. For example, Rift Stalker is "4 sparks consumed as costs / Spark-cost cards cost 1 fewer spark" (:800), and Void Scout gives "+200 ATK" (:807).
- :809 says "F12–F15 champions not yet implemented".
- The Act 4 passive table (:758-767) is stale too. It says `captain_orders` is "Crit multiplier is 2.5× instead of 2×" (:764). In the code, Throne's Command costs 1 less spark (CombatState.gd:2999), and at the end of the enemy turn each friendly minion with Critical Strike spends one stack to hit the player's hero for its ATK (CombatHandlers.gd:1949-1965). Task 081 (roadmap DL1) rewrites that table and the Act 4 encounter rows (:751-756); this task replaces only the champion tables.

## Decision (owner, 2026-10-01)

- **QN1:** "Code wins; drop the Void Ritualist aura."
  - Fix every card text, CHAMPION_INFO tooltip and PASSIVE_INFO to match the code: Rift Stalker 1000, ACP 5, the Void Warband's 2 Spirits and crit-on-death aura, and RIP's 300/400 stats.
  - Delete the Void Ritualist "rune placement costs 1 less Mana" text everywhere.
  - Balance-neutral.
  - Add the missing tooltips (the F13-F15 champions and the Act 3-4 passives).
- **Q6:** CardDatabase.gd is the source of truth. Task 079 deletes CARD_LIBRARY.md.

After this task the Void Ritualist has no aura. Its text is just "Summoned when ritual sacrifice triggers." Giving it a real aura is a later design call, not part of this task.

## Proposed fix

1. **Card descriptions** (`CardDatabase.gd`). Follow `CARD_DESCRIPTION_STYLE.md` (the `AURA:` label, "Whenever …").
   - ACP: 4 → 5 (:2876).
   - Void Ritualist: drop the AURA line (:2891).
   - Rift Stalker: 1500 → 1000 (:2923).
   - Void Warband: 3 → 2 Spirits, and the aura as the code has it (:2985), e.g. "AURA: Whenever another friendly Spirit dies, give a random friendly minion 1 Critical Strike."
     - "Dies" is exact. A Spirit consumed as spark fuel leaves silently: `_consume_minion` fires only ON_*_SPARK_CONSUMED (CombatState.gd:3063-3082).
   - Void Scout: add "On summon: gains 1 Critical Strike." (:2970).
   - Void Captain: reword the aura to two random hits (:3000).
2. **Move the two tables to class level**: `EnemyHeroPanel.CHAMPION_INFO` and `CombatUiStyle.PASSIVE_INFO`. The functions keep reading them, and tests can now reach them.
3. **CHAMPION_INFO:**
   - RIP stats: 300 ATK.
   - Void Ritualist: aura `""`.
   - Rift Stalker: 1000.
   - Void Warband: condition and aura.
   - Void Scout stats: "— 1 Critical Strike".
   - Void Captain: wording.
   - Add entries for F13-F15, taken from the card and the handler:
     - Void Ritualist Prime (CombatHandlers.gd:1739-1756): 5 enemy spells cast; 2 Critical Strike; friendly spells cost 1 less Mana.
     - Void Champion (:1773-1815): 3 player minions killed by an enemy Critical Strike attack; 3 Critical Strike; +1 max Mana and +1 max Essence at the end of the enemy turn.
     - Avatar of the Abyss (:1834-1871): the player has played 12 cards this fight; it arrives in phase 2 only; 2 Critical Strike; Abyss Awakened grants 2 stacks instead of 1. The count runs across both phases once task 067 lands; until then it restarts at phase 2.
4. **PASSIVE_INFO:** fix the Void Ritualist description and add the 22 entries listed above.
   - Write each from the code: the handler in `CombatHandlers.gd`, its `CombatSetup._REGISTRY` entry, `CombatState.spark_cost_of` / `spell_cost`, and `CombatManager._post_crit`.
   - Don't copy DESIGN_DOCUMENT.md's Act 4 passive table, which is stale (see above).
   - Leave the `champion_duel` entries (EnemyHeroPanel.gd:811, CombatUiStyle.gd:270) alone; task 081 deletes them.
5. **F15 phase-2 tooltip:**
   - `PHASE_TRANSITION` carries `{passives = enemy_passives.duplicate()}`. `PhaseTransition.attempt` has already swapped the list when the event is emitted (CombatState.gd:2055-2065).
   - `add_enemy_passive_hover_icon` takes the passive list as a parameter instead of reading `_scene.state.enemy_passives`.
   - The enemy hero panel keeps a handle to the icon and its tooltip, and the presenter's PHASE_TRANSITION branch rebuilds both from the payload.
   - The panel then reads the journal, not live state, as roadmap §E wants.
6. **Handler comments** (`CombatHandlers.gd`):
   - Rift Stalker :1430 → 1000.
   - Corrupted Handler :2220 → 3.
   - Void Warband :1610 → the real aura.
   - Void Ritualist :2197: delete the aura line.
   - Delete the twelve "On death: deal 20% … max HP" lines. :2071 is also fixed by task 066; whichever lands second skips it.
7. **DESIGN_DOCUMENT.md:**
   - Delete the Void Ritualist aura (:794).
   - Replace the four champion tables (:783-809) with a pointer to the "Enemy Champions" sections of `cards/data/CardDatabase.gd` (the source of truth, Q6). Keep the prose at :771-781.
   - Rewriting the tables by hand would only start the drift again. Task 096 (roadmap B2) phase 3 generates champion text from the spec table.

## Verification

- New probe in `debug/tests/ScenarioTests.gd`, `_enemy_tooltips_cover_every_encounter` (it moves to task 104's ContentTests layer when that exists):
  - For every passive in every `EncounterTable.ENCOUNTERS` entry, plus `PhaseTransition.SOVEREIGN_P2_PASSIVES` (EncounterTable's phase-2 list once task 125 deletes that constant), `CombatUiStyle.PASSIVE_INFO` has an entry with a non-empty `desc`.
  - Every `champion_*` id among them has an `EnemyHeroPanel.CHAMPION_INFO` entry.
- Second probe, `_champion_tooltip_stats_match_cards`: for every CHAMPION_INFO entry, `stats` begins with `"%d ATK / %d HP" % [card.atk, card.health]`, read from `CardDatabase.get_card(id)`. This would have caught the RIP drift. Checking thresholds against the code needs the spec table (task 096).
- `grep -rni "rune placement costs" cards combat enemies design` finds nothing, apart from `design/master_doc/CARD_LIBRARY.md` if task 079 hasn't landed yet.
- Manual (editor):
  - Hover the champion pips in F7, F11, F13, F14 and F15, and the passive icon in F7-F15.
  - After F15's phase change, the passive tooltip lists `void_might`, `abyss_awakened` and `champion_abyss_sovereign`.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1-4, every act whose champion text changes) diffs empty (design/TESTING.md 'Refactor / extraction work'). Only text, tooltips and the PHASE_TRANSITION payload change; no rules code does.

## Related

- Related: task 096 (roadmap B2). It depends on this task. Its phase 3 generates champion card text and tooltips from the spec table, which ends this class of drift.
- Related: task 079. Deletes `CARD_LIBRARY.md`, the copy this task doesn't edit.
- Related: task 081 (roadmap DL1). Deletes `champion_duel`, including its tooltip entries.
- Related: task 104 (roadmap D1). Its ContentTests layer is where the coverage probe ends up.
- Related: task 067. The Avatar counter fix; the Avatar tooltip text assumes it.
- Related: task 066. Champion auras stop when the champion dies; the "AURA:" text already implies that.
- Related: task 071 (roadmap E1b) and task 127 (roadmap H6). Both rework EnemyHeroPanel; step 5 touches the same panel.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from unit B's straight-to-task bugs B-bug3 and B-bug4 (roadmap §B), with owner decision QN1. Re-checked every line at `404b51c`.
  - Added the Void Scout on-summon crit, the Void Captain wording, the stale F15 phase-2 passive tooltip, `abyss_awakened` (22 missing passives, not 21), and DESIGN_DOCUMENT.md's champion tables (a fifth copy of the Void Ritualist aura).
  - Recorded that DESIGN_DOCUMENT.md's Act 4 passive table is stale.

## Summary

_(filled in at /task-done)_
