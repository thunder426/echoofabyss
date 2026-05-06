## HardcodedEffects.gd
## Executes card effects that cannot be expressed declaratively in EffectStep.
## Works with both CombatScene (live) and SimState (headless sim) via duck-typing —
## all state access goes through _scene, same pattern as CombatHandlers.
##
## IMPORTANT: All effects MUST be symmetric — they must work correctly when
## played by either "player" or "enemy". Use ctx.owner with _friendly_board(),
## _opponent_board(), _friendly_traps(), etc. Never hardcode player_board or
## enemy_board directly.
##
## Usage:
##   var _hardcoded := HardcodedEffects.new()
##   _hardcoded.setup(self)   # pass CombatScene or SimState
##   func _resolve_hardcoded(id, ctx): _hardcoded.resolve(id, ctx)
class_name HardcodedEffects
extends RefCounted

## The scene object — either a CombatScene node or a SimState RefCounted.
var _scene: Object

## _LogType enum values matching CombatScene (TURN=0, PLAYER=1, ENEMY=2, DAMAGE=3, HEAL=4, TRAP=5, DEATH=6)
const _LOG_PLAYER := 1
const _LOG_ENEMY  := 2
const _LOG_TRAP   := 5

func setup(scene: Object) -> void:
	_scene = scene

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
			_scene._resolve_void_devourer_sacrifice(ctx.source, ctx.owner)
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
			_scene.set("_soul_rune_fires_this_turn", 0)
		# --- Feral Imp Clan ---
		"frenzied_imp_play":
			_frenzied_imp_play(ctx)
		"brood_call":
			_brood_call(ctx)
		"pack_frenzy":
			_pack_frenzy(ctx)
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
	SacrificeSystem.sacrifice(_scene, demon, "soul_shatter")
	var dmg := 300 if pre_hp >= 300 else 200
	var ls := _log_side(ctx.owner)
	_log("  Soul Shatter: sacrifice had %d HP — %d AoE to all %s minions." % [pre_hp, dmg, _scene._opponent_of(ctx.owner)], ls)
	# abyss_order spell — VOID school per Phase 7 audit rule. (Hardcoded handler so
	# the school can't live on a damage_school field; declared at the call site.)
	var ss_info := CombatManager.make_damage_info(0, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID, null, "soul_shatter")
	for m in (_scene._opponent_board(ctx.owner) as Array).duplicate():
		_scene._spell_dmg(m, dmg, ss_info)

## Seris Starter — Grafted Butcher ON PLAY: sacrifice chosen friendly minion, then 200 AoE to opponent board.
## chosen_target is the sac target (picked via on_play_target_type = "friendly_minion_other").
func _grafted_butcher(ctx: EffectContext) -> void:
	var sac := ctx.chosen_target
	var ls := _log_side(ctx.owner)
	if sac == null or sac == ctx.source:
		_log("  Grafted Butcher: no sacrifice target — fizzle.", ls)
		return
	# Capture the sac slot centre BEFORE kill — needed by the graft tendril VFX.
	var sac_center: Vector2 = Vector2.ZERO
	var sac_slot: Variant = _scene._find_slot_for(sac)
	if sac_slot != null and is_instance_valid(sac_slot):
		sac_center = sac_slot.global_position + sac_slot.size * 0.5
	SacrificeSystem.sacrifice(_scene, sac, "grafted_butcher")
	_log("  Grafted Butcher: sacrificed %s — 200 AoE to all %s minions." % [sac.card_data.card_name, _scene._opponent_of(ctx.owner)], ls)
	# Play the VFX (skip in sim) and sync the AoE damage with its impact beat.
	if _scene.has_method("_play_grafted_butcher_vfx"):
		await _scene._play_grafted_butcher_vfx(ctx.source, sac_center, ctx.owner)
	# Grafted Butcher is a minion ON-PLAY effect — MINION-source per design rule.
	# Attacker is the butcher itself (ctx.source) for attribution.
	var gb_info := CombatManager.make_damage_info(0, Enums.DamageSource.MINION, Enums.DamageSchool.NONE, ctx.source, "grafted_butcher")
	for m in (_scene._opponent_board(ctx.owner) as Array).duplicate():
		_scene._spell_dmg(m, 200, gb_info)

## Seris Starter — Fiendish Pact: arm a pending 2-Essence discount for the NEXT Demon played this turn.
## The discount is consumed on the first Demon played (see CombatScene._consume_fiendish_pact_discount
## / SimState._consume_fiendish_pact_discount). Display-only essence_delta on hand Demons reflects
## the pending discount until consumed or turn end. Player-only — enemy Seris is not supported.
func _fiendish_pact(ctx: EffectContext) -> void:
	var ls := _log_side(ctx.owner)
	if ctx.owner != "player":
		return
	_scene.set("_fiendish_pact_pending", 2)
	# Display hint: mark every Demon in hand with essence_delta = -2 (cleared on consume or turn start).
	var hand: Array = _scene._friendly_hand(ctx.owner)
	var count := 0
	for inst in hand:
		if inst == null or inst.card_data == null:
			continue
		if not (inst.card_data is MinionCardData):
			continue
		if (inst.card_data as MinionCardData).minion_type != Enums.MinionType.DEMON:
			continue
		inst.essence_delta = mini(inst.essence_delta, -2)
		count += 1
	_log("  Fiendish Pact: next Demon costs 2 less Essence this turn (%d in hand)." % count, ls)
	if _scene.has_method("_refresh_hand_spell_costs"):
		_scene._refresh_hand_spell_costs()

# ---------------------------------------------------------------------------
# Environment passives
# ---------------------------------------------------------------------------

## #4 — dark_covenant_passive: symmetric — buffs owner's board
func _dark_covenant_passive(ctx: EffectContext) -> void:
	var board: Array = _scene._friendly_board(ctx.owner)
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
	var has_human: bool = board.any(func(m: MinionInstance) -> bool: return m.card_data.minion_type == Enums.MinionType.HUMAN)
	var has_demon: bool = board.any(func(m: MinionInstance) -> bool: return m.card_data.minion_type == Enums.MinionType.DEMON)
	if has_human:
		for m in board:
			if m.card_data.minion_type == Enums.MinionType.DEMON:
				# Defer to BuffApplyVFX's chevron beat in live combat (state
				# mutation aligned with visible value tween). Sim falls back to
				# immediate apply via the null vfx_controller check.
				if _scene.has_method("_request_buff_apply") and _scene.vfx_controller != null:
					_scene._request_buff_apply(m, Enums.BuffType.ATK_BONUS, 100, "dark_covenant", false)
				else:
					BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "dark_covenant")
					_scene._refresh_slot_for(m)
	if has_demon:
		for m in board:
			if m.card_data.minion_type == Enums.MinionType.HUMAN:
				if had_aura.has(m.get_instance_id()):
					BuffSystem.apply(m, Enums.BuffType.HP_BONUS, 100, "dark_covenant", false, false)
				elif _scene.has_method("_request_buff_apply") and _scene.vfx_controller != null:
					_scene._request_buff_apply(m, Enums.BuffType.HP_BONUS, 100, "dark_covenant", true)
				else:
					BuffSystem.apply_hp_gain(m, 100, "dark_covenant")
				_scene._refresh_slot_for(m)
	# Humans that lost the aura this tick (no demon present) may have current_health
	# above their new (lower) effective max — clamp to prevent stale overshoot.
	for m in board:
		if had_aura.has(m.get_instance_id()) and not _has_source(m, "dark_covenant"):
			var hp_cap: int = m.card_data.health + BuffSystem.sum_type(m, Enums.BuffType.HP_BONUS)
			if m.current_health > hp_cap:
				m.current_health = hp_cap
				_scene._refresh_slot_for(m)

func _has_source(minion: MinionInstance, source: String) -> bool:
	for e in minion.buffs:
		if (e as BuffEntry).source == source:
			return true
	return false

## #5 — dark_covenant_remove: symmetric — removes buffs from owner's board
func _dark_covenant_remove(ctx: EffectContext) -> void:
	for m in (_scene._friendly_board(ctx.owner) as Array):
		BuffSystem.remove_source(m, "dark_covenant")
		_scene._refresh_slot_for(m)

# ---------------------------------------------------------------------------
# Trap effects
# ---------------------------------------------------------------------------

## #7 — smoke_veil: symmetric — exhausts the opponent's board (the attacker's side)
func _smoke_veil(ctx: EffectContext) -> void:
	var opponent: String = _scene._opponent_of(ctx.owner)
	# Cancel the opponent's attack
	if opponent == "enemy":
		var ai = _scene.get("enemy_ai")
		if ai:
			ai.attack_cancelled = true
	# Exhaust all opponent minions and track damage prevented
	var dmg_prevented := 0
	for m in (_scene._opponent_board(ctx.owner) as Array):
		if m.can_attack():
			dmg_prevented += m.effective_atk()
		m.state = Enums.MinionState.EXHAUSTED
		_scene._refresh_slot_for(m)
	var fires: int = (_scene.get("_smoke_veil_fires") as int) if _scene.get("_smoke_veil_fires") != null else 0
	_scene.set("_smoke_veil_fires", fires + 1)
	var prev: int = (_scene.get("_smoke_veil_damage_prevented") as int) if _scene.get("_smoke_veil_damage_prevented") != null else 0
	_scene.set("_smoke_veil_damage_prevented", prev + dmg_prevented)
	_log("  Smoke Veil: attack cancelled! All %s minions exhausted. (%d damage prevented)" % [opponent, dmg_prevented], _LOG_TRAP)

# ---------------------------------------------------------------------------
# Rune effects
# ---------------------------------------------------------------------------

## #12 — soul_rune_death: symmetric — summons spark for rune owner when demon dies on opponent's turn
func _soul_rune_death(ctx: EffectContext) -> void:
	var fires: int = _scene.get("_soul_rune_fires_this_turn") if _scene.get("_soul_rune_fires_this_turn") != null else 0
	var soul_rune_count := 0
	for trap in _scene._friendly_traps(ctx.owner):
		if (trap as TrapCardData).is_rune and (trap as TrapCardData).rune_type == Enums.RuneType.SOUL_RUNE:
			soul_rune_count += 1
	if fires >= soul_rune_count:
		return
	# Only fires during the opponent's turn (not the rune owner's turn)
	var is_player_turn = _scene.turn_manager.get("is_player_turn")
	var is_owner_turn: bool = (is_player_turn == true) if ctx.owner == "player" else (is_player_turn == false)
	if is_owner_turn:
		return
	if ctx.trigger_minion == null or ctx.trigger_minion.card_data.minion_type != Enums.MinionType.DEMON:
		return
	_scene.set("_soul_rune_fires_this_turn", fires + 1)
	var mult: int = _scene._rune_aura_multiplier()
	_scene._summon_token("void_spark", ctx.owner, 100 * mult, 100 * mult)
	_log("  Soul Rune: Demon died — %d/%d Spirit summoned." % [100 * mult, 100 * mult], _LOG_TRAP)

# ---------------------------------------------------------------------------
# Feral Imp Clan effects (already symmetric)
# ---------------------------------------------------------------------------

func _frenzied_imp_play(ctx: EffectContext) -> void:
	var board: Array = _scene._friendly_board(ctx.owner)
	var feral_count := 0
	for m in board:
		if m != ctx.source and _scene._minion_has_tag(m, "feral_imp"):
			feral_count += 1
	var dmg := 100 + 100 * feral_count
	var frenzied_target: MinionInstance = _scene._find_random_minion(_scene._opponent_board(ctx.owner))
	if frenzied_target == null:
		_log("  Frenzied Imp: no target.", _log_side(ctx.owner))
		return
	_log("  Frenzied Imp: %d damage to %s." % [dmg, frenzied_target.card_data.card_name], _log_side(ctx.owner))
	var target_ref: MinionInstance = frenzied_target
	var src_ref: MinionInstance = ctx.source
	var apply_damage := func() -> void:
		if target_ref == null or not is_instance_valid(target_ref) or target_ref.current_health <= 0:
			return
		# Minion-emitted effect → MINION source, NONE school (per design rule:
		# only piercing_void talent retags Void minion damage; default is NONE).
		_scene._spell_dmg(target_ref, dmg,
				CombatManager.make_damage_info(0, Enums.DamageSource.MINION, Enums.DamageSchool.NONE, src_ref, "frenzied_imp"))
	# Live scene plays VFX (with impact-synced damage). Sim skips and applies immediately.
	if _scene.has_method("_play_frenzied_imp_vfx"):
		await _scene._play_frenzied_imp_vfx(ctx.source, frenzied_target, feral_count, apply_damage)
	else:
		apply_damage.call()

func _brood_call(ctx: EffectContext) -> void:
	var feral_ids: Array[String] = ["rabid_imp", "brood_imp", "imp_brawler", "void_touched_imp", "frenzied_imp", "matriarchs_broodling", "rogue_imp_elder"]
	var pick := feral_ids[randi() % feral_ids.size()]
	# Play portal VFX fully before summoning (live scene only — sim skips).
	if _scene.has_method("_play_brood_call_vfx"):
		await _scene._play_brood_call_vfx(ctx.owner)
	_scene._summon_token(pick, ctx.owner)
	_log("  Brood Call: summoned %s." % pick, _log_side(ctx.owner))

func _pack_frenzy(ctx: EffectContext) -> void:
	var feral_board: Array = _scene._friendly_board(ctx.owner).duplicate()
	var ancient_active: bool = "ancient_frenzy" in (_scene.get("_active_enemy_passives") if _scene.get("_active_enemy_passives") != null else [])

	# Collect targets + their slots up front so the VFX can sweep from hero
	# to each imp in a single synced wave.
	var targets: Array = []
	var target_slots: Array = []
	for m in feral_board:
		if _scene._minion_has_tag(m, "feral_imp"):
			targets.append(m)
			var slot: BoardSlot = _scene._find_slot_for(m)
			if slot != null:
				target_slots.append(slot)

	# Play the warcry and await impact before applying buffs — ATK pop lands
	# synced to the first imp's ignition burst. VFX owns the full buff visual.
	if not target_slots.is_empty() and _scene.has_method("_play_pack_frenzy_vfx"):
		await _scene._play_pack_frenzy_vfx(ctx.owner, target_slots, ancient_active)

	for m in targets:
		BuffSystem.apply(m, Enums.BuffType.TEMP_ATK, 250, "pack_frenzy", true)
		if m.state == Enums.MinionState.EXHAUSTED and m.attack_count == 0:
			m.state = Enums.MinionState.SWIFT
		if ancient_active:
			BuffSystem.apply(m, Enums.BuffType.GRANT_LIFEDRAIN, 1, "pack_frenzy", true)
		_scene._refresh_slot_for(m)
		if _scene.has_method("_spawn_atk_chevron"):
			_scene._spawn_atk_chevron(m)
		if ancient_active and _scene.has_method("_pulse_lifedrain_icon"):
			_scene._pulse_lifedrain_icon(m)

	var frenzy_msg := "  Pack Frenzy: all Feral Imps +250 ATK and SWIFT"
	if ancient_active:
		frenzy_msg += " and LIFEDRAIN (Ancient Frenzy)"
	_log(frenzy_msg + ".", _log_side(ctx.owner))

# ---------------------------------------------------------------------------
# Logging helper
# ---------------------------------------------------------------------------

func _log(msg: String, type: int = _LOG_PLAYER) -> void:
	_scene._log(msg, type)
