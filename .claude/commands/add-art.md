---
description: Wire up art for a card in EchoOfAbyss — finds the PNG in assets and sets art_path in CardDatabase.gd
argument-hint: <card_id>
---

Add art to a card in the EchoOfAbyss project at c:\Thunder\work\Projects\EchoOfAbyss.

**Note:** `battlefield_art_path` is no longer used. Do not search for `_small.png` / `_battlefield.png` files and do not add `battlefield_art_path`.

The card id is: $ARGUMENTS

Steps:
1. Search for `$ARGUMENTS.png` under `echoofabyss/assets/` recursively using Bash find.
2. If not found, tell the user the file is missing from the assets folder and stop.
3. Derive the `res://` path: replace everything up to and including `echoofabyss/` with `res://`.
4. In `echoofabyss/cards/data/CardDatabase.gd`, find the block for card id `$ARGUMENTS`.
5. If `art_path` is already set on that card, report it and stop.
6. Add `<var_name>.art_path = "<res_path>"` immediately before the `.faction = ` line of that card block.
7. Report what was done.
