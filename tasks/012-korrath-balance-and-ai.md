---
id: "012"
title: Korrath balance pass and branch-aware AI profiles
status: backlog
area: balance
priority: normal
started:
finished:
---

## Description

Two related follow-ups gated on Korrath being content-complete (tasks 008 and 010 don't need to ship first, but balance signal is noisier without the support pools).

- **Run a formal balance pass** via `BalanceSimBatch.tscn` across the Act 1 / Act 2 encounter matrix with the `korrath` profile and each starter deck × each talent set. Identify outlier branches/talents. Particular concerns: T2 sibling balance in Branches 2 and 3 (Path of Demons vs Humans, Path of Ruination vs Destruction), and T3 capstone power across all three branches. Tune numbers based on win-rate gaps.
- **Branch-aware player profiles** — `KorrathPlayerProfile` is intentionally branch-agnostic ([profile docstring](enemies/ai/profiles/KorrathPlayerProfile.gd)). It plays the knight first regardless of branch, which under-pilots Branch 1 (Bulwark wants to pair the knight with a Human first to maximise Formation HP/Armour). Once balance sim flags a branch as under-performing the baseline, split into subclasses à la `FleshcraftPlayerProfile`: `KorrathBulwarkProfile`, `KorrathBreakerProfile`, `KorrathRunicProfile`. Each registers under a distinct id in `CombatSim._PLAYER_PROFILES`.

Re-run the balance matrix after profile splits to confirm the numbers reflect the hero's actual ceiling, not a weak bot.

## Work log

- 2026-05-08: opened.

## Summary

_(filled in at /task-done)_
