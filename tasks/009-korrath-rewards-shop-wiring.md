---
id: "009"
title: Korrath rewards and shop pool wiring
status: done
area: meta
priority: normal
started: 2026-05-29
finished: 2026-05-29
---

## Description

Even once Korrath card pools exist (task 008), they will silently no-op without explicit wiring in two places. Vael and Seris each have these branches; Korrath has none.

- **[RewardScene.gd:91-105](rewards/RewardScene.gd#L91-L105)** — `_add_branch_pool()` needs three Korrath branches added (`infernal_bulwark`, `runic_knight`, `abyssal_breaker`) appending the matching pool ids.
- **[ShopScene.gd:443-456](shop/ShopScene.gd#L443-L456)** AND **[ShopScene.gd:482-495](shop/ShopScene.gd#L482-L495)** — both spots need the same three branches added to `branch_pool_names` / `talent_pools`.
- **`_card_act_gates`** in [CardDatabase.gd:3149](cards/data/CardDatabase.gd#L3149) — every new Korrath card from task 008 needs an act gate (1/2/3) to appear in rewards/shop.

Trivial diff — three or four one-liners — but easy to miss and fully invisible in tests. Verify by running a Korrath run and checking that branch-specific cards appear in card-reward picks and the shop after committing to a branch.

## Work log

- 2026-05-08: opened.
- 2026-05-29: started. Reconciled scope against what shipped in tasks 023/024/025. RewardScene Korrath wiring + all act gates already exist; the real gap is ShopScene (`_get_branch_pool` + `_get_full_pool`) which has zero Korrath handling. Only `korrath_common` (branch-agnostic) and `korrath_iron_vanguard` (B1, gated on `iron_formation`) pools exist so far; runic_knight/abyssal_breaker are unshipped (§13/§14). `korrath_core` is deck-builder-only (§10) — correctly absent from reward/shop.
- 2026-05-29: closed.

## Summary

Wired Korrath into both ShopScene pool builders — `_get_branch_pool` (active-branch-only view, falls back to `korrath_common` when no branch committed) and `_get_full_pool` (`korrath_common` always + unlocked branch pools) — mirroring the existing Vael/Seris pattern exactly. `korrath_common` is branch-agnostic (no talent gate); `korrath_iron_vanguard` (5 cards) gates on the `iron_formation` B1 T0 talent. RewardScene and all `_card_act_gates` entries (9 common + 5 iron-vanguard cards) were already in place from tasks 023/024/025, so the only code change is +12 lines in ShopScene.gd. 784/784 tests pass; pool membership verified from source (`_card_pools` + `_card_act_gates`). The task's original branch names (`infernal_bulwark`/`runic_knight`/`abyssal_breaker`) are outdated — B1 shipped as `iron_vanguard`.

Follow-ups: B2 (`korrath_runic_knight`) and B3 (`korrath_abyssal_breaker`) pools are still unshipped (KORRATH_HERO_DESIGN §13/§14); when they land, add their `runeforge_strike`/`corrupting_presence` gates to the same two ShopScene blocks plus RewardScene `_get_active_support_pool_ids`. The branch-name update should be reflected in design docs that still say "Infernal Bulwark" (see [[korrath_branch_names]]).
