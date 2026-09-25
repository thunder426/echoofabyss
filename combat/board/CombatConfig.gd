## CombatConfig.gd
## A fight's inputs as plain data (LIVE_SIM_UNIFICATION_PLAN.md 4.1). Everything
## CombatState.setup_combat needs — decks, heroes, passives, relics, seed — so
## live, sim, replays and tests build a fight through one path.
##
##   live:  state.setup_combat(CombatConfig.from_game_manager())
##   sim:   state.setup_combat(CombatConfig.from_dict(record_config, seed))
class_name CombatConfig
extends RefCounted

## Played when an encounter has no deck configured (live only; sim passes decks).
const FALLBACK_ENEMY_DECK: Array[String] = [
	"void_imp", "void_imp", "void_imp",
	"shadow_hound", "shadow_hound",
	"abyssal_brute",
	"void_bolt", "void_bolt",
]

var player_deck_ids: Array[String] = []
var enemy_deck_ids: Array[String] = []
var player_hp: int = 3000
var enemy_hp: int = 2000
var player_hero_id: String = "lord_vael"
var talents: Array[String] = []
var hero_passives: Array[String] = []
var enemy_passives: Array[String] = []
## Enemy AI profile id (ProfileRegistry, side "enemy"). Also marks the encounter
## for PhaseTransition (abyss_sovereign).
var enemy_profile_id: String = "default"
## Player AI profile id — sim / replay only (live is driven by input).
var player_profile_id: String = "default"
var enemy_limited_cards: Array[String] = []
var relic_ids: Array[String] = []
var relic_bonus_charges: Dictionary = {}
var seed: int = 0
## Attach a CombatDiagnostics (damage log, debug print) — sim reports only.
var diagnostics_enabled: bool = false

## The current run's fight, as CombatScene starts it. Consumes
## GameManager.next_combat_seed (a negative one rolls a fresh seed) and records
## the seed used in GameManager.combat_seed.
static func from_game_manager() -> CombatConfig:
	var c := CombatConfig.new()
	c.player_deck_ids.assign(GameManager.player_deck)
	c.player_hp = GameManager.player_hp_max
	c.player_hero_id = GameManager.current_hero
	c.talents.assign(GameManager.unlocked_talents)
	var hero: HeroData = HeroDatabase.get_hero(GameManager.current_hero)
	if hero != null:
		for p in hero.passives:
			c.hero_passives.append(p.id)
	var enemy: EnemyData = GameManager.current_enemy
	if enemy != null:
		c.enemy_deck_ids.assign(enemy.deck)
		c.enemy_hp = enemy.hp
		c.enemy_passives.assign(enemy.passives)
		c.enemy_profile_id = enemy.ai_profile
		c.enemy_limited_cards.assign(enemy.limited_cards)
	if c.enemy_deck_ids.is_empty():
		c.enemy_deck_ids.assign(FALLBACK_ENEMY_DECK)
	c.relic_ids.assign(GameManager.player_relics)
	c.relic_bonus_charges = GameManager.relic_bonus_charges.duplicate()
	var combat_seed: int = GameManager.next_combat_seed
	if combat_seed < 0:
		combat_seed = randi() & 0x7FFFFFFF  # lint: allow-rng (seed roll)
	GameManager.next_combat_seed = -1
	GameManager.combat_seed = combat_seed
	c.seed = combat_seed
	return c

## A sim / replay config Dictionary (CombatSim.make_config — JSON-safe, the
## shape replay files store) plus its seed. The enemy passives come from the
## encounter the enemy profile plays (EncounterTable). JSON numbers may be floats.
static func from_dict(d: Dictionary, rng_seed: int) -> CombatConfig:
	var c := CombatConfig.new()
	c.player_deck_ids.assign(d["player_deck"])
	c.enemy_deck_ids.assign(d["enemy_deck"])
	c.player_hp = int(d["player_hp"])
	c.enemy_hp = int(d["enemy_hp"])
	c.player_hero_id = d["hero_id"]
	c.talents.assign(d["talents"])
	c.hero_passives.assign(d["hero_passives"])
	c.enemy_profile_id = d["enemy_profile"]
	c.player_profile_id = d["player_profile"]
	c.enemy_passives.assign(EncounterTable.passives_for_profile(c.enemy_profile_id))
	c.enemy_limited_cards.assign(d["enemy_limited"])
	c.relic_ids.assign(d["relics"])
	for k in (d["relic_bonus_charges"] as Dictionary):
		c.relic_bonus_charges[k] = int(d["relic_bonus_charges"][k])
	c.seed = rng_seed
	return c
