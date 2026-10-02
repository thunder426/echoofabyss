## GameManager.gd
## Global autoload — persists across all scenes.
## Holds run state, permanent unlocks, and scene transitions.
extends Node

## Fights in each act (Acts 1–3: 3 fights, Act 4: 6 fights).
const ACT_SIZES: Array[int] = [3, 3, 3, 6]
const TOTAL_FIGHTS := 15
## 1-based indices of the boss fight in each act.
const BOSS_INDICES: Array[int] = [3, 6, 9, 15]

## Per-act-gate unlock chance (rolled once per eligible card per boss kill).
const _UNLOCK_CHANCE: Dictionary = {
	1: 0.60,
	2: 0.25,
	3: 0.20,
	4: 0.10,
}

# --- Run State ---
var run_active: bool = false
var void_shards: int = 0
var player_hp_max: int = 3000
var player_hp: int = 3000         # current HP; persists between fights
## Max copies of the core unit allowed in deck; starts at 4 for Lord Vael.
## Increased by special reward #4 (up to 6).
var core_unit_limit: int = 4
## If true, player can restart the same fight after defeat (consumed on use).
var has_revive: bool = false
## Set by HeroSelectScene before start_new_run() — not reset by start_new_run()
var current_hero: String = "lord_vael"
## Faction chosen on HeroSelectScene; used by DeckBuilderScene to pre-filter cards
var current_faction: String = "abyss_order"

# --- Deck & Cards ---
var player_deck: Array[String] = []   # card IDs
var player_relics: Array[String] = []          # relic IDs collected this run
var relic_bonus_charges: Dictionary = {}       # relic_id → int bonus charges from upgrades
var permanent_unlocks: Array[String] = []   # survives between runs
var last_boss_unlocks: Array[String] = []   # cards unlocked by the most recent boss kill; cleared after display

# --- Progression ---
var run_node_index: int = 1           # which encounter the player is on (1-based)
var current_enemy: EnemyData = null   # set before entering CombatScene
## Engine RNG seed for the next combat. -1 = roll a fresh one; tests and replays
## set it to reproduce a fight. CombatScene consumes it (resets to -1).
var next_combat_seed: int = -1
## Seed the current/last combat actually used — logged so a bug report carries it.
var combat_seed: int = 0

# --- Talents ---
var talent_points: int = 0
var unlocked_talents: Array[String] = []

## False until DeckBuilderScene finalises the deck — used by TalentSelectScene to know where to route
var deck_built: bool = false

# ---------------------------------------------------------------------------
# Scene Management
# ---------------------------------------------------------------------------

func go_to_scene(path: String) -> void:
	UserProfile.save()
	get_tree().change_scene_to_file(path)

# ---------------------------------------------------------------------------
# Run Management
# ---------------------------------------------------------------------------

func start_new_run() -> void:
	run_active = true
	run_node_index = 1
	player_relics = []
	relic_bonus_charges = {}
	player_hp_max = 3000
	player_hp = player_hp_max
	core_unit_limit = 4
	has_revive = false
	current_enemy = get_encounter(1)
	talent_points = 1       # initial point — spend before first fight
	unlocked_talents = []
	deck_built = false
	void_shards = 0

func end_run(_victory: bool) -> void:
	# Boss drops are granted in advance_node() when the act boss is detected,
	# so nothing extra is needed here for the final boss.
	run_active = false
	current_enemy = null
	UserProfile.clear_run()  # wipes run from save, keeps permanent_unlocks

func earn_shards(amount: int) -> void:
	void_shards += amount

func spend_shards(amount: int) -> bool:
	if void_shards < amount:
		return false
	void_shards -= amount
	return true

func advance_node() -> void:
	# Detect act boss BEFORE incrementing (boss indices: 3, 6, 9, 15).
	var act_boss_completed: bool = run_node_index in BOSS_INDICES
	var completed_act: int       = _act_for_index(run_node_index)

	run_node_index += 1
	if run_node_index <= TOTAL_FIGHTS:
		current_enemy = get_encounter(run_node_index)

	if act_boss_completed:
		grant_boss_unlocks(completed_act)

func is_run_complete() -> bool:
	return run_node_index > TOTAL_FIGHTS

## True when the player has just finished the last fight of an act.
## Call AFTER advance_node() — checks if run_node_index sits on an act boundary (4, 7, 10, 16).
func is_act_complete() -> bool:
	var boundary := 1
	for size in ACT_SIZES:
		boundary += size
		if run_node_index == boundary:
			return true
	return false

## Which act (1-based) the player is currently in.
func get_current_act() -> int:
	return _act_for_index(run_node_index)

## Which act (1-based) was just completed (call after advance_node + is_act_complete check).
func get_completed_act() -> int:
	return _act_for_index(run_node_index - 1)

## True when the current encounter is the final boss.
func is_boss_fight() -> bool:
	return run_node_index == TOTAL_FIGHTS

## Maps a 1-based fight index to its act number (1-based).
func _act_for_index(index: int) -> int:
	var cumulative := 0
	for i in ACT_SIZES.size():
		cumulative += ACT_SIZES[i]
		if index <= cumulative:
			return i + 1
	return ACT_SIZES.size()

# ---------------------------------------------------------------------------
# Boss Drop / Permanent Unlock System
# ---------------------------------------------------------------------------

## Roll permanent unlocks from all support pools relevant to the current run.
## act_number: 1–4 matching the act whose boss was just defeated.
## Eligible rarities scale with act: Act 1 → common only;
##   Act 2 → common + rare; Acts 3 & 4 → all rarities.
func grant_boss_unlocks(act_number: int) -> void:
	# Gather all support pool cards relevant to the current hero + talents.
	# Talent-pool checks are nested inside the hero gate so a future shared talent
	# id can't cross-contaminate the other hero's pool.
	var candidates: Array[String] = []
	if current_hero == "lord_vael":
		candidates.append_array(CardDatabase.get_card_ids_in_pools(["vael_common"]))
		if has_talent("piercing_void"):
			candidates.append_array(CardDatabase.get_card_ids_in_pools(["vael_piercing_void"]))
		if has_talent("imp_evolution"):
			candidates.append_array(CardDatabase.get_card_ids_in_pools(["vael_endless_tide"]))
		if has_talent("rune_caller"):
			candidates.append_array(CardDatabase.get_card_ids_in_pools(["vael_rune_master"]))
	elif current_hero == "seris":
		candidates.append_array(CardDatabase.get_card_ids_in_pools(["seris_common"]))
		if has_talent("flesh_infusion"):
			candidates.append_array(CardDatabase.get_card_ids_in_pools(["seris_fleshcraft"]))
		if has_talent("soul_forge"):
			# soul_shatter is dual-pooled (vael_common + seris_demon_forge); pulled in here for Seris.
			candidates.append_array(CardDatabase.get_card_ids_in_pools(["seris_demon_forge"]))
		if has_talent("corrupt_flesh"):
			# font_of_the_depths is dual-pooled (vael_piercing_void + seris_corruption); pulled in here for Seris.
			candidates.append_array(CardDatabase.get_card_ids_in_pools(["seris_corruption"]))
	elif current_hero == "korrath":
		# korrath_common is branch-agnostic; branch pools unlock at their T0 talent
		# (same mapping as RewardScene / ShopScene).
		candidates.append_array(CardDatabase.get_card_ids_in_pools(["korrath_common"]))
		if has_talent("iron_formation"):
			candidates.append_array(CardDatabase.get_card_ids_in_pools(["korrath_iron_vanguard"]))

	# Roll each candidate whose act_gate <= current act and not yet unlocked.
	last_boss_unlocks.clear()
	for card_id in candidates:
		if card_id in permanent_unlocks:
			continue  # already unlocked
		var card := CardDatabase.get_card(card_id)
		if not card or card.act_gate == 0 or card.act_gate > act_number:
			continue
		var chance: float = _UNLOCK_CHANCE.get(card.act_gate, 0.0)
		if randf() < chance:
			permanent_unlocks.append(card_id)
			last_boss_unlocks.append(card_id)

# ---------------------------------------------------------------------------
# Talent Management
# ---------------------------------------------------------------------------

func add_talent_point(amount: int = 1) -> void:
	talent_points += amount

func unlock_talent(id: String) -> void:
	if talent_points <= 0:
		push_error("GameManager: no talent points to spend")
		return
	if id in unlocked_talents:
		push_error("GameManager: talent '%s' already unlocked" % id)
		return
	unlocked_talents.append(id)
	talent_points -= 1
	# Capstone rewards: add cards to player deck
	if id == "abyss_convergence":
		player_deck.append("echo_rune")
		player_deck.append("echo_rune")

func has_talent(id: String) -> bool:
	return id in unlocked_talents

## Talent-driven cost modifications were retired here. Costs that change under
## a talent (e.g. piercing_void's +1 Mana on Void Imp) are now baked into the
## card's mana_cost / essence_cost via talent_overrides in CardDatabase. Read
## the card's cost fields directly — no modifier helper needed.

# ---------------------------------------------------------------------------
# Encounters — 4 acts (3 + 3 + 3 + 6 = 15 fights), defined in EncounterTable;
# decks come from EncounterDecks.
# ---------------------------------------------------------------------------

## The deck ID that was picked for the current encounter (for logging/display).
var current_deck_id: String = ""

func get_encounter(index: int) -> EnemyData:
	var e: EnemyData = _build_encounter(index)
	if e == null:
		return null
	var result := EncounterDecks.pick_random_with_id(index)
	current_deck_id = result.id as String
	var cards: Array[String] = []
	for id in (result.cards as Array):
		cards.append(id as String)
	e.deck = cards
	# Per-deck AI profile override (falls back to encounter default)
	var deck_profile: String = result.get("ai_profile", "") as String
	if not deck_profile.is_empty():
		e.ai_profile = deck_profile
	# Per-deck limited cards
	e.limited_cards = EncounterDecks.get_deck_limited(current_deck_id)
	return e

## Encounter data (HP, passives, default AI profile, story) lives in
## EncounterTable — the one table live and sim read (plan 2A.7).
func _build_encounter(index: int) -> EnemyData:
	return EncounterTable.make_enemy(index)

