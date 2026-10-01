---
id: "053"
title: Gate the cheat panel and test config out of release builds
status: backlog
area: meta
priority: high
started:
finished:
---

## Description

Found in the 2026-09-25 architecture review (issue 7 of 9). Re-verified 2026-09-30 at `3009a60`. Line numbers are from that commit.

Debug tooling ships in every build.

### The cheat panel

- `CombatScene.gd:231-233` always creates `CheatPanel`.
- `CombatInputHandler.gd:468`: F12, or a bare **C** when not typing, toggles it. `:470` reads `_scene._cheat.visible` on every ESC press.
- Its actions go beyond the current fight:
  - **Fight:** Dmg Player / Dmg Enemy (CheatPanel.gd:137-149) and Kill Enemy (:151-156), all through `combat_manager.apply_hero_damage`, outside the commands. Also heal (:160-170), refill resources (:173-178) and add card (:279-292).
  - **Run and save:**
    - unlock talent (:302-322) writes `GameManager.add_talent_point / unlock_talent` and re-runs `CombatSetup.setup`;
    - grant relic (:333-348) writes `GameManager.player_relics`;
    - switch enemy (:368-376) writes `current_enemy` / `run_node_index` and calls `go_to_scene`, which auto-saves.

So in a release build, one key press gives the player an instant win and permanent edits to the save. The panel's damage also bypasses `command_log`, so those fights don't replay.

### TestConfig and the debug launch path

- **The `TestConfig` autoload** (project.godot:27) always loads.
- **`CombatScene._apply_test_config`** (:1031-1095) writes state directly, but only `if TestConfig.enabled` (:234).
  - Only `TestConfig.launch()` sets `enabled` (debug/TestConfig.gd:87-88), and only TestLaunchScene calls it (:203).
  - So it does nothing in normal play.
- **The `start_new_run` fallback:** `CombatScene._ready` silently calls `GameManager.start_new_run` (:181-182) when there's no active run. It is reachable only by launching the scene directly (F6), because loading a save sets `run_active` (UserProfile.gd:73).

### Exports and references to debug/

- **No export preset.** There is no `export_presets.cfg`, and `.gitignore:4-5` ignores it on purpose ("contains paths, not source").
- **References to `debug/`:** non-debug code reaches it only through the autoload line and the `TestConfig.*` reads in CombatScene (:234, :1033-1095). There is no `preload` or `load` of `res://debug`, and no debug `class_name` is used outside `debug/`.
- **Existing patterns:** `OS.is_debug_build()` is used once (VfxSequence.gd:203), and there is no dev-tools project setting. CheatPanel is already exempt from L8 (lint_engine.py:290).

## Open decision (owner)

- **The export filter:**
  - commit an `export_presets.cfg`, which means changing the .gitignore rule; or
  - keep presets local and document the `debug/*` exclude in TESTING.md.

## Proposed fix

1. **Debug builds only.** `CombatScene` creates CheatPanel only when `OS.is_debug_build()`. In CombatInputHandler, guard the toggle **and** the ESC branch (`_scene._cheat != null and ...`); the ESC read would crash on a null panel.
2. **Drop the bare C binding** and keep F12. Update the "[F12 / C]" label (CheatPanel.gd:90) and the doc comment (CombatInputHandler.gd:459).
3. **Decouple CombatScene from TestConfig before excluding anything.**
   - Move the apply step into debug code: TestLaunchScene passes its overrides through `CombatConfig`, or TestConfig applies them through a hook it registers. CombatScene then has no `TestConfig.` references.
   - Excluding `debug/*` while CombatScene still references it would fail to compile, or crash `_ready`, in release.
4. **Take the TestConfig autoload out of release:**
   - register it at runtime from debug code; or
   - keep a no-op stub outside `debug/`.

   Don't rely on feature-tag overrides for autoload entries; it's unverified that Godot honours them.
5. **Make the `start_new_run` fallback debug-only.** In release, `_ready` returns before `setup_combat` (`current_enemy` may be null) and uses `call_deferred` to change scene to the main menu, with an error.
6. **Export filter:** exclude `debug/*`, per the decision above.
7. **Optional:** mark a fight "tainted" when the cheat panel acts, so parity and replay tooling skip it.

## Verification

- **Release build.** This needs a release export template (`--export-release`): `is_debug_build()` is false only there, so `--no-debug` isn't a real test. Check:
  - no cheat panel; C and F12 do nothing; ESC still works;
  - TestConfig is absent;
  - launching CombatScene directly returns to the menu.
- **Editor / debug run:** F12 toggles the panel, and TestLaunchScene still applies its config.
- `tools/run_checks.sh` green. The tests run on a debug binary and never touch `_cheat`, and LiveSmoke and Parity call `start_new_run` themselves.

## Related

- 047 needs an export check for the deck JSON; do it with the same preset.

## Work log

- 2026-09-25: opened from the architecture review. Verified the C/F12 binding at CombatInputHandler :468 and the unconditional CheatPanel creation at CombatScene :231.
- 2026-09-30: re-verified at `3009a60` and rewritten.
  - The panel also edits GameManager and the save, which makes this worse than first stated.
  - TestConfig does nothing in normal play; the replay concern is the cheat panel's.
  - Step 4 as written would crash release builds, so CombatScene is decoupled first.
  - Added the ESC guard.
  - Noted the deliberate `.gitignore` of export presets.
  - `--no-debug` isn't a valid check.
