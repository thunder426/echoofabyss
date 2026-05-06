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
##                 NOTE: this is a CLAN-WIDE deck-build adjustment baked into the card's
##                 essence_cost / cost field at construction. Distinct from the per-copy
##                 CardInstance.mana_delta / essence_delta used for runtime "this turn"
##                 discounts (rune_caller, Fiendish Pact). Different system, similar name.
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
	# Lord Vael Void Resonance T2 — every Void Imp clan death deals 100 Void Bolt.
	# Was on_player_minion_died_death_bolt handler. Migrated to clan-wide step
	# injection: each Void Imp clan card gets a VOID_BOLT step appended to its
	# on_death_effect_steps, plus a description postfix so the in-hand text shows
	# the talent's contribution. Stacks naturally with the card's own on-death
	# effects (Imp Vessel still summons 2 Void Imps AND fires the bolt).
	{
		"id":   "death_bolt",
		"when": { "talent": "death_bolt" },
		"filter": { "tag": "void_imp" },
		"append_on_death_effect_steps": [
			{"type": "VOID_BOLT", "amount": 100},
		],
		"append_description": "\nON DEATH: Deal 100 Void Bolt damage to enemy hero.",
	},
	# Lord Vael Void Resonance T3 (capstone) — Void Imp clan basic attacks deal
	# Void Bolt damage. Pure school tag on the attack DamageInfo; routes through
	# the standard attack pipeline so lifedrain/siphon/crit work correctly.
	# Was a special-case bypass in CombatInputHandler that skipped those hooks
	# and routed through _deal_void_bolt_damage instead.
	{
		"id":   "void_manifestation",
		"when": { "talent": "void_manifestation" },
		"filter": { "tag": "void_imp" },
		"set_attack_damage_school": Enums.DamageSchool.VOID_BOLT,
		"append_description": "\nBasic attacks deal Void Bolt damage.",
	},
	# Lord Vael Endless Tide T0 — Imp Evolution. Playing a base Void Imp adds a
	# Senior Void Imp to your hand (1/turn). Was on_summon_imp_evolution handler
	# (gated on imp_evolution_used_this_turn). Migrated to ADD_CARD step gated by
	# the generic "once_per_turn" condition. NOTE: original handler fired on summon
	# (any path); this fires on PLAY only. No card token-summons base Void Imps as
	# of this migration, so the practical behavior is identical.
	{
		"id":     "imp_evolution",
		"when":   { "talent": "imp_evolution" },
		"filter": { "tag": "base_void_imp" },
		"append_on_play_effect_steps": [
			{"type": "ADD_CARD", "card_id": "senior_void_imp",
			 "conditions": ["once_per_turn:imp_evolution"]},
		],
		"append_description": "\nIMP EVOLUTION: First Void Imp played each turn adds a Senior Void Imp to your hand.",
	},
	# Lord Vael Endless Tide T2 — Imp Warband. Playing a Senior Void Imp grants
	# +50 ATK to all OTHER Void Imp clan minions on the friendly board. Was
	# on_summon_imp_warband handler. Migrated to BUFF_ATK step on Senior's on-play.
	# Same summon-vs-play caveat as imp_evolution: no card token-summons Seniors today.
	{
		"id":     "imp_warband",
		"when":   { "talent": "imp_warband" },
		"filter": { "tag": "senior_void_imp" },
		"append_on_play_effect_steps": [
			{"type": "BUFF_ATK", "scope": "ALL_FRIENDLY", "filter": "VOID_IMP",
			 "amount": 50, "permanent": true, "source_tag": "imp_warband",
			 "exclude_self": true},
		],
		"append_description": "\nIMP WARBAND: All other Void Imp Clan minions gain +50 ATK.",
	},
	# Lord Vael Rune Master T0 — Rune Caller. Playing a base Void Imp tutors a
	# random Rune from deck, discounted by 1 Mana this turn. Was on_played_rune_caller
	# handler calling scene._draw_rune_from_deck. Migrated to TUTOR + MOD_LAST_ADDED_COST
	# pair: TUTOR pulls a rune from deck, MOD_LAST_ADDED_COST writes mana_delta = -1
	# on the just-tutored CardInstance. Both delta and the once-per-cast linkage live
	# in EffectContext.last_added_instance.
	# TUTOR is deck-order, not uniform-random — for a freshly shuffled deck this is
	# statistically equivalent to "random rune from deck"; mid-combat after draws/burns
	# the distributions diverge slightly but not in a player-detectable way.
	{
		"id":     "rune_caller",
		"when":   { "talent": "rune_caller" },
		"filter": { "tag": "base_void_imp" },
		"append_on_play_effect_steps": [
			{"type": "TUTOR", "tutor_filter": "rune", "amount": 1},
			{"type": "MOD_LAST_ADDED_COST", "amount": -1, "resource": "mana"},
		],
		"append_description": "\nRUNE CALLER: Draw a Rune from your deck. It costs 1 less Mana this turn.",
	},
	# Seris Fleshcraft T0 — Flesh Infusion. Playing a Grafted Fiend from hand spends
	# 1 Flesh to grant +200 ATK permanent. Was on_played_flesh_infusion handler.
	# Migrated to clan-wide on-play step injection: SPEND_FLESH gates the BUFF_ATK
	# via the standard "flesh_spent_this_cast" condition (same pattern as Mend the
	# Flesh / Flesh-Stitched Horror). Fires only on hand play (on_play_effect_steps),
	# not on Soul Forge token summons — same semantics as the original handler which
	# listened on ON_PLAYER_MINION_PLAYED, not ON_PLAYER_MINION_SUMMONED.
	# Filter is the "grafted_fiend" tag, so Grafted Reaver / Flesh Scout / Matron of
	# Flesh inherit the same buff (matching the original _has_tag check).
	{
		"id":     "flesh_infusion",
		"when":   { "talent": "flesh_infusion" },
		"filter": { "tag": "grafted_fiend" },
		"append_on_play_effect_steps": [
			{"type": "SPEND_FLESH", "amount": 1},
			{"type": "BUFF_ATK", "scope": "SELF", "amount": 200, "permanent": true,
			 "source_tag": "flesh_infusion", "conditions": ["flesh_spent_this_cast"]},
		],
		# Two-part talent: declarative on-play half (above) + non-declarative
		# on-kill half (CombatState._add_kill_stacks under has_talent flesh_infusion).
		# Both halves are described here so the card reads end-to-end after talent.
		"append_description": "\nON PLAY: Spend 1 Flesh: gain +200 ATK.\nWhenever this minion kills an enemy minion, gain +100 ATK and +100 HP.",
	},
	# Seris Fleshcraft T2 — Predatory Surge. Grafted Fiend tagged minions enter with
	# Swift. Was on_summon_predatory_surge handler that flipped MinionState to SWIFT.
	# Migrated by adding SWIFT to the card's keywords array — MinionInstance.create
	# already converts EXHAUSTED→SWIFT for cards with the keyword, so behavior is
	# identical for both hand play and token summons (which is correct: predatory_surge
	# was on ON_PLAYER_MINION_SUMMONED, covering all summon paths).
	# The "3 kill stacks → Siphon" half lives on under flesh_infusion's
	# on_enemy_died_grafted_constitution handler (kill_stacks counter is non-declarative).
	{
		"id":     "predatory_surge",
		"when":   { "talent": "predatory_surge" },
		"filter": { "tag": "grafted_fiend" },
		"append_keywords": [Enums.Keyword.SWIFT],
		# Two-part talent: declarative SWIFT keyword (above) + non-declarative
		# Siphon-at-3-kill_stacks half (CombatState._add_kill_stacks under has_talent
		# predatory_surge). SWIFT is shown via the keyword field per CARD_DESCRIPTION_STYLE
		# rule #39, so the description only carries the non-keyword on-kill clause.
		"append_description": "\nAfter killing 3 enemy minions, gain SIPHON.",
	},
	# Korrath hero passive — Abyssal Commander. Knight's essence_cost reduced by 1
	# (4 → 3) for the entire combat. Baked at construction time so the discount is
	# permanent within a run, distinct from per-copy CardInstance.essence_delta
	# (which is reserved for per-cast "this turn" discounts like fiendish_pact).
	{
		"id":         "abyssal_commander",
		"when":       { "hero_passive": "abyssal_commander" },
		"filter":     { "tag": "abyssal_knight" },
		"cost_delta": -1,
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
