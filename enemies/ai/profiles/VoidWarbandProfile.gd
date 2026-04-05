## VoidWarbandProfile.gd
## AI profile for the Void Warband encounter (Act 4, Fight 11).
##
## Passive: void_might (shared) + spirit_conscription (first void_spirit
## summoned each turn spawns a free 100/100 Void Spark on the enemy board).
##
## Strategy: Lead with one spirit summon each turn to trigger conscription
## and generate a free Void Spark for fuel, then flood the board with
## remaining minions and spend sparks aggressively.
##
## Play order:
##   1. One spirit (triggers conscription → free Void Spark)
##   2. Remaining regular minions (spirits, heralds)
##   3. Regular mana spells
##   4. Spark-cost spells (Rift Collapse for AoE, Void Pulse for draw)
##   5. Spark-cost minions (Bastion Colossus, Void Behemoth, Phase Stalker)
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7
class_name VoidWarbandProfile
extends VoidScoutProfile

func play_phase() -> void:
	# Phase 1: Play one spirit to trigger spirit_conscription (free Void Spark)
	await _play_one_spirit()
	if not agent.is_alive(): return
	# Phase 2: Remaining regular minions
	await _play_regular_minions()
	if not agent.is_alive(): return
	# Phase 3: Mana spells
	await _play_spells_pass()
	if not agent.is_alive(): return
	# Phase 4: Spark-cost spells
	await _play_spark_spells()
	if not agent.is_alive(): return
	# Phase 5: Spark-cost minions
	await _play_spark_minions()

# ---------------------------------------------------------------------------
# Spirit-first helper
# ---------------------------------------------------------------------------

## Play exactly one void_spirit minion (cheapest) to trigger spirit_conscription.
func _play_one_spirit() -> void:
	var candidates: Array[CardInstance] = []
	for inst in agent.hand:
		if not (inst.card_data is MinionCardData):
			continue
		var mc := inst.card_data as MinionCardData
		if mc.void_spark_cost > 0:
			continue
		if not ("void_spirit" in mc.minion_tags):
			continue
		candidates.append(inst)
	candidates.sort_custom(agent.sort_by_total_cost)
	for inst in candidates:
		var mc := inst.card_data as MinionCardData
		var mana_cost: int = agent.effective_minion_mana_cost(mc)
		if mc.essence_cost > agent.essence or mana_cost > agent.mana:
			continue
		var slot: BoardSlot = agent.find_empty_slot()
		if slot == null:
			return
		agent.essence -= mc.essence_cost
		agent.mana    -= mana_cost
		await agent.commit_play_minion(inst, slot, pick_on_play_target(mc))
		return  # Only play ONE spirit for conscription
