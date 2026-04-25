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
	"feral_pack_screech":   preload("res://enemies/ai/profiles/FeralPackScreechProfile.gd"),
	"corrupted_brood":      preload("res://enemies/ai/profiles/CorruptedBroodProfile.gd"),
	"corrupted_brood_aggro": preload("res://enemies/ai/profiles/CorruptedBroodAggroProfile.gd"),
	"corrupted_brood_rune": preload("res://enemies/ai/profiles/CorruptedBroodRuneProfile.gd"),
	"matriarch":            preload("res://enemies/ai/profiles/MatriarchProfile.gd"),
	"matriarch_aggro":      preload("res://enemies/ai/profiles/MatriarchAggroProfile.gd"),
	"matriarch_sac":        preload("res://enemies/ai/profiles/MatriarchSacProfile.gd"),
	"cultist_patrol":       preload("res://enemies/ai/profiles/CultistPatrolProfile.gd"),
	"cultist_patrol_tempo": preload("res://enemies/ai/profiles/CultistPatrolTempoProfile.gd"),
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
	"abyss_sovereign_p2":   preload("res://enemies/ai/profiles/AbyssSovereignPhase2Profile.gd"),
	# Scored variants
	"scored":               preload("res://enemies/ai/profiles/ScoredDefaultProfile.gd"),
	"scored_feral_pack":    preload("res://enemies/ai/profiles/ScoredFeralPackProfile.gd"),
	"scored_corrupted_brood": preload("res://enemies/ai/profiles/ScoredCorruptedBroodProfile.gd"),
	"scored_matriarch":     preload("res://enemies/ai/profiles/ScoredMatriarchProfile.gd"),
}

## Passive IDs active for each enemy profile — mirrors EnemyData.passives in the live game.
const _ENEMY_PASSIVES: Dictionary = {
	"feral_pack":           ["pack_instinct", "champion_rogue_imp_pack"],
	"feral_pack_screech":   ["pack_instinct", "champion_rogue_imp_pack"],
	"corrupted_brood":      ["corrupted_death", "champion_corrupted_broodlings"],
	"corrupted_brood_aggro": ["corrupted_death", "champion_corrupted_broodlings"],
	"corrupted_brood_rune": ["corrupted_death", "champion_corrupted_broodlings"],
	"matriarch":            ["ancient_frenzy", "champion_imp_matriarch"],
	"matriarch_aggro":      ["ancient_frenzy", "champion_imp_matriarch"],
	"matriarch_sac":        ["ancient_frenzy", "champion_imp_matriarch"],
	"default":              [],
	"cultist_patrol":       ["feral_reinforcement", "corrupt_authority", "champion_abyss_cultist_patrol"],
	"cultist_patrol_tempo": ["feral_reinforcement", "corrupt_authority", "champion_abyss_cultist_patrol"],
	"void_ritualist":       ["feral_reinforcement", "ritual_sacrifice", "champion_void_ritualist"],
	"corrupted_handler":    ["feral_reinforcement", "void_unraveling", "champion_corrupted_handler"],
	"rift_stalker":         ["void_rift", "void_empowerment", "champion_rift_stalker"],
	"void_aberration":      ["void_rift", "void_detonation_passive", "champion_void_aberration"],
	"void_herald":          ["void_rift", "void_mastery", "champion_void_herald"],
	# Act 4 — Void Castle
	"void_scout":           ["void_might", "void_precision", "champion_void_scout"],
	"void_warband":         ["void_might", "spirit_resonance", "champion_void_warband"],
	"void_captain":         ["void_might", "captain_orders", "champion_void_captain"],
	"void_ritualist_prime": ["void_might", "dark_channeling", "ritualist_spark_free", "champion_void_ritualist_prime"],
	"void_champion":        ["void_might", "mana_for_spark", "champion_void_champion"],
	"abyss_sovereign":      ["void_might", "abyssal_mandate", "dark_channeling"],
	# Scored variants
	"scored":               [],
	"scored_feral_pack":    ["pack_instinct", "champion_rogue_imp_pack"],
	"scored_corrupted_brood": ["corrupted_death", "champion_corrupted_broodlings"],
	"scored_matriarch":     ["ancient_frenzy", "champion_imp_matriarch"],
}

const _PLAYER_PROFILES: Dictionary = {
	"default":    preload("res://enemies/ai/profiles/DefaultPlayerProfile.gd"),
	"swarm":      preload("res://enemies/ai/profiles/SwarmPlayerProfile.gd"),
	"spell_burn": preload("res://enemies/ai/profiles/SpellBurnPlayerProfile.gd"),
	"rune_tempo": preload("res://enemies/ai/profiles/RuneTempoPlayerProfile.gd"),
	"scored":     preload("res://enemies/ai/profiles/ScoredDefaultProfile.gd"),
	"seris":      preload("res://enemies/ai/profiles/SerisPlayerProfile.gd"),
	"fleshcraft": preload("res://enemies/ai/profiles/FleshcraftPlayerProfile.gd"),
}

## Maximum turns before declaring a draw — prevents infinite loops.
const MAX_TURNS := 60

## Optional per-turn snapshot callback forwarded to SimState. Set before run().
var turn_snapshot_callback: Callable = Callable()

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
		relic_bonus_charges: Dictionary = {},
		dmg_log: bool = false,
		debug: bool = false,
		enemy_limited: Array[String] = [],
		player_hero_id: String = "lord_vael") -> Dictionary:

	var state := SimState.new()
	state.dmg_log_enabled = dmg_log
	if turn_snapshot_callback.is_valid():
		state.turn_snapshot_callback = turn_snapshot_callback
	state.debug_log_enabled = debug
	state.enemy_limited_cards = enemy_limited
	state.setup(player_deck_ids, enemy_deck_ids, player_hp, enemy_hp)
	state.enemy_hp_max = enemy_hp
	state.talents = player_talents
	state.hero_passives = player_hero_passives
	state.player_hero_id = player_hero_id
	state.enemy_passives.assign(_ENEMY_PASSIVES.get(enemy_profile_id, []))
	state.enemy_ai_profile = enemy_profile_id

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
	# Store on state so the F15 phase-transition can swap it mid-run.
	state._e_profile = e_profile
	state._e_profile_factory = _make_profile_factory(e_agent, state)

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

		if state.debug_log_enabled:
			print("\n=== TURN %d === P_HP:%d E_HP:%d" % [turn, state.player_hp, state.enemy_hp])
			var p_cards: Array[String] = []
			for m in state.player_board: p_cards.append("%s(%d/%d)" % [m.card_data.card_name, m.effective_atk(), m.current_health])
			var e_cards: Array[String] = []
			for m in state.enemy_board: e_cards.append("%s(%d/%d)" % [m.card_data.card_name, m.effective_atk(), m.current_health])
			print("  P_Board: %s" % ", ".join(p_cards) if not p_cards.is_empty() else "  P_Board: (empty)")
			print("  E_Board: %s" % ", ".join(e_cards) if not e_cards.is_empty() else "  E_Board: (empty)")
			var e_hand: Array[String] = []
			for inst in state.enemy_hand: e_hand.append(inst.card_data.card_name)
			print("  E_Hand: %s" % ", ".join(e_hand) if not e_hand.is_empty() else "  E_Hand: (empty)")

		# ── Player turn ──────────────────────────────────────────────────────
		state.begin_player_turn(turn)
		state._relic_hero_immune = false
		state._relic_cost_reduction = 0
		if relic_rt:
			relic_rt.on_turn_start()
			# Phase 1: Activate draw/imp/guardian relics at turn start (on cooldown)
			_try_relic_start_of_turn(relic_rt, relic_fx, state)
			# Phase 1b: Dark Mirror — cost reduction before play phase
			if not relic_rt.activated_this_turn:
				_try_relic_dark_mirror(relic_rt, relic_fx, state)
		await p_profile.play_phase()
		if not state.winner.is_empty(): break
		# Phase 2: Mana Shard — after play phase if mana spent and castable cards remain
		if relic_rt and not relic_rt.activated_this_turn:
			_try_relic_mana_shard(relic_rt, relic_fx, state, p_agent)
			# If mana shard fired, try playing more cards
			if relic_rt.activated_this_turn:
				await p_profile.play_phase()
				if not state.winner.is_empty(): break
		# Phase 2b: Void Lens — AoE after play phase
		if relic_rt and not relic_rt.activated_this_turn:
			_try_relic_void_lens(relic_rt, relic_fx, state)
		# Phase 2c: Blood Chalice — execute after play phase
		if relic_rt and not relic_rt.activated_this_turn:
			_try_relic_blood_chalice(relic_rt, relic_fx, state)
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
		if state.debug_log_enabled:
			print("  -- Enemy play phase --")
		e_profile = state._e_profile
		await e_profile.play_phase()
		if not state.winner.is_empty(): break
		if state.debug_log_enabled:
			var e_cards_post: Array[String] = []
			for m in state.enemy_board: e_cards_post.append("%s(%d/%d)" % [m.card_data.card_name, m.effective_atk(), m.current_health])
			print("  E_Board after play: %s" % ", ".join(e_cards_post) if not e_cards_post.is_empty() else "  E_Board after play: (empty)")
			print("  -- Enemy attack phase --")
		e_profile = state._e_profile
		await e_profile.attack_phase()
		if state.debug_log_enabled:
			print("  P_HP after attacks: %d  E_HP: %d" % [state.player_hp, state.enemy_hp])
		state.end_enemy_turn()
		if state.turn_snapshot_callback.is_valid():
			state.turn_snapshot_callback.call(state, turn)

	# Count Behemoth/Bastion still alive on enemy board as "survived"
	for m: MinionInstance in state.enemy_board:
		if m.card_data.id == "void_behemoth":
			state._vw_behemoth_lost["survived"] += 1
		elif m.card_data.id == "bastion_colossus":
			state._vw_bastion_lost["survived"] += 1
	# Disconnect global-bus subscriptions so this sim's callable doesn't fire for the next run.
	state.teardown()
	# Also reset Seris globals so they don't bleed into the next sim invocation.
	MinionInstance.corruption_inverts_on_friendly_demons = false
	var _seris_sf: int = state._debug_soul_forge_fires
	var _seris_cf: int = state._debug_corrupt_flesh_fires
	return {
		"winner":       state.winner if not state.winner.is_empty() else "draw",
		"turns":        turn,
		"player_hp":    state.player_hp,
		"enemy_hp":     state.enemy_hp,
		"player_board": state.player_board.size(),
		"enemy_board":  state.enemy_board.size(),
		"seris_sf": _seris_sf,
		"seris_cf": _seris_cf,
		"vw_behemoth_lost": state._vw_behemoth_lost.duplicate(),
		"vw_bastion_lost": state._vw_bastion_lost.duplicate(),
		"ritual_sacrifice_count": state._ritual_sacrifice_count,
		"detonation_count": state._detonation_count,
		"player_ritual_count": state._player_ritual_count,
		"spark_spawned_count": state._spark_spawned_count,
		"spark_transfer_count": state._spark_transfer_count,
		"champion_summon_count": state._champion_summon_count,
		"vw_behemoth_plays": state._vw_behemoth_plays,
		"vw_bastion_plays": state._vw_bastion_plays,
		"vw_death_crit_grants": state._vw_death_crit_grants,
		"corruption_detonation_times": state._corruption_detonation_times,
		"ritual_invoke_times": state._ritual_invoke_times,
		"handler_spark_buff_times": state._handler_spark_buff_times,
		"champion_ch_aura_dmg": state._champion_ch_aura_dmg,
		"player_clogged_slots": _count_clogged_slots(state),
		"smoke_veil_fires": state._smoke_veil_fires,
		"smoke_veil_damage_prevented": state._smoke_veil_damage_prevented,
		"abyssal_plague_fires": state._abyssal_plague_fires,
		"abyssal_plague_kills": state._abyssal_plague_kills,
		"void_bolt_spell_casts": state._void_bolt_spell_casts,
		"void_bolt_total_dmg": state._void_bolt_total_dmg,
		"void_imp_dmg": state._void_imp_dmg,
		"spark_atk_dmg": state._champion_rs_spark_dmg,
		"hollow_sentinel_buffs": state._hollow_sentinel_buffs,
		"immune_dmg_prevented": state._immune_dmg_prevented,
		"rift_lord_plays": state._rift_lord_plays,
		"enemy_crits_consumed": state._enemy_crits_consumed,
		"dc_amp_count": state._dark_channeling_amp_count,
		"dc_amp_by_spell": state._dark_channeling_amp_by_spell.duplicate(),
		"dc_dmg_by_spell": state._dark_channeling_dmg_by_spell.duplicate(),
		"rift_collapse_casts": state._rift_collapse_casts,
		"rift_collapse_kills": state._rift_collapse_kills,
		"dmg_log": state.dmg_log,
		"relic_activations": relic_rt.total_activations if relic_rt else 0,
		"sovereign_phase_reached":   state._sovereign_phase,
		"sovereign_transition_turn": state._sovereign_transition_turn,
	}

# ---------------------------------------------------------------------------
# Run N simulations and aggregate
# ---------------------------------------------------------------------------

## Run count simulations and return aggregate stats.
## Useful for win-rate estimation over a sample.
##
## When `base_seed >= 0`, each run is seeded with `base_seed + run_index` so the
## whole batch is bit-reproducible run-by-run. Changing `count` extends the
## sequence rather than reshuffling it. `base_seed = -1` keeps legacy
## unseeded behaviour (Godot's randomized startup state).
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
		relic_bonus_charges: Dictionary = {},
		enemy_limited: Array[String] = [],
		player_hero_id: String = "lord_vael",
		base_seed: int = -1) -> Dictionary:

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
	var total_vw_behemoth := 0
	var total_vw_bastion := 0
	var total_vw_death_crit := 0
	var total_beh_lost := {"consumed": 0, "damage": 0, "combat": 0, "survived": 0}
	var total_bas_lost := {"consumed": 0, "damage": 0, "combat": 0, "survived": 0}
	var total_corruption_det := 0
	var total_ritual_invoke := 0
	var total_spark_buff := 0
	var total_ch_aura_dmg := 0
	var total_clogged := 0
	var total_smoke_veil_fires := 0
	var total_smoke_veil_dmg := 0
	var total_plague_fires := 0
	var total_plague_kills := 0
	var total_void_bolt_casts := 0
	var total_void_bolt_dmg := 0
	var total_void_imp_dmg := 0
	var total_spark_atk_dmg := 0
	var total_sentinel_buffs := 0
	var total_immune_prevented := 0
	var total_collapse_casts := 0
	var total_collapse_kills := 0
	var total_rift_lord_plays := 0
	var rift_lord_wins := 0
	var rift_lord_games := 0
	var total_crits_consumed := 0
	var total_dc_amp := 0
	var total_dc_amp_by_spell: Dictionary = {}
	var total_dc_dmg_by_spell: Dictionary = {}
	# F15 phase-transition metrics
	var p2_reached_count := 0       # number of runs where the Sovereign entered P2
	var total_transition_turn := 0  # sum of turn numbers at transition (for avg)
	var p1_wins := 0                # player wins that never transitioned
	var p2_wins := 0                # player wins after transitioning to P2
	var p1_losses := 0              # player losses before transition (died in P1)
	var p2_losses := 0              # player losses after transition (died in P2)

	for _i in count:
		if base_seed >= 0:
			seed(base_seed + _i)
		var r: Dictionary = await run(player_deck_ids, enemy_profile_id,
				enemy_deck_ids, player_hp, enemy_hp, player_talents, player_profile_id,
				player_hero_passives, player_relic_ids, relic_bonus_charges, false, false,
				enemy_limited, player_hero_id)
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
		total_vw_behemoth += r.get("vw_behemoth_plays", 0)
		total_vw_bastion += r.get("vw_bastion_plays", 0)
		total_vw_death_crit += r.get("vw_death_crit_grants", 0)
		var beh_lost: Dictionary = r.get("vw_behemoth_lost", {})
		for k in beh_lost:
			total_beh_lost[k] += beh_lost[k]
		var bas_lost: Dictionary = r.get("vw_bastion_lost", {})
		for k in bas_lost:
			total_bas_lost[k] += bas_lost[k]
		total_corruption_det += r.get("corruption_detonation_times", 0)
		total_ritual_invoke += r.get("ritual_invoke_times", 0)
		total_spark_buff += r.get("handler_spark_buff_times", 0)
		total_ch_aura_dmg += r.get("champion_ch_aura_dmg", 0)
		total_clogged += r.get("player_clogged_slots", 0)
		total_smoke_veil_fires += r.get("smoke_veil_fires", 0)
		total_smoke_veil_dmg += r.get("smoke_veil_damage_prevented", 0)
		total_plague_fires += r.get("abyssal_plague_fires", 0)
		total_plague_kills += r.get("abyssal_plague_kills", 0)
		total_void_bolt_casts += r.get("void_bolt_spell_casts", 0)
		total_void_bolt_dmg += r.get("void_bolt_total_dmg", 0)
		total_void_imp_dmg += r.get("void_imp_dmg", 0)
		total_spark_atk_dmg += r.get("spark_atk_dmg", 0)
		total_sentinel_buffs += r.get("hollow_sentinel_buffs", 0)
		total_immune_prevented += r.get("immune_dmg_prevented", 0)
		total_collapse_casts += r.get("rift_collapse_casts", 0)
		total_collapse_kills += r.get("rift_collapse_kills", 0)
		total_crits_consumed += r.get("enemy_crits_consumed", 0)
		total_dc_amp += r.get("dc_amp_count", 0)
		var run_by_spell: Dictionary = r.get("dc_amp_by_spell", {})
		for sid in run_by_spell.keys():
			total_dc_amp_by_spell[sid] = int(total_dc_amp_by_spell.get(sid, 0)) + int(run_by_spell[sid])
		var run_dmg: Dictionary = r.get("dc_dmg_by_spell", {})
		for sid in run_dmg.keys():
			total_dc_dmg_by_spell[sid] = int(total_dc_dmg_by_spell.get(sid, 0)) + int(run_dmg[sid])
		var rl: int = r.get("rift_lord_plays", 0)
		total_rift_lord_plays += rl
		if rl > 0:
			rift_lord_games += 1
			if r["winner"] == "player":
				rift_lord_wins += 1
		# F15 phase-transition tracking
		var phase_reached: int = r.get("sovereign_phase_reached", 1)
		var trans_turn: int    = r.get("sovereign_transition_turn", 0)
		if phase_reached == 2:
			p2_reached_count += 1
			total_transition_turn += trans_turn
			if r["winner"] == "player":
				p2_wins += 1
			elif r["winner"] == "enemy":
				p2_losses += 1
		else:
			if r["winner"] == "player":
				p1_wins += 1
			elif r["winner"] == "enemy":
				p1_losses += 1

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
		"avg_vw_behemoth": float(total_vw_behemoth) / count,
		"avg_vw_bastion": float(total_vw_bastion) / count,
		"avg_vw_death_crit": float(total_vw_death_crit) / count,
		"vw_behemoth_lost_total": total_beh_lost,
		"vw_bastion_lost_total": total_bas_lost,
		"avg_corruption_det": float(total_corruption_det) / count,
		"avg_ritual_invoke": float(total_ritual_invoke) / count,
		"avg_spark_buff": float(total_spark_buff) / count,
		"avg_ch_aura_dmg": float(total_ch_aura_dmg) / count,
		"avg_clogged_slots": float(total_clogged) / count,
		"avg_smoke_veil_fires": float(total_smoke_veil_fires) / count,
		"avg_smoke_veil_dmg": float(total_smoke_veil_dmg) / count,
		"avg_plague_fires": float(total_plague_fires) / count,
		"avg_plague_kills": float(total_plague_kills) / count,
		"avg_void_bolt_casts": float(total_void_bolt_casts) / count,
		"avg_void_bolt_dmg": float(total_void_bolt_dmg) / count,
		"avg_void_imp_dmg": float(total_void_imp_dmg) / count,
		"avg_spark_atk_dmg": float(total_spark_atk_dmg) / count,
		"avg_sentinel_buffs": float(total_sentinel_buffs) / count,
		"avg_immune_prevented": float(total_immune_prevented) / count,
		"avg_collapse_casts": float(total_collapse_casts) / count,
		"avg_collapse_kills": float(total_collapse_kills) / count,
		"avg_crits_consumed": float(total_crits_consumed) / count,
		"avg_dc_amp": float(total_dc_amp) / count,
		"dc_amp_by_spell_total": total_dc_amp_by_spell,
		"dc_dmg_by_spell_total": total_dc_dmg_by_spell,
		"avg_rift_lord_plays": float(total_rift_lord_plays) / count,
		"rift_lord_games": rift_lord_games,
		"rift_lord_win_rate": float(rift_lord_wins) / rift_lord_games if rift_lord_games > 0 else 0.0,
		# F15 phase-transition
		"p2_reached_rate":    float(p2_reached_count) / count,
		"avg_transition_turn": float(total_transition_turn) / p2_reached_count if p2_reached_count > 0 else 0.0,
		"p1_wins":            p1_wins,
		"p2_wins":            p2_wins,
		"p1_losses":          p1_losses,
		"p2_losses":          p2_losses,
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
		if eid in ["relic_draw_2", "relic_add_void_imp", "relic_summon_guardian"]:
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

## Dark Mirror: use before play phase — reduces next card cost by 2E+2M.
func _try_relic_dark_mirror(rt: RelicRuntime, fx: RelicEffects, _state: SimState) -> void:
	var idx: int = rt.find_by_id("dark_mirror")
	if idx < 0 or not rt.can_activate(idx):
		return
	var effect_id: String = rt.activate(idx)
	if effect_id != "":
		fx.resolve(effect_id)

## Void Lens: use after play phase — AoE 100 damage + corruption to all enemies.
func _try_relic_void_lens(rt: RelicRuntime, fx: RelicEffects, state: SimState) -> void:
	var idx: int = rt.find_by_id("void_lens")
	if idx < 0 or not rt.can_activate(idx):
		return
	# Only fire if enemy has minions to hit
	if state.enemy_board.is_empty():
		return
	var effect_id: String = rt.activate(idx)
	if effect_id != "":
		fx.resolve(effect_id)

## Blood Chalice: use after play phase — 500 damage to highest ATK enemy.
func _try_relic_blood_chalice(rt: RelicRuntime, fx: RelicEffects, state: SimState) -> void:
	var idx: int = rt.find_by_id("blood_chalice")
	if idx < 0 or not rt.can_activate(idx):
		return
	# Fire if there's a high-value target (ATK >= 300) or if it would kill something
	var best_atk := 0
	for m in state.enemy_board:
		if m.effective_atk() > best_atk:
			best_atk = m.effective_atk()
	if best_atk < 300 and state.enemy_board.is_empty():
		return
	var effect_id: String = rt.activate(idx)
	if effect_id != "":
		fx.resolve(effect_id)

## Count 0-ATK minions on the player board (corrupted sparks clogging slots).
static func _count_clogged_slots(state: SimState) -> int:
	var count := 0
	for m in state.player_board:
		if m.effective_atk() <= 0:
			count += 1
	return count

## Build a factory callable the F15 phase transition can invoke to instantiate
## a new enemy CombatProfile by id. Bound to the current sim's e_agent + state.
func _make_profile_factory(e_agent: Object, state: SimState) -> Callable:
	return func(profile_id: String) -> CombatProfile:
		var script = _ENEMY_PROFILES.get(profile_id, _ENEMY_PROFILES["default"])
		var p: CombatProfile = script.new()
		p.setup(e_agent)
		p.setup_resource_growth(state)
		return p
