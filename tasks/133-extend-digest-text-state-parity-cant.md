---
id: "133"
title: Extend digest_text to the state Parity can't see today
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item I5 (`design/refactors/ARCHITECTURE_ROADMAP.md` §I). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

`CombatState.digest_text()` (CombatState.gd:2242-2288) is the one "same game position" check. It is compared by:
- Parity, before every command and at the end (ParityTests.gd:103, :122, :167, :343);
- ScenarioTests' replay probe (:66-88) and the two determinism probes (:123-150);
- CommandTests' refusal check, `_snap` (:61): a refused command must leave the digest unchanged;
- ReplayRunner (:29-30).

It prints: turn number and winner, both HP, both resources, Void Marks / Flesh / Forge / hero armour, hero buffs, each slot as `"%s[%d] %s atk %d hp %d arm %d st %d %s"` (:2258-2261), board order, hand ids, deck and graveyard **sizes**, trap ids, environment ids, relic charges.

Everything else on the state is invisible to those checks. Parity stays green while any of it differs between the live scene and the engine.

### What the digest omits (gameplay state)

- **Per minion** (MinionInstance.gd): `current_shield` (:57), `attack_count` (:99), `kill_stacks` (:49), `aura_tags` (:54), `formation_fired` (:68), `granted_on_death_effects` (:78), `attack_riders` (:90).
- **Turn flow:** `is_player_turn` (:1366) is not printed. Nor are `_pending_player_growth` (:2325), `last_player_growth` (:1764) or `_transition_ends_player_turn` (:2915).
- **Hands:** ids only (:2268-2269). Each card's `mana_delta` / `essence_delta` (CardInstance.gd:25, :29) is missing.
- **Deck and graveyard:** sizes only (:2270-2271). No order, and no `resolved_on_turn` (CardInstance.gd:33), which EffectResolver reads to copy last turn's spells (:380 `if inst.resolved_on_turn != target_turn:`).
- **Costs and counters:** `_player_spell_counter` / `_enemy_spell_counter` (:1736-1737); `player_spell_cost_penalty` (:1717), `enemy_spell_cost_penalty` (:1720), `enemy_spell_cost_aura` (:1723), `enemy_spell_cost_discounts` / `enemy_essence_cost_discounts` (:1724-1725), `enemy_minion_essence_cost_aura` (:1728), `_spell_tax_for_enemy_turn` / `_spell_tax_for_player_turn` (:1713-1714); trap blocks `_enemy_traps_blocked` / `_player_traps_blocked` (:1731, :1733); mana drains (:1742, :1744); `_fiendish_pact_pending` / `_enemy_fiendish_pact_pending` (:1674, :1677); `_relic_hero_immune` / `_relic_cost_reduction` (:1774-1775).
- **Per-turn gates:** `_once_per_turn_used` (:1705), `_soul_rune_fires_this_turn` (:1747), `_imp_caller_fired` (:1749), `_seris_corrupt_used_this_turn` (:1757), `_void_echo_fired_this_turn` (:1853). `_player_spell_damage_bonus` (:1698) should be 0 between commands.
- **Crit / channeling:** `crit_multiplier`, `enemy_crit_multiplier`, `_enemy_crits_consumed`, `_vp_pre_crit_stacks` (:1781-1785); `_dark_channeling_active` / `_dark_channeling_multiplier` (:1792-1793).
- **Setup and encounter:** `player_hero_id` (:1655), `talents` (:1647), `hero_passives` (:1651), `enemy_passives` (:1807), `enemy_profile_id` (:1810), `_sovereign_phase` (:1288), `void_mark_damage_per_stack` / `rune_aura_multiplier` (:1802-1803), the Korrath flags `_armour_doubled_on_knight` (:1857), `_corrupting_presence_active` (:1863), `_path_of_corruption_active` (:1869), and `enemy_limited_cards` (:1401).
- **Champions:** 31 `_champion_*` fields (`grep -c '^var _champion_'`), at :1818-1850 and :1937-1946.
- **Engine RNG position:** `rng.state` (:247). Today a live-only extra draw shows up only once it changes an outcome.

### Why it matters now

Task 129 (roadmap I1), task 131 (roadmap I3), task 083 / 084 (roadmap A1 / A2) and task 097 (roadmap B3) all claim to be behaviour-neutral and prove it with Parity. The fields they move or rewrite (kill credit, crit, Flesh / Forge, champion progress, per-side counters) are mostly the ones above. Without this task, Parity can't see them go wrong.

### What stays out

- **The 33 diagnostic-only counters** (`_vw_*`, `_rift_collapse_*`, `_void_bolt_spell_casts`, `_smoke_veil_*`, …). They aren't gameplay. Task 094 (roadmap B1) moves them off CombatState. The AI-written ones only become replay-stable after task 051: replay applies the command log without running profiles (CombatSim.gd:92-112), so a counter the AI writes stays 0 on replay.
- **The side-channel fields** (`_last_attacker`, `_last_attack_was_crit`, `_pending_dmg_source`, `attack_cancelled`, `_spell_cancelled`, `enemy_play_target`, `_silent_buff_apply`). Task 129 (roadmap I1) deletes them.
- **Object identities:** `CardInstance.instance_id` (a process-wide counter, CardInstance.gd:15-18) and `get_instance_id()` values. The live and engine runs of one Parity case live in the same process, so these always differ. `_champion_rip_attack_ids` holds such ids (CombatHandlers.gd:2046-2049), so print only its size.
- `journal` and `command_log`: Parity compares command records separately. The same goes for task 114's `resolutions` stack and `CombatEvent.cause`: task 114's digest neutrality depends on keeping them out.

## Proposed fix

1. **Per-minion line.** Append `sh %d ac %d ks %d` (`current_shield`, `attack_count`, `kill_stacks`), sorted `aura_tags`, the `attack_riders` source tags in order, `ff` for `formation_fired`, and the `granted_on_death_effects` sources in order.
2. **Turn line.** Add `is_player_turn`, `_pending_player_growth`, `last_player_growth` and `_transition_ends_player_turn` to the first line.
3. **Cards.**
   - Hands: `id` plus `:m<delta>:e<delta>` when either delta is non-zero.
   - Decks: ids in order. If Parity's runtime grows noticeably, print `",".join(ids).hash()` instead.
   - Graveyards: `id@resolved_on_turn` in order.
4. **Counters line(s):** every field in "Costs and counters", "Per-turn gates" and "Crit / channeling" above. Print dictionaries as sorted `key=value` lists, so key order can't make two equal states differ.
5. **Setup line:** every field in "Setup and encounter" above, with arrays sorted except `enemy_passives` (its order is the trigger order).
6. **Champion line:** a `_digest_champions()` helper with an explicit list of the gameplay `_champion_*` fields. Leave out `_champion_ch_aura_dmg`, which is diagnostic and moves in task 094. If task 095 (roadmap B2a) has landed, print its `ChampionTracker`'s state instead; whichever lands second owns that change.
7. **RNG line:** `rng %d` with `rng.state`.
8. Read members explicitly. Lint L4 bans `.get("name")` on objects in rules code, so no loops over `get_property_list()`.
9. **Docs.** In `design/TESTING.md` ("Parity" and "Determinism and seeds"), list what the digest covers and what it leaves out, and why. Note that replay records dumped before this change report `DIVERGED` in ReplayRunner; re-record them.
10. **Triage what the gate finds.** Expect Parity, the replay probe or the CommandTests refusal check to fail somewhere. For each failure:
    - A real engine or live divergence: file it as its own bug task. If it blocks the gate, comment out that one field with `# excluded until task NNN` and land the rest.
    - A test-harness artefact (for example, the engine run and the live run set up the growth pick differently): fix the harness in this task and say so in the work log.

## Verification

- New probe `_digest_sees_hidden_state` in `debug/tests/ScenarioTests.gd`, next to the determinism probes:
  - Build a state with `TestHarness.build_state({})` and one friendly minion, and take `digest_text()`.
  - Change one field at a time, take the digest again, and assert it differs: `kill_stacks += 1`; `aura_tags.append("void_growth")`; `_player_spell_counter = 1`; a hand card's `mana_delta = -1`; swap two graveyard cards; `rng.randi()`; `is_player_turn = not is_player_turn`.
- New probe `_digest_is_identity_free` in the same file: build two states from the same `CombatConfig` and seed. Assert their digests are equal, so no instance id leaks in.
- `tools/run_checks.sh` green. That includes Parity, the replay and determinism probes, and the CommandTests refusal checks, all with the extended digest. Each divergence found is a bug task named in the work log.
- Behaviour-neutral: the digest is read-only and BalanceSimBatch prints no digest. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1–4) diffs empty (design/TESTING.md 'Refactor / extraction work').

## Related

- Depends on: task 051 — moves the AI profiles' state writes (the diagnostic counters and the DefaultProfile in-place hand sort) into the engine or deletes them. After that, a digest divergence on replay is engine behaviour, not an AI-side write that replay never runs.
- Related: task 094 (roadmap B1) — owns the 33 diagnostic counters this digest leaves out.
- Related: task 095 (roadmap B2a) — `ChampionTracker`. Its Related list already expects this task to print the tracker's progress.
- Related: task 129 (roadmap I1) and task 131 (roadmap I3) — lean on Parity for kill credit, crit and iteration order. Land this first if possible.
- Related: task 083 (roadmap A1), task 084 (roadmap A2) and task 097 (roadmap B3) — they keep `digest_text` output byte-identical. If this task lands first, that applies to the extended lines too.
- Related: task 135 (roadmap I8) — the same check on the view side: board slots and ViewState against the engine.
- Related: task 114 (roadmap F1) — adds the resolution stack and `CombatEvent.cause`; neither goes into the digest.
- Related: task 131 (roadmap I3) — once phase b adds `MinionInstance.zone`, add it to the per-minion line.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item I5.
  - Re-check at `404b51c`: confirmed every field the roadmap lists is missing.
  - Also missing: `is_player_turn`, shield, attack count, hand cost deltas, deck order, graveyard turn stamps, setup / encounter fields, per-turn gates and the RNG position.
  - Diagnostic counters, side-channel fields and instance ids stay out, with the reasons above.

## Summary

_(filled in at /task-done)_
