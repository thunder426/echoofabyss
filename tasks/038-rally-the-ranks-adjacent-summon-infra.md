---
id: "038"
title: Implement rally_the_ranks + adjacent-summon infra + dual-tag race picker
status: done
area: combat
priority: normal
started: 2026-05-16
finished: 2026-05-16
---

## Description

Split out from task 023 because Rally the Ranks (Korrath core spell §10) needs three new pieces of generic infrastructure: a `target_type` that accepts "friendly Human OR Demon" minions, a SUMMON step variant that places tokens into the two slots adjacent to a chosen target minion (instead of any free slot), and a runtime race-picker modal so the player can choose Human or Demon when the chosen target carries both tags (e.g. Abyssal Knight under runeforge_strike, or Squire of the Order). All three pieces must also work on the sim side so enemy AI / balance sims can resolve the spell. Card body itself is trivial; the infra is the work.

## Work log

- 2026-05-16: opened.
- 2026-05-16: closed.

## Summary

Shipped `rally_the_ranks` (2M Korrath core spell) plus all three pieces of reusable infrastructure split from task 023: (1) `friendly_human_or_demon` target_type added to Targeting validation + highlight wiring; (2) SUMMON step extended with `adjacent_to_target: bool` + `adjacent_side: "left"|"right"` fields, dispatched via new `_summon_token_at_slot` on both CombatScene and CombatState (refactored the existing `_summon_token` paths to share extracted `_spawn_token_into_slot[_vfx]` cores — no duplication); (3) generic dual-tag race-picker via `EffectContext.extra_cast_data: Dictionary` plumbed through `cast_player_targeted_spell` (live) and both `commit_play_spell` paths (sim), gated by new `ConditionResolver` conditions `rally_race_human`/`rally_race_demon`. Live combat shows a new programmatic `combat/ui/ChoiceModal.gd` (2–4 option modal, reusable for any future "spell needs a runtime choice" UX); sim falls back to `CombatState._rally_pick_race_for(owner)` heuristic (dominant friendly race, tie → demon). Rally itself is declared declaratively as 4 conditional SUMMON steps. Edge slots and occupied adjacent slots silently fizzle ("up to 2" semantics). Added `TestHarness.spawn_friendly_at` for slot-specific test setup. 729/729 tests pass (9 new Rally probes + 1 heuristic probe).

Follow-ups: ChoiceModal styling is bare-bones (no theme, no animation) — polish pass when other modals join. The race-picker is hardcoded by `spell.id == "rally_the_ranks"` in `CombatScene._resolve_spell_extra_cast_data`; when a second spell needs a cast-time modal, refactor that switch into a per-spell registry. Sim AI doesn't currently cast Rally (no enemy deck holds it), but the plumbing and heuristic are ready when an enemy deck eventually does.
