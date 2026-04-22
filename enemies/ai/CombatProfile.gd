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
	# Tempo: trade only when behind on board; go face when ahead or even
	if _is_tempo() and not can_go_lethal and _is_behind_on_board():
		await _execute_tempo_trades()
		if not agent.is_alive(): return

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

## Return true if this profile represents a tempo/board-control deck.
## Tempo profiles prioritise trading into opponent minions over going face,
## unless lethal is available.
## Execute all favorable tempo trades. Goal: minimize enemy board total ATK.
##
## Trade types (in priority order):
##   1. Favored: our minion kills target and survives
##   2. Trade-up: both die, but our minion is smaller (ATK+HP < target ATK+HP)
##   3. Multi-minion kill: multiple small minions gang up to kill a high-ATK target
##
## After all good trades, remaining attackers go face.
func _execute_tempo_trades() -> void:
	# --- Pass 0: Protective trades ---
	# If an enemy minion threatens to kill our high-value minion next turn,
	# preemptively trade a cheaper minion into it to protect the big one.
	await _execute_protective_trades()
	if not agent.is_alive(): return

	var traded := true
	while traded:
		traded = false
		if agent.opponent_board.is_empty():
			break

		var best_plan: Array[MinionInstance] = []
		var best_target: MinionInstance = null
		var best_score: float = -1.0

		var attackers: Array[MinionInstance] = []
		for m: MinionInstance in agent.friendly_board:
			if m.can_attack():
				attackers.append(m)
		if attackers.is_empty():
			break

		# Must attack guards first — handled by main loop, skip tempo for guarded boards
		var guards := CombatManager.get_taunt_minions(agent.opponent_board)
		if not guards.is_empty():
			break

		for target: MinionInstance in agent.opponent_board:
			var t_hp: int = target.current_health + target.current_shield
			var t_atk: int = target.effective_atk()
			var t_value: int = t_atk + target.current_health

			# --- Single attacker options ---
			for atk: MinionInstance in attackers:
				var a_dmg: int = atk.effective_atk()
				var a_hp: int = atk.current_health
				var a_value: int = a_dmg + a_hp
				var can_kill: bool = a_dmg >= t_hp
				var survives: bool = t_atk < a_hp

				if can_kill and survives:
					# Favored: kill + survive. Skip if our ATK massively outclasses target (>2x)
					if t_atk * 2 < a_dmg:
						continue
					var score: float = t_atk + 1000.0  # +1000 bonus for surviving
					if score > best_score:
						best_score = score
						best_target = target
						best_plan = [atk]
				elif can_kill and not survives:
					# Trade-up: both die, only if our minion is smaller
					if a_value < t_value:
						var score: float = float(t_atk - a_dmg)
						if score > best_score:
							best_score = score
							best_target = target
							best_plan = [atk]

			# --- Multi-minion kill: gang up on high-value targets ---
			if t_atk >= 200:
				# Sort attackers by value ascending (sacrifice cheapest first)
				var sorted_atks: Array[MinionInstance] = attackers.duplicate()
				sorted_atks.sort_custom(func(a: MinionInstance, b: MinionInstance) -> bool:
					return (a.effective_atk() + a.current_health) < (b.effective_atk() + b.current_health))
				var plan: Array[MinionInstance] = []
				var remaining_hp: int = t_hp
				var total_friendly_value := 0
				for atk: MinionInstance in sorted_atks:
					if remaining_hp <= 0:
						break
					plan.append(atk)
					remaining_hp -= atk.effective_atk()
					total_friendly_value += atk.effective_atk() + atk.current_health
				if remaining_hp <= 0 and plan.size() > 1 and total_friendly_value < t_value:
					# Multi-kill is worth it: our total value < their value
					var score: float = float(t_atk)
					if score > best_score:
						best_score = score
						best_target = target
						best_plan = plan

		if best_target != null and not best_plan.is_empty():
			for atk: MinionInstance in best_plan:
				if not agent.friendly_board.has(atk) or not atk.can_attack():
					continue
				if not agent.opponent_board.has(best_target):
					break  # target already dead from earlier hit
				if not await agent.do_attack_minion(atk, best_target):
					if not agent.is_alive(): return
			traded = true

## Protective trades: if an enemy minion can kill our high-value minion next turn,
## trade a cheaper minion into it now.
## Example: we have 500/100 + 200/100, enemy has 100/100.
## Enemy 100 ATK kills our 500/100 → trade 200/100 into 100/100 to protect.
func _execute_protective_trades() -> void:
	var traded := true
	while traded:
		traded = false
		if agent.opponent_board.is_empty():
			break
		var guards := CombatManager.get_taunt_minions(agent.opponent_board)
		if not guards.is_empty():
			break

		# Find the biggest threat: enemy minion that can kill our most valuable minion
		var best_threat: MinionInstance = null
		var best_protected: MinionInstance = null
		var best_protector: MinionInstance = null
		var best_protected_value := 0

		for enemy: MinionInstance in agent.opponent_board:
			var e_atk: int = enemy.effective_atk()
			var e_hp: int = enemy.current_health + enemy.current_shield

			# Which of our minions does this enemy threaten? (can kill next turn)
			var threatened: MinionInstance = null
			var threatened_value := 0
			for friendly: MinionInstance in agent.friendly_board:
				if e_atk >= friendly.current_health:
					var f_value: int = friendly.effective_atk() + friendly.current_health
					if friendly.effective_atk() > threatened_value:
						threatened = friendly
						threatened_value = friendly.effective_atk()

			if threatened == null:
				continue

			# Find cheapest attacker that can kill this enemy (and is cheaper than what we protect)
			var protector: MinionInstance = null
			var protector_value := 999999
			for friendly: MinionInstance in agent.friendly_board:
				if not friendly.can_attack() or friendly == threatened:
					continue
				var f_value: int = friendly.effective_atk() + friendly.current_health
				if friendly.effective_atk() >= e_hp and f_value < protector_value:
					# Only worth it if protector is less valuable than protected
					if f_value < threatened_value:
						protector = friendly
						protector_value = f_value

			if protector != null and threatened_value > best_protected_value:
				best_threat = enemy
				best_protected = threatened
				best_protector = protector
				best_protected_value = threatened_value

		if best_threat != null and best_protector != null:
			if agent.friendly_board.has(best_protector) and agent.opponent_board.has(best_threat):
				if not await agent.do_attack_minion(best_protector, best_threat):
					if not agent.is_alive(): return
				traded = true

## True if the enemy is behind on board — opponent has more total ATK.
func _is_behind_on_board() -> bool:
	var friendly_atk := 0
	for m: MinionInstance in agent.friendly_board:
		friendly_atk += m.effective_atk()
	var opponent_atk := 0
	for m: MinionInstance in agent.opponent_board:
		opponent_atk += m.effective_atk()
	return opponent_atk > friendly_atk

func _is_tempo() -> bool:
	return false

## Called by CombatSim after profile setup so the profile can install a custom
## resource-growth strategy on the SimState.  Override to set
## state.player_growth_override to a Callable(turn: int).
## Default: no-op — SimState uses its built-in _grow_player_resources.
func setup_resource_growth(_state: Object) -> void:
	pass

## Called by EnemyAI._choose_resource_growth() each turn (after turn 1).
## Mutate enemy_ai.essence_max / enemy_ai.mana_max directly.
## Return true if handled (skips the default growth logic), false to fall through.
## Default: not handled — EnemyAI uses its own heuristic.
func grow_resources(_enemy_ai: Object) -> bool:
	return false

## Override to provide scoring weights (ScoredCombatProfile and subclasses).
## Returning null means this profile does not use the scoring system.
func get_weights() -> ScoringWeights:
	return null

## Returns false to hold a spell this turn.
## Evaluates rules from _get_spell_rules(); override for logic not covered by rules.
func can_cast_spell(spell: SpellCardData) -> bool:
	# Block summon spells if not enough board slots (respecting reserved slots for champion)
	if _spell_needs_board_slot(spell) and agent.empty_slot_count() <= _reserved_slots():
		return false
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
		"has_friendly_type":
			var type_name: String = rule.get("type", "")
			var type_val: int = Enums.MinionType.get(type_name, -1)
			for m in agent.friendly_board:
				if m.card_data is MinionCardData and \
						(m.card_data as MinionCardData).minion_type == type_val:
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
		"has_3_feral_imps":
			var imp_count := 0
			for m in agent.friendly_board:
				if agent.scene and agent.scene._minion_has_tag(m, "feral_imp"):
					imp_count += 1
			return imp_count >= 3
		"always":
			return true
		"never":
			return false
		_:
			return true

## Returns true if a spell's effect steps include a SUMMON that needs a board slot.
func _spell_needs_board_slot(spell: SpellCardData) -> bool:
	for step in spell.effect_steps:
		if (step as Dictionary).get("type", "") == "SUMMON":
			return true
		if (step as Dictionary).get("type", "") == "HARDCODED":
			var hid: String = (step as Dictionary).get("hardcoded_id", "")
			if hid in ["brood_call", "void_summoning"]:
				return true
	return false

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
		"friendly_feral_imp":
			return _pick_best_friendly_with_tag("feral_imp")
		"friendly_void_imp":
			return _pick_best_friendly_with_tag("void_imp")
		"friendly_human":
			return _pick_best_friendly_with_type(Enums.MinionType.HUMAN)
		"friendly_demon":
			return _pick_best_friendly_with_type(Enums.MinionType.DEMON)
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
	if not agent.is_alive(): return
	# Hand-jam relief: if hand is near cap and normal passes couldn't play anything
	# rule-gated, dump any castable spell to make room for draws.
	await _play_spells_relief_pass()

## Hand-jam relief pass. Triggered when hand is near cap (>=9) — bypasses
## _get_spell_rules() gating so the AI doesn't brick holding uncastable cards.
## Still respects mana, board-slot requirements for summon spells, and target
## availability. Skips spells explicitly gated "never".
func _play_spells_relief_pass() -> void:
	const HAND_JAM_THRESHOLD: int = 9
	if agent.hand.size() < HAND_JAM_THRESHOLD:
		return
	var cast := true
	while cast and agent.hand.size() >= HAND_JAM_THRESHOLD:
		cast = false
		var spell_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is SpellCardData and inst.card_data.void_spark_cost <= 0:
				spell_hand.append(inst)
		spell_hand.sort_custom(agent.sort_by_total_cost)
		var rules := _get_spell_rules()
		for inst in spell_hand:
			var spell := inst.card_data as SpellCardData
			var cost: int = agent.effective_spell_cost(spell)
			if cost > agent.mana:
				continue
			# Skip explicit "never" rules — profile is deliberately withholding
			if rules.has(spell.id) and (rules[spell.id] as Dictionary).get("cast_if", "") == "never":
				continue
			# Respect board-slot reservation for summon spells
			if _spell_needs_board_slot(spell) and agent.empty_slot_count() <= _reserved_slots():
				continue
			var target: Variant = pick_spell_target(spell)
			# If spell requires a target but none is available, skip
			if spell.requires_target and target == null:
				continue
			agent.mana -= cost
			if not await agent.commit_play_spell(inst, target):
				return
			cast = true
			break

## How many board slots to keep free for champion/ritual summons.
## Override in profiles that need space for triggered summons.
func _reserved_slots() -> int:
	if agent.scene == null:
		return 0
	# Default: reserve 1 slot if champion hasn't been summoned yet
	var champion_summoned: Variant = agent.scene.get("_champion_summon_count")
	if champion_summoned != null and (champion_summoned as int) > 0:
		return 0
	# Check if this encounter even has a champion passive
	var passives: Variant = agent.scene.get("_active_enemy_passives")
	if passives == null:
		return 0
	for p in (passives as Array):
		if (p as String).begins_with("champion_"):
			return 1
	return 0

## Place minions until board is full or no affordable minions remain.
## Respects _reserved_slots() to keep room for champion/ritual summons.
func _play_minions_pass() -> void:
	var placed := true
	while placed:
		placed = false
		var minion_hand: Array[CardInstance] = []
		for inst in agent.hand:
			if inst.card_data is MinionCardData and inst.card_data.void_spark_cost <= 0:
				minion_hand.append(inst)
		var reserved: int = _reserved_slots()
		# Last slot (accounting for reserved): prefer highest-value card.
		if agent.empty_slot_count() <= 1 + reserved:
			minion_hand.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
				return agent.sort_by_total_cost(b, a))
		else:
			minion_hand.sort_custom(agent.sort_by_total_cost)
		for inst in minion_hand:
			var mc := inst.card_data as MinionCardData
			var ess_cost: int = agent.effective_minion_essence_cost(mc)
			var mana_cost: int = agent.effective_minion_mana_cost(mc)
			if ess_cost > agent.essence or mana_cost > agent.mana:
				continue
			if agent.empty_slot_count() <= reserved:
				return  # keep slots reserved
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return
			agent.essence -= ess_cost
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
			if inst.card_data is SpellCardData and inst.card_data.void_spark_cost <= 0:
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
## Pick the highest-ATK friendly minion that has the given tag.
func _pick_best_friendly_with_tag(tag: String) -> MinionInstance:
	var best: MinionInstance = null
	for m: MinionInstance in agent.friendly_board:
		if agent.scene != null and agent.scene._minion_has_tag(m, tag):
			if best == null or m.effective_atk() > best.effective_atk():
				best = m
	return best

## Pick the highest-ATK friendly minion of the given MinionType.
func _pick_best_friendly_with_type(mtype: Enums.MinionType) -> MinionInstance:
	var best: MinionInstance = null
	for m: MinionInstance in agent.friendly_board:
		if m.card_data.minion_type == mtype:
			if best == null or m.effective_atk() > best.effective_atk():
				best = m
	return best

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

# ---------------------------------------------------------------------------
# Shared spark-cost helpers (Act 3 + Act 4)
# ---------------------------------------------------------------------------

## Deck archetype for fuel attack priority.
enum DeckType { AGGRO, TEMPO }

## Effective spark cost after passive discounts:
##   - captain_orders: Throne's Command costs 1 less spark (min 0)
##   - void_mastery: halves all spark costs (min 1)
##   - void_herald champion: all spark costs become 0
func _effective_spark_cost(card: CardData) -> int:
	var base: int = card.void_spark_cost
	if base <= 0:
		return 0
	# Void Herald champion aura: all spark costs become 0
	var vh_alive: bool = agent.scene.get("_champion_vh_summoned") if agent.scene.get("_champion_vh_summoned") != null else false
	if vh_alive:
		# Check champion is actually on the board
		for m: MinionInstance in agent.friendly_board:
			if m.card_data.id == "champion_void_herald":
				return 0
	var cost: int = base
	var passives = agent.scene.get("_active_enemy_passives")
	# ritualist_spark_free (F13 Void Ritualist Prime): all spark costs become 0 for spells.
	if passives != null and "ritualist_spark_free" in passives and card is SpellCardData:
		return 0
	# captain_orders: Throne's Command costs 1 less spark
	if passives != null and "captain_orders" in passives and card.id == "thrones_command":
		cost = maxi(cost - 1, 0)
	if passives != null and "void_mastery" in passives:
		return maxi(ceili(float(cost) / 2.0), 1)
	return cost

## True if a spark-cost card can be played (resource + spark check).
func _can_afford_spark_card(card: CardData) -> bool:
	# Only applies to cards that have a base spark cost
	if card.void_spark_cost <= 0:
		return false
	var spark_cost: int = _effective_spark_cost(card)
	# mana_for_spark passive (F14): spark shortfall can be paid 1 extra Mana each.
	var extra_mana_for_sparks := _mana_for_spark_shortfall(spark_cost)
	# spark_cost can be 0 if Void Herald aura is active — that's affordable
	if spark_cost > 0 and extra_mana_for_sparks == 0 and not _can_afford_sparks(spark_cost):
		return false
	if card is SpellCardData:
		var spell := card as SpellCardData
		return agent.effective_spell_cost(spell) + extra_mana_for_sparks <= agent.mana
	elif card is MinionCardData:
		var mc := card as MinionCardData
		var mana_cost: int = agent.effective_minion_mana_cost(mc) + extra_mana_for_sparks
		return agent.effective_minion_essence_cost(mc) <= agent.essence and mana_cost <= agent.mana
	return false

## With mana_for_spark passive: returns extra mana needed to cover spark shortfall.
## Returns 0 if passive inactive OR board already has enough sparks.
## Returns -1 when passive inactive and board is short (caller should treat as unaffordable).
func _mana_for_spark_shortfall(spark_cost: int) -> int:
	if spark_cost <= 0:
		return 0
	var available: int = _available_sparks()
	if available >= spark_cost:
		return 0
	var passives = agent.scene.get("_active_enemy_passives")
	if passives != null and "mana_for_spark" in passives:
		return spark_cost - available
	return 0  # Caller will fail the spark check separately

## Total spark value available on the friendly board.
## Uses effective_spark_value which respects spirit_resonance passive.
func _available_sparks() -> int:
	var total := 0
	for m: MinionInstance in agent.friendly_board:
		total += m.effective_spark_value(agent.scene)
	return total

## True if the board has enough spark fuel to pay the given cost.
func _can_afford_sparks(cost: int) -> bool:
	return cost <= 0 or _available_sparks() >= cost

## Plan which minions to consume for a spark cost. Returns an array of
## MinionInstances to consume, or empty if payment is not possible.
## Rules:
##   - Only minions with spark_value > 0 are eligible
##   - Block minions with spark_value > cost (don't waste big bodies on small cards)
##   - spark_value == cost is allowed (exact match)
##   - Prefer fewest bodies: sort eligible by spark_value descending, greedily pick
func _plan_spark_payment(cost: int) -> Array[MinionInstance]:
	if cost <= 0:
		return []

	# Gather all eligible fuel (effective spark_value > 0 and not bigger than cost)
	var eligible: Array[MinionInstance] = []
	for m: MinionInstance in agent.friendly_board:
		var sv: int = m.effective_spark_value(agent.scene)
		if sv > 0 and sv <= cost:
			eligible.append(m)

	# Sort by spark_value descending (pick biggest first = fewest bodies consumed)
	eligible.sort_custom(func(a: MinionInstance, b: MinionInstance) -> bool:
		return a.effective_spark_value(agent.scene) > b.effective_spark_value(agent.scene))

	var plan: Array[MinionInstance] = []
	var remaining := cost

	for m: MinionInstance in eligible:
		if remaining <= 0:
			break
		plan.append(m)
		remaining -= m.effective_spark_value(agent.scene)

	if remaining > 0:
		# mana_for_spark passive: shortfall is paid in extra Mana, not fuel.
		# Return whatever plan we have — caller reads _mana_for_spark_shortfall to pay extra.
		var passives = agent.scene.get("_active_enemy_passives")
		if passives != null and "mana_for_spark" in passives:
			return plan
		return []  # Can't afford
	return plan

## Execute a planned spark payment. Lets fuel attack before consuming them.
## Void Sparks always go face (they die to any trade). Spirits use deck_type rules.
## All consumption is silent — NO death triggers fire.
func _pay_sparks_smart(plan: Array[MinionInstance], deck_type: DeckType) -> void:
	# Let each fuel minion attack first if it can
	for m: MinionInstance in plan:
		if not m.can_attack():
			continue
		if not agent.is_alive():
			return
		if (m.card_data as MinionCardData).spark_value == 1:
			# 1-value fuel (Void Sparks, Void Wisps) — hit face, they die to any trade
			await _fuel_attack(DeckType.AGGRO, m)
		else:
			await _fuel_attack(deck_type, m)

	# Now consume all planned fuel
	for m: MinionInstance in plan:
		if agent.friendly_board.has(m):
			agent.consume_minion(m)

## Simple pay without pre-attack (backwards compat for Act 3 profiles).
func _pay_sparks(cost: int) -> bool:
	var plan := _plan_spark_payment(cost)
	if plan.is_empty() and cost > 0:
		return false
	for m: MinionInstance in plan:
		if agent.friendly_board.has(m):
			agent.consume_minion(m)
	return true

# ---------------------------------------------------------------------------
# Fuel attack — let a spirit get value before being consumed
# ---------------------------------------------------------------------------

## Let a spirit about to be consumed attack first.
## Tempo: kill minion > trade minion > face > don't attack
## Aggro: face > kill minion > trade minion > don't attack
## Constraint: spirit must survive the trade (we need the body to consume).
func _fuel_attack(deck_type: DeckType, spirit: MinionInstance) -> void:
	if not spirit.can_attack():
		return

	var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
	var pool: Array[MinionInstance] = guards if not guards.is_empty() else agent.opponent_board.duplicate()

	# Find killable targets (spirit survives)
	var killable: Array[MinionInstance] = []
	for t: MinionInstance in pool:
		var total_hp: int = t.current_health + t.current_shield
		if spirit.effective_atk() >= total_hp and t.effective_atk() < spirit.current_health:
			killable.append(t)

	# Find survivable targets (spirit survives but doesn't kill)
	var survivable: Array[MinionInstance] = []
	for t: MinionInstance in pool:
		if t.effective_atk() < spirit.current_health and t not in killable:
			survivable.append(t)

	var can_face: bool = guards.is_empty() and spirit.can_attack_hero()

	if deck_type == DeckType.AGGRO:
		# Aggro: face > kill > trade > skip
		if can_face:
			await agent.do_attack_hero(spirit)
		elif not killable.is_empty():
			await agent.do_attack_minion(spirit, _pick_highest_value(killable))
		elif not survivable.is_empty():
			await agent.do_attack_minion(spirit, _pick_highest_value(survivable))
		# else: don't attack — all trades would kill us
	else:
		# Tempo: kill > trade > face > skip
		if not killable.is_empty():
			await agent.do_attack_minion(spirit, _pick_highest_value(killable))
		elif not survivable.is_empty():
			await agent.do_attack_minion(spirit, _pick_highest_value(survivable))
		elif can_face:
			await agent.do_attack_hero(spirit)
		# else: don't attack

## Pick the highest-value target from a pool (HP + Shield + ATK sum).
func _pick_highest_value(pool: Array[MinionInstance]) -> MinionInstance:
	var best: MinionInstance = pool[0]
	var best_value: int = 0
	for m: MinionInstance in pool:
		var value: int = m.current_health + m.current_shield + m.effective_atk()
		if value > best_value:
			best = m
			best_value = value
	return best

# ---------------------------------------------------------------------------
# Shared spell helpers
# ---------------------------------------------------------------------------

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
