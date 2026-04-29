---
description: Scan CardDatabase.gd for cards without art, list them with Midjourney prompts
---

Scan `echoofabyss/cards/data/CardDatabase.gd` (the single source of truth) and identify all cards that are missing art.

A card is "missing art" if:
1. It has no `art_path` set, OR
2. Its `art_path` is set to `""`

Also flag non-neutral minions (MinionCardData) that have `art_path` but are missing `battlefield_art_path`.

**Note**: Neutral minions (faction = "neutral") do NOT need `battlefield_art_path` — their card art is already 1:1 and is reused as battlefield art. Only flag non-neutral minions missing battlefield art.

## Output Format

### Section 1: Cards with NO art at all (excluding champions)

For each non-champion card missing art, output:

```
### <card_name> (id: <card_id>)
- **Type**: Minion / Spell / Trap / Environment
- **Cost**: <essence_cost>E / <mana_cost>M / <void_spark_cost> Sparks (show whichever costs are non-zero)
- **Stats**: <ATK>/<HP> (minions only)
- **Effect**: <description field from the card, or "vanilla" if empty>
- **Card fantasy**: <1-2 sentence description of what this card represents based on its name, description, stats, and faction>

```
<card_id>: <subject description>, <style keywords>, <lighting>, <mood>, --ar X:Y --s 250 --q 2
```
```

### Section 2: Champions with NO art at all

For each champion (is_champion = true) missing art, output the same format as Section 1 but also include:
- **Act**: which act the champion belongs to (Act 3 or Act 4, based on code comments)

#### Midjourney Prompt Rules

- **Style**: Dark fantasy card game art. Dramatic lighting, painterly style, dark color palette with glowing accents (void purple, abyssal green, blood red). Similar to Darkest Dungeon / Magic: The Gathering dark sets.
- **Aspect ratio**: All cards use `--ar 1:1`.
- **Each prompt must be distinct** — avoid repeating compositions. Vary poses, angles, lighting direction, and background elements.
- **Format**: The prompt must be on its own line inside a single-backtick code block so the user can copy it directly. **Do NOT include any leading slash command** (no `/imagine prompt:`, no leading `/` — Midjourney will break). Instead, begin the prompt with the card's id followed by a colon, then the subject description. Format: `<card_id>: <subject description>, <style keywords>, <lighting>, <mood>, --ar X:Y --s 250 --q 2`
- **Subject**: Describe the creature/spell visually based on the card's fantasy. Be specific about visual features (armor, weapons, aura, body type, expression).
- **DO NOT** include text, card frames, UI elements, or card borders in prompts.
- **Champions** should look more imposing/powerful than regular minions — larger scale, more dramatic effects. **Each champion prompt MUST depict the champion actively performing its signature attack or spell-casting action** — not a static portrait or idle pose. Derive the action from the card's effect/aura text (e.g. an aura-buffer channeling an empowering pulse; a damage-dealer mid-swing; a summoner casting a rift). The prompt must specify:
  - A **specific signature weapon or casting implement** unique to that champion (polearm, runed greatsword, focus orb, banner-staff, skull-censer, twin curved daggers, etc. — vary across champions).
  - A **specific attack/spell glow** tied to that weapon or hands — either an **attack-slash glow** (motion-trail arc of void purple / abyssal green / blood red along the weapon's swing path) or a **spell-casting glow** (radiant energy gathered at palms, orb, or weapon tip with runic light leaking outward).
  - An **action pose** (mid-swing, lunging strike, arms raised channeling, palm thrust, banner slam, etc.) — never a neutral standing pose.
  - The result: each champion reads as a **hero action shot**, visually distinct from plain minion portraits.
- **Spirits** should look ethereal, translucent, with void energy crackling through them.
- **Demons** should look twisted, corrupted, with dark flesh and glowing eyes.
- **Humans** should look like dark fantasy cultists, warriors, or mages.

### Section 4: Summary

- Total cards missing all art: X
- Total champions missing all art: X