# Echo of Abyss — Master Design Document
**Version:** 0.6 (pre-alpha)
**Last updated:** 2026-03-29
**Engine:** Godot 4 · GDScript
**Platform:** Steam (PC)
**Genre:** Single-player roguelike deckbuilder

---

## Table of Contents
1. [Game Overview](#1-game-overview)
2. [Core Concepts & Stat Scale](#2-core-concepts--stat-scale)
3. [Card Types](#3-card-types)
4. [Resources](#4-resources)
5. [Keywords](#5-keywords)
6. [Minion Types](#6-minion-types)
7. [Turn Structure](#7-turn-structure)
8. [Combat Resolution](#8-combat-resolution)
9. [Buff System](#9-buff-system)
10. [Trap & Rune System](#10-trap--rune-system)
11. [Ritual System](#11-ritual-system)
12. [Void Marks & Void Bolt](#12-void-marks--void-bolt)
13. [Trigger Event System](#13-trigger-event-system)
14. [Hero System](#14-hero-system)
15. [Talent System](#15-talent-system)
16. [Relic System](#16-relic-system)
17. [Progression & Run Structure](#17-progression--run-structure)
18. [Enemy Encounters](#18-enemy-encounters)
19. [Enemy AI](#19-enemy-ai)
20. [Win & Loss Conditions](#20-win--loss-conditions)
21. [Known Gaps / TODO](#21-known-gaps--todo)

---

## 1. Game Overview

Echo of Abyss is a single-player roguelike deckbuilder. The player takes the role of a hero who fights a series of 15 increasingly difficult encounters across 4 acts. Between fights they gain new cards, relics, and talents to build a more powerful deck.

**Core loop:**
1. Start a run — pick hero, receive starter deck.
2. Fight encounter → earn rewards (cards, relics, talent points).
3. Grow essence/mana cap, refine deck.
4. Defeat final boss to unlock permanent reward cards for future runs.

**Pillars:**
- Tactical board play with minions, spells, traps, and environments.
- Dual-resource system (Essence for minions, Mana for spells/traps).
- Deep synergy through keywords, buffs, runes, and rituals.
- Build variety through three talent branches per hero.

---

## 2. Core Concepts & Stat Scale

### Stat Scale
All ATK, HP, Shield, and damage values use a **×100 internal scale**.
- 100 internal = 1 displayed point
- 300 ATK = displayed as "3" (or "300" depending on display context)
- This allows integer-precision percentage modifiers (e.g. +5% of 300 = +15)

### Board
- **5 slots** per side (player and enemy).
- Minions occupy one slot each. A full board cannot accept new minions.
- Slots retain their index for adjacency effects (e.g. Void Devourer sacrifice).

### Hand & Deck
- Max hand size: **10 cards**. Cards drawn beyond 10 are burned (discarded without effect).
- When deck is empty, the discard pile is shuffled back in.
- Opening hand: **3 cards**.

---

## 3. Card Types

| Type | Resource | Rules |
|---|---|---|
| **Minion** | Essence (+ optional Mana dual cost) | Placed on board; has ATK/HP; destroyed at 0 HP |
| **Spell** | Mana | Resolved immediately; goes to discard |
| **Trap** | Mana | Placed face-down; triggers reactively on enemy actions; one-use by default |
| **Rune** | Mana | Trap subtype; placed face-up; persistent passive aura; ritual component |
| **Environment** | Mana | Only one active at a time; replaced when new one played; passive aura fires each turn |

### Minion Card Fields
- `essence_cost`, `mana_cost` — Dual costs (most minions use only essence)
- `atk`, `health`, `shield_max` — Base stats
- `minion_type` — Type tag for synergy
- `keywords` — Array of keyword enums (GUARD, SWIFT, LIFEDRAIN, etc.)
- `on_play_requires_target` + `on_play_target_type` — Whether battle cry needs player to select target
- `on_play_effect_steps` — Array of EffectStep; battle cry effects
- `on_turn_start_effect_steps` — Array of EffectStep; fires at start of owner's turn
- `on_death_effect_steps` — Array of EffectStep; deathrattle effects
- `passive_effect_id` — String ID for passives that require custom CombatScene logic (not expressible as EffectSteps)
- `mana_cost_discount` — Reduces all player spell costs (stacks across multiple minions; floor 0)
- `minion_tags` — String tags for data-driven queries ("void_imp", "base_void_imp", etc.)
- `is_champion` + `auto_summon_condition/tag/threshold` — Champion auto-summon logic

### Spell Card Fields
- `requires_target` + `target_type` — Whether player must click a target
- `effect_steps` — Array of EffectStep defining the spell's effects

### Trap / Rune Card Fields
- `trigger` — TriggerEvent enum (which event activates the trap)
- `trigger_threshold` — Minimum value required to trigger (0 = no threshold)
- `effect_steps` — Array of EffectStep; executed when trap triggers
- `reusable` — If true, trap resets after triggering
- `is_rune` — True if this is a Rune
- `rune_type` — RuneType enum (VOID_RUNE, BLOOD_RUNE, DOMINION_RUNE, SHADOW_RUNE)
- `aura_effect_id` — String ID for continuous aura effect while rune is on board

### Environment Card Fields
- `passive_effect_steps` — Array of EffectStep; fires on ON_PLAYER_TURN_START (and enemy turn if `fires_on_enemy_turn = true`)
- `on_player_minion_died_steps` — Array of EffectStep; fires when a friendly minion dies
- `on_replace_effect_steps` — Array of EffectStep; fires when replaced by a new environment
- `fires_on_enemy_turn` — If true passive also fires on ON_ENEMY_TURN_START
- `rituals` — Array of RitualData defining valid 2-rune combinations

### EffectStep Fields
Effects on all card types are expressed as arrays of `EffectStep` objects rather than string IDs. Key fields:
- `type` — EffectType enum (DAMAGE_MINION, DAMAGE_HERO, BUFF_ATK, CORRUPTION, SUMMON, DRAW, CONVERT_RESOURCE, etc.)
- `scope` — TargetScope enum (SINGLE_CHOSEN, ALL_ENEMY, ALL_FRIENDLY, SELF, TRIGGER_MINION, etc.)
- `amount` — Primary numeric value
- `bonus_amount` + `bonus_conditions` — Conditional additive bonus added to `amount` when all bonus conditions pass (board-state check). Used for "deal X, +Y if condition" patterns on a single hit.
- `conditions` — Array of condition IDs that must ALL pass before this step executes (gates the step; not shown as glow)
- `filter` — MinionFilter enum; narrows the target pool (DEMON, HUMAN, CORRUPTED, VOID_IMP, etc.)
- `permanent` — For ATK/HP buffs: true = permanent, false = expires at turn end
- `multiplier_key` — Optional scaling ("rune_aura", "void_marks", "board_count")

> **Targeting rule:** SINGLE_CHOSEN steps that lose their target (e.g. target dies mid-resolution) fizzle silently — they do not redirect to a random unit.

---

## 4. Resources

### Essence
- Spent on minion cards.
- Refills fully to `essence_max` at the start of each player turn.
- Starting max: **1**. Grows by 1 when player chooses "grow essence" at end of turn.

### Mana
- Spent on spells, traps, environments.
- Refills fully to `mana_max` at the start of each player turn.
- Starting max: **1**. Grows by 1 when player chooses "grow mana" at end of turn.

### Combined Cap
- `essence_max + mana_max ≤ 11`. Player may not grow beyond this combined total.
- At end of each player turn, player chooses to grow either essence_max **or** mana_max (not both).

### Resource Conversions
| Action | Effect |
|---|---|
| `CONVERT_RESOURCE` (EffectStep) | Converts up to `amount` of one resource into the other. Fields: `convert_from` ("essence"/"mana"), `convert_to` ("mana"/"essence"), `amount`. Actual converted = `min(amount, current_resource)`. Overflow beyond the target cap is kept as temporary excess. |
| `gain_essence(n)` | Grants temporary Essence above essence_max; resets on next turn refill |
| `gain_mana(n)` | Grants Mana (capped at mana_max) |

> `Energy Conversion` converts up to 3 Essence → Mana. `Flux Siphon` converts up to 3 Mana → Essence.

### Resource Display (UI)
Resources are displayed as vertical **pip bars** in the bottom-right of the combat screen.
- Each bar shows pips up to the current `essence_max` / `mana_max` (not a fixed 10).
- **Filled pips** = current resource. **Empty-bordered pips** = unused capacity.
- **Overflow pips** (temporary resource above max): shown above the normal bar with a distinct accent colour — amber-gold for Essence overflow, cyan-teal for Mana overflow.
- **Card-cost preview blink**: when a card is selected from hand, the pips that will be spent fade in/out; gain pips (e.g. from Flux Siphon) glow with the resource colour.

### Dual-Cost Minions
Some minions require both Essence **and** Mana (e.g. `essence_cost = 2, mana_cost = 1`). Both pools must have sufficient resources to play the card.

### Spell Cost Discounts
Minions with `mana_cost_discount > 0` reduce the cost of all player spells by that amount. Multiple minions stack. Floor is 0 (cannot go negative).

### Spell Tax (Spell Taxer Minion)
When an enemy Spell Taxer is summoned, player spells cost +1 Mana next turn. Applied at player turn start, cleared at turn end. Player's own Spell Taxer taxes enemy spells similarly.

---

## 5. Keywords

| Keyword | Effect |
|---|---|
| **GUARD** | Enemy MUST attack this minion first if any Guard minion exists on the board. Applies to minion-on-minion and minion-on-hero attacks. |
| **SWIFT** | Can attack enemy minions on the turn it is summoned. Cannot attack the enemy hero that turn. Transitions to NORMAL state next turn. |
| **LIFEDRAIN** | Damage dealt to the enemy hero also heals your hero by the same amount. |
| **SHIELD_REGEN_1** | Regenerates 100 Shield at the start of the owner's turn (clamped to shield cap). |
| **SHIELD_REGEN_2** | Regenerates 200 Shield at the start of the owner's turn (clamped to shield cap). |
| **CHAMPION** | Legendary unit. Auto-summoned for free when a specified board condition is met. Maximum 1 copy in deck. |
| **RUNE** | Displayed as keyword badge on Rune trap cards. Persistent face-up placement with passive aura. |
| **CORRUPTION** | Displayed as keyword badge on cards that reference corruption. Stacking debuff: each stack reduces ATK by 100 (or 200 with talents). |
| **DEATHLESS** | Prevents the next instance of fatal damage. When it would trigger, HP is set to 50 and the keyword is consumed (removed). Granted at runtime via GRANT_DEATHLESS buff. |
| **VOID_MARK** | Display-only pseudo-keyword. Shown in tooltip on cards that apply Void Marks. Has no mechanical effect of its own. |
| **RITUAL** | Display-only pseudo-keyword. Shown in tooltip on Environment cards that define rituals. Has no mechanical effect of its own. |

---

## 6. Minion Types

Used for synergy checks, targeting filters, and tag-based effects.

| Type | Notes |
|---|---|
| DEMON | Primary faction type for Abyss Order; benefits from Dominion Rune, Dark Surge, etc. |
| SPIRIT | Placeholder; Wandering Spirit is current example |
| BEAST | Neutral threats |
| UNDEAD | Available type, no current cards |
| HUMAN | Abyss Order corruption-synergy minions + neutral utility |
| CONSTRUCT | Shield-bearing neutral tanks |
| GIANT | Available type, no current cards |
| MERCENARY | Neutral generics with no faction synergy. Displayed as "Mercenary" in the race tag. Previously called UNTAGGED. |

---

## 7. Turn Structure

### Player Turn
1. **Turn Start Phase**
   - Increment turn number.
   - Refill Essence to essence_max, Mana to mana_max.
   - Draw 1 card (burn if hand full).
   - Unexhaust all friendly minions (EXHAUSTED/SWIFT → NORMAL).
   - Expire temporary buffs.
   - Regenerate shields (SHIELD_REGEN keywords).
   - Fire ON_PLAYER_TURN_START event (environment passives, rune auras, etc.).

2. **Action Phase**
   - Player may play cards from hand in any order.
   - Player may attack with any number of ready minions.
   - No limit on number of actions per turn.

3. **End Turn**
   - Player clicks End Turn.
   - Player chooses to grow essence_max OR mana_max (if below combined cap 11).
   - Control passes to enemy.

### Enemy Turn
1. **Turn Start Phase**
   - Enemy draws 2 cards (burn if hand > 5).
   - Resource growth (see AI section).
   - Refill Essence/Mana.
   - Unexhaust all enemy minions.
   - Expire temporary buffs.
   - Regenerate shields.
   - Fire ON_ENEMY_TURN_START event.

2. **AI Play Phase** — Enemy plays cards (see §19).

3. **AI Attack Phase** — Enemy minions attack (see §19).

4. **End Enemy Turn**
   - Fire ON_ENEMY_TURN_END event.
   - Control returns to player.

---

## 8. Combat Resolution

### Minion vs Minion
1. Both units deal damage to each other simultaneously.
2. **Damage absorption:** Shield absorbs first. Overflow reduces HP.
   - `shield_absorbed = min(damage, current_shield)`
   - `current_health -= (damage − shield_absorbed)`
3. If HP ≤ 0: minion is removed from board; ON_DEATH effects fire.
4. If attacker has **Lifedrain**: heal attacker's hero by attacker's effective_atk.
5. Attacker state → EXHAUSTED.

### Minion vs Hero
1. Damage = attacker's effective_atk.
2. Hero HP reduced directly (heroes have no shield).
3. If attacker has **Lifedrain**: same amount heals attacker's hero.
4. Attacker state → EXHAUSTED.

### Guard Enforcement
- If opponent has ≥ 1 Guard minion, attacker MUST target one of them.
- Cannot target the hero or non-Guard minions while Guard exists.
- Note: **Void Manifestation talent** converts Void Imp Clan hero attacks to Void Bolt damage, but Guard enforcement still applies.

### Shield Mechanics
- Shield absorbs damage before HP.
- Max shield = `shield_cap()` = card_data.shield_max + SHIELD_BONUS buffs.
- Clamped when SHIELD_BONUS is removed.
- Never exceeds `shield_cap()`.

### Effective ATK
`effective_atk() = current_atk + ATK_BONUS + TEMP_ATK − CORRUPTION_PENALTY`
Minimum 0. Minion with 0 effective ATK **cannot attack**.

### Minion States
| State | Can Attack Minion | Can Attack Hero |
|---|---|---|
| NORMAL | ✅ | ✅ |
| SWIFT | ✅ | ❌ |
| EXHAUSTED | ❌ | ❌ |

---

## 9. Buff System

All buffs are managed exclusively through `BuffSystem`. Each buff is a `BuffEntry`:
- `type` — BuffType enum
- `amount` — Numeric value
- `source` — String identifier for the origin (e.g. "dominion_rune", "void_amplifier")
- `is_temp` — True if cleared at turn start

### Buff Types
| BuffType | Effect |
|---|---|
| ATK_BONUS | Flat ATK increase (permanent; stacks) |
| HP_BONUS | Flat max HP increase (permanent) |
| TEMP_ATK | ATK boost lasting one turn; cleared at turn start |
| SHIELD_BONUS | Increases shield cap (permanent) |
| GRANT_GUARD | Runtime Guard grant (dispellable) |
| GRANT_LIFEDRAIN | Runtime Lifedrain grant (dispellable) |
| GRANT_DEATHLESS | Grants Deathless at runtime (e.g. Imp Idol on-play). Consumed (removed) when Deathless activates. |
| CORRUPTION | Stacking ATK debuff. Each stack: −100 ATK (−200 with deepened_curse talent) |

### Key Operations
| Operation | Behavior |
|---|---|
| `apply(minion, type, amount, source)` | Adds a new BuffEntry |
| `remove_source(minion, source)` | Removes all entries from the named source |
| `remove_type(minion, type)` | Removes all entries of a type |
| **Dispel** | Removes all buffs EXCEPT CORRUPTION (cannot dispel debuffs) |
| **Cleanse** | Removes all CORRUPTION stacks only (buffs untouched) |
| `expire_temp(minion)` | Clears all `is_temp=true` entries (called at turn start) |

### Shield Clamping
When a SHIELD_BONUS buff is removed, `current_shield` is immediately clamped to the new (lower) `shield_cap()`.

### HP Clamping
When HP_BONUS is removed, `current_health` is clamped to new max HP.

---

## 10. Trap & Rune System

### Trap Slots
- Max **3 active traps/runes** simultaneously (shared pool).
- Traps and Runes both occupy slots.

### Normal Traps
- Placed **face-down** (hidden from opponent).
- Trigger automatically when their `trigger` event fires during the enemy turn.
- Consumed (removed) on trigger by default. `reusable = true` allows reset.
- Destroyed by trap removal effects (Cyclone, Hurricane, Trapbreaker Rogue).

### Runes (Trap Subtype)
- Placed **face-up** (always visible).
- Apply a **persistent passive aura** immediately on placement.
- Never auto-consumed by triggering; persist until destroyed.
- Destroyed by any trap removal effect.
- Cannot be manually removed by the player.
- Count as **Rune Components** for ritual combinations.

### Rune Auras
| Rune | Aura Effect |
|---|---|
| Void Rune | At start of your turn: 100 Void Bolt damage to enemy hero |
| Blood Rune | When a friendly minion dies: restore 100 HP to your hero |
| Dominion Rune | All friendly Demons have +100 ATK (board-wide aura) |
| Shadow Rune | Enemy minions enter the board with 1 stack of Corruption |

With **Runic Attunement** talent, all aura values are doubled.

---

## 11. Ritual System

A Ritual is a powerful one-time effect that fires automatically when specific rune conditions are met. Rituals are defined on Environment cards.

### Trigger Timing
The ritual check fires **immediately** in two situations:
- When a **rune is placed** — checks if current runes satisfy any environment ritual.
- When an **environment is placed** — checks if runes already on board satisfy its rituals.

Order of play does not matter.

### Resolution Order
1. Check for valid **3-rune Grand Ritual** first (enabled by Abyss Convergence talent).
2. Check for valid **2-rune rituals** defined by the active environment.
3. If valid: **consume the required runes**, then execute the ritual effect.
4. The environment remains active after the ritual fires.

### Special Summon Rule
Units summoned by rituals do **not** fire On-Play effects. Passive abilities, Guard, Lifedrain, and Deathrattle remain active normally.

### 2-Rune Rituals (Current Environments)
| Environment | Required Runes | Effect |
|---|---|---|
| Abyssal Summoning Circle | Blood + Dominion | Demon Ascendant: 200 damage to 2 random enemies; Special Summon 500/500 Demon |
| Abyss Ritual Circle | Void + Blood | Soul Cataclysm: 400 Void Bolt to enemy hero; 400 HP healing |

### Grand Ritual (Abyss Convergence Talent)
| Required Runes | Effect |
|---|---|
| Blood + Dominion + Shadow | Abyssal Dominion: 300 damage to all enemy minions; all friendly Demons permanently +200 ATK/HP |

---

## 12. Void Marks & Void Bolt

### Void Marks
- Accumulated on the enemy hero during combat.
- Persist across turns within a single combat.
- Do not reset between turns.

### Sources
- `piercing_void` talent: +1 Mark when Void Imp plays from hand
- Void Bolt spell with `piercing_void`: +1 Mark
- Void Imp Wizard on-play: +1 Mark
- Void Channeler passive: +1 extra Mark per Void Bolt damage event
- Abyssal Sacrificer passive: +1 Mark when a Void Imp dies
- Mark the Target spell: +2 Marks directly
- Mark Convergence spell: doubles current Mark count

### Void Bolt Damage
`total_damage = base_damage + (void_marks × bonus_per_mark)`

- Base bonus per mark: **25** damage
- With **deepened_curse** talent: **50** damage per mark

Any effect labelled "Void Bolt damage" scales with marks. Regular damage does not.

### Void Manifestation Talent
Void Imp Clan minions deal Void Bolt damage when attacking the enemy hero:
- Damage = Void Bolt formula instead of physical ATK
- Does NOT bypass Guard (Guard enforcement still applies)

---

## 13. Trigger Event System

`TriggerManager` is the central event dispatcher. Events fire all registered handlers in priority order (lower priority number = fires first).

### TriggerEvent Enum

**Player Turn**
- `ON_PLAYER_TURN_START` — Start of player turn (rune auras, environment passives)
- `ON_PLAYER_TURN_END` — End of player turn

**Enemy Turn**
- `ON_ENEMY_TURN_START` — Start of enemy turn
- `ON_ENEMY_TURN_END` — End of enemy turn

**Card Play**
- `ON_PLAYER_CARD_DRAWN` — Player draws a card (ctx.card)
- `ON_PLAYER_MINION_PLAYED` — Fires when player plays a minion from hand, **before** the minion joins `player_board`. The slot is already occupied visually (to prevent token effects from stealing the slot), but `ALL_FRIENDLY` scopes will not include the caster yet. On-play effects that target other friendly minions use this event.
- `ON_PLAYER_MINION_SUMMONED` — After minion enters board from ANY source (fires after `player_board.append()` so the minion is visible to ALL_FRIENDLY scopes)
- `ON_PLAYER_SPELL_CAST` — Player casts a spell (ctx.card)
- `ON_PLAYER_TRAP_PLACED` — Player places a trap/rune
- `ON_PLAYER_ENVIRONMENT_PLACED` — Player places an environment
- `ON_ENEMY_MINION_PLAYED` — Enemy plays a minion from hand (fires before `ON_ENEMY_MINION_SUMMONED`). On-play battlecries gate on this event so token summons (Brood Call etc.) don't retrigger them.
- `ON_ENEMY_MINION_SUMMONED` — Enemy minion enters board from ANY source (hand play, token summon, on-death summons)
- `ON_ENEMY_SPELL_CAST` — Enemy casts a spell
- `ON_ENEMY_ATTACK` — Enemy minion is about to attack (ctx.minion = attacker)

**Minion Death**
- `ON_PLAYER_MINION_DIED` — Friendly minion dies
- `ON_ENEMY_MINION_DIED` — Enemy minion dies

**Damage**
- `ON_HERO_DAMAGED` — Any hero takes damage
- `ON_ENEMY_HERO_DAMAGED` — Enemy hero takes damage

**Ritual**
- `ON_RUNE_PLACED` — A rune is placed (checks ritual conditions)
- `ON_RITUAL_ENVIRONMENT_PLAYED` — Ritual environment placed (checks ritual conditions)

**Combat Lifecycle**
- `ON_COMBAT_START` — Combat begins
- `ON_COMBAT_END` — Combat ends

### EventContext Fields
| Field | Type | Description |
|---|---|---|
| `event_type` | TriggerEvent | Which event fired |
| `owner` | String | "player" or "enemy" |
| `minion` | MinionInstance | Primary minion |
| `target` | MinionInstance | Player-chosen target for targeted effects |
| `card` | CardData | Card played/drawn |
| `damage` | int | Damage amount |
| `cancelled` | bool | Set true to cancel the action |
| `override_effect` | bool | Set true to suppress default on-play effect |

---

## 14. Hero System

### HeroData Fields
- `id`, `hero_name`, `title`, `faction`
- `portrait_path`, `frame_path`
- `passives` — Array of HeroPassive (always-active in all combats)
- `starter_deck` — Card IDs for initial deck
- `talent_branch_ids` — Available talent trees
- `flavor` — Thematic quote

### Lord Vael, Void Caller (Current Only Hero)
**Faction:** Abyss Order

**Passives (always active):**
- `void_imp_boost` — Void Imps enter with +100/+100 (base stats become 200/200)
- `void_imp_extra_copy` — Up to 4 copies of Void Imp allowed in deck (same as other units; may be expanded by upgrades)

**Starter Decks:** Players choose from 3 preset decks of 15 cards each in the DeckBuilderScene. Decks are defined in `PresetDecks.gd`:
- **Swarm** — Board-flood with Imps and Demons; Shadow Hound scales with board width.
- **Voidbolt Burst** — Sacrifice Imps to fuel spells; burn the enemy hero with Void Bolts.
- **Death Circle** — Place Runes to empower Demons; complete the ritual to summon a Demon Ascendant.

**Talent Branches:** swarm · rune_master · void_bolt

---

## 15. Talent System

Talents are unlocked during a run using talent points (1 at start; more from relics). Each talent is in a branch and requires the previous tier to be unlocked first.

### TalentData Fields
- `id`, `talent_name`, `description`, `hero_id`, `branch`, `tier`
- `requires` — Prerequisite talent ID
- `grand_ritual` — Optional RitualData (capstone talent only)

---

### Branch 1 — Endless Tide (Swarm)
*Focus: multiply Void Imps, snowball stats*

| Tier | ID | Name | Effect |
|---|---|---|---|
| 0 | imp_evolution | Imp Evolution | When you summon a Void Imp, add a Senior Void Imp to your hand (once per turn) |
| 1 | swarm_discipline | Swarm Discipline | All Void Imps gain +100 HP |
| 2 | imp_warband | Imp Warband | When Senior Void Imp is summoned, all Void Imps permanently gain +50 ATK |
| 3 | void_echo | Void Echo | CAPSTONE: Once per turn, when a Void Imp is drawn, add a free copy to hand |

---

### Branch 2 — Rune Master
*Focus: deploy runes through imp play, double auras, Grand Ritual*

| Tier | ID | Name | Effect |
|---|---|---|---|
| 0 | rune_caller | Rune Caller | When you play a Void Imp from hand, draw a random Rune from your deck |
| 1 | runic_attunement | Runic Attunement | All Rune aura effects are doubled |
| 2 | ritual_surge | Ritual Surge | When a ritual fires, summon a Void Imp |
| 3 | abyss_convergence | Abyss Convergence | Unlocks Grand Ritual: Blood + Dominion + Shadow → Abyssal Dominion *(no Environment required)* |

**Runic Attunement doubled values:**
| Rune | Base | Doubled |
|---|---|---|
| Void Rune | 100 Void Bolt/turn | 200 Void Bolt/turn |
| Blood Rune | 100 HP per death | 200 HP per death |
| Dominion Rune | +100 ATK to Demons | +200 ATK to Demons |
| Shadow Rune | 1 Corruption on summon | 2 Corruption on summon |

---

### Branch 3 — Void Resonance (Void Bolt)
*Focus: Void Mark stacking, Void Bolt burst damage*

| Tier | ID | Name | Effect |
|---|---|---|---|
| 0 | piercing_void | Piercing Void | Void Imp on-play becomes 200 Void Bolt + 1 Mark. Void Imp costs +1 Mana. Unlocks Void Bolt support pool. |
| 1 | deepened_curse | Deepened Curse | Void Mark bonus damage: 25 → 50 per mark |
| 2 | death_bolt | Death Bolt | When a Void Imp dies, deal 100 Void Bolt damage to the enemy hero |
| 3 | void_manifestation | Void Manifestation | Void Imp Clan minions deal Void Bolt damage when attacking the enemy hero |

---

### Talent Interaction Notes
- `rune_caller` fires only on Void Imp **played from hand** — not on tokens from Imp Evolution, Ritual Surge, or Call the Swarm.
- `imp_evolution` fires once per turn even if multiple Void Imps are summoned.
- `runic_attunement` doubles the **value** of each aura, not the number of times it fires.
- `ritual_surge` imps enter after ritual resolution — they benefit from any permanent stat grants from the ritual.
- `abyss_convergence` Grand Ritual fires before any 2-rune environment ritual when all 3 runes are present.
- `void_manifestation` Void Imp Clan minions deal Void Bolt damage (with Void Mark bonus) when hitting the enemy hero. Does not bypass Guard.

---

## 16. Relic System

Relics are **activated abilities** with limited charges and cooldowns. They persist across a run but charges reset each combat. The player acquires one relic per act boss defeated.

### RelicData Fields
- `id`, `relic_name`, `description`
- `act` — Which act offers this relic (1, 2, or 3)
- `charges` — Number of uses per combat
- `cooldown` — Turns before first use and between uses
- `effect_id` — Effect identifier for activation logic

### Activation Rules
- **1 relic activation per turn** — cannot fire multiple relics in the same turn.
- **Cooldown** = turns before available. First available turn = cooldown + 1.
- **After each use**, the relic goes on cooldown again for the same duration.
- **Charges reset** at the start of each new combat.

### Acquisition
- **Act 1 boss**: choose 1 of 2 random relics from the Act 1 pool.
- **Act 2+ bosses**: choose 1 of 2 random relics from that act's pool, **OR** +1 charge to a random existing relic.

### Act 1 Relics (utility / resource)
| ID | Name | Charges | Cooldown | Effect |
|---|---|---|---|---|
| scouts_lantern | Scout's Lantern | 1 | 3 | Draw 2 cards |
| imp_talisman | Imp Talisman | 1 | 3 | Add a Void Imp to your hand |
| mana_shard | Mana Shard | 2 | 2 | Gain +2 Mana this turn (cannot exceed max) |
| bone_shield | Bone Shield | 1 | 5 | Your hero takes no damage until your next turn |

### Act 2 Relics (tempo / removal)
| ID | Name | Charges | Cooldown | Effect |
|---|---|---|---|---|
| void_lens | Void Lens | 1 | 4 | Cast Abyssal Plague (1 Corruption ALL + 100 AoE) for free |
| soul_anchor | Soul Anchor | 1 | 4 | Summon a 300/300 Void Spark and grant it Guard |
| dark_mirror | Dark Mirror | 1 | 3 | Reduce the cost of your next card by 2 Essence and 2 Mana (minimum 0) |
| blood_chalice | Blood Chalice | 1 | 3 | Deal 500 damage to a target enemy |

### Act 3 Relics (powerful / game-swinging)
| ID | Name | Charges | Cooldown | Effect |
|---|---|---|---|---|
| void_hourglass | Void Hourglass | 1 | 5 | Take an extra turn after this one |
| oblivion_seal | Oblivion Seal | 1 | 5 | Summon a 500/500 Void Demon with Lifedrain |
| nether_crown | Nether Crown | 1 | 4 | All friendly minions gain +200 ATK this turn |
| phantom_deck | Phantom Deck | 1 | 4 | Add copies of your 3 highest-cost cards to hand |

### Combat UI
Relics are displayed as a clickable icon bar below the End Turn panel. Each icon shows charge count and cooldown timer. Hovering shows a tooltip with name, description, charges, cooldown, and current status.

### Sim Support
RelicRuntime + RelicEffects are shared between CombatScene (live) and CombatSim (headless). The sim AI uses simple heuristics: draw/imp relics fire on cooldown, mana shard fires after play phase if castable cards remain, bone shield fires after attacks if enemy threatens lethal.

---

## 17. Progression & Run Structure

### Run State (GameManager)
| Field | Description |
|---|---|
| `player_hp_max` | Max hero HP (default 3000) |
| `player_hp` | Current HP — persists between fights |
| `core_unit_limit` | Max copies of core unit in deck (default 4) |
| `player_deck` | Array of card IDs in current deck |
| `player_relics` | Relic IDs collected this run |
| `relic_bonus_charges` | Dictionary of relic_id → bonus charges from upgrades |
| `unlocked_talents` | Talent IDs unlocked this run |
| `talent_points` | Unspent talent points (start with 1) |
| `permanent_unlocks` | Cards unlocked permanently (survives between runs) |
| `run_node_index` | Current fight index (1-based, 1–15) |

### Act Structure
| Act | Title | Fights | Boss Index (1-based) |
|---|---|---|---|
| Act 1 | The Imp Lair | 3 fights (1–3) | 3 |
| Act 2 | The Abyss Dungeon | 3 fights (4–6) | 6 |
| Act 3 | The Void Rift | 3 fights (7–9) | 9 |
| Act 4 | The Final Descent | 6 fights (10–15) | 15 (final boss) |

### Boss Drops (Permanent Unlocks)
- Rolled after boss defeat.
- One card offered per eligible entry in hero's reward pool.
- Cards that satisfy talent requirements are added to the eligible pool.
- Rarity availability by act:
  - Act 1: common only
  - Act 2: common + rare
  - Acts 3–4: all rarities (common/rare/epic/legendary)

### Lord Vael — Common Pool (always available)
imp_recruiter, blood_pact, soul_taskmaster, soul_shatter, void_amplifier, soul_rune

### Lord Vael — Piercing Void Pool (requires piercing_void talent)
mark_the_target, void_detonation, abyssal_arcanist, void_archmagus, abyss_ritual_circle

### Lord Vael — Endless Tide Pool (requires imp_evolution talent)
imp_frenzy, imp_martyr, imp_vessel, imp_idol, vaels_colossal_guard

### Lord Vael — Rune Master Pool (requires rune_caller talent)
runic_blast, runic_echo, rune_warden, rune_seeker, echo_rune

---

## 18. Enemy Encounters

All 15 encounters are defined in `GameManager._build_encounter()`. Indices are 1-based.

### Act 1 — The Imp Lair
| Index | Name | HP | Profile | Passives |
|---|---|---|---|---|
| 1 | Rogue Imp Pack | 1800 | feral_pack | pack_instinct, champion_rogue_imp_pack |
| 2 | Corrupted Broodlings | 2100 | corrupted_brood | corrupted_death, champion_corrupted_broodlings |
| 3 | Imp Matriarch *(boss)* | 2200 | matriarch | ancient_frenzy, champion_imp_matriarch |

### Act 1 Enemy Passives
| ID | Name | Effect |
|---|---|---|
| pack_instinct | Pack Instinct | Each Feral Imp on board gains +50 ATK per other Feral Imp (dynamic aura) |
| corrupted_death | Corrupted Death | Void-Touched Imp costs -1 Essence (static discount) |
| ancient_frenzy | Ancient Frenzy | Pack Frenzy costs -1 Mana. On cast, also grants Lifedrain to all Feral Imps |

#### Act 1 Decks

**Fight 1 — Rogue Imp Pack** (14 cards, identity: SWIFT rush):
rabid_imp ×5, imp_brawler ×3, rogue_imp_elder ×1, feral_surge ×3, void_screech ×2

**Fight 2 — Corrupted Broodlings** (14 cards, identity: death punishment):
void_touched_imp ×5, brood_imp ×3, frenzied_imp ×2, matriarchs_broodling ×1, void_screech ×2, feral_surge ×1

**Fight 3 — Imp Matriarch** (12 cards, identity: summoner boss):
brood_call ×6, pack_frenzy ×2, feral_surge ×2, void_screech ×2
No minions — all board presence from brood_call summons. Pure mana growth.

Deck identity principle: zero signature card overlap between fights. Rabid Imp only in Fight 1, Void-Touched Imp only in Fight 2, Pack Frenzy only in Fight 3.

### Act 2 — The Abyss Dungeon
| Index | Name | HP | Profile | Passives |
|---|---|---|---|---|
| 4 | Abyss Cultist Patrol | 2800 | cultist_patrol | feral_reinforcement, corrupt_authority, champion_abyss_cultist_patrol |
| 5 | Void Ritualist | 3400 | void_ritualist | feral_reinforcement, ritual_sacrifice, champion_void_ritualist |
| 6 | Corrupted Handler *(boss)* | 4000 | corrupted_handler | feral_reinforcement, void_unraveling, champion_corrupted_handler |

### Act 2 Enemy Passives
| ID | Name | Effect |
|---|---|---|
| feral_reinforcement | Feral Reinforcement | First Human summoned each turn → enemy draws a random Feral Imp (once per turn) |
| corrupt_authority | Corrupt Authority | Each Human summoned → 1 Corruption to random player minion. Each Feral Imp summoned → consume all Corruption stacks, deal 100 damage per stack |
| corrupted_death | Corrupted Death | Void-Touched Imp costs -1 Essence (static discount) |
| ritual_sacrifice | Ritual Sacrifice | When Feral Imp summoned with Blood Rune + Dominion Rune active → consume runes + imp, deal 200 damage ×2, summon 500/500 Void Demon |
| void_unraveling | Void Unraveling | When Human summoned → spawn 100/100 Void Spark. When Feral Imp summoned → consume 1 friendly Void Spark, grant +100/+100 to that imp. End of enemy turn → corrupt 1 random friendly spark and transfer it to player board |

### Act 2 Enemy-Only Cards (abyss_cultist_clan pool)
| Card | Cost | ATK/HP | Type | Effect |
|---|---|---|---|---|
| cult_fanatic | 2E | 300/300 | Human | — |
| dark_command | 1M | — | Spell | +100 ATK and +100 HP to all friendly Humans (permanent) |

#### Act 2 Decks

**Fight 4 — Abyss Cultist Patrol** (14 cards, identity: corruption burst):
abyss_cultist ×5, corruption_weaver ×3, spell_taxer ×2, void_screech ×2, dark_command ×2

**Fight 5 — Void Ritualist** (12 cards, identity: ritual setup):
cult_fanatic ×5, dominion_rune ×2, blood_rune ×2, dark_command ×2, rune_seeker ×1

**Fight 6 — Corrupted Handler** (14 cards, identity: spark factory):
abyss_cultist ×3, cult_fanatic ×2, brood_imp ×3, void_stalker ×2, void_spawner ×2, dark_command ×2

Deck identity principle: zero signature card overlap. Abyss_cultist+corruption_weaver only in Fight 4, cult_fanatic+runes only in Fight 5, brood_imp+void_spawner only in Fight 6.

### Act 3 — Void Rift World
| Index | Name | HP | Profile | Passives |
|---|---|---|---|---|
| 7 | Rift Stalker | 3000 | rift_stalker | void_rift, void_empowerment, champion_rift_stalker |
| 8 | Void Aberration | 3400 | void_aberration | void_rift, void_detonation_passive, champion_void_aberration |
| 9 | Void Herald *(boss)* | 4000 | void_herald | void_rift, void_mastery, champion_void_herald |

### Act 4 — Void Castle
| Index | Name | HP | Profile | Passives |
|---|---|---|---|---|
| 10 | Void Scout | 5000 | void_scout | void_might, void_precision, champion_void_scout |
| 11 | Void Warband | 5000 | void_warband | void_might, spirit_resonance, champion_void_warband |
| 12 | Void Captain | 6200 | void_captain | void_might, captain_orders |
| 13 | Void Ritualist Prime | 7000 | void_ritualist_prime | void_might, dark_channeling |
| 14 | Void Champion | 7800 | void_champion | void_might, champion_duel |
| 15 | Abyss Sovereign *(final boss, Phase 1)* | 3000 | abyss_sovereign | void_might, abyssal_mandate, dark_channeling |

### Act 4 Enemy Passives
| ID | Effect |
|---|---|
| void_might | At enemy turn start, grant 1 random friendly minion +1 Critical Strike |
| void_precision | After an enemy minion deals crit damage, grant it +200 ATK permanently |
| spirit_resonance | Spirits with crit have +1 effective spark_value. Consuming a crit-Spirit spawns a 100/100 Void Spark |
| captain_orders | Crit multiplier is 2.5× instead of 2× |
| dark_channeling | When enemy casts a spell, consume 1 crit from a random friendly minion to cast the spell at 1.5× damage |
| abyssal_mandate | (F15 Phase 1) The player's most recent resource-growth choice grants the enemy a matching discount for one enemy turn: Essence → all enemy minions cost −2 Essence; Mana → all enemy spells cost −2 Mana. Discount clears at end of the enemy turn. |
| champion_duel | Enemy minions with Critical Strike have Spell Immune |

### Champion Units

Every encounter has a **champion unit** named after the encounter itself. Champions are auto-summoned (not from deck) when a fight-specific condition is met. Killing the champion has no built-in HP-damage payoff — their threat is purely the aura/on-board effect they project while alive.

**Champion effects are aura-type or keywords only — no on-play effects.**

**UI**: A visible counter shows progress toward the champion summon. Visual urgency escalates:
- Below 50%: white/grey, no animation
- 50-75%: yellow, gentle pulse
- 75%+: orange/red, urgent pulse
- Trigger: full screen effect, champion slams onto the board

Each time the counter increments, the UI pulses/highlights to alert the player.

#### Act 1 Champions
| Champion | HP | ATK | Keywords | Summon Condition | Effect |
|---|---|---|---|---|---|
| Rogue Imp Pack | 400 | 300 | SWIFT | 4 different rabid imps have attacked | Aura: all friendly imps gain +100 ATK |
| Corrupted Broodlings | 400 | 200 | — | 3 friendly minions have died | On Death: summon a Void-Touched Imp |
| Imp Matriarch | 500 | 300 | GUARD | 2nd Pack Frenzy cast | Aura: Pack Frenzy also grants +200 HP |

#### Act 2 Champions
| Champion | HP | ATK | Keywords | Summon Condition | Effect |
|---|---|---|---|---|---|
| Abyss Cultist Patrol | 300 | 300 | — | 5 corruption stacks consumed | Aura: corruption applied to player minions instantly detonates |
| Void Ritualist | 300 | 200 | — | First ritual sacrifice triggers | Aura: rune placement costs 1 less mana |
| Corrupted Handler | 300 | 300 | — | 3 void sparks created | Aura: Void Spark summoned → deal 200 damage to player hero + heal 200 HP to enemy hero |

#### Act 3 Champions
| Champion | HP | ATK | Keywords | Summon Condition | On-Board Effect |
|---|---|---|---|---|---|
| Rift Stalker | 700 | 400 | SWIFT | 4 sparks consumed as costs | Spark-cost cards cost 1 fewer spark |
| Void Aberration | 800 | 400 | — | Void detonation has hit 5+ times | Spark consumption deals 150 damage instead of 100 |
| Void Herald | 1000 | 500 | GUARD | 6 sparks consumed as costs | Spark costs become 0 (free) for rest of fight |

#### Act 4 Champions
| Champion | HP | ATK | Keywords | Summon Condition | On-Board Effect |
|---|---|---|---|---|---|
| Void Scout | 500 | 400 | — | 5 crits consumed | At end of enemy turn, all friendly crit minions gain +200 ATK |
| Void Warband | 600 | 500 | — | 2 Spirits consumed as fuel | Aura: when a friendly Spirit dies, apply 1 Critical Strike to a random friendly minion |
| *F12–F15 champions not yet implemented* | | | | | |

### Fight Modifiers & Difficulty

**Modifiers** are per-fight environmental effects that vary between runs, separate from enemy passives. They are shown on the encounter loading screen and as a banner during combat.

- **Enemy passives** = "who the enemy is" (fixed per encounter)
- **Modifiers** = "what's different this run" (randomized, environmental)

Modifiers can be **global** (apply to any act) or **act-specific** (interact with that act's theme).

**Difficulty levels** control both modifier count and enemy passive strength:

| Difficulty | Modifiers per Fight | Passive Strength |
|---|---|---|
| Easy | 0-1 | Base |
| Medium | 1-2 | Enhanced |
| Hard | 2-3 | Maximum |

When stacking multiple modifiers, they should be drawn from different categories (offensive / defensive / constraint) to create interesting decisions rather than doubling down on one axis.

Act-specific modifier examples:
- **Act 1 (Swarm)**: "Feral Frenzy" — enemy starts with 2 imps on board
- **Act 2 (Corruption)**: "Spreading Corruption" — corruption stacks tick +1 at end of player turn
- **Act 3 (Sparks)**: "Volatile Sparks" — sparks explode for 150 damage (both sides) when killed
- **Act 4 (Crit)**: "Battle Hardened" — enemy minions start with 1 crit stack

### Deck Identity Principle

Each encounter's deck should be built around **signature cards** that only that encounter uses. Shared filler cards are acceptable for mid-game but the first 1-2 turns must look visually and mechanically distinct from other encounters in the same act. The signature card should appear at high count (4-5 copies) to define the fight's identity.

---

## 19. Enemy AI

### Resources
- Same dual-resource system as player (essence + mana; combined cap 11).
- **Growth rule:** Grows Mana if `mana_max < essence_max − 2`; otherwise grows Essence.

### Deck & Hand
- Real shuffled deck drawn without replacement.
- On draw: card moves to hand AND a fresh replacement is inserted and reshuffled (infinite pool simulation).
- Max hand: **10 cards**.
- Draws **1 card per turn** (+ opening hand of 5).

### Play Phase
The base AI uses a greedy algorithm. Encounter-specific profiles may override this with custom logic (e.g. FeralPackProfile plays minions before spells).

**Base greedy algorithm:**
1. Sort hand by total cost (essence + mana) ascending.
2. Play cheapest affordable card.
3. Repeat until no more playable cards remain.

**FeralPackProfile (Act 1 — encounter 0):**
1. Pass 1 — flood board with minions, cheapest first.
2. Pass 2 — cast affordable spells that meet their cast conditions.
3. Attack phase — cast Pack Frenzy before attacking if the board has ≥ 3 Feral Imps OR it achieves lethal. `void_screech` is held until board is full or no more minions in hand. `feral_surge` is held until a Feral Imp is on board.

**MatriarchProfile (Act 1 — encounter 2, Imp Matriarch boss):**
Extends FeralPackProfile with a survival Pack Frenzy condition.
- Same play phase and base Pack Frenzy logic as FeralPackProfile.
- Additional Pack Frenzy trigger when HP ≤ 1200 (40 % of max): if Ancient Frenzy is active (grants Lifedrain), the player has minions on board, and ≥ 2 Feral Imps are present — fire Pack Frenzy to clear the board and leech HP back even if the value threshold is not met.

**Ancient Frenzy passive (Imp Matriarch):** Pack Frenzy costs 1 less Mana, also grants all Feral Imps Lifedrain for the turn, and adds one guaranteed Pack Frenzy to the opening hand at the start of the encounter.

**CultistPatrolProfile (Act 2 — encounter 4):**
Corruption-detonation loop with interleaved human/imp play.
1. Play up to 2 Humans per turn (triggers feral_reinforcement → draws imp + corrupt_authority → applies corruption).
2. Immediately play any Feral Imps drawn (detonates corruption stacks).
3. Cast spells (Dark Command, Abyssal Plague).
4. Resource growth: mana to 2 early (for spells), then essence-first.

**VoidRitualistProfile (Act 2 — encounter 5):**
Ritual sacrifice combo with rune setup.
1. Play runes first (Blood Rune + Dominion Rune for ritual).
2. Play up to 2 Humans (draws imps via feral_reinforcement).
3. Cast spells (Dark Command).
4. Play Feral Imps LAST (triggers ritual_sacrifice if both runes active → 200 dmg ×2 + 500/500 Demon).
5. Resource growth: if abyss_cultist in hand → mana to 2 first, then essence to 5, mana to 4, essence to 7.

**CorruptedHandlerProfile (Act 2 — encounter 6, boss):**
Void Unraveling loop with post-attack imp play.
1. Play Humans (triggers feral_reinforcement + board presence).
2. Cast spells.
3. Attack with all minions — Humans trade and die → Void Sparks spawn on enemy board.
4. AFTER attacks: play Feral Imps → triggers void_unraveling → corrupted Void Sparks transferred to player board (clogs their slots).
5. Ignores 0-ATK Void Sparks on opponent board when choosing attack targets.
6. Resource growth: essence to 7, then mana to 2, then all essence.

### Attack Phase
- Every ready minion attacks in board order (slot 0 → slot 4).
- Guard enforcement applies (must target Guard minions if present).
- **Smart attack logic:** If the total ATK of player minions on board equals or exceeds the enemy hero's current HP, the enemy trades into player minions instead of attacking face — to clear the lethal threat before it resolves.
- Delay: 0.55 seconds between actions.

### Signals
- `enemy_about_to_attack` — fires before attack (for trap resolution)
- `enemy_attacking_hero` — fires when enemy minion targets the player hero

---

## 20. Win & Loss Conditions

### Victory
- Enemy hero HP ≤ 0.
- Run advances; card/relic rewards offered.
- If final boss (index 14): permanent unlock cards offered.

### Defeat
- Player hero HP ≤ 0.
- Run ends; return to main menu / retry option.

---

## 21. Known Gaps / TODO

| Area | Status |
|---|---|
| Enemy traps | Enemy rune/trap placement implemented for Act 2 profiles. |
| Fatigue damage | When deck is empty and discard is also empty, no damage is applied yet. |
| Hero powers | Not yet designed or implemented. |
| Additional heroes | Lord Vael only. More planned for future. |
| More factions | Abyss Order + neutral + Feral Imp Clan + Abyss Cultist Clan (enemy-only). |
| Act 3-4 encounters | Use placeholder decks and default AI profile. Need custom profiles and decks. |
| Scoring-based AI | Infrastructure built (ScoredCombatProfile, BoardEvaluator, ScoringWeights) but not used in production encounters. Available for future use. |
| Relic UI polish | Relic bar icons need art assets. Currently uses default button style. |
