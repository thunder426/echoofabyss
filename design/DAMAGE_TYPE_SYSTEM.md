# Damage Type System

Status: Implemented (2026-04-25).

Unifies damage classification across the codebase. Replaces the partial `Enums.DamageType` (PHYSICAL / SPELL / VOID_BOLT) with two orthogonal axes plus a lineage table for sub-schools.

## Motivation

The pre-existing `DamageType` enum conflated two unrelated concepts:

- **Source** — who/what dealt the damage (a minion's attack vs. a spell card)
- **School** — what kind of damage it is (physical, void, fire, …)

`VOID_BOLT` was wedged in as a peer of `PHYSICAL` and `SPELL`, which forced category errors: a Void Bolt is *spell-source, void-school*, not its own third category. Compounding this, damage type information never reached `EffectStep`, `EventContext`, or trigger handlers — so cards could not react to damage flavor at all (e.g. "when you take void damage, …" was unimplementable).

The new model separates the two axes, plumbs them through every damage path, and adds a lineage table so sub-schools (Void Bolt is-a Void; Bleeding is-a Physical) compose cleanly with buffs, resists, and triggers.

## The Two Axes

### DamageSource

Who/what dealt the damage.

| Source   | Applies to                                                                                       |
| -------- | ------------------------------------------------------------------------------------------------ |
| `MINION` | Minion basic attacks; minion-emitted effects (battlecries, deathrattles, on-play, auras, etc.)   |
| `SPELL`  | Spell cards, traps, environment, hero powers, **all DoT ticks regardless of who applied the DoT** |

Future sources (e.g. `FATIGUE`) can be added as needed.

### DamageSchool

What kind of damage it is.

| School             | Notes                                                          |
| ------------------ | -------------------------------------------------------------- |
| `NONE`             | Minion-emitted default (battlecries, deathrattles, auras). Surfaces forgotten tags loudly — see "Defaults" below. **Not valid for spell DAMAGE_* steps** — lint-enforced at load |
| `PHYSICAL`         | Default for minion basic attacks; also the mundane-hit spell flavor (e.g. `precision_strike`) |
| `ARCANE`           | Generic neutral magic — `arcane_strike` and other neutral spells without a more specific flavor |
| `VOID`             | Void faction default                                           |
| `VOID_BOLT`        | Sub-school of `VOID`. Bolt-themed direct burst — `void_bolt`, `void_detonation`. Triggers bolt passives |
| `VOID_FLESH`       | Sub-school of `VOID`. Flesh/visceral damage — `flesh_rend`, `flesh_eruption`, `resonant_outburst`. Gates Seris's Void Amplification |
| `VOID_CORRUPTION`  | Sub-school of `VOID`. Corruption-themed damage — `abyssal_plague`, future Korrath corruption spells. Gates Korrath's Path of Corruption |
| `TRUE_DMG`         | Bypasses school resistances. `TRUE` is a GDScript reserved word |

More schools (`FIRE`, `FROST`, `BLEEDING`, `POISON`, `HOLY`, `CHAOS`, …) added on demand. **Resist the urge to define schools speculatively** — only add what cards actually use.

### Things that are NOT schools

- `PIERCING` — existing keyword for excess-damage carry-through on minion attacks
- `PIERCING_VOID` — talent that retags Void minion damage as `VOID_BOLT` at the emission site

These compose with schools rather than replacing them.

## Lineage (Sub-schools)

Each school declares the array of schools it satisfies — itself plus its parents.

```gdscript
const SCHOOL_LINEAGE := {
    DamageSchool.NONE:            [],
    DamageSchool.PHYSICAL:        [DamageSchool.PHYSICAL],
    DamageSchool.ARCANE:          [DamageSchool.ARCANE],
    DamageSchool.VOID:            [DamageSchool.VOID],
    DamageSchool.VOID_BOLT:       [DamageSchool.VOID_BOLT, DamageSchool.VOID],
    DamageSchool.VOID_FLESH:      [DamageSchool.VOID_FLESH, DamageSchool.VOID],
    DamageSchool.VOID_CORRUPTION: [DamageSchool.VOID_CORRUPTION, DamageSchool.VOID],
    DamageSchool.TRUE_DMG:        [DamageSchool.TRUE_DMG],
    # Examples for future schools:
    # DamageSchool.BLEEDING: [DamageSchool.BLEEDING, DamageSchool.PHYSICAL],
    # DamageSchool.BURNING:  [DamageSchool.BURNING, DamageSchool.FIRE],
}

static func has_school(school: DamageSchool, target: DamageSchool) -> bool:
    return target in SCHOOL_LINEAGE.get(school, [])
```

**All buff/resist/trigger predicates use `has_school()`, never `==`.** Direct equality silently misses subschools — `info.school == VOID` would not match Void Bolt damage.

### Examples

| DamageInfo school   | Satisfies                  | "+20% void" buffs it? | Bolt passive triggers? | Seris Void Amplification (Flesh amp)? | Korrath Path of Corruption (Corruption amp)? |
| ------------------- | -------------------------- | --------------------- | ---------------------- | ------------------------------------- | -------------------------------------------- |
| `VOID`              | VOID                       | yes                   | no                     | no                                    | no                                           |
| `VOID_BOLT`         | VOID_BOLT, VOID            | yes                   | yes                    | no (sibling)                          | no (sibling)                                 |
| `VOID_FLESH`        | VOID_FLESH, VOID           | yes                   | no                     | **yes**                               | no (sibling)                                 |
| `VOID_CORRUPTION`   | VOID_CORRUPTION, VOID      | yes                   | no                     | no (sibling)                          | **yes**                                      |
| `BLEEDING`          | BLEEDING, PHYSICAL         | "+20% physical" yes   | n/a                    | no                                    | no                                           |
| `PHYSICAL`          | PHYSICAL                   | "+20% physical" yes   | n/a                    | no                                    | no                                           |
| `NONE`              | (none)                     | no                    | no                     | no                                    | no                                           |

### Multi-parent (future)

Single-parent only for now. The lookup already returns an array, so adding multi-parent later is a non-breaking change:

```gdscript
DamageSchool.FROSTFIRE_BOLT: [DamageSchool.FROSTFIRE_BOLT, DamageSchool.FIRE, DamageSchool.FROST]
```

A "+20% fire" buff and a "+20% frost" buff both apply. Resist this until a card actually needs it.

## DamageInfo

Replaces the bare `type: Enums.DamageType` parameter on damage entry points. Carried through every damage path and surfaced on `EventContext.damage_info` so trigger handlers can branch on source/school.

```gdscript
{
    "amount": int,
    "source": Enums.DamageSource,
    "school": Enums.DamageSchool,
    "attacker": MinionInstance,    # null for spell damage
    "source_card": String,         # card id for attribution (e.g. for triggers)
}
```

Stored as a `Dictionary` rather than a `Resource` for now — lighter, no class overhead, and we have no need for typed methods on it yet. Constructor helper:

```gdscript
static func make_damage_info(
    amount: int,
    source: Enums.DamageSource,
    school: Enums.DamageSchool = Enums.DamageSchool.NONE,
    attacker: MinionInstance = null,
    source_card: String = ""
) -> Dictionary
```

## Tagging Rules (at emission site)

The emitting site is responsible for setting source and school correctly. The implemented rules are narrower than the original design speculated — we resisted faction-wide auto-tagging and kept school assignment explicit per card / per call site.

### Source

| Damage emission              | Source   |
| ---------------------------- | -------- |
| Minion basic attack          | `MINION` |
| Minion-emitted EffectStep    | `MINION` |
| Spell card EffectStep        | `SPELL`  |
| Trap / environment EffectStep | `SPELL`  |
| Hero power                   | `SPELL`  |
| DoT tick (any DoT)           | `SPELL`  |

`EffectResolver._build_damage_info()` infers source from `ctx.source`:

```gdscript
var source = Enums.DamageSource.MINION if ctx.source != null else Enums.DamageSource.SPELL
```

`EffectContext.source` is non-null for minion-emitted effects (set when a minion's on-play / passive / hardcoded handler fires) and null for spells, traps, environments, DoT ticks. No new field needed on EffectStep — the resolver decides automatically. Card authors can't misclassify source.

### School

| Damage emission                                         | School      |
| ------------------------------------------------------- | ----------- |
| Minion basic attack (default)                           | `PHYSICAL`  |
| Minion-emitted effect (default)                         | `NONE`      |
| Spell DAMAGE_* step (required, lint-enforced)           | as declared (must be non-NONE) |
| `EffectStep.VOID_BOLT` (special EffectType)             | `VOID_BOLT` (via `_deal_void_bolt_damage` wrapper) |
| Trap / ritual / environment DAMAGE_* step               | as declared, or `NONE` |
| HARDCODED spell step                                    | as the handler declares (e.g. `soul_shatter` → `VOID`) |
| Talent / passive override at the call site              | as the override declares |

**Key principle: school is opt-in, not auto-derived.** We considered (and rejected) faction-default rules like "all abyss_order minions auto-tag VOID." Two reasons:

1. Faction is a clan/lore concept; school is a damage-flavor concept. They're correlated but not identical (e.g. a future abyss_order fire-flavored minion shouldn't auto-tag VOID).
2. Buff/resist surface area: "+X% void damage" buffs become predictable when you can see at a glance which cards declare VOID. Auto-tagging hides the wiring.

### Talent overrides

The two talents that already retag damage at the call site (no `damage_school` field involved):

- **`piercing_void` (Lord Vael, capstone-tier-1)** — replaces base Void Imp's on-play "deal 100" with a 200 Void Bolt + Void Mark, via [`on_summon_piercing_void`](echoofabyss/combat/events/CombatHandlers.gd) calling `_deal_void_bolt_damage`. The replacement emits `VOID_BOLT` school.
- **`void_manifestation` (Lord Vael, capstone-tier-3)** — Void Imp clan minions' attacks against the enemy hero route through `_deal_void_bolt_damage` instead of `resolve_minion_attack_hero`, both in [`SimPlayerAgent.gd`](echoofabyss/sim/SimPlayerAgent.gd) and [`CombatScene.gd`](echoofabyss/combat/board/CombatScene.gd). Emits `VOID_BOLT` school.

Talents intercept at the call site rather than overriding `damage_school` on the step. This keeps the data definitions stable across talent loadouts — the same EffectStep emits different schools depending on which talents are active, decided at fire time.

### Currently tagged (Phase 7 audit results)

| School             | Cards                                                                                          |
| ------------------ | ---------------------------------------------------------------------------------------------- |
| `VOID`             | `void_execution`, `rift_collapse`, `void_lance`, `void_shatter`, `runic_blast`, `void_screech`, `sovereigns_decree`, `soul_shatter` (spells); `abyssal_summoning_circle` death effect; `_abyss_ritual_circle_passive` hardcoded handler |
| `VOID_BOLT`        | `void_bolt` spell; `void_rune` aura; Soul Cataclysm ritual; `_void_detonation` hardcoded; all `EffectStep.VOID_BOLT` invocations |
| `VOID_FLESH`       | `flesh_rend`, `flesh_eruption`, `resonant_outburst`. Seris's flesh-themed Abyss spells — exclusively amplified by Void Amplification (+50/stack across friendly Demons). |
| `VOID_CORRUPTION`  | `abyssal_plague`, future Korrath corruption spells. Corruption-themed Abyss spells — exclusively amplified by Korrath's Path of Corruption (+100/stack on target). |
| `ARCANE`           | `arcane_strike`. Generic neutral magic.                                                       |
| `PHYSICAL`         | All minion basic attacks (default in `_attack_damage_info`); `precision_strike` spell         |
| `NONE`             | All minion-emitted effects (Void Imp on-play, Senior Void Imp on-play, Runic Void Imp, Void Netter, Nyx'ael turn-start, Frenzied Imp, void-touched imp on-death); neutral traps. **Spells are NOT allowed to be `NONE` — task 018 lint-enforces.** |

## Defaults: why `NONE`, not `PHYSICAL`

Defaulting to `PHYSICAL` would silently absorb forgotten tags. A new Void card with no school set would deal physical damage, get buffed by "+20% physical," and the bug would be invisible until someone playtested the wrong interaction.

`NONE` makes the bug loud:
- "+20% physical" doesn't buff it
- "+20% void" doesn't buff it
- Resists don't reduce it
- "When you take void damage" doesn't trigger

Missing tags become obvious during playtest or sim, not silent miscalibrations.

`PHYSICAL` is reserved for emissions that *meaningfully are physical* — minion basic attacks and explicit physical spells. It's an opinion, not a fallback.

### Spells: school is required, lint-enforced

`NONE` is valid for minion-emitted effects (on-play, on-death, auras, hardcoded handlers), but **not** for spell DAMAGE_* steps. Every `SpellCardData` with a `DAMAGE_MINION` / `DAMAGE_HERO` / `DAMAGE_ANY` step must declare a non-NONE `damage_school`. `CardDatabase._validate_spell_damage_schools()` runs at load and fails fast with the offending card id and step index if anything is untagged.

The rule scope:

- **Spells** — must declare a school. Generic neutral spells use `ARCANE` or `PHYSICAL` based on flavor; faction spells use the faction's flavor (e.g. `VOID` for Abyss Order).
- **Minion-emitted effects** — keep defaulting to `NONE` unless the design wants school-keyed interactions (e.g. `abyssal_summoning_circle`'s on-death effect uses `VOID` because it's themed corruption).
- **Traps, rituals, environments** — same as minion-emitted: `NONE` default, opt in when flavored.
- **EffectStep.VOID_BOLT** — special EffectType that emits via `_deal_void_bolt_damage`; no `damage_school` field needed.
- **HARDCODED spell steps** — bypass the lint because the school is set in code (see `soul_shatter` → `VOID` in `HardcodedEffects.gd`).

## Implementation Map

Where each piece lives in the codebase:

| File                              | Role                                                                                          |
| --------------------------------- | --------------------------------------------------------------------------------------------- |
| `shared/scripts/Enums.gd`         | `DamageSource`, `DamageSchool`, `SCHOOL_LINEAGE` table, `has_school()` predicate              |
| `combat/board/CombatManager.gd`   | `make_damage_info()` constructor; three entry points `apply_hero_damage(target, info)`, `apply_damage_to_minion(minion, info)`, `_deal_damage(minion, info)`; `_attack_damage_info()` for basic-attack info building |
| `combat/effects/EffectStep.gd`    | `damage_school: int = NONE` field; `from_dict()` accepts string ("VOID") or int              |
| `combat/effects/EffectResolver.gd` | `_build_damage_info(step, ctx, amount)` infers source from `ctx.source`, school from step    |
| `combat/events/EventContext.gd`   | `damage_info: Dictionary` populated by `_on_hero_damaged` at trigger fire site                |
| `combat/board/CombatScene.gd`     | `_on_hero_damaged(target, info)` listener; `_flash_hero` and `_dmg_color` key off school via `has_school(school, VOID_BOLT)` |
| `sim/SimState.gd`                 | Mirror of CombatScene's listener; `_pending_dmg_source` log classification reads `info.source` |

### Resistance / amplification behavior

- **`SPELL_IMMUNE`** — blocks `info.source == SPELL`. Source-keyed (not school-keyed), so a SPELL-immune minion absorbs any spell-school combination but still takes minion-attack damage.
- **`ETHEREAL`** — amplifies SPELL-source damage by 50% in `apply_damage_to_minion`; reduces minion basic-attack damage by 50% in `resolve_minion_attack`. Source-keyed only — schools are not exempted.
- **Void Bolt scaling** — per-Void-Mark scaling stays on `_deal_void_bolt_damage` (the EffectStep.VOID_BOLT path). The school is metadata; the scaling is mechanics. Don't conflate them.
- **Korrath Armour / Armour Break** — **school-keyed, not source-keyed** (task 019). `CombatManager._school_bypasses_armour(school)` returns true for the VOID lineage and `TRUE_DMG`; everything else (PHYSICAL, ARCANE, NONE) runs through `_apply_armour_math`. So a PHYSICAL spell (`shatterstrike`) respects armour; a VOID minion-emitted effect bypasses it. Armour Break amplifies every non-bypassing hit, including PHYSICAL/ARCANE spells — this is a real power increase for Korrath B3 Path of Shattering + spell builds.

### Source vs school for armour: why the gate moved

Before task 019, the armour gate was `info.source == MINION` — i.e. minion attacks reduced by armour, everything else bypassed. That collapsed two distinct concerns into one axis: a "physical spell" couldn't exist because being a spell meant bypassing armour. Once the design called for PHYSICAL spells (`shatterstrike`) that interact with the Armour system, the gate had to switch to the orthogonal axis — school — and the source distinction became irrelevant for the armour decision. Minion basic attacks still respect armour because they default to PHYSICAL school in `_attack_damage_info`, not because their source is MINION.

## Card Authoring Implications

- **New damage-dealing spells must declare a `damage_school` — lint-enforced at load.** Pick the flavor that matches the card: `VOID` (and sub-schools) for Abyss spells, `ARCANE` for generic neutral magic, `PHYSICAL` for mundane-hit neutrals.
- Minion-emitted effects (on-play, deathrattle, hardcoded handlers) generally stay `NONE` unless the design wants school-keyed buff interactions. The conservative rule for non-spell sources: opt in when flavored; otherwise stay `NONE`.
- Talent-driven retags happen at the call site (see `piercing_void` and `void_manifestation` examples). Don't bake talent assumptions into `damage_school` data.
- "When you take X damage" / "Your X damage +Y%" cards: handler reads `ctx.damage_info.school` and uses `Enums.has_school(school, X)` for the predicate. Direct `==` is wrong — it misses sub-schools.

## Locked Decisions

- **`hero_damaged` signal** — single shape `hero_damaged(target: String, info: Dictionary)`. All listeners migrated at once in Phase 6.
- **Trigger events stay generic** (`ON_HERO_DAMAGED`); handlers branch on `ctx.damage_info.school` via `Enums.has_school()`. No per-school events.
- **`ETHEREAL`** keys off `info.source == SPELL` (resolved during Phase 6 migration).
- **No faction-default school inference**. School is opt-in per card.
- **`piercing_void` / `void_manifestation` retags** happen at the call site, not via `damage_school` field overrides.

## Test Coverage

`echoofabyss/debug/tests/DamageTypeTests.gd` — 21 probes / ~50 assertions covering:

- Phase 1: lineage helper (self / parent / unrelated / NONE / TRUE_DMG isolation)
- Phase 2: `make_damage_info()` field shape; `apply_hero_damage` signal emission and zero-amount silence; `apply_damage_to_minion` SPELL_IMMUNE / ETHEREAL semantics
- Phase 3: EffectResolver source inference (spell → SPELL, minion → MINION); explicit `damage_school` passes through; default is NONE
- Phase 4: minion basic attacks emit `(MINION, PHYSICAL, attacker)`; PIERCE carry-through inherits attacker
- Phase 5: `EventContext.damage_info` round-trips through TriggerManager; handler can branch on school via lineage
- Phase 7: `void_imp` on-play emits `(MINION, NONE)`; `void_bolt` spell emits `VOID_BOLT`; `void_lance` spell emits `VOID`; `arcane_strike` stays `NONE`
