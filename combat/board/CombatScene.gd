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
var end_turn_button: Button  # shown at soft cap instead of the two-choice buttons
var fight_label: Label
var hand_display: HandDisplay
var environment_slot: Panel
var environment_slot_name: Label
var environment_slot_desc: Label
var trap_slot_panels: Array[Panel] = []
var trap_slot_labels: Array[Label]  = []
var enemy_trap_slot_panels: Array[Panel] = []
var enemy_trap_slot_labels: Array[Label]  = []
var turn_label: Label
var deck_count_label: Label
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
var _enemy_status_mana_label: Label = null
var _enemy_status_hand_label: Label = null
var _enemy_status_marks_row:   HBoxContainer = null
var _enemy_status_marks_label: Label = null
var _enemy_hero_attack_hint: Label = null
var enemy_hp_max: int = 0

# Player hero status panel (built programmatically)
var _player_status_panel: Panel = null
var _player_status_hp_label: Label = null

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

# Attack animation — captured BEFORE resolve_minion_attack so death doesn't erase them
var _anim_pre_hp:   int       = 0
var _anim_atk_slot: BoardSlot = null
var _anim_def_slot: BoardSlot = null

# Card the player is currently trying to play (dragged or clicked from hand)
var pending_play_card: CardData = null

# Player-chosen target for targeted on-play effects (set after clicking a valid target,
# before clicking the placement slot). Cleared after the minion is placed or deselected.
var pending_minion_target: MinionInstance = null

# True while waiting for the player to click a valid target before choosing a placement slot.
# False when no valid targets existed (skip straight to placement) or after target is chosen.
var _awaiting_minion_target: bool = false

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

## Set to true by Silence Trap to skip the enemy spell's effect resolution.
var _spell_cancelled: bool = false

## Prevents Soul Rune from firing more than once per enemy turn.
var _soul_rune_fired: bool = false

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
	_load_combat_background()
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

	# Override enemy HP / name / fight number from current encounter
	if GameManager.current_enemy != null:
		enemy_hp = GameManager.current_enemy.hp
		enemy_hp_max = enemy_hp
		if fight_label:
			fight_label.text = "Fight %d / %d" % [GameManager.run_node_index + 1, GameManager.TOTAL_FIGHTS]

	# Build the deck from GameManager and begin combat
	var deck_ids: Array[String] = GameManager.player_deck
	var deck: Array[CardData] = CardDatabase.get_cards(deck_ids)
	turn_manager.player_board = player_board
	turn_manager.enemy_board = enemy_board
	_setup_enemy_ai()
	turn_manager.start_combat(deck)
	_setup_enemy_status_panel()
	_setup_player_status_panel()
	_setup_large_preview()
	_setup_triggers()
	_setup_cheat_panel()
	if TestConfig.enabled:
		_apply_test_config.call_deferred()

func _load_combat_background() -> void:
	const ACT_BACKGROUNDS := [
		"res://assets/art/progression/backgrounds/a1_combat_background.png",
		"res://assets/art/progression/backgrounds/a1_combat_background.png",
		"res://assets/art/progression/backgrounds/a1_combat_background.png",
		"res://assets/art/progression/backgrounds/a1_combat_background.png",
	]
	var act: int = clamp(GameManager.get_current_act() - 1, 0, ACT_BACKGROUNDS.size() - 1)
	var path: String = ACT_BACKGROUNDS[act]
	if not ResourceLoader.exists(path):
		return
	var bg_node := $UI/Background
	var tex_rect := TextureRect.new()
	tex_rect.name = "Background"
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.texture = load(path)
	bg_node.get_parent().add_child(tex_rect)
	bg_node.get_parent().move_child(tex_rect, bg_node.get_index())
	bg_node.queue_free()

func _find_nodes() -> void:
	turn_manager            = $TurnManager
	enemy_ai               = $EnemyAI
	essence_label          = $UI/EssenceLabel
	mana_label             = $UI/ManaLabel
	end_turn_essence_button = $UI/EndTurnPanel/EndTurnEssenceButton
	end_turn_mana_button   = $UI/EndTurnPanel/EndTurnManaButton
	# Single button shown when at soft cap
	end_turn_button = Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30, 1))
	end_turn_button.add_theme_font_size_override("font_size", 18)
	end_turn_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_turn_button.offset_top    = 38.0
	end_turn_button.offset_bottom = -16.0
	end_turn_button.offset_left   = 6.0
	end_turn_button.offset_right  = -6.0
	end_turn_button.visible = false
	$UI/EndTurnPanel.add_child(end_turn_button)
	fight_label       = $UI/FightLabel if has_node("UI/FightLabel") else null
	hand_display      = $UI/HandDisplay
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
	if end_turn_button:
		end_turn_button.pressed.connect(_do_end_turn)
	if hand_display:
		hand_display.card_selected.connect(_on_hand_card_selected)
		hand_display.card_hovered.connect(_show_large_preview)
		hand_display.card_unhovered.connect(_hide_large_preview)
		hand_display.card_deselected.connect(_on_hand_card_deselected)
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
	if end_turn_button:
		end_turn_button.disabled = not is_player_turn
	_refresh_end_turn_mode()
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
	_refresh_hand_spell_costs()
	# NOTE: end-turn button mode is NOT updated here — temp gains (gain_mana, gain_essence)
	# also fire this signal and must not flip the button layout.
	# Use _refresh_end_turn_mode() only when permanent max values change.

## Update end-turn panel layout based on permanent resource max values.
## Call only after grow_essence_max / grow_mana_max or at turn start.
func _refresh_end_turn_mode() -> void:
	var at_cap := (turn_manager.essence_max + turn_manager.mana_max) >= TurnManager.COMBINED_RESOURCE_CAP
	if end_turn_essence_button:
		end_turn_essence_button.visible = not at_cap
	if end_turn_mana_button:
		end_turn_mana_button.visible = not at_cap
	if has_node("UI/EndTurnPanel/ETSubLabel"):
		$UI/EndTurnPanel/ETSubLabel.visible = not at_cap
	if end_turn_button:
		end_turn_button.visible = at_cap

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
	pending_minion_target = null
	_awaiting_minion_target = false
	if hand_display:
		hand_display.deselect_current()
	turn_manager.end_player_turn()

# ---------------------------------------------------------------------------
# Hand card selection
# ---------------------------------------------------------------------------

func _on_hand_card_selected(card_data: CardData) -> void:
	# Guard: card plays are only valid on the player's turn
	if not turn_manager.is_player_turn:
		return

	selected_attacker = null
	_clear_all_highlights()
	pending_play_card = card_data

	if card_data is SpellCardData:
		var spell := card_data as SpellCardData
		if spell.requires_target:
			# Check affordability before showing target highlights (Void Crystal bypasses)
			var effective_cost := maxi(0, spell.cost - _spell_mana_discount())
			if not _relic_first_card_free and not turn_manager.can_afford(0, effective_cost):
				pending_play_card = null
				if hand_display:
					hand_display.deselect_current()
				return
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
		var mc := card_data as MinionCardData
		# Check affordability (Void Crystal relic bypasses cost for the first card)
		var extra_mana := 1 if (_card_has_tag(mc, "void_imp") and _has_talent("piercing_void")) else 0
		if not _relic_first_card_free and not turn_manager.can_afford(mc.essence_cost, mc.mana_cost + extra_mana):
			pending_play_card = null
			if hand_display:
				hand_display.deselect_current()
			return
		# Check board space before highlighting
		var has_empty_slot := player_slots.any(func(s: BoardSlot) -> bool: return s.is_empty())
		if not has_empty_slot:
			pending_play_card = null
			if hand_display:
				hand_display.deselect_current()
			return
		if mc.on_play_requires_target and _has_valid_minion_on_play_targets(mc):
			_awaiting_minion_target = true
			_highlight_minion_on_play_targets(mc)
		else:
			# No valid targets (or card doesn't need one) — go straight to placement.
			# Effect will fire but resolve with null target (logs "no targets" and skips).
			_awaiting_minion_target = false
			_highlight_empty_player_slots()

func _on_hand_card_deselected() -> void:
	pending_play_card = null
	pending_minion_target = null
	_awaiting_minion_target = false
	_tear_down_trap_env_targeting()
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
	turn_manager.remove_from_hand(spell)
	if hand_display:
		hand_display.remove_card(spell)
		hand_display.deselect_current()
	pending_play_card = null
	# Show large card preview; resolve effects on impact so damage visuals sync
	_show_spell_cast_anim(spell, false, func() -> void:
		if not spell.effect_steps.is_empty():
			EffectResolver.run(spell.effect_steps, EffectContext.make(self, "player"))
		else:
			_resolve_spell_effect(spell.effect_id, null)
		var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
		spell_ctx.card = spell
		trigger_manager.fire(spell_ctx)
	)

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
	# Run on-enter burst steps if defined
	if not env.on_enter_effect_steps.is_empty():
		var enter_ctx := EffectContext.make(self, "player")
		EffectResolver.run(env.on_enter_effect_steps, enter_ctx)
	# Apply passive immediately on the turn it is played
	if not env.passive_effect_steps.is_empty():
		var pass_ctx := EffectContext.make(self, "player")
		EffectResolver.run(env.passive_effect_steps, pass_ctx)
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
			environment_slot_name.visible = true
			environment_slot_name.text = active_environment.card_name
		if environment_slot_desc:
			environment_slot_desc.text = active_environment.passive_description
		environment_slot.tooltip_text = _build_environment_tooltip(active_environment)
	else:
		_apply_empty_slot(environment_slot, environment_slot_name)
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
		Enums.RuneType.SOUL_RUNE:     return "Soul Rune"
		Enums.RuneType.SHADOW_RUNE:   return "Shadow Rune"
	return "Unknown Rune"

# ---------------------------------------------------------------------------
# Player input — board slot clicks
# ---------------------------------------------------------------------------

func _on_player_slot_clicked_empty(slot: BoardSlot) -> void:
	# If a minion card is pending to be played, place it here.
	# For targeted cards, pending_minion_target holds the player's chosen target
	# (set when they clicked a valid target slot before choosing placement).
	if pending_play_card and pending_play_card is MinionCardData:
		# Still waiting for player to click a valid target — ignore slot clicks until then
		if _awaiting_minion_target:
			return
		_try_play_minion(pending_play_card as MinionCardData, slot, pending_minion_target)
		pending_minion_target = null
		pending_play_card = null
		_awaiting_minion_target = false
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
	# If a targeted minion card is waiting for a friendly target, store it and show placement slots.
	# If the minion card is pending but NOT awaiting a target (board was shown), block attacker
	# selection so clicking an occupied slot doesn't accidentally select an attacker.
	if pending_play_card is MinionCardData:
		var mc := pending_play_card as MinionCardData
		if _awaiting_minion_target and _is_valid_minion_on_play_target(minion, mc.on_play_target_type):
			pending_minion_target = minion
			_awaiting_minion_target = false
			_highlight_empty_player_slots()
		return  # swallow the click — don't fall through to attacker selection
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
	# If a targeted minion card is waiting for an enemy target, store it and show placement slots
	if pending_play_card is MinionCardData:
		var mc := pending_play_card as MinionCardData
		if _awaiting_minion_target and _is_valid_minion_on_play_target(minion, mc.on_play_target_type):
			pending_minion_target = minion
			_awaiting_minion_target = false
			_highlight_empty_player_slots()
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
	_anim_pre_hp   = minion.current_health
	_anim_atk_slot = _find_slot_for(selected_attacker)
	_anim_def_slot = _find_slot_for(minion)
	if _anim_atk_slot: _anim_atk_slot.freeze_visuals = true
	if _anim_def_slot: _anim_def_slot.freeze_visuals = true
	combat_manager.resolve_minion_attack(selected_attacker, minion)
	selected_attacker = null
	_clear_all_highlights()

# ---------------------------------------------------------------------------
# Minion play
# ---------------------------------------------------------------------------

func _try_play_minion(card: MinionCardData, slot: BoardSlot, on_play_target: MinionInstance = null) -> void:
	if not slot.is_empty():
		return
	# Talent: piercing_void — Void Imps cost +1 Mana
	var extra_mana := 1 if (_card_has_tag(card, "void_imp") and _has_talent("piercing_void")) else 0
	if not _pay_card_cost(card.essence_cost, card.mana_cost + extra_mana):
		return
	_log("You play: %s" % card.card_name)
	var instance := MinionInstance.create(card, "player")
	# Place visually first so the slot is not mistakenly taken by tokens summoned during on-play.
	# Do NOT append to player_board yet — on-play effects should not see this minion on the board.
	slot.place_minion(instance)
	# Fire ON_PLAYER_MINION_PLAYED — carries the player-chosen target for targeted battle cries.
	# The minion is not in player_board during this event, so ALL_FRIENDLY effects exclude it naturally.
	var play_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, "player")
	play_ctx.minion = instance
	play_ctx.card   = card
	play_ctx.target = on_play_target
	turn_manager.remove_from_hand(card)
	if hand_display:
		hand_display.remove_card(card)
		hand_display.deselect_current()
	trigger_manager.fire(play_ctx)
	# Now officially join the board before ON_PLAYER_MINION_SUMMONED (summon triggers expect it present).
	player_board.append(instance)
	var summon_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
	summon_ctx.minion = instance
	summon_ctx.card   = card
	trigger_manager.fire(summon_ctx)
	_refresh_hand_spell_costs()


## Fire the On Death effect of a minion that just died.
func _resolve_on_death_effect(minion: MinionInstance) -> void:
	match minion.card_data.on_death_effect:
		_:
			pass


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

## Generic token summon used by EffectResolver. Summons card_id into the first empty slot for owner.
## token_atk / token_hp / token_shield override the template defaults when non-zero.
func _summon_token(card_id: String, owner: String, token_atk: int = 0, token_hp: int = 0, token_shield: int = 0) -> void:
	var data := CardDatabase.get_card(card_id) as MinionCardData
	if data == null:
		return
	var slots  := player_slots if owner == "player" else enemy_slots
	var board  := player_board if owner == "player" else enemy_board
	for slot in slots:
		if slot.is_empty():
			var instance := MinionInstance.create(data, owner)
			if token_atk    > 0: instance.current_atk    = token_atk
			if token_hp     > 0: instance.current_health = token_hp
			if token_shield > 0:
				instance.current_shield = token_shield
				BuffSystem.apply(instance, Enums.BuffType.SHIELD_BONUS, token_shield, "token")
			board.append(instance)
			slot.place_minion(instance)
			_log("  %s summoned!" % data.card_name, _LogType.PLAYER)
			var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
			var ctx   := EventContext.make(event, owner)
			ctx.minion = instance
			ctx.card   = data
			trigger_manager.fire(ctx)
			return

## Count minions of a given type on the specified owner's board.
func _count_type_on_board(type: Enums.MinionType, owner: String) -> int:
	return _friendly_board(owner).filter(func(m: MinionInstance): return m.card_data.minion_type == type).size()

## Return true if there is at least one empty player slot.
func _has_empty_player_slot() -> bool:
	for slot in player_slots:
		if slot.is_empty():
			return true
	return false

# ---------------------------------------------------------------------------
# Test Mode (Option C) — applied after normal combat startup
# ---------------------------------------------------------------------------

func _apply_test_config() -> void:
	# Override HP values
	if TestConfig.player_hp > 0:
		player_hp = TestConfig.player_hp

	if TestConfig.enemy_hp > 0:
		enemy_hp     = TestConfig.enemy_hp
		enemy_hp_max = TestConfig.enemy_hp
	# Add cards directly to hand
	for id in TestConfig.hand_cards:
		var card := CardDatabase.get_card(id)
		if card:
			turn_manager.add_to_hand(card)

	# Pre-summon player board minions
	for id in TestConfig.player_board_cards:
		_summon_token(id, "player")

	# Pre-summon enemy board minions
	for id in TestConfig.enemy_board_cards:
		_summon_token(id, "enemy")

	# Override starting resources
	if TestConfig.start_essence_max > 0:
		turn_manager.essence_max = TestConfig.start_essence_max
		turn_manager.essence     = TestConfig.start_essence_max
	if TestConfig.start_mana_max > 0:
		turn_manager.mana_max = TestConfig.start_mana_max
		turn_manager.mana     = TestConfig.start_mana_max
	if TestConfig.start_essence_max > 0 or TestConfig.start_mana_max > 0:
		turn_manager.resources_changed.emit(
			turn_manager.essence, turn_manager.essence_max,
			turn_manager.mana,    turn_manager.mana_max)
		_refresh_end_turn_mode()

	_log("[TEST] Test config applied.", _LogType.TURN)
	TestConfig.enabled = false  # consumed — reset so normal navigation isn't affected

# ---------------------------------------------------------------------------
# Cheat Panel (Option B) — F12 toggle, always present during combat
# ---------------------------------------------------------------------------

var _cheat_panel: CanvasLayer
var _cheat_visible: bool = false
var _cheat_card_input: LineEdit
var _cheat_dmg_input:  SpinBox
var _cheat_status_lbl: Label

func _setup_cheat_panel() -> void:
	_cheat_panel = CanvasLayer.new()
	_cheat_panel.layer = 128
	add_child(_cheat_panel)

	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(320, 0)
	root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	root.offset_left  = -330
	root.offset_top   = 10
	root.offset_right = -10
	_cheat_panel.add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "⚙ Cheat Panel  [F12]"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Add card to hand
	var hand_label := Label.new()
	hand_label.text = "Add card to hand (ID):"
	hand_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hand_label)

	var hand_row := HBoxContainer.new()
	vbox.add_child(hand_row)
	_cheat_card_input = LineEdit.new()
	_cheat_card_input.placeholder_text = "e.g. arcane_strike"
	_cheat_card_input.custom_minimum_size = Vector2(200, 0)
	_cheat_card_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cheat_card_input.text_submitted.connect(func(_t): _cheat_add_card())
	hand_row.add_child(_cheat_card_input)
	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(_cheat_add_card)
	hand_row.add_child(add_btn)

	vbox.add_child(HSeparator.new())

	# Damage / heal heroes
	var dmg_label := Label.new()
	dmg_label.text = "Damage / Heal heroes:"
	dmg_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(dmg_label)

	var dmg_row := HBoxContainer.new()
	vbox.add_child(dmg_row)
	_cheat_dmg_input = SpinBox.new()
	_cheat_dmg_input.min_value = 0
	_cheat_dmg_input.max_value = 99999
	_cheat_dmg_input.value     = 500
	_cheat_dmg_input.step      = 100
	_cheat_dmg_input.custom_minimum_size = Vector2(110, 0)
	dmg_row.add_child(_cheat_dmg_input)

	var dmg_player := Button.new()
	dmg_player.text = "Dmg Player"
	dmg_player.pressed.connect(func(): _on_hero_damaged("player", int(_cheat_dmg_input.value)))
	dmg_row.add_child(dmg_player)

	var dmg_enemy := Button.new()
	dmg_enemy.text = "Dmg Enemy"
	dmg_enemy.pressed.connect(func(): _on_hero_damaged("enemy", int(_cheat_dmg_input.value)))
	dmg_row.add_child(dmg_enemy)

	var heal_row := HBoxContainer.new()
	vbox.add_child(heal_row)
	var heal_player := Button.new()
	heal_player.text = "Heal Player"
	heal_player.pressed.connect(func(): _on_hero_healed("player", int(_cheat_dmg_input.value)))
	heal_row.add_child(heal_player)

	var heal_enemy := Button.new()
	heal_enemy.text = "Heal Enemy"
	heal_enemy.pressed.connect(func(): _on_hero_healed("enemy", int(_cheat_dmg_input.value)))
	heal_row.add_child(heal_enemy)

	vbox.add_child(HSeparator.new())

	# Summon token
	var summon_label := Label.new()
	summon_label.text = "Summon minion (ID):"
	summon_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(summon_label)

	var summon_row := HBoxContainer.new()
	vbox.add_child(summon_row)
	var summon_input := LineEdit.new()
	summon_input.placeholder_text = "e.g. shadow_hound"
	summon_input.custom_minimum_size = Vector2(160, 0)
	summon_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summon_row.add_child(summon_input)
	var summon_player_btn := Button.new()
	summon_player_btn.text = "Mine"
	summon_player_btn.pressed.connect(func(): _summon_token(summon_input.text.strip_edges(), "player"))
	summon_row.add_child(summon_player_btn)
	var summon_enemy_btn := Button.new()
	summon_enemy_btn.text = "Enemy"
	summon_enemy_btn.pressed.connect(func(): _summon_token(summon_input.text.strip_edges(), "enemy"))
	summon_row.add_child(summon_enemy_btn)

	vbox.add_child(HSeparator.new())

	# Resources
	var res_btn := Button.new()
	res_btn.text = "Refill Resources (Essence + Mana)"
	res_btn.pressed.connect(func():
		turn_manager.gain_essence(turn_manager.essence_max)
		turn_manager.gain_mana(turn_manager.mana_max))
	vbox.add_child(res_btn)

	# Status feedback
	_cheat_status_lbl = Label.new()
	_cheat_status_lbl.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	_cheat_status_lbl.add_theme_font_size_override("font_size", 11)
	_cheat_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_cheat_status_lbl)

	# Hidden by default
	_cheat_panel.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_cheat_visible = not _cheat_visible
			_cheat_panel.visible = _cheat_visible

func _cheat_add_card() -> void:
	var id := _cheat_card_input.text.strip_edges()
	if id == "":
		return
	var card := CardDatabase.get_card(id)
	if card == null:
		_cheat_status_lbl.text = "Unknown card: " + id
		return
	turn_manager.add_to_hand(card)
	_cheat_status_lbl.text = ""
	_cheat_card_input.text = ""

## Entry point for EffectResolver HARDCODED steps.
func _resolve_hardcoded(id: String, ctx: EffectContext) -> void:
	match id:
		"void_devourer_sacrifice":
			_resolve_void_devourer_sacrifice(ctx.source, ctx.owner)
		"destroy_random_enemy_trap":
			if ctx.owner == "player":
				_log("  Trapbreaker: no enemy traps to destroy.", _LogType.PLAYER)
		"spell_taxer_effect":
			if ctx.owner == "player":
				_spell_tax_for_enemy_turn += 1
				_log("  Spell Taxer: enemy spells cost +1 next turn.", _LogType.PLAYER)
		"saboteur_adept_effect":
			if ctx.owner == "player":
				_log("  Saboteur Adept: enemy traps blocked this turn (not yet active).", _LogType.PLAYER)
		# --- Environment passives ---
		"dark_covenant_passive":
			# Re-apply ATK aura to Demons (clear first to prevent stacking), heal Humans if Demon present.
			for m in player_board:
				BuffSystem.remove_source(m, "dark_covenant")
			var has_human := player_board.any(func(m: MinionInstance) -> bool: return m.card_data.minion_type == Enums.MinionType.HUMAN)
			var has_demon := player_board.any(func(m: MinionInstance) -> bool: return m.card_data.minion_type == Enums.MinionType.DEMON)
			if has_human:
				for m in player_board:
					if m.card_data.minion_type == Enums.MinionType.DEMON:
						BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "dark_covenant")
						_refresh_slot_for(m)
			if has_demon:
				for m in player_board:
					if m.card_data.minion_type == Enums.MinionType.HUMAN:
						m.current_health = mini(m.current_health + 100, m.card_data.health)
						_refresh_slot_for(m)
		"dark_covenant_remove":
			for m in player_board:
				BuffSystem.remove_source(m, "dark_covenant")
				_refresh_slot_for(m)
		"abyss_ritual_circle_passive":
			var all_minions: Array[MinionInstance] = []
			all_minions.assign(player_board + enemy_board)
			if not all_minions.is_empty():
				var hit := all_minions[randi() % all_minions.size()]
				_log("  Abyss Ritual Circle: 100 damage to %s." % hit.card_data.card_name, _LogType.PLAYER)
				_spell_dmg(hit, 100)
		# --- Ritual effects ---
		"demon_ascendant":
			_log("  Demon Ascendant: deal 200 damage to 2 random enemy minions.", _LogType.PLAYER)
			for _i in 2:
				var target_m := _find_random_enemy_minion()
				if target_m:
					_spell_dmg(target_m, 200)
			_log("  Demon Ascendant: Special Summon a 500/500 Void Demon!", _LogType.PLAYER)
			for slot in player_slots:
				if slot.is_empty():
					var demon_data := CardDatabase.get_card("void_demon") as MinionCardData
					if demon_data:
						var instance := MinionInstance.create(demon_data, "player")
						instance.current_atk    = 500
						instance.current_health = 500
						player_board.append(instance)
						slot.place_minion(instance)
						# Special Summon: do NOT fire ON_PLAYER_MINION_SUMMONED (no on-play effects)
					break
		# --- Trap effects ---
		"smoke_veil":
			enemy_ai.attack_cancelled = true
			for m in enemy_board:
				m.state = Enums.MinionState.EXHAUSTED
				_refresh_slot_for(m)
			_log("  Smoke Veil: attack cancelled! All enemies exhausted.", _LogType.TRAP)
		"silence_trap":
			_spell_cancelled = true
			_log("  Silence Trap: enemy spell cancelled!", _LogType.TRAP)
		# --- Dominion Rune ---
		"dominion_rune_place":
			_refresh_dominion_aura(true, 100 * _rune_aura_multiplier())
		"dominion_rune_remove":
			_refresh_dominion_aura(false)
		# --- Soul Rune ---
		"soul_rune_death":
			if _soul_rune_fired:
				return
			if turn_manager.is_player_turn:
				return
			if ctx.trigger_minion == null or ctx.trigger_minion.card_data.minion_type != Enums.MinionType.DEMON:
				return
			_soul_rune_fired = true
			var mult := _rune_aura_multiplier()
			_summon_soul_rune_spirit(100 * mult, 100 * mult)
			_log("  Soul Rune: Demon died — %d/%d Spirit summoned." % [100 * mult, 100 * mult], _LogType.TRAP)
		"soul_rune_reset":
			_soul_rune_fired = false
		# --- vael_endless_tide: Vael's Colossal Guard on-play ---
		"colossal_guard_play":
			pass  # Handled declaratively by on_play_effect_steps; stub for forward compat
		# --- vael_rune_master: Runic Blast ---
		"runic_blast":
			var rune_count := 0
			for t in active_traps:
				if (t as TrapCardData).is_rune:
					rune_count += 1
			if rune_count >= 2:
				_log("  Runic Blast: 2+ Runes active — 200 damage to ALL enemy minions!", _LogType.PLAYER)
				for m in enemy_board.duplicate():
					_spell_dmg(m, 200)
			else:
				var target_m := _find_random_enemy_minion()
				if target_m:
					_log("  Runic Blast: 200 damage to %s." % target_m.card_data.card_name, _LogType.PLAYER)
					_spell_dmg(target_m, 200)
				else:
					_log("  Runic Blast: no enemy minions.", _LogType.PLAYER)
		# --- vael_rune_master: Runic Echo ---
		"runic_echo":
			var last_rune := _find_last_non_echo_rune()
			if last_rune and not last_rune.aura_effect_steps.is_empty():
				_log("  Runic Echo: copies %s's effect." % last_rune.card_name, _LogType.PLAYER)
				var eff_ctx := EffectContext.make(self, ctx.owner)
				EffectResolver.run(last_rune.aura_effect_steps, eff_ctx)
			else:
				_log("  Runic Echo: no previous Rune effect to copy.", _LogType.PLAYER)
		# --- vael_rune_master: Echo Rune aura fire (ON_PLAYER_TURN_START) ---
		"echo_rune_fire":
			var last_rune := _find_last_non_echo_rune()
			if last_rune and not last_rune.aura_effect_steps.is_empty():
				_log("  Echo Rune: fires %s's effect." % last_rune.card_name, _LogType.TRAP)
				var eff_ctx := EffectContext.make(self, "player")
				EffectResolver.run(last_rune.aura_effect_steps, eff_ctx)
		# --- vael_rune_master: Rune Seeker on-play ---
		"rune_seeker_play":
			var found := false
			for i in turn_manager.player_deck.size():
				var c := turn_manager.player_deck[i]
				if c is TrapCardData and (c as TrapCardData).is_rune:
					turn_manager.player_deck.remove_at(i)
					turn_manager.add_to_hand(c)
					if hand_display:
						hand_display.add_card(c)
					_log("  Rune Seeker: found %s." % c.card_name, _LogType.PLAYER)
					found = true
					break
			if not found:
				_log("  Rune Seeker: no Rune in deck.", _LogType.PLAYER)
		# --- Feral Imp Clan (Act 1 enemy cards) ---
		"frenzied_imp_play":
			var board := _friendly_board(ctx.owner)
			var feral_count := 0
			for m in board:
				if m != ctx.source and _minion_has_tag(m, "feral_imp"):
					feral_count += 1
			var dmg := 100 + 100 * feral_count
			var frenzied_target := _find_random_minion(_opponent_board(ctx.owner))
			if frenzied_target:
				_log("  Frenzied Imp: %d damage to %s." % [dmg, frenzied_target.card_data.card_name], _LogType.ENEMY)
				_spell_dmg(frenzied_target, dmg)
			else:
				_log("  Frenzied Imp: no target.", _LogType.ENEMY)
		"void_screech":
			var owner_board := _friendly_board(ctx.owner)
			var feral_on_board := 0
			for m in owner_board:
				if _minion_has_tag(m, "feral_imp"):
					feral_on_board += 1
			var screech_dmg := 350 if feral_on_board >= 3 else 250
			_on_hero_damaged(_opponent_of(ctx.owner), screech_dmg)
			_log("  Void Screech: %d damage to hero (%d feral imps)." % [screech_dmg, feral_on_board], _LogType.ENEMY)
		"brood_call":
			var feral_ids: Array[String] = ["rabid_imp", "brood_imp", "imp_brawler", "void_touched_imp", "frenzied_imp", "matriarchs_broodling", "rogue_imp_elder"]
			var pick := feral_ids[randi() % feral_ids.size()]
			_summon_token(pick, ctx.owner)
			_log("  Brood Call: summoned %s." % pick, _LogType.ENEMY)
		"pack_frenzy":
			var feral_board := _friendly_board(ctx.owner).duplicate()
			for m in feral_board:
				if _minion_has_tag(m, "feral_imp"):
					BuffSystem.apply(m, Enums.BuffType.TEMP_ATK, 250, "pack_frenzy")
					if m.state == Enums.MinionState.EXHAUSTED:
						m.state = Enums.MinionState.SWIFT
					_refresh_slot_for(m)
			_log("  Pack Frenzy: all Feral Imps +250 ATK and SWIFT.", _LogType.ENEMY)
		"rogue_imp_elder_remove":
			var elder_board := _friendly_board(ctx.owner)
			for m in elder_board:
				BuffSystem.remove_source(m, "rogue_imp_elder")
				_refresh_slot_for(m)
		_:
			_resolve_spell_effect(id, ctx.chosen_target, ctx.owner)

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

## Return the most recently placed non-Echo Rune from active_traps (or null).
## Used by Runic Echo and Echo Rune to copy the last placed Rune's effect.
func _find_last_non_echo_rune() -> TrapCardData:
	for i in range(active_traps.size() - 1, -1, -1):
		var t := active_traps[i] as TrapCardData
		if t.is_rune and t.id != "echo_rune":
			return t
	return null

## Summon a Void Spark Spirit token with the given ATK/HP into the first empty player slot.
## Used by Soul Rune aura (stats scale with rune stacks).
func _summon_soul_rune_spirit(atk: int, hp: int) -> void:
	_summon_token("void_spark", "player", atk, hp)

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

## Refresh hand card cost display and large preview to reflect the current board discount.
func _refresh_hand_spell_costs() -> void:
	var discount := _spell_mana_discount()
	if hand_display:
		hand_display.refresh_spell_costs(discount)
	if _large_preview and _large_preview.visible:
		_large_preview.apply_cost_discount(discount)

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
	var damage: int = max(0, _anim_pre_hp - defender.current_health)
	_anim_pre_hp = 0
	var a := _anim_atk_slot
	var d := _anim_def_slot
	_anim_atk_slot = null
	_anim_def_slot = null
	if a and d:
		# Refresh happens inside _play_attack_anim after the lunge completes
		_play_attack_anim(a, d, damage, attacker, defender)
	else:
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
	_refresh_hand_spell_costs()

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
		_update_player_status_panel()
		_log("  You take %d damage  (HP: %d)" % [amount, player_hp], _LogType.DAMAGE)
		if player_hp <= 0:
			_flash_hero("player", amount, _on_defeat)
		else:
			_flash_hero("player", amount)
			var _ctx := EventContext.make(Enums.TriggerEvent.ON_HERO_DAMAGED, "player")
			_ctx.damage = amount
			trigger_manager.fire(_ctx)
	else:
		enemy_hp -= amount
		_log("  Enemy takes %d damage  (HP: %d)" % [amount, enemy_hp], _LogType.DAMAGE)
		_update_enemy_status_panel()
		if enemy_hp <= 0:
			_flash_hero("enemy", amount, _on_victory)
		else:
			_flash_hero("enemy", amount)

func _on_hero_healed(target: String, amount: int) -> void:
	if target == "player":
		player_hp = mini(player_hp + amount, GameManager.player_hp_max)
		_update_player_status_panel()
		_log("  You heal %d HP  (HP: %d)" % [amount, player_hp], _LogType.HEAL)
		# Eternal Hunger — deal the healed amount to the enemy hero too
		if "eternal_hunger" in GameManager.player_relics:
			_log("  Eternal Hunger: deal %d damage to enemy hero." % amount, _LogType.PLAYER)
			_on_hero_damaged("enemy", amount)

# ---------------------------------------------------------------------------
# Targeted spell helpers
# ---------------------------------------------------------------------------

## Returns true if at least one valid target exists for this card's on-play target type.
## If false, the card skips targeting and goes straight to placement (effect fires but does nothing).
func _has_valid_minion_on_play_targets(card: MinionCardData) -> bool:
	var hits_enemy    := card.on_play_target_type in ["enemy_minion", "corrupted_enemy_minion"]
	var hits_friendly := card.on_play_target_type in ["friendly_minion"]
	if hits_enemy:
		for slot in enemy_slots:
			if not slot.is_empty() and _is_valid_minion_on_play_target(slot.minion, card.on_play_target_type):
				return true
	if hits_friendly:
		for slot in player_slots:
			if not slot.is_empty() and _is_valid_minion_on_play_target(slot.minion, card.on_play_target_type):
				return true
	return false

## Highlight valid target slots for a targeted minion on-play effect (battle cry).
## Step 1 of the two-click flow: player clicks card → sees valid targets highlighted.
## Step 2: player clicks a valid target → pending_minion_target set → placement slots shown.
func _highlight_minion_on_play_targets(card: MinionCardData) -> void:
	_clear_all_highlights()
	var hits_enemy    := card.on_play_target_type in ["enemy_minion", "corrupted_enemy_minion"]
	var hits_friendly := card.on_play_target_type in ["friendly_minion"]
	if hits_enemy:
		for slot in enemy_slots:
			if not slot.is_empty() and _is_valid_minion_on_play_target(slot.minion, card.on_play_target_type):
				slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET)
	if hits_friendly:
		for slot in player_slots:
			if not slot.is_empty() and _is_valid_minion_on_play_target(slot.minion, card.on_play_target_type):
				slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET)

func _is_valid_minion_on_play_target(minion: MinionInstance, target_type: String) -> bool:
	match target_type:
		"enemy_minion":           return true
		"corrupted_enemy_minion": return BuffSystem.has_type(minion, Enums.BuffType.CORRUPTION)
		"friendly_minion":        return true
	return false

## Highlight player slots that have a minion matching the spell's target_type
func _highlight_spell_targets(spell: SpellCardData) -> void:
	_clear_all_highlights()
	if spell.target_type == "trap_or_env":
		_setup_trap_env_targeting()
		return
	var hits_friendly := spell.target_type in ["friendly_minion", "friendly_human", "friendly_demon", "friendly_void_imp", "any_minion"]
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
		"friendly_human":    return minion.card_data.minion_type == Enums.MinionType.HUMAN
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
	if not spell.effect_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		ctx.chosen_target = target
		EffectResolver.run(spell.effect_steps, ctx)
	else:
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
	# Called only from _resolve_hardcoded() fallback for effects that cannot be declarative.
	match effect_id:
		"void_detonation_effect":
			if owner == "player":
				var bonus_per_mark := 50
				var total_base := 150 + enemy_void_marks * bonus_per_mark
				_log("  Void Detonation: %d Void Bolt dmg (150 + %d×%d marks)." % [total_base, bonus_per_mark, enemy_void_marks], _LogType.PLAYER)
				_deal_void_bolt_damage(total_base)

# ---------------------------------------------------------------------------
# Cyclone / trap-or-env targeting
# ---------------------------------------------------------------------------

## Stored gui_input connections so they can be disconnected cleanly.
var _active_trap_env_connections: Array = []  # Array[{node: Control, cb: Callable}]

func _setup_trap_env_targeting() -> void:
	_tear_down_trap_env_targeting()
	for i in trap_slot_panels.size():
		if i < active_traps.size():
			var cb := func(ev: InputEvent) -> void: _on_trap_env_input(ev, i, null)
			trap_slot_panels[i].gui_input.connect(cb)
			_active_trap_env_connections.append({node = trap_slot_panels[i], cb = cb})
			trap_slot_panels[i].modulate = Color(1.3, 1.3, 0.5)
	if environment_slot and active_environment:
		var env := active_environment
		var cb := func(ev: InputEvent) -> void: _on_trap_env_input(ev, -1, env)
		environment_slot.gui_input.connect(cb)
		_active_trap_env_connections.append({node = environment_slot, cb = cb})
		environment_slot.modulate = Color(1.3, 1.3, 0.5)

func _tear_down_trap_env_targeting() -> void:
	for c in _active_trap_env_connections:
		if is_instance_valid(c.node):
			if c.node.gui_input.is_connected(c.cb):
				c.node.gui_input.disconnect(c.cb)
			c.node.modulate = Color.WHITE
	_active_trap_env_connections.clear()

func _on_trap_env_input(event: InputEvent, trap_idx: int, env_data) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var spell := pending_play_card as SpellCardData
	if spell == null:
		return
	var effective_cost := maxi(0, spell.cost - _spell_mana_discount())
	if not _pay_card_cost(0, effective_cost):
		if hand_display:
			hand_display.deselect_current()
		return
	if trap_idx >= 0 and trap_idx < active_traps.size():
		var trap := active_traps[trap_idx]
		_log("You cast: %s → %s" % [spell.card_name, trap.card_name])
		if trap.is_rune:
			_remove_rune_aura(trap)
		active_traps.erase(trap)
		_update_trap_display()
		_log("  Cyclone: %s removed." % trap.card_name, _LogType.PLAYER)
	elif env_data != null and active_environment == env_data:
		_log("You cast: %s → %s" % [spell.card_name, active_environment.card_name])
		_log("  Cyclone: %s dispelled." % active_environment.card_name, _LogType.PLAYER)
		_unregister_env_rituals()
		active_environment = null
		_update_environment_display()
	var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
	spell_ctx.card = spell
	trigger_manager.fire(spell_ctx)
	turn_manager.remove_from_hand(spell)
	pending_play_card = null
	_tear_down_trap_env_targeting()
	if hand_display:
		hand_display.deselect_current()

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
		var ctx := EffectContext.make(self, "player")
		ctx.trigger_minion = triggering_minion
		EffectResolver.run(trap.effect_steps, ctx)
		if not trap.reusable:
			active_traps.erase(trap)
			_update_trap_display()

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
	# ON_PLAY effects are resolved by _handler_enemy_minion_on_play registered in _setup_triggers().
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "enemy")
	ctx.minion = minion
	trigger_manager.fire(ctx)

## Called by EnemyAI's enemy_spell_cast signal.
func _on_enemy_spell_cast(spell: SpellCardData) -> void:
	_log("Enemy casts: %s" % spell.card_name, _LogType.ENEMY)
	# Fire ON_ENEMY_SPELL_CAST BEFORE resolving so Null Seal can set _spell_cancelled.
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "enemy")
	ctx.card = spell
	trigger_manager.fire(ctx)
	var was_cancelled := _spell_cancelled
	_spell_cancelled = false
	if was_cancelled:
		return
	# Show large card preview; resolve effects on impact so damage visuals sync
	_show_spell_cast_anim(spell, true, func() -> void:
		if not spell.effect_steps.is_empty():
			EffectResolver.run(spell.effect_steps, EffectContext.make(self, "enemy"))
		elif not spell.effect_id.is_empty():
			_resolve_spell_effect(spell.effect_id, null, "enemy")
	)

func _update_trap_display() -> void:
	for i in trap_slot_panels.size():
		var panel := trap_slot_panels[i]
		var lbl   := trap_slot_labels[i]
		if i < active_traps.size():
			var trap := active_traps[i]
			lbl.visible = true
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
			_apply_empty_slot(panel, lbl)
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

## Run teardown steps for the outgoing environment (e.g. remove persistent buffs).
## Called when the environment is replaced mid-turn so buffs don't linger.
func _unregister_env_aura(env: EnvironmentCardData) -> void:
	if not env.on_replace_effect_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		EffectResolver.run(env.on_replace_effect_steps, ctx)

## Register persistent aura event handlers for a newly placed rune.
## _rune_aura_handlers stores Array[{event, handler}] per rune so _remove_rune_aura
## can unregister them without a match block.
## Each rune declares its trigger(s) and effect_steps in CardDatabase — no match needed here.
func _apply_rune_aura(rune: TrapCardData) -> void:
	var entries: Array = []

	# Primary handler
	if rune.aura_trigger >= 0 and not rune.aura_effect_steps.is_empty():
		var h := func(event_ctx: EventContext):
			var ctx := EffectContext.make(self, "player")
			ctx.trigger_minion = event_ctx.minion
			EffectResolver.run(rune.aura_effect_steps, ctx)
		trigger_manager.register(rune.aura_trigger, h, 20)
		entries.append({event = rune.aura_trigger, handler = h})

	# Secondary handler (e.g. Soul Rune per-turn reset)
	if rune.aura_secondary_trigger >= 0 and not rune.aura_secondary_steps.is_empty():
		var h2 := func(event_ctx: EventContext):
			var ctx := EffectContext.make(self, "player")
			ctx.trigger_minion = event_ctx.minion
			EffectResolver.run(rune.aura_secondary_steps, ctx)
		trigger_manager.register(rune.aura_secondary_trigger, h2, 20)
		entries.append({event = rune.aura_secondary_trigger, handler = h2})

	# On-place steps run immediately at placement (e.g. Dominion Rune existing-minion sweep)
	if not rune.aura_on_place_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		EffectResolver.run(rune.aura_on_place_steps, ctx)

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
	if not rune.aura_on_remove_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		EffectResolver.run(rune.aura_on_remove_steps, ctx)

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
	var ritual_ctx := EffectContext.make(self, "player")
	EffectResolver.run(ritual.effect_steps, ritual_ctx)
	# Talent: ritual_surge — summon 2 Void Imps after any ritual fires
	if _has_talent("ritual_surge"):
		_summon_void_imp()
		_summon_void_imp()
		_log("  Ritual Surge: 2 Void Imps summoned!", _LogType.PLAYER)


func _update_enemy_trap_display() -> void:
	for i in enemy_trap_slot_panels.size():
		var panel := enemy_trap_slot_panels[i]
		var lbl   := enemy_trap_slot_labels[i]
		_apply_empty_slot(panel, lbl)

func _apply_slot_style(panel: Panel, bg: Color, border: Color) -> void:
	# Hide empty-slot image if the slot is now occupied/styled
	var img := panel.get_node_or_null("_empty_slot_bg") as TextureRect
	if img:
		img.visible = false
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

const _ABYSS_EMPTY_SLOT_PATH := "res://assets/art/frames/abyss_order/abyss_empty_slot.png"
const _ABYSS_HEROES_LIST     := ["lord_vael"]

## Apply the abyss empty-slot image (or fallback dark style) to a plain Panel.
## Pass lbl=null if the panel has no text label to manage.
func _apply_empty_slot(panel: Panel, lbl: Label) -> void:
	var is_abyss: bool = GameManager.current_hero in _ABYSS_HEROES_LIST
	var img := panel.get_node_or_null("_empty_slot_bg") as TextureRect
	if is_abyss and ResourceLoader.exists(_ABYSS_EMPTY_SLOT_PATH):
		# Transparent panel so the image shows through
		var blank := StyleBoxFlat.new()
		blank.bg_color = Color(0, 0, 0, 0)
		panel.add_theme_stylebox_override("panel", blank)
		# Create image node on first use
		if img == null:
			img = TextureRect.new()
			img.name = "_empty_slot_bg"
			img.stretch_mode = TextureRect.STRETCH_SCALE
			img.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
			img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(img)
		img.texture = load(_ABYSS_EMPTY_SLOT_PATH)
		img.visible = true
		if lbl:
			lbl.visible = false
	else:
		if img:
			img.visible = false
		_apply_slot_style(panel, Color(0.08, 0.08, 0.14, 1), Color(0.22, 0.22, 0.38, 1))
		if lbl:
			lbl.text    = "[ — ]"
			lbl.visible = true

# ---------------------------------------------------------------------------
# Hero attack helpers
# ---------------------------------------------------------------------------

var _enemy_hero_attackable: bool = false

func _show_hero_button(attackable: bool) -> void:
	_enemy_hero_attackable = attackable
	if not _enemy_status_panel:
		return
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	if attackable:
		style.bg_color     = Color(0.18, 0.10, 0.10, 0.95)
		style.border_color = Color(1.0, 0.80, 0.15, 1.0)
		style.set_border_width_all(3)
		_enemy_status_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		style.bg_color     = Color(0.08, 0.04, 0.13, 0.93)
		style.border_color = Color(0.55, 0.20, 0.80, 1.0)
		style.set_border_width_all(2)
		_enemy_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_status_panel.add_theme_stylebox_override("panel", style)
	if _enemy_hero_attack_hint:
		_enemy_hero_attack_hint.visible = attackable

func _on_enemy_hero_frame_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _enemy_hero_attackable:
			_on_enemy_hero_button_pressed()

# ---------------------------------------------------------------------------
# Hero passives panel
# ---------------------------------------------------------------------------

func _setup_enemy_status_panel() -> void:
	var ui_root: Node = get_node_or_null("UI")
	if not ui_root:
		return

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(300, 155)
	panel.anchor_left    = 0.5
	panel.anchor_right   = 0.5
	panel.anchor_top     = 0.0
	panel.anchor_bottom  = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_left    = -150.0
	panel.offset_right   = 150.0
	panel.offset_top     = 5.0
	panel.offset_bottom  = 160.0
	panel.mouse_filter   = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.08, 0.04, 0.13, 0.93)
	style.border_color = Color(0.55, 0.20, 0.80, 1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	# --- Portrait + name row ---
	var portrait_row := HBoxContainer.new()
	portrait_row.add_theme_constant_override("separation", 8)
	portrait_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(portrait_row)

	var portrait := ColorRect.new()
	portrait.custom_minimum_size = Vector2(36, 36)
	portrait.color = Color(0.25, 0.08, 0.45, 1)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_row.add_child(portrait)

	var initial_label := Label.new()
	initial_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	initial_label.add_theme_font_size_override("font_size", 20)
	initial_label.add_theme_color_override("font_color", Color(0.85, 0.60, 1.0, 1))
	initial_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameManager.current_enemy:
		initial_label.text = GameManager.current_enemy.enemy_name.left(1)
	portrait.add_child(initial_label)

	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.90, 0.65, 1.0, 1))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	if GameManager.current_enemy:
		var prefix: String = "⚔ BOSS  " if GameManager.is_boss_fight() else ""
		name_lbl.text = prefix + GameManager.current_enemy.enemy_name
	portrait_row.add_child(name_lbl)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# --- Two-column stats area ---
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cols)

	# Left column: core stats
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 3)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left_col)

	# Right column: status effects
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 3)
	right_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(right_col)

	_enemy_status_hp_label = Label.new()
	_enemy_status_hp_label.add_theme_font_size_override("font_size", 12)
	_enemy_status_hp_label.add_theme_color_override("font_color", Color(0.95, 0.40, 0.40, 1))
	_enemy_status_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_enemy_status_hp_label)

	_enemy_status_essence_label = Label.new()
	_enemy_status_essence_label.add_theme_font_size_override("font_size", 12)
	_enemy_status_essence_label.add_theme_color_override("font_color", Color(0.70, 0.40, 1.0, 1))
	_enemy_status_essence_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_enemy_status_essence_label)

	_enemy_status_mana_label = Label.new()
	_enemy_status_mana_label.add_theme_font_size_override("font_size", 12)
	_enemy_status_mana_label.add_theme_color_override("font_color", Color(0.30, 0.65, 1.0, 1))
	_enemy_status_mana_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_enemy_status_mana_label)

	_enemy_status_hand_label = Label.new()
	_enemy_status_hand_label.add_theme_font_size_override("font_size", 12)
	_enemy_status_hand_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85, 1))
	_enemy_status_hand_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_enemy_status_hand_label)

	# Void Mark row — right column, hidden when count is 0
	_enemy_status_marks_row = HBoxContainer.new()
	_enemy_status_marks_row.add_theme_constant_override("separation", 4)
	_enemy_status_marks_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_status_marks_row.visible = false
	right_col.add_child(_enemy_status_marks_row)

	const VOIDMARK_ICON := "res://assets/art/icons/icon_voidmark.png"
	if ResourceLoader.exists(VOIDMARK_ICON):
		var vm_icon := TextureRect.new()
		vm_icon.texture             = load(VOIDMARK_ICON)
		vm_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vm_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		vm_icon.custom_minimum_size = Vector2(14, 14)
		vm_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vm_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		_enemy_status_marks_row.add_child(vm_icon)

	_enemy_status_marks_label = Label.new()
	_enemy_status_marks_label.add_theme_font_size_override("font_size", 12)
	_enemy_status_marks_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15, 1))
	_enemy_status_marks_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_status_marks_row.add_child(_enemy_status_marks_label)

	_enemy_hero_attack_hint = Label.new()
	_enemy_hero_attack_hint.text = "▶  Click to Attack"
	_enemy_hero_attack_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_hero_attack_hint.add_theme_font_size_override("font_size", 12)
	_enemy_hero_attack_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20, 1.0))
	_enemy_hero_attack_hint.visible = false
	_enemy_hero_attack_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_enemy_hero_attack_hint)

	_enemy_status_panel = panel
	panel.gui_input.connect(_on_enemy_hero_frame_input)
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
	if _enemy_status_mana_label:
		var mana_max := enemy_ai.mana_max if enemy_ai else 0
		var mana_cur := enemy_ai.mana if enemy_ai else 0
		_enemy_status_mana_label.text = "◈ Mana: %d / %d" % [mana_cur, mana_max]
	if _enemy_status_hand_label:
		var hand_size := enemy_ai.hand.size() if enemy_ai else 0
		_enemy_status_hand_label.text = "🂠 Hand: %d" % hand_size
	if _enemy_status_marks_row:
		if enemy_void_marks > 0:
			if _enemy_status_marks_label:
				_enemy_status_marks_label.text = "Void Mark ×%d" % enemy_void_marks
			_enemy_status_marks_row.visible = true
		else:
			_enemy_status_marks_row.visible = false

# ---------------------------------------------------------------------------
# Player hero status panel (bottom-right)
# ---------------------------------------------------------------------------

func _setup_player_status_panel() -> void:
	var ui_root: Node = get_node_or_null("UI")
	if not ui_root:
		return

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(240, 140)
	panel.anchor_left   = 1.0
	panel.anchor_right  = 1.0
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	panel.offset_left   = -250.0
	panel.offset_right  = -10.0
	panel.offset_top    = -150.0
	panel.offset_bottom = -10.0
	panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.06, 0.06, 0.14, 0.93)
	style.border_color = Color(0.35, 0.55, 0.90, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 5)
	vbox.add_theme_constant_override("margin_left", 6)
	vbox.add_theme_constant_override("margin_right", 6)
	vbox.add_theme_constant_override("margin_top", 5)
	vbox.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(vbox)

	# Portrait row
	var portrait_row := HBoxContainer.new()
	portrait_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_row.add_theme_constant_override("separation", 8)
	vbox.add_child(portrait_row)

	var portrait := ColorRect.new()
	portrait.custom_minimum_size = Vector2(40, 40)
	portrait.color = Color(0.08, 0.15, 0.38, 1)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_row.add_child(portrait)

	var initial_label := Label.new()
	initial_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	initial_label.add_theme_font_size_override("font_size", 20)
	initial_label.add_theme_color_override("font_color", Color(0.60, 0.80, 1.0, 1))
	initial_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hero := HeroDatabase.get_hero(GameManager.current_hero)
	if hero:
		initial_label.text = hero.hero_name.left(1)
	portrait.add_child(initial_label)

	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 1))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hero:
		name_lbl.text = hero.hero_name
	portrait_row.add_child(name_lbl)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	_player_status_hp_label = Label.new()
	_player_status_hp_label.add_theme_font_size_override("font_size", 13)
	_player_status_hp_label.add_theme_color_override("font_color", Color(0.95, 0.40, 0.40, 1))
	_player_status_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_player_status_hp_label)

	_player_status_panel = panel
	ui_root.add_child(panel)
	_update_player_status_panel()

func _update_player_status_panel() -> void:
	if not _player_status_hp_label:
		return
	_player_status_hp_label.text = "❤ HP: %d / %d" % [player_hp, GameManager.player_hp_max]

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
	_large_preview.apply_cost_discount(_spell_mana_discount())
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
	var _hero_atk_slot := _find_slot_for(selected_attacker)
	combat_manager.resolve_minion_attack_hero(selected_attacker, "enemy")
	if _hero_atk_slot and _enemy_status_panel:
		_play_hero_attack_anim(_hero_atk_slot, _enemy_status_panel)
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
	if end_turn_button:
		end_turn_button.disabled = true
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
# Attack animation — lunge + flash + damage popup
# ---------------------------------------------------------------------------

func _play_attack_anim(atk_slot: BoardSlot, def_slot: BoardSlot, damage: int,
		attacker: MinionInstance = null, defender: MinionInstance = null) -> void:
	var atk_rect  := atk_slot.get_global_rect()
	var def_rect  := def_slot.get_global_rect()
	var direction := (def_rect.get_center() - atk_rect.get_center()).normalized()
	var lunge_pos := atk_rect.position + direction * 55.0

	var orig_parent: Control = atk_slot.get_parent()
	var orig_index:  int     = atk_slot.get_index()

	# Placeholder keeps the gap in the HBoxContainer while slot is reparented
	var placeholder := Control.new()
	placeholder.custom_minimum_size = Vector2(BoardSlot.SLOT_W, BoardSlot.SLOT_H)
	placeholder.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	orig_parent.add_child(placeholder)
	orig_parent.move_child(placeholder, orig_index)   # inserts before slot (slot shifts +1)
	orig_parent.remove_child(atk_slot)                # remove slot; placeholder holds the gap

	# Move slot to $UI so its position is free from container layout
	$UI.add_child(atk_slot)
	atk_slot.position = atk_rect.position
	atk_slot.size     = atk_rect.size

	var tw := create_tween()
	tw.tween_property(atk_slot, "position", lunge_pos, 0.10)
	tw.tween_callback(func() -> void:
		_flash_slot(def_slot)
		if damage > 0:
			_spawn_damage_popup(def_rect.get_center(), damage)
	)
	tw.tween_property(atk_slot, "position", atk_rect.position, 0.16)
	tw.tween_callback(func() -> void:
		$UI.remove_child(atk_slot)
		orig_parent.add_child(atk_slot)
		orig_parent.move_child(atk_slot, orig_index)
		placeholder.queue_free()
		# Unfreeze and refresh both slots now that lunge is done
		atk_slot.freeze_visuals = false
		def_slot.freeze_visuals = false
		atk_slot._refresh_visuals()
		def_slot._refresh_visuals()
		if attacker: _refresh_slot_for(attacker)
		if defender: _refresh_slot_for(defender)
	)

func _play_hero_attack_anim(atk_slot: BoardSlot, hero_panel: Panel) -> void:
	var atk_rect   := atk_slot.get_global_rect()
	var hero_rect  := hero_panel.get_global_rect()
	var direction  := (hero_rect.get_center() - atk_rect.get_center()).normalized()
	var lunge_pos  := atk_rect.position + direction * 55.0

	var orig_parent: Control = atk_slot.get_parent()
	var orig_index:  int     = atk_slot.get_index()

	var placeholder := Control.new()
	placeholder.custom_minimum_size = Vector2(BoardSlot.SLOT_W, BoardSlot.SLOT_H)
	placeholder.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	orig_parent.add_child(placeholder)
	orig_parent.move_child(placeholder, orig_index)
	orig_parent.remove_child(atk_slot)

	$UI.add_child(atk_slot)
	atk_slot.position = atk_rect.position
	atk_slot.size     = atk_rect.size

	var tw := create_tween()
	tw.tween_property(atk_slot, "position", lunge_pos, 0.10)
	tw.tween_callback(func() -> void:
		# Flash the hero panel red on impact
		var ftw := create_tween()
		ftw.tween_property(hero_panel, "modulate", Color(1.8, 0.30, 0.30, 1.0), 0.06)
		ftw.tween_property(hero_panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.22)
	)
	tw.tween_property(atk_slot, "position", atk_rect.position, 0.16)
	tw.tween_callback(func() -> void:
		$UI.remove_child(atk_slot)
		orig_parent.add_child(atk_slot)
		orig_parent.move_child(atk_slot, orig_index)
		placeholder.queue_free()
		atk_slot._refresh_visuals()
	)

func _flash_slot(slot: BoardSlot) -> void:
	var tw := create_tween()
	tw.tween_property(slot, "modulate", Color(1.8, 0.30, 0.30, 1.0), 0.06)
	tw.tween_property(slot, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.22)

## Show a large centred card visual when a spell is cast.
## Animates in → calls on_impact (damage resolves here) → holds → fades out.
func _show_spell_cast_anim(spell: SpellCardData, is_enemy: bool, on_impact: Callable) -> void:
	var cv: CardVisual = CARD_VISUAL_SCENE.instantiate() as CardVisual
	cv.apply_size_mode("combat_preview")
	cv.setup(spell)
	cv.z_index = 100
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(cv)
	# Centre on screen
	var vp      := get_viewport().get_visible_rect().size
	var card_sz := Vector2(336.0, 504.0)
	cv.position     = (vp - card_sz) * 0.5
	cv.pivot_offset = card_sz * 0.5
	# Optional tinted outline to distinguish enemy vs player cast
	cv.modulate = Color(1.10, 0.85, 1.00, 0.0) if not is_enemy \
		else Color(1.10, 0.75, 0.70, 0.0)
	cv.scale = Vector2(0.65, 0.65)
	var tw := create_tween()
	# Animate in
	tw.set_parallel(true)
	tw.tween_property(cv, "modulate:a", 1.0, 0.22)
	tw.tween_property(cv, "scale", Vector2(1.0, 1.0), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(0.08)
	# Impact: resolve spell effects, flash, damage numbers
	tw.tween_callback(on_impact)
	# Hold so player can read the card
	tw.tween_interval(0.55)
	# Animate out
	tw.tween_property(cv, "modulate:a", 0.0, 0.22)
	tw.tween_callback(cv.queue_free)

## Wrapper: apply spell damage to a minion + show flash and damage popup.
func _spell_dmg(target: MinionInstance, damage: int) -> void:
	var slot := _find_slot_for(target)
	combat_manager.apply_spell_damage(target, damage)
	if slot:
		_flash_slot(slot)
		_spawn_damage_popup(slot.get_global_rect().get_center(), damage)

## Flash a hero status panel and show a damage number.
## on_done (optional) is called after the flash animation completes.
func _flash_hero(target: String, amount: int, on_done: Callable = Callable()) -> void:
	var panel := _player_status_panel if target == "player" else _enemy_status_panel
	if panel == null:
		if on_done.is_valid():
			on_done.call()
		return
	var tw := create_tween()
	tw.tween_property(panel, "modulate", Color(1.8, 0.30, 0.30, 1.0), 0.06)
	tw.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.30)
	if on_done.is_valid():
		tw.tween_callback(on_done)
	_spawn_damage_popup(panel.get_global_rect().get_center(), amount)

func _spawn_damage_popup(screen_center: Vector2, damage: int) -> void:
	var lbl := Label.new()
	lbl.text = "-%d" % damage
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.22, 0.22, 1.0))
	var bold: Font = load("res://assets/fonts/cinzel/Cinzel-Bold.ttf") \
		if ResourceLoader.exists("res://assets/fonts/cinzel/Cinzel-Bold.ttf") else null
	if bold:
		lbl.add_theme_font_override("font", bold)
	lbl.z_index = 200
	$UI.add_child(lbl)
	lbl.position = screen_center - Vector2(18, 18)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position", lbl.position + Vector2(0, -72), 0.75)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.75)
	tw.chain().tween_callback(lbl.queue_free)

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
	_anim_pre_hp   = target.current_health
	_anim_atk_slot = _find_slot_for(attacker)
	_anim_def_slot = _find_slot_for(target)
	if _anim_atk_slot: _anim_atk_slot.freeze_visuals = true
	if _anim_def_slot: _anim_def_slot.freeze_visuals = true
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
	if atk_slot and _player_status_panel:
		_play_hero_attack_anim(atk_slot, _player_status_panel)

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
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TURN_START, _handler_minion_turn_start_passives, 21)

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
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, _handler_rogue_imp_elder_aura, 7)

	# -----------------------------------------------------------------------
	# Trap routing for enemy actions  (priority 30 — after any future pre-trap passives)
	# -----------------------------------------------------------------------
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, _trap_check_enemy_summon, 30)
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST,      _trap_check_enemy_spell,  30)
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_ATTACK,          _trap_check_enemy_attack, 30)
	trigger_manager.register(Enums.TriggerEvent.ON_HERO_DAMAGED,          _trap_check_damage_taken, 10)

	# -----------------------------------------------------------------------
	# ON_RUNE_PLACED — board passive: Rune Warden (priority 5)
	# -----------------------------------------------------------------------
	trigger_manager.register(Enums.TriggerEvent.ON_RUNE_PLACED, _handler_rune_warden_passive, 5)

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
	if active_environment != null and not active_environment.passive_effect_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		EffectResolver.run(active_environment.passive_effect_steps, ctx)

func _handler_minion_turn_start_passives(_ctx: EventContext) -> void:
	for m in player_board.duplicate():
		var mc := m.card_data as MinionCardData
		if mc and not mc.on_turn_start_effect_steps.is_empty():
			var ectx := EffectContext.make(self, "player")
			ectx.source = m
			EffectResolver.run(mc.on_turn_start_effect_steps, ectx)

# ---------------------------------------------------------------------------
# ON_ENEMY_TURN_START handlers
# ---------------------------------------------------------------------------

func _handler_enemy_turn_environment(_ctx: EventContext) -> void:
	if active_environment != null and active_environment.fires_on_enemy_turn and not active_environment.passive_effect_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		EffectResolver.run(active_environment.passive_effect_steps, ctx)

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
		"void_amplifier_buff_demon":
			if summoned.card_data.minion_type == Enums.MinionType.DEMON and summoned != passive_owner:
				BuffSystem.apply(summoned, Enums.BuffType.ATK_BONUS, 100, "void_amplifier")
				summoned.current_health += 100
				_refresh_slot_for(summoned)
				_log("  Void Amplifier: %s enters with +100 ATK / +100 HP." % summoned.card_data.card_name, _LogType.PLAYER)

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_DIED handlers
# ---------------------------------------------------------------------------

func _handler_rune_warden_passive(ctx: EventContext) -> void:
	for m in player_board:
		if (m.card_data as MinionCardData).passive_effect_id == "rune_warden":
			BuffSystem.apply(m, Enums.BuffType.TEMP_ATK, 200, "rune_warden")
			_log("  Rune Warden: +200 ATK until end of turn.", _LogType.PLAYER)
			_refresh_slot_for(m)

func _handler_minion_on_death_effect(ctx: EventContext) -> void:
	var minion := ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var card := minion.card_data as MinionCardData
	if not card.on_death_effect.is_empty():
		_resolve_on_death_effect(minion)
	if not card.on_death_effect_steps.is_empty():
		var eff_ctx := EffectContext.make(self, minion.owner)
		eff_ctx.source = minion
		EffectResolver.run(card.on_death_effect_steps, eff_ctx)

func _handler_board_passives_on_player_death(ctx: EventContext) -> void:
	var dead := ctx.minion
	# Active environment on-death steps
	if active_environment != null and not active_environment.on_player_minion_died_steps.is_empty():
		var eff_ctx := EffectContext.make(self, "player")
		eff_ctx.dead_minion = dead
		EffectResolver.run(active_environment.on_player_minion_died_steps, eff_ctx)
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
		"soul_taskmaster_gain_atk":
			if dead.card_data.minion_type == Enums.MinionType.DEMON and dead != passive_owner:
				BuffSystem.apply(passive_owner, Enums.BuffType.ATK_BONUS, 50, "soul_taskmaster_stack")
				_refresh_slot_for(passive_owner)
				_log("  Soul Taskmaster: Demon died → gains +50 ATK.", _LogType.PLAYER)

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

## Resolve the on_play_effect_steps (battle cry) of a player minion played from hand.
## Registered at priority 10 — after hand-play talent effects (priority 0).
func _handler_player_minion_on_play_effect(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var mc := minion.card_data as MinionCardData
	if not mc.on_play_effect_steps.is_empty():
		var ectx        := EffectContext.make(self, "player")
		ectx.source     = minion
		ectx.chosen_target = ctx.target
		EffectResolver.run(mc.on_play_effect_steps, ectx)

# ---------------------------------------------------------------------------
# ON_PLAYER_MINION_SUMMONED — on-summon effect resolver (fires for ALL player summons)
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# ON_ENEMY_MINION_SUMMONED — on-play / on-summon effect resolvers (fire before traps)
# ---------------------------------------------------------------------------

## Resolve the on_play_effect of an enemy minion (played from EnemyAI hand).
## Priority 5 — runs before trap handlers (priority 30).
func _handler_enemy_minion_on_play(ctx: EventContext) -> void:
	var minion: MinionInstance = ctx.minion
	if minion == null or not (minion.card_data is MinionCardData):
		return
	var mc := minion.card_data as MinionCardData
	if not mc.on_play_effect_steps.is_empty():
		var ectx    := EffectContext.make(self, "enemy")
		ectx.source = minion
		EffectResolver.run(mc.on_play_effect_steps, ectx)


## Apply Rogue Imp Elder +100 ATK aura to a newly summoned enemy feral imp.
func _handler_rogue_imp_elder_aura(ctx: EventContext) -> void:
	var summoned := ctx.minion
	if summoned == null or not _minion_has_tag(summoned, "feral_imp"):
		return
	var has_elder := enemy_board.any(func(m: MinionInstance) -> bool: return m.card_data.id == "rogue_imp_elder" and m != summoned)
	if has_elder:
		BuffSystem.apply(summoned, Enums.BuffType.ATK_BONUS, 100, "rogue_imp_elder")
		_refresh_slot_for(summoned)
		_log("  Rogue Imp Elder aura: %s enters with +100 ATK." % summoned.card_data.card_name, _LogType.ENEMY)

# ---------------------------------------------------------------------------
# ON_ENEMY_MINION_SUMMONED / ON_ENEMY_SPELL_CAST / ON_ENEMY_ATTACK / ON_HERO_DAMAGED
# Trap routing handlers — delegate to _check_and_fire_traps() which runs
# each matching trap's effect_steps via EffectResolver.
# ---------------------------------------------------------------------------

func _trap_check_enemy_summon(ctx: EventContext) -> void:
	_check_and_fire_traps(ctx.event_type, ctx.minion)

func _trap_check_enemy_spell(ctx: EventContext) -> void:
	_check_and_fire_traps(ctx.event_type)

func _trap_check_enemy_attack(ctx: EventContext) -> void:
	_check_and_fire_traps(ctx.event_type, ctx.minion)

func _trap_check_damage_taken(ctx: EventContext) -> void:
	_check_and_fire_traps(ctx.event_type)
