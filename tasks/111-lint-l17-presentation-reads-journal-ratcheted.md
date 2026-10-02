---
id: "111"
title: Lint L17: presentation reads the journal (ratcheted engine-read count in UI files)
status: backlog
area: tooling
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item E4 (`design/refactors/ARCHITECTURE_ROADMAP.md` §E, direction 4). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

ARCHITECTURE.md invariant 7 says "Nothing on screen changes before the presenter plays the event that explains it". The lint enforces only the other half: L8 stops presentation from *mutating* the engine (tools/lint/lint_engine.py:285-299). Nothing stops presentation from *reading* the live `CombatState`, and every bug in roadmap §E came from such a read. Tasks 070, 071, 109 and 110 remove the existing reads; without a ratchet, new ones keep arriving while they do.

### Current reads

Pattern A is `\b(state|st)\.[a-z_]`, comments stripped, not counting `state.journal` / `state.journaled` (the presenter's input). Run over L8's presentation file set (lint_engine.py:287-292) minus the input files, it counts these lines:

| File | Lines | What they read | Removed by |
|---|---|---|---|
| combat/ui/PipBar.gd | 12 | :201-202 setup; :293-294, :343-350 blink; :517-518 Flesh; :707-708 Forge | task 109 (E2a) |
| combat/board/CombatUI.gd | 11 | :49, :58 enemy panel; :67 hero badges; :156, :174, :189-190, :199-200, :206-207 resources, end turn, hand | tasks 071, 109 |
| combat/ui/EnemyHeroPanel.gd | 7 | :434-442 essence, mana, hand; :184, :760 `enemy_passives` (builds the passive icon / champion tooltip) | task 071; :184 / :760 are setup reads |
| combat/effects/vfx/CombatVFXBridge.gd | 6 | :117 ACP aura pulse finds the champion on the live `enemy_board`; :260, :262 rune slot; :1185 `state._minion_has_tag` (card data only); :1354-1355 Void Rune bolt origin | task 070 (:260, :262, :1354-1355); :117 open; :1185 harmless |
| combat/ui/SerisResourceBar.gd | 4 | :222, :226-227 Flesh and the Corrupt Flesh flag; :236 `cmd_hero_skill` (a button's command) | task 109 (E2a); :236 is input |
| combat/board/CombatPresenter.gd | 2 | :241 PHASE_TRANSITION panel push; :305 `state.enemy_passives` (summon reveal extra) | task 071 (:241) |
| combat/board/TrapEnvDisplay.gd | 2 | :109 environment; :137 traps | tasks 109 (E2c), 070 |
| combat/board/LargePreview.gd | 2 | :42-43 `_relic_cost_reduction` | task 109 (E2a) |
| combat/ui/CombatUiStyle.gd | 1 | :322 `enemy_passives` tooltip | setup read |
| combat/effects/vfx/VfxController.gd | 1 | :124 `_minion_has_tag` (card data only) | harmless |
| combat/board/CounterWarning.gd | 1 | :44 `_player_spell_counter` | task 109 (E2b) |

Excluded as input files, whose engine reads validate commands: CombatInputHandler.gd (35 lines) and Targeting.gd (6). Task 113 (roadmap E7) makes Targeting compare the engine with the view on purpose. CombatScene.gd (103 lines) is outside L8's set and mixes input, wiring and presentation. Its display reads (`show_turn_started`, :417-419) are fixed by task 109.

### Reads pattern A can't see

- **BoardSlot** reads the live minion, not `state.`. Pattern B, `minion\.(has_\w+|can_attack|formation_fired|critical_strike_stacks|current_atk|current_shield|state)\b|BuffSystem\.(sum_type|count_type|net_armour|has_type)\(minion`, counts 19 lines in BoardSlot.gd at `404b51c` (:305, :445, :525, :583, :652, :661, :678, :682-704, :716, :737, :739). Task 110 removes them.
- **Scene helpers that read state**, for example `_scene._spell_mana_discount()` (CombatScene.gd:1291-1295, live `state.player_board`), called from CombatUI.gd:199 and LargePreview.gd:42. Not covered by this task; listed in the lint's docstring as a known gap.

## Proposed fix

1. **New rule L17** in tools/lint/lint_engine.py (provisional; take the next free number if the landing order differs), `scan_presentation_reads`.
   - File set: L8's presentation set (lint_engine.py:287-292) minus CombatInputHandler.gd and Targeting.gd.
   - If task 140 (roadmap J4) has landed with its derived file list, use that list minus the input files and CombatScene.gd.
2. **Pattern A** over every file in the set:
   - skip comments (`strip_comment`);
   - don't count `state.journal`, `state.journaled`, command calls `state.cmd_\w+\(` (a button issuing a command is input), or the pure card-data helpers `_minion_has_tag` / `_card_has_tag`. Better: make those two helpers static on CombatState and call them on the class.
3. **Pattern B** over BoardSlot.gd only, as a first cut. Widen it to other files that hold a `MinionInstance` if new reads show up.
4. **Ratchet.**
   - `L17_BASELINE = {path: count}` with the counts taken when the rule lands. Tasks 069, 070 and 071 may land first and change them.
   - Fail when a file's count is above its baseline, or when a file not in the dict has any hit.
   - Print "lower the baseline" when a count drops below it.
   - Use the same per-file baseline shape as task 140's L10 rewrite, and share the counting helper with the other ratchets from this grooming pass: task 087 (L16), task 122 (L18), task 099 (L19).
5. **Setup marker.** A line ending in `# lint: setup` doesn't count. Use it for reads that build a widget once at setup: EnemyHeroPanel.gd:184 and :760, CombatUiStyle.gd:322.
6. **Enforce and document.**
   - Add L17 to `ENFORCED` (:107) and to the module docstring, with the known gaps (scene helpers, live-minion reads outside BoardSlot).
   - ARCHITECTURE.md invariant 7 gains "(lint L17, a ratchet)".
   - Add a row to design/TESTING.md's lint table.
7. **Ratchet down.** Tasks 070, 071, 109 and 110 lower the baseline in their own commits. When only `# lint: setup` lines are left, delete the baseline dict, so any hit fails.

## Verification

- `python3 tools/lint/lint_engine.py` reports 0 L17 errors on the branch.
- Seeded negatives: make each local edit, run the lint, then revert it, and record the output in the work log.
  - `var x: int = _scene.state.enemy_hp` in CombatUI.gd: L17 fails, naming the file and the count over the baseline.
  - `if minion.has_guard():` added to BoardSlot.gd: L17 fails (pattern B).
  - The same CombatUI line ending in `# lint: setup`: passes.
  - `state.journal.size()` in CombatPresenter.gd: passes.
- `tools/run_checks.sh` green.
- Behaviour-neutral: only tools/lint/ and docs change, no game code, so the balance fingerprint (design/TESTING.md "Refactor / extraction work") can't move and needs no run.

## Related

- Related: task 070 (roadmap E1a), task 071 (roadmap E1b), task 109 (roadmap E2), task 110 (roadmap E3) — each lowers this rule's baseline in its own commit.
- Related: task 140 (roadmap J4) — derives L8's file list and rewrites L10 as a per-file baseline; reuse both.
- Related: task 087 (roadmap A4, L16), task 122 (roadmap G7, L18), task 099 (roadmap B7, L19) — the other ratchet rules; share the counting helper.
- Related: task 113 (roadmap E7) — why Targeting and CombatInputHandler are excluded.
- Related: task 112 (roadmap E6) — adds `state._log(` to L8 (presentation mustn't journal); a separate rule from this one.
- Related: task 103 (roadmap C5) — adds the GameManager-read pattern to L8 over the same file set.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item E4.
  - Re-ran the per-file counts at `404b51c` with the presenter's journal reads excluded: CombatPresenter has 2 engine reads, not 11.
  - Added pattern B for BoardSlot (19 lines), and the exclusions for command calls and the card-data tag helpers.

## Summary

_(filled in at /task-done)_
