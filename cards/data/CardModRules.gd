## CardModRules.gd
## Filter-matched conditional card-data deltas, applied at combat construction
## time inside CardDatabase.get_card_for_combat().
##
## Where this fits vs. CardData.talent_overrides:
##   - talent_overrides: per-card replacements ("under this talent, this specific
##     card looks like X"). Lives on the card. Overwrite semantics.
##   - CardModRules: clan/filter-wide deltas ("under this condition, every card
##     matching this filter gets +X stats"). Lives in this table. Additive
##     (deltas stack across rules and survive across cards by tag, not by id).
##
## Composition order in get_card_for_combat:
##   1. talent_overrides apply first (replacement on the duplicate).
##   2. CardModRules apply second as deltas on the (possibly-overridden) values.
## This way a per-card override defines the new "base" and clan rules stack on top.
##
## Adding a rule = appending to RULES below. Adding a card to a clan = giving
## the card the right tag in CardDatabase. No code change needed in either case.
class_name CardModRules
extends RefCounted

## Each rule is a Dictionary with:
##   "id":     debug label (string)
##   "when":   condition dict — currently supports keys:
##                 "talent":        <talent_id>      (player talent unlocked)
##                 "hero_passive":  <passive_id>     (player hero passive active)
##                 "enemy_passive": <passive_id>     (enemy passive active)
##             Multiple keys are AND-combined.
##   "filter": match dict — currently supports keys:
##                 "tag":          <tag_string>     (card has minion_tag)
##                 "minion_type":  <Enums.MinionType key string>
##                 "clan":         <clan_string>    (exact clan match)
##             Multiple keys are AND-combined. All filters require the card to
##             be a MinionCardData (no spell/trap clan rules today).
##   "atk_delta":  int (optional)
##   "hp_delta":   int (optional, applied to base health)
##   "cost_delta": int (optional, floored at 0)
##
## Side semantics: condition checks always read from the CARD'S OWNING SIDE.
## Player cards check player talents/passives; enemy cards check enemy passives.
## Cross-side rules are not modeled (no use case yet).
const RULES: Array = [
	# Lord Vael hero passive — every Void Imp clan card baseline +100/+100.
	# Was on_summon_passive_void_imp_boost handler (BuffSystem ATK + direct HP);
	# migrated to base stats so cleanse/dispel cannot strip the talent baseline.
	{
		"id":        "void_imp_boost",
		"when":      { "hero_passive": "void_imp_boost" },
		"filter":    { "tag": "void_imp" },
		"atk_delta": 100,
		"hp_delta":  100,
	},
	# Lord Vael Endless Tide T1 — Void Imp clan +100 HP.
	# Was on_summon_swarm_discipline handler; migrated to base HP.
	{
		"id":       "swarm_discipline",
		"when":     { "talent": "swarm_discipline" },
		"filter":   { "tag": "void_imp" },
		"hp_delta": 100,
	},
]

## Returns the list of rules that match the given filter context. Side is
## "player" or "enemy" — controls which talent/passive arrays are read off ctx.
static func matching_rules(card: CardData, side: String, talents: Array[String],
		hero_passives: Array[String], enemy_passives: Array[String]) -> Array:
	var out: Array = []
	for rule_any in RULES:
		var rule: Dictionary = rule_any
		if not _condition_active(rule.get("when", {}), side, talents, hero_passives, enemy_passives):
			continue
		if not _filter_matches(rule.get("filter", {}), card):
			continue
		out.append(rule)
	return out

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _condition_active(when_dict: Dictionary, side: String,
		talents: Array[String], hero_passives: Array[String],
		enemy_passives: Array[String]) -> bool:
	if when_dict.is_empty():
		return false  # no condition = never fires; rules must declare intent
	for key in when_dict:
		var needed: String = when_dict[key]
		match key:
			"talent":
				# Player-side only — enemies have no talents today.
				if side != "player" or not (needed in talents):
					return false
			"hero_passive":
				# Player-side only — enemy hero passives are modeled separately.
				if side != "player" or not (needed in hero_passives):
					return false
			"enemy_passive":
				# Enemy-side only.
				if side != "enemy" or not (needed in enemy_passives):
					return false
			_:
				push_warning("CardModRules: unknown 'when' key '%s'" % key)
				return false
	return true

static func _filter_matches(filter: Dictionary, card: CardData) -> bool:
	if filter.is_empty():
		return false  # no filter = match nothing; rules must declare intent
	if not (card is MinionCardData):
		return false
	var mc: MinionCardData = card
	for key in filter:
		var needed: String = filter[key]
		match key:
			"tag":
				if not (needed in mc.minion_tags):
					return false
			"minion_type":
				# String like "DEMON" → Enums.MinionType.DEMON
				if not (needed in Enums.MinionType):
					push_warning("CardModRules: unknown minion_type '%s'" % needed)
					return false
				if mc.minion_type != Enums.MinionType[needed]:
					return false
			"clan":
				if mc.clan != needed:
					return false
			_:
				push_warning("CardModRules: unknown 'filter' key '%s'" % key)
				return false
	return true
