## SimState.gd
## Headless simulation state — extends CombatState for shared data, adds the
## sim-specific behaviors (setup, profile-driven turns, diagnostic counters).
## No scene tree, no timers, no UI.  Pure game logic only.
##
## CombatSim creates one of these, builds two CombatAgents on top of it,
## and runs two CombatProfiles against each other.
class_name SimState
extends CombatState

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# BOARD_MAX inherited from CombatState
const PLAYER_HAND_MAX    := 10  ## matches TurnManager.HAND_SIZE_MAX
const ENEMY_HAND_MAX     := 10  ## matches EnemyAI.HAND_MAX
const COMBINED_RESOURCE_CAP := 11
const ESSENCE_HARD_CAP   := 10

## Self-pointer so callers (handlers, effects, profiles) can use the same
## `_scene.state.X` accessor whether `_scene` is a CombatScene (which composes
## CombatState) or a SimState (which IS a CombatState).
var state: CombatState:
	get: return self

# ---------------------------------------------------------------------------
# Boards, hero HP, sovereign phase, _combat_ended, winner — inherited from CombatState
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Resources — profiles write these directly via agent.essence / agent.mana
# ---------------------------------------------------------------------------

var player_essence:     int = 0
## Direct writes by profiles record the growth choice for F15 abyssal_mandate.
var _player_essence_max: int = 0
var player_essence_max: int:
	get: return _player_essence_max
	set(v):
		if v > _player_essence_max:
			last_player_growth = "essence"
		_player_essence_max = v
var player_mana:        int = 0
var _player_mana_max: int = 0
var player_mana_max: int:
	get: return _player_mana_max
	set(v):
		if v > _player_mana_max:
			last_player_growth = "mana"
		_player_mana_max = v

var enemy_essence:      int = 0
var enemy_essence_max:  int = 0
var enemy_mana:         int = 0
var enemy_mana_max:     int = 0

# ---------------------------------------------------------------------------
# Decks / hands / discards
# ---------------------------------------------------------------------------

var player_deck:    Array[CardInstance] = []
var player_hand:    Array[CardInstance] = []
## Unified player graveyard — every card the player plays this combat is appended
## here (minions, spells, traps, runes, environments) at play time. Each entry has
## its `resolved_on_turn` stamped at append time. Full-combat record.
var player_graveyard: Array[CardInstance] = []

var enemy_deck:    Array[CardInstance] = []
var enemy_hand:    Array[CardInstance] = []
## Unified enemy graveyard — mirror of player_graveyard for the enemy side.
var enemy_graveyard: Array[CardInstance] = []
var enemy_limited_cards: Array[String] = []

# ---------------------------------------------------------------------------
# Traps / environment / void marks
# ---------------------------------------------------------------------------

## Trap/env/rune fields (active_traps, active_environment, enemy_active_traps,
## enemy_active_environment, enemy_void_marks, _rune_aura_handlers,
## _env_ritual_handlers) inherited from CombatState.

## Talent / hero / Seris state (player_flesh, player_flesh_max,
## _fiendish_pact_pending, forge_counter, forge_counter_threshold,
## _player_spell_damage_bonus, talents, hero_passives, player_hero_id) inherited
## from CombatState.

## (`_last_attacker` inherited from CombatState — populated during attack
## resolution so death triggers can read the killer via ctx.attacker.)

## Callable SimTriggerSetup registered on BuffSystem.bus() for corruption_removed.
## Stored so teardown() can cleanly disconnect and avoid cross-sim leaks.
var _buff_bus_callable: Callable = Callable()

# ---------------------------------------------------------------------------
# Cost penalties / spell counters / once-per-turn flags / passive config /
# crit + dark channeling / champion counters / diagnostics / relic flags —
# all inherited from CombatState. SimState only retains the sim-specific
# orchestration fields below.
# ---------------------------------------------------------------------------

## Active enemy CombatProfile reference — CombatSim re-reads this each turn so
## the F15 phase transition can swap profiles mid-run.
var _e_profile: CombatProfile = null
## Factory callable (profile_id: String) -> CombatProfile. Bound by CombatSim.
var _e_profile_factory: Callable = Callable()

## AI profile id currently driving the enemy (sim mirror of EnemyAI.ai_profile).
var enemy_ai_profile: String = ""

# ---------------------------------------------------------------------------
# Sim result — `winner` inherited from CombatState
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Shared combat manager — both agents use this
# ---------------------------------------------------------------------------

## (`combat_manager` inherited from CombatState — assigned in setup() below.)

## (`trigger_manager` inherited from CombatState — wired by SimTriggerSetup
## after SimState.setup() / by CombatScene._ready in live combat.)

# ---------------------------------------------------------------------------
# Duck-typed scene sub-objects (EffectResolver accesses ctx.scene.turn_manager
# and ctx.scene.enemy_ai)
# ---------------------------------------------------------------------------

## (`turn_manager` inherited from CombatState — assigned to a SimTurnManager
## instance in setup(). Untyped on the parent so both SimTurnManager (sim) and
## TurnManager (live) fit.)
var enemy_ai: SimEnemyAgent       ## set by CombatSim after creating the agent
## (`_hardcoded` inherited from CombatState — assigned in setup() below.)

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(p_deck_ids: Array[String], e_deck_ids: Array[String],
		p_hp: int = 3000, e_hp: int = 2000) -> void:
	player_hp = p_hp
	enemy_hp  = e_hp

	# Build decks. Player side applies talent_overrides via _card_for; enemy
	# side passes [] (enemies have no talents today). Mirrors live combat.
	for id in p_deck_ids:
		var card := _card_for("player", id)
		if card:
			player_deck.append(CardInstance.create(card))
	player_deck.shuffle()

	for id in e_deck_ids:
		var card := _card_for("enemy", id)
		if card:
			enemy_deck.append(CardInstance.create(card))
	enemy_deck.shuffle()

	# Pre-allocate board slot placeholders (no scene tree — _ready never fires,
	# _overlay stays null, so _refresh_visuals() returns early — safe to use)
	for i in BOARD_MAX:
		var ps := BoardSlot.new()
		ps.slot_owner = "player"
		ps.index      = i
		player_slots.append(ps)
		var es := BoardSlot.new()
		es.slot_owner = "enemy"
		es.index      = i
		enemy_slots.append(es)

	# Wire up combat manager
	combat_manager = CombatManager.new()
	combat_manager.scene = self
	combat_manager.minion_vanished.connect(_on_minion_vanished)
	combat_manager.hero_damaged.connect(_on_hero_damaged)
	combat_manager.hero_healed.connect(_on_hero_healed)

	# Subscribe to damage_dealt for dmg_log diagnostic capture. Replaces the
	# inline `if dmg_log_enabled: dmg_log.append(...)` block in _on_hero_damaged
	# so any future damage source emitting through state goes through one path.
	damage_dealt.connect(_capture_damage_for_dmg_log)

	# Turn manager proxy (for EffectResolver DRAW / GRANT_MANA etc.)
	turn_manager = SimTurnManager.new()
	turn_manager.setup(self)

	# Hardcoded effect resolver
	_hardcoded = HardcodedEffects.new()
	_hardcoded.setup(self)

	# Draw opening hands
	_draw_player(3)
	_draw_enemy(5)

## Subscriber to CombatState.damage_dealt — appends to dmg_log when enabled.
## Skips entries marked "__logged__" (void bolt split-log already captured the
## base + bonus components separately at the source — see _deal_void_bolt_damage).
func _capture_damage_for_dmg_log(source: String, _target: String, amount: int, _school: int, _was_crit: bool) -> void:
	if not dmg_log_enabled:
		return
	if source == "__logged__":
		return
	dmg_log.append({turn = _current_turn, amount = amount, source = source})

# ---------------------------------------------------------------------------
# Signal handlers — called by CombatManager
# ---------------------------------------------------------------------------

func _on_minion_vanished(minion: MinionInstance) -> void:
	# Locate slot index for the minion_died signal payload before clearing.
	var slot_index: int = -1
	var search_slots := player_slots if minion.owner == "player" else enemy_slots
	for i in search_slots.size():
		if search_slots[i].minion == minion:
			slot_index = i
			break
	player_board.erase(minion)
	enemy_board.erase(minion)
	# Clear the slot so it can be reused
	for slot in player_slots:
		if slot.minion == minion:
			slot.minion = null
			break
	for slot in enemy_slots:
		if slot.minion == minion:
			slot.minion = null
			break
	# Re-emit through state — symmetric with CombatScene._on_minion_vanished.
	minion_died.emit(minion.owner, minion, slot_index)
	# Fire death trigger AFTER removal so passive recalculations see the correct board state
	if trigger_manager != null:
		var event := Enums.TriggerEvent.ON_PLAYER_MINION_DIED if minion.owner == "player" \
			else Enums.TriggerEvent.ON_ENEMY_MINION_DIED
		var pre_corruption: int = BuffSystem.count_type(minion, Enums.BuffType.CORRUPTION)
		if pre_corruption > 0:
			var rm_ctx := EventContext.make(Enums.TriggerEvent.ON_CORRUPTION_REMOVED, minion.owner)
			rm_ctx.minion = minion
			rm_ctx.damage = pre_corruption
			trigger_manager.fire(rm_ctx)
		var ctx := EventContext.make(event, minion.owner)
		ctx.minion = minion
		ctx.attacker = _last_attacker
		trigger_manager.fire(ctx)

func _on_hero_damaged(target: String, info: Dictionary) -> void:
	var amount: int = info.get("amount", 0)
	var src: Enums.DamageSource = info.get("source", Enums.DamageSource.SPELL)
	if target == "player":
		if _relic_hero_immune:
			return  # Bone Shield: immune this turn
		player_hp -= amount
		# Fire ON_HERO_DAMAGED for every landed hit — including lethal. Mirrors live combat.
		var _pctx := EventContext.make(Enums.TriggerEvent.ON_HERO_DAMAGED, "player")
		_pctx.damage = amount
		_pctx.damage_info = info
		trigger_manager.fire(_pctx)
		if player_hp <= 0 and winner.is_empty():
			winner = "enemy"
	else:
		enemy_hp -= amount
		# Emit damage_dealt — sim subscribes for dmg_log; live combat ignores.
		# Source attribution: prefer DamageInfo.source_card, fall back to the
		# legacy _pending_dmg_source plumbing, finally a generic label.
		var src_label: String = str(info.get("source_card", ""))
		if src_label.is_empty():
			src_label = _pending_dmg_source if not _pending_dmg_source.is_empty() \
				else ("minion_atk" if src == Enums.DamageSource.MINION else "spell_onplay")
		damage_dealt.emit(src_label, "enemy", amount, info.get("school", Enums.DamageSchool.NONE), false)
		_pending_dmg_source = ""
		# Fire ON_ENEMY_HERO_DAMAGED for every landed hit — including lethal.
		var _ectx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_HERO_DAMAGED, "enemy")
		_ectx.damage = amount
		_ectx.damage_info = info
		trigger_manager.fire(_ectx)
		if enemy_hp <= 0 and winner.is_empty():
			# F15 Abyss Sovereign: intercept P1 death and transition to P2
			# instead of ending the fight.
			var pt = preload("res://combat/board/PhaseTransition.gd")
			if pt.attempt(self):
				return
			winner = "player"

func _on_hero_healed(target: String, amount: int) -> void:
	if target == "player":
		player_hp += amount
	else:
		enemy_hp += amount

# ---------------------------------------------------------------------------
# Scene API — called by EffectResolver
# ---------------------------------------------------------------------------

## (`_friendly_board`, `_opponent_board`, `_count_type_on_board` inherited from
## CombatState.)

func _friendly_hand(owner: String) -> Array:
	return player_hand if owner == "player" else enemy_hand

## (`_peek_fiendish_pact_discount` inherited from CombatState.)

func _consume_fiendish_pact_discount() -> void:
	if _fiendish_pact_pending <= 0:
		return
	_fiendish_pact_pending = 0
	for inst in player_hand:
		if inst == null or inst.card_data == null:
			continue
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).minion_type == Enums.MinionType.DEMON:
			inst.essence_delta = 0

## (`_spell_dmg` inherited from CombatState.)

## (`_summon_token` inherited from CombatState — pure-logic version since sim
## doesn't register a _summon_delegate.)

## (`_corrupt_minion` and `_apply_void_mark` inherited from CombatState.)

## (`_gain_flesh`, `_spend_flesh`, `_on_flesh_spent` inherited from CombatState.
## Flesh Bond's draw routes through state.turn_manager.draw_card(), which on
## sim is SimTurnManager.draw_card() → _draw_player(1).)

## (`_forge_counter_tick`, `_forge_counter_reset`, `_gain_forge_counter`,
## `_summon_forged_demon`, `_grant_forged_demon_auras` inherited from CombatState.)

## (`_heal_minion` and `_heal_minion_full` inherited from CombatState.)

## (`_sacrifice_minion` inherited from CombatState.)

## (`_add_kill_stacks` inherited from CombatState.)

## (`_on_demon_sacrificed` and `_FORGED_DEMON_AURAS` inherited from CombatState.)

## (`_pre_player_spell_cast` and `_post_player_spell_cast` inherited from CombatState.)

## Forwards BuffSystem.corruption_removed into this sim's TriggerManager so
## Corrupt Detonation (and other ON_CORRUPTION_REMOVED listeners) fire during sims.
func _on_corruption_removed_bus(minion: MinionInstance, stacks: int) -> void:
	if trigger_manager == null or minion == null or stacks <= 0:
		return
	var ctx := EventContext.make(Enums.TriggerEvent.ON_CORRUPTION_REMOVED, minion.owner)
	ctx.minion = minion
	ctx.damage = stacks
	trigger_manager.fire(ctx)

## Disconnect global-bus subscriptions and drop references so this sim instance
## can be freed cleanly and its callbacks don't leak into the next sim run.
func teardown() -> void:
	var buff_bus: Object = BuffSystem.bus()
	if buff_bus != null and _buff_bus_callable.is_valid():
		if buff_bus.is_connected("corruption_removed", _buff_bus_callable):
			buff_bus.disconnect("corruption_removed", _buff_bus_callable)
	_buff_bus_callable = Callable()

## Seris — button-press counters used by BalanceSim for behavior diagnostics.
## Zeroed per combat (fresh SimState per run).
var _debug_soul_forge_fires: int = 0
var _debug_corrupt_flesh_fires: int = 0

## Seris — Soul Forge wrapper for SerisPlayerProfile. Calls inherited
## state._soul_forge_activate and increments the diagnostic counter on success.
func _soul_forge_activate() -> bool:
	if not super._soul_forge_activate():
		return false
	_debug_soul_forge_fires += 1
	return true

## Seris — Corrupt Flesh activated-ability for sim profiles. Wraps
## state._seris_corrupt_apply with the diagnostic counter increment used by
## BalanceSim's behavior reports.
func _seris_corrupt_activate(target: MinionInstance) -> bool:
	if not _seris_corrupt_apply(target):
		return false
	_debug_corrupt_flesh_fires += 1
	return true

## (`_seris_corrupt_reset_turn` and `_try_save_from_death` inherited from CombatState.)

## (`_deal_void_bolt_damage`, `_deal_enemy_void_bolt_damage`, and
## `_void_mark_damage_per_stack` inherited from CombatState.)

var debug_log_enabled: bool = false

func _log(_msg: Variant, _type: int = 0) -> void:
	if debug_log_enabled:
		print(_msg)

## (`_refresh_slot_for` inherited from CombatState — emits minion_stats_changed
## which has no subscribers in headless sim, so the call is a no-op here.)

func _update_counter_warning() -> void:
	pass  # no UI

func _update_champion_progress(_current: int, _total: int) -> void:
	pass  # no UI in headless sim

func _on_champion_killed() -> void:
	pass  # no UI in headless sim

func _spawn_void_imp_claw_vfx_at(_source_pos: Vector2, _owner_side: String) -> void:
	pass  # no VFX in headless sim

func _find_slot_for(_minion) -> Variant:
	return null  # no slots in headless sim; callers null-check

## (`_opponent_of` inherited from CombatState.)

func _friendly_deck(owner: String) -> Array:
	return player_deck if owner == "player" else enemy_deck

func _add_to_owner_hand(owner: String, inst: CardInstance) -> void:
	if owner == "player":
		turn_manager.add_instance_to_hand(inst)
	else:
		if enemy_hand.size() < 10:
			enemy_hand.append(inst)

## (`_friendly_slots` inherited from CombatState.)

func _friendly_traps(owner: String) -> Array:
	return active_traps if owner == "player" else enemy_active_traps

## Return the unified card graveyard belonging to the given owner. Mirror of CombatScene._friendly_graveyard.
func _friendly_graveyard(owner: String) -> Array:
	return player_graveyard if owner == "player" else enemy_graveyard

func _opponent_traps(owner: String) -> Array:
	return _friendly_traps(_opponent_of(owner))

## (`_update_trap_display_for` inherited from CombatState — emits traps_changed
## which has no subscribers in headless sim, so the call is a no-op.)

func _find_random_enemy_minion() -> MinionInstance:
	return _find_random_minion(enemy_board)

func _resolve_void_devourer_sacrifice(_devourer: MinionInstance, _owner: String) -> void:
	pass  # complex effect — not simulated

## (`_update_trap_display`, `_update_environment_display`, `_find_random_minion`,
## `_remove_rune_aura`, `_unregister_env_rituals`, `_rune_aura_multiplier`,
## `_minion_has_tag`, `_has_talent` all inherited from CombatState.)

## (`_resolve_hardcoded` inherited from CombatState.)

# ---------------------------------------------------------------------------
# Rune / trap / ritual / environment infrastructure
# ---------------------------------------------------------------------------

## Register persistent aura handlers for a newly placed rune.
## (`_apply_rune_aura` inherited from CombatState.)

## Register 2-rune ritual handlers for the given environment.
func _register_env_rituals(env: EnvironmentCardData) -> void:
	for ritual in env.rituals:
		var r: RitualData = ritual
		var h := func(_ctx: EventContext): _handlers_ref.on_env_ritual(r)
		_env_ritual_handlers.append(h)
		trigger_manager.register(Enums.TriggerEvent.ON_RUNE_PLACED, h, 5)
		trigger_manager.register(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, h, 5)

## Run teardown steps for the outgoing environment.
func _unregister_env_aura(env: EnvironmentCardData) -> void:
	if not env.on_replace_effect_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		EffectResolver.run(env.on_replace_effect_steps, ctx)

## (`_check_and_fire_traps` inherited from CombatState.)

## (`_runes_satisfy` inherited from CombatState.)

## Sim wrapper — increments diagnostic counter then runs inherited
## state._fire_ritual (rune consumption + effect resolution + ON_RITUAL_FIRED).
func _fire_ritual(ritual: RitualData) -> void:
	_player_ritual_count += 1
	super._fire_ritual(ritual)

## Summon a Void Imp token on the player board (used by ritual_surge talent).
func _summon_void_imp() -> void:
	_summon_token("void_imp", "player", 0, 0, 0)

## Reference to the CombatHandlers instance — set by SimTriggerSetup for env rituals.
var _handlers_ref: CombatHandlers = null

## Duck-typing alias — Act 3 AI profiles read `_handlers` to fire rune handlers.
var _handlers: CombatHandlers:
	get: return _handlers_ref

## (`_active_enemy_passives` and `_void_mana_drain_pending` inherited from
## CombatState. SimTriggerSetup keeps `_active_enemy_passives` synced with the
## sim-side `enemy_passives` field at setup time.)

# ---------------------------------------------------------------------------
# Card draw helpers
# ---------------------------------------------------------------------------

func _draw_player(count: int) -> void:
	for _i in count:
		if player_hand.size() >= PLAYER_HAND_MAX: break
		if player_deck.is_empty(): break  # finite deck — no reshuffle
		var inst: CardInstance = player_deck.pop_front()
		player_hand.append(inst)
		if trigger_manager != null:
			var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, "player")
			ctx.card = inst.card_data
			trigger_manager.fire(ctx)

## Rebuild the enemy deck/hand/graveyard from a fresh card-id list. Used by the
## F15 phase transition to swap the Sovereign's deck between P1 and P2.
func setup_enemy_deck(card_ids: Array[String]) -> void:
	enemy_deck.clear()
	enemy_hand.clear()
	enemy_graveyard.clear()
	for id in card_ids:
		var card := _card_for("enemy", id)
		if card:
			enemy_deck.append(CardInstance.create(card))
	enemy_deck.shuffle()
	_draw_enemy(5)

func _draw_enemy(count: int) -> void:
	for _i in count:
		if enemy_hand.size() >= ENEMY_HAND_MAX: break
		if enemy_deck.is_empty():
			break
		var inst: CardInstance = enemy_deck.pop_front()
		enemy_hand.append(inst)
		# Add a fresh replacement so the deck never truly empties
		# Limited cards are NOT re-added (one-time draw per copy)
		if inst.card_data.id not in enemy_limited_cards:
			enemy_deck.append(CardInstance.create(inst.card_data))
			enemy_deck.shuffle()

# ---------------------------------------------------------------------------
# Turn helpers — called by CombatSim
# ---------------------------------------------------------------------------

## Optional override set by a CombatProfile to replace the default resource-growth logic.
## Signature: func(turn_number: int) -> void
var player_growth_override: Callable = Callable()
var enemy_growth_override: Callable = Callable()

func begin_player_turn(turn_number: int) -> void:
	_current_turn = turn_number
	if player_growth_override.is_valid():
		player_growth_override.call(turn_number)
	else:
		_grow_player_resources(turn_number)
	player_essence = player_essence_max
	player_mana    = player_mana_max
	player_spell_cost_penalty = _spell_tax_for_player_turn
	_spell_tax_for_player_turn = 0
	if _void_mana_drain_pending:
		_void_mana_drain_pending = false
		player_mana = 0
	for inst in player_hand:
		inst.reset_deltas()
	_fiendish_pact_pending = 0
	_once_per_turn_used.clear()
	if trigger_manager != null:
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_PLAYER_TURN_START))
	_draw_player(1)
	_unexhaust_board(player_board)

func end_player_turn() -> void:
	player_spell_cost_penalty = 0
	_enemy_traps_blocked = false

func begin_enemy_turn(turn_number: int) -> void:
	if enemy_growth_override.is_valid():
		enemy_growth_override.call(turn_number)
	else:
		_grow_enemy_resources(turn_number)
	enemy_essence = enemy_essence_max
	enemy_mana    = enemy_mana_max
	enemy_spell_cost_penalty = _spell_tax_for_enemy_turn
	_spell_tax_for_enemy_turn = 0
	if trigger_manager != null:
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_ENEMY_TURN_START))
	_draw_enemy(1)
	_unexhaust_board(enemy_board)

func end_enemy_turn() -> void:
	# Fire ON_ENEMY_TURN_END before cleanup (void_unraveling spark transfer)
	if trigger_manager:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_TURN_END, "enemy")
		trigger_manager.fire(ctx)
	enemy_spell_cost_penalty = 0
	_player_traps_blocked = false

func _grow_player_resources(turn_number: int) -> void:
	if turn_number <= 1: return
	if player_essence_max + player_mana_max >= COMBINED_RESOURCE_CAP: return
	if player_mana_max < player_essence_max - 2:
		player_mana_max += 1
		last_player_growth = "mana"
	else:
		player_essence_max += 1
		last_player_growth = "essence"

func _grow_enemy_resources(turn_number: int) -> void:
	if turn_number <= 1: return
	if enemy_essence_max + enemy_mana_max >= COMBINED_RESOURCE_CAP: return
	if enemy_mana_max < enemy_essence_max - 2:
		enemy_mana_max += 1
	else:
		enemy_essence_max += 1

func _unexhaust_board(board: Array[MinionInstance]) -> void:
	for minion in board:
		minion.on_turn_start()
