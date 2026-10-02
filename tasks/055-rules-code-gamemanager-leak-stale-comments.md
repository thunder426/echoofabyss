---
id: "055"
title: Remove the GameManager read from CombatHandlers; fix stale Phase-4 comments
status: done
area: combat
priority: normal
started: 2026-10-02
finished: 2026-10-02
---

## Description

Found in the 2026-09-25 architecture review (issue 9 of 9). Re-verified 2026-09-30 at `3009a60`. Line numbers are from that commit.

Do this together with 054. Both edit the same lines of CombatHandlers.gd, and the log lines at :160 and :174 use the `_LOG_PLAYER` constant that 054 replaces.

1. **Rules code reads an autoload.**
   - `CombatHandlers.gd:159`, in `on_summon_passive_void_imp_boost`, does `var hero := HeroDatabase.get_hero(GameManager.current_hero)`. It is used only for the hero name in the log line at :160.
   - In the sim and the tests it names whatever hero the autoload holds.
   - This is the only code hit: grepping `GameManager.`, `UserProfile.` and `TestConfig.` over lint's `RULES_FILES` (plus RelicRuntime and BuffSystem) finds only comments otherwise. `PhaseTransition.gd:70`'s `EncounterDecks.get_deck` reads static data, not run state.
   - `state.player_hero_id` exists (CombatState.gd:1655) and `setup_combat` sets it (:2335).
   - The handler runs only on ON_PLAYER_MINION_SUMMONED (CombatSetup:251-252), and the state has no enemy hero id. So "the hero for `ctx.owner`" isn't possible; use `state.player_hero_id`.
2. **Hardcoded side.** `on_ritual_fired_ritual_surge(_ctx)` (:172-173) calls `state._summon_token("void_imp", "player")`.
   - ON_RITUAL_FIRED is only fired with owner "player" (CombatState:896, CombatHandlers:380; Enums.gd:99), and no enemy passive is "ritual_surge".
   - So this is an invariant clean-up with no behaviour change.
3. **Stale comments** describing the flow before Phase 4:
   - CombatState.gd:
     - :215-217, on `_has_talent`: "...populates `talents` from GameManager.unlocked_talents in CombatScene._ready";
     - :1644-1646 (`talents`), :1650 (`hero_passives`), :1653-1654 (`player_hero_id`, "Sim-only today").
   - VfxController.gd:145: "P4B: scene's wrapper mutates state …".
   - EffectStep.gd: :18 (`scene._armour_doubled_on_knight`), :44 (`scene._add_kill_stacks`), :47 (`scene._spell_cancelled`), :50 (`scene._void_mana_drain_pending`). All of these now live on CombatState.
   - CombatUI.gd: the section header at :32 and every "Subscriber to CombatState.…" header (:36, :51, :85, :92, :102, :112, :118, :124). The presenter calls these methods; nothing subscribes.
   - ARCHITECTURE.md:21 ("Signal X → refresh UI Y") and :319 ("L1–L9"; it is L1–L11 now, more after 050 and 051).
   - RelicRuntime.gd:5 ("from GameManager.player_relics") and CombatScene.gd:170.
## Out of scope (owner, 2026-09-30)

About 7 combat UI files read hero / talent info from `GameManager` instead of `state` or the `CombatConfig`:
- PipBar.gd:194-198
- SerisResourceBar.gd:47-48
- CombatUiStyle.gd:32, :173, :206, :214
- PlayerHeroPanel.gd:64, :98
- EnemyHeroPanel.gd:86, :179-181
- BoardSlot.gd:547

In normal play they show the same values, so they are left out of this task. They are recorded under roadmap item C5 (`ARCHITECTURE_ROADMAP.md`), for task 056 to groom.

## Proposed fix

1. Use `HeroDatabase.get_hero(state.player_hero_id)`.
2. Rename `_ctx` → `ctx` and call `state._summon_token("void_imp", ctx.owner)`.
3. Rewrite the stale comments to describe the current flow: `CombatConfig` → `setup_combat`, and presenter → CombatUI.
4. **Lint:** extend L1's rules-code scan with the regex `(?<![\w.])(GameManager|UserProfile|TestConfig)\.`.
   - L1 lives in `tools/lint/lint_engine.py`: `RULES_FILES` is at :89-102, and `scan_shell` (:215-222) already strips comments.
   - CombatConfig.gd reads GameManager by design (`from_game_manager`, :40-67) and stays outside `RULES_FILES`.

## Verification

- The new lint passes, with zero hits in rules code.
- `tools/run_checks.sh` green. The handler-order snapshot is unchanged, since no registrations change.

## Work log

- 2026-09-25: opened from the architecture review. Verified the GameManager read at CombatHandlers :159 and the stale comments at CombatState :215-217 / :1645-1654.
- 2026-09-30: re-verified at `3009a60` and rewritten.
  - "Hero for `ctx.owner`" isn't buildable, so use `state.player_hero_id`.
  - The Ritual Surge hardcode is style, not a bug.
  - Corrected line numbers and added the missed stale comments (EffectStep:18, the CombatUI headers, ARCHITECTURE.md:21/:319, RelicRuntime:5).
  - Listed the other UI GameManager readers as an open scope decision.
  - Bundled with 054.
- 2026-09-30: owner decision: the UI readers are out of scope, moved to roadmap C5.
- 2026-10-02: implemented, steps 1–4.
  - `on_summon_passive_void_imp_boost` names the hero from `state.player_hero_id`; `on_ritual_fired_ritual_surge(ctx)` summons for `ctx.owner`.
  - Comments rewritten to the current flow: CombatState `_has_talent` / `talents` / `hero_passives` / `player_hero_id` (CombatConfig → setup_combat); VfxController's Abyssal Plague note (the engine has resolved it; the presenter plays each minion's captured events as the wave reaches it); EffectStep :18, :44, :47, :50 (`scene.` → `state.`; the mana-drain step is no longer "player-only", EffectResolver sets either side's flag); RelicRuntime header; CombatUI's section header and every handler header (each named by the journal event the presenter plays; nothing subscribes); ARCHITECTURE.md's wiring row and the gate line (L1–L11, plus Parity). Also fixed: CardDatabase.gd:443 (`scene._armour_doubled_on_knight`), and deleted CombatScene's empty "Enemy passive state — populated from GameManager…" section.
  - Found: `CombatUI.on_state_minion_stats_changed` has no caller (slots follow the journal's stat snapshots since task 046). Its header now says so; deleting it fits task 132's dead-code sweep.
  - Lint: L1 now also flags `GameManager.` / `UserProfile.` / `TestConfig.` in RULES_FILES (comments stripped). 0 hits; restoring the old read gives exactly one L1 error at CombatHandlers.gd:159. TESTING.md's L1 row updated.
  - Gate green: lint 0, 1121 tests, LiveSmoke OK, Parity 24/24; handler-order snapshot unchanged.
  - Fingerprint Acts 1–4 identical to `af5c599`.
- 2026-10-02: closed.

## Summary

Rules code no longer reads an autoload: the Void Imp boost log names the hero from `state.player_hero_id`, Ritual Surge summons for `ctx.owner`, and lint L1 now fails on `GameManager.` / `UserProfile.` / `TestConfig.` in rules code. The stale pre-Phase-4 comments (CombatState, EffectStep, VfxController, CombatUI, RelicRuntime, CombatScene, CardDatabase, ARCHITECTURE.md) describe the current CombatConfig → setup_combat and presenter → CombatUI flow. Behaviour-neutral: BalanceSimBatch Acts 1–4 identical.
Follow-ups: `CombatUI.on_state_minion_stats_changed` has no caller (task 132's dead-code sweep). The UI `GameManager` readers stay with roadmap C5 / task 103.

