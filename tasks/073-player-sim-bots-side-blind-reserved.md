---
id: "073"
title: Player sim bots — side-blind reserved champion slot, and a Void Execution rule that checks a tag no card has
status: backlog
area: ai
priority: normal
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §G and §D). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Two bugs in the player-side AI bots, the sim's stand-ins for the human player (`ProfileRegistry.PLAYER`, ProfileRegistry.gd:41-50). No shipped play path runs a player profile. The sim, BalanceSimBatch, Parity, LiveSmoke and the debug sims do. Only bug 1 moves BalanceSimBatch numbers.

### Bug 1: player bots keep a board slot free for the enemy's champion

`CombatProfile._reserved_slots()` reads the enemy's encounter config whatever side the agent plays:

```
func _reserved_slots() -> int:                        # CombatProfile.gd:548
	# Default: reserve 1 slot if champion hasn't been summoned yet
	if agent.state._champion_summon_count > 0:
		return 0
	# Check if this encounter even has a champion passive
	for p: String in agent.state.enemy_passives:
		if p.begins_with("champion_"):
			return 1
	return 0
```

- All 15 encounters carry a `champion_*` passive (EncounterTable.gd:16-142). The sim copies them into `enemy_passives` (CombatConfig.gd:85).
- `_champion_summon_count` counts enemy champions only (`st._champion_summon_count += 1` in `_summon_enemy_champion`, CombatHandlers.gd:2280).
- So a player bot gets 1 back from `_reserved_slots()` until the enemy's champion arrives, and in a fight where it never arrives, for the whole fight.

What that blocks:
- `_play_minions_pass` stops at 4 of 5 slots (`BOARD_MAX := 5`, CombatState.gd:10): CombatProfile.gd:568 `var reserved: int = _reserved_slots()`, `:581-582` `if agent.empty_slot_count() <= reserved:` / `return  # keep slots reserved`.
- Summon spells are held at one free slot: `can_cast_spell` (CombatProfile.gd:305) and the relief pass (:535).

Affected player profiles: `default`, `swarm`, `spell_burn`, `rune_tempo` and `korrath` (they inherit the base method).
- `seris` and `fleshcraft` override it (SerisPlayerProfile.gd:79-81). Their comment says what the base should do: `## Note: player profiles (unlike enemy profiles) don't reserve slots for champions,`.
- `swarm` is hit only partly. Its `_play_minions_by_id` (SwarmPlayerProfile.gd:204-224) places Void Imps and Shadow Hounds without a reservation. Stalker, Brute and Spawner go through `_play_minions_pass` (:51, :63) and stop at 4.

Consequences:
- BalanceSimBatch: 3 of its 6 presets use these bots. `swarm` → `swarm`, `voidbolt_burst` → `spell_burn`, `death_circle` → `rune_tempo` (BalanceSimBatch.gd:22-55). Their rows are skewed in every act, most likely understated (one slot fewer for minions until the enemy champion arrives).
- Parity cases F1 swarm, F2 voidbolt, F3 death_circle, F13 swarm and F15 swarm (ParityTests.gd:32-50), LiveSmoke's AI-vs-AI fight (`default`, LiveSmokeTests.gd:209) and the ScenarioTests replay / determinism fights (`default`) all play the reduced bot. They compare within one run, so they stay green.

### Bug 2: the default bot never casts Void Execution

- `DefaultPlayerProfile.gd:30` `"void_execution": {"cast_if": "has_friendly_tag", "tag": "human"},`. The header states the intent: `## Spell rules  — void_execution: only if a Human is on the friendly board.` (:6).
- The `has_friendly_tag` arm tests `tag in (m.card_data as MinionCardData).minion_tags` (CombatProfile.gd:318-324).
- No card has a `human` minion tag. Tags are card-family ids (`feral_imp`, `void_imp`, `order_footman`, `enemy_champion`, …). Humans are `minion_type` HUMAN, e.g. `abyss_cultist.minion_type = Enums.MinionType.HUMAN` (CardDatabase.gd:1928).
- So the rule is always false, and the `default` bot never casts Void Execution, even with a Human on board. The card deals 500, or 700 with a friendly Human (CardDatabase.gd:1584, `bonus_conditions: ["has_friendly_human"]` at :1588).
- The right arm already exists: `"has_friendly_type"` (CombatProfile.gd:325-332). VoidRitualistProfile.gd:45 and CorruptedHandlerProfile.gd:50 use it for Dark Command with `"type": "HUMAN"`.

Reach:
- The `default` player profile runs in BalanceSim.gd (option at :42, default at :95), SimRunner (`"player_profile":   "default"`, :100), LiveSmoke (:209), ScenarioTests replays and CommandTests `_profile_play_pays_once` (:705).
- Only the two debug sims can pair it with a Void Execution deck (e.g. `voidbolt_burst`, PresetDecks.gd:39). The tests all use the `swarm` deck.
- BalanceSimBatch never runs `default`: its presets map to `swarm`, `spell_burn`, `rune_tempo`, `fleshcraft` and `seris` (BalanceSimBatch.gd:22-90). `spell_burn` has its own Void Execution rule (SpellBurnPlayerProfile.gd:224). So this fix is BalanceSimBatch-neutral.

## Decision (owner, 2026-10-01)

Q1 and Q2: PvP is planned, and no mechanic is one-sided by design. "Who has what is decided by data and config, never by `if owner == "player"` in rules code." The AI's view of a side follows the same rule. So the fix doesn't hard-code "player bots never reserve". A side reserves a slot for its own champion, read from its own side's config. Today only the enemy side has one.

## Proposed fix

Bug 2 first, as its own commit (balance-neutral):
1. `DefaultPlayerProfile.gd:30` → `"void_execution": {"cast_if": "has_friendly_type", "type": "HUMAN"},`.

Bug 1, second commit:
2. Add `has_pending_champion() -> bool` to `CombatAgent` (base: `false`), implemented in `StateAgent`: true when this side has a `champion_*` passive and its champion hasn't been summoned.
   - Today only the enemy side has champion passives (`enemy_passives`) and a summon count (`_champion_summon_count`). StateAgent maps the side the way `_get_friendly_hp` already does (StateAgent.gd:34), so the side literal lives in the agent, not in a profile.
   - It returns false for the player side until per-side champion state exists.
3. `CombatProfile._reserved_slots()` → `return 1 if agent.has_pending_champion() else 0`. The enemy side behaves exactly as before.
4. Reword the SerisPlayerProfile comment (:79-80). The base no longer reserves for the other side's champion, so it is true by construction.
5. Task 122 (roadmap G7) folds `has_pending_champion` into its side-aware agent API (`passive_with_prefix("champion_")`).

## Verification

New probes in `debug/tests/CommandTests.gd`, next to the "agents /" probes (:695+):
- **Void Execution rule.** `ProfileRegistry.make("player", "default")` with `setup(TestHarness.agent_for(state, "player"))`, and `var ve := CardDatabase.get_card("void_execution") as SpellCardData`.
  - `can_cast_spell(ve) == false` on an empty board, and with only a Demon (e.g. `void_imp`).
  - After `TestHarness.spawn_friendly(state, "abyss_cultist")` it is `true`. Fails before.
- **Reserved slot, unit.** `build_state({"enemy_passives": ["champion_rogue_imp_pack"]})`.
  - A `swarm` profile on the player agent: `_reserved_slots() == 0` (1 before the fix).
  - A profile that keeps the base method on the enemy agent (e.g. `feral_pack`): 1. After `state._champion_summon_count = 1`: 0.
- **Reserved slot, play.** Same state, player profile `swarm`, 4 player minions, hand [`abyssal_brute`] (not a Void Imp or Shadow Hound, which bypass the reservation), Essence 4. After `play_phase()` the player board has 5 minions (4 before the fix).

Gate:
- `tools/run_checks.sh` green. Parity stays green; its F1 / F2 / F3 / F13 / F15 cases now play different fights.
- Commit 1 (bug 2) is behaviour-neutral for BalanceSimBatch, which never runs the `default` player profile. Show it: the seeded fingerprint `BalanceSimBatch -- --act 1 --runs 200 --seed 7` diffs empty before and after (design/TESTING.md "Refactor / extraction work").
- Commit 2 (bug 1) is a behaviour change. Record the BalanceSimBatch delta in the task summary for `--act 1`, `--act 2`, `--act 3` and `--act 4` (`--runs 200 --seed 7`, before and after). Expect the Swarm, Voidbolt and DeathCircle rows to move, and the S.Flesh / S.Forge / S.Corr rows to stay byte-identical.

## Related

- Related: task 122 (roadmap G7) — depends on this task; its side-aware CombatAgent API absorbs `has_pending_champion` (without this fix, routing `_reserved_slots` through the side-aware agent would change the player bots' behaviour).
- Related: task 095 (roadmap B2a) — consolidates the champions' state, including `_champion_summon_count`.
- Related: task 104 (roadmap D1) — the content check validates `_get_spell_rules` keys, `cast_if` values and tags. Its prototype allowlisted this `human` tag; whichever task lands second removes the allowlist entry.
- Related: task 141 (roadmap J5) — retires VoidboltDmgDebug, ScoredAITest and DebugF13LossAnalysis, and keeps BalanceSim.gd and SimRunner, the only paths that pair `default` with a Void Execution deck.
- Related: task 072 — the same roadmap §G re-check; it fixes the enemy-side boss AI.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap §G bug BUG-G-3 and the §D content-check bug (unit D-lint, bug 1).
  - Re-check: the Void Execution fix doesn't move BalanceSimBatch (no preset runs `default`). Only bug 1 skews its baselines.
  - Swarm is hit only partly (imps and hounds bypass the reservation).
  - The fix keeps the reservation for a side's own champion instead of exempting the player side (owner Q1/Q2).

## Summary

_(filled in at /task-done)_
