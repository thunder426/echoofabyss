---
id: "114"
title: Engine: a Resolution stack that stamps a cause on every journal event (digest-neutral)
status: backlog
area: combat
priority: high
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item F1 (`design/refactors/ARCHITECTURE_ROADMAP.md` §F). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

Journal events carry no link to the resolution that produced them. The presenter can only guess from kind and position which damage belongs to an attack's strike, its counter, a spell, a void bolt or a trigger. Today's content already makes those guesses wrong; task 115 has the reachable bugs. This task gives the engine the information. Task 115 makes the presenter use it.

### What exists

- **One journal choke point.** `CombatState.gd:99-104`:
  ```
  func emit_event(kind: int, side: String, payload: Dictionary = {}) -> CombatEvent:
  	var ev := CombatEvent.make(kind, side, turn_number, payload)
  	ev.seq = journal.size()
  	journal.append(ev)
  ```
  This is the only `journal.append` in the repo. All 88 `emit_event(` call sites (5 files: CombatState, CombatManager, CombatHandlers, EffectResolver, HardcodedEffects) go through it.
- **No cause on the event.** `CombatEvent` (CombatEvent.gd:36-40) has `seq`, `kind`, `side`, `turn` and `payload`.
- **One trigger dispatch.** `TriggerManager.fire` (TriggerManager.gd:79-86) calls each handler: `for entry in snapshot: if entry.handler.is_valid(): entry.handler.call(ctx)`. All 32 `trigger_manager.fire(` sites go through it.
- **Payloads can't tell the hits apart.** Void-Touched Imp's on-death AoE gets its DamageInfo from `EffectResolver._build_damage_info` (EffectResolver.gd:683-685), with `source = MINION` and `source_minion = VTI`. VTI's counter-attack gets `_attack_damage_info(counter_damage, defender)` (CombatManager.gd:138, :322-330), also `MINION` and VTI. Only `school` and `source_card` differ, and only by accident.

### Where resolutions begin and end today

| Resolution | Code | Anchor event |
|---|---|---|
| Command | 10 `cmd_*` wrappers (CombatState.gd:2534 … :2884), each `return _finish_command(_cmd_x(...))`; `_finish_command` :2920 | COMMAND (:3119), journaled by `_log_command` after validation |
| Attack | `CombatManager.resolve_minion_attack` :74-154, `resolve_minion_attack_hero` :156-187 | ATTACK_STARTED (:77, :159) |
| Strike | `_deal_damage(defender, …)` :100; `apply_hero_damage(target_owner, …)` :170 | its DAMAGE_DEALT |
| Counter | `_deal_damage(attacker, …)` :138 | its DAMAGE_DEALT |
| Spell | `cast_player_targeted_spell` :523-539, `cast_player_hero_spell` :546-568, `cast_enemy_spell` :1063-1076 | SPELL_CAST … SPELL_RESOLVED |
| Trap | each trap in `_fire_traps_for` :1044-1057 | TRAP_FIRED (:1053) |
| Trigger | each handler call in `TriggerManager.fire` :84-86 | none |
| Void bolt | `_deal_void_bolt_damage` :952-983, `_deal_enemy_void_bolt_damage` :988-1000 | VOID_BOLT (:970, :990) |
| Ritual | `_fire_ritual` :853-897 | RITUAL_FIRED (:891) |

They nest. A strike that kills a Void-Touched Imp:
- `_deal_damage` journals the strike, then emits `minion_vanished` (CombatManager.gd:300);
- `_on_minion_vanished` (CombatState.gd:1985-2009) journals MINION_DIED and fires ON_ENEMY_MINION_DIED;
- `_resolve_on_death` (CombatHandlers.gd:712-717) runs the AoE, which journals its DAMAGE_DEALTs;
- only then does the counter run (CombatManager.gd:138).

All of it is synchronous (CombatState never awaits, lint L6), so a stack pushed and popped at these boundaries stays balanced.

### Digest-neutral

- `digest_text` (CombatState.gd:2242-2288) reads HP, resources, slots, boards, hands, decks, traps, environments and relics. It reads no journal.
- The journal is read only by CombatPresenter, CommandTests, LiveSmokeTests and ParityTests. ParityTests uses `jpos` only to print logs (:159-160).

So a new event field changes no Parity comparison and no sim result, as long as the stack draws no RNG and no rule reads it.

### Why now

- Task 115 (roadmap F2) can't fix the presenter bugs without it.
- Task 129 (roadmap I1) moves `_last_attacker`, `_last_attack_was_crit`, `_pending_dmg_source`, the cancel flags and `_silent_buff_apply` onto the same Resolution. That means one class and one stack, not two.

## Decision (owner, 2026-10-01)

- Q7b: "AI look-ahead: **Planned.** Task 049 (leaks), I2 (statics per state) and I1 (Resolution context) become prerequisites and go up in priority." This task is I1's base, so it is high priority too.
- The stack lives on the state, not in a static, so a cloned state used for look-ahead has its own.
- Grooming plan: the Resolution and its stack hold no reference back to CombatState (task 049's cycle class).

## Proposed fix

1. **`combat/board/Resolution.gd`** (`class_name Resolution`, RefCounted):
   - `enum Kind { COMMAND, ATTACK, STRIKE, COUNTER, SPELL, TRAP, TRIGGER, VOID_BOLT, RITUAL }`;
   - fields `id: int`, `kind: Kind`, `label: String` (command name, card id or handler method), `side: String`, `parent: Resolution`;
   - helpers `has_ancestor(r: Resolution) -> bool` and `nearest(kinds: Array) -> Resolution`.

   It holds no reference to CombatState, CombatManager or any Node. Task 129 adds its fields (attacker, crit_spent, cancelled, silent_buffs, dark_channeling) to this class.
2. **`combat/board/ResolutionStack.gd`** (RefCounted):
   - `push(kind, label, side) -> Resolution`: the parent is the current top, the id comes from a counter;
   - `pop(r)`: if `r` isn't the top, `push_error`, unwind down to it and add 1 to `mismatches`;
   - `top()`, `depth()`, `reset()`.

   `CombatState` creates one at field init (`var resolutions := ResolutionStack.new()`).
3. **`CombatEvent.cause: Resolution`**, a typed field. It is null outside any resolution (for example during `setup_combat`).
   - `emit_event` sets `ev.cause = resolutions.top()`.
   - `_to_string` prints the cause id and kind.
   - Use a typed field, not `payload.cause` / `payload.parent_cause` as the roadmap sketched. Payloads, and the tests that read them, stay untouched, and a missing cause can't hide behind a `.get()` default. The parent is `ev.cause.parent`.
4. **Push and pop at the boundaries in the table above.**
   - **Commands.** Each `cmd_*` wrapper pushes `COMMAND` (label = command name) before calling `_cmd_x`. `_finish_command` takes that Resolution and pops it after the F15 end-turn it may run (:2920-2928), so those events nest too.
     - Every refusal returns through `_finish_command`, so no early return can skip the pop.
     - Leave `_log_command` where it is in `_cmd_hero_skill` (:2875-2878). It logs after the body because the body can still refuse. The skill's effects nest under the pushed command anyway.
   - **Attacks.** `resolve_minion_attack` pushes `ATTACK` before ATTACK_STARTED (:77) and pops it after the exit bookkeeping (:152-154), with a nested `STRIKE` around :100 and a nested `COUNTER` around :138.
     - `resolve_minion_attack_hero` pushes `ATTACK`, with `STRIKE` around `apply_hero_damage` (:170).
     - Guard both with `state != null`, as the methods already do.
     - Pierce (:120-125), lifedrain, siphon and `_check_post_crit` (:150) stay directly under `ATTACK`.
   - **The enemy's attack declaration stays outside `ATTACK` here.** `_fire_enemy_attack_declared` (called at :2775, body :3086-3097) runs before `resolve_minion_attack`, and its trap events come before ATTACK_STARTED. Tests call `resolve_minion_attack` directly, so it must push its own `ATTACK` when none is open. Task 129 (step 2) later opens `ATTACK` in `_cmd_attack` / `_cmd_attack_hero` right after `_log_command`, before the declaration, and `resolve_minion_attack` reuses it. This task may place it there from the start, as long as the bare call still pushes its own.
   - **Spells.** The 3 `cast_*` functions push `SPELL` (label = spell id) before SPELL_CAST and pop after SPELL_RESOLVED. The ON_*_SPELL_CAST triggers (:2645-2649) fire before them and stay under the command. Task 129 (step 3) moves this push into `_cmd_play_spell`, before the cast triggers; the `cast_*` functions are only called from there (:2658-2662), so this task may also put it there from the start.
   - **Traps.** `_fire_traps_for` pushes `TRAP` (label = trap id) for each trap, after the `continue` at :1046-1047. The push covers TRAP_FIRED and `EffectResolver.run`.
   - **Triggers.** `TriggerManager.fire` pushes `TRIGGER` around each `entry.handler.call(ctx)`. The label is `entry.handler.get_method()`, as `dump_order` reads it.
     - `CombatSetup.setup` creates the TriggerManager (CombatSetup.gd:525-526). It hands that TriggerManager the state's stack (`tm.resolutions = st.resolutions`), and does so again when the setup is re-run.
     - A TriggerManager with no stack skips the push. None exists today; the check is only a guard.
   - **Void bolts.** Both functions push `VOID_BOLT` at entry, so the VOID_BOLT event and its hero hit share a cause.
   - **Rituals.** `_fire_ritual` pushes `RITUAL`. Grand Ritual: Chaos (CombatHandlers.gd:318-366) already runs inside its handler's `TRIGGER`.
   - Use plain push / pop calls. No lambda wrappers that capture `self` (task 049).
5. **Balance check in `_finish_command`.** After popping the command:
   - the depth must be back to what it was when the command was pushed. That is 0 today: no rules code issues a command from inside another (the `cmd_*` callers are the scene, the input handler, EnemyTurnRunner, the sim agents and tests);
   - if it isn't: `push_error`, unwind to that depth, and add 1 to `mismatches`;
   - this way, a script error inside a handler can't mis-stamp every later event;
   - `push_error` alone doesn't fail `run_checks.sh`, which greps for `SCRIPT ERROR`, so the tests assert `mismatches == 0`.
6. **No behaviour change.**
   - Draw no RNG.
   - Add no rule branch on the stack.
   - Keep the stack out of `digest_text`.

   Task 129 is where rules start reading it.
7. **Docs and comments.**
   - ARCHITECTURE.md: the CombatEvent row (`cause`), the file-finder table (Resolution, ResolutionStack), and invariant 7 (each event carries the resolution that produced it).
   - The CombatEvent.gd header.
   - The TriggerManager.gd header. Lines :2-3 and :19-27 still describe the flow before Phase 4 ("CombatScene owns one instance, created in _ready() and populated by _setup_triggers()"); handlers are now registered in `CombatSetup.setup`. Task 082 assigns this header to task 088; task 131 also edits the file. Whichever of 088 / 114 / 131 lands first rewrites it, and the others skip it. Task 055's stale-comment list doesn't include it.

## Verification

New probes in `debug/tests/CommandTests.gd` (bare CombatState, no scene):
- **`_journal_cause_attack_counter`.**
  - Setup: `TestHarness.build_state({})`; `vti = spawn_enemy(state, "void_touched_imp")` with `vti.current_health = 100`; `att = spawn_friendly(state, "void_imp")` with `att.current_health = 1000`. Record the journal size, then call `state.combat_manager.resolve_minion_attack(att, vti)`.
  - Assert the hit on `vti` has `cause.kind == STRIKE`, and that cause's parent is ATTACK_STARTED's cause (`ATTACK`).
  - Assert the 200 hit on `att` has `cause.kind == COUNTER`.
  - Assert the 100 hit on `att` has `cause.kind == TRIGGER`, with the `STRIKE` among its ancestors.
- **`_journal_cause_spell_nested`.**
  - Setup: a friendly minion on the board, a full-HP VTI (300), enough Mana (`_set_res`), and `arcane_strike` cast on the VTI through `cmd_play_spell`.
  - Assert the spell's own hit on the VTI has the same cause as SPELL_CAST (`SPELL`, label `arcane_strike`).
  - Assert VTI's AoE hits have a `TRIGGER` cause with that `SPELL` among its ancestors.
- **`_journal_cause_void_bolt`.**
  - Setup: cast `void_bolt` with `cmd_play_spell("player", inst, null)`.
  - Assert the hero DAMAGE_DEALT has the same cause as the VOID_BOLT event (`VOID_BOLT`), whose parent is the `SPELL`.
- **`_journal_cause_commands`.**
  - Setup: run a few commands (play_minion, play_spell, attack, end_turn, and one refused command).
  - Assert every event each one journals has a cause chain whose root is a `COMMAND` with that command's label.
  - Assert `state.resolutions.depth() == 0` and `mismatches == 0` after each command.
- **Whole fights.** In ParityTests and LiveSmoke `_ai_vs_ai_fight`, assert `st.resolutions.mismatches == 0` at the end of every fight.
- **Handler order.** The handler-order snapshot (`debug/tests/snapshots/handler_order.txt`) is unchanged: no registration changes.
- `tools/run_checks.sh` green.
- **Behaviour-neutral.** The seeded balance fingerprint (`BalanceSimBatch -- --act <N> --runs 200 --seed 7`, before and after, for Acts 1, 2, 3 and 4, since the stack runs in every fight) diffs empty (design/TESTING.md 'Refactor / extraction work').
- **Cost.**
  - Compare BalanceSimBatch wall time for Act 1 before and after; the change adds one push / pop per handler call.
  - If it grows by more than a few percent, push one `TRIGGER` per `fire()` that has listeners, labelled with the TriggerEvent name, instead of one per handler. Task 115 needs only the nesting, not the handler name.

## Related

- Related: task 115 (roadmap F2): the consumer. The presenter matches look-ahead events by cause.
- Related: task 129 (roadmap I1): depends on this task. It extends Resolution with attacker, crit_spent, cancelled, silent_buffs and dark_channeling, deletes the side-channel fields, and moves the ATTACK / SPELL pushes up to the commands. It keeps one stack.
- Related: task 088 (roadmap A5) and task 131 (roadmap I3): 088 owns the TriggerManager.gd header (task 082's assignment); 131 phase a edits the same `TriggerManager.fire` loop (depth counter, skip handlers unregistered mid-fire). Whichever lands second keeps the `TRIGGER` push around the call.
- Related: task 049: Resolution and ResolutionStack hold no back-reference, so they add no cycle and `teardown()` needn't touch them.
- Related: task 057 (BUG-double-death): edits the same lines of `resolve_minion_attack` (no strike or counter once a side has left the board). Whichever task lands second keeps the STRIKE / COUNTER pushes around the calls that remain.
- Related: task 060 (BUG-crit-leak): carries crit on the DamageInfo now. Task 129 keeps `is_crit` on the DamageInfo and moves the crit-spent flag onto the ATTACK resolution.
- Related: task 086 (roadmap A3): side-neutral trigger events. It edits `TriggerManager.fire` and adds enemy PRE/POST fires. Those go through `fire`, so they nest automatically.
- Related: task 110 (roadmap E3): its plan note says F1 "also widens payloads". It doesn't: the cause is a typed field, not a payload key.
- Related: task 133 (roadmap I5): extends `digest_text`. Keep the journal and causes out of the digest.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item F1.

## Summary

_(filled in at /task-done)_
