## MatriarchAggroProfile.gd
## AI profile for Imp Matriarch — Aggro variant with minions + pack frenzy.
##
## Unlike the base MatriarchProfile (pure spells), this variant has actual
## minions in the deck. Resource growth is essence-first to play minions,
## then mana for pack_frenzy.
##
## Resource growth: 4E → 2M → 6E → 4M → 7E
## Pack Frenzy: cast with 2+ feral imps or lethal (same as base matriarch).
## Arcane Strike: only cast when it kills an enemy minion, target highest HP killable.
class_name MatriarchAggroProfile
extends FeralPackProfile

const MATRIARCH_FERAL_THRESHOLD := 2

func _is_tempo() -> bool:
	return true

func _get_spell_rules() -> Dictionary:
	return {
		"pack_frenzy":  {"cast_if": "before_attacks"},
		"feral_surge":  {"cast_if": "has_friendly_tag", "tag": "feral_imp"},
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
		"arcane_strike": {"cast_if": "can_kill_enemy_minion"},
		"cyclone":      {"cast_if": "opponent_has_rune_or_env"},
	}

## Only cast arcane_strike when it kills.
func can_cast_spell(spell: SpellCardData) -> bool:
	if spell.id == "arcane_strike":
		for m in agent.opponent_board:
			if m.current_health <= 300:
				return true
		return false
	return super.can_cast_spell(spell)

## Arcane strike: target highest HP enemy we can kill (HP ≤ 300).
func pick_spell_target(spell: SpellCardData):
	if spell.id == "arcane_strike":
		var best: MinionInstance = null
		for m in agent.opponent_board:
			if m.current_health <= 300:
				if best == null or m.current_health > best.current_health:
					best = m
		return best
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
