## CombatScene.gd
## Root script for the combat scene.
## Wires together TurnManager, CombatManager, BoardSlots, and the UI.
## Handles player input (selecting cards, selecting targets, attacking).
extends Node2D

const CARD_VISUAL_SCENE := preload("res://combat/ui/CardVisual.tscn")

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
var end_turn_essence_button: Button
var end_turn_mana_button: Button
var player_hp_label: Label
var enemy_hp_label: Label
var enemy_name_label: Label
var fight_label: Label
var hand_display: HandDisplay
var enemy_hero_button: Button
var environment_slot: Panel
var environment_slot_name: Label
var environment_slot_desc: Label
var trap_slot_panels: Array[Panel] = []
var trap_slot_labels: Array[Label]  = []
var enemy_trap_slot_panels: Array[Panel] = []
var enemy_trap_slot_labels: Array[Label]  = []
var turn_label: Label
var deck_count_label: Label
var _hp_panel: Panel      = null  # Repurposed as Hero Passives info panel
var _hp_desc_label: Label = null
var game_over_panel: Panel
var game_over_label: Label
var restart_button: Button
var _log_scroll: ScrollContainer = null
var _log_container: VBoxContainer = null
var _large_preview: CardVisual = null

# Enemy hero status panel (built programmatically)
var _enemy_status_panel: Panel = null
var _enemy_status_hp_label: Label = null
var _enemy_status_essence_label: Label = null
var _enemy_status_marks_label: Label = null
var enemy_hp_max: int = 0

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var combat_manager := CombatManager.new()

## Central event dispatcher — populated by _setup_triggers() in _ready().
var trigger_manager: TriggerManager

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

# Active global environment
var active_environment: EnvironmentCardData = null

# Active traps and runes (shared pool, max 3 slots)
var active_traps: Array[TrapCardData] = []
# Callables registered for the current environment's 2-rune rituals.
# Cleared and re-populated whenever the active environment changes.
var _env_ritual_handlers: Array[Callable] = []
# TriggerManager Callables registered per rune placement.
# Stored as an Array of {rune_id, entries} so two runes of the same type each
# get an independent entry and can be individually unregistered.
var _rune_aura_handlers: Array = []  # Array[{rune_id: String, entries: Array}]

# ---------------------------------------------------------------------------
# Relic state — reset each combat
# ---------------------------------------------------------------------------

## True until the first card is played this turn (Void Crystal: first card free)
var _relic_first_card_free: bool = false

# ---------------------------------------------------------------------------
# Talent state — reset each combat
# ---------------------------------------------------------------------------

## Void Mark stacks on the enemy hero (accumulate through the run)
var enemy_void_marks: int = 0

## True until the first hit lands on the player (Shadow Veil: ignore first damage)
var _shadow_veil_spent: bool = false

## Set to true the moment victory/defeat is triggered — prevents re-entrant damage/scene calls
var _combat_ended: bool = false

## Pending spell cost penalty to apply to the enemy on their next turn (from Spell Taxer).
var _spell_tax_for_enemy_turn: int = 0

## Set to true by Null Seal trap to skip the enemy spell's effect resolution.
var _spell_cancelled: bool = false

## Void Imps summoned by Imp Overload that must die at end of the player's turn.
var _temp_imps: Array[MinionInstance] = []

## True once Imp Evolution has added a Senior Void Imp this turn; reset on turn start.
var _imp_evolution_used_this_turn: bool = false

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	trigger_manager = TriggerManager.new()
	_find_nodes()
	_connect_turn_manager()
	_connect_board_slots()
	_connect_combat_manager()
	_connect_ui()
	_update_environment_display()
	_update_trap_display()
	_update_enemy_trap_display()
	# If no run is active (e.g. launched directly for testing), start one now
	if not GameManager.run_active:
		GameManager.start_new_run()

	# HP resets to full at the start of every new combat
	player_hp = GameManager.player_hp_max
	if player_hp_label:
		player_hp_label.text = "HP: %d" % player_hp

	# Override enemy HP / name / fight number from current encounter
	if GameManager.current_enemy != null:
		enemy_hp = GameManager.current_enemy.hp
		enemy_hp_max = enemy_hp
		if enemy_hp_label:
			enemy_hp_label.text = "HP: %d" % enemy_hp
		if enemy_name_label:
			var prefix := "⚔ BOSS: " if GameManager.is_boss_fight() else ""
			enemy_name_label.text = prefix + GameManager.current_enemy.enemy_name
		if fight_label:
			fight_label.text = "Fight %d / %d" % [GameManager.run_node_index + 1, GameManager.TOTAL_FIGHTS]

	# Build the deck from GameManager and begin combat
	var deck_ids: Array[String] = GameManager.player_deck
	var deck: Array[CardData] = CardDatabase.get_cards(deck_ids)
	turn_manager.player_board = player_board
	turn_manager.enemy_board = enemy_board
	_setup_enemy_ai()
	turn_manager.start_combat(deck)
	_setup_hero_passives_panel()
	_setup_enemy_status_panel()
	_setup_large_preview()
	_setup_triggers()

func _find_nodes() -> void:
	turn_manager            = $TurnManager
	enemy_ai               = $EnemyAI
	essence_label          = $UI/EssenceLabel
	mana_label             = $UI/ManaLabel
	end_turn_essence_button = $UI/EndTurnPanel/EndTurnEssenceButton
	end_turn_mana_button   = $UI/EndTurnPanel/EndTurnManaButton
	player_hp_label        = $UI/PlayerHP
	enemy_hp_label    = $UI/EnemyHP
	enemy_name_label  = $UI/EnemyNameLabel if has_node("UI/EnemyNameLabel") else null
	fight_label       = $UI/FightLabel     if has_node("UI/FightLabel")     else null
	hand_display      = $UI/HandDisplay
	enemy_hero_button = $UI/EnemyHeroButton
	if has_node("UI/EnvironmentSlot"):
		environment_slot      = $UI/EnvironmentSlot
		environment_slot_name = $UI/EnvironmentSlot/SlotNameLabel if $UI/EnvironmentSlot.has_node("SlotNameLabel") else null
		environment_slot_desc = $UI/EnvironmentSlot/SlotDescLabel if $UI/EnvironmentSlot.has_node("SlotDescLabel") else null
	if has_node("UI/TrapSlotsRow"):
		var row := $UI/TrapSlotsRow
		for i in 3:
			var panel := row.get_child(i) as Panel
			trap_slot_panels.append(panel)
			trap_slot_labels.append(panel.get_child(0) as Label)
	if has_node("UI/EnemyTrapSlotsRow"):
		var row := $UI/EnemyTrapSlotsRow
		for i in 3:
			var panel := row.get_child(i) as Panel
			enemy_trap_slot_panels.append(panel)
			enemy_trap_slot_labels.append(panel.get_child(0) as Label)
	turn_label      = $UI/TurnLabel      if has_node("UI/TurnLabel")      else null
	deck_count_label = $UI/DeckSlot/DeckCountLabel if has_node("UI/DeckSlot/DeckCountLabel") else null
	if has_node("UI/HeroPowerPanel"):
		_hp_panel      = $UI/HeroPowerPanel
		_hp_desc_label = $UI/HeroPowerPanel/HPDescLabel if $UI/HeroPowerPanel.has_node("HPDescLabel") else null
		# Hide the old use-button and used-label nodes if they still exist in the scene
		if $UI/HeroPowerPanel.has_node("HPUseButton"):
			$UI/HeroPowerPanel.get_node("HPUseButton").visible = false
		if $UI/HeroPowerPanel.has_node("HPUsedLabel"):
			$UI/HeroPowerPanel.get_node("HPUsedLabel").visible = false
	game_over_panel   = $UI/GameOverPanel
	game_over_label   = $UI/GameOverPanel/GameOverLabel
	restart_button    = $UI/GameOverPanel/RestartButton
	_log_scroll     = $UI/CombatLogPanel/LogScroll           if has_node("UI/CombatLogPanel/LogScroll")                     else null
	_log_container  = $UI/CombatLogPanel/LogScroll/LogContainer if has_node("UI/CombatLogPanel/LogScroll/LogContainer") else null
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
	enemy_ai.minion_summoned.connect(_on_enemy_minion_summoned)
	enemy_ai.enemy_spell_cast.connect(_on_enemy_spell_cast)
	enemy_ai.enemy_about_to_attack.connect(_on_enemy_about_to_attack)
	enemy_ai.enemy_attacking_hero.connect(_on_enemy_attacking_hero)
	# Load the enemy's deck from the current encounter (falls back to EnemyAI.FALLBACK_DECK)
	var enemy_deck: Array[String] = []
	if GameManager.current_enemy != null:
		enemy_deck = GameManager.current_enemy.deck
	enemy_ai.setup_deck(enemy_deck)

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
		player_slots[i].mouse_entered.connect(_on_board_slot_hover_enter.bind(player_slots[i]))
		player_slots[i].mouse_exited.connect(_hide_large_preview)
	for i in enemy_slots.size():
		enemy_slots[i].slot_owner = "enemy"
		enemy_slots[i].index = i
		enemy_slots[i].slot_clicked_occupied.connect(_on_enemy_slot_clicked)
		enemy_slots[i].mouse_entered.connect(_on_board_slot_hover_enter.bind(enemy_slots[i]))
		enemy_slots[i].mouse_exited.connect(_hide_large_preview)

func _connect_combat_manager() -> void:
	combat_manager.attack_resolved.connect(_on_attack_resolved)
	combat_manager.minion_vanished.connect(_on_minion_vanished)
	combat_manager.hero_damaged.connect(_on_hero_damaged)
	combat_manager.hero_healed.connect(_on_hero_healed)

func _connect_ui() -> void:
	if end_turn_essence_button:
		end_turn_essence_button.pressed.connect(_on_end_turn_essence_pressed)
	if end_turn_mana_button:
		end_turn_mana_button.pressed.connect(_on_end_turn_mana_pressed)
	if hand_display:
		hand_display.card_selected.connect(_on_hand_card_selected)
		hand_display.card_hovered.connect(_show_large_preview)
		hand_display.card_unhovered.connect(_hide_large_preview)
		hand_display.card_deselected.connect(_on_hand_card_deselected)
	if enemy_hero_button:
		enemy_hero_button.pressed.connect(_on_enemy_hero_button_pressed)
	if _hp_panel:
		_hp_panel.mouse_entered.connect(_on_hero_passives_hover_enter)
		_hp_panel.mouse_exited.connect(_on_hero_passives_hover_exit)
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	_connect_trap_and_env_hover()

func _connect_trap_and_env_hover() -> void:
	for i in trap_slot_panels.size():
		trap_slot_panels[i].mouse_entered.connect(_on_trap_slot_hover.bind(i))
		trap_slot_panels[i].mouse_exited.connect(_hide_large_preview)
	if environment_slot:
		environment_slot.mouse_entered.connect(func() -> void:
			if active_environment:
				_show_large_preview(active_environment))
		environment_slot.mouse_exited.connect(_hide_large_preview)

func _on_trap_slot_hover(idx: int) -> void:
	if idx < active_traps.size():
		_show_large_preview(active_traps[idx])

# ---------------------------------------------------------------------------
# Turn events
# ---------------------------------------------------------------------------

func _on_turn_started(is_player_turn: bool) -> void:
	var who := "Player" if is_player_turn else "Enemy"
	_log("── Turn %d  %s ──" % [turn_manager.turn_number, who], _LogType.TURN)
	if end_turn_essence_button:
		end_turn_essence_button.disabled = not is_player_turn
	if end_turn_mana_button:
		end_turn_mana_button.disabled = not is_player_turn
	# Update turn counter and remaining deck count
	if turn_label:
		turn_label.text = "Turn %d  |  Deck: %d" % [turn_manager.turn_number, turn_manager.player_deck.size()]
	if deck_count_label:
		deck_count_label.text = "%d cards" % turn_manager.player_deck.size()
	_update_enemy_status_panel()
	# Refresh all player slot visuals so Exhausted badge clears at turn start
	for slot in player_slots:
		if not slot.is_empty():
			slot._refresh_visuals()
	# Fire turn-start events — all effects are handled by registered listeners in _setup_triggers().
	if is_player_turn:
		_imp_evolution_used_this_turn = false
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_PLAYER_TURN_START))
	else:
		enemy_ai.spell_cost_penalty = _spell_tax_for_enemy_turn
		_spell_tax_for_enemy_turn = 0
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_ENEMY_TURN_START))
		await get_tree().create_timer(0.4).timeout
		if not is_inside_tree():
			return
		enemy_ai.run_turn()

func _on_turn_ended(is_player_turn: bool) -> void:
	_clear_all_highlights()
	_show_hero_button(false)
	selected_attacker = null
	pending_play_card = null
	if is_player_turn:
		# Imp Overload: temp Void Imps summoned this turn expire now
		for imp in _temp_imps.duplicate():
			if imp in player_board:
				_log("  Imp Overload: temp Void Imp expires.", _LogType.DEATH)
				combat_manager.kill_minion(imp)
		_temp_imps.clear()
	else:
		# Clear enemy spell cost penalty after their turn ends
		enemy_ai.spell_cost_penalty = 0

func _on_resources_changed(essence: int, essence_max: int, mana: int, mana_max: int) -> void:
	if essence_label:
		essence_label.text = "Essence: %d / %d" % [essence, essence_max]
	if mana_label:
		mana_label.text = "Mana: %d / %d" % [mana, mana_max]
	if hand_display:
		hand_display.refresh_playability(essence, mana)
	var at_cap := (essence_max + mana_max) >= TurnManager.COMBINED_RESOURCE_CAP
	if end_turn_essence_button:
		end_turn_essence_button.disabled = at_cap
	if end_turn_mana_button:
		end_turn_mana_button.disabled = at_cap

func _on_card_drawn(card_data: CardData) -> void:
	if hand_display:
		hand_display.add_card(card_data)
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, "player")
	ctx.card = card_data
	trigger_manager.fire(ctx)

func _on_end_turn_essence_pressed() -> void:
	turn_manager.grow_essence_max()
	_do_end_turn()

func _on_end_turn_mana_pressed() -> void:
	turn_manager.grow_mana_max()
	_do_end_turn()

func _do_end_turn() -> void:
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
	var effective_cost := maxi(0, spell.cost - _spell_mana_discount())
	if not _pay_card_cost(0, effective_cost):
		if hand_display:
			hand_display.deselect_current()
		return
	_log("You cast: %s" % spell.card_name)
	_resolve_spell_effect(spell.effect_id, null)
	turn_manager.remove_from_hand(spell)
	if hand_display:
		hand_display.remove_card(spell)
		hand_display.deselect_current()
	pending_play_card = null
	var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
	spell_ctx.card = spell
	trigger_manager.fire(spell_ctx)

func _try_play_trap(trap: TrapCardData) -> void:
	if active_traps.size() >= trap_slot_panels.size():
		_log("Trap slots are full.", _LogType.PLAYER)
		if hand_display:
			hand_display.deselect_current()
		return
	if not _pay_card_cost(0, trap.cost):
		if hand_display:
			hand_display.deselect_current()
		return
	if trap.is_rune:
		_log("You place rune: %s" % trap.card_name)
	else:
		_log("You set trap: %s" % trap.card_name)
	active_traps.append(trap)
	_update_trap_display()
	turn_manager.remove_from_hand(trap)
	if hand_display:
		hand_display.remove_card(trap)
		hand_display.deselect_current()
	pending_play_card = null
	# Fire placement event
	var place_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_TRAP_PLACED, "player")
	place_ctx.card = trap
	trigger_manager.fire(place_ctx)
	# Runes: register persistent aura handlers, then fire ON_RUNE_PLACED for ritual checks
	if trap.is_rune:
		_apply_rune_aura(trap)
		var rune_ctx := EventContext.make(Enums.TriggerEvent.ON_RUNE_PLACED, "player")
		rune_ctx.card = trap
		trigger_manager.fire(rune_ctx)

func _try_play_environment(env: EnvironmentCardData) -> void:
	if not _pay_card_cost(0, env.cost):
		if hand_display:
			hand_display.deselect_current()
		return
	_log("You play environment: %s" % env.card_name)
	# Tear down previous environment's handlers and stat buffs before replacing
	if active_environment != null:
		_unregister_env_rituals()
		_unregister_env_aura(active_environment)
	active_environment = env
	_register_env_rituals(env)
	# If this environment defines rituals, fire the scan event so handlers can check
	# whether runes already on board satisfy a combination.
	if not env.rituals.is_empty():
		var env_ctx := EventContext.make(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, "player")
		env_ctx.card = env
		trigger_manager.fire(env_ctx)
	# Apply passive immediately on the turn it is played
	_apply_environment_passive(env.passive_effect_id)
	_update_environment_display()
	turn_manager.remove_from_hand(env)
	if hand_display:
		hand_display.remove_card(env)
		hand_display.deselect_current()
	pending_play_card = null

func _update_environment_display() -> void:
	if not environment_slot:
		return
	if active_environment:
		_apply_slot_style(environment_slot, Color(0.06, 0.14, 0.09, 1), Color(0.15, 0.75, 0.35, 1))
		if environment_slot_name:
			environment_slot_name.text = active_environment.card_name
		if environment_slot_desc:
			environment_slot_desc.text = active_environment.passive_description
		environment_slot.tooltip_text = _build_environment_tooltip(active_environment)
	else:
		_apply_slot_style(environment_slot, Color(0.08, 0.08, 0.14, 1), Color(0.22, 0.22, 0.38, 1))
		if environment_slot_name:
			environment_slot_name.text = "No Environment"
		if environment_slot_desc:
			environment_slot_desc.text = ""
		environment_slot.tooltip_text = ""

## Build the hover tooltip text for an active environment card.
## Includes cost, passive, and ritual combinations if any.
func _build_environment_tooltip(env: EnvironmentCardData) -> String:
	var lines: Array[String] = []
	lines.append(env.card_name)
	lines.append("Cost: %dM" % env.cost)
	lines.append("─")
	lines.append(env.passive_description if env.passive_description != "" else env.description)
	if not env.rituals.is_empty():
		lines.append("─")
		lines.append("Rituals:")
		for ritual in env.rituals:
			var r := ritual as RitualData
			var rune_names: Array[String] = []
			for rune_type in r.required_runes:
				rune_names.append(_rune_type_name(rune_type))
			lines.append("  %s → %s" % [" + ".join(rune_names), r.ritual_name])
			lines.append("  %s" % r.description)
	return "\n".join(lines)

## Return a human-readable name for a RuneType enum value.
func _rune_type_name(rune_type: int) -> String:
	match rune_type:
		Enums.RuneType.VOID_RUNE:     return "Void Rune"
		Enums.RuneType.BLOOD_RUNE:    return "Blood Rune"
		Enums.RuneType.DOMINION_RUNE: return "Dominion Rune"
		Enums.RuneType.SHADOW_RUNE:   return "Shadow Rune"
	return "Unknown Rune"

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
	if not turn_manager.is_player_turn:
		return
	# If a targeted spell that can hit enemy minions is pending, apply it here
	if pending_play_card is SpellCardData:
		var spell := pending_play_card as SpellCardData
		if spell.requires_target and _is_valid_spell_target(minion, spell.target_type):
			_apply_targeted_spell(spell, minion)
			return
	if selected_attacker == null:
		return
	# Talent: void_manifestation — Void Imps fire Void Bolt at enemy hero, ignoring Taunt
	if _minion_has_tag(selected_attacker, "void_imp") and _has_talent("void_manifestation"):
		_log("Your Void Imp fires a Void Bolt (ignores Taunt)!", _LogType.PLAYER)
		_deal_void_bolt_damage(selected_attacker.effective_atk())
		_apply_void_mark(1)
		selected_attacker.state = Enums.MinionState.EXHAUSTED
		_refresh_slot_for(selected_attacker)
		selected_attacker = null
		_clear_all_highlights()
		return
	# Enforce Guard — must attack a Guard minion if one exists
	if CombatManager.board_has_taunt(enemy_board) and not minion.has_guard():
		return  # Invalid target
	_log("Your %s attacks enemy %s" % [selected_attacker.card_data.card_name, minion.card_data.card_name])
	combat_manager.resolve_minion_attack(selected_attacker, minion)
	selected_attacker = null
	_clear_all_highlights()

# ---------------------------------------------------------------------------
# Minion play
# ---------------------------------------------------------------------------

func _try_play_minion(card: MinionCardData, slot: BoardSlot) -> void:
	if not slot.is_empty():
		return
	# Talent: piercing_void — Void Imps cost +1 Mana
	var extra_mana := 1 if (_card_has_tag(card, "void_imp") and _has_talent("piercing_void")) else 0
	if not _pay_card_cost(card.essence_cost, card.mana_cost + extra_mana):
		return
	_log("You play: %s" % card.card_name)
	var instance := MinionInstance.create(card, "player")
	player_board.append(instance)
	slot.place_minion(instance)
	# Fire ON_PLAYER_MINION_SUMMONED — handlers in _setup_triggers() apply all
	# hero passives, relics, talents, and board synergies in priority order.
	var play_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, "player")
	play_ctx.minion = instance
	play_ctx.card   = card
	trigger_manager.fire(play_ctx)
	var summon_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
	summon_ctx.minion = instance
	summon_ctx.card   = card
	trigger_manager.fire(summon_ctx)
	turn_manager.remove_from_hand(card)
	if hand_display:
		hand_display.remove_card(card)
		hand_display.deselect_current()

## owner is "player" (default) or "enemy" — all board/hero references are resolved relative to owner.
func _resolve_on_play_effect(effect_id: String, source: MinionInstance, owner: String = "player") -> void:
	match effect_id:
		"deal_1_enemy_hero":
			# piercing_void replaces the 100 direct damage with 200 Void Bolt (player-only talent)
			if owner == "player" and _has_talent("piercing_void"):
				pass  # handled in _try_play_minion for player; no-op here
			else:
				_on_hero_damaged(_opponent_of(owner), 100)
		"shadow_hound_atk_bonus":
			var bonus := 0
			for minion in _friendly_board(owner):
				if minion != source and minion.card_data.minion_type == Enums.MinionType.DEMON:
					bonus += 100
			if bonus > 0:
				BuffSystem.apply(source, Enums.BuffType.ATK_BONUS, bonus, "shadow_hound")
				_refresh_slot_for(source)
		"abyss_cultist_corrupt":
			var target := _find_random_minion(_opponent_board(owner))
			if target:
				_corrupt_minion(target)
		"void_netter_damage":
			var target := _find_random_minion(_opponent_board(owner))
			if target:
				combat_manager.apply_spell_damage(target, 200)
		"corruption_weaver_corrupt_all":
			for m in _opponent_board(owner).duplicate():
				_corrupt_minion(m)
		"soul_collector_execute":
			var target := _find_random_corrupted_minion(_opponent_board(owner))
			if target:
				_log("  Soul Collector devours Corrupted %s!" % target.card_data.card_name, _LogType.DEATH)
				combat_manager.kill_minion(target)
			else:
				_log("  Soul Collector: no Corrupted targets.", _LogType.PLAYER)
		"void_devourer_sacrifice":
			_resolve_void_devourer_sacrifice(source, owner)
		# --- Neutral Core Set ---
		"draw_1_card":
			if owner == "player":
				turn_manager.draw_card()
			else:
				enemy_ai._draw_cards(1)
		"destroy_random_enemy_trap":
			if owner == "player":
				# Enemy traps not yet implemented — no-op stub.
				_log("  Trapbreaker: no enemy traps to destroy.", _LogType.PLAYER)
		"spell_taxer_effect":
			if owner == "player":
				# Enemy's spells cost +1 extra essence on their next turn.
				_spell_tax_for_enemy_turn += 1
				_log("  Spell Taxer: enemy spells cost +1 next turn.", _LogType.PLAYER)
		"saboteur_adept_effect":
			if owner == "player":
				# Enemy traps not yet implemented — no-op stub.
				_log("  Saboteur Adept: enemy traps blocked this turn (not yet active).", _LogType.PLAYER)
		# --- Void Bolt Support Pool ---
		"abyssal_arcanist_effect":
			var bolt := CardDatabase.get_card("void_bolt")
			if bolt:
				if owner == "player":
					turn_manager.add_to_hand(bolt)
				else:
					enemy_ai.add_to_hand(bolt)
				_log("  Abyssal Arcanist: Void Bolt added to hand.", _LogType.PLAYER)
		# (lord_vael is now a hero, not a minion card — no on_play_effect needed)
		# --- Common Imp Support Pool ---
		"abyss_recruiter_effect":
			var imp_card := CardDatabase.get_card("void_imp")
			if imp_card:
				if owner == "player":
					turn_manager.add_to_hand(imp_card)
				else:
					enemy_ai.add_to_hand(imp_card)
				_log("  Abyss Recruiter: Void Imp added to hand.", _LogType.PLAYER)
		"grant_taunt_to_void_imps":
			for m in _friendly_board(owner):
				if _is_void_imp_type(m):
					BuffSystem.apply(m, Enums.BuffType.GRANT_GUARD, 1, "imp_overseer_aura")
					_refresh_slot_for(m)
			_log("  Imp Overseer: all Void Imps now have Guard.", _LogType.PLAYER)

## Fire the On Death effect of a minion that just died.
func _resolve_on_death_effect(minion: MinionInstance) -> void:
	match minion.card_data.on_death_effect:
		"remove_taunt_from_void_imps":
			# Only strip Guard if no other Imp Overseer remains on the same owner's board
			if not _has_imp_overseer_on_board(minion.owner):
				for m in _friendly_board(minion.owner):
					if _is_void_imp_type(m):
						BuffSystem.remove_source(m, "imp_overseer_aura")
						_refresh_slot_for(m)

## Apply the active environment's passive effect at the start of the player's turn.
func _apply_environment_passive(effect_id: String) -> void:
	match effect_id:
		"dark_covenant_passive":
			# ATK aura: Demons +100 ATK while any Human is on board.
			# Clear previous entries first to prevent stacking across turns.
			for m in player_board:
				BuffSystem.remove_source(m, "dark_covenant")
			var has_human := player_board.any(func(m: MinionInstance) -> bool: return m.card_data.minion_type == Enums.MinionType.HUMAN)
			var has_demon := player_board.any(func(m: MinionInstance) -> bool: return m.card_data.minion_type == Enums.MinionType.DEMON)
			if has_human:
				for m in player_board:
					if m.card_data.minion_type == Enums.MinionType.DEMON:
						BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "dark_covenant")
						_refresh_slot_for(m)
			# HP restore: Humans heal 100 HP per turn while any Demon is on board.
			if has_demon:
				for m in player_board:
					if m.card_data.minion_type == Enums.MinionType.HUMAN:
						m.current_health = mini(m.current_health + 100, m.card_data.health)
						_refresh_slot_for(m)
		"void_bolt_rain_passive":
			# Enemy hero: Void Bolt damage (scales with Void Marks). Player hero: flat 100 damage.
			_log("  Void Bolt Rain: enemy hero takes 100 Void Bolt damage, you take 100 damage.", _LogType.PLAYER)
			_deal_void_bolt_damage(100)
			_on_hero_damaged("player", 100)
		"imp_hatchery_passive":
			if _count_void_imps_on_board() < 2:
				_summon_void_imp()
				_log("  Imp Hatchery: fewer than 2 Void Imps — one summoned.", _LogType.PLAYER)
		"abyssal_summoning_circle_passive":
			# Passive fires on player minion death (event-driven), not turn start — handled separately.
			pass
		"abyss_ritual_circle_passive":
			# Deal 100 damage to a random minion (friendly or enemy) on the battlefield.
			var all_minions: Array[MinionInstance] = []
			all_minions.assign(player_board + enemy_board)
			if not all_minions.is_empty():
				var hit := all_minions[randi() % all_minions.size()]
				_log("  Abyss Ritual Circle: 100 damage to %s." % hit.card_data.card_name, _LogType.PLAYER)
				combat_manager.apply_spell_damage(hit, 100)

# ---------------------------------------------------------------------------
# Relic effects
# ---------------------------------------------------------------------------

## Stub kept for call-site compatibility — logic now lives in _handler_player_turn_relics.
func _apply_relic_turn_start() -> void:
	pass  # Handled by ON_PLAYER_TURN_START event handlers

## Stub kept for call-site compatibility — logic now lives in _handler_relic_on_summon.
func _apply_relic_on_player_summon(_instance: MinionInstance) -> void:
	pass  # Handled by ON_PLAYER_MINION_SUMMONED event handlers

# ---------------------------------------------------------------------------
# Abyss Order — Corruption helpers
# ---------------------------------------------------------------------------

## Apply one Corruption stack to a minion (each stack reduces ATK by 100).
func _corrupt_minion(minion: MinionInstance) -> void:
	var penalty := 100
	BuffSystem.apply(minion, Enums.BuffType.CORRUPTION, penalty, "corruption")
	_log("  %s is Corrupted! (−%d ATK)" % [minion.card_data.card_name, penalty], _LogType.ENEMY)
	_refresh_slot_for(minion)

## Return a random living enemy minion, or null if the board is empty.
func _find_random_enemy_minion() -> MinionInstance:
	return _find_random_minion(enemy_board)

## Return a random Corrupted enemy minion, or null if none exist.
func _find_random_corrupted_enemy() -> MinionInstance:
	return _find_random_corrupted_minion(enemy_board)

# ---------------------------------------------------------------------------
# Owner-aware board helpers
# ---------------------------------------------------------------------------

## Return the board belonging to the given owner ("player" or "enemy").
func _friendly_board(owner: String) -> Array[MinionInstance]:
	return player_board if owner == "player" else enemy_board

## Return the board belonging to the opponent of the given owner.
func _opponent_board(owner: String) -> Array[MinionInstance]:
	return enemy_board if owner == "player" else player_board

## Return the string identifier of the opponent ("player" → "enemy" and vice-versa).
func _opponent_of(owner: String) -> String:
	return "enemy" if owner == "player" else "player"

## Return a random minion from the given board array, or null if empty.
func _find_random_minion(board: Array[MinionInstance]) -> MinionInstance:
	if board.is_empty():
		return null
	return board[randi() % board.size()]

## Return a random Corrupted minion from the given board array, or null if none exist.
func _find_random_corrupted_minion(board: Array[MinionInstance]) -> MinionInstance:
	var corrupted: Array[MinionInstance] = []
	for m in board:
		if BuffSystem.has_type(m, Enums.BuffType.CORRUPTION):
			corrupted.append(m)
	if corrupted.is_empty():
		return null
	return corrupted[randi() % corrupted.size()]

# ---------------------------------------------------------------------------
# Abyss Order — Sacrifice helpers
# ---------------------------------------------------------------------------

## Void Devourer on-play: sacrifice adjacent friendly minions, grow per kill.
func _resolve_void_devourer_sacrifice(devourer: MinionInstance, owner: String = "player") -> void:
	var idx := devourer.slot_index
	var to_sacrifice: Array[MinionInstance] = []
	for m in _friendly_board(owner):
		if m != devourer and (m.slot_index == idx - 1 or m.slot_index == idx + 1):
			to_sacrifice.append(m)
	var count := to_sacrifice.size()
	for m in to_sacrifice:
		_log("  Void Devourer sacrifices %s!" % m.card_data.card_name, _LogType.PLAYER)
		combat_manager.kill_minion(m)
	if count > 0:
		BuffSystem.apply(devourer, Enums.BuffType.ATK_BONUS, count * 300, "void_devourer")
		devourer.current_health += count * 300
		_log("  Void Devourer grows to %d/%d!" % [devourer.effective_atk(), devourer.current_health], _LogType.PLAYER)
		_refresh_slot_for(devourer)

# ---------------------------------------------------------------------------
# Abyss Order — Board-wide passive triggers (fire on friendly death)
# ---------------------------------------------------------------------------

## Kept as a thin stub — logic lives in _handler_board_passives_on_player_death (registered via TriggerManager).
func _on_friendly_minion_died(_dead_minion: MinionInstance) -> void:
	pass  # Handled by ON_PLAYER_MINION_DIED event handlers

## Summon a 100/100 Void Spark into the first empty player slot.
func _summon_void_spark() -> void:
	for slot in player_slots:
		if slot.is_empty():
			var spark_data := CardDatabase.get_card("void_spark") as MinionCardData
			if spark_data == null:
				return
			var instance := MinionInstance.create(spark_data, "player")
			player_board.append(instance)
			slot.place_minion(instance)
			_log("  Void Spark summoned (100/100)!", _LogType.PLAYER)
			var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
			ctx.minion = instance
			ctx.card   = spark_data
			trigger_manager.fire(ctx)
			return

## Summon a 100/200 Wandering Spirit token into the first empty player slot.
func _summon_wandering_spirit() -> void:
	for slot in player_slots:
		if slot.is_empty():
			var data := CardDatabase.get_card("wandering_spirit") as MinionCardData
			if data == null:
				return
			var instance := MinionInstance.create(data, "player")
			player_board.append(instance)
			slot.place_minion(instance)
			_log("  Wandering Spirit (100/200) summoned!", _LogType.PLAYER)
			var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
			ctx.minion = instance
			ctx.card   = data
			trigger_manager.fire(ctx)
			return

## Summon a 100/100 Soldier token into the first empty player slot.
func _summon_soldier() -> void:
	for slot in player_slots:
		if slot.is_empty():
			var data := CardDatabase.get_card("soldier") as MinionCardData
			if data == null:
				return
			var instance := MinionInstance.create(data, "player")
			player_board.append(instance)
			slot.place_minion(instance)
			_log("  Soldier (100/100) summoned!", _LogType.PLAYER)
			var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
			ctx.minion = instance
			ctx.card   = data
			trigger_manager.fire(ctx)
			return

## Summon a Void Imp into the first empty player slot.
## Fires ON_PLAYER_MINION_SUMMONED so all registered handlers (passives, talents, relics) apply.
## Returns the instance, or null if no free slot.
func _summon_void_imp() -> MinionInstance:
	for slot in player_slots:
		if slot.is_empty():
			var imp_data := CardDatabase.get_card("void_imp") as MinionCardData
			if imp_data == null:
				return null
			var instance := MinionInstance.create(imp_data, "player")
			player_board.append(instance)
			slot.place_minion(instance)
			_log("  Void Imp summoned!", _LogType.PLAYER)
			var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
			ctx.minion = instance
			ctx.card   = imp_data
			trigger_manager.fire(ctx)
			return instance
	return null

## True if at least one Imp Overseer is currently on the given owner's board.
func _has_imp_overseer_on_board(owner: String = "player") -> bool:
	for m in _friendly_board(owner):
		if _minion_has_tag(m, "imp_overseer"):
			return true
	return false

# ---------------------------------------------------------------------------
# Tag query helpers — data-driven alternative to card ID checks
# ---------------------------------------------------------------------------

## True if the MinionInstance has the given tag in its card_data.minion_tags.
func _minion_has_tag(m: MinionInstance, tag: String) -> bool:
	return tag in m.card_data.minion_tags

## True if the CardData (from hand/deck/ctx.card) has the given tag.
## Returns false for non-minion cards.
func _card_has_tag(card: CardData, tag: String) -> bool:
	if card is MinionCardData:
		return tag in (card as MinionCardData).minion_tags
	return false

## Count minions on the player board that have the given tag.
func _count_with_tag(tag: String) -> int:
	var count := 0
	for m in player_board:
		if _minion_has_tag(m, tag):
			count += 1
	return count

# ---------------------------------------------------------------------------
# Abyss Order — Void Imp helpers
# ---------------------------------------------------------------------------

## True if a MinionInstance belongs to the Void Imp family (has "void_imp" tag).
func _is_void_imp_type(m: MinionInstance) -> bool:
	return _minion_has_tag(m, "void_imp")

## Count all Void Imp-type minions currently on the player board.
func _count_void_imps_on_board() -> int:
	return _count_with_tag("void_imp")

## Check all champion cards in hand/deck and auto-summon any whose condition is met.
## Called whenever the board changes in a way that could trigger a champion (e.g. minion summon).
func _check_champion_triggers() -> void:
	var all_cards: Array = turn_manager.player_hand + turn_manager.player_deck
	for card in all_cards:
		if not (card is MinionCardData):
			continue
		var champion := card as MinionCardData
		if not champion.is_champion:
			continue
		# Skip if this champion is already on the board
		var already_on_board := false
		for m in player_board:
			if m.card_data.id == champion.id:
				already_on_board = true
				break
		if already_on_board:
			continue
		if _check_champion_condition(champion):
			_summon_champion_card(champion, card in turn_manager.player_hand)
			return  # One champion summon per trigger check

## Evaluate whether a champion's auto-summon condition is currently met.
func _check_champion_condition(champion: MinionCardData) -> bool:
	match champion.auto_summon_condition:
		"board_tag_count":
			return _count_with_tag(champion.auto_summon_tag) >= champion.auto_summon_threshold
	return false

## Place the champion card on the first empty player slot (free of cost).
func _summon_champion_card(card: MinionCardData, from_hand: bool) -> void:
	for slot in player_slots:
		if slot.is_empty():
			var instance := MinionInstance.create(card, "player")
			player_board.append(instance)
			slot.place_minion(instance)
			if from_hand:
				turn_manager.remove_from_hand(card)
				if hand_display:
					hand_display.remove_card(card)
			else:
				turn_manager.player_deck.erase(card)
			_log("⚡ 3 Void Imps on board — %s emerges!" % card.card_name, _LogType.PLAYER)
			var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
			ctx.minion = instance
			ctx.card   = card
			trigger_manager.fire(ctx)
			return

# ---------------------------------------------------------------------------
# Talent helpers
# ---------------------------------------------------------------------------

func _has_talent(id: String) -> bool:
	return GameManager.has_talent(id)

## Mana discount applied to all player spells — summed from all minions on board.
## Data-driven via MinionCardData.mana_cost_discount.
func _spell_mana_discount() -> int:
	var discount := 0
	for m in player_board:
		discount += m.card_data.mana_cost_discount
	return discount

## Void Bolt damage per Void Mark stack (25 base; 50 with deepened_curse).
func _void_mark_damage_per_stack() -> int:
	return 50 if _has_talent("deepened_curse") else 25

## Add Void Mark stacks to the enemy hero.
func _apply_void_mark(stacks: int = 1) -> void:
	enemy_void_marks += stacks
	_log("  Void Mark x%d applied! (total: %d)" % [stacks, enemy_void_marks], _LogType.PLAYER)
	_update_enemy_status_panel()

## Deal Void Bolt damage to the enemy hero, scaled by current Void Marks.
## CONVENTION: ALL "Void Bolt damage" in the game must go through this function
## so that talents like deepened_curse and future modifiers apply automatically.
## Never call _on_hero_damaged("enemy", x) directly for Void Bolt-typed damage.
func _deal_void_bolt_damage(base_damage: int) -> void:
	var bonus := enemy_void_marks * _void_mark_damage_per_stack()
	var total := base_damage + bonus
	if bonus > 0:
		_log("  Void Bolt: %d dmg (base %d + %d from %d marks)" % [total, base_damage, bonus, enemy_void_marks], _LogType.PLAYER)
	else:
		_log("  Void Bolt: %d damage." % total, _LogType.PLAYER)
	_on_hero_damaged("enemy", total)
	# Board passives that react to Void Bolt hits (e.g. Void Channeler)
	_apply_void_bolt_passives()

## Tries to spend a card's costs, respecting the Void Crystal relic.
## Returns true if the card can be played (and costs are deducted).
func _pay_card_cost(essence_cost: int, mana_cost: int) -> bool:
	if _relic_first_card_free and "void_crystal" in GameManager.player_relics:
		_relic_first_card_free = false
		_log("  Void Crystal: first card is free!", _LogType.PLAYER)
		return true
	if not turn_manager.can_afford(essence_cost, mana_cost):
		return false
	turn_manager.spend_essence(essence_cost)
	if mana_cost > 0:
		turn_manager.spend_mana(mana_cost)
	return true

# ---------------------------------------------------------------------------
# Combat manager events
# ---------------------------------------------------------------------------

func _on_attack_resolved(attacker: MinionInstance, defender: MinionInstance) -> void:
	_refresh_slot_for(attacker)
	_refresh_slot_for(defender)
	# ON_ENEMY_ATTACK traps fire BEFORE the attack (in _on_enemy_about_to_attack /
	# _on_enemy_attacking_hero) so they can cancel it via Smoke Veil, deal damage
	# first via Hidden Ambush, etc.

func _on_minion_vanished(minion: MinionInstance) -> void:
	# Remove from the appropriate board array and clear its slot
	if minion.owner == "player":
		player_board.erase(minion)
		_clear_slot_for(minion, player_slots)
	else:
		enemy_board.erase(minion)
		_clear_slot_for(minion, enemy_slots)
	_log("  %s died" % minion.card_data.card_name, _LogType.DEATH)
	# Fire death events — handlers in _setup_triggers() apply all passive/talent/deathrattle effects
	var ctx := EventContext.make(
		Enums.TriggerEvent.ON_PLAYER_MINION_DIED if minion.owner == "player"
		else Enums.TriggerEvent.ON_ENEMY_MINION_DIED,
		minion.owner)
	ctx.minion = minion
	trigger_manager.fire(ctx)

func _on_hero_damaged(target: String, amount: int) -> void:
	if _combat_ended:
		return
	if target == "player":
		# Shadow Veil — absorb the first hit of the combat
		if not _shadow_veil_spent and "shadow_veil" in GameManager.player_relics:
			_shadow_veil_spent = true
			_log("  Shadow Veil absorbs %d damage!" % amount, _LogType.PLAYER)
			return
		player_hp -= amount
		if player_hp_label:
			player_hp_label.text = "HP: %d" % player_hp
		_log("  You take %d damage  (HP: %d)" % [amount, player_hp], _LogType.DAMAGE)
		if player_hp <= 0:
			_on_defeat()
		else:
			var _ctx := EventContext.make(Enums.TriggerEvent.ON_HERO_DAMAGED, "player")
			_ctx.damage = amount
			trigger_manager.fire(_ctx)
	else:
		enemy_hp -= amount
		if enemy_hp_label:
			enemy_hp_label.text = "HP: %d" % enemy_hp
		_log("  Enemy takes %d damage  (HP: %d)" % [amount, enemy_hp], _LogType.DAMAGE)
		_update_enemy_status_panel()
		if enemy_hp <= 0:
			_on_victory()

func _on_hero_healed(target: String, amount: int) -> void:
	if target == "player":
		player_hp = mini(player_hp + amount, GameManager.player_hp_max)
		if player_hp_label:
			player_hp_label.text = "HP: %d" % player_hp
		_log("  You heal %d HP  (HP: %d)" % [amount, player_hp], _LogType.HEAL)
		# Eternal Hunger — deal the healed amount to the enemy hero too
		if "eternal_hunger" in GameManager.player_relics:
			_log("  Eternal Hunger: deal %d damage to enemy hero." % amount, _LogType.PLAYER)
			_on_hero_damaged("enemy", amount)

# ---------------------------------------------------------------------------
# Targeted spell helpers
# ---------------------------------------------------------------------------

## Highlight player slots that have a minion matching the spell's target_type
func _highlight_spell_targets(spell: SpellCardData) -> void:
	_clear_all_highlights()
	var hits_friendly := spell.target_type in ["friendly_minion", "friendly_demon", "friendly_void_imp", "any_minion"]
	var hits_enemy    := spell.target_type in ["enemy_minion", "any_minion"]
	if hits_friendly:
		for slot in player_slots:
			if not slot.is_empty() and _is_valid_spell_target(slot.minion, spell.target_type):
				slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET)
	if hits_enemy:
		for slot in enemy_slots:
			if not slot.is_empty():
				slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET)

func _is_valid_spell_target(minion: MinionInstance, target_type: String) -> bool:
	match target_type:
		"friendly_demon":    return minion.card_data.minion_type == Enums.MinionType.DEMON
		"friendly_minion":   return true
		"friendly_void_imp": return _minion_has_tag(minion, "void_imp")
		"enemy_minion":      return true
		"any_minion":        return true
	return false

## Spend mana, resolve the effect on the target, then remove the card
func _apply_targeted_spell(spell: SpellCardData, target: MinionInstance) -> void:
	var effective_cost := maxi(0, spell.cost - _spell_mana_discount())
	if not _pay_card_cost(0, effective_cost):
		if hand_display:
			hand_display.deselect_current()
		return
	_log("You cast: %s → %s" % [spell.card_name, target.card_data.card_name])
	_resolve_spell_effect(spell.effect_id, target)
	turn_manager.remove_from_hand(spell)
	if hand_display:
		hand_display.remove_card(spell)
		hand_display.deselect_current()
	pending_play_card = null
	_clear_all_highlights()
	var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
	spell_ctx.card = spell
	trigger_manager.fire(spell_ctx)

## Apply a spell's effect. target is null for untargeted spells.
## owner is "player" (default) or "enemy" — board/hero references are resolved relative to owner.
func _resolve_spell_effect(effect_id: String, target: MinionInstance, owner: String = "player") -> void:
	match effect_id:
		# --- Enemy-pool spells (work correctly via owner-aware helpers) ---
		"shadow_bolt_effect":
			_on_hero_damaged(_opponent_of(owner), 300)
		"void_barrage_effect":
			for m in _opponent_board(owner).duplicate():
				combat_manager.apply_spell_damage(m, 100)
		"soul_leech_effect":
			if target:
				BuffSystem.apply(target, Enums.BuffType.ATK_BONUS, 100, "soul_leech")
				target.current_health += 100
				_refresh_slot_for(target)
				_on_hero_healed(owner, 100)
		"dark_surge_effect":
			for minion in _friendly_board(owner):
				if minion.card_data.minion_type == Enums.MinionType.DEMON:
					BuffSystem.apply(minion, Enums.BuffType.TEMP_ATK, 100, "dark_surge", true)
					_refresh_slot_for(minion)
		"flux_siphon_effect":
			if owner == "player":
				turn_manager.convert_mana_to_essence()
		# Void Bolt card ecosystem (player-only — void marks track enemy hero)
		"void_bolt_effect":
			if owner == "player":
				_deal_void_bolt_damage(300)
				if _has_talent("piercing_void"):
					_apply_void_mark(1)
		# --- Core Spells (Abyss Order) ---
		"abyssal_sacrifice_effect":
			# Destroy a friendly minion. Draw 2 cards (player only).
			if target:
				_log("  Abyssal Sacrifice: %s destroyed." % target.card_data.card_name, _LogType.PLAYER)
				combat_manager.kill_minion(target)
				if owner == "player":
					turn_manager.draw_card()
					turn_manager.draw_card()
		"corrupting_mist_effect":
			# Apply 1 Corruption to all opponent minions.
			for m in _opponent_board(owner).duplicate():
				_corrupt_minion(m)
		"abyssal_fury_effect":
			# Give a friendly Demon +200 ATK permanently and grant it Lifedrain.
			if target:
				BuffSystem.apply(target, Enums.BuffType.ATK_BONUS,      200, "abyssal_fury")
				BuffSystem.apply(target, Enums.BuffType.GRANT_LIFEDRAIN, 1,   "abyssal_fury")
				_refresh_slot_for(target)
				_log("  Abyssal Fury: %s gains +200 ATK and Lifedrain." % target.card_data.card_name, _LogType.PLAYER)
		"abyssal_reinforcement_effect":
			# Summon two 100/100 Void Sparks. Draw 1 card (player only).
			if owner == "player":
				_summon_void_spark()
				_summon_void_spark()
				turn_manager.draw_card()
		"corruption_collapse_effect":
			# Destroy all Corrupted opponent minions.
			for m in _opponent_board(owner).duplicate():
				if BuffSystem.has_type(m, Enums.BuffType.CORRUPTION):
					_log("  Corruption Collapse: %s destroyed." % m.card_data.card_name, _LogType.DEATH)
					combat_manager.kill_minion(m)
		"abyssal_purge_effect":
			# Deal 200 damage to all opponent minions.
			for m in _opponent_board(owner).duplicate():
				combat_manager.apply_spell_damage(m, 200)
		# --- Neutral Spells (player-only — traps/environment not yet for enemy) ---
		"cyclone_effect":
			if owner == "player":
				if not active_traps.is_empty():
					var removed := active_traps[randi() % active_traps.size()]
					active_traps.erase(removed)
					if removed.is_rune:
						_remove_rune_aura(removed)
					_update_trap_display()
					_log("  Cyclone: %s trap removed." % removed.card_name, _LogType.PLAYER)
				elif active_environment:
					_log("  Cyclone: %s dispelled." % active_environment.card_name, _LogType.PLAYER)
					_unregister_env_rituals()
					active_environment = null
					_update_environment_display()
				else:
					_log("  Cyclone: nothing to destroy.", _LogType.PLAYER)
		"hurricane_effect":
			if owner == "player":
				if not active_traps.is_empty():
					_log("  Hurricane: all traps swept away.", _LogType.PLAYER)
					for t in active_traps:
						if t.is_rune:
							_remove_rune_aura(t)
					active_traps.clear()
					_update_trap_display()
				if active_environment:
					_log("  Hurricane: %s dispelled." % active_environment.card_name, _LogType.PLAYER)
					_unregister_env_rituals()
					active_environment = null
					_update_environment_display()
		"arcane_strike_effect":
			if target:
				_log("  Arcane Strike: %s takes 200 damage." % target.card_data.card_name, _LogType.PLAYER)
				combat_manager.apply_spell_damage(target, 200)
		"precision_strike_effect":
			if target:
				_log("  Precision Strike: %s takes 400 damage." % target.card_data.card_name, _LogType.PLAYER)
				combat_manager.apply_spell_damage(target, 400)
		"tactical_planning_effect":
			if owner == "player":
				turn_manager.draw_card()
		"emergency_reinforcements_effect":
			if owner == "player":
				_summon_soldier()
				_summon_soldier()
		"energy_conversion_effect":
			if owner == "player":
				var converted := turn_manager.essence
				turn_manager.convert_essence_to_mana()
				_log("  Energy Conversion: %d Essence → Mana." % converted, _LogType.PLAYER)
		"essence_surge_effect":
			if owner == "player":
				turn_manager.gain_essence(3)
				_log("  Essence Surge: +3 Essence this turn.", _LogType.PLAYER)
		"battlefield_tactics_effect":
			if target:
				BuffSystem.apply(target, Enums.BuffType.TEMP_ATK, 200, "battlefield_tactics", true)
				_refresh_slot_for(target)
				_log("  Battlefield Tactics: %s gains +200 ATK this turn." % target.card_data.card_name, _LogType.PLAYER)
		"reinforced_armor_effect":
			if target:
				BuffSystem.apply(target, Enums.BuffType.SHIELD_BONUS, 300, "reinforced_armor")
				target.current_shield += 300
				_refresh_slot_for(target)
				_log("  Reinforced Armor: %s gains +300 Shield." % target.card_data.card_name, _LogType.PLAYER)
		"shield_break_effect":
			if target:
				_log("  Shield Break: %s shield removed." % target.card_data.card_name, _LogType.PLAYER)
				target.current_shield = 0
				_refresh_slot_for(target)
		"purge_effect":
			if target:
				if target.owner == _opponent_of(owner):
					# Dispel: remove all buffs from an opponent minion
					BuffSystem.dispel(target)
					_log("  Purge: buffs removed from %s." % target.card_data.card_name, _LogType.PLAYER)
				else:
					# Cleanse: remove all debuffs from a friendly minion
					BuffSystem.cleanse(target)
					_log("  Purge: debuffs cleansed from %s." % target.card_data.card_name, _LogType.PLAYER)
				_refresh_slot_for(target)
		"battlefield_salvage_effect":
			if target:
				_log("  Battlefield Salvage: %s sacrificed — draw 2 cards." % target.card_data.card_name, _LogType.PLAYER)
				combat_manager.kill_minion(target)
				if owner == "player":
					turn_manager.draw_card()
					turn_manager.draw_card()
		"shockwave_effect":
			_log("  Shockwave: all minions take 200 damage.", _LogType.PLAYER)
			for m in player_board.duplicate():
				combat_manager.apply_spell_damage(m, 200)
			for m in enemy_board.duplicate():
				combat_manager.apply_spell_damage(m, 200)
		# --- Void Bolt Support Pool spells (player-only — void mark system) ---
		"mark_the_target_effect":
			if owner == "player":
				_apply_void_mark(2)
				turn_manager.draw_card()
		"imp_combustion_effect":
			if owner == "player":
				if target and _minion_has_tag(target, "void_imp"):
					combat_manager.kill_minion(target)
					_deal_void_bolt_damage(200)
		"dark_ritual_effect":
			if owner == "player":
				if target and _minion_has_tag(target, "void_imp"):
					combat_manager.kill_minion(target)
					turn_manager.draw_card()
					turn_manager.draw_card()
		"imp_overload_effect":
			if owner == "player":
				for _i in 2:
					for slot in player_slots:
						if slot.is_empty():
							var imp_data := CardDatabase.get_card("void_imp") as MinionCardData
							if imp_data == null:
								break
							var instance := MinionInstance.create(imp_data, "player")
							player_board.append(instance)
							slot.place_minion(instance)
							_temp_imps.append(instance)
							_log("  Imp Overload: temp Void Imp summoned (dies end of turn).", _LogType.PLAYER)
							break
		"void_detonation_effect":
			if owner == "player":
				var bonus_per_mark := 50
				var total_base := 150 + enemy_void_marks * bonus_per_mark
				_log("  Void Detonation: %d Void Bolt dmg (150 + %d×%d marks)." % [total_base, bonus_per_mark, enemy_void_marks], _LogType.PLAYER)
				_deal_void_bolt_damage(total_base)
		"mark_convergence_effect":
			if owner == "player":
				if enemy_void_marks > 0:
					_apply_void_mark(enemy_void_marks)
					_log("  Mark Convergence: Void Marks doubled to ×%d." % enemy_void_marks, _LogType.PLAYER)
				else:
					_log("  Mark Convergence: no Void Marks to double.", _LogType.PLAYER)
		# --- Common Imp Support Pool spells (player-only — summon tokens into player board) ---
		"abyssal_conjuring_effect":
			if owner == "player":
				if player_board.is_empty():
					_summon_void_imp()
					_log("  Abyssal Conjuring: board empty — Void Imp summoned.", _LogType.PLAYER)
				else:
					_summon_void_spark()
					_log("  Abyssal Conjuring: board occupied — Void Spark summoned.", _LogType.PLAYER)
		"call_the_swarm_effect":
			if owner == "player":
				_summon_void_imp()
				_summon_void_imp()
				_log("  Call the Swarm: 2 Void Imps summoned.", _LogType.PLAYER)
		"void_breach_effect":
			if owner == "player":
				var breach_imp := CardDatabase.get_card("void_imp")
				if breach_imp:
					turn_manager.add_to_hand(breach_imp)
					_log("  Void Breach: Void Imp added to hand.", _LogType.PLAYER)

# ---------------------------------------------------------------------------
# Trap helpers
# ---------------------------------------------------------------------------

## Check all active traps whose trigger matches the given TriggerEvent and fire them.
## triggering_minion is the relevant minion (attacker, summoned minion, dead minion, etc.).
func _check_and_fire_traps(trigger: int, triggering_minion: MinionInstance = null) -> void:
	for trap in active_traps.duplicate():
		if trap.is_rune:
			continue  # Runes are persistent — never triggered by enemy events; handled by ritual system
		if trap.trigger != trigger:
			continue
		var slot_idx := active_traps.find(trap)
		_show_trap_triggered_vfx(trap, slot_idx)
		_resolve_trap_effect(trap.effect_id, triggering_minion)
		if not trap.reusable:
			active_traps.erase(trap)
			_update_trap_display()

## Resolve the effect of a triggered trap.
## triggering_minion is populated for ON_ENEMY_SUMMON traps (the newly summoned minion).
func _resolve_trap_effect(effect_id: String, triggering_minion: MinionInstance = null) -> void:
	match effect_id:
		"void_snare_effect":
			_on_hero_damaged("enemy", 300)
		"soul_cage_effect":
			_on_hero_damaged("enemy", 200)
		"phantom_recoil_effect":
			_on_hero_healed("player", 400)
		"abyss_retaliation_effect":
			_on_hero_damaged("enemy", 400)
		"death_bolt_trap_effect":
			_deal_void_bolt_damage(200)
		"corruption_surge_effect":
			# Corrupt the summoned minion and deal 300 damage to it.
			if triggering_minion and triggering_minion in enemy_board:
				_corrupt_minion(triggering_minion)
				combat_manager.apply_spell_damage(triggering_minion, 300)
		"abyssal_claim_effect":
			# Summon a Void Spark and deal 200 damage to the enemy hero.
			_summon_void_spark()
			_on_hero_damaged("enemy", 200)
		"void_collapse_effect":
			# Deal 200 damage to all enemy minions.
			for m in enemy_board.duplicate():
				combat_manager.apply_spell_damage(m, 200)
		# --- Neutral Traps ---
		"hidden_ambush_effect":
			# Deal 200 damage to the attacking minion (triggering_minion).
			if triggering_minion and triggering_minion in enemy_board:
				combat_manager.apply_spell_damage(triggering_minion, 200)
		"arcane_rebound_effect":
			_on_hero_damaged("enemy", 300)
		"null_seal_effect":
			# Cancel the enemy spell — flag checked in _on_enemy_spell_cast.
			_spell_cancelled = true
			_log("  Null Seal: enemy spell cancelled!", _LogType.TRAP)
		"gate_collapse_effect":
			# Destroy the summoned minion (triggering_minion).
			if triggering_minion and triggering_minion in enemy_board:
				_log("  Gate Collapse: %s destroyed!" % triggering_minion.card_data.card_name, _LogType.TRAP)
				combat_manager.kill_minion(triggering_minion)
		"trap_disruption_effect":
			# Enemy traps not implemented — no-op stub.
			_log("  Trap Disruption: no enemy trap to disrupt.", _LogType.TRAP)
		"smoke_veil_effect":
			# Cancel the current attack and exhaust ALL enemy minions.
			enemy_ai.attack_cancelled = true
			for m in enemy_board:
				m.state = Enums.MinionState.EXHAUSTED
				_refresh_slot_for(m)
			_log("  Smoke Veil: attack cancelled! All enemies exhausted.", _LogType.TRAP)
		"hidden_cache_effect":
			# Draw 2 cards when enemy summons a minion.
			turn_manager.draw_card()
			turn_manager.draw_card()
		"trap_emergency_reinforcements_effect":
			# Summon two 100/200 Wandering Spirits when hero takes damage.
			_summon_wandering_spirit()
			_summon_wandering_spirit()
		"shock_mine_effect":
			# Deal 200 damage to all enemy minions.
			for m in enemy_board.duplicate():
				combat_manager.apply_spell_damage(m, 200)
		# --- Common Imp Support Pool traps ---
		"dark_nursery_effect":
			# Summon a Void Imp when a friendly minion dies on the enemy's turn.
			# The trap already only fires when is_player_turn == false (in _on_minion_vanished).
			_summon_void_imp()
			_log("  Dark Nursery: friendly death → Void Imp summoned.", _LogType.TRAP)
		"imp_barricade_effect":
			# Summon a Void Imp and redirect the attacking enemy minion to it.
			var barricade_imp := _summon_void_imp()
			if barricade_imp != null:
				enemy_ai.redirect_attack_target = barricade_imp
				_log("  Imp Barricade: Void Imp summoned — attack redirected!", _LogType.TRAP)
			else:
				_log("  Imp Barricade: no free slot for Void Imp.", _LogType.TRAP)
		# --- Void Bolt Support Pool traps ---
		"soul_rupture_effect":
			# Only fires if the minion that died was a Void Imp.
			if triggering_minion and _minion_has_tag(triggering_minion, "void_imp"):
				_log("  Soul Rupture: Void Imp died → 250 Void Bolt damage!", _LogType.TRAP)
				_deal_void_bolt_damage(250)
		"mark_collapse_effect":
			# Fires at start of enemy turn if ≥5 Void Marks. Consume all marks; 150 Void Bolt per mark.
			if enemy_void_marks >= 5:
				var marks := enemy_void_marks
				var total_base := marks * 150
				_log("  Mark Collapse: %d marks consumed → %d Void Bolt damage!" % [marks, total_base], _LogType.TRAP)
				enemy_void_marks = 0
				_update_enemy_status_panel()
				_deal_void_bolt_damage(total_base)

## Flash the trap slot and show a floating triggered label.
func _show_trap_triggered_vfx(trap: TrapCardData, slot_idx: int) -> void:
	_log("⚡ %s triggered!" % trap.card_name, _LogType.TRAP)
	# Flash the slot panel gold then restore
	if slot_idx >= 0 and slot_idx < trap_slot_panels.size():
		var panel := trap_slot_panels[slot_idx]
		_apply_slot_style(panel, Color(0.35, 0.28, 0.0, 1), Color(1.0, 0.85, 0.1, 1))
		var restore_tween := create_tween()
		restore_tween.tween_interval(0.5)
		restore_tween.tween_callback(_update_trap_display)

	# Floating "TRAP!" label that rises and fades
	var lbl := Label.new()
	lbl.text = "⚡ %s!" % trap.card_name
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.15, 1))
	lbl.z_index = 20
	$UI.add_child(lbl)
	# Position above the trap slot, or centre-screen as fallback
	var start_pos: Vector2
	if slot_idx >= 0 and slot_idx < trap_slot_panels.size():
		start_pos = trap_slot_panels[slot_idx].global_position + Vector2(20, -30)
	else:
		start_pos = get_viewport().get_visible_rect().size / 2
	lbl.position = start_pos
	var tween := create_tween()
	tween.tween_property(lbl, "position", start_pos + Vector2(0, -70), 0.9)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9)
	tween.tween_callback(lbl.queue_free)

## Called by EnemyAI's minion_summoned signal.
func _on_enemy_minion_summoned(minion: MinionInstance) -> void:
	_log("Enemy summons: %s" % minion.card_data.card_name, _LogType.ENEMY)
	# ON_PLAY and ON_SUMMON effects are resolved by _handler_enemy_minion_on_play /
	# _handler_enemy_minion_on_summon_effect registered in _setup_triggers() — do NOT
	# call _resolve_on_play_effect here or effects would fire twice.
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "enemy")
	ctx.minion = minion
	trigger_manager.fire(ctx)

## Called by EnemyAI's enemy_spell_cast signal.
func _on_enemy_spell_cast(spell: SpellCardData) -> void:
	_log("Enemy casts: %s" % spell.card_name, _LogType.ENEMY)
	# Fire ON_ENEMY_SPELL_CAST BEFORE resolving the spell so Null Seal can set _spell_cancelled.
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "enemy")
	ctx.card = spell
	trigger_manager.fire(ctx)
	if not _spell_cancelled:
		_resolve_spell_effect(spell.effect_id, null, "enemy")
	_spell_cancelled = false

func _update_trap_display() -> void:
	for i in trap_slot_panels.size():
		var panel := trap_slot_panels[i]
		var lbl   := trap_slot_labels[i]
		if i < active_traps.size():
			var trap := active_traps[i]
			if trap.is_rune:
				# Rune: face-up, persistent — purple/void colour scheme
				_apply_slot_style(panel, Color(0.10, 0.04, 0.22, 1), Color(0.65, 0.25, 0.90, 1))
				lbl.text = trap.card_name
				panel.tooltip_text = "%s\n─\n%s" % [trap.card_name, trap.description]
			else:
				# Hidden trap: face-down — amber scheme
				_apply_slot_style(panel, Color(0.12, 0.08, 0.05, 1), Color(0.85, 0.45, 0.10, 1))
				lbl.text = trap.card_name
				panel.tooltip_text = "%s\n─\n%s" % [trap.card_name, trap.description]
		else:
			_apply_slot_style(panel, Color(0.08, 0.08, 0.14, 1), Color(0.22, 0.22, 0.38, 1))
			lbl.text = "[ — ]"
			panel.tooltip_text = ""

# ---------------------------------------------------------------------------
# Rune & Ritual system
# ---------------------------------------------------------------------------

## Register 2-rune ritual handlers for the given environment.
## Called when the environment is first played.
func _register_env_rituals(env: EnvironmentCardData) -> void:
	for ritual in env.rituals:
		var r: RitualData = ritual
		var h := func(_ctx: EventContext): _handler_env_ritual(r)
		_env_ritual_handlers.append(h)
		trigger_manager.register(Enums.TriggerEvent.ON_RUNE_PLACED, h, 5)
		trigger_manager.register(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, h, 5)

## Unregister all 2-rune ritual handlers for the current environment.
## Called when the environment is replaced or destroyed.
func _unregister_env_rituals() -> void:
	for h in _env_ritual_handlers:
		trigger_manager.unregister(Enums.TriggerEvent.ON_RUNE_PLACED, h)
		trigger_manager.unregister(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, h)
	_env_ritual_handlers.clear()

## Remove any persistent stat buffs left on the board by the given environment.
## Called when the environment is replaced mid-turn so buffs don't linger.
func _unregister_env_aura(env: EnvironmentCardData) -> void:
	match env.passive_effect_id:
		"dark_covenant_passive":
			for m in player_board:
				BuffSystem.remove_source(m, "dark_covenant")
				_refresh_slot_for(m)

## Register persistent aura event handlers for a newly placed rune.
## Each rune type subscribes to its specific event(s) in TriggerManager.
## Dominion Rune is a calculated ATK modifier applied/removed directly via _refresh_dominion_aura().
## Register persistent aura event handlers for a newly placed rune.
## _rune_aura_handlers stores Array[{event, handler}] so _remove_rune_aura
## needs no match block — it just unregisters from the stored event.
func _apply_rune_aura(rune: TrapCardData) -> void:
	var entries: Array = []
	var mult := _rune_aura_multiplier()
	match rune.aura_effect_id:
		"void_rune_aura":
			var dmg := 100 * mult
			var h := func(_ctx: EventContext):
				_log("  Void Rune: deal %d Void Bolt damage to enemy hero." % dmg, _LogType.PLAYER)
				_deal_void_bolt_damage(dmg)
			trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TURN_START, h, 20)
			entries.append({event = Enums.TriggerEvent.ON_PLAYER_TURN_START, handler = h})
		"blood_rune_aura":
			var heal := 100 * mult
			var h := func(_ctx: EventContext):
				_log("  Blood Rune: friendly minion died — restore %d HP." % heal, _LogType.PLAYER)
				_on_hero_healed("player", heal)
			trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED, h, 20)
			entries.append({event = Enums.TriggerEvent.ON_PLAYER_MINION_DIED, handler = h})
		"dominion_rune_aura":
			var bonus := 100 * mult
			_refresh_dominion_aura(true, bonus)
			var h := func(ctx: EventContext):
				if ctx.minion != null and ctx.minion.card_data.minion_type == Enums.MinionType.DEMON:
					BuffSystem.apply(ctx.minion, Enums.BuffType.ATK_BONUS, bonus, "dominion_rune")
					_refresh_slot_for(ctx.minion)
			trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, h, 20)
			entries.append({event = Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, handler = h})
		"shadow_rune_aura":
			var stacks := mult
			var h := func(ctx: EventContext):
				if ctx.minion != null:
					for _i in stacks:
						_corrupt_minion(ctx.minion)
					_log("  Shadow Rune: %s enters with %d Corruption." % [ctx.minion.card_data.card_name, stacks], _LogType.PLAYER)
			trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, h, 20)
			entries.append({event = Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, handler = h})
	if not entries.is_empty():
		_rune_aura_handlers.append({rune_id = rune.id, entries = entries})

## Unregister aura handlers when a rune is removed (destroyed or consumed by ritual).
## Finds the FIRST placement entry matching rune.id and removes only that one,
## so two runes of the same type are handled independently.
func _remove_rune_aura(rune: TrapCardData) -> void:
	for i in _rune_aura_handlers.size():
		if _rune_aura_handlers[i].rune_id == rune.id:
			for entry in _rune_aura_handlers[i].entries:
				trigger_manager.unregister(entry.event, entry.handler)
			_rune_aura_handlers.remove_at(i)
			break
	if rune.aura_effect_id == "dominion_rune_aura":
		_refresh_dominion_aura(false)

## Apply or remove the Dominion Rune's ATK aura on all friendly Demons.
## active=true adds the bonus per-minion; active=false removes all "dominion_rune" entries.
## amount is passed in from _apply_rune_aura so runic_attunement doubling is respected.
func _refresh_dominion_aura(active: bool, amount: int = 100) -> void:
	for m in player_board:
		if m.card_data.minion_type == Enums.MinionType.DEMON:
			if active:
				BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, amount, "dominion_rune")
			else:
				BuffSystem.remove_source(m, "dominion_rune")
			_refresh_slot_for(m)
	if active:
		_log("  Dominion Rune: all friendly Demons gain +%d ATK." % amount, _LogType.PLAYER)
	else:
		_log("  Dominion Rune removed: all friendly Demons lose ATK bonus.", _LogType.PLAYER)

## Grand ritual handler — registered at combat start for each talent with grand_ritual set.
## Priority 0 ensures it fires before environment rituals (priority 5).
func _handler_grand_ritual(ritual: RitualData) -> void:
	var runes := active_traps.filter(func(t: TrapCardData): return t.is_rune)
	if _runes_satisfy(runes, ritual.required_runes):
		_fire_ritual(ritual)

## Environment ritual handler — registered dynamically when an environment is played.
## Priority 5 ensures it fires after grand rituals; if a grand ritual already consumed
## the runes, _runes_satisfy will return false and this handler does nothing.
func _handler_env_ritual(ritual: RitualData) -> void:
	var runes := active_traps.filter(func(t: TrapCardData): return t.is_rune)
	if _runes_satisfy(runes, ritual.required_runes):
		_fire_ritual(ritual)

## Talent: rune_caller — draw a random Rune card from the player's deck into hand.
func _draw_rune_from_deck() -> void:
	var runes_in_deck: Array = []
	for c in turn_manager.player_deck:
		if c is TrapCardData and (c as TrapCardData).is_rune:
			runes_in_deck.append(c)
	if runes_in_deck.is_empty():
		_log("  Rune Caller: no Runes left in deck.", _LogType.PLAYER)
		return
	var chosen: CardData = runes_in_deck[randi() % runes_in_deck.size()]
	turn_manager.player_deck.erase(chosen)
	turn_manager.add_to_hand(chosen)
	_log("  Rune Caller: drew %s from deck." % chosen.card_name, _LogType.PLAYER)

## Talent: runic_attunement — multiplier applied to all Rune aura numeric values.
func _rune_aura_multiplier() -> int:
	return 2 if _has_talent("runic_attunement") else 1

## Returns true if the rune board contains at least one of each required rune type.
func _runes_satisfy(runes: Array, required: Array[int]) -> bool:
	var available: Array[int] = []
	for r in runes:
		available.append((r as TrapCardData).rune_type)
	for req in required:
		if req not in available:
			return false
	return true

## Consume the required runes and cast the ritual effect.
func _fire_ritual(ritual: RitualData) -> void:
	for req in ritual.required_runes:
		for i in active_traps.size():
			if active_traps[i].is_rune and active_traps[i].rune_type == req:
				_remove_rune_aura(active_traps[i])
				active_traps.remove_at(i)
				break
	_update_trap_display()
	_log("★ RITUAL — %s!" % ritual.ritual_name, _LogType.PLAYER)
	_resolve_ritual_effect(ritual.effect_id)
	# Talent: ritual_surge — summon 2 Void Imps after any ritual fires
	if _has_talent("ritual_surge"):
		_summon_void_imp()
		_summon_void_imp()
		_log("  Ritual Surge: 2 Void Imps summoned!", _LogType.PLAYER)

## Resolve the gameplay effect of a triggered ritual.
## Add a new match arm here when a new ritual effect_id is designed.
func _resolve_ritual_effect(effect_id: String) -> void:
	match effect_id:
		"demon_cataclysm":
			_log("  Demon Cataclysm: deal 300 damage to all enemies.", _LogType.PLAYER)
			for enemy in enemy_board.duplicate():
				combat_manager.apply_spell_damage(enemy, 300)
		"forbidden_insight":
			_log("  Forbidden Insight: draw 2 cards, gain 1 Mana.", _LogType.PLAYER)
			turn_manager.draw_card()
			turn_manager.draw_card()
			turn_manager.gain_mana(1)
		"demon_ascendant":
			# Deal 200 damage to 2 random enemy minions, then Special Summon a 500/500 Demon.
			_log("  Demon Ascendant: deal 200 damage to 2 random enemy minions.", _LogType.PLAYER)
			for _i in 2:
				var target_m := _find_random_enemy_minion()
				if target_m:
					combat_manager.apply_spell_damage(target_m, 200)
			_log("  Demon Ascendant: Special Summon a 500/500 Demon Ascendant!", _LogType.PLAYER)
			for slot in player_slots:
				if slot.is_empty():
					var demon_data := CardDatabase.get_card("ritual_demon") as MinionCardData
					if demon_data:
						var instance := MinionInstance.create(demon_data, "player")
						player_board.append(instance)
						slot.place_minion(instance)
						# Special Summon: do NOT fire ON_PLAYER_MINION_SUMMONED (no on-play effects)
					break
		"soul_cataclysm":
			# Deal 400 Void Bolt damage to enemy hero, restore 400 HP to player hero.
			_log("  Soul Cataclysm: 400 Void Bolt damage to enemy hero!", _LogType.PLAYER)
			_deal_void_bolt_damage(400)
			_log("  Soul Cataclysm: restore 400 HP to your hero.", _LogType.PLAYER)
			_on_hero_healed("player", 400)
		"abyssal_dominion":
			# Grand Ritual: 300 damage to all enemy minions + all friendly Demons +200/+200 permanently.
			_log("  Abyssal Dominion: 300 damage to all enemy minions!", _LogType.PLAYER)
			for enemy in enemy_board.duplicate():
				combat_manager.apply_spell_damage(enemy, 300)
			_log("  Abyssal Dominion: all friendly Demons gain +200 ATK and +200 HP permanently.", _LogType.PLAYER)
			for m in player_board:
				if m.card_data.minion_type == Enums.MinionType.DEMON:
					BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 200, "abyssal_dominion")
					m.current_health += 200
					_refresh_slot_for(m)
		_:
			_log("  Ritual effect '%s' not yet implemented." % effect_id, _LogType.PLAYER)

func _update_enemy_trap_display() -> void:
	for i in enemy_trap_slot_panels.size():
		var panel := enemy_trap_slot_panels[i]
		var lbl   := enemy_trap_slot_labels[i]
		_apply_slot_style(panel, Color(0.08, 0.08, 0.14, 1), Color(0.22, 0.22, 0.38, 1))
		lbl.text = "[ — ]"

func _apply_slot_style(panel: Panel, bg: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color            = bg
	style.border_width_left   = 2
	style.border_width_top    = 2
	style.border_width_right  = 2
	style.border_width_bottom = 2
	style.border_color        = border
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left  = 4
	panel.add_theme_stylebox_override("panel", style)

# ---------------------------------------------------------------------------
# Hero attack helpers
# ---------------------------------------------------------------------------

func _show_hero_button(visible_state: bool) -> void:
	if enemy_hero_button:
		enemy_hero_button.visible = visible_state

# ---------------------------------------------------------------------------
# Hero passives panel
# ---------------------------------------------------------------------------

## Initialise the panel on combat load — show compact hero name.
func _setup_hero_passives_panel() -> void:
	if not _hp_panel:
		return
	if _hp_desc_label:
		_hp_desc_label.text = _hero_passives_compact()

## Compact one-liner shown at rest.
func _hero_passives_compact() -> String:
	var hero := HeroDatabase.get_hero(GameManager.current_hero)
	if hero == null:
		return "Hero Passives"
	var talent_count := GameManager.unlocked_talents.size()
	if talent_count > 0:
		return "%s  (%d talent%s)\n[ Hover for details ]" % [hero.hero_name, talent_count, "s" if talent_count != 1 else ""]
	return "%s\n[ Hover for passives ]" % hero.hero_name

## Full descriptions shown on hover.
## Shows always-on hero passives, then each unlocked talent by branch.
func _hero_passives_detail() -> String:
	var hero := HeroDatabase.get_hero(GameManager.current_hero)
	if hero == null:
		return ""
	var lines: Array[String] = [
		"%s, %s" % [hero.hero_name, hero.title],
		"━━━━━━━━━━━━━━━━━━",
		"[Always On]",
	]
	for p in hero.passives:
		lines.append(p.description)
	var unlocked: Array[String] = GameManager.unlocked_talents
	if unlocked.is_empty():
		lines.append("── No talents unlocked ──")
		return "\n".join(lines)
	# Group by branch for readability
	for branch_id in hero.talent_branch_ids:
		var branch_talents := TalentDatabase.get_branch(branch_id)
		var has_any := false
		var branch_lines: Array[String] = []
		for t in branch_talents:
			if t.id in unlocked:
				if not has_any:
					branch_lines.append("── %s ──" % TalentDatabase.get_branch_display_name(branch_id))
					has_any = true
				branch_lines.append("● %s: %s" % [t.talent_name, t.description])
		if has_any:
			lines.append_array(branch_lines)
	return "\n".join(lines)

func _on_hero_passives_hover_enter() -> void:
	if _hp_desc_label:
		_hp_desc_label.text = _hero_passives_detail()

func _on_hero_passives_hover_exit() -> void:
	if _hp_desc_label:
		_hp_desc_label.text = _hero_passives_compact()

func _setup_enemy_status_panel() -> void:
	var ui_root: Node = get_node_or_null("UI")
	if not ui_root:
		return

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(240, 130)
	panel.anchor_left   = 1.0
	panel.anchor_right  = 1.0
	panel.anchor_top    = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left   = -258.0
	panel.offset_right  = -10.0
	panel.offset_top    = 6.0
	panel.offset_bottom = 145.0

	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.08, 0.04, 0.13, 0.93)
	style.border_color = Color(0.55, 0.20, 0.80, 1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 5)
	vbox.add_theme_constant_override("margin_left", 6)
	vbox.add_theme_constant_override("margin_right", 6)
	vbox.add_theme_constant_override("margin_top", 5)
	vbox.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(vbox)

	# Portrait row
	var portrait_row := HBoxContainer.new()
	portrait_row.add_theme_constant_override("separation", 8)
	vbox.add_child(portrait_row)

	var portrait := ColorRect.new()
	portrait.custom_minimum_size = Vector2(44, 44)
	portrait.color = Color(0.25, 0.08, 0.45, 1)
	portrait_row.add_child(portrait)

	var initial_label := Label.new()
	initial_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	initial_label.add_theme_font_size_override("font_size", 24)
	initial_label.add_theme_color_override("font_color", Color(0.85, 0.60, 1.0, 1))
	if GameManager.current_enemy:
		initial_label.text = GameManager.current_enemy.enemy_name.left(1)
	portrait.add_child(initial_label)

	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.90, 0.65, 1.0, 1))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if GameManager.current_enemy:
		var prefix := "⚔ BOSS\n" if GameManager.is_boss_fight() else ""
		name_lbl.text = prefix + GameManager.current_enemy.enemy_name
	portrait_row.add_child(name_lbl)

	vbox.add_child(HSeparator.new())

	_enemy_status_hp_label = Label.new()
	_enemy_status_hp_label.add_theme_font_size_override("font_size", 13)
	_enemy_status_hp_label.add_theme_color_override("font_color", Color(0.95, 0.40, 0.40, 1))
	vbox.add_child(_enemy_status_hp_label)

	_enemy_status_essence_label = Label.new()
	_enemy_status_essence_label.add_theme_font_size_override("font_size", 13)
	_enemy_status_essence_label.add_theme_color_override("font_color", Color(0.45, 0.80, 1.0, 1))
	vbox.add_child(_enemy_status_essence_label)

	_enemy_status_marks_label = Label.new()
	_enemy_status_marks_label.add_theme_font_size_override("font_size", 13)
	_enemy_status_marks_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15, 1))
	_enemy_status_marks_label.visible = false
	vbox.add_child(_enemy_status_marks_label)

	_enemy_status_panel = panel
	ui_root.add_child(panel)
	_update_enemy_status_panel()

func _update_enemy_status_panel() -> void:
	if not _enemy_status_panel:
		return
	if _enemy_status_hp_label:
		_enemy_status_hp_label.text = "❤ HP: %d / %d" % [enemy_hp, enemy_hp_max]
	if _enemy_status_essence_label:
		var ess_max := enemy_ai.essence_max if enemy_ai else 0
		var ess_cur := enemy_ai.essence if enemy_ai else 0
		_enemy_status_essence_label.text = "◆ Essence: %d / %d" % [ess_cur, ess_max]
	if _enemy_status_marks_label:
		if enemy_void_marks > 0:
			_enemy_status_marks_label.text = "☠ Void Mark: ×%d" % enemy_void_marks
			_enemy_status_marks_label.visible = true
		else:
			_enemy_status_marks_label.visible = false

# ---------------------------------------------------------------------------
# Large card preview (hover over hand cards or board slots)
# ---------------------------------------------------------------------------

func _setup_large_preview() -> void:
	var ui_root := get_node_or_null("UI")
	if not ui_root:
		return
	_large_preview = CARD_VISUAL_SCENE.instantiate() as CardVisual
	_large_preview.apply_size_mode("combat_preview")
	_large_preview.z_index      = 20
	_large_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_large_preview.visible      = false
	ui_root.add_child(_large_preview)
	# $UI is a CanvasLayer — children use screen-space position, not anchors
	var vp_size := get_viewport().get_visible_rect().size
	var ps      := _large_preview.size
	_large_preview.position = Vector2(16.0, vp_size.y - ps.y - 16.0)

func _show_large_preview(card_data: CardData) -> void:
	if not _large_preview or not card_data:
		return
	_large_preview.setup(card_data)
	_large_preview.enable_tooltip()
	_large_preview.visible = true

func _hide_large_preview() -> void:
	if _large_preview:
		_large_preview.visible = false

func _on_board_slot_hover_enter(slot: BoardSlot) -> void:
	if slot.minion and slot.minion.card_data:
		_show_large_preview(slot.minion.card_data)

func _on_enemy_hero_button_pressed() -> void:
	if not turn_manager.is_player_turn or selected_attacker == null:
		return
	if CombatManager.board_has_taunt(enemy_board):
		return
	if not selected_attacker.can_attack_hero():
		return
	_log("Your %s attacks Enemy Hero" % selected_attacker.card_data.card_name)
	combat_manager.resolve_minion_attack_hero(selected_attacker, "enemy")
	selected_attacker = null
	_clear_all_highlights()
	_show_hero_button(false)

# ---------------------------------------------------------------------------
# Win / loss
# ---------------------------------------------------------------------------

func _on_victory() -> void:
	if _combat_ended:
		return
	_combat_ended = true
	GameManager.advance_node()
	if GameManager.is_run_complete():
		GameManager.end_run(true)
		_disable_combat_buttons()
		if game_over_label:
			game_over_label.text = "RUN COMPLETE!\nThe Abyss is silenced."
		if restart_button:
			restart_button.text = "Return to Menu"
		if game_over_panel:
			game_over_panel.visible = true
	else:
		GameManager.go_to_scene.call_deferred("res://rewards/RewardScene.tscn")

func _on_defeat() -> void:
	if _combat_ended:
		return
	_combat_ended = true
	GameManager.end_run(false)
	_disable_combat_buttons()
	if game_over_label:
		game_over_label.text = "DEFEAT"
	if restart_button:
		restart_button.text = "Return to Menu"
	if game_over_panel:
		game_over_panel.visible = true

func _disable_combat_buttons() -> void:
	if end_turn_essence_button:
		end_turn_essence_button.disabled = true
	if end_turn_mana_button:
		end_turn_mana_button.disabled = true
	_show_hero_button(false)

func _on_restart_pressed() -> void:
	GameManager.go_to_scene("res://ui/MainMenu.tscn")

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

func _find_slot_for(minion: MinionInstance) -> BoardSlot:
	var slots := player_slots if minion.owner == "player" else enemy_slots
	for slot in slots:
		if slot.minion == minion:
			return slot
	return null

# ---------------------------------------------------------------------------
# Enemy attack visuals
# ---------------------------------------------------------------------------

func _on_enemy_about_to_attack(attacker: MinionInstance, target: MinionInstance) -> void:
	var atk_slot := _find_slot_for(attacker)
	var def_slot := _find_slot_for(target)
	if atk_slot:
		atk_slot.set_highlight(BoardSlot.HighlightMode.SELECTED)
	if def_slot:
		def_slot.set_highlight(BoardSlot.HighlightMode.INVALID)
	_log("Enemy %s attacks your %s" % [attacker.card_data.card_name, target.card_data.card_name], _LogType.ENEMY)
	# Fire ON_ENEMY_ATTACK BEFORE the attack resolves (enables cancel/pre-damage traps)
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_ATTACK, "enemy")
	ctx.minion = attacker
	trigger_manager.fire(ctx)

func _on_enemy_attacking_hero(attacker: MinionInstance) -> void:
	var atk_slot := _find_slot_for(attacker)
	if atk_slot:
		atk_slot.set_highlight(BoardSlot.HighlightMode.SELECTED)
	_log("Enemy %s attacks your Hero" % attacker.card_data.card_name, _LogType.ENEMY)
	# Fire ON_ENEMY_ATTACK BEFORE the attack resolves
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_ATTACK, "enemy")
	ctx.minion = attacker
	trigger_manager.fire(ctx)

enum _LogType { TURN, PLAYER, ENEMY, DAMAGE, HEAL, TRAP, DEATH }
const _LOG_MAX := 80

func _log(msg: String, type: _LogType = _LogType.PLAYER) -> void:
	if not _log_container:
		return
	var lbl := Label.new()
	lbl.text = msg
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", _log_color(type))
	_log_container.add_child(lbl)
	while _log_container.get_child_count() > _LOG_MAX:
		var old := _log_container.get_child(0)
		_log_container.remove_child(old)
		old.free()
	if _log_scroll:
		_log_scroll.set_deferred("scroll_vertical", 999999)

func _log_color(type: _LogType) -> Color:
	match type:
		_LogType.TURN:   return Color(0.50, 0.50, 0.62, 1)
		_LogType.PLAYER: return Color(0.50, 0.82, 1.00, 1)
		_LogType.ENEMY:  return Color(1.00, 0.55, 0.40, 1)
		_LogType.DAMAGE: return Color(1.00, 0.38, 0.38, 1)
		_LogType.HEAL:   return Color(0.35, 0.90, 0.55, 1)
		_LogType.TRAP:   return Color(1.00, 0.85, 0.15, 1)
		_LogType.DEATH:  return Color(0.65, 0.45, 0.75, 1)
	return Color(0.9, 0.9, 0.9, 1)

func _highlight_empty_player_slots() -> void:
	_clear_all_highlights()
	for slot in player_slots:
		if slot.is_empty():
			slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET)

func _highlight_valid_attack_targets() -> void:
	_clear_all_highlights()
	if selected_attacker == null:
		return
	# Highlight the selected attacker's own slot
	for slot in player_slots:
		if slot.minion == selected_attacker:
			slot.set_highlight(BoardSlot.HighlightMode.SELECTED)
			break
	var has_taunt := CombatManager.board_has_taunt(enemy_board)
	for slot in enemy_slots:
		if slot.is_empty():
			continue
		var valid := (not has_taunt) or slot.minion.has_guard()
		slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET if valid else BoardSlot.HighlightMode.INVALID)
	# Hero is valid only when no Guard minion blocks it AND attacker can attack hero (not Swift)
	_show_hero_button(not has_taunt and selected_attacker.can_attack_hero())

# ===========================================================================
# TriggerManager setup
# Called once at the end of _ready(), after all run state is initialised.
#
# HOW TO ADD A NEW MECHANIC:
#   1. Write a handler method  func _handler_my_thing(ctx: EventContext) -> void
#   2. Register it here:  trigger_manager.register(EVENT, _handler_my_thing, priority)
#   3. Fire the event from the appropriate CombatScene callsite if it doesn't exist yet.
# ===========================================================================

func _setup_triggers() -> void:
	# -----------------------------------------------------------------------
	# ON_PLAYER_TURN_START  (priority: 0=relics, 10=environment, 20+=talents/cards)
	# -----------------------------------------------------------------------
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TURN_START, _handler_player_turn_relics,      0)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TURN_START, _handler_player_turn_environment, 10)
	# Nyx'ael is a board-presence check — always registered, fires only if card is on board
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TURN_START, _handler_nyx_ael_passive, 21)

	# -----------------------------------------------------------------------
	# ON_PLAYER_SPELL_CAST  (priority: 0=board passives)
	# -----------------------------------------------------------------------
	# Void Archmagus is a board-presence check — always registered, fires only if on board
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, _handler_void_archmagus_on_spell, 0)

	# -----------------------------------------------------------------------
	# ON_ENEMY_TURN_START  (priority: 10=environment, 30=traps)
	# -----------------------------------------------------------------------
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_TURN_START, _handler_enemy_turn_environment, 10)
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_TURN_START, _trap_check_enemy_turn_start,    30)

	# -----------------------------------------------------------------------
	# ON_PLAYER_CARD_DRAWN  (priority: 0=hero passives)
	# -----------------------------------------------------------------------
	if _has_talent("void_echo"):
		trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, _handler_talent_void_echo, 0)

	# -----------------------------------------------------------------------
	# ON_PLAYER_MINION_PLAYED  (priority: hand-play-only talent effects)
	# -----------------------------------------------------------------------
	if _has_talent("rune_caller"):
		trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, _handler_talent_rune_caller,          0)
	# on_play_effect (battle cry) fires after talent effects
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, _handler_player_minion_on_play_effect, 10)

	# -----------------------------------------------------------------------
	# ON_PLAYER_MINION_SUMMONED  (priority: 0=hero passives, 10=relics, 20+=talents, 30=board synergies)
	# -----------------------------------------------------------------------
	if HeroDatabase.has_passive(GameManager.current_hero, "void_imp_boost"):
		trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, _handler_passive_void_imp_boost,       0)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED,     _handler_relic_on_summon,             10)
	if _has_talent("swarm_discipline"):
		trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, _handler_talent_swarm_discipline,     20)
	if _has_talent("abyssal_legion"):
		trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, _handler_talent_abyssal_legion,       21)
	if _has_talent("piercing_void"):
		trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, _handler_talent_piercing_void,        23)
	if _has_talent("imp_evolution"):
		trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, _handler_talent_imp_evolution,        24)
	if _has_talent("imp_warband"):
		trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, _handler_talent_imp_warband,          25)
	# Board synergies always registered — handlers check board state at fire time
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED,     _handler_board_synergies_on_summon,        30)
	# on_summon_effect fires last (after all buff/synergy handlers have applied)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED,     _handler_player_minion_on_summon_effect,   35)

	# -----------------------------------------------------------------------
	# ON_PLAYER_MINION_DIED  (priority: 0=board passives, 5=deathrattle, 10=talents, 20=traps)
	# -----------------------------------------------------------------------
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED, _handler_board_passives_on_player_death,  0)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED, _handler_minion_on_death_effect,          5)
	if _has_talent("death_bolt"):
		trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED, _handler_talent_death_bolt,           10)
	# Trap: ON_FRIENDLY_DEATH fires during enemy's turn — handler guards internally
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED, _trap_check_friendly_death,               20)

	# -----------------------------------------------------------------------
	# ON_ENEMY_MINION_DIED  (priority: 5=deathrattle)
	# -----------------------------------------------------------------------
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_DIED, _handler_minion_on_death_effect, 5)

	# -----------------------------------------------------------------------
	# ON_ENEMY_MINION_SUMMONED — on-play (priority 5) and on-summon (priority 6), before traps (30)
	# -----------------------------------------------------------------------
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, _handler_enemy_minion_on_play,          5)
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, _handler_enemy_minion_on_summon_effect, 6)

	# -----------------------------------------------------------------------
	# Trap routing for enemy actions  (priority 30 — after any future pre-trap passives)
	# -----------------------------------------------------------------------
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, _trap_check_enemy_summon, 30)
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST,      _trap_check_enemy_spell,  30)
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_ATTACK,          _trap_check_enemy_attack, 30)
	trigger_manager.register(Enums.TriggerEvent.ON_HERO_DAMAGED,          _trap_check_damage_taken, 10)

	# -----------------------------------------------------------------------
	# ON_RUNE_PLACED — grand rituals from active talents (priority 0, before env rituals at 5)
	# Env rituals are registered dynamically in _register_env_rituals().
	# -----------------------------------------------------------------------
	for talent_id in GameManager.unlocked_talents:
		var talent: TalentData = TalentDatabase.get_talent(talent_id)
		if talent != null and talent.grand_ritual != null:
			var gr: RitualData = talent.grand_ritual
			trigger_manager.register(Enums.TriggerEvent.ON_RUNE_PLACED,
				func(_ctx: EventContext): _handler_grand_ritual(gr), 0)
			trigger_manager.register(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED,
				func(_ctx: EventContext): _handler_grand_ritual(gr), 0)

# ---------------------------------------------------------------------------
# ON_PLAYER_TURN_START handlers
# ---------------------------------------------------------------------------

func _handler_player_turn_relics(_ctx: EventContext) -> void:
	var relics := GameManager.player_relics
	_relic_first_card_free = "void_crystal" in relics
	if "blood_pact" in relics:
		_log("  Blood Pact: deal 100 damage to enemy hero.", _LogType.PLAYER)
		_on_hero_damaged("enemy", 100)
	if "soul_ember" in relics:
		turn_manager.essence = mini(turn_manager.essence + 1, turn_manager.essence_max)
		turn_manager.resources_changed.emit(
			turn_manager.essence, turn_manager.essence_max,
			turn_manager.mana, turn_manager.mana_max)
		_log("  Soul Ember: +1 Essence.", _LogType.PLAYER)
	if "ancient_tome" in relics:
		turn_manager.draw_card()
		_log("  Ancient Tome: draw 1 extra card.", _LogType.PLAYER)
	if "void_surge" in relics and not player_board.is_empty():
		for minion in player_board:
			BuffSystem.apply(minion, Enums.BuffType.TEMP_ATK, 100, "void_surge", true)
			_refresh_slot_for(minion)
		_log("  Void Surge: all friendly minions +100 ATK this turn.", _LogType.PLAYER)

func _handler_player_turn_environment(_ctx: EventContext) -> void:
	if active_environment != null:
		_apply_environment_passive(active_environment.passive_effect_id)

func _handler_nyx_ael_passive(_ctx: EventContext) -> void:
	for m in player_board:
		if _minion_has_tag(m, "void_champion"):
			for enemy in enemy_board.duplicate():
				if not BuffSystem.has_type(enemy, Enums.BuffType.CORRUPTION):
					_corrupt_minion(enemy)
			for enemy in enemy_board.duplicate():
				if BuffSystem.has_type(enemy, Enums.BuffType.CORRUPTION):
					_log("  Nyx'ael: %s takes 200 damage." % enemy.card_data.card_name, _LogType.PLAYER)
					combat_manager.apply_spell_damage(enemy, 200)
			break

# ---------------------------------------------------------------------------
# ON_ENEMY_TURN_START handlers
# ---------------------------------------------------------------------------

func _handler_enemy_turn_environment(_ctx: EventContext) -> void:
	if active_environment != null and active_environment.fires_on_enemy_turn:
		_apply_environment_passive(active_environment.passive_effect_id)

func _trap_check_enemy_turn_start(ctx: EventContext) -> void:
	_check_and_fire_traps(ctx.event_type)

# ---------------------------------------------------------------------------
# ON_PLAYER_SPELL_CAST handlers
# ---------------------------------------------------------------------------

## Board passive on spell cast — fires each unique passive once per spell (first matching minion wins).
func _handler_void_archmagus_on_spell(_ctx: EventContext) -> void:
	var fired: Array[String] = []
	for m in player_board:
		var eid: String = m.card_data.on_spell_cast_passive_effect_id
		if eid != "" and not eid in fired:
			_apply_spell_cast_passive(eid)
			fired.append(eid)

## Resolve a board passive triggered when the player casts any spell.
func _apply_spell_cast_passive(effect_id: String) -> void:
	match effect_id:
		"add_void_bolt_on_spell":
			var bolt := CardDatabase.get_card("void_bolt")
			if bolt:
				turn_manager.add_to_hand(bolt)
				_log("  Void Archmagus: Void Bolt added to hand.", _LogType.PLAYER)

## Fire all on_void_bolt_passive_effect_id passives on the player board.
## Counts stacking minions (e.g. two Void Channelers = 2 marks).
func _apply_void_bolt_passives() -> void:
	var counts: Dictionary = {}
	for m in player_board:
		var eid: String = m.card_data.on_void_bolt_passive_effect_id
		if eid != "":
			counts[eid] = counts.get(eid, 0) + 1
	for eid in counts:
		_apply_void_bolt_passive(eid, counts[eid])

## Resolve a single void bolt passive with the count of minions that triggered it.
func _apply_void_bolt_passive(effect_id: String, count: int) -> void:
	match effect_id:
		"void_mark_per_channeler":
			_apply_void_mark(count)
			_log("  Void Channeler: +%d Void Mark(s) applied." % count, _LogType.PLAYER)

# ---------------------------------------------------------------------------
# ON_PLAYER_CARD_DRAWN handler
# ---------------------------------------------------------------------------

func _handler_talent_void_echo(ctx: EventContext) -> void:
	if ctx.card == null or not _card_has_tag(ctx.card, "void_imp"):
		return
	# Append directly (not via turn_manager.add_to_hand) to avoid re-triggering card_drawn signal
	var copy := CardDatabase.get_card("void_imp")
	if copy and turn_manager.player_hand.size() < TurnManager.HAND_SIZE_MAX:
		turn_manager.player_hand.append(copy)
		if hand_display:
			hand_display.add_card(copy)
		_log("  Void Echo: Void Imp drawn — free copy added to hand.", _LogType.PLAYER)

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_SUMMONED handlers  (fired in priority order by TriggerManager)
# ---------------------------------------------------------------------------

func _handler_passive_void_imp_boost(ctx: EventContext) -> void:
	if not _is_void_imp_type(ctx.minion):
		return
	BuffSystem.apply(ctx.minion, Enums.BuffType.ATK_BONUS, 100, "void_imp_boost")
	ctx.minion.current_health += 100
	var hero := HeroDatabase.get_hero(GameManager.current_hero)
	_log("  %s: %s summoned with +100/+100." % [(hero.hero_name if hero else "Hero"), ctx.card.card_name], _LogType.PLAYER)

func _handler_relic_on_summon(ctx: EventContext) -> void:
	var relics := GameManager.player_relics
	if "demon_pact" in relics and ctx.minion.card_data.minion_type == Enums.MinionType.DEMON:
		BuffSystem.apply(ctx.minion, Enums.BuffType.ATK_BONUS, 100, "demon_pact")
		_log("  Demon Pact: %s gains +100 ATK." % ctx.card.card_name, _LogType.PLAYER)
	if "abyssal_core" in relics:
		BuffSystem.apply(ctx.minion, Enums.BuffType.ATK_BONUS, 100, "abyssal_core")
		ctx.minion.current_health += 100
		_log("  Abyssal Core: %s gains +100/+100." % ctx.card.card_name, _LogType.PLAYER)

func _handler_talent_swarm_discipline(ctx: EventContext) -> void:
	if not _is_void_imp_type(ctx.minion):
		return
	ctx.minion.current_health += 100
	_log("  Swarm Discipline: %s +100 HP." % ctx.card.card_name, _LogType.PLAYER)

func _handler_talent_abyssal_legion(ctx: EventContext) -> void:
	if not _is_void_imp_type(ctx.minion):
		return
	var imp_count := _count_void_imps_on_board()
	if imp_count >= 3:
		BuffSystem.apply(ctx.minion, Enums.BuffType.ATK_BONUS, 100, "abyssal_legion")
		ctx.minion.current_health += 100
		_log("  Abyssal Legion: %s +100/+100." % ctx.card.card_name, _LogType.PLAYER)
		if imp_count == 3:
			for m in player_board:
				if m != ctx.minion and _is_void_imp_type(m):
					BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "abyssal_legion")
					m.current_health += 100
					_refresh_slot_for(m)
					_log("  Abyssal Legion: %s +100/+100." % m.card_data.card_name, _LogType.PLAYER)

func _handler_talent_rune_caller(ctx: EventContext) -> void:
	if not _card_has_tag(ctx.card, "void_imp"):
		return
	_draw_rune_from_deck()

func _handler_talent_piercing_void(ctx: EventContext) -> void:
	# Only base Void Imp — not Senior Void Imp
	if not _card_has_tag(ctx.card, "base_void_imp"):
		return
	_deal_void_bolt_damage(200)
	_apply_void_mark(1)

func _handler_talent_imp_evolution(ctx: EventContext) -> void:
	if not _card_has_tag(ctx.card, "base_void_imp") or _imp_evolution_used_this_turn:
		return
	var senior := CardDatabase.get_card("senior_void_imp")
	if senior and turn_manager.player_hand.size() < TurnManager.HAND_SIZE_MAX:
		turn_manager.add_to_hand(senior)
		_imp_evolution_used_this_turn = true
		_log("  Imp Evolution: Senior Void Imp added to hand.", _LogType.PLAYER)

func _handler_talent_imp_warband(ctx: EventContext) -> void:
	if not _card_has_tag(ctx.card, "senior_void_imp"):
		return
	for m in player_board:
		if _is_void_imp_type(m):
			BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 50, "imp_warband")
			_refresh_slot_for(m)
	_log("  Imp Warband: Senior Void Imp summoned — all Void Imps +50 ATK.", _LogType.PLAYER)

func _handler_board_synergies_on_summon(ctx: EventContext) -> void:
	var summoned := ctx.minion
	for m in player_board:
		var pid: String = (m.card_data as MinionCardData).passive_effect_id
		if pid != "" and m != summoned:
			_apply_board_passive_on_summon(pid, m, summoned)
	if _is_void_imp_type(summoned):
		_refresh_slot_for(summoned)
		_check_champion_triggers()

## Resolve a persistent board passive triggered when a friendly minion is summoned.
func _apply_board_passive_on_summon(passive_id: String, passive_owner: MinionInstance, summoned: MinionInstance) -> void:
	match passive_id:
		"buff_void_imp_on_summon":
			if _is_void_imp_type(summoned):
				summoned.current_health += 100
				_log("  Imp Handler: %s gains +100 HP." % summoned.card_data.card_name, _LogType.PLAYER)
		"void_imp_taunt_aura":
			if _is_void_imp_type(summoned):
				BuffSystem.apply(summoned, Enums.BuffType.GRANT_GUARD, 1, "imp_overseer_aura")

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_DIED handlers
# ---------------------------------------------------------------------------

func _handler_minion_on_death_effect(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var effect_id: String = (minion.card_data as MinionCardData).on_death_effect
	if not effect_id.is_empty():
		_resolve_on_death_effect(minion)

func _handler_board_passives_on_player_death(ctx: EventContext) -> void:
	var dead := ctx.minion
	# Active environment on-death effect
	if active_environment != null and active_environment.on_player_minion_died_effect_id != "":
		match active_environment.on_player_minion_died_effect_id:
			"abyssal_summoning_circle_death":
				_log("  Abyssal Summoning Circle: %s died — deal 100 damage to enemy hero." % dead.card_data.card_name, _LogType.PLAYER)
				_on_hero_damaged("enemy", 100)
	for m in player_board.duplicate():
		var pid: String = (m.card_data as MinionCardData).passive_effect_id
		if pid != "":
			_apply_board_passive_on_death(pid, m, dead)

## Resolve a persistent board passive triggered when a friendly minion dies.
func _apply_board_passive_on_death(passive_id: String, passive_owner: MinionInstance, dead: MinionInstance) -> void:
	match passive_id:
		"void_spark_on_friendly_death":
			_summon_void_spark()
		"deal_200_hero_on_friendly_death":
			_log("  Abyssal Tide: deal 200 damage to enemy hero.", _LogType.PLAYER)
			_on_hero_damaged("enemy", 200)
		"void_mark_on_void_imp_death":
			if _is_void_imp_type(dead):
				_log("  Abyssal Sacrificer: %s died → 1 Void Mark." % dead.card_data.card_name, _LogType.PLAYER)
				_apply_void_mark(1)
		"gain_atk_on_void_imp_death":
			if _is_void_imp_type(dead):
				BuffSystem.apply(passive_owner, Enums.BuffType.ATK_BONUS, 100, "taskmaster_stack")
				_refresh_slot_for(passive_owner)
				_log("  Abyssal Taskmaster: Void Imp died → Taskmaster gains +100 ATK.", _LogType.PLAYER)

func _handler_talent_death_bolt(ctx: EventContext) -> void:
	if not _is_void_imp_type(ctx.minion):
		return
	_log("  Death Bolt: %s death fires Void Bolt." % ctx.minion.card_data.card_name, _LogType.PLAYER)
	_deal_void_bolt_damage(100)

func _trap_check_friendly_death(ctx: EventContext) -> void:
	# Traps that react to friendly death only fire during the enemy's turn
	if not turn_manager.is_player_turn:
		_check_and_fire_traps(ctx.event_type, ctx.minion)

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_PLAYED — on-play (battle cry) resolver (fires only for hand plays)
# ---------------------------------------------------------------------------

## Resolve the on_play_effect (battle cry) of a player minion played from hand.
## Registered at priority 10 — after hand-play talent effects (priority 0).
func _handler_player_minion_on_play_effect(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var effect_id: String = (minion.card_data as MinionCardData).on_play_effect
	if not effect_id.is_empty():
		_resolve_on_play_effect(effect_id, minion, "player")

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_SUMMONED — on-summon effect resolver (fires for ALL player summons)
# ---------------------------------------------------------------------------

## Resolve the on_summon_effect of a player minion whenever it enters the board.
## Fires from hand play, spell effects, trap effects, and token generation.
## Registered at priority 35 — after all buff handlers (passives/talents/relics at 0–30).
func _handler_player_minion_on_summon_effect(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var effect_id: String = (minion.card_data as MinionCardData).on_summon_effect
	if not effect_id.is_empty():
		_resolve_on_play_effect(effect_id, minion, "player")

# ---------------------------------------------------------------------------
# ON_ENEMY_MINION_SUMMONED — on-play / on-summon effect resolvers (fire before traps)
# ---------------------------------------------------------------------------

## Resolve the on_play_effect of an enemy minion (played from EnemyAI hand).
## Priority 5 — runs before trap handlers (priority 30).
func _handler_enemy_minion_on_play(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var effect_id: String = (minion.card_data as MinionCardData).on_play_effect
	if not effect_id.is_empty():
		_resolve_on_play_effect(effect_id, minion, "enemy")

## Resolve the on_summon_effect of an enemy minion (any summon source).
## Priority 6 — after on_play, before traps.
func _handler_enemy_minion_on_summon_effect(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var effect_id: String = (minion.card_data as MinionCardData).on_summon_effect
	if not effect_id.is_empty():
		_resolve_on_play_effect(effect_id, minion, "enemy")

# ---------------------------------------------------------------------------
# ON_ENEMY_MINION_SUMMONED / ON_ENEMY_SPELL_CAST / ON_ENEMY_ATTACK / ON_HERO_DAMAGED
# Trap routing handlers — delegate to _check_and_fire_traps() which handles
# iterating active_traps and calling _resolve_trap_effect().
# ---------------------------------------------------------------------------

func _trap_check_enemy_summon(ctx: EventContext) -> void:
	_check_and_fire_traps(ctx.event_type, ctx.minion)

func _trap_check_enemy_spell(ctx: EventContext) -> void:
	_check_and_fire_traps(ctx.event_type)

func _trap_check_enemy_attack(ctx: EventContext) -> void:
	_check_and_fire_traps(ctx.event_type, ctx.minion)

func _trap_check_damage_taken(ctx: EventContext) -> void:
	_check_and_fire_traps(ctx.event_type)
