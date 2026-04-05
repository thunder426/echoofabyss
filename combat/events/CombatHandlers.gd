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

## Old passive relic system removed — relics are now activated abilities.
## See RelicRuntime, RelicEffects, and RelicBar for the new system.

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
	if ctx.card == null or not _card_has_tag(ctx.card, "base_void_imp"):
		return
	# Append directly — NOT via turn_manager.add_to_hand — to avoid re-triggering the drawn signal
	var copy := CardDatabase.get_card("void_imp")
	if copy and _scene.turn_manager.player_hand.size() < _scene.turn_manager.HAND_SIZE_MAX:
		var inst := CardInstance.create(copy)
		_scene.turn_manager.player_hand.append(inst)
		if "hand_display" in _scene and _scene.hand_display:
			_scene.hand_display.add_card_generated(inst)
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

## Old passive relic summon handlers removed — relics are now activated abilities.

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
	if not _card_has_tag(ctx.card, "base_void_imp"):
		return
	_scene._draw_rune_from_deck()

func on_summon_piercing_void(ctx: EventContext) -> void:
	if not _card_has_tag(ctx.card, "base_void_imp"):
		return
	_scene._deal_void_bolt_damage(200, ctx.minion)
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
	# Runtime-granted on-death summon effects (e.g. Sovereign's Edict)
	for eff: Dictionary in minion.granted_on_death_effects:
		var summon_id: String = eff.get("summon_id", "")
		if not summon_id.is_empty():
			_scene._summon_token(summon_id, minion.owner, 0, 0)
			_log("  %s dies — summons a %s." % [minion.card_data.card_name, summon_id], _LOG_ENEMY if minion.owner == "enemy" else _LOG_PLAYER)

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
	# Void bolt visual is handled by _deal_void_bolt_damage (called from
	# on_summon_piercing_void) — no extra projectile needed here.
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
func on_enemy_turn_reset_feral_reinforcement(_ctx: EventContext) -> void:
	_scene.set("_imp_caller_fired", false)

func on_enemy_summon_feral_reinforcement(ctx: EventContext) -> void:
	if _scene.get("_imp_caller_fired") == true:
		return
	var minion := ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	if (minion.card_data as MinionCardData).minion_type != Enums.MinionType.HUMAN:
		return
	_scene.set("_imp_caller_fired", true)
	var feral_imps: Array[CardData] = []
	for id in CardDatabase.get_all_card_ids():
		var card: CardData = CardDatabase.get_card(id)
		if _card_has_tag(card, "feral_imp"):
			feral_imps.append(card)
	if feral_imps.is_empty():
		return
	var chosen: CardData = feral_imps[randi() % feral_imps.size()]
	_scene.enemy_ai.add_to_hand(chosen)
	_log("  Feral Reinforcement: %s summoned → enemy draws %s." % [minion.card_data.card_name, chosen.card_name], _LOG_ENEMY)

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

## When a feral imp is summoned: consume all Corruption on each player minion, deal 100 damage per stack.
func on_enemy_summon_corrupt_authority_imp(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not _has_tag(minion, "feral_imp"):
		return
	var _prev_det = _scene.get("_detonation_count")
	_scene.set("_detonation_count", (_prev_det if _prev_det != null else 0) + 1)
	for m: MinionInstance in _scene.player_board.duplicate():
		var stacks := 0
		for b in m.buffs:
			if (b as BuffEntry).type == Enums.BuffType.CORRUPTION:
				stacks += 1
		if stacks == 0:
			continue
		BuffSystem.remove_type(m, Enums.BuffType.CORRUPTION)
		_scene._refresh_slot_for(m)
		_scene.combat_manager.apply_spell_damage(m, 100 * stacks)
		_log("  Corrupt Authority: %s had %d stack(s) → consumed, dealt %d damage." % [m.card_data.card_name, stacks, 100 * stacks], _LOG_ENEMY)

## Ritual Sacrifice — encounter 4 (Void Ritualist)
## When a feral imp is summoned and enemy has Blood Rune + Dominion Rune active:
## consume both runes + the feral imp, deal 200 damage to 2 random player targets,
## Special Summon a 500/500 Demon on the enemy board.
func on_enemy_summon_ritual_sacrifice(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not _has_tag(minion, "feral_imp"):
		return
	var enemy_traps: Array = _scene.enemy_ai.active_traps
	var blood_idx    := -1
	var dominion_idx := -1
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
	var _prev_count = _scene.get("_ritual_sacrifice_count")
	_scene.set("_ritual_sacrifice_count", (_prev_count if _prev_count != null else 0) + 1)
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
	var _prev = _scene.get("_spark_spawned_count")
	_scene.set("_spark_spawned_count", (_prev if _prev != null else 0) + 1)
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
	var _prev = _scene.get("_spark_transfer_count")
	_scene.set("_spark_transfer_count", (_prev if _prev != null else 0) + sparks.size())
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
# Act 3 — Void Rift World passive handlers
# ---------------------------------------------------------------------------

## Void Rift (shared Act 3): summon a 100/100 Void Spark on the enemy board at turn start.
func on_enemy_turn_void_rift(_ctx: EventContext) -> void:
	_scene._summon_token("void_spark", "enemy", 100, 100)
	_log("  Void Rift: a Void Spark materialises on the enemy board.", _LOG_ENEMY)

## Void Empowerment (Rift Stalker): all enemy Void Sparks enter as 200/200.
func on_enemy_summon_void_empowerment(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or minion.card_data.id != "void_spark":
		return
	if minion.owner != "enemy":
		return
	var atk_diff: int = 200 - minion.current_atk
	var hp_diff: int = 200 - minion.current_health
	if atk_diff > 0:
		minion.current_atk += atk_diff
	if hp_diff > 0:
		minion.current_health += hp_diff
	_scene._refresh_slot_for(minion)
	_log("  Void Empowerment: Void Spark empowered to 200/200.", _LOG_ENEMY)

## Void Detonation (Void Aberration): called directly by AI when sparks are consumed as card cost.
## Deals 100 damage per spark consumed to all player minions AND the player hero.
func apply_void_detonation(spark_count: int) -> void:
	for i in spark_count:
		for m: MinionInstance in _scene.player_board.duplicate():
			_scene.combat_manager.apply_spell_damage(m, 100)
		_scene.combat_manager.apply_hero_damage("player", 100, Enums.DamageType.SPELL)
		_log("  Void Detonation: Void Spark consumed — 100 damage to all player minions and hero!", _LOG_ENEMY)

# ---------------------------------------------------------------------------
# Act 4 — Void Castle passive handlers
# ---------------------------------------------------------------------------

## void_might (shared Act 4): at enemy turn start, grant 1 random friendly
## minion +1 stack of CRITICAL_STRIKE.
func on_enemy_turn_void_might(_ctx: EventContext) -> void:
	if _scene.enemy_board.is_empty():
		return
	var target: MinionInstance = _scene.enemy_board.pick_random()
	BuffSystem.apply(target, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike")
	_scene._refresh_slot_for(target)
	_log("  Void Might: %s gains Critical Strike." % target.card_data.card_name, _LOG_ENEMY)

## abyss_awakened (Abyss Sovereign Phase 2): at enemy turn start, grant ALL
## friendly minions +1 stack of CRITICAL_STRIKE.
func on_enemy_turn_abyss_awakened(_ctx: EventContext) -> void:
	for m: MinionInstance in _scene.enemy_board:
		BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike")
		_scene._refresh_slot_for(m)
	if not _scene.enemy_board.is_empty():
		_log("  Abyss Awakened: all enemy minions gain Critical Strike.", _LOG_ENEMY)

## void_precision (Fight 10 — Void Scout): after an enemy minion deals crit
## damage (attack resolves), grant it +200 ATK permanently.
## Listens to ON_ENEMY_ATTACK — we check after the attack if a crit was consumed.
## Implementation: tracks pre-attack crit count via scene field, compares after.
func on_enemy_attack_void_precision_pre(ctx: EventContext) -> void:
	var attacker: MinionInstance = ctx.minion
	if attacker == null or attacker.owner != "enemy":
		return
	_scene.set("_vp_pre_crit_stacks", attacker.critical_strike_stacks())

func on_enemy_attack_void_precision_post(ctx: EventContext) -> void:
	var attacker: MinionInstance = ctx.minion
	if attacker == null or attacker.owner != "enemy":
		return
	if attacker.current_health <= 0:
		return
	var raw = _scene.get("_vp_pre_crit_stacks")
	var pre_stacks: int = raw if raw != null else 0
	if pre_stacks > attacker.critical_strike_stacks():
		BuffSystem.apply(attacker, Enums.BuffType.ATK_BONUS, 200, "void_precision", false)
		_scene._refresh_slot_for(attacker)
		_log("  Void Precision: %s gains +200 ATK from critical strike." % attacker.card_data.card_name, _LOG_ENEMY)

## spirit_conscription (Fight 11 — Void Warband): once per turn, when enemy
## plays a Void Spirit clan minion, summon a 100/100 Void Spark.
func on_enemy_turn_reset_spirit_conscription(_ctx: EventContext) -> void:
	_scene.set("_spirit_conscription_fired", false)

func on_enemy_summon_spirit_conscription(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or minion.owner != "enemy":
		return
	if not _has_tag(minion, "void_spirit"):
		return
	if _scene.get("_spirit_conscription_fired") == true:
		return
	_scene.set("_spirit_conscription_fired", true)
	_scene._summon_token("void_spark", "enemy", 100, 100)
	_log("  Spirit Conscription: a Void Spark joins the enemy ranks.", _LOG_ENEMY)

## captain_orders (Fight 12 — Void Captain): crit damage is 2.5x instead of 2x.
## Implemented as a stat override: scene.crit_multiplier = 2.5
## No trigger handler needed — just the stat in the registry.

## dark_channeling (Fight 13 — Void Ritualist Prime): when enemy casts a
## damage-dealing spell, consume 1 crit stack from a random friendly minion.
## If consumed, spell deals 1.5x damage. Listens to ON_ENEMY_SPELL_CAST.
func on_enemy_spell_dark_channeling(ctx: EventContext) -> void:
	if _scene.enemy_board.is_empty():
		return
	# Find a minion with crit stacks
	var candidates: Array[MinionInstance] = []
	for m: MinionInstance in _scene.enemy_board:
		if m.has_critical_strike():
			candidates.append(m)
	if candidates.is_empty():
		return
	var donor: MinionInstance = candidates.pick_random()
	BuffSystem.remove_one_source(donor, "critical_strike")
	_scene._refresh_slot_for(donor)
	_scene.set("_dark_channeling_active", true)
	_scene.set("_dark_channeling_multiplier", 1.5)
	_log("  Dark Channeling: %s channels crit energy into the spell (1.5x)." % donor.card_data.card_name, _LOG_ENEMY)

## champion_duel (Fight 14 — Void Champion): enemy minions with Critical Strike
## have SPELL_IMMUNE. We check on crit grant and crit consumption.
## Implemented via ON_ENEMY_TURN_START (refresh after void_might grants) and
## ON_ENEMY_ATTACK (refresh after crit consumed by attack).
func on_enemy_turn_champion_duel_refresh(_ctx: EventContext) -> void:
	_refresh_champion_duel_immunity()

func on_enemy_attack_champion_duel_refresh(_ctx: EventContext) -> void:
	# Small delay not needed — just refresh all after attack resolves
	_refresh_champion_duel_immunity()

func _refresh_champion_duel_immunity() -> void:
	for m: MinionInstance in _scene.enemy_board:
		var has_crit := m.has_critical_strike()
		var has_immune := m.has_spell_immune()
		if has_crit and not has_immune:
			BuffSystem.apply(m, Enums.BuffType.GRANT_SPELL_IMMUNE, 1, "champion_duel")
			_scene._refresh_slot_for(m)
		elif not has_crit and has_immune:
			BuffSystem.remove_source(m, "champion_duel")
			_scene._refresh_slot_for(m)

# ---------------------------------------------------------------------------
# Enemy champion passives (Act 1)
# ---------------------------------------------------------------------------

## ── Champion: Rogue Imp Pack ────────────────────────────────────────────────
## Summon condition: 4 different rabid imps have attacked.
## Aura: all friendly feral imps gain +100 ATK.
## On death: deal 20% of enemy hero max HP to enemy hero.

func on_enemy_attack_champion_rip(ctx: EventContext) -> void:
	if _scene.get("_champion_rip_summoned"):
		return
	var minion := ctx.minion
	if minion == null or minion.card_data.id != "rabid_imp":
		return
	var uid: int = minion.get_instance_id()
	if uid in _scene._champion_rip_attack_ids:
		return
	_scene._champion_rip_attack_ids.append(uid)
	var count: int = _scene._champion_rip_attack_ids.size()
	_scene._update_champion_progress(count, 4)
	_log("  Champion progress: %d / 4 rabid imp attacks." % count, _LOG_ENEMY)
	if count >= 4:
		_summon_enemy_champion("champion_rogue_imp_pack")

func on_enemy_summon_champion_rip_aura(ctx: EventContext) -> void:
	if not _scene.get("_champion_rip_summoned"):
		return
	_refresh_champion_rip_aura()

func on_enemy_died_champion_rip(ctx: EventContext) -> void:
	if not _scene.get("_champion_rip_summoned"):
		return
	var minion := ctx.minion
	if minion == null:
		return
	# Refresh aura when any imp dies
	if _has_tag(minion, "feral_imp") and minion.card_data.id != "champion_rogue_imp_pack":
		_refresh_champion_rip_aura()
		return
	# Champion died — deal 20% max HP to enemy hero
	if minion.card_data.id == "champion_rogue_imp_pack":
		_on_enemy_champion_killed()

func _refresh_champion_rip_aura() -> void:
	for m in _scene.enemy_board:
		BuffSystem.remove_source(m, "champion_rip_aura")
		if _has_tag(m, "feral_imp") and m.card_data.id != "champion_rogue_imp_pack":
			BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "champion_rip_aura")
		_scene._refresh_slot_for(m)

## ── Champion: Corrupted Broodlings ──────────────────────────────────────────
## Summon condition: 3 friendly minions have died.
## On death: summon a Void-Touched Imp + deal 20% max HP to enemy hero.

func on_enemy_died_champion_cb(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	# Champion died — summon void_touched_imp + deal 20% max HP
	if minion.card_data.id == "champion_corrupted_broodlings":
		_scene._summon_token("void_touched_imp", "enemy", 200, 300)
		_log("  Corrupted Broodlings champion falls — a Void-Touched Imp rises!", _LOG_ENEMY)
		_on_enemy_champion_killed()
		return
	# Count non-champion deaths toward summon threshold
	if _scene.get("_champion_cb_summoned"):
		return
	var count: int = _scene.get("_champion_cb_death_count") + 1
	_scene.set("_champion_cb_death_count", count)
	_scene._update_champion_progress(count, 3)
	_log("  Champion progress: %d / 3 minion deaths." % count, _LOG_ENEMY)
	if count >= 3:
		_summon_enemy_champion("champion_corrupted_broodlings")

## ── Champion: Imp Matriarch ─────────────────────────────────────────────────
## Summon condition: 1st Pack Frenzy cast.
## Aura: Pack Frenzy also grants +200 HP to all feral imps.
## On death: deal 20% max HP to enemy hero.

func on_enemy_spell_champion_im(ctx: EventContext) -> void:
	if ctx.card == null or ctx.card.id != "pack_frenzy":
		return
	# If champion is alive, apply +200 HP to all feral imps
	if _scene.get("_champion_im_summoned"):
		for m in _scene.enemy_board:
			if _has_tag(m, "feral_imp"):
				m.current_health += 200
				_scene._refresh_slot_for(m)
		_log("  Imp Matriarch champion aura: Pack Frenzy grants +200 HP to all feral imps!", _LOG_ENEMY)
		return
	# First Pack Frenzy cast summons the champion
	_scene._update_champion_progress(1, 1)
	_log("  Champion progress: 1 / 1 Pack Frenzy cast.", _LOG_ENEMY)
	_summon_enemy_champion("champion_imp_matriarch")

func on_enemy_died_champion_im(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_imp_matriarch":
		_on_enemy_champion_killed()

## ── Shared champion helpers ─────────────────────────────────────────────────

func _summon_enemy_champion(card_id: String) -> void:
	match card_id:
		"champion_rogue_imp_pack":
			_scene.set("_champion_rip_summoned", true)
		"champion_corrupted_broodlings":
			_scene.set("_champion_cb_summoned", true)
		"champion_imp_matriarch":
			_scene.set("_champion_im_summoned", true)
	var count: int = _scene.get("_champion_summon_count")
	_scene.set("_champion_summon_count", count + 1)
	_scene._summon_token(card_id, "enemy")
	_log("  ★ %s champion has arrived!" % CardDatabase.get_card(card_id).card_name, _LOG_ENEMY)
	# Apply aura immediately for Rogue Imp Pack
	if card_id == "champion_rogue_imp_pack":
		_refresh_champion_rip_aura()

func _on_enemy_champion_killed() -> void:
	var damage: int = int(_scene.enemy_hp_max * 0.2)
	_scene.combat_manager.apply_hero_damage("enemy", damage, Enums.DamageType.SPELL)
	_log("  ★ Champion slain! Enemy hero takes %d damage (20%% of max HP)!" % damage, _LOG_ENEMY)
	_scene._on_champion_killed()

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
