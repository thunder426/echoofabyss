## RuneTempoPlayerProfile.gd
## Player bot tuned for the Death Circle rune/ritual deck.
##
## Resource growth
##   Phase 1 — Mana to 2 first so key 2M cards (runes, void_summoning) come online.
##             Exception: no Void Imp in opening hand AND hand has a 2E minion → grow E.
##   Phase 2 — Grow E to 4 (while M stays at 2).
##   Phase 3 — Grow M to 4.
##   Phase 4 — Grow E towards 7 (final 7E/4M); or M to 5 if no minion in hand (6E/5M).
##   Flex overrides (apply in phases 2-4):
##     • No minion in hand + M < 4 → grow M (nothing to spend E on, get mana up).
##     • Large minion in hand (essence_cost > current E) + no affordable spell → grow E.
##
## Play priority per turn
##   1. Void Imp              — cheap fodder / board presence
##   2. Cheap minions         — Shadow Hound, Void Netter (board before runes)
##   3. Environment           — Abyssal Summoning Circle (opens ritual window)
##   4. Runes                 — Dominion Rune, Blood Rune (buff + ritual triggers)
##   5. Void Summoning        — summons Demon after rune buffs are in place
##   6. Remaining minions     — Abyssal Brute etc.
##   7. Abyssal Sacrifice     — draw only when hand ≤ 3 AND a cheap token can be sacrificed
##   8. Fallback              — remaining spells, remaining traps
##
## Attack behaviour
##   Inherits the base smart-attack logic (guard → lethal → face / best kill).
##   Not marked aggro — prefers board control over rushing face.
class_name RuneTempoPlayerProfile
extends CombatProfile

const _RUNE_IDS:         Array[String] = ["dominion_rune", "blood_rune"]
const _CHEAP_MINION_IDS: Array[String] = ["void_imp", "shadow_hound", "void_netter"]

# ---------------------------------------------------------------------------
# Resource growth hook
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.player_growth_override = func(turn: int) -> void:
		_grow_rune_tempo(sim_state, turn)

func _grow_rune_tempo(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e: int = state.player_essence_max
	var m: int = state.player_mana_max
	if e + m >= 11:
		return

	# Phase 1: Mana to 2 first
	if m < 2:
		# Exception: no Void Imp in hand AND has a 2E minion → grow E instead
		if not _hand_has_void_imp(state) and _hand_has_essence_minion(state, 2):
			state.player_essence_max += 1
		else:
			state.player_mana_max += 1
		return

	# Flex override: no minion in hand + M below 4 → grow M
	if not _hand_has_minion(state) and m < 4:
		state.player_mana_max += 1
		return

	# Flex override: large unaffordable minion in hand + no castable spell → grow E
	if _hand_has_large_minion(state, e) and not _hand_has_castable_spell(state, m):
		state.player_essence_max += 1
		return

	# Phase 2: E to 4
	if e < 4:
		state.player_essence_max += 1
		return

	# Phase 3: M to 4
	if m < 4:
		state.player_mana_max += 1
		return

	# Phase 4: E towards 7 (default); or M to 5 if nothing to play on board
	if not _hand_has_minion(state) and m < 5:
		state.player_mana_max += 1
	else:
		state.player_essence_max += 1

# ---------------------------------------------------------------------------
# Play phase
# ---------------------------------------------------------------------------

func play_phase() -> void:
	# 1. Void Imp — cheapest board presence, ritual fodder
	await _play_minions_by_id(["void_imp"])
	if not agent.is_alive(): return
	# 2. Shadow Hound / Void Netter — cheap bodies before spending mana on runes
	await _play_minions_by_id(["shadow_hound", "void_netter"])
	if not agent.is_alive(): return
	# 3. Environment — Abyssal Summoning Circle opens the ritual window
	await _play_environment_pass()
	if not agent.is_alive(): return
	# 4. Runes — Dominion Rune buffs existing Demons; Blood Rune completes ritual
	await _play_traps_by_id(_RUNE_IDS)
	if not agent.is_alive(): return
	# 5. Void Summoning — new Demon lands into an already-buffed board
	await _play_spells_by_id(["void_summoning"])
	if not agent.is_alive(): return
	# 6. Remaining minions (Abyssal Brute etc.)
	await _play_minions_pass()
	if not agent.is_alive(): return
	# 7. Abyssal Sacrifice — draw only when hand is low and something cheap can be sacrificed
	await _play_spells_by_id(["abyssal_sacrifice"])
	if not agent.is_alive(): return
	# 8. Fallback — any remaining spells / traps
	await _play_spells_pass()
	if not agent.is_alive(): return
	await _play_traps_pass()

# ---------------------------------------------------------------------------
# Spell cast conditions
# ---------------------------------------------------------------------------

func can_cast_spell(spell: SpellCardData) -> bool:
	if spell.id == "abyssal_sacrifice":
		# Only sacrifice when hand is running low AND a cheap token can be given up
		return agent.hand.size() <= 3 and _has_cheap_token_on_board()
	return super.can_cast_spell(spell)

# ---------------------------------------------------------------------------
# Play-phase helpers
# ---------------------------------------------------------------------------

## Play only the first affordable environment (skips if one is already active).
func _play_environment_pass() -> void:
	for inst in agent.hand.duplicate():
		if not (inst.card_data is EnvironmentCardData):
			continue
		var env := inst.card_data as EnvironmentCardData
		var scene: Object = agent.scene
		if scene != null and scene.get("active_environment") != null:
			return  # already have one — don't replace
		if env.cost > agent.mana:
			continue
		agent.mana -= env.cost
		if not await agent.commit_play_environment(inst):
			return

## Play all affordable minions whose ID is in ids, restarting after each play.
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
			var mana_cost: int = agent.effective_minion_mana_cost(mc)
			if mc.essence_cost > agent.essence or mana_cost > agent.mana:
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return
			agent.essence -= mc.essence_cost
			agent.mana    -= mana_cost
			if not await agent.commit_play_minion(inst, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

## Cast all affordable spells whose ID is in ids, checking can_cast_spell each time.
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

## Place all affordable traps/runes whose ID is in ids.
func _play_traps_by_id(ids: Array[String]) -> void:
	var placed: bool = true
	while placed:
		placed = false
		for inst in agent.hand.duplicate():
			if not (inst.card_data is TrapCardData):
				continue
			var trap := inst.card_data as TrapCardData
			if not (trap.id in ids):
				continue
			var trap_cost: int = inst.effective_cost()
			if trap_cost > agent.mana:
				continue
			agent.mana -= trap_cost
			if not await agent.commit_play_trap(inst):
				return
			placed = true
			break

# ---------------------------------------------------------------------------
# Growth helpers
# ---------------------------------------------------------------------------

func _hand_has_void_imp(state: Object) -> bool:
	for inst in state.player_hand:
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).id == "void_imp":
			return true
	return false

func _hand_has_essence_minion(state: Object, min_cost: int) -> bool:
	for inst in state.player_hand:
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).essence_cost >= min_cost:
			return true
	return false

func _hand_has_minion(state: Object) -> bool:
	for inst in state.player_hand:
		if inst.card_data is MinionCardData:
			return true
	return false

## Returns true if hand has a minion whose essence_cost exceeds current essence_max.
func _hand_has_large_minion(state: Object, essence_max: int) -> bool:
	for inst in state.player_hand:
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).essence_cost > essence_max:
			return true
	return false

func _hand_has_castable_spell(state: Object, mana: int) -> bool:
	for inst in state.player_hand:
		if inst.card_data is SpellCardData and (inst.card_data as SpellCardData).cost <= mana:
			return true
	return false

## True if a cheap token (total cost ≤ 1, e.g. Void Imp) is on the board to sacrifice.
func _has_cheap_token_on_board() -> bool:
	for m in agent.friendly_board:
		var mc := (m as MinionInstance).card_data as MinionCardData
		if mc != null and mc.essence_cost + mc.mana_cost <= 1:
			return true
	return false
