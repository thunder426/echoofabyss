# Echo of Abyss — Free Cities Faction Design Document

**Version:** 0.2 (pre-alpha)
**Last updated:** 2026-04-24
**Status:** Design phase

-----

## 1. Faction Overview

**Name:** Free Cities
**Race Composition:** Humans · Beasts · Mercenaries
**Alignment:** Independent — no allegiance to Abyss, Void, or Astral forces

-----

## 2. Theme

Commerce, survival, and strength-for-hire.

The Free Cities are a loose confederation of independent city-states that refused to bow to any major cosmic power. Where the Abyss Order experiments with demon magic and the Kingdom of Solmara enforces rigid law, the Free Cities operate on a simpler principle: everything has a price.

Their culture produces:

- Gladiator arenas and fighting pits
- Mercenary guilds and bounty networks
- Trade caravans and smuggling operations
- Wandering beast tamers and wilderness scouts

The Void invasion is not their war — but war is good for business.

-----

## 3. Background

The Free Cities emerged from the collapse of an older human empire that tried and failed to harness abyssal energy. Rather than rebuild under a central authority, the surviving city-states chose independence.

Each city specializes in something:

- **Ironhaven** — mercenary guilds, gladiator tournaments
- **Duskport** — trade, smuggling, black market relics
- **Crestholm** — contracts, law enforcement, bounty hunting

When the Void invasion began, the Free Cities did not mobilize armies. Instead they opened their gates to refugees, hired out soldiers to whoever paid most, and quietly positioned themselves to profit from the chaos.

-----

## 4. Gameplay Identity

The Free Cities play differently from every other faction. They do not empower through death (Abyss Order), through cosmic forces (Astral Conclave), or through ancient power (Titanblood). They empower through **endurance, commerce, and calculated risk**.

### Core Philosophy

- **Survival rewards** — units that stay alive generate value over time
- **Economic pressure** — drain enemy resources and restrict enemy actions
- **Calculated volatility** — high-risk contracts with asymmetric payoffs
- **Board control through obligation** — Contracts force enemy decision-making

### Faction Signature Mechanics

|Mechanic   |Category        |Summary                                                            |
|-----------|----------------|-------------------------------------------------------------------|
|Cargo      |Survival reward |Units that survive X turns trigger a delivery effect once          |
|Bounty     |Kill reward     |Mark an enemy; reward triggers if prey dies while issuer lives     |
|Contract   |Persistent trap |Face-up trap with ongoing pressure and a one-time violation penalty|
|Hire       |Upkeep unit     |Units with recurring Gold cost; removed (not killed) if unpaid     |
|Bleeding   |Damage over time|Stacking debuff dealing damage each turn                           |
|Dual Strike|Attack modifier |Unit may attack twice per turn                                     |

-----

## 5. Faction Resource

Free Cities heroes use **Gold** — a unified single resource replacing the Abyss Order’s dual Essence / Mana system.

|Property       |Value                                                      |
|---------------|-----------------------------------------------------------|
|Resource name  |Gold                                                       |
|Starting amount|1                                                          |
|Maximum cap    |10                                                         |
|Growth         |+1 per end of turn                                         |
|Function       |Pays for all card types (Minions, Spells, Traps, Contracts)|

Neutral cards played by Free Cities heroes have their Essence and Mana costs converted to Gold using a simple sum rule (Essence cost + Mana cost = Gold cost).

-----

## 6. Signature Mechanics — Full Rules

-----

### 6.1 Cargo X

**Category:** Keyword — Minion

**Keyword text:** *Cargo X — at the start of your turn, add 1 counter to this minion. When it reaches X counters, trigger the delivery effect once.*

**Rules:**

- Counter is added at the start of the owner’s turn, during the same phase as rune auras and environment passives
- Delivery triggers immediately when the Xth counter is added — same turn start phase
- Delivery is a one-time effect — counters are not removed after delivery; the keyword is simply consumed
- If the minion dies before delivery, the effect is lost with no partial reward
- Cargo does not interact with death triggers — a minion dying with pending counters does not trigger delivery
- Cargo X value appears on the card as part of the keyword badge (e.g. Cargo 2, Cargo 3)

**Design intent:** Cargo rewards patient board presence. Keeping a Cargo unit alive long enough to deliver is a meaningful goal that creates tension — the owner protects the unit, the enemy prioritizes removing it. Higher X values allow stronger delivery effects since they require more investment to reach.

**Natural pairing:** Cargo units often also have an on-death effect. This creates a two-sided dilemma for the enemy — kill it to deny the delivery but trigger the death effect, or ignore it and face the delivery reward. Neither option is clearly correct.

-----

### 6.2 Bounty

**Category:** Named effect — Minion on-play

**Effect text:** *ON PLAY: mark a target enemy minion. If that enemy dies while this minion is still alive, trigger the bounty reward once.*

**Rules:**

- Bounty is issued on play — the owner selects a target enemy minion
- The reward only triggers if BOTH conditions are true simultaneously at the moment the marked enemy dies:
  - The marked enemy is dead
  - The Bounty-issuing minion is still alive on the board
- If the Bounty issuer dies before the marked enemy, the Bounty is cancelled permanently
- If the marked enemy dies after the issuer, Bounty is already cancelled — no reward
- Bounty is a one-time effect — once the reward triggers, it does not reapply
- Bounty cannot be issued on the enemy hero — only enemy minions
- If the marked enemy leaves the board without dying (future removal effects), Bounty is cancelled

**Design intent:** Bounty creates a two-unit protection puzzle. The owner must keep the issuer alive long enough for the target to die. The enemy must choose: kill the issuer to cancel the Bounty, or kill something else and risk the reward. Both players have agency in the outcome.

-----

### 6.3 Contract

**Category:** Card type — Persistent Trap subtype (face-up)

**Rules:**

- Contracts are placed face-up in the trap zone, visible to both players
- Contracts occupy one trap slot (shared with normal traps and future subtypes)
- Maximum 3 active traps/contracts simultaneously
- A Contract has three components defined on the card:
  - **Persistent effect** — ongoing passive effect active while the Contract is on board
  - **Violation condition** — a specific enemy action that triggers the violation
  - **Violation reward** — the effect that fires when the violation condition is met
- When the violation condition is triggered by the enemy, the violation reward fires immediately, then the Contract is removed
- The persistent effect and violation condition are independent — they do not need to be thematically related
- The enemy may choose to violate a Contract deliberately if the persistent pressure outweighs the violation penalty
- Contracts are destroyed by any trap removal effect (Cyclone, Hurricane, Trapbreaker Rogue)
- Contracts cannot be manually removed by the owner once placed
- The persistent effect fires each turn during the owner’s turn start phase unless the violation condition fires first

**Example — Trade Embargo:**

- Persistent: all enemy minions cost 2 more Gold
- Violation condition: enemy casts a spell
- Violation reward: draw 3 cards, remove Contract

**Design intent:** Contracts force enemy decision-making every turn. The enemy is always evaluating whether the persistent pressure is more costly than the violation penalty. The Contract owner benefits either way — sustained economic drain or an immediate payoff. Unlike normal traps which the enemy tries to avoid triggering, Contracts may sometimes be worth violating deliberately, creating a genuine dilemma.

-----

### 6.4 Hire X

**Category:** Keyword — Minion

**Keyword text:** *Hire X — at the start of your turn, pay X Gold to keep this minion on board. If you do not or cannot pay, this minion is removed.*

**Rules:**

- Hire X is an ongoing upkeep cost separate from the card’s play cost
- The play cost on the card is the initial hiring fee (paid once on play)
- Hire X is paid at the start of the owner’s turn, during the resource phase
- Payment is mandatory if the owner has sufficient Gold — the owner cannot choose to underpay if they have the Gold available. Underpayment is only possible if total Gold is insufficient.
- If the owner cannot pay (insufficient Gold), the minion is removed from the board
- Removal via Hire expiry is NOT a death — it does not trigger on-death effects, deathrattles, or death watchers
- Cargo counters on a Hired unit are lost when the unit is removed via Hire expiry
- Bounty issued by a Hired unit is cancelled when the unit is removed via Hire expiry
- Hire X value appears on the card as part of the keyword badge (e.g. Hire 1, Hire 2, Hire 3)
- Hired units can have stats and effects that would be overpowered on permanent units — the upkeep cost is the primary balance lever

**Design intent:** Hire creates recurring resource tension. A Hired unit is a continuous commitment — the owner must evaluate each turn whether the unit’s value justifies the Gold drain. In the late game when expensive cards compete for Gold, letting a Hired unit go may be the correct play. The enemy can apply indirect pressure by forcing the owner to spend Gold elsewhere, making Hire upkeep difficult to sustain.

-----

### 6.5 Bleeding

**Category:** Status effect — Stackable debuff

**Applicable to:** Enemy minions and enemy hero

**Rules:**

|Property                 |Value                                                 |
|-------------------------|------------------------------------------------------|
|Damage per stack per turn|50                                                    |
|Duration                 |3 turns                                               |
|Stacking                 |Each additional stack increases total damage per turn |
|Refresh                  |Duration resets to 3 turns when new stacks are applied|
|Removal                  |Expires naturally after 3 turns with no new stacks    |

**Damage by stack count:**

|Stacks|Damage per turn|
|------|---------------|
|1     |50             |
|2     |100            |
|3     |150            |
|4     |200            |

**Burst calculation (Bloodburst talent — Dagan):**

- 3 stacks × 3 remaining turns × 50 = **450 burst damage**
- With Deep Cut talent: 3 stacks × 3 turns × 75 = **675 burst damage**

**Rules:**

- Bleeding damage fires at the start of the affected unit’s controller’s turn
- Bleeding ticks down by 1 duration each turn; at 0 duration, all stacks are removed
- New stacks applied to a target with existing Bleeding reset the duration to 3 turns (stacks are additive, duration refreshes)
- Bleeding damage is not blocked by Armour (it is poison/bleed type, not physical)
- Bleeding cannot be applied to structures or environments

**Design intent:** Bleeding rewards consistent attack pressure. A unit that applies Bleeding on every attack (e.g. Arena Challenger with First Blood talent) builds up stacks over multiple turns for compounding damage. The 3-turn duration window means Bleeding must be maintained — if the applying unit is removed, the stacks decay naturally.

-----

### 6.6 Dual Strike

**Category:** Keyword — Minion

**Keyword text:** *This minion may attack twice per turn. Each attack exhausts one charge. After two attacks the minion is fully exhausted until the next turn.*

**Rules:**

- Dual Strike grants exactly 2 attack charges per turn — no more
- Dual Strike does not stack — a minion cannot attack more than twice per turn regardless of how many times the keyword is applied
- Rush (Arena Empowerment passive) + Dual Strike: a minion with both can attack twice on the turn it is summoned
- Guard enforcement applies independently to each attack — if the enemy has a Guard minion, both attacks must target it (unless it dies after the first attack)
- Lifedrain applies to both attacks independently
- Bleeding application (if any) applies on each attack separately — both attacks can stack Bleeding
- Bounty: if a Bounty-issuing minion has Dual Strike, each attack is a separate combat event; Bounty resolves when the marked enemy dies regardless of which attack killed it
- After two attacks the minion enters EXHAUSTED state and cannot attack again until the next turn

**Design intent:** Dual Strike is a high-value keyword that amplifies any on-attack effect. It pairs naturally with Bleeding application (two stacks per turn instead of one), Bounty (more attacks = more chances to kill the marked target), and stat-scaling units (two attacks = double the kill potential). It is deliberately rare — the capstone of Dagan’s Combat branch — to prevent it from becoming a baseline expectation.

-----

## 7. Mechanic Interactions Summary

|Mechanic A |Mechanic B     |Interaction                                                        |
|-----------|---------------|-------------------------------------------------------------------|
|Cargo      |On-death effect|Enemy dilemma: kill to deny delivery but trigger death effect      |
|Cargo      |Hire           |Must keep paying upkeep to complete delivery; expiry loses counters|
|Bounty     |Dual Strike    |Two attacks per turn increases pressure on marked target           |
|Bounty     |Hire           |Bounty cancelled if Hired unit expires before prey dies            |
|Bleeding   |Dual Strike    |Two attacks per turn = two Bleeding stacks applied per turn        |
|Contract   |Hire           |Hiring a unit drains Gold, making Contract upkeep harder for enemy |
|Dual Strike|Lifedrain      |Lifedrain applies on both attacks                                  |

-----

## 8. City Identity Mapping

Each city maps naturally onto the faction’s mechanical identity.

|City         |Mechanical Theme                      |
|-------------|--------------------------------------|
|**Ironhaven**|Bleeding · Dual Strike · arena combat |
|**Duskport** |Hire · Cargo · smuggling volatility   |
|**Crestholm**|Bounty · Contract · enforcer precision|

-----

## 9. Heroes

|Hero                    |Status       |Branch Focus                               |
|------------------------|-------------|-------------------------------------------|
|Dagan, the Undefeated   |Designed     |Bleeding · Warband · Combat (Dual Strike)  |
|Caravan Master (unnamed)|Concept phase|Combat Escort · Trade Route · Smuggling Run|

-----

## 10. Design Aesthetic

**Frame colors**

- Warm gold
- Amber
- Bronze
- Crimson

**Visual motifs**

- Arena chains and broken shackles
- Caravan wheels and road markers
- Contract scrolls and wax seals
- Trophy weapons from defeated opponents
- Coin purses and trade goods

**Tone**

- Practical, worn, lived-in
- No arcane symbols or cosmic imagery
- Everything looks like it has been used and survived use

### 10.1 Free Cities Minion Card Frame Direction

The Free Cities minion frame should feel like a high-quality martial object built by craftsmen, quartermasters, and armorers rather than by sorcerers. It must communicate coin, steel, contract law, and arena prestige at a glance while still obeying the locked minion layout in `CARD_FRAME_DESIGN_REGULATION.md`.

**Core read at first glance**

- A disciplined metal frame with warm gold and bronze as the main body materials
- Crimson used as a controlled accent, not a full-surface glow language
- Ornament that looks forged, riveted, engraved, and repaired rather than grown or enchanted
- A subtle sense of wealth and status without reading as royal, holy, or magical

**Primary material language**

- Main frame body: brushed bronze and aged gold with visible wear on corners and high-contact edges
- Dark recess metal: iron or gunmetal in joints, seams, and inset channels
- Accent color: crimson enamel, wax-seal red, and muted amber highlights
- Surface finish: scratches, small dents, leather backing, and soot-darkened creases are good
- Avoid polished mirror gold, gemstone glow, void haze, or smooth cosmic gradients

**Motif hierarchy**

Use motifs in this priority order so the frame has a strong identity without becoming cluttered.

1. Forged civic metalwork and mercenary equipment
2. Arena prestige details
3. Trade and contract details
4. Caravan references

That means the frame should primarily read as forged wargear first, with arena and commerce cues embedded into the ornament.

**Recommended structural expression**

- Cost badge: a minted coin or medallion look, thick and stamped, with a hammered rim rather than a glowing orb
- Title bar: long forged nameplate with inset brass trim and a slightly notched, practical silhouette
- Race bar: narrow engraved plaque or contract plate; clean and uninterrupted for text readability
- Art window frame: heavy square inner braces like reinforced armor corners or arena gate brackets
- Description panel: dark leather or deep oxblood-backed plate inset into metal, still dark enough for runtime readability
- Attack and health bars: asymmetrical by icon language only, not by placement; both should feel like attached equipment plates
- Bottom-center ornament: small guild crest, crossed blades, wheel hub, or sealed medallion; keep it secondary

**Faction motif placement by region**

- Top-left cost badge: coin minting, stamped laurels, civic seal, or chain-ring geometry
- Top-center title crest: small contract seal, crossed spearheads, or shield boss
- Side pillars: restrained chain links, riveted straps, trophy hooks, or wagon-brace metalwork
- Around the art window corners: bracketed steel corners, broken shackle shapes, or arena gate ironwork
- Description panel surround: leather-backed metal trim, wax-seal accents, or inset merchant filigree
- Bottom stat bars: weapon and shieldcraft styling, with clear readable icon recesses

**City blend recommendation**

The minion frame should not split into three separate city looks. Use one unified faction frame with mixed influences:

- Ironhaven as the primary read: arena steel, trophy hardware, gladiator grit
- Duskport as secondary texture: cargo straps, coin detail, trade-worn patina
- Crestholm as precision finish: contract plaques, official seals, measured symmetry

This keeps the faction broad enough for many cards while preserving a stable visual identity.

**What should make it different from Abyss Order**

- No purple energy, glowing crystals, occult ornament, or thorned demonic curvature
- Less mystical verticality, more grounded plate construction
- More visible hardware: rivets, braces, hinges, clasp logic, layered metal joins
- Warmer and drier palette overall
- Decorative language should imply labor, ownership, and earned prestige rather than forbidden power

**Shape language**

- Mostly rectangular and production-efficient, matching the locked minion template exactly
- Corners may be reinforced and slightly proud, but not spiked or winged
- Use notches, plates, straps, and stamped trim instead of horns, blades, or crystal flares
- Silhouette should feel sturdy, load-bearing, and reusable

**Recommended color distribution**

- 55% aged gold / bronze
- 20% dark iron / shadow metal
- 15% crimson enamel / wax-seal accents
- 10% leather, wood, or muted amber highlight detail

**Do not use**

- Floating coins, oversized treasure piles, or comedic merchant props
- Royal crowns or church-like sanctified motifs that could read as Solmara
- Arcane runes, void cracks, nebula glow, or magical smoke
- Large chain bundles that clutter the text lanes
- Scrollwork so ornate that it weakens the practical mercenary tone

**Art brief summary for production**

Create a `1024x1536` full-card minion frame that follows the locked minion template exactly, using a forged bronze-and-gold body with crimson contract accents, reinforced square art-window corners, a coin-like cost badge, a leather-backed dark description panel, and compact mercenary guild ornament. The frame should feel battle-worn, valuable, and human-made, with Ironhaven arena grit as the dominant read and Duskport/Crestholm details supporting it.

### 10.2 Minion Frame Visual Blueprint

This section translates the Free Cities frame direction into a concrete visual blueprint for the full-card minion frame.

The blueprint assumes strict compliance with the locked minion layout in `CARD_FRAME_DESIGN_REGULATION.md`. All notes below describe appearance and ornament only, not placement drift.

**Overall composition**

- The frame should read as a forged rectangular plate assembly with attached hardware
- Major masses should feel bolted together from crafted components rather than grown from one magical material
- Visual weight should be strongest at the top-left badge, top bar corners, art window braces, and bottom stat housings
- Side rails should stay slimmer and quieter so the art remains dominant

**1. Cost badge**

- Form: a thick minted coin medallion seated in a metal socket
- Main materials: aged gold outer rim, darker bronze inner ring, iron shadow in recesses
- Surface detail: stamped ridges, slight hammer marks, tiny civic laurels or ring notches
- Accent language: faint crimson enamel ring or wax-seal red inset, used sparingly
- Read goal: this should instantly communicate Gold without needing floating coin props
- Avoid: gem orb reads, magical glow core, crown silhouettes, or treasure-chest comedy

**2. Title bar**

- Form: a long forged nameplate, flatter and more practical than Abyss Order's mystical band
- Edge treatment: beveled metal trim with cut corners or shallow notches
- Interior fill: dark brushed plate, muted crimson-brown leather, or darkened brass inset
- Small center accent: a compact crest boss or stamped guild seal at the top-center only if it does not intrude on the text lane
- Read goal: the title bar should feel official, manufactured, and slightly militarized

**3. Race bar**

- Form: a narrower engraved contract plaque mounted beneath the title bar
- Material: brass or bronze plate with dark iron edge brackets
- Interior: dark readable inset, less decorative than the title bar
- Optional details: tiny rivets, legal-seal corners, subtle line engraving
- Read goal: this should feel like an identification plate or contract registry tag

**4. Art window frame**

- Form: a strict square opening with heavy reinforced corner brackets
- Corner language: armor braces, gate joints, or wagon-frame ironwork
- Inner edge: clean metal lip with enough depth to feel engineered
- Outer edge: slight layered trim so the art window feels protected, not floating
- Read goal: the square should feel sturdy and load-bearing, like a framed fighting pit gate or armored viewing aperture
- Best motif use: broken shackle arcs or chain-ring geometry integrated into corner brace shapes, not hanging loose over the art

**5. Side rails**

- Form: long vertical support members, visually quieter than the top and bottom
- Material stack: bronze/gold outer frame, dark iron inner channels
- Details: restrained rivets, seam lines, cargo-strap logic, or narrow engraved patterns
- Read goal: these should support the “constructed object” feel without stealing attention from the portrait
- Avoid: large trophies, loose chains, wide spikes, or big outward side flares

**6. Description panel**

- Form: a broad inset plate seated into the lower frame body
- Interior fill: dark oxblood, wine-brown, or soot-dark leather-purple tuned for text readability
- Outer trim: warm metal lip with worn corners and slight edge scratching
- Optional corner details: wax-seal stamp impressions, pressed leather tooling, or subtle document-border lines
- Read goal: the panel should feel like a field ledger, contract board, or hardened equipment insert
- Important: this area should stay calm; it is a readability zone first

**7. Attack bar**

- Form: a left-mounted weapon plate bolted into the base
- Icon language: sword, axe edge, spearhead, or crossed blades integrated modestly
- Material feel: heavier iron with gold/bronze trim, slightly more aggressive geometry than the health bar
- Accent use: very restrained crimson linework or enamel seam
- Read goal: it should feel like a forged combat plate attached to the frame body

**8. Health bar**

- Form: a right-mounted protection or vitality plate mirroring the attack bar placement
- Icon language: heart inset, shield-heart hybrid, or durable civic crest form
- Material feel: slightly smoother and steadier than the attack plate, but still in the same family
- Accent use: amber or subdued crimson is fine, but keep it secondary to readability
- Read goal: durable, maintained, dependable; not magical healing energy

**9. Bottom-center ornament**

- Form: small and integrated, acting as a joining badge between the lower elements
- Best candidates:
  - guild medallion
  - wheel hub
  - wax-sealed crest
  - crossed arena blades
- Read goal: this should be a signature accent, not a giant centerpiece
- Avoid: oversized gemstone, demonic idol, or anything that pushes into stat readability

**10. Surface storytelling**

- Good wear:
  - edge rub on gold
  - scratches near corners and brackets
  - soot in recesses
  - slightly darkened rivet seams
  - faint leather creasing
- Bad wear:
  - excessive rust
  - junkyard decay
  - blood splatter everywhere
  - comedy-level grime

The frame should feel maintained by professionals who use hard equipment every day, not abandoned relic scavengers.

**11. Motif usage rules**

- Chains should appear as controlled structural references, not dangling clutter
- Caravan details should read as brace logic, straps, wheel-hub geometry, or cargo hardware, not literal wagons pasted onto the frame
- Contract details should read as seals, plaques, registration marks, and official trim
- Arena prestige should come through trophy craftsmanship and reinforced combat architecture, not giant colosseum miniatures
- Coins should be most visible in the cost badge, with only tiny supporting echoes elsewhere

**12. Visual balance target**

- 60% practical forged metal
- 20% prestige ornament
- 10% contract/trade detail
- 10% grit and wear storytelling

If the frame starts feeling like a luxury merchant relic, reduce ornament. If it starts feeling generic medieval metal, add more contract-seal and coin-mint identity.

### 10.3 Free Cities Battlefield Minion Frame Direction

The Free Cities battlefield minion frame should be a compact combat HUD translation of the full-card frame, not a cropped-down version of it. It must follow the battlefield frame standard in `CARD_FRAME_DESIGN_REGULATION.md`: `900x975` master export, true transparent alpha in the art window, no visible transparent outer margin, and clearly separated status, attack, and health zones.

**Core battlefield read**

- A sturdy bronze-and-iron arena equipment frame built for board readability
- Warm gold and worn bronze as the primary faction signal
- Crimson used only as slim enamel strips, seal accents, or small leather insets
- Large portrait window with quiet side rails and no ornament intruding into the art
- Bottom HUD that reads instantly at small scale: status first, attack left, health right

**Recommended structure**

- Outer silhouette: mostly rectangular, thick enough to feel armored, but slimmer than the full-card frame
- Top strip: a low forged name/status cap with a small central guild boss or arena helm mark
- Art window: large rounded-rectangle or soft-square opening with reinforced metal corner brackets
- Side rails: narrow bronze posts with dark iron inner channels, rivets, and subtle cargo-strap logic
- Status bar: broad horizontal plate above the stats, preferably dark oxblood leather or gunmetal inset for icon contrast
- Attack panel: left-bottom weapon plate with a small crossed-blade or spearhead motif
- Health panel: right-bottom shield-heart or civic shield plate, visually quieter than attack
- Bottom-center join: tiny sealed medallion, wheel hub, or contract rivet; keep it secondary

**Motif priority at battlefield scale**

Use fewer, larger shapes. Tiny details disappear on the board, so the asset should rely on readable silhouette, color blocking, and material contrast.

1. Forged arena hardware: corner braces, rivets, shield bosses, worn metal lips
2. Mercenary economy: coin-stamped top boss or small minted rim details
3. Contract law: wax-seal red accent, registration plaque edges, measured symmetry
4. Caravan utility: strap logic, wheel-hub geometry, cargo-brace seams

Avoid literal scrolls, dangling chains, big coins, treasure props, or full-card-level filigree. Those will either clutter the portrait or fight the status icons.

**Color distribution**

- 50% aged bronze / warm gold
- 25% dark iron / gunmetal recesses
- 15% oxblood leather / muted crimson enamel
- 10% worn edge highlights, scratches, soot, and amber glints

At battlefield size, the frame should read warmer and more human-made than Abyss Order, but less ornate than the full-card Free Cities minion frame.

**Readability rules**

- Keep the art window visually dominant; do not reduce it for title ornament
- Do not add a cost badge unless the live battlefield layout explicitly needs one
- Keep the top treatment quiet because board slots already compete for attention
- Reserve the bottom HUD for numbers and status icons; ornament must frame these areas, not occupy them
- Attack and health panels must remain separate blocks with clear visual separation
- Status icons need a dark, calm backing with no bright pattern underneath
- Use scratches and dents on outer edges, not behind text or numbers

**Difference from existing references**

- Compared with neutral: richer bronze/gold material, more guild/arena identity, less plain stone
- Compared with Abyss Order: no purple glow, no occult arcs, no thorny or void-like curvature
- Compared with Free Cities full-card frame: fewer plaques, less vertical detail, no large cost medallion, stronger HUD discipline

**Production art brief**

Create a `900x975` transparent PNG battlefield minion frame for the Free Cities faction. The frame should fully cover the outer image edge, with a large true-alpha portrait window and a separated lower HUD: wide status bar above, attack panel bottom-left, health panel bottom-right. Use forged aged bronze, warm gold, dark iron, oxblood leather, and restrained crimson enamel. Integrate arena hardware, rivets, compact guild-seal details, and small contract/wax-seal accents. The asset should feel battle-worn, valuable, practical, and human-made, with no cosmic glow, no arcane symbols, no oversized crest, no dangling chain clutter, and no ornament blocking the portrait, status icons, or stat numbers.

-----

## 11. Faction Design Principles

- **Free Cities units survive through player investment** — unlike Abyss Order which generates value through death, Free Cities generates value through endurance
- **Every mechanic creates a two-sided decision** — Cargo forces the enemy to prioritize removal; Bounty forces the enemy to choose which unit to protect; Contract forces the enemy to evaluate violation cost vs. persistent pressure; Hire forces the owner to evaluate ongoing Gold commitment
- **Volatility is a feature, not a bug** — Smuggling Run (caravan hero branch) and Bloodburst (Dagan branch) have high variance payoffs by design
- **Gold as unified resource reflects the faction** — mercenaries do not split their payment into categories; everything costs coin
- **No cosmic power source** — Free Cities cards never reference Abyss, Void, or Astral energy; their power comes from skill, equipment, and determination

-----

*End of Free Cities Faction Design Document · Echo of Abyss*
