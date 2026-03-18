## TurnManager.gd
## Manages the turn cycle, resource growth, and phase transitions.
## Attach this as a Node child of the CombatScene.
## CombatScene listens to its signals to update UI and trigger AI.
class_name TurnManager
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Fired at the start of a turn. is_player_turn = true means it's the player's turn.
signal turn_started(is_player_turn: bool)

## Fired at the end of a turn.
signal turn_ended(is_player_turn: bool)

## Fired whenever resources change so the UI can update its display.
signal resources_changed(essence: int, essence_max: int, mana: int, mana_max: int)

## Fired when the player draws a card. The scene adds it to the hand.
signal card_drawn(card_data: CardData)

## Fired at the start of each player turn to clear per-turn buffs on minions.
signal player_turn_cleanup(player_board: Array[MinionInstance])

# ---------------------------------------------------------------------------
# Resource caps
# ---------------------------------------------------------------------------

## Combined essence_max + mana_max can never exceed this.
const COMBINED_RESOURCE_CAP: int = 11

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var is_player_turn: bool = true
var turn_number: int = 0

# Current pool and maximums — updated each turn
var essence: int = 0
var essence_max: int = 0
var mana: int = 0
var mana_max: int = 0

# References set by CombatScene on ready
var player_deck: Array[CardData] = []
var player_hand: Array[CardData] = []
var player_board: Array[MinionInstance] = []
var enemy_board: Array[MinionInstance] = []

# Max hand size
const HAND_SIZE_MAX: int = 10

# ---------------------------------------------------------------------------
# Combat start
# ---------------------------------------------------------------------------

## Call this once when the combat scene loads to begin the first turn.
func start_combat(deck: Array[CardData]) -> void:
	player_deck = deck.duplicate()
	player_deck.shuffle()
	player_hand.clear()
	turn_number = 0
	essence_max = 1
	mana_max = 1
	# Draw opening hand (3 cards)
	for i in 3:
		_draw_card()
	begin_player_turn()

# ---------------------------------------------------------------------------
# Turn flow
# ---------------------------------------------------------------------------

func begin_player_turn() -> void:
	is_player_turn = true
	turn_number += 1
	_refill_resources()
	_draw_card()
	_unexhaust_minions(player_board)
	_clear_temp_buffs(player_board)
	player_turn_cleanup.emit(player_board)
	resources_changed.emit(essence, essence_max, mana, mana_max)
	turn_started.emit(true)

func end_player_turn() -> void:
	turn_ended.emit(true)
	begin_enemy_turn()

func begin_enemy_turn() -> void:
	is_player_turn = false
	_unexhaust_minions(enemy_board)
	_clear_temp_buffs(enemy_board)
	turn_started.emit(false)
	# The CombatScene / EnemyAI listens to this signal and runs AI logic,
	# then calls end_enemy_turn() when done.

func end_enemy_turn() -> void:
	turn_ended.emit(false)
	begin_player_turn()

# ---------------------------------------------------------------------------
# Resource management
# ---------------------------------------------------------------------------

func _refill_resources() -> void:
	essence = essence_max
	mana = mana_max

## Grow Essence maximum by 1 (called by CombatScene when player clicks End Turn + Essence)
func grow_essence_max() -> void:
	if essence_max + mana_max < COMBINED_RESOURCE_CAP:
		essence_max += 1

## Grow Mana maximum by 1 (called by CombatScene when player clicks End Turn + Mana)
func grow_mana_max() -> void:
	if essence_max + mana_max < COMBINED_RESOURCE_CAP:
		mana_max += 1

## True if the player can afford a card with these dual costs
func can_afford(e: int, m: int) -> bool:
	return essence >= e and mana >= m

## Convert all current Essence into Mana (up to mana_max cap).
## Used by the Energy Conversion neutral spell.
func convert_essence_to_mana() -> void:
	var amount := essence
	essence = 0
	mana = mini(mana + amount, mana_max)
	resources_changed.emit(essence, essence_max, mana, mana_max)

## Grant bonus Essence this turn (ignores essence_max cap since it's temporary).
## Used by Essence Surge; resets naturally when the turn ends and _refill_resources() runs.
func gain_essence(amount: int) -> void:
	essence += amount
	resources_changed.emit(essence, essence_max, mana, mana_max)

## Grant bonus Mana this turn (capped at mana_max).
func gain_mana(amount: int) -> void:
	mana = mini(mana + amount, mana_max)
	resources_changed.emit(essence, essence_max, mana, mana_max)

## Convert all current Mana into Essence (up to essence_max cap)
func convert_mana_to_essence() -> void:
	var amount := mana
	mana = 0
	essence = mini(essence + amount, essence_max)
	resources_changed.emit(essence, essence_max, mana, mana_max)

## Attempt to spend Abyss Essence. Returns false if not enough.
func spend_essence(amount: int) -> bool:
	if essence < amount:
		return false
	essence -= amount
	resources_changed.emit(essence, essence_max, mana, mana_max)
	return true

## Attempt to spend Mana. Returns false if not enough.
func spend_mana(amount: int) -> bool:
	if mana < amount:
		return false
	mana -= amount
	resources_changed.emit(essence, essence_max, mana, mana_max)
	return true

# ---------------------------------------------------------------------------
# Card draw
# ---------------------------------------------------------------------------

## Remove a card from the tracked hand (call whenever a card is played).
func remove_from_hand(card: CardData) -> void:
	player_hand.erase(card)

## Public wrapper — lets CombatScene draw an extra card (e.g. Ancient Tome relic).
func draw_card() -> void:
	_draw_card()

## Add a specific card directly to the player's hand (e.g. Abyssal Arcanist, Void Archmagus).
## Burns silently if the hand is already full.
func add_to_hand(card: CardData) -> void:
	if player_hand.size() >= HAND_SIZE_MAX:
		return
	player_hand.append(card)
	card_drawn.emit(card)

func _draw_card() -> void:
	if player_deck.is_empty():
		# TODO: fatigue damage when deck runs out
		return
	if player_hand.size() >= HAND_SIZE_MAX:
		# Card is burned — drawn but discarded immediately
		player_deck.pop_front()
		return
	var card: CardData = player_deck.pop_front()
	player_hand.append(card)
	card_drawn.emit(card)

# ---------------------------------------------------------------------------
# Minion helpers
# ---------------------------------------------------------------------------

func _unexhaust_minions(board: Array[MinionInstance]) -> void:
	for minion in board:
		minion.on_turn_start()

func _clear_temp_buffs(board: Array[MinionInstance]) -> void:
	for minion in board:
		BuffSystem.expire_temp(minion)
