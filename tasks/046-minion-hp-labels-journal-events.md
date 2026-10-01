---
id: "046"
title: Minion HP labels driven by journal events, not live state
status: done
area: ui
priority: normal
started: 2026-09-25
finished: 2026-09-25
---

## Description

Board slot ATK / HP labels snap to the live engine values whenever a slot refreshes, but the engine resolves a whole enemy turn before the presenter plays it, so an enemy rush minion (and the minion it hits) shows post-attack HP the moment it is summoned. Make the labels a lagging view: summon / slot events carry the minion's stats at emit time, damage / heal / buff / stats-changed events update the shown values as they play, and the attack lunge tweens between the event's before / after values instead of reconstructing from live HP.

## Work log

- 2026-09-25: opened.
- 2026-09-25: summon / slot / stats events carry a stat snapshot (`CombatState.minion_stat_payload`); BoardSlot labels render `shown_atk / shown_hp / shown_shield`; damage / heal / buff events move them (tween re-targets when a newer value arrives); the lunge tweens from the DAMAGE_DEALT before / after values, no longer `state._refresh_slot_for` from the scene; the presenter's `_ahead` guard keeps early-shown HP from being rewound by older snapshots. LiveSmoke probe `_hp_labels_lag_the_engine` (task 046).
- 2026-09-25: closed.

## Summary

Board slot ATK / HP labels no longer read the live minion: they render the slot's own `shown_atk / shown_hp / shown_shield`, seeded from a stat snapshot the summon / slot / stats-changed events now carry (`CombatState.minion_stat_payload`) and moved only by damage / heal / buff events as the presenter plays them. The attack lunge tweens from the DAMAGE_DEALT before / after values (the scene no longer calls `state._refresh_slot_for`), a label tween re-targets when a newer value arrives, and the presenter's `_ahead` guard keeps an HP shown early by the look-ahead from being rewound by an older snapshot journaled before it. LiveSmoke gained `_hp_labels_lag_the_engine`; run_checks.sh green (1109 tests, LiveSmoke, Parity 24/24).
Follow-ups: status icons / shield frame / buff glow still read the live minion on refresh; the enemy-turn visual pass (plan 3.6) should confirm the rush case by eye.
