## DefaultPlayerProfile.gd
## Competitive player bot for balance simulation.
##
## Play phase  — two-pass: flood board with minions (cheapest first), then cast spells.
## Attack phase — inherited smart default (guard → lethal trade → face/swift).
## Spell rules  — void_execution: only if a Human is on the friendly board.
##               void_screech:   hold until board full or no minions left in hand.
##               cyclone:        only if opponent has an active Rune or Environment.
##
## Resource growth  (essence-first, with smart overrides)
##   Default: grow Essence each turn; catch Mana up when it falls >2 behind Essence.
##   Mana push:    if mana_max < 2 AND a high-importance 2M card is in hand.
##                   abyssal_sacrifice — important when hand ≤ 3 cards AND board has
##                                       a cheap token (total cost ≤ 1) to sacrifice.
##                   dominion_rune    — important when 3+ Demons are on the board.
##   Essence push: if any minion in hand has essence_cost > current essence_max
##                 (covers "5E minion with E=4" and "6E minion with E=5" cases).
##   Cap: combined 11.
class_name DefaultPlayerProfile
extends CombatProfile

func _is_aggro() -> bool:
	return true

func play_phase() -> void:
	await play_phase_two_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"void_execution": {"cast_if": "has_friendly_tag", "tag": "human"},
		"void_screech":   {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":        {"cast_if": "opponent_has_rune_or_env"},
	}

# ---------------------------------------------------------------------------
# Resource growth hook
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.player_growth_override = func(turn: int) -> void:
		_grow_aggro(sim_state, turn)

func _grow_aggro(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e_max: int = state.player_essence_max
	var m_max: int = state.player_mana_max
	if e_max + m_max >= 11:
		return

	# Mana push — grow Mana when a high-value 2M card can't yet be cast
	if m_max < 2 and _needs_mana_push(state):
		state.player_mana_max += 1
		return

	# Essence push — grow Essence when a minion in hand needs more than we have
	for inst in state.player_hand:
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).essence_cost > e_max:
			state.player_essence_max += 1
			return

	# Default: essence-first; catch Mana up when it falls more than 2 behind
	if m_max < e_max - 2:
		state.player_mana_max += 1
	else:
		state.player_essence_max += 1

## Returns true if a high-importance 2-Mana card in hand warrants growing Mana now.
func _needs_mana_push(state: Object) -> bool:
	for inst in state.player_hand:
		if inst.card_data is SpellCardData and (inst.card_data as SpellCardData).cost == 2:
			if (inst.card_data as SpellCardData).id == "abyssal_sacrifice":
				# Worth growing Mana if hand is running low AND a cheap token can be sacrificed
				if state.player_hand.size() <= 3 and _has_cheap_token(state):
					return true
		elif inst.card_data is TrapCardData and (inst.card_data as TrapCardData).cost == 2:
			if (inst.card_data as TrapCardData).id == "dominion_rune":
				# Worth growing Mana if 3+ Demons are already on the board
				if _demon_count(state) >= 3:
					return true
	return false

## True if the player board has at least one minion with total cost ≤ 1 (e.g. Void Imp).
func _has_cheap_token(state: Object) -> bool:
	for m in state.player_board:
		var mc: MinionCardData = (m as MinionInstance).card_data as MinionCardData
		if mc != null and mc.essence_cost + mc.mana_cost <= 1:
			return true
	return false

func _demon_count(state: Object) -> int:
	var n := 0
	for m in state.player_board:
		if (m as MinionInstance).card_data.minion_type == Enums.MinionType.DEMON:
			n += 1
	return n
