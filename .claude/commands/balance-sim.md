---
description: Run full balance simulation matrix for Act 1 and/or Act 2 encounters
argument-hint: [--act 1|2] [--fight N] [--runs N] [--preset swarm|voidbolt_burst|death_circle]
---

Run the batch balance sim using BalanceSimBatch.tscn. This auto-loads decks from PresetDecks.gd and enemy encounters from GameManager — no hardcoded card lists.

Arguments from user: $ARGUMENTS

Default (no args): run both Act 1 + Act 2, all 3 presets, all relics, 200 runs each.

Argument translation — convert natural language to flags before passing:
- "fight 6 only" → `--fight 6`
- "act 2 only" → `--act 2`
- "swarm only" → `--preset swarm`
- "500 runs" → `--runs 500`

Run this command:

```bash
"C:\Thunder\work\Projects\Godot\Godot_v4.6.1-stable_win64_console.exe" --headless --path "C:\Thunder\work\Projects\EchoOfAbyss\echoofabyss" "res://debug/BalanceSimBatch.tscn" -- $ARGUMENTS 2>&1 | grep -v "codec\|Godot Engine\|Supported\|backtrace\|at:\|ERROR.*Audio\|SCRIPT ERROR.*current_scene\|WARNING\|decode"
```

Use a 600000ms timeout. Present ALL individual rows to the user — do not aggregate or summarize unless asked.
