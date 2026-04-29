# Echo of Abyss — Card Library
**Version:** 0.6 (pre-alpha)
**Last updated:** 2026-04-25

> This file is the **single source of truth** for all card data.
> All stats use the ×100 internal scale (100 = 1 displayed point).
> Cost notation: **E** = Essence · **M** = Mana · **E+M** = dual cost

---

## Table of Contents
1. [Abyss Order — Core](#1-abyss-order--core)
2. [Abyss Order — Common Pool](#2-abyss-order--common-pool)
3. [Abyss Order — Piercing Void Pool](#3-abyss-order--piercing-void-pool)
4. [Abyss Order — Endless Tide Pool](#4-abyss-order--endless-tide-pool)
5. [Abyss Order — Rune Master Pool](#5-abyss-order--rune-master-pool)
5b. [Abyss Order — Seris Core Pool](#5b-abyss-order--seris-core-pool)
5c. [Abyss Order — Seris Common Support Pool](#5c-abyss-order--seris-common-support-pool)
5d. [Abyss Order — Seris Fleshcraft Pool](#5d-abyss-order--seris-fleshcraft-pool)
5e. [Abyss Order — Seris Demon Forge Pool](#5e-abyss-order--seris-demon-forge-pool)
5f. [Abyss Order — Seris Corruption Engine Pool](#5f-abyss-order--seris-corruption-engine-pool)
6. [Neutral — Core](#6-neutral--core)
7. [Feral Imp Clan — Act 1 Enemy Cards](#7-feral-imp-clan--act-1-enemy-cards)
8. [Abyss Cultist Clan — Act 2 Enemy Cards](#8-abyss-cultist-clan--act-2-enemy-cards)
9. [Tokens & Special Summons](#9-tokens--special-summons)

---

## 1. Abyss Order — Core

*Always available in the card pool. Starter deck draws from this group.*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Void Imp | Abyss Order | abyss_core | 1E | Minion — Demon 100/100 | — | Void Imp | — | ON PLAY: Deal 100 damage to enemy hero. |
| Senior Void Imp | Abyss Order | abyss_core | 2E | Minion — Demon 300/250 | — | Void Imp | — | ON PLAY: Deal 100 damage to enemy hero. |
| Runic Void Imp | Abyss Order | abyss_core | 2E+1M | Minion — Demon 200/300 | — | Void Imp | — | ON PLAY: Deal 300 damage to an enemy minion. |
| Void Imp Wizard | Abyss Order | abyss_core | 2E+1M | Minion — Demon 100/300 | — | Void Imp | — | ON PLAY: Deal 300 Void Bolt damage to enemy hero and apply 1 VOID MARK. |
| Grafted Fiend | Abyss Order | abyss_core | 3E | Minion — Demon 300/300 | — | Grafted Fiend | — | Vanilla stat-stick. Carries the `grafted_fiend` clan tag — a target for Seris Fleshcraft synergies even when included via the core pool. |
| Shadow Hound | Abyss Order | abyss_core | 2E | Minion — Demon 200/300 | — | — | — | ON PLAY: Gain +100 ATK for each other friendly Demon on board. |
| Abyssal Brute | Abyss Order | abyss_core | 4E | Minion — Demon 300/600 | GUARD | — | — | — |
| Void Stalker | Abyss Order | abyss_core | 3E | Minion — Demon 300/200 | SWIFT, LIFEDRAIN | — | — | — |
| Void Spawner | Abyss Order | abyss_core | 4E | Minion — Demon 200/600 | — | — | — | PASSIVE: Whenever a friendly minion dies, summon a 100/100 Void Spark. |
| Abyssal Tide | Abyss Order | abyss_core | 5E | Minion — Demon 400/400 | — | — | — | PASSIVE: Whenever a friendly minion dies, deal 200 damage to enemy hero. |
| Void Devourer | Abyss Order | abyss_core | 6E | Minion — Demon 200/600 | GUARD | — | — | ON PLAY: Sacrifice adjacent friendly minions. Gain +300 ATK and +300 HP per sacrificed minion. |
| Nyx'ael, Void Sovereign | Abyss Order | abyss_core | 5E | Minion — Demon 500/500 | CHAMPION | Void Imp | — | Auto-summon when 3 Void Imps are on board. PASSIVE: At the start of your turn, deal 200 damage to all enemy minions. |
| Abyss Cultist | Abyss Order | abyss_core | 1E | Minion — Human 100/300 | — | — | ON PLAY: Apply 1 CORRUPTION to a random enemy minion. |
| Void Netter | Abyss Order | abyss_core | 2E | Minion — Human 100/300 | — | — | ON PLAY: Deal 200 damage to an enemy minion. |
| Corruption Weaver | Abyss Order | abyss_core | 3E | Minion — Human 100/400 | — | — | ON PLAY: Apply 1 CORRUPTION to all enemy minions. |
| Soul Collector | Abyss Order | abyss_core | 5E | Minion — Human 300/700 | — | — | ON PLAY: Destroy a Corrupted enemy minion. |
| Dark Empowerment | Abyss Order | abyss_core | 1M | Spell | — | — | Give a friendly minion +150 ATK. If it is a Demon, also give +150 HP. |
| Abyssal Sacrifice | Abyss Order | abyss_core | 2M | Spell | — | — | Destroy a friendly minion. Draw 2 cards. |
| Abyssal Plague | Abyss Order | abyss_core | 2M | Spell | — | — | Apply 1 CORRUPTION to all enemy minions. Deal 100 damage to all enemy minions. |
| Void Summoning | Abyss Order | abyss_core | 2M | Spell | — | — | Summon a 300/300 Demon. If you control any Human, summon a 400/400 Demon instead. |
| Void Execution | Abyss Order | abyss_core | 3M | Spell | — | — | Deal 500 damage to an enemy minion or enemy hero. If you control any Human, deal 700 instead. |
| Void Bolt | Abyss Order | abyss_core | 2M | Spell | — | — | Deal 500 Void Bolt damage to enemy hero. With `piercing_void` talent: also applies 1 Void Mark. |
| Void Rune | Abyss Order | abyss_core | 2M | Rune | RUNE | — | At the start of your turn, deal 100 Void Bolt damage to the enemy hero. |
| Blood Rune | Abyss Order | abyss_core | 2M | Rune | RUNE | — | Whenever a friendly minion dies, heal your hero for 100 HP. |
| Dominion Rune | Abyss Order | abyss_core | 2M | Rune | RUNE | — | All friendly Demons have +100 ATK (board-wide aura). |
| Shadow Rune | Abyss Order | abyss_core | 2M | Rune | RUNE | — | Enemy minions enter the board with 1 stack of CORRUPTION. |
| Dark Covenant | Abyss Order | abyss_core | 2M | Environment | — | — | While any friendly Human is on board, all friendly Demons have +100 ATK. While any friendly Demon is on board, all friendly Humans have +100 HP. |
| Abyssal Summoning Circle | Abyss Order | abyss_core | 2M | Environment · Ritual | RITUAL | — | PASSIVE: Whenever a friendly Demon dies, deal 200 damage to enemy hero. RITUAL: Blood + Dominion → Demon Ascendant (deal 200 to 2 random enemies; summon 500/500 Demon). |

---

## 2. Abyss Order — Common Pool

*Unlocked as boss drop rewards for Lord Vael. Available from Act 1.*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Imp Recruiter | Abyss Order | vael_common | 2E | Minion — Human 200/300 | — | — | Common | ON PLAY: add a Void Imp to your hand. |
| Soul Taskmaster | Abyss Order | vael_common | 3E | Minion — Demon 250/400 | — | — | Rare | PASSIVE: Whenever a friendly Demon dies, this minion gains +50 ATK. |
| Void Amplifier | Abyss Order | vael_common | 4E | Minion — Human 250/350 | — | — | Epic | PASSIVE: Whenever you play a Demon, it enters with +100 ATK and +100 HP. |
| Blood Pact | Abyss Order | vael_common | 2M | Spell | — | — | Common | Sacrifice a friendly Human. Give all friendly Demons +200 ATK and +100 HP. |
| Soul Shatter | Abyss Order | vael_common | 3M | Spell | — | — | Rare | Sacrifice a friendly Demon. Deal 200 damage to all enemy minions. Deal 300 if the sacrifice had 300+ HP. |
| Soul Rune | Abyss Order | vael_common | 2M | Rune | RUNE | — | Epic | Whenever a friendly Demon dies during the enemy's turn, summon a 100/100 Spirit token. Triggers once per enemy turn. |

---

## 3. Abyss Order — Piercing Void Pool

*Requires `piercing_void` talent. Never appears without it.*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Abyssal Arcanist | Abyss Order | vael_piercing_void | 1E+2M | Minion — Human 200/300 | — | — | Common | ON PLAY: add a Void Bolt spell to your hand. |
| Void Archmagus | Abyss Order | vael_piercing_void | 5E+5M | Minion — Human 400/600 | — | — | Legendary | Your spells cost 1 less Mana. Whenever you cast a spell, add a Void Bolt to your hand. Deck limit: 1. |
| Mark the Target | Abyss Order | vael_piercing_void | 2M | Spell | — | — | Common | Apply 2 VOID MARKS to enemy hero. Draw a card. |
| Void Detonation | Abyss Order | vael_piercing_void | 4M | Spell | — | — | Rare | Deal 500 Void Bolt damage to enemy hero. Gain +50 damage per VOID MARK on enemy hero. |
| Abyss Ritual Circle | Abyss Order | vael_piercing_void | 2M | Environment · Ritual | RITUAL | — | Epic | PASSIVE: At start of each turn, deal 100 damage to a random minion. RITUAL: Void + Blood → Soul Cataclysm (deal 400 Void Bolt damage to enemy hero; heal your hero for 400 HP). |

---

## 4. Abyss Order — Endless Tide Pool

*Requires `imp_evolution` talent. Swarm / Void Imp synergy theme.*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Imp Martyr | Abyss Order | vael_endless_tide | 2E | Minion — Demon 100/100 | — | Void Imp | Common | ON DEATH: Give all friendly VOID IMP CLAN minions +100 ATK and +100 HP. |
| Imp Vessel | Abyss Order | vael_endless_tide | 3E | Minion — Demon 100/200 | — | Void Imp | Rare | ON DEATH: summon 2 Void Imps. |
| Imp Idol | Abyss Order | vael_endless_tide | 5E | Minion — Demon 300/600 | — | Void Imp | Epic | ON PLAY: Give all other friendly VOID IMP CLAN minions DEATHLESS. |
| Vael's Colossal Guard | Abyss Order | vael_endless_tide | 7E | Minion — Demon 300/300 | GUARD | Void Imp | Legendary | ON PLAY: Gain +300 ATK and +300 HP for each other VOID IMP CLAN minion on board. Give all other VOID IMP CLAN minions +100 ATK. Deck limit: 1. |
| Imp Frenzy | Abyss Order | vael_endless_tide | 1M | Spell | — | — | Common | Give a friendly Void Imp +300 ATK. |

---

## 5. Abyss Order — Rune Master Pool

*Requires `rune_caller` talent. Rune / ritual synergy theme.*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Rune Warden | Abyss Order | vael_rune_master | 3E | Minion — Human 200/400 | — | — | Rare | PASSIVE: Whenever you place a Rune, this minion gains +200 ATK this turn. |
| Rune Seeker | Abyss Order | vael_rune_master | 3E | Minion — Human 150/400 | — | — | Rare | ON PLAY: search your deck for a Rune and add it to your hand. |
| Runic Blast | Abyss Order | vael_rune_master | 2M | Spell | — | — | Common | Deal 200 damage to a random enemy minion. If you have 2+ active Runes, deal 200 to all enemy minions instead. |
| Runic Echo | Abyss Order | vael_rune_master | 2M | Spell | — | — | Rare | Add a copy of each Rune on the battlefield to your hand. |
| Echo Rune | Abyss Order | vael_rune_master | 2M | Rune | RUNE | — | Legendary | At the start of your turn, fire the effect of the last Rune you placed once. |

---

## 5b. Abyss Order — Seris Core Pool

*Visible in the deck builder only when Seris is the active hero. Each card is intentionally weak or conditional outside Seris's kit (Flesh, Demons, sacrifice).*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Void Spawning | Abyss Order | seris_core | 1M | Spell | — | — | Common | Summon two 100/100 Void Demons. |
| Fiendish Pact | Abyss Order | seris_core | 1M | Spell | — | — | Common | Draw a card. Your next Demon costs 2 less this turn. |
| Grafted Butcher | Abyss Order | seris_core | 2E | Minion — Demon 200/100 | — | — | Common | ON PLAY: SACRIFICE another friendly minion. Deal 200 damage to all enemy minions. |
| Flesh Rend | Abyss Order | seris_core | 2M | Spell | — | — | Common | Deal 300 damage to a minion or enemy hero. If you have 3+ Flesh, deal 600 instead. |

**Notes:**
- Fiendish Pact arms a single-use 2-Mana discount on `_fiendish_pact_pending`. The discount applies only to the **next** Demon played this turn — it is consumed when the first Demon resolves, so subsequent Demons pay full cost. `cost_delta = -2` is set on all Demons in hand as a display hint and is cleared when the discount is consumed or at turn start. Player-only (enemy Seris not supported).
- Grafted Butcher fizzles (no AoE) if no friendly sacrifice target exists. The card can still be played, but the ON PLAY does nothing in that case.
- Flesh Rend's 3+ Flesh threshold uses the new `flesh_gte_3` declarative condition (ConditionResolver.gd).

---

## 5c. Abyss Order — Seris Common Support Pool

*Unlocked as combat rewards and shop offerings when Seris is the active hero. Branch-neutral — every card is useful across all three talent branches (Fleshcraft, Demon Forge, Corruption Engine).*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Flesh Harvester | Abyss Order | seris_common | 2E | Minion — Demon 200/300 | — | — | Common | ON PLAY: Gain 1 Flesh. |
| Ravenous Fiend | Abyss Order | seris_common | 3E | Minion — Demon 400/300 | — | — | Common | ON DEATH: Gain 2 Flesh. |
| Feast of Flesh | Abyss Order | seris_common | 1M | Spell | — | — | Common | Sacrifice a friendly Demon. Gain 2 Flesh. Draw a card. |
| Mend the Flesh | Abyss Order | seris_common | 1M | Spell | — | — | Common | Heal all friendly minions for 200 HP. Spend 1 Flesh: heal 350 HP instead. |
| Flesh Eruption | Abyss Order | seris_common | 3M | Spell | — | — | Common | Deal 250 damage to all enemies. Spend 2 Flesh: deal 400 damage instead. |
| Gorged Fiend | Abyss Order | seris_common | 3E | Minion — Demon 300/300 | — | — | Rare | ON PLAY: Spend up to 3 Flesh. Gain +150 ATK and +150 HP per Flesh spent. |
| Flesh-Stitched Horror | Abyss Order | seris_common | 4E | Minion — Demon 400/400 | — | — | Rare | ON PLAY: Spend 2 Flesh: gain GUARD and +300 HP. |
| Flesh Rune | Abyss Order | seris_common | 2M | Rune | RUNE | — | Epic | At the start of your turn, spend 2 Flesh: summon a 300/300 Void Spark. If you do not have enough Flesh, destroy this Rune. |

**Flesh-spend semantics (applies to all cards in this pool):**
- Flesh spending is **automatic and optional** — the card checks current Flesh when it resolves; the player is never prompted.
- **"Spend N Flesh"** is all-or-nothing. If current Flesh ≥ N, exactly N is spent and the gated effect triggers. Otherwise zero is spent and the gated effect does not trigger.
- **"Spend up to N Flesh"** is partial. Spends `min(current Flesh, N)` and the effect scales with however much was spent (including 0).

**Notes:**
- "All enemies" on Flesh Eruption includes both enemy minions and the enemy hero.
- Flesh Rune summons a stat-overridden 300/300 Void Spark (base token is 100/100, like how Void Summoning overrides Void Demon stats at summon time).
- Flesh Rune self-destructs at start of turn if the 2-Flesh upkeep cannot be paid.

---

## 5d. Abyss Order — Seris Fleshcraft Pool

*Branch 1 support pool. Unlocked as combat rewards and shop offerings once Seris takes the `flesh_infusion` talent (Fleshcraft T0). Theme: Grafted Fiend clan synergy, kill-stack growth, long-term investment protection.*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Grafted Reaver | Abyss Order | seris_fleshcraft | 2E | Minion — Demon 200/300 | — | Grafted Fiend | Common | ON PLAY: Gain +100 ATK for each other friendly Grafted Fiend. |
| Flesh Scout | Abyss Order | seris_fleshcraft | 1E | Minion — Demon 100/200 | — | Grafted Fiend | Common | ON PLAY: If friendly Grafted Fiends have 3 or more total kill stacks, draw 2 cards. |
| Flesh Surgeon | Abyss Order | seris_fleshcraft | 2E | Minion — Human 100/300 | — | — | Common | ON PLAY: Heal a friendly Grafted Fiend to full. Spend 1 Flesh: also give it +200 HP permanently. |
| Flesh Sacrament | Abyss Order | seris_fleshcraft | 2M | Spell | — | — | Rare | Give a friendly Grafted Fiend 1 kill stack. Spend 2 Flesh: give it 3 kill stacks instead. |
| Matron of Flesh | Abyss Order | seris_fleshcraft | 5E | Minion — Demon 400/600 | — | Grafted Fiend | Epic | ON PLAY: Gain +100 ATK and +100 HP for each other friendly Grafted Fiend. Whenever this minion kills an enemy minion, gain 1 Flesh. |

**Notes:**
- Kill stacks granted by Flesh Sacrament route through `CombatScene._add_kill_stacks` — the same entry point used by organic kills. Taking `flesh_infusion` converts every granted stack into +100/+100 permanent (so 3 stacks → +300/+300). Taking `predatory_surge` grants Siphon as soon as the target reaches 3 kill stacks from any source.
- Matron of Flesh's on-kill Flesh gain uses the new declarative `on_kill_effect_steps` field on MinionCardData — fired by a shared ON_*_MINION_DIED handler that inspects the attacker. Reusable for any future "when this minion kills" card.
- Flesh Surgeon applies the +200 max-HP buff before healing to full, so a 300/300 target with 100 HP heals to 500/500 when Flesh is paid.

---

## 5e. Abyss Order — Seris Demon Forge Pool

*Branch 2 support pool. Unlocked as combat rewards and shop offerings once Seris takes the `soul_forge` talent (Demon Forge T0). Theme: sacrifice Demons to feed the Forge Counter; ON LEAVE-driven payoffs.*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Altar Thrall | Abyss Order | seris_demon_forge | 2E | Minion — Demon 300/300 | SWIFT | — | Common | SWIFT. At the end of your turn, sacrifice this minion. |
| Forge Acolyte | Abyss Order | seris_demon_forge | 3E | Minion — Human 100/400 | — | — | Common | PASSIVE: Whenever you sacrifice a Demon, gain 1 Flesh. |
| Ember Pact | Abyss Order | seris_demon_forge | 1M | Spell | — | — | Common | Sacrifice a friendly Demon. Gain 1 Flesh. Add +1 Forge Counter. |
| Soul Shatter | Abyss Order | vael_common (dual) | 3M | Spell | — | — | Rare | *Dual-pool: also offered to Demon Forge decks.* Sacrifice a friendly Demon. Deal 200 damage to all enemy minions. Deal 300 if the sacrifice had 300+ HP. |
| Bound Offering | Abyss Order | seris_demon_forge | 2E | Minion — Demon 200/200 | — | — | Rare | ON LEAVE: Summon two 100/100 Void Demons. |
| Forgeborn Tyrant | Abyss Order | seris_demon_forge | 6E | Minion — Demon 500/500 | — | — | Epic | ON DEATH and ON LEAVE: Add +3 Forge Counter. |

**Notes:**
- **Strict sacrifice rule**: sacrifice is NOT death. Sacrificed minions fire ON LEAVE (`on_leave_effect_steps`) and ON_*_MINION_SACRIFICED, but NOT ON DEATH. Cards that need to react to sacrifice must use ON LEAVE or listen on the sacrifice event.
- **Migrated to listen on both events**: Fleshbind (gain Flesh on Demon death OR sacrifice), Blood Rune (heal on friendly death OR sacrifice), Soul Rune (Spirit token on Demon death OR sacrifice during enemy turn).
- **Death-only (deliberately)**: Ravenous Fiend, Void Spawner, Abyssal Tide, Soul Taskmaster, Imp Martyr, Imp Vessel — their on-death effects do NOT fire when sacrificed.
- Forgeborn Tyrant is the one card with both triggers populated. They never double-fire on a single removal — sacrifice runs only ON LEAVE, combat death runs only ON DEATH. Either path adds +3 to Forge Counter (looped through `_gain_forge_counter` so threshold-overflow auto-summons multiple Forged Demons).
- Altar Thrall's end-of-turn sacrifice uses the new declarative `on_turn_end_effect_steps` field on MinionCardData (mirror of `on_turn_start_effect_steps`).
- Ember Pact and Forgeborn Tyrant use the new `GAIN_FORGE_COUNTER` EffectStep, which routes through `_gain_forge_counter` and is gated by the `soul_forge` talent. Without Soul Forge, the step is a no-op — but the pool itself is gated on Soul Forge so this only matters for off-pool cases (e.g. theoretical future enemy use).

---

## 5f. Abyss Order — Seris Corruption Engine Pool

*Branch 3 support pool. Unlocked as combat rewards and shop offerings once Seris takes the `corrupt_flesh` talent (Corruption Engine T0). Theme: stack Corruption on friendly Demons as an ATK buff (post-T0), detonate stacks for AoE pressure (T1), feed spell-damage scaling (T2), and replay spell turns (T3).*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Bloodscribe Imp | Abyss Order | seris_corruption | 1E | Minion — Demon 100/100 | — | — | Common | ON PLAY: Add a Flesh Rend to your hand. |
| Tainted Ritualist | Abyss Order | seris_corruption | 2E | Minion — Human 100/300 | — | — | Common | ON PLAY: Apply 1 Corruption to a friendly Demon. Spend 1 Flesh: apply 2 instead. |
| Festering Fiend | Abyss Order | seris_corruption | 3E | Minion — Demon 300/400 | — | — | Common | ON PLAY: Apply 2 Corruption to itself. ON DEATH: Apply 1 Corruption to a random friendly Demon. |
| Self-Mutilation | Abyss Order | seris_corruption | 1M | Spell | — | — | Common | Apply 2 Corruption to a friendly Demon. Draw a card. |
| Font of the Depths | Abyss Order | vael_piercing_void (dual) | 1M | Spell | — | — | Common | *Dual-pool: also offered to Corruption Engine decks.* Gain +1 maximum Mana. Draw a card. |
| Resonant Outburst | Abyss Order | seris_corruption | 2M | Spell | — | — | Rare | Deal 100 damage to all enemies. Spend 2 Flesh: deal 300 instead. |
| Voidshaped Acolyte | Abyss Order | seris_corruption | 3E | Minion — Demon 300/300 | — | — | Rare | ON PLAY: Place a Shadow Rune on the enemy's battlefield. |
| Recursive Hex | Abyss Order | seris_corruption | 5M | Spell | — | — | Epic | Copy each spell you cast last turn (excluding Recursive Hex) into your hand. Deal 200 damage to enemy hero per spell copied. |

**Notes:**
- **Bloodscribe Imp** tutors the Seris Core Pool spell Flesh Rend directly into hand — an Imp-side cheap enabler that puts Corruption-Engine decks on a faster spell-density curve. The added Flesh Rend instance is a fresh copy (new instance_id), not a graveyard recall.
- **Tainted Ritualist / Self-Mutilation / Festering Fiend** all apply Corruption to *friendly* Demons. Outside this pool the engine has no friendly-side stacking source, so these are the engine fuel. They remain functional pre-T0 (Corruption is a −100 ATK debuff on the friendly), but only become net-positive once `corrupt_flesh` flips the sign to +100 ATK / stack — pool gating on T0 enforces this.
- **Festering Fiend** self-corrupts on play (2 stacks), so post-T0 it enters as effectively 500/400. Its ON DEATH targets a random friendly Demon (not itself, since it's already gone), keeping the engine running off-board.
- **Resonant Outburst** "all enemies" includes both enemy minions and the enemy hero, matching Flesh Eruption's wording. T2 Void Amplification adds +50 damage per total friendly Corruption stack — at 6 stacks across the board (e.g. 2 corrupted Demons at 3 stacks each), the Spend-2-Flesh mode hits for 300 + 300 = 600 to all enemies.
- **Voidshaped Acolyte** summons a Shadow Rune *on the enemy's side* of the battlefield. Read from the enemy's perspective: "*your* (= our friendly) minions enter with 1 stack of Corruption." With `corrupt_flesh` this becomes a board-wide friendly-Demon entry buff worth +100 ATK per summon. The Rune is enemy-controlled, so player-side Cyclone / Hurricane targets it normally.
- **Recursive Hex** reads from the new spell graveyard system (see Spell Graveyard Notes below). Copies enter the caster's hand at *base cost* — Fiendish Pact discounts and similar single-use cost mods do not persist on the copy. Copies are fresh card instances with new instance_ids, not graveyard recalls — the original entries remain in the graveyard. If the caster's hand is full, excess copies burn silently. Damage is paid first, then copies are added (so a full-hand cast still does the face damage). Self-copies are filtered out by `card_id == "recursive_hex"` even if multiple instances of Recursive Hex were cast last turn.
- **Recursive Hex × T3 Void Resonance**: T3 doubles a single cast (one entry in graveyard, doubled effect). When Recursive Hex itself is doubled by T3, the copy phase runs once on a 2× damage payload — net result is the same hand-copy set, with 400 damage per copied spell to enemy hero.
- **Pool composition**: 4 Common / 2 Rare / 1 Epic / 1 dual-pool Common — matches the established mix density of Branches 1 and 2.

**Spell Graveyard Notes (new system, used by Recursive Hex):**

A unified per-side graveyard is added to track resolved cards across the full combat. Tracks all card types (minions, spells, runes, traps, environments) but Recursive Hex filters to spells only.

- Storage: `CombatScene._player_graveyard: Array[CardInstance]` and `CombatScene._enemy_graveyard: Array[CardInstance]`, mirrored as `SimState._player_graveyard` / `_enemy_graveyard`.
- Each `CardInstance` in the graveyard carries an added `resolved_on_turn: int` field, set at the moment the card resolves (after effects fully apply, including ON PLAY).
- Append point: a card is added to the caster-side graveyard when it finishes resolving. Minions go to the graveyard when they leave the board (death OR sacrifice OR removal — same trigger as `_on_minion_left`). Runes/Environments go to the graveyard when destroyed or replaced.
- Graveyard is **not cleared mid-combat** (it is a full-combat record) and is cleared at combat end alongside other per-combat state.
- Recursive Hex query: `caster_graveyard.filter(e => e.card_data.card_type == CARD_TYPE_SPELL && e.resolved_on_turn == current_turn - 1 && e.card_data.id != "recursive_hex")`.
- Sim parity required: SimState must wire identical graveyard tracking and the same append points in SimPlayerAgent / SimEnemyAgent.

---

## 6. Neutral — Core

*Available to all heroes. No faction synergy.*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Roadside Drifter | Neutral | neutral_core | 1E | Minion — Human 100/300 | — | — | — | — |
| Ashland Forager | Neutral | neutral_core | 1E | Minion — Beast 200/200 | — | — | — | — |
| Freelance Sellsword | Neutral | neutral_core | 2E | Minion — Mercenary 300/200 | — | — | — | — |
| Traveling Merchant | Neutral | neutral_core | 2E | Minion — Human 100/100 | — | — | — | ON PLAY: draw a card. |
| Trapbreaker Rogue | Neutral | neutral_core | 2E | Minion — Human 250/200 | — | — | — | ON PLAY: destroy a random enemy trap. |
| Caravan Guard | Neutral | neutral_core | 3E | Minion — Mercenary 350/350 | — | — | — | — |
| Arena Challenger | Neutral | neutral_core | 3E | Minion — Mercenary 450/200 | — | — | — | — |
| Spell Taxer | Neutral | neutral_core | 3E | Minion — Human 250/300 | — | — | — | ON PLAY: enemy spells cost +1 Mana next turn. |
| Saboteur Adept | Neutral | neutral_core | 3E | Minion — Human 300/300 | — | — | — | ON PLAY: enemy traps cannot trigger this turn. |
| Aether Bulwark | Neutral | neutral_core | 3E+2M | Minion — Construct 300/400 · Shield 300 | SHIELD_REGEN_1 | — | — | Regenerates 100 Shield at the start of your turn. |
| Bulwark Automaton | Neutral | neutral_core | 4E | Minion — Construct 300/500 | Deathless | — | — | — |
| Wandering Warden | Neutral | neutral_core | 4E+1M | Minion — Mercenary 300/400 · Shield 300 | SHIELD_REGEN_1 | — | — | Regenerates 100 Shield at the start of your turn. |
| Ruins Archivist | Neutral | neutral_core | 5E | Minion — Mercenary 450/500 | — | — | — | ON PLAY: draw a card. |
| Wildland Behemoth | Neutral | neutral_core | 6E | Minion — Beast 700/600 | — | — | — | — |
| Stone Sentinel | Neutral | neutral_core | 7E | Minion — Mercenary 900/600 | — | — | — | — |
| Rift Leviathan | Neutral | neutral_core | 8E | Minion — Beast 1000/700 | — | — | — | — |
| Energy Conversion | Neutral | neutral_core | 0M | Spell | — | — | — | Convert up to 3 remaining Essence into Mana. |
| Flux Siphon | Neutral | neutral_core | 0M | Spell | — | — | — | Convert up to 3 remaining Mana into Essence. |
| Arcane Strike | Neutral | neutral_core | 1M | Spell | — | — | — | Deal 300 damage to a minion. |
| Purge | Neutral | neutral_core | 1M | Spell | — | — | — | Remove all buffs and debuffs from a minion. |
| Cyclone | Neutral | neutral_core | 1M | Spell | — | — | — | Destroy an active Trap/Rune or the active Environment. |
| Tactical Planning | Neutral | neutral_core | 1M | Spell | — | — | — | Draw a card. |
| Precision Strike | Neutral | neutral_core | 3M | Spell | — | — | — | Deal 600 damage to a minion. |
| Hurricane | Neutral | neutral_core | 3M | Spell | — | — | — | Destroy all active Traps/Runes and the active Environment (including your own). |
| Hidden Ambush | Neutral | neutral_core | 1M | Trap | — | — | — | When an enemy minion attacks: deal 400 damage to that attacker. |
| Smoke Veil | Neutral | neutral_core | 2M | Trap | — | — | — | When an enemy minion attacks: cancel that attack and exhaust all enemy minions. |
| Silence Trap | Neutral | neutral_core | 2M | Trap | — | — | — | When the enemy casts a spell: cancel that spell. |
| Death Trap | Neutral | neutral_core | 2M | Trap | — | — | — | When the enemy summons a minion: destroy that minion immediately. |

---

## 7. Feral Imp Clan — Act 1 Enemy Cards

*Enemy-only pool (`feral_imp_clan`). Not visible to players. Used by Act 1 Imp Lair encounters.*
*Clan: **Feral Imp** · Tag: `feral_imp` · Faction: `abyss_order` (uses Abyss Order card frame)*

| Name | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|
| Rabid Imp | feral_imp_clan | 1E | Minion — Demon 200/100 | SWIFT | Feral Imp | — | SWIFT. |
| Brood Imp | feral_imp_clan | 2E | Minion — Demon 100/300 | — | Feral Imp | — | ON DEATH: Summon two 100/100 Void Sparks. |
| Imp Brawler | feral_imp_clan | 2E | Minion — Demon 300/250 | — | Feral Imp | — | — |
| Void-Touched Imp | feral_imp_clan | 2E | Minion — Demon 200/300 | — | Feral Imp | — | ON DEATH: Deal 100 damage to all enemy minions. |
| Frenzied Imp | feral_imp_clan | 3E | Minion — Demon 300/300 | — | Feral Imp | — | ON PLAY: Deal 100 damage to a random enemy minion, plus 100 more for each other Feral Imp on your board. |
| Matriarch's Broodling | feral_imp_clan | 4E | Minion — Demon 200/500 | GUARD | Feral Imp | — | GUARD. ON DEATH: Summon a Brood Imp. |
| Rogue Imp Elder | feral_imp_clan | 4E | Minion — Demon 300/500 | — | Feral Imp | — | AURA: All friendly FERAL IMP minions have +100 ATK. |
| Feral Surge | feral_imp_clan | 1M | Spell | — | Feral Imp | — | Give a friendly Feral Imp minion +300 ATK. |
| Void Screech | feral_imp_clan | 1M | Spell | — | Feral Imp | — | Deal 250 damage to enemy hero. If you have 3+ Feral Imp minions on board, deal 350 instead. |
| Brood Call | feral_imp_clan | 2M | Spell | — | Feral Imp | — | Summon a random Feral Imp minion. |
| Pack Frenzy | feral_imp_clan | 3M | Spell | — | Feral Imp | — | All friendly Feral Imp minions gain +250 ATK and SWIFT this turn. |

---

## 8. Abyss Cultist Clan — Act 2 Enemy Cards

*Enemy-only pool (`abyss_cultist_clan`). Not visible to players. Used by Act 2 Abyss Dungeon encounters.*
*Faction: `abyss_order` (uses Abyss Order card frame)*

| Name | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|
| Cult Fanatic | abyss_cultist_clan | 2E | Minion — Human 300/300 | — | — | — | — |
| Dark Command | abyss_cultist_clan | 1M | Spell | — | — | — | Give all friendly Human minions +100 ATK and +100 HP. |

---

## 9. Void Rift World — Act 3 Enemy Cards

*Enemy-only pool (`void_rift`). Not visible to players. Used by Act 3 Void Rift encounters.*
*Faction: `abyss_order` (uses Abyss Order card frame)*
*All cards have a dual cost: normal mana/essence + Void Spark cost. To play, the enemy must pay both.*

### Spark-cost cards (essence/mana + void spark fuel)

| Name | Pool | Cost | Spark Cost | Effect | Keywords | Description |
|---|---|---|---|---|---|---|
| Void Pulse | void_rift | 1M | 1 | Spell | — | Draw 3 cards. |
| Phase Stalker | void_rift | 2E | 1 | Minion — Spirit 400/300 | Swift | — |
| Rift Collapse | void_rift | 1M | 1 | Spell | — | Deal 200 damage to all enemy minions. |
| Rift Warden | void_rift | 4E | 1 | Minion — Spirit 350/400 | Guard, Ethereal | AURA: Damage prevented by Ethereal is dealt to enemy hero. |
| Void Behemoth | void_rift | 3E | 2 | Minion — Spirit 400/600 | Guard | — |
| Dimensional Breach | void_rift | 1M | 2 | Spell | — | Summon 3 Void Sparks. |
| Void Rift Lord | void_rift | 4E | 3 | Minion — Spirit 400/600 | — | ON PLAY: Set enemy Mana to 0 next turn. |

### Non-spark cards (mana/essence only)

| Name | Pool | Cost | Effect | Keywords | Description |
|---|---|---|---|---|---|
| Void Lance | void_rift | 2M | Spell | — | Deal 600 damage to a minion. |
| Void Shatter | void_rift | 3M | Spell | — | Deal 100 damage to a random enemy minion 8 times. |
| Spirit Surge | void_rift | 2M | Spell | — | Draw a Spark Cost card from your deck. Summon a 100/100 Void Spark. |
| Void Wind | void_rift | 1M | Spell | — | Destroy a random enemy trap. Heal your hero for 500 HP. |
| Void Resonance | void_rift | 1E | Minion — Spirit 100/100 | Ethereal | ON PLAY: Heal your hero for 300 HP. |
| Void Echo | void_rift | 2E | Minion — Spirit 200/150 | Swift, Ethereal | ON PLAY: Draw 1 card. |
| Rift Tender | void_rift | 2E | Minion — Spirit 150/250 | — | ON PLAY: Summon a 100/100 Void Spark. |
| Hollow Sentinel | void_rift | 4E | Minion — Spirit 300/500 | Ethereal | AURA: At the end of your turn, give all friendly Void Sparks +100 ATK. |
| Phase Disruptor | void_rift | 3E | Minion — Spirit 300/250 | Ethereal | ON PLAY: Counter the next spell the enemy casts. |
| Void Architect | void_rift | 4E | Minion — Spirit 250/400 | — | ON PLAY: Increase max Mana by 1. |
| Riftscarred Colossus | void_rift | 4E | Minion — Spirit 500/300 | Swift | ON PLAY: Summon a 100/100 Void Spark. |
| Ethereal Titan | void_rift | 5E | Minion — Spirit 600/400 | Swift, Ethereal, Pierce | — |

---

## 9b. Void Castle — Act 4 Enemy Cards

*Enemy-only pool (`void_castle`). Not visible to players. Used by Act 4 Void Castle encounters (F10–F15).*
*Faction: `abyss_order` (uses Abyss Order card frame)*

### Spirit fuel minions (consumed as spark fuel)

| Name | Pool | Cost | Effect | Spark Value | Keywords | Description |
|---|---|---|---|---|---|---|
| Void Wisp | void_castle | 1E | Minion — Spirit 150/200 | 1 | — | — |
| Void Shade | void_castle | 2E | Minion — Spirit 250/250 | 2 | — | — |
| Void Wraith | void_castle | 3E | Minion — Spirit 300/400 | 3 | — | — |
| Void Revenant | void_castle | 5E | Minion — Spirit 500/500 | 4 | — | — |

### Non-spark minions & spells

| Name | Pool | Cost | Effect | Keywords | Description |
|---|---|---|---|---|---|
| Sovereign's Herald | void_castle | 2E | Minion — Spirit 200/200 | — | ON PLAY: Give a friendly minion +1 Critical Strike. |
| Sovereign's Edict | void_castle | 3M | Spell | — | Give all friendly minions 'ON DEATH: Summon a Void Spark.' |

### Spark-cost cards

| Name | Pool | Cost | Spark Cost | Effect | Keywords | Description |
|---|---|---|---|---|---|---|
| Sovereign's Decree | void_castle | 2M | 2 | Spell | — | Deal 300 damage to enemy hero. Apply 2 Corruption to all enemy minions. |
| Throne's Command | void_castle | 1M | 2 | Spell | — | Give all friendly minions +1 Critical Strike. |
| Bastion Colossus | void_castle | 4E | 4 | Minion — Spirit 600/800 | Guard, Ethereal | ON PLAY: Gain 2 stacks of Critical Strike. |

---

## 10. Tokens & Special Summons

*Not in any deck. Registered in CardDatabase and summoned by card effects or passives.*

| Name | Faction | Pool | Cost | Effect | Keywords | Clan | Rarity | Description |
|---|---|---|---|---|---|---|---|---|
| Void Spark | Abyss Order | — | 0 | Minion — Spirit 100/100 | — | — | — | Summoned by Void Spawner passive and Brood Imp on-death. Reused by Soul Rune with stat scaling (×Runic Attunement multiplier). Soul Anchor relic also summons a stat-overridden 300/300 Void Spark with GRANT_GUARD applied at summon time. |
| Void Demon | Abyss Order | — | 0 | Minion — Demon 200/200 | — | — | — | Base token stats are 200/200. Stats are always overridden at summon time: Void Summoning summons it at 300/300 (or 400/400 with a Human on board); Demon Ascendant ritual Special Summons it at 500/500 (no on-play effects). |
| Lesser Demon | Abyss Order | — | 0 | Minion — Demon 400/400 | — | — | — | Summoned by Seris's Fiend Offering (Demon Forge T1). Tags: `lesser_demon`, `demon`. |
| Forged Demon | Abyss Order | — | 0 | Minion — Demon 500/500 | — | — | — | Forged by Seris's Soul Forge (Demon Forge T0). Auras (Void Growth / Void Pulse / Flesh Bond) granted at summon time via Abyssal Forge T3 capstone. Tags: `forged_demon`, `demon`. |

> **Notes:**
> - **Void Imp** is not a separate token — summon effects reuse the regular `void_imp` card entry directly.
> - Void Spark, Void Demon, Lesser Demon, and Forged Demon are registered in `_TOKEN_DEFS` in CardDatabase.gd (compact dictionary format).
> - **Guardian Spirit** (previously listed here) is no longer a registered token. Soul Anchor now summons a stat-overridden Void Spark with GRANT_GUARD instead.

---

## 11. Enemy Champion Cards

*Not in any deck. Auto-summoned by passive handlers when fight-specific conditions are met. Named after the encounter. Killing a champion deals **20% of enemy hero max HP** as damage to enemy hero.*

### Act 1 Champions
| Name | Stats | Keywords | Summon Condition | Effect |
|---|---|---|---|---|
| Rogue Imp Pack | 300 ATK / 400 HP | CHAMPION, SWIFT | 4 different Rabid Imps have attacked | AURA: All friendly FERAL IMP minions have +100 ATK |
| Corrupted Broodlings | 200 ATK / 400 HP | CHAMPION | 3 friendly minions have died | On Death: summon a Void-Touched Imp |
| Imp Matriarch | 300 ATK / 500 HP | CHAMPION, GUARD | 2nd Pack Frenzy cast | AURA: Pack Frenzy also gives all FERAL IMP minions +200 HP |

### Act 2 Champions
| Name | Stats | Keywords | Summon Condition | Effect |
|---|---|---|---|---|
| Abyss Cultist Patrol | 300 ATK / 300 HP | CHAMPION | 5 corruption stacks consumed | AURA: Corruption applied to enemy minions instantly detonates (100 damage per stack) |
| Void Ritualist | 200 ATK / 300 HP | CHAMPION | First ritual sacrifice triggers | AURA: Rune placement costs 1 less Mana |
| Corrupted Handler | 300 ATK / 300 HP | CHAMPION | 3 void sparks created | AURA: Whenever a Void Spark is summoned, deal 200 damage to enemy hero and heal your hero for 200 HP |

### Act 3 Champions
| Name | Stats | Keywords | Summon Condition | Effect |
|---|---|---|---|---|
| Rift Stalker | 400 ATK / 400 HP | CHAMPION | Void Sparks deal 1500+ total damage | AURA: All friendly Void Sparks have Immune |
| Void Aberration | 300 ATK / 300 HP | CHAMPION, ETHEREAL | 5 sparks consumed as costs | AURA: Void Detonation deals 200 damage instead of 100 |
| Void Herald | 200 ATK / 500 HP | CHAMPION | 6 spark-cost cards played | AURA: All spark costs become 0. Void Rift stops generating sparks |

### Act 4 Champions
| Name | Stats | Keywords | Summon Condition | Effect |
|---|---|---|---|---|
| Void Scout | 400 ATK / 500 HP | CHAMPION | 5 crits consumed | AURA: At end of enemy turn, all friendly crit minions gain +200 ATK |
| Void Warband | 500 ATK / 600 HP | CHAMPION | 2 Spirits consumed as fuel | On summon: gains 1 Critical Strike. AURA: When a friendly Spirit dies, apply 1 Critical Strike to a random friendly minion |
| Void Captain | 300 ATK / 600 HP | CHAMPION | 2 Throne's Command cast | On summon: gains 2 Critical Strike. AURA: When a friendly minion consumes a Critical Strike, deal 100 damage to each of 2 random enemies (minions or hero) |
| Void Champion | 500 ATK / 600 HP | CHAMPION | 3 enemy minions killed by Critical Strike | On summon: gains 3 Critical Strike. AURA: At end of enemy turn, gain +1 max Mana and +1 max Essence |
| Void Ritualist Prime | 100 ATK / 500 HP | CHAMPION | 5 enemy spells cast | On summon: gains 2 Critical Strike. AURA: Friendly spells cost 1 less Mana |
