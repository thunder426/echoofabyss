---
description: Process champion art from assets/tmp — scans for portrait and card art PNGs, moves them to correct folders, wires them up, and cleans tmp
argument-hint: [encounter_name] or leave empty to process all champion files in tmp
---

Process champion art files in the EchoOfAbyss project at c:\Thunder\work\Projects\EchoOfAbyss.

**Note:** `battlefield_art_path` is no longer used. Ignore any `*_battlefield.png` files — do not move them, do not wire them up.

## Mode selection

- If `$ARGUMENTS` is empty, "batch", or "all": **scan mode** — scan `echoofabyss/assets/tmp/` for all champion-related PNGs and process them all.
- Otherwise: **single mode** — process only files for the encounter `$ARGUMENTS`.

## Scan mode — auto-detect from tmp

1. **List** all `.png` files in `echoofabyss/assets/tmp/`.
2. **Classify** each file by pattern:
   - `*_portrait.png` (but NOT starting with `champion_`) → enemy portrait. The encounter name is the filename minus `_portrait.png`.
   - `champion_*_battlefield.png` → **skip** (battlefield art is no longer used). Note in report.
   - `champion_*.png` (not matching battlefield) → champion card art. The champion id is the filename minus `.png`.
3. **Group** by encounter: extract the encounter name from champion ids by stripping the `champion_` prefix (e.g. `champion_corrupted_broodlings` → `corrupted_broodlings`). Match portraits to encounters by their filename.
4. **For each encounter**, run the single-encounter processing steps below.
5. **Report** a full summary table of everything processed.

## Single-encounter processing

### Step 1 — Identify the encounter and champion

1. In `echoofabyss/shared/scripts/GameManager.gd`, find the `_build_encounter` match block whose passives array contains `"champion_<encounter_name>"`.
2. Note the fight index number.
3. In `echoofabyss/cards/data/CardDatabase.gd`, find the champion card block for id `"champion_<encounter_name>"`.
4. Read the card's `.faction` and `.clan` to determine the art subfolder:
   - Feral Imp clan → `feral_imp_clan/`
   - Abyss Order with no specific clan → `abyss_order/`
   - Cards with `abyss_cultist` tags → `abyss_cultist_clan/`
   - Other → match existing art paths for the same faction

### Step 2 — Enemy portrait

1. Check if `echoofabyss/assets/tmp/<encounter_name>_portrait.png` exists.
2. If found:
   - Move to `echoofabyss/assets/art/enemies/portraits/<encounter_name>_portrait.png`
   - In `GameManager.gd`, find the `_make_encounter` call for this fight. Add the portrait path as the last argument (`eportrait`): `"res://assets/art/enemies/portraits/<encounter_name>_portrait.png"`.
   - If the call already has an `eportrait` value, update it. If not, append it after the ai_profile argument.
   - Delete the file from `assets/tmp/`.
3. If not found, report missing and continue.

### Step 3 — Champion card art

1. Check if `echoofabyss/assets/tmp/champion_<encounter_name>.png` exists.
2. If found:
   - Move to `echoofabyss/assets/art/minions/<subfolder>/champion_<encounter_name>.png`
   - In `CardDatabase.gd`, if `art_path` is already set on this champion, report and skip.
   - Otherwise add `<var>.art_path = "res://assets/art/minions/<subfolder>/champion_<encounter_name>.png"` immediately before the `.faction` line.
   - Delete the file from `assets/tmp/`.
3. If not found, report missing and continue.

### Step 4 — Report

Print a summary table per encounter:

| Encounter | File | Status | Destination |
|-----------|------|--------|-------------|
| name | portrait / card art | moved / missing / already set | path |

If any `*_battlefield.png` files were found in tmp, list them as "skipped (battlefield_art deprecated)" — do not move or delete them; leave them in tmp so the user can clean up manually.

## Important notes

- Always use `mv` (not `cp`) — clean up tmp.
- Never overwrite existing destination files without warning the user.
- The variable name in CardDatabase.gd is the champion card id (e.g. `champion_corrupted_broodlings`). Read the actual var name from the code.
- Portrait paths go in GameManager.gd; card art paths go in CardDatabase.gd. Battlefield art is deprecated — ignore those files.
- If tmp is empty, just report "No files found in assets/tmp/" and stop.
