## RewardScene.gd
## After combat victory — player picks one card to add to their deck.
extends Node2D

const CardVisualScene := preload("res://combat/ui/CardVisual.tscn")

const REWARD_POOL: Array[String] = [
	# Abyss Order minions
	"void_imp", "shadow_hound", "abyssal_brute",
	"abyss_cultist", "void_netter", "corruption_weaver",
	"soul_collector", "void_stalker", "void_spawner", "abyssal_tide",
	"void_devourer",
	# Abyss Order spells
	"soul_leech", "dark_surge", "flux_siphon", "void_bolt",
	"abyssal_sacrifice", "corrupting_mist", "abyssal_fury",
	"abyssal_reinforcement", "corruption_collapse", "abyssal_purge",
	# Abyss Order traps
	"void_snare", "soul_cage", "phantom_recoil", "abyss_retaliation",
	"death_bolt_trap", "corruption_surge", "abyssal_claim", "void_collapse",
	# Neutral traps
	"hidden_ambush", "arcane_rebound",
	"null_seal", "gate_collapse",
	"trap_disruption", "smoke_veil", "hidden_cache",
	"trap_emergency_reinforcements", "shock_mine",
	# Neutral minions
	"ashland_forager", "wandering_pilgrim",
	"freelance_sellsword", "traveling_merchant", "trapbreaker_rogue", "arcane_ward_drone",
	"caravan_guard", "arena_challenger", "wandering_warden", "spell_taxer", "saboteur_adept", "aether_bulwark",
	"bronze_sentinel", "gatekeeper_golem", "bulwark_automaton", "runic_shieldbearer",
	"bastion_walker", "ruins_archivist",
	"wildland_behemoth", "iron_mountain_titan", "rift_leviathan",
	# Neutral spells
	"cyclone", "hurricane",
	"arcane_strike", "precision_strike",
	"tactical_planning", "emergency_reinforcements",
	"energy_conversion", "essence_surge",
	"battlefield_tactics", "reinforced_armor", "shield_break", "purge",
	"battlefield_salvage", "shockwave",
]

## Cards only available when the player has the piercing_void talent (Lord Vael).
const PIERCING_VOID_POOL: Array[String] = [
	"mark_the_target", "imp_combustion", "dark_ritual_of_the_abyss", "imp_overload",
	"void_channeler", "abyssal_sacrificer", "abyssal_arcanist",
	"void_detonation", "soul_rupture", "void_rain", "mark_convergence",
	"mark_collapse", "void_archmagus",
]

## Cards only available when the hero has permanently unlocked them (boss drops).
## Stored in HeroData.hero_reward_pool — no per-hero constant needed here.

var _reward_ids: Array[String] = []

func _ready() -> void:
	_pick_rewards()
	_build_card_visuals()

func _pick_rewards() -> void:
	var pool := REWARD_POOL.duplicate()
	# Add hero-specific cards that have been permanently unlocked (boss drops).
	var hero := HeroDatabase.get_hero(GameManager.current_hero)
	if hero:
		for card_id in hero.hero_reward_pool:
			if card_id in GameManager.permanent_unlocks:
				pool.append(card_id)
	# Add talent-gated support cards that have ALSO been permanently unlocked.
	# Both conditions must be true: correct talent + card in permanent_unlocks.
	if GameManager.has_talent("piercing_void"):
		for card_id in PIERCING_VOID_POOL:
			if card_id in GameManager.permanent_unlocks:
				pool.append(card_id)
	pool.shuffle()
	_reward_ids = pool.slice(0, 3)

func _build_card_visuals() -> void:
	var container := $UI/CardContainer
	for card_id in _reward_ids:
		var data := CardDatabase.get_card(card_id)
		if data == null:
			continue
		var visual: CardVisual = CardVisualScene.instantiate()
		# Make reward cards larger than hand cards
		visual.custom_minimum_size = Vector2(270, 405)
		container.add_child(visual)
		visual.setup(data)
		visual.card_clicked.connect(_on_reward_picked.bind(card_id))

func _on_reward_picked(_visual: CardVisual, card_id: String) -> void:
	GameManager.player_deck.append(card_id)
	# After completing the last fight of an act, offer a relic before returning to map
	if GameManager.is_act_complete():
		GameManager.go_to_scene("res://relics/RelicRewardScene.tscn")
	else:
		GameManager.go_to_scene("res://map/MapScene.tscn")
