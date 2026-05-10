---
id: "009"
title: Korrath rewards and shop pool wiring
status: backlog
area: meta
priority: normal
started:
finished:
---

## Description

Even once Korrath card pools exist (task 008), they will silently no-op without explicit wiring in two places. Vael and Seris each have these branches; Korrath has none.

- **[RewardScene.gd:91-105](rewards/RewardScene.gd#L91-L105)** — `_add_branch_pool()` needs three Korrath branches added (`infernal_bulwark`, `runic_knight`, `abyssal_breaker`) appending the matching pool ids.
- **[ShopScene.gd:443-456](shop/ShopScene.gd#L443-L456)** AND **[ShopScene.gd:482-495](shop/ShopScene.gd#L482-L495)** — both spots need the same three branches added to `branch_pool_names` / `talent_pools`.
- **`_card_act_gates`** in [CardDatabase.gd:3149](cards/data/CardDatabase.gd#L3149) — every new Korrath card from task 008 needs an act gate (1/2/3) to appear in rewards/shop.

Trivial diff — three or four one-liners — but easy to miss and fully invisible in tests. Verify by running a Korrath run and checking that branch-specific cards appear in card-reward picks and the shop after committing to a branch.

## Work log

- 2026-05-08: opened.

## Summary

_(filled in at /task-done)_
