## CombatHandlers.gd
## All trigger handler logic for combat events.
## Works with both CombatScene (live) and SimState (headless sim) via duck-typing.
##
## Usage:
##   var _handlers := CombatHandlers.new()
##   _handlers.setup(self)   # pass CombatScene or SimState as scene
##   trigger_manager.register(event, _handlers.method_name, priority)
class_name CombatHandlers
extends RefCounted

## The scene object — either a CombatScene node or a SimState RefCounted.
## All data access goes through this reference so both contexts work identically.
var _scene: Object

## Log-side constants matching CombatScene._LogType enum values.
const _LOG_PLAYER := 0
const _LOG_ENEMY  := 1

func setup(scene: Object) -> void:
	_scene = scene

# ---------------------------------------------------------------------------
# ON_PLAYER_TURN_START
# ---------------------------------------------------------------------------

func on_player_turn_relics(_ctx: EventContext) -> void:
	var relics := GameManager.player_relics
	_scene.relic_first_card_free = "void_crystal" in relics
	if "blood_pact" in relics:
		_log("  Blood Pact: deal 100 damage to enemy hero.", _LOG_PLAYER)
		_scene.combat_manager.apply_hero_damage("enemy", 100, Enums.DamageType.SPELL)
	if "soul_ember" in relics:
		_scene.turn_manager.essence = mini(_scene.turn_manager.essence + 1, _scene.turn_manager.essence_max)
		_scene.turn_manager.resources_changed.emit(
			_scene.turn_manager.essence, _scene.turn_manager.essence_max,
			_scene.turn_manager.mana, _scene.turn_manager.mana_max)
		_log("  Soul Ember: +1 Essence.", _LOG_PLAYER)
	if "ancient_tome" in relics:
		_scene.turn_manager.draw_card()
		_log("  Ancient Tome: draw 1 extra card.", _LOG_PLAYER)
	if "void_surge" in relics and not _scene.player_board.is_empty():
		for minion in _scene.player_board:
			BuffSystem.apply(minion, Enums.BuffType.TEMP_ATK, 100, "void_surge", true)
			_scene._refresh_slot_for(minion)
		_log("  Void Surge: all friendly minions +100 ATK this turn.", _LOG_PLAYER)

func on_player_turn_environment(_ctx: EventContext) -> void:
	if _scene.active_environment != null and not _scene.active_environment.passive_effect_steps.is_empty():
		var ctx := EffectContext.make(_scene, "player")
		EffectResolver.run(_scene.active_environment.passive_effect_steps, ctx)

func on_minion_turn_start_passives(_ctx: EventContext) -> void:
	for m in _scene.player_board.duplicate():
		var mc := m.card_data as MinionCardData
		if mc and not mc.on_turn_start_effect_steps.is_empty():
			var ectx    := EffectContext.make(_scene, "player")
			ectx.source = m
			EffectResolver.run(mc.on_turn_start_effect_steps, ectx)

# ---------------------------------------------------------------------------
# ON_ENEMY_TURN_START
# ---------------------------------------------------------------------------

func on_enemy_turn_environment(_ctx: EventContext) -> void:
	if _scene.active_environment != null \
			and _scene.active_environment.fires_on_enemy_turn \
			and not _scene.active_environment.passive_effect_steps.is_empty():
		var ctx := EffectContext.make(_scene, "player")
		EffectResolver.run(_scene.active_environment.passive_effect_steps, ctx)

# ---------------------------------------------------------------------------
# ON_PLAYER_SPELL_CAST
# ---------------------------------------------------------------------------

func on_void_archmagus_spell(_ctx: EventContext) -> void:
	var fired: Array[String] = []
	for m in _scene.player_board:
		var eid: String = m.card_data.on_spell_cast_passive_effect_id
		if eid != "" and not eid in fired:
			_apply_spell_cast_passive(eid)
			fired.append(eid)

func _apply_spell_cast_passive(effect_id: String) -> void:
	match effect_id:
		"add_void_bolt_on_spell":
			var bolt := CardDatabase.get_card("void_bolt")
			if bolt:
				_scene.turn_manager.add_to_hand(bolt)
				_log("  Void Archmagus: Void Bolt added to hand.", _LOG_PLAYER)

func _apply_void_bolt_passives() -> void:
	var counts: Dictionary = {}
	for m in _scene.player_board:
		var eid: String = m.card_data.on_void_bolt_passive_effect_id
		if eid != "":
			counts[eid] = counts.get(eid, 0) + 1
	for eid in counts:
		_apply_void_bolt_passive(eid, counts[eid])

func _apply_void_bolt_passive(effect_id: String, count: int) -> void:
	match effect_id:
		"void_mark_per_channeler":
			_scene._apply_void_mark(count)
			_log("  Void Channeler: +%d Void Mark(s) applied." % count, _LOG_PLAYER)

# ---------------------------------------------------------------------------
# ON_PLAYER_CARD_DRAWN
# ---------------------------------------------------------------------------

func on_card_drawn_void_echo(ctx: EventContext) -> void:
	if ctx.card == null or not _card_has_tag(ctx.card, "void_imp"):
		return
	# Append directly — NOT via turn_manager.add_to_hand — to avoid re-triggering the drawn signal
	var copy := CardDatabase.get_card("void_imp")
	if copy and _scene.turn_manager.player_hand.size() < _scene.turn_manager.HAND_SIZE_MAX:
		var inst := CardInstance.create(copy)
		_scene.turn_manager.player_hand.append(inst)
		if "hand_display" in _scene and _scene.hand_display:
			_scene.hand_display.add_card(inst)
			_scene.hand_display.refresh_playability(_scene.turn_manager.essence, _scene.turn_manager.mana)
		_log("  Void Echo: Void Imp drawn — free copy added to hand.", _LOG_PLAYER)

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_SUMMONED
# ---------------------------------------------------------------------------

func on_summon_passive_void_imp_boost(ctx: EventContext) -> void:
	if not _is_void_imp(ctx.minion):
		return
	BuffSystem.apply(ctx.minion, Enums.BuffType.ATK_BONUS, 100, "void_imp_boost")
	ctx.minion.current_health += 100
	var hero := HeroDatabase.get_hero(GameManager.current_hero)
	_log("  %s: %s summoned with +100/+100." % [(hero.hero_name if hero else "Hero"), ctx.card.card_name], _LOG_PLAYER)

func on_summon_relic(ctx: EventContext) -> void:
	var relics := GameManager.player_relics
	if "demon_pact" in relics and ctx.minion.card_data.minion_type == Enums.MinionType.DEMON:
		BuffSystem.apply(ctx.minion, Enums.BuffType.ATK_BONUS, 100, "demon_pact")
		_log("  Demon Pact: %s gains +100 ATK." % ctx.card.card_name, _LOG_PLAYER)
	if "abyssal_core" in relics:
		BuffSystem.apply(ctx.minion, Enums.BuffType.ATK_BONUS, 100, "abyssal_core")
		ctx.minion.current_health += 100
		_log("  Abyssal Core: %s gains +100/+100." % ctx.card.card_name, _LOG_PLAYER)

func on_summon_swarm_discipline(ctx: EventContext) -> void:
	if not _is_void_imp(ctx.minion):
		return
	ctx.minion.current_health += 100
	_log("  Swarm Discipline: %s +100 HP." % ctx.card.card_name, _LOG_PLAYER)

func on_summon_abyssal_legion(ctx: EventContext) -> void:
	if not _is_void_imp(ctx.minion):
		return
	var imp_count := _count_void_imps(_scene.player_board)
	if imp_count >= 3:
		BuffSystem.apply(ctx.minion, Enums.BuffType.ATK_BONUS, 100, "abyssal_legion")
		ctx.minion.current_health += 100
		_log("  Abyssal Legion: %s +100/+100." % ctx.card.card_name, _LOG_PLAYER)
		if imp_count == 3:
			for m in _scene.player_board:
				if m != ctx.minion and _is_void_imp(m):
					BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "abyssal_legion")
					m.current_health += 100
					_scene._refresh_slot_for(m)
					_log("  Abyssal Legion: %s +100/+100." % m.card_data.card_name, _LOG_PLAYER)

func on_played_rune_caller(ctx: EventContext) -> void:
	if not _card_has_tag(ctx.card, "void_imp"):
		return
	_scene._draw_rune_from_deck()

func on_summon_piercing_void(ctx: EventContext) -> void:
	if not _card_has_tag(ctx.card, "base_void_imp"):
		return
	_scene._deal_void_bolt_damage(200)
	_scene._apply_void_mark(1)

func on_summon_imp_evolution(ctx: EventContext) -> void:
	if not _card_has_tag(ctx.card, "base_void_imp") or _scene.imp_evolution_used_this_turn:
		return
	var senior := CardDatabase.get_card("senior_void_imp")
	if senior and _scene.turn_manager.player_hand.size() < _scene.turn_manager.HAND_SIZE_MAX:
		_scene.turn_manager.add_to_hand(senior)
		_scene.imp_evolution_used_this_turn = true
		_log("  Imp Evolution: Senior Void Imp added to hand.", _LOG_PLAYER)

func on_summon_imp_warband(ctx: EventContext) -> void:
	if not _card_has_tag(ctx.card, "senior_void_imp"):
		return
	for m in _scene.player_board:
		if _is_void_imp(m):
			BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 50, "imp_warband")
			_scene._refresh_slot_for(m)
	_log("  Imp Warband: Senior Void Imp summoned — all Void Imps +50 ATK.", _LOG_PLAYER)

func on_summon_board_synergies(ctx: EventContext) -> void:
	var summoned := ctx.minion
	for m in _scene.player_board:
		var pid: String = (m.card_data as MinionCardData).passive_effect_id
		if pid != "" and m != summoned:
			_apply_board_passive_on_summon(pid, m, summoned)
	if _is_void_imp(summoned):
		_scene._refresh_slot_for(summoned)
		if _scene.has_method("_check_champion_triggers"):
			_scene._check_champion_triggers()

func _apply_board_passive_on_summon(passive_id: String, passive_owner: MinionInstance, summoned: MinionInstance) -> void:
	match passive_id:
		"void_amplifier_buff_demon":
			if summoned.card_data.minion_type == Enums.MinionType.DEMON and summoned != passive_owner:
				BuffSystem.apply(summoned, Enums.BuffType.ATK_BONUS, 100, "void_amplifier")
				summoned.current_health += 100
				_scene._refresh_slot_for(summoned)
				_log("  Void Amplifier: %s enters with +100 ATK / +100 HP." % summoned.card_data.card_name, _LOG_PLAYER)

# ---------------------------------------------------------------------------
# ON_RUNE_PLACED / ON_RITUAL_ENVIRONMENT_PLAYED
# ---------------------------------------------------------------------------

func on_player_minion_died_rune_warden(_ctx: EventContext) -> void:
	for m in _scene.player_board:
		if (m.card_data as MinionCardData).passive_effect_id == "rune_warden":
			BuffSystem.apply(m, Enums.BuffType.TEMP_ATK, 200, "rune_warden")
			_log("  Rune Warden: +200 ATK until end of turn.", _LOG_PLAYER)
			_scene._refresh_slot_for(m)

func on_grand_ritual(ritual: RitualData) -> void:
	var runes: Array = _scene.active_traps.filter(func(t: TrapCardData): return t.is_rune)
	if _scene._runes_satisfy(runes, ritual.required_runes):
		_scene._fire_ritual(ritual)

func on_env_ritual(ritual: RitualData) -> void:
	var runes: Array = _scene.active_traps.filter(func(t: TrapCardData): return t.is_rune)
	if _scene._runes_satisfy(runes, ritual.required_runes):
		_scene._fire_ritual(ritual)

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_DIED
# ---------------------------------------------------------------------------

func on_minion_died_death_effect(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var card := minion.card_data as MinionCardData
	if not card.on_death_effect.is_empty() and _scene.has_method("_resolve_on_death_effect"):
		_scene._resolve_on_death_effect(minion)
	if not card.on_death_effect_steps.is_empty():
		var eff_ctx    := EffectContext.make(_scene, minion.owner)
		eff_ctx.source = minion
		EffectResolver.run(card.on_death_effect_steps, eff_ctx)

func on_player_minion_died_board_passives(ctx: EventContext) -> void:
	var dead := ctx.minion
	if _scene.active_environment != null and not _scene.active_environment.on_player_minion_died_steps.is_empty():
		var eff_ctx         := EffectContext.make(_scene, "player")
		eff_ctx.dead_minion = dead
		EffectResolver.run(_scene.active_environment.on_player_minion_died_steps, eff_ctx)
	for m in _scene.player_board.duplicate():
		var pid: String = (m.card_data as MinionCardData).passive_effect_id
		if pid != "":
			_apply_board_passive_on_death(pid, m, dead)

func _apply_board_passive_on_death(passive_id: String, passive_owner: MinionInstance, dead: MinionInstance) -> void:
	match passive_id:
		"void_spark_on_friendly_death":
			if dead.card_data.minion_type == Enums.MinionType.DEMON \
					and _scene.has_method("_summon_void_spark"):
				_scene._summon_void_spark()
		"deal_200_hero_on_friendly_death":
			_log("  Abyssal Tide: deal 200 damage to enemy hero.", _LOG_PLAYER)
			_scene.combat_manager.apply_hero_damage("enemy", 200, Enums.DamageType.SPELL)
		"void_mark_on_void_imp_death":
			if _is_void_imp(dead):
				_log("  Abyssal Sacrificer: %s died → 1 Void Mark." % dead.card_data.card_name, _LOG_PLAYER)
				_scene._apply_void_mark(1)
		"soul_taskmaster_gain_atk":
			if dead.card_data.minion_type == Enums.MinionType.DEMON and dead != passive_owner:
				BuffSystem.apply(passive_owner, Enums.BuffType.ATK_BONUS, 50, "soul_taskmaster_stack")
				_scene._refresh_slot_for(passive_owner)
				_log("  Soul Taskmaster: Demon died → gains +50 ATK.", _LOG_PLAYER)

func on_player_minion_died_death_bolt(ctx: EventContext) -> void:
	if not _is_void_imp(ctx.minion):
		return
	_log("  Death Bolt: %s death fires Void Bolt." % ctx.minion.card_data.card_name, _LOG_PLAYER)
	_scene._deal_void_bolt_damage(100)

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_PLAYED
# ---------------------------------------------------------------------------

func on_player_minion_played_effect(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var mc := minion.card_data as MinionCardData
	if not mc.on_play_effect_steps.is_empty():
		var ectx           := EffectContext.make(_scene, "player")
		ectx.source        = minion
		ectx.chosen_target = ctx.target
		EffectResolver.run(mc.on_play_effect_steps, ectx)

# ---------------------------------------------------------------------------
# ON_ENEMY_MINION_SUMMONED
# ---------------------------------------------------------------------------

func on_enemy_minion_played_effect(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var mc := minion.card_data as MinionCardData
	if not mc.on_play_effect_steps.is_empty():
		var chosen                       = _scene.enemy_ai.minion_play_chosen_target
		_scene.enemy_ai.minion_play_chosen_target = null
		var ectx                         := EffectContext.make(_scene, "enemy")
		ectx.source                      = minion
		if chosen is MinionInstance:
			ectx.chosen_target = chosen
		else:
			ectx.chosen_object = chosen
		EffectResolver.run(mc.on_play_effect_steps, ectx)

func on_enemy_summon_rogue_imp_elder(ctx: EventContext) -> void:
	var summoned := ctx.minion
	if summoned == null or not _scene._minion_has_tag(summoned, "feral_imp"):
		return
	var has_elder: bool = _scene.enemy_board.any(
		func(m: MinionInstance) -> bool: return m.card_data.id == "rogue_imp_elder" and m != summoned)
	if has_elder:
		BuffSystem.apply(summoned, Enums.BuffType.ATK_BONUS, 100, "rogue_imp_elder")
		_scene._refresh_slot_for(summoned)
		_log("  Rogue Imp Elder aura: %s enters with +100 ATK." % summoned.card_data.card_name, _LOG_ENEMY)

# ---------------------------------------------------------------------------
# Enemy encounter passive handlers
# ---------------------------------------------------------------------------

func on_enemy_turn_feral_instinct_reset(_ctx: EventContext) -> void:
	_scene.feral_instinct_granted_this_turn = false

func on_enemy_summon_feral_instinct(ctx: EventContext) -> void:
	if _scene.feral_instinct_granted_this_turn:
		return
	var minion := ctx.minion
	if minion == null or not _scene._minion_has_tag(minion, "feral_imp"):
		return
	_scene.feral_instinct_granted_this_turn = true
	minion.granted_on_death_effects.append({"description": "Draw 1 card.", "source": "feral_instinct"})
	_scene._refresh_slot_for(minion)
	_log("  Feral Instinct: %s will draw 1 card on death." % minion.card_data.card_name, _LOG_ENEMY)

func on_enemy_died_feral_instinct(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	var has_effect := minion.granted_on_death_effects.any(
		func(e: Dictionary) -> bool: return e.get("source") == "feral_instinct")
	if not has_effect:
		return
	_scene.enemy_ai.draw_cards(1)
	_log("  Feral Instinct: death draw triggered — enemy draws 1.", _LOG_ENEMY)

func on_board_changed_pack_instinct(_ctx: EventContext) -> void:
	var feral_imps: Array[MinionInstance] = []
	for m in _scene.enemy_board:
		if _scene._minion_has_tag(m, "feral_imp"):
			feral_imps.append(m)
	for m in feral_imps:
		BuffSystem.remove_source(m, "pack_instinct")
		var others := feral_imps.size() - 1
		if others > 0:
			BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, others * 50, "pack_instinct")
		_scene._refresh_slot_for(m)

func on_enemy_died_corrupted_death(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or minion.card_data.id != "void_touched_imp":
		return
	if _scene.player_board.is_empty():
		return
	for m in _scene.player_board:
		_scene._corrupt_minion(m)
	_log("  Corrupted Death: Void-Touched Imp death spreads Corruption to all player minions.", _LOG_ENEMY)

## Human Imp Caller — shared Act 2 passive
## When a human is summoned: add a random feral imp to the enemy's hand.
func on_enemy_summon_human_imp_caller(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	if (minion.card_data as MinionCardData).minion_type != Enums.MinionType.HUMAN:
		return
	var feral_imps: Array[CardData] = []
	for id in CardDatabase.get_all_card_ids():
		var card: CardData = CardDatabase.get_card(id)
		if _card_has_tag(card, "feral_imp"):
			feral_imps.append(card)
	if feral_imps.is_empty():
		return
	var chosen: CardData = feral_imps[randi() % feral_imps.size()]
	_scene.enemy_ai.add_to_hand(chosen)
	_log("  Imp Caller: %s summoned → enemy draws %s." % [minion.card_data.card_name, chosen.card_name], _LOG_ENEMY)

## Corrupt Authority — encounter 3 (Abyss Cultist Patrol)
## When a human is summoned: apply 1 Corruption to a random player minion.
func on_enemy_summon_corrupt_authority_human(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or (minion.card_data as MinionCardData).minion_type != Enums.MinionType.HUMAN:
		return
	if _scene.player_board.is_empty():
		return
	var target: MinionInstance = _scene.player_board[randi() % _scene.player_board.size()]
	_scene._corrupt_minion(target)
	_log("  Corrupt Authority: %s summoned → %s is Corrupted." % [minion.card_data.card_name, target.card_data.card_name], _LOG_ENEMY)

## When a feral imp is summoned: consume all Corruption on each player minion, deal 200 damage per stack.
func on_enemy_summon_corrupt_authority_imp(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not _has_tag(minion, "feral_imp"):
		return
	for m: MinionInstance in _scene.player_board.duplicate():
		var stacks := 0
		for b in m.buffs:
			if (b as BuffEntry).type == Enums.BuffType.CORRUPTION:
				stacks += 1
		if stacks == 0:
			continue
		BuffSystem.remove_type(m, Enums.BuffType.CORRUPTION)
		_scene._refresh_slot_for(m)
		_scene.combat_manager.apply_spell_damage(m, 200 * stacks)
		_log("  Corrupt Authority: %s had %d stack(s) → consumed, dealt %d damage." % [m.card_data.card_name, stacks, 200 * stacks], _LOG_ENEMY)

## Ritual Sacrifice — encounter 4 (Void Ritualist)
## When a feral imp is summoned and enemy has Blood Rune + Dominion Rune active:
## consume both runes + the feral imp, deal 200 damage to 2 random player targets,
## Special Summon a 500/500 Demon on the enemy board.
func on_enemy_summon_ritual_sacrifice(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not _has_tag(minion, "feral_imp"):
		return
	var blood_idx    := -1
	var dominion_idx := -1
	var enemy_traps: Array = _scene.enemy_ai.active_traps
	for i in enemy_traps.size():
		var trap: TrapCardData = enemy_traps[i] as TrapCardData
		if not trap.is_rune:
			continue
		if trap.rune_type == Enums.RuneType.BLOOD_RUNE and blood_idx == -1:
			blood_idx = i
		elif trap.rune_type == Enums.RuneType.DOMINION_RUNE and dominion_idx == -1:
			dominion_idx = i
	if blood_idx == -1 or dominion_idx == -1:
		return
	# Remove runes — erase higher index first to preserve lower index position
	var hi := maxi(blood_idx, dominion_idx)
	var lo := mini(blood_idx, dominion_idx)
	_scene.enemy_ai.active_traps.remove_at(hi)
	_scene.enemy_ai.active_traps.remove_at(lo)
	# Consume the feral imp that triggered this
	_scene.combat_manager.kill_minion(minion)
	_log("  Ritual Sacrifice: runes consumed + %s sacrificed — Demon Ascendant!" % minion.card_data.card_name, _LOG_ENEMY)
	# Deal 200 damage to 2 random player targets (minion or hero if board is empty)
	for _i in 2:
		if _scene.player_board.is_empty():
			_scene.combat_manager.apply_hero_damage("player", 200, Enums.DamageType.SPELL)
		else:
			var t: MinionInstance = _scene.player_board[randi() % _scene.player_board.size()]
			_scene.combat_manager.apply_spell_damage(t, 200)
	# Special Summon a 500/500 Demon
	_scene._summon_token("void_demon", "enemy", 500, 500)

## Void Unraveling — encounter 5 (Corrupted Handler)
## When a friendly human dies: summon a 100/100 Void Spark on the enemy board.
func on_enemy_died_void_unraveling(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or (minion.card_data as MinionCardData).minion_type != Enums.MinionType.HUMAN:
		return
	_scene._summon_token("void_spark", "enemy", 100, 100)
	_log("  Void Unraveling: %s died → a Void Spark arises on the enemy board." % minion.card_data.card_name, _LOG_ENEMY)

## When a feral imp is summoned: apply 1 Corruption to all friendly Void Sparks and
## transfer each to the player board. Destroy those that can't fit.
func on_enemy_summon_void_unraveling(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not _has_tag(minion, "feral_imp"):
		return
	var sparks: Array[MinionInstance] = []
	for m: MinionInstance in _scene.enemy_board:
		if m.card_data.id == "void_spark":
			sparks.append(m)
	if sparks.is_empty():
		return
	for spark: MinionInstance in sparks:
		_scene._corrupt_minion(spark)
		if not _transfer_to_player_board(spark):
			_scene.combat_manager.kill_minion(spark)
			_log("  Void Unraveling: player board full — Void Spark destroyed.", _LOG_ENEMY)
		else:
			_log("  Void Unraveling: Void Spark (Corrupted) transferred to player board!", _LOG_ENEMY)

## Move a minion from the enemy board to an empty player board slot without firing death/summon events.
## Returns false if the player board has no empty slot.
func _transfer_to_player_board(m: MinionInstance) -> bool:
	var target_slot: BoardSlot = null
	for s: BoardSlot in _scene.player_slots:
		if s.is_empty():
			target_slot = s
			break
	if target_slot == null:
		return false
	for s: BoardSlot in _scene.enemy_slots:
		if s.minion == m:
			s.remove_minion()
			break
	_scene.enemy_board.erase(m)
	m.owner = "player"
	_scene.player_board.append(m)
	target_slot.place_minion(m)
	_scene._refresh_slot_for(m)
	return true

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

func _log(msg: String, side: int = _LOG_PLAYER) -> void:
	if _scene.has_method("_log"):
		_scene._log(msg, side)

func _is_void_imp(minion: MinionInstance) -> bool:
	return _has_tag(minion, "void_imp")

func _has_tag(minion: MinionInstance, tag: String) -> bool:
	if minion == null or not (minion.card_data is MinionCardData):
		return false
	return tag in (minion.card_data as MinionCardData).minion_tags

func _card_has_tag(card: CardData, tag: String) -> bool:
	if card is MinionCardData:
		return tag in (card as MinionCardData).minion_tags
	return false

func _count_void_imps(board: Array[MinionInstance]) -> int:
	var count := 0
	for m in board:
		if _is_void_imp(m):
			count += 1
	return count
