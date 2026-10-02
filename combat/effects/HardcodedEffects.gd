## HardcodedEffects.gd
## Executes card effects that cannot be expressed declaratively in EffectStep.
## Reads and writes gameplay only through the typed CombatState, like
## CombatHandlers; presentation follows from the journal (plan 4.4).
##
## IMPORTANT: All effects MUST be symmetric — they must work correctly when
## played by either "player" or "enemy". Use ctx.owner with _friendly_board(),
## _opponent_board(), _friendly_traps(), etc. Never hardcode player_board or
## enemy_board directly.
##
## Usage:
##   var _hardcoded := HardcodedEffects.new()
##   _hardcoded.setup(state)   # CombatState.setup_combat
##   _hardcoded.resolve(id, ctx)
class_name HardcodedEffects
extends RefCounted

## The combat state — every gameplay read and write.
var state: CombatState

## Log line types (Enums.LogType) this file uses.
const _LOG_PLAYER := Enums.LogType.PLAYER
const _LOG_ENEMY  := Enums.LogType.ENEMY
const _LOG_TRAP   := Enums.LogType.TRAP

func setup(p_state: CombatState) -> void:
	state = p_state

func _log_side(owner: String) -> int:
	return _LOG_PLAYER if owner == "player" else _LOG_ENEMY

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

func resolve(id: String, ctx: EffectContext) -> void:
	match id:
		# --- Spell effects ---
		"soul_shatter":
			_soul_shatter(ctx)
		"grafted_butcher":
			_grafted_butcher(ctx)
		"fiendish_pact":
			_fiendish_pact(ctx)
		"void_devourer_sacrifice":
			state._resolve_void_devourer_sacrifice(ctx.source, ctx.owner)
		# --- Environment passives ---
		"dark_covenant_passive":
			_dark_covenant_passive(ctx)
		"dark_covenant_remove":
			_dark_covenant_remove(ctx)
		# --- Trap effects ---
		"smoke_veil":
			_smoke_veil(ctx)
		# --- Rune effects ---
		"soul_rune_death":
			_soul_rune_death(ctx)
		"soul_rune_reset":
			state._soul_rune_fires_this_turn = 0
		# --- Feral Imp Clan ---
		"frenzied_imp_play":
			_frenzied_imp_play(ctx)
		"brood_call":
			_brood_call(ctx)
		"pack_frenzy":
			_pack_frenzy(ctx)
		# --- Korrath — Battle Drillmaster cascade ---
		"battle_drillmaster_cascade":
			_battle_drillmaster_cascade(ctx)
		# --- Seris Corruption Engine ---

# ---------------------------------------------------------------------------
# Spell effects
# ---------------------------------------------------------------------------

## #1 — soul_shatter: symmetric — damages opponent board
func _soul_shatter(ctx: EffectContext) -> void:
	var demon := ctx.chosen_target
	if demon == null:
		return
	var pre_hp: int = demon.current_health
	SacrificeSystem.sacrifice(state, demon, "soul_shatter")
	var dmg := 300 if pre_hp >= 300 else 200
	var ls := _log_side(ctx.owner)
	_log("  Soul Shatter: sacrifice had %d HP — %d AoE to all %s minions." % [pre_hp, dmg, state._opponent_of(ctx.owner)], ls)
	# abyss_order spell — VOID school per Phase 7 audit rule. (Hardcoded handler so
	# the school can't live on a damage_school field; declared at the call site.)
	var ss_info := CombatManager.make_damage_info(0, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID, null, "soul_shatter")
	for m in (state._opponent_board(ctx.owner) as Array).duplicate():
		state._spell_dmg(m, dmg, ss_info)

## Seris Starter — Grafted Butcher ON PLAY: sacrifice chosen friendly minion, then 200 AoE to opponent board.
## chosen_target is the sac target (picked via on_play_target_type = "friendly_minion_other").
func _grafted_butcher(ctx: EffectContext) -> void:
	var sac := ctx.chosen_target
	var ls := _log_side(ctx.owner)
	if sac == null or sac == ctx.source:
		_log("  Grafted Butcher: no sacrifice target — fizzle.", ls)
		return
	SacrificeSystem.sacrifice(state, sac, "grafted_butcher")
	_log("  Grafted Butcher: sacrificed %s — 200 AoE to all %s minions." % [sac.card_data.card_name, state._opponent_of(ctx.owner)], ls)
	# The graft + cleaver VFX is a journal event; the AoE lands now (plan 3.0).
	state.emit_event(CombatEvent.Kind.VFX, ctx.owner, {name = "grafted_butcher", butcher = ctx.source, sac = sac})
	# Grafted Butcher is a minion ON-PLAY effect — MINION-source per design rule.
	# Attacker is the butcher itself (ctx.source) for attribution.
	var gb_info := CombatManager.make_damage_info(0, Enums.DamageSource.MINION, Enums.DamageSchool.NONE, ctx.source, "grafted_butcher")
	for m in (state._opponent_board(ctx.owner) as Array).duplicate():
		state._spell_dmg(m, 200, gb_info)

## Seris Starter — Fiendish Pact: arm a pending 2-Essence discount for the NEXT Demon played this turn.
## The discount is consumed on the first Demon played (see CombatScene._consume_fiendish_pact_discount
## . Display-only essence_delta on hand Demons reflects
## the pending discount until consumed or turn end. Symmetric: enemy casts arm
## `_enemy_fiendish_pact_pending` on the state.
func _fiendish_pact(ctx: EffectContext) -> void:
	var ls := _log_side(ctx.owner)
	if ctx.owner == "player":
		state._fiendish_pact_pending = 2
	else:
		state._enemy_fiendish_pact_pending = 2
	# Display hint: mark every Demon in the caster's hand with essence_delta = -2 (cleared on consume or turn start).
	var hand: Array[CardInstance] = state.hand_of(ctx.owner)
	var count := 0
	for inst in hand:
		if inst == null or inst.card_data == null:
			continue
		if not (inst.card_data is MinionCardData):
			continue
		if not (inst.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
			continue
		inst.essence_delta = mini(inst.essence_delta, -2)
		count += 1
	_log("  Fiendish Pact: next Demon costs 2 less Essence this turn (%d in hand)." % count, ls)
	state.emit_event(CombatEvent.Kind.HAND_COSTS_CHANGED, ctx.owner)

# ---------------------------------------------------------------------------
# Environment passives
# ---------------------------------------------------------------------------

## #4 — dark_covenant_passive: symmetric — buffs owner's board
func _dark_covenant_passive(ctx: EffectContext) -> void:
	var board: Array = state._friendly_board(ctx.owner)
	# Snapshot which minions already had the aura before we strip it. Humans that
	# retained the aura keep their +100 max HP unchanged (just re-add the buff
	# entry); humans newly gaining the aura get apply_hp_gain so current_health
	# rises with the cap. Without this distinction, a per-turn re-apply would
	# either grow current_health unboundedly (always apply_hp_gain) or fail to
	# heal newly-eligible humans (always plain apply).
	var had_aura: Dictionary = {}
	for m in board:
		if _has_source(m, "dark_covenant"):
			had_aura[m.get_instance_id()] = true
		BuffSystem.remove_source(m, "dark_covenant")
	var has_human: bool = board.any(func(m: MinionInstance) -> bool: return (m.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN))
	var has_demon: bool = board.any(func(m: MinionInstance) -> bool: return (m.card_data as MinionCardData).is_race(Enums.MinionType.DEMON))
	if has_human:
		for m in board:
			if (m.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
				var atk_before: int = m.effective_atk()
				var hp_before: int = m.current_health
				BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "dark_covenant")
				state.emit_event(CombatEvent.Kind.BUFF_APPLIED, ctx.owner, {minion = m, source_tag = "dark_covenant",
						atk_before = atk_before, atk_after = m.effective_atk(), hp_before = hp_before, hp_after = m.current_health, silent = false})
				state._refresh_slot_for(m)
	if has_demon:
		for m in board:
			if (m.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN):
				if had_aura.has(m.get_instance_id()):
					BuffSystem.apply(m, Enums.BuffType.HP_BONUS, 100, "dark_covenant", false, false)
				else:
					var atk_before_hp: int = m.effective_atk()
					var hp_before_hp: int = m.current_health
					BuffSystem.apply_hp_gain(m, 100, "dark_covenant")
					state.emit_event(CombatEvent.Kind.BUFF_APPLIED, ctx.owner, {minion = m, source_tag = "dark_covenant",
							atk_before = atk_before_hp, atk_after = m.effective_atk(), hp_before = hp_before_hp, hp_after = m.current_health, silent = false})
				state._refresh_slot_for(m)
	# Humans that lost the aura this tick (no demon present) may have current_health
	# above their new (lower) effective max — clamp to prevent stale overshoot.
	for m in board:
		if had_aura.has(m.get_instance_id()) and not _has_source(m, "dark_covenant"):
			var hp_cap: int = m.card_data.health + BuffSystem.sum_type(m, Enums.BuffType.HP_BONUS)
			if m.current_health > hp_cap:
				m.current_health = hp_cap
				state._refresh_slot_for(m)

func _has_source(minion: MinionInstance, source: String) -> bool:
	for e in minion.buffs:
		if (e as BuffEntry).source == source:
			return true
	return false

## #5 — dark_covenant_remove: symmetric — removes buffs from owner's board
func _dark_covenant_remove(ctx: EffectContext) -> void:
	for m in (state._friendly_board(ctx.owner) as Array):
		BuffSystem.remove_source(m, "dark_covenant")
		state._refresh_slot_for(m)

# ---------------------------------------------------------------------------
# Trap effects
# ---------------------------------------------------------------------------

## #7 — smoke_veil: symmetric — exhausts the opponent's board (the attacker's side)
func _smoke_veil(ctx: EffectContext) -> void:
	var opponent: String = state._opponent_of(ctx.owner)
	# Cancel the opponent's attack
	if opponent == "enemy":
		state.attack_cancelled = true
	# Exhaust all opponent minions and track damage prevented
	var dmg_prevented := 0
	for m in (state._opponent_board(ctx.owner) as Array):
		if m.can_attack():
			dmg_prevented += m.effective_atk()
		m.state = Enums.MinionState.EXHAUSTED
		state._refresh_slot_for(m)
	var fires: int = state._smoke_veil_fires
	state._smoke_veil_fires = fires + 1
	var prev: int = state._smoke_veil_damage_prevented
	state._smoke_veil_damage_prevented = prev + dmg_prevented
	_log("  Smoke Veil: attack cancelled! All %s minions exhausted. (%d damage prevented)" % [opponent, dmg_prevented], _LOG_TRAP)

# ---------------------------------------------------------------------------
# Rune effects
# ---------------------------------------------------------------------------

## #12 — soul_rune_death: symmetric — summons spark for rune owner when demon dies on opponent's turn
func _soul_rune_death(ctx: EffectContext) -> void:
	var fires: int = state._soul_rune_fires_this_turn
	var soul_rune_count := 0
	for trap: TrapCardData in state.traps_of(ctx.owner):
		if trap.is_rune and trap.rune_type == Enums.RuneType.SOUL_RUNE:
			soul_rune_count += 1
	if fires >= soul_rune_count:
		return
	# Only fires during the opponent's turn (not the rune owner's turn)
	var is_owner_turn: bool = state.is_player_turn == (ctx.owner == "player")
	if is_owner_turn:
		return
	if ctx.trigger_minion == null or not (ctx.trigger_minion.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
		return
	state._soul_rune_fires_this_turn = fires + 1
	var mult: int = state._rune_aura_multiplier()
	state._summon_token("void_spark", ctx.owner, 100 * mult, 100 * mult)
	_log("  Soul Rune: Demon died — %d/%d Spirit summoned." % [100 * mult, 100 * mult], _LOG_TRAP)

# ---------------------------------------------------------------------------
# Feral Imp Clan effects (already symmetric)
# ---------------------------------------------------------------------------

func _frenzied_imp_play(ctx: EffectContext) -> void:
	var board: Array = state._friendly_board(ctx.owner)
	var feral_count := 0
	for m in board:
		if m != ctx.source and state._minion_has_tag(m, "feral_imp"):
			feral_count += 1
	var dmg := 100 + 100 * feral_count
	var frenzied_target: MinionInstance = state._find_random_minion(state._opponent_board(ctx.owner))
	if frenzied_target == null:
		_log("  Frenzied Imp: no target.", _log_side(ctx.owner))
		return
	_log("  Frenzied Imp: %d damage to %s." % [dmg, frenzied_target.card_data.card_name], _log_side(ctx.owner))
	# The hurl VFX is a journal event; the damage lands now (plan 3.0).
	state.emit_event(CombatEvent.Kind.VFX, ctx.owner, {name = "frenzied_imp", source = ctx.source, target = frenzied_target, count = feral_count})
	# Minion-emitted effect → MINION source, NONE school (per design rule:
	# only piercing_void talent retags Void minion damage; default is NONE).
	state._spell_dmg(frenzied_target, dmg,
			CombatManager.make_damage_info(0, Enums.DamageSource.MINION, Enums.DamageSchool.NONE, ctx.source, "frenzied_imp"))

func _brood_call(ctx: EffectContext) -> void:
	var feral_ids: Array[String] = ["rabid_imp", "brood_imp", "imp_brawler", "void_touched_imp", "frenzied_imp", "matriarchs_broodling", "rogue_imp_elder"]
	var pick: String = state.rng_pick(feral_ids)
	# The portal VFX is a journal event; the summon lands now (plan 3.0).
	state.emit_event(CombatEvent.Kind.VFX, ctx.owner, {name = "brood_call"})
	state._summon_token(pick, ctx.owner)
	_log("  Brood Call: summoned %s." % pick, _log_side(ctx.owner))

func _pack_frenzy(ctx: EffectContext) -> void:
	var feral_board: Array = state._friendly_board(ctx.owner).duplicate()
	var ancient_active: bool = "ancient_frenzy" in (state.enemy_passives)

	var targets: Array = []
	for m in feral_board:
		if state._minion_has_tag(m, "feral_imp"):
			targets.append(m)

	# The warcry VFX is a journal event that owns the full buff visual; the
	# buffs land now (plan 3.0).
	if not targets.is_empty():
		state.emit_event(CombatEvent.Kind.VFX, ctx.owner, {name = "pack_frenzy", targets = targets.duplicate(), ancient = ancient_active})

	for m in targets:
		BuffSystem.apply(m, Enums.BuffType.TEMP_ATK, 250, "pack_frenzy", true)
		if m.state == Enums.MinionState.EXHAUSTED and m.attack_count == 0:
			m.state = Enums.MinionState.SWIFT
		if ancient_active:
			BuffSystem.apply(m, Enums.BuffType.GRANT_LIFEDRAIN, 1, "pack_frenzy", true)
		state._refresh_slot_for(m)
		state.emit_event(CombatEvent.Kind.VFX, ctx.owner, {name = "atk_chevron", minion = m})
		if ancient_active:
			state.emit_event(CombatEvent.Kind.VFX, ctx.owner, {name = "lifedrain_pulse", minion = m})

	var frenzy_msg := "  Pack Frenzy: all Feral Imps +250 ATK and SWIFT"
	if ancient_active:
		frenzy_msg += " and LIFEDRAIN (Ancient Frenzy)"
	_log(frenzy_msg + ".", _log_side(ctx.owner))

# ---------------------------------------------------------------------------
# Logging helper
# ---------------------------------------------------------------------------

## Korrath common — Battle Drillmaster ON PLAY. Fires every FORMATION minion on
## the caster's side whose Formation has not yet been consumed, bypassing the
## both-sides adjacency requirement. Drillmaster itself doesn't have FORMATION
## so it's a no-op for it. Routes through CombatHandlers.fire_unconsumed_formations_cascade
## so the cascade + ON_FORMATION_TRIGGERED dispatch lives in one place (next to
## the normal Formation handler).
func _battle_drillmaster_cascade(ctx: EffectContext) -> void:
	if state == null:
		return
	var handlers: CombatHandlers = state._handlers
	if handlers == null:
		push_warning("battle_drillmaster_cascade: no _handlers on scene")
		return
	handlers.fire_unconsumed_formations_cascade(ctx.owner)

func _log(msg: String, type: int = _LOG_PLAYER) -> void:
	state._log(msg, type)
