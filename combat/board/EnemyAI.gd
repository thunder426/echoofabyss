## EnemyAI.gd
## Simple reactive enemy AI.
## CombatScene calls run_turn() when the enemy turn starts.
## The AI plays minions, attacks, then emits ai_turn_finished when done.
class_name EnemyAI
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the AI has finished all its actions for this turn
signal ai_turn_finished()

# ---------------------------------------------------------------------------
# References — set by CombatScene before start_combat()
# ---------------------------------------------------------------------------

var enemy_board: Array[MinionInstance]
var player_board: Array[MinionInstance]
var enemy_slots: Array[BoardSlot]
var combat_manager: CombatManager

# ---------------------------------------------------------------------------
# Enemy resources (grows independently of the player)
# ---------------------------------------------------------------------------

var essence: int = 0
var essence_max: int = 0
const ESSENCE_MAX_CAP := 10

# ---------------------------------------------------------------------------
# Enemy hand
# ---------------------------------------------------------------------------

var hand: Array[MinionCardData] = []
const HAND_MAX := 5

## Card IDs the enemy draws from each turn (weighted toward cheap minions)
const CARD_POOL: Array[String] = [
	"void_imp", "void_imp", "void_imp",
	"shadow_hound", "shadow_hound",
	"abyssal_brute",
]

# ---------------------------------------------------------------------------
# Timing — delay between actions so the player can follow along
# ---------------------------------------------------------------------------

const ACTION_DELAY := 0.55

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

## Run a full enemy turn asynchronously, then emit ai_turn_finished.
func run_turn() -> void:
	_grow_essence()
	_draw_cards(2)
	await _play_phase()
	await _attack_phase()
	ai_turn_finished.emit()

# ---------------------------------------------------------------------------
# Resource
# ---------------------------------------------------------------------------

func _grow_essence() -> void:
	essence_max = mini(essence_max + 1, ESSENCE_MAX_CAP)
	essence = essence_max

# ---------------------------------------------------------------------------
# Card draw
# ---------------------------------------------------------------------------

func _draw_cards(count: int) -> void:
	for _i in count:
		if hand.size() >= HAND_MAX:
			break
		var id: String = CARD_POOL[randi() % CARD_POOL.size()]
		var card := CardDatabase.get_card(id) as MinionCardData
		if card:
			hand.append(card)

# ---------------------------------------------------------------------------
# Play phase — spend Essence on minions, cheapest first
# ---------------------------------------------------------------------------

func _play_phase() -> void:
	# Sort hand cheapest first so we fill the board efficiently
	hand.sort_custom(func(a, b): return a.cost < b.cost)

	var made_a_play := true
	while made_a_play:
		made_a_play = false
		for card in hand.duplicate():
			if card.cost > essence:
				continue
			var slot := _find_empty_enemy_slot()
			if slot == null:
				return  # Board is full
			essence -= card.cost
			var instance := MinionInstance.create(card, "enemy")
			enemy_board.append(instance)
			slot.place_minion(instance)
			hand.erase(card)
			made_a_play = true
			await get_tree().create_timer(ACTION_DELAY).timeout
			# Re-sort after each play in case costs vary
			hand.sort_custom(func(a, b): return a.cost < b.cost)
			break  # Restart the loop with the updated hand

# ---------------------------------------------------------------------------
# Attack phase — every ready minion attacks
# ---------------------------------------------------------------------------

func _attack_phase() -> void:
	# Snapshot the board so removals mid-loop are safe
	for minion in enemy_board.duplicate():
		if not enemy_board.has(minion):
			continue  # Vanished due to a counter-attack earlier this phase
		if not minion.can_attack():
			continue

		var target := _pick_player_target()
		if target != null:
			combat_manager.resolve_minion_attack(minion, target)
		else:
			# No player minions — attack the player hero directly
			combat_manager.resolve_minion_attack_hero(minion, "player")

		await get_tree().create_timer(ACTION_DELAY).timeout

# ---------------------------------------------------------------------------
# Target selection
# ---------------------------------------------------------------------------

func _find_empty_enemy_slot() -> BoardSlot:
	for slot in enemy_slots:
		if slot.is_empty():
			return slot
	return null

func _pick_player_target() -> MinionInstance:
	if player_board.is_empty():
		return null
	# Must attack a Taunt minion if any exist
	var taunts := CombatManager.get_taunt_minions(player_board)
	if not taunts.is_empty():
		return taunts[randi() % taunts.size()]
	# Otherwise pick a random player minion
	return player_board[randi() % player_board.size()]
