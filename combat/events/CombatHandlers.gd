## CombatHandlers.gd
## All trigger handler logic for combat events.
## Reads and writes gameplay only through the typed CombatState; presentation
## follows from the journal events the state appends (plan 4.4).
##
## Usage (CombatSetup.setup):
##   var h := CombatHandlers.new()
##   h.setup(state)
##   trigger_manager.register(event, h.method_name, priority)
class_name CombatHandlers
extends RefCounted

## The combat state — every gameplay read and write.
var state: CombatState

## Log line types (Enums.LogType) for each side's lines.
const _LOG_PLAYER := Enums.LogType.PLAYER
const _LOG_ENEMY  := Enums.LogType.ENEMY

func setup(p_state: CombatState) -> void:
	state = p_state

# ---------------------------------------------------------------------------
# ON_PLAYER_TURN_START
# ---------------------------------------------------------------------------

## Old passive relic system removed — relics are now activated abilities.
## See RelicRuntime, RelicEffects, and RelicBar for the new system.

## Fires passive_effect_steps for every active environment on every turn start.
## Each environment runs with ctx.owner = the side that played it, so DAMAGE_HERO
## targets that side's opponent and _friendly_board() resolves correctly. An env
## fires on its owner's turn unconditionally; it fires on the OTHER side's turn
## only if fires_on_enemy_turn is true (read as "fires on both turns").
func on_player_turn_environment(ctx_evt: EventContext) -> void:
	_run_env_passives_for_turn(ctx_evt.event_type)

func on_minion_turn_start_passives(_ctx: EventContext) -> void:
	for m in state.player_board.duplicate():
		var mc := m.card_data as MinionCardData
		if mc and not mc.on_turn_start_effect_steps.is_empty():
			var ectx    := EffectContext.make(state, "player")
			ectx.source = m
			EffectResolver.run(mc.on_turn_start_effect_steps, ectx)

## ON_PLAYER_TURN_END / ON_ENEMY_TURN_END — fires every minion's on_turn_end_effect_steps
## for the side whose turn is ending. Used by Altar Thrall (sacrifice self) and any future
## upkeep-style minions.
func on_minion_turn_end_passives(ctx: EventContext) -> void:
	var board: Array
	var owner: String
	if ctx.event_type == Enums.TriggerEvent.ON_PLAYER_TURN_END:
		board = state.player_board
		owner = "player"
	else:
		board = state.enemy_board
		owner = "enemy"
	for m in board.duplicate():
		var mc := m.card_data as MinionCardData
		if mc and not mc.on_turn_end_effect_steps.is_empty():
			var ectx    := EffectContext.make(state, owner)
			ectx.source = m
			ectx.source_card_id = mc.id
			EffectResolver.run(mc.on_turn_end_effect_steps, ectx)

# ---------------------------------------------------------------------------
# ON_ENEMY_TURN_START
# ---------------------------------------------------------------------------

func on_enemy_turn_environment(ctx_evt: EventContext) -> void:
	_run_env_passives_for_turn(ctx_evt.event_type)

## Shared implementation for both ON_*_TURN_START env-passive sweeps. Walks both
## sides' active environments; for each, owner == that side; only runs when the
## current turn matches the owner OR the env's fires_on_enemy_turn flag is set.
func _run_env_passives_for_turn(event_type: int) -> void:
	var turn_owner: String = "player" if event_type == Enums.TriggerEvent.ON_PLAYER_TURN_START else "enemy"
	for entry in _active_environments():
		var env: EnvironmentCardData = entry["env"]
		if env.passive_effect_steps.is_empty():
			continue
		var env_owner: String = entry["owner"]
		if env_owner != turn_owner and not env.fires_on_enemy_turn:
			continue
		var ctx := EffectContext.make(state, env_owner)
		EffectResolver.run(env.passive_effect_steps, ctx)

## Returns [{env, owner}, ...] for every active environment across both sides.
func _active_environments() -> Array:
	var out: Array = []
	for side in ["player", "enemy"]:
		var env: EnvironmentCardData = state.environment_of(side)
		if env != null:
			out.append({"env": env, "owner": side})
	return out

# ---------------------------------------------------------------------------
# ON_PLAYER_SPELL_CAST
# ---------------------------------------------------------------------------

func on_void_archmagus_spell(_ctx: EventContext) -> void:
	var fired: Array[String] = []
	for m in state.player_board:
		var eid: String = m.card_data.on_spell_cast_passive_effect_id
		if eid != "" and not eid in fired:
			_apply_spell_cast_passive(eid)
			fired.append(eid)

func _apply_spell_cast_passive(effect_id: String) -> void:
	match effect_id:
		"add_void_bolt_on_spell":
			# _card_for so any future cost/effect overrides on Void Bolt apply.
			var bolt: CardData = state._card_for("player", "void_bolt")
			if bolt:
				state.add_to_hand("player", bolt)
				_log("  Void Archmagus: Void Bolt added to hand.", _LOG_PLAYER)

# ---------------------------------------------------------------------------
# ON_PLAYER_CARD_DRAWN
# ---------------------------------------------------------------------------

func on_card_drawn_void_echo(ctx: EventContext) -> void:
	if ctx.card == null or not _card_has_tag(ctx.card, "base_void_imp"):
		return
	# Once per turn — tracked via a state flag, reset at player turn start.
	if state._void_echo_fired_this_turn:
		return
	# Append directly — NOT via state.add_to_hand — so the copy doesn't fire
	# ON_PLAYER_CARD_DRAWN again. _card_for so clan rules / overrides apply to the copy.
	var copy: CardData = state._card_for("player", "void_imp")
	var hand: Array[CardInstance] = state.player_hand
	if copy and hand.size() < CombatState.HAND_MAX:
		var inst := CardInstance.create(copy)
		hand.append(inst)
		state._void_echo_fired_this_turn = true
		state.card_generated.emit("player", inst)
		state.emit_event(CombatEvent.Kind.CARD_GENERATED, "player", {inst = inst})
		_log("  Void Echo: Void Imp drawn — free copy added to hand.", _LOG_PLAYER)

## Reset void_echo once-per-turn flag at player turn start.
func on_player_turn_start_void_echo(_ctx: EventContext) -> void:
	state._void_echo_fired_this_turn = false

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_SUMMONED
# ---------------------------------------------------------------------------

## void_imp_boost (Lord Vael hero passive) — was +100 ATK (buff) + 100 HP (direct)
## at summon. Migrated to a CardModRules clan rule so the boost is BASE stats:
## the +100 ATK is now cleanse-immune, hand previews show the boosted stats, and
## tokens summoned from any source (Imp Vessel, Recruiter, etc.) inherit the
## boost automatically. See cards/data/CardModRules.gd "void_imp_boost".
##
## Handler retained only for the combat-log line so the player can see when the
## passive fired. No stat application.
func on_summon_passive_void_imp_boost(ctx: EventContext) -> void:
	if not _is_void_imp(ctx.minion):
		return
	var hero := HeroDatabase.get_hero(state.player_hero_id)
	_log("  %s: %s summoned with passive +100/+100." % [(hero.hero_name if hero else "Hero"), ctx.card.card_name], _LOG_PLAYER)

## Old passive relic summon handlers removed — relics are now activated abilities.

## swarm_discipline (Lord Vael Endless Tide T1) — was +100 HP (direct) at summon.
## Migrated to CardModRules clan rule. Handler retained only for the log line.
## See cards/data/CardModRules.gd "swarm_discipline".
func on_summon_swarm_discipline(ctx: EventContext) -> void:
	if not _is_void_imp(ctx.minion):
		return
	_log("  Swarm Discipline: %s +100 HP (passive)." % ctx.card.card_name, _LOG_PLAYER)

func on_ritual_fired_ritual_surge(ctx: EventContext) -> void:
	state._summon_token("void_imp", ctx.owner)
	_log("  Ritual Surge: Void Imp summoned!", _LOG_PLAYER)

## piercing_void retag retired — Void Imp's on_play_effect_steps now declares
## the VOID_BOLT + VOID_MARK steps directly via talent_overrides. See
## CardDatabase.gd void_imp.talent_overrides for the override entry.

## rune_caller / imp_evolution / imp_warband retired — all three migrated to
## CardModRules append_on_play_effect_steps. See cards/data/CardModRules.gd.
## - rune_caller: TUTOR rune + MOD_LAST_ADDED_COST mana -1 on Void Imp's on-play.
## - imp_evolution: ADD_CARD senior_void_imp gated by once_per_turn:imp_evolution.
## - imp_warband: BUFF_ATK ALL_FRIENDLY filter VOID_IMP exclude_self on Senior's on-play.

func on_summon_board_synergies(ctx: EventContext) -> void:
	var summoned := ctx.minion
	for m in state.player_board:
		var pid: String = (m.card_data as MinionCardData).passive_effect_id
		if pid != "" and m != summoned:
			_apply_board_passive_on_summon(pid, m, summoned)
	if _is_void_imp(summoned):
		state._refresh_slot_for(summoned)
		state._check_champion_triggers()

## Korrath FORMATION — fires whenever a minion enters the board (either side). Walks
## both adjacent slots on the summoned minion's own side and, for each adjacent
## minion, attempts to fire Formation in both directions.
##
## Trigger rules (combined task 036 + task 037):
## - **One-shot consumable per lifetime (task 036).** Once an actor's
##   formation_fired flips to true, that actor's Formation can never re-trigger.
## - **Both-sides requirement (task 037).** Actor needs same-race minions on BOTH
##   the left (slot_index - 1) AND the right (slot_index + 1) adjacent slots.
##   Each side is checked independently against the actor's race set via
##   shares_race, so dual-tag actors can have either tag satisfy each side.
##   Edge-slot actors (slot 0 or last slot) can never fire Formation through
##   normal adjacency — Battle Drillmaster is the only rescue path.
##
## Bidirectional walk: a newly placed minion can trigger its OWN Formation against
## an existing neighbor, AND an existing neighbor can trigger ITS Formation against
## the newcomer. Each actor's formation_fired flag is independent.
func on_minion_summoned_formation(ctx: EventContext) -> void:
	var summoned: MinionInstance = ctx.minion
	if summoned == null or summoned.slot_index < 0:
		return
	var board: Array = state.player_board if summoned.owner == "player" else state.enemy_board
	if board == null:
		return
	for raw in board:
		var neighbor: MinionInstance = raw as MinionInstance
		if neighbor == null or neighbor == summoned:
			continue
		var dx: int = absi(neighbor.slot_index - summoned.slot_index)
		if dx != 1:
			continue
		_try_fire_formation(summoned, neighbor)
		_try_fire_formation(neighbor, summoned)

## Korrath T1 — Commander's Reach. Whenever any friendly minion's FORMATION fires,
## permanently grant +50 Armour to every friendly Human on the same side. Stacks
## across multiple Formation triggers in a combat. Buff routes through MinionInstance
## .add_armour() so T3 unbreakable still doubles the knight's portion.
func on_formation_triggered_commanders_reach(ctx: EventContext) -> void:
	var actor: MinionInstance = ctx.minion
	if actor == null or actor.owner != "player":
		return
	for raw in state.player_board:
		var m: MinionInstance = raw as MinionInstance
		if m == null or m.card_data == null:
			continue
		if not (m.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN):
			continue
		m.add_armour(50, state)
		state._refresh_slot_for(m)

## Korrath B2 T0 — Runeforge Strike on-attack half. Whenever the Abyssal Knight
## attacks (any target), place a random rune on the player's board. Board-full +
## absorption logic lives in CombatState._korrath_place_random_rune.
func on_player_attack_runeforge_strike(ctx: EventContext) -> void:
	var attacker: MinionInstance = ctx.minion
	if attacker == null or attacker.card_data == null:
		return
	if attacker.card_data.id != "abyssal_knight":
		return
	state._korrath_place_random_rune()

## Korrath B2 T2 — Path of Demons. When a Demon is summoned on the player side, deal
## 50 damage to a random enemy, repeated X times — where X = active rune slots +
## total absorbed aura stacks across friendly Abyssal Knights. Repeats the dmg
## random-pick X times so each iteration may hit a different enemy.
func on_summon_path_of_demons(ctx: EventContext) -> void:
	var summoned: MinionInstance = ctx.minion
	if summoned == null or summoned.owner != "player":
		return
	if not (summoned.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
		return
	var x: int = _korrath_x_count()
	if x <= 0:
		return
	for _i in x:
		var pool: Array = (state.enemy_board as Array).filter(
			func(m): return m != null and m.current_health > 0)
		if pool.is_empty():
			return
		var target: MinionInstance = state.rng_pick(pool)
		var info := CombatManager.make_damage_info(50, Enums.DamageSource.SPELL,
				Enums.DamageSchool.NONE, summoned, "path_of_demons")
		state.combat_manager.apply_damage_to_minion(target, info)

## Korrath B2 T2 — Path of Humans. When a Human is summoned on the player side, give
## 50 ATK to a random friendly minion, repeated X times. X uses the same formula as
## path_of_demons. Each repetition may pick a different friendly minion.
func on_summon_path_of_humans(ctx: EventContext) -> void:
	var summoned: MinionInstance = ctx.minion
	if summoned == null or summoned.owner != "player":
		return
	if not (summoned.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN):
		return
	var x: int = _korrath_x_count()
	if x <= 0:
		return
	for _i in x:
		var pool: Array = (state.player_board as Array).filter(
			func(m): return m != null and m.current_health > 0)
		if pool.is_empty():
			return
		var target: MinionInstance = state.rng_pick(pool)
		BuffSystem.apply(target, Enums.BuffType.ATK_BONUS, 50, "path_of_humans", false, false)
		state._refresh_slot_for(target)

## X = active rune slots on board + total absorbed-aura stacks across friendly knights.
func _korrath_x_count() -> int:
	var rune_slots: int = 0
	for trap in state.active_traps:
		if (trap as TrapCardData).is_rune:
			rune_slots += 1
	return rune_slots + state._korrath_absorbed_aura_count()

## Korrath B2 T3 — Grand Ritual: Chaos. Fires on ON_RUNE_PLACED whenever the rune
## board reaches 3. Consumes ALL 3 active runes, fires three volatile effects with
## per-effect damage/value variance, then randomly picks one as Enhanced (×3 output)
## and re-applies that bonus on top. The "T1 triggers three times simultaneously"
## clause from the design doc is now satisfied implicitly — each of the three
## _remove_rune_aura calls below routes through the centralized B2 T1 hook in
## CombatState._remove_rune_aura, granting one absorbed-aura stack per consumed
## rune (each pick may land on a different Abyssal Knight).
func on_rune_placed_grand_ritual_chaos(_ctx: EventContext) -> void:
	# Re-entrancy guard: removing the runes will not re-fire this handler
	# (ON_RUNE_PLACED only fires on placement), but a defensive check on the
	# rune count keeps the path predictable.
	var runes: Array = (state.active_traps as Array).filter(
			func(t): return (t as TrapCardData).is_rune)
	if runes.size() < 3:
		return

	# ── Consume any 3 runes (oldest first). Clean up auras via _remove_rune_aura
	# so board passives drop correctly; mirror the bookkeeping in _fire_ritual.
	var to_consume: Array = runes.slice(0, 3)
	for rune in to_consume:
		state._remove_rune_aura(rune as TrapCardData, "player")
		(state.active_traps as Array).erase(rune)
	state.traps_changed.emit("player")
	_log("★ GRAND RITUAL: CHAOS — three runes shatter!", _LOG_PLAYER)

	# ── Roll variance for each effect, then randomly pick one to Enhance (×3).
	var burst_amount: int = state.rng_range(200, 400)
	var sweep_amount: int = state.rng_range(100, 250)
	var forge_amount: int = state.rng_range(200, 400)
	var enhanced_idx: int = state.rng_index(3)
	if enhanced_idx == 0: burst_amount *= 3
	elif enhanced_idx == 1: sweep_amount *= 3
	else: forge_amount *= 3
	var enhanced_label: String = ["Burst", "Sweep", "Forge"][enhanced_idx]
	_log("  Enhanced: %s!" % enhanced_label, _LOG_PLAYER)

	# ── Effect 1 (Burst) — single-target spell damage to a random enemy minion.
	var enemy_pool: Array = (state.enemy_board as Array).filter(
			func(m): return m != null and (m as MinionInstance).current_health > 0)
	if not enemy_pool.is_empty():
		var target: MinionInstance = state.rng_pick(enemy_pool)
		var info := CombatManager.make_damage_info(burst_amount, Enums.DamageSource.SPELL,
				Enums.DamageSchool.NONE, null, "grand_ritual_chaos")
		state.combat_manager.apply_damage_to_minion(target, info)
		_log("  Burst: %d spell dmg to %s." % [burst_amount, target.card_data.card_name], _LOG_PLAYER)

	# ── Effect 2 (Sweep) — spell damage to ALL enemy minions. Snapshot pool so
	# mid-resolution deaths don't mutate iteration.
	var sweep_targets: Array = (state.enemy_board as Array).filter(
			func(m): return m != null and (m as MinionInstance).current_health > 0)
	if not sweep_targets.is_empty():
		_log("  Sweep: %d spell dmg to all enemy minions." % sweep_amount, _LOG_PLAYER)
		for t in sweep_targets:
			var info := CombatManager.make_damage_info(sweep_amount, Enums.DamageSource.SPELL,
					Enums.DamageSchool.NONE, null, "grand_ritual_chaos")
			state.combat_manager.apply_damage_to_minion(t as MinionInstance, info)

	# ── Effect 3 (Forge) — permanent ATK to a random friendly minion.
	var friendly_pool: Array = (state.player_board as Array).filter(
			func(m): return m != null and (m as MinionInstance).current_health > 0)
	if not friendly_pool.is_empty():
		var fwd: MinionInstance = state.rng_pick(friendly_pool)
		BuffSystem.apply(fwd, Enums.BuffType.ATK_BONUS, forge_amount,
				"grand_ritual_chaos", false, false)
		state._refresh_slot_for(fwd)
		_log("  Forge: +%d ATK to %s." % [forge_amount, fwd.card_data.card_name], _LOG_PLAYER)

	# Fire ON_RITUAL_FIRED so ritual_surge and other ritual-listeners react.
	if state.trigger_manager != null:
		var fired_ctx := EventContext.make(Enums.TriggerEvent.ON_RITUAL_FIRED, "player")
		state.trigger_manager.fire(fired_ctx)

## Korrath B3 T1 — Corrupting Strike. Knight applies 1 Corruption stack to its attack
## target on every attack — minion or enemy hero. Routes through state's
## _corrupt_minion / _corrupt_hero so corrupting_presence's one-shot AB emission
## (when active) fires consistently regardless of target type.
func on_player_attack_corrupting_strike(ctx: EventContext) -> void:
	var attacker: MinionInstance = ctx.minion
	if attacker == null or attacker.card_data == null:
		return
	if attacker.card_data.id != "abyssal_knight":
		return
	var defender = ctx.defender
	if defender is MinionInstance:
		state._corrupt_minion(defender as MinionInstance)
	elif defender is String and defender == "enemy_hero":
		state._corrupt_hero("enemy")

## Korrath B3 T2 — Path of Shattering. Friendly Demon attacks apply 50 Armour
## Break to the attack target (minion or enemy hero).
func on_player_attack_path_of_shattering(ctx: EventContext) -> void:
	var attacker: MinionInstance = ctx.minion
	if attacker == null or attacker.owner != "player":
		return
	if not (attacker.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
		return
	var defender = ctx.defender
	if defender is MinionInstance:
		BuffSystem.apply(defender as MinionInstance, Enums.BuffType.ARMOUR_BREAK, 50,
				"path_of_shattering", false, false)
	elif defender is String and defender == "enemy_hero":
		state.apply_hero_buff("enemy", Enums.BuffType.ARMOUR_BREAK, 50,
				"path_of_shattering")

## Korrath B3 T3 — Shattering Doom. When an enemy minion dies, snapshot its total
## Armour Break stacks and deal that as spell damage to every other enemy minion on
## the board. The dead minion itself is excluded (already at 0 HP). Damage is
## DamageSource.SPELL so it bypasses any armour the targets have.
func on_enemy_died_shattering_doom(ctx: EventContext) -> void:
	var dead: MinionInstance = ctx.minion
	if dead == null:
		return
	var ab_total: int = BuffSystem.sum_type(dead, Enums.BuffType.ARMOUR_BREAK)
	if ab_total <= 0:
		return
	for raw in (state.enemy_board as Array).duplicate():
		var m: MinionInstance = raw as MinionInstance
		if m == null or m == dead or m.current_health <= 0:
			continue
		var info := CombatManager.make_damage_info(ab_total, Enums.DamageSource.SPELL,
				Enums.DamageSchool.NONE, dead, "shattering_doom")
		state.combat_manager.apply_damage_to_minion(m, info)

## Korrath — per-minion attack-rider dispatcher. Fires on ON_PLAYER_ATTACK_POST
## (after the strike's damage resolves on the defender, before counter-attack —
## same beat as path_of_shattering). Iterates attacker.attack_riders and runs
## each rider's effect_steps with ctx.source = attacker, ctx.chosen_target bound
## to the defender (per rider scope == "attack_target"). Hero defenders are
## passed through as the sentinel string "enemy_hero" / "player_hero" so steps
## that handle a String defender (APPLY_ARMOUR_BREAK against a hero) work via
## the same code path as Banner of the Order's rider.
##
## A symmetric handler fires on ON_ENEMY_ATTACK so enemy-side carriers also fire
## their riders. (No riders are stamped on enemy minions in shipped content, but
## the symmetry matches every other attack-driven effect.)
##
## Registered in CombatSetup with no card_id filter — riders are dynamic data,
## not a card-static keyword, so every attack must check the rider list.
func on_attack_fire_riders(ctx: EventContext) -> void:
	var attacker: MinionInstance = ctx.minion
	if attacker == null or attacker.attack_riders.is_empty():
		return
	var defender = ctx.defender
	# Build a copy in case a rider somehow mutates the list (defensive — currently
	# no rider step removes riders, but copy keeps iteration stable).
	for rider_any in attacker.attack_riders.duplicate():
		var rider: Dictionary = rider_any
		var steps: Array = rider.get("effect_steps", [])
		if steps.is_empty():
			continue
		var ectx := EffectContext.make(state, attacker.owner)
		ectx.source         = attacker
		ectx.source_card_id = rider.get("source_tag", "")
		# Bind chosen_target for minion defenders; hero defenders go through
		# include_hero on APPLY_ARMOUR_BREAK steps instead (rider's scope today
		# is "attack_target" and steps are expected to be SINGLE_CHOSEN-like).
		if defender is MinionInstance:
			ectx.chosen_target = defender
			EffectResolver.run(steps, ectx)
		elif defender is String:
			# Hero defender — synthesize a single-step path that hits the hero
			# directly. Banner's rider is APPLY_ARMOUR_BREAK against the attack
			# target; for hero defenders we apply directly via apply_hero_buff.
			# Iterate steps and route APPLY_ARMOUR_BREAK manually; other step
			# types are unsupported as rider steps today (loud warn).
			for raw in steps:
				var d: Dictionary = raw if raw is Dictionary else {}
				var t: String = d.get("type", "")
				if t == "APPLY_ARMOUR_BREAK":
					var amt: int = d.get("amount", 0)
					var tag: String = d.get("source_tag", rider.get("source_tag", ""))
					var hero_side: String = "enemy" if attacker.owner == "player" else "player"
					state.apply_hero_buff(hero_side, Enums.BuffType.ARMOUR_BREAK, amt, tag)
				else:
					push_warning("Attack rider hero-defender path: unsupported step type '%s' (rider tag=%s)" % [t, rider.get("source_tag", "")])

## Korrath — Battle Drillmaster cascade. Fires every FORMATION minion on the
## given side whose formation_fired flag is false, IGNORING the adjacency /
## sandwich requirement that normally gates Formation. Each cascade-fired
## minion still consumes its one-shot — Drillmaster cannot re-fire an already
## consumed Formation. The order is left-to-right by slot_index for
## determinism. Drillmaster itself doesn't have FORMATION so it is not in the
## iteration; if it did, it would be skipped (formation_fired check still
## applies).
func fire_unconsumed_formations_cascade(side: String) -> void:
	var board: Array = state.player_board if side == "player" else state.enemy_board
	if board == null:
		return
	# Snapshot the cascade targets first so effects that re-arrange the board
	# (kills, summons) don't perturb iteration.
	var to_fire: Array = []
	for raw in board:
		var m: MinionInstance = raw as MinionInstance
		if m == null or m.card_data == null:
			continue
		var card := m.card_data as MinionCardData
		if card == null or not (Enums.Keyword.FORMATION in card.keywords):
			continue
		if m.formation_fired:
			continue
		to_fire.append(m)
	# Slot-order: deterministic left-to-right pass.
	to_fire.sort_custom(func(a, b): return (a as MinionInstance).slot_index < (b as MinionInstance).slot_index)
	for raw in to_fire:
		var actor: MinionInstance = raw
		if actor.formation_fired:
			continue  # defensive — earlier cascade step might have already fired it
		var card := actor.card_data as MinionCardData
		actor.formation_fired = true
		if not card.formation_effect_steps.is_empty():
			var ectx := EffectContext.make(state, actor.owner)
			ectx.source = actor
			ectx.source_card_id = card.id
			EffectResolver.run(card.formation_effect_steps, ectx)
		if state.trigger_manager != null:
			var tctx := EventContext.make(Enums.TriggerEvent.ON_FORMATION_TRIGGERED, actor.owner)
			tctx.minion = actor
			# No partner in the cascade path — leave tctx.target null.
			state.trigger_manager.fire(tctx)
		state._refresh_slot_for(actor)

## Fires `actor`'s Formation if conditions are met. `partner` is the minion whose
## summon event triggered the check (used to short-circuit when partner clearly
## fails the race test); the actual gate requires same-race minions on BOTH the
## left AND the right adjacent slots of actor (task 037).
##   - actor has FORMATION keyword on its card data
##   - actor.formation_fired is false (one-shot consumption — task 036)
##   - actor and partner share at least one race (cheap early-out)
##   - actor has BOTH left (slot_index - 1) and right (slot_index + 1) neighbors
##     present on its own side, each sharing at least one race with actor
##     (task 037 — formation requires a sandwich, not just one partner)
## Edge-slot actors (slot 0 or last slot) can never fire Formation by normal
## adjacency because one side is structurally absent. Battle Drillmaster is the
## escape hatch — it bypasses the both-sides check.
## On success, sets actor.formation_fired = true (Formation consumed for life),
## runs formation_effect_steps with ctx.source = actor, fires ON_FORMATION_TRIGGERED.
func _try_fire_formation(actor: MinionInstance, partner: MinionInstance) -> void:
	if actor == null or partner == null:
		return
	var card: MinionCardData = actor.card_data as MinionCardData
	if card == null or not (Enums.Keyword.FORMATION in card.keywords):
		return
	if actor.formation_fired:
		return
	if not card.shares_race(partner.card_data as MinionCardData):
		return
	if not _formation_both_sides_satisfied(actor, card):
		return
	actor.formation_fired = true
	if not card.formation_effect_steps.is_empty():
		var ectx := EffectContext.make(state, actor.owner)
		ectx.source = actor
		ectx.source_card_id = card.id
		EffectResolver.run(card.formation_effect_steps, ectx)
	# Fire ON_FORMATION_TRIGGERED so talents like commanders_reach can react —
	# fires even when formation_effect_steps is empty so future "any FORMATION
	# trigger" effects don't depend on the step list being populated.
	if state.trigger_manager != null:
		var tctx := EventContext.make(Enums.TriggerEvent.ON_FORMATION_TRIGGERED, actor.owner)
		tctx.minion = actor
		tctx.target = partner
		state.trigger_manager.fire(tctx)
	# Refresh UI so the FORMATION chip disappears from the battlefield frame.
	state._refresh_slot_for(actor)

## Task 037 — Formation now requires same-race partners on BOTH adjacent sides
## (left slot_index - 1 AND right slot_index + 1). Each side is checked
## independently against actor's race set via shares_race, so a dual-tag actor
## like Runebound Initiate can have either tag satisfy each side independently
## (e.g. Human on the left and Demon on the right both pass for Initiate).
## Edge-slot actors (slot 0 or last slot) return false because one side is
## structurally absent.
func _formation_both_sides_satisfied(actor: MinionInstance, card: MinionCardData) -> bool:
	if actor == null or card == null:
		return false
	if actor.slot_index < 0:
		return false
	var slots: Array = state.player_slots if actor.owner == "player" else state.enemy_slots
	if slots == null:
		return false
	var left_idx: int = actor.slot_index - 1
	var right_idx: int = actor.slot_index + 1
	if left_idx < 0 or right_idx >= slots.size():
		return false
	var left_slot: SlotState = slots[left_idx]
	var right_slot: SlotState = slots[right_idx]
	if left_slot == null or right_slot == null:
		return false
	var left_minion: MinionInstance = left_slot.minion
	var right_minion: MinionInstance = right_slot.minion
	if left_minion == null or right_minion == null:
		return false
	if not card.shares_race(left_minion.card_data as MinionCardData):
		return false
	if not card.shares_race(right_minion.card_data as MinionCardData):
		return false
	return true

func _apply_board_passive_on_summon(passive_id: String, passive_owner: MinionInstance, summoned: MinionInstance) -> void:
	match passive_id:
		"void_amplifier_buff_demon":
			if (summoned.card_data as MinionCardData).is_race(Enums.MinionType.DEMON) and summoned != passive_owner:
				BuffSystem.apply(summoned, Enums.BuffType.ATK_BONUS, 100, "void_amplifier", false, false)
				summoned.current_health += 100
				state._refresh_slot_for(summoned)
				_log("  Void Amplifier: %s enters with +100 ATK / +100 HP." % summoned.card_data.card_name, _LOG_PLAYER)

# ---------------------------------------------------------------------------
# Declarative on-friendly-summon aura dispatcher
# ---------------------------------------------------------------------------

## Fires on ON_PLAYER_MINION_SUMMONED and ON_ENEMY_MINION_SUMMONED. Walks the side
## board of the summoned minion, finds every aura source whose MinionCardData has
## non-empty on_friendly_summon_aura_steps, and runs the steps once per source. The
## newly summoned minion is passed as ctx.trigger_minion so steps can target it via
## scope=TRIGGER_MINION. Self is always skipped (no self-buff on own entry). Sources
## stack — N aura sources on the side = N independent firings on each new summon.
##
## This is the generic equivalent of the bespoke on_summon_path_of_demons /
## on_summon_path_of_humans handlers; new on-summon aura cards drop in by declaring
## on_friendly_summon_aura_steps with no new handler required.
func on_minion_summoned_friendly_aura(ctx: EventContext) -> void:
	var summoned: MinionInstance = ctx.minion
	if summoned == null:
		return
	var board: Array = state._friendly_board(summoned.owner)
	if board == null:
		return
	for raw in board:
		var src: MinionInstance = raw as MinionInstance
		if src == null or src == summoned:
			continue
		var mc := src.card_data as MinionCardData
		if mc == null or mc.on_friendly_summon_aura_steps.is_empty():
			continue
		var ectx := EffectContext.make(state, src.owner)
		ectx.source         = src
		ectx.source_card_id = mc.id
		ectx.trigger_minion = summoned
		EffectResolver.run(mc.on_friendly_summon_aura_steps, ectx)

## Fires on ON_FORMATION_TRIGGERED. Walks the actor's side board, finds every minion
## with non-empty on_formation_triggered_aura_steps, and runs the steps once per source
## with ctx.trigger_minion = the actor (the minion whose Formation just fired). N
## listeners on the same side = N independent firings. Vanguard Marshal is the first
## consumer (draws a card per friendly Formation trigger).
func on_formation_triggered_card_auras(ctx: EventContext) -> void:
	var actor: MinionInstance = ctx.minion
	if actor == null:
		return
	var board: Array = state._friendly_board(actor.owner)
	if board == null:
		return
	for raw in board:
		var src: MinionInstance = raw as MinionInstance
		if src == null:
			continue
		var mc := src.card_data as MinionCardData
		if mc == null or mc.on_formation_triggered_aura_steps.is_empty():
			continue
		var ectx := EffectContext.make(state, src.owner)
		ectx.source         = src
		ectx.source_card_id = mc.id
		ectx.trigger_minion = actor
		EffectResolver.run(mc.on_formation_triggered_aura_steps, ectx)

# ---------------------------------------------------------------------------
# ON_RUNE_PLACED / ON_RITUAL_ENVIRONMENT_PLAYED
# ---------------------------------------------------------------------------

func on_player_minion_died_rune_warden(_ctx: EventContext) -> void:
	for m in state.player_board:
		if (m.card_data as MinionCardData).passive_effect_id == "rune_warden":
			BuffSystem.apply(m, Enums.BuffType.TEMP_ATK, 200, "rune_warden", false, false)
			_log("  Rune Warden: +200 ATK until end of turn.", _LOG_PLAYER)
			state._refresh_slot_for(m)

func on_grand_ritual(ritual: RitualData) -> void:
	var runes: Array = state.active_traps.filter(func(t: TrapCardData): return t.is_rune)
	if state._runes_satisfy(runes, ritual.required_runes):
		state._fire_ritual(ritual)

func on_env_ritual(ritual: RitualData) -> void:
	var runes: Array = state.active_traps.filter(func(t: TrapCardData): return t.is_rune)
	if state._runes_satisfy(runes, ritual.required_runes):
		state._fire_ritual(ritual)

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_DIED
# ---------------------------------------------------------------------------

func on_minion_died_death_effect(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	# Resolves inline on both shells (D3, plan 3.0): the presenter orders the
	# death animation + on-death icon before the effects' own visuals.
	_resolve_on_death(minion)


## Resolves a minion's on-death effects (steps + granted summons).
func _resolve_on_death(minion: MinionInstance) -> void:
	var card := minion.card_data as MinionCardData
	if not card.on_death_effect_steps.is_empty():
		var eff_ctx    := EffectContext.make(state, minion.owner)
		eff_ctx.source = minion
		EffectResolver.run(card.on_death_effect_steps, eff_ctx)
	# Runtime-granted on-death summon effects (e.g. Sovereign's Edict)
	for eff: Dictionary in minion.granted_on_death_effects:
		var summon_id: String = eff.get("summon_id", "")
		if not summon_id.is_empty():
			state._summon_token(summon_id, minion.owner, 0, 0)
			_log("  %s dies — summons a %s." % [minion.card_data.card_name, summon_id], _log_side(minion.owner))

## Shared handler — fires the killer's on_kill_effect_steps (declarative primitive on
## MinionCardData). Runs on both ON_ENEMY_MINION_DIED and ON_PLAYER_MINION_DIED; ctx.attacker
## is CombatState._last_attacker, set by CombatState._on_minion_vanished for every death
## during an attack. The attacker's owner drives ctx.owner so effects like GAIN_FLESH
## resolve to the correct side.
func on_minion_killed_on_kill_steps(ctx: EventContext) -> void:
	var attacker: MinionInstance = ctx.attacker
	if attacker == null or attacker.card_data == null:
		return
	if not (attacker.card_data is MinionCardData):
		return
	# Only an opposing minion's death is a kill: not the attacker's own death (the
	# counter) and not friendly deaths during its attack (task 059). Kill credit for
	# nested effects and counter-kills is task 129's.
	if ctx.minion == null or ctx.minion.owner == attacker.owner:
		return
	var steps: Array = (attacker.card_data as MinionCardData).on_kill_effect_steps
	if steps.is_empty():
		return
	var eff_ctx         := EffectContext.make(state, attacker.owner)
	eff_ctx.source      = attacker
	eff_ctx.source_card_id = attacker.card_data.id
	eff_ctx.dead_minion = ctx.minion
	EffectResolver.run(steps, eff_ctx)

## ON_PLAYER_MINION_SACRIFICED — board-wide passives that react to friendly sacrifices.
## Mirrors the death dispatcher's structure but listens specifically for sacrifice. The
## sacrificed minion has not yet been removed when this fires (per _sacrifice_minion order).
func on_player_minion_sacrificed_board_passives(ctx: EventContext) -> void:
	var sacd: MinionInstance = ctx.minion
	if sacd == null or not (sacd.card_data is MinionCardData):
		return
	if not (sacd.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
		# Currently only Forge Acolyte cares, and it cares about Demons. Add more
		# branches here if other passives need non-Demon sacrifice triggers.
		return
	for m in state.player_board.duplicate():
		var pid: String = (m.card_data as MinionCardData).passive_effect_id
		match pid:
			"forge_acolyte_flesh_on_sacrifice":
				state._gain_flesh(1)

func on_player_minion_died_board_passives(ctx: EventContext) -> void:
	var dead := ctx.minion
	for m in state.player_board.duplicate():
		var pid: String = (m.card_data as MinionCardData).passive_effect_id
		if pid != "":
			_apply_board_passive_on_death(pid, m, dead)

## Environment on_player_minion_died_steps — global / side-agnostic.
## The environment card has no owner-side: any active environment (player's or
## enemy's) fires its steps for deaths on either side. "friendly" in the card
## description is relative to the dying minion — so ctx.owner is set to the
## dying minion's owner, which makes DAMAGE_HERO target that side's opponent.
func on_minion_died_environment(ctx: EventContext) -> void:
	var dead_owner: String = ctx.minion.owner if ctx.minion != null else ""
	if dead_owner == "":
		return
	for entry in _active_environments():
		var env: EnvironmentCardData = entry["env"]
		if env.on_player_minion_died_steps.is_empty():
			continue
		var eff_ctx         := EffectContext.make(state, dead_owner)
		eff_ctx.dead_minion = ctx.minion
		EffectResolver.run(env.on_player_minion_died_steps, eff_ctx)

func _apply_board_passive_on_death(passive_id: String, passive_owner: MinionInstance, dead: MinionInstance) -> void:
	match passive_id:
		"void_spark_on_friendly_death":
			if (dead.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
				state._summon_void_spark()
		"deal_200_hero_on_friendly_death":
			_log("  Abyssal Tide: deal 200 damage to enemy hero.", _LOG_PLAYER)
			state.combat_manager.apply_hero_damage("enemy",
					CombatManager.make_damage_info(200, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "abyssal_tide"))
		"soul_taskmaster_gain_atk":
			if (dead.card_data as MinionCardData).is_race(Enums.MinionType.DEMON) and dead != passive_owner:
				BuffSystem.apply(passive_owner, Enums.BuffType.ATK_BONUS, 50, "soul_taskmaster_stack", false, false)
				state._refresh_slot_for(passive_owner)
				_log("  Soul Taskmaster: Demon died → gains +50 ATK.", _LOG_PLAYER)

## death_bolt retired — clan-wide on-death VOID_BOLT step lives on each Void Imp
## clan card via CardModRules step injection. See cards/data/CardModRules.gd
## "death_bolt" rule.

## Seris — Fleshbind passive. When a friendly Demon dies (by any cause — combat,
## sacrifice, enemy effect), gain 1 Flesh (scene-capped at player_flesh_max).
## Mirror: the ctx.owner check lets the handler stay symmetric — Seris's side
## gains Flesh regardless of whether she is the player or (future) enemy.
func on_minion_died_fleshbind(ctx: EventContext) -> void:
	if ctx.minion == null or not (ctx.minion.card_data is MinionCardData):
		return
	if not (ctx.minion.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
		return
	state._gain_flesh(1)

# ---------------------------------------------------------------------------
# Seris — Fleshcraft branch
# ---------------------------------------------------------------------------

## flesh_infusion T0 — "spend 1 Flesh → +200 ATK on Grafted Fiend played from hand"
## is declarative — see CardModRules.gd "flesh_infusion" rule. Only the kill-stack
## counter half (formerly grafted_constitution T1, merged into T0) lives below.

## flesh_infusion T0 (formerly grafted_constitution T1) — Grafted Fiend gains kill stacks
## when it kills an enemy minion. _add_kill_stacks routes through the unified helper so
## +100/+100 stat conversion and Predatory Surge's Siphon grant happen in one place.
func on_enemy_died_grafted_constitution(ctx: EventContext) -> void:
	var attacker: MinionInstance = ctx.attacker
	if attacker == null or not _has_tag(attacker, "grafted_fiend"):
		return
	state._add_kill_stacks(attacker, 1)

## grafting_ritual (T1) — When you play a Grafted Fiend, optionally transform a
## friendly Demon (ctx.target) into a fresh 300/300 Grafted Fiend. Resets stats,
## buffs, kill_stacks, corruption, state. Player may play without a target — the
## Fiend is still summoned normally. Transform preserves the target's slot.
func on_played_grafting_ritual(ctx: EventContext) -> void:
	if ctx.minion == null or not _has_tag(ctx.minion, "grafted_fiend"):
		return
	var target: MinionInstance = ctx.target as MinionInstance
	if target == null:
		return
	# Validate: must be a friendly Demon, must not be the just-played Fiend itself.
	if target == ctx.minion:
		return
	if target.owner != ctx.minion.owner:
		return
	var tc := target.card_data as MinionCardData
	if tc == null or not tc.is_race(Enums.MinionType.DEMON):
		return
	# Transform in place — swap card_data and reset runtime state.
	# _card_for so the transformed Fiend inherits any clan rules / overrides.
	var fiend_data: MinionCardData = state._card_for("player", "grafted_fiend") as MinionCardData
	if fiend_data == null:
		return
	target.card_data       = fiend_data
	target.current_atk     = fiend_data.atk
	target.current_health  = fiend_data.health
	target.current_shield  = fiend_data.shield_max
	target.buffs           = []
	target.kill_stacks     = 0
	target.aura_tags       = []
	target.granted_on_death_effects = []
	target.state           = Enums.MinionState.EXHAUSTED
	# Grafted Fiend's base keywords (none by default) — no DEATHLESS re-apply needed.
	_log("  Grafting Ritual: %s transformed into Grafted Fiend." % tc.card_name, _LOG_PLAYER)
	state._refresh_slot_for(target)

## predatory_surge T2 — Grafted Fiends enter with Swift. Declarative via CardModRules
## "predatory_surge" rule (append_keywords [SWIFT]). The "3 kill stacks → Siphon"
## half of the talent lives in on_enemy_died_grafted_constitution because it needs
## the non-declarative kill_stacks counter.

# ---------------------------------------------------------------------------
# Seris — Corruption Engine branch
# ---------------------------------------------------------------------------

## corrupt_detonation (T1) — whenever Corruption stacks are removed from a friendly
## Demon, deal 100 damage per stack to a random enemy (minions + hero mixed pool).
## Only friendly side: enemy corruption removal doesn't detonate on player.
func on_corruption_removed_detonation(ctx: EventContext) -> void:
	if ctx.minion == null or not (ctx.minion.card_data is MinionCardData):
		return
	if ctx.minion.owner != "player":
		return
	if not (ctx.minion.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
		return
	var stacks: int = ctx.damage
	if stacks <= 0:
		return
	var damage: int = 100 * stacks
	# Pick one target from the mixed pool: all alive enemy minions + enemy hero.
	# Each minion and the hero are one entry each (no weighting).
	var pool: Array = []
	for m: MinionInstance in state.enemy_board:
		if m.current_health > 0:
			pool.append(m)
	pool.append("enemy_hero")
	var pick: Variant = state.rng_pick(pool)
	_log("  Corrupt Detonation: %d damage to random enemy (%d stacks)." % [damage, stacks], _LOG_PLAYER)
	if pick is MinionInstance:
		var pick_info := CombatManager.make_damage_info(damage, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "corrupt_detonation")
		state._spell_dmg(pick, damage, pick_info)
	else:
		state.combat_manager.apply_hero_damage("enemy",
				CombatManager.make_damage_info(damage, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "corrupt_detonation"))

## corrupt_flesh (T0) — reset the 1-per-turn activated-ability flag at the start of
## the player's turn. The button starts targeting (CombatScene._seris_corrupt_activate);
## the apply is CombatState._seris_corrupt_apply.
func on_turn_start_corrupt_flesh_reset(_ctx: EventContext) -> void:
	state._seris_corrupt_reset_turn()

## void_resonance_seris (T3 capstone), half 1 — any enemy death grants 1 Flesh.
## Stacks with Fleshbind (friendly Demon death): a trade where a friendly Demon
## kills an enemy and dies in the process grants +2 Flesh total (per design Q5).
func on_enemy_died_void_resonance(_ctx: EventContext) -> void:
	state._gain_flesh(1)

# ---------------------------------------------------------------------------
# Seris — Demon Forge branch (aura effects)
# ---------------------------------------------------------------------------

## Abyssal Forge — end of player turn, apply Void Growth and Void Pulse auras to any
## minion on the player board that carries them. Flesh Bond (draw on flesh-spend) is
## driven by state._on_flesh_spent, not this handler. Iterates a snapshot so an aura
## whose effect kills its own carrier doesn't corrupt the loop.
func on_turn_end_forge_auras(_ctx: EventContext) -> void:
	var snapshot: Array = (state.player_board as Array).duplicate()
	for m: MinionInstance in snapshot:
		if m.aura_tags.is_empty():
			continue
		if "void_growth" in m.aura_tags:
			BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "void_growth", false, false)
			BuffSystem.apply_hp_gain(m, 100, "void_growth", true)
			_log("  Void Growth: %s +100/+100." % m.card_data.card_name, _LOG_PLAYER)
			state._refresh_slot_for(m)
		if "void_pulse" in m.aura_tags:
			_log("  Void Pulse: 100 damage to all enemy minions.", _LOG_PLAYER)
			for target: MinionInstance in (state.enemy_board as Array).duplicate():
				var t_info := CombatManager.make_damage_info(100, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE)
				state._spell_dmg(target, 100, t_info)

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_PLAYED
# ---------------------------------------------------------------------------

func on_player_minion_played_effect(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var mc := minion.card_data as MinionCardData
	# Shadow claw VFX for base & senior Void Imp only (runic/wizard have their own effects).
	# Base Void Imp skips claw when piercing_void is active (fires Void Bolt instead).
	var _show_claw: bool = (_card_has_tag(mc, "base_void_imp") and not state._has_talent("piercing_void")) or _card_has_tag(mc, "senior_void_imp")
	if _show_claw:
		_spawn_void_imp_claw_vfx(minion, "player")
	# Void Netter: the net VFX is a journal event; the 200 damage is the card's
	# on-play step below on both shells (live used to deal it at the VFX impact).
	if mc.id == "void_netter" and ctx.target is MinionInstance:
		state.emit_event(CombatEvent.Kind.VFX, "player", {name = "void_netter", source = minion, target = ctx.target})
	if not mc.on_play_effect_steps.is_empty():
		var ectx           := EffectContext.make(state, "player")
		ectx.source        = minion
		ectx.source_card_id = mc.id
		ectx.chosen_target = ctx.target
		EffectResolver.run(mc.on_play_effect_steps, ectx)

# ---------------------------------------------------------------------------
# ON_ENEMY_MINION_PLAYED
# ---------------------------------------------------------------------------

func on_enemy_minion_played_effect(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var mc := minion.card_data as MinionCardData
	var chosen = state.enemy_play_target
	state.enemy_play_target = null
	# Symmetric: shadow claw VFX for base & senior Void Imp only.
	if _card_has_tag(mc, "base_void_imp") or _card_has_tag(mc, "senior_void_imp"):
		_spawn_void_imp_claw_vfx(minion, "enemy")
	if mc.id == "void_netter" and chosen is MinionInstance:
		state.emit_event(CombatEvent.Kind.VFX, "enemy", {name = "void_netter", source = minion, target = chosen})
	if not mc.on_play_effect_steps.is_empty():
		var ectx                         := EffectContext.make(state, "enemy")
		ectx.source                      = minion
		ectx.source_card_id              = mc.id
		if chosen is MinionInstance:
			ectx.chosen_target = chosen
		else:
			ectx.chosen_object = chosen
		EffectResolver.run(mc.on_play_effect_steps, ectx)

## Generic presence aura recompute. Fires on any minion summon/death/sacrifice on either
## side. Walks both boards, finds every minion with non-empty presence_aura_steps, groups
## the steps by source_tag per side, strips the tag from every minion on that side, then
## re-runs the steps once per (side, source_tag) so multiplier_key="board_count" can scale
## the amount against the number of sources alive. Replaces the old bespoke
## _refresh_rogue_imp_elder_aura logic with a fully data-driven path that any minion can
## opt into via MinionCardData.presence_aura_steps.
func on_minion_event_presence_auras(ctx: EventContext) -> void:
	# When the event minion itself is leaving (death/sacrifice), it may already be off
	# the board. Capture the side it belonged to so we strip its source_tags below — the
	# board walk alone won't find it once it's gone, and lingering buffs would stick.
	var leaving_side: String = ""
	var leaving_minion: MinionInstance = ctx.minion if ctx != null else null
	if leaving_minion != null:
		match ctx.event_type:
			Enums.TriggerEvent.ON_PLAYER_MINION_DIED, Enums.TriggerEvent.ON_PLAYER_MINION_SACRIFICED:
				leaving_side = "player"
			Enums.TriggerEvent.ON_ENEMY_MINION_DIED, Enums.TriggerEvent.ON_ENEMY_MINION_SACRIFICED:
				leaving_side = "enemy"
	_refresh_presence_auras_for_side("player", leaving_minion if leaving_side == "player" else null)
	_refresh_presence_auras_for_side("enemy",  leaving_minion if leaving_side == "enemy"  else null)

func _refresh_presence_auras_for_side(side: String, leaving: MinionInstance) -> void:
	var board: Array[MinionInstance] = state._friendly_board(side)
	# (source_tag → steps) — first source on the side wins; multiple sources of the same
	# kind share the tag and the count multiplier, so re-running the same steps is a no-op.
	var groups: Dictionary = {}
	for src in board:
		var mc := src.card_data as MinionCardData
		if mc == null or mc.presence_aura_steps.is_empty():
			continue
		for step in mc.presence_aura_steps:
			var tag: String = _step_source_tag(step)
			if tag == "":
				continue  # presence auras require a source_tag for clean stripping
			if not groups.has(tag):
				groups[tag] = {"src": src, "steps": mc.presence_aura_steps}
	# Always include the leaving minion's own tags in the strip set, even though it's no
	# longer on the board — otherwise its lingering buffs would never get cleaned up.
	var strip_tags: Dictionary = {}
	for tag in groups.keys():
		strip_tags[tag] = true
	if leaving != null:
		var lm := leaving.card_data as MinionCardData
		if lm != null:
			for step in lm.presence_aura_steps:
				var tag: String = _step_source_tag(step)
				if tag != "":
					strip_tags[tag] = true
	# Snapshot pre-recompute stats so we can compute true per-minion deltas after
	# the silent strip+reapply. Aura recomputes fire on every summon/death/sacrifice;
	# in steady state (no new aura sources, no count change) the net delta is zero
	# and we want NO visible flicker — neither label nor VFX.
	var pre_atk: Dictionary = {}    # MinionInstance → int
	var pre_hp_cap: Dictionary = {} # MinionInstance → int (HP_BONUS sum)
	for m in board:
		pre_atk[m] = m.effective_atk()
		pre_hp_cap[m] = m.card_data.health + BuffSystem.sum_type(m, Enums.BuffType.HP_BONUS)
	# Silent strip+reapply: state mutates immediately, no buff_applied signal, no
	# queued BuffApplyVFX. EffectResolver routes BUFF_ATK/BUFF_HP through the
	# silent branch while state._silent_buff_apply is true.
	var prev_silent: bool = state._silent_buff_apply
	state._silent_buff_apply = true
	# Strip-then-apply (not interleaved) so cross-target counting stays consistent.
	for tag in strip_tags.keys():
		for m in board:
			BuffSystem.remove_source(m, tag)
	for tag in groups.keys():
		var entry: Dictionary = groups[tag]
		var ctx2 := EffectContext.make(state, side)
		ctx2.source         = entry["src"]
		ctx2.source_card_id = (entry["src"] as MinionInstance).card_data.id
		EffectResolver.run(entry["steps"], ctx2)
	state._silent_buff_apply = prev_silent
	# Compute deltas and spawn cosmetic BuffApplyVFX only for minions whose net
	# stats actually changed (e.g. a 2nd Elder just summoned → existing imps go
	# from +100 to +200, real +100 delta worth animating). Zero-delta minions
	# need no visual since state was silently restored to the same value.
	for m in board:
		var atk_delta: int = m.effective_atk() - int(pre_atk.get(m, 0))
		var post_hp_cap: int = m.card_data.health + BuffSystem.sum_type(m, Enums.BuffType.HP_BONUS)
		var hp_delta: int = post_hp_cap - int(pre_hp_cap.get(m, 0))
		state._refresh_slot_for(m)
		if atk_delta != 0 or hp_delta != 0:
			state.emit_event(CombatEvent.Kind.VFX, m.owner, {name = "presence_aura", minion = m, atk_delta = atk_delta, hp_delta = hp_delta})

## Extract source_tag from a step that may be either a Dictionary or an EffectStep.
func _step_source_tag(step) -> String:
	if step is Dictionary:
		return step.get("source_tag", "")
	if step is EffectStep:
		return (step as EffectStep).source_tag
	return ""

# ---------------------------------------------------------------------------
# Enemy encounter passive handlers
# ---------------------------------------------------------------------------

func on_board_changed_pack_instinct(ctx: EventContext) -> void:
	var feral_imps: Array[MinionInstance] = []
	for m in state.enemy_board:
		if state._minion_has_tag(m, "feral_imp"):
			feral_imps.append(m)
	# Snapshot old ATK so we can show a buff-gain VFX for each imp whose ATK goes up
	var pre_atk: Dictionary = {}  # MinionInstance → int
	for m in feral_imps:
		pre_atk[m] = m.effective_atk()
	for m in feral_imps:
		BuffSystem.remove_source(m, "pack_instinct")
		var others := feral_imps.size() - 1
		if others > 0:
			BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, others * 50, "pack_instinct", false, false)
		state._refresh_slot_for(m)
	# Visualize the pack link — only on SUMMONED events, tying the new imp to its neighbors.
	var is_summon: bool = ctx.event_type == Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	if is_summon \
			and feral_imps.size() >= 2 \
			and ctx.minion != null \
			and state._minion_has_tag(ctx.minion, "feral_imp"):
		state.emit_event(CombatEvent.Kind.VFX, "enemy", {name = "pack_chain", minion = ctx.minion})
	# ATK-increase popup on every imp that gained ATK this tick (only on summon —
	# death events should silently lose the buff without drawing attention).
	# The buff is ALREADY applied (game state uses new ATK immediately); the VFX
	# helper holds the visual ATK label at the OLD value and flips it in sync
	# with the chain animation.
	if is_summon:
		for m in feral_imps:
			var old_atk: int = int(pre_atk.get(m, m.effective_atk()))
			if m.effective_atk() > old_atk:
				state.emit_event(CombatEvent.Kind.VFX, "enemy", {name = "pack_instinct", minion = m, old_atk = old_atk})

## Human Imp Caller — shared Act 2 passive
## When a human is summoned: add a random feral imp to the enemy's hand.
func on_enemy_turn_reset_feral_reinforcement(_ctx: EventContext) -> void:
	state._imp_caller_fired = false

func on_enemy_summon_feral_reinforcement(ctx: EventContext) -> void:
	if state._imp_caller_fired:
		return
	var minion := ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	if not (minion.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN):
		return
	state._imp_caller_fired = true
	var feral_imps: Array[CardData] = []
	for id in CardDatabase.get_all_card_ids():
		var card: CardData = CardDatabase.get_card(id)
		if _card_has_tag(card, "feral_imp") and not (card is MinionCardData and (card as MinionCardData).is_champion):
			feral_imps.append(card)
	if feral_imps.is_empty():
		return
	var chosen: CardData = state.rng_pick(feral_imps)
	state.add_to_hand("enemy", chosen)
	state.emit_event(CombatEvent.Kind.VFX, "enemy", {name = "feral_reinforcement", source = minion, card = chosen})
	_log("  Feral Reinforcement: %s summoned → enemy draws %s." % [minion.card_data.card_name, chosen.card_name], _LOG_ENEMY)

## Corrupt Authority — encounter 3 (Abyss Cultist Patrol)
## When a human is summoned: apply 1 Corruption to a random player minion.
func on_enemy_summon_corrupt_authority_human(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not (minion.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN):
		return
	if state.player_board.is_empty():
		return
	var target: MinionInstance = state.rng_pick(state.player_board)
	state._corrupt_minion(target)
	_log("  Corrupt Authority: %s summoned → %s is Corrupted." % [minion.card_data.card_name, target.card_data.card_name], _LOG_ENEMY)

## When a feral imp is summoned: consume all Corruption on each player minion, deal 100 damage per stack.
func on_enemy_summon_corrupt_authority_imp(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not _has_tag(minion, "feral_imp"):
		return
	state._detonation_count += 1
	state._corruption_detonation_times += 1

	var targets: Array = []
	for m: MinionInstance in state.player_board.duplicate():
		var stacks := 0
		for b in m.buffs:
			if (b as BuffEntry).type == Enums.BuffType.CORRUPTION:
				stacks += 1
		if stacks > 0:
			targets.append({"minion": m, "stacks": stacks})
	if targets.is_empty():
		return

	# Each DETONATION event carries the VFX; the stacks are consumed and the
	# damage lands now (plan 3.0).
	for t in targets:
		var m: MinionInstance = t["minion"]
		var stacks: int = t["stacks"]
		state.emit_event(CombatEvent.Kind.DETONATION, "enemy", {minion = m, stacks = stacks, damage = 100 * stacks})
		BuffSystem.remove_type(m, Enums.BuffType.CORRUPTION)
		state._refresh_slot_for(m)
		# Route through _spell_dmg so the spell_damage_dealt signal fires and the
		# floating damage number / slot flash spawns. apply_damage_to_minion alone
		# applies the HP change but does NOT emit the popup signal.
		var info := CombatManager.make_damage_info(100 * stacks, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "corrupt_authority")
		state._spell_dmg(m, 100 * stacks, info)
		_log("  Corrupt Authority: %s had %d stack(s) → consumed, dealt %d damage." % [m.card_data.card_name, stacks, 100 * stacks], _LOG_ENEMY)
		# Track consumed stacks toward Abyss Cultist Patrol champion
		on_champion_acp_track_stacks(stacks)

## Ritual Sacrifice — encounter 5 (Void Ritualist)
## When a feral imp is summoned and enemy has Blood Rune + Dominion Rune active:
## consume both runes + the feral imp, deal 200 damage to 2 random player targets,
## Special Summon a 500/500 Demon on the enemy board.
##
## Resolves inline on both shells (plan 3.0); live then plays the SacrificeVFX →
## rune-shine-and-merge → projectiles + beam sequence as presentation.
func on_enemy_summon_ritual_sacrifice(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not _has_tag(minion, "feral_imp"):
		return
	var enemy_traps: Array[TrapCardData] = state.enemy_active_traps
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

	# Snapshot trap refs + panels BEFORE state mutation so the VFX can locate
	# them. The runes will be removed inside the on_state_change callback below.
	var blood_trap: TrapCardData    = enemy_traps[blood_idx] as TrapCardData
	var dominion_trap: TrapCardData = enemy_traps[dominion_idx] as TrapCardData

	# Pre-pick up to 2 DISTINCT random player minions so live and sim apply
	# the same damage to the same minions (random rolls happen once, here,
	# before any VFX gate). Demon Ascendant spec: minions only — if the board
	# has fewer than 2 minions, fewer projectiles fire (no hero fallback,
	# matches the player-side ritual).
	var damage_pool: Array = (state.player_board as Array).duplicate()
	state.rng_shuffle(damage_pool)
	var damage_targets: Array = []
	var damage_picks: int = mini(2, damage_pool.size())
	for i in damage_picks:
		damage_targets.append({"kind": "minion", "minion": damage_pool[i]})

	# Everything mutates inline (plan 3.0); the presenter then plays the
	# sacrifice → rune merge → projectiles → beam sequence as presentation.
	var imp := minion
	SacrificeSystem.emit(imp, "ritual_sacrifice")  # VFX bus: snapshot the imp's slot before the kill
	state.combat_manager.kill_minion(imp)
	state._ritual_sacrifice_count += 1
	state._ritual_invoke_times += 1
	_log("  Ritual Sacrifice: runes consumed + %s sacrificed — Demon Ascendant!" % minion.card_data.card_name, _LOG_ENEMY)
	# Remove the runes — unregister auras then erase (higher index first so the
	# lower index stays valid). Re-index by reference: other handlers may have
	# changed enemy_traps since the snapshot above.
	var live_traps: Array[TrapCardData] = state.enemy_active_traps
	var b_idx: int = live_traps.find(blood_trap)
	var d_idx: int = live_traps.find(dominion_trap)
	if b_idx != -1 and d_idx != -1:
		var hi: int = maxi(b_idx, d_idx)
		var lo: int = mini(b_idx, d_idx)
		state._remove_rune_aura(live_traps[hi] as TrapCardData, "enemy")
		state._remove_rune_aura(live_traps[lo] as TrapCardData, "enemy")
		live_traps.remove_at(hi)
		live_traps.remove_at(lo)
		state._update_enemy_trap_display()
	for t in damage_targets:
		var info := CombatManager.make_damage_info(200, Enums.DamageSource.SPELL,
				Enums.DamageSchool.NONE, null, "ritual_sacrifice")
		var kind: String = t.get("kind", "") as String
		if kind == "hero":
			state.combat_manager.apply_hero_damage("player", info)
		elif kind == "minion":
			var m: MinionInstance = t.get("minion") as MinionInstance
			if m != null and is_instance_valid(m):
				state.combat_manager.apply_damage_to_minion(m, info)
	# Special Summon a 500/500 Demon
	var demon: MinionInstance = state._summon_token("void_demon", "enemy", 500, 500)
	# Trigger Void Ritualist champion on first ritual
	on_ritual_sacrifice_champion_vr()
	state.emit_event(CombatEvent.Kind.VFX, "enemy", {name = "ritual_sacrifice", imp = imp, blood_trap = blood_trap,
			dominion_trap = dominion_trap, blood_idx = blood_idx, dominion_idx = dominion_idx,
			targets = damage_targets, damage = 200, demon = demon})

## Void Unraveling — encounter 6 (Corrupted Handler)
## When a human is summoned: summon a 100/100 Void Spark on the enemy board.
func on_enemy_summon_void_unraveling_human(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	if not (minion.card_data as MinionCardData).is_race(Enums.MinionType.HUMAN):
		return
	state._spark_spawned_count += 1
	state._summon_token("void_spark", "enemy", 100, 100)
	_log("  Void Unraveling: %s summoned → a Void Spark arises!" % minion.card_data.card_name, _LOG_ENEMY)

## When a feral imp is summoned: consume 1 friendly Void Spark, grant +100/+100 to the imp.
func on_enemy_summon_void_unraveling_imp(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not _has_tag(minion, "feral_imp"):
		return
	# Find a friendly void spark to consume
	for m: MinionInstance in state.enemy_board.duplicate():
		if m.card_data.id == "void_spark":
			state.combat_manager.kill_minion(m)
			minion.current_atk += 100
			minion.current_health += 100
			state._refresh_slot_for(minion)
			_log("  Void Unraveling: feral imp consumed a Void Spark → +100/+100!" , _LOG_ENEMY)
			return

## At end of enemy turn: corrupt 1 random friendly spark and transfer it to player board.
func on_enemy_turn_end_void_unraveling(_ctx: EventContext) -> void:
	var sparks: Array[MinionInstance] = []
	for m: MinionInstance in state.enemy_board:
		if m.card_data.id == "void_spark":
			sparks.append(m)
	if sparks.is_empty():
		return
	# Pick one random spark, corrupt it, transfer it
	var spark: MinionInstance = state.rng_pick(sparks)
	if not BuffSystem.has_type(spark, Enums.BuffType.CORRUPTION):
		state._corrupt_minion(spark)
	state._spark_transfer_count += 1
	if not _transfer_to_player_board(spark):
		state.combat_manager.kill_minion(spark)
		_log("  Void Unraveling: player board full — Void Spark destroyed.", _LOG_ENEMY)
	else:
		_log("  Void Unraveling: corrupted Void Spark transferred to player board!", _LOG_ENEMY)

## Move a minion from the enemy board to an empty player board slot without firing death/summon events.
## Returns false if the player board has no empty slot.
func _transfer_to_player_board(m: MinionInstance) -> bool:
	var target_slot: SlotState = null
	for s: SlotState in state.player_slots:
		if s.is_empty():
			target_slot = s
			break
	if target_slot == null:
		return false
	var from_slot: SlotState = state.slot_for(m)
	if from_slot != null:
		from_slot.clear()
	state.enemy_board.erase(m)
	m.owner = "player"
	state.player_board.append(m)
	state.emit_event(CombatEvent.Kind.MINION_SUMMONED, "player", {minion = m, slot = target_slot.index}.merged(CombatState.minion_stat_payload(m)))
	target_slot.place(m)
	state.minion_summoned.emit("player", m, target_slot.index)
	state._refresh_slot_for(m)
	return true

# ---------------------------------------------------------------------------
# Act 3 — Void Rift World passive handlers
# ---------------------------------------------------------------------------

## Void Rift (shared Act 3): summon a 100/100 Void Spark on the enemy board at turn start.
## Suppressed when Void Herald champion is alive (aura: no more spark generation).
func on_enemy_turn_void_rift(_ctx: EventContext) -> void:
	if _champion_vh_is_alive():
		return  # Void Herald aura suppresses spark generation
	state._summon_token("void_spark", "enemy", 100, 100)
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
	state._refresh_slot_for(minion)
	_log("  Void Empowerment: Void Spark empowered to 200/200.", _LOG_ENEMY)

## Void Detonation: fires on spark consumed.
## Deals 100 damage (200 if Void Aberration champion alive) per spark_value consumed
## to all opponent minions AND opponent hero.
## Symmetric — works for both player and enemy spark consumption.
func on_spark_consumed_void_detonation(ctx: EventContext) -> void:
	var spark_val: int = ctx.damage if ctx.damage > 0 else 1
	var opponent: String = state._opponent_of(ctx.owner)
	var opponent_board: Array[MinionInstance] = state._opponent_board(ctx.owner)
	var side: int = _log_side(ctx.owner)
	var dmg_per_spark: int = 200 if _champion_va_is_alive() else 100
	for i in spark_val:
		for m: MinionInstance in opponent_board.duplicate():
			state.combat_manager.apply_damage_to_minion(m,
					CombatManager.make_damage_info(dmg_per_spark, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "void_detonation"))
		state.combat_manager.apply_hero_damage(opponent,
				CombatManager.make_damage_info(dmg_per_spark, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "void_detonation"))
		_log("  Void Detonation: spark consumed — %d damage to all %s minions and hero!" % [dmg_per_spark, opponent], side)

## Hollow Sentinel: at end of owner's turn, +100 ATK permanently to all friendly Void Sparks.
## Works for both player and enemy boards (symmetric).
func on_turn_end_hollow_sentinel(ctx: EventContext) -> void:
	var owner: String = ctx.owner
	# Determine which boards to scan based on trigger event
	var boards: Array = []
	if ctx.event_type == Enums.TriggerEvent.ON_ENEMY_TURN_END:
		boards.append({"board": state.enemy_board, "owner": "enemy"})
	elif ctx.event_type == Enums.TriggerEvent.ON_PLAYER_TURN_END:
		boards.append({"board": state.player_board, "owner": "player"})
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
				BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "hollow_sentinel", false, false)
				state._refresh_slot_for(m)
				buffed += 1
		if buffed > 0:
			state._hollow_sentinel_buffs += 1
			var side: int = _log_side(entry.owner)
			_log("  Hollow Sentinel: %d Void Sparks gain +100 ATK." % buffed, side)

## ── Champion: Rift Stalker ─────────────────────────────────────────────────
## Summon condition: Void Sparks have dealt 1500 cumulative damage.
## Aura: All friendly Void Sparks are immune.
## On death: deal 20% of enemy hero max HP to enemy hero.

const _RS_THRESHOLD := 1000
const _RS_PIPS := 5  # 1000 / 5 = 200 per pip

func on_enemy_attack_champion_rs(ctx: EventContext) -> void:
	if state._champion_rs_summoned:
		return
	var minion := ctx.minion
	if minion == null or minion.card_data.id != "void_spark":
		return
	var dmg: int = minion.effective_atk()
	state._champion_rs_spark_dmg += dmg
	var total: int = state._champion_rs_spark_dmg
	var pips: int = mini(total / (_RS_THRESHOLD / _RS_PIPS), _RS_PIPS)
	_show_champion_progress(pips, _RS_PIPS)
	_log("  Champion progress: %d / %d spark damage." % [mini(total, _RS_THRESHOLD), _RS_THRESHOLD], _LOG_ENEMY)
	if total >= _RS_THRESHOLD:
		_summon_enemy_champion("champion_rift_stalker")
		_refresh_champion_rs_immune()

func on_enemy_summon_champion_rs_immune(ctx: EventContext) -> void:
	if not state._champion_rs_summoned:
		return
	var minion := ctx.minion
	if minion == null or minion.card_data.id != "void_spark":
		return
	# Grant immune to newly summoned void sparks while champion is alive
	if _champion_rs_is_alive():
		BuffSystem.apply(minion, Enums.BuffType.GRANT_IMMUNE, 1, "champion_rs_immune", false, false)
		state._refresh_slot_for(minion)

func on_enemy_died_champion_rs(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_rift_stalker":
		# Champion killed — remove immune from all sparks
		for m: MinionInstance in state.enemy_board:
			if m.card_data.id == "void_spark":
				BuffSystem.remove_source(m, "champion_rs_immune")
				state._refresh_slot_for(m)
		_on_enemy_champion_killed()

func _refresh_champion_rs_immune() -> void:
	if not _champion_rs_is_alive():
		return
	for m: MinionInstance in state.enemy_board:
		if m.card_data.id == "void_spark" and not BuffSystem.has_type(m, Enums.BuffType.GRANT_IMMUNE):
			BuffSystem.apply(m, Enums.BuffType.GRANT_IMMUNE, 1, "champion_rs_immune", false, false)
			state._refresh_slot_for(m)

func _champion_rs_is_alive() -> bool:
	for m: MinionInstance in state.enemy_board:
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
	if state._champion_va_summoned:
		return
	var spark_val: int = ctx.damage if ctx.damage > 0 else 1
	state._champion_va_sparks_consumed += spark_val
	var total: int = state._champion_va_sparks_consumed
	var pips: int = mini(total, _VA_PIPS)
	_show_champion_progress(pips, _VA_PIPS)
	var side: int = _log_side(ctx.owner)
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
	for m: MinionInstance in state.enemy_board:
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
	if state._champion_vh_summoned:
		return
	# Check if the card that triggered this event had a spark cost
	var card: CardData = ctx.card
	if card == null or card.void_spark_cost <= 0:
		return
	state._champion_vh_spark_cards_played += 1
	var total: int = state._champion_vh_spark_cards_played
	var pips: int = mini(total, _VH_PIPS)
	_show_champion_progress(pips, _VH_PIPS)
	var side: int = _log_side(ctx.owner)
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
	for m: MinionInstance in state.enemy_board:
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
	if state._champion_vs_summoned:
		return
	var total: int = state._enemy_crits_consumed if state._enemy_crits_consumed != null else 0
	if total <= 0:
		return
	var pips: int = mini(total, _VS_PIPS)
	_show_champion_progress(pips, _VS_PIPS)
	if total >= _VS_THRESHOLD and not state._champion_vs_summoned:
		_log("  Champion progress: %d / %d crits consumed." % [_VS_THRESHOLD, _VS_THRESHOLD], _LOG_ENEMY)
		_summon_enemy_champion("champion_void_scout")
		# Grant 1 Critical Strike on summon
		for m: MinionInstance in state.enemy_board:
			if m.card_data.id == "champion_void_scout":
				BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike", false, false)
				state._refresh_slot_for(m)
				break
		# Set enemy crit multiplier to 2.5
		state.enemy_crit_multiplier = 2.5

func on_enemy_died_champion_vs(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_void_scout":
		# Revert crit multiplier
		state.enemy_crit_multiplier = 0.0
		_on_enemy_champion_killed()

func _champion_vs_is_alive() -> bool:
	for m: MinionInstance in state.enemy_board:
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
	if not (minion.card_data as MinionCardData).is_race(Enums.MinionType.SPIRIT):
		return
	if not minion.has_critical_strike():
		return
	state._summon_token("void_spark", "enemy", 100, 100)
	_log("  Spirit Resonance: crit-Spirit consumed — a Void Spark manifests!", _LOG_ENEMY)

func on_spark_consumed_champion_vw(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null:
		return
	if not (minion.card_data as MinionCardData).is_race(Enums.MinionType.SPIRIT):
		return
	# Champion already summoned — no further tracking needed
	if state._champion_vw_summoned:
		return
	state._champion_vw_spirits_consumed += 1
	var total: int = state._champion_vw_spirits_consumed
	var pips: int = mini(total, _VW_PIPS)
	_show_champion_progress(pips, _VW_PIPS)
	_log("  Champion progress: %d / %d Spirits consumed." % [mini(total, _VW_THRESHOLD), _VW_THRESHOLD], _LOG_ENEMY)
	if total >= _VW_THRESHOLD:
		_summon_enemy_champion("champion_void_warband")
		# Grant 1 Critical Strike on summon
		for m: MinionInstance in state.enemy_board:
			if m.card_data.id == "champion_void_warband":
				BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike", false, false)
				state._refresh_slot_for(m)
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
	if not (minion.card_data as MinionCardData).is_race(Enums.MinionType.SPIRIT):
		return
	var candidates: Array[MinionInstance] = []
	for m: MinionInstance in state.enemy_board:
		if m == minion:
			continue
		candidates.append(m)
	if candidates.is_empty():
		return
	var target: MinionInstance = state.rng_pick(candidates)
	BuffSystem.apply(target, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike", false, false)
	state._refresh_slot_for(target)
	if state._vw_death_crit_grants != null:
		state._vw_death_crit_grants += 1
	_log("  Void Warband aura: %s's death grants Critical Strike to %s." % [minion.card_data.card_name, target.card_data.card_name], _LOG_ENEMY)

func _champion_vw_is_alive() -> bool:
	for m: MinionInstance in state.enemy_board:
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
	if state._champion_vc_summoned:
		return
	var card: CardData = ctx.card
	if card == null or card.id != "thrones_command":
		return
	state._champion_vc_tc_cast += 1
	var total: int = state._champion_vc_tc_cast
	var pips: int = mini(total, _VC_PIPS)
	_show_champion_progress(pips, _VC_PIPS)
	_log("  Champion progress: %d / %d Throne's Command cast." % [mini(total, _VC_THRESHOLD), _VC_THRESHOLD], _LOG_ENEMY)
	if total >= _VC_THRESHOLD:
		_summon_enemy_champion("champion_void_captain")
		# Grant 2 Critical Strike on summon
		for m: MinionInstance in state.enemy_board:
			if m.card_data.id == "champion_void_captain":
				BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, 2, "critical_strike", false, false)
				state._refresh_slot_for(m)
				break

func on_enemy_died_champion_vc(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_void_captain":
		_on_enemy_champion_killed()

func _champion_vc_is_alive() -> bool:
	for m: MinionInstance in state.enemy_board:
		if m.card_data.id == "champion_void_captain":
			return true
	return false

# ---------------------------------------------------------------------------
# Fight 13 — Void Ritualist Prime champion
#
# Summon: after 5 enemy spells cast.
# On summon: gains 2 Critical Strike.
# Aura: friendly spells cost 1 less Mana (applied via spell_cost_aura = -1,
#       cleared when the champion dies).
# ---------------------------------------------------------------------------

const _VRP_THRESHOLD := 5
const _VRP_PIPS := 5

func on_enemy_spell_champion_vrp(_ctx: EventContext) -> void:
	if state._champion_vrp_summoned:
		return
	state._champion_vrp_spells_cast += 1
	var total: int = state._champion_vrp_spells_cast
	var pips: int = mini(total, _VRP_PIPS)
	_show_champion_progress(pips, _VRP_PIPS)
	_log("  Champion progress: %d / %d spells cast." % [mini(total, _VRP_THRESHOLD), _VRP_THRESHOLD], _LOG_ENEMY)
	if total >= _VRP_THRESHOLD:
		_summon_enemy_champion("champion_void_ritualist_prime")
		# Grant 2 Critical Strike on summon and activate aura
		for m: MinionInstance in state.enemy_board:
			if m.card_data.id == "champion_void_ritualist_prime":
				BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, 2, "critical_strike", false, false)
				state._refresh_slot_for(m)
				break
		state.enemy_spell_cost_aura = -1
		_log("  Void Ritualist Prime's aura: enemy spells cost 1 less Mana.", _LOG_ENEMY)

func on_enemy_died_champion_vrp(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_void_ritualist_prime":
		state.enemy_spell_cost_aura = 0
		_on_enemy_champion_killed()

## ── Champion: Void Champion (F14) ─────────────────────────────────────────
## Summon condition: 3 player minions killed by an enemy Critical Strike attack.
## On summon: gains 3 Critical Strike.

const _VCH_THRESHOLD := 3
const _VCH_PIPS := 3

func on_player_died_champion_vch(ctx: EventContext) -> void:
	if state._champion_vch_summoned:
		return
	# Only count kills by an enemy attacker that consumed a crit on the killing hit.
	var attacker: MinionInstance = ctx.attacker
	if attacker == null or attacker.owner != "enemy":
		return
	if not state._last_attack_was_crit:
		return
	state._champion_vch_crit_kills += 1
	var total: int = state._champion_vch_crit_kills
	var pips: int = mini(total, _VCH_PIPS)
	_show_champion_progress(pips, _VCH_PIPS)
	_log("  Champion progress: %d / %d crit kills." % [mini(total, _VCH_THRESHOLD), _VCH_THRESHOLD], _LOG_ENEMY)
	if total >= _VCH_THRESHOLD:
		_summon_enemy_champion("champion_void_champion")
		for m: MinionInstance in state.enemy_board:
			if m.card_data.id == "champion_void_champion":
				BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, 3, "critical_strike", false, false)
				state._refresh_slot_for(m)
				break

func on_enemy_died_champion_vch(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_void_champion":
		_on_enemy_champion_killed()

## Aura: while Void Champion is alive, at end of enemy turn gain +1 max Mana and +1 max Essence.
func on_enemy_turn_end_champion_vch_aura(_ctx: EventContext) -> void:
	if not state._champion_vch_summoned:
		return
	var alive := false
	for m: MinionInstance in state.enemy_board:
		if m.card_data.id == "champion_void_champion":
			alive = true
			break
	if not alive:
		return
	state.grow_mana_max("enemy", 1)
	state.grow_essence_max("enemy", 1)
	_log("  Void Champion aura: enemy gains +1 max Mana and +1 max Essence.", _LOG_ENEMY)

# ---------------------------------------------------------------------------
# Act 4 — Void Castle passive handlers
# ---------------------------------------------------------------------------

## void_might (shared Act 4): at enemy turn start, grant 1 random friendly
## minion +1 stack of CRITICAL_STRIKE.
func on_enemy_turn_void_might(_ctx: EventContext) -> void:
	if state.enemy_board.is_empty():
		return
	var target: MinionInstance = state.rng_pick(state.enemy_board)
	BuffSystem.apply(target, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike", false, false)
	state._refresh_slot_for(target)
	_log("  Void Might: %s gains Critical Strike." % target.card_data.card_name, _LOG_ENEMY)

## abyss_awakened (Abyss Sovereign Phase 2): at enemy turn start, grant ALL
## friendly minions +1 stack of CRITICAL_STRIKE. While the Avatar of the Abyss
## champion is alive, the grant is doubled to 2 stacks.
func on_enemy_turn_abyss_awakened(_ctx: EventContext) -> void:
	var stacks: int = 2 if _champion_as_is_alive() else 1
	for m: MinionInstance in state.enemy_board:
		BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, stacks, "critical_strike", false, false)
		state._refresh_slot_for(m)
	if not state.enemy_board.is_empty():
		if stacks == 2:
			_log("  Abyss Awakened (empowered): all enemy minions gain 2 Critical Strike.", _LOG_ENEMY)
		else:
			_log("  Abyss Awakened: all enemy minions gain Critical Strike.", _LOG_ENEMY)

## ── Champion: Avatar of the Abyss (F15 Phase 2) ───────────────────────────
## Summon condition: player has played 12 cards (minions + spells, total fight).
## On summon: gains 2 Critical Strike.
## Aura: while alive, abyss_awakened grants 2 stacks of Critical Strike instead
## of 1 (handled inside on_enemy_turn_abyss_awakened).

const _AS_THRESHOLD := 12
const _AS_PIPS := 12

func on_player_card_champion_as(_ctx: EventContext) -> void:
	if state._champion_as_summoned:
		return
	state._champion_as_cards_played += 1
	var total: int = state._champion_as_cards_played
	var pips: int = mini(total, _AS_PIPS)
	_show_champion_progress(pips, _AS_PIPS)
	_log("  Champion progress: %d / %d cards played." % [mini(total, _AS_THRESHOLD), _AS_THRESHOLD], _LOG_ENEMY)
	# Gate the summon on Phase 2 so the avatar can never appear during P1, even
	# if the player burns through 12 cards before the Sovereign's HP drops.
	if total >= _AS_THRESHOLD and state._sovereign_phase == 2:
		_summon_enemy_champion("champion_abyss_sovereign")
		# Grant 2 Critical Strike on summon.
		for m: MinionInstance in state.enemy_board:
			if m.card_data.id == "champion_abyss_sovereign":
				BuffSystem.apply(m, Enums.BuffType.CRITICAL_STRIKE, 2, "critical_strike", false, false)
				state._refresh_slot_for(m)
				break

func on_enemy_died_champion_as(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_abyss_sovereign":
		_on_enemy_champion_killed()

func _champion_as_is_alive() -> bool:
	for m in state.enemy_board:
		if (m as MinionInstance).card_data.id == "champion_abyss_sovereign":
			return true
	return false

## abyssal_mandate (Abyss Sovereign Phase 1): the player's resource growth choice
## from the previous turn grants a matching discount to the Sovereign this turn.
##   - last_player_growth == "essence" → enemy minions cost -2 Essence this turn
##   - last_player_growth == "mana"    → enemy spells cost -2 Mana this turn
## The discount is cleared at ON_ENEMY_TURN_END so it lasts exactly one enemy turn.
const _ABYSSAL_MANDATE_AMOUNT: int = 2

func on_enemy_turn_start_abyssal_mandate(_ctx: EventContext) -> void:
	var choice: String = state.last_player_growth as String
	if choice == "essence":
		state.enemy_minion_essence_cost_aura = -_ABYSSAL_MANDATE_AMOUNT
		_log("  Abyssal Mandate: enemy minions cost %d less Essence this turn." % _ABYSSAL_MANDATE_AMOUNT, _LOG_ENEMY)
	elif choice == "mana":
		state.enemy_spell_cost_aura = -_ABYSSAL_MANDATE_AMOUNT
		_log("  Abyssal Mandate: enemy spells cost %d less Mana this turn." % _ABYSSAL_MANDATE_AMOUNT, _LOG_ENEMY)
	# No growth yet (turn 1, or player never grew) → no discount.

func on_enemy_turn_end_abyssal_mandate(_ctx: EventContext) -> void:
	if state.enemy_minion_essence_cost_aura < 0:
		state.enemy_minion_essence_cost_aura = 0
	if state.enemy_spell_cost_aura < 0:
		state.enemy_spell_cost_aura = 0

## void_precision (Fight 10 — Void Scout): after an enemy minion deals crit
## damage (attack resolves), grant it +200 ATK permanently.
## Listens to ON_ENEMY_ATTACK — we check after the attack if a crit was consumed.
## Implementation: tracks pre-attack crit count via a state field, compares after.
func on_enemy_attack_void_precision_pre(ctx: EventContext) -> void:
	var attacker: MinionInstance = ctx.minion
	if attacker == null or attacker.owner != "enemy":
		return
	state._vp_pre_crit_stacks = attacker.critical_strike_stacks()

func on_enemy_attack_void_precision_post(ctx: EventContext) -> void:
	var attacker: MinionInstance = ctx.minion
	if attacker == null or attacker.owner != "enemy":
		return
	if attacker.current_health <= 0:
		return
	var raw = state._vp_pre_crit_stacks
	var pre_stacks: int = raw if raw != null else 0
	if pre_stacks > attacker.critical_strike_stacks():
		BuffSystem.apply(attacker, Enums.BuffType.ATK_BONUS, 200, "void_precision", false, false)
		state._refresh_slot_for(attacker)
		_log("  Void Precision: %s gains +200 ATK from critical strike." % attacker.card_data.card_name, _LOG_ENEMY)

## captain_orders (Fight 12 — Void Captain):
##   1. Throne's Command costs 1 less spark (handled in CombatState.spark_cost_of)
##   2. At end of enemy turn, consume 1 crit from each friendly minion and deal
##      that minion's ATK as damage to enemy hero.
func on_enemy_turn_end_captain_orders(_ctx: EventContext) -> void:
	for m: MinionInstance in state.enemy_board:
		if not BuffSystem.has_type(m, Enums.BuffType.CRITICAL_STRIKE):
			continue
		BuffSystem.remove_one_source(m, "critical_strike")
		var dmg: int = m.effective_atk()
		if dmg > 0:
			state.combat_manager.apply_hero_damage("player",
					CombatManager.make_damage_info(dmg, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, m, "captains_orders"))
			_log("  Captain's Orders: %s's crit consumed — %d damage to enemy hero." % [m.card_data.card_name, dmg], _LOG_ENEMY)
		state._refresh_slot_for(m)
		# Track for crit counter
		state._enemy_crits_consumed += 1

## dark_channeling (Fight 13 — Void Ritualist Prime): when enemy casts a
## damage-dealing spell, consume 1 crit stack from a random friendly minion.
## If consumed, spell deals 1.5x damage. Listens to ON_ENEMY_SPELL_CAST.
func on_enemy_spell_dark_channeling(ctx: EventContext) -> void:
	if state.enemy_board.is_empty():
		return
	# Only trigger on damage-dealing spells (utility like void_pulse should not consume crits)
	var spell := ctx.card as SpellCardData if ctx.card is SpellCardData else null
	if spell == null or not _spell_deals_damage(spell):
		return
	# Find a minion with crit stacks
	var candidates: Array[MinionInstance] = []
	for m: MinionInstance in state.enemy_board:
		if m.has_critical_strike():
			candidates.append(m)
	if candidates.is_empty():
		return
	var donor: MinionInstance = state.rng_pick(candidates)
	BuffSystem.remove_one_source(donor, "critical_strike")
	state._refresh_slot_for(donor)
	state._dark_channeling_active = true
	state._dark_channeling_multiplier = 1.5
	var amp_count: int = state._dark_channeling_amp_count + 1
	state._dark_channeling_amp_count = amp_count
	var by_spell: Dictionary = state._dark_channeling_amp_by_spell
	by_spell[spell.id] = int(by_spell.get(spell.id, 0)) + 1
	_log("  Dark Channeling: %s channels crit energy into the spell (1.5x)." % donor.card_data.card_name, _LOG_ENEMY)

## Returns true if the spell has any DAMAGE_HERO or DAMAGE_MINION effect step.
## Used by dark_channeling so utility spells (draw, buff, etc.) don't consume crits.
func _spell_deals_damage(spell: SpellCardData) -> bool:
	for step in spell.effect_steps:
		if step is Dictionary:
			var t: String = step.get("type", "")
			if t == "DAMAGE_HERO" or t == "DAMAGE_MINION":
				return true
		elif step is EffectStep:
			var et = (step as EffectStep).effect_type
			if et == EffectStep.EffectType.DAMAGE_HERO or et == EffectStep.EffectType.DAMAGE_MINION:
				return true
	return false

# ---------------------------------------------------------------------------
# Enemy champion passives (Act 1)
# ---------------------------------------------------------------------------

## ── Champion: Rogue Imp Pack ────────────────────────────────────────────────
## Summon condition: 4 different rabid imps have attacked.
## Aura: all friendly feral imps gain +100 ATK.
## On death: deal 20% of enemy hero max HP to enemy hero.

func on_enemy_attack_champion_rip(ctx: EventContext) -> void:
	if state._champion_rip_summoned:
		return
	var minion := ctx.minion
	if minion == null or minion.card_data.id != "rabid_imp":
		return
	var uid: int = minion.get_instance_id()
	if uid in state._champion_rip_attack_ids:
		return
	state._champion_rip_attack_ids.append(uid)
	var count: int = state._champion_rip_attack_ids.size()
	_show_champion_progress(count, 4)
	_log("  Champion progress: %d / 4 rabid imp attacks." % count, _LOG_ENEMY)
	if count >= 4:
		_summon_enemy_champion("champion_rogue_imp_pack")

func on_enemy_summon_champion_rip_aura(ctx: EventContext) -> void:
	if not state._champion_rip_summoned:
		return
	_refresh_champion_rip_aura()

func on_enemy_died_champion_rip(ctx: EventContext) -> void:
	if not state._champion_rip_summoned:
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
	for m in state.enemy_board:
		BuffSystem.remove_source(m, "champion_rip_aura")
		if _has_tag(m, "feral_imp") and m.card_data.id != "champion_rogue_imp_pack":
			BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "champion_rip_aura", false, false)
		state._refresh_slot_for(m)

## ── Champion: Corrupted Broodlings ──────────────────────────────────────────
## Summon condition: 3 friendly minions have died.
## On death: summon a Void-Touched Imp + deal 20% max HP to enemy hero.

func on_enemy_died_champion_cb(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	# Champion died — summon void_touched_imp + deal 20% max HP
	if minion.card_data.id == "champion_corrupted_broodlings":
		state._summon_token("void_touched_imp", "enemy", 200, 300)
		_log("  Corrupted Broodlings champion falls — a Void-Touched Imp rises!", _LOG_ENEMY)
		_on_enemy_champion_killed()
		return
	# Count non-champion deaths toward summon threshold
	if state._champion_cb_summoned:
		return
	var count: int = state._champion_cb_death_count + 1
	state._champion_cb_death_count = count
	_show_champion_progress(count, 3)
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
	if state._champion_im_summoned:
		for m in state.enemy_board:
			if _has_tag(m, "feral_imp"):
				m.current_health += 200
				state._refresh_slot_for(m)
		_log("  Imp Matriarch champion aura: Pack Frenzy grants +200 HP to all feral imps!", _LOG_ENEMY)
		return
	# Track Pack Frenzy casts toward summon threshold
	var count: int = state._champion_im_frenzy_count + 1
	state._champion_im_frenzy_count = count
	_show_champion_progress(count, 2)
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
	if state._champion_acp_summoned:
		return
	var total: int = state._champion_acp_stacks_consumed + stacks
	state._champion_acp_stacks_consumed = total
	_show_champion_progress(mini(total, 5), 5)
	_log("  Champion progress: %d / 5 corruption stacks consumed." % mini(total, 5), _LOG_ENEMY)
	if total >= 5:
		_summon_enemy_champion("champion_abyss_cultist_patrol")

## Aura: while champion alive, corruption application instantly detonates.
## Hooks into ON_ENEMY_MINION_SUMMONED at high priority to run after corrupt_authority_human
## applies corruption. Checks for any corruption on player minions and detonates immediately.
func on_enemy_summon_champion_acp_corrupt(_ctx: EventContext) -> void:
	if not state._champion_acp_summoned:
		return
	# Instantly detonate all corruption stacks on player minions
	var targets: Array = []
	# Prepare targets first so we only pulse the aura when something will actually
	# detonate — avoids a phantom champion pulse when no player minion is corrupted.
	for m: MinionInstance in state.player_board.duplicate():
		var stacks := 0
		for b in m.buffs:
			if (b as BuffEntry).type == Enums.BuffType.CORRUPTION:
				stacks += 1
		if stacks > 0:
			targets.append({"minion": m, "stacks": stacks})
	if targets.is_empty():
		return

	# Pulse the champion's aura — plays alongside the detonations' charge-up.
	state.emit_event(CombatEvent.Kind.VFX, "enemy", {name = "champion_acp_aura_pulse"})
	for t in targets:
		var m: MinionInstance = t["minion"]
		var stacks: int = t["stacks"]
		state.emit_event(CombatEvent.Kind.DETONATION, "enemy", {minion = m, stacks = stacks, damage = 100 * stacks})
		BuffSystem.remove_type(m, Enums.BuffType.CORRUPTION)
		state._refresh_slot_for(m)
		# Route through _spell_dmg so the damage event / popup fires.
		var info := CombatManager.make_damage_info(100 * stacks, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "cultist_patrol_aura")
		state._spell_dmg(m, 100 * stacks, info)
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
	if state._champion_vr_summoned:
		return
	_show_champion_progress(1, 1)
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
		if not state._champion_ch_summoned:
			state._champion_ch_spark_count += 1
			var count: int = state._champion_ch_spark_count
			_show_champion_progress(mini(count, 3), 3)
			_log("  Champion progress: %d / 3 void sparks created." % mini(count, 3), _LOG_ENEMY)
			if count >= 3:
				_summon_enemy_champion("champion_corrupted_handler")
		# Champion aura: each spark summoned deals 200 damage to player hero (only while champion is alive)
		if state._champion_ch_summoned and self._champion_ch_is_alive():
			state.combat_manager.apply_hero_damage("player",
					CombatManager.make_damage_info(200, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "champion_corrupted_handler_aura"))
			var prev_dmg: int = state._champion_ch_aura_dmg
			state._champion_ch_aura_dmg = prev_dmg + 200
			_log("  Corrupted Handler aura: Void Spark summoned → 200 damage to player!", _LOG_ENEMY)

func on_enemy_died_champion_ch(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null:
		return
	if minion.card_data.id == "champion_corrupted_handler":
		_on_enemy_champion_killed()

## ── Shared champion helpers ─────────────────────────────────────────────────

## Champion progress pips on the enemy hero panel (the presenter shows them).
func _show_champion_progress(current: int, total: int) -> void:
	state.emit_event(CombatEvent.Kind.CHAMPION_PROGRESS, "enemy", {current = current, total = total})

func _summon_enemy_champion(card_id: String) -> void:
	# Mark the champion summoned first — a second qualifying event inside the
	# summon (e.g. an AoE killing several minions) must see the flag.
	var st: CombatState = state
	match card_id:
		"champion_rogue_imp_pack":       st._champion_rip_summoned = true
		"champion_corrupted_broodlings": st._champion_cb_summoned = true
		"champion_imp_matriarch":        st._champion_im_summoned = true
		"champion_abyss_cultist_patrol": st._champion_acp_summoned = true
		"champion_void_ritualist":       st._champion_vr_summoned = true
		"champion_corrupted_handler":    st._champion_ch_summoned = true
		"champion_rift_stalker":         st._champion_rs_summoned = true
		"champion_void_aberration":      st._champion_va_summoned = true
		"champion_void_herald":          st._champion_vh_summoned = true
		"champion_void_scout":           st._champion_vs_summoned = true
		"champion_void_warband":         st._champion_vw_summoned = true
		"champion_void_captain":         st._champion_vc_summoned = true
		"champion_void_ritualist_prime": st._champion_vrp_summoned = true
		"champion_void_champion":        st._champion_vch_summoned = true
		"champion_abyss_sovereign":      st._champion_as_summoned = true
	st._champion_summon_count += 1
	state._summon_token(card_id, "enemy")
	_log("  ★ %s champion has arrived!" % CardDatabase.get_card(card_id).card_name, _LOG_ENEMY)
	# Apply aura immediately for Rogue Imp Pack
	if card_id == "champion_rogue_imp_pack":
		_refresh_champion_rip_aura()

func _on_enemy_champion_killed() -> void:
	_log("  ★ Champion slain!", _LOG_ENEMY)
	state.emit_event(CombatEvent.Kind.CHAMPION_KILLED, "enemy")

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

func _champion_ch_is_alive() -> bool:
	for m in state.enemy_board:
		if (m as MinionInstance).card_data.id == "champion_corrupted_handler":
			return true
	return false

## The log line type for `owner`'s side.
func _log_side(owner: String) -> int:
	return _LOG_ENEMY if owner == "enemy" else _LOG_PLAYER

func _log(msg: String, side: int = _LOG_PLAYER) -> void:
	state._log(msg, side)

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

## Spawn shadow claw VFX over the opponent's hero panel.
## owner_side: "player" means the imp belongs to the player → claw hits enemy panel.
func _spawn_void_imp_claw_vfx(minion: MinionInstance, owner_side: String) -> void:
	state.emit_event(CombatEvent.Kind.VFX, owner_side, {name = "void_imp_claw", minion = minion})


## Pack Frenzy card text is "+250 ATK and SWIFT this turn" — so the ATK buff
## (and the Matriarch-variant LIFEDRAIN grant) must revert at the end of the
## caster's turn, not at the start of their next turn (which is what global
## TEMP_ATK cleanup does). Same handler registered on both turn-end events so
## either side can cast it.
func on_turn_end_pack_frenzy_revert(ctx: EventContext) -> void:
	var board: Array = state.enemy_board if ctx.event_type == Enums.TriggerEvent.ON_ENEMY_TURN_END else state.player_board
	for m: MinionInstance in board:
		var had_frenzy: bool = false
		for e: BuffEntry in m.buffs:
			if e.source == "pack_frenzy":
				had_frenzy = true
				break
		if had_frenzy:
			BuffSystem.remove_source(m, "pack_frenzy")
			state._refresh_slot_for(m)
