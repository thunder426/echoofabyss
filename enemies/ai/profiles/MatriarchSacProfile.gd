## MatriarchSacProfile.gd
## AI profile for Imp Matriarch — Aggro sacrifice variant.
##
## Aggro face style with abyssal_sacrifice for card draw.
## Sacrifice targets: void_spark first, brood_imp second, never other minions.
## Resource growth: 4E → 2M → 6E → 4M → 7E
## Pack Frenzy: cast with 2+ feral imps or lethal.
class_name MatriarchSacProfile
extends FeralPackProfile

const MATRIARCH_FERAL_THRESHOLD := 2

func _is_aggro() -> bool:
	return true

func _get_spell_rules() -> Dictionary:
	return {
		"pack_frenzy":      {"cast_if": "before_attacks"},
		"feral_surge":      {"cast_if": "has_friendly_tag", "tag": "feral_imp"},
		"void_screech":     {"cast_if": "board_full_or_no_minions_in_hand"},
		"abyssal_sacrifice": {"cast_if": "never"},
		"cyclone":          {"cast_if": "opponent_has_rune_or_env"},
	}

func play_phase() -> void:
	await _play_minions_pass()
	if not agent.is_alive(): return
	if _has_sac_target():
		await _play_spell_by_id("abyssal_sacrifice")
		if not agent.is_alive(): return
		await _play_minions_pass()
		if not agent.is_alive(): return
	await _play_spells_pass()
	if not agent.is_alive(): return
	await _play_traps_pass()

func can_cast_spell(spell: SpellCardData) -> bool:
	if spell.id == "abyssal_sacrifice":
		return false
	return super.can_cast_spell(spell)

func pick_spell_target(spell: SpellCardData):
	if spell.id == "abyssal_sacrifice":
		return _pick_sac_target()
	return super.pick_spell_target(spell)

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		if turn <= 1:
			return
		var e: int = sim_state.enemy_essence_max
		var m: int = sim_state.enemy_mana_max
		if e + m >= 11:
			return
		if e < 4:
			sim_state.enemy_essence_max += 1
		elif m < 2:
			sim_state.enemy_mana_max += 1
		elif e < 6:
			sim_state.enemy_essence_max += 1
		elif m < 4:
			sim_state.enemy_mana_max += 1
		else:
			sim_state.enemy_essence_max += 1

func _should_cast_pack_frenzy() -> bool:
	var pf := _find_pack_frenzy()
	if pf == null or agent.effective_spell_cost(pf.card_data as SpellCardData) > agent.mana:
		return false
	if _calc_lethal_with_pack_frenzy() >= agent.opponent_hp:
		return true
	var feral_count := 0
	for m in agent.friendly_board:
		if _is_feral_imp(m):
			feral_count += 1
	return feral_count >= MATRIARCH_FERAL_THRESHOLD

# ---------------------------------------------------------------------------
# Sacrifice helpers
# ---------------------------------------------------------------------------

func _has_sac_target() -> bool:
	var has_sac := false
	for inst in agent.hand:
		if inst.card_data is SpellCardData and inst.card_data.id == "abyssal_sacrifice":
			if agent.effective_spell_cost(inst.card_data as SpellCardData) <= agent.mana:
				has_sac = true
				break
	if not has_sac:
		return false
	return _pick_sac_target() != null

func _pick_sac_target() -> MinionInstance:
	for m in agent.friendly_board:
		if m.card_data is MinionCardData and (m.card_data as MinionCardData).id == "void_spark":
			return m
	for m in agent.friendly_board:
		if m.card_data is MinionCardData and (m.card_data as MinionCardData).id == "brood_imp":
			return m
	return null

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
