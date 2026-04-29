# Dagan, the Undefeated — Hero Design Document

**Version:** 0.1 (pre-alpha)  
**Faction:** Neutral  
**Status:** Design phase

---

## 1. Hero Identity

**Name:** Dagan, the Undefeated  
**Title:** Arena Champion  
**Archetype:** A legendary gladiator who rose from the fighting pits to lead a warband of unaffiliated fighters. Dagan answers to no faction — his followers are drawn to his unbeaten record and commanding presence rather than any shared ideology.

---

## 2. Resource System

Dagan uses a single unified resource called **Gold** instead of the dual Essence / Mana system used by Lord Vael.

| Property | Value |
|---|---|
| Resource name | Gold |
| Starting amount | 1 |
| Maximum cap | 10 |
| Growth | +1 per end turn |
| Function | Pays for all card types (Minions, Spells, Traps, Environments) |

Gold simplifies resource management — there is no end turn choice between Essence and Mana growth. This makes Dagan more accessible while the narrower card pool (neutral only) provides its own strategic depth.

**Dual-cost neutral minions** (e.g. Aether Bulwark 3e+2m) cost the sum of their components in Gold, making them easier to play than in a Lord Vael run.

---

## 3. Card Pool

Dagan can only use **neutral cards**. He cannot access Abyss Order cards. The narrower card pool is compensated by the Gold resource's flexibility and convenience.

---

## 4. Core Unit — Arena Challenger

Arena Challenger is Dagan's core unit, functioning as the activator and centerpiece for all three talent branches.

| Card Name | Cost | ATK | HP | Type | Keywords | Effect |
|---|---|---|---|---|---|---|
| Arena Challenger | 3 Gold | 450 | 200 | Untagged | — | On Play: give a friendly minion Taunt |

> **Note:** Rush is removed from the card itself and baked into Dagan's hero passive instead.

---

## 5. Permanent Passives

| Passive | Effect |
|---|---|
| **Arena Empowerment** | Arena Challengers enter the board with Rush |
| **Arena Cap** | May include up to 4 copies of Arena Challenger in the deck (normal cap is 2) |

Arena Cap ensures Arena Challenger flows consistently throughout the run, preventing the hero from feeling dead when the core unit is removed.

---

## 6. New Keyword — Dual Strike

| Keyword | Effect |
|---|---|
| **Dual Strike** | This minion can attack twice per turn. Each attack exhausts one charge. After two attacks the minion is fully exhausted until the next turn. |

**Rules:**
- Dual Strike does not stack — a minion cannot attack more than twice per turn regardless of how many times the keyword is applied
- Rush + Dual Strike: a minion with both can attack twice on the turn it is summoned
- Taunt rules apply to both attacks independently

---

## 7. New Status Effect — Bleeding

| Property | Value |
|---|---|
| Applicable to | Enemy minions and enemy hero |
| Default damage | 50 per stack per turn |
| Duration | 3 turns |
| Stacking | Each additional stack increases total damage per turn (2 stacks = 100/turn, 3 stacks = 150/turn) |
| Refresh | Duration resets to 3 turns when new stacks are applied |
| Removal | Expires naturally after 3 turns if no new stacks are applied |

---

## 8. Talent Tree

Dagan has 3 talent branches, each with 4 tiers. One talent point is granted at run start and one per act boss defeat (up to 4 total).

---

### Branch 1 — Blade Master
*Focus: Arena Challenger applies Bleeding, amplify and burst Bleeding stacks*

| Tier | Name | Effect |
|---|---|---|
| T1 | **First Blood** | When Arena Challenger attacks, apply 1 Bleeding stack to the target |
| T2 | **Deep Cut** | Bleeding damage per stack increases from 50 to 75 |
| T3 | **Fatal Wound** | When a Bleeding enemy dies, deal 100 damage to a random enemy minion |
| T4 Capstone | **Bloodburst** | When a target reaches 3 Bleeding stacks, instantly resolve all remaining duration damage and remove all stacks |

**Bloodburst damage calculation:**
- Base: 3 stacks × 3 turns × 50 = **450 burst damage**
- With Deep Cut: 3 stacks × 3 turns × 75 = **675 burst damage**

---

### Branch 2 — Warband
*Focus: Arena Challenger as cost reduction activator, untagged minion board flooding*

| Tier | Name | Effect |
|---|---|---|
| T1 | **Battle Command** | While Arena Challenger is on board, untagged minions cost 1 less Gold (unstackable) |
| T2 | **Warband Strength** | For each untagged minion on board, Arena Challenger gains +100 ATK |
| T3 | **Rally Cry** | When you play an Arena Challenger, summon a 200/200 Warband Recruit token |
| T4 Capstone | **Iron Vanguard** | Untagged minions that cost more than 5 Gold cost 2 less Gold instead |

**Combined cost reduction with T1 + T4:**
| Minion | Base | T1 | T4 | Combined |
|---|---|---|---|---|
| Wildland Behemoth | 6 | 5 | 4 | 3 |
| Stone Sentinel | 7 | 6 | 5 | 4 |
| Rift Leviathan | 8 | 7 | 6 | 5 |

**Warband Recruit token:** 200/200, Untagged, no effects, not deck-buildable.

---

### Branch 3 — Combat
*Focus: Arena Challenger grows through kills and inspires the whole warband*

| Tier | Name | Effect |
|---|---|---|
| T1 | **Proven Fighter** | When Arena Challenger kills an enemy minion, it gains +100/+100 permanently |
| T2 | **Open Challenge** | Arena Challenger enters with +200 HP. On play, summon a 100/100 untagged token for the enemy |
| T3 | **Lead by Example** | When Arena Challenger kills an enemy minion, a random friendly minion also gains +100/+100 |
| T4 Capstone | **Dual Mastery** | Arena Challenger gains Dual Strike |

**T1 + T2 Combo:**
- Play Arena Challenger (Rush from hero passive)
- Enemy 100/100 token spawns (T2)
- Arena Challenger attacks and kills the token (Rush)
- T1 triggers — Arena Challenger gains +100/+100
- Net result: a 550/400 Arena Challenger that has already attacked once

**Thematic note:** The Open Challenge mechanic reflects the arena gladiator lore — Dagan issues a challenge on entry, a weak opponent steps forward, and Arena Challenger proves their worth by defeating them.

---

## 9. Visual Identity

| Property | Direction |
|---|---|
| Color palette | Bronze, gold, crimson |
| Frame/UI color | Warm gold and amber (distinct from Lord Vael's cool violet) |
| Visual motifs | Arena chains, broken shackles, trophy weapons from defeated opponents |
| Appearance | Battle-scarred veteran in arena armor, commanding presence |
| Background art | Colosseum or fighting pit environment |

---

## 10. Design Notes

- **Single point of failure mitigation:** Arena Cap (4 copies) and Arena Empowerment (Rush) ensure Arena Challenger is always impactful and consistently available throughout the run
- **Branch independence:** Each branch uses Arena Challenger as an activator but pursues a distinct playstyle — Bleeding burst, board flooding, or combat scaling
- **Gold vs dual resource:** Dagan trades strategic resource allocation depth for flexibility and accessibility, compensated by a narrower card pool
- **Dual Strike keyword** is designed as a reusable keyword for future cards beyond just Dagan's talent tree

---

*End of Dagan Hero Design Document · Echo of Abyss*
