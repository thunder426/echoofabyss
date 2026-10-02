---
id: "058"
title: Imp Talisman (and three latent sites) bypass _card_for: Vael gets an un-boosted Void Imp
status: backlog
area: combat
priority: high
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §I, item 7; unit I, candidate I7b). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

`CombatState._card_for(side, id)` (CombatState.gd:228-229) is how rules code builds a card mid-fight. It calls `CardDatabase.get_card_for_combat` with that side's talents, hero passives and enemy passives, so the card's `talent_overrides` and the `CardModRules` deltas apply. Its comment (:221-224) says to use it "whenever combat code constructs new CardInstances mid-fight". Deck setup does (`setup_deck`, :1548), and so does ADD_CARD (EffectResolver.gd:72-73: `# _card_for so clan rules / overrides apply to the added copy.`).

Four rules-code sites call `CardDatabase.get_card(` instead, which returns the base card.

### Reachable today: Imp Talisman

- Imp Talisman is an Act-1 relic: "Add a Void Imp to your hand." (RelicDatabase.gd:71-73).
- `RelicEffects.resolve("relic_add_void_imp")` (RelicEffects.gd:22-27):
  ```gdscript
  var imp_data: CardData = CardDatabase.get_card("void_imp")
  if imp_data:
      state.add_to_hand("player", imp_data)
  ```
  `add_to_hand` wraps the base card as is (CombatState.gd:1585-1595), and `_cmd_play_minion` plays `inst.card_data` unchanged (:2553).
- For Lord Vael, the Talisman's imp misses:
  - the hero passive `void_imp_boost`, +100/+100 to the Void Imp clan (CardModRules.gd:50-56). It is 100/100 instead of 200/200;
  - every Void Imp clan talent: `swarm_discipline` +100 HP (:59-64), `death_bolt`'s on-death Void Bolt (:71-79), the `piercing_void` override (CardDatabase.gd:330-341: 1E+1M, "Deal 200 Void Bolt damage to enemy hero and apply 1 VOID MARK"), and the rest of the `void_imp`-tagged rules.
- The hand card shows the base text, so the player sees a plain 100/100 Void Imp next to their 200/200 deck copies.
- The sim activates the Talisman at turn start (SimRelicPolicy.gd:15). BalanceSimBatch runs it in Acts 2–4 (`_ACT_RELICS`, BalanceSimBatch.gd:99-120).
- Seris and Korrath see no difference today: no override or rule applies to their `void_imp`.

### Latent (nothing overrides these cards today)

- `CombatState._korrath_place_random_rune` (:1898-1899), Korrath's Runeforge Strike: `var rune: TrapCardData = CardDatabase.get_card(rune_id) as TrapCardData`.
- `RelicEffects._relic_place_random_rune` (:120-122), Oblivion Seal: `var rune_card: CardData = CardDatabase.get_card(rune_id)`.
- `CombatHandlers.on_enemy_summon_feral_reinforcement` (:1143-1151): builds its pool with `CardDatabase.get_card(id)`, then `state.add_to_hand("enemy", chosen)`. An enemy-passive rule on feral imps would be skipped.

No rune has `talent_overrides`, and `CardModRules` only matches minions. `get_card_for_combat` returns the base object when nothing applies (CardDatabase.gd:125-126). So switching the rune sites changes nothing today; it only stops the next override from being skipped.

### Not in scope

- `CombatHandlers.gd:2282` uses `CardDatabase.get_card(card_id).card_name` for a log line only. Switch it as well so the lint below needs no exception.
- `CombatScene.gd:1061`, `:1069` pre-place traps for the TestLaunchScene debug path. That isn't rules code; task 050 owns trap placement.
- `BoardEvaluator.gd:218` estimates a summon's value from base stats. That's AI scoring; see task 120 (roadmap G4) and task 122 (roadmap G7).

## Proposed fix

1. `RelicEffects.gd:23` → `state._card_for("player", "void_imp")`. Task 091 (roadmap PS-relics) later replaces `"player"` with the relic owner's side.
2. `CombatState.gd:1899` → `_card_for("player", rune_id) as TrapCardData`.
3. `RelicEffects.gd:122` → `state._card_for("player", rune_id)`.
4. `CombatHandlers.gd:1143-1151`: keep the base-card filter, so the pool and its `rng_pick` are unchanged, then add `state._card_for("enemy", chosen.id)` to the hand. The VFX payload and the log use the resolved card.
5. `CombatHandlers.gd:2282` → `state._card_for("enemy", card_id).card_name`.
6. **Lint rule:** no `CardDatabase.get_card(` in RULES_FILES (tools/lint/lint_engine.py:91-104). The message: "use state._card_for(side, id)". Take the next free number at landing; L12–L19 are spoken for by tasks 051, 050, 104, 137, 087, 111, 122 and 099, and task 131 (roadmap I3) holds L20 for its board-loop snapshot rule (all provisional), so this rule is L21 unless the landing order differs. Name the rule in the `_card_for` comment (:221-224).

## Verification

- New probe in `debug/tests/TriggerHandlerTests.gd`, next to the `_relic_*` probes (:524):
  - Setup: `TestHarness.vael_state(["swarm_discipline"])`; `var fx := RelicEffects.new()`; `fx.setup(state)`; `fx.resolve("relic_add_void_imp")`.
  - Assert the added card (`state.player_hand.back().card_data as MinionCardData`) has `atk == 200` and `health == 300`: base 100/100, +100/+100 from `void_imp_boost`, +100 HP from `swarm_discipline`. Today it is 100/100.
- Second case: `TestHarness.vael_state(["piercing_void"])` → the added card has `mana_cost == 1` (the override's cost).
- Lint: add a `CardDatabase.get_card(` line to a RULES_FILES file once by hand and confirm `tools/run_checks.sh` fails, then remove it.
- `tools/run_checks.sh` green.
- Behaviour change: record the BalanceSimBatch delta in the task summary. Run Acts 2, 3 and 4 (request 3–4 explicitly; BalanceSimBatch defaults to Acts 1–2). Only Vael rows with an Imp Talisman (`IT`) relic combo should move; Seris rows should be identical.

## Related

- Related: task 091 (roadmap PS-relics) — relics for either side; the `"player"` literal in `RelicEffects` becomes the owner's side there.
- Related: task 050 — owns trap placement and removal (`place_trap` / `remove_trap`). It edits lines next to steps 2–3 (`_korrath_place_random_rune` :1896-1897, `RelicEffects` :120-138); whichever lands second rebases.
- Related: task 098 (roadmap B4) — moves `_korrath_place_random_rune` into the Korrath module.
- Related: task 104 (roadmap D1) — the sibling content guard (L14, provisional: card-id literals and dispatch vocabularies).
- Related: task 087 (roadmap A4, lint L16) — steps 1–5 add `_card_for("player", …)` / `_card_for("enemy", …)` literals (RelicEffects.gd:23, :122; CombatState.gd:1899; CombatHandlers.gd:1151, :2282). If 087 lands first, raise its baseline for them in this commit.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item I7 (unit I candidate I7b / straight-to-task bug 2). Re-checked all four sites at `404b51c`, and confirmed the Talisman is the only reachable one: no override or mod rule matches runes or feral imps today. Added the log-name site to the fix so the lint needs no allowlist.

## Summary

_(filled in at /task-done)_
