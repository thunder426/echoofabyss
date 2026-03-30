## CombatProfile.gd
## Base class for all AI profiles — enemy and player alike.
## Subclass this to define how a combatant plays cards and attacks.
##
## Profiles receive a CombatAgent (via setup()) and use its helpers to commit
## actions.  All game state lives in the CombatAgent; profiles contain only
## decision logic and, where needed, per-profile state.
##
## ── Quick-start guide for new profiles ──────────────────────────────────────
##
## Minimal profile (two-pass play, smart attack, custom spell rules):
##
##   class_name MyProfile
##   extends CombatProfile
##
##   func play_phase() -> void:
##       await play_phase_two_pass()
##
##   func _get_spell_rules() -> Dictionary:
##       return {
##           "my_spell_id": {"cast_if": "board_not_full"},
##           "my_buff_id":  {"cast_if": "has_friendly_tag", "tag": "my_tag"},
##       }
##
## Supported "cast_if" values:
##   "has_friendly_tag"                 — friendly board must have a minion with rule["tag"]
##   "board_not_full"                   — friendly board must have an empty slot
##   "opponent_has_rune_or_env"         — opponent must have an active rune or environment
##   "board_full_or_no_minions_in_hand" — hold until board full OR no minions left in hand
##
## ─────────────────────────────────────────────────────────────────────────────
class_name CombatProfile
extends RefCounted

## Perspective-agnostic game-state interface.
var agent: CombatAgent

func setup(combat_agent: CombatAgent) -> void:
	agent = combat_agent

# ---------------------------------------------------------------------------
# Virtual methods — override in each profile
# ---------------------------------------------------------------------------

## Spend resources on cards from hand.  Called once per turn before attacks.
func play_phase() -> void:
	pass

## Execute all ready minion attacks.  Called after play_phase.
## Default: guard (prefer safe trades) → lethal-threat trade → face / best kill.
## Aggro profiles (see _is_aggro): when under lethal threat but can't win this turn,
## trade to neutralise the threat first, then go face with survivors.
func attack_phase() -> void:
	var lethal_threat  := _opponent_threatens_lethal()
	var can_go_lethal  := _calc_lethal_damage() >= agent.opponent_hp
	if can_go_lethal:
		# Cast buff spells (pump minions) then damage spells before attacking face
		await _play_lethal_spells()
		if not agent.is_alive(): return
	# Aggro threat response: trade to neutralise lethal threat, then go face
	if _is_aggro() and lethal_threat and not can_go_lethal:
		await _aggro_threat_response()
		return
	for minion in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(minion) or not minion.can_attack():
			continue
		var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
		if can_go_lethal and guards.is_empty():
			# Lethal available and no taunts blocking — NORMAL go face, SWIFT clear board
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

## Override to declare per-spell cast conditions as data.
## Returns a dict mapping spell IDs → rule dicts with a "cast_if" key.
## Spells not listed always cast if affordable.
func _get_spell_rules() -> Dictionary:
	return {}

## Return true if this profile represents an aggro/swarm deck.
## Aggro profiles apply threat-reduction trading logic when under lethal threat.
func _is_aggro() -> bool:
	return false

## Called by CombatSim after profile setup so the profile can install a custom
## resource-growth strategy on the SimState.  Override to set
## state.player_growth_override to a Callable(turn: int).
## Default: no-op — SimState uses its built-in _grow_player_resources.
func setup_resource_growth(_state: Object) -> void:
	pass

## Override to provide scoring weights (ScoredCombatProfile and subclasses).
## Returning null means this profile does not use the scoring system.
func get_weights() -> ScoringWeights:
	return null

## Returns false to hold a spell this turn.
## Evaluates rules from _get_spell_rules(); override for logic not covered by rules.
func can_cast_spell(spell: SpellCardData) -> bool:
	var rules := _get_spell_rules()
	if not rules.has(spell.id):
		return true
	var rule: Dictionary = rules[spell.id]
	match rule.get("cast_if", ""):
		"has_friendly_tag":
			var tag: String = rule.get("tag", "")
			for m in agent.friendly_board:
				if m.card_data is MinionCardData and \
						tag in (m.card_data as MinionCardData).minion_tags:
					return true
			return false
		"board_not_full":
			return agent.find_empty_slot() != null
		"opponent_has_rune_or_env":
			return agent.opponent_has_rune_or_environment()
		"board_full_or_no_minions_in_hand":
			if agent.find_empty_slot() == null:
				return true
			for inst in agent.hand:
				if inst.card_data is MinionCardData:
					return false
			return true
		"before_attacks":
			return false  # held during play phase; profile handles casting in attack_phase
		_:
			return true

## Return the target for a targeted spell.
## Default minion priority: killable targets (our damage >= their HP) → highest ATK.
## Trap/env spells: runes first → environment → random hidden trap.
## Override for per-spell logic not covered by the defaults.
func pick_spell_target(spell: SpellCardData):
	match spell.target_type:
		"enemy_minion", "any_minion", "enemy_minion_or_hero":
			var pool: Array[MinionInstance] = agent.opponent_board
			if pool.is_empty():
				return null
			var killable: Array[MinionInstance] = []
			for m in pool:
				if _spell_can_kill(spell, m):
					killable.append(m)
			var candidates := killable if not killable.is_empty() else pool
			var best: MinionInstance = candidates[0]
			for m in candidates:
				if killable.is_empty():
					if m.effective_atk() > best.effective_atk():
						best = m
				else:
					if m.current_health < best.current_health:
						best = m
			return best
		"friendly_minion":
			return _pick_cheapest_friendly()
		"trap_or_env":
			return _pick_default_trap_env_target()
	return null

## Return the target for this card's on-play effect.
## Default minion priority: killable first, then highest ATK.
## Default trap/env priority: runes → environment → random hidden trap.
## Override with match mc.id for per-card logic.
func pick_on_play_target(mc: MinionCardData):
	for raw in mc.on_play_effect_steps:
		var step: EffectStep = EffectStep.from_dict(raw) if raw is Dictionary else raw as EffectStep
		if step == null:
			continue
		match step.scope:
			EffectStep.TargetScope.SINGLE_CHOSEN, EffectStep.TargetScope.SINGLE_CHOSEN_FRIENDLY:
				return _pick_default_minion_target(mc)
			EffectStep.TargetScope.SINGLE_CHOSEN_TRAP_OR_ENV:
				return _pick_default_trap_env_target()
	return null

# ---------------------------------------------------------------------------
# Reusable play-phase helpers
# ---------------------------------------------------------------------------

## Three-pass play: flood board with minions, cast spells, then play traps/runes/environments.
func play_phase_two_pass() -> void:
	await _play_minions_pass()
	if not agent.is_alive(): return
	await _play_spells_pass()
	if not agent.is_alive(): return
	await _play_traps_pass()

## Place minions until board is full or no affordable minions remain.
func _play_minions_pass() -> void:
	var placed := true
	while placed:
		placed = false
		var minion_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is MinionCardData:
				minion_hand.append(inst)
		# Last slot: prefer highest-value card to avoid wasting it on a cheap throwaway.
		# Multiple slots: cheapest-first to flood the board.
		if agent.empty_slot_count() <= 1:
			minion_hand.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
				return agent.sort_by_total_cost(b, a))
		else:
			minion_hand.sort_custom(agent.sort_by_total_cost)
		for inst in minion_hand:
			var mc := inst.card_data as MinionCardData
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

## Cast affordable spells that pass can_cast_spell, cheapest first.
func _play_spells_pass() -> void:
	var cast := true
	while cast:
		cast = false
		var spell_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is SpellCardData:
				spell_hand.append(inst)
		spell_hand.sort_custom(agent.sort_by_total_cost)
		for inst in spell_hand:
			var spell := inst.card_data as SpellCardData
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

## Play affordable traps, runes, and environments from hand.
## Environments: play the first affordable one, replacing any existing.
## Traps/runes: play all affordable ones.
func _play_traps_pass() -> void:
	var placed := true
	while placed:
		placed = false
		for inst in agent.hand.duplicate():
			if inst.card_data is EnvironmentCardData:
				var env := inst.card_data as EnvironmentCardData
				# Don't replace an environment that's already active — would waste it
				var scene: Object = agent.scene
				if scene != null and scene.get("active_environment") != null:
					continue
				if env.cost <= agent.mana:
					agent.mana -= env.cost
					if not await agent.commit_play_environment(inst):
						return
					placed = true
					break
			elif inst.card_data is TrapCardData:
				var trap_cost: int = inst.effective_cost()
				if trap_cost <= agent.mana:
					agent.mana -= trap_cost
					if not await agent.commit_play_trap(inst):
						return
					placed = true
					break

# ---------------------------------------------------------------------------
# Shared attack-phase helpers
# ---------------------------------------------------------------------------

## Returns true if total opponent board ATK >= friendly hero HP (lethal threat).
func _opponent_threatens_lethal() -> bool:
	if agent.scene == null:
		return false
	var total_atk: int = 0
	for m in agent.opponent_board:
		total_atk += m.effective_atk()
	return total_atk >= agent.friendly_hp

## Simulate optimal guard assignment given an explicit ATK pool (sorted ascending).
## For each guard: assign the lowest-ATK minion that can one-shot it to minimise overkill.
## If no single minion can one-shot, spend the strongest minions until the guard dies.
## Returns total remaining face damage from unused attackers.
func _sim_face_damage(atk_pool: Array[int]) -> int:
	var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
	var pool := atk_pool.duplicate()
	pool.sort()  # ascending — cheapest attacker first
	if guards.is_empty():
		var total := 0
		for a in pool: total += a
		return total
	var guard_hps: Array[int] = []
	for g in guards:
		guard_hps.append(g.current_health)
	guard_hps.sort()  # kill easiest guards first to free up more attackers
	for guard_hp in guard_hps:
		if pool.is_empty():
			return 0
		# Find the cheapest attacker that one-shots this guard
		var chosen := -1
		for i in pool.size():
			if pool[i] >= guard_hp:
				chosen = i
				break
		if chosen >= 0:
			pool.remove_at(chosen)
		else:
			# No single attacker can one-shot — spend strongest until guard dies
			var hp_left := guard_hp
			while hp_left > 0 and not pool.is_empty():
				hp_left -= pool.back()
				pool.remove_at(pool.size() - 1)
	var face_damage := 0
	for a in pool: face_damage += a
	return face_damage

## Estimate total damage deliverable this turn.
## Buffs are applied to the ATK pool BEFORE the guard simulation so overkill
## on guards is computed with post-buff values (e.g. 2×500 ATK + 200 buff vs
## 100 HP guard → one 700-ATK minion kills the guard, one 700 goes face = 700,
## not 1400-100=1300).
func _calc_lethal_damage() -> int:
	# Collect affordable lethal spells — buffs first, then direct damage
	var lethal_spells: Array = []
	for inst in agent.hand:
		if not (inst.card_data is SpellCardData):
			continue
		var spell := inst.card_data as SpellCardData
		var cost  := agent.effective_spell_cost(spell)
		var hero_dmg := 0
		var atk_buff := 0
		var single_atk_buff := 0
		for raw in spell.effect_steps:
			var step: EffectStep = EffectStep.from_dict(raw) if raw is Dictionary else raw as EffectStep
			if step == null:
				continue
			match step.effect_type:
				EffectStep.EffectType.DAMAGE_HERO, EffectStep.EffectType.VOID_BOLT:
					hero_dmg += step.amount
				EffectStep.EffectType.BUFF_ATK:
					if step.scope in [EffectStep.TargetScope.ALL_FRIENDLY, EffectStep.TargetScope.ALL_BOARD]:
						atk_buff += step.amount
					elif step.scope == EffectStep.TargetScope.SINGLE_CHOSEN_FRIENDLY:
						single_atk_buff += step.amount
		if hero_dmg > 0 or atk_buff > 0 or single_atk_buff > 0:
			lethal_spells.append({cost = cost, hero_dmg = hero_dmg, atk_buff = atk_buff,
					single_atk_buff = single_atk_buff})
	lethal_spells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.atk_buff > b.atk_buff)

	# Spend mana on affordable spells, accumulating total buff and direct damage
	var remaining_mana := agent.mana
	var total_atk_buff        := 0
	var total_single_atk_buff := 0
	var spell_damage          := 0
	for entry in lethal_spells:
		if entry.cost > remaining_mana:
			continue
		total_atk_buff        += entry.atk_buff
		total_single_atk_buff += entry.single_atk_buff
		spell_damage          += entry.hero_dmg
		remaining_mana        -= entry.cost

	# Build buffed ATK pool, then simulate guard assignment with post-buff values
	var atk_pool: Array[int] = []
	for m in agent.friendly_board:
		if m.can_attack() and m.can_attack_hero():
			atk_pool.append(m.effective_atk() + total_atk_buff)

	# Single-target buff: best case applies to the highest-ATK minion
	if total_single_atk_buff > 0 and not atk_pool.is_empty():
		var max_idx := 0
		for i in atk_pool.size():
			if atk_pool[i] > atk_pool[max_idx]:
				max_idx = i
		atk_pool[max_idx] += total_single_atk_buff

	return _sim_face_damage(atk_pool) + spell_damage

## Before a lethal attack: cast ALL_FRIENDLY BUFF_ATK spells first (so minions
## hit harder), then DAMAGE_HERO / VOID_BOLT spells, overriding hold rules.
func _play_lethal_spells() -> void:
	for pass_type in ["buff", "damage"]:
		for inst in agent.hand.duplicate():
			if not (inst.card_data is SpellCardData):
				continue
			var spell := inst.card_data as SpellCardData
			var cost  := agent.effective_spell_cost(spell)
			if cost > agent.mana:
				continue
			var is_buff_spell   := false
			var is_damage_spell := false
			for raw in spell.effect_steps:
				var step: EffectStep = EffectStep.from_dict(raw) if raw is Dictionary else raw as EffectStep
				if step == null:
					continue
				match step.effect_type:
					EffectStep.EffectType.DAMAGE_HERO, EffectStep.EffectType.VOID_BOLT:
						is_damage_spell = true
					EffectStep.EffectType.BUFF_ATK:
						if step.scope in [EffectStep.TargetScope.ALL_FRIENDLY, EffectStep.TargetScope.ALL_BOARD,
								EffectStep.TargetScope.SINGLE_CHOSEN_FRIENDLY]:
							is_buff_spell = true
			var should_cast: bool = (pass_type == "buff" and is_buff_spell) \
							or (pass_type == "damage" and is_damage_spell and not is_buff_spell)
			if not should_cast:
				continue
			agent.mana -= cost
			if not await agent.commit_play_spell(inst, pick_spell_target(spell)):
				return

## Pick the best guard to attack.
## Priority: guards we survive → among those, ones we can kill (lowest HP first to eliminate
## board presence) → if none killable, lowest-ATK guard (minimise damage taken).
func _pick_best_guard(attacker: MinionInstance, guards: Array[MinionInstance]) -> MinionInstance:
	var safe: Array[MinionInstance] = []
	for g in guards:
		if g.effective_atk() <= attacker.current_health:
			safe.append(g)
	var candidates := safe if not safe.is_empty() else guards
	# Among candidates, prefer ones we kill outright (lowest HP = easiest kill)
	var killable: Array[MinionInstance] = []
	for g in candidates:
		if attacker.effective_atk() >= g.current_health:
			killable.append(g)
	if not killable.is_empty():
		var best: MinionInstance = killable[0]
		for g in killable:
			if g.current_health < best.current_health:
				best = g
		return best
	# Can't kill any — attack the least dangerous (lowest ATK)
	var weakest: MinionInstance = candidates[0]
	for g in candidates:
		if g.effective_atk() < weakest.effective_atk():
			weakest = g
	return weakest

## Aggro threat response: for each attacker, trade into the most dangerous enemy
## minion until the opponent's total ATK drops below player HP, then go face with
## any remaining attackers.  Guards are handled first (mandatory targets).
func _aggro_threat_response() -> void:
	for attacker in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(attacker) or not attacker.can_attack():
			continue
		var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
		if not guards.is_empty():
			# Guards must be attacked — use fixed targeting (issue 1 fix)
			var g := _pick_best_guard(attacker, guards)
			if not await agent.do_attack_minion(attacker, g):
				return
			continue
		# Recalculate threat each iteration as enemies die
		var threat: int = 0
		for m in agent.opponent_board:
			threat += m.effective_atk()
		if threat >= agent.friendly_hp:
			# Still under lethal threat — trade to reduce it
			var target := _pick_threat_reduction_target(attacker)
			if target != null:
				if not await agent.do_attack_minion(attacker, target):
					return
			elif attacker.can_attack_hero():
				if not await agent.do_attack_hero(attacker):
					return
		else:
			# Threat neutralised — go face
			if attacker.can_attack_hero():
				if not await agent.do_attack_hero(attacker):
					return
			elif not agent.opponent_board.is_empty():
				var t := agent.pick_swift_target(attacker)
				if not await agent.do_attack_minion(attacker, t):
					return

## Choose the best threat-reduction trade target on the opponent board.
## Prefers the highest-ATK enemy we can kill outright (maximum threat removed per trade).
## Falls back to lowest-HP enemy (chip toward a kill) if nothing is one-shottable.
func _pick_threat_reduction_target(attacker: MinionInstance) -> MinionInstance:
	var pool: Array[MinionInstance] = agent.opponent_board
	if pool.is_empty():
		return null
	# Highest-ATK killable — removes the most threat per trade
	var killable: Array[MinionInstance] = []
	for m in pool:
		if attacker.effective_atk() >= m.current_health:
			killable.append(m)
	if not killable.is_empty():
		var best: MinionInstance = killable[0]
		for m in killable:
			if m.effective_atk() > best.effective_atk():
				best = m
		return best
	# Nothing one-shottable — chip at lowest HP to set up a kill next trade
	var weakest: MinionInstance = pool[0]
	for m in pool:
		if m.current_health < weakest.current_health:
			weakest = m
	return weakest

# ---------------------------------------------------------------------------
# Shared targeting helpers
# ---------------------------------------------------------------------------

## Cheapest friendly minion to sacrifice (lowest total cost; ties broken by lowest HP).
func _pick_cheapest_friendly() -> MinionInstance:
	var pool: Array[MinionInstance] = agent.friendly_board
	if pool.is_empty():
		return null
	var best: MinionInstance = pool[0]
	for m in pool:
		var mc := m.card_data as MinionCardData
		var bc := best.card_data as MinionCardData
		var m_cost  := mc.essence_cost + mc.mana_cost if mc != null else 9999
		var b_cost  := bc.essence_cost + bc.mana_cost if bc != null else 9999
		if m_cost < b_cost or (m_cost == b_cost and m.current_health < best.current_health):
			best = m
	return best

func _pick_default_minion_target(mc: MinionCardData) -> MinionInstance:
	var pool: Array[MinionInstance] = agent.opponent_board
	if pool.is_empty():
		return null
	var killable: Array[MinionInstance] = []
	for m in pool:
		if mc.atk >= m.current_health:
			killable.append(m)
	var candidates := killable if not killable.is_empty() else pool
	var best: MinionInstance = candidates[0]
	for m in candidates:
		if m.effective_atk() > best.effective_atk():
			best = m
	return best

func _pick_default_trap_env_target():
	var s = agent.scene
	if s == null:
		return null
	var runes: Array = s.active_traps.filter(func(t) -> bool: return (t as TrapCardData).is_rune)
	if not runes.is_empty():
		return runes[randi() % runes.size()]
	if s.active_environment != null:
		return s.active_environment
	if not s.active_traps.is_empty():
		return s.active_traps[randi() % s.active_traps.size()]
	return null

## Returns true if this spell's damage step can kill the target (used for targeting priority).
func _spell_can_kill(spell: SpellCardData, target: MinionInstance) -> bool:
	for raw in spell.effect_steps:
		var step: EffectStep = EffectStep.from_dict(raw) if raw is Dictionary else raw as EffectStep
		if step == null or step.effect_type != EffectStep.EffectType.DAMAGE_MINION:
			continue
		var estimated := step.amount
		match step.multiplier_key:
			"board_count":
				var board: Array = agent.friendly_board \
					if step.multiplier_board == "friendly" else agent.opponent_board
				estimated = step.amount * board.size()
			"void_marks":
				if agent.scene != null:
					estimated = step.amount * agent.scene.enemy_void_marks
		if estimated >= target.current_health:
			return true
	return false
