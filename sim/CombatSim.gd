## CombatSim.gd
## Headless combat simulator for balance testing.
##
## Usage:
##   var sim := CombatSim.new()
##   var result := await sim.run(player_deck_ids, "feral_pack")
##   print(result)
##
## The runner is intentionally async-compatible: profile phases use
## "await agent.commit_*()" calls, but since the sim agents return values
## directly (no coroutines/signals), GDScript 4 resolves every await
## immediately — the entire run completes in one frame.
class_name CombatSim
extends RefCounted

# ---------------------------------------------------------------------------
# Profile registry — mirrors EnemyAI._PROFILES
# ---------------------------------------------------------------------------

const _ENEMY_PROFILES: Dictionary = {
	"default":              preload("res://enemies/ai/profiles/DefaultProfile.gd"),
	"feral_pack":           preload("res://enemies/ai/profiles/FeralPackProfile.gd"),
	"corrupted_brood":      preload("res://enemies/ai/profiles/CorruptedBroodProfile.gd"),
	"matriarch":            preload("res://enemies/ai/profiles/MatriarchProfile.gd"),
	"cultist_patrol":       preload("res://enemies/ai/profiles/CultistPatrolProfile.gd"),
	"void_ritualist":       preload("res://enemies/ai/profiles/VoidRitualistProfile.gd"),
	"corrupted_handler":    preload("res://enemies/ai/profiles/CorruptedHandlerProfile.gd"),
	"rift_stalker":         preload("res://enemies/ai/profiles/RiftStalkerProfile.gd"),
	"void_aberration":      preload("res://enemies/ai/profiles/VoidAberrationProfile.gd"),
	"void_herald":          preload("res://enemies/ai/profiles/VoidHeraldProfile.gd"),
	# Act 4 — Void Castle
	"void_scout":           preload("res://enemies/ai/profiles/VoidScoutProfile.gd"),
	"void_warband":         preload("res://enemies/ai/profiles/VoidWarbandProfile.gd"),
	"void_captain":         preload("res://enemies/ai/profiles/VoidCaptainProfile.gd"),
	"void_ritualist_prime": preload("res://enemies/ai/profiles/VoidRitualistPrimeProfile.gd"),
	"void_champion":        preload("res://enemies/ai/profiles/VoidChampionProfile.gd"),
	"abyss_sovereign":      preload("res://enemies/ai/profiles/AbyssSovereignProfile.gd"),
	# Scored variants
	"scored":               preload("res://enemies/ai/profiles/ScoredDefaultProfile.gd"),
	"scored_feral_pack":    preload("res://enemies/ai/profiles/ScoredFeralPackProfile.gd"),
	"scored_corrupted_brood": preload("res://enemies/ai/profiles/ScoredCorruptedBroodProfile.gd"),
	"scored_matriarch":     preload("res://enemies/ai/profiles/ScoredMatriarchProfile.gd"),
}

## Passive IDs active for each enemy profile — mirrors EnemyData.passives in the live game.
const _ENEMY_PASSIVES: Dictionary = {
	"feral_pack":           ["feral_instinct", "pack_instinct", "champion_rogue_imp_pack"],
	"corrupted_brood":      ["feral_instinct", "corrupted_death", "champion_corrupted_broodlings"],
	"matriarch":            ["feral_instinct", "ancient_frenzy", "champion_imp_matriarch"],
	"default":              [],
	"cultist_patrol":       ["feral_reinforcement", "corrupt_authority"],
	"void_ritualist":       ["feral_reinforcement", "ritual_sacrifice"],
	"corrupted_handler":    ["feral_reinforcement", "void_unraveling"],
	"rift_stalker":         ["void_rift", "void_empowerment"],
	"void_aberration":      ["void_rift", "void_detonation_passive"],
	"void_herald":          ["void_rift", "void_mastery"],
	# Act 4 — Void Castle
	"void_scout":           ["void_might", "void_precision"],
	"void_warband":         ["void_might", "spirit_conscription"],
	"void_captain":         ["void_might", "captain_orders"],
	"void_ritualist_prime": ["void_might", "dark_channeling"],
	"void_champion":        ["void_might", "champion_duel"],
	"abyss_sovereign":      ["void_might", "void_precision", "dark_channeling"],
	# Scored variants
	"scored":               [],
	"scored_feral_pack":    ["feral_instinct", "pack_instinct", "champion_rogue_imp_pack"],
	"scored_corrupted_brood": ["feral_instinct", "corrupted_death", "champion_corrupted_broodlings"],
	"scored_matriarch":     ["feral_instinct", "ancient_frenzy", "champion_imp_matriarch"],
}

const _PLAYER_PROFILES: Dictionary = {
	"default":    preload("res://enemies/ai/profiles/DefaultPlayerProfile.gd"),
	"spell_burn": preload("res://enemies/ai/profiles/SpellBurnPlayerProfile.gd"),
	"rune_tempo": preload("res://enemies/ai/profiles/RuneTempoPlayerProfile.gd"),
	"scored":     preload("res://enemies/ai/profiles/ScoredDefaultProfile.gd"),
}

## Maximum turns before declaring a draw — prevents infinite loops.
const MAX_TURNS := 60

# ---------------------------------------------------------------------------
# Run a single simulation
# ---------------------------------------------------------------------------

## Returns a Dictionary with keys:
##   winner         — "player", "enemy", or "draw"
##   turns          — number of full turn pairs completed
##   player_hp      — final player HP
##   enemy_hp       — final enemy HP
##   player_board   — number of minions on player board at end
##   enemy_board    — number of minions on enemy board at end
func run(
		player_deck_ids: Array[String],
		enemy_profile_id: String = "default",
		enemy_deck_ids: Array[String] = [],
		player_hp: int = 3000,
		enemy_hp:  int = 2000,
		player_talents: Array[String] = [],
		player_profile_id: String = "default",
		player_hero_passives: Array[String] = [],
		player_relic_ids: Array[String] = [],
		relic_bonus_charges: Dictionary = {}) -> Dictionary:

	var state := SimState.new()
	state.setup(player_deck_ids, enemy_deck_ids, player_hp, enemy_hp)
	state.enemy_hp_max = enemy_hp
	state.talents = player_talents
	state.hero_passives = player_hero_passives
	state.enemy_passives.assign(_ENEMY_PASSIVES.get(enemy_profile_id, []))

	# Build agents
	var p_agent := SimPlayerAgent.new()
	p_agent.setup(state)

	var e_agent := SimEnemyAgent.new()
	e_agent.setup(state)  # also sets state.enemy_ai = e_agent

	# Wire TriggerManager — must happen after agents are set up (enemy_ai duck-type ready)
	var trigger_setup := SimTriggerSetup.new()
	trigger_setup.setup(state)

	# Build profiles
	var p_profile_script = _PLAYER_PROFILES.get(player_profile_id, _PLAYER_PROFILES["default"])
	var p_profile: CombatProfile = p_profile_script.new()
	p_profile.setup(p_agent)
	p_profile.setup_resource_growth(state)

	var e_profile_script = _ENEMY_PROFILES.get(enemy_profile_id, _ENEMY_PROFILES["default"])
	var e_profile: CombatProfile = e_profile_script.new()
	e_profile.setup(e_agent)
	e_profile.setup_resource_growth(state)

	# Relic system
	var relic_rt: RelicRuntime = null
	var relic_fx: RelicEffects = null
	if not player_relic_ids.is_empty():
		relic_rt = RelicRuntime.new()
		relic_rt.setup(player_relic_ids, relic_bonus_charges)
		relic_fx = RelicEffects.new()
		relic_fx.setup(state)

	# Initialise resources (turn 1 starts at 1/1)
	state.player_essence_max = 1
	state.player_mana_max    = 1
	state.enemy_essence_max  = 1
	state.enemy_mana_max     = 1

	# Run the loop
	var turn := 0
	while state.winner.is_empty() and turn < MAX_TURNS:
		turn += 1

		# ── Player turn ──────────────────────────────────────────────────────
		state.begin_player_turn(turn)
		state._relic_hero_immune = false
		state._relic_cost_reduction = 0
		if relic_rt:
			relic_rt.on_turn_start()
			# Phase 1: Activate draw/imp relics at turn start (on cooldown)
			_try_relic_start_of_turn(relic_rt, relic_fx, state)
		await p_profile.play_phase()
		if not state.winner.is_empty(): break
		# Phase 2: Mana Shard — after play phase if mana spent and castable cards remain
		if relic_rt and not relic_rt.activated_this_turn:
			_try_relic_mana_shard(relic_rt, relic_fx, state, p_agent)
			# If mana shard fired, try playing more cards
			if relic_rt.activated_this_turn:
				await p_profile.play_phase()
				if not state.winner.is_empty(): break
		await p_profile.attack_phase()
		# Phase 3: Bone Shield — after attacks, if enemy threatens lethal
		if relic_rt and not relic_rt.activated_this_turn:
			_try_relic_bone_shield(relic_rt, relic_fx, state)
		state.end_player_turn()
		# Void Hourglass: extra player turn
		if state._relic_extra_turn:
			state._relic_extra_turn = false
			state.begin_player_turn(turn)
			state._relic_hero_immune = false
			state._relic_cost_reduction = 0
			await p_profile.play_phase()
			if not state.winner.is_empty(): break
			await p_profile.attack_phase()
			state.end_player_turn()
		if not state.winner.is_empty(): break

		# ── Enemy turn ───────────────────────────────────────────────────────
		state.begin_enemy_turn(turn)
		await e_profile.play_phase()
		if not state.winner.is_empty(): break
		await e_profile.attack_phase()
		state.end_enemy_turn()

	return {
		"winner":       state.winner if not state.winner.is_empty() else "draw",
		"turns":        turn,
		"player_hp":    state.player_hp,
		"enemy_hp":     state.enemy_hp,
		"player_board": state.player_board.size(),
		"enemy_board":  state.enemy_board.size(),
		"ritual_sacrifice_count": state._ritual_sacrifice_count,
		"detonation_count": state._detonation_count,
		"player_ritual_count": state._player_ritual_count,
		"spark_spawned_count": state._spark_spawned_count,
		"spark_transfer_count": state._spark_transfer_count,
		"champion_summon_count": state._champion_summon_count,
		"relic_activations": relic_rt.total_activations if relic_rt else 0,
	}

# ---------------------------------------------------------------------------
# Run N simulations and aggregate
# ---------------------------------------------------------------------------

## Run count simulations and return aggregate stats.
## Useful for win-rate estimation over a sample.
func run_many(
		count: int,
		player_deck_ids: Array[String],
		enemy_profile_id: String = "default",
		enemy_deck_ids: Array[String] = [],
		player_hp: int = 3000,
		enemy_hp:  int = 2000,
		player_talents: Array[String] = [],
		player_profile_id: String = "default",
		player_hero_passives: Array[String] = [],
		player_relic_ids: Array[String] = [],
		relic_bonus_charges: Dictionary = {}) -> Dictionary:

	var wins   := 0
	var losses := 0
	var draws  := 0
	var total_turns := 0
	var total_player_hp := 0
	var total_enemy_hp  := 0
	var total_ritual_sac := 0
	var total_detonation := 0
	var total_player_ritual := 0
	var total_spark_spawned := 0
	var total_spark_transfer := 0
	var total_relic_activations := 0
	var total_champion_summons := 0

	for _i in count:
		var r: Dictionary = await run(player_deck_ids, enemy_profile_id,
				enemy_deck_ids, player_hp, enemy_hp, player_talents, player_profile_id,
				player_hero_passives, player_relic_ids, relic_bonus_charges)
		match r["winner"]:
			"player": wins   += 1
			"enemy":  losses += 1
			_:        draws  += 1
		total_turns     += r["turns"]
		total_player_hp += r["player_hp"]
		total_enemy_hp  += r["enemy_hp"]
		total_ritual_sac += r.get("ritual_sacrifice_count", 0)
		total_detonation += r.get("detonation_count", 0)
		total_player_ritual += r.get("player_ritual_count", 0)
		total_spark_spawned += r.get("spark_spawned_count", 0)
		total_spark_transfer += r.get("spark_transfer_count", 0)
		total_relic_activations += r.get("relic_activations", 0)
		total_champion_summons += r.get("champion_summon_count", 0)

	return {
		"count":          count,
		"wins":           wins,
		"losses":         losses,
		"draws":          draws,
		"win_rate":       float(wins) / count,
		"avg_turns":      float(total_turns) / count,
		"avg_player_hp":  float(total_player_hp) / count,
		"avg_enemy_hp":   float(total_enemy_hp) / count,
		"avg_ritual_sac": float(total_ritual_sac) / count,
		"avg_detonation": float(total_detonation) / count,
		"avg_player_ritual": float(total_player_ritual) / count,
		"avg_spark_spawned": float(total_spark_spawned) / count,
		"avg_spark_transfer": float(total_spark_transfer) / count,
		"avg_relic_activations": float(total_relic_activations) / count,
		"avg_champion_summons": float(total_champion_summons) / count,
	}

# ---------------------------------------------------------------------------
# Relic AI helpers
# ---------------------------------------------------------------------------

## Start-of-turn relics: draw cards, add imp — fire on cooldown.
func _try_relic_start_of_turn(rt: RelicRuntime, fx: RelicEffects, _state: SimState) -> void:
	for i in rt.relics.size():
		if not rt.can_activate(i):
			continue
		var eid: String = rt.relics[i].data.effect_id
		if eid in ["relic_draw_2", "relic_add_void_imp"]:
			var effect_id: String = rt.activate(i)
			if effect_id != "":
				fx.resolve(effect_id)
			return  # 1 per turn

## Mana Shard: use after play phase if mana is low and hand has castable mana cards.
func _try_relic_mana_shard(rt: RelicRuntime, fx: RelicEffects, state: SimState, agent: CombatAgent) -> void:
	var idx: int = rt.find_by_id("mana_shard")
	if idx < 0 or not rt.can_activate(idx):
		return
	# Only fire if we've spent mana (mana < max) and have castable cards after refill
	if state.player_mana >= state.player_mana_max:
		return  # Mana is full — no need
	var mana_after: int = mini(state.player_mana + 2, state.player_mana_max)
	var has_castable := false
	for inst in agent.hand:
		if inst.card_data is SpellCardData:
			if (inst.card_data as SpellCardData).cost <= mana_after and (inst.card_data as SpellCardData).cost > state.player_mana:
				has_castable = true
				break
		elif inst.card_data is TrapCardData:
			var trap_cost: int = inst.effective_cost()
			if trap_cost <= mana_after and trap_cost > state.player_mana:
				has_castable = true
				break
		elif inst.card_data is EnvironmentCardData:
			if (inst.card_data as EnvironmentCardData).cost <= mana_after and (inst.card_data as EnvironmentCardData).cost > state.player_mana:
				has_castable = true
				break
	if not has_castable:
		return
	var effect_id: String = rt.activate(idx)
	if effect_id != "":
		fx.resolve(effect_id)

## Bone Shield: use after attacks if enemy board threatens lethal next turn.
func _try_relic_bone_shield(rt: RelicRuntime, fx: RelicEffects, state: SimState) -> void:
	var idx: int = rt.find_by_id("bone_shield")
	if idx < 0 or not rt.can_activate(idx):
		return
	# Calculate enemy board total ATK
	var enemy_atk := 0
	for m in state.enemy_board:
		enemy_atk += m.effective_atk()
	# Only activate if enemy can kill us next turn
	if enemy_atk >= state.player_hp:
		var effect_id: String = rt.activate(idx)
		if effect_id != "":
			fx.resolve(effect_id)
