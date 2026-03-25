## FeralPackProfile.gd
## AI profile for the Feral Imp Pack encounter.
##
## Play phase  — two-pass: minions first (cheapest first), then spells.
##               pack_frenzy is held during play phase ("before_attacks" rule).
## Attack phase — cast pack_frenzy first if:
##                  (a) doing so achieves lethal this turn, OR
##                  (b) there are >= 3 feral imps on the board (value threshold).
##               Then run the inherited smart attack logic.
##
## Lethal simulation for pack_frenzy:
##   • NORMAL feral imps   → +250 ATK buff, can still attack hero (face pool).
##   • EXHAUSTED feral imps → +250 ATK buff + Swift grant, can only kill guards (guard pool).
##   • Other NORMAL minions → no buff, can attack hero (face pool).
##   Guard assignment uses the Swift guard pool first to preserve face attackers.
class_name FeralPackProfile
extends CombatProfile

const _PACK_FRENZY_BUFF := 250
const _FERAL_IMP_THRESHOLD := 3

func play_phase() -> void:
	await play_phase_two_pass()

func _get_spell_rules() -> Dictionary:
	return {
		"pack_frenzy":  {"cast_if": "before_attacks"},
		"feral_surge":  {"cast_if": "has_friendly_tag", "tag": "feral_imp"},
		"void_screech": {"cast_if": "board_full_or_no_minions_in_hand"},
		"cyclone":      {"cast_if": "opponent_has_rune_or_env"},
	}

func attack_phase() -> void:
	if _should_cast_pack_frenzy():
		var pf := _find_pack_frenzy()
		if pf:
			agent.mana -= agent.effective_spell_cost(pf)
			if not await agent.commit_play_spell(pf, null):
				return
	await super.attack_phase()

# ---------------------------------------------------------------------------
# Pack frenzy decision
# ---------------------------------------------------------------------------

func _should_cast_pack_frenzy() -> bool:
	var pf := _find_pack_frenzy()
	if pf == null or agent.effective_spell_cost(pf) > agent.mana:
		return false
	if _calc_lethal_with_pack_frenzy() >= agent.opponent_hp:
		return true
	var feral_count := 0
	for m in agent.friendly_board:
		if _is_feral_imp(m):
			feral_count += 1
	return feral_count >= _FERAL_IMP_THRESHOLD

# ---------------------------------------------------------------------------
# Lethal simulation including pack_frenzy effect
# ---------------------------------------------------------------------------

## Estimate face damage this turn if pack_frenzy is cast.
## NORMAL feral imps → +250 ATK → face pool (can attack hero).
## EXHAUSTED feral imps → gain Swift (+250 ATK) → guard pool (can clear guards only).
## Other NORMAL minions → no buff → face pool.
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
					guard_pool.append(buffed_atk)  # gains Swift — guard duty only
	return _sim_face_damage_with_swift_guards(guard_pool, face_pool)

## Simulate optimal guard clearing given two ATK pools.
##   guard_pool — Swift minions (EXHAUSTED feral imps gaining Swift): assign to guards first,
##                cannot attack hero even after guards are cleared.
##   face_pool  — NORMAL minions: attack hero after guards are cleared.
## Returns total face damage delivered by the face pool after guards are handled.
func _sim_face_damage_with_swift_guards(guard_pool: Array[int], face_pool: Array[int]) -> int:
	var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
	if guards.is_empty():
		# No guards — Swift guard_pool still can't attack hero; only face_pool goes face.
		var total := 0
		for a in face_pool: total += a
		return total

	var guard_hps: Array[int] = []
	for g in guards:
		guard_hps.append(g.current_health)
	guard_hps.sort()  # easiest guard first — minimize waste

	var gpool := guard_pool.duplicate()
	var fpool := face_pool.duplicate()
	gpool.sort()  # ascending: cheapest attacker first
	fpool.sort()

	for guard_hp in guard_hps:
		# Priority 1: use a Swift minion (guard pool) that can one-shot
		var idx := _min_overkill_idx(gpool, guard_hp)
		if idx >= 0:
			gpool.remove_at(idx)
			continue
		# Priority 2: use a face pool minion that can one-shot (preserve face pool)
		idx = _min_overkill_idx(fpool, guard_hp)
		if idx >= 0:
			fpool.remove_at(idx)
			continue
		# No one-shot available — burn the strongest attacker from whichever pool has more
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

	# Remaining face pool goes face; guard pool cannot attack hero (Swift)
	var face_damage := 0
	for a in fpool: face_damage += a
	return face_damage

func _min_overkill_idx(pool: Array[int], target_hp: int) -> int:
	for i in pool.size():
		if pool[i] >= target_hp:
			return i
	return -1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_pack_frenzy() -> SpellCardData:
	for c in agent.hand:
		if c is SpellCardData and c.id == "pack_frenzy":
			return c as SpellCardData
	return null

func _is_feral_imp(m: MinionInstance) -> bool:
	return agent.scene != null and agent.scene._minion_has_tag(m, "feral_imp")
