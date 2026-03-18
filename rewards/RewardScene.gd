## RewardScene.gd
## Two-phase reward flow after each combat victory:
##   Phase 1 — pick one of 3 cards (with 2-copy cap enforced).
##   Phase 2 — on fights 1,4,7,10,13: pick one special reward.
extends Node2D

const CardVisualScene := preload("res://combat/ui/CardVisual.tscn")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

## Maximum copies of any single card the player can hold.
const COPY_CAP := 2

## Fight indices (1-based) that trigger a special reward after the card pick.
const SPECIAL_REWARD_FIGHTS: Array[int] = [1, 4, 7, 10, 13]

## Variant core units — excluded from all reward pools; only granted as special rewards.
const VARIANT_CORE_UNITS: Array[String] = [
	"senior_void_imp",
	"runic_void_imp",
	"void_imp_wizard",
]

# ---------------------------------------------------------------------------
# Card reward pool
# ---------------------------------------------------------------------------

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

## Cards unlocked by the piercing_void talent.
const PIERCING_VOID_POOL: Array[String] = [
	"mark_the_target", "imp_combustion", "dark_ritual_of_the_abyss", "imp_overload",
	"void_channeler", "abyssal_sacrificer", "abyssal_arcanist",
	"void_detonation", "soul_rupture", "void_rain", "mark_convergence",
	"mark_collapse", "void_archmagus",
]

# ---------------------------------------------------------------------------
# Special reward types
# ---------------------------------------------------------------------------

enum SpecialReward {
	VARIANT_CORE_UNIT,   # Pick one of 3 variant core units (senior/runic/wizard imp)
	SUPPORT_CARD,        # Pick one unlocked support card to add permanently
	HP_RESTORE,          # Restore 500 HP
	CORE_UNIT_SLOT,      # +1 core unit limit (max 6)
	REMOVE_CARD,         # Remove one card from deck
	UPGRADE_CARD,        # Upgrade one card (placeholder)
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _reward_ids: Array[String] = []
var _phase: int = 1  # 1 = card reward, 2 = special reward

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_pick_card_rewards()
	_build_card_phase_ui()

# ---------------------------------------------------------------------------
# Phase 1 — Card reward
# ---------------------------------------------------------------------------

func _pick_card_rewards() -> void:
	var pool := _build_card_pool()
	pool.shuffle()
	_reward_ids = []
	for card_id in pool:
		if _reward_ids.size() >= 3:
			break
		# Enforce copy cap
		var copies_held := GameManager.player_deck.count(card_id)
		if copies_held >= COPY_CAP:
			continue
		_reward_ids.append(card_id)

func _build_card_pool() -> Array[String]:
	var pool: Array[String] = []
	for id in REWARD_POOL:
		if id not in VARIANT_CORE_UNITS:
			pool.append(id)
	# Add hero-specific unlocked cards
	var hero := HeroDatabase.get_hero(GameManager.current_hero)
	if hero:
		for card_id in hero.hero_reward_pool:
			if card_id in GameManager.permanent_unlocks and card_id not in VARIANT_CORE_UNITS:
				pool.append(card_id)
	# Add piercing_void talent cards
	if GameManager.has_talent("piercing_void"):
		for card_id in PIERCING_VOID_POOL:
			if card_id in GameManager.permanent_unlocks and card_id not in VARIANT_CORE_UNITS:
				pool.append(card_id)
	return pool

func _build_card_phase_ui() -> void:
	var container := $UI/CardContainer
	for child in container.get_children():
		child.queue_free()

	if _reward_ids.is_empty():
		# No valid cards — skip directly to special reward if applicable
		_on_card_phase_done()
		return

	for card_id in _reward_ids:
		var data := CardDatabase.get_card(card_id)
		if data == null:
			continue
		var visual: CardVisual = CardVisualScene.instantiate()
		visual.custom_minimum_size = Vector2(270, 405)
		container.add_child(visual)
		visual.setup(data)
		visual.card_clicked.connect(_on_reward_picked.bind(card_id))

func _on_reward_picked(_visual: CardVisual, card_id: String) -> void:
	GameManager.player_deck.append(card_id)
	_on_card_phase_done()

func _on_card_phase_done() -> void:
	var fight_idx: int = GameManager.run_node_index  # 1-based fight number
	if fight_idx in SPECIAL_REWARD_FIGHTS:
		_begin_special_reward_phase()
	elif GameManager.is_act_complete():
		GameManager.go_to_scene("res://relics/RelicRewardScene.tscn")
	else:
		GameManager.go_to_scene("res://map/MapScene.tscn")

# ---------------------------------------------------------------------------
# Phase 2 — Special reward
# ---------------------------------------------------------------------------

func _begin_special_reward_phase() -> void:
	_phase = 2
	var container := $UI/CardContainer
	for child in container.get_children():
		child.queue_free()

	var choices := _build_special_reward_choices()
	for choice in choices:
		_add_special_reward_button(container, choice)

func _build_special_reward_choices() -> Array[SpecialReward]:
	var available: Array[SpecialReward] = []

	# Variant core unit — only if player doesn't already own all 3
	var has_all_variants := true
	for id in VARIANT_CORE_UNITS:
		if GameManager.player_deck.count(id) == 0:
			has_all_variants = false
			break
	if not has_all_variants:
		available.append(SpecialReward.VARIANT_CORE_UNIT)

	# Support card — only if there are unlocked support cards not yet in deck
	if not _support_pool().is_empty():
		available.append(SpecialReward.SUPPORT_CARD)

	# HP restore — only if not at max
	if GameManager.player_hp < GameManager.player_hp_max:
		available.append(SpecialReward.HP_RESTORE)

	# Core unit slot — only if below cap
	if GameManager.core_unit_limit < 6:
		available.append(SpecialReward.CORE_UNIT_SLOT)

	# Remove card — only if deck has enough cards
	if GameManager.player_deck.size() > 5:
		available.append(SpecialReward.REMOVE_CARD)

	# Upgrade card (always available as placeholder)
	available.append(SpecialReward.UPGRADE_CARD)

	available.shuffle()
	return available.slice(0, 3)

func _support_pool() -> Array[String]:
	var pool: Array[String] = []
	for card_id in GameManager.permanent_unlocks:
		if card_id not in VARIANT_CORE_UNITS and GameManager.player_deck.count(card_id) < COPY_CAP:
			pool.append(card_id)
	return pool

func _add_special_reward_button(container: Node, reward: SpecialReward) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(320, 80)
	btn.add_theme_font_size_override("font_size", 18)
	match reward:
		SpecialReward.VARIANT_CORE_UNIT:
			btn.text = "Variant Core Unit\nChoose a variant Void Imp to add to your deck"
		SpecialReward.SUPPORT_CARD:
			btn.text = "Support Card\nAdd one of your unlocked support cards"
		SpecialReward.HP_RESTORE:
			btn.text = "Restoration\nRestore 500 HP"
		SpecialReward.CORE_UNIT_SLOT:
			btn.text = "Core Unit Slot\n+1 core unit limit"
		SpecialReward.REMOVE_CARD:
			btn.text = "Purge\nRemove one card from your deck"
		SpecialReward.UPGRADE_CARD:
			btn.text = "Upgrade\nUpgrade one card in your deck"
	btn.pressed.connect(_on_special_reward_chosen.bind(reward))
	container.add_child(btn)

func _on_special_reward_chosen(reward: SpecialReward) -> void:
	match reward:
		SpecialReward.VARIANT_CORE_UNIT:
			_show_variant_core_unit_pick()
			return
		SpecialReward.SUPPORT_CARD:
			_show_support_card_pick()
			return
		SpecialReward.HP_RESTORE:
			GameManager.player_hp = mini(GameManager.player_hp + 500, GameManager.player_hp_max)
		SpecialReward.CORE_UNIT_SLOT:
			GameManager.core_unit_limit = mini(GameManager.core_unit_limit + 1, 6)
		SpecialReward.REMOVE_CARD:
			_show_remove_card_ui()
			return
		SpecialReward.UPGRADE_CARD:
			pass  # Placeholder — go to map for now
	_finish()

func _show_variant_core_unit_pick() -> void:
	var container := $UI/CardContainer
	for child in container.get_children():
		child.queue_free()
	var options: Array[String] = []
	for id in VARIANT_CORE_UNITS:
		if GameManager.player_deck.count(id) == 0:
			options.append(id)
	for card_id in options:
		var data := CardDatabase.get_card(card_id)
		if not data:
			continue
		var visual: CardVisual = CardVisualScene.instantiate()
		visual.custom_minimum_size = Vector2(270, 405)
		container.add_child(visual)
		visual.setup(data)
		visual.card_clicked.connect(func(_v, id): GameManager.player_deck.append(id); _finish())

func _show_support_card_pick() -> void:
	var container := $UI/CardContainer
	for child in container.get_children():
		child.queue_free()
	var pool := _support_pool()
	pool.shuffle()
	var picks := pool.slice(0, 3)
	for card_id in picks:
		var data := CardDatabase.get_card(card_id)
		if not data:
			continue
		var visual: CardVisual = CardVisualScene.instantiate()
		visual.custom_minimum_size = Vector2(270, 405)
		container.add_child(visual)
		visual.setup(data)
		visual.card_clicked.connect(func(_v, id): GameManager.player_deck.append(id); _finish())

func _show_remove_card_ui() -> void:
	var container := $UI/CardContainer
	for child in container.get_children():
		child.queue_free()
	var unique_ids: Array[String] = []
	for id in GameManager.player_deck:
		if id not in unique_ids:
			unique_ids.append(id)
	for card_id in unique_ids:
		var btn := Button.new()
		var data := CardDatabase.get_card(card_id)
		btn.text = data.card_name if data else card_id
		btn.custom_minimum_size = Vector2(0, 48)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(func():
			var idx := GameManager.player_deck.find(card_id)
			if idx >= 0:
				GameManager.player_deck.remove_at(idx)
			_finish()
		)
		container.add_child(btn)

func _finish() -> void:
	if GameManager.is_act_complete():
		GameManager.go_to_scene("res://relics/RelicRewardScene.tscn")
	else:
		GameManager.go_to_scene("res://map/MapScene.tscn")
