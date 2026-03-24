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
func attack_phase() -> void:
	var lethal_threat := _opponent_threatens_lethal()
	for minion in agent.friendly_board.duplicate():
		if not agent.friendly_board.has(minion) or not minion.can_attack():
			continue
		var guards: Array[MinionInstance] = CombatManager.get_taunt_minions(agent.opponent_board)
		if not guards.is_empty():
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
			for c in agent.hand:
				if c is MinionCardData:
					return false
			return true
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
		"trap_or_environment":
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

## Two-pass play: flood board with minions (cheapest first), then cast spells.
func play_phase_two_pass() -> void:
	await _play_minions_pass()
	if not agent.is_alive(): return
	await _play_spells_pass()

## Place minions until board is full or no affordable minions remain.
func _play_minions_pass() -> void:
	var placed := true
	while placed:
		placed = false
		var minion_hand: Array[CardData] = []
		for c in agent.hand:
			if c is MinionCardData:
				minion_hand.append(c)
		minion_hand.sort_custom(agent.sort_by_total_cost)
		for card in minion_hand:
			var mc := card as MinionCardData
			if mc.essence_cost > agent.essence or mc.mana_cost > agent.mana:
				continue
			var slot: BoardSlot = agent.find_empty_slot()
			if slot == null:
				return  # board full
			agent.essence -= mc.essence_cost
			agent.mana    -= mc.mana_cost
			if not await agent.commit_play_minion(mc, slot, pick_on_play_target(mc)):
				return
			placed = true
			break

## Cast affordable spells that pass can_cast_spell, cheapest first.
func _play_spells_pass() -> void:
	var cast := true
	while cast:
		cast = false
		var spell_hand: Array[CardData] = []
		for c in agent.hand:
			if c is SpellCardData:
				spell_hand.append(c)
		spell_hand.sort_custom(agent.sort_by_total_cost)
		for card in spell_hand:
			var spell := card as SpellCardData
			var cost: int = agent.effective_spell_cost(spell)
			if cost > agent.mana:
				continue
			if not can_cast_spell(spell):
				continue
			agent.mana -= cost
			if not await agent.commit_play_spell(spell, pick_spell_target(spell)):
				return
			cast = true
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

## Prefer guards we survive attacking; fall back to the lowest-ATK guard.
func _pick_best_guard(attacker: MinionInstance, guards: Array[MinionInstance]) -> MinionInstance:
	var safe: Array[MinionInstance] = []
	for g in guards:
		if g.effective_atk() <= attacker.current_health:
			safe.append(g)
	if not safe.is_empty():
		return safe[randi() % safe.size()]
	var weakest: MinionInstance = guards[0]
	for g in guards:
		if g.effective_atk() < weakest.effective_atk():
			weakest = g
	return weakest

# ---------------------------------------------------------------------------
# Shared targeting helpers
# ---------------------------------------------------------------------------

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
