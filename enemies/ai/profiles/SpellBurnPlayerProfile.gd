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
##   6. Arcane Strike     — targeted removal (only when it kills a minion with HP ≤ 300)
##   7. Void Execution   — removal (only when it kills; see below)
##   8. Abyssal Sacrifice + remaining — fallback via base helpers
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
	# Mana to 3 first (void_bolt online early)
	if m_max < 3:
		state.player_mana_max += 1
	# Essence to 2 (traveling_merchant playable)
	elif e_max < 2:
		state.player_essence_max += 1
	# Then pure mana for spell scaling
	else:
		state.player_mana_max += 1

# ---------------------------------------------------------------------------
# Play phase
# ---------------------------------------------------------------------------

func play_phase() -> void:
	# 1. Survival — if enemy burst threatens heavy damage, prioritise defense before spending mana
	if _enemy_threatens_heavy_damage() and not agent.opponent_board.is_empty():
		# AoE clear first — if plague kills enough minions to prevent lethal, saves smoke_veil
		if _plague_prevents_lethal():
			await _play_spells_by_id(_BOARD_CLEAR_IDS)
			if not agent.is_alive(): return
		# Smoke Veil — if still threatened after plague (or no plague available)
		if _should_place_smoke_veil():
			await _play_traps_by_id(["smoke_veil"])
			if not agent.is_alive(): return
		# Fallback AoE — cast plague anyway to reduce board even if it doesn't fully prevent lethal
		await _play_spells_by_id(_BOARD_CLEAR_IDS)
		if not agent.is_alive(): return
	# 2. AoE clear — if abyssal_plague would kill 3+ enemies, cast before spending mana
	elif _should_prioritise_board_clear():
		await _play_spells_by_id(_BOARD_CLEAR_IDS)
		if not agent.is_alive(): return
	# 3. Void Imps — board presence / sacrifice fodder
	await _play_minions_by_id(["void_imp"])
	if not agent.is_alive(): return
	# 4. Draw minions — refuel hand before committing Mana to spells
	await _play_minions_by_id(_DRAW_MINION_IDS)
	if not agent.is_alive(): return
	# 5. Board-clear spells — mop up remaining enemies if not already cast
	if not agent.opponent_board.is_empty():
		await _play_spells_by_id(_BOARD_CLEAR_IDS)
		if not agent.is_alive(): return
	# 6. Arcane Strike — targeted removal (only cast when it kills)
	await _play_spells_by_id(["arcane_strike"])
	if not agent.is_alive(): return
	# 7. Smoke Veil — place if enemy still threatens lethal after spending mana
	if _should_place_smoke_veil():
		await _play_traps_by_id(["smoke_veil"])
		if not agent.is_alive(): return
	# 8. Void Rune — passive chip every turn
	await _play_traps_by_id(["void_rune"])
	if not agent.is_alive(): return
	# 9. Void Bolt — burn face
	await _play_spells_by_id(_BURN_IDS)
	if not agent.is_alive(): return
	# 9. Fallback — Abyssal Sacrifice (draw) + anything else
	await _play_spells_pass()
	if not agent.is_alive(): return
	await _play_minions_pass()
	if not agent.is_alive(): return
	await _play_traps_pass()

## Returns true when AoE clear should be cast before spending mana on minions.
## Conditions: abyssal_plague in hand, affordable, and would kill 3+ enemies
## OR opponent threatens lethal next turn.
func _should_prioritise_board_clear() -> bool:
	if agent.opponent_board.size() < 2:
		return false
	var has_plague := false
	for inst in agent.hand:
		if inst.card_data is SpellCardData and inst.card_data.id == "abyssal_plague":
			if agent.effective_spell_cost(inst.card_data as SpellCardData) <= agent.mana:
				has_plague = true
				break
	if not has_plague:
		return false
	# Count enemies that would die to 200 AoE
	var killable := 0
	for m in agent.opponent_board:
		if m.current_health <= 200:
			killable += 1
	if killable >= 3:
		return true
	# Also prioritise if opponent burst (including frenzy) threatens lethal
	if _estimate_enemy_burst() >= agent.friendly_hp:
		return true
	return false

## Returns true if casting abyssal_plague would kill enough minions to drop
## enemy burst below player HP — making smoke_veil unnecessary.
func _plague_prevents_lethal() -> bool:
	# Check if plague is in hand and affordable
	var has_plague := false
	for inst in agent.hand:
		if inst.card_data is SpellCardData and inst.card_data.id == "abyssal_plague":
			if agent.effective_spell_cost(inst.card_data as SpellCardData) <= agent.mana:
				has_plague = true
				break
	if not has_plague:
		return false
	# Simulate board after 100 AoE damage — estimate surviving burst
	var surviving_atk := 0
	var surviving_feral := 0
	for m in agent.opponent_board:
		if m.current_health > 100:  # survives plague
			surviving_atk += m.effective_atk()
			if m.card_data is MinionCardData and "feral_imp" in (m.card_data as MinionCardData).minion_tags:
				surviving_feral += 1
	# Add frenzy potential for survivors
	if surviving_feral > 0 and agent.scene:
		var ai = agent.scene.get("enemy_ai")
		if ai and ai.mana >= 2:
			surviving_atk += surviving_feral * 250
	return surviving_atk < agent.friendly_hp

## Estimate enemy board burst damage, including Pack Frenzy potential.
## If enemy has feral imps and enough mana for Pack Frenzy (+250 ATK all imps + SWIFT),
## add the buffed ATK to the estimate. EXHAUSTED imps gain SWIFT so they also attack.
func _estimate_enemy_burst() -> int:
	var total_atk := 0
	var feral_count := 0
	for m in agent.opponent_board:
		total_atk += m.effective_atk()
		if m.card_data is MinionCardData and "feral_imp" in (m.card_data as MinionCardData).minion_tags:
			feral_count += 1
			# EXHAUSTED feral imps can't currently attack but Pack Frenzy grants SWIFT
			if m.state == Enums.MinionState.EXHAUSTED and m.attack_count == 0:
				total_atk += m.effective_atk()  # count them as attackers too
	# If enemy could cast Pack Frenzy (2M with ancient_frenzy, 3M without), add +250 per feral imp
	if feral_count > 0 and agent.scene:
		var enemy_mana: int = 0
		var ai = agent.scene.get("enemy_ai")
		if ai:
			enemy_mana = ai.mana if "mana" in ai else 0
		# Pack Frenzy costs 3M (2M with ancient_frenzy discount)
		if enemy_mana >= 2:
			total_atk += feral_count * 250
	return total_atk

## Returns true when enemy burst damage is >= 50% of player's current HP.
func _enemy_threatens_heavy_damage() -> bool:
	return _estimate_enemy_burst() * 2 >= agent.friendly_hp

## Place Smoke Veil when enemy burst could kill the player next turn.
func _should_place_smoke_veil() -> bool:
	if agent.opponent_board.is_empty():
		return false
	if _estimate_enemy_burst() < agent.friendly_hp:
		return false
	# Check if we have smoke_veil in hand and can afford it
	for inst in agent.hand:
		if inst.card_data is TrapCardData and inst.card_data.id == "smoke_veil":
			if inst.effective_cost() <= agent.mana:
				# Don't place if a non-rune trap is already active
				if agent.scene:
					var traps = agent.scene.get("active_traps")
					if traps is Array:
						for t in traps:
							if t is TrapCardData and not (t as TrapCardData).is_rune:
								return false
				return true
	return false

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
		"arcane_strike":
			# Only cast when it kills at least one enemy minion (HP ≤ 300)
			for m in agent.opponent_board:
				if m.current_health <= 300:
					return true
			return false
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
				(m.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN):
			return 700
	return 500

# ---------------------------------------------------------------------------
# Spell targeting
# ---------------------------------------------------------------------------

func pick_spell_target(spell: SpellCardData):
	if spell.id == "arcane_strike":
		return _pick_arcane_strike_target()
	if spell.id == "void_execution":
		return _pick_void_execution_target()
	return super.pick_spell_target(spell)

## Pick best arcane_strike target (300 damage).
## Priority: champion we can finish off (with trades), then highest ATK+HP killable.
func _pick_arcane_strike_target() -> MinionInstance:
	# Check if a champion can be killed by arcane_strike + friendly minion trades
	var champion: MinionInstance = null
	for m in agent.opponent_board:
		if m.card_data is MinionCardData and Enums.Keyword.CHAMPION in (m.card_data as MinionCardData).keywords:
			champion = m
			break
	if champion != null and champion.current_health <= 300 + _available_trade_damage(champion):
		return champion
	# Fallback: highest ATK+HP enemy we can kill outright with 300 damage
	var best: MinionInstance = null
	var best_score: int = -1
	for m in agent.opponent_board:
		if m.current_health <= 300:
			var score: int = m.effective_atk() + m.current_health
			if score > best_score:
				best = m
				best_score = score
	return best

## Estimate how much damage friendly minions can deal to a target via trades.
func _available_trade_damage(target: MinionInstance) -> int:
	var total := 0
	for m in agent.friendly_board:
		if m.can_attack():
			total += m.effective_atk()
	return total

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
			# Track Void Imp on-play damage (100 per imp, fired via DAMAGE_HERO effect step)
			if mc.id == "void_imp" and agent.scene:
				var prev: int = (agent.scene.get("_void_imp_dmg") as int) if agent.scene.get("_void_imp_dmg") != null else 0
				agent.scene.set("_void_imp_dmg", prev + 100)
			placed = true
			break

## Cast all affordable spells whose ID is in ids, checking can_cast_spell each time.
## Tracks abyssal_plague fires and kills for sim analytics.
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
			# Track abyssal_plague: count board before/after to measure kills
			var pre_board := agent.opponent_board.size() if spell.id == "abyssal_plague" else 0
			# Set dmg source label BEFORE resolving so _on_hero_damaged picks it up
			if agent.scene and spell.id == "void_bolt":
				var casts: int = (agent.scene.get("_void_bolt_spell_casts") as int) if agent.scene.get("_void_bolt_spell_casts") != null else 0
				agent.scene.set("_void_bolt_spell_casts", casts + 1)
				agent.scene.set("_pending_dmg_source", "void_bolt_spell")
			if not await agent.commit_play_spell(inst, pick_spell_target(spell)):
				return
			if agent.scene and spell.id == "abyssal_plague":
				var kills: int = pre_board - agent.opponent_board.size()
				var fires: int = (agent.scene.get("_abyssal_plague_fires") as int) if agent.scene.get("_abyssal_plague_fires") != null else 0
				agent.scene.set("_abyssal_plague_fires", fires + 1)
				var total_kills: int = (agent.scene.get("_abyssal_plague_kills") as int) if agent.scene.get("_abyssal_plague_kills") != null else 0
				agent.scene.set("_abyssal_plague_kills", total_kills + kills)
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
