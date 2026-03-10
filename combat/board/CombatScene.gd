## CombatScene.gd
## Root script for the combat scene.
## Wires together TurnManager, CombatManager, BoardSlots, and the UI.
## Handles player input (selecting cards, selecting targets, attacking).
extends Node2D

# ---------------------------------------------------------------------------
# Node references — resolved automatically in _find_nodes()
# ---------------------------------------------------------------------------

var turn_manager: TurnManager
var enemy_ai: EnemyAI
var player_slots: Array[BoardSlot] = []
var enemy_slots: Array[BoardSlot] = []

# UI nodes
var essence_label: Label
var mana_label: Label
var end_turn_button: Button
var player_hp_label: Label
var enemy_hp_label: Label
var hand_display: HandDisplay
var enemy_hero_button: Button
var trap_zone_label: Label
var hero_power_button: Button
var game_over_panel: Panel
var game_over_label: Label
var restart_button: Button

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var combat_manager := CombatManager.new()

# Live boards
var player_board: Array[MinionInstance] = []
var enemy_board: Array[MinionInstance] = []

# Player HP
var player_hp: int = 30
var enemy_hp: int = 30

# Currently selected attacker (if player clicked one of their minions)
var selected_attacker: MinionInstance = null

# Card the player is currently trying to play (dragged or clicked from hand)
var pending_play_card: CardData = null

# Whether the hero power has been used this turn
var hero_power_used: bool = false

# Active global environment
var active_environment: EnvironmentCardData = null

# Active face-down traps
var active_traps: Array[TrapCardData] = []

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_find_nodes()
	_connect_turn_manager()
	_connect_board_slots()
	_connect_combat_manager()
	_connect_ui()

	# If no run is active (e.g. launched directly for testing), start one now
	if not GameManager.run_active:
		GameManager.start_new_run()

	# Build the deck from GameManager and begin combat
	var deck_ids: Array[String] = GameManager.player_deck
	var deck: Array[CardData] = CardDatabase.get_cards(deck_ids)
	turn_manager.player_board = player_board
	turn_manager.enemy_board = enemy_board
	_setup_enemy_ai()
	turn_manager.start_combat(deck)

func _find_nodes() -> void:
	turn_manager      = $TurnManager
	enemy_ai          = $EnemyAI
	essence_label     = $UI/EssenceLabel
	mana_label        = $UI/ManaLabel
	end_turn_button   = $UI/EndTurnButton
	player_hp_label   = $UI/PlayerHP
	enemy_hp_label    = $UI/EnemyHP
	hand_display      = $UI/HandDisplay
	enemy_hero_button = $UI/EnemyHeroButton
	trap_zone_label   = $UI/TrapZoneLabel
	hero_power_button = $UI/HeroPowerButton
	game_over_panel   = $UI/GameOverPanel
	game_over_label   = $UI/GameOverPanel/GameOverLabel
	restart_button    = $UI/GameOverPanel/RestartButton
	for i in 5:
		player_slots.append($UI/PlayerBoard.get_child(i) as BoardSlot)
		enemy_slots.append($UI/EnemyBoard.get_child(i) as BoardSlot)

# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func _setup_enemy_ai() -> void:
	enemy_ai.enemy_board   = enemy_board
	enemy_ai.player_board  = player_board
	enemy_ai.enemy_slots   = enemy_slots
	enemy_ai.combat_manager = combat_manager
	enemy_ai.ai_turn_finished.connect(turn_manager.end_enemy_turn)

func _connect_turn_manager() -> void:
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.resources_changed.connect(_on_resources_changed)
	turn_manager.card_drawn.connect(_on_card_drawn)

func _connect_board_slots() -> void:
	for i in player_slots.size():
		player_slots[i].slot_owner = "player"
		player_slots[i].index = i
		player_slots[i].slot_clicked_empty.connect(_on_player_slot_clicked_empty)
		player_slots[i].slot_clicked_occupied.connect(_on_player_slot_clicked_occupied)
	for i in enemy_slots.size():
		enemy_slots[i].slot_owner = "enemy"
		enemy_slots[i].index = i
		enemy_slots[i].slot_clicked_occupied.connect(_on_enemy_slot_clicked)

func _connect_combat_manager() -> void:
	combat_manager.attack_resolved.connect(_on_attack_resolved)
	combat_manager.minion_vanished.connect(_on_minion_vanished)
	combat_manager.hero_damaged.connect(_on_hero_damaged)
	combat_manager.hero_healed.connect(_on_hero_healed)

func _connect_ui() -> void:
	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_pressed)
	if hand_display:
		hand_display.card_selected.connect(_on_hand_card_selected)
		hand_display.card_deselected.connect(_on_hand_card_deselected)
	if enemy_hero_button:
		enemy_hero_button.pressed.connect(_on_enemy_hero_button_pressed)
	if hero_power_button:
		hero_power_button.pressed.connect(_on_hero_power_pressed)
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)

# ---------------------------------------------------------------------------
# Turn events
# ---------------------------------------------------------------------------

func _on_turn_started(is_player_turn: bool) -> void:
	hero_power_used = false
	end_turn_button.disabled = not is_player_turn
	if hero_power_button:
		hero_power_button.disabled = not is_player_turn
	# Refresh all player slot visuals so Exhausted badge clears at turn start
	for slot in player_slots:
		if not slot.is_empty():
			slot._refresh_visuals()
	if not is_player_turn:
		await get_tree().create_timer(0.4).timeout  # brief pause before AI acts
		enemy_ai.run_turn()

func _on_turn_ended(_is_player_turn: bool) -> void:
	_clear_all_highlights()
	_show_hero_button(false)
	selected_attacker = null
	pending_play_card = null

func _on_resources_changed(essence: int, essence_max: int, mana: int, mana_max: int) -> void:
	if essence_label:
		essence_label.text = "Essence: %d / %d" % [essence, essence_max]
	if mana_label:
		mana_label.text = "Mana: %d / %d" % [mana, mana_max]
	if hand_display:
		hand_display.refresh_playability(essence, mana)
	if hero_power_button and not hero_power_used:
		hero_power_button.disabled = not turn_manager.is_player_turn or mana < 2

func _on_card_drawn(card_data: CardData) -> void:
	if hand_display:
		hand_display.add_card(card_data)

func _on_end_turn_pressed() -> void:
	selected_attacker = null
	pending_play_card = null
	if hand_display:
		hand_display.deselect_current()
	turn_manager.end_player_turn()

# ---------------------------------------------------------------------------
# Hand card selection
# ---------------------------------------------------------------------------

func _on_hand_card_selected(card_data: CardData) -> void:
	selected_attacker = null
	_clear_all_highlights()
	pending_play_card = card_data

	if card_data is SpellCardData:
		var spell := card_data as SpellCardData
		if spell.requires_target:
			_highlight_spell_targets(spell)
		else:
			_try_play_spell(spell)
		return

	if card_data is TrapCardData:
		_try_play_trap(card_data as TrapCardData)
		return

	if card_data is EnvironmentCardData:
		_try_play_environment(card_data as EnvironmentCardData)
		return

	if card_data is MinionCardData:
		_highlight_empty_player_slots()

func _on_hand_card_deselected() -> void:
	pending_play_card = null
	_clear_all_highlights()

# ---------------------------------------------------------------------------
# Spell / Trap / Environment play
# ---------------------------------------------------------------------------

func _try_play_spell(spell: SpellCardData) -> void:
	if not turn_manager.spend_mana(spell.cost):
		if hand_display:
			hand_display.deselect_current()
		return
	_resolve_spell_effect(spell.effect_id, null)
	if hand_display:
		hand_display.remove_card(spell)
		hand_display.deselect_current()
	pending_play_card = null

func _try_play_trap(trap: TrapCardData) -> void:
	if not turn_manager.spend_mana(trap.cost):
		if hand_display:
			hand_display.deselect_current()
		return
	active_traps.append(trap)
	_update_trap_display()
	if hand_display:
		hand_display.remove_card(trap)
		hand_display.deselect_current()
	pending_play_card = null

func _try_play_environment(env: EnvironmentCardData) -> void:
	if not turn_manager.spend_mana(env.cost):
		if hand_display:
			hand_display.deselect_current()
		return
	active_environment = env
	# TODO: trigger on_replace_effect for old environment, on_enter_effect for new
	if hand_display:
		hand_display.remove_card(env)
		hand_display.deselect_current()
	pending_play_card = null

# ---------------------------------------------------------------------------
# Player input — board slot clicks
# ---------------------------------------------------------------------------

func _on_player_slot_clicked_empty(slot: BoardSlot) -> void:
	# If a minion card is pending to be played, place it here
	if pending_play_card and pending_play_card is MinionCardData:
		_try_play_minion(pending_play_card as MinionCardData, slot)
		pending_play_card = null
		_clear_all_highlights()

func _on_player_slot_clicked_occupied(_slot: BoardSlot, minion: MinionInstance) -> void:
	if not turn_manager.is_player_turn:
		return
	# If a targeted spell is waiting for a target, apply it
	if pending_play_card is SpellCardData:
		var spell := pending_play_card as SpellCardData
		if spell.requires_target and _is_valid_spell_target(minion, spell.target_type):
			_apply_targeted_spell(spell, minion)
			return
	# Select this minion as the attacker if it can attack
	if minion.can_attack():
		selected_attacker = minion
		_highlight_valid_attack_targets()
	else:
		selected_attacker = null
		_clear_all_highlights()

func _on_enemy_slot_clicked(_slot: BoardSlot, minion: MinionInstance) -> void:
	if not turn_manager.is_player_turn or selected_attacker == null:
		return
	# Enforce Taunt — must attack a Taunt minion if one exists
	if CombatManager.board_has_taunt(enemy_board) and not minion.has_taunt():
		return  # Invalid target
	combat_manager.resolve_minion_attack(selected_attacker, minion)
	selected_attacker = null
	_clear_all_highlights()

# ---------------------------------------------------------------------------
# Minion play
# ---------------------------------------------------------------------------

func _try_play_minion(card: MinionCardData, slot: BoardSlot) -> void:
	if not slot.is_empty():
		return
	if not turn_manager.spend_essence(card.cost):
		return
	var instance := MinionInstance.create(card, "player")
	player_board.append(instance)
	slot.place_minion(instance)
	if hand_display:
		hand_display.remove_card(card)
		hand_display.deselect_current()
	_resolve_on_play_effect(card.on_play_effect, instance)

func _resolve_on_play_effect(effect_id: String, source: MinionInstance) -> void:
	match effect_id:
		"deal_1_enemy_hero":
			_on_hero_damaged("enemy", 1)
		"shadow_hound_atk_bonus":
			var bonus := 0
			for minion in player_board:
				if minion != source and minion.card_data.minion_type == Enums.MinionType.DEMON:
					bonus += 1
			if bonus > 0:
				source.current_atk += bonus
				_refresh_slot_for(source)

# ---------------------------------------------------------------------------
# Combat manager events
# ---------------------------------------------------------------------------

func _on_attack_resolved(attacker: MinionInstance, defender: MinionInstance) -> void:
	_refresh_slot_for(attacker)
	_refresh_slot_for(defender)

func _on_minion_vanished(minion: MinionInstance) -> void:
	# Remove from the appropriate board array and clear its slot
	if minion.owner == "player":
		player_board.erase(minion)
		_clear_slot_for(minion, player_slots)
	else:
		enemy_board.erase(minion)
		_clear_slot_for(minion, enemy_slots)

func _on_hero_damaged(target: String, amount: int) -> void:
	if target == "player":
		player_hp -= amount
		if player_hp_label:
			player_hp_label.text = "HP: %d" % player_hp
		if player_hp <= 0:
			_on_defeat()
	else:
		enemy_hp -= amount
		if enemy_hp_label:
			enemy_hp_label.text = "HP: %d" % enemy_hp
		if enemy_hp <= 0:
			_on_victory()

func _on_hero_healed(target: String, amount: int) -> void:
	if target == "player":
		player_hp = mini(player_hp + amount, GameManager.player_hp_max)
		if player_hp_label:
			player_hp_label.text = "HP: %d" % player_hp

# ---------------------------------------------------------------------------
# Targeted spell helpers
# ---------------------------------------------------------------------------

## Highlight player slots that have a minion matching the spell's target_type
func _highlight_spell_targets(spell: SpellCardData) -> void:
	_clear_all_highlights()
	for slot in player_slots:
		if not slot.is_empty() and _is_valid_spell_target(slot.minion, spell.target_type):
			slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET)
	# Also allow enemy targets if the spell targets enemy minions
	if spell.target_type == "enemy_minion":
		for slot in enemy_slots:
			if not slot.is_empty():
				slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET)

func _is_valid_spell_target(minion: MinionInstance, target_type: String) -> bool:
	match target_type:
		"friendly_demon":  return minion.card_data.minion_type == Enums.MinionType.DEMON
		"friendly_minion": return true
		"enemy_minion":    return true
	return false

## Spend mana, resolve the effect on the target, then remove the card
func _apply_targeted_spell(spell: SpellCardData, target: MinionInstance) -> void:
	if not turn_manager.spend_mana(spell.cost):
		if hand_display:
			hand_display.deselect_current()
		return
	_resolve_spell_effect(spell.effect_id, target)
	if hand_display:
		hand_display.remove_card(spell)
		hand_display.deselect_current()
	pending_play_card = null
	_clear_all_highlights()

## Apply a spell's effect. target is null for untargeted spells.
func _resolve_spell_effect(effect_id: String, target: MinionInstance) -> void:
	match effect_id:
		"soul_leech_effect":
			if target:
				target.current_atk += 1
				target.current_health += 1
				_refresh_slot_for(target)
				_on_hero_healed("player", 1)
		"dark_surge_effect":
			for minion in player_board:
				if minion.card_data.minion_type == Enums.MinionType.DEMON:
					minion.temp_atk_bonus += 1
					_refresh_slot_for(minion)

# ---------------------------------------------------------------------------
# Trap helpers
# ---------------------------------------------------------------------------

func _update_trap_display() -> void:
	if not trap_zone_label:
		return
	if active_traps.is_empty():
		trap_zone_label.text = ""
		return
	var lines: Array[String] = []
	for trap in active_traps:
		lines.append("- " + trap.card_name)
	trap_zone_label.text = "Active Traps:\n" + "\n".join(lines)

# ---------------------------------------------------------------------------
# Hero attack helpers
# ---------------------------------------------------------------------------

func _show_hero_button(visible_state: bool) -> void:
	if enemy_hero_button:
		enemy_hero_button.visible = visible_state

# ---------------------------------------------------------------------------
# Hero power
# ---------------------------------------------------------------------------

func _on_hero_power_pressed() -> void:
	if hero_power_used or not turn_manager.is_player_turn:
		return
	# Find the first empty player slot
	var empty_slot: BoardSlot = null
	for slot in player_slots:
		if slot.is_empty():
			empty_slot = slot
			break
	if empty_slot == null:
		return  # Board is full
	if not turn_manager.spend_mana(2):
		return  # Not enough mana
	hero_power_used = true
	if hero_power_button:
		hero_power_button.disabled = true
	var spirit_data := CardDatabase.get_card("wandering_spirit") as MinionCardData
	if spirit_data == null:
		return
	var instance := MinionInstance.create(spirit_data, "player")
	player_board.append(instance)
	empty_slot.place_minion(instance)

func _on_enemy_hero_button_pressed() -> void:
	if not turn_manager.is_player_turn or selected_attacker == null:
		return
	if CombatManager.board_has_taunt(enemy_board):
		return
	combat_manager.resolve_minion_attack_hero(selected_attacker, "enemy")
	selected_attacker = null
	_clear_all_highlights()
	_show_hero_button(false)

# ---------------------------------------------------------------------------
# Win / loss
# ---------------------------------------------------------------------------

func _on_victory() -> void:
	GameManager.end_run(true)
	_show_game_over("VICTORY!")

func _on_defeat() -> void:
	GameManager.end_run(false)
	_show_game_over("DEFEAT")

func _show_game_over(message: String) -> void:
	end_turn_button.disabled = true
	if hero_power_button:
		hero_power_button.disabled = true
	_show_hero_button(false)
	if game_over_label:
		game_over_label.text = message
	if game_over_panel:
		game_over_panel.visible = true

func _on_restart_pressed() -> void:
	GameManager.start_new_run()
	get_tree().reload_current_scene()

# ---------------------------------------------------------------------------
# Visual helpers
# ---------------------------------------------------------------------------

func _refresh_slot_for(minion: MinionInstance) -> void:
	var slots := player_slots if minion.owner == "player" else enemy_slots
	for slot in slots:
		if slot.minion == minion:
			slot._refresh_visuals()
			return

func _clear_slot_for(minion: MinionInstance, slots: Array[BoardSlot]) -> void:
	for slot in slots:
		if slot.minion == minion:
			slot.remove_minion()
			return

func _clear_all_highlights() -> void:
	for slot in player_slots:
		slot.clear_highlight()
	for slot in enemy_slots:
		slot.clear_highlight()

func _highlight_empty_player_slots() -> void:
	_clear_all_highlights()
	for slot in player_slots:
		if slot.is_empty():
			slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET)

func _highlight_valid_attack_targets() -> void:
	_clear_all_highlights()
	if selected_attacker == null:
		return
	var has_taunt := CombatManager.board_has_taunt(enemy_board)
	for slot in enemy_slots:
		if slot.is_empty():
			continue
		var valid := (not has_taunt) or slot.minion.has_taunt()
		slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET if valid else BoardSlot.HighlightMode.INVALID)
	# Hero is a valid target only when no enemy Taunt minion blocks it
	_show_hero_button(not has_taunt)
