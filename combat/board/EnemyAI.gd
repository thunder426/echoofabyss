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

## Emitted each time the AI summons a minion (lets CombatScene check ON_ENEMY_SUMMON traps)
signal minion_summoned(minion: MinionInstance)

## Emitted when the AI casts a spell (lets CombatScene resolve effect + check ON_ENEMY_SPELL traps)
signal enemy_spell_cast(spell: SpellCardData)

## Emitted just before an enemy minion attacks another minion
signal enemy_about_to_attack(attacker: MinionInstance, target: MinionInstance)

## Emitted just before an enemy minion attacks the player hero
signal enemy_attacking_hero(attacker: MinionInstance)

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

## Extra essence cost added to enemy spells this turn (set by Spell Taxer).
## CombatScene sets this at the start of the enemy turn and clears it after.
var spell_cost_penalty: int = 0

## Set to true by Smoke Veil trap to cancel the current attack before it resolves.
## EnemyAI checks this immediately after emitting the pre-attack signals.
var attack_cancelled: bool = false

## When non-null, Imp Barricade has redirected this attack to the given player minion.
## CombatScene sets this when resolving the ON_ENEMY_ATTACK trap.
var redirect_attack_target: MinionInstance = null

# ---------------------------------------------------------------------------
# Enemy hand
# ---------------------------------------------------------------------------

var hand: Array[CardData] = []
const HAND_MAX := 5

## Card IDs the enemy draws from each turn (weighted toward cheap minions + some spells)
const CARD_POOL: Array[String] = [
	"void_imp", "void_imp", "void_imp",
	"shadow_hound", "shadow_hound",
	"abyssal_brute",
	"shadow_bolt", "shadow_bolt",
	"void_barrage",
]

## If non-empty, overrides CARD_POOL for this encounter.
var card_pool_override: Array[String] = []

# ---------------------------------------------------------------------------
# Timing — delay between actions so the player can follow along
# ---------------------------------------------------------------------------

const ACTION_DELAY := 0.55

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

## Run a full enemy turn asynchronously, then emit ai_turn_finished.
func run_turn() -> void:
	_choose_resource_growth()
	essence = essence_max  # refill
	_draw_cards(2)
	await _play_phase()
	await _attack_phase()
	ai_turn_finished.emit()

# ---------------------------------------------------------------------------
# Resource
# ---------------------------------------------------------------------------

## Simple AI always grows Essence — override this for smarter enemy behaviour
func _choose_resource_growth() -> void:
	essence_max = mini(essence_max + 1, ESSENCE_MAX_CAP)

# ---------------------------------------------------------------------------
# Card draw
# ---------------------------------------------------------------------------

func _draw_cards(count: int) -> void:
	for _i in count:
		if hand.size() >= HAND_MAX:
			break
		var pool := card_pool_override if not card_pool_override.is_empty() else CARD_POOL
		var id: String = pool[randi() % pool.size()]
		var card := CardDatabase.get_card(id)
		if card:
			hand.append(card)

# ---------------------------------------------------------------------------
# Play phase — spend Essence on minions, cheapest first
# ---------------------------------------------------------------------------

func _play_phase() -> void:
	var made_a_play := true
	while made_a_play:
		made_a_play = false
		# Sort cheapest first: spells (by .cost) and minions (by .essence_cost)
		hand.sort_custom(func(a: CardData, b: CardData) -> bool:
			var ac: int = (a as MinionCardData).essence_cost if a is MinionCardData else a.cost
			var bc: int = (b as MinionCardData).essence_cost if b is MinionCardData else b.cost
			return ac < bc
		)
		for card in hand.duplicate():
			if card is SpellCardData:
				var spell := card as SpellCardData
				if spell.cost + spell_cost_penalty > essence:
					continue
				essence -= spell.cost
				hand.erase(card)
				enemy_spell_cast.emit(spell)
				made_a_play = true
				if not is_inside_tree():
					return
				await get_tree().create_timer(ACTION_DELAY).timeout
				if not is_inside_tree():
					return
				break
			elif card is MinionCardData:
				var minion_card := card as MinionCardData
				if minion_card.essence_cost > essence:
					continue
				var slot := _find_empty_enemy_slot()
				if slot == null:
					return  # Board is full
				essence -= minion_card.essence_cost
				var instance := MinionInstance.create(minion_card, "enemy")
				enemy_board.append(instance)
				slot.place_minion(instance)
				hand.erase(card)
				minion_summoned.emit(instance)
				made_a_play = true
				if not is_inside_tree():
					return
				await get_tree().create_timer(ACTION_DELAY).timeout
				if not is_inside_tree():
					return
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
			enemy_about_to_attack.emit(minion, target)
			# Smoke Veil or another trap may have cancelled this attack
			if attack_cancelled:
				attack_cancelled = false
				continue
			# Imp Barricade may have redirected the attack to a freshly-summoned Void Imp
			if redirect_attack_target != null:
				target = redirect_attack_target
				redirect_attack_target = null
			# Minion may have died from trap damage (e.g. Hidden Ambush) — skip if so
			if not enemy_board.has(minion):
				continue
			combat_manager.resolve_minion_attack(minion, target)
		else:
			# No player minions — attack the player hero directly
			enemy_attacking_hero.emit(minion)
			if attack_cancelled:
				attack_cancelled = false
				continue
			# Imp Barricade summoned a Void Imp — redirect the hero attack to it
			if redirect_attack_target != null:
				var barricade_target := redirect_attack_target
				redirect_attack_target = null
				if enemy_board.has(minion):
					combat_manager.resolve_minion_attack(minion, barricade_target)
				if not is_inside_tree():
					return
				await get_tree().create_timer(ACTION_DELAY).timeout
				if not is_inside_tree():
					return
				continue
			if not enemy_board.has(minion):
				continue
			combat_manager.resolve_minion_attack_hero(minion, "player")

		# Scene may have been freed by the damage signal (defeat) — guard before and after
		if not is_inside_tree():
			return
		await get_tree().create_timer(ACTION_DELAY).timeout
		if not is_inside_tree():
			return

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
