## ScoredFeralPackProfile.gd
## Scored AI profile for the Feral Imp Pack encounter.
## Combines scoring-based board evaluation with encounter-specific spell timing:
##   • Pack Frenzy held during play, cast in attack loop when lethal OR ≥3 imps
##   • Feral Surge only cast when feral imps on board
##   • Void Screech / Cyclone conditional holds
class_name ScoredFeralPackProfile
extends ScoredCombatProfile

const _PACK_FRENZY_BUFF := 250
const _FERAL_IMP_THRESHOLD := 3

# ---------------------------------------------------------------------------
# Spell rules — inherited by the scoring system via can_cast_spell()
# ---------------------------------------------------------------------------

func _get_spell_rules() -> Dictionary:
	return {
		"pack_frenzy":  {"cast_if": "before_attacks"},
		"feral_surge":  {"cast_if": "has_friendly_tag", "tag": "feral_imp"},
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":      {"cast_if": "opponent_has_rune_or_env"},
	}

# ---------------------------------------------------------------------------
# Play phase: use the original two-pass to flood board fast (swarm strategy).
# Scoring only drives the attack phase — swarm decks must flood first.
# ---------------------------------------------------------------------------

func play_phase() -> void:
	await play_phase_two_pass()

# ---------------------------------------------------------------------------
# Attack phase: Pack Frenzy timing, then original CombatProfile attack logic.
# We bypass ScoredCombatProfile's unified loop here because the original
# guard → lethal → face/swift sequence is proven for this encounter.
# The scored system contributes via _adjust hooks and evaluation framework.
# ---------------------------------------------------------------------------

func attack_phase() -> void:
	if _should_cast_pack_frenzy():
		var pf := _find_pack_frenzy()
		if pf:
			agent.mana -= agent.effective_spell_cost(pf.card_data as SpellCardData)
			if not await agent.commit_play_spell(pf, null):
				return
	# Use CombatProfile's proven attack logic (grandparent), not the scored loop
	var lethal_threat  := _opponent_threatens_lethal()
	var can_go_lethal  := _calc_lethal_damage() >= agent.opponent_hp
	if can_go_lethal:
		await _play_lethal_spells()
		if not agent.is_alive(): return
	for minion in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(minion) or not minion.can_attack():
			continue
		var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
		if can_go_lethal and guards.is_empty():
			if minion.can_attack_hero():
				if not await agent.do_attack_hero(minion):
					if not agent.is_alive(): return
			elif not agent.opponent_board.is_empty():
				var target := agent.pick_swift_target(minion)
				if not await agent.do_attack_minion(minion, target):
					if not agent.is_alive(): return
		elif not guards.is_empty():
			var target := _pick_best_guard(minion, guards)
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return
		elif lethal_threat and not agent.opponent_board.is_empty():
			var target := agent.pick_swift_target(minion)
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return
		elif minion.can_attack_hero():
			if not await agent.do_attack_hero(minion):
				if not agent.is_alive(): return
		elif not agent.opponent_board.is_empty():
			var target := agent.pick_swift_target(minion)
			if not await agent.do_attack_minion(minion, target):
				if not agent.is_alive(): return

# ---------------------------------------------------------------------------
# Pack Frenzy decision (ported from FeralPackProfile)
# ---------------------------------------------------------------------------

func _should_cast_pack_frenzy() -> bool:
	var pf := _find_pack_frenzy()
	if pf == null or agent.effective_spell_cost(pf.card_data as SpellCardData) > agent.mana:
		return false
	# Condition 1: lethal with pack frenzy
	if _calc_lethal_with_pack_frenzy() >= agent.opponent_hp:
		return true
	# Condition 2: value threshold (≥3 feral imps)
	var feral_count := 0
	for m in agent.friendly_board:
		if _is_feral_imp(m):
			feral_count += 1
	return feral_count >= _FERAL_IMP_THRESHOLD

# ---------------------------------------------------------------------------
# Lethal simulation including pack_frenzy effect
# ---------------------------------------------------------------------------

func _calc_lethal_with_pack_frenzy() -> int:
	var face_pool:  Array[int] = []
	var guard_pool: Array[int] = []
	for m in agent.friendly_board:
		var is_feral: bool = _is_feral_imp(m)
		var buffed_atk: int = m.effective_atk() + (_PACK_FRENZY_BUFF if is_feral else 0)
		if buffed_atk <= 0:
			continue
		match m.state:
			Enums.MinionState.NORMAL:
				face_pool.append(buffed_atk)
			Enums.MinionState.EXHAUSTED:
				if is_feral and m.attack_count == 0:
					guard_pool.append(buffed_atk)
	return _sim_face_damage_with_swift_guards(guard_pool, face_pool)

func _sim_face_damage_with_swift_guards(guard_pool: Array[int], face_pool: Array[int]) -> int:
	var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
	if guards.is_empty():
		var total := 0
		for a in face_pool: total += a
		return total
	var guard_hps: Array[int] = []
	for g in guards:
		guard_hps.append(g.current_health)
	guard_hps.sort()
	var gpool := guard_pool.duplicate()
	var fpool := face_pool.duplicate()
	gpool.sort()
	fpool.sort()
	for guard_hp in guard_hps:
		var idx := _min_overkill_idx(gpool, guard_hp)
		if idx >= 0:
			gpool.remove_at(idx)
			continue
		idx = _min_overkill_idx(fpool, guard_hp)
		if idx >= 0:
			fpool.remove_at(idx)
			continue
		var hp_left := guard_hp
		while hp_left > 0:
			if gpool.is_empty() and fpool.is_empty():
				return 0
			var use_guard: bool = not gpool.is_empty() and \
				(fpool.is_empty() or gpool.back() >= fpool.back())
			if use_guard:
				hp_left -= gpool.back()
				gpool.remove_at(gpool.size() - 1)
			else:
				hp_left -= fpool.back()
				fpool.remove_at(fpool.size() - 1)
	var face_damage := 0
	for a in fpool: face_damage += a
	return face_damage

func _min_overkill_idx(pool: Array[int], target_hp: int) -> int:
	for i in pool.size():
		if pool[i] >= target_hp:
			return i
	return -1

# ---------------------------------------------------------------------------
# Scoring hooks — encounter-specific adjustments
# ---------------------------------------------------------------------------

## Feral imps are more valuable because of Pack Frenzy synergy.
## An imp on board is worth more than its raw stats suggest.
func _adjust_minion_value(m: MinionInstance, base_value: float, is_friendly: bool) -> float:
	if is_friendly and _is_feral_imp(m):
		return base_value + 80.0  # Synergy bonus: imp contributes to Pack Frenzy
	return base_value

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_pack_frenzy() -> CardInstance:
	for inst in agent.hand:
		if inst.card_data is SpellCardData and (inst.card_data as SpellCardData).id == "pack_frenzy":
			return inst
	return null

func _is_feral_imp(m: MinionInstance) -> bool:
	return agent.scene != null and agent.scene._minion_has_tag(m, "feral_imp")
