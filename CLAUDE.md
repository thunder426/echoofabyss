# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Echo of Abyss** — single-player roguelike deckbuilder, Godot 4 (GDScript), pre-alpha. Solo dev project. Run via Godot editor; no build scripts.

- Engine: Godot 4.6, GL Compatibility renderer, 1920×1080
- Godot project root = repo root. Config: `project.godot`. Main scene: `res://ui/MainMenu.tscn`.
- Master design docs: `design/master_doc/` — `DESIGN_DOCUMENT.md`, `CARD_LIBRARY.md`, `ARCHITECTURE.md`, `CARD_DESCRIPTION_STYLE.md`.
- Feature design docs (read before touching the relevant subsystem): `design/DAMAGE_TYPE_SYSTEM.md`, `design/TRAP_RUNE_RITUAL_SYSTEM.md`, `design/REWARD_SYSTEM_DESIGN.md`, `design/SERIS_HERO_DESIGN.md`, `design/DAGAN_HERO_DESIGN.md`, `design/FACTION_FREE_CITIES_DESIGN.md`, `design/CARD_FRAME_DESIGN_REGULATION.md`, `design/CASTING_GLYPH_DESIGN.md`.

## Where things live

**Read [`design/master_doc/ARCHITECTURE.md`](design/master_doc/ARCHITECTURE.md) before grepping the codebase.** It has a quick file-finder table ("looking for X → look in Y"), the autoload list, the combat state/shell/sim split, signal contracts on CombatScene/CombatState/TurnManager/CombatManager, and the architectural invariants (symmetric handlers, sim parity, declarative effects, animation gating). Keep it in sync when you add a new sub-system, autoload, or major file.

## GDScript Rules

- **Always use `: Type =` not `:=`** when reading from untyped Array or Dictionary — `:=` infers `Variant` from untyped collections and causes silent errors. Example: `var m: MinionInstance = state.player_slots[i]`, never `var m := state.player_slots[i]`.

## Testing & simulation

`design/TESTING.md` is the inventory of every test harness, simulator, and debug tool, with run commands. The two defaults:

- **Correctness** — `res://debug/tests/RunAllTests.tscn` (~10s, ~500 assertions across 4 layers). Use `--filter <substring>` to scope. New cards/handlers should ship with a probe in `CardEffectTests.gd` or `TriggerHandlerTests.gd`.
- **Balance** — `res://debug/BalanceSimBatch.tscn` is the default sim entry point (full Act × profile matrix). Reach for it first; use `DebugSingleSim` only for step-by-step debug logs.

Both run headless via `godot --headless --path . <scene>`.

## Adding New Cards

1. Define card data in `CARD_LIBRARY.md` (source of truth).
2. Add a new `CardData` subclass instance in `cards/data/CardDatabase.gd`.
3. If the card has art, use the `/add-art` skill to wire up `art_path` (and `battlefield_art_path` for minions).
4. Use declarative `effect_steps` (EffectStep objects) — avoid adding to HardcodedEffects.gd.
5. Follow card description style rules in `design/master_doc/CARD_DESCRIPTION_STYLE.md`.
6. For damage-dealing steps (DAMAGE_HERO / DAMAGE_MINION), set `damage_school` only when the card has deliberate flavor (e.g. `"damage_school": "VOID"`). Default `NONE` is correct for generic spells and minion-emitted effects. See `design/DAMAGE_TYPE_SYSTEM.md`.

## Adding New Trigger Handlers

Register via `TriggerManager.register_handler(TriggerEvent.X, callable, priority)` inside `CombatSetup.gd` (for real combat) and `sim/SimTriggerSetup.gd` (for simulation). Both must stay in sync.
