## EffectStep.gd
## A single declarative effect step stored on a card.
## Cards define their effects as Array[EffectStep] instead of a string ID
## dispatched through a match chain.
class_name EffectStep
extends Resource

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum EffectType {
	DAMAGE_HERO,       # Deal amount damage to opponent hero
	DAMAGE_MINION,     # Deal amount damage to resolved minion target(s)
	HEAL_HERO,         # Restore amount HP to own hero
	BUFF_ATK,          # Grant amount ATK to target(s); permanent flag controls temp vs perm
	BUFF_HP,           # Grant amount max/current HP to target(s)
	CORRUPTION,        # Apply amount stacks of Corruption to target(s)
	SUMMON,            # Summon token minion (card_id) for owner
	DRAW,              # Draw amount cards
	ADD_CARD,          # Add card_id to owner's hand
	SACRIFICE,         # Kill target ritually (emits SacrificeSystem signal → VFX); bypasses shield
	KILL_MINION,       # Kill target without ritual connotation (e.g. Death Trap); bypasses shield
	GRANT_MANA,        # Give owner amount Mana this turn
	GRANT_ESSENCE,     # Give owner amount Essence this turn
	GROW_MANA_MAX,     # Permanently raise owner's mana_max by 1 (capped by COMBINED_RESOURCE_CAP)
	VOID_MARK,         # Apply amount Void Marks to enemy hero
	GRANT_KEYWORD,     # Grant keyword (keyword field) to target(s)
	DESTROY,           # Destroy a trap, rune, or environment (non-minion targets)
	VOID_BOLT,         # Deal amount Void Bolt damage to enemy hero (scales with Void Marks, triggers bolt passives)
	GRANT_CRITICAL_STRIKE,  # Grant amount stacks of Critical Strike to target(s)
	GRANT_ON_DEATH_SUMMON,  # Grant target(s) a runtime "ON DEATH: summon card_id" effect
	COUNTER_SPELL,     # Increment owner's spell counter — next enemy spell is cancelled
	TUTOR,             # Search owner's deck for a card matching tutor_filter and add to hand
	HARDCODED,         # Fall through to CombatScene._resolve_hardcoded(hardcoded_id, ctx)
	CONVERT_RESOURCE,  # Convert all of convert_from resource into convert_to, capped at target's max
	PURGE,             # Dispel all buffs from enemy target or cleanse all debuffs from friendly target; purge_filter narrows to a specific BuffType
}

enum TargetScope {
	NONE,                  # No target (hero/global effects use EffectType directly)
	SELF,                  # The minion that owns this effect (passive source)
	SINGLE_CHOSEN,          # Player-chosen enemy target; falls back to random if null (AI path)
	SINGLE_CHOSEN_FRIENDLY, # Player-chosen friendly target; falls back to random friendly if null
	SINGLE_RANDOM,         # One random minion from the base pool
	FILTERED_RANDOM,       # One random minion from the filtered pool
	ALL_ENEMY,             # All opposing board minions
	ALL_FRIENDLY,          # All friendly board minions
	ALL_BOARD,             # Every minion on both boards
	TRIGGER_MINION,        # The minion that caused the trap/aura to fire
	DEAD_MINION,           # The minion that just died (on-death passives)
	SINGLE_RANDOM_TRAP,    # One random entry in active_traps
	ALL_TRAPS,             # All entries in active_traps
	ACTIVE_ENVIRONMENT,    # The active environment card (if any)
	SINGLE_CHOSEN_TRAP_OR_ENV,  # ctx.chosen_object if set; falls back to random from traps+env
}

enum MinionFilter {
	NONE,        # No filter — all minions in pool qualify
	DEMON,
	HUMAN,
	SPIRIT,
	BEAST,
	VOID_IMP,    # Has "void_imp" tag
	FERAL_IMP,   # Has "feral_imp" tag
	CORRUPTED,   # Has at least one CORRUPTION buff stack
	IS_RUNE,     # Target is a TrapCardData with is_rune=true
}

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

@export var effect_type:   EffectType   = EffectType.DAMAGE_MINION
@export var scope:         TargetScope  = TargetScope.NONE
@export var filter:        MinionFilter = MinionFilter.NONE

## Numeric value used by the effect (damage, heal, buff amount, draw count, etc.)
@export var amount: int = 0

## Condition IDs that must ALL pass before this step executes.
## Evaluated per-target for minion-targeting effects, once globally for hero/global effects.
@export var conditions: Array[String] = []

## Source label applied to buff entries (e.g. "dominion_rune", "blood_pact").
@export var source_tag: String = ""

## Card ID used by SUMMON and ADD_CARD effects.
@export var card_id: String = ""

## If false, ATK/HP buffs are temporary (expire at turn end via TEMP_ATK).
@export var permanent: bool = true

## Optional scaling key. Resolved by EffectResolver._amount().
## "" = no scaling, "rune_aura" = × rune count, "void_marks" = × enemy void marks
## "board_count" = × count of minions matching multiplier_board/multiplier_filter/multiplier_tag;
##                 respects exclude_self for self-exclusion from the count.
@export var multiplier_key: String = ""

## Used with "board_count": which board to count — "friendly" or "enemy".
@export var multiplier_board: String = ""

## Used with "board_count": how to filter — "tag" (checks minion_tags) or "race" (checks minion_type).
## Leave empty to count all minions on the board side.
@export var multiplier_filter: String = ""

## Used with "board_count": the tag name or race name to match (e.g. "void_imp", "demon").
@export var multiplier_tag: String = ""

## Keyword enum value (Enums.Keyword) for GRANT_KEYWORD effects.
@export var keyword: int = -1

## Effect ID passed to CombatScene._resolve_hardcoded() for HARDCODED steps.
@export var hardcoded_id: String = ""

## Token stat overrides for SUMMON effects (0 = use template default).
@export var token_atk:    int = 0
@export var token_hp:     int = 0
@export var token_shield: int = 0

## CONVERT_RESOURCE: source resource ("mana" or "essence").
@export var convert_from: String = ""
## CONVERT_RESOURCE: destination resource ("mana" or "essence"). Conversion is capped at the destination's current max.
@export var convert_to: String = ""

## PURGE: optional Enums.BuffType name to target only that type (e.g. "CORRUPTION").
## Empty string = remove all buffs (dispel) or all debuffs (cleanse) depending on target ownership.
@export var purge_filter: String = ""

## When true, ctx.source is excluded from the resolved target pool (used for self-granting effects).
@export var exclude_self: bool = false

## TUTOR: filter key for deck search. "spark_cost" = void_spark_cost > 0, "rune" = is_rune.
@export var tutor_filter: String = ""

## Conditional bonus added on top of amount when ALL bonus_conditions pass.
## Checked globally (board state), not per-target. Use for "deal X, +Y if condition" on a single hit.
@export var bonus_amount: int = 0
@export var bonus_conditions: Array[String] = []

# ---------------------------------------------------------------------------
# Convenience factory
# ---------------------------------------------------------------------------

static func make(type: EffectType, scope: TargetScope = TargetScope.NONE, amount: int = 0) -> EffectStep:
	var s := EffectStep.new()
	s.effect_type = type
	s.scope       = scope
	s.amount      = amount
	return s

## Build an EffectStep from a plain Dictionary (used by CardDatabase for data-only definitions).
## Keys: "type", "scope", "filter", "amount", "permanent", "card_id", "source_tag",
##       "multiplier_key", "multiplier_board", "multiplier_filter", "multiplier_tag",
##       "conditions", "hardcoded_id", "keyword"
static func from_dict(d: Dictionary) -> EffectStep:
	var s := EffectStep.new()
	if "type"           in d: s.effect_type    = EffectType[d["type"]]
	if "scope"          in d: s.scope          = TargetScope[d["scope"]]
	if "filter"         in d: s.filter         = MinionFilter[d["filter"]]
	if "amount"         in d: s.amount         = d["amount"]
	if "permanent"      in d: s.permanent      = d["permanent"]
	if "card_id"        in d: s.card_id        = d["card_id"]
	if "source_tag"     in d: s.source_tag     = d["source_tag"]
	if "multiplier_key"    in d: s.multiplier_key    = d["multiplier_key"]
	if "multiplier_board"  in d: s.multiplier_board  = d["multiplier_board"]
	if "multiplier_filter" in d: s.multiplier_filter = d["multiplier_filter"]
	if "multiplier_tag"    in d: s.multiplier_tag    = d["multiplier_tag"]
	if "conditions"     in d:
		var conds: Array[String] = []
		conds.assign(d["conditions"])
		s.conditions = conds
	if "hardcoded_id"   in d: s.hardcoded_id   = d["hardcoded_id"]
	if "keyword"        in d: s.keyword        = Enums.Keyword[d["keyword"]]
	if "token_atk"      in d: s.token_atk      = d["token_atk"]
	if "token_hp"       in d: s.token_hp       = d["token_hp"]
	if "token_shield"   in d: s.token_shield   = d["token_shield"]
	if "convert_from"   in d: s.convert_from   = d["convert_from"]
	if "convert_to"     in d: s.convert_to     = d["convert_to"]
	if "purge_filter"   in d: s.purge_filter   = d["purge_filter"]
	if "exclude_self"   in d: s.exclude_self   = d["exclude_self"]
	if "tutor_filter"   in d: s.tutor_filter   = d["tutor_filter"]
	if "bonus_amount"   in d: s.bonus_amount   = d["bonus_amount"]
	if "bonus_conditions" in d:
		var bc: Array[String] = []
		bc.assign(d["bonus_conditions"])
		s.bonus_conditions = bc
	return s
