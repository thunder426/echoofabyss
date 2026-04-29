# Casting Windup Glyph Design

Faction-themed circular glyphs that appear at the caster position during the spell-cast preview window (~1 second). Provides visual feedback that the caster is "charging" the spell while the card preview is held on screen.

## Where they appear

- **Player caster:** bottom-center of screen, ~100 px above the hand zone.
- **Enemy caster:** centered on the enemy hero panel.
- One glyph per cast; despawns as the preview fades out and the actual spell VFX begins.

## Faction → glyph mapping

| Faction | Used by | Palette family |
|---|---|---|
| `void` | Player (Lord Vael / Abyss Order), Act 3 enemies | purple / violet (#8A3FCC, #B870FF accents) |
| `feral` | Act 1 enemies | blood-red + bone-white |
| `corrupted` | Act 2 enemies | sickly green + black smoke |
| `abyss` | Act 4 enemies | deep violet + near-black + faint starfield |

All four glyphs live in the same visual palette family per the "similar color, different style" rule — distinction is carried mostly by **shape and motion**, not hue.

## Shared asset rules (applies to all four glyphs)

These are the rules the generated PNGs must satisfy so they drop into the engine cleanly and tint consistently.

- **Canvas size:** 512 × 512 PNG with full alpha channel.
- **Background:** fully transparent. No background fills, no border boxes.
- **Color:** draw in **white / light gray only** on transparent. All per-faction coloring is applied in-engine via `modulate` tinting. Do NOT bake purple/red/green/etc. into the asset.
- **Line weight:** medium — thin enough to look etched, thick enough to read clearly when scaled to ~150 px (enemy hero panel size).
- **Style:** line-art / rune-etching. Glowing edges OK, solid fills discouraged (too heavy when tinted).
- **Composition:** all four glyphs share the same 4-part structure so the family reads as a unified system:
  1. **Outer ring** — defines the glyph's outer boundary.
  2. **Inner ring** — concentric, smaller; adds visual weight.
  3. **Central sigil** — the distinctive faction motif at the geometric center.
  4. **Radial accents** — small repeating marks around the ring (cardinals N/E/S/W or diagonals).
- **Symmetry:** centered on canvas, radially symmetric (except where the faction explicitly breaks symmetry — see Feral below).
- **Readability:** must remain legible when scaled down to 150 px and when alpha-faded to ~40%. Avoid overly fine detail.
- **Centering:** the geometric center of the glyph must be at pixel (256, 256) — the engine spawns it at a point and relies on centered pivot.
- **No text, no numerals.** Pure occult/ritual iconography.
- **File naming:** `void_glyph.png`, `feral_glyph.png`, `corrupted_glyph.png`, `abyss_glyph.png`. Place in `echoofabyss/assets/art/fx/casting_glyphs/`.

## Per-faction designs

### `void_glyph.png` — Player & Act 3

- **Motif:** official Abyss Order sigil — cold, clean, controlled.
- **Outer ring:** single solid thin circle.
- **Inner ring:** thin dashed circle (8 evenly spaced segments).
- **Central sigil:** downward-pointing triangle with an eye / vertical slit in its center (the "watching abyss").
- **Radial accents:** 4 small sharp diamond-shaped runes at N / E / S / W.
- **Feel:** organized, hierarchical, ritualistic, precise lines.

### `feral_glyph.png` — Act 1

- **Motif:** primal hunt mark, tribal carving.
- **Outer ring:** rough and cracked — not a smooth mathematical circle. Small gaps / chips / irregular thickness, as if clawed or scraped into stone.
- **Inner ring:** not a full ring — three curved claw-slash arcs arranged around the center.
- **Central sigil:** four claw marks converging inward from the diagonals (an X made of talons). Alternate option: a stylized fanged-skull silhouette.
- **Radial accents:** 4 bone-shard shapes placed at the diagonals (NE / SE / SW / NW), tilted at slightly varying angles — deliberately unruly.
- **Feel:** wild, aggressive, asymmetric-within-symmetry. Deliberately rough edges.

### `corrupted_glyph.png` — Act 2

- **Motif:** infected ritual, diseased growth, parasitic.
- **Outer ring:** solid circle with "drips" or melting tendrils leaking inward from its inner edge.
- **Inner ring:** thorny / barbed — small spike or hook protrusions along its circumference.
- **Central sigil:** organic cell pattern — hexagonal honeycomb, or spider-leg radial arms, with a single drop / pustule / egg at the dead center.
- **Radial accents:** 4 small "growth" blobs at cardinals, deliberately asymmetric in size (one bigger, one smaller) to feel wrong / infected.
- **Feel:** organic, wrong, slightly off-balance, parasitic. Controlled asymmetry inside an overall symmetric frame.

### `abyss_glyph.png` — Act 4

- **Motif:** cosmic void, starfield, elder power. An evolution / heavier version of the void glyph.
- **Outer ring:** **two** thin concentric rings close together (doubled outer boundary) — gives a heavier, denser look.
- **Inner ring:** 8-pointed star inscribed in a circle — the star's points touch the inner-ring circle.
- **Central sigil:** a larger downward-pointing triangle (echoing void_glyph but bigger and heavier in weight) containing a tight spiral or black-hole swirl at center, surrounded by 5–7 tiny dots representing stars.
- **Radial accents:** 8 small star-points (5-point stars or 4-point crosses) evenly distributed around the outer ring — double the count of the other glyphs.
- **Feel:** heavier, denser, cosmic, gravitationally oppressive. Reads as "void, but older and deeper."

## In-engine usage (reference — informs shape/readability requirements)

These notes describe how the glyphs will be animated once wired in, so the art-generation pass can anticipate how each glyph needs to hold up under motion and alpha changes.

- Glyph is spawned at windup start, tinted with the faction palette, and tweened:
  - Fades in over ~0.22 s as preview fades in.
  - Rotates and pulses during the ~0.63 s hold.
  - Fades out over ~0.22 s as preview fades out.
- Per-faction motion profile:

  | Faction | Rotation | Pulse | Feel |
  |---|---|---|---|
  | void | slow steady clockwise | gentle sine | smooth, controlled |
  | feral | jittery counter-clockwise with occasional snaps | sharp irregular | flickering, unstable |
  | corrupted | slow irregular clockwise with wobble | uneven bubbling | creeping, sick |
  | abyss | very slow clockwise (almost still) | deep slow breathing | heavy, oppressive |

Because the void glyph barely jitters while the feral glyph flickers, the line work for Feral can afford to be rougher without looking broken — the motion supports it. Conversely the Void glyph needs clean geometry because its slow steady rotation exposes any imperfection.

## Generation prompt template

For AI-art generation, use this template and swap the `[faction motif]` block per glyph:

> Circular magical glyph, [faction motif], line-art sigil on fully transparent background, white / light gray lines only (no color baked in), symmetric composition, outer ring + inner ring + central symbol + radial accent marks, 512 × 512, PNG with alpha, clean and readable when scaled down to 150 px, occult ritual style, no text, no numerals, no background fills.

Per-faction `[faction motif]` values:

- **void:** "ordered ritual sigil, downward triangle with central eye, dashed inner ring, 4 sharp diamond marks at cardinals"
- **feral:** "tribal hunt mark, four converging claw slashes, cracked and chipped outer ring, 4 tilted bone shards at diagonals"
- **corrupted:** "diseased infection ritual, thorny barbed inner ring, dripping outer ring, central hexagonal cell cluster with egg, 4 asymmetric growth blobs at cardinals"
- **abyss:** "cosmic void sigil, doubled outer ring, 8-pointed inscribed star, central downward triangle with tight spiral and small star dots, 8 small star accents around outer ring"
