## KorrathPlayerProfile.gd
## Player bot for Korrath, the Abyssal Commander. Used by balance sim and as the
## default bot when the run is Korrath-hero. Branch-agnostic baseline — plays the
## knight as the centerpiece and lets the talent overrides + on-attack triggers
## drive branch-specific behaviour. Per-branch refinements (formation pairing for
## Iron Vanguard, rune-stack management for Runic Knight, AB stacking for
## Abyssal Breaker) can be split into subclasses later if balance sim flags them
## as needed; the same pattern Seris used (SerisPlayerProfile → FleshcraftPlayerProfile).
##
## Strategy:
##   1. Flux Siphon (free Mana→Essence)
##   2. Place runes / traps where cheap (rune auras buff on-summon)
##   3. Abyssal Knight first — centerpiece, scales with talent investment
##   4. Other minions
##   5. Spells
##   6. Late minion pass for catch-ups
##
## Attack: aggro by default. Branch 1 (Iron Vanguard) actually wants to keep
## the knight alive on board for armour-stacking + Iron Resolve ATK conversion,
## but a face-pressure baseline is closer to correct than a defensive one given
## min-100 floor + Armour Break already give the bot a hard time on the back foot.
class_name KorrathPlayerProfile
extends CombatProfile

func _is_aggro() -> bool:
	return true

# ---------------------------------------------------------------------------
# Play phase
# ---------------------------------------------------------------------------

func play_phase() -> void:
	await _play_spells_by_id(["flux_siphon"])
	if not agent.is_alive(): return

	# Traps / Runes before minions so auras buff on-play and on-attack rune
	# generation (runeforge_strike T0) lands into a board with room.
	await _play_traps_pass()
	if not agent.is_alive(): return

	# Abyssal Knight first — it's the win condition. T0 talents reshape it
	# (race / FORMATION / dual-tag), and T1+ feeds off it being on the board.
	await _play_minions_by_id(["abyssal_knight"])
	if not agent.is_alive(): return

	# Remaining minions (Demons, Humans, neutrals).
	await _play_minions_pass()
	if not agent.is_alive(): return

	# Spells last — most need a board state to target effectively.
	await _play_spells_pass()
	if not agent.is_alive(): return

	# One more minion pass in case spell draws / sacrifices opened plays.
	await _play_minions_pass()

# ---------------------------------------------------------------------------
# Resource growth — essence-first with mana catch-up. Knight is 4E (3E with
# abyssal_commander) so the deck strongly favours essence. Same shape Vael's
# Swarm and Seris use.
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.player_growth_override = func(turn: int) -> void:
		_grow_korrath(sim_state, turn)

func _grow_korrath(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e_max: int = state.player_essence_max
	var m_max: int = state.player_mana_max
	if e_max + m_max >= 11:
		return
	# Essence push if any minion in hand costs more than current essence_max.
	for inst in state.player_hand:
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).essence_cost > e_max:
			state.player_essence_max += 1
			return
	# Default: essence-first; catch mana up when it falls >2 behind.
	if m_max < e_max - 2:
		state.player_mana_max += 1
	else:
		state.player_essence_max += 1

# ---------------------------------------------------------------------------
# Play-phase helpers (shape mirrors SerisPlayerProfile / SwarmPlayerProfile —
# duplicated rather than shared because the helpers are small and each profile
# tweaks them independently. If a third hero needs the same helpers, hoist
# them into CombatProfile.)
# ---------------------------------------------------------------------------

func _play_minions_by_id(ids: Array[String]) -> void:
	var placed: bool = true
	while placed:
		placed = false
		for inst in agent.hand.duplicate():
			if not (inst.card_data is MinionCardData):
				continue
			var mc := inst.card_data as MinionCardData
			if not (mc.id in ids):
				continue
			var ess_cost: int = agent.effective_minion_essence_cost(mc)
			var mana_cost: int = agent.effective_minion_mana_cost(mc)
			if ess_cost > agent.essence or mana_cost > agent.mana:
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return
			agent.essence -= ess_cost
			agent.mana    -= mana_cost
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

func _play_spells_by_id(ids: Array[String]) -> void:
	var cast: bool = true
	while cast:
		cast = false
		for inst in agent.hand.duplicate():
			if not (inst.card_data is SpellCardData):
				continue
			var spell := inst.card_data as SpellCardData
			if not (spell.id in ids):
				continue
			var cost: int = agent.effective_spell_cost(spell)
			if cost > agent.mana:
				continue
			if not can_cast_spell(spell):
				continue
			agent.mana -= cost
			if not await agent.commit_play_spell(inst, pick_spell_target(spell)):
				return
			cast = true
			break
