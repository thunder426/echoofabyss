# Echo of Abyss — System Changes
**Version:** 0.4 (pre-alpha)
**Last updated:** 2026-03-22

---

## Table of Contents
1. [Card Rarity System](#1-card-rarity-system)
2. [Card Acquisition](#2-card-acquisition)
3. [Card Pool Gating](#3-card-pool-gating)
4. [Card Act Gating Map](#4-card-act-gating-map)
5. [Shop System](#5-shop-system)

---

## 1. Card Rarity System

### Removed
- Common, Rare, Epic, Legendary rarity labels removed entirely
- No rarity-based power hierarchy
- No meta-progression unlock system

### Kept
- **CHAMPION** keyword retained as the only special card designation
- Champion definition: **one copy only** in deck
- Auto-summon is a separate card effect, not tied to Champion keyword

### Act Gating — Replaces Rarity
Cards introduced progressively based on a hidden complexity score assigned per card:

| Act | Card Complexity |
|---|---|
| Act 1 | Simple — work immediately with no setup |
| Act 2 | Synergy — reward build investment |
| Act 3 | Complex — require committed builds |
| Act 4 | Champion cards + all previous |

---

## 2. Card Acquisition

### Normal Fight Reward
- Offer 3 randomly drawn cards from all available pools
- Player chooses 1
- System rerolls any card that already has max copies in deck
- Unchanged from original design

### Boss Fight Reward
- Offer 3 randomly drawn cards from active support pool only
- Player chooses 1
- System rerolls any card that already has max copies in deck
- Support pool availability depends on talent taken this run

### Shop
- One optional map node per act appearing before each boss fight
- Player spends Void Shards to buy cards and services
- System rerolls any card that already has max copies in deck

### Max Copy Limit
All card acquisition channels enforce max copy limits:
- Standard cards: 2 copies maximum
- Champion cards: 1 copy maximum
- If drawn card already at max copies → system rerolls until valid card found

---

## 3. Card Pool Gating

### Core Pool Availability
All core pool cards are unlocked by default and available from the very first run.

**One exception:**

| Card | Unlock Condition |
|---|---|
| Nyx'ael, Void Sovereign | Complete a full run with Lord Vael — defeat the Abyss Sovereign (Fight 15) |

### Support Pool Availability Within Run
One talent branch per run. Taking a talent unlocks that branch's pool for the entire run:

| Talent Taken | Pools Available |
|---|---|
| None | Core pool only |
| Imp Evolution | Core pool + Endless Tide pool |
| Rune Caller | Core pool + Rune Master pool |
| Piercing Void | Core pool + Piercing Void pool |

---

## 4. Card Act Gating Map

### Abyss Order Core Pool
All cards unlocked by default and available from Act 1, except Nyx'ael as noted above.

---

### Abyss Order Common Pool

| Card | Old Rarity | Act Gate |
|---|---|---|
| Imp Recruiter | Common | Act 1 |
| Blood Pact | Common | Act 1 |
| Soul Taskmaster | Rare | Act 2 |
| Soul Shatter | Rare | Act 2 |
| Void Amplifier | Epic | Act 3 |
| Soul Rune | Epic | Act 3 |

---

### Endless Tide Pool *(requires Imp Evolution talent)*

| Card | Old Rarity | Act Gate |
|---|---|---|
| Imp Frenzy | Common | Act 1 |
| Imp Martyr | Rare | Act 2 |
| Imp Vessel | Rare | Act 2 |
| Imp Idol | Epic | Act 3 |
| Vael's Colossal Guard | Legendary | Act 4 — Champion |

---

### Piercing Void Pool *(requires Piercing Void talent)*

| Card | Old Rarity | Act Gate |
|---|---|---|
| Void Surge | Common | Act 1 |
| Abyssal Arcanist | Common | Act 1 |
| Mark the Target | Rare | Act 2 |
| Void Detonation | Rare | Act 2 |
| Abyss Ritual Circle | Epic | Act 3 |
| Void Archmagus | Legendary | Act 4 — Champion |

---

### Rune Master Pool *(requires Rune Caller talent)*

| Card | Old Rarity | Act Gate |
|---|---|---|
| Rune Seeker | Common | Act 1 |
| Runic Blast | Common | Act 1 |
| Rune Warden | Rare | Act 2 |
| Runic Echo | Rare | Act 2 |
| Echo Rune | Legendary | Act 4 — Champion |

---

### Neutral Core Pool
All neutral cards unlocked by default and available from Act 1.

---

### Feral Imp Pool — Enemy Only
All feral imp cards are Act 1 enemy-specific. Not available to players through any acquisition channel.

---

## 5. Shop System

### Currency — Void Shards
Earned through combat. Carried across the entire run, never resets between fights.

| Source | Shards Earned |
|---|---|
| Normal fight win | 1 |
| Boss fight win | 3 |

---

### Shop Appearance
One optional map node per act, appearing **before each boss fight.**
Player chooses whether to visit — skipping is valid.

---

### Shard Budget per Shop Visit

| Shop | Before Shop Shards | Notes |
|---|---|---|
| Shop 1 (before Act 1 boss) | 2 | Limited — only ≤2 Shard items available |
| Shop 2 (before Act 2 boss) | 7 | All options unlocked |
| Shop 3 (before Act 3 boss) | 12 | Champion cards affordable |
| Shop 4 (before Act 4 boss) | 20 | All options including Core Unit Variant |

---

### Full Run Shard Economy

| Act | Normal Fights | Boss Fight | Total per Act |
|---|---|---|---|
| Act 1 | 2× 1 = 2 | 1× 3 = 3 | 5 |
| Act 2 | 2× 1 = 2 | 1× 3 = 3 | 5 |
| Act 3 | 2× 1 = 2 | 1× 3 = 3 | 5 |
| Act 4 | 5× 1 = 5 | 1× 3 = 3 | 8 |
| **Total** | **11** | **12** | **23 Shards** |

---

### Shop Layout

```
4 card slots
2 service slots
```

---

### Card Slots

| Slot | Contents |
|---|---|
| Slot 1 | Guaranteed card from active branch pool |
| Slot 2 | Guaranteed card from active branch pool (different from Slot 1) |
| Slot 3 | Random from any available pool |
| Slot 4 | Random from any available pool |

> If no talent taken — Slots 1 and 2 show core pool cards instead.

---

### Card Pricing

| Card Type | Cost |
|---|---|
| Standard card | 2 Shards |
| Champion card | 4 Shards |

---

### Service Slots
2 randomly selected from 7 services per shop visit.

| Service | Cost | Weight | Available First Shop? |
|---|---|---|---|
| Card Removal | 3 Shards | 3 | ❌ |
| HP Restoration | 1 Shard | 3 | ✅ |
| Refresh Shop | 1 Shard | 3 | ✅ |
| Random Card | 1 Shard | 3 | ✅ |
| Max HP Increase | 4 Shards | 2 | ❌ |
| Expand Core Unit | 3 Shards | 1 | ❌ |
| Add Core Unit Variant | 4 Shards | 1 | ❌ |

**Total weight: 16**

#### Service Descriptions

| Service | Effect |
|---|---|
| Card Removal | Remove one card from deck permanently |
| HP Restoration | Restore 500 HP |
| Refresh Shop | Reroll all 4 card slots and both service slots |
| Random Card | Add a random card from any available pool to deck |
| Max HP Increase | Permanently increase max HP by 300 |
| Expand Core Unit | Increase max Void Imp copies allowed by 1 and add one Void Imp to deck |
| Add Core Unit Variant | Add the branch-appropriate Void Imp variant to deck |

#### Core Unit Variant per Branch

| Talent Branch | Variant Offered |
|---|---|
| Endless Tide | Senior Void Imp |
| Piercing Void | Void Imp Wizard |
| Rune Caller | Runic Void Imp |
| No talent | Random from all three variants |

---

#### Per Slot Probability

| Service | Probability per slot |
|---|---|
| Card Removal | 19% |
| HP Restoration | 19% |
| Refresh Shop | 19% |
| Random Card | 19% |
| Max HP Increase | 12% |
| Expand Core Unit | 6% |
| Add Core Unit Variant | 6% |

---

### First Shop Restrictions
Player arrives with exactly 2 Shards. Items costing more than 2 Shards are removed from the first shop entirely.

**Removed from first shop:**
- Champion cards from card slots
- Card Removal, Max HP Increase, Expand Core Unit, Add Core Unit Variant from service pool

**Available services in first shop:**
- HP Restoration (1 Shard)
- Refresh Shop (1 Shard)
- Random Card (1 Shard)

**First shop decisions with 2 Shards:**

| Option | Cost | Result |
|---|---|---|
| Buy one standard card | 2 Shards | Add card to deck |
| Buy two 1-Shard services | 2 Shards | Any combination of available services |
| Buy one 1-Shard service | 1 Shard | Save 1 Shard for after boss fight |