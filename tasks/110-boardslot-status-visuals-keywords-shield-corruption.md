---
id: "110"
title: BoardSlot status visuals (keywords, shield, corruption, crit, armour, READY) from the journal snapshot
status: backlog
area: ui
priority: normal
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item E3 (`design/refactors/ARCHITECTURE_ROADMAP.md` §E). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

This is task 046's recorded follow-up ("status icons / shield frame / buff glow still read the live minion on refresh"). Task 046 moved only the ATK / HP / shield numbers onto the slot's own `shown_atk / shown_hp / shown_shield`, seeded from `CombatState.minion_stat_payload`:

```gdscript
static func minion_stat_payload(m: MinionInstance) -> Dictionary:   # CombatState.gd:128-131
	...
	return {atk = m.effective_atk(), hp = m.current_health, shield = m.current_shield}
```

Everything else a slot draws still comes from the live `MinionInstance` whenever the slot re-renders:

| What | Live read in BoardSlot.gd |
|---|---|
| Shield frame | :583 `var _has_shield := minion.has_shield() and minion.current_shield > 0` |
| HP label's "hp+shield" form | :305 `_shield_shown()` uses `minion.has_shield()` |
| ATK colour (corruption dim) | :525 (`refresh_stats_only`) and :445 (`animate_atk_change`): `BuffSystem.sum_type(minion, Enums.BuffType.CORRUPTION)` |
| Buff / debuff glow | :652, :659-663 `elif shown_atk > minion.current_atk:` |
| Keyword icons | :678 `minion.formation_fired`; :682-700 `has_guard()`, `has_deathless()`, `has_immune()`, `has_spell_immune()`, `has_ethereal()`, `has_pierce()`, `has_lifedrain()` |
| Crit stacks | :703-704 `has_critical_strike()`, `critical_strike_stacks()` |
| Armour / Armour Break | :716 `BuffSystem.net_armour(minion)` |
| Corruption icon and count | :725-733 |
| READY / EXHAUSTED | :737 `if minion.owner == "player" and minion.can_attack():`, :739 `minion.state == Enums.MinionState.EXHAUSTED` |

A full re-render (`_refresh_visuals` → `_show_occupied_state`) happens on:
- MINION_STATS_CHANGED playback (CombatPresenter.gd:743) and TURN_STARTED playback (:751-752);
- `show_minion` (BoardSlot.gd:292), used by summons and `_apply_slot` (CombatPresenter.gd:799);
- highlight changes, hover and the highlight pulse (BoardSlot.gd:248, :254, :262, :265);
- VFX tails (CombatVFXBridge.gd:165, :1159; VfxController.gd:87) and CombatScene.gd:855, :1782, :1838.

MINION_STATS_CHANGED has one emitter, `_refresh_slot_for` (CombatState.gd:120-123), reached from 66 call sites (`grep -rn --include='*.gd' '_refresh_slot_for(' combat relics enemies | grep -v 'func '`). The snapshot is also merged into the summon and slot events (CombatState.gd:612, :1324, :2145, :2581; CombatHandlers.gd:1347). Widening `minion_stat_payload` therefore covers every one of them at once.

`CombatUI.on_state_minion_stats_changed` (CombatUI.gd:124-131) has no caller. Delete it.

### Reachable today

1. **READY shows during the enemy's turn.**
   - The engine decides the enemy's turn and begins the player's next one in the same batch (`cmd_end_turn` → `begin_turn`, CombatState.gd:2894-2896). `begin_turn("player")` readies the board: `_ready_board` (:2424, :2507-2510) → `MinionInstance.on_turn_start` sets EXHAUSTED → NORMAL (MinionInstance.gd:247-251).
   - So any full re-render of a player slot while the enemy's events play draws READY.
   - Example, F4 Abyss Cultist Patrol (deck f4_a): Abyss Cultist ("ON PLAY: Apply 1 CORRUPTION to a random enemy minion", CardDatabase.gd:1925) and Corruption Weaver ("Apply 1 CORRUPTION to all enemy minions", :1963, :1967) go through `_corrupt_minion` → `_refresh_slot_for` (CombatState.gd:1138). When that MINION_STATS_CHANGED plays, the player's exhausted minions show READY with the enemy's turn still playing.
2. **Statuses show before the event that explains them.** Any re-render earlier in a batch shows statuses applied later in it: the corruption icon and dimmed ATK colour before their CORRUPTION_APPLIED plays, keyword grants before their buff event, Armour Break before the hit that applied it.
3. **A regenerated shield shows the wrong frame and label for a whole turn.**
   - Aether Bulwark and Wandering Warden (pool `neutral_core`, CardDatabase.gd:3536-3537; "Magic Shield 300 (Shield Regen I)", :1718-1731, :1748-1760) regain 100 shield in `on_turn_start` (MinionInstance.gd:252-255). Nothing is journaled.
   - Example: an enemy attack breaks the Bulwark's 300 shield. DAMAGE_DEALT sets `shown_shield` to 0, so the label reads "400". At the player's next turn start the engine has 400 + 100. TURN_STARTED playback re-renders the slot: the frame reads live `current_shield > 0` and switches to the shield frame, but the label keeps `shown_shield` 0 and still reads "400".
   - It stays like that until the minion's next damage event.

### Latent

- Temporary buffs expire in `_ready_board` (`BuffSystem.expire_temp`, CombatState.gd:2510; MinionInstance.gd:248) with no event. No card uses a temporary BUFF_ATK today (`permanent` defaults to true, EffectStep.gd:129-130, and no card sets it false). Pack Frenzy's +250 reverts through a journaled turn-end handler (CombatHandlers.gd:2335-2345).
- Exhaustion after an attack (CombatManager.gd:149, :184) and crit consumption (`_apply_crit` → `BuffSystem.remove_one_source`, :348-352) journal nothing. They appear at the slot's next re-render, which is right for a single command and early when the player queues commands (owner decision QN5).
- `formation_fired` is set with no `_refresh_slot_for` unless a formation step happens to refresh the actor (CombatHandlers.gd:519, :559).

## Decision (owner, 2026-10-01)

QN5: "Keep player input responsive (do NOT gate on presenter idle). The display fixes (E1–E3, E7) make the UI correct during playback instead."

## Proposed fix

Two phases, each its own commit with its own gate run. Phase E3b step 1 (turn-start snapshots) fixes reachable case 3 on its own and can ship first.

### Phase E3a: status in the snapshot, BoardSlot renders it

1. **Widen the snapshot.** `minion_stat_payload` gains a flat `status` dictionary:
   - keyword flags: `guard`, `deathless`, `immune`, `spell_immune`, `ethereal`, `pierce`, `lifedrain`;
   - `formation_ready` (has FORMATION and `not formation_fired`), `crit_stacks`, `armour_net`, `corruption` (the summed amount);
   - `shield_cap` (`shield_cap()`, which `has_shield()` tests), `can_attack`, `exhausted`;
   - `base_atk` (`current_atk`, for the buff glow);
   - `corruption_inverts`: the Corrupt Flesh inversion that `flash_atk_debuff` reads live (BoardSlot.gd:894-897, `MinionInstance.corruption_inverts_on_friendly_demons`; a static today, per state after task 130).
   Build it in one function so every event that merges `minion_stat_payload` carries it.
2. **BoardSlot keeps `shown_status`.**
   - Set it wherever the shown stats come from a snapshot: `show_minion(m, stats)` (BoardSlot.gd:286-292, via `CombatPresenter._stats_of`, :181-185, which passes `status` through), `_apply_slot` (:799) and MINION_STATS_CHANGED (CombatPresenter.gd:735-743).
   - The status always applies. Only the HP keeps the `_hp_shown_ahead` guard (:739-742).
   - A newly shown minion without a snapshot takes a live one, as `show_minion` already does for the numbers (:289-290).
3. **Render from it.** `_show_occupied_state`, `refresh_stats_only`, `animate_atk_change` and `_shield_shown` read `shown_status`. The frame uses `shown_status.shield_cap > 0 and shown_shield > 0`. Static card data stays on `minion.card_data`: name, art, faction, spark value and the on-death tooltip.
4. **Name each status icon after its title** (as :730 does for `corruption_icon`), so tests can find them.
5. Delete `CombatUI.on_state_minion_stats_changed`.

### Phase E3b: journal the status changes that emit nothing

1. **Turn start.** `_ready_board` (CombatState.gd:2507-2510) compares each minion's `minion_stat_payload` before and after `on_turn_start()` / `expire_temp` and calls `_refresh_slot_for(m)` for those that changed (readied, shield regenerated, temp buff gone). This runs inside `begin_turn`, before TURN_STARTED (:2454), so the presenter re-renders those slots when the turn start plays. The re-render loop at CombatPresenter.gd:751-752 can then go, or stay as a harmless re-render of snapshots.
2. **After an attack.** At the end of `resolve_minion_attack` and `resolve_minion_attack_hero` (CombatManager.gd:148-150, :182-184), if the attacker is still on the board, call `state._refresh_slot_for(attacker)`: exhaustion and crit consumption.
   - Check that `_play_attack`'s look-ahead doesn't take this MINION_STATS_CHANGED for part of the attack.
   - `_hp_labels_lag_the_engine` must stay green: the `_ahead` guard keeps an HP shown early by the lunge from being rewound.
3. **Formation.** CombatHandlers.gd:519 and :559 call `state._refresh_slot_for(actor)` after setting `formation_fired`.
4. **Audit the rest.** Grep for writes to `MinionInstance.state`, `formation_fired`, `current_shield` and BuffSystem calls on minions that don't reach `_refresh_slot_for`. Fix each, or list it in the work log as covered by a later event.
5. **Journal noise.** Only minions whose snapshot changed get an event. Compare BalanceSimBatch wall time before and after: the sim journals every event, and task 136 (roadmap I7d) is measuring the journal's cost.

If task 111 (roadmap E4, lint L17, provisional; take the next free number if the landing order differs) has landed, lower its BoardSlot pattern baseline in the same commits.

## Verification

- **New LiveSmoke probe `_status_icons_lag_the_engine`** (debug/tests/LiveSmokeTests.gd, next to `_hp_labels_lag_the_engine`, :161):
  - Setup: launch F1, watch `scene.presenter.event_played`.
  - Action, synchronously: `var m := st._summon_token("void_imp", "player")`, then `BuffSystem.apply(m, Enums.BuffType.GRANT_GUARD, 1, "probe", false, false)`, `st._corrupt_minion(m)` and `st._refresh_slot_for(m)`.
  - Expect: at the TOKEN_SUMMONED event the slot's status bar has no GUARD icon and no `corruption_icon`; after the MINION_STATS_CHANGED plays it has both.
- **Same file, READY during the enemy's turn:**
  - Setup: `st._summon_token("void_imp", "player", 0, 5000)` (exhausted on summon; 5000 HP so the F1 enemy can't kill it), then drain.
  - Action: `st.cmd_end_turn("player")`; the scene runs the enemy's turn.
  - Expect: on any `event_played` with side "enemy" after the enemy's TURN_STARTED, a forced `_refresh_visuals()` on the token's slot draws no READY icon (today it does). After the player's TURN_STARTED plays, the slot shows READY.
- **Same file, shield regen:**
  - Setup: `var b := st._summon_token("aether_bulwark", "player")`, set `b.current_shield = 0`, `st._refresh_slot_for(b)`, drain. The label reads "400".
  - Action: `st._ready_board(st.player_board)` (the turn-start step under test), then drain and force `_refresh_visuals()` on its slot, as TURN_STARTED playback does.
  - Expect: the HP label reads "400+100" and the frame is the shield frame. Today: the shield frame with a "400" label.
- **New CommandTests probe** (debug/tests/CommandTests.gd): with an Aether Bulwark at 0 shield and an exhausted minion, `begin_turn("player")` journals one MINION_STATS_CHANGED for each before TURN_STARTED (shield 100; `status.can_attack` true). A minion whose snapshot didn't change gets none.
- **Same file:** after `cmd_attack`, the journal's last MINION_STATS_CHANGED for the attacker has `status.can_attack == false`, and `crit_stacks` one lower when it had a stack.
- Update any CommandTests probe that asserts an exact journal sequence around a turn start or an attack.
- `tools/run_checks.sh` green (LiveSmoke `_hp_labels_lag_the_engine` included).
- Behaviour-neutral: the engine changes only add a payload field and MINION_STATS_CHANGED events. `digest_text` excludes the journal (CombatState.gd:2242-2288), and `minion_stats_changed` has no subscriber that mutates. The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for `--act 1` through `--act 4`; turn start and attacks run in every fight) diffs empty (design/TESTING.md "Refactor / extraction work"). Record the wall-time change from Phase E3b step 5 in the task summary.

## Related

- Depends on: task 048 — both edit CombatPresenter `_play` / `_emit_ui` (048's deadline, generation guard and resync re-render slots). Ordering only.
- Related: task 046 — recorded this follow-up; same snapshot path.
- Related: task 114 (roadmap F1) — stamps a cause on every event as a typed `CombatEvent.cause` field, not a payload key, so it doesn't touch `minion_stat_payload`. Land them in either order.
- Related: task 115 (roadmap F2) — the presenter's look-ahead by cause. It generalises the `_ahead` / `shown_hp` guard with a delta rule for out-of-order HP events; that, not task 114, is the real overlap with this task's snapshot path. Phase E3b step 2's attacker MINION_STATS_CHANGED must not be taken as part of the strike by its look-ahead.
- Related: task 057 — a minion that dies mid-attack; Phase E3b step 2's refresh runs only if the attacker is still on the board, which matches 057's spent-attack exit.
- Related: task 130 (roadmap I2) — moves the Corrupt Flesh inversion off the MinionInstance static; `corruption_inverts` in the snapshot reads it from there.
- Related: task 061 — journals a stats event after a Deathless save; the DEATHLESS icon then follows that snapshot.
- Related: task 135 (roadmap I8) — the idle-consistency probe can also compare `shown_status` with the engine once this lands.
- Related: task 136 (roadmap I7d) — journal noise and the sim's journal cost.
- Related: task 113 (roadmap E7) — target highlights; validity comes from the engine, display from these snapshots.
- Related: task 111 (roadmap E4, lint L17) — its second pattern counts BoardSlot's live-minion reads (19 lines at `404b51c`); this task brings it to zero.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item E3.
  - Re-check found a reachable label bug in the same gap: Shield Regen (Aether Bulwark, Wandering Warden) changes `current_shield` at turn start with no event, so the label keeps the broken shield while the frame switches back. Folded into Phase E3b step 1, which can ship on its own.
  - Also found: `CombatUI.on_state_minion_stats_changed` is dead; `formation_fired` writes don't refresh the slot.

## Summary

_(filled in at /task-done)_
