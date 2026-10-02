## PhaseTransition.gd
## Logic for the F15 Abyss Sovereign two-phase boss transition. When the
## Sovereign's P1 HP drops to 0, this helper resets the fight to Phase 2:
## HP refill, both boards wiped, statuses cleared, passives swapped, deck
## replaced. One body for every shell (it runs inside CombatState).
##
## Usage:
##   PhaseTransition.attempt(state)  # returns true if transition fired
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
## champion_abyss_sovereign is registered on the base encounter (P1 list) so
## the card-played counter ticks from the first turn. The handler itself gates
## the actual summon on _sovereign_phase == 2.
const SOVEREIGN_P1_PASSIVES: Array[String] = ["void_might", "abyssal_mandate", "dark_channeling", "champion_abyss_sovereign"]
const SOVEREIGN_P2_PASSIVES: Array[String] = ["void_might", "abyss_awakened", "champion_abyss_sovereign"]

## Returns true if the fight is the Abyss Sovereign in Phase 1 and the
## transition should fire instead of a victory.
static func should_transition(st: CombatState) -> bool:
	return st._sovereign_phase == 1 and st.enemy_profile_id == "abyss_sovereign"

## Run the P1 → P2 transition. Returns true if it fired (caller should skip
## the normal enemy-defeated flow for this damage event).
static func attempt(st: CombatState) -> bool:
	if not should_transition(st):
		return false
	_do_transition(st)
	return true

# ---------------------------------------------------------------------------
# Core transition — mutates state atomically (no await, no animations). The
# presenter shows it from the PHASE_TRANSITION journal event.
# ---------------------------------------------------------------------------

static func _do_transition(st: CombatState) -> void:
	st._sovereign_phase = 2
	st._sovereign_transition_turn = st.turn_number

	# 1. Refill Sovereign HP to P2 max.
	st.enemy_hp = SOVEREIGN_P2_HP
	st.enemy_hp_max = SOVEREIGN_P2_HP

	# 2. Silently wipe both boards. We do NOT fire death triggers — this is
	#    a banish, not a kill (prevents cascading passives / player buffs).
	_wipe_boards_silently(st)

	# 3. Clear environments, traps, void marks, per-turn/persistent auras.
	_clear_combat_state(st)

	# 4. Clear the mandate bookkeeping — P2 has no abyssal_mandate.
	st.last_player_growth = ""

	# 5. Enemy resources inherit current values (per Q1 option b). Nothing to do.

	# 6. Swap passives (unregister P1, register P2).
	_swap_passives(st)

	# 7. Swap enemy deck + opening hand of 5, then the AI profile (the shell
	#    rebuilds its enemy CombatProfile on enemy_profile_changed).
	st.setup_deck("enemy", EncounterDecks.get_deck(SOVEREIGN_P2_DECK_ID))
	st.enemy_profile_id = SOVEREIGN_P2_PROFILE
	st.enemy_profile_changed.emit(SOVEREIGN_P2_PROFILE)

	st._log("THE SOVEREIGN REAWAKENS — Phase 2 begins.", Enums.LogType.ENEMY)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _wipe_boards_silently(st: CombatState) -> void:
	st.player_board.clear()
	st.enemy_board.clear()
	# clear() journals SLOT_CHANGED, so the live slot views empty too.
	for slot: SlotState in st.player_slots + st.enemy_slots:
		if slot != null and slot.minion != null:
			slot.clear()

static func _clear_combat_state(st: CombatState) -> void:
	# Environments, traps and runes (both sides)
	st.active_environment = null
	st.enemy_active_environment = null
	st.active_traps.clear()
	st.enemy_active_traps.clear()
	# Enemy cost modifiers
	st.enemy_spell_cost_aura = 0
	st.enemy_minion_essence_cost_aura = 0
	st.enemy_spell_cost_penalty = 0
	# Void marks on enemy hero (cosmetic but resets cleanly)
	st.enemy_void_marks = 0

static func _swap_passives(st: CombatState) -> void:
	if st.trigger_manager == null or st._handlers == null:
		push_warning("PhaseTransition: missing trigger_manager or handlers — cannot swap passives")
		return
	for p in SOVEREIGN_P1_PASSIVES:
		CombatSetup.unapply_passive(p, st.trigger_manager, st._handlers)
	for p in SOVEREIGN_P2_PASSIVES:
		CombatSetup.apply_passive(p, st)
	st.enemy_passives.assign(SOVEREIGN_P2_PASSIVES)
