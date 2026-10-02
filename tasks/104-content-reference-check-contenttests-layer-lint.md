---
id: "104"
title: Content-reference check — ContentTests layer + lint L14 for card-id literals and dispatch vocabularies
status: backlog
area: tooling
priority: high
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item D1, with G6 folded in (`design/refactors/ARCHITECTURE_ROADMAP.md` §D and §G). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Content reaches rules and AI code by string: card ids, condition names, multiplier keys, hardcoded ids, registry method names, talent and passive ids, `passive_effect_id`s, minion tags, AI `cast_if` kinds and step-dict keys. Nothing checks these strings at load or in the gate. A typo or a rename fails silently, or only when the card is played.

### How each vocabulary fails today

| Vocabulary | Where it is read | What a typo does |
|---|---|---|
| Step-dict keys | `EffectStep.from_dict` (EffectStep.gd:261-315): 37 `if "x" in d:` checks, no unknown-key branch | The key is dropped; the field keeps its default |
| Step enum values (`type`, `scope`, `filter`, `keyword`, `damage_school`) | `s.effect_type = EffectType[d["type"]]` (:263) | SCRIPT ERROR, but only when that step first resolves. Steps are parsed lazily at 11 sites; nothing parses every card |
| Condition names | ConditionResolver.gd:154-156 `_:` / `push_warning("ConditionResolver: unknown condition '%s'" % cond)` / `return true` | The gated effect always fires |
| `multiplier_key` | EffectResolver.gd:661 `_: base = step.amount` | Scaling silently ignored |
| `hardcoded_id` | `HardcodedEffects.resolve` (:36-70): 13 arms, no `_:` | The step does nothing |
| Registry method names | CombatSetup.gd:642 `tm.register(t["event"], Callable(st._handlers, t["method"]), t["priority"])`; TriggerManager.gd:85 `if entry.handler.is_valid():` | The handler is registered and never fires. `register()` (:52) doesn't check validity |
| Passive / talent ids at setup | CombatSetup.gd:637-638 `if not _REGISTRY.has(id):` / `return` | The passive does nothing |
| `talent_overrides` talent ids | CardDatabase.gd:112-116: an id in no active list is never "active" | The override never applies; no warning |
| `talent_overrides` field names | CardDatabase.gd:146 `push_warning("CardDatabase: talent_override on '%s' references unknown field '%s'"` | Warns only in a fight where that talent is active |
| Card ids in logic | 280 card-id literals in `combat/` (260 outside comments) and 280 in 31 of the 42 `.gd` files under `enemies/ai/`; 214 `.id ==` / `.id !=` comparisons repo-wide | A rename silently kills the rule or AI branch |
| Pool / act-gate keys | CardDatabase.gd:3459 `var _card_pools := {` and :3596 `var _card_act_gates := {` are locals inside `_register_wanderer_cards`, applied by `_card_pools.get(c.id, [])` (:3654) | The card gets no pool and act gate 0. A runtime test can't see the tables |
| AI `cast_if` kinds | `CombatProfile.can_cast_spell` match (:317-357) ends in `_:` / `return true` | The spell is always cast |

Around that:
- The lint checks only registry `"stats"` keys (`scan_setup_stats`, tools/lint/lint_engine.py:224-240).
- `tools/run_checks.sh` fails only on `SCRIPT ERROR` (:46, :60), so `push_warning` / `push_error` lines don't trip it.
- The only load-time content checks are `_validate_spell_damage_schools` (CardDatabase.gd:3670) and the duplicate-id warning in `_register` (:304). Cross-database checks can't run at CardDatabase load anyway: CardDatabase loads before the RelicDatabase, TalentDatabase and HeroDatabase autoloads (project.godot).

### What a prototype found

A read-only prototype of every check below (grooming unit D-lint) found no typo and no dangling id today:
- 246 step dicts (CardDatabase, CardModRules, TalentDatabase, tests): 0 unknown keys or enum values.
- 15 condition names in non-test content (14 match arms plus `once_per_turn:imp_evolution`), all known. 5 multiplier keys, all handled. 13 hardcoded ids, equal to the 13 `resolve` arms.
- Registry: 76 keys, 79 trigger entries, 75 distinct methods, all defined in CombatHandlers.gd.
- 163 `_card_pools` keys and 61 `_card_act_gates` keys, all card ids.
- 0 dangling card-id literals in card-id positions across `combat/`, `enemies/`, relics, talents, heroes, PresetDecks and CardModRules.

So this task is a guard, not a fix. It makes every later rename, migration and new card safe. It also surfaces stale entries that must be fixed or allowlisted first:
- `spirit_conscription` (CombatSetup.gd:481) and `champion_duel` (:496): registry entries that no encounter, talent, hero passive or phase swap applies. Task 081 deletes them.
- `"void_mark_on_void_imp_death":` (CombatHandlers.gd:794): an arm no card's `passive_effect_id` uses. Task 081.
- CombatProfile.gd:366 `if hid in ["brood_call", "void_summoning"]:`. `void_summoning` is no longer a hardcoded id; its steps are SUMMON (CardDatabase.gd:1573-1574). Task 081.
- DefaultPlayerProfile.gd:30 `"void_execution": {"cast_if": "has_friendly_tag", "tag": "human"},`. No card has a `human` minion tag. Task 073 fixes it.
- MatriarchAggroProfile.gd:24 `"arcane_strike": {"cast_if": "can_kill_enemy_minion"},`. Not a supported kind, so it falls to `_: return true` (CombatProfile.gd:356-357). Harmless today only because the profile's own `can_cast_spell` (:28-34) handles arcane_strike before calling super. Fixed here.
- `"echo_rune": 4,` (CardDatabase.gd:3615): an act gate on a card with no pool (`# echo_rune: removed from pool`, :3567). Only CollectionScene's gate column reads it.
- 5 ids that setup applies but the registry lacks: talents `abyss_convergence` and `void_manifestation`, hero passives `void_imp_extra_copy`, `abyssal_commander` and `iron_legion`. GameManager, CardModRules or DeckBuilderScene handle them, so that's legitimate. The check needs them declared (step 4); task 106 then makes `apply_passive` fail loudly.

### Where the checks live

In both places, because each half sees something the other can't:
- **Loaded data → a new RunAllTests layer, `debug/tests/ContentTests.gd`.** Only the running game sees the real cards, overrides, CardModRules, the registry, talents, hero passives and AI profiles. `has_method` is fine there (L4 and L9 don't scan `debug/`).
- **Source text → lint rule L14 in `tools/lint/lint_engine.py`.** Provisional; take the next free number if the landing order differs (L12 is task 051, L13 is task 050). Card-id literals in logic code and the function-local pool tables exist only as text. Python already has `strip_comment` and runs first in the gate.

## Proposed fix

Land after task 081, or allowlist its items with a pointer to it.

### Part 1: ContentTests (loaded data)

1. Add `debug/tests/ContentTests.gd` with `static func run_all()` printing `=== Layer 0: Content ===`. Preload it in RunAllTests.gd and call it first, before `DamageTypeTestsScript.run_all()` (:27). Labels start with `content / ` so `--filter content` works.
2. **Step walk.** For every id in `CardDatabase.get_all_card_ids()` (191 today), walk every step array:
   - MinionCardData's 10 `*_steps` fields, SpellCardData `effect_steps`, TrapCardData's 5, EnvironmentCardData's 4 and each `rituals[].effect_steps`;
   - nested `attack_rider_steps`, recursively (`from_dict` keeps them as raw dicts, EffectStep.gd:303-306);
   - every `*_steps` value inside `talent_overrides` entries;
   - every `append_*_steps` / `set_*_steps` payload in `CardModRules.RULES`;
   - each `TalentData.grand_ritual.effect_steps` (TalentDatabase.gd:175).

   For each step dict:
   - keys ⊆ `EffectStep.DICT_KEYS` (new const, step 9);
   - `type`, `scope` and `filter` are keys of `EffectStep.EffectType`, `TargetScope` and `MinionFilter`; `keyword` is in `Enums.Keyword`; a string `damage_school` is in `Enums.DamageSchool`; `purge_filter` is in `Enums.BuffType`;
   - `card_id` and `exclude_card_id` are card ids;
   - every `conditions` / `bonus_conditions` entry is in `ConditionResolver.KNOWN_CONDITIONS` or matches `once_per_turn:<non-empty>`;
   - `multiplier_key` is `""` or in `EffectResolver.MULTIPLIER_KEYS`; `hardcoded_id` is in `HardcodedEffects.IDS`;
   - `multiplier_tag` is a known minion tag when `multiplier_filter == "tag"`, and a race name when it is `"race"`; `card_tag` is a known tag; `multiplier_board` ∈ {friendly, enemy}; `tutor_filter` ∈ {spark_cost, rune}; `resource`, `convert_from` and `convert_to` ∈ {mana, essence}.
   - no `presence_aura_steps` step is `BUFF_HP`. That is a latent bug: the aura is recomputed by `BuffSystem.remove_source` (drops HP_BONUS without lowering `current_health`, BuffSystem.gd:124-131) and re-applied through `apply_hp_gain` (raises `current_health` again, :116-121; EffectResolver.gd:491), so it would heal on every recompute. Only Rogue Imp Elder (BUFF_ATK) has a presence aura today.

   A failure names the card, the field and the step index. If task 105 (roadmap D2) has landed, its load-time validator already covers keys, enum values and closed-set strings; keep only the id checks here.
3. **Overrides and mod rules.**
   - Every `talent_overrides` `talent_id` is a TalentDatabase talent, a HeroDatabase passive or an EncounterTable passive.
   - Every override field satisfies `field in card`, checked for every override, not only active ones (unlike the warning at CardDatabase.gd:146).
   - In `CardModRules.RULES`: every `when` value is in its namespace (talent, hero passive or enemy passive), every filter tag exists on some card, and every `set_` / `append_` field exists on at least one card the filter matches.
4. **Registry.**
   - For every `CombatSetup._REGISTRY` entry: each event is in `Enums.TriggerEvent.values()`, and `CombatHandlers.new().has_method(method)` holds.
   - Every key is reachable: a talent, a hero passive, an EncounterTable passive or a passive PhaseTransition swaps in.
   - Every id setup applies (talents, hero passives, encounter passives) has a registry entry or is listed in a new `CombatSetup.DATA_ONLY_PASSIVES` const (the 5 ids above, each with a comment naming where it is handled).
5. **Ids.**
   - Every `TalentData.requires` is a talent id. Every `HeroData.talent_branch_ids` entry has at least one talent (9 branches today).
   - Every PresetDecks card id and hero id resolves.
   - Every `MinionCardData.passive_effect_id` is in `CombatHandlers.BOARD_PASSIVE_IDS`, and every `on_spell_cast_passive_effect_id` is in `SPELL_CAST_PASSIVE_IDS` (new consts, step 9; 8 + 1 ids today).
   - Every act-gated card has a pool. This flags `echo_rune`: delete the stale gate (it only changes the Collection's gate column) or allowlist it with a pointer to task 102.
   - Every `champion_*` passive in EncounterTable (and in the phase-2 passive list: PhaseTransition's constant today, EncounterTable's `phase2` after task 125) has a champion card with the same id. All 15 do at `404b51c`; task 096 phase 3 relies on it.
6. **AI rules (roadmap G6).**
   - For each script in `ProfileRegistry.ENEMY` and `ProfileRegistry.PLAYER`, call `script.new()._get_spell_rules()` (21 profiles override it; none reads `agent` there). Keys are spell ids; `cast_if` is in `CombatProfile.CAST_IF_KINDS`; `tag` is a known minion tag; `type` is in `Enums.MinionType`.
   - Every `EncounterTable` `ai_profile` and `variant_profiles` entry passes `ProfileRegistry.has_profile("enemy", id)`. `make()` silently falls back to "default" (ProfileRegistry.gd:58).
   - Fix MatriarchAggroProfile.gd:24: `"cast_if": "always"`, with a comment that the profile's `can_cast_spell` decides. Allowlist DefaultPlayerProfile's `human` with a pointer to task 073 if that hasn't landed.
7. **Source sync.** Read `res://cards/data/CardDatabase.gd` with `FileAccess`, apply L14's id regexes (`^\s*\w+\.id\s*=\s*"([^"]+)"` and `\{"id":\s*"([^"]+)"`) and assert the result equals `get_all_card_ids()` (183 + 8 = 191 today). The lint's id set then can't drift from the runtime.
8. **Fold-ins.** Task 068's `_enemy_tooltips_cover_every_encounter` and `_champion_tooltip_stats_match_cards` probes move into this layer (every encounter passive has a `PASSIVE_INFO` entry, every champion a `CHAMPION_INFO` entry, and the tooltip stats match the card's ATK / HP). Task 047's enemy-deck checks (deck and `limited` card ids, deck `ai_profile`s, the F15 phase-2 deck) belong here too, if this layer exists when 047 lands.

### Part 2: vocabulary consts and lint L14 (source text)

9. Add inert consts next to each string dispatch. No behaviour change.
   - `ConditionResolver.KNOWN_CONDITIONS` (33 names).
   - `EffectResolver.MULTIPLIER_KEYS` (`rune_aura`, `void_marks`, `flesh_spent`, `board_count`, `armour_sum`).
   - `HardcodedEffects.IDS` (13).
   - `CombatHandlers.BOARD_PASSIVE_IDS` and `SPELL_CAST_PASSIVE_IDS`.
   - `CombatProfile.CAST_IF_KINDS` (9: `has_friendly_tag`, `has_friendly_type`, `board_not_full`, `opponent_has_rune_or_env`, `board_full_or_no_minions_in_hand`, `before_attacks`, `has_3_feral_imps`, `always`, `never`). Also fix the header list (CombatProfile.gd:25-29), which names only 4.
   - `EffectStep.DICT_KEYS` (37).
10. Lint L14:
    - **(a) Consts match their dispatch.** Each const equals the string arms (`"x":` lines inside the named function's `match`, at whatever indentation) of its dispatch: `ConditionResolver.check`, `EffectResolver._amount`, `HardcodedEffects.resolve`, the CombatHandlers passive dispatchers (`_apply_spell_cast_passive` :109, `_apply_board_passive_on_summon` :609, `_apply_board_passive_on_death` :785, and the `match pid:` in `on_player_minion_sacrificed_board_passives` :747-758) and `CombatProfile.can_cast_spell`. `BOARD_PASSIVE_IDS` also covers the ids compared directly: every `passive_effect_id == "x"` literal (CombatHandlers.gd:683, :1413, CombatManager.gd:390, RiftStalkerProfile.gd:72, :296, :320) must be in it. `DICT_KEYS` equals `from_dict`'s `if "x" in d` keys.
    - **(b) Card-id literals in card-id positions resolve.** Scan, comment-stripped: `combat/`, `enemies/` (G6), `relics/`, `talents/`, `heroes/`, `sim/`, `shared/`, `ui/`, `rewards/`, `shop/`, `cards/data/PresetDecks.gd` and `cards/data/CardModRules.gd`. Positions:
      - `\.id\s*(==|!=)\s*"x"` and `"x"\s*(==|!=)\s*<expr>\.id`;
      - the first argument of `get_card(`, `get_card_for_combat(` and `_summon_token(`, and `_card_for(<side>, "x")`;
      - `"card_id": "x"` and `"exclude_card_id": "x"`;
      - `_by_id([...])`;
      - the arms of a `match` whose subject is `<expr>.id` or `card_id` (this covers CardVfxRegistry's tables), except `HardcodedEffects.resolve`;
      - arrays whose string members are at least 50% card ids.

      Match the member `.id`, not a bare `id`, so `GameManager.gd:224` (a talent id) and `CombatSetup.gd:621` (a passive id) don't false-positive.
    - **(c) Pool tables.** `_card_pools` and `_card_act_gates` keys in CardDatabase.gd are card ids. Task 102 (roadmap C3) moves pools and gates onto the cards; drop this sub-check then.
11. Docs: design/TESTING.md gets the Content layer (layer table, the quick-reference row at :25) and the L14 row in the lint table. ARCHITECTURE.md's test-suite rows list ContentTests.

## Verification

- `tools/run_checks.sh` green: lint 0 errors including L14, and RunAllTests with the new content layer.
- Expected counts today (from the prototype): 246 step dicts, 0 unknown keys or values; 15 condition names, all known; 5 multiplier keys; 13 of 13 hardcoded ids; 75 of 75 registry methods; 7 override talent ids; 163 + 61 pool and act-gate keys; 0 dangling card-id literals. The allowlist is empty once tasks 081 and 073 have landed.
- Mutation checks, done locally and reverted; record what each printed in the task summary:
  1. `"flesh_spent_this_cast"` → `"flesh_spent_this_cst"` in one CardDatabase step: ContentTests fails and names the card and step.
  2. `"amount"` → `"amout"` in one step: fails on the unknown key.
  3. A registry `"method"` misspelled in CombatSetup: fails on `has_method`.
  4. `"feral_surge"` → `"feral_surg"` in `FeralPackProfile._get_spell_rules`: ContentTests fails, and so does L14.
  5. `"card_id": "void_spark"` → `"void_sprak"`: fails.
  6. A misspelled key in `_card_pools`: L14 fails.
  7. A new arm in ConditionResolver without updating `KNOWN_CONDITIONS`: L14 fails.
  8. One `.id == "void_imp"` in `combat/` changed to `"void_imps"`: L14 fails.
- Behaviour-neutral: test code, lint code and inert consts, plus the MatriarchAggro rule row that its own `can_cast_spell` shadows. The seeded balance fingerprint (`BalanceSimBatch -- --act 1 --runs 200 --seed 7`, before and after; MatriarchAggro plays F3) diffs empty (design/TESTING.md 'Refactor / extraction work').

## Related

- Depends on: task 081 (roadmap DL1) — deletes the unreachable registry entries, the dead passive arm and the stale AI hardcoded-id literal that the reachability and id checks flag; landing it first keeps the allowlist empty.
- Related: task 073 — fixes DefaultPlayerProfile's `human` tag. Whichever lands second removes the allowlist entry.
- Related: task 105 (roadmap D2) — its load-time step validator takes over this task's step-shape checks (keys, enum values, closed-set strings); the id and cross-database checks stay here.
- Related: task 106 (roadmap D3) — depends on this task. It uses the vocabulary consts and `DATA_ONLY_PASSIVES` to fail loudly at runtime.
- Related: task 108 (roadmap D7) — replaces `KNOWN_CONDITIONS` with its declared condition table; L14's const-vs-arms check follows the table.
- Related: task 089 (roadmap A8) and task 096 (roadmap B2) — both depend on this task. A8 retires `passive_effect_id`, which removes `BOARD_PASSIVE_IDS`. B2 adds spec-table checks here (every spec card id exists; every champion passive has a spec row).
- Related: task 062 — deletes the board-passive ids `void_spark_on_friendly_death`, `deal_200_hero_on_friendly_death`, `soul_taskmaster_gain_atk` and `void_mark_on_void_imp_death`. If 062 lands first, leave them out of `BOARD_PASSIVE_IDS`; if this task lands first, 062 removes them.
- Related: task 125 (roadmap H3) — once it lands, step 4's "a passive PhaseTransition swaps in" reads EncounterTable's phase-2 passive lists, not PhaseTransition constants.
- Related: task 047 — its enemy-deck checks can live in this layer.
- Related: task 068 — its tooltip-coverage probe moves into this layer.
- Related: task 100 (roadmap C1) — its structural pool checks can join this layer.
- Related: task 102 (roadmap C3) — moves pools and act gates onto the cards; L14 (c) goes away then. It also moves the card blocks into `cards/data/pools/*.gd`: add those files to L14 (b)'s scan and to step 7's source sync. Its permanent card-count / feral-order probe can live in this layer.
- Related: task 120 (roadmap G4) — deletes the scored profiles; the `variant_profiles` check catches a leftover `scored_*` id in EncounterTable.
- Related: task 142 (roadmap J6) — the card-id check for the VFX registries is L14's `match card_id:` position today. After 142's phases a and b those ids are Dictionary keys (`CardVfxRegistry.token_summon_for`'s table, VfxController's spell table), so L14 (b) must also cover those keys, or this layer checks them at runtime.
- Related: task 137 (roadmap J1) — test-registration lint; until it lands, ContentTests is registered in RunAllTests by hand.
- Related: task 140 (roadmap J4) — hardens `strip_comment` (escaped quotes), which L14 relies on.
- Related: task 051 (L12) and task 050 (L13) — lint numbering.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap items D1 and G6.
  - Counts re-checked: 280 card-id literals in 31 of the 42 `enemies/ai/` files (roadmap: ~275 across 33); 178 `.id ==` comparisons, 214 with `!=` (roadmap: ~217).
  - Added the AI checks from the G unit (`cast_if` kinds, `variant_profiles`) and the stale `echo_rune` gate.
  - Lint rule renumbered L14 (the unit report's L13 now belongs to task 050).

## Summary

_(filled in at /task-done)_
