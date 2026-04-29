# Card Description Style Guide

All card descriptions in `CARD_LIBRARY.md` and `CardDatabase.gd` must follow these rules:

## Targeting

- Any target (minion or hero): just "deal X damage"
- Any minion (friendly or enemy): "deal X damage to a minion"
- Enemy only: "enemy minion" or "enemy hero" — no article "the"
- Friendly only: "friendly minion" or "your hero"
- Friendly/enemy are **relative** to the card player — never say "player hero" or hardcode a side

## Buffs

- Use "Give" not "Grant": "Give X +Y ATK and +Z HP"
- Expand shorthand: "+X/+Y" → "+X ATK and +Y HP"
- Permanence is default — don't say "permanently". Only say "this turn" for temporary effects

## Auras (continuous effects while source is alive)

- Use `AURA:` label — not "PASSIVE:" or "(aura)" suffix
- Stat auras use "have": "AURA: All friendly X have +Y ATK and +Z HP"
- Non-stat auras still use `AURA:` label: "AURA: Whenever a Void Spark is summoned, deal 200 damage to enemy hero."

## Healing

"heal X for Y" — not "restore"

## Destruction

"Destroy" — not "instantly kill"

## Formatting

- Capitalize first word after trigger labels (ON PLAY:, ON DEATH:, PASSIVE:, AURA:, RUNE:, TRAP:)
- Remove redundant "target", "selected" — targeting is implicit
- Clan names stay ALL CAPS: FERAL IMP, VOID IMP CLAN
- No internal jargon ("AoE") — use "damage"
- Keywords (SWIFT, GUARD, DEATHLESS, etc.) must NOT appear in description if the card already has them in its keyword field. Only mention keywords in description when the effect grants them to other minions.
