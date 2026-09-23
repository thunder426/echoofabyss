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

## Fired when the player draws a card. The scene adds it to the hand display.
signal card_drawn(card_inst: CardInstance)

## Fired when a card is generated into the hand (not drawn from deck).
signal card_generated(card_inst: CardInstance)

## Fired at the start of each player turn to clear per-turn buffs on minions.
signal player_turn_cleanup(player_board: Array[MinionInstance])

# ---------------------------------------------------------------------------
# Resource caps
# ---------------------------------------------------------------------------

const COMBINED_RESOURCE_CAP: int = CombatState.COMBINED_RESOURCE_CAP
const ESSENCE_HARD_CAP: int = CombatState.ESSENCE_HARD_CAP
const HAND_SIZE_MAX: int = CombatState.HAND_MAX

# ---------------------------------------------------------------------------
# State — façade over CombatState (LIVE_SIM_UNIFICATION_PLAN.md 1.3). The turn
# counter, resources, deck, hand and graveyard live on `state`; these forward
# so the UI keeps reading `turn_manager.essence` etc. Set by
# CombatScene._connect_turn_manager, which also relays state's player-side
# resources_changed / card_drawn / card_generated signals through this node.
# ---------------------------------------------------------------------------

var state: CombatState = null:
	set(v):
		state = v
		state.resources_changed.connect(_on_state_resources_changed)
		state.card_drawn.connect(_on_state_card_drawn)
		state.card_generated.connect(_on_state_card_generated)

var is_player_turn: bool:
	get: return state.is_player_turn
	set(v): state.is_player_turn = v
var turn_number: int:
	get: return state.turn_number
	set(v): state.turn_number = v
var essence: int:
	get: return state.player_essence
	set(v): state.player_essence = v
var essence_max: int:
	get: return state.player_essence_max
	set(v): state.player_essence_max = v
var mana: int:
	get: return state.player_mana
	set(v): state.player_mana = v
var mana_max: int:
	get: return state.player_mana_max
	set(v): state.player_mana_max = v
var player_deck: Array[CardInstance]:
	get: return state.player_deck
var player_hand: Array[CardInstance]:
	get: return state.player_hand
## Unified graveyard — every card the player plays this combat, stamped with
## `resolved_on_turn` (see CombatState.send_to_graveyard).
var player_graveyard: Array[CardInstance]:
	get: return state.player_graveyard

func _on_state_resources_changed(side: String, e: int, e_max: int, m: int, m_max: int) -> void:
	if side == "player":
		resources_changed.emit(e, e_max, m, m_max)

func _on_state_card_drawn(side: String, inst: CardInstance) -> void:
	if side == "player":
		card_drawn.emit(inst)

func _on_state_card_generated(side: String, inst: CardInstance) -> void:
	if side == "player":
		card_generated.emit(inst)

# ---------------------------------------------------------------------------
# Combat start
# ---------------------------------------------------------------------------

## Call this once when the combat scene loads to begin the first turn.
func start_combat(deck: Array[CardData]) -> void:
	state.player_deck.clear()
	for card in deck:
		state.player_deck.append(CardInstance.create(card))
	state.rng_shuffle(state.player_deck)
	state.player_hand.clear()
	state.player_graveyard.clear()
	state.turn_number = 0
	# Opening maxima are not a growth choice — write the backing fields so
	# last_player_growth stays "" until the player actually picks.
	state._player_essence_max = 1
	state._player_mana_max = 1
	# Draw opening hand (3 cards)
	state.draw_cards("player", 3)
	begin_player_turn()

# ---------------------------------------------------------------------------
# Turn flow
# ---------------------------------------------------------------------------

func begin_player_turn() -> void:
	state.is_player_turn = true
	state.turn_number += 1
	state.refill_resources("player")
	state.draw_cards("player", 1)
	_unexhaust_minions(state.player_board)
	_clear_temp_buffs(state.player_board)
	player_turn_cleanup.emit(state.player_board)
	state.emit_resources("player")
	turn_started.emit(true)

func end_player_turn() -> void:
	turn_ended.emit(true)
	begin_enemy_turn()

func begin_enemy_turn() -> void:
	state.is_player_turn = false
	_unexhaust_minions(state.enemy_board)
	_clear_temp_buffs(state.enemy_board)
	turn_started.emit(false)
	# The CombatScene / EnemyAI listens to this signal and runs AI logic,
	# then calls end_enemy_turn() when done.

func end_enemy_turn() -> void:
	turn_ended.emit(false)
	begin_player_turn()

# ---------------------------------------------------------------------------
# Resource management — player side of the CombatState mutators. The ones that
# emit on state reach the UI through _on_state_resources_changed.
# ---------------------------------------------------------------------------

## Grow Essence maximum by amount (called by CombatScene on end-turn and by card/relic effects).
func grow_essence_max(amount: int = 1) -> void:
	state.grow_essence_max("player", amount)

## Grow Mana maximum by amount (called by CombatScene on end-turn and by card effects).
func grow_mana_max(amount: int = 1) -> void:
	state.grow_mana_max("player", amount)

## True if the player can afford a card with these dual costs
func can_afford(e: int, m: int) -> bool:
	return state.can_afford("player", e, m)

func convert_essence_to_mana() -> void:
	state.convert_essence_to_mana("player")

func gain_essence(amount: int) -> void:
	state.gain_essence("player", amount)

func gain_mana(amount: int) -> void:
	state.gain_mana("player", amount)

func convert_mana_to_essence(max_convert: int = -1) -> void:
	state.convert_mana_to_essence("player", max_convert)

## Attempt to spend Abyss Essence. Returns false if not enough.
func spend_essence(amount: int) -> bool:
	return state.spend_essence("player", amount)

## Attempt to spend Mana. Returns false if not enough.
func spend_mana(amount: int) -> bool:
	return state.spend_mana("player", amount)

# ---------------------------------------------------------------------------
# Card draw
# ---------------------------------------------------------------------------

## Remove a specific card instance from the tracked hand (call when a card is played).
func remove_from_hand(inst: CardInstance) -> void:
	state.remove_from_hand("player", inst)

## Public wrapper — lets CombatScene draw an extra card (e.g. Ancient Tome relic).
func draw_card() -> void:
	state.draw_cards("player", 1)

## Add a CardData to the player's hand. Burns silently if the hand is full.
func add_to_hand(card: CardData) -> void:
	state.add_to_hand("player", card)

## Add an existing CardInstance to the player's hand. Burns silently if full.
func add_instance_to_hand(inst: CardInstance) -> void:
	state.add_to_hand("player", inst)

# ---------------------------------------------------------------------------
# Minion helpers
# ---------------------------------------------------------------------------

func _unexhaust_minions(board: Array[MinionInstance]) -> void:
	for minion in board:
		minion.on_turn_start()

func _clear_temp_buffs(board: Array[MinionInstance]) -> void:
	for minion in board:
		BuffSystem.expire_temp(minion)
