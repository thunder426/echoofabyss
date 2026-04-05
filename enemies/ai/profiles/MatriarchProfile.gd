## MatriarchProfile.gd
## Extends FeralPackProfile with custom resource growth and loosened Pack Frenzy conditions.
##
## Resource growth: mana-first to enable early Pack Frenzy / brood_call,
## then alternates essence and mana for mid-game board presence.
##   Turn sequence: M→2, E→4, M→4, E→5, M→6
##
## Pack Frenzy conditions (loosened from base):
##   • Original: ≥ 3 feral imps OR lethal
##   • Matriarch: ≥ 2 feral imps OR lethal
##   (With ancient_frenzy passive, Pack Frenzy costs 2M instead of 3M)
##
## Survival condition (all must be true):
##   • Enemy HP ≤ 40% of max (1200 of 3000)
##   • Ancient Frenzy is active (grants Lifedrain on Pack Frenzy)
##   • Player has ≥ 1 minion on board (targets for SWIFT imps to hit)
##   • ≥ 2 Feral Imps on the Matriarch's board
##   • Pack Frenzy is affordable this turn
class_name MatriarchProfile
extends FeralPackProfile

## HP below which the survival Pack Frenzy activates.
const LOW_HP_THRESHOLD := 1200

## Minimum Feral Imps on board to cast Pack Frenzy (loosened from 3 to 2).
const MATRIARCH_FERAL_THRESHOLD := 2

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		if turn <= 1:
			return
		var e: int = sim_state.enemy_essence_max
		var m: int = sim_state.enemy_mana_max
		if e + m >= 11:
			return
		# Mana to 2 first (enables brood_call turn 2, pack_frenzy turn 3 with ancient_frenzy)
		if m < 2:
			sim_state.enemy_mana_max += 1
		# Essence to 4 (board presence with imp_brawler, frenzied_imp)
		elif e < 4:
			sim_state.enemy_essence_max += 1
		# Mana to 4 (comfortable pack_frenzy casting, double brood_call)
		elif m < 4:
			sim_state.enemy_mana_max += 1
		# Essence to 5
		elif e < 5:
			sim_state.enemy_essence_max += 1
		# Mana to 6
		elif m < 6:
			sim_state.enemy_mana_max += 1
		else:
			sim_state.enemy_essence_max += 1

func _should_cast_pack_frenzy() -> bool:
	var pf := _find_pack_frenzy()
	if pf == null or agent.effective_spell_cost(pf.card_data as SpellCardData) > agent.mana:
		return false
	# Lethal check
	if _calc_lethal_with_pack_frenzy() >= agent.opponent_hp:
		return true
	# Loosened threshold: cast with ≥ 2 feral imps (base requires 3)
	var feral_count := 0
	for m in agent.friendly_board:
		if _is_feral_imp(m):
			feral_count += 1
	if feral_count >= MATRIARCH_FERAL_THRESHOLD:
		return true
	# Survival condition: low HP + Lifedrain combo
	if agent.friendly_hp <= LOW_HP_THRESHOLD and _has_ancient_frenzy():
		if not agent.opponent_board.is_empty() and feral_count >= 2:
			return true
	return false

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
