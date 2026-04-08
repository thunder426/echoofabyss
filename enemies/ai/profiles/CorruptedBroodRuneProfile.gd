## CorruptedBroodRuneProfile.gd
## AI profile for the Corrupted Broodlings — Rune variant.
##
## Tempo deck with runes for sustained value.
## Play order: flux siphon → minions → runes (dominion > void > blood) → sacrifice → screech
## Sacrifice targets: void_spark first, brood_imp second, never other minions.
## Screech only when 3+ feral imps on board.
##
## Resource growth: 2E → 2M → 6E → 4M → 7E
class_name CorruptedBroodRuneProfile
extends CombatProfile

const _RUNE_ORDER: Array[String] = ["dominion_rune", "void_rune", "blood_rune"]

func _is_aggro() -> bool:
	return true

func play_phase() -> void:
	# 1. Flux Siphon — convert spare mana to essence if it helps summon
	if _should_flux():
		await _play_spell_by_id("flux_siphon")
		if not agent.is_alive(): return
	# 2. Minions — cheapest first
	await _play_minions_pass()
	if not agent.is_alive(): return
	# 3. Runes — dominion > void > blood, skip if already active
	for rune_id in _RUNE_ORDER:
		if not _has_active_rune(rune_id):
			await _play_trap_by_id(rune_id)
			if not agent.is_alive(): return
	# 4. Abyssal Sacrifice — on spark or brood_imp only
	if _has_sac_target():
		await _play_spell_by_id("abyssal_sacrifice")
		if not agent.is_alive(): return
	# 5. Remaining spells (screech with gate, feral_surge)
	await _play_spells_pass()
	if not agent.is_alive(): return
	# 6. Remaining traps
	await _play_traps_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"void_screech":      {"cast_if": "has_3_feral_imps"},
		"feral_surge":       {"cast_if": "has_friendly_tag", "tag": "feral_imp"},
		"flux_siphon":       {"cast_if": "never"},  # handled manually in play_phase
		"abyssal_sacrifice": {"cast_if": "never"},   # handled manually in play_phase
	}

## Only cast screech with 3+ feral imps.
func can_cast_spell(spell: SpellCardData) -> bool:
	if spell.id == "void_screech":
		return _count_board_feral_imps() >= 3
	if spell.id == "flux_siphon":
		return false  # handled manually
	if spell.id == "abyssal_sacrifice":
		return false  # handled manually
	return super.can_cast_spell(spell)

## Sacrifice target: void_spark first, brood_imp second, nothing else.
func pick_spell_target(spell: SpellCardData):
	if spell.id == "abyssal_sacrifice":
		return _pick_sac_target()
	return super.pick_spell_target(spell)

## Resource growth: 2E → 2M → 6E → 4M → 7E
func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		if turn <= 1:
			return
		var e: int = sim_state.enemy_essence_max
		var m: int = sim_state.enemy_mana_max
		if e + m >= 11:
			return
		if e < 2:
			sim_state.enemy_essence_max += 1
		elif m < 2:
			sim_state.enemy_mana_max += 1
		elif e < 6:
			sim_state.enemy_essence_max += 1
		elif m < 4:
			sim_state.enemy_mana_max += 1
		else:
			sim_state.enemy_essence_max += 1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _count_board_feral_imps() -> int:
	var count := 0
	for m in agent.friendly_board:
		if _minion_has_tag(m, "feral_imp"):
			count += 1
	return count

func _minion_has_tag(m: MinionInstance, tag: String) -> bool:
	return agent.scene != null and agent.scene._minion_has_tag(m, tag)

## Check if flux siphon would help: have mana to spare AND a minion in hand
## that costs more essence than we currently have.
func _should_flux() -> bool:
	if agent.mana <= 0:
		return false
	var has_flux := false
	for inst in agent.hand:
		if inst.card_data is SpellCardData and inst.card_data.id == "flux_siphon":
			has_flux = true
			break
	if not has_flux:
		return false
	# Check if converting mana would let us play an extra minion
	for inst in agent.hand:
		if inst.card_data is MinionCardData:
			var mc := inst.card_data as MinionCardData
			if mc.essence_cost > agent.essence and mc.essence_cost <= agent.essence + mini(agent.mana, 3):
				return true
	return false

## Check if a valid sacrifice target exists.
func _has_sac_target() -> bool:
	# Need sac in hand and affordable
	var has_sac := false
	for inst in agent.hand:
		if inst.card_data is SpellCardData and inst.card_data.id == "abyssal_sacrifice":
			if agent.effective_spell_cost(inst.card_data as SpellCardData) <= agent.mana:
				has_sac = true
				break
	if not has_sac:
		return false
	return _pick_sac_target() != null

## Pick sacrifice target: void_spark first, brood_imp second.
func _pick_sac_target() -> MinionInstance:
	# Priority 1: void_spark
	for m in agent.friendly_board:
		if m.card_data is MinionCardData and (m.card_data as MinionCardData).id == "void_spark":
			return m
	# Priority 2: brood_imp
	for m in agent.friendly_board:
		if m.card_data is MinionCardData and (m.card_data as MinionCardData).id == "brood_imp":
			return m
	return null

## Check if a specific rune is already active.
func _has_active_rune(rune_id: String) -> bool:
	if agent.scene == null:
		return false
	var traps: Variant = agent.scene.get("enemy_active_traps")
	if traps == null:
		traps = agent.scene.get("active_traps")
	if traps == null:
		return false
	for t in (traps as Array):
		if t is TrapCardData and (t as TrapCardData).id == rune_id:
			return true
	return false

## Play a specific spell by ID if in hand and affordable.
func _play_spell_by_id(spell_id: String) -> void:
	for inst in agent.hand.duplicate():
		if not (inst.card_data is SpellCardData):
			continue
		if inst.card_data.id != spell_id:
			continue
		var cost: int = agent.effective_spell_cost(inst.card_data as SpellCardData)
		if cost > agent.mana:
			continue
		agent.mana -= cost
		var target = pick_spell_target(inst.card_data as SpellCardData)
		if not await agent.commit_play_spell(inst, target):
			return
		return

## Play a specific trap by ID if in hand and affordable.
func _play_trap_by_id(trap_id: String) -> void:
	for inst in agent.hand.duplicate():
		if not (inst.card_data is TrapCardData):
			continue
		if inst.card_data.id != trap_id:
			continue
		var trap_cost: int = inst.effective_cost()
		if trap_cost > agent.mana:
			continue
		agent.mana -= trap_cost
		if not await agent.commit_play_trap(inst):
			return
		return
