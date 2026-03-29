## ScoredMatriarchProfile.gd
## Scored AI profile for the Imp Matriarch boss.
## Extends ScoredFeralPackProfile with survival Pack Frenzy condition:
##   • Low HP + Ancient Frenzy active → cast Pack Frenzy for Lifedrain combo
class_name ScoredMatriarchProfile
extends ScoredFeralPackProfile

const LOW_HP_THRESHOLD := 1200
const SURVIVAL_IMP_MIN := 2

func _should_cast_pack_frenzy() -> bool:
	if super._should_cast_pack_frenzy():
		return true
	# Survival condition: low HP + Ancient Frenzy + targets to leech
	if agent.friendly_hp > LOW_HP_THRESHOLD:
		return false
	if not _has_ancient_frenzy():
		return false
	if agent.opponent_board.is_empty():
		return false
	var pf := _find_pack_frenzy()
	if pf == null or agent.effective_spell_cost(pf.card_data as SpellCardData) > agent.mana:
		return false
	var feral_count := 0
	for m in agent.friendly_board:
		if _is_feral_imp(m):
			feral_count += 1
	return feral_count >= SURVIVAL_IMP_MIN

func _has_ancient_frenzy() -> bool:
	if agent.scene == null:
		return false
	var passives = agent.scene.get("_active_enemy_passives")
	if passives == null:
		return false
	return "ancient_frenzy" in (passives as Array)
