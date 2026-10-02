---
id: "126"
title: Move the shared textured button style into global_theme.tres; delete the 5 _make_btn_style copies
status: backlog
area: ui
priority: low
started:
finished:
---

## Description

From the 2026-09-25 architecture review, roadmap item H5 (`design/refactors/ARCHITECTURE_ROADMAP.md` §H), narrowed to buttons by grooming. Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

One textured button look is rebuilt in code by five scripts, and a sixth copy sits in a scene. The project theme holds only a font.

### The copies

- **Four identical builders** (`_make_btn_style(path) -> StyleBoxTexture`, texture margins 16 on all sides; the function bodies have the same md5): MainMenu.gd:109, TalentSelectScene.gd:434, EncounterLoadingScene.gd:306, EscMenu.gd:137.
- **One variant:** HeroSelectScene.gd:450, with `texture_margin_top = 4.0`, `texture_margin_bottom = 4.0`, `content_margin_top = 2.0` and `content_margin_bottom = 2.0`.
- **The path constants** for `res://assets/art/buttons/button_{normal,hover,pressed}.png` are repeated in all five scripts (e.g. MainMenu.gd:14-16, `_BTN_PATH` / `_BTN_HOVER_PATH` / `_BTN_PRESSED_PATH`; TalentSelectScene.gd:7-9 and EncounterLoadingScene.gd:13-15 name them `_BTN_NORMAL` / `_BTN_HOVER` / `_BTN_PRESSED`).
- **A scene copy:** MainMenu.tscn:10-29 defines the same three StyleBoxTextures, and its five buttons set `theme_override_styles/{normal,pressed,hover,disabled}` from them (:110-113, :128-131, :146-149, :164-167, :181-184). `_apply_menu_assets` (MainMenu.gd:117-126, called at :22) then overwrites all five at runtime with code-built copies.
- **The applying code** also differs. TalentSelectScene, EncounterLoadingScene, HeroSelectScene and MainMenu set a `disabled` style (normal texture); EscMenu's `_make_button` (:120-135) doesn't. Every copy guards each texture with `ResourceLoader.exists`.

`ui/theme/global_theme.tres` (8 lines; project.godot:40 `theme/custom="res://ui/theme/global_theme.tres"`) holds only `default_font` (CinzelDecorative-Regular) and `default_font_size = 16`.

### Consequence

Restyling the menu buttons means six edits, and the copies have already drifted (the `disabled` state). There is no visible bug today.

### Out of scope

- The other theme overrides: 209 `add_theme_*_override` calls across 11 meta-scene scripts (about 70 font sizes, 49 font colours, 34 separations, 31 styleboxes). Grooming deferred that consolidation (H5b) to the next UI or art pass, when the palette is decided anyway. Start it with the duplicated palette: ShopScene.gd:16-19 and EncounterLoadingScene.gd:7-10 hold the same purple / gold / light / dim colours.
- Making the textured style the default for **every** Button (shop, reward, combat, debug) would change how those screens look. That is a visual call for the owner. This task uses a type variation, so only the buttons that opt in change.
- Static layout of EnemyHeroPanel / PipBar / CardVisual: task 127 (roadmap H6) and task 103 (roadmap C5).

## Proposed fix

1. **global_theme.tres:** add two type variations, both with `base_type = &"Button"`:
   - `AbyssButton`: `normal`, `hover`, `pressed` and `disabled` StyleBoxTextures from `button_normal.png`, `button_hover.png`, `button_pressed.png` and `button_normal.png`, texture margins 16 on all sides;
   - `AbyssButtonCompact`: the same textures with texture margins 16 / 4 / 16 / 4 (left / top / right / bottom) and content margins top and bottom 2, as HeroSelectScene.gd:450 builds them.

   Don't put a `focus` style in either; buttons keep the default focus look they have today.
2. **Scripts:** replace `_apply_btn_style` / `_make_btn_style` and the `_BTN_*` constants with `btn.theme_type_variation = &"AbyssButton"` in MainMenu.gd, TalentSelectScene.gd, EncounterLoadingScene.gd and EscMenu.gd, and `&"AbyssButtonCompact"` in HeroSelectScene.gd. Keep each script's font, size and colour overrides; they are out of scope.
3. **MainMenu.tscn:** delete the three StyleBoxTexture sub-resources (:10-29), the three texture `ext_resource` lines if nothing else uses them (:5-7), and the four `theme_override_styles/{normal,pressed,hover,disabled}` lines per button. Set `theme_type_variation = &"AbyssButton"` on the five buttons. Keep `StyleBoxFlat_focus` and its `theme_override_styles/focus` lines. Delete `_apply_menu_assets` (MainMenu.gd:117-126; it does nothing but this) and its call at :22.
4. **No `ResourceLoader.exists` fallback.** The textures are in the repo, and the Godot import step in `tools/run_checks.sh` fails loudly if a theme references a missing file.
5. EscMenu is a CanvasLayer autoload (EscMenu.gd:4). Its buttons resolve the project theme like any other Control, so the variation applies there too; check it in the visual QA.

## Verification

- `grep -rn "_make_btn_style\|_apply_btn_style\|button_normal.png" --include='*.gd' --include='*.tscn' --include='*.tres' .` (excluding `.godot/`) → only `ui/theme/global_theme.tres`.
- Theme probe (ScenarioTests, or MetaTests once task 052 has added it): `var t: Theme = load("res://ui/theme/global_theme.tres")`; `t.is_type_variation(&"AbyssButton", &"Button")`; `t.get_stylebox(&"normal", &"AbyssButton")` is a StyleBoxTexture whose `texture.resource_path` ends in `button_normal.png` with `texture_margin_top == 16`; `AbyssButtonCompact`'s has `texture_margin_top == 4` and `content_margin_top == 2`.
- Manual visual QA: before/after screenshots of MainMenu, HeroSelect, TalentSelect, EncounterLoading and the ESC menu in normal, hover, pressed and disabled states (a locked talent and the encounter button after it is pressed, EncounterLoadingScene.gd:265, show `disabled`). They should match; the ESC menu's buttons gain a `disabled` style, which no ESC button uses today.
- `tools/run_checks.sh` green.
- Behaviour-neutral: meta UI only, no rules, sim or AI code changes, so the balance fingerprint can't move.

## Related

- Related: task 080 (roadmap H4) — deletes MapScene, whose 7 overrides were part of the 209 count.
- Related: task 127 (roadmap H6) — moves EnemyHeroPanel's static overrides into a scene or the theme; it can add its own type variations to the same theme file.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item H5, narrowed to buttons. Re-checked at `404b51c`: four identical copies plus the HeroSelect variant (md5 of the function bodies), and the MainMenu.tscn copy that MainMenu.gd overwrites at runtime. The 209-override consolidation (H5b) is deferred.

## Summary

_(filled in at /task-done)_
