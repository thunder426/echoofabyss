## SerisPlayerProfile.gd
## Player bot for Seris, the Fleshbinder. Used by balance sim and as a sane
## default bot when the run is Seris-hero. Activates hero-specific buttons
## (Soul Forge, Corrupt Flesh) that generic profiles never press, so the
## Demon Forge and Corruption Engine branches actually engage in sim.
##
## Strategy — generic but hero-aware:
##   1. Flux Siphon (free Mana→Essence)
##   2. Place runes / traps where cheap
##   3. Corrupt Flesh button (once/turn, greedy on highest-ATK friendly Demon)
##   4. Minions — Grafted Fiends first (for Fleshcraft synergy), then others
##   5. Soul Forge button (spend 3 Flesh → Grafted Fiend) after other plays
##   6. Sacrifice spells (Abyssal Sacrifice / Blood Pact / Soul Shatter) —
##      trigger Fleshbind + Forge Counter
##   7. Remaining spells / traps
##
## Attack: aggro — face when possible, trade under lethal threat.
class_name SerisPlayerProfile
extends CombatProfile

func _is_aggro() -> bool:
	return true

# ---------------------------------------------------------------------------
# Play phase
# ---------------------------------------------------------------------------

func play_phase() -> void:
	await _play_spells_by_id(["flux_siphon"])
	if not agent.is_alive(): return

	# Traps / Runes before minions so auras buff on-play.
	await _play_traps_pass()
	if not agent.is_alive(): return

	# Soul Forge BEFORE minion plays — if we can afford it, Forge first so we
	# don't fill the board with cheap minions and block our own hero power.
	# _reserved_slots() also keeps a slot free during the minion pass when
	# Flesh >= 3, so a Forge press is possible even mid-phase.
	_maybe_soul_forge_loop()
	if not agent.is_alive(): return

	# Prefer Grafted Fiends — they feed every Seris branch.
	await _play_minions_by_id(["grafted_fiend"])
	if not agent.is_alive(): return

	await _play_minions_pass()
	if not agent.is_alive(): return

	# Corrupt Flesh AFTER minions land — only useful if there's a friendly Demon
	# on board to receive stacks. Running it here means turn-1 fiend landing gets
	# its buff on turn 1 rather than waiting for the next turn.
	_maybe_corrupt_flesh()
	if not agent.is_alive(): return

	# Soul Forge AGAIN — sacrifice plays below may free slots / grant Flesh, so
	# re-check after the minion pass settles.
	_maybe_soul_forge_loop()
	if not agent.is_alive(): return

	# Sacrifice spells — drive Fleshbind gain and Forge Counter ticks.
	await _play_spells_by_id(["abyssal_sacrifice", "blood_pact", "soul_shatter"])
	if not agent.is_alive(): return

	# Anything else.
	await _play_spells_pass()
	if not agent.is_alive(): return

	# One more minion pass in case sacrifices / draws opened up new plays.
	await _play_minions_pass()
	if not agent.is_alive(): return

	# Final Soul Forge check after all sacrifice-driven Flesh gains.
	_maybe_soul_forge_loop()

## Reserve one board slot specifically for Soul Forge when we have enough Flesh
## to press the button. This prevents _play_minions_pass from filling the board
## and locking the button out. Only active on Seris with soul_forge unlocked.
## Note: player profiles (unlike enemy profiles) don't reserve slots for champions,
## so we don't need to call the parent implementation here.
func _reserved_slots() -> int:
	if agent.sim == null:
		return 0
	if not agent.sim._has_talent("soul_forge"):
		return 0
	var flesh: int = int(agent.sim.get("player_flesh"))
	if flesh < 3:
		return 0
	# Only reserve if a slot is actually free — otherwise we'd force-cap the minion pass to 0.
	if agent.empty_slot_count() <= 0:
		return 0
	return 1

func _get_spell_rules() -> Dictionary:
	return {
		"cyclone":       {"cast_if": "opponent_has_rune_or_env"},
		"void_screech":  {"cast_if": "board_full_or_no_minions_in_hand"},
	}

# ---------------------------------------------------------------------------
# Hero-power presses
# ---------------------------------------------------------------------------

## Spend 1 Flesh on the highest-ATK friendly Demon to apply Corruption.
## Under Corrupt Flesh talent, Corruption adds ATK instead of subtracting,
## so buffing the biggest Demon maximises damage and feeds Corrupt Detonation.
func _maybe_corrupt_flesh() -> void:
	var sim: SimState = agent.sim
	if sim == null or not sim.has_method("_seris_corrupt_activate"):
		return
	if not sim._has_talent("corrupt_flesh"):
		return
	if sim.player_flesh < 1 or sim._seris_corrupt_used_this_turn:
		return
	var best: MinionInstance = null
	for m in agent.friendly_board:
		if (m.card_data as MinionCardData).minion_type != Enums.MinionType.DEMON:
			continue
		if best == null or m.effective_atk() > best.effective_atk():
			best = m
	if best == null:
		return
	sim._seris_corrupt_activate(best)

## Greedy Soul Forge — summon Grafted Fiends while we can afford 3 Flesh and
## have board space. Multiple presses per turn are allowed (design does not
## cap it). Stops on first failure (board full / no flesh).
func _maybe_soul_forge_loop() -> void:
	var sim: SimState = agent.sim
	if sim == null or not sim.has_method("_soul_forge_activate"):
		return
	if not sim._has_talent("soul_forge"):
		return
	var guard := 5  # hard stop — should never loop this many times in practice
	while guard > 0 and sim._soul_forge_activate():
		guard -= 1

# ---------------------------------------------------------------------------
# Resource growth — essence-first with mana catches (same shape as Swarm)
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.player_growth_override = func(turn: int) -> void:
		_grow_seris(sim_state, turn)

func _grow_seris(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e_max: int = state.player_essence_max
	var m_max: int = state.player_mana_max
	if e_max + m_max >= 11:
		return
	# Essence push — minion in hand costs more than current essence_max
	for inst in state.player_hand:
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).essence_cost > e_max:
			state.player_essence_max += 1
			return
	# Default: essence-first; catch mana up when it falls >2 behind
	if m_max < e_max - 2:
		state.player_mana_max += 1
	else:
		state.player_essence_max += 1

# ---------------------------------------------------------------------------
# Play-phase helpers (shaped like SwarmPlayerProfile)
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
