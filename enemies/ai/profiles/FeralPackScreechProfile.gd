## FeralPackScreechProfile.gd
## AI profile for the Feral Imp Pack — Screech Burst variant.
##
## Strategy: Build board first with essence-heavy growth, then screech
## only when 3+ feral imps are on board for 350 damage.
## Feral surge targets highest HP minion, or a swift minion if the buff
## would let it secure a kill it couldn't get without it.
##
## Resource growth: 4E → 2M → 6E → 3M → 8E (essence-heavy, mana catch-up)
class_name FeralPackScreechProfile
extends CombatProfile

func play_phase() -> void:
	await play_phase_two_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"void_screech": {"cast_if": "has_3_feral_imps"},
		"feral_surge":  {"cast_if": "has_friendly_tag", "tag": "feral_imp"},
	}

## Custom spell gate: only cast screech when 3+ feral imps on board.
func can_cast_spell(spell: SpellCardData) -> bool:
	if spell.id == "void_screech":
		return _count_board_feral_imps() >= 3
	return super.can_cast_spell(spell)

## Feral surge targeting: prefer swift minion that can secure a kill with +300 ATK,
## otherwise target highest HP friendly feral imp.
func pick_spell_target(spell: SpellCardData):
	if spell.id == "feral_surge":
		return _pick_surge_target()
	return super.pick_spell_target(spell)

func _pick_surge_target() -> MinionInstance:
	# Check for a swift minion that can secure a kill with +300 ATK buff
	for m in agent.friendly_board:
		if not _is_feral_imp(m):
			continue
		if m.state != Enums.MinionState.SWIFT:
			continue
		var buffed_atk: int = m.effective_atk() + 300
		for enemy in agent.opponent_board:
			# Can kill with buff but not without
			if enemy.current_health <= buffed_atk and enemy.current_health > m.effective_atk():
				return m
	# Fallback: highest HP friendly feral imp (survives longest to use the buff)
	var best: MinionInstance = null
	for m in agent.friendly_board:
		if not _is_feral_imp(m):
			continue
		if best == null or m.current_health > best.current_health:
			best = m
	return best

## Resource growth: 4E → 2M → 6E → 3M → 8E
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
		elif m < 3:
			sim_state.enemy_mana_max += 1
		else:
			sim_state.enemy_essence_max += 1

func _count_board_feral_imps() -> int:
	var count := 0
	for m in agent.friendly_board:
		if _is_feral_imp(m):
			count += 1
	return count

func _is_feral_imp(m: MinionInstance) -> bool:
	return agent.scene != null and agent.scene._minion_has_tag(m, "feral_imp")
