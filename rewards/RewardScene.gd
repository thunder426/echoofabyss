## RewardScene.gd
## After each combat victory: pick one of 3 cards.
extends Node2D

const CardVisualScene := preload("res://combat/ui/CardVisual.tscn")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

## Maximum copies of any single card the player can hold.
const COPY_CAP := 2

## Variant core units — excluded from all reward pools.
const VARIANT_CORE_UNITS: Array[String] = [
	"senior_void_imp",
	"runic_void_imp",
	"void_imp_wizard",
]

## Pool names that make up the always-available core card pool.
const CORE_POOL_NAMES: Array[String] = ["abyss_core", "neutral_core"]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _reward_ids: Array[String] = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_pick_card_rewards()
	_build_card_phase_ui()

# ---------------------------------------------------------------------------
# Card reward
# ---------------------------------------------------------------------------

func _pick_card_rewards() -> void:
	# Use support pool only if we just won a boss fight; otherwise use full normal pool
	var prev_fight := GameManager.run_node_index - 1
	var pool := _build_boss_pool() if prev_fight in GameManager.BOSS_INDICES else _build_normal_pool()
	pool.shuffle()
	_reward_ids = []
	for card_id in pool:
		if _reward_ids.size() >= 3:
			break
		if GameManager.player_deck.count(card_id) >= COPY_CAP:
			continue
		if CardDatabase.get_card(card_id) == null:
			continue
		_reward_ids.append(card_id)

## Normal fight pool: core cards + all unlocked support pool cards for active talents.
func _build_normal_pool() -> Array[String]:
	var pool: Array[String] = []
	for id in CardDatabase.get_card_ids_in_pools(CORE_POOL_NAMES):
		if id not in VARIANT_CORE_UNITS and not _is_champion(id):
			pool.append(id)
	for card_id in _get_active_support_pool_ids():
		if card_id in GameManager.permanent_unlocks and card_id not in VARIANT_CORE_UNITS and not _is_champion(card_id):
			pool.append(card_id)
	return pool

## Boss fight pool: only the active support pool (talent branch cards that are unlocked).
## Falls back to core pool if nothing is unlocked.
func _build_boss_pool() -> Array[String]:
	var pool: Array[String] = []
	for card_id in _get_active_support_pool_ids():
		if card_id in GameManager.permanent_unlocks and card_id not in VARIANT_CORE_UNITS and not _is_champion(card_id):
			pool.append(card_id)
	if pool.is_empty():
		for id in CardDatabase.get_card_ids_in_pools(CORE_POOL_NAMES):
			if id not in VARIANT_CORE_UNITS and not _is_champion(id):
				pool.append(id)
	return pool

func _is_champion(card_id: String) -> bool:
	var card: CardData = CardDatabase.get_card(card_id)
	return card is MinionCardData and card.is_champion

## Returns card IDs from all support pools active in this run (based on hero + talents taken).
func _get_active_support_pool_ids() -> Array[String]:
	var ids: Array[String] = []
	if GameManager.current_hero == "lord_vael":
		ids.append_array(CardDatabase.get_card_ids_in_pools(["vael_common"]))
		if GameManager.has_talent("piercing_void"):
			ids.append_array(CardDatabase.get_card_ids_in_pools(["vael_piercing_void"]))
		if GameManager.has_talent("imp_evolution"):
			ids.append_array(CardDatabase.get_card_ids_in_pools(["vael_endless_tide"]))
		if GameManager.has_talent("rune_caller"):
			ids.append_array(CardDatabase.get_card_ids_in_pools(["vael_rune_master"]))
	elif GameManager.current_hero == "seris":
		ids.append_array(CardDatabase.get_card_ids_in_pools(["seris_starter"]))
	return ids

func _build_card_phase_ui() -> void:
	var container := $UI/CardContainer
	for child in container.get_children():
		child.queue_free()

	if _reward_ids.is_empty():
		_finish()
		return

	for card_id in _reward_ids:
		var data := CardDatabase.get_card(card_id)
		if data == null:
			continue
		var visual: CardVisual = CardVisualScene.instantiate()
		visual.apply_size_mode("reward")
		container.add_child(visual)
		visual.setup(data)
		visual.card_clicked.connect(_on_reward_picked.bind(card_id))

func _on_reward_picked(_visual: CardVisual, card_id: String) -> void:
	GameManager.player_deck.append(card_id)
	_finish()

func _finish() -> void:
	if GameManager.is_act_complete():
		GameManager.go_to_scene("res://relics/RelicRewardScene.tscn")
	elif GameManager.run_node_index in GameManager.BOSS_INDICES:
		# Next fight is the act boss — visit the shop first
		GameManager.go_to_scene("res://shop/ShopScene.tscn")
	else:
		GameManager.go_to_scene("res://map/EncounterLoadingScene.tscn")
