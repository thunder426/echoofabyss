## SpellBurnPlayerProfile.gd
## Player bot tuned for spell-burn decks (e.g. Voidbolt Burst).
##
## Resource growth
##   Mana-first so Void Bolts come online early.
##   If hand has 2+ essence-costing minions, grow Essence instead.
##   Once Mana hits 3, catch Essence up to 3 before growing Mana further.
##   Cap: 5E / 6M (combined 11).
##
## Play priority per turn
##   1. Void Imps        — cheap board presence / sacrifice fodder
##   2. Draw minions     — refuel before spending Mana on spells
##   3. Board-clear spells (Abyssal Plague) — only when enemies are present
##   4. Void Rune        — passive chip damage every turn
##   5. Void Bolt        — direct burn
##   6. Void Execution   — removal (only when it kills; see below)
##   7. Abyssal Sacrifice + remaining — fallback via base helpers
##
## Attack behaviour
##   Trade into enemies we can kill outright (highest-HP killable = biggest threat removed).
##   If nothing is killable, go face.
##   Never attack a minion we cannot kill (no unfavourable trades).
##   Guards: only attack guards we can kill; skip this minion if all guards survive.
##
## Void Execution
##   Only cast when it can kill at least one enemy minion (HP ≤ 500, or 700 with a Human).
##   Targets the highest-HP killable enemy (max threat removed per cast).
class_name SpellBurnPlayerProfile
extends CombatProfile

const _DRAW_MINION_IDS: Array[String] = ["traveling_merchant"]
const _BOARD_CLEAR_IDS: Array[String] = ["abyssal_plague"]
const _BURN_IDS:        Array[String] = ["void_bolt"]

# ---------------------------------------------------------------------------
# Resource growth hook
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.player_growth_override = func(turn: int) -> void:
		_grow_spell_burn(sim_state, turn)

func _grow_spell_burn(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e_max: int = state.player_essence_max
	var m_max: int = state.player_mana_max
	if e_max + m_max >= 11:
		return
	# Once Mana reaches 3, bring Essence up to 3 before growing Mana further
	if m_max >= 3 and e_max < 3:
		state.player_essence_max += 1
		return
	# Count essence-costing minions in hand — if 2+, grow Essence
	var e_minion_count: int = 0
	for inst in state.player_hand:
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).essence_cost >= 2:
			e_minion_count += 1
	if e_minion_count >= 2:
		state.player_essence_max += 1
	else:
		state.player_mana_max += 1

# ---------------------------------------------------------------------------
# Play phase
# ---------------------------------------------------------------------------

func play_phase() -> void:
	# 1. Void Imps — flood early, fodder for Abyssal Sacrifice
	await _play_minions_by_id(["void_imp"])
	if not agent.is_alive(): return
	# 2. Draw minions — refuel hand before committing Mana to spells
	await _play_minions_by_id(_DRAW_MINION_IDS)
	if not agent.is_alive(): return
	# 3. Board-clear spells — only when enemies are present
	if not agent.opponent_board.is_empty():
		await _play_spells_by_id(_BOARD_CLEAR_IDS)
		if not agent.is_alive(): return
	# 4. Void Rune — passive chip every turn
	await _play_traps_by_id(["void_rune"])
	if not agent.is_alive(): return
	# 5. Void Bolt — burn face
	await _play_spells_by_id(_BURN_IDS)
	if not agent.is_alive(): return
	# 6. Void Execution — removal (cast_if handled in can_cast_spell)
	await _play_spells_by_id(["void_execution"])
	if not agent.is_alive(): return
	# 7. Fallback — Abyssal Sacrifice (draw) + anything else
	await _play_spells_pass()
	if not agent.is_alive(): return
	await _play_minions_pass()
	if not agent.is_alive(): return
	await _play_traps_pass()

# ---------------------------------------------------------------------------
# Spell cast conditions
# ---------------------------------------------------------------------------

func can_cast_spell(spell: SpellCardData) -> bool:
	match spell.id:
		"abyssal_sacrifice":
			# Hold while a Void Bolt is already in hand — don't sacrifice for nothing
			for inst in agent.hand:
				if inst.card_data is SpellCardData and (inst.card_data as SpellCardData).id == "void_bolt":
					return false
			return true
		"void_execution":
			# Only cast when it kills at least one enemy minion outright
			var dmg: int = _void_execution_damage()
			for m in agent.opponent_board:
				if m.current_health <= dmg:
					return true
			return false
		_:
			return super.can_cast_spell(spell)

func _void_execution_damage() -> int:
	for m in agent.friendly_board:
		if m.card_data is MinionCardData and \
				(m.card_data as MinionCardData).minion_type == Enums.MinionType.HUMAN:
			return 700
	return 500

# ---------------------------------------------------------------------------
# Spell targeting
# ---------------------------------------------------------------------------

func pick_spell_target(spell: SpellCardData):
	if spell.id == "void_execution":
		return _pick_void_execution_target()
	return super.pick_spell_target(spell)

## Highest-HP enemy we can kill — removes the biggest threat per cast.
func _pick_void_execution_target() -> MinionInstance:
	var dmg: int = _void_execution_damage()
	var best: MinionInstance = null
	for m in agent.opponent_board:
		if m.current_health <= dmg:
			if best == null or m.current_health > best.current_health:
				best = m
	return best

# ---------------------------------------------------------------------------
# Attack phase
# ---------------------------------------------------------------------------

func attack_phase() -> void:
	var can_go_lethal: bool = _calc_lethal_damage() >= agent.opponent_hp
	if can_go_lethal:
		await _play_lethal_spells()
		if not agent.is_alive(): return

	for minion in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(minion) or not minion.can_attack():
			continue
		var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
		if can_go_lethal and guards.is_empty():
			# Lethal window — go face (NORMAL) or clear board (SWIFT)
			if minion.can_attack_hero():
				if not await agent.do_attack_hero(minion):
					return
			elif not agent.opponent_board.is_empty():
				var t: MinionInstance = agent.pick_swift_target(minion)
				if not await agent.do_attack_minion(minion, t):
					return
		elif not guards.is_empty():
			# Must attack a guard — only attack if we can kill it (no unfavourable trade)
			var target: MinionInstance = _pick_killable_guard(minion, guards)
			if target != null:
				if not await agent.do_attack_minion(minion, target):
					return
			# else: skip this minion — all guards survive, not worth trading
		else:
			# No guards — trade into killable enemy, otherwise go face
			var target: MinionInstance = _pick_kill_target(minion)
			if target != null:
				if not await agent.do_attack_minion(minion, target):
					return
			elif minion.can_attack_hero():
				if not await agent.do_attack_hero(minion):
					return
			# else: nothing killable and can't attack hero — skip

# ---------------------------------------------------------------------------
# Attack targeting helpers
# ---------------------------------------------------------------------------

## Among guards, return the highest-HP one we can kill (or null if none killable).
func _pick_killable_guard(attacker: MinionInstance, guards: Array[MinionInstance]) -> MinionInstance:
	var best: MinionInstance = null
	for g in guards:
		if attacker.effective_atk() >= g.current_health:
			if best == null or g.current_health > best.current_health:
				best = g
	return best

## Among all enemy minions, return the highest-HP one we can kill outright (or null).
func _pick_kill_target(attacker: MinionInstance) -> MinionInstance:
	var best: MinionInstance = null
	for m in agent.opponent_board:
		if attacker.effective_atk() >= m.current_health:
			if best == null or m.current_health > best.current_health:
				best = m
	return best

# ---------------------------------------------------------------------------
# Play-phase helpers
# ---------------------------------------------------------------------------

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
				return  # board full
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
