---
id: "083"
title: Side constants + SideState, part 1: hand, deck, graveyard, essence/mana behind state.side(s)
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item A1 (`design/refactors/ARCHITECTURE_ROADMAP.md` §A). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Sides are the strings `"player"` / `"enemy"`. Every per-side value is a pair of CombatState fields, and each accessor picks one with a ternary. This task is the first of three that put per-side state on one `SideState` object per side: hand, deck, graveyard and the four resource values. Task 084 moves traps, environment, board, slots and hero; task 085 moves the per-turn counters and cost modifiers.

### The fields

CombatState.gd:1368-1401 holds seven pairs plus one enemy-only list:
- `player_essence` / `enemy_essence`, `player_mana` / `enemy_mana`;
- `player_essence_max` / `enemy_essence_max`, `player_mana_max` / `enemy_mana_max`. The two player max fields are setter properties that record the growth choice for F15 Abyssal Mandate (:1371-1384, `last_player_growth = "essence"`);
- `player_deck` / `enemy_deck`, `player_hand` / `enemy_hand`, `player_graveyard` / `enemy_graveyard`;
- `enemy_limited_cards` (:1401), the ids the enemy draws once per copy.

### The accessors

Every accessor is a ternary on the side string (CombatState.gd:1410-1454):

```gdscript
func hand_of(side: String) -> Array[CardInstance]:
	return player_hand if side == "player" else enemy_hand
```

The same shape repeats in `deck_of`, `graveyard_of`, `essence_of`, `mana_of`, `essence_max_of`, `mana_max_of`, `set_essence` and `set_mana`, and as `if side == "player"` branches in `grow_essence_max` (:1498) and `grow_mana_max` (:1508).

### Deck rules are side branches, not data

- `draw_cards` (:1559-1580) branches on `if side == "player":` (:1561). The player's deck is finite and a draw into a full hand burns the card (:1565-1566). The enemy's draw stops at a full hand (:1572), and each drawn card goes back into the deck as a fresh copy, then the deck is reshuffled (:1576-1578), unless its id is in `enemy_limited_cards`.
- `setup_deck` (:1552-1553): `if side == "enemy": draw_cards("enemy", 5)`. PhaseTransition.gd:70 calls `setup_deck("enemy", …)` mid-fight for F15 phase 2, so the opening draw belongs to `setup_deck`. The player's opening 3 are drawn by `setup_combat` (:2356).
- `add_to_hand` (:1593-1594) and `draw_cards` fire `_fire_card_drawn` for the player only (`EventContext.make(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, "player")`, :1600). Firing it for the enemy is task 086's.

The owner ruled that no mechanic is one-sided by design (Q2). The draw model is a real per-side difference today, so it should be per-side configuration, not an `if side == "player"`.

### How much code reads the fields

Raw references to the 14 paired fields (comments stripped; inside CombatState the bare name, elsewhere through a `state.` / `st.` / `_state.` / `ctx.state.` receiver; `enemy_limited_cards` adds 7 more):
- CombatState: 71.
- Tests and debug: 130 (TriggerHandlerTests 42, CommandTests 32, CardEffectTests 23, LiveSmokeTests 14, TestHarness 10, DebugF13LossAnalysis 7, ParityTests 2).
- Presentation: PipBar 12, CombatScene 10, CombatUI 10, ViewState 8, EnemyHeroPanel 5, CombatInputHandler 4, CheatPanel 2.
- Sim and AI: SimRelicPolicy 6, RuneTempoPlayerProfile 5, DefaultPlayerProfile 2, CombatSim 1.
- Rules: EffectResolver 3 (one is the direct write `st.enemy_essence = mini(…)` in GRANT_ESSENCE, :136), RelicEffects 3, CombatHandlers 1.

Accessor calls today: `hand_of` 17, `deck_of` 2, `graveyard_of` 3, `essence_of` 9, `set_essence` 7, `mana_of` 13, `set_mana` 7, `essence_max_of` 31, `mana_max_of` 33.

Some non-CombatState code assigns the int fields directly, e.g. the TestConfig path in CombatScene.gd:1077-1092 (`state.player_essence_max = TestConfig.start_essence_max`). No code reassigns a whole hand, deck or graveyard array on the state: the only `enemy_deck =` hits are on other objects (TestConfig.gd:76, BalanceSim.gd:600/:603).

### Consequence

Every new per-side resource or deck rule costs another field pair and another ternary, and the side branches hide which rules differ by side. The hero modules (tasks 097, 098) and per-side talents (task 090) have nowhere to hang per-side data. Lint L16's side-literal count (task 087) can't fall much without this.

### Why string constants, not an int enum

The roadmap's direction 1 proposes `enum Side { PLAYER, ENEMY }`. Grooming deferred that (A7):
- The strings are not confined to boundaries. They are the runtime type of `EventContext.owner`, `EffectContext.owner`, `MinionInstance.owner`, `SlotState.side`, `HeroState.side`, `CombatEvent.side`, every engine signal, the presentation and the AI. There are 1090 literal occurrences repo-wide and about 240 `side` / `owner: String` declarations.
- `command_log`, `digest_text` and the replay JSON carry the strings.
- A bare `Side` name clashes with Godot's global `Side` enum (`SIDE_LEFT`, …).

String constants on a `CombatSide` class keep every payload byte-identical.

## Proposed fix

1. **`combat/board/CombatSide.gd`.** `class_name CombatSide`, `const PLAYER := "player"`, `const ENEMY := "enemy"`, `const BOTH: Array[String] = [PLAYER, ENEMY]`, `static func opponent(s: String) -> String`. `CombatState._opponent_of` (:166-167) forwards to it. Don't respell existing literals in this task; new code uses the constants.
2. **`combat/board/SideState.gd`** (RefCounted, with no reference back to CombatState, so task 049's teardown gains no cycle). Fields:
   - `side: String`;
   - `hand`, `deck`, `graveyard: Array[CardInstance]`;
   - `essence`, `essence_max`, `mana`, `mana_max: int`;
   - deck rules: `regenerating_deck: bool` (enemy true), `burn_on_full_hand: bool` (player true), `opening_draw: int` (enemy 5, player 0; the player's 3 stay in `setup_combat`), `limited_cards: Array[String]` (from `enemy_limited_cards`).
3. **Deck rules come from config.** `CombatConfig` gains per-side deck-rule fields whose defaults are today's values, and `from_dict` falls back to the defaults, so old replay records build the same fight. `setup_combat` copies them onto each `SideState`. This is what lets a PvP or mirror match give both sides a finite deck later without an `if`.
4. **CombatState.** Build the two SideStates in `_init` (next to `_alloc_slots`, :1308-1309). Add `func side(s: String) -> SideState` and `func opponent_side(s: String) -> SideState`. Keep today's fallback (anything other than `"player"` is the enemy) so behaviour is unchanged, but `push_error` on a value outside `CombatSide.BOTH` so a bad side shows in the gate output. Take a side string, not a ctx: a `me(ctx)` helper taking an untyped context would be duck typing (lint L4).
5. **Legacy names become forwarders.**
   - The 6 arrays: getter-only properties onto `side(s).hand` etc. Getter-only makes a future whole-array reassignment a compile error instead of a silent desync.
   - The 8 ints: get/set properties. Keep the `player_essence_max` / `player_mana_max` setter hook that records `last_player_growth` (:1371-1384); task 085 moves that record per side.
   - `enemy_limited_cards` forwards to `side("enemy").limited_cards`.
6. **Rewrite the accessors and growth** (:1410-1454, :1494-1511) as `side(s).x`, with no ternary.
7. **Rewrite `setup_deck`, `draw_cards` and `add_to_hand`** (:1542-1595) to read the deck rules instead of `if side == "player"`.
   - Keep the RNG call order exactly: `rng_shuffle(deck)` after each regenerating draw, and the shuffle in `setup_deck` before the opening draw.
   - Keep the journal order: the `card_drawn` signal, then the CARD_DRAWN event, per card.
   - Keep the card-drawn trigger player-only for now (one explicit `if side == "player"` around `_fire_card_drawn`, with `# lint: allow-side (task 086)` if task 087 has landed). Task 086 phase P2c fires it for both sides.
8. **Leave the readers outside CombatState on the forwarders.** Changing them here is churn that other tasks redo:
   - presentation reads (PipBar, CombatUI, CombatInputHandler, CombatScene, EnemyHeroPanel, ViewState) move to journal payloads in tasks 071 and 109;
   - AI reads (RuneTempoPlayerProfile, DefaultPlayerProfile, SimRelicPolicy) move behind `CombatAgent` in task 122;
   - the GRANT_ESSENCE write (EffectResolver.gd:136) is task 092's;
   - relic reads (RelicEffects.gd:32, :96) are task 091's.
9. **Docs.** ARCHITECTURE.md: add CombatSide and SideState to the file finder and the engine paragraph.

## Verification

- New probe in debug/tests/CommandTests.gd, "side model / SideState backs the legacy fields":
  - Setup: `TestHarness.build_state({})`.
  - Assert `is_same(state.side("player").hand, state.player_hand)`, and the same for deck and graveyard on both sides.
  - Set `state.side("enemy").essence = 3`; assert `state.enemy_essence == 3` and `state.essence_of("enemy") == 3`.
  - Set `state.player_mana = 2`; assert `state.side("player").mana == 2`.
- New probe in CommandTests.gd, "side model / deck rules":
  - Setup: `setup_deck("enemy", ["void_wind", "void_bolt"])` with `side("enemy").limited_cards = ["void_wind"]` and `opening_draw = 0`.
  - Draw both: the deck regenerated `void_bolt` only.
  - Player side: fill the hand to `HAND_MAX`, then draw: the card is burned and the deck shrank by one. Enemy side at `HAND_MAX`: the draw stops and the deck is unchanged.
- The existing `last_player_growth` probe (CommandTests.gd:604) still passes.
- `tools/run_checks.sh` green.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` through `--act 4`) diffs empty (design/TESTING.md "Refactor / extraction work").
- Performance: time the `--act 1` fingerprint run before and after. The int properties sit on the sim's hot path. If it is more than ~3% slower, have the legacy array names alias the SideState arrays instead of forwarding through a getter.

## Related

- Related: task 084 (roadmap A2): part 2, traps, environment, board, slots and hero.
- Related: task 085 (roadmap A6): part 3, per-turn counters and cost modifiers, and `last_player_growth` per side.
- Related: task 086 (roadmap A3): fires the card-drawn trigger for both sides (P2c) and wants `SideState` for the per-side filters.
- Related: task 087 (roadmap A4, lint L16, provisional; take the next free number if the landing order differs): counts `CombatSide.PLAYER/ENEMY` as side literals too, so respelling never lowers the count.
- Related: tasks 090, 091, 092 (per-side talents, relics, Void Marks) and 097 / 098 (Seris / Korrath modules): they put their per-side state on `SideState`.
- Related: task 049: SideState must hold no reference back to CombatState.
- Soft order: land after tasks 050, 054 and 055, which edit CombatState and CombatHandlers lines this task touches. No hard dependency.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item A1. The int `Side` enum (A7) is deferred; this task uses `CombatSide` string constants.

## Summary

_(filled in at /task-done)_
