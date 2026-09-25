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



## Maximum turns before declaring a draw — prevents infinite loops.
const MAX_TURNS := 60

## Optional per-turn snapshot callback, called with (state, turn) at the end of
## each enemy turn. Set before run().
var turn_snapshot_callback: Callable = Callable()

## Sim replay (plan 2A.8): when set, run() returns result["replay"] =
## {seed, config, command_log, digest}; with dump_replay_path it also writes
## that as JSON (the last run wins). ReplayRunner.tscn plays one back.
var record_replay: bool = false
var dump_replay_path: String = ""

## A fight's inputs as plain data — with the seed, everything a replay needs.
static func make_config(player_deck_ids: Array[String], enemy_profile_id: String,
		enemy_deck_ids: Array[String], player_hp: int, enemy_hp: int,
		player_talents: Array[String], player_profile_id: String,
		player_hero_passives: Array[String], player_relic_ids: Array[String],
		relic_bonus_charges: Dictionary, enemy_limited: Array[String],
		player_hero_id: String) -> Dictionary:
	return {
		"player_deck": player_deck_ids.duplicate(), "enemy_profile": enemy_profile_id,
		"enemy_deck": enemy_deck_ids.duplicate(), "player_hp": player_hp, "enemy_hp": enemy_hp,
		"talents": player_talents.duplicate(), "player_profile": player_profile_id,
		"hero_passives": player_hero_passives.duplicate(), "relics": player_relic_ids.duplicate(),
		"relic_bonus_charges": relic_bonus_charges.duplicate(), "enemy_limited": enemy_limited.duplicate(),
		"hero_id": player_hero_id,
	}

## Build and wire a CombatState for `config`: setup_combat (seed, decks,
## heroes, triggers, relics), then one StateAgent + profile per side and the
## growth hooks. Combat not yet started. Returns {state, p_profile, enemy} —
## `enemy.profile` is the live enemy CombatProfile (the F15 phase transition
## swaps it). JSON-loaded configs work (numbers may be floats).
func _build(config: Dictionary, rng_seed: int, dmg_log: bool = false, debug: bool = false) -> Dictionary:
	var state := CombatState.new()
	if dmg_log or debug:
		state.diagnostics = CombatDiagnostics.new(state, dmg_log, debug)
	state.setup_combat(CombatConfig.from_dict(config, rng_seed))
	var enemy_profile_id: String = config["enemy_profile"]

	# One StateAgent per side — every action is a state command (plan 2A.5).
	var p_agent := StateAgent.new()
	p_agent.setup(state, "player")
	var e_agent := StateAgent.new()
	e_agent.setup(state, "enemy")

	var p_profile: CombatProfile = ProfileRegistry.make("player", config["player_profile"])
	p_profile.setup(p_agent)
	var e_profile: CombatProfile = ProfileRegistry.make("enemy", enemy_profile_id)
	e_profile.setup(e_agent)
	# A Dictionary so the lambdas share it: the F15 phase transition swaps the
	# profile (enemy_profile_changed) and the growth hook follows.
	var enemy: Dictionary = {"profile": e_profile}
	state.enemy_profile_changed.connect(func(profile_id: String) -> void:
		var p: CombatProfile = ProfileRegistry.make("enemy", profile_id)
		p.setup(e_agent)
		enemy["profile"] = p)
	# Resource growth: each side's profile, run by state.begin_turn (plan 2A.4).
	state.growth_hooks["player"] = func(side: String, turn: int) -> void:
		p_profile.grow_resources(state, side, turn)
	state.growth_hooks["enemy"] = func(side: String, turn: int) -> void:
		(enemy["profile"] as CombatProfile).grow_resources(state, side, turn)

	return {"state": state, "p_profile": p_profile, "enemy": enemy}

## Play a recorded fight back: build the same state from its config and seed,
## start combat and apply the command log. Profiles are built only for their
## resource curves — they make no decisions. Returns {winner, digest_text,
## digest, failed_index (-1 = all applied), failed_command, reason}.
func replay(record: Dictionary) -> Dictionary:
	var built: Dictionary = _build(record["config"], int(record["seed"]))
	var state: CombatState = built["state"]
	state.start_combat()
	var log: Array = record["command_log"]
	var failed: int = -1
	var reason: String = ""
	for i in log.size():
		var r: CommandResult = apply_logged_command(state, log[i])
		if not r.ok:
			failed = i
			reason = r.reason
			break
	var text: String = state.digest_text()
	var out: Dictionary = {
		"winner": state.winner if not state.winner.is_empty() else "draw",
		"digest_text": text, "digest": text.hash(),
		"failed_index": failed, "failed_command": log[failed] if failed >= 0 else {}, "reason": reason,
	}
	state.teardown()
	return out

## Re-issue one command_log entry against `state` (targets and spark fuel by slot).
static func apply_logged_command(state: CombatState, rec: Dictionary) -> CommandResult:
	var side: String = rec["side"]
	var slot: int = int(rec["slot"])
	var target: Variant = _decode_target(state, rec.get("target"))
	var extra: Dictionary = (rec.get("extra", {}) as Dictionary).duplicate()
	if extra.has("spark_fuel"):
		var fuel: Array = []
		for s in extra["spark_fuel"]:
			fuel.append(state._friendly_slots(side)[int(s)].minion)
		extra["spark_fuel"] = fuel
	if extra.has("sparks_prepaid"):
		extra["sparks_prepaid"] = int(extra["sparks_prepaid"])
	var inst: CardInstance = null
	var hand_index: int = int(rec.get("hand_index", -1))
	if hand_index >= 0:
		var hand: Array[CardInstance] = state.hand_of(side)
		if hand_index >= hand.size() or hand[hand_index].card_data.id != rec["card_id"]:
			return CommandResult.refused("replay_hand_mismatch")
		inst = hand[hand_index]
	var minion_at_slot: MinionInstance = null
	if slot >= 0 and slot < state._friendly_slots(side).size():
		minion_at_slot = (state._friendly_slots(side)[slot] as SlotState).minion
	match rec["cmd"]:
		"play_minion":      return state.cmd_play_minion(side, inst, slot, target, extra)
		"play_spell":       return state.cmd_play_spell(side, inst, target, extra)
		"play_trap":        return state.cmd_play_trap(side, inst)
		"play_environment": return state.cmd_play_environment(side, inst)
		"attack":           return state.cmd_attack(side, minion_at_slot, target)
		"attack_hero":      return state.cmd_attack_hero(side, minion_at_slot)
		"consume_minion":   return state.cmd_consume_minion(side, minion_at_slot)
		"activate_relic":   return state.cmd_activate_relic(slot, target)
		"hero_skill":       return state.cmd_hero_skill(side, extra.get("skill", ""), target)
		"end_turn":         return state.cmd_end_turn(side, extra.get("growth", ""))
	return CommandResult.refused("replay_unknown_command")

static func _decode_target(state: CombatState, t: Variant) -> Variant:
	if t == null or not (t is Dictionary):
		return null
	var d: Dictionary = t
	var side: String = d.get("side", "")
	var slot: int = int(d.get("slot", -1))
	match d.get("kind", ""):
		"minion":
			if slot >= 0 and slot < state._friendly_slots(side).size():
				return (state._friendly_slots(side)[slot] as SlotState).minion
		"hero":
			return "%s_hero" % side
		"trap":
			var traps: Array[TrapCardData] = state.traps_of(side)
			if slot >= 0 and slot < traps.size():
				return traps[slot]
		"env":
			return state.environment_of(side)
	return null

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
		player_hero_id: String = "lord_vael",
		rng_seed: int = -1) -> Dictionary:

	# Engine RNG — a negative seed rolls a fresh one; either way it's returned as
	# result["seed"] so any run can be reproduced by passing it back in.
	if rng_seed < 0:
		rng_seed = randi() & 0x7FFFFFFF  # lint: allow-rng (seed roll)
	var config: Dictionary = make_config(player_deck_ids, enemy_profile_id, enemy_deck_ids,
			player_hp, enemy_hp, player_talents, player_profile_id, player_hero_passives,
			player_relic_ids, relic_bonus_charges, enemy_limited, player_hero_id)
	var built: Dictionary = _build(config, rng_seed, dmg_log, debug)
	var state: CombatState = built["state"]
	var p_profile: CombatProfile = built["p_profile"]
	var enemy: Dictionary = built["enemy"]
	var e_profile: CombatProfile = enemy["profile"]
	var debug_on: bool = state.diagnostics != null and state.diagnostics.debug_log_enabled
	if turn_snapshot_callback.is_valid():
		# Snapshot at the end of each enemy turn (before the player's next begins).
		var snap: Callable = turn_snapshot_callback
		state.turn_ended.connect(func(side: String) -> void:
			if side == "enemy":
				snap.call(state, state.turn_number))

	# Both sides open at 1/1; the player's first turn begins (shared turn engine,
	# plan 2A.3). Each side's turn then ends with cmd_end_turn.
	state.start_combat()

	# Run the loop
	var turn := 0
	while true:
		turn += 1

		if debug_on:
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

		# ── Player turn (already begun) ──────────────────────────────────────
		# Relic use is SimRelicPolicy's call; each activation is cmd_activate_relic.
		if state.relic_runtime:
			SimRelicPolicy.start_of_turn(state)
		await p_profile.play_phase()
		if not state.winner.is_empty(): break
		if state.relic_runtime and not state.relic_runtime.activated_this_turn:
			if SimRelicPolicy.mana_shard(state):
				await p_profile.play_phase()  # spend the refill
				if not state.winner.is_empty(): break
		if state.relic_runtime and not state.relic_runtime.activated_this_turn:
			SimRelicPolicy.void_lens(state)
		if state.relic_runtime and not state.relic_runtime.activated_this_turn:
			SimRelicPolicy.blood_chalice(state)
		await p_profile.attack_phase()
		if state.relic_runtime and not state.relic_runtime.activated_this_turn:
			SimRelicPolicy.bone_shield(state)
		state.cmd_end_turn("player")
		if not state.winner.is_empty(): break

		# ── Enemy turn (begun by the player's cmd_end_turn) ─────────────────
		if debug_on:
			print("  -- Enemy play phase --")
		e_profile = enemy["profile"]
		await e_profile.play_phase()
		if not state.winner.is_empty(): break
		if debug_on:
			var e_cards_post: Array[String] = []
			for m in state.enemy_board: e_cards_post.append("%s(%d/%d)" % [m.card_data.card_name, m.effective_atk(), m.current_health])
			print("  E_Board after play: %s" % ", ".join(e_cards_post) if not e_cards_post.is_empty() else "  E_Board after play: (empty)")
			print("  -- Enemy attack phase --")
		e_profile = enemy["profile"]
		await e_profile.attack_phase()
		if debug_on:
			print("  P_HP after attacks: %d  E_HP: %d" % [state.player_hp, state.enemy_hp])
		state.cmd_end_turn("enemy")  # also begins the player's next turn
		if not state.winner.is_empty() or turn >= MAX_TURNS:
			break

	# Count Behemoth/Bastion still alive on enemy board as "survived"
	for m: MinionInstance in state.enemy_board:
		if m.card_data.id == "void_behemoth":
			state._vw_behemoth_lost["survived"] += 1
		elif m.card_data.id == "bastion_colossus":
			state._vw_bastion_lost["survived"] += 1
	# Snapshot before teardown drops references.
	var digest_text: String = state.digest_text()
	var replay: Dictionary = {}
	if record_replay or not dump_replay_path.is_empty():
		replay = {"seed": rng_seed, "config": config, "command_log": state.command_log.duplicate(true), "digest": digest_text.hash()}
		if not dump_replay_path.is_empty():
			var f := FileAccess.open(dump_replay_path, FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(replay, "\t"))
				f.close()
	# Disconnect the global-bus subscription and reset the MinionInstance globals
	# so nothing bleeds into the next sim run.
	state.teardown()
	var _seris_sf: int = state._debug_soul_forge_fires
	var _seris_cf: int = state._debug_corrupt_flesh_fires
	return {
		"winner":       state.winner if not state.winner.is_empty() else "draw",
		"seed":         rng_seed,
		"digest":       digest_text.hash(),
		"digest_text":  digest_text,
		"replay":       replay,
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
		"dmg_log": state.diagnostics.dmg_log if state.diagnostics != null else [],
		"relic_activations": state.relic_runtime.total_activations if state.relic_runtime else 0,
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
		var run_seed: int = -1
		if base_seed >= 0:
			run_seed = base_seed + _i
			seed(run_seed)  # also pin anything still on the global RNG
		var r: Dictionary = await run(player_deck_ids, enemy_profile_id,
				enemy_deck_ids, player_hp, enemy_hp, player_talents, player_profile_id,
				player_hero_passives, player_relic_ids, relic_bonus_charges, false, false,
				enemy_limited, player_hero_id, run_seed)
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

## Count 0-ATK minions on the player board (corrupted sparks clogging slots).
static func _count_clogged_slots(state: CombatState) -> int:
	var count := 0
	for m in state.player_board:
		if m.effective_atk() <= 0:
			count += 1
	return count
