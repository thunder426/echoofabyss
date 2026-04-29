# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Echo of Abyss** — single-player roguelike deckbuilder, Godot 4 (GDScript), pre-alpha. Solo dev project. Run via Godot editor; no build scripts.

- Engine: Godot 4.6, GL Compatibility renderer, 1920×1080
- Config: `echoofabyss/project.godot`
- Design docs: `design/master_doc/` (DESIGN_DOCUMENT.md, CARD_LIBRARY.md)

## Where things live

**Read [`design/master_doc/ARCHITECTURE.md`](design/master_doc/ARCHITECTURE.md) before grepping the codebase.** It has a quick file-finder table ("looking for X → look in Y"), the autoload list, the combat state/shell/sim split, signal contracts on CombatScene/CombatState/TurnManager/CombatManager, and the architectural invariants (symmetric handlers, sim parity, declarative effects, animation gating). Keep it in sync when you add a new sub-system, autoload, or major file.

## GDScript Rules

- **Always use `: Type =` not `:=`** when reading from untyped Array or Dictionary. Type inference from untyped collections causes silent errors.

## Adding New Cards

1. Define card data in `CARD_LIBRARY.md` (source of truth).
2. Add a new `CardData` subclass instance in `cards/data/CardDatabase.gd`.
3. If the card has art, use the `/add-art` skill to wire up `art_path` (and `battlefield_art_path` for minions).
4. Use declarative `effect_steps` (EffectStep objects) — avoid adding to HardcodedEffects.gd.
5. Follow card description style rules in `design/master_doc/CARD_DESCRIPTION_STYLE.md`.
6. For damage-dealing steps (DAMAGE_HERO / DAMAGE_MINION), set `damage_school` only when the card has deliberate flavor (e.g. `"damage_school": "VOID"`). Default `NONE` is correct for generic spells and minion-emitted effects. See `design/DAMAGE_TYPE_SYSTEM.md`.

## Adding New Trigger Handlers

Register via `TriggerManager.register_handler(TriggerEvent.X, callable, priority)` inside `CombatSetup.gd` (for real combat) and `sim/SimTriggerSetup.gd` (for simulation). Both must stay in sync.
