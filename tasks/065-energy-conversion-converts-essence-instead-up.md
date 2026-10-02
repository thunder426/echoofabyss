---
id: "065"
title: Energy Conversion converts all Essence instead of 'up to 3'; its hover preview shows no gain
status: backlog
area: combat
priority: normal
started:
finished:
---

## Description

Found while grooming the 2026-09-25 architecture review (roadmap §D). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Energy Conversion is a 0-Mana `neutral_core` spell. It is also in the deck builder's `CORE_FILL_POOL` (DeckBuilderScene.gd:46-51). Its text is "Convert up to 3 of your remaining Essence into Mana." (CardDatabase.gd:1817). The code does something else in two ways.

### 1. It converts all Essence, and can destroy some

The step has no `amount`: CardDatabase.gd:1820 `[{"type": "CONVERT_RESOURCE", "convert_from": "essence", "convert_to": "mana"}]`. The resolver calls `convert_essence_to_mana("player")` (EffectResolver.gd:339), which takes no limit. CombatState.gd:1514-1518:

```gdscript
func convert_essence_to_mana(side: String) -> void:
	var amount: int = essence_of(side)
	set_essence(side, 0)
	set_mana(side, mini(mana_of(side) + amount, mana_max_of(side)))
	emit_resources(side)
```

- With 5 Essence and 0/6 Mana, the player ends with 0 Essence and 5 Mana. The card promises 3 Mana with 2 Essence left.
- With 4 Essence and 5/6 Mana, the player ends with 0 Essence and 6 Mana. Three Essence are destroyed.

### 2. The hover preview shows no gain

`CombatInputHandler.start_pip_blink_for_card` reads the raw step: `var amount: int = step.get("amount", 0)` (:146), then `var actual: int = mini(amount, maxi(available, 0))` (:151). With no `amount` this is 0, so the pip bar blinks no Essence spend and no Mana gain, while the engine converts everything.

### The documented rule

- DESIGN_DOCUMENT.md:151: CONVERT_RESOURCE "Converts up to `amount` of one resource into the other. … Actual converted = `min(amount, current_resource)`. Overflow beyond the target cap is kept as temporary excess."
- DESIGN_DOCUMENT.md:155: "`Energy Conversion` converts up to 3 Essence → Mana."
- Flux Siphon, the mirror card, follows the doc: `"amount": 3` (CardDatabase.gd:1599), and `convert_mana_to_essence(side, max_convert)` ignores `essence_max` and clamps at `ESSENCE_HARD_CAP` (CombatState.gd:1520-1526). It can still destroy Mana when Essence is near 10.
- The EffectStep comments match neither the doc nor Flux Siphon: EffectStep.gd:37 "Convert all of convert_from resource into convert_to, capped at target's max" and :185 "Conversion is capped at the destination's current max."

### Who sees it

The player only, with any hero, in any run whose deck has the card (rewards and shop from `neutral_core`, deck-builder core fill). No enemy deck, preset deck or sim profile uses Energy Conversion (`grep -rn energy_conversion enemies/ debug/ cards/data/PresetDecks.gd` → nothing), so the balance sim never sees it. No test covers conversion.

## Proposed fix

CardDatabase.gd is the card source of truth (owner Q6), and the card text says "up to 3". Fix the code, not the text.

1. **Data.** Add `"amount": 3` to Energy Conversion's step (CardDatabase.gd:1820).
2. **One conversion rule for both directions, in one place** (DESIGN_DOCUMENT.md:151):
   - Add a pure static `CombatState.conversion_amount(max_convert: int, source_now: int, dest_now: int) -> int` returning `maxi(0, mini(max_convert, mini(source_now, RESOURCE_HARD_CAP - dest_now)))`.
   - Add `convert_resource(side, from, to, max_convert)`. It moves that amount, ignores the destination's max (temporary excess; the turn-start refill resets it, CombatState.gd:1462-1464), and calls `emit_resources(side)` once.
   - `RESOURCE_HARD_CAP := 10` replaces `ESSENCE_HARD_CAP` (CombatState.gd:1360). The pip bar has 10 pips per column (PipBar.gd:60) and already draws Mana overflow pips (:248-256).
   - Capping by the room left means no resource is destroyed. For Flux Siphon this only differs when Essence is above 7 before the cast.
   - Delete `convert_essence_to_mana` and `convert_mana_to_essence`. The resolver is their only caller.
3. **Resolver.** The CONVERT_RESOURCE arm (EffectResolver.gd:333-339) calls `convert_resource` with `step.amount`. Task 063 removes the arm's `ctx.owner == "player"` gate. If it has landed, pass `ctx.owner`; if not, leave the gate to it.
4. **Preview.** `start_pip_blink_for_card` (CombatInputHandler.gd:143-155) computes `actual` with `CombatState.conversion_amount`, using the resources left after this card's own cost. The preview can then no longer drift from the engine.
5. **Comments.** Rewrite EffectStep.gd:37 and :185 to state the rule.
6. **Alternative, only if the owner prefers it at task start:** keep Mana capped at `mana_max` for Energy Conversion. Then convert only `min(3, essence, mana_max - mana)`, so that no Essence is destroyed, and change DESIGN_DOCUMENT.md:151 to match.

Don't edit `design/master_doc/CARD_LIBRARY.md:270`. Task 079 deletes that file.

## Verification

- New probes in `debug/tests/CardEffectTests.gd`. Run the card's steps with `TestHarness.make_ctx(state, "player")` after setting resources with `set_essence` / `set_mana` / `player_mana_max`:
  - 5 Essence, 0/6 Mana → 2 Essence, 3 Mana.
  - 2 Essence, 0/6 Mana → 0 Essence, 2 Mana.
  - Overflow: 4 Essence, 5/6 Mana → 1 Essence, 8 Mana. Then `refill_resources("player")` → 6 Mana.
  - Hard cap: 3 Essence, 9/9 Mana → 2 Essence, 10 Mana. Only 1 converts.
  - Flux Siphon regression: 3 Mana, 0 Essence → 0 Mana, 3 Essence. With 8 Essence, only 2 Mana convert (new rule; today 3 Mana are spent and 1 is lost).
  - `CombatState.conversion_amount` unit cases, which also cover the preview's arithmetic.
- `tools/run_checks.sh` green.
- Live behaviour change for the player only; the sim can't see it. No preset holds either conversion card. The only enemy deck with Flux Siphon (`f2_c`) grows Essence to at most 7 (CorruptedBroodRuneProfile.gd:9 "2E → 2M → 6E → 4M → 7E"), so the new room cap never binds there.
  - The seeded balance fingerprint (`BalanceSimBatch -- --act 1 --runs 200 --seed 7` and `--act 2`, before and after) should diff empty. If any F2 `f2_c` row moves, explain why in the summary.
- Manual: hover Energy Conversion with 5 Essence and 0/6 Mana. Three Essence pips blink as spent and three Mana pips glow as gained.

## Related

- Related: task 063. It edits the same CONVERT_RESOURCE arm (removes the player-only gate). Land in either order; the second one rebases.
- Related: task 105 (roadmap D2). Its strict step parsing can reject a CONVERT_RESOURCE step with no `amount`. The preview's raw `step.get(...)` reads become `EffectStep` reads there.
- Related: task 079. It deletes CARD_LIBRARY.md, so that table is not updated here.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from the D-effects unit's bug 3 (roadmap §D).

## Summary

_(filled in at /task-done)_
