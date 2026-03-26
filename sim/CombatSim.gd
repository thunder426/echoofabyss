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
	"default":         preload("res://enemies/ai/profiles/DefaultProfile.gd"),
	"feral_pack":      preload("res://enemies/ai/profiles/FeralPackProfile.gd"),
	"corrupted_brood": preload("res://enemies/ai/profiles/CorruptedBroodProfile.gd"),
	"matriarch":       preload("res://enemies/ai/profiles/MatriarchProfile.gd"),
}

## Passive IDs active for each enemy profile — mirrors EnemyData.passives in the live game.
const _ENEMY_PASSIVES: Dictionary = {
	"feral_pack":      ["feral_instinct", "pack_instinct"],
	"corrupted_brood": ["feral_instinct", "corrupted_death"],
	"matriarch":       ["feral_instinct", "ancient_frenzy"],
	"default":         [],
}

const _PLAYER_PROFILES: Dictionary = {
	"default":    preload("res://enemies/ai/profiles/DefaultPlayerProfile.gd"),
	"spell_burn": preload("res://enemies/ai/profiles/SpellBurnPlayerProfile.gd"),
	"rune_tempo": preload("res://enemies/ai/profiles/RuneTempoPlayerProfile.gd"),
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
		player_profile_id: String = "default") -> Dictionary:

	var state := SimState.new()
	state.setup(player_deck_ids, enemy_deck_ids, player_hp, enemy_hp)
	state.talents = player_talents
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
		await p_profile.play_phase()
		if not state.winner.is_empty(): break
		await p_profile.attack_phase()
		if not state.winner.is_empty(): break

		# ── Enemy turn ───────────────────────────────────────────────────────
		state.begin_enemy_turn(turn)
		await e_profile.play_phase()
		if not state.winner.is_empty(): break
		await e_profile.attack_phase()

	return {
		"winner":       state.winner if not state.winner.is_empty() else "draw",
		"turns":        turn,
		"player_hp":    state.player_hp,
		"enemy_hp":     state.enemy_hp,
		"player_board": state.player_board.size(),
		"enemy_board":  state.enemy_board.size(),
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
		player_profile_id: String = "default") -> Dictionary:

	var wins   := 0
	var losses := 0
	var draws  := 0
	var total_turns := 0
	var total_player_hp := 0
	var total_enemy_hp  := 0

	for _i in count:
		var r: Dictionary = await run(player_deck_ids, enemy_profile_id,
				enemy_deck_ids, player_hp, enemy_hp, player_talents, player_profile_id)
		match r["winner"]:
			"player": wins   += 1
			"enemy":  losses += 1
			_:        draws  += 1
		total_turns     += r["turns"]
		total_player_hp += r["player_hp"]
		total_enemy_hp  += r["enemy_hp"]

	return {
		"count":          count,
		"wins":           wins,
		"losses":         losses,
		"draws":          draws,
		"win_rate":       float(wins) / count,
		"avg_turns":      float(total_turns) / count,
		"avg_player_hp":  float(total_player_hp) / count,
		"avg_enemy_hp":   float(total_enemy_hp) / count,
	}
