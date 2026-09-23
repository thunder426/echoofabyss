## SimRelicPolicy.gd
## When the sim's player uses its relics (LIVE_SIM_UNIFICATION_PLAN.md 2A.6).
## Decisions only — every activation is state.cmd_activate_relic, the same
## command the live relic bar issues. CombatSim calls these at fixed points of
## the player's turn; each fires at most one relic (one activation per turn).
class_name SimRelicPolicy
extends RefCounted

## Turn start: draw / imp / guardian relics fire on cooldown; else Dark Mirror.
static func start_of_turn(state: CombatState) -> void:
	var rt: RelicRuntime = state.relic_runtime
	for i in rt.relics.size():
		if not rt.can_activate(i):
			continue
		if rt.relics[i].data.effect_id in ["relic_draw_2", "relic_add_void_imp", "relic_summon_guardian"]:
			state.cmd_activate_relic(i)
			return
	if not rt.activated_this_turn:
		_try(state, "dark_mirror")

## After the play phase: Mana Shard when Mana was spent and a card in hand
## becomes castable with +2. Returns true if it fired (the caller replays).
static func mana_shard(state: CombatState) -> bool:
	var rt: RelicRuntime = state.relic_runtime
	var idx: int = rt.find_by_id("mana_shard")
	if idx < 0 or not rt.can_activate(idx):
		return false
	if state.player_mana >= state.player_mana_max:
		return false
	var mana_after: int = mini(state.player_mana + 2, state.player_mana_max)
	var has_castable := false
	for inst: CardInstance in state.player_hand:
		var cost: int = -1
		if inst.card_data is SpellCardData or inst.card_data is EnvironmentCardData:
			cost = inst.card_data.cost
		elif inst.card_data is TrapCardData:
			cost = inst.effective_cost()
		if cost >= 0 and cost <= mana_after and cost > state.player_mana:
			has_castable = true
			break
	if not has_castable:
		return false
	return state.cmd_activate_relic(idx).ok

## After the play phase: Void Lens when the enemy has minions to hit.
static func void_lens(state: CombatState) -> void:
	if not state.enemy_board.is_empty():
		_try(state, "void_lens")

## After the play phase: Blood Chalice on the highest-ATK enemy minion (held
## while the enemy board is empty).
static func blood_chalice(state: CombatState) -> void:
	var best: MinionInstance = null
	for m: MinionInstance in state.enemy_board:
		if best == null or m.effective_atk() > best.effective_atk():
			best = m
	if best != null:
		_try(state, "blood_chalice", best)

## After attacks: Bone Shield when the enemy board threatens lethal.
static func bone_shield(state: CombatState) -> void:
	var enemy_atk := 0
	for m: MinionInstance in state.enemy_board:
		enemy_atk += m.effective_atk()
	if enemy_atk >= state.player_hp:
		_try(state, "bone_shield")

static func _try(state: CombatState, relic_id: String, target = null) -> bool:
	var rt: RelicRuntime = state.relic_runtime
	var idx: int = rt.find_by_id(relic_id)
	if idx < 0 or not rt.can_activate(idx):
		return false
	return state.cmd_activate_relic(idx, target).ok
