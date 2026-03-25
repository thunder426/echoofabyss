## MatriarchProfile.gd
## Extends FeralPackProfile with a survival Pack Frenzy condition.
##
## In addition to the base conditions (lethal OR ≥ 3 Feral Imps on board),
## the Matriarch will also cast Pack Frenzy when her HP is low and Ancient
## Frenzy is active, using the SWIFT + Lifedrain combo to clear the player
## board and leech HP back.
##
## Survival condition (all must be true):
##   • Enemy HP ≤ LOW_HP_THRESHOLD (40 % of her 3000 max = 1200)
##   • Ancient Frenzy is active (grants Lifedrain on Pack Frenzy)
##   • Player has ≥ 1 minion on board (targets for SWIFT imps to hit)
##   • ≥ 2 Feral Imps on the Matriarch's board (any attack state —
##     Pack Frenzy grants SWIFT so even EXHAUSTED imps get new attacks)
##   • Pack Frenzy is affordable this turn
class_name MatriarchProfile
extends FeralPackProfile

## HP below which the survival Pack Frenzy activates (×100 scale — 1200 = 12 displayed HP).
const LOW_HP_THRESHOLD := 1200

## Minimum Feral Imps on board to trigger survival mode (lower than value threshold).
const SURVIVAL_IMP_MIN := 2

func _should_cast_pack_frenzy() -> bool:
	# Original conditions: lethal available OR value threshold (≥ 3 imps)
	if super._should_cast_pack_frenzy():
		return true
	# Survival condition: low HP, Lifedrain active, can leech back
	if agent.friendly_hp > LOW_HP_THRESHOLD:
		return false
	if not _has_ancient_frenzy():
		return false
	if agent.opponent_board.is_empty():
		return false
	var pf := _find_pack_frenzy()
	if pf == null or agent.effective_spell_cost(pf) > agent.mana:
		return false
	var feral_count := 0
	for m in agent.friendly_board:
		if _is_feral_imp(m):
			feral_count += 1
	return feral_count >= SURVIVAL_IMP_MIN

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns true when the encounter has the ancient_frenzy passive active,
## meaning Pack Frenzy also grants Lifedrain to all Feral Imps.
func _has_ancient_frenzy() -> bool:
	if agent.scene == null:
		return false
	var passives = agent.scene.get("_active_enemy_passives")
	if passives == null:
		return false
	return "ancient_frenzy" in (passives as Array)
