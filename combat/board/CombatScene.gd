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

## True while an enemy summon card reveal is on screen — EnemyAI waits on this before its next action.
var _enemy_summon_reveal_active: bool = false
signal enemy_summon_reveal_done()

# Enemy hero status panel (built programmatically)
var _enemy_status_panel: Panel = null
var _hero_spell_tween: Tween = null
var _hero_spell_pulse: float = 0.0
var _hero_attack_tween: Tween = null
var _hero_attack_pulse: float = 0.0
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

# Pip bar columns (essence left, mana right) — 10 pips each, built in _setup_pip_bars()
var _pip_essence_panels: Array[Panel]       = []
var _pip_mana_panels:    Array[Panel]       = []
var _pip_essence_rects:  Array[TextureRect] = []
var _pip_mana_rects:     Array[TextureRect] = []
var _ess_pip_tex: GradientTexture2D = null
var _mna_pip_tex: GradientTexture2D = null
var _ess_ovf_tex: GradientTexture2D = null  # overflow/temp essence
var _mna_ovf_tex: GradientTexture2D = null  # overflow/temp mana
# Outer border panels — animated on resource gain/spend
var _ess_col_panel: Panel = null
var _mna_col_panel: Panel = null
var _ess_col_tween: Tween = null
var _mna_col_tween: Tween = null
# Previous values used to detect direction of change
var _prev_essence: int = -1
var _prev_mana:    int = -1
# Card-cost blink — highlights which pips will be spent / gained when a card is selected
var _pip_ess_blink:  int   = 0   # essence pips to fade (spend)
var _pip_mna_blink:  int   = 0   # mana pips to fade (spend)
var _pip_ess_gain:   int   = 0   # essence pips to glow (gain)
var _pip_mna_gain:   int   = 0   # mana pips to glow (gain)
var _pip_blink_tween: Tween = null
var _pip_blink_phase: float = 0.0

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var combat_manager := CombatManager.new()

## Central event dispatcher — populated by _setup_triggers() in _ready().
var trigger_manager: TriggerManager
var _handlers: CombatHandlers
var _hardcoded: HardcodedEffects

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

# Death animations deferred until after lunge freeze_visuals is released.
# Each entry is {slot: BoardSlot, pos: Vector2} — position captured when slot is still in-place.
var _deferred_death_slots: Array = []

# Card the player is currently trying to play (dragged or clicked from hand)
var pending_play_card: CardInstance = null

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
var relic_first_card_free: bool = false

# ---------------------------------------------------------------------------
# Talent state — reset each combat
# ---------------------------------------------------------------------------

## Void Mark stacks on the enemy hero (accumulate through the run)
var enemy_void_marks: int = 0

## Passive-configurable stats — set by CombatSetup from the registry at combat start.
var void_mark_damage_per_stack: int = 25  ## deepened_curse sets this to 50
var rune_aura_multiplier:       int = 1   ## runic_attunement sets this to 2

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
var imp_evolution_used_this_turn: bool = false

## Currently hovered hand card visual — used for pip-blink cost preview.
var _hovered_hand_visual: CardVisual = null

# ---------------------------------------------------------------------------
# Enemy passive state — populated from GameManager.current_enemy.passives
# ---------------------------------------------------------------------------

## Active passive IDs for the current encounter.
var _active_enemy_passives: Array[String] = []

## True after Feral Instinct has been granted this enemy turn (resets at ON_ENEMY_TURN_START).
var feral_instinct_granted_this_turn: bool = false

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	trigger_manager = TriggerManager.new()
	_hardcoded = HardcodedEffects.new()
	_hardcoded.setup(self)
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
	if GameManager.current_enemy != null:
		_active_enemy_passives = GameManager.current_enemy.passives.duplicate()
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
	enemy_ai.trap_placed.connect(_on_enemy_trap_placed)
	enemy_ai.environment_placed.connect(_on_enemy_environment_placed)
	# Load the enemy's deck and profile from the current encounter
	var enemy_deck: Array[String] = []
	if GameManager.current_enemy != null:
		enemy_deck = GameManager.current_enemy.deck
		enemy_ai.ai_profile = GameManager.current_enemy.ai_profile
	enemy_ai.scene = self
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
		hand_display.card_hovered.connect(_on_hand_card_hovered)
		hand_display.card_unhovered.connect(_on_hand_card_unhovered)
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
	# Refresh all slot visuals — clears Exhausted badges and any stale occupied states
	for slot in player_slots + enemy_slots:
		slot._refresh_visuals()
	# Fire turn-start events — all effects are handled by registered listeners in _setup_triggers().
	if is_player_turn:
		imp_evolution_used_this_turn     = false
		for inst in turn_manager.player_hand:
			inst.cost_delta = 0
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_PLAYER_TURN_START))
	else:
		enemy_ai.spell_cost_penalty = _spell_tax_for_enemy_turn
		_spell_tax_for_enemy_turn = 0
		trigger_manager.fire(EventContext.make(Enums.TriggerEvent.ON_ENEMY_TURN_START))
		await get_tree().create_timer(0.4).timeout
		if not is_inside_tree():
			return
		enemy_ai.run_turn()
		# run_turn() grows resources and refills them synchronously before its
		# first await, so this panel refresh sees the correct post-growth values.
		_update_enemy_status_panel()

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
		essence_label.text = "%d/%d" % [essence, essence_max]
	if mana_label:
		mana_label.text = "%d/%d" % [mana, mana_max]
	if hand_display:
		hand_display.refresh_playability(essence, mana)
	_refresh_hand_spell_costs()
	_update_pip_bars(essence, essence_max, mana, mana_max)
	# Pulse the column border to signal gain (green) or spend (red/orange)
	if _prev_essence >= 0 and essence != _prev_essence:
		_pulse_pip_col(true, essence > _prev_essence)
	if _prev_mana >= 0 and mana != _prev_mana:
		_pulse_pip_col(false, mana > _prev_mana)
	_prev_essence = essence
	_prev_mana    = mana
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

func _on_card_drawn(inst: CardInstance) -> void:
	if hand_display:
		hand_display.add_card(inst)
		hand_display.refresh_playability(turn_manager.essence, turn_manager.mana)
		hand_display.refresh_condition_glows(self, turn_manager.essence, turn_manager.mana)
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, "player")
	ctx.card = inst.card_data
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

func _on_hand_card_selected(inst: CardInstance) -> void:
	# Guard: card plays are only valid on the player's turn
	if not turn_manager.is_player_turn:
		return
	selected_attacker = null
	_clear_all_highlights()
	pending_play_card = inst
	if inst.card_data is SpellCardData:
		_begin_spell_select(inst.card_data as SpellCardData)
	elif inst.card_data is TrapCardData:
		_try_play_trap(inst.card_data as TrapCardData)
	elif inst.card_data is EnvironmentCardData:
		_try_play_environment(inst.card_data as EnvironmentCardData)
	elif inst.card_data is MinionCardData:
		_begin_minion_select(inst.card_data as MinionCardData)

## Cancel a pending card selection: clear state and deselect hand.
func _cancel_card_select() -> void:
	_stop_pip_blink()
	pending_play_card = null
	if hand_display:
		hand_display.deselect_current()

## Hand card hover — show large preview and cost blink.
## Suppressed entirely while another card is pending a target selection.
func _on_hand_card_hovered(card_data: CardData, visual: CardVisual) -> void:
	_hovered_hand_visual = visual
	if pending_play_card != null:
		return   # targeting in progress — don't interrupt with another card's preview
	_show_large_preview(card_data, visual)
	if turn_manager and turn_manager.is_player_turn:
		_start_pip_blink_for_card(card_data)

## Hand card unhover — hide preview and stop blink (unless a targeted card is still pending).
func _on_hand_card_unhovered() -> void:
	_hovered_hand_visual = null
	_hide_large_preview()
	if pending_play_card == null:
		_stop_pip_blink()

## Compute and start the pip blink preview for any card type.
## Used by hover preview and as a fallback when a targeted card is clicked.
func _start_pip_blink_for_card(card_data: CardData) -> void:
	if not turn_manager:
		return
	var ess_spend := 0
	var mna_spend := 0
	var ess_gain  := 0
	var mna_gain  := 0
	if card_data is SpellCardData:
		var spell := card_data as SpellCardData
		mna_spend = _effective_spell_cost(spell)
		for step: Dictionary in spell.effect_steps:
			if step.get("type") != "CONVERT_RESOURCE":
				continue
			var amount: int    = step.get("amount", 0)
			var from: String   = step.get("convert_from", "")
			var to: String     = step.get("convert_to", "")
			var available: int = turn_manager.mana - mna_spend if from == "mana" \
					else turn_manager.essence - ess_spend
			var actual: int    = mini(amount, maxi(available, 0))
			if from == "mana":   mna_spend += actual
			elif from == "essence": ess_spend += actual
			if to == "essence": ess_gain += actual
			elif to == "mana":  mna_gain += actual
	elif card_data is MinionCardData:
		var mc := card_data as MinionCardData
		var extra_mana := 1 if (_card_has_tag(mc, "void_imp") and _has_talent("piercing_void")) else 0
		ess_spend = mc.essence_cost
		mna_spend = mc.mana_cost + extra_mana
	elif card_data is TrapCardData:
		mna_spend = _effective_trap_cost(card_data as TrapCardData)
	elif card_data is EnvironmentCardData:
		mna_spend = (card_data as EnvironmentCardData).cost
	if not relic_first_card_free and not turn_manager.can_afford(ess_spend, mna_spend):
		return
	_start_pip_blink(ess_spend, mna_spend, ess_gain, mna_gain)

## Handle a spell card being selected from hand.
## Instant spells cast immediately (cost preview shown on hover).
## Targeted spells enter pending state and highlight valid targets.
func _begin_spell_select(spell: SpellCardData) -> void:
	if not relic_first_card_free and not turn_manager.can_afford(0, _effective_spell_cost(spell)):
		_cancel_card_select()
		return
	if spell.requires_target:
		_start_pip_blink_for_card(spell)   # ensure blink runs even if card wasn't hovered
		_highlight_spell_targets(spell)
	else:
		_try_play_spell(spell)

## Handle a minion card being selected from hand.
## Checks affordability and board space, then highlights valid placement/target slots.
func _begin_minion_select(mc: MinionCardData) -> void:
	# Check affordability (Void Crystal relic bypasses cost for the first card)
	var extra_mana := 1 if (_card_has_tag(mc, "void_imp") and _has_talent("piercing_void")) else 0
	if not relic_first_card_free and not turn_manager.can_afford(mc.essence_cost, mc.mana_cost + extra_mana):
		_cancel_card_select()
		return
	# Check board space before highlighting
	if not player_slots.any(func(s: BoardSlot) -> bool: return s.is_empty()):
		_cancel_card_select()
		return
	_start_pip_blink_for_card(mc)   # ensure blink runs even if card wasn't hovered
	if mc.on_play_requires_target and _has_valid_minion_on_play_targets(mc):
		_awaiting_minion_target = true
		_highlight_minion_on_play_targets(mc)
	else:
		# No valid targets (or card doesn't need one) — go straight to placement.
		# Effect will fire but resolve with null target (logs "no targets" and skips).
		_awaiting_minion_target = false
		_highlight_empty_player_slots()

func _on_hand_card_deselected() -> void:
	_stop_pip_blink()
	pending_play_card = null
	pending_minion_target = null
	_awaiting_minion_target = false
	_tear_down_trap_env_targeting()
	_clear_all_highlights()

# ---------------------------------------------------------------------------
# Spell / Trap / Environment play
# ---------------------------------------------------------------------------

func _try_play_spell(spell: SpellCardData) -> void:
	if not _pay_card_cost(0, _effective_spell_cost(spell)):
		if hand_display:
			hand_display.deselect_current()
		return
	_log("You cast: %s" % spell.card_name)
	turn_manager.remove_from_hand(pending_play_card)
	if hand_display:
		hand_display.remove_card(pending_play_card)
		hand_display.deselect_current()
	pending_play_card = null
	# Show large card preview; resolve effects on impact so damage visuals sync
	_show_card_cast_anim(spell, false, func() -> void:
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
	if not _pay_card_cost(0, pending_play_card.effective_cost()):
		if hand_display:
			hand_display.deselect_current()
		return
	if trap.is_rune:
		_log("You place rune: %s" % trap.card_name)
	else:
		_log("You set trap: %s" % trap.card_name)
	active_traps.append(trap)
	_update_trap_display()
	turn_manager.remove_from_hand(pending_play_card)
	if hand_display:
		hand_display.remove_card(pending_play_card)
		hand_display.deselect_current()
	pending_play_card = null
	# Show card preview (traps have no immediate effects — they fire on trigger)
	_show_card_cast_anim(trap, false, func() -> void: pass)
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
	_update_environment_display()
	turn_manager.remove_from_hand(pending_play_card)
	if hand_display:
		hand_display.remove_card(pending_play_card)
		hand_display.deselect_current()
	pending_play_card = null
	# Show card preview; fire on-enter effects and ritual checks on impact
	_show_card_cast_anim(env, false, func() -> void:
		if not env.rituals.is_empty():
			var env_ctx := EventContext.make(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, "player")
			env_ctx.card = env
			trigger_manager.fire(env_ctx)
		if not env.on_enter_effect_steps.is_empty():
			EffectResolver.run(env.on_enter_effect_steps, EffectContext.make(self, "player"))
		if not env.passive_effect_steps.is_empty():
			EffectResolver.run(env.passive_effect_steps, EffectContext.make(self, "player"))
	)

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
	if pending_play_card != null and pending_play_card.card_data is MinionCardData:
		# Still waiting for player to click a valid target — ignore slot clicks until then
		if _awaiting_minion_target:
			return
		var inst_to_play := pending_play_card
		var on_play_target := pending_minion_target
		pending_minion_target = null
		pending_play_card = null
		_awaiting_minion_target = false
		_clear_all_highlights()
		_try_play_minion_animated(inst_to_play, slot, on_play_target)

func _on_player_slot_clicked_occupied(_slot: BoardSlot, minion: MinionInstance) -> void:
	if not turn_manager.is_player_turn:
		return
	# If a targeted spell is waiting for a target, apply it
	if pending_play_card != null and pending_play_card.card_data is SpellCardData:
		var spell := pending_play_card.card_data as SpellCardData
		if spell.requires_target and _is_valid_spell_target(minion, spell.target_type):
			_apply_targeted_spell(spell, minion)
			return
	# If a targeted minion card is waiting for a friendly target, store it and show placement slots.
	# If the minion card is pending but NOT awaiting a target (board was shown), block attacker
	# selection so clicking an occupied slot doesn't accidentally select an attacker.
	if pending_play_card != null and pending_play_card.card_data is MinionCardData:
		var mc := pending_play_card.card_data as MinionCardData
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
	if pending_play_card != null and pending_play_card.card_data is SpellCardData:
		var spell := pending_play_card.card_data as SpellCardData
		if spell.requires_target and _is_valid_spell_target(minion, spell.target_type):
			_apply_targeted_spell(spell, minion)
			return
	# If a targeted minion card is waiting for an enemy target, store it and show placement slots
	if pending_play_card != null and pending_play_card.card_data is MinionCardData:
		var mc := pending_play_card.card_data as MinionCardData
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
	_show_hero_button(false)

# ---------------------------------------------------------------------------
# Minion play
# ---------------------------------------------------------------------------

func _try_play_minion(inst: CardInstance, slot: BoardSlot, on_play_target: MinionInstance = null) -> void:
	if not slot.is_empty():
		return
	var card := inst.card_data as MinionCardData
	# Talent: piercing_void — Void Imps cost +1 Mana
	var extra_mana := 1 if (_card_has_tag(card, "void_imp") and _has_talent("piercing_void")) else 0
	if not _pay_card_cost(card.essence_cost, card.mana_cost + extra_mana):
		return
	_log("You play: %s" % card.card_name)
	var instance := MinionInstance.create(card, "player")
	instance.card_instance = inst
	# Place visually first so the slot is not mistakenly taken by tokens summoned during on-play.
	# Do NOT append to player_board yet — on-play effects should not see this minion on the board.
	slot.place_minion(instance)
	# Fire ON_PLAYER_MINION_PLAYED — carries the player-chosen target for targeted battle cries.
	# The minion is not in player_board during this event, so ALL_FRIENDLY effects exclude it naturally.
	var play_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, "player")
	play_ctx.minion = instance
	play_ctx.card   = card
	play_ctx.target = on_play_target
	turn_manager.remove_from_hand(inst)
	if hand_display:
		hand_display.remove_card(inst)
		hand_display.deselect_current()
	trigger_manager.fire(play_ctx)
	# Now officially join the board before ON_PLAYER_MINION_SUMMONED (summon triggers expect it present).
	player_board.append(instance)
	var summon_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
	summon_ctx.minion = instance
	summon_ctx.card   = card
	trigger_manager.fire(summon_ctx)
	_refresh_hand_spell_costs()


## Animated variant of _try_play_minion — fires card flight + landing before triggers.
## State changes happen immediately; triggers fire after landing animation.
## Called without await so input is never blocked.
func _try_play_minion_animated(inst: CardInstance, slot: BoardSlot, on_play_target: MinionInstance = null) -> void:
	if not slot.is_empty():
		return
	var card := inst.card_data as MinionCardData
	var extra_mana := 1 if (_card_has_tag(card, "void_imp") and _has_talent("piercing_void")) else 0
	if not _pay_card_cost(card.essence_cost, card.mana_cost + extra_mana):
		return
	_log("You play: %s" % card.card_name)
	var instance := MinionInstance.create(card, "player")
	instance.card_instance = inst
	# slot.place_minion deferred to on_landing so empty placeholder stays visible during flight

	# Capture hand index BEFORE popping (pop removes the visual from the list)
	var hand_index := hand_display.get_index_for(card) if hand_display else 0
	var flying_visual: CardVisual = null
	if hand_display:
		flying_visual = hand_display.pop_selected_for_animation()
	turn_manager.remove_from_hand(inst)
	_refresh_hand_spell_costs()

	var total_cost: int = card.essence_cost + card.mana_cost
	var is_champion: bool = card.is_champion
	var on_landing := func() -> void:
		slot.place_minion(instance)  # switches slot from empty→occupied view at landing
		var play_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, "player")
		play_ctx.minion = instance
		play_ctx.card   = card
		play_ctx.target = on_play_target
		trigger_manager.fire(play_ctx)
		player_board.append(instance)
		var summon_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
		summon_ctx.minion = instance
		summon_ctx.card   = card
		trigger_manager.fire(summon_ctx)
		_refresh_hand_spell_costs()
	_animate_card_to_slot(flying_visual, slot, hand_index, total_cost, is_champion, on_landing)

## Async arc-flight + landing animation.
## Empty slot stays visible throughout flight; slot switches to minion view at landing.
## on_landing fires at card arrival (before punch) so triggers see the placed minion.
func _animate_card_to_slot(visual: CardVisual, slot: BoardSlot, hand_index: int, total_cost: int, is_champion: bool, on_landing: Callable) -> void:
	if visual == null or not is_inside_tree():
		on_landing.call()
		return
	var ui_layer: Node = $UI
	var start_pos: Vector2 = visual.global_position
	visual.reparent(ui_layer, true)  # preserves global_position; HBoxContainer reflows
	visual.z_index = 10

	var end_pos: Vector2 = slot.global_position

	# Arc peak: midpoint laterally + slight per-card lateral drift, 180px above
	var lateral_offset := (hand_index - 2) * 12.0
	var peak_pos := Vector2(
		(start_pos.x + end_pos.x) / 2.0 + lateral_offset,
		min(start_pos.y, end_pos.y) - 180.0
	)

	# Step 1 — rise to peak (card fully opaque, slot shows empty placeholder)
	var t1 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t1.tween_property(visual, "global_position", peak_pos, 0.22)
	await t1.finished
	if not is_inside_tree():
		visual.queue_free()
		on_landing.call()
		return

	# Step 2 — descend; card fades out as it arrives (slot still shows empty placeholder)
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(visual, "global_position", end_pos, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t2.tween_property(visual, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE)
	await t2.finished
	visual.queue_free()
	if not is_inside_tree():
		on_landing.call()
		return

	# Card has arrived — switch slot to minion view and fire triggers
	on_landing.call()
	if not is_inside_tree():
		return

	# Landing punch on the slot (now showing the minion)
	slot.pivot_offset = slot.size / 2.0
	var t3 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t3.tween_property(slot, "scale", Vector2(1.15, 1.15), 0.06)
	await t3.finished
	var t4 := create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t4.tween_property(slot, "scale", Vector2(1.0, 1.0), 0.10)
	await t4.finished
	slot.pivot_offset = Vector2.ZERO  # restore default

	_spawn_slot_ripple(slot, total_cost, is_champion)

## Spawn a ripple ring expanding from a board slot.
## Higher total_cost → larger expansion and higher initial opacity for more impact.
## The ring draws above other board slots but below the target slot (which is raised temporarily).
func _spawn_slot_ripple(slot: BoardSlot, total_cost: int = 0, is_champion: bool = false) -> void:
	var sz: Vector2 = slot.size
	var t_norm: float = clampf(total_cost / 8.0, 0.0, 1.0)
	var end_scale: float   = lerp(1.4, 2.4, t_norm)
	var start_alpha: float = lerp(0.4, 0.85, t_norm)
	var duration: float    = lerp(0.35, 0.55, t_norm)

	var ring := ColorRect.new()
	# Champions get a gold ripple; normal cards get white
	var base_color := Color(1.0, 0.78, 0.10) if is_champion else Color(1.0, 1.0, 1.0)
	ring.color = Color(base_color.r, base_color.g, base_color.b, start_alpha)
	# z=1 absolute: above other board slots (z=0) but below the target slot (raised to z=2)
	ring.z_index = 1
	ring.z_as_relative = false
	$UI.add_child(ring)
	ring.set_size(sz)
	ring.pivot_offset = sz * 0.5
	ring.global_position = slot.global_position
	ring.scale = Vector2(1.0, 1.0)  # starts at card edge, radiates outward

	# Raise target slot above the ring for the duration of the ripple
	var prev_z := slot.z_index
	var prev_relative := slot.z_as_relative
	slot.z_index = 2
	slot.z_as_relative = false

	var t := create_tween().set_parallel(true)
	t.tween_property(ring, "scale",      Vector2(end_scale, end_scale), duration).set_trans(Tween.TRANS_SINE)
	t.tween_property(ring, "modulate:a", 0.0,                           duration).set_trans(Tween.TRANS_SINE)
	await t.finished
	ring.queue_free()
	slot.z_index = prev_z
	slot.z_as_relative = prev_relative

## Placeholder for data-driven on-death effects (not yet implemented).
## Called by CombatHandlers.on_minion_died_death_effect via has_method check.
func _resolve_on_death_effect(_minion: MinionInstance) -> void:
	pass


# ---------------------------------------------------------------------------
# Relic effects
# ---------------------------------------------------------------------------

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

## Kept as a thin stub — logic lives in CombatHandlers.on_player_minion_died_board_passives (registered via TriggerManager).
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

	var kill_enemy := Button.new()
	kill_enemy.text = "Kill Enemy (5000)"
	kill_enemy.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
	kill_enemy.pressed.connect(func(): _on_hero_damaged("enemy", 5000))
	dmg_row.add_child(kill_enemy)

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

## Entry point for EffectResolver HARDCODED steps — delegates to HardcodedEffects.
func _resolve_hardcoded(id: String, ctx: EffectContext) -> void:
	_hardcoded.resolve(id, ctx)

## Legacy shim for spells that still use effect_id instead of effect_steps.
func _resolve_spell_effect(effect_id: String, target: MinionInstance, owner: String = "player") -> void:
	var ctx := EffectContext.make(self, owner)
	ctx.chosen_target = target
	_hardcoded.resolve(effect_id, ctx)

## Summon a 100/100 Void Spark into the first empty player slot.
func _summon_void_spark() -> void:
	_summon_token("void_spark", "player")

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
func _summon_void_imp() -> void:
	_summon_token("void_imp", "player")

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
	var all_cards: Array[CardInstance] = turn_manager.player_hand + turn_manager.player_deck
	for inst in all_cards:
		if not (inst.card_data is MinionCardData):
			continue
		var champion := inst.card_data as MinionCardData
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
			_summon_champion_card(champion, inst, inst in turn_manager.player_hand)
			return  # One champion summon per trigger check

## Evaluate whether a champion's auto-summon condition is currently met.
func _check_champion_condition(champion: MinionCardData) -> bool:
	match champion.auto_summon_condition:
		"board_tag_count":
			return _count_with_tag(champion.auto_summon_tag) >= champion.auto_summon_threshold
	return false

## Place the champion card on the first empty player slot (free of cost).
func _summon_champion_card(card: MinionCardData, inst: CardInstance, from_hand: bool) -> void:
	for slot in player_slots:
		if slot.is_empty():
			var instance := MinionInstance.create(card, "player")
			instance.card_instance = inst
			player_board.append(instance)
			slot.place_minion(instance)
			if from_hand:
				turn_manager.remove_from_hand(inst)
				if hand_display:
					hand_display.remove_card(inst)
			else:
				turn_manager.player_deck.erase(inst)
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
		hand_display.refresh_condition_glows(self, turn_manager.essence, turn_manager.mana)
	if _large_preview and _large_preview.visible:
		var extra := -(_hovered_hand_visual.card_inst.cost_delta) if _hovered_hand_visual != null and _hovered_hand_visual.card_inst != null else 0
		_large_preview.apply_cost_discount(discount + extra)

## Effective mana cost for a player spell after applying board discount.
func _effective_spell_cost(spell: SpellCardData) -> int:
	return maxi(0, spell.cost - _spell_mana_discount())

## Effective mana cost for a player trap/rune — reads cost_delta from the hovered card's CardInstance.
## Used for pip-blink preview only; actual play uses pending_play_card.effective_cost().
func _effective_trap_cost(trap: TrapCardData) -> int:
	if _hovered_hand_visual != null and _hovered_hand_visual.card_inst != null:
		return _hovered_hand_visual.card_inst.effective_cost()
	return maxi(0, trap.cost)

## Mana discount applied to all player spells — summed from all minions on board.
## Data-driven via MinionCardData.mana_cost_discount.
func _spell_mana_discount() -> int:
	var discount := 0
	for m in player_board:
		discount += m.card_data.mana_cost_discount
	return discount

## Void Bolt damage per Void Mark stack. Set by CombatSetup (deepened_curse → 50).
func _void_mark_damage_per_stack() -> int:
	return void_mark_damage_per_stack

## Add Void Mark stacks to the enemy hero.
func _apply_void_mark(stacks: int = 1) -> void:
	enemy_void_marks += stacks
	_log("  Void Mark x%d applied! (total: %d)" % [stacks, enemy_void_marks], _LogType.PLAYER)
	_update_enemy_status_panel()

## Deal Void Bolt damage to the enemy hero, scaled by current Void Marks.
## CONVENTION: ALL Void Bolt damage in the game must go through this function
## so that talents like deepened_curse and future modifiers apply automatically.
## Void bolt passives are fired automatically in _on_hero_damaged when type == VOID_BOLT.
func _deal_void_bolt_damage(base_damage: int) -> void:
	var bonus := enemy_void_marks * _void_mark_damage_per_stack()
	var total := base_damage + bonus
	if bonus > 0:
		_log("  Void Bolt: %d dmg (base %d + %d from %d marks)" % [total, base_damage, bonus, enemy_void_marks], _LogType.PLAYER)
	else:
		_log("  Void Bolt: %d damage." % total, _LogType.PLAYER)
	combat_manager.apply_hero_damage("enemy", total, Enums.DamageType.VOID_BOLT)

## Tries to spend a card's costs, respecting the Void Crystal relic.
## Returns true if the card can be played (and costs are deducted).
func _pay_card_cost(essence_cost: int, mana_cost: int) -> bool:
	_stop_pip_blink()
	if relic_first_card_free and "void_crystal" in GameManager.player_relics:
		relic_first_card_free = false
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
	# Capture slot position before clearing for the death animation
	var dead_slot: BoardSlot = null
	var search_slots := player_slots if minion.owner == "player" else enemy_slots
	for s in search_slots:
		if s.minion == minion:
			dead_slot = s
			break

	# Remove from the appropriate board array and clear its slot
	if minion.owner == "player":
		player_board.erase(minion)
		_clear_slot_for(minion, player_slots)
		if hand_display:
			hand_display.refresh_condition_glows(self, turn_manager.essence, turn_manager.mana)
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
	# Death animation — defer if lunge is in progress so ghost positions correctly.
	# Position is captured NOW while the slot is still in its original container.
	if dead_slot:
		if dead_slot.freeze_visuals:
			_deferred_death_slots.append({slot = dead_slot, pos = dead_slot.global_position})
		else:
			_animate_minion_death(dead_slot, dead_slot.global_position)

func _on_hero_damaged(target: String, amount: int, type: Enums.DamageType = Enums.DamageType.PHYSICAL) -> void:
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
			if type == Enums.DamageType.VOID_BOLT and _handlers:
				_handlers._apply_void_bolt_passives()

func _on_hero_healed(target: String, amount: int) -> void:
	if target == "player":
		player_hp = mini(player_hp + amount, GameManager.player_hp_max)
		_update_player_status_panel()
		_log("  You heal %d HP  (HP: %d)" % [amount, player_hp], _LogType.HEAL)
		# Eternal Hunger — deal the healed amount to the enemy hero too
		if "eternal_hunger" in GameManager.player_relics:
			_log("  Eternal Hunger: deal %d damage to enemy hero." % amount, _LogType.PLAYER)
			combat_manager.apply_hero_damage("enemy", amount, Enums.DamageType.SPELL)

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

## Apply VALID_TARGET highlight to every slot in slots where filter returns true.
func _highlight_slots(slots: Array, filter: Callable) -> void:
	for slot in slots:
		if filter.call(slot):
			slot.set_highlight(BoardSlot.HighlightMode.VALID_TARGET)

## Highlight valid target slots for a targeted minion on-play effect (battle cry).
## Step 1 of the two-click flow: player clicks card → sees valid targets highlighted.
## Step 2: player clicks a valid target → pending_minion_target set → placement slots shown.
func _highlight_minion_on_play_targets(card: MinionCardData) -> void:
	_clear_all_highlights()
	var hits_enemy    := card.on_play_target_type in ["enemy_minion", "corrupted_enemy_minion"]
	var hits_friendly := card.on_play_target_type in ["friendly_minion"]
	if hits_enemy:
		_highlight_slots(enemy_slots,  func(s): return not s.is_empty() and _is_valid_minion_on_play_target(s.minion, card.on_play_target_type))
	if hits_friendly:
		_highlight_slots(player_slots, func(s): return not s.is_empty() and _is_valid_minion_on_play_target(s.minion, card.on_play_target_type))

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
	var hits_enemy    := spell.target_type in ["enemy_minion", "any_minion", "enemy_minion_or_hero"]
	var hits_hero     := spell.target_type == "enemy_minion_or_hero"
	if hits_friendly:
		_highlight_slots(player_slots, func(s): return not s.is_empty() and _is_valid_spell_target(s.minion, spell.target_type))
	if hits_enemy:
		_highlight_slots(enemy_slots, func(s): return not s.is_empty())
	if hits_hero and _enemy_status_panel:
		_enemy_status_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_enemy_status_panel.gui_input.connect(_on_enemy_hero_spell_input)
		_start_hero_spell_pulse()

func _is_valid_spell_target(minion: MinionInstance, target_type: String) -> bool:
	match target_type:
		"friendly_human":    return minion.card_data.minion_type == Enums.MinionType.HUMAN
		"friendly_demon":    return minion.card_data.minion_type == Enums.MinionType.DEMON
		"friendly_minion":   return true
		"friendly_void_imp": return _minion_has_tag(minion, "void_imp")
		"enemy_minion":           return true
		"any_minion":             return true
		"enemy_minion_or_hero":   return true
	return false

## Spend mana, resolve the effect on the target, then remove the card
func _apply_targeted_spell(spell: SpellCardData, target: MinionInstance) -> void:
	if not _pay_card_cost(0, _effective_spell_cost(spell)):
		if hand_display:
			hand_display.deselect_current()
		return
	_log("You cast: %s → %s" % [spell.card_name, target.card_data.card_name])
	turn_manager.remove_from_hand(pending_play_card)
	if hand_display:
		hand_display.remove_card(pending_play_card)
		hand_display.deselect_current()
	pending_play_card = null
	_clear_all_highlights()
	var captured_target: MinionInstance = target
	_show_card_cast_anim(spell, false, func() -> void:
		if not spell.effect_steps.is_empty():
			var ctx := EffectContext.make(self, "player")
			ctx.chosen_target = captured_target
			EffectResolver.run(spell.effect_steps, ctx)
		else:
			_resolve_spell_effect(spell.effect_id, captured_target)
		var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
		spell_ctx.card = spell
		trigger_manager.fire(spell_ctx)
	)

## Fired when player clicks the enemy hero panel while targeting a spell with "enemy_minion_or_hero".
func _on_enemy_hero_spell_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if pending_play_card == null or not pending_play_card.card_data is SpellCardData:
		return
	var spell := pending_play_card.card_data as SpellCardData
	if not _pay_card_cost(0, _effective_spell_cost(spell)):
		if hand_display:
			hand_display.deselect_current()
		return
	_log("You cast: %s → Enemy Hero" % spell.card_name)
	turn_manager.remove_from_hand(pending_play_card)
	if hand_display:
		hand_display.remove_card(pending_play_card)
		hand_display.deselect_current()
	pending_play_card = null
	_clear_all_highlights()
	_show_card_cast_anim(spell, false, func() -> void:
		# Compute damage using the same bonus_amount/bonus_conditions logic as EffectResolver._amount
		var base_dmg: int = 0
		for step in spell.effect_steps:
			var s := EffectStep.from_dict(step) if step is Dictionary else step as EffectStep
			if s and s.effect_type == EffectStep.EffectType.DAMAGE_MINION:
				var ctx := EffectContext.make(self, "player")
				if ConditionResolver.check_all(s.conditions, ctx, null):
					base_dmg += s.amount
					if s.bonus_amount != 0 and not s.bonus_conditions.is_empty():
						if ConditionResolver.check_all(s.bonus_conditions, ctx, null):
							base_dmg += s.bonus_amount
		var total: int = base_dmg
		_log("  %s: %d Void damage to enemy hero." % [spell.card_name, total], _LogType.PLAYER)
		combat_manager.apply_hero_damage("enemy", total, Enums.DamageType.SPELL)
		var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
		spell_ctx.card = spell
		trigger_manager.fire(spell_ctx)
	)


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
	if pending_play_card == null or not pending_play_card.card_data is SpellCardData:
		return
	var spell := pending_play_card.card_data as SpellCardData
	if not _pay_card_cost(0, _effective_spell_cost(spell)):
		if hand_display:
			hand_display.deselect_current()
		return
	turn_manager.remove_from_hand(pending_play_card)
	pending_play_card = null
	_tear_down_trap_env_targeting()
	if hand_display:
		hand_display.deselect_current()
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
	_show_card_cast_anim(spell, false, func() -> void:
		var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
		spell_ctx.card = spell
		trigger_manager.fire(spell_ctx)
	)

# ---------------------------------------------------------------------------
# Trap helpers
# ---------------------------------------------------------------------------

## Fire all non-rune traps for owner ("player"/"enemy") whose trigger matches trigger.
## triggering_minion is the relevant minion (attacker, summoned minion, dead minion, etc.).
func _fire_traps_for(owner: String, trigger: int, triggering_minion: MinionInstance = null) -> void:
	var traps: Array = active_traps if owner == "player" else (enemy_ai.active_traps if enemy_ai else [])
	if owner == "enemy" and enemy_ai == null:
		return
	for trap in traps.duplicate():
		if trap.is_rune:
			continue  # Runes are persistent — handled by ritual/aura system
		if trap.trigger != trigger:
			continue
		var slot_idx := traps.find(trap)
		_flash_trap_slot_for(owner, slot_idx)
		_log("⚡ %s%s triggered!" % [("Enemy " if owner == "enemy" else ""), trap.card_name], _LogType.TRAP)
		var captured_trap:   TrapCardData   = trap
		var captured_minion: MinionInstance = triggering_minion
		_show_card_cast_anim(captured_trap, owner == "enemy", func() -> void:
			var ctx := EffectContext.make(self, owner)
			ctx.trigger_minion = captured_minion
			EffectResolver.run(captured_trap.effect_steps, ctx)
			if not captured_trap.reusable:
				traps.erase(captured_trap)
				_update_trap_display_for(owner)
		)

## Flash a trap slot gold to indicate it fired.
func _flash_trap_slot_for(owner: String, slot_idx: int) -> void:
	var panels := trap_slot_panels if owner == "player" else enemy_trap_slot_panels
	if slot_idx >= 0 and slot_idx < panels.size():
		var panel := panels[slot_idx]
		_apply_slot_style(panel, Color(0.35, 0.28, 0.0, 1), Color(1.0, 0.85, 0.1, 1))
		var tw := create_tween()
		tw.tween_interval(0.5)
		tw.tween_callback(func(): _update_trap_display_for(owner))

## Called by EnemyAI's minion_summoned signal.
## slot.place_minion and triggers are deferred until after the reveal animation.
func _on_enemy_minion_summoned(minion: MinionInstance, slot: BoardSlot) -> void:
	_log("Enemy summons: %s" % minion.card_data.card_name, _LogType.ENEMY)
	_update_enemy_status_panel()
	_enemy_summon_reveal_then_land(minion, slot,
		minion.card_data.essence_cost + minion.card_data.mana_cost,
		minion.card_data.is_champion)

## Punch + ripple for an enemy minion landing — no flight, just impact on the slot.
func _animate_enemy_landing(slot: BoardSlot, total_cost: int, is_champion: bool) -> void:
	slot.pivot_offset = slot.size / 2.0
	var t1 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t1.tween_property(slot, "scale", Vector2(1.15, 1.15), 0.06)
	await t1.finished
	if not is_inside_tree(): return
	var t2 := create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t2.tween_property(slot, "scale", Vector2(1.0, 1.0), 0.10)
	await t2.finished
	slot.pivot_offset = Vector2.ZERO
	_spawn_slot_ripple(slot, total_cost, is_champion)

## Sequences reveal → place_minion → triggers → punch+ripple for an enemy summon.
## Empty placeholder stays visible during the reveal; minion appears only after it.
func _enemy_summon_reveal_then_land(minion: MinionInstance, slot: BoardSlot, total_cost: int, is_champion: bool) -> void:
	await _show_enemy_summon_reveal(minion.card_data)
	if not is_inside_tree():
		enemy_summon_reveal_done.emit()  # unblock commit_minion_play
		return
	# Clear the pending reservation and visually place the minion BEFORE emitting
	# enemy_summon_reveal_done, so the AI never acts while slot.minion is still null.
	if enemy_ai:
		enemy_ai._pending_slots.erase(slot)
	if slot:
		slot.place_minion(minion)
	# ON_PLAY effects are resolved by CombatHandlers.on_enemy_minion_played_effect registered in _setup_triggers().
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "enemy")
	ctx.minion = minion
	trigger_manager.fire(ctx)
	# Signal AFTER place_minion — guarantees AI continues only after the slot is occupied.
	enemy_summon_reveal_done.emit()
	if not is_inside_tree(): return
	if slot:
		_animate_enemy_landing(slot, total_cost, is_champion)

## Centre-screen card reveal when an enemy summons a minion.
## Uses the same "combat_preview" size mode as the hover preview.
## Returns after the fade-out so callers can await it.
func _show_enemy_summon_reveal(card: CardData) -> void:
	_enemy_summon_reveal_active = true
	var visual: CardVisual = CARD_VISUAL_SCENE.instantiate()
	visual.apply_size_mode("combat_preview")
	visual.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	visual.z_index       = 20
	visual.z_as_relative = false
	visual.modulate.a    = 0.0
	$UI.add_child(visual)
	visual.setup(card)
	# Centre on screen
	var vp := get_viewport().get_visible_rect().size
	visual.position = vp / 2.0 - visual.size / 2.0

	# Fade in
	var t1 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t1.tween_property(visual, "modulate:a", 1.0, 0.18)
	await t1.finished
	if not is_inside_tree(): visual.queue_free(); _enemy_summon_reveal_active = false; enemy_summon_reveal_done.emit(); return

	# Hold
	await get_tree().create_timer(0.9).timeout
	if not is_inside_tree(): visual.queue_free(); _enemy_summon_reveal_active = false; enemy_summon_reveal_done.emit(); return

	# Fade out
	var t2 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t2.tween_property(visual, "modulate:a", 0.0, 0.22)
	await t2.finished
	visual.queue_free()
	_enemy_summon_reveal_active = false
	# Do NOT emit enemy_summon_reveal_done here — _enemy_summon_reveal_then_land emits
	# it after slot.place_minion() so the AI never acts before the minion is on the board.

## Called by EnemyAI's enemy_spell_cast signal.
func _on_enemy_spell_cast(spell: SpellCardData) -> void:
	_log("Enemy casts: %s" % spell.card_name, _LogType.ENEMY)
	_update_enemy_status_panel()
	# Fire ON_ENEMY_SPELL_CAST BEFORE resolving so Null Seal can set _spell_cancelled.
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "enemy")
	ctx.card = spell
	trigger_manager.fire(ctx)
	var was_cancelled := _spell_cancelled
	_spell_cancelled = false
	if was_cancelled:
		return
	# Capture chosen target before animation; dispatch to the correct EffectContext field by type.
	var chosen = enemy_ai.spell_chosen_target
	enemy_ai.spell_chosen_target = null
	# Show large card preview; resolve effects on impact so damage visuals sync
	_show_card_cast_anim(spell, true, func() -> void:
		if not spell.effect_steps.is_empty():
			var ectx := EffectContext.make(self, "enemy")
			if chosen is MinionInstance:
				ectx.chosen_target = chosen
			else:
				ectx.chosen_object = chosen
			EffectResolver.run(spell.effect_steps, ectx)
		elif not spell.effect_id.is_empty():
			_resolve_spell_effect(spell.effect_id, null, "enemy")
	)

## Called by EnemyAI's trap_placed signal.
func _on_enemy_trap_placed(trap: TrapCardData) -> void:
	if trap.is_rune:
		_log("Enemy places rune: %s" % trap.card_name, _LogType.ENEMY)
	else:
		_log("Enemy sets a trap.", _LogType.ENEMY)
	_update_enemy_status_panel()
	_update_enemy_trap_display()

## Called by EnemyAI's environment_placed signal.
func _on_enemy_environment_placed(env: EnvironmentCardData) -> void:
	_log("Enemy plays environment: %s" % env.card_name, _LogType.ENEMY)
	_update_enemy_status_panel()

func _update_trap_display_for(owner: String) -> void:
	var panels: Array = trap_slot_panels      if owner == "player" else enemy_trap_slot_panels
	var labels: Array = trap_slot_labels      if owner == "player" else enemy_trap_slot_labels
	var traps:  Array = active_traps          if owner == "player" else (enemy_ai.active_traps if enemy_ai else [])
	var is_enemy := owner == "enemy"
	for i in panels.size():
		var panel := panels[i] as Panel
		var lbl   := labels[i] as Label
		if i < traps.size():
			var trap := traps[i] as TrapCardData
			lbl.visible = true
			if trap.is_rune:
				# Rune: face-up, persistent — purple/void colour scheme
				_apply_slot_style(panel, Color(0.10, 0.04, 0.22, 1), Color(0.65, 0.25, 0.90, 1))
				lbl.text = trap.card_name
				panel.tooltip_text = "%s\n─\n%s" % [trap.card_name, trap.description]
			elif is_enemy:
				# Enemy traps are face-down — red scheme with hidden name
				_apply_slot_style(panel, Color(0.14, 0.04, 0.04, 1), Color(0.80, 0.18, 0.18, 1))
				lbl.text = "??"
				panel.tooltip_text = "Enemy Trap"
			else:
				# Player trap: face-down — amber scheme
				_apply_slot_style(panel, Color(0.12, 0.08, 0.05, 1), Color(0.85, 0.45, 0.10, 1))
				lbl.text = trap.card_name
				panel.tooltip_text = "%s\n─\n%s" % [trap.card_name, trap.description]
		else:
			_apply_empty_slot(panel, lbl)
			panel.tooltip_text = ""

func _update_trap_display() -> void:
	_update_trap_display_for("player")

func _update_enemy_trap_display() -> void:
	_update_trap_display_for("enemy")

# ---------------------------------------------------------------------------
# Rune & Ritual system
# ---------------------------------------------------------------------------

## Register 2-rune ritual handlers for the given environment.
## Called when the environment is first played.
func _register_env_rituals(env: EnvironmentCardData) -> void:
	for ritual in env.rituals:
		var r: RitualData = ritual
		var h := func(_ctx: EventContext): _handlers.on_env_ritual(r)
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

## Apply or remove one layer of the Dominion Rune's ATK aura on all friendly Demons.
## active=true adds one bonus entry per-minion; active=false removes one entry per-minion,
## preserving buffs from any other Dominion Runes still on the board.
## amount is passed in from _apply_rune_aura so runic_attunement doubling is respected.
func _refresh_dominion_aura(active: bool, amount: int = 100) -> void:
	for m in player_board:
		if m.card_data.minion_type == Enums.MinionType.DEMON:
			if active:
				BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, amount, "dominion_rune")
			else:
				BuffSystem.remove_one_source(m, "dominion_rune")
			_refresh_slot_for(m)
	if active:
		_log("  Dominion Rune: all friendly Demons gain +%d ATK." % amount, _LogType.PLAYER)
	else:
		_log("  Dominion Rune removed: all friendly Demons lose ATK bonus.", _LogType.PLAYER)

## Talent: rune_caller — draw a random Rune from the player's deck, discounted by 1 mana via cost_delta.
func _draw_rune_from_deck() -> void:
	var runes_in_deck: Array[CardInstance] = []
	for inst in turn_manager.player_deck:
		if inst.card_data is TrapCardData and (inst.card_data as TrapCardData).is_rune:
			runes_in_deck.append(inst)
	if runes_in_deck.is_empty():
		_log("  Rune Caller: no Runes left in deck.", _LogType.PLAYER)
		return
	var chosen: CardInstance = runes_in_deck[randi() % runes_in_deck.size()]
	turn_manager.player_deck.erase(chosen)
	chosen.cost_delta = -1
	turn_manager.add_instance_to_hand(chosen)
	_refresh_hand_spell_costs()
	_log("  Rune Caller: drew %s from deck (costs 1 less mana this turn)." % chosen.card_data.card_name, _LogType.PLAYER)

## Rune aura numeric multiplier. Set by CombatSetup (runic_attunement → 2).
func _rune_aura_multiplier() -> int:
	return rune_aura_multiplier

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


## Create a StyleBoxFlat with uniform border/corner settings.
func _create_stylebox(bg: Color, border: Color, corner_radius: int = 4, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color     = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style

func _apply_slot_style(panel: Panel, bg: Color, border: Color) -> void:
	# Hide empty-slot image if the slot is now occupied/styled
	var img := panel.get_node_or_null("_empty_slot_bg") as TextureRect
	if img:
		img.visible = false
	panel.add_theme_stylebox_override("panel", _create_stylebox(bg, border))

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
	if attackable:
		_start_hero_attack_pulse()
		_enemy_status_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		_stop_hero_attack_pulse()
		_enemy_status_panel.add_theme_stylebox_override("panel", _create_stylebox(Color(0.08, 0.04, 0.13, 0.93), Color(0.55, 0.20, 0.80, 1.0), 6))
		_enemy_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _enemy_hero_attack_hint:
		_enemy_hero_attack_hint.visible = attackable

## Apply green border style (static, no shadow) — used when hero is a valid attack target.
func _apply_hero_attack_style() -> void:
	if _enemy_status_panel == null:
		return
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(6)
	s.bg_color     = Color(0.04, 0.12, 0.05, 0.95)
	s.border_color = Color(0.25, 0.92, 0.40, 1.0)
	s.set_border_width_all(3)
	s.shadow_color = Color(0.25, 0.92, 0.40, 0.45 + _hero_attack_pulse * 0.35)
	s.shadow_size  = int(8.0 + _hero_attack_pulse * 10.0)
	_enemy_status_panel.add_theme_stylebox_override("panel", s)

## Show static green border and wire hover signals for glow-on-hover.
func _start_hero_attack_pulse() -> void:
	_hero_attack_pulse = 0.0
	_apply_hero_attack_style()
	if not _enemy_status_panel.mouse_entered.is_connected(_on_hero_attack_hover_enter):
		_enemy_status_panel.mouse_entered.connect(_on_hero_attack_hover_enter)
		_enemy_status_panel.mouse_exited.connect(_on_hero_attack_hover_exit)

## Remove attack-target style and disconnect hover signals.
func _stop_hero_attack_pulse() -> void:
	if _hero_attack_tween:
		_hero_attack_tween.kill()
		_hero_attack_tween = null
	_hero_attack_pulse = 0.0
	if _enemy_status_panel and _enemy_status_panel.mouse_entered.is_connected(_on_hero_attack_hover_enter):
		_enemy_status_panel.mouse_entered.disconnect(_on_hero_attack_hover_enter)
		_enemy_status_panel.mouse_exited.disconnect(_on_hero_attack_hover_exit)

func _on_hero_attack_hover_enter() -> void:
	if _hero_attack_tween:
		_hero_attack_tween.kill()
	_hero_attack_tween = create_tween().set_loops()
	_hero_attack_tween.tween_method(func(v: float) -> void:
		_hero_attack_pulse = v
		_apply_hero_attack_style(), 0.0, 1.0, 0.5)
	_hero_attack_tween.tween_method(func(v: float) -> void:
		_hero_attack_pulse = v
		_apply_hero_attack_style(), 1.0, 0.0, 0.5)

func _on_hero_attack_hover_exit() -> void:
	if _hero_attack_tween:
		_hero_attack_tween.kill()
		_hero_attack_tween = null
	_hero_attack_pulse = 0.0
	_apply_hero_attack_style()

func _on_enemy_hero_frame_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _enemy_hero_attackable:
			_on_enemy_hero_button_pressed()

# ---------------------------------------------------------------------------
# Enemy hero spell-target pulse
# ---------------------------------------------------------------------------

func _apply_hero_spell_style() -> void:
	if _enemy_status_panel == null:
		return
	var border_w: float = 3.0 + _hero_spell_pulse * 2.5
	var shadow_sz: float = 8.0 + _hero_spell_pulse * 10.0
	var shadow_a: float  = 0.55 + _hero_spell_pulse * 0.30
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(6)
	s.bg_color     = Color(0.08, 0.04, 0.13, 0.93)
	s.border_color = Color(0.20, 0.85, 0.30, 1.0)
	s.set_border_width_all(border_w)
	s.shadow_color = Color(0.20, 0.85, 0.30, shadow_a)
	s.shadow_size  = shadow_sz
	_enemy_status_panel.add_theme_stylebox_override("panel", s)

func _start_hero_spell_pulse() -> void:
	# Apply static border immediately; pulse begins only on hover.
	_hero_spell_pulse = 0.0
	_apply_hero_spell_style()
	if not _enemy_status_panel.mouse_entered.is_connected(_on_hero_spell_hover_enter):
		_enemy_status_panel.mouse_entered.connect(_on_hero_spell_hover_enter)
		_enemy_status_panel.mouse_exited.connect(_on_hero_spell_hover_exit)

func _stop_hero_spell_pulse() -> void:
	if _hero_spell_tween:
		_hero_spell_tween.kill()
		_hero_spell_tween = null
	_hero_spell_pulse = 0.0
	if _enemy_status_panel and _enemy_status_panel.mouse_entered.is_connected(_on_hero_spell_hover_enter):
		_enemy_status_panel.mouse_entered.disconnect(_on_hero_spell_hover_enter)
		_enemy_status_panel.mouse_exited.disconnect(_on_hero_spell_hover_exit)

func _on_hero_spell_hover_enter() -> void:
	if _hero_spell_tween:
		_hero_spell_tween.kill()
	_hero_spell_tween = create_tween().set_loops()
	_hero_spell_tween.tween_method(func(v: float) -> void:
		_hero_spell_pulse = v
		_apply_hero_spell_style(), 0.0, 1.0, 0.5)
	_hero_spell_tween.tween_method(func(v: float) -> void:
		_hero_spell_pulse = v
		_apply_hero_spell_style(), 1.0, 0.0, 0.5)

func _on_hero_spell_hover_exit() -> void:
	if _hero_spell_tween:
		_hero_spell_tween.kill()
		_hero_spell_tween = null
	_hero_spell_pulse = 0.0
	_apply_hero_spell_style()

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
	panel.add_theme_stylebox_override("panel", _create_stylebox(Color(0.08, 0.04, 0.13, 0.93), Color(0.55, 0.20, 0.80, 1), 6))

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

	_build_enemy_portrait_row(vbox, ui_root)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	_build_enemy_stats_cols(vbox)

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

## Build the portrait + name label + passive icon row for the enemy status panel.
func _build_enemy_portrait_row(vbox: VBoxContainer, ui_root: Node) -> void:
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

	if not _active_enemy_passives.is_empty():
		_add_enemy_passive_hover_icon(portrait_row, ui_root)

## Build the two-column stats area (HP/Essence/Mana/Hand + Void Mark row).
func _build_enemy_stats_cols(vbox: VBoxContainer) -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cols)

	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 3)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left_col)

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

	panel.add_theme_stylebox_override("panel", _create_stylebox(Color(0.06, 0.06, 0.14, 0.93), Color(0.35, 0.55, 0.90, 1.0), 6))

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

	# Talent hover icon — shows unlocked talent list on hover
	_add_talent_hover_icon(portrait_row, panel)

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
	_setup_pip_bars(ui_root)
	_update_player_status_panel()

func _update_player_status_panel() -> void:
	if not _player_status_hp_label:
		return
	_player_status_hp_label.text = "❤ HP: %d / %d" % [player_hp, GameManager.player_hp_max]

## Build two vertical pip columns (essence left, mana right) above the player status panel.
## Each column holds MAX_PIPS pip panels; colors are updated by _update_pip_bars().
func _setup_pip_bars(ui_root: Node) -> void:
	const MAX_PIPS      := 10
	const PIP_W         := 20
	const PIP_H         := 22
	const PIP_GAP       := 4
	const PIP_CORNER    := 3
	const COL_GAP       := 12   # gap between the two columns
	const COL_BORDER    := 3    # inner padding inside the outer border panel
	const COL_W         := PIP_W + COL_BORDER * 2   # = 26px
	const COL_H         := MAX_PIPS * PIP_H + (MAX_PIPS - 1) * PIP_GAP  # = 256px
	# MARGIN_BOTTOM = player_panel_top(150) + label_h + gap leaves room below the pips
	const MARGIN_BOTTOM := 196
	const RIGHT_MARGIN  := 15
	const LBL_W         := 44   # fits "10/10" at font 13 with some breathing room
	const LBL_H         := 22
	# Column centres from screen-right edge (used for label centering)
	const MNA_CENTER    := RIGHT_MARGIN + COL_W / 2                     # = 28
	const ESS_CENTER    := RIGHT_MARGIN + COL_W + COL_GAP + COL_W / 2  # = 67

	# Reusable gradient textures: lighter at pip top, deeper at pip bottom
	_ess_pip_tex = _make_pip_gradient_tex(Color(0.72, 0.42, 0.96, 1.0), Color(0.62, 0.06, 0.18, 1.0))
	_mna_pip_tex = _make_pip_gradient_tex(Color(0.40, 0.78, 1.00, 1.0), Color(0.05, 0.18, 0.58, 1.0))
	# Overflow (temp) textures — gold→orange for essence, bright-cyan→teal for mana
	_ess_ovf_tex = _make_pip_gradient_tex(Color(1.00, 0.92, 0.38, 1.0), Color(0.95, 0.48, 0.05, 1.0))
	_mna_ovf_tex = _make_pip_gradient_tex(Color(0.65, 1.00, 1.00, 1.0), Color(0.08, 0.75, 0.90, 1.0))

	# --- Reposition existing scene labels to sit centred under their pip column ---
	# [label, col_center_from_right, font_color]
	for lbl_info in [
		[essence_label, ESS_CENTER, Color(0.78, 0.45, 1.0, 1.0)],
		[mana_label,    MNA_CENTER, Color(0.35, 0.70, 1.0, 1.0)],
	]:
		var lbl := lbl_info[0] as Label
		if lbl == null:
			continue
		var cx: float = float(lbl_info[1] as int)
		lbl.anchor_left              = 1.0
		lbl.anchor_right             = 1.0
		lbl.anchor_top               = 1.0
		lbl.anchor_bottom            = 1.0
		lbl.grow_horizontal          = Control.GROW_DIRECTION_BEGIN
		lbl.grow_vertical            = Control.GROW_DIRECTION_BEGIN
		lbl.offset_right             = -(cx - LBL_W / 2.0)
		lbl.offset_left              = -(cx + LBL_W / 2.0)
		lbl.offset_top               = -float(MARGIN_BOTTOM)
		lbl.offset_bottom            = -(MARGIN_BOTTOM - LBL_H)
		lbl.horizontal_alignment     = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", lbl_info[2] as Color)

	# --- Build two pip columns ---
	for col_idx in 2:
		var is_essence := col_idx == 0
		# col 0 (essence) sits to the LEFT of col 1 (mana)
		var col_right := RIGHT_MARGIN + (1 - col_idx) * (COL_W + COL_GAP)

		# Outer Panel — provides the visible border and receives the glow animation
		var col_panel := Panel.new()
		col_panel.mouse_filter    = Control.MOUSE_FILTER_IGNORE
		col_panel.anchor_left     = 1.0
		col_panel.anchor_right    = 1.0
		col_panel.anchor_top      = 1.0
		col_panel.anchor_bottom   = 1.0
		col_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		col_panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
		col_panel.offset_right    = -float(col_right)
		col_panel.offset_left     = col_panel.offset_right - COL_W
		col_panel.offset_bottom   = -float(MARGIN_BOTTOM)
		col_panel.offset_top      = col_panel.offset_bottom - COL_H
		col_panel.custom_minimum_size = Vector2(COL_W, COL_H)
		ui_root.add_child(col_panel)
		_apply_col_border_style(col_panel, 0.0, true, is_essence)

		if is_essence:
			_ess_col_panel = col_panel
		else:
			_mna_col_panel = col_panel

		# Inner margin to inset pips from the border
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left",   COL_BORDER)
		margin.add_theme_constant_override("margin_right",  COL_BORDER)
		margin.add_theme_constant_override("margin_top",    COL_BORDER)
		margin.add_theme_constant_override("margin_bottom", COL_BORDER)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col_panel.add_child(margin)

		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", PIP_GAP)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(vbox)

		# Spacer at top pushes visible pips to the bottom as max increases
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(spacer)

		# Pips: index 0 = value 10 (top), index 9 = value 1 (bottom)
		for _pip_idx in MAX_PIPS:
			var pip := Panel.new()
			pip.custom_minimum_size   = Vector2(PIP_W, PIP_H)
			pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pip.mouse_filter          = Control.MOUSE_FILTER_IGNORE
			pip.clip_contents         = true
			pip.visible               = false
			pip.add_theme_stylebox_override("panel",
				_create_stylebox(Color(0.10, 0.08, 0.16, 0.85),
					Color(0.28, 0.24, 0.38, 0.65), PIP_CORNER, 1))
			vbox.add_child(pip)

			var tr := TextureRect.new()
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tr.offset_left   =  1.0
			tr.offset_top    =  1.0
			tr.offset_right  = -1.0
			tr.offset_bottom = -1.0
			tr.stretch_mode  = TextureRect.STRETCH_SCALE
			tr.expand_mode   = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tr.texture       = _ess_pip_tex if is_essence else _mna_pip_tex
			tr.visible       = false
			tr.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			pip.add_child(tr)

			if is_essence:
				_pip_essence_panels.append(pip)
				_pip_essence_rects.append(tr)
			else:
				_pip_mana_panels.append(pip)
				_pip_mana_rects.append(tr)

	if turn_manager:
		_update_pip_bars(turn_manager.essence, turn_manager.essence_max,
				turn_manager.mana, turn_manager.mana_max)

## Create a small vertical-gradient texture used for filled pip interiors.
## color_top = colour at the top edge of the pip; color_bot = colour at the bottom edge.
func _make_pip_gradient_tex(color_top: Color, color_bot: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, color_top)
	grad.set_color(1, color_bot)
	var tex := GradientTexture2D.new()
	tex.gradient  = grad
	tex.fill      = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to   = Vector2(0.5, 1.0)
	tex.width     = 4
	tex.height    = 22
	return tex

func _update_pip_bars(essence: int, essence_max: int, mana: int, mana_max: int) -> void:
	const MAX_PIPS     := 10
	const EMPTY_BG       := Color(0.10, 0.08, 0.16, 0.85)
	const EMPTY_BORDER   := Color(0.28, 0.24, 0.38, 0.65)
	const ESS_BORDER     := Color(0.62, 0.32, 0.88, 0.90)
	const MNA_BORDER     := Color(0.22, 0.58, 0.98, 0.90)
	# Overflow (temp) pips use distinct warm/cool accent borders per resource
	const ESS_OVF_BORDER := Color(0.98, 0.80, 0.12, 0.95)   # amber-gold  — essence overflow
	const MNA_OVF_BORDER := Color(0.20, 0.95, 0.88, 0.95)   # cyan-teal   — mana overflow

	if _pip_essence_panels.size() == MAX_PIPS:
		for i in MAX_PIPS:
			# i=0 → value=10 (top), i=9 → value=1 (bottom); bar fills from bottom up.
			var pip_value  := MAX_PIPS - i
			var pip        := _pip_essence_panels[i] as Panel
			var tr         := _pip_essence_rects[i]  as TextureRect
			var visible    := pip_value <= maxi(essence, essence_max)
			var filled     := pip_value <= essence
			var overflow   := filled and pip_value > essence_max
			pip.visible    = visible
			pip.modulate   = Color.WHITE
			tr.modulate    = Color.WHITE
			tr.visible     = filled
			if visible:
				if overflow:
					tr.texture = _ess_ovf_tex
					pip.add_theme_stylebox_override("panel",
						_create_stylebox(Color(0, 0, 0, 0), ESS_OVF_BORDER, 3, 1))
				else:
					tr.texture = _ess_pip_tex
					pip.add_theme_stylebox_override("panel",
						_create_stylebox(
							Color(0, 0, 0, 0) if filled else EMPTY_BG,
							ESS_BORDER if filled else EMPTY_BORDER, 3, 1))

	if _pip_mana_panels.size() == MAX_PIPS:
		for i in MAX_PIPS:
			var pip_value  := MAX_PIPS - i
			var pip        := _pip_mana_panels[i] as Panel
			var tr         := _pip_mana_rects[i]  as TextureRect
			var visible    := pip_value <= maxi(mana, mana_max)
			var filled     := pip_value <= mana
			var overflow   := filled and pip_value > mana_max
			pip.visible    = visible
			pip.modulate   = Color.WHITE
			tr.modulate    = Color.WHITE
			tr.visible     = filled
			if visible:
				if overflow:
					tr.texture = _mna_ovf_tex
					pip.add_theme_stylebox_override("panel",
						_create_stylebox(Color(0, 0, 0, 0), MNA_OVF_BORDER, 3, 1))
				else:
					tr.texture = _mna_pip_tex
					pip.add_theme_stylebox_override("panel",
						_create_stylebox(
							Color(0, 0, 0, 0) if filled else EMPTY_BG,
							MNA_BORDER if filled else EMPTY_BORDER, 3, 1))

## Start a slow blink showing spend (fade filled pips) and/or gain (glow empty pips).
## ess_cost/mana_cost = pips being spent; ess_gain/mna_gain = pips being gained (0 = skip).
func _start_pip_blink(ess_cost: int, mana_cost: int, ess_gain: int = 0, mna_gain: int = 0) -> void:
	_pip_ess_blink = ess_cost
	_pip_mna_blink = mana_cost
	_pip_ess_gain  = ess_gain
	_pip_mna_gain  = mna_gain
	if _pip_blink_tween:
		_pip_blink_tween.kill()
	_pip_blink_phase = 0.0
	_pip_blink_tween = create_tween().set_loops()
	_pip_blink_tween.tween_method(func(v: float) -> void:
			_pip_blink_phase = v
			_refresh_blink_pips(), 0.0, 1.0, 0.55)
	_pip_blink_tween.tween_method(func(v: float) -> void:
			_pip_blink_phase = v
			_refresh_blink_pips(), 1.0, 0.0, 0.55)

## Stop blinking and restore normal pip styles.
func _stop_pip_blink() -> void:
	if _pip_blink_tween:
		_pip_blink_tween.kill()
		_pip_blink_tween = null
	_pip_ess_blink  = 0
	_pip_mna_blink  = 0
	_pip_ess_gain   = 0
	_pip_mna_gain   = 0
	_pip_blink_phase = 0.0
	if turn_manager:
		_update_pip_bars(turn_manager.essence, turn_manager.essence_max,
				turn_manager.mana, turn_manager.mana_max)

## Repaint only the blinking pips based on the current _pip_blink_phase (0→1).
## Called every tween tick — fades spent pips, glows gain pips.
func _refresh_blink_pips() -> void:
	if not turn_manager:
		return
	const MAX_PIPS   := 10
	const ESS_BORDER := Color(0.62, 0.32, 0.88, 0.90)
	const MNA_BORDER := Color(0.22, 0.58, 0.98, 0.90)
	_blink_pip_range(_pip_essence_panels, _pip_essence_rects,
			turn_manager.essence, _pip_ess_blink, MAX_PIPS)
	_blink_pip_range(_pip_mana_panels, _pip_mana_rects,
			turn_manager.mana,    _pip_mna_blink, MAX_PIPS)
	_blink_pip_gain_range(_pip_essence_panels,
			turn_manager.essence, _pip_ess_gain, ESS_BORDER, MAX_PIPS)
	_blink_pip_gain_range(_pip_mana_panels,
			turn_manager.mana,    _pip_mna_gain, MNA_BORDER, MAX_PIPS)

func _blink_pip_range(panels: Array[Panel], rects: Array[TextureRect],
		current: int, cost: int, max_pips: int) -> void:
	if cost <= 0 or panels.size() != max_pips or current <= 0:
		return
	# The topmost filled pips are the ones that will be spent: indices [first, last].
	var first := max_pips - current
	var last  := first + cost - 1
	for i in range(clampi(first, 0, max_pips - 1), clampi(last, 0, max_pips - 1) + 1):
		var pip := panels[i] as Panel
		var tr  := rects[i]  as TextureRect
		if not pip.visible:
			continue
		# Fade only the gradient fill; the pip border stays visible as an empty-pip outline.
		tr.modulate.a = 1.0 - _pip_blink_phase

## Glow empty pips that will be filled by a gain effect (e.g. CONVERT_RESOURCE).
## Pips just above the current fill level pulse with the resource colour.
func _blink_pip_gain_range(panels: Array[Panel], current: int,
		gain: int, border_color: Color, max_pips: int) -> void:
	if gain <= 0 or panels.size() != max_pips:
		return
	# The empty pips that will be filled sit just above current fill.
	var first := max_pips - current - gain
	var last  := max_pips - current - 1
	for i in range(clampi(first, 0, max_pips - 1), clampi(last, 0, max_pips - 1) + 1):
		var pip := panels[i] as Panel
		# Force-show overflow pips that are hidden because they exceed the current max.
		# _update_pip_bars will restore correct visibility when the blink stops.
		pip.visible = true
		# Pulse the empty pip with resource colour to signal incoming gain.
		var s := StyleBoxFlat.new()
		s.bg_color     = Color(border_color.r, border_color.g, border_color.b,
				_pip_blink_phase * 0.30)
		s.border_color = border_color
		s.set_border_width_all(1)
		s.set_corner_radius_all(3)
		s.shadow_color = Color(border_color.r, border_color.g, border_color.b,
				_pip_blink_phase * 0.75)
		s.shadow_size  = int(_pip_blink_phase * 8.0)
		pip.add_theme_stylebox_override("panel", s)

## Apply the border/background style to a pip column's outer Panel.
## `pulse` 0→1 drives the shadow size and border brightness.
## `is_gain` selects green (gain) vs red-orange (spend) glow color.
func _apply_col_border_style(panel: Panel, pulse: float, is_gain: bool, is_essence: bool) -> void:
	var normal_bg     := Color(0.06, 0.05, 0.12, 0.88)
	var normal_border := Color(0.38, 0.28, 0.58, 0.75) if is_essence \
			else Color(0.22, 0.38, 0.72, 0.75)
	var s := StyleBoxFlat.new()
	s.bg_color = normal_bg
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	if pulse > 0.0:
		var glow := Color(0.22, 0.92, 0.35, 1.0) if is_gain \
				else Color(0.98, 0.32, 0.10, 1.0)
		s.border_color = normal_border.lerp(glow, pulse * 0.85)
		s.shadow_color = Color(glow.r, glow.g, glow.b, pulse * 0.75)
		s.shadow_size  = int(pulse * 14.0)
	else:
		s.border_color = normal_border
		s.shadow_size  = 0
	panel.add_theme_stylebox_override("panel", s)

## Animate the pip column border with a gain (green) or spend (red-orange) glow.
## Pulse rises 0→1 in 0.15 s then decays 1→0 in 0.50 s.
func _pulse_pip_col(is_essence: bool, is_gain: bool) -> void:
	var panel := _ess_col_panel if is_essence else _mna_col_panel
	if panel == null:
		return
	if is_essence:
		if _ess_col_tween:
			_ess_col_tween.kill()
	else:
		if _mna_col_tween:
			_mna_col_tween.kill()
	var apply_fn := func(v: float) -> void:
		_apply_col_border_style(panel, v, is_gain, is_essence)
	var tween := create_tween()
	if is_essence:
		_ess_col_tween = tween
	else:
		_mna_col_tween = tween
	tween.tween_method(apply_fn, 0.0, 1.0, 0.15)
	tween.tween_method(apply_fn, 1.0, 0.0, 0.50)

## Build a floating tooltip panel scaffold (PanelContainer → MarginContainer → VBoxContainer).
## Anchors at bottom-left of the viewport. Returns {tip, tip_vbox}.
func _build_hover_tooltip_scaffold(ui_root: Node, min_width: float, bg_color: Color, border_color: Color) -> Dictionary:
	var tip := PanelContainer.new()
	tip.visible             = false
	tip.z_index             = 50
	tip.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	tip.custom_minimum_size = Vector2(min_width, 0)
	tip.add_theme_stylebox_override("panel", _create_stylebox(bg_color, border_color, 6))
	ui_root.add_child(tip)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(margin)
	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 8)
	tip_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(tip_vbox)
	tip.position = Vector2(16.0, 0.0)
	# Label text measurement is deferred to the first layout frame, so
	# get_minimum_size() returns 0-height on the very first hover call.
	# Connect minimum_size_changed so the panel self-sizes as soon as Godot
	# measures the content (typically one frame after being added to the tree).
	tip.minimum_size_changed.connect(func() -> void:
		if not tip.is_inside_tree():
			return
		var ms := tip.get_minimum_size()
		if ms.y > 0:
			tip.size = ms
			tip.position.y = get_viewport().get_visible_rect().size.y - ms.y - 16.0
	)
	return {tip = tip, tip_vbox = tip_vbox}

func _add_talent_hover_icon(parent: HBoxContainer, _anchor_panel: Control) -> void:
	var icon_btn := Label.new()
	icon_btn.text = "✦"
	icon_btn.add_theme_font_size_override("font_size", 14)
	icon_btn.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0, 0.75))
	icon_btn.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	icon_btn.custom_minimum_size = Vector2(18, 18)
	icon_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(icon_btn)

	var ui_root := get_node_or_null("UI")
	if ui_root == null:
		return
	var scaffold := _build_hover_tooltip_scaffold(ui_root, 400, Color(0.05, 0.02, 0.10, 0.97), Color(0.55, 0.30, 0.85, 0.90))
	var tip: PanelContainer = scaffold.tip
	var tip_vbox: VBoxContainer = scaffold.tip_vbox

	# --- Passives section ---
	var hero_data := HeroDatabase.get_hero(GameManager.current_hero)
	if hero_data != null and not hero_data.passives.is_empty():
		var passive_hdr := Label.new()
		passive_hdr.text = "PASSIVES"
		passive_hdr.add_theme_font_size_override("font_size", 13)
		passive_hdr.add_theme_color_override("font_color", Color(0.55, 0.85, 0.65, 1.0))
		passive_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		passive_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(passive_hdr)

		for passive in hero_data.passives:
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 3)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tip_vbox.add_child(row)

			var p_desc := Label.new()
			p_desc.text = passive.description
			p_desc.add_theme_font_size_override("font_size", 12)
			p_desc.add_theme_color_override("font_color", Color(0.65, 0.82, 0.70, 1))
			p_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			p_desc.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			row.add_child(p_desc)

		var passive_sep := HSeparator.new()
		passive_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(passive_sep)

	# --- Talents section ---
	var talents_hdr := Label.new()
	talents_hdr.text = "TALENTS"
	talents_hdr.add_theme_font_size_override("font_size", 13)
	talents_hdr.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0, 1.0))
	talents_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	talents_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_vbox.add_child(talents_hdr)

	if GameManager.unlocked_talents.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No talents unlocked"
		none_lbl.add_theme_font_size_override("font_size", 13)
		none_lbl.add_theme_color_override("font_color", Color(0.55, 0.52, 0.60, 1))
		none_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(none_lbl)
	else:
		for tid in GameManager.unlocked_talents:
			var td: TalentData = TalentDatabase.get_talent(tid)
			if td == null:
				continue
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 3)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tip_vbox.add_child(row)

			var t_name := Label.new()
			t_name.text = td.talent_name
			t_name.add_theme_font_size_override("font_size", 15)
			t_name.add_theme_color_override("font_color", Color(0.92, 0.85, 1.0, 1))
			t_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t_name.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			row.add_child(t_name)

			var t_desc := Label.new()
			t_desc.text = td.description
			t_desc.add_theme_font_size_override("font_size", 12)
			t_desc.add_theme_color_override("font_color", Color(0.65, 0.62, 0.72, 1))
			t_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t_desc.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			row.add_child(t_desc)

	icon_btn.mouse_entered.connect(func() -> void:
		icon_btn.add_theme_color_override("font_color", Color(0.90, 0.70, 1.0, 1.0))
		# PanelContainer in CanvasLayer has no parent Container to set its size —
		# force it to its content minimum size each time it is shown.
		tip.size = tip.get_minimum_size()
		tip.position.y = get_viewport().get_visible_rect().size.y - tip.size.y - 16.0
		tip.visible = true
	)
	icon_btn.mouse_exited.connect(func() -> void:
		icon_btn.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0, 0.75))
		tip.visible = false
	)

func _add_enemy_passive_hover_icon(parent: HBoxContainer, ui_root: Node) -> void:
	const PASSIVE_INFO: Dictionary = {
		"feral_instinct": {
			"name": "Feral Instinct",
			"desc": "The first Feral Imp summoned each turn gains: draw 1 card on death."
		},
		"pack_instinct": {
			"name": "Pack Instinct",
			"desc": "Each Feral Imp gains +1 ATK for every other Feral Imp on the board."
		},
		"corrupted_death": {
			"name": "Corrupted Death",
			"desc": "When a Void-Touched Imp dies, apply 1 Corruption to all player minions."
		},
		"ancient_frenzy": {
			"name": "Ancient Frenzy",
			"desc": "Pack Frenzy also grants all Feral Imps Lifedrain for the turn, and costs 1 less Mana. Starts with one extra Pack Frenzy in hand."
		},
	}

	var icon_btn := Label.new()
	icon_btn.text = "◉"
	icon_btn.add_theme_font_size_override("font_size", 13)
	icon_btn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.30, 0.75))
	icon_btn.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	icon_btn.custom_minimum_size = Vector2(18, 18)
	icon_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(icon_btn)

	var scaffold := _build_hover_tooltip_scaffold(ui_root, 300, Color(0.06, 0.02, 0.10, 0.97), Color(0.75, 0.35, 0.20, 0.90))
	var tip: PanelContainer = scaffold.tip
	var tip_vbox: VBoxContainer = scaffold.tip_vbox

	var hdr := Label.new()
	hdr.text = "ENEMY PASSIVES"
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", Color(1.0, 0.60, 0.25, 1.0))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_vbox.add_child(hdr)

	for pid in _active_enemy_passives:
		var info: Dictionary = PASSIVE_INFO.get(pid, {})
		var p_name: String = info.get("name", pid) as String
		var p_desc: String = info.get("desc", "") as String

		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_vbox.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = p_name
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.50, 1.0))
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_lbl)

		if p_desc != "":
			var desc_lbl := Label.new()
			desc_lbl.text = p_desc
			desc_lbl.add_theme_font_size_override("font_size", 12)
			desc_lbl.add_theme_color_override("font_color", Color(0.78, 0.65, 0.55, 1.0))
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			row.add_child(desc_lbl)

	icon_btn.mouse_entered.connect(func() -> void:
		icon_btn.add_theme_color_override("font_color", Color(1.0, 0.70, 0.40, 1.0))
		# PanelContainer in CanvasLayer has no parent Container to set its size —
		# force it to its content minimum size each time it is shown.
		tip.size = tip.get_minimum_size()
		tip.position.y = get_viewport().get_visible_rect().size.y - tip.size.y - 16.0
		tip.visible = true
	)
	icon_btn.mouse_exited.connect(func() -> void:
		icon_btn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.30, 0.75))
		tip.visible = false
	)

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

func _show_large_preview(card_data: CardData, source_visual: CardVisual = null) -> void:
	if not _large_preview or not card_data:
		return
	_large_preview.setup(card_data)
	_large_preview.enable_tooltip()
	var extra := -(source_visual.card_inst.cost_delta) if source_visual != null and source_visual.card_inst != null else 0
	_large_preview.apply_cost_discount(_spell_mana_discount() + extra)
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
	# Grant shards: 3 for boss fights, 1 for normal fights
	var _shard_amount := 3 if GameManager.run_node_index in GameManager.BOSS_INDICES else 1
	GameManager.earn_shards(_shard_amount)
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

## Flash + dissolve upward death animation.
## Spawns a ghost overlay in $UI so the HBoxContainer layout is never disturbed.
## pos must be passed explicitly — do NOT read slot.global_position here, as the slot
## may have just been reparented and layout recalculation is deferred to the next frame.
func _animate_minion_death(slot: BoardSlot, pos: Vector2) -> void:
	var sz := slot.size
	# White flash layer — briefly bright, then transitions to soft purple as it rises
	var ghost := ColorRect.new()
	ghost.color = Color(1.0, 1.0, 1.0, 0.85)
	ghost.z_index = 5
	ghost.z_as_relative = false
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(ghost)
	ghost.set_size(sz)
	ghost.pivot_offset = sz / 2.0
	ghost.global_position = pos

	# Step 1 — white flash: hold briefly then fade
	var t1 := create_tween().set_trans(Tween.TRANS_SINE)
	t1.tween_property(ghost, "modulate:a", 0.0, 0.20)
	await t1.finished
	if not is_inside_tree(): ghost.queue_free(); return

	# Reset for soul-rise: soft purple, drift upward 50px while fading out
	ghost.modulate.a = 0.85
	ghost.color = Color(0.72, 0.52, 1.0, 1.0)  # abyss purple

	var t2 := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t2.tween_property(ghost, "global_position:y", ghost.global_position.y - 50.0, 0.65)
	t2.tween_property(ghost, "modulate:a", 0.0, 0.65)
	await t2.finished
	ghost.queue_free()

func _clear_all_highlights() -> void:
	for slot in player_slots:
		slot.clear_highlight()
	for slot in enemy_slots:
		slot.clear_highlight()
	if _enemy_status_panel and _enemy_status_panel.gui_input.is_connected(_on_enemy_hero_spell_input):
		_enemy_status_panel.gui_input.disconnect(_on_enemy_hero_spell_input)
		_stop_hero_spell_pulse()
		_show_hero_button(_enemy_hero_attackable)

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
		# Fire death animations that were deferred because freeze_visuals blocked them.
		# Use the pre-captured position — slot may not be laid out yet after reparenting.
		var pending := _deferred_death_slots.duplicate()
		_deferred_death_slots.clear()
		for entry in pending:
			_animate_minion_death(entry.slot, entry.pos)
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

## Show a large centred card visual when a spell/trap/environment is cast or triggered.
## Animates in → calls on_impact → holds → fades out.
## Pass Callable() for on_impact when there are no effects to delay.
func _show_card_cast_anim(card: CardData, is_enemy: bool, on_impact: Callable) -> void:
	var cv: CardVisual = CARD_VISUAL_SCENE.instantiate() as CardVisual
	cv.apply_size_mode("combat_preview")
	cv.z_index = 100
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(cv)
	# setup() must be called AFTER add_child so _ready() has run and child nodes exist
	cv.setup(card)
	# Centre on screen
	var vp      := get_viewport().get_visible_rect().size
	var card_sz := Vector2(336.0, 504.0)
	cv.position     = (vp - card_sz) * 0.5
	cv.pivot_offset = card_sz * 0.5
	cv.modulate = Color(1.0, 1.0, 1.0, 0.0)  # start transparent, natural colours
	cv.scale = Vector2(0.65, 0.65)
	var tw := create_tween()
	# Animate in
	tw.set_parallel(true)
	tw.tween_property(cv, "modulate:a", 1.0, 0.22)
	tw.tween_property(cv, "scale", Vector2(1.0, 1.0), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(0.08)
	# Impact: resolve effects, flash, damage numbers
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
	_refresh_slot_for(target)
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
	# Rise quickly at first, then ease to a stop over 1.6s total.
	# Clamp the endpoint so the label never scrolls above a 16 px top margin.
	var rise_end_y := maxf(lbl.position.y - 90.0, 16.0)
	tw.tween_property(lbl, "position:y", rise_end_y, 1.6) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	# Stay fully visible for 0.9s then fade out over 0.7s
	tw.tween_property(lbl, "modulate:a", 1.0, 0.9)
	tw.chain().tween_property(lbl, "modulate:a", 0.0, 0.7)
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
	_highlight_slots(player_slots, func(s): return s.is_empty())

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
#   1. Write a handler method in CombatHandlers.gd:  func on_my_thing(ctx: EventContext) -> void
#   2. Register it here:  trigger_manager.register(EVENT, _handlers.on_my_thing, priority)
#   3. Fire the event from the appropriate CombatScene callsite if it doesn't exist yet.
# ===========================================================================

func _setup_triggers() -> void:
	_handlers = CombatHandlers.new()
	_handlers.setup(self)

	# Load active enemy passives before anything else
	if GameManager.current_enemy != null:
		_active_enemy_passives = GameManager.current_enemy.passives.duplicate()

	# ── Live-only always-on handlers ─────────────────────────────────────────
	# Priority guide: 0=relics, 5=enemy passives, 10=environment, 21+=minion passives, 30=traps/synergies
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TURN_START,    _handlers.on_player_turn_relics,           0)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST,    _handlers.on_void_archmagus_spell,         0)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, _handlers.on_player_minion_played_effect,  10)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, _handlers.on_summon_relic,               10)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, _handlers.on_summon_board_synergies,     30)
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED,  _handlers.on_enemy_minion_played_effect,  5)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_DIED,    _trap_check_friendly_death,               20)
	# Trap routing — scene-specific methods bridging events to _fire_traps_for()
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_TURN_START,      _trap_check_enemy_turn_start,             30)
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, _trap_check_enemy_summon,                 30)
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST,      _trap_check_enemy_spell,                  30)
	trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_ATTACK,          _trap_check_enemy_attack,                 30)
	trigger_manager.register(Enums.TriggerEvent.ON_HERO_DAMAGED,          _trap_check_damage_taken,                 10)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, _enemy_trap_check_player_summon,         35)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST,      _enemy_trap_check_player_spell,          35)
	trigger_manager.register(Enums.TriggerEvent.ON_PLAYER_TURN_START,      _enemy_trap_check_player_turn_start,     35)

	# ── ancient_frenzy hand injection (live-only side effect) ─────────────────
	if "ancient_frenzy" in _active_enemy_passives:
		var pf_card := CardDatabase.get_card("pack_frenzy")
		if pf_card:
			enemy_ai.hand.append(CardInstance.create(pf_card))

	# ── Shared: talents, hero passives, enemy passives via registry ───────────
	var hero_passive_ids: Array[String] = []
	var hero := HeroDatabase.get_hero(GameManager.current_hero)
	if hero:
		for p in hero.passives:
			hero_passive_ids.append(p.id)

	CombatSetup.new().setup(
		trigger_manager, _handlers, self,
		GameManager.unlocked_talents,
		hero_passive_ids,
		_active_enemy_passives
	)

# ---------------------------------------------------------------------------
# Trap routing stubs — bridge TriggerManager events to _fire_traps_for()
# ---------------------------------------------------------------------------

func _trap_check_enemy_turn_start(ctx: EventContext) -> void:
	_fire_traps_for("player", ctx.event_type)

func _trap_check_friendly_death(ctx: EventContext) -> void:
	# Traps that react to friendly death only fire during the enemy's turn
	if not turn_manager.is_player_turn:
		_fire_traps_for("player", ctx.event_type, ctx.minion)

func _trap_check_enemy_summon(ctx: EventContext) -> void:
	_fire_traps_for("player", ctx.event_type, ctx.minion)

func _trap_check_enemy_spell(ctx: EventContext) -> void:
	_fire_traps_for("player", ctx.event_type)

func _trap_check_enemy_attack(ctx: EventContext) -> void:
	_fire_traps_for("player", ctx.event_type, ctx.minion)

func _trap_check_damage_taken(ctx: EventContext) -> void:
	_fire_traps_for("player", ctx.event_type)

func _enemy_trap_check_player_summon(ctx: EventContext) -> void:
	_fire_traps_for("enemy", ctx.event_type, ctx.minion)

func _enemy_trap_check_player_spell(_ctx: EventContext) -> void:
	_fire_traps_for("enemy", Enums.TriggerEvent.ON_PLAYER_SPELL_CAST)

func _enemy_trap_check_player_turn_start(_ctx: EventContext) -> void:
	_fire_traps_for("enemy", Enums.TriggerEvent.ON_PLAYER_TURN_START)
