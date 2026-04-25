## SimState.gd
## Headless simulation state — duck-types as CombatScene for EffectResolver.
## No scene tree, no timers, no UI.  Pure game logic only.
##
## CombatSim creates one of these, builds two CombatAgents on top of it,
## and runs two CombatProfiles against each other.
class_name SimState
extends RefCounted

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const BOARD_MAX          := 5
const PLAYER_HAND_MAX    := 10  ## matches TurnManager.HAND_SIZE_MAX
const ENEMY_HAND_MAX     := 10  ## matches EnemyAI.HAND_MAX
const COMBINED_RESOURCE_CAP := 11
const ESSENCE_HARD_CAP   := 10

# ---------------------------------------------------------------------------
# Boards — shared by both agents
# ---------------------------------------------------------------------------

var player_board: Array[MinionInstance] = []
var enemy_board:  Array[MinionInstance] = []

## Pre-allocated BoardSlot placeholders (no scene tree — visuals never initialise).
## Profiles call find_empty_slot() which returns one of these.
var player_slots: Array[BoardSlot] = []
var enemy_slots:  Array[BoardSlot] = []

# ---------------------------------------------------------------------------
# Hero HP
# ---------------------------------------------------------------------------

var player_hp: int = 3000
var enemy_hp:  int = 2000

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

var active_traps:       Array       = []   ## Array[TrapCardData] — player side
var active_environment              = null ## EnvironmentCardData or null — player side
var enemy_active_traps: Array       = []   ## Array[TrapCardData] — enemy side
var enemy_active_environment        = null ## EnvironmentCardData or null — enemy side
var enemy_void_marks:   int         = 0

## Seris — Flesh counter (per-combat, capped). Mirrors CombatScene.player_flesh.
var player_flesh:     int = 0
var player_flesh_max: int = 5

## Seris — Fiendish Pact pending Mana discount. Mirrors CombatScene._fiendish_pact_pending.
var _fiendish_pact_pending: int = 0

## Seris — Forge Counter (Demon Forge branch). Mirrors CombatScene.forge_counter.
var forge_counter:           int = 0
var forge_counter_threshold: int = 3

## Mirrors CombatScene._last_attacker — populated during attack resolution so death
## triggers can read the killer via ctx.attacker.
var _last_attacker: MinionInstance = null

## Identifies which hero the player is running as, so profiles can branch on
## hero-specific activated abilities (Seris's Forge / Corrupt buttons). Matches
## HeroDatabase ids ("lord_vael", "seris"). Defaults to Vael for back-compat with
## existing sim callers that don't pass it.
var player_hero_id: String = "lord_vael"

## Callable SimTriggerSetup registered on BuffSystem.bus() for corruption_removed.
## Stored so teardown() can cleanly disconnect and avoid cross-sim leaks.
var _buff_bus_callable: Callable = Callable()

## Mirrors CombatScene._player_spell_damage_bonus — set on ON_PLAYER_SPELL_CAST start,
## cleared after resolution. _spell_dmg adds it to every spell-damage target hit.
var _player_spell_damage_bonus: int = 0

## Aura handlers registered for each active rune — Array[{rune_id, entries}]
## where entries is Array[{event, handler}].
var _rune_aura_handlers: Array = []

## Ritual handlers registered for the current environment.
var _env_ritual_handlers: Array = []

# ---------------------------------------------------------------------------
# Spell cost modifier (enemy side, mirrors EnemyAI)
# ---------------------------------------------------------------------------

var enemy_spell_cost_penalty:   int        = 0
## Persistent flat mana-cost adjustment from an active aura (e.g. Void Ritualist
## Prime champion reduces by 1). Negative = discount. Not reset per turn.
var enemy_spell_cost_aura:      int        = 0
var enemy_spell_cost_discounts: Dictionary = {}
var enemy_essence_cost_discounts: Dictionary = {}
## Flat enemy minion essence-cost aura (F15 Abyssal Mandate). Negative = cheaper.
## Set when the player grows Essence; cleared at end of the following enemy turn.
var enemy_minion_essence_cost_aura: int = 0

## Pending spell tax applied at next turn start (set by Spell Taxer effect).
var _spell_tax_for_enemy_turn:  int = 0
var _spell_tax_for_player_turn: int = 0

## Active player spell cost penalty this turn (applied at turn start, cleared at turn end).
var player_spell_cost_penalty: int = 0

## When true, enemy traps cannot trigger (set by Saboteur Adept, cleared at player turn end).
var _enemy_traps_blocked: bool = false

## When true, player traps cannot trigger (set by enemy Saboteur Adept, cleared at enemy turn end).
var _player_traps_blocked: bool = false

## Spell counter: when > 0, next spell cast by this side is cancelled and counter decrements.
var _player_spell_counter: int = 0
var _enemy_spell_counter: int = 0

## Debug counters for sim tracking.
var _ritual_sacrifice_count: int = 0   ## Enemy ritual_sacrifice passive fires
var _detonation_count: int = 0         ## Enemy corrupt_authority imp detonation fires
var _player_ritual_count: int = 0      ## Player ritual fires (e.g. Demon Ascendant)

var _spark_spawned_count: int = 0     ## Void Sparks spawned on enemy board (human died)
var _spark_transfer_count: int = 0    ## Void Spark transfers to player board
var _champion_summon_count: int = 0   ## Enemy champion summons
var _corruption_detonation_times: int = 0  ## Fight 4: corruption detonation events
var _ritual_invoke_times: int = 0          ## Fight 5: ritual sacrifice triggers
var _handler_spark_buff_times: int = 0     ## Fight 6: feral imp → spark ATK buff events
var _smoke_veil_fires: int = 0        ## Smoke Veil trap activations
var _smoke_veil_damage_prevented: int = 0  ## Total ATK blocked by Smoke Veil
var _abyssal_plague_fires: int = 0    ## Abyssal Plague casts
var _abyssal_plague_kills: int = 0    ## Enemy minions killed by Abyssal Plague
var _void_bolt_spell_casts: int = 0   ## Void Bolt spell casts (not rune procs)
var _void_bolt_total_dmg: int = 0     ## Total void bolt damage (spells + runes)
var _void_imp_dmg: int = 0            ## Total damage from Void Imp on-play

## Optional per-turn snapshot hook. Called at end of enemy turn with (state, turn).
var turn_snapshot_callback: Callable = Callable()

## Verbose damage log — populated when dmg_log_enabled = true.
## Each entry: { turn: int, amount: int, source: String }
var dmg_log_enabled: bool = false
var dmg_log: Array = []
var _current_turn: int = 0
var _pending_dmg_source: String = ""

## Most recent player resource-growth choice ("" | "essence" | "mana").
## Written by _grow_player_resources; read by abyssal_mandate handler.
var last_player_growth: String = ""

## F15 Abyss Sovereign phase marker (1 = P1, 2 = P2). Always starts at 1; the
## phase-transition helper flips it to 2. Non-F15 fights leave this alone.
var _sovereign_phase: int = 1
## Turn number at which the P1→P2 transition fired. 0 = never transitioned.
var _sovereign_transition_turn: int = 0

## Active enemy CombatProfile reference — CombatSim re-reads this each turn so
## the F15 phase transition can swap profiles mid-run.
var _e_profile: CombatProfile = null
## Factory callable (profile_id: String) -> CombatProfile. Bound by CombatSim.
var _e_profile_factory: Callable = Callable()

## AI profile id currently driving the enemy (sim mirror of EnemyAI.ai_profile).
var enemy_ai_profile: String = ""

## Once-per-turn gate for feral_reinforcement passive.
var _imp_caller_fired: bool = false
var _soul_rune_fires_this_turn: int = 0

## Relic state flags (set by RelicEffects, consumed by combat logic).
var _relic_hero_immune: bool = false
var _relic_cost_reduction: int = 0
var _relic_extra_turn: bool = false

# ---------------------------------------------------------------------------
# Player talents (configure before running to simulate a talent build)
# ---------------------------------------------------------------------------

## Set of active talent IDs for the player. Example: ["piercing_void"]
var talents: Array[String] = []

## Hero passive IDs for the current hero. Set by CombatSim before SimTriggerSetup.setup().
var hero_passives: Array[String] = []

## Active passive IDs for the current enemy encounter (e.g. ["pack_instinct"]).
## Set by CombatSim before calling SimTriggerSetup.setup().
var enemy_passives: Array[String] = []

## Passive-configurable stats — set by CombatSetup from the registry at combat start.
var void_mark_damage_per_stack: int = 25  ## deepened_curse sets this to 40
var rune_aura_multiplier:       int = 1   ## runic_attunement sets this to 2

## Imp Evolution once-per-turn gate — reset at the start of each player turn.
var imp_evolution_used_this_turn: bool = false

## Act 4 passive stats — set dynamically by CombatSetup via scene.set().
var _vp_pre_crit_stacks: int = 0
var _spirit_conscription_fired: bool = false
var crit_multiplier: float = 2.0
var enemy_crit_multiplier: float = 0.0  ## Per-side override; 0 = use global
var _enemy_crits_consumed: int = 0
var _player_crits_consumed: int = 0
var _last_crit_attacker: MinionInstance = null
var _last_attack_was_crit: bool = false
var _dark_channeling_active: bool = false
var _dark_channeling_multiplier: float = 1.0
var _dark_channeling_amp_count: int = 0
var _dark_channeling_amp_by_spell: Dictionary = {}  ## spell_id -> count
var _dark_channeling_dmg_by_spell: Dictionary = {}  ## spell_id -> extra damage dealt by amp

## Enemy champion state — set dynamically by CombatSetup via scene.set().
var enemy_hp_max: int = 0
var _champion_rip_attack_ids: Array = []
var _champion_rip_summoned: bool = false
var _champion_cb_death_count: int = 0
var _champion_cb_summoned: bool = false
var _champion_im_frenzy_count: int = 0
var _champion_im_summoned: bool = false
# Act 2 champion state
var _champion_acp_stacks_consumed: int = 0
var _champion_acp_summoned: bool = false
var _champion_vr_summoned: bool = false
var _champion_ch_spark_count: int = 0
var _champion_ch_summoned: bool = false
var _champion_ch_aura_dmg: int = 0
# Act 3 champion state
var _champion_rs_spark_dmg: int = 0
var _champion_rs_summoned: bool = false
# Act 3 champion: Void Aberration
var _champion_va_sparks_consumed: int = 0
var _champion_va_summoned: bool = false
# Act 3 champion: Void Herald
var _champion_vh_spark_cards_played: int = 0
var _champion_vh_summoned: bool = false
# Act 4 champion: Void Scout
var _champion_vs_crits_consumed: int = 0
var _champion_vs_summoned: bool = false
# Act 4 champion: Void Captain
var _champion_vc_tc_cast: int = 0
var _champion_vc_summoned: bool = false
# Act 4 champion: Void Champion
var _champion_vch_crit_kills: int = 0
var _champion_vch_summoned: bool = false
# Act 4 champion: Void Ritualist Prime
var _champion_vrp_spells_cast: int = 0
var _champion_vrp_summoned: bool = false
# Act 4 champion: Void Warband
var _champion_vw_spirits_consumed: int = 0
var _champion_vw_summoned: bool = false
var _vw_behemoth_plays: int = 0   ## Void Behemoth plays by Warband profile
var _vw_bastion_plays: int = 0    ## Bastion Colossus plays by Warband profile
var _void_echo_fired_this_turn: bool = false ## Swarm capstone once-per-turn flag
var _vw_death_crit_grants: int = 0 ## Spirit-death aura crit grants while champion alive
## Death/loss tracking for Behemoth/Bastion (key = minion card id, value = count)
## Causes: "consumed" (fuel), "damage" (spell/AoE), "combat" (minion attack), "survived"
var _vw_behemoth_lost: Dictionary = {"consumed": 0, "damage": 0, "combat": 0, "survived": 0}
var _vw_bastion_lost: Dictionary = {"consumed": 0, "damage": 0, "combat": 0, "survived": 0}
var _rift_lord_plays: int = 0  ## Times Void Rift Lord was played
var _hollow_sentinel_buffs: int = 0  ## Times Hollow Sentinel buffed sparks
var _immune_dmg_prevented: int = 0  ## Total damage prevented by GRANT_IMMUNE
var _rift_collapse_casts: int = 0   ## Rift Collapse casts by enemy
var _rift_collapse_kills: int = 0   ## Player minions killed by Rift Collapse

# ---------------------------------------------------------------------------
# Sim result
# ---------------------------------------------------------------------------

var winner: String = ""  ## "player", "enemy", or "" while running

# ---------------------------------------------------------------------------
# Shared combat manager — both agents use this
# ---------------------------------------------------------------------------

var combat_manager: CombatManager

## TriggerManager — wired by SimTriggerSetup after SimState.setup().
var trigger_manager: TriggerManager = null

# ---------------------------------------------------------------------------
# Duck-typed scene sub-objects (EffectResolver accesses ctx.scene.turn_manager
# and ctx.scene.enemy_ai)
# ---------------------------------------------------------------------------

var turn_manager: SimTurnManager  ## set up in setup()
var enemy_ai: SimEnemyAgent       ## set by CombatSim after creating the agent
var _hardcoded: HardcodedEffects  ## set up in setup()

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(p_deck_ids: Array[String], e_deck_ids: Array[String],
		p_hp: int = 3000, e_hp: int = 2000) -> void:
	player_hp = p_hp
	enemy_hp  = e_hp

	# Build decks
	for id in p_deck_ids:
		var card := CardDatabase.get_card(id)
		if card:
			player_deck.append(CardInstance.create(card))
	player_deck.shuffle()

	for id in e_deck_ids:
		var card := CardDatabase.get_card(id)
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

	# Turn manager proxy (for EffectResolver DRAW / GRANT_MANA etc.)
	turn_manager = SimTurnManager.new()
	turn_manager.setup(self)

	# Hardcoded effect resolver
	_hardcoded = HardcodedEffects.new()
	_hardcoded.setup(self)

	# Draw opening hands
	_draw_player(3)
	_draw_enemy(5)

# ---------------------------------------------------------------------------
# Signal handlers — called by CombatManager
# ---------------------------------------------------------------------------

func _on_minion_vanished(minion: MinionInstance) -> void:
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
		if dmg_log_enabled:
			if _pending_dmg_source == "__logged__":
				pass  # already split-logged in _deal_void_bolt_damage
			else:
				var source: String = _pending_dmg_source if not _pending_dmg_source.is_empty() \
					else ("minion_atk" if src == Enums.DamageSource.MINION else "spell_onplay")
				dmg_log.append({turn = _current_turn, amount = amount, source = source})
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

func _friendly_board(owner: String) -> Array:
	return player_board if owner == "player" else enemy_board

func _count_type_on_board(type: Enums.MinionType, owner: String) -> int:
	var count := 0
	for m in _friendly_board(owner):
		if (m as MinionInstance).card_data.minion_type == type:
			count += 1
	return count

func _opponent_board(owner: String) -> Array:
	return enemy_board if owner == "player" else player_board

func _friendly_hand(owner: String) -> Array:
	return player_hand if owner == "player" else enemy_hand

## Seris Starter — Fiendish Pact discount peek (mirror of CombatScene).
func _peek_fiendish_pact_discount(mc: MinionCardData) -> int:
	if _fiendish_pact_pending <= 0:
		return 0
	if mc == null or mc.minion_type != Enums.MinionType.DEMON:
		return 0
	return mini(_fiendish_pact_pending, mc.essence_cost)

func _consume_fiendish_pact_discount() -> void:
	if _fiendish_pact_pending <= 0:
		return
	_fiendish_pact_pending = 0
	for inst in player_hand:
		if inst == null or inst.card_data == null:
			continue
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).minion_type == Enums.MinionType.DEMON:
			inst.cost_delta = 0

func _spell_dmg(minion: MinionInstance, amount: int, info: Dictionary = {}) -> void:
	var total := amount + _player_spell_damage_bonus
	if info.is_empty():
		info = CombatManager.make_damage_info(total, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE)
	else:
		info = info.duplicate()
		info["amount"] = total
	combat_manager.apply_damage_to_minion(minion, info)

func _summon_token(card_id: String, owner: String, token_atk: int = 0, token_hp: int = 0, token_shield: int = 0) -> void:
	var base := CardDatabase.get_card(card_id)
	if base == null or not (base is MinionCardData):
		return
	var board := player_board if owner == "player" else enemy_board
	var slots := player_slots if owner == "player" else enemy_slots
	# Find an empty slot
	var slot: BoardSlot = null
	for s in slots:
		if s.is_empty():
			slot = s
			break
	if slot == null:
		return  # board full
	# Duplicate card data to override stats without corrupting the original
	var mc := (base as MinionCardData).duplicate() as MinionCardData
	if token_atk > 0:    mc.atk        = token_atk
	if token_hp > 0:     mc.health     = token_hp
	if token_shield > 0: mc.shield_max = token_shield
	var instance := MinionInstance.create(mc, owner)
	board.append(instance)
	slot.place_minion(instance)
	if trigger_manager != null:
		var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" \
			else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
		var ctx := EventContext.make(event, owner)
		ctx.minion = instance
		ctx.card   = mc
		trigger_manager.fire(ctx)

func _corrupt_minion(target: MinionInstance) -> void:
	BuffSystem.apply(target, Enums.BuffType.CORRUPTION, 100, "corruption", false, false)

func _apply_void_mark(amount: int) -> void:
	enemy_void_marks += amount

## Seris — mirrors CombatScene._gain_flesh. No UI side effects in sim.
func _gain_flesh(amount: int = 1) -> void:
	if amount <= 0:
		return
	player_flesh = min(player_flesh + amount, player_flesh_max)

func _spend_flesh(amount: int) -> bool:
	if amount <= 0 or player_flesh < amount:
		return false
	player_flesh -= amount
	_on_flesh_spent(amount)
	return true

## Mirror of CombatScene._on_flesh_spent — Flesh Bond aura draws a card per spend.
func _on_flesh_spent(_amount: int) -> void:
	var has_flesh_bond := false
	for m in player_board:
		if "flesh_bond" in m.aura_tags:
			has_flesh_bond = true
			break
	if not has_flesh_bond:
		return
	_draw_player(1)

func _forge_counter_tick(amount: int = 1) -> bool:
	if amount <= 0:
		return false
	forge_counter += amount
	return forge_counter >= forge_counter_threshold

func _forge_counter_reset() -> void:
	forge_counter = 0

## Sim mirror of CombatScene._summon_forged_demon — summons + applies Abyssal Forge auras.
func _summon_forged_demon() -> void:
	_summon_token("forged_demon", "player")
	var forged: MinionInstance = null
	for i in range(player_board.size() - 1, -1, -1):
		var m: MinionInstance = player_board[i]
		if m.card_data.id == "forged_demon":
			forged = m
			break
	if forged != null and _has_talent("abyssal_forge"):
		if player_flesh >= 5 and _spend_flesh(5):
			forged.aura_tags = _FORGED_DEMON_AURAS.duplicate()
		else:
			var roll: String = _FORGED_DEMON_AURAS[randi() % _FORGED_DEMON_AURAS.size()]
			forged.aura_tags = [roll]

## Sim mirror of CombatScene._gain_forge_counter.
func _gain_forge_counter(amount: int = 1) -> bool:
	if amount <= 0 or not _has_talent("soul_forge"):
		return false
	var summoned := false
	while amount > 0:
		var step := mini(amount, forge_counter_threshold)
		amount -= step
		if _forge_counter_tick(step):
			_summon_forged_demon()
			_forge_counter_reset()
			summoned = true
	return summoned

func _on_flesh_changed() -> void:
	pass

## Sim mirror of CombatScene._heal_minion — HP math only, no logging / UI.
func _heal_minion(minion: MinionInstance, amount: int) -> void:
	if minion == null or amount <= 0 or minion.current_health <= 0:
		return
	var hp_cap: int = minion.card_data.health + BuffSystem.sum_type(minion, Enums.BuffType.HP_BONUS)
	minion.current_health = mini(minion.current_health + amount, hp_cap)

## Sim mirror of CombatScene._heal_minion_full.
func _heal_minion_full(minion: MinionInstance) -> void:
	if minion == null or minion.current_health <= 0:
		return
	var hp_cap: int = minion.card_data.health + BuffSystem.sum_type(minion, Enums.BuffType.HP_BONUS)
	minion.current_health = hp_cap

## Sim mirror of CombatScene._sacrifice_minion. Sacrifice is NOT death — fires ON LEAVE
## and ON_*_MINION_SACRIFICED but NOT ON_*_MINION_DIED.
func _sacrifice_minion(minion: MinionInstance) -> void:
	if minion == null:
		return
	# Step 1 — declarative ON LEAVE steps.
	var card_data := minion.card_data as MinionCardData
	if card_data != null and not card_data.on_leave_effect_steps.is_empty():
		var leave_ctx := EffectContext.make(self, minion.owner)
		leave_ctx.source         = minion
		leave_ctx.source_card_id = card_data.id
		EffectResolver.run(card_data.on_leave_effect_steps, leave_ctx)
	# Step 2 — corruption removal still fires.
	if trigger_manager != null:
		var pre_corruption: int = BuffSystem.count_type(minion, Enums.BuffType.CORRUPTION)
		if pre_corruption > 0:
			var rm_ctx := EventContext.make(Enums.TriggerEvent.ON_CORRUPTION_REMOVED, minion.owner)
			rm_ctx.minion = minion
			rm_ctx.damage = pre_corruption
			trigger_manager.fire(rm_ctx)
		# Step 3 — sacrifice event.
		var sac_event := Enums.TriggerEvent.ON_PLAYER_MINION_SACRIFICED if minion.owner == "player" \
			else Enums.TriggerEvent.ON_ENEMY_MINION_SACRIFICED
		var sac_ctx := EventContext.make(sac_event, minion.owner)
		sac_ctx.minion = minion
		trigger_manager.fire(sac_ctx)
	# Step 4 — silent removal.
	player_board.erase(minion)
	enemy_board.erase(minion)
	for slot in player_slots:
		if slot.minion == minion:
			slot.minion = null
			break
	for slot in enemy_slots:
		if slot.minion == minion:
			slot.minion = null
			break

## Sim mirror of CombatScene._add_kill_stacks.
func _add_kill_stacks(minion: MinionInstance, count: int = 1) -> void:
	if minion == null or count <= 0:
		return
	minion.kill_stacks += count
	if _has_talent("flesh_infusion"):
		BuffSystem.apply(minion, Enums.BuffType.ATK_BONUS, 100 * count, "grafted_constitution", false, false)
		BuffSystem.apply_hp_gain(minion, 100 * count, "grafted_constitution", true)
	if _has_talent("predatory_surge") and minion.kill_stacks >= 3 \
			and not BuffSystem.has_type(minion, Enums.BuffType.GRANT_SIPHON):
		BuffSystem.apply(minion, Enums.BuffType.GRANT_SIPHON, 1, "predatory_surge", false, false)

func _on_forge_changed() -> void:
	pass

## Seris — mirror of CombatScene._on_demon_sacrificed. Same mechanics, no UI/log.
const _FORGED_DEMON_AURAS: Array[String] = ["void_growth", "void_pulse", "flesh_bond"]
func _on_demon_sacrificed(minion: MinionInstance, _source_tag: String) -> void:
	if minion == null or minion.owner != "player":
		return
	if not (minion.card_data is MinionCardData):
		return
	if (minion.card_data as MinionCardData).minion_type != Enums.MinionType.DEMON:
		return
	if _has_talent("fiend_offering") and "grafted_fiend" in (minion.card_data as MinionCardData).minion_tags:
		if _spend_flesh(2):
			_summon_token("lesser_demon", "player")
	if not _has_talent("soul_forge"):
		return
	if _forge_counter_tick(1):
		_summon_forged_demon()
		_forge_counter_reset()

## Seris — mirror of CombatScene._pre_player_spell_cast. Computes the Void
## Amplification damage bonus from friendly-Demon Corruption stacks.
var _spell_cast_depth: int = 0
var _double_cast_in_progress: bool = false
func _pre_player_spell_cast(_spell: SpellCardData) -> void:
	_spell_cast_depth += 1
	if _spell_cast_depth > 1:
		return
	if _has_talent("void_amplification"):
		var total_stacks: int = 0
		for m in player_board:
			if (m.card_data as MinionCardData).minion_type == Enums.MinionType.DEMON:
				total_stacks += BuffSystem.count_type(m, Enums.BuffType.CORRUPTION)
		_player_spell_damage_bonus = total_stacks * 50
	else:
		_player_spell_damage_bonus = 0

## Seris — mirror of CombatScene._post_player_spell_cast. Handles Void Resonance
## double-cast at the outermost cast level only. No VFX side effects in sim.
func _post_player_spell_cast(spell: SpellCardData, target) -> void:
	if _spell_cast_depth == 1 \
			and _has_talent("void_resonance_seris") \
			and player_flesh >= 5 \
			and not _double_cast_in_progress:
		_double_cast_in_progress = true
		if _spend_flesh(5):
			var target_alive: bool = target == null or (target is MinionInstance and (target as MinionInstance).current_health > 0)
			if target_alive:
				_sim_resolve_spell(spell, target)
		_double_cast_in_progress = false
	_spell_cast_depth = maxi(0, _spell_cast_depth - 1)
	if _spell_cast_depth == 0:
		_player_spell_damage_bonus = 0

## Sim-local re-resolve helper — runs the spell's effect steps a second time
## for Void Resonance. Mirrors SimPlayerAgent._resolve_spell's effect-step path.
func _sim_resolve_spell(spell: SpellCardData, target) -> void:
	if spell.effect_steps.is_empty():
		return
	var ctx := EffectContext.make(self, "player")
	ctx.chosen_target = target
	ctx.source_card_id = spell.id
	EffectResolver.run(spell.effect_steps, ctx)

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

## Seris — Soul Forge activated-ability mirror. Called by SerisPlayerProfile.
## Same checks and effects as CombatScene._soul_forge_activate: spend 3 Flesh,
## summon Grafted Fiend. Returns true if the summon attempt was made (Flesh spent).
func _soul_forge_activate() -> bool:
	if not _has_talent("soul_forge"):
		return false
	if player_flesh < 3:
		return false
	# Check for empty slot before spending — active uses should not waste Flesh
	var has_slot := false
	for slot in player_slots:
		if slot.minion == null:
			has_slot = true
			break
	if not has_slot:
		return false
	if not _spend_flesh(3):
		return false
	_summon_token("grafted_fiend", "player")
	_debug_soul_forge_fires += 1
	return true

## Seris — Corrupt Flesh activated-ability mirror. Targeted: caller selects
## which friendly Demon to corrupt. 1/turn flag tracked here. Returns true if
## Corruption was applied.
var _seris_corrupt_used_this_turn: bool = false
func _seris_corrupt_activate(target: MinionInstance) -> bool:
	if not _has_talent("corrupt_flesh"):
		return false
	if _seris_corrupt_used_this_turn:
		return false
	if player_flesh < 1:
		return false
	if target == null or target.owner != "player":
		return false
	if (target.card_data as MinionCardData).minion_type != Enums.MinionType.DEMON:
		return false
	if not _spend_flesh(1):
		return false
	var stacks: int = 2 if "grafted_fiend" in (target.card_data as MinionCardData).minion_tags else 1
	for _i in stacks:
		BuffSystem.apply(target, Enums.BuffType.CORRUPTION, 100, "corrupt_flesh", false, false)
	_seris_corrupt_used_this_turn = true
	_debug_corrupt_flesh_fires += 1
	return true

## Seris — reset the Corrupt Flesh 1/turn flag at player turn start.
## Called by the corrupt_flesh registry trigger via CombatHandlers.on_turn_start_corrupt_flesh_reset.
func _seris_corrupt_reset_turn() -> void:
	_seris_corrupt_used_this_turn = false

## Seris — mirror of CombatScene._try_save_from_death. Same rules, no UI/log side effects.
func _try_save_from_death(minion: MinionInstance) -> bool:
	if minion == null or minion.owner != "player":
		return false
	if _has_talent("deathless_flesh") \
			and minion.card_data is MinionCardData \
			and "grafted_fiend" in (minion.card_data as MinionCardData).minion_tags \
			and player_flesh >= 2:
		_spend_flesh(2)
		minion.current_health = 50
		return true
	return false

## is_minion_emitted: when true, the emitted DamageInfo carries MINION source instead
## of SPELL — used by talent paths (void_manifestation, piercing_void) that retag a
## minion attack/effect into a Void Bolt. Default false preserves spell-cast and
## triggered-passive semantics. Mirrors CombatScene._deal_void_bolt_damage.
func _deal_void_bolt_damage(base_damage: int, _source_minion: MinionInstance = null, _from_rune: bool = false, is_minion_emitted: bool = false) -> void:
	var bonus: int = enemy_void_marks * void_mark_damage_per_stack
	var total: int = base_damage + bonus
	# Determine base source label
	var base_source: String = _pending_dmg_source
	if base_source.is_empty():
		base_source = "void_rune" if _from_rune else "void_bolt_spell"
	_pending_dmg_source = base_source  # pass to _on_hero_damaged for total hit
	# Split log: base damage + mark bonus separately
	if dmg_log_enabled:
		dmg_log.append({turn = _current_turn, amount = base_damage, source = base_source})
		if bonus > 0:
			dmg_log.append({turn = _current_turn, amount = bonus, source = "void_mark"})
		_pending_dmg_source = "__logged__"  # signal _on_hero_damaged to skip logging
	var src: Enums.DamageSource = Enums.DamageSource.MINION if is_minion_emitted else Enums.DamageSource.SPELL
	combat_manager.apply_hero_damage("enemy",
			CombatManager.make_damage_info(total, src, Enums.DamageSchool.VOID_BOLT, _source_minion, base_source))
	_void_bolt_total_dmg += total

func _deal_enemy_void_bolt_damage(base_damage: int, _source_minion: MinionInstance = null, is_minion_emitted: bool = false) -> void:
	var base_source: String = _pending_dmg_source
	if base_source.is_empty():
		base_source = "enemy_void_bolt"
	_pending_dmg_source = base_source
	if dmg_log_enabled:
		dmg_log.append({turn = _current_turn, amount = base_damage, source = base_source})
		_pending_dmg_source = "__logged__"
	var src: Enums.DamageSource = Enums.DamageSource.MINION if is_minion_emitted else Enums.DamageSource.SPELL
	combat_manager.apply_hero_damage("player",
			CombatManager.make_damage_info(base_damage, src, Enums.DamageSchool.VOID_BOLT, _source_minion, base_source))

func _void_mark_damage_per_stack() -> int:
	return void_mark_damage_per_stack

var debug_log_enabled: bool = false

func _log(_msg: Variant, _type: int = 0) -> void:
	if debug_log_enabled:
		print(_msg)

func _refresh_slot_for(_target) -> void:
	pass  # no UI

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

func _opponent_of(owner: String) -> String:
	return "enemy" if owner == "player" else "player"

func _friendly_deck(owner: String) -> Array:
	return player_deck if owner == "player" else enemy_deck

func _add_to_owner_hand(owner: String, inst: CardInstance) -> void:
	if owner == "player":
		turn_manager.add_instance_to_hand(inst)
	else:
		if enemy_hand.size() < 10:
			enemy_hand.append(inst)

func _friendly_slots(owner: String) -> Array:
	return player_slots if owner == "player" else enemy_slots

func _friendly_traps(owner: String) -> Array:
	return active_traps if owner == "player" else enemy_active_traps

## Return the unified card graveyard belonging to the given owner. Mirror of CombatScene._friendly_graveyard.
func _friendly_graveyard(owner: String) -> Array:
	return player_graveyard if owner == "player" else enemy_graveyard

func _opponent_traps(owner: String) -> Array:
	return _friendly_traps(_opponent_of(owner))

func _update_trap_display_for(_owner: String) -> void:
	pass  # no UI in headless sim

func _find_random_enemy_minion() -> MinionInstance:
	return _find_random_minion(enemy_board)

func _find_random_minion(board: Array) -> MinionInstance:
	if board.is_empty():
		return null
	return board[randi() % board.size()]

func _refresh_dominion_aura(active: bool, amount: int = 100) -> void:
	for m in player_board:
		if (m as MinionInstance).card_data.minion_type == Enums.MinionType.DEMON:
			if active:
				BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, amount, "dominion_rune", false, false)
			else:
				BuffSystem.remove_source(m, "dominion_rune")

func _find_last_non_echo_rune() -> TrapCardData:
	for i in range(active_traps.size() - 1, -1, -1):
		var t := active_traps[i] as TrapCardData
		if t.is_rune and t.id != "echo_rune":
			return t
	return null

func _resolve_void_devourer_sacrifice(_devourer: MinionInstance, _owner: String) -> void:
	pass  # complex effect — not simulated

func _remove_rune_aura(rune: TrapCardData, owner: String = "player") -> void:
	for i in _rune_aura_handlers.size():
		if _rune_aura_handlers[i].rune_id == rune.id:
			for entry in _rune_aura_handlers[i].entries:
				trigger_manager.unregister(entry.event, entry.handler)
			_rune_aura_handlers.remove_at(i)
			break
	if not rune.aura_on_remove_steps.is_empty():
		var ctx := EffectContext.make(self, owner)
		EffectResolver.run(rune.aura_on_remove_steps, ctx)

func _unregister_env_rituals() -> void:
	for h in _env_ritual_handlers:
		trigger_manager.unregister(Enums.TriggerEvent.ON_RUNE_PLACED, h)
		trigger_manager.unregister(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, h)
	_env_ritual_handlers.clear()

func _update_trap_display() -> void:
	pass  # no UI

func _update_environment_display() -> void:
	pass  # no UI

func _rune_aura_multiplier() -> int:
	return rune_aura_multiplier

func _minion_has_tag(minion: MinionInstance, tag: String) -> bool:
	if minion.card_data is MinionCardData:
		return tag in (minion.card_data as MinionCardData).minion_tags
	return false

func _has_talent(talent_id: String) -> bool:
	return talent_id in talents

func _resolve_hardcoded(hardcoded_id: String, ctx: EffectContext) -> void:
	_hardcoded.resolve(hardcoded_id, ctx)

# ---------------------------------------------------------------------------
# Rune / trap / ritual / environment infrastructure
# ---------------------------------------------------------------------------

## Register persistent aura handlers for a newly placed rune.
func _apply_rune_aura(rune: TrapCardData, owner: String = "player") -> void:
	var entries: Array = []
	if rune.aura_trigger >= 0 and not rune.aura_effect_steps.is_empty():
		# Mirror trigger for enemy side (e.g. ON_PLAYER_MINION_SUMMONED → ON_ENEMY_MINION_SUMMONED)
		var trigger: int = rune.aura_trigger if owner == "player" else Enums.mirror_trigger(rune.aura_trigger as Enums.TriggerEvent)
		var h := func(event_ctx: EventContext):
			var ctx := EffectContext.make(self, owner)
			ctx.trigger_minion = event_ctx.minion
			ctx.from_rune = true
			ctx.source_rune = rune
			EffectResolver.run(rune.aura_effect_steps, ctx)
		trigger_manager.register(trigger, h, 20)
		entries.append({event = trigger, handler = h})
		if rune.aura_extra_trigger >= 0:
			var extra_trigger: int = rune.aura_extra_trigger if owner == "player" else Enums.mirror_trigger(rune.aura_extra_trigger as Enums.TriggerEvent)
			trigger_manager.register(extra_trigger, h, 20)
			entries.append({event = extra_trigger, handler = h})
	if rune.aura_secondary_trigger >= 0 and not rune.aura_secondary_steps.is_empty():
		var sec_trigger: int = rune.aura_secondary_trigger if owner == "player" else Enums.mirror_trigger(rune.aura_secondary_trigger as Enums.TriggerEvent)
		var h2 := func(event_ctx: EventContext):
			var ctx := EffectContext.make(self, owner)
			ctx.trigger_minion = event_ctx.minion
			ctx.source_rune = rune
			EffectResolver.run(rune.aura_secondary_steps, ctx)
		trigger_manager.register(sec_trigger, h2, 20)
		entries.append({event = sec_trigger, handler = h2})
	if not rune.aura_on_place_steps.is_empty():
		var ctx := EffectContext.make(self, owner)
		EffectResolver.run(rune.aura_on_place_steps, ctx)
	if not entries.is_empty():
		_rune_aura_handlers.append({rune_id = rune.id, entries = entries})

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

## Fire matching non-rune traps for the given trigger event (both player and enemy).
func _check_and_fire_traps(trigger: int, triggering_minion: MinionInstance = null) -> void:
	# Player traps
	if not _player_traps_blocked:
		for trap in active_traps.duplicate():
			if trap.is_rune:
				continue
			if trap.trigger != trigger:
				continue
			var ctx := EffectContext.make(self, "player")
			ctx.trigger_minion = triggering_minion
			EffectResolver.run(trap.effect_steps, ctx)
			if not trap.reusable:
				active_traps.erase(trap)
	# Enemy traps (mirror trigger: player events → enemy equivalents)
	var enemy_trigger: int = Enums.mirror_trigger(trigger as Enums.TriggerEvent)
	for trap in enemy_active_traps.duplicate():
		if trap.is_rune:
			continue
		if trap.trigger != enemy_trigger:
			continue
		var ctx := EffectContext.make(self, "enemy")
		ctx.trigger_minion = triggering_minion
		EffectResolver.run(trap.effect_steps, ctx)
		if not trap.reusable:
			enemy_active_traps.erase(trap)

## Returns true if the rune board satisfies the ritual's required rune types.
func _runes_satisfy(runes: Array, required: Array[int]) -> bool:
	var available: Array[int] = []
	var wildcards: int = 0
	for r in runes:
		var trap := r as TrapCardData
		if trap.is_wildcard_rune:
			wildcards += 1
		else:
			available.append(trap.rune_type)
	var remaining_wildcards := wildcards
	for req in required:
		if req in available:
			available.erase(req)
		elif remaining_wildcards > 0:
			remaining_wildcards -= 1
		else:
			return false
	return true

## Consume the required runes and cast the ritual effect.
## Exact matches consumed first; wildcard runes fill remaining gaps.
func _fire_ritual(ritual: RitualData) -> void:
	_player_ritual_count += 1
	for req in ritual.required_runes:
		var consumed := false
		for i in active_traps.size():
			if active_traps[i].is_rune and not (active_traps[i] as TrapCardData).is_wildcard_rune and active_traps[i].rune_type == req:
				_remove_rune_aura(active_traps[i])
				active_traps.remove_at(i)
				consumed = true
				break
		if not consumed:
			for i in active_traps.size():
				if active_traps[i].is_rune and (active_traps[i] as TrapCardData).is_wildcard_rune:
					_remove_rune_aura(active_traps[i])
					active_traps.remove_at(i)
					break
	var ritual_ctx := EffectContext.make(self, "player")
	EffectResolver.run(ritual.effect_steps, ritual_ctx)
	# Fire ON_RITUAL_FIRED so registry-based handlers (ritual_surge) can respond
	if trigger_manager:
		var fired_ctx := EventContext.make(Enums.TriggerEvent.ON_RITUAL_FIRED, "player")
		trigger_manager.fire(fired_ctx)

## Draw a random Rune card from the player's deck into hand, applying -1 cost via cost_delta.
func _draw_rune_from_deck() -> void:
	var runes_in_deck: Array[CardInstance] = []
	for inst in player_deck:
		if inst.card_data is TrapCardData and (inst.card_data as TrapCardData).is_rune:
			runes_in_deck.append(inst)
	if runes_in_deck.is_empty():
		return
	var chosen: CardInstance = runes_in_deck[randi() % runes_in_deck.size()]
	player_deck.erase(chosen)
	if player_hand.size() < PLAYER_HAND_MAX:
		player_hand.append(chosen)
	chosen.cost_delta = -1

## Summon a Void Imp token on the player board (used by ritual_surge talent).
func _summon_void_imp() -> void:
	_summon_token("void_imp", "player", 0, 0, 0)

## Reference to the CombatHandlers instance — set by SimTriggerSetup for env rituals.
var _handlers_ref: CombatHandlers = null

## Aliases for duck-typing compatibility with CombatScene — used by Act 3 AI profiles.
var _active_enemy_passives: Array[String]:
	get: return enemy_passives
var _handlers: CombatHandlers:
	get: return _handlers_ref

## Pending mana drain flag (Void Rift Lord). SimState applies at player turn start.
var _void_mana_drain_pending: bool = false

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
		var card := CardDatabase.get_card(id)
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
	imp_evolution_used_this_turn = false
	for inst in player_hand:
		inst.cost_delta = 0
	_fiendish_pact_pending = 0
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
