## PhaseTransition.gd
## Logic for the F15 Abyss Sovereign two-phase boss transition. When the
## Sovereign's P1 HP drops to 0, this helper resets the fight to Phase 2:
## HP refill, both boards wiped, statuses cleared, passives swapped, deck
## replaced. Shared by live (CombatScene) and sim (SimState) via duck-typing.
##
## Usage:
##   PhaseTransition.attempt(scene, ...)  # returns true if transition fired
##   Hook this before the "enemy defeated" path in hero-damage logic. If it
##   returns true, skip the victory handler for this damage event.
class_name PhaseTransition
extends RefCounted

# ---------------------------------------------------------------------------
# Phase 2 configuration — kept here so live and sim stay in lockstep.
# ---------------------------------------------------------------------------

const SOVEREIGN_P2_HP: int = 3000
const SOVEREIGN_P2_DECK_ID: String = "f15_p2"
const SOVEREIGN_P2_PROFILE: String = "abyss_sovereign_p2"
const SOVEREIGN_P1_PASSIVES: Array[String] = ["void_might", "abyssal_mandate", "dark_channeling"]
const SOVEREIGN_P2_PASSIVES: Array[String] = ["void_might", "abyss_awakened"]

## Returns true if the scene is the Abyss Sovereign in Phase 1 and the
## transition should fire instead of a victory.
static func should_transition(scene: Object) -> bool:
	if scene.get("_sovereign_phase") != 1:
		return false
	# Guard: encounter must actually be Abyss Sovereign. We use ai_profile
	# to detect this without coupling to GameManager.
	var profile_id: String = _read_ai_profile(scene)
	return profile_id == "abyss_sovereign"

## Run the P1 → P2 transition. Returns true if it fired (caller should skip
## the normal enemy-defeated flow for this damage event).
static func attempt(scene: Object) -> bool:
	if not should_transition(scene):
		return false
	_do_transition(scene)
	return true

# ---------------------------------------------------------------------------
# Core transition — mutates state atomically (no await, no animations).
# Animations / VFX are the caller's job via the _play_phase2_vfx hook.
# ---------------------------------------------------------------------------

static func _do_transition(scene: Object) -> void:
	scene._sovereign_phase = 2
	scene._sovereign_transition_turn = _current_turn_number(scene)

	# 1. Refill Sovereign HP to P2 max.
	_set_enemy_hp(scene, SOVEREIGN_P2_HP, SOVEREIGN_P2_HP)

	# 2. Silently wipe both boards. We do NOT fire death triggers — this is
	#    a banish, not a kill (prevents cascading passives / player buffs).
	_wipe_boards_silently(scene)

	# 3. Clear environments, traps, void marks, per-turn/persistent auras.
	_clear_combat_state(scene)

	# 4. Clear the mandate bookkeeping — P2 has no abyssal_mandate.
	scene.last_player_growth = ""

	# 5. Enemy resources inherit current values (per Q1 option b). Nothing to do.

	# 6. Swap passives (unregister P1, register P2).
	_swap_passives(scene)

	# 7. Swap enemy deck + AI profile + opening hand of 5.
	_swap_deck_and_profile(scene)

	# 8. VFX hook — stubbed in live CombatScene, no-op in sim.
	if scene.has_method("_play_phase2_vfx"):
		scene._play_phase2_vfx()

# ---------------------------------------------------------------------------
# Helpers — duck-typed across CombatScene and SimState.
# ---------------------------------------------------------------------------

static func _current_turn_number(scene: Object) -> int:
	# Sim: _current_turn on SimState. Live: turn_manager.turn_number.
	var t = scene.get("_current_turn")
	if t != null:
		return int(t)
	var tm = scene.get("turn_manager")
	if tm != null and tm.get("turn_number") != null:
		return int(tm.turn_number)
	return 0

static func _read_ai_profile(scene: Object) -> String:
	# Live: scene.enemy_ai.ai_profile. Sim: scene.enemy_ai_profile (string).
	var ai = scene.get("enemy_ai")
	if ai != null and ai.get("ai_profile") != null:
		return ai.ai_profile as String
	var direct = scene.get("enemy_ai_profile")
	if direct != null:
		return direct as String
	return ""

static func _set_enemy_hp(scene: Object, hp: int, hp_max: int) -> void:
	scene.enemy_hp = hp
	if scene.get("enemy_hp_max") != null:
		scene.enemy_hp_max = hp_max

static func _wipe_boards_silently(scene: Object) -> void:
	# Clear minion arrays and any slot references on both sides.
	for side in ["player_board", "enemy_board"]:
		var board: Array = scene.get(side)
		if board != null:
			board.clear()
	# Slots: live uses player_slots/enemy_slots; sim uses the same names.
	for side in ["player_slots", "enemy_slots"]:
		var slots = scene.get(side)
		if slots != null and slots is Array:
			for slot in slots:
				if slot != null and slot.get("minion") != null:
					slot.minion = null

static func _clear_combat_state(scene: Object) -> void:
	# Environments (both sides)
	if scene.get("active_environment") != null:
		scene.active_environment = null
	var ai = scene.get("enemy_ai")
	if ai != null:
		if ai.get("active_environment") != null:
			ai.active_environment = null
		if ai.get("active_traps") != null:
			(ai.active_traps as Array).clear()
		if ai.get("spell_cost_aura") != null:
			ai.spell_cost_aura = 0
		if ai.get("minion_essence_cost_aura") != null:
			ai.minion_essence_cost_aura = 0
		if ai.get("spell_cost_penalty") != null:
			ai.spell_cost_penalty = 0
	# Player-side traps (live: scene.active_traps; sim: scene.active_traps)
	if scene.get("active_traps") != null:
		(scene.active_traps as Array).clear()
	# Void marks on enemy hero (cosmetic but resets cleanly)
	if scene.get("enemy_void_marks") != null:
		scene.enemy_void_marks = 0

static func _swap_passives(scene: Object) -> void:
	var tm: TriggerManager = scene.get("trigger_manager")
	var h: CombatHandlers  = scene.get("_handlers_ref") if scene.get("_handlers_ref") != null else scene.get("_handlers")
	if tm == null or h == null:
		push_warning("PhaseTransition: missing trigger_manager or handlers — cannot swap passives")
		return
	for p in SOVEREIGN_P1_PASSIVES:
		CombatSetup.unapply_passive(p, tm, h)
	for p in SOVEREIGN_P2_PASSIVES:
		CombatSetup.apply_passive(p, tm, h, scene)
	# Keep scene.enemy_passives in sync (for any other systems that read it).
	var passives = scene.get("enemy_passives")
	if passives != null and passives is Array:
		passives.clear()
		passives.append_array(SOVEREIGN_P2_PASSIVES)

static func _swap_deck_and_profile(scene: Object) -> void:
	var cards: Array[String] = EncounterDecks.get_deck(SOVEREIGN_P2_DECK_ID)
	# Live (CombatScene) path — EnemyAI has setup_deck + ai_profile setter.
	var ai = scene.get("enemy_ai")
	if ai != null and ai.has_method("setup_deck"):
		ai.setup_deck(cards)
		ai.ai_profile = SOVEREIGN_P2_PROFILE
		return
	# Sim (SimState) path — rebuild deck on SimState, swap profile via factory.
	if scene.has_method("setup_enemy_deck"):
		scene.setup_enemy_deck(cards)
	scene.enemy_ai_profile = SOVEREIGN_P2_PROFILE
	var factory: Callable = scene.get("_e_profile_factory")
	if factory.is_valid():
		scene._e_profile = factory.call(SOVEREIGN_P2_PROFILE)
