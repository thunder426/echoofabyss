## HardcodedEffects.gd
## Executes card effects that cannot be expressed declaratively in EffectStep.
## Works with both CombatScene (live) and SimState (headless sim) via duck-typing —
## all state access goes through _scene, same pattern as CombatHandlers.
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

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

func resolve(id: String, ctx: EffectContext) -> void:
	match id:
		# --- Spell effects ---
		"soul_shatter":
			_soul_shatter(ctx)
		"void_devourer_sacrifice":
			_scene._resolve_void_devourer_sacrifice(ctx.source, ctx.owner)
		"void_detonation_effect":
			_void_detonation(ctx)
		"destroy_random_enemy_trap":
			_destroy_random_enemy_trap(ctx)
		"spell_taxer_effect":
			if ctx.owner == "player":
				var _cur_tax = _scene.get("_spell_tax_for_enemy_turn")
				_scene.set("_spell_tax_for_enemy_turn", (_cur_tax if _cur_tax != null else 0) + 1)
				_log("  Spell Taxer: enemy spells cost +1 Mana next turn.", _LOG_PLAYER)
			elif ctx.owner == "enemy":
				var _cur_tax = _scene.get("_spell_tax_for_player_turn")
				_scene.set("_spell_tax_for_player_turn", (_cur_tax if _cur_tax != null else 0) + 1)
				_log("  Spell Taxer: player spells cost +1 Mana next turn.", _LOG_ENEMY)
		"saboteur_adept_effect":
			if ctx.owner == "player":
				_log("  Saboteur Adept: enemy traps blocked this turn (not yet active).", _LOG_PLAYER)
		# --- Environment passives ---
		"dark_covenant_passive":
			_dark_covenant_passive()
		"dark_covenant_remove":
			_dark_covenant_remove()
		"abyss_ritual_circle_passive":
			_abyss_ritual_circle_passive()
		# --- Ritual effects ---
		"demon_ascendant":
			_demon_ascendant()
		# --- Trap effects ---
		"smoke_veil":
			_smoke_veil()
		"silence_trap":
			_scene.set("_spell_cancelled", true)
			_log("  Silence Trap: enemy spell cancelled!", _LOG_TRAP)
		# --- Rune effects ---
		"dominion_rune_place":
			_scene._refresh_dominion_aura(true, 100 * _scene._rune_aura_multiplier())
		"dominion_rune_remove":
			_scene._refresh_dominion_aura(false)
		"soul_rune_death":
			_soul_rune_death(ctx)
		"soul_rune_reset":
			_scene.set("_soul_rune_fires_this_turn", 0)
		# --- vael_endless_tide ---
		"colossal_guard_play":
			pass  # Handled declaratively; stub for forward compat
		# --- vael_rune_master ---
		"runic_blast":
			_runic_blast()
		"runic_echo":
			_runic_echo(ctx)
		"echo_rune_fire":
			_echo_rune_fire()
		"rune_seeker_play":
			_rune_seeker_play()
		# --- Void Rift World ---
		"void_rift_lord_mana_drain":
			if ctx.owner == "enemy":
				_scene.set("_void_mana_drain_pending", true)
				_log("  Void Rift Lord: player's Mana will be drained to 0 next turn!", _LOG_ENEMY)
		# --- Feral Imp Clan ---
		"frenzied_imp_play":
			_frenzied_imp_play(ctx)
		"void_screech":
			_void_screech(ctx)
		"brood_call":
			_brood_call(ctx)
		"pack_frenzy":
			_pack_frenzy(ctx)
		"rogue_imp_elder_remove":
			_rogue_imp_elder_remove(ctx)

# ---------------------------------------------------------------------------
# Spell effects
# ---------------------------------------------------------------------------

func _soul_shatter(ctx: EffectContext) -> void:
	var demon := ctx.chosen_target
	if demon == null:
		return
	var pre_hp: int = demon.current_health
	_scene.combat_manager.kill_minion(demon)
	var dmg := 300 if pre_hp >= 300 else 200
	_log("  Soul Shatter: sacrifice had %d HP — %d AoE to all enemy minions." % [pre_hp, dmg], _LOG_PLAYER)
	for m in (_scene.enemy_board as Array).duplicate():
		_scene._spell_dmg(m, dmg)

func _destroy_random_enemy_trap(ctx: EffectContext) -> void:
	if ctx.owner != "player":
		return
	var ai = _scene.get("enemy_ai")
	if ai == null or (ai.active_traps as Array).is_empty():
		_log("  Trapbreaker: no enemy traps to destroy.", _LOG_PLAYER)
		return
	var traps: Array = ai.active_traps
	var target: TrapCardData = traps[randi() % traps.size()]
	traps.erase(target)
	_log("  Trapbreaker: destroyed enemy %s!" % target.card_name, _LOG_PLAYER)
	if _scene.has_method("_update_enemy_trap_display"):
		_scene._update_enemy_trap_display()

func _void_detonation(ctx: EffectContext) -> void:
	if ctx.owner == "player":
		var bonus_per_mark := 50
		var total_base: int = 500 + _scene.enemy_void_marks * bonus_per_mark
		_log("  Void Detonation: base %d (500 + %d×%d marks) — Void Bolt adds %d×%d marks on top." % [
			total_base, bonus_per_mark, _scene.enemy_void_marks,
			_scene._void_mark_damage_per_stack(), _scene.enemy_void_marks], _LOG_PLAYER)
		_scene._deal_void_bolt_damage(total_base)

# ---------------------------------------------------------------------------
# Environment passives
# ---------------------------------------------------------------------------

func _dark_covenant_passive() -> void:
	var board: Array = _scene.player_board
	for m in board:
		BuffSystem.remove_source(m, "dark_covenant")
	var has_human: bool = board.any(func(m: MinionInstance) -> bool: return m.card_data.minion_type == Enums.MinionType.HUMAN)
	var has_demon: bool = board.any(func(m: MinionInstance) -> bool: return m.card_data.minion_type == Enums.MinionType.DEMON)
	if has_human:
		for m in board:
			if m.card_data.minion_type == Enums.MinionType.DEMON:
				BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "dark_covenant")
				_scene._refresh_slot_for(m)
	if has_demon:
		for m in board:
			if m.card_data.minion_type == Enums.MinionType.HUMAN:
				m.current_health = mini(m.current_health + 100, m.card_data.health)
				_scene._refresh_slot_for(m)

func _dark_covenant_remove() -> void:
	for m in (_scene.player_board as Array):
		BuffSystem.remove_source(m, "dark_covenant")
		_scene._refresh_slot_for(m)

func _abyss_ritual_circle_passive() -> void:
	var all_minions: Array[MinionInstance] = []
	all_minions.assign(_scene.player_board + _scene.enemy_board)
	if not all_minions.is_empty():
		var hit: MinionInstance = all_minions[randi() % all_minions.size()]
		_log("  Abyss Ritual Circle: 100 damage to %s." % hit.card_data.card_name, _LOG_PLAYER)
		_scene._spell_dmg(hit, 100)

# ---------------------------------------------------------------------------
# Ritual effects
# ---------------------------------------------------------------------------

func _demon_ascendant() -> void:
	_log("  Demon Ascendant: deal 200 damage to 2 random enemy minions.", _LOG_PLAYER)
	for _i in 2:
		var target_m: MinionInstance = _scene._find_random_enemy_minion()
		if target_m:
			_scene._spell_dmg(target_m, 200)
	_log("  Demon Ascendant: Special Summon a 500/500 Void Demon!", _LOG_PLAYER)
	for slot in (_scene.player_slots as Array):
		if slot.is_empty():
			var demon_data := CardDatabase.get_card("void_demon") as MinionCardData
			if demon_data:
				var instance := MinionInstance.create(demon_data, "player")
				instance.current_atk    = 500
				instance.current_health = 500
				(_scene.player_board as Array).append(instance)
				slot.place_minion(instance)
				# Special Summon: intentionally does NOT fire ON_PLAYER_MINION_SUMMONED
			break

# ---------------------------------------------------------------------------
# Trap effects
# ---------------------------------------------------------------------------

func _smoke_veil() -> void:
	var ai = _scene.get("enemy_ai")
	if ai:
		ai.attack_cancelled = true
	for m in (_scene.enemy_board as Array):
		m.state = Enums.MinionState.EXHAUSTED
		_scene._refresh_slot_for(m)
	_log("  Smoke Veil: attack cancelled! All enemies exhausted.", _LOG_TRAP)

# ---------------------------------------------------------------------------
# Rune effects
# ---------------------------------------------------------------------------

func _soul_rune_death(ctx: EffectContext) -> void:
	# Each Soul Rune can fire once per enemy turn. Track fires vs active soul rune count.
	var fires: int = _scene.get("_soul_rune_fires_this_turn") if _scene.get("_soul_rune_fires_this_turn") != null else 0
	var soul_rune_count := 0
	for trap in _scene.active_traps:
		if (trap as TrapCardData).is_rune and (trap as TrapCardData).rune_type == Enums.RuneType.SOUL_RUNE:
			soul_rune_count += 1
	if fires >= soul_rune_count:
		return
	if _scene.turn_manager.get("is_player_turn") != false:
		return
	if ctx.trigger_minion == null or ctx.trigger_minion.card_data.minion_type != Enums.MinionType.DEMON:
		return
	_scene.set("_soul_rune_fires_this_turn", fires + 1)
	var mult: int = _scene._rune_aura_multiplier()
	_scene._summon_token("void_spark", "player", 100 * mult, 100 * mult)
	_log("  Soul Rune: Demon died — %d/%d Spirit summoned." % [100 * mult, 100 * mult], _LOG_TRAP)

# ---------------------------------------------------------------------------
# vael_rune_master effects
# ---------------------------------------------------------------------------

func _runic_blast() -> void:
	var rune_count := 0
	for t in (_scene.active_traps as Array):
		if (t as TrapCardData).is_rune:
			rune_count += 1
	if rune_count >= 2:
		_log("  Runic Blast: 2+ Runes active — 200 damage to ALL enemy minions!", _LOG_PLAYER)
		for m in (_scene.enemy_board as Array).duplicate():
			_scene._spell_dmg(m, 200)
	else:
		_log("  Runic Blast: 200 damage to 2 random enemy minions.", _LOG_PLAYER)
		for _i in 2:
			var target_m: MinionInstance = _scene._find_random_enemy_minion()
			if target_m:
				_scene._spell_dmg(target_m, 200)

func _runic_echo(ctx: EffectContext) -> void:
	if ctx.owner != "player":
		return
	var added: Array[String] = []
	for trap in (_scene.active_traps as Array):
		if not (trap as TrapCardData).is_rune:
			continue
		_scene.turn_manager.add_to_hand(trap)
		added.append((trap as TrapCardData).card_name)
	if added.is_empty():
		_log("  Runic Echo: no Runes on the battlefield.", _LOG_PLAYER)
	else:
		_log("  Runic Echo: added copies of %s to hand." % ", ".join(added), _LOG_PLAYER)

func _echo_rune_fire() -> void:
	var last_rune: TrapCardData = _scene._find_last_non_echo_rune()
	if last_rune and not last_rune.aura_effect_steps.is_empty():
		_log("  Echo Rune: fires %s's effect." % last_rune.card_name, _LOG_TRAP)
		var eff_ctx := EffectContext.make(_scene, "player")
		EffectResolver.run(last_rune.aura_effect_steps, eff_ctx)

func _rune_seeker_play() -> void:
	var deck: Array = _scene.turn_manager.player_deck
	for i in deck.size():
		var inst: CardInstance = deck[i]
		if inst.card_data is TrapCardData and (inst.card_data as TrapCardData).is_rune:
			deck.remove_at(i)
			_scene.turn_manager.add_instance_to_hand(inst)
			_log("  Rune Seeker: found %s." % inst.card_data.card_name, _LOG_PLAYER)
			return
	_log("  Rune Seeker: no Rune in deck.", _LOG_PLAYER)

# ---------------------------------------------------------------------------
# Feral Imp Clan effects
# ---------------------------------------------------------------------------

func _frenzied_imp_play(ctx: EffectContext) -> void:
	var board: Array = _scene._friendly_board(ctx.owner)
	var feral_count := 0
	for m in board:
		if m != ctx.source and _scene._minion_has_tag(m, "feral_imp"):
			feral_count += 1
	var dmg := 100 + 100 * feral_count
	var frenzied_target: MinionInstance = _scene._find_random_minion(_scene._opponent_board(ctx.owner))
	if frenzied_target:
		_log("  Frenzied Imp: %d damage to %s." % [dmg, frenzied_target.card_data.card_name], _LOG_ENEMY)
		_scene._spell_dmg(frenzied_target, dmg)
	else:
		_log("  Frenzied Imp: no target.", _LOG_ENEMY)

func _void_screech(ctx: EffectContext) -> void:
	var owner_board: Array = _scene._friendly_board(ctx.owner)
	var feral_on_board := 0
	for m in owner_board:
		if _scene._minion_has_tag(m, "feral_imp"):
			feral_on_board += 1
	var screech_dmg := 350 if feral_on_board >= 3 else 250
	_scene.combat_manager.apply_hero_damage(_scene._opponent_of(ctx.owner), screech_dmg, Enums.DamageType.SPELL)
	_log("  Void Screech: %d damage to hero (%d feral imps)." % [screech_dmg, feral_on_board], _LOG_ENEMY)

func _brood_call(ctx: EffectContext) -> void:
	var feral_ids: Array[String] = ["rabid_imp", "brood_imp", "imp_brawler", "void_touched_imp", "frenzied_imp", "matriarchs_broodling", "rogue_imp_elder"]
	var pick := feral_ids[randi() % feral_ids.size()]
	_scene._summon_token(pick, ctx.owner)
	_log("  Brood Call: summoned %s." % pick, _LOG_ENEMY)

func _pack_frenzy(ctx: EffectContext) -> void:
	var feral_board: Array = _scene._friendly_board(ctx.owner).duplicate()
	var ancient_active: bool = "ancient_frenzy" in (_scene.get("_active_enemy_passives") if _scene.get("_active_enemy_passives") != null else [])
	for m in feral_board:
		if _scene._minion_has_tag(m, "feral_imp"):
			BuffSystem.apply(m, Enums.BuffType.TEMP_ATK, 250, "pack_frenzy")
			if m.state == Enums.MinionState.EXHAUSTED and m.attack_count == 0:
				m.state = Enums.MinionState.SWIFT
			if ancient_active:
				BuffSystem.apply(m, Enums.BuffType.GRANT_LIFEDRAIN, 1, "pack_frenzy", true)
			_scene._refresh_slot_for(m)
	var frenzy_msg := "  Pack Frenzy: all Feral Imps +250 ATK and SWIFT"
	if ancient_active:
		frenzy_msg += " and LIFEDRAIN (Ancient Frenzy)"
	_log(frenzy_msg + ".", _LOG_ENEMY)

func _rogue_imp_elder_remove(ctx: EffectContext) -> void:
	for m in (_scene._friendly_board(ctx.owner) as Array):
		BuffSystem.remove_source(m, "rogue_imp_elder")
		_scene._refresh_slot_for(m)

# ---------------------------------------------------------------------------
# Logging helper
# ---------------------------------------------------------------------------

func _log(msg: String, type: int = _LOG_PLAYER) -> void:
	_scene._log(msg, type)
