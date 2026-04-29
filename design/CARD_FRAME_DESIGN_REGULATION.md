# Card Frame Design Regulation

This document is the strict source of truth for all future card frame design work in Echo of Abyss.

Going forward, all newly created or revised card frame assets must follow these rules unless this document is explicitly updated first.

## Purpose

The goal is to keep all card frames:

- visually unified across factions and card types
- structurally consistent in-game
- readable at gameplay size
- compatible with the real `CardVisual` runtime template

This regulation exists because "looks similar" is not enough. Frame assets must match the same production template, not just the same art direction.

## Runtime Standard

The real runtime standard is `CardVisual`, not legacy preview scenes.

Reference:

- `echoofabyss/combat/ui/CardVisual.gd`
- `echoofabyss/combat/ui/CardVisual.tscn`

Current runtime size modes all use a strict `2:3` ratio:

- default: `200x300`
- hand: `160x240`
- combat preview: `336x504`
- deck preview: `480x720`
- reward: `270x405`
- shop: `260x390`

Therefore:

- every production card frame PNG must use a strict `2:3` ratio
- all production card frame master exports must use `1024x1536`

Do not use older preview assets or older scene sizes as the standard for new frame work.

## Master Asset Rules

All production card frame PNGs must follow these requirements:

1. Canvas size must be exactly `1024x1536`.
2. Outer background must be true transparent alpha.
3. Transparent openings must be true transparent alpha, not fake painted checker, fog, white, gray, or black fill.
4. The frame must be authored to fit the template naturally. Do not stretch finished art to force fit.
5. The frame silhouette must be designed so it fills the production card efficiently with only thin transparent safety margins.

## Painted Bounds Rules

The visible painted frame footprint must be large and consistent.

Target rule:

- painted width must be greater than `1000`
- painted height must be at least `1500`

This is a hard target for production card frames.

If a frame cannot hit this target without stretching, the frame art must be redesigned to fit the template better. Do not solve this by scaling distortion.

## Transparency Rules

Transparency must be real.

Allowed:

- true alpha outside the frame
- true alpha in designated open windows such as art openings

Not allowed:

- baked checkerboard
- pale painted placeholder background
- black-filled "fake open" art window
- mist, haze, or glow floating across a window that is supposed to be open

Verification rule:

- before accepting a frame, check pixel alpha at corners and inside the art window

## Shared Structural Rules

All card frame families must share the same structural logic even if the ornament differs.

The following must stay standardized across families:

- overall card canvas ratio
- top badge scale
- title bar placement logic
- race tag placement logic where applicable
- art window sizing discipline
- description panel sizing discipline
- bottom stat bar placement logic for minions
- general edge coverage and silhouette efficiency

Faction identity should come from material language, ornament, accent motifs, and crest design, not from breaking the structural template.

Card frame silhouette must remain mostly rectangular.

Rules:

- the frame should occupy most of the `1024x1536` canvas
- ornament may project slightly beyond the main rectangle, but only in a minor supporting way
- major frame mass must stay inside a stable rectangular card body
- no faction should rely on large outward spikes, wings, horns, medallions, or side flares to define its identity
- silhouette variation should be subtle and controlled, not extreme
- at gameplay size, the frame should still read first as a rectangular card, not as an irregular emblem

## Locked Full-Card Minion Template

Minion frames now use one locked master template across all factions.

This is not approximate guidance.

These size and placement rules are fixed unless this document is updated first.

All faction minion frames must place their ornament around this same structure so the same `CardVisual` text template can be reused without faction-specific drift.

Master template reference size:

- `1024x1536`

Locked minion master regions:

- cost badge outer footprint: `224x224`, anchored top-left, target box `x=12..236`, `y=12..236`
- title bar outer footprint: target box `x=252..968`, `y=42..140`
- race bar outer footprint: target box `x=316..708`, `y=158..226`
- art window opening: true square `816x816`, target box `x=104..920`, `y=232..1048`
- description panel outer footprint: target box `x=84..940`, `y=1058..1368`
- attack bar outer footprint: target box `x=44..424`, `y=1384..1496`
- health bar outer footprint: target box `x=600..980`, `y=1384..1496`

Locked minion content-safe regions for runtime text/template alignment:

- cost value safe region: `x=28..184`, `y=34..176`
- title text safe region: `x=308..920`, `y=58..128`
- race text safe region: `x=352..672`, `y=170..216`
- art crop safe region: `x=112..912`, `y=240..1040`
- description text safe region: `x=164..860`, `y=1096..1308`
- attack value safe region: `x=84..380`, `y=1398..1482`
- health value safe region: `x=644..940`, `y=1398..1482`

Equivalent normalized `CardVisual` anchors:

- cost value: `[0.03, 0.03, 0.18, 0.115]`
- title text: `[0.30, 0.038, 0.90, 0.083]`
- race text: `[0.34, 0.111, 0.66, 0.141]`
- art: `[0.109, 0.156, 0.891, 0.677]`
- desc: `[0.160, 0.714, 0.840, 0.852]`
- atk: `[0.082, 0.910, 0.371, 0.965]`
- hp: `[0.629, 0.910, 0.918, 0.965]`

These locked regions apply to all future full-card minion frame families, including neutral.

They replace older neutral-specific and preview-scene-specific placements.

## Content Region Rules

Functional text and content zones always take priority over decoration.

Rules:

- title lane must remain clean and readable
- race tag lane must remain uninterrupted if present
- no crest, gem, spike, or ornament may sit inside a text lane
- description panel must remain readable at gameplay size
- decorative elements may border content regions but may not occupy them

## Art Window Rules

Art windows must be designed intentionally, not approximately.

Current approved minion direction:

- minion art window should be a true square `1:1` opening
- the square opening must be fully transparent alpha
- the square opening should be centered in the upper-middle card area

If another card type uses a different opening shape, that must be stated explicitly and still follow the same production template discipline.

## Description Panel Rules

Description readability is mandatory.

Rules:

- minion and spell description panels should use a filled dark purple interior
- fully transparent description panels are not approved for production use
- panel fill should support readability without abandoning faction identity

## Card-Type Specific Rules

### Minion Frames

Minion frames must follow these rules:

- one top-left cost badge
- long centered title bar
- shorter centered race tag below the title bar
- race tag must be center-aligned with the title bar
- race tag must be uninterrupted
- the cost badge, title bar, race bar, art window, description panel, and stat bars must use the locked minion template above
- long bottom-left attack bar
- long bottom-right health bar
- integrated sword and heart icons are allowed
- bottom-center crest is allowed if it does not intrude into content areas
- dual-cost neutral minion variants are not part of the locked full-card minion standard
- shield display is not part of the locked full-card minion standard

Approved reference direction:

- `echoofabyss/assets/art/frames/abyss_order/abyss_minion_v4.png`

### Spell Frames

Spell frames must follow these rules:

- one top-left cost badge
- spell cost badge should use blue to signal mana cost
- clean uninterrupted title bar
- no race tag strip
- transparent art window
- dark purple filled description panel
- a distinct spell-type signal may exist at the bottom center, but must not block title or text lanes

Approved reference direction:

- `echoofabyss/assets/art/frames/abyss_order/abyss_spell_v2.png`

Note: if spell frame size or silhouette is later adjusted to match minion template more tightly, this document should be updated with the new reference file.

### Trap Frames

Trap frames must follow these rules:

- one top-left cost badge
- trap cost badge should use blue to signal mana cost
- clean uninterrupted title bar
- no race tag strip
- transparent art window
- trap art window should be a true square `1:1` opening
- dark purple filled description panel
- trap identity should be communicated through a compact bottom-center rune or trigger sigil
- the trap sigil must stay below the description panel and must not intrude into content space
- the trap sigil must not read like a literal lock, keyhole, or padlock UI

Approved reference direction:

- `echoofabyss/assets/art/frames/abyss_order/abyss_trap_v2.png`

Note: trap recognition should come from the bottom-center rune / trigger language and overall frame mood, not from blocking the title lane with a type sigil.

### Environment Frames

Environment frames must follow these rules:

- one top-left cost badge
- environment cost badge should use blue to signal mana cost
- clean uninterrupted title bar
- no race tag strip
- transparent art window
- environment art window should be a large vertical opening sized for scenic art and ritual compositions
- dark purple filled description panel
- environment identity should be communicated through ritual architecture, altar framing, or a compact bottom-center world/ritual sigil
- any environment sigil must stay below the description panel and must not intrude into content space
- the frame must not use minion stat bars or trap-style trigger sigils

Approved reference direction:

- `echoofabyss/assets/art/frames/abyss_order/abyss_environment.png`

Note: environment recognition should come from scenic framing, ritual/world motif language, and overall atmosphere, not from obstructing the title lane or description space.

### Battlefield Minion Frames

Battlefield minion frames are a separate UI asset family from full card frames.

They are not judged by the `1024x1536` production card export standard.

Instead, they must follow the live battlefield slot layout and readability needs.

Rules:

- battlefield frame masters must use the battlefield slot ratio
- approved master export size is `900x975`
- the frame must be authored for the real battlefield slot, not adapted from a full card frame
- the frame must fully cover the image edge with no visible transparent outer margin
- the center art window must be true transparent alpha where the minion art shows through
- the frame must preserve a large readable art opening suitable for battlefield-scale portraits
- the lower HUD must keep three clearly separated functions: status bar, attack panel, health panel
- the status bar should sit above the attack and health panels
- the status bar should be wide and visually readable at battlefield size
- attack and health panels must remain clearly separated, not merged into one continuous bar
- attack and health icons should be legible at battlefield size without dominating the slot
- bottom-center ornament, if used, must remain small and secondary
- battlefield frames should not use oversized crests or sigils that compete with art, stats, or status icons
- title treatment, if present, must remain visually quiet and must not reduce battlefield readability
- future combat-specific counters may use reserved space in the top bar, but that space must not damage the current art and name layout

Approved reference direction:

- `echoofabyss/assets/art/frames/abyss_order/abyss_battlefield_minion_generic_v2.png`

Note: battlefield minion frames should read as compact combat HUD assets first and ornamental faction frames second.

## Ornament Rules

Ornament is allowed only when it does not damage function.

Allowed:

- faction-specific metalwork
- sigils
- crest variation
- subtle glow seams
- integrated icons inside stat bars

Not allowed:

- very wide lateral spikes that break template efficiency
- center gems covering text lanes
- oversized mid-divider crests that reduce usable description or art space
- extra decorative sockets that imply fake gameplay information

## Normalization Rules

Frame normalization must follow this order:

1. design the silhouette to fit the `1024x1536` template naturally
2. verify true transparency
3. measure painted bounds
4. only then accept the asset

Do not treat "trim transparent edge" as normalization.

Trimming alone is not enough because it does not guarantee equal perceived size in game.

The correct standard is:

- same canvas
- same ratio
- same functional layout logic
- same painted envelope target

## Approval Checklist

Before approving any new card frame, verify all of the following:

- canvas is exactly `1024x1536`
- ratio is exactly `2:3`
- outer background is true alpha
- art window is true alpha where required
- description panel uses the approved fill behavior
- painted width is `>1000`
- painted height is `>=1500`
- title lane is unobstructed
- race lane is unobstructed where applicable
- frame is not stretched to fit
- bottom stat containers match the approved type logic
- the frame still reads as the correct faction and card type at first glance

If any item fails, the asset is not production-ready.

## Change Control

These rules are strict by default.

If future work needs a different standard, update this document first, then create new frame assets against the revised rules.
