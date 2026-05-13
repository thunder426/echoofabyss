## Enums.gd
## Global enum definitions. Use class_name so all scripts can access
## Enums.CardType, Enums.Keyword, etc. without importing.
class_name Enums
extends RefCounted

enum CardType {
	MINION,
	SPELL,
	TRAP,
	ENVIRONMENT,
}

## Which resource pool is spent to play this card
enum CostType {
	ESSENCE,  # Summon minions
	MANA,     # Spells, traps, environments
}

## Minion sub-types used for synergy triggers
enum MinionType {
	DEMON,
	SPIRIT,
	BEAST,
	UNDEAD,
	HUMAN,
	CONSTRUCT,
	GIANT,
	MERCENARY,
}

## Keywords that modify minion behaviour
enum Keyword {
	GUARD,          # Enemy must attack this minion first
	SWIFT,          # Can attack enemy minions on the turn summoned; cannot attack the enemy hero that turn
	LIFEDRAIN,      # Damage dealt to enemy hero also heals your hero
	SHIELD_REGEN_1, # Regenerate 1 Shield at the start of owner's turn (magic shield, slow)
	SHIELD_REGEN_2, # Regenerate 2 Shield at the start of owner's turn (magic shield, fast)
	CHAMPION,       # Named/legendary unit — gold name display, unique card
	RUNE,           # A persistent trap placed face-up; provides an ongoing aura effect until consumed by a Ritual
	CORRUPTION,     # Reduces the afflicted minion's ATK by 100 per stack
	DEATHLESS,      # Prevents the next fatal damage once; sets HP to 50 and is consumed
	ETHEREAL,       # Takes 50% reduced damage from minion attacks, 50% increased from spells
	PIERCE,         # Excess kill damage on a minion carries through to the enemy hero
	SIPHON,         # This minion heals itself for 50% of damage it deals (distinct from Lifedrain which heals the hero)
	VOID_MARK,      # Display-only pseudo-keyword: shown in tooltip on cards that apply Void Marks
	RITUAL,         # Display-only pseudo-keyword: shown in tooltip on environment cards that define rituals
	SACRIFICE,      # Display-only pseudo-keyword: shown on cards whose effect destroys a friendly minion as cost
	FORMATION,      # Korrath — when placed adjacent to another minion of the same race, fires formation_effect_steps once permanently per pair
}

## All game events that flow through TriggerManager.
## This is the single unified vocabulary used by:
##   • TriggerManager handlers (talents, passives, relics, environments, minion abilities)
##   • TrapCardData.trigger — the condition that activates a trap
## Add a new value here when a new trigger point is needed, fire it from CombatScene,
## and register handlers in _setup_triggers().
enum TriggerEvent {
	# ---- Player turn ----
	ON_PLAYER_TURN_START,       # Start of the player's turn (relics, environment, talents)
	ON_PLAYER_TURN_END,         # End of the player's turn

	# ---- Enemy turn ----
	ON_ENEMY_TURN_START,        # Start of the enemy's turn (traps, Void Rain)
	ON_ENEMY_TURN_END,          # End of the enemy's turn

	# ---- Card draw / play ----
	ON_PLAYER_CARD_DRAWN,       # Player draws a card (ctx.card = the drawn card)
	ON_PLAYER_MINION_PLAYED,    # Player played a minion from hand (ctx.minion, ctx.card) — fires before ON_PLAYER_MINION_SUMMONED
	ON_PLAYER_MINION_SUMMONED,  # Player minion enters the board from ANY source (ctx.minion, ctx.card)
	ON_PLAYER_SPELL_CAST,       # Player casts a spell (ctx.card)
	ON_PLAYER_TRAP_PLACED,      # Player places a trap (ctx.card)
	ON_PLAYER_ATTACK_PRE,       # Player minion attacks — fires BEFORE damage resolves (ctx.minion=attacker, ctx.defender=MinionInstance or "X_hero" string)
	ON_PLAYER_ATTACK_POST,      # Player minion attacks — fires AFTER damage resolves on the defender, before counter-attack. Same ctx shape. AB-residual handlers (path_of_shattering, banner_of_the_order rider) live here.
	ON_PLAYER_ENVIRONMENT_PLACED, # Player places an environment card (ctx.card)

	# ---- Minion death ----
	ON_PLAYER_MINION_DIED,      # A player minion died (ctx.minion = the dead minion)
	ON_ENEMY_MINION_DIED,       # An enemy minion died (ctx.minion = the dead minion)

	# ---- Minion sacrifice (NOT death — strict rule: sacrifice does not fire ON DEATH) ----
	ON_PLAYER_MINION_SACRIFICED, # A player minion was sacrificed (ctx.minion = the sacrificed minion)
	ON_ENEMY_MINION_SACRIFICED,  # An enemy minion was sacrificed (ctx.minion = the sacrificed minion)

	# ---- Enemy actions ----
	ON_ENEMY_MINION_PLAYED,     # Enemy played a minion from hand (ctx.minion, ctx.card) — fires before ON_ENEMY_MINION_SUMMONED. Mirror of ON_PLAYER_MINION_PLAYED.
	ON_ENEMY_MINION_SUMMONED,   # Enemy minion enters the board from ANY source (ctx.minion = summoned)
	ON_ENEMY_SPELL_CAST,        # Enemy casts a spell (ctx.card = spell)
	ON_ENEMY_TRAP_PLACED,       # Enemy plays a trap (stub — enemy traps not yet implemented)
	ON_ENEMY_ATTACK,            # Enemy minion attacks (ctx.minion = attacker; fires BEFORE attack)

	# ---- Damage / healing ----
	ON_HERO_DAMAGED,            # Player hero took damage (ctx.owner="player", ctx.damage=amount)
	ON_ENEMY_HERO_DAMAGED,      # Enemy hero took damage (ctx.owner="enemy",  ctx.damage=amount)

	# ---- Rune / Ritual ----
	ON_RUNE_PLACED,                    # Player places a Rune (ctx.card = rune). Ritual handlers listen here.
	ON_RITUAL_ENVIRONMENT_PLAYED,      # Player plays an Environment that defines rituals. Ritual handlers scan here.
	ON_RITUAL_FIRED,                   # A ritual has resolved (ctx.owner = "player").
	ON_PLAYER_SPARK_CONSUMED,          # A player minion was consumed as spark cost (ctx.damage = spark_value).
	ON_ENEMY_SPARK_CONSUMED,           # An enemy minion was consumed as spark cost (ctx.damage = spark_value).

	# ---- Corruption ----
	ON_CORRUPTION_REMOVED,      # Corruption stacks removed from a minion by any means — death, Purge, Cleanse, enemy effect.
	                            # ctx.minion = the minion, ctx.owner = minion owner, ctx.damage = stacks removed.

	# ---- Formation ----
	ON_FORMATION_TRIGGERED,     # Korrath — a friendly minion's FORMATION fired (ctx.minion = actor whose Formation ran,
	                            # ctx.target = partner that satisfied the pairing, ctx.owner = actor's side).

	# ---- Combat lifecycle ----
	ON_COMBAT_START,            # Combat has begun
	ON_COMBAT_END,              # Combat ended (victory or defeat)
}

## Mirror a player-perspective trigger to its enemy equivalent (and vice versa).
## Used so rune aura triggers work symmetrically for both sides.
static func mirror_trigger(trigger: TriggerEvent) -> TriggerEvent:
	match trigger:
		TriggerEvent.ON_PLAYER_TURN_START:      return TriggerEvent.ON_ENEMY_TURN_START
		TriggerEvent.ON_ENEMY_TURN_START:        return TriggerEvent.ON_PLAYER_TURN_START
		TriggerEvent.ON_PLAYER_TURN_END:         return TriggerEvent.ON_ENEMY_TURN_END
		TriggerEvent.ON_ENEMY_TURN_END:          return TriggerEvent.ON_PLAYER_TURN_END
		TriggerEvent.ON_PLAYER_MINION_PLAYED:    return TriggerEvent.ON_ENEMY_MINION_PLAYED
		TriggerEvent.ON_ENEMY_MINION_PLAYED:     return TriggerEvent.ON_PLAYER_MINION_PLAYED
		TriggerEvent.ON_PLAYER_MINION_SUMMONED:  return TriggerEvent.ON_ENEMY_MINION_SUMMONED
		TriggerEvent.ON_ENEMY_MINION_SUMMONED:   return TriggerEvent.ON_PLAYER_MINION_SUMMONED
		TriggerEvent.ON_PLAYER_MINION_DIED:      return TriggerEvent.ON_ENEMY_MINION_DIED
		TriggerEvent.ON_ENEMY_MINION_DIED:       return TriggerEvent.ON_PLAYER_MINION_DIED
		TriggerEvent.ON_PLAYER_MINION_SACRIFICED: return TriggerEvent.ON_ENEMY_MINION_SACRIFICED
		TriggerEvent.ON_ENEMY_MINION_SACRIFICED:  return TriggerEvent.ON_PLAYER_MINION_SACRIFICED
		TriggerEvent.ON_PLAYER_SPELL_CAST:       return TriggerEvent.ON_ENEMY_SPELL_CAST
		TriggerEvent.ON_ENEMY_SPELL_CAST:        return TriggerEvent.ON_PLAYER_SPELL_CAST
		# Enemy side stays single-phase (pre-damage only) — traps and champion AI all
		# fire before damage. Both player phases mirror to the same enemy event; the
		# enemy-side mirror picks PRE as the closest 1:1.
		TriggerEvent.ON_PLAYER_ATTACK_PRE:        return TriggerEvent.ON_ENEMY_ATTACK
		TriggerEvent.ON_PLAYER_ATTACK_POST:       return TriggerEvent.ON_ENEMY_ATTACK
		TriggerEvent.ON_ENEMY_ATTACK:             return TriggerEvent.ON_PLAYER_ATTACK_PRE
		TriggerEvent.ON_HERO_DAMAGED:            return TriggerEvent.ON_ENEMY_HERO_DAMAGED
		TriggerEvent.ON_ENEMY_HERO_DAMAGED:      return TriggerEvent.ON_HERO_DAMAGED
		TriggerEvent.ON_PLAYER_SPARK_CONSUMED:   return TriggerEvent.ON_ENEMY_SPARK_CONSUMED
		TriggerEvent.ON_ENEMY_SPARK_CONSUMED:    return TriggerEvent.ON_PLAYER_SPARK_CONSUMED
	return trigger

## Rune sub-types used as ritual components (Abyss Order signature mechanic)
enum RuneType {
	VOID_RUNE,      # Void / spell synergy — aura: deal 100 Void Bolt damage at turn start
	BLOOD_RUNE,     # Sacrifice / demon synergy — aura: restore 100 HP when friendly minion dies
	DOMINION_RUNE,  # Board control / buff synergy — aura: all friendly Demons +100 ATK
	SHADOW_RUNE,    # Corruption synergy — aura: enemy minions enter with 1 Corruption
	SOUL_RUNE,      # Demon sacrifice synergy — aura: friendly Demon death on enemy turn → Spirit token
}

## Phase of a combat turn
enum TurnPhase {
	DRAW,
	PLAYER_TURN,
	ENEMY_TURN,
	RESOLUTION,
}

## State a minion can be in
enum MinionState {
	NORMAL,
	EXHAUSTED, # Cannot attack — just summoned or already attacked this turn
	SWIFT,     # Summoned with Swift — can attack enemy minions but not the enemy hero this turn
}

## Who/what dealt the damage — orthogonal to school.
## See design/DAMAGE_TYPE_SYSTEM.md.
enum DamageSource {
	MINION,  # Minion basic attacks AND minion-emitted effects (battlecries, deathrattles, on-play, auras)
	SPELL,   # Spell cards, traps, environment, hero powers, all DoT ticks
}

## What kind of damage — orthogonal to source. Composes with SCHOOL_LINEAGE for sub-schools.
## Default NONE: surfaces forgotten tags loudly rather than silently absorbing them as PHYSICAL.
## See design/DAMAGE_TYPE_SYSTEM.md.
enum DamageSchool {
	NONE,
	PHYSICAL,
	ARCANE,           # Generic neutral magic — arcane_strike etc. No parent.
	VOID,
	VOID_BOLT,        # Sub-school of VOID — bolt-themed direct burst (void_bolt, void_detonation). Triggers bolt passives.
	VOID_FLESH,       # Sub-school of VOID — flesh/visceral damage (flesh_rend, flesh_eruption, resonant_outburst). Gates Seris's Void Amplification.
	VOID_CORRUPTION,  # Sub-school of VOID — corruption-themed damage (abyssal_plague, future Korrath corruption spells). Gates Korrath's Path of Corruption.
	TRUE_DMG,         # Bypasses school resistances. Named TRUE_DMG because TRUE is a GDScript reserved word.
}

## Maps each school to the array of schools it satisfies (itself plus parents).
## Predicate `has_school()` walks this — never compare schools with `==` outside this file.
## Adding a sub-school: include itself first, then parent chain.
const SCHOOL_LINEAGE := {
	DamageSchool.NONE:            [],
	DamageSchool.PHYSICAL:        [DamageSchool.PHYSICAL],
	DamageSchool.ARCANE:          [DamageSchool.ARCANE],
	DamageSchool.VOID:            [DamageSchool.VOID],
	DamageSchool.VOID_BOLT:       [DamageSchool.VOID_BOLT, DamageSchool.VOID],
	DamageSchool.VOID_FLESH:      [DamageSchool.VOID_FLESH, DamageSchool.VOID],
	DamageSchool.VOID_CORRUPTION: [DamageSchool.VOID_CORRUPTION, DamageSchool.VOID],
	DamageSchool.TRUE_DMG:        [DamageSchool.TRUE_DMG],
}

## Returns true if `school` satisfies `target` (i.e. target is school itself or one of its parents).
## Use this for ALL school checks — buffs, resists, triggers. Direct == comparison silently
## misses subschools (e.g. school == VOID would not match VOID_BOLT damage).
static func has_school(school: int, target: int) -> bool:
	var lineage = SCHOOL_LINEAGE.get(school, [])
	return target in lineage

## Buff and debuff types tracked per-minion by BuffSystem.
## Buffs are removed by Dispel; debuffs are removed by Cleanse.
enum BuffType {
	# ---- Stat buffs (permanent unless is_temp) ----
	ATK_BONUS,       # Flat ATK increase. Permanent; reversible via remove_source or dispel.
	HP_BONUS,        # Flat max HP increase. Permanent; reversible; current_health clamped on removal.
	TEMP_ATK,        # Flat ATK increase for one turn. Auto-expired by BuffSystem.expire_temp.
	SHIELD_BONUS,    # Increases shield cap permanently. Reversible; current_shield clamped on removal.
	# ---- Keyword grants ----
	GRANT_GUARD,     # Grants Guard at runtime (e.g. Imp Overseer aura). Dispellable.
	GRANT_LIFEDRAIN, # Grants Lifedrain at runtime (e.g. Abyssal Fury). Dispellable.
	GRANT_DEATHLESS, # Grants Deathless at runtime. Consumed (removed) when it activates.
	GRANT_SIPHON,    # Grants Siphon at runtime (minion heals itself for 50% damage dealt). Dispellable.
	# ---- Combat grants ----
	CRITICAL_STRIKE, # Stacking. Consumed 1 per attack; doubles effective_atk for that attack.
	GRANT_SPELL_IMMUNE, # Grants Spell Immune at runtime. Dispellable.
	GRANT_IMMUNE,       # Grants full damage immunity. Cannot take any damage. Dispellable.
	# ---- Debuffs ----
	CORRUPTION,      # Stacking ATK penalty. amount = penalty per stack (100 base, 200 w/ talent).
	ARMOUR_BREAK,    # Korrath — stackable. Reduces target Armour for physical attacks; excess (AB > Armour) becomes flat bonus damage. Permanent unless cleansed.
}
