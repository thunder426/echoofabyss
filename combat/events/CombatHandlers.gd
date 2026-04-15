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
	# Once per turn — tracked via scene flag, reset at player turn start.
	if _scene.get("_void_echo_fired_this_turn"):
		return
	# Append directly — NOT via turn_manager.add_to_hand — to avoid re-triggering the drawn signal
	var copy := CardDatabase.get_card("void_imp")
	if copy and _scene.turn_manager.player_hand.size() < _scene.turn_manager.HAND_SIZE_MAX:
		var inst := CardInstance.create(copy)
		_scene.turn_manager.player_hand.append(inst)
		_scene.set("_void_echo_fired_this_turn", true)
		if "hand_display" in _scene and _scene.hand_display:
			_scene.hand_display.add_card_generated(inst)
		_log("  Void Echo: Void Imp drawn — free copy added to hand.", _LOG_PLAYER)

## Reset void_echo once-per-turn flag at player turn start.
func on_player_turn_start_void_echo(_ctx: EventContext) -> void:
	_scene.set("_void_echo_fired_this_turn", false)

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

func on_ritual_fired_ritual_surge(_ctx: EventContext) -> void:
	_scene._summon_token("void_imp", "player")
	_log("  Ritual Surge: Void Imp summoned!", _LOG_PLAYER)

func on_summon_piercing_void(ctx: EventContext) -> void:
	if not _card_has_tag(ctx.card, "base_void_imp"):
		return
	_scene.set("_pending_dmg_source", "imp_piercing")
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
		if _is_void_imp(m) and m != ctx.minion:
			BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 50, "imp_warband")
			_scene._refresh_slot_for(m)
	_log("  Imp Warband: Senior Void Imp summoned — all other Void Imps +50 ATK.", _LOG_PLAYER)

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
	_scene.set("_pending_dmg_source", "death_bolt")
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
		_scene._update_counter_warning()

## Rogue Imp Elder — true aura: each live Elder grants +100 ATK to every friendly
## FERAL IMP on the same side (including other Elders). Recomputed on every
## summon/death so the buff count always matches the live Elder count.
## Symmetric: works for both player-owned and enemy-owned Elders.
func on_minion_event_rogue_imp_elder_aura(ctx: EventContext) -> void:
	_refresh_rogue_imp_elder_aura("player")
	_refresh_rogue_imp_elder_aura("enemy")

func _refresh_rogue_imp_elder_aura(side: String) -> void:
	var board: Array[MinionInstance] = _scene._friendly_board(side)
	var elder_count: int = 0
	for m in board:
		if m.card_data.id == "rogue_imp_elder":
			elder_count += 1
	for m in board:
		BuffSystem.remove_source(m, "rogue_imp_elder_aura")
		if _scene._minion_has_tag(m, "feral_imp") and elder_count > 0:
			BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100 * elder_count, "rogue_imp_elder_aura")
		_scene._refresh_slot_for(m)

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

func on_board_changed_pack_instinct(ctx: EventContext) -> void:
	var feral_imps: Array[MinionInstance] = []
	for m in _scene.enemy_board:
		if _scene._minion_has_tag(m, "feral_imp"):
			feral_imps.append(m)
	# Snapshot old ATK so we can show a buff-gain VFX for each imp whose ATK goes up
	var pre_atk: Dictionary = {}  # MinionInstance → int
	for m in feral_imps:
		pre_atk[m] = m.effective_atk()
	for m in feral_imps:
		BuffSystem.remove_source(m, "pack_instinct")
		var others := feral_imps.size() - 1
		if others > 0:
			BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, others * 50, "pack_instinct")
		_scene._refresh_slot_for(m)
	# Visualize the pack link — only on SUMMONED events, tying the new imp to its neighbors.
	var is_summon: bool = ctx.event_type == Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	if is_summon \
			and feral_imps.size() >= 2 \
			and ctx.minion != null \
			and _scene._minion_has_tag(ctx.minion, "feral_imp") \
			and _scene.has_method("_spawn_pack_chain_vfx_for_new_imp"):
		_scene._spawn_pack_chain_vfx_for_new_imp(ctx.minion, "enemy")
	# ATK-increase popup on every imp that gained ATK this tick (only on summon —
	# death events should silently lose the buff without drawing attention).
	# The buff is ALREADY applied (game state uses new ATK immediately), but we
	# hold the visual ATK label at the OLD value and let the VFX helper flip it
	# in sync with the chain animation.
	if is_summon and _scene.has_method("_spawn_pack_instinct_buff_vfx"):
		for m in feral_imps:
			var old_atk: int = int(pre_atk.get(m, m.effective_atk()))
			var new_atk: int = m.effective_atk()
			if new_atk > old_atk:
				# Override the atk label text back to the old value so it doesn't
				# update instantly — _spawn_pack_instinct_buff_vfx flips it later.
				var slot: BoardSlot = _scene._find_slot_for(m)
				if slot != null and slot._atk_label != null:
					slot._atk_label.text = str(old_atk)
				_scene._spawn_pack_instinct_buff_vfx(m, new_atk - old_atk)

func on_enemy_died_corrupted_death(_ctx: EventContext) -> void:
	pass  # Death effect removed — corrupted_death now only provides cost discounts

## Corrupted Death — when PLAYER casts a spell, reduce a random enemy minion's
## essence cost in hand by 1.
func on_player_spell_corrupted_death(_ctx: EventContext) -> void:
	var ai = _scene.get("enemy_ai")
	if ai == null:
		return
	# Find all minion CardInstances in enemy hand
	var minion_insts: Array = []
	for inst in ai.hand:
		if inst.card_data is MinionCardData:
			minion_insts.append(inst)
	if minion_insts.is_empty():
		return
	# Pick a random minion and discount its essence cost by 1
	var chosen: CardInstance = minion_insts[randi() % minion_insts.size()] as CardInstance
	var mc: MinionCardData = chosen.card_data as MinionCardData
	var discounts: Dictionary = ai.essence_cost_discounts
	var current: int = (discounts.get(mc.id, 0) as int)
	discounts[mc.id] = current + 1
	_log("  Corrupted Death: player spell → %s cost reduced (-%d Essence)." % [mc.card_name, current + 1], _LOG_ENEMY)

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
		if _card_has_tag(card, "feral_imp") and not (card is MinionCardData and (card as MinionCardData).is_champion):
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
	_scene._corruption_detonation_times += 1
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
		# Track consumed stacks toward Abyss Cultist Patrol champion
		on_champion_acp_track_stacks(stacks)

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
	# Remove runes — unregister auras then erase (higher index first to preserve positions)
	var hi := maxi(blood_idx, dominion_idx)
	var lo := mini(blood_idx, dominion_idx)
	_scene._remove_rune_aura(enemy_traps[hi] as TrapCardData, "enemy")
	_scene._remove_rune_aura(enemy_traps[lo] as TrapCardData, "enemy")
	_scene.enemy_ai.active_traps.remove_at(hi)
	_scene.enemy_ai.active_traps.remove_at(lo)
	if _scene.has_method("_update_enemy_trap_display"):
		_scene._update_enemy_trap_display()
	# Consume the feral imp that triggered this
	_scene.combat_manager.kill_minion(minion)
	var _prev_count = _scene.get("_ritual_sacrifice_count")
	_scene.set("_ritual_sacrifice_count", (_prev_count if _prev_count != null else 0) + 1)
	_scene._ritual_invoke_times += 1
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
	# Trigger Void Ritualist champion on first ritual
	on_ritual_sacrifice_champion_vr()

## Void Unraveling — encounter 6 (Corrupted Handler)
## When a human is summoned: summon a 100/100 Void Spark on the enemy board.
func on_enemy_summon_void_unraveling_human(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	if (minion.card_data as MinionCardData).minion_type != Enums.MinionType.HUMAN:
		return
	var _prev = _scene.get("_spark_spawned_count")
	_scene.set("_spark_spawned_count", (_prev if _prev != null else 0) + 1)
	_scene._summon_token("void_spark", "enemy", 100, 100)
	_log("  Void Unraveling: %s summoned → a Void Spark arises!" % minion.card_data.card_name, _LOG_ENEMY)

## When a feral imp is summoned: consume 1 friendly Void Spark, grant +100/+100 to the imp.
func on_enemy_summon_void_unraveling_imp(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not _has_tag(minion, "feral_imp"):
		return
	# Find a friendly void spark to consume
	for m: MinionInstance in _scene.enemy_board.duplicate():
		if m.card_data.id == "void_spark":
			_scene.combat_manager.kill_minion(m)
			minion.current_atk += 100
			minion.current_health += 100
			_scene._refresh_slot_for(minion)
			_log("  Void Unraveling: feral imp consumed a Void Spark → +100/+100!" , _LOG_ENEMY)
			return

## At end of enemy turn: corrupt 1 random friendly spark and transfer it to player board.
func on_enemy_turn_end_void_unraveling(_ctx: EventContext) -> void:
	var sparks: Array[MinionInstance] = []
	for m: MinionInstance in _scene.enemy_board:
		if m.card_data.id == "void_spark":
			sparks.append(m)
	if sparks.is_empty():
		return
	# Pick one random spark, corrupt it, transfer it
	var spark: MinionInstance = sparks[randi() % sparks.size()]
	if not BuffSystem.has_type(spark, Enums.BuffType.CORRUPTION):
		_scene._corrupt_minion(spark)
	var _prev = _scene.get("_spark_transfer_count")
	_scene.set("_spark_transfer_count", (_prev if _prev != null else 0) + 1)
	if not _transfer_to_player_board(spark):
		_scene.combat_manager.kill_minion(spark)
		_log("  Void Unraveling: player board full — Void Spark destroyed.", _LOG_ENEMY)
	else:
		_log("  Void Unraveling: corrupted Void Spark transferred to player board!", _LOG_ENEMY)

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
## Suppressed when Void Herald champion is alive (aura: no more spark generation).
func on_enemy_turn_void_rift(_ctx: EventContext) -> void:
	if _champion_vh_is_alive():
		return  # Void Herald aura suppresses spark generation
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

## Void Detonation: fires on spark consumed.
## Deals 100 damage (200 if Void Aberration champion alive) per spark_value consumed
## to all opponent minions AND opponent hero.
## Symmetric — works for both player and enemy spark consumption.
func on_spark_consumed_void_detonation(ctx: EventContext) -> void:
	var spark_val: int = ctx.damage if ctx.damage > 0 else 1
	var opponent: String = _scene._opponent_of(ctx.owner)
	var opponent_board: Array[MinionInstance] = _scene._opponent_board(ctx.owner)
	var side: int = _LOG_ENEMY if ctx.owner == "enemy" else _LOG_PLAYER
	var dmg_per_spark: int = 200 if _champion_va_is_alive() else 100
	for i in spark_val:
		for m: MinionInstance in opponent_board.duplicate():
			_scene.combat_manager.apply_spell_damage(m, dmg_per_spark)
		_scene.combat_manager.apply_hero_damage(opponent, dmg_per_spark, Enums.DamageType.SPELL)
		_log("  Void Detonation: spark consumed — %d damage to all %s minions and hero!" % [dmg_per_spark, opponent], side)

## Hollow Sentinel: at end of owner's turn, +100 ATK permanently to all friendly Void Sparks.
## Works for both player and enemy boards (symmetric).
func on_turn_end_hollow_sentinel(ctx: EventContext) -> void:
	var owner: String = ctx.get("owner") if ctx.get("owner") != null else ""
	# Determine which boards to scan based on trigger event
	var boards: Array = []
	if ctx.event_type == Enums.TriggerEvent.ON_ENEMY_TURN_END:
		boards.append({"board": _scene.enemy_board, "owner": "enemy"})
	elif ctx.event_type == Enums.TriggerEvent.ON_PLAYER_TURN_END:
		boards.append({"board": _scene.player_board, "owner": "player"})
	for entry in boards:
		var board: Array[MinionInstance] = entry.board
		var has_sentinel := false
		for m: MinionInstance in board:
			if (m.card_data as MinionCardData).passive_effect_id == "hollow_sentinel_spark_buff":
				has_sentinel = true
				break
		if not has_sentinel:
			continue
		var buffed := 0
		for m: MinionInstance in board:
			if m.card_data.id == "void_spark":
				BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "hollow_sentinel")
				_scene._refresh_slot_for(m)
				buffed += 1
		if buffed > 0:
			if _scene.get("_hollow_sentinel_buffs") != null:
				_scene._hollow_sentinel_buffs += 1
			var side: int = _LOG_ENEMY if entry.owner == "enemy" else _LOG_PLAYER
			_log("  Hollow Sentinel: %d Void Sparks gain +100 ATK." % buffed, side)

## ── Champion: Rift Stalker ─────────────────────────────────────────────────
## Summon condition: Void Sparks have dealt 1500 cumulative damage.
## Aura: All friendly Void Sparks are immune.
## On death: deal 20% of enemy hero max HP to enemy hero.

const _RS_THRESHOLD := 1000
const _RS_PIPS := 5  # 1000 / 5 = 200 per pip

func on_enemy_attack_champion_rs(ctx: EventContext) -> void:
	if _scene.get("_champion_rs_summoned"):
		return
	var minion := ctx.minion
	if minion == null or minion.card_data.id != "void_spark":
		return
	var dmg: int = minion.effective_atk()
	_scene._champion_rs_spark_dmg += dmg
	var total: int = _scene._champion_rs_spark_dmg
	var pips: int = mini(total / (_RS_THRESHOLD / _RS_PIPS), _RS_PIPS)
	_scene._update_champion_progress(pips, _RS_PIPS)
	_log("  Champion progress: %d / %d spark damage." % [mini(total, _RS_THRESHOLD), _RS_THRESHOLD], _LOG_ENEMY)
	if total >= _RS_THRESHOLD:
		_summon_enemy_champion("champion_rift_stalker")
		_refresh_champion_rs_immune()

func on_enemy_summon_champion_rs_immune(ctx: EventContext) -> void:
	if not _scene.get("_champion_rs_summoned"):
		return
	var minion := ctx.minion
	if minion == null or minion.card_data.id != "void_spark":
		return
	# Grant immune to newly summoned void sparks while champion is alive
	if _champion_rs_is_alive():
		BuffSystem.apply(minion, Enums.BuffType.GRANT_IMMUNE, 1, "champion_rs_immune")
		_scene._refresh_slot_for(minion)

func on_enemy_died_champion_rs(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_rift_stalker":
		# Champion killed — remove immune from all sparks
		for m: MinionInstance in _scene.enemy_board:
			if m.card_data.id == "void_spark":
				BuffSystem.remove_source(m, "champion_rs_immune")
				_scene._refresh_slot_for(m)
		_on_enemy_champion_killed()

func _refresh_champion_rs_immune() -> void:
	if not _champion_rs_is_alive():
		return
	for m: MinionInstance in _scene.enemy_board:
		if m.card_data.id == "void_spark" and not BuffSystem.has_type(m, Enums.BuffType.GRANT_IMMUNE):
			BuffSystem.apply(m, Enums.BuffType.GRANT_IMMUNE, 1, "champion_rs_immune")
			_scene._refresh_slot_for(m)

func _champion_rs_is_alive() -> bool:
	for m: MinionInstance in _scene.enemy_board:
		if m.card_data.id == "champion_rift_stalker":
			return true
	return false

## ── Champion: Void Aberration ─────────────────────────────────────────────
## Summon condition: 5 sparks consumed as costs (cumulative).
## Aura: Void Detonation deals 200 damage instead of 100.
## On death: deal 20% of enemy hero max HP to enemy hero.

const _VA_THRESHOLD := 5
const _VA_PIPS := 5

func on_spark_consumed_champion_va(ctx: EventContext) -> void:
	if _scene.get("_champion_va_summoned"):
		return
	var spark_val: int = ctx.damage if ctx.damage > 0 else 1
	_scene._champion_va_sparks_consumed += spark_val
	var total: int = _scene._champion_va_sparks_consumed
	var pips: int = mini(total, _VA_PIPS)
	_scene._update_champion_progress(pips, _VA_PIPS)
	var side: int = _LOG_ENEMY if ctx.owner == "enemy" else _LOG_PLAYER
	_log("  Champion progress: %d / %d sparks consumed." % [mini(total, _VA_THRESHOLD), _VA_THRESHOLD], side)
	if total >= _VA_THRESHOLD:
		_summon_enemy_champion("champion_void_aberration")

func on_enemy_died_champion_va(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_void_aberration":
		_on_enemy_champion_killed()

func _champion_va_is_alive() -> bool:
	for m: MinionInstance in _scene.enemy_board:
		if m.card_data.id == "champion_void_aberration":
			return true
	return false

## ── Champion: Void Herald ─────────────────────────────────────────────────
## Summon condition: 6 spark-cost cards played (cumulative).
## Aura: All spark costs become 0. Void Rift stops generating sparks.
## On death: deal 20% of enemy hero max HP to enemy hero.

const _VH_THRESHOLD := 6
const _VH_PIPS := 6

func on_enemy_spark_card_champion_vh(ctx: EventContext) -> void:
	if _scene.get("_champion_vh_summoned"):
		return
	# Check if the card that triggered this event had a spark cost
	var card: CardData = ctx.card
	if card == null or card.void_spark_cost <= 0:
		return
	_scene._champion_vh_spark_cards_played += 1
	var total: int = _scene._champion_vh_spark_cards_played
	var pips: int = mini(total, _VH_PIPS)
	_scene._update_champion_progress(pips, _VH_PIPS)
	var side: int = _LOG_ENEMY if ctx.owner == "enemy" else _LOG_PLAYER
	_log("  Champion progress: %d / %d spark-cost cards played." % [mini(total, _VH_THRESHOLD), _VH_THRESHOLD], side)
	if total >= _VH_THRESHOLD:
		_summon_enemy_champion("champion_void_herald")

func on_enemy_died_champion_vh(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_void_herald":
		_on_enemy_champion_killed()

func _champion_vh_is_alive() -> bool:
	for m: MinionInstance in _scene.enemy_board:
		if m.card_data.id == "champion_void_herald":
			return true
	return false

## ── Champion: Void Scout ──────────────────────────────────────────────────
## Summon condition: 5 critical strikes consumed by enemy minions.
## On summon: gains 1 Critical Strike.
## Aura: enemy_crit_multiplier = 2.5 (instead of 2.0).
## On death: deal 20% of enemy hero max HP to enemy hero.

const _VS_THRESHOLD := 5
const _VS_PIPS := 5

## Track crit consumption at end of enemy turn (after all attacks resolve).
## Uses _enemy_crits_consumed counter incremented by CombatManager._apply_crit.
func on_enemy_turn_end_champion_vs(ctx: EventContext) -> void:
	if _scene.get("_champion_vs_summoned"):
		return
	var total: int = _scene._enemy_crits_consumed if _scene.get("_enemy_crits_consumed") != null else 0
	if total <= 0:
		return
	var pips: int = mini(total, _VS_PIPS)
	_scene._update_champion_progress(pips, _VS_PIPS)
	if total >= _VS_THRESHOLD and not _scene.get("_champion_vs_summoned"):
		_log("  Champion progress: %d / %d crits consumed." % [_VS_THRESHOLD, _VS_THRESHOLD], _LOG_ENEMY)
		_summon_enemy_champion("champion_void_scout")
		# Grant 1 Critical Strike on summon
		for m: MinionInstance in _scene.enemy_board:
			if m.card_data.id == "champion_void_scout":
				BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike")
				_scene._refresh_slot_for(m)
				break
		# Set enemy crit multiplier to 2.5
		_scene.set("enemy_crit_multiplier", 2.5)

func on_enemy_died_champion_vs(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_void_scout":
		# Revert crit multiplier
		_scene.set("enemy_crit_multiplier", 0.0)
		_on_enemy_champion_killed()

func _champion_vs_is_alive() -> bool:
	for m: MinionInstance in _scene.enemy_board:
		if m.card_data.id == "champion_void_scout":
			return true
	return false

## ── Champion: Void Warband ────────────────────────────────────────────────
## Summon condition: 2 Spirits consumed as spark fuel.
## On summon: gains 1 Critical Strike.
## Aura: (separate — to be defined)

const _VW_THRESHOLD := 2
const _VW_PIPS := 2

## spirit_resonance passive — shared enemy passive, 2 effects:
##   1. Spirits with crit have +1 effective spark_value (checked in MinionInstance)
##   2. Consuming a crit-Spirit spawns a 100/100 Void Spark
func on_spark_consumed_spirit_resonance(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null:
		return
	if minion.card_data.minion_type != Enums.MinionType.SPIRIT:
		return
	if not minion.has_critical_strike():
		return
	_scene._summon_token("void_spark", "enemy", 100, 100)
	_log("  Spirit Resonance: crit-Spirit consumed — a Void Spark manifests!", _LOG_ENEMY)

func on_spark_consumed_champion_vw(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null:
		return
	if minion.card_data.minion_type != Enums.MinionType.SPIRIT:
		return
	# Champion already summoned — no further tracking needed
	if _scene.get("_champion_vw_summoned"):
		return
	_scene._champion_vw_spirits_consumed += 1
	var total: int = _scene._champion_vw_spirits_consumed
	var pips: int = mini(total, _VW_PIPS)
	_scene._update_champion_progress(pips, _VW_PIPS)
	_log("  Champion progress: %d / %d Spirits consumed." % [mini(total, _VW_THRESHOLD), _VW_THRESHOLD], _LOG_ENEMY)
	if total >= _VW_THRESHOLD:
		_summon_enemy_champion("champion_void_warband")
		# Grant 1 Critical Strike on summon
		for m: MinionInstance in _scene.enemy_board:
			if m.card_data.id == "champion_void_warband":
				BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike")
				_scene._refresh_slot_for(m)
				break

func on_enemy_died_champion_vw(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_void_warband":
		_on_enemy_champion_killed()
		return
	# Aura: while champion is alive, dying friendly Spirits apply 1 Critical Strike
	# to a random friendly minion.
	if not _champion_vw_is_alive():
		return
	if minion.card_data.minion_type != Enums.MinionType.SPIRIT:
		return
	var candidates: Array[MinionInstance] = []
	for m: MinionInstance in _scene.enemy_board:
		if m == minion:
			continue
		candidates.append(m)
	if candidates.is_empty():
		return
	var target: MinionInstance = candidates[randi() % candidates.size()]
	BuffSystem.apply(target, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike")
	_scene._refresh_slot_for(target)
	if _scene.get("_vw_death_crit_grants") != null:
		_scene._vw_death_crit_grants += 1
	_log("  Void Warband aura: %s's death grants Critical Strike to %s." % [minion.card_data.card_name, target.card_data.card_name], _LOG_ENEMY)

func _champion_vw_is_alive() -> bool:
	for m: MinionInstance in _scene.enemy_board:
		if m.card_data.id == "champion_void_warband":
			return true
	return false

## ── Champion: Void Captain ──────────────────────────────────────────────
## Summon condition: 2 Throne's Command cast.
## On summon: gains 2 Critical Strike.
## Aura: When a friendly minion consumes a Critical Strike, deal 100 damage
##        to each of 2 random enemies (minions or hero).

const _VC_THRESHOLD := 2
const _VC_PIPS := 2

func on_enemy_spell_champion_vc(ctx: EventContext) -> void:
	if _scene.get("_champion_vc_summoned"):
		return
	var card: CardData = ctx.card
	if card == null or card.id != "thrones_command":
		return
	_scene._champion_vc_tc_cast += 1
	var total: int = _scene._champion_vc_tc_cast
	var pips: int = mini(total, _VC_PIPS)
	_scene._update_champion_progress(pips, _VC_PIPS)
	_log("  Champion progress: %d / %d Throne's Command cast." % [mini(total, _VC_THRESHOLD), _VC_THRESHOLD], _LOG_ENEMY)
	if total >= _VC_THRESHOLD:
		_summon_enemy_champion("champion_void_captain")
		# Grant 2 Critical Strike on summon
		for m: MinionInstance in _scene.enemy_board:
			if m.card_data.id == "champion_void_captain":
				BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, 2, "critical_strike")
				_scene._refresh_slot_for(m)
				break

func on_enemy_died_champion_vc(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_void_captain":
		_on_enemy_champion_killed()

func _champion_vc_is_alive() -> bool:
	for m: MinionInstance in _scene.enemy_board:
		if m.card_data.id == "champion_void_captain":
			return true
	return false

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

## captain_orders (Fight 12 — Void Captain):
##   1. Throne's Command costs 1 less spark (handled in CombatProfile._effective_spark_cost)
##   2. At end of enemy turn, consume 1 crit from each friendly minion and deal
##      that minion's ATK as damage to enemy hero.
func on_enemy_turn_end_captain_orders(_ctx: EventContext) -> void:
	for m: MinionInstance in _scene.enemy_board:
		if not BuffSystem.has_type(m, Enums.BuffType.CRITICAL_STRIKE):
			continue
		BuffSystem.remove_one_source(m, "critical_strike")
		var dmg: int = m.effective_atk()
		if dmg > 0:
			_scene.combat_manager.apply_hero_damage("player", dmg, Enums.DamageType.SPELL)
			_log("  Captain's Orders: %s's crit consumed — %d damage to enemy hero." % [m.card_data.card_name, dmg], _LOG_ENEMY)
		_scene._refresh_slot_for(m)
		# Track for crit counter
		var key := "_enemy_crits_consumed"
		var cur = _scene.get(key)
		if cur != null:
			_scene.set(key, (cur as int) + 1)

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
## Summon condition: 2nd Pack Frenzy cast.
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
	# Track Pack Frenzy casts toward summon threshold
	var count: int = _scene.get("_champion_im_frenzy_count") + 1
	_scene.set("_champion_im_frenzy_count", count)
	_scene._update_champion_progress(count, 2)
	_log("  Champion progress: %d / 2 Pack Frenzy casts." % count, _LOG_ENEMY)
	if count >= 2:
		_summon_enemy_champion("champion_imp_matriarch")

func on_enemy_died_champion_im(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_imp_matriarch":
		_on_enemy_champion_killed()

## ── Shared champion helpers ─────────────────────────────────────────────────

## ── Champion: Abyss Cultist Patrol (Act 2) ──────────────────────────────────
## Summon condition: 4 corruption stacks consumed (detonated).
## Aura: corruption applied to player minions instantly detonates (100 dmg per stack).
## On death: deal 20% max HP to enemy hero.

## Called by corrupt_authority_imp handler — tracks stacks consumed toward champion threshold.
func on_champion_acp_track_stacks(stacks: int) -> void:
	if _scene.get("_champion_acp_summoned"):
		return
	var total: int = _scene._champion_acp_stacks_consumed + stacks
	_scene._champion_acp_stacks_consumed = total
	_scene._update_champion_progress(mini(total, 5), 5)
	_log("  Champion progress: %d / 5 corruption stacks consumed." % mini(total, 5), _LOG_ENEMY)
	if total >= 5:
		_summon_enemy_champion("champion_abyss_cultist_patrol")

## Aura: while champion alive, corruption application instantly detonates.
## Hooks into ON_ENEMY_MINION_SUMMONED at high priority to run after corrupt_authority_human
## applies corruption. Checks for any corruption on player minions and detonates immediately.
func on_enemy_summon_champion_acp_corrupt(_ctx: EventContext) -> void:
	if not _scene.get("_champion_acp_summoned"):
		return
	# Instantly detonate all corruption stacks on player minions
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
		_log("  Cultist Patrol aura: instant detonation — %s takes %d damage!" % [m.card_data.card_name, 100 * stacks], _LOG_ENEMY)

func on_enemy_died_champion_acp(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_abyss_cultist_patrol":
		_on_enemy_champion_killed()

## ── Champion: Void Ritualist (Act 2) ────────────────────────────────────────
## Summon condition: first ritual_sacrifice triggers.
## Aura: rune placement costs 1 less mana.
## On death: deal 20% max HP to enemy hero.

## Called by ritual_sacrifice handler when the ritual fires.
func on_enemy_summon_champion_vr(_ctx: EventContext) -> void:
	# Ritual sacrifice handler calls this — champion spawns on first ritual
	pass  # Summon handled directly in ritual_sacrifice via on_ritual_sacrifice_champion_vr()

func on_ritual_sacrifice_champion_vr() -> void:
	if _scene.get("_champion_vr_summoned"):
		return
	_scene._update_champion_progress(1, 1)
	_log("  Champion progress: 1 / 1 ritual sacrifice triggered.", _LOG_ENEMY)
	_summon_enemy_champion("champion_void_ritualist")

func on_enemy_died_champion_vr(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_void_ritualist":
		_on_enemy_champion_killed()

## ── Champion: Corrupted Handler (Act 2 Boss) ───────────────────────────────
## Summon condition: 4 void sparks summoned.
## Passive (always active): feral imp summon corrupts all sparks on both boards.
## Aura (champion alive): whenever a Void Spark is summoned, deal 200 damage to player hero.
## On death: deal 20% max HP to enemy hero.

## Track spark creation toward champion threshold. Champion aura: spark summon → 200 hero damage.
func on_enemy_summon_champion_ch_spark_buff(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	# Track void spark creation toward champion threshold
	if minion.card_data.id == "void_spark":
		if not _scene.get("_champion_ch_summoned"):
			_scene._champion_ch_spark_count += 1
			var count: int = _scene._champion_ch_spark_count
			_scene._update_champion_progress(mini(count, 3), 3)
			_log("  Champion progress: %d / 3 void sparks created." % mini(count, 3), _LOG_ENEMY)
			if count >= 3:
				_summon_enemy_champion("champion_corrupted_handler")
		# Champion aura: each spark summoned deals 200 damage to player hero (only while champion is alive)
		if _scene.get("_champion_ch_summoned") and self._champion_ch_is_alive():
			_scene.combat_manager.apply_hero_damage("player", 200, Enums.DamageType.SPELL)
			var prev_dmg: int = _scene.get("_champion_ch_aura_dmg") if _scene.get("_champion_ch_aura_dmg") != null else 0
			_scene.set("_champion_ch_aura_dmg", prev_dmg + 200)
			_log("  Corrupted Handler aura: Void Spark summoned → 200 damage to player!", _LOG_ENEMY)

func on_enemy_died_champion_ch(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_corrupted_handler":
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
		"champion_abyss_cultist_patrol":
			_scene.set("_champion_acp_summoned", true)
		"champion_void_ritualist":
			_scene.set("_champion_vr_summoned", true)
		"champion_corrupted_handler":
			_scene.set("_champion_ch_summoned", true)
		"champion_rift_stalker":
			_scene.set("_champion_rs_summoned", true)
		"champion_void_aberration":
			_scene.set("_champion_va_summoned", true)
		"champion_void_herald":
			_scene.set("_champion_vh_summoned", true)
		"champion_void_scout":
			_scene.set("_champion_vs_summoned", true)
		"champion_void_warband":
			_scene.set("_champion_vw_summoned", true)
		"champion_void_captain":
			_scene.set("_champion_vc_summoned", true)
	var count: int = _scene.get("_champion_summon_count")
	_scene.set("_champion_summon_count", count + 1)
	_scene._summon_token(card_id, "enemy")
	_log("  ★ %s champion has arrived!" % CardDatabase.get_card(card_id).card_name, _LOG_ENEMY)
	# Apply aura immediately for Rogue Imp Pack
	if card_id == "champion_rogue_imp_pack":
		_refresh_champion_rip_aura()

func _on_enemy_champion_killed() -> void:
	_log("  ★ Champion slain!", _LOG_ENEMY)
	_scene._on_champion_killed()

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

func _champion_ch_is_alive() -> bool:
	for m in _scene.enemy_board:
		if (m as MinionInstance).card_data.id == "champion_corrupted_handler":
			return true
	return false

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
