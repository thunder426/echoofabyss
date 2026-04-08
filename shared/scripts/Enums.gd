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
	VOID_MARK,      # Display-only pseudo-keyword: shown in tooltip on cards that apply Void Marks
	RITUAL,         # Display-only pseudo-keyword: shown in tooltip on environment cards that define rituals
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
	ON_PLAYER_ATTACK,           # Player minion attacks (ctx.minion = attacker; fires BEFORE attack)
	ON_PLAYER_ENVIRONMENT_PLACED, # Player places an environment card (ctx.card)

	# ---- Minion death ----
	ON_PLAYER_MINION_DIED,      # A player minion died (ctx.minion = the dead minion)
	ON_ENEMY_MINION_DIED,       # An enemy minion died (ctx.minion = the dead minion)

	# ---- Enemy actions ----
	ON_ENEMY_MINION_SUMMONED,   # Enemy summons a minion (ctx.minion = summoned)
	ON_ENEMY_SPELL_CAST,        # Enemy casts a spell (ctx.card = spell)
	ON_ENEMY_TRAP_PLACED,       # Enemy plays a trap (stub — enemy traps not yet implemented)
	ON_ENEMY_ATTACK,            # Enemy minion attacks (ctx.minion = attacker; fires BEFORE attack)

	# ---- Damage / healing ----
	ON_HERO_DAMAGED,            # Player hero took damage (ctx.owner="player", ctx.damage=amount)
	ON_ENEMY_HERO_DAMAGED,      # Enemy hero took damage (ctx.owner="enemy",  ctx.damage=amount)

	# ---- Rune / Ritual ----
	ON_RUNE_PLACED,                    # Player places a Rune (ctx.card = rune). Ritual handlers listen here.
	ON_RITUAL_ENVIRONMENT_PLAYED,      # Player plays an Environment that defines rituals. Ritual handlers scan here.

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
		TriggerEvent.ON_PLAYER_MINION_SUMMONED:  return TriggerEvent.ON_ENEMY_MINION_SUMMONED
		TriggerEvent.ON_ENEMY_MINION_SUMMONED:   return TriggerEvent.ON_PLAYER_MINION_SUMMONED
		TriggerEvent.ON_PLAYER_MINION_DIED:      return TriggerEvent.ON_ENEMY_MINION_DIED
		TriggerEvent.ON_ENEMY_MINION_DIED:       return TriggerEvent.ON_PLAYER_MINION_DIED
		TriggerEvent.ON_PLAYER_SPELL_CAST:       return TriggerEvent.ON_ENEMY_SPELL_CAST
		TriggerEvent.ON_ENEMY_SPELL_CAST:        return TriggerEvent.ON_PLAYER_SPELL_CAST
		TriggerEvent.ON_PLAYER_ATTACK:           return TriggerEvent.ON_ENEMY_ATTACK
		TriggerEvent.ON_ENEMY_ATTACK:            return TriggerEvent.ON_PLAYER_ATTACK
		TriggerEvent.ON_HERO_DAMAGED:            return TriggerEvent.ON_ENEMY_HERO_DAMAGED
		TriggerEvent.ON_ENEMY_HERO_DAMAGED:      return TriggerEvent.ON_HERO_DAMAGED
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

## How damage is delivered — determines scaling, shield interaction, and trigger reactions.
enum DamageType {
	PHYSICAL,   # Minion combat attacks
	SPELL,      # Spell / effect damage (minion or hero target)
	VOID_BOLT,  # Hero-targeted; scales with Void Marks; triggers bolt passives
	# Future: TRAP, POISON, FIRE, CHAOS…
}

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
	# ---- Combat grants ----
	CRITICAL_STRIKE, # Stacking. Consumed 1 per attack; doubles effective_atk for that attack.
	GRANT_SPELL_IMMUNE, # Grants Spell Immune at runtime. Dispellable.
	# ---- Debuffs ----
	CORRUPTION,      # Stacking ATK penalty. amount = penalty per stack (100 base, 200 w/ talent).
}
