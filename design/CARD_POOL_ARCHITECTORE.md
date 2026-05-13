# Echo of Abyss — Card Pool Architecture

**Version:** 0.2
**Last updated:** 2026-05-10
**Purpose:** Define the layered card pool system for deck building, combat rewards, and hero differentiation across the project.

-----

## 1. Overview

Cards in Echo of Abyss are organized into **layered pools** rather than a single flat list. Pools are split into two kinds based on how the player accesses them:

|Pool Kind  |How Accessed               |When Available                 |
|-----------|---------------------------|-------------------------------|
|**Core**   |Deck builder at run start  |Always (subject to scope)      |
|**Support**|Combat rewards during a run|Subject to scope and act gating|

The layered system solves three problems:

1. **Hero differentiation at run start** — without hero-specific pools, every hero of the same faction would start from an identical card pool and feel mechanically interchangeable until talents kick in.
1. **Mechanic seeding** — new mechanics introduced by a hero (e.g. Armour for Korrath, Flesh for Seris) need card support available from turn one, otherwise the mechanic is dead until branch unlocks.
1. **Build variety scaling** — talent choices unlock distinct support pools mid-run, giving each branch a meaningfully different set of reward cards to draft from.

-----

## 2. Core Pools

Core pools are accessible during deck building at run start. Cards from core pools may also appear as combat rewards during the run.

### 2.1 Neutral Core

- **Pool ID example:** `neutral_core`
- **Access:** Available to every hero regardless of faction.
- **Purpose:** Baseline utility cards (basic minions, generic spells, traps) that provide fundamental tools without faction synergy.
- **Examples:** Roadside Drifter, Arcane Strike, Hidden Ambush, Energy Conversion.
- **Design constraint:** No strong synergy with any faction-specific mechanic. Provides flexible tools, not power spikes.

### 2.2 Faction Core

- **Pool ID example:** `abyss_core`
- **Access:** Available to all heroes of a single faction.
- **Purpose:** Establishes the faction’s mechanical identity. Contains the faction’s signature mechanics (e.g. Demon synergy, Corruption, Runes, Rituals for Abyss Order).
- **Examples (Abyss Order):** Void Imp, Senior Void Imp, Abyss Cultist, Dark Empowerment, the four Runes, Abyssal Summoning Circle.
- **Design constraint:** Must be balanced for use by any hero in the faction. Cannot lean too hard into a single hero’s identity. Hero-specific power gating happens via hero passives (e.g. Vael’s `void_imp_boost` adds +100/+100 to Void Imps), not by restricting the card itself.

### 2.3 Hero Core

- **Pool ID example:** `korrath_core`, `seris_core`
- **Access:** Available only to one specific hero.
- **Purpose:** Solves hero differentiation and mechanic seeding. A small set of hero-exclusive cards that:
  - Make the deck *feel* like that hero from the first hand
  - Provide minimal card support for new mechanics introduced by the hero (so the mechanic is functional pre-talent)
  - Stay branch-neutral so they remain useful regardless of branch choice
- **Size:** Small — typically 4-6 cards.
- **Design constraint:**
  - Each card must be useful regardless of which branch the hero takes
  - Must not be strong enough in any single direction to make support pools redundant
  - Should introduce baseline support for hero-specific mechanics (e.g. Armour and Armour Break for Korrath)
  - Avoid leaning too hard into any branch’s identity — that’s talent-specific support pool territory

-----

## 3. Support Pools

Support pools are not accessible during deck building. Cards from support pools are offered only as combat rewards during a run. Each support pool applies **act gating** — specific cards within the pool unlock only after defeating that act’s boss.

### 3.1 Hero Common Support

- **Pool ID example:** `vael_common`, `korrath_common`, `seris_common`
- **Access:** One specific hero. All cards in this pool are eligible from the start of a run; act gating still applies (see § 3.3).
- **Purpose:** Provides additional hero-aligned cards as combat rewards regardless of branch. These are available from the very first reward roll (subject to act gating) — no talent investment required.
- **Examples (Vael):** Imp Recruiter, Soul Taskmaster, Void Amplifier, Blood Pact, Soul Shatter, Soul Rune.
- **Design constraint:** Must be useful regardless of branch choice. Stronger or more synergistic than core pool cards (since they appear as rewards rather than starter material), but not branch-locked.

### 3.2 Talent-Specific Support

- **Pool ID example:** `vael_piercing_void`, `vael_endless_tide`, `vael_rune_master`
- **Access:** One specific hero, locked behind that hero’s branch T0 talent. Cards in this pool become eligible reward drops only after the player unlocks the corresponding T0 talent. Act gating still applies on top of talent gating.
- **Purpose:** Deep synergy cards that reward branch commitment. Defines the late-game power spike of each branch.
- **Examples (Vael Piercing Void):** Mark the Target, Void Detonation, Abyssal Arcanist, Void Archmagus, Abyss Ritual Circle.
- **Design constraint:**
  - Cards should be powerful with the branch’s T0 talent active
  - Cards may reference branch-specific mechanics directly (e.g. Void Marks, Imp swarm scaling)
  - Cards never appear in deck builder or rewards without the T0 talent unlocked

### 3.3 Act Gating

Within every support pool, individual cards are tagged with an act unlock requirement. A card with an Act N unlock becomes eligible to appear in reward rolls only after the Act N boss is defeated.

|Act Gate|Becomes Available After                          |
|--------|-------------------------------------------------|
|Act 1   |Run start (no boss required)                     |
|Act 2   |Defeating Act 1 boss (Imp Matriarch, fight 3)    |
|Act 3   |Defeating Act 2 boss (Corrupted Handler, fight 6)|
|Act 4   |Defeating Act 3 boss (Void Herald, fight 9)      |

Act gating is independent of rarity gating. Both filters apply simultaneously to determine which cards are eligible for any given reward roll. Rarity gating works as currently defined in `DESIGN_DOCUMENT § 17`:

- Act 1: Common only
- Act 2: Common + Rare
- Acts 3-4: All rarities

-----

## 4. Pool Access Summary

|Context                                    |Pools Accessed                         |
|-------------------------------------------|---------------------------------------|
|**Deck building at run start**             |Neutral Core, Faction Core, Hero Core  |
|**Combat rewards (always eligible)**       |Hero Common Support                    |
|**Combat rewards (after T0 talent unlock)**|Talent-Specific Support for that branch|

Cross-faction borrowing is disabled. A hero cannot access another faction’s Faction Core or any other hero’s pools. Common pool deck cap: max 2 copies per card.

-----

## 5. Hero Core Pool — Design Workflow

When designing a new hero’s core pool:

1. **Identify the gap** — what new mechanics does this hero introduce that have no support in shared faction core? (e.g. Korrath introduces Armour and Armour Break; neither exists in `abyss_core`.)
1. **Seed the mechanics** — include 1-2 cards per new mechanic so it’s functional from turn one regardless of branch.
1. **Reinforce hero identity** — include cards that make the hero’s playstyle recognizable in early turns (e.g. Korrath’s slow knight investment vs. Vael’s aggressive imp swarm).
1. **Stay branch-neutral** — every core pool card should be useful regardless of which branch the player commits to.
1. **Keep it small** — 4-6 cards is the target. Larger pools dilute support pool relevance and make starter decks feel generic.

-----

## 6. Current Pool Inventory (as of v0.6)

### Core Pools

**Neutral**

- `neutral_core` — Neutral Core (CARD_LIBRARY.md § 6)

**Abyss Order**

- `abyss_core` — Faction Core (CARD_LIBRARY.md § 1)
- `korrath_core` — Korrath Hero Core *(to be designed)*
- `seris_core` — Seris Hero Core *(to be designed)*

**Free Cities**

- (Faction Core — to be designed)
- `dagan_core` — Dagan Hero Core *(to be designed; may not be needed since Dagan is restricted to neutral cards only — open question)*

### Support Pools

**Abyss Order — Vael**

- `vael_common` — Common Support (CARD_LIBRARY.md § 2)
- `vael_piercing_void` — Talent-Specific Support, requires `piercing_void` (CARD_LIBRARY.md § 3)
- `vael_endless_tide` — Talent-Specific Support, requires `imp_evolution` (CARD_LIBRARY.md § 4)
- `vael_rune_master` — Talent-Specific Support, requires `rune_caller` (CARD_LIBRARY.md § 5)

**Abyss Order — Korrath** *(to be designed)*

- `korrath_common` — Common Support
- Three talent-specific support pools — one per branch:
  - `korrath_iron_vanguard` (gated behind `iron_formation` T0)
  - `korrath_runic_knight` (gated behind `runeforge_strike` T0)
  - `korrath_abyssal_breaker` (gated behind `corrupting_presence` T0)

**Abyss Order — Seris** *(to be designed)*

- `seris_common` — Common Support
- Three talent-specific support pools — one per branch (Fleshcraft, Demon Forge, Corruption Engine)

### Enemy-Only Pools (out of scope for this architecture)

- `feral_imp_clan` — Act 1 enemy pool
- `abyss_cultist_clan` — Act 2 enemy pool
- `void_rift` — Act 3 enemy pool

-----

## 7. Open Questions

- **Dagan core pool:** Dagan is restricted to neutral cards only (no Abyss Order access per `DAGAN_HERO_DESIGN § 3`). Does he need a hero core pool, and if so what would it contain (Bleeding sources? Dual Strike support?). Without a hero core pool, Bleeding and Dual Strike cards can only reach Dagan through support pools — confirm if this is intended.
- **Act gating granularity:** Confirm whether every support pool card needs an explicit act tag, or whether a default rule is applied (e.g. common = Act 1, rare = Act 2, etc.) with manual overrides.
- **Cross-campaign card unlocks:** Whether cards unlocked in one campaign carry over to other campaigns is deferred (see `DESIGN_DOCUMENT § 21`).

-----

*End of Card Pool Architecture · Echo of Abyss*