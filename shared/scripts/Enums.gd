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
	MANA,     # Spells, traps, environments, hero power
}

## Minion sub-types used for synergy triggers
enum MinionType {
	DEMON,
	SPIRIT,
	BEAST,
	UNDEAD,
}

## Keywords that modify minion behaviour
enum Keyword {
	TAUNT,     # Enemy must attack this minion first
	RUSH,      # Can attack minions the turn it is summoned
	LIFEDRAIN, # Damage dealt to enemy hero also heals your hero
}

## Conditions that cause a face-down Trap card to activate
enum TrapTrigger {
	ON_ENEMY_ATTACK,   # Enemy minion declares an attack
	ON_ENEMY_SPELL,    # Enemy plays a spell card
	ON_ENEMY_SUMMON,   # Enemy summons a minion
	ON_DAMAGE_TAKEN,   # Your hero takes damage
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
}
