## MinionCardData.gd
## Card data for Minion type cards.
## Minions cost Abyss Essence and occupy board slots.
## Combat uses ATK / HP — HP reaching 0 means the minion is destroyed.
class_name MinionCardData
extends CardData

## Abyss Essence cost to play this minion
@export var essence_cost: int = 1

## Additional Mana cost (0 = pure-essence minion; dual-cost minions need both)
@export var mana_cost: int = 0

## Base attack value
@export var atk: int = 1

## Damage school applied to this minion's BASIC ATTACK (the attack action that
## happens on its turn — not on-play / on-death effect steps, which carry their
## own per-step `damage_school`). NONE means physical/untyped — current default
## for almost every minion. Set this when a card's basic attack should be tagged
## as VOID, VOID_BOLT, etc. for school-aware damage modifiers, audit trails, or
## future cleanse/dispel rules. Override-friendly via talent_overrides.
@export var attack_damage_school: Enums.DamageSchool = Enums.DamageSchool.NONE

## Hit points — minion is destroyed when this reaches 0
@export var health: int = 1

## Maximum Shield value (0 = no shield). Shield absorbs damage before HP.
## Physical shields (no SHIELD_REGEN keyword) do not regenerate.
## Magic shields (SHIELD_REGEN_1/2) regenerate at the start of the owner's turn.
@export var shield_max: int = 0

## Korrath — base Armour. Reduces incoming physical (DamageSource.MINION) damage with a
## min-100 floor; spells bypass it entirely. 0 means the card has no armour stat (no
## armour math runs against it). Mutated at runtime via MinionInstance.add_armour() so
## branch-1 T3 doubling can be centralized in one place.
@export var armour: int = 0

## Sub-type tag used for synergy triggers (e.g. "all your Demons gain +100 ATK")
@export var minion_type: Enums.MinionType = Enums.MinionType.DEMON

## Korrath B2 — secondary race tags. Most minions have a single race (`minion_type`).
## Multi-race minions (e.g. Abyssal Knight under runic_transcendence becomes Human +
## Demon) list extra races here. ALL race-aware code must read via `is_race(type)` so
## the primary and the extras are checked together; never compare `minion_type` directly.
@export var extra_minion_types: Array[int] = []

## True if this card carries the given race — either as `minion_type` or in
## `extra_minion_types`. Replaces every `minion_type == X` comparison in the codebase.
func is_race(type: int) -> bool:
	if minion_type == type:
		return true
	return type in extra_minion_types

## True if this card and `other` share at least one race. Used by Korrath FORMATION
## (which fires when adjacent minions share a race) so a multi-race knight matches both
## Human and Demon partners.
func shares_race(other: MinionCardData) -> bool:
	if other == null:
		return false
	if is_race(other.minion_type):
		return true
	for t in other.extra_minion_types:
		if is_race(t):
			return true
	return false

## Keywords this minion has (e.g. [Enums.Keyword.TAUNT, Enums.Keyword.RUSH])
@export var keywords: Array[int] = []

## If true, playing this card from hand requires the player to select a target first.
@export var on_play_requires_target: bool = false

## If true, the on-play target is OPTIONAL — the player may click a valid target
## to resolve the effect, or click an empty board slot to summon without it.
## Mutually exclusive with on_play_requires_target (optional wins if both set).
@export var on_play_target_optional: bool = false

## Valid target type when on_play_requires_target OR on_play_target_optional is true.
## Mirrors SpellCardData.target_type — e.g. "enemy_minion", "corrupted_enemy_minion",
## "friendly_minion", "friendly_minion_other", "friendly_demon".
@export var on_play_target_type: String = ""

## Alert text shown at the top of the screen during target selection. If empty,
## no alert is shown. Use short, action-oriented phrasing — e.g.
## "Click a Demon to transform, or click a slot to summon without effect."
@export var on_play_target_prompt: String = ""

## Declarative effect steps fired when this minion is played from hand (On Play).
## Uses EffectResolver. Does NOT fire when summoned by a spell, trap, or other effect.
@export var on_play_effect_steps: Array = []

## Effect triggered when this minion is destroyed (On Death).
@export var on_death_effect: String = ""

## Declarative effect steps fired when this minion is destroyed (On Death).
## Uses EffectResolver. Runs in addition to the legacy on_death_effect string.
@export var on_death_effect_steps: Array = []

## Persistent board passive effect ID. Resolved by CombatScene whenever a
## friendly minion dies or a friendly minion is summoned. Empty = no passive.
@export var passive_effect_id: String = ""

## Effect ID resolved when the player casts any spell while this minion is on board.
## E.g. "add_void_bolt_on_spell" for Void Archmagus.
@export var on_spell_cast_passive_effect_id: String = ""

## Effect ID resolved each time _deal_void_bolt_damage fires while this minion is on board.
## E.g. "void_mark_per_channeler" for Void Channeler.
@export var on_void_bolt_passive_effect_id: String = ""

## Declarative effect steps fired at the start of the owner's turn while this minion is on board.
## Uses EffectResolver with the minion as ctx.source.
@export var on_turn_start_effect_steps: Array = []

## Declarative effect steps fired at the end of the owner's turn while this minion is on board.
## Uses EffectResolver with the minion as ctx.source.
@export var on_turn_end_effect_steps: Array = []

## Declarative effect steps fired when this minion kills an enemy minion (i.e. is the attacker
## in an ON_ENEMY_MINION_DIED event). Uses EffectResolver with the killing minion as ctx.source
## and the dead minion as ctx.dead_minion.
@export var on_kill_effect_steps: Array = []

## Declarative effect steps fired when this minion is sacrificed (ON LEAVE). Sacrifice is a
## ritual removal — distinct from death — so on_death_effect_steps do NOT fire on sacrifice.
## Uses EffectResolver with the leaving minion as ctx.source. Fires while the minion is still
## on its slot, before the silent removal.
@export var on_leave_effect_steps: Array = []

## Presence aura steps. While this minion is on the board, the steps below are recomputed
## whenever any minion on either side enters or leaves play. The recompute strips every
## buff matching the steps' source_tag from this minion's side, then re-runs the steps with
## ctx.owner = this minion's side. Use multiplier_key="board_count" to scale the buff with
## the number of sources on the same side. Cleared automatically when the minion leaves.
##
## Example — Rogue Imp Elder grants +100 ATK per Elder to every friendly Feral Imp:
##   {"type": "BUFF_ATK", "scope": "ALL_FRIENDLY", "filter": "FERAL_IMP",
##    "amount": 100, "source_tag": "rogue_imp_elder_aura",
##    "multiplier_key": "board_count", "multiplier_board": "friendly",
##    "multiplier_filter": "tag", "multiplier_tag": "rogue_imp_elder"}
@export var presence_aura_steps: Array = []

## Reduces the Mana cost of all player spells by this amount while this minion is on board.
## Multiple minions stack (e.g. two Archmagus = -2). Floor is 0.
@export var mana_cost_discount: int = 0

## Korrath FORMATION — declarative effect steps fired the first time this minion ends up
## adjacent to another minion of the same race. Each unique partner is one Formation
## trigger; the pair is tracked on MinionInstance.formation_partners so it cannot re-fire
## even if adjacency is broken and reformed. EffectResolver runs these with ctx.source =
## this minion. Empty = the FORMATION keyword fires no steps (still tracks pair tagging).
@export var formation_effect_steps: Array = []

## Family / synergy tags used for data-driven queries instead of hardcoded card ID checks.
## Examples: "void_imp", "base_void_imp", "senior_void_imp", "void_champion", "imp_overseer".
## Add all applicable tags; CombatScene queries with _minion_has_tag() / _card_has_tag().
@export var minion_tags: Array[String] = []

## Player-facing clan label shown as "Clan: <name>" in the keyword panel and description line.
## Clans group minions that share synergy. Empty = no clan displayed.
@export var clan: String = ""

## If true, this card is a champion that can be auto-summoned when its condition is met.
@export var is_champion: bool = false

## Condition type for auto-summon. Currently supported: "board_tag_count".
@export var auto_summon_condition: String = ""

## For "board_tag_count": the minion tag to count on the player board.
@export var auto_summon_tag: String = ""

## For "board_tag_count": the minimum count needed to trigger auto-summon.
@export var auto_summon_threshold: int = 0

## Void Spark value when this minion is consumed to pay spark costs.
## 0 = cannot be consumed as spark fuel. Void Spirit clan minions have values 1–4.
@export var spark_value: int = 0

func _init() -> void:
	card_type = Enums.CardType.MINION
