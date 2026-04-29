# Echo of Abyss — Rune, Ritual & Ritual Environment System
**Version:** 0.1 (pre-alpha)
**Last updated:** 2026-03-15

---

## Table of Contents
1. [Overview](#1-overview)
2. [Rune Cards](#2-rune-cards)
3. [Rune Keywords](#3-rune-keywords)
4. [Ritual System](#4-ritual-system)
5. [Ritual Environments](#5-ritual-environments)
6. [Lord Vael — Rune Mastery Branch](#6-lord-vael--rune-mastery-branch)
7. [Card Type Updates](#7-card-type-updates)

---

## 1. Overview

The Rune and Ritual system adds a proactive, setup-oriented layer on top of the existing reactive trap system. Runes are a subtype of Trap that behave as **persistent passive auras** rather than one-shot reactive effects — the key distinction that separates them from normal traps at a glance.

### How It Works

1. Player plays a Rune card from hand — it enters the board **face-up** and immediately begins applying its passive aura.
2. Runes occupy the **shared trap slot limit (max 3)**. A player running two runes only has one slot left for normal traps.
3. If the active **Environment card** defines a ritual combination, and the required runes are simultaneously on board, the **ritual fires immediately**.
4. Ritual resolution **consumes the required runes** and executes the ritual effect.
5. The environment's base passive remains active before, during, and after any ritual fires.

### Key Distinctions from Normal Traps

| Property | Normal Trap | Rune |
|---|---|---|
| Placement | Face-down | Face-up (Revealed) |
| Consumed on trigger? | Yes (one-use) | No (Persistent) |
| Effect type | Reactive trigger | Passive aura (always on) |
| Ritual component? | No | Yes (Rune Component) |
| Destroyed by trap removal? | Yes | Yes |

### Player Cannot Self-Remove Runes

Once placed, the player has no way to manually remove their own runes. This is intentional — a rune is a permanent commitment for the combat. The aura value it provides justifies the locked slot. The only way a rune leaves the board is if the enemy destroys it via trap removal (Cyclone, Trapbreaker Rogue, Gate Collapse, Hurricane, etc.). This creates a meaningful deckbuilding tradeoff: each rune permanently occupies one of your three trap slots in exchange for a standing passive aura.

---

## 2. Rune Cards

All runes share the Trap type and are destroyed by any trap removal effect. All stats use the ×100 internal scale.

| Name | Cost | Rune Type | Passive Aura |
|---|---|---|---|
| Void Rune | 2M | Void | At the start of your turn, deal 100 Void Bolt damage to the enemy hero *(scales with Void Marks)* |
| Blood Rune | 2M | Blood | Whenever a friendly minion dies, restore 100 HP to your hero |
| Dominion Rune | 1M | Dominion | All friendly Demons have +100 ATK |
| Shadow Rune | 1M | Shadow | Enemy minions enter the board with 1 stack of Corruption |

### Design Notes

**Void Rune** deals Void Bolt damage, meaning it scales with Void Marks. At zero marks it is modest chip damage useful in any build; in a deep Void Resonance build with many marks stacked it becomes a meaningful pressure engine every turn start.

**Blood Rune** fires on every friendly minion death with no per-turn cap. In a sacrifice or imp-death loop build this is significant sustain — popping three imps in a turn restores 300 HP. It rewards the sacrifice archetype without being useful in a vacuum.

**Dominion Rune** applies a board-wide +100 ATK aura to all friendly Demons for only 1 Mana. This is the rune most likely to be targeted by enemy trap removal, creating real tension between playing it early for value versus waiting until ready to complete a ritual.

**Shadow Rune** applies Corruption on entry to every enemy minion, making it a corrupting field that affects the board state continuously. It is extremely strong alongside any Corruption-synergy cards and future hero talents that interact with Corruption stacks.

---

## 3. Rune Keywords

| Keyword | Effect |
|---|---|
| **Revealed** | Placed face-up; visible to both players at all times |
| **Persistent** | Not consumed on trigger; remains on board until destroyed |
| **Rune Component** | Counts toward ritual combinations defined by the active Environment card |

---

## 4. Ritual System

### Concept

A **Ritual** is a powerful one-time spell effect that fires automatically when specific rune conditions are met. Rituals are defined on **Environment cards** — the environment acts as the ritual enabler, and the runes act as components.

```
Runes on board + matching Environment → Ritual fires immediately
```

### Ritual Timing

The ritual check fires **immediately** in two situations:
- When a **rune is placed** — checks if the active environment's ritual conditions are now met
- When an **environment is placed** — checks if the required runes are already on board

This means the order of play does not matter. Playing runes first and the environment second triggers the ritual on environment placement just as reliably as playing the environment first and completing the runes second.

### Ritual Resolution Order

1. Check for valid 3-rune rituals first (enabled by Talents or Relics)
2. Check for valid 2-rune rituals defined by the active environment
3. If valid: consume the required runes, then execute the ritual effect
4. The environment remains active after the ritual fires

### 2-Rune Ritual Conflict Rule

Each Environment card defines its own ritual combinations. By design, a single environment never defines two combinations that could simultaneously be valid with the same set of three runes — conflicts are avoided at the design level.

### Special Summon

Units summoned by rituals use **Special Summon** rules:
- The unit appears directly on the board
- **On Play effects do NOT trigger**
- Passive abilities, Taunt, Lifedrain, Rush, and On Death effects remain active normally

---

## 5. Ritual Environments

### Core — Abyss Order

#### Abyssal Summoning Circle
**Cost:** 3M · **Faction:** Abyss Order · **Type:** Environment (Ritual)

**Base passive:** Whenever a friendly minion dies, deal 100 damage to the enemy hero.
*(Fires on both player and enemy turns.)*

**Ritual — Blood + Dominion → Demon Ascendant**
Consume both runes. Deal 200 damage to 2 random enemy minions. Special Summon a 500/500 Demon.

> The passive rewards swarm and sacrifice play — every imp death chips the enemy hero. Blood Rune converts those same deaths into healing, so the full package of Abyssal Summoning Circle + Blood Rune + Dominion Rune creates a self-sustaining death loop that culminates in a 500/500 Demon. Total setup cost is 6M (3M environment + 2M Blood Rune + 1M Dominion Rune) spread across multiple turns.

---

### Piercing Void Support Pool — Abyss Order

*(Available only when `piercing_void` talent is unlocked. Never appears in the deck builder.)*

#### Abyss Ritual Circle
**Cost:** 3M · **Faction:** Abyss Order · **Type:** Environment (Ritual) · **Rarity:** Epic

**Base passive *(both sides)*:** At the start of each turn, deal 100 damage to a random minion on the battlefield.
*(Can hit any minion — friendly or enemy. Fires on both player and enemy turns.)*

**Ritual — Void + Blood → Soul Cataclysm**
Consume both runes. Deal 400 Void Bolt damage to the enemy hero. Restore 400 HP to your hero.

> The random minion ping creates urgency to complete the ritual quickly, naturally pushing toward a swarm style of small imps. Soul Cataclysm's 400 Void Bolt damage scales with Void Marks, making it a massive burst swing in a deep Void Resonance build. The 400 HP restoration makes it a simultaneous life swing of up to 800 points. Total setup cost is 7M (3M environment + 2M Void Rune + 2M Blood Rune) spread across turns.

---

## 6. Lord Vael — Rune Mastery Branch

This branch replaces the Corruption branch. It is Lord Vael's dedicated rune entry point, tying rune deployment naturally to Void Imp play and culminating in a 3-rune Grand Ritual that requires no Environment card.

*Focus: Deploying runes through imp play, doubling all rune aura effects, and culminating in a board-wide demon power spike*

| ID | Name | Tier | Requires | Effect |
|---|---|---|---|---|
| `rune_caller` | Rune Caller | 1 | — | When you play a Void Imp from hand, draw a random Rune card from your deck |
| `runic_attunement` | Runic Attunement | 2 | rune_caller | All Rune aura effects are doubled |
| `ritual_surge` | Ritual Surge | 3 | runic_attunement | When a ritual fires, summon 2 Void Imps |
| `abyss_convergence` | Abyss Convergence | 4 (Capstone) | ritual_surge | Unlocks the Grand Ritual: when Blood Rune, Dominion Rune, and Shadow Rune are simultaneously on board, **Abyssal Dominion** fires automatically — no Environment required. *Abyssal Dominion: consume all three runes; deal 300 damage to all enemy minions; all friendly Demons permanently gain +200 ATK and +200 HP* |

### Runic Attunement — Doubled Aura Effects

With `runic_attunement` active, all four rune auras are doubled:

| Rune | Base Aura | Doubled Aura |
|---|---|---|
| Void Rune | 100 Void Bolt damage per turn start | 200 Void Bolt damage per turn start |
| Blood Rune | Restore 100 HP per friendly death | Restore 200 HP per friendly death |
| Dominion Rune | All friendly Demons +100 ATK | All friendly Demons +200 ATK |
| Shadow Rune | 1 Corruption on enemy summon | 2 Corruption on enemy summon |

### Talent Interactions

- `rune_caller` fires only when a Void Imp is **played from hand** — not when summoned by effects such as Imp Evolution tokens, Call the Swarm, or Ritual Surge itself.
- `runic_attunement` doubles the value of each rune aura effect, not the number of times it fires. If 3 imps die in a turn with Blood Rune active, it restores 200 × 3, not 100 × 6.
- `ritual_surge` summons 2 Void Imps after ritual resolution — the ritual effect lands first, then the imps enter. Those imps benefit from any permanent buffs granted by the ritual.
- `abyss_convergence` enables the 3-rune Grand Ritual. Abyssal Dominion always fires before any 2-rune ritual from the active environment when all three runes are present. Ritual Surge also fires after Abyssal Dominion — the 2 summoned imps enter a board where all friendly Demons have already received +200/+200 permanently, including the imps themselves since they are Demons.

### Branch Arc

Each tier feeds the next with no conflicts: play imps to draw runes (T1) → all rune auras are doubled (T2) → rituals replenish your imp board (T3) → Grand Ritual fires and permanently empowers everything (T4).

---

## 7. Card Type Updates

### Trap — Updated Definition

- **Cost:** Mana
- **Mechanic:** Placed face-down; triggers automatically when the condition is met during the enemy's turn
- One-use by default (consumed on trigger); reusable flag exists for future use
- Up to **3 trap slots** active simultaneously — shared with Rune cards
- Can be destroyed by trap removal effects (Cyclone, Trapbreaker Rogue, Gate Collapse, Hurricane, etc.)

### Rune — New Subtype of Trap

- **Cost:** Mana
- **Mechanic:** A subtype of Trap. Placed **face-up** (Revealed) on the board; applies a **persistent passive aura** while it remains on the board
- **Persistent** — not consumed on trigger; remains active until destroyed
- Occupies a trap slot (shares the 3-slot limit with normal traps)
- Can be destroyed by any trap removal effect
- Acts as a **Rune Component** for ritual combinations defined by Environment cards
- Ritual check fires **immediately** on placement, and also when a new Environment is placed