## SimTriggerSetup.gd
## Wires TriggerManager handlers for headless simulation using CombatHandlers.
## Registration only — all logic lives in CombatHandlers.
class_name SimTriggerSetup
extends RefCounted

func setup(sim: SimState) -> void:
	var h := CombatHandlers.new()
	h.setup(sim)

	var tm := TriggerManager.new()
	sim.trigger_manager = tm

	# ── ON_PLAYER_TURN_START ─────────────────────────────────────────────
	tm.register(Enums.TriggerEvent.ON_PLAYER_TURN_START, h.on_minion_turn_start_passives, 21)

	# ── ON_PLAYER_MINION_SUMMONED — talents ──────────────────────────────
	if "swarm_discipline" in sim.talents:
		tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, h.on_summon_swarm_discipline,  20)
	if "abyssal_legion" in sim.talents:
		tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, h.on_summon_abyssal_legion,    21)
	if "piercing_void" in sim.talents:
		tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, h.on_summon_piercing_void,     23)
	if "imp_evolution" in sim.talents:
		tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, h.on_summon_imp_evolution,     24)
	if "imp_warband" in sim.talents:
		tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, h.on_summon_imp_warband,       25)

	# ── ON_PLAYER_MINION_DIED ────────────────────────────────────────────
	tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED, h.on_minion_died_death_effect,        5)
	if "death_bolt" in sim.talents:
		tm.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED, h.on_player_minion_died_death_bolt, 10)

	# ── ON_ENEMY_MINION_SUMMONED ─────────────────────────────────────────
	tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, h.on_enemy_summon_rogue_imp_elder, 7)

	# ── ON_ENEMY_MINION_DIED ─────────────────────────────────────────────
	tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_DIED, h.on_minion_died_death_effect, 5)

	# ── ON_PLAYER_CARD_DRAWN ─────────────────────────────────────────────
	if "void_echo" in sim.talents:
		tm.register(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, h.on_card_drawn_void_echo, 0)

	# ── Enemy encounter passives ─────────────────────────────────────────
	if "feral_instinct" in sim.enemy_passives:
		tm.register(Enums.TriggerEvent.ON_ENEMY_TURN_START,      h.on_enemy_turn_feral_instinct_reset, 5)
		tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, h.on_enemy_summon_feral_instinct,     1)
		tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     h.on_enemy_died_feral_instinct,       4)
	if "pack_instinct" in sim.enemy_passives:
		tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, h.on_board_changed_pack_instinct,     9)
		tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     h.on_board_changed_pack_instinct,     3)
	if "corrupted_death" in sim.enemy_passives:
		tm.register(Enums.TriggerEvent.ON_ENEMY_MINION_DIED,     h.on_enemy_died_corrupted_death,      6)
	if "ancient_frenzy" in sim.enemy_passives:
		sim.enemy_spell_cost_discounts["pack_frenzy"] = 1
