## CombatScene.gd
## The live combat shell: presenter + input + wiring (plan 4). Every gameplay
## field and rule is on `state` (CombatState, built by setup_combat); player
## input goes through its cmd_* commands; the presenter plays the journal. The
## scene owns the node refs, transient selection state, the animation bodies the
## presenter awaits, and the helpers (input, UI, targeting, VFX bridge) that
## read `state` directly.
extends Node2D

const CARD_VISUAL_SCENE := preload("res://combat/ui/CardVisual.tscn")
const DAMAGE_FONT: Font = preload("res://assets/fonts/cinzel/Cinzel-Bold.ttf")

## The combat engine — every gameplay read and write.
var state: CombatState = CombatState.new()
## Plays the journal (plan 3.2): one animation per event, lagging ViewState, UI refresh.
var presenter: CombatPresenter = null
## Emitted by _on_buff_vfx_finished when the last BuffApplyVFX of a batch ends.
signal buff_vfx_batch_done()

var enemy_turn: EnemyTurnRunner

## Deferred by _on_hero_damaged after a P1→P2 transition. Runs next frame so
## the current damage/attack resolution can finish before we yank player
## control. Ends the player turn and lets the normal enemy-turn pipeline fire.
func _force_end_player_turn_for_phase_transition() -> void:
	if state._combat_ended:
		return
	if not state.is_player_turn:
		return  # already flipped (double-defer safety)
	# Cancel any in-flight player-side selection so no stale state bleeds
	# into the enemy turn or P2.
	selected_attacker = null
	pending_play_card = null
	pending_minion_target = null
	_awaiting_minion_target = false
	if hand_display:
		hand_display.deselect_current()
	_clear_all_highlights()
	# End the turn — the state emits turn_ended then turn_started for the enemy,
	# which routes through _on_turn_started and kicks off enemy_turn.run_turn().
	state.cmd_end_turn("player")
## Board slot *views* (plan 3.1a). Gameplay occupancy is `state.player_slots`
## / `state.enemy_slots` (SlotState); these Panels mirror it via
## `_on_slot_changed` and are what VFX / targeting anchor to.
var player_slots: Array[BoardSlot] = []
var enemy_slots:  Array[BoardSlot] = []

# UI nodes
var essence_label: Label
var mana_label: Label
var end_turn_essence_button: Button
var end_turn_mana_button: Button
var end_turn_button: Button  # shown at soft cap instead of the two-choice buttons
var fight_label: Label
var hand_display: HandDisplay
var trap_env_display := TrapEnvDisplay.new()
# Public mirror of the trap_env_display arrays — RelicEffects reads
# trap_slot_panels.size() to enforce slot cap. Pointed at the display's
# arrays in _find_nodes() after setup().
var trap_slot_panels: Array[Panel] = []
var enemy_trap_slot_panels: Array[Panel] = []
var turn_label: Label
var deck_count_label: Label
var game_over_panel: Panel
var game_over_label: Label
var restart_button: Button
var combat_log := CombatLog.new()
# _large_preview moved into LargePreview.gd (large_preview.visual)

## Re-entrancy guard for _do_end_turn — set true while we're awaiting in-flight
## VFX and tearing down the turn. Prevents a second click from queuing another
## end_player_turn() while the first is still in progress.
var _end_turn_in_progress: bool = false

# Enemy hero status panel
var _enemy_hero_panel: EnemyHeroPanel = null
var _enemy_status_panel: Control = null   ## alias → _enemy_hero_panel (backward-compat)

# Player hero status panel
var _player_hero_panel: PlayerHeroPanel = null
var _player_status_panel: Control = null  ## alias → _player_hero_panel (backward-compat)

# Pip bar (essence + mana columns)
var _pip_bar: PipBar = null
var _prev_essence: int = -1
var _prev_mana:    int = -1

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _relic_bar: RelicBar

## Centralised VFX dispatcher — resolved in _find_nodes. All spell/apply VFX
## should be parented via vfx_controller.spawn(vfx) so they render on VfxLayer
## (CanvasLayer layer=2, above UI).
var vfx_controller: VfxController = null
var _vfx_layer: CanvasLayer = null
var _vfx_shake_root: Control = null

## Compound VFX (sigil summons, summon reveals, death animations, projectiles
## etc.) live on the bridge so this scene file isn't 6,000 lines of `create_tween`
## chains. Set up in _ready alongside vfx_controller. Scene methods that used
## to inline VFX delegate via vfx_bridge.X(...).
var vfx_bridge: CombatVFXBridge = null

## Click/hover/select/target chain owner. Scene's `_on_*` signal handlers
## stay as thin wrappers that delegate here. See CombatInputHandler.gd.
var input_handler: CombatInputHandler = null

## Signal-driven UI refresh subscribers (state / CombatManager / TurnManager
## / BuffSystem signals → hero panel / pip bar / combat log / trap display
## updates). Scene's `_on_*` subscribers stay as thin wrappers that delegate
## here so signal connections don't have to change. See CombatUI.gd.
var combat_ui: CombatUI = null

# Live boards

# Hero HP

# Currently selected attacker (if player clicked one of their minions)
var selected_attacker: MinionInstance = null

# Card the player is currently trying to play (dragged or clicked from hand)
var pending_play_card: CardInstance = null

# Player-chosen target for targeted on-play effects (set after clicking a valid target,
# before clicking the placement slot). Cleared after the minion is placed or deselected.
var pending_minion_target: MinionInstance = null

# True while waiting for the player to click a valid target before choosing a placement slot.
# False when no valid targets existed (skip straight to placement) or after target is chosen.
var _awaiting_minion_target: bool = false

# Relic targeting — set when a relic (e.g. Blood Chalice) needs the player to pick a target.
# Stores the effect_id; cleared after the target is chosen or cancelled.
var _pending_relic_target: String = ""
var _pending_relic_index: int = -1  ## Relic awaiting a target (Blood Chalice) — activated once one is picked

# Active global environment — forwarded to state.active_environment.

# Active traps and runes (shared pool, max 3 slots) — forwarded to state.active_traps.
# Callables registered for the current environment's 2-rune rituals.
# Cleared and re-populated whenever the active environment changes.
# TriggerManager Callables registered per rune placement.
# Stored as an Array of {rune_id, entries} so two runes of the same type each
# get an independent entry and can be individually unregistered.

# ---------------------------------------------------------------------------
# Relic state — reset each combat
# ---------------------------------------------------------------------------

## True until the first card is played this turn (Void Crystal: first card free)
## (Removed: relic_first_card_free — old passive relic system replaced by activated relics)

# ---------------------------------------------------------------------------
# Talent state — reset each combat
# ---------------------------------------------------------------------------

## Seris — Corrupt Flesh activated ability. `_seris_corrupt_targeting` is true while
## the player is picking a friendly Demon to corrupt; `_seris_corrupt_used_this_turn`
## enforces the 1-per-turn cap. Reset to false on each ON_PLAYER_TURN_START.
var _seris_corrupt_targeting: bool = false

## Targeting helper — owns the on-play prompt label, target validation, and
## slot highlighting. CombatScene keeps thin facades for play-card flow.
var targeting: Targeting = null

## Bottom-left card preview shown on hand/board hover.
var large_preview: LargePreview = null

## Panel styles and hero-panel hover tooltips (CombatUiStyle).
var ui_style: CombatUiStyle = null

## "Your next spell will be COUNTERED" warning label.
var counter_warning: CounterWarning = null

## Persistent warning label shown when the player's next spell will be countered.
# _counter_warning_label moved into CounterWarning.gd (counter_warning.label)

## Transient prompt label shown during on-play target selection (required or
## optional). Text comes from MinionCardData.on_play_target_prompt. Shared
## across all targeted-play cards.
# _target_prompt_label moved into Targeting.gd (targeting.prompt_label)

## Currently hovered hand card visual — used for pip-blink cost preview.
var _hovered_hand_visual: CardVisual = null

# ---------------------------------------------------------------------------
# Enemy passive state — populated from GameManager.current_enemy.passives
# ---------------------------------------------------------------------------

# Act 2 champion state

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# If no run is active (e.g. launched directly for testing), start one now.
	if not GameManager.run_active:
		GameManager.start_new_run()
	# The one setup path (plan 4.1): seed, heroes, passives, decks, opening hands,
	# triggers and relics. The presenter plays everything it journaled.
	state.setup_combat(CombatConfig.from_game_manager())
	presenter = CombatPresenter.new()
	presenter.name = "Presenter"
	add_child(presenter)
	presenter.setup(self, state)
	targeting = Targeting.new(self)
	large_preview = LargePreview.new(self)
	counter_warning = CounterWarning.new(self)
	ui_style = CombatUiStyle.new(self)
	_find_nodes()
	_register_buff_preludes()
	_load_combat_background()
	_connect_turn_signals()
	_connect_board_slots()
	_connect_ui()
	# UI refresh is driven by the presenter as it plays the journal (plan 3.2);
	# the initial display refresh calls below journal their events.
	state._update_environment_display()
	state._update_trap_display()
	state._update_enemy_trap_display()
	if GameManager.current_enemy != null and fight_label:
		fight_label.text = "Fight %d / %d" % [GameManager.run_node_index, GameManager.TOTAL_FIGHTS]
	_setup_enemy_turn()
	var ui_root: Node = get_node_or_null("UI")
	_enemy_hero_panel = EnemyHeroPanel.new()
	_enemy_hero_panel.setup(self, ui_root)
	if ui_root:
		ui_root.add_child(_enemy_hero_panel)
	_enemy_status_panel = _enemy_hero_panel
	_enemy_hero_panel.hero_pressed.connect(_on_enemy_hero_button_pressed)
	_player_hero_panel = PlayerHeroPanel.new()
	_player_hero_panel.setup(self, ui_root)
	if ui_root:
		ui_root.add_child(_player_hero_panel)
	_player_status_panel = _player_hero_panel
	# Initial panel sync — the setup's HP events journaled before the panels
	# existed, so push the values once; later changes arrive through the presenter.
	_player_hero_panel.update(state.player_hp, state.player_hp_max)
	_enemy_hero_panel.update(state.enemy_hp, state.enemy_hp_max, state, state.enemy_void_marks)
	_setup_second_wind_indicator(ui_root)
	_pip_bar = PipBar.new()
	_pip_bar.setup(self, ui_root, essence_label, mana_label)
	large_preview.setup()
	state._log("Seed: %d" % state.rng_seed, CombatLog.LogType.TURN)
	_setup_relics()
	state.start_combat()
	_cheat = CheatPanel.new()
	add_child(_cheat)
	_cheat.setup(self)
	if TestConfig.enabled:
		_apply_test_config.call_deferred()

func _load_combat_background() -> void:
	const ACT_BACKGROUNDS := [
		"res://assets/art/progression/backgrounds/a1_combat.png",
		"res://assets/art/progression/backgrounds/a2_combat.png",
		"res://assets/art/progression/backgrounds/a3_combat.png",
		"res://assets/art/progression/backgrounds/a4_combat.png",
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
	enemy_turn             = $EnemyTurnRunner
	enemy_turn.scene       = self
	vfx_controller          = $VfxController
	_vfx_layer              = $VfxLayer
	_vfx_shake_root         = $VfxLayer/VfxShakeRoot
	vfx_controller.setup(self, _vfx_layer, _vfx_shake_root)
	vfx_bridge = CombatVFXBridge.new()
	vfx_bridge.name = "VfxBridge"
	add_child(vfx_bridge)
	vfx_bridge.setup(self, state, vfx_controller)
	input_handler = CombatInputHandler.new()
	input_handler.name = "InputHandler"
	add_child(input_handler)
	input_handler.setup(self, state)
	combat_ui = CombatUI.new()
	combat_ui.name = "CombatUI"
	add_child(combat_ui)
	combat_ui.setup(self, state)
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
	trap_env_display.setup(self)
	# Mirror the display's panel arrays so external callers (RelicEffects) can
	# still read trap_slot_panels.size() to determine slot cap.
	trap_slot_panels = trap_env_display.player_panels
	enemy_trap_slot_panels = trap_env_display.enemy_panels
	turn_label      = $UI/TurnLabel      if has_node("UI/TurnLabel")      else null
	deck_count_label = $UI/DeckSlot/DeckCountLabel if has_node("UI/DeckSlot/DeckCountLabel") else null
	game_over_panel   = $UI/GameOverPanel
	game_over_label   = $UI/GameOverPanel/GameOverLabel
	restart_button    = $UI/GameOverPanel/RestartButton
	combat_log.setup(self)
	for i in 5:
		player_slots.append($UI/PlayerBoard.get_child(i) as BoardSlot)
		enemy_slots.append($UI/EnemyBoard.get_child(i) as BoardSlot)
	# Counter-spell warning label — owned by CounterWarning helper.
	counter_warning.setup()
	# On-play target-selection prompt — owned by Targeting helper.
	targeting.setup()

# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

## The live enemy: EnemyTurnRunner drives a StateAgent on the state (plan 3.4). Its deck
## and passives came from setup_combat; the growth hook is its profile's curve.
func _setup_enemy_turn() -> void:
	enemy_turn.scene = self
	enemy_turn.ai_profile = state.enemy_profile_id
	state.enemy_profile_changed.connect(func(id: String) -> void: enemy_turn.ai_profile = id)
	# Enemy resource growth runs inside state.begin_turn("enemy"); the opening
	# 1 Essence / 1 Mana is set by state.start_combat.
	state.growth_hooks["enemy"] = enemy_turn.grow_at_turn_start

func _connect_turn_signals() -> void:
	state.turn_started.connect(func(side: String, _turn: int) -> void: _on_turn_started(side == "player"))
	state.turn_ended.connect(func(side: String) -> void: _on_turn_ended(side == "player"))

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
		hand_display.card_anim_finished.connect(_on_card_anim_finished)
		hand_display.card_deselected.connect(_on_hand_card_deselected)
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	_connect_trap_and_env_hover()

func _connect_trap_and_env_hover() -> void:
	for i in trap_slot_panels.size():
		trap_slot_panels[i].mouse_entered.connect(_on_trap_slot_hover.bind(i))
		trap_slot_panels[i].mouse_exited.connect(_hide_large_preview)
	for i in enemy_trap_slot_panels.size():
		enemy_trap_slot_panels[i].mouse_entered.connect(_on_enemy_trap_slot_hover.bind(i))
		enemy_trap_slot_panels[i].mouse_exited.connect(_hide_large_preview)
	var env_slot := trap_env_display.env_slot
	if env_slot:
		env_slot.mouse_entered.connect(func() -> void:
			if state.active_environment:
				_show_large_preview(state.active_environment))
		env_slot.mouse_exited.connect(_hide_large_preview)

func _on_trap_slot_hover(idx: int) -> void:
	if input_handler != null:
		input_handler.on_trap_slot_hover(idx)

func _on_enemy_trap_slot_hover(idx: int) -> void:
	if input_handler != null:
		input_handler.on_enemy_trap_slot_hover(idx)

# ---------------------------------------------------------------------------
# Turn events
# ---------------------------------------------------------------------------

## UI half of a turn start — the state's begin_turn already ran the gameplay
## (growth, refill, draw, resets, ON_*_TURN_START). Kicks off the enemy's turn.
func _on_turn_started(is_player_turn: bool) -> void:
	if end_turn_essence_button:
		end_turn_essence_button.disabled = not is_player_turn
	if end_turn_mana_button:
		end_turn_mana_button.disabled = not is_player_turn
	if end_turn_button:
		end_turn_button.disabled = not is_player_turn
	_refresh_end_turn_mode()
	# Update turn counter and remaining deck count
	if turn_label:
		turn_label.text = "Turn %d  |  Deck: %d" % [state.turn_number, state.player_deck.size()]
	if deck_count_label:
		deck_count_label.text = "%d cards" % state.player_deck.size()
	if is_player_turn:
		_refresh_hand_spell_costs()
		if _relic_bar:
			_relic_bar.refresh()
		return
	if state._combat_ended:
		return
	# The enemy acts only once everything the player did has been shown.
	await presenter.pump_and_wait_idle()
	if not is_inside_tree() or state._combat_ended:
		return
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree() or state._combat_ended:
		return
	enemy_turn.run_turn()

## UI half of a turn end — the state's end_turn fired ON_*_TURN_END and cleaned up.
func _on_turn_ended(_is_player_turn: bool) -> void:
	_clear_all_highlights()
	_enemy_hero_panel.show_attackable(false)
	selected_attacker = null
	pending_play_card = null

func _refresh_end_turn_mode() -> void:
	if combat_ui != null:
		combat_ui.refresh_end_turn_mode()

func _on_card_anim_finished() -> void:
	if combat_ui != null:
		combat_ui.on_card_anim_finished()

func _on_end_turn_essence_pressed() -> void:
	_do_end_turn("essence")

func _on_end_turn_mana_pressed() -> void:
	_do_end_turn("mana")

## End the player turn. If any animation/VFX is mid-flight (player spell, minion
## on-play VFX, death animations), wait for it to finish first — otherwise the
## enemy turn can begin before the spell's effect resolution lands, letting
## enemies that the spell would have killed still take actions.
##
## `growth` is "essence", "mana", or "" — picks which resource pool grows on
## turn end. Folded in here (rather than the button handlers) so the
## re-entrancy guard covers spam-clicks during VFX.
func _do_end_turn(growth: String = "") -> void:
	if _end_turn_in_progress:
		return
	if not state.is_player_turn:
		return
	_end_turn_in_progress = true
	# Everything the player did is shown before the turn passes.
	await presenter.pump_and_wait_idle()
	# Combat may have ended while we were awaiting (lethal spell on enemy hero).
	if state._combat_ended:
		_end_turn_in_progress = false
		return
	if not state.is_player_turn:
		_end_turn_in_progress = false
		return
	selected_attacker = null
	pending_play_card = null
	pending_minion_target = null
	_awaiting_minion_target = false
	if hand_display:
		hand_display.deselect_current()
	# The growth pick applies when the player's next turn begins (D10).
	state.cmd_end_turn("player", growth)
	_end_turn_in_progress = false

# ---------------------------------------------------------------------------
# Hand card selection
# ---------------------------------------------------------------------------

## Hand-card chain delegated to input_handler. Scene wrappers preserve the
## external API (signal connections in _connect_ui still target these methods).
func _on_hand_card_selected(inst: CardInstance) -> void:
	if input_handler != null:
		input_handler.on_hand_card_selected(inst)

func _on_hand_card_hovered(card_data: CardData, visual: CardVisual) -> void:
	if input_handler != null:
		input_handler.on_hand_card_hovered(card_data, visual)

func _on_hand_card_unhovered() -> void:
	if input_handler != null:
		input_handler.on_hand_card_unhovered()

func _begin_spell_select(spell: SpellCardData) -> void:
	if input_handler != null:
		input_handler.begin_spell_select(spell)

func _begin_minion_select(mc: MinionCardData) -> void:
	if input_handler != null:
		input_handler.begin_minion_select(mc)

func _on_hand_card_deselected() -> void:
	if input_handler != null:
		input_handler.on_hand_card_deselected()

# ---------------------------------------------------------------------------
# Spell / Trap / Environment play
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Player input — board slot clicks
# ---------------------------------------------------------------------------

## Slot click chain delegated to input_handler. Scene wrappers kept so signal
## connections in _connect_board_slots stay pointing at scene methods.
func _on_player_slot_clicked_empty(slot: BoardSlot) -> void:
	if input_handler != null:
		input_handler.on_player_slot_clicked_empty(slot)

func _on_player_slot_clicked_occupied(slot: BoardSlot, minion: MinionInstance) -> void:
	if input_handler != null:
		input_handler.on_player_slot_clicked_occupied(slot, minion)

func _on_enemy_slot_clicked(slot: BoardSlot, minion: MinionInstance) -> void:
	if input_handler != null:
		input_handler.on_enemy_slot_clicked(slot, minion)

# ---------------------------------------------------------------------------
# Minion play
# ---------------------------------------------------------------------------

## Player plays go through the engine commands (plan 3.4): the engine validates,
## pays and resolves; the presenter plays the journal. A refusal leaves the
## card in hand.
func _command_play_spell(spell: SpellCardData) -> void:
	var inst: CardInstance = pending_play_card
	pending_play_card = null
	if hand_display:
		hand_display.deselect_current()
	if inst == null:
		return
	var r: CommandResult = state.cmd_play_spell("player", inst, null)
	if not r.ok:
		state._log("  %s: %s." % [spell.card_name, r.reason], _LogType.PLAYER)

## Targeted spell on a minion. Cast-time choices (Rally the Ranks's race pick)
## are resolved before the command so the engine gets the committed choice.
func _apply_targeted_spell(spell: SpellCardData, target: MinionInstance) -> void:
	var inst: CardInstance = pending_play_card
	if inst == null or target == null:
		return
	var extra_cast_data: Dictionary = await _resolve_spell_extra_cast_data(spell, target)
	if not is_inside_tree():
		return
	pending_play_card = null
	if hand_display:
		hand_display.deselect_current()
	_clear_all_highlights()
	var r: CommandResult = state.cmd_play_spell("player", inst, target, extra_cast_data)
	if not r.ok:
		state._log("  %s: %s." % [spell.card_name, r.reason], _LogType.PLAYER)

func _command_play_trap(trap: TrapCardData) -> void:
	var inst: CardInstance = pending_play_card
	pending_play_card = null
	if hand_display:
		hand_display.deselect_current()
	if inst == null:
		return
	var r: CommandResult = state.cmd_play_trap("player", inst)
	if not r.ok:
		if r.reason == "trap_slots_full":
			state._log("Trap slots are full.", _LogType.PLAYER)
		else:
			state._log("  %s: %s." % [trap.card_name, r.reason], _LogType.PLAYER)

func _command_play_environment(env: EnvironmentCardData) -> void:
	var inst: CardInstance = pending_play_card
	pending_play_card = null
	if hand_display:
		hand_display.deselect_current()
	if inst == null:
		return
	var r: CommandResult = state.cmd_play_environment("player", inst)
	if not r.ok:
		state._log("  %s: %s." % [env.card_name, r.reason], _LogType.PLAYER)

## Minion play with the card flight: the hand visual is popped and handed to
## the presenter, which flies it to the slot at MINION_PLAYED playback.
func _command_play_minion(inst: CardInstance, slot: BoardSlot, on_play_target: MinionInstance = null) -> void:
	if inst == null or slot == null:
		return
	var plan: Dictionary = state.plan_cost("player", inst, {})
	var why: String = plan.get("why", "")
	if not why.is_empty() or not state.slot_of("player", slot.index).is_empty():
		if hand_display:
			hand_display.deselect_current()
		return
	var card := inst.card_data as MinionCardData
	var hand_index: int = hand_display.get_index_for(card) if hand_display else 0
	var visual: CardVisual = hand_display.pop_selected_for_animation() if hand_display else null
	if visual != null:
		presenter.register_flight(inst, visual, hand_index)
	var r: CommandResult = state.cmd_play_minion("player", inst, slot.index, on_play_target)
	if not r.ok:
		var flight: Dictionary = presenter.take_flight(inst)
		if not flight.is_empty():
			(flight["visual"] as CardVisual).queue_free()
			if hand_display:
				hand_display.add_card(inst)
		state._log("  %s: %s." % [card.card_name, r.reason], _LogType.PLAYER)

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
	AudioManager.play_sfx("res://assets/audio/sfx/minions/minion_summon.wav", -20.0)
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

## Spawn a screen-distortion wave expanding from a board slot.
## Uses the sonic_wave shader for a glass/heat-haze warp — no visible ring,
## just a radial displacement of the screen behind it.
## Higher total_cost → larger radius and longer duration. Champion = gold tint,
## normal = white.
func _spawn_slot_ripple(slot: BoardSlot, total_cost: int = 0, is_champion: bool = false) -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	var t_norm: float = clampf(total_cost / 8.0, 0.0, 1.0)
	var expand_px: float = lerp(6.0, 14.0, t_norm)
	var duration: float  = lerp(0.28, 0.44, t_norm)
	var strength: float  = lerp(0.010, 0.020, t_norm)

	var base_color: Color = Color(1.0, 0.78, 0.10) if is_champion else Color(1.0, 1.0, 1.0)
	var tint: Color = Color(base_color.r, base_color.g, base_color.b, 0.0)

	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 2
	add_child(fx_layer)

	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.z_index = 15
	rect.z_as_relative = false

	var aspect: float = vp_size.x / vp_size.y
	var center_world: Vector2 = slot.global_position + slot.size * 0.5
	var rect_center_uv := Vector2(center_world.x / vp_size.x, center_world.y / vp_size.y)
	# Half-size in screen-UV (x uses vp width, y uses vp height).
	# The shader aspect-compensates x internally, so pass raw UV values here.
	var rect_half_uv := Vector2(
		(slot.size.x * 0.5) / vp_size.x,
		(slot.size.y * 0.5) / vp_size.y
	)
	# Convert expand/thickness from pixels to UV (height-based so shader math lines up).
	var expand_uv: float = expand_px / vp_size.y
	var thickness_uv: float = 90.0 / vp_size.y
	var corner_uv: float = 14.0 / vp_size.y
	# Start the band deep inside the card so the wave emerges from the center.
	var band_start_inset_uv: float = (slot.size.y * 0.5) / vp_size.y
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://combat/effects/card_summon_wave.gdshader")
	mat.set_shader_parameter("aspect", aspect)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("rect_center", rect_center_uv)
	mat.set_shader_parameter("rect_half_size", rect_half_uv)
	mat.set_shader_parameter("expand_max", expand_uv)
	mat.set_shader_parameter("thickness", thickness_uv)
	mat.set_shader_parameter("corner_radius", corner_uv)
	mat.set_shader_parameter("band_start_inset", band_start_inset_uv)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("alpha_multiplier", 1.0)
	rect.material = mat
	fx_layer.add_child(rect)

	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			mat.set_shader_parameter("progress", p),
			0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, duration * 0.4).set_delay(duration * 0.6).set_trans(Tween.TRANS_SINE)
	await tw.finished
	if is_instance_valid(fx_layer):
		fx_layer.queue_free()

## Register per-card buff VFX preludes. Cards whose visual identity diverges
## from the generic blessing language (e.g. Abyss Order corruption) supply a
## factory here; the rest fall through to BuffApplyVFX's default phases.
func _register_buff_preludes() -> void:
	BuffVfxRegistry.register("dark_empowerment",
			DarkEmpowermentPreludeVFX.prelude_factory)
	BuffVfxRegistry.register("feral_surge",
			FeralSurgePreludeVFX.prelude_factory)
	BuffVfxRegistry.register("dark_command",
			DarkCommandPreludeVFX.prelude_factory)
	BuffVfxRegistry.register_palette("dark_command",
			DarkCommandPreludeVFX.PALETTE)

## The BuffSystem bus subscription is the state's (CombatSetup.setup);
## teardown drops it and resets the per-fight MinionInstance globals.
func _exit_tree() -> void:
	state.teardown()

## Minions currently mid-sacrifice — maps instance_id → delay in seconds
## that _animate_minion_death should wait before starting its ghost rise.
## Populated by _on_sacrifice_occurred right before kill_minion is called;
## drained by _animate_minion_death_body when the death anim actually runs.
## Keeping it as a plain Dictionary (not a Set) so the delay value can be
## tuned per-source later if a prelude adds extra windup time.
var _pending_sacrifice_ghost_delay: Dictionary = {}

## Slots that are mid-sacrifice and must NOT be auto-unfrozen by the
## generic spell-cast wrapper (_apply_targeted_spell etc.). _schedule_sacrifice_unfreeze
## owns the unfreeze for these slots — it waits for the dagger animation to
## complete before clearing the art and flushing deferred deaths. Keys are
## BoardSlot refs; values are unused (used as a set). Cleaned up when the
## scheduled unfreeze runs.
var _sacrifice_locked_slots: Dictionary = {}

## Spawn a SacrificeVFX on the sacrificed minion's slot. No coalescing —
## each sacrifice is its own distinct ritual event (Void Devourer emitting
## twice spawns two parallel VFX on two slots, which is what we want).
##
## Freezes the slot's visual so the minion card stays on screen while the
## dagger plunges into it. Once the dagger hits, we unfreeze and refresh
## so the slot clears in time for the drain overlay to darken empty space.
##
## Also registers a delay so the subsequent soul-rise death animation
## waits until the sacrifice's drain phase completes — the ghost should
## leave during the shatter beat, not during the sigil bloom.
func _on_sacrifice_occurred(minion: MinionInstance, source_tag: String) -> void:
	if minion == null or not is_instance_valid(minion):
		return
	if vfx_controller == null:
		return
	var slot: BoardSlot = _find_slot_for(minion)
	if slot == null:
		return
	# Delay = time from VFX start to when shatter spawns (dagger plunge,
	# sigil bloom, and drain overlay must all resolve first). Ghost rises in
	# sync with the shatter so the soul leaving reads as being freed by the
	# ritual completing.
	var delay: float = SacrificeVFX.DAGGER_DURATION \
			+ SacrificeVFX.SIGIL_DURATION + SacrificeVFX.DRAIN_DURATION
	_pending_sacrifice_ghost_delay[minion.get_instance_id()] = delay
	# Keep the minion card rendered through the dagger approach + embedded
	# hold — kill_minion fires immediately after this emit and _clear_slot_for
	# would otherwise wipe the art before the blade even lands. Unfreeze when
	# the blade starts fading, and fade the card out to match the drain beat.
	slot.freeze_visuals = true
	# Lock the slot from the generic spell-cast wrapper's auto-unfreeze.
	# _schedule_sacrifice_unfreeze owns the unfreeze for sacrifices.
	_sacrifice_locked_slots[slot] = true
	_schedule_sacrifice_unfreeze(slot, SacrificeVFX.MINION_VISIBLE_DURATION)
	var prelude: Callable = SacrificeVfxRegistry.build_prelude(source_tag, slot, minion)
	var vfx := SacrificeVFX.create(slot, prelude)
	vfx_controller.spawn(vfx)

## Unfreeze a slot's visuals and clear the now-null minion, coordinated
## with a fade-out on the slot's art so the card dissolves into the drain
## rather than popping off instantly.
##
## Runs at the end of the dagger's embedded hold — the blade is still in
## the card when the fade starts, so the card "bleeds out" under the blade
## before the blade itself fades and the sigil bloom takes over.
##
## If the slot's death animation was deferred (because freeze_visuals was
## on when _on_minion_vanished fired), flush the queue so the ghost rise
## path can run with its own scheduled delay.
func _schedule_sacrifice_unfreeze(slot: BoardSlot, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree() or slot == null or not is_instance_valid(slot):
		return
	# Fade the slot's art out before clearing so the minion dissolves into
	# the drain overlay instead of snapping away.
	var fade_t: float = SacrificeVFX.MINION_FADE_DURATION
	var art: TextureRect = slot._art_rect
	if art != null and is_instance_valid(art):
		var tw := create_tween()
		tw.tween_property(art, "modulate:a", 0.0, fade_t).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(fade_t).timeout
	if not is_inside_tree() or slot == null or not is_instance_valid(slot):
		return
	slot.freeze_visuals = false
	slot._refresh_visuals()
	_sacrifice_locked_slots.erase(slot)
	# Restore the art's alpha for the next minion that occupies this slot;
	# _refresh_visuals hides it behind visible=false but modulate persists.
	if art != null and is_instance_valid(art):
		art.modulate.a = 1.0

## Pending buff VFX to spawn — keyed by (minion, source_tag) so:
##   • Multiple steps from the same source on the same minion coalesce into
##     one VFX with combined deltas (e.g. Dark Empowerment's +ATK + +HP).
##   • Different sources hitting the same minion in the same frame get their
##     own VFX so per-source preludes don't collide.
## Pending buff requests from EffectResolver — keyed by "minion_id|source_tag"
## so multiple BUFF_ATK + BUFF_HP steps from the same source on the same
## minion aggregate into one BuffApplyVFX. Each entry value:
##   { "minion": MinionInstance, "source": String,
##     "intents": Array[{ "buff_type": int, "amount": int, "is_hp_gain": bool }] }
## Drained next frame by _flush_buff_requests.
var _pending_buff_requests: Dictionary = {}

## Presenter hook (plan 3.0): the buff is already applied on the engine; queue
## its animation. Requests for the same minion + source in one frame merge into
## one BuffApplyVFX that tweens the labels from the first pre-buff snapshot to
## the live values at flush. The labels are held at the pre-buff values until
## the pulse beat, so that beat is where the number visibly changes.
func _show_buff_apply(minion: MinionInstance, source_tag: String, atk_before: int, hp_before: int) -> void:
	if minion == null or not is_instance_valid(minion) or vfx_controller == null:
		return
	# Pack Frenzy owns its full buff visual (PackFrenzyVFX tween + chevron).
	if source_tag == "pack_frenzy":
		return
	var key: String = "%d|%s" % [minion.get_instance_id(), source_tag]
	var was_empty: bool = _pending_buff_requests.is_empty()
	if not _pending_buff_requests.has(key):
		_pending_buff_requests[key] = {"minion": minion, "source": source_tag,
			"atk_before": atk_before, "hp_before": hp_before}
	var agg: Dictionary = _pending_buff_requests[key]
	var slot: BoardSlot = _find_slot_for(minion)
	if slot != null and slot.minion == minion:
		slot.hold_stats(agg["atk_before"], agg["hp_before"])
	if was_empty:
		call_deferred("_flush_buff_requests")

## Spawn one BuffApplyVFX per (minion, source) bucket with the pre-buff
## snapshot; the VFX tweens the labels to the live values at its pulse beat.
func _flush_buff_requests() -> void:
	var pending: Dictionary = _pending_buff_requests
	_pending_buff_requests = {}
	# Build the spawn list first so we can count it for the AI gate.
	var to_spawn: Array = []
	for key in pending.keys():
		var agg: Dictionary = pending[key]
		var m: MinionInstance = agg["minion"] as MinionInstance
		if m == null or not is_instance_valid(m):
			continue
		var slot: BoardSlot = _find_slot_for(m)
		if slot == null or slot.minion != m:
			continue
		var atk_before: int = agg["atk_before"]
		var hp_before: int = agg["hp_before"]
		var atk_d: int = m.effective_atk() - atk_before
		var hp_d: int = m.current_health - hp_before
		if atk_d == 0 and hp_d == 0:
			slot.refresh_stats_only()
			continue
		to_spawn.append({"minion": m, "slot": slot, "src": String(agg["source"]),
			"atk_before": atk_before, "hp_before": hp_before, "atk_d": atk_d, "hp_d": hp_d})
	if to_spawn.is_empty():
		return
	_active_buff_vfx_count = to_spawn.size()
	for s in to_spawn:
		var prelude: Callable   = BuffVfxRegistry.build_prelude(s["src"], s["slot"], s["atk_d"], s["hp_d"])
		var palette: Dictionary = BuffVfxRegistry.get_palette(s["src"])
		var vfx := BuffApplyVFX.create(s["slot"], s["atk_d"], s["hp_d"], prelude, palette)
		vfx.set_stat_snapshot(s["atk_before"], s["hp_before"])
		vfx.finished.connect(_on_buff_vfx_finished, CONNECT_ONE_SHOT)
		vfx_controller.spawn(vfx)

## Called when each BuffApplyVFX completes; the presenter awaits
## buff_vfx_batch_done when the last one in the batch finishes.
var _active_buff_vfx_count: int = 0

func _on_buff_vfx_finished() -> void:
	_active_buff_vfx_count -= 1
	if _active_buff_vfx_count <= 0:
		_active_buff_vfx_count = 0
		buff_vfx_batch_done.emit()

## Cosmetic buff VFX for presence-aura recompute deltas. State has already been
## mutated silently inside _refresh_presence_auras_for_side (silent strip+reapply,
## no buff_applied signal). Only the visual flash remains, gated to minions whose
## net stats actually changed (e.g. 2nd Elder summoned → existing imps go from
## +100 to +200 — real +100 delta worth animating). No intents passed: BuffApplyVFX
## runs purely cosmetic without re-applying buffs.
func _spawn_presence_aura_buff_vfx(minion: MinionInstance, atk_delta: int, hp_delta: int) -> void:
	if vfx_controller == null:
		return
	var slot: BoardSlot = _find_slot_for(minion)
	if slot == null or slot.minion != minion:
		return
	var vfx := BuffApplyVFX.create(slot, atk_delta, hp_delta)
	vfx_controller.spawn(vfx)

## Champion entrance VFX (banner reveal, screen shake, gold flash) live on
## vfx_bridge — see CombatVFXBridge.champion_summon_sequence and friends.

# ---------------------------------------------------------------------------
# Relic effects
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Abyss Order — Corruption helpers
# ---------------------------------------------------------------------------

## Presenter hook — CombatState._apply_void_mark: the mark VFX on the enemy panel.
func _show_void_mark_applied() -> void:
	if _enemy_status_panel and is_instance_valid(_enemy_status_panel) and vfx_controller != null:
		var vfx := VoidMarkApplyVFX.create(_enemy_status_panel)
		vfx_controller.spawn(vfx)

## Spawn the corruption-apply VFX, blink, and ATK-debuff flash on a slot. Split
## out so both the immediate path and the queued-drain path go through the same
## code.
func _play_corruption_apply_visual(slot: BoardSlot) -> void:
	if slot == null or not is_instance_valid(slot):
		return
	var vfx := CorruptionApplyVFX.create(slot)
	vfx_controller.spawn(vfx)
	slot.blink_corruption_status()
	slot.flash_atk_debuff()

## Champion / passive / on-play VFX delegated to vfx_bridge. External callers
## (HardcodedEffects, CombatHandlers) keep using these scene wrappers via
## `_scene.has_method("X")` guards.
func _play_champion_acp_aura_pulse() -> void:
	if vfx_bridge != null:
		vfx_bridge.play_champion_acp_aura_pulse()

func _play_corruption_detonations(targets: Array) -> void:
	if vfx_bridge != null:
		await vfx_bridge.play_corruption_detonations(targets)

func _play_feral_reinforcement_vfx(source: MinionInstance, imp_card: CardData) -> void:
	if vfx_bridge != null:
		await vfx_bridge.play_feral_reinforcement_vfx(source, imp_card)

# ---------------------------------------------------------------------------
# Owner-aware board helpers
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Abyss Order — Sacrifice helpers
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Abyss Order — Board-wide passive triggers (fire on friendly death)
# ---------------------------------------------------------------------------

## Aura-source minions play a one-shot breathing halo on their own summon to
## advertise "I project an aura" without the noise of a persistent effect.
## Strictly on-summon: never fires on aura refresh or when another source of
## the same aura enters play. Per-card dispatch lives in CardVfxRegistry.
func _maybe_spawn_aura_pulse(card: CardData, slot: BoardSlot) -> void:
	CardVfxRegistry.play_summon_aura_pulse(vfx_controller, card, slot)

# ---------------------------------------------------------------------------
# Test Mode (Option C) — applied after normal combat startup
# ---------------------------------------------------------------------------

func _apply_test_config() -> void:
	# Override HP values
	if TestConfig.player_hp > 0:
		state.player_hp = TestConfig.player_hp

	if TestConfig.enemy_hp > 0:
		state.enemy_hp     = TestConfig.enemy_hp
		state.enemy_hp_max = TestConfig.enemy_hp
	# Add cards directly to player hand
	for id in TestConfig.hand_cards:
		var card := state._card_for("player", id)
		if card:
			state.add_to_hand("player", card)

	# Add cards directly to enemy hand
	for id in TestConfig.enemy_hand_cards:
		var ecard := state._card_for("enemy", id)
		if ecard:
			state.add_to_hand("enemy", ecard)

	# Pre-summon player board minions
	for id in TestConfig.player_board_cards:
		state._summon_token(id, "player")

	# Pre-summon enemy board minions
	for id in TestConfig.enemy_board_cards:
		state._summon_token(id, "enemy")

	# Pre-place player traps
	for id in TestConfig.player_traps:
		var trap_card := CardDatabase.get_card(id)
		if trap_card is TrapCardData and state.active_traps.size() < trap_slot_panels.size():
			state.active_traps.append(trap_card as TrapCardData)
	if not TestConfig.player_traps.is_empty():
		state._update_trap_display()

	# Pre-place enemy traps
	for id in TestConfig.enemy_traps:
		var trap_card := CardDatabase.get_card(id)
		if trap_card is TrapCardData and state.enemy_active_traps.size() < enemy_trap_slot_panels.size():
			state.enemy_active_traps.append(trap_card as TrapCardData)
	if not TestConfig.enemy_traps.is_empty():
		state._update_enemy_trap_display()

	# Override starting resources
	if TestConfig.start_essence_max > 0:
		state.player_essence_max = TestConfig.start_essence_max
		state.player_essence     = TestConfig.start_essence_max
	if TestConfig.start_mana_max > 0:
		state.player_mana_max = TestConfig.start_mana_max
		state.player_mana     = TestConfig.start_mana_max
	if TestConfig.start_essence_max > 0 or TestConfig.start_mana_max > 0:
		state.emit_resources("player")
		_refresh_end_turn_mode()

	# Override enemy starting resources (so test-cast spells on turn 1)
	if TestConfig.enemy_start_essence_max > 0:
		state.enemy_essence_max = TestConfig.enemy_start_essence_max
		state.enemy_essence     = TestConfig.enemy_start_essence_max
	if TestConfig.enemy_start_mana_max > 0:
		state.enemy_mana_max = TestConfig.enemy_start_mana_max
		state.enemy_mana     = TestConfig.enemy_start_mana_max

	state._log("[TEST] Test config applied.", _LogType.TURN)
	TestConfig.enabled = false  # consumed — reset so normal navigation isn't affected

var _cheat: CheatPanel
var _talent_tip_vbox: VBoxContainer  ## Talent tooltip content — rebuilt after cheat unlocks

# ---------------------------------------------------------------------------
# Relic System
# ---------------------------------------------------------------------------

func _setup_relics() -> void:
	# Clean up existing relic bar when rebuilding (e.g. from cheat panel)
	if _relic_bar != null:
		_relic_bar.queue_free()
		_relic_bar = null
	if state.relic_runtime == null or state.relic_runtime.relics.is_empty():
		return

	# Build relic bar UI just below the EndTurnPanel, same width, center-aligned
	var ui_root: Node = get_node_or_null("UI")
	if not ui_root:
		return
	_relic_bar = RelicBar.new()
	# Match EndTurnPanel anchoring: right side, vertically centered
	_relic_bar.anchor_left   = 1.0
	_relic_bar.anchor_right  = 1.0
	_relic_bar.anchor_top    = 0.5
	_relic_bar.anchor_bottom = 0.5
	_relic_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# Position just below EndTurnPanel (bottom = 16) with a small gap
	_relic_bar.offset_left   = -185.0
	_relic_bar.offset_right  = -10.0
	_relic_bar.offset_top    = -26.0
	_relic_bar.offset_bottom = 54.0
	_relic_bar.add_theme_constant_override("separation", 6)
	_relic_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	ui_root.add_child(_relic_bar)
	_relic_bar.setup(state.relic_runtime)
	_relic_bar.relic_activated.connect(_on_relic_activated)
	_relic_bar.relic_hovered.connect(_on_relic_hovered)
	_relic_bar.relic_unhovered.connect(_on_relic_unhovered)

func _on_relic_hovered(effect_id: String) -> void:
	if input_handler != null:
		input_handler.on_relic_hovered(effect_id)

func _on_relic_unhovered() -> void:
	if input_handler != null:
		input_handler.on_relic_unhovered()

## Relic bar click. Relics resolve through state.cmd_activate_relic (plan
## 2A.6); Blood Chalice first asks for a target and activates once one is picked.
func _on_relic_activated(index: int) -> void:
	if not state.is_player_turn or state.relic_runtime == null:
		return
	if not state.relic_runtime.can_activate(index):
		return
	_pip_bar.stop_blink()
	var effect_id: String = state.relic_runtime.get_state(index).data.effect_id
	if effect_id == "relic_execute":
		_pending_relic_index = index
		_begin_relic_targeting(effect_id)
		return
	state.cmd_activate_relic(index)
	if _relic_bar:
		_relic_bar.refresh()
	_refresh_hand_spell_costs()

## Enter relic targeting mode — highlight all enemy minions + enemy hero as valid targets.
func _begin_relic_targeting(effect_id: String) -> void:
	_clear_all_highlights()  # This resets _pending_relic_target — set it after
	_pending_relic_target = effect_id
	selected_attacker = null
	if hand_display:
		hand_display.deselect_current()
	pending_play_card = null
	_highlight_slots(enemy_slots, func(s: BoardSlot) -> bool: return not s.is_empty())
	if _enemy_status_panel:
		_enemy_status_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_enemy_status_panel.gui_input.connect(_on_relic_target_hero_input)
		_enemy_hero_panel.start_spell_pulse()
	state._log("  Blood Chalice: choose a target (right-click to cancel).", _LogType.PLAYER)

## Blood Chalice target picked: an enemy minion.
func _resolve_relic_target_minion(minion: MinionInstance) -> void:
	_activate_pending_relic(minion)

## Blood Chalice target picked: the enemy hero.
func _resolve_relic_target_hero() -> void:
	_activate_pending_relic("enemy_hero")

func _activate_pending_relic(target) -> void:
	var index: int = _pending_relic_index
	_pending_relic_target = ""
	_pending_relic_index = -1
	_clear_all_highlights()
	if index >= 0:
		state.cmd_activate_relic(index, target)
	if _relic_bar:
		_relic_bar.refresh()

## Cancel relic targeting — nothing was spent (the charge goes on activation).
func _cancel_relic_targeting() -> void:
	if _pending_relic_index >= 0:
		state._log("  Relic cancelled.", _LogType.PLAYER)
	_pending_relic_target = ""
	_pending_relic_index = -1
	_clear_all_highlights()
	if _relic_bar:
		_relic_bar.refresh()

## Fired when player clicks the enemy hero panel while relic targeting is active.
func _on_relic_target_hero_input(event: InputEvent) -> void:
	if input_handler != null:
		input_handler.on_relic_target_hero_input(event)

func _input(event: InputEvent) -> void:
	if input_handler != null:
		input_handler.handle_input(event)

## Delegated to vfx_bridge — preserves the external entry point used by
## HardcodedEffects.brood_call. Kept as a thin async wrapper so callers can
## still `await scene._play_brood_call_vfx(...)` unchanged.
func _play_brood_call_vfx(owner: String) -> void:
	if vfx_bridge != null:
		await vfx_bridge.play_brood_call_vfx(owner)

## Delegated to vfx_bridge — Grafted Butcher ON PLAY graft + cleaver wave.
func _play_grafted_butcher_vfx(butcher: MinionInstance,
		sac_center: Vector2, butcher_owner: String) -> void:
	if vfx_bridge != null:
		await vfx_bridge.play_grafted_butcher_vfx(butcher, sac_center, butcher_owner)

## Delegated to vfx_bridge — Pack Frenzy warcry sweep.
func _play_pack_frenzy_vfx(owner: String, target_slots: Array,
		is_matriarch: bool) -> void:
	if vfx_bridge != null:
		await vfx_bridge.play_pack_frenzy_vfx(owner, target_slots, is_matriarch)

## (`_pack_frenzy_active_vfx` lives on vfx_bridge. VfxController reads it via
## `_combat.vfx_bridge._pack_frenzy_active_vfx` to await the lingering visual.)

## Delegated to vfx_bridge — ATK buff chevron used by Pack Frenzy.
func _spawn_atk_chevron(minion: MinionInstance) -> void:
	if vfx_bridge != null:
		vfx_bridge.spawn_atk_chevron(minion)

# ---------------------------------------------------------------------------
# Tag query helpers — data-driven alternative to card ID checks
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Abyss Order — Void Imp helpers
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Talent helpers
# ---------------------------------------------------------------------------

## Sync the talent / passive set from GameManager into combat state, then clear
## the override cache so future _card_for calls reflect the new context.
##
## Used when talents change mid-combat (cheat panel unlock, future relics that
## grant talents). CardInstances already in hand / deck / graveyard keep their
## existing card_data — only NEW cards drawn / spawned / added after this call
## pick up the override. This matches the historical handler behavior where
## mid-combat talent unlocks affected only subsequent events.
func _refresh_override_context() -> void:
	state.talents.assign(GameManager.unlocked_talents)
	var _hero := HeroDatabase.get_hero(GameManager.current_hero)
	state.hero_passives.clear()
	if _hero != null:
		for p in _hero.passives:
			state.hero_passives.append(p.id)
	if GameManager.current_enemy != null:
		state.enemy_passives.assign(GameManager.current_enemy.passives)
	CardDatabase.clear_override_cache()

## Refresh hand card cost displays / playability glows / preview overlay.
## Delegated to combat_ui.
func _refresh_hand_spell_costs() -> void:
	if combat_ui != null:
		combat_ui.refresh_hand_spell_costs()

## Effective mana cost for a player spell after applying board discount and tax penalty.
func _effective_spell_cost(spell: SpellCardData) -> int:
	return maxi(0, spell.cost - _spell_mana_discount() + state.player_spell_cost_penalty)

## Effective mana cost for a player trap/rune — reads mana_delta from the hovered card's CardInstance.
## Used for pip-blink preview only; actual play uses pending_play_card.effective_cost().
func _effective_trap_cost(trap: TrapCardData) -> int:
	if _hovered_hand_visual != null and _hovered_hand_visual.card_inst != null:
		return _hovered_hand_visual.card_inst.effective_cost()
	return maxi(0, trap.cost)

## Mana discount applied to all player spells — summed from all minions on board.
## Data-driven via MinionCardData.mana_cost_discount.
func _spell_mana_discount() -> int:
	var discount := 0
	for m in state.player_board:
		discount += m.card_data.mana_cost_discount
	return discount

# Flesh / Forge facades — delegate to CombatState primitives. The state
# setters emit flesh_changed / forge_changed which refresh Seris's resource
# bar via the _on_state_*_changed subscribers. Wrappers preserved for
# external callers (handlers, EffectResolver).

## Seris — Corrupt Flesh activated ability. Entry point from SerisResourceBar button.
## Toggles targeting mode; player clicks a friendly Demon to apply Corruption.
## Costs are consumed inside _seris_corrupt_apply_target after a valid click so
## misclicks / cancels don't waste Flesh.
func _seris_corrupt_activate() -> void:
	if not state._has_talent("corrupt_flesh"):
		return
	if state._seris_corrupt_used_this_turn:
		state._log("  Corrupt Flesh already used this turn.", _LogType.PLAYER)
		return
	if state.player_flesh < 1:
		return
	# Check there's at least one valid target (friendly Demon) before entering target mode.
	var has_target := false
	for m in state.player_board:
		if (m.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
			has_target = true
			break
	if not has_target:
		state._log("  Corrupt Flesh: no friendly Demon on board.", _LogType.PLAYER)
		return
	_seris_corrupt_targeting = true
	_clear_all_highlights()
	_highlight_slots(player_slots,
		func(s: BoardSlot) -> bool:
			return not s.is_empty() \
				and (s.minion.card_data as MinionCardData).is_race(Enums.MinionType.DEMON))
	state._log("  Corrupt Flesh: pick a friendly Demon (right-click to cancel).", _LogType.PLAYER)

## Applies Corrupt Flesh to the clicked minion. Called from _on_player_slot_clicked_occupied
## when _seris_corrupt_targeting is active. Non-Demon picks cancel targeting.
## The engine's hero-skill command applies it; the scene clears the targeting flag.
func _seris_corrupt_apply_target(minion: MinionInstance) -> void:
	_seris_corrupt_targeting = false
	_clear_all_highlights()
	if minion != null and not (minion.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
		state._log("  Corrupt Flesh: target must be a friendly Demon.", _LogType.PLAYER)
		return
	state.cmd_hero_skill("player", "seris_corrupt", minion)

## Cancel Corrupt Flesh targeting without applying. Right-click / empty-slot
## click path. Flesh is not consumed (cost only debits inside _seris_corrupt_apply).
func _cancel_seris_corrupt_targeting() -> void:
	_seris_corrupt_targeting = false
	_clear_all_highlights()
	state._log("  Corrupt Flesh cancelled.", _LogType.PLAYER)

## Delegated to vfx_bridge — fires the player's void bolt projectile.
func _fire_void_bolt_projectile(source_minion: MinionInstance = null, from_rune: bool = false) -> VoidBoltProjectile:
	if vfx_bridge == null:
		return null
	return vfx_bridge.fire_void_bolt_projectile(source_minion, from_rune)

## Delegated to vfx_bridge — fires the enemy's void bolt projectile.
func _fire_enemy_void_bolt_projectile(source_minion: MinionInstance = null) -> VoidBoltProjectile:
	if vfx_bridge == null:
		return null
	return vfx_bridge.fire_enemy_void_bolt_projectile(source_minion)

# ---------------------------------------------------------------------------
# Combat manager events
# ---------------------------------------------------------------------------

## Presenter hook — CombatState._on_minion_vanished (before the death triggers).
## Minions with an on-death icon VFX resolve their on-death effects after the
## icon plays; CombatHandlers.on_minion_died_death_effect skips the ones queued here.

# ---------------------------------------------------------------------------
# Targeted spell helpers
# ---------------------------------------------------------------------------

## Returns true if at least one valid target exists for this card's on-play target type.
## If false, the card skips targeting and goes straight to placement (effect fires but does nothing).
## Uses the card's raw target type — for talent-gated overrides see _has_valid_minion_on_play_targets_for.
# Targeting facades — delegate to Targeting helper. Kept on scene so the
# play-card flow doesn't need to prefix every call with `targeting.`.

func _highlight_slots(slots: Array, filter: Callable, color_picker: Callable = Callable()) -> void:
	targeting.highlight_slots(slots, filter, color_picker)

func _highlight_minion_on_play_targets(card: MinionCardData) -> void:
	targeting.highlight_minion_on_play_targets(card)

func _effective_target_type(mc: MinionCardData) -> String:
	return targeting.effective_target_type(mc)

func _effective_target_optional(mc: MinionCardData) -> bool:
	return targeting.effective_target_optional(mc)

func _effective_target_prompt(mc: MinionCardData) -> String:
	return targeting.effective_target_prompt(mc)

func _mark_selected_target(minion: MinionInstance) -> void:
	targeting.mark_selected_target(minion)

func _show_target_prompt(text: String) -> void:
	targeting.show_prompt(text)

func _hide_target_prompt() -> void:
	targeting.hide_prompt()

func _has_valid_minion_on_play_targets_for(target_type: String) -> bool:
	return targeting.has_valid_minion_on_play_targets_for(target_type)

func _is_valid_minion_on_play_target(minion: MinionInstance, target_type: String) -> bool:
	return targeting.is_valid_minion_on_play_target(minion, target_type)

func _highlight_spell_targets(spell: SpellCardData) -> void:
	targeting.highlight_spell_targets(spell)

func _is_valid_spell_target(minion: MinionInstance, target_type: String) -> bool:
	return targeting.is_valid_spell_target(minion, target_type)

## Resolve cast-time runtime parameters for spells that need a choice the
## EffectResolver can't make on its own (e.g. Rally the Ranks's race pick when
## the chosen target is dual-tag Human+Demon). Returns a Dictionary forwarded
## into cast_player_targeted_spell as ctx.extra_cast_data. Empty {} when the
## spell needs no runtime params, or when the choice is determined by the
## target's only race (single-tag target → no modal needed).
##
## Currently only Rally the Ranks uses this. Future cards that need similar
## "pick a parameter at cast time" UX wire here via a per-spell branch.
func _resolve_spell_extra_cast_data(spell: SpellCardData, target: MinionInstance) -> Dictionary:
	if spell == null or target == null or target.card_data == null:
		return {}
	match spell.id:
		"rally_the_ranks":
			var mc := target.card_data as MinionCardData
			var is_human: bool = mc.is_race(Enums.MinionType.HUMAN)
			var is_demon: bool = mc.is_race(Enums.MinionType.DEMON)
			if is_human and is_demon:
				# Dual-tag target — ask the player.
				var modal := ChoiceModal.new()
				add_child(modal)
				modal.show_modal("%s is both Human and Demon — which race for the Rank and File tokens?" % target.card_data.card_name,
					[{"label": "Human", "value": "human"},
					 {"label": "Demon", "value": "demon"}])
				var picked = await modal.choice_made
				modal.queue_free()
				return {"rally_race": picked}
			if is_human:
				return {"rally_race": "human"}
			if is_demon:
				return {"rally_race": "demon"}
			return {}  # shouldn't happen — target_type gates this
	return {}

## Fired when player clicks the enemy hero panel while targeting a spell with "enemy_minion_or_hero".
func _on_enemy_hero_spell_input(event: InputEvent) -> void:
	if input_handler != null:
		input_handler.on_enemy_hero_spell_input(event)

# ---------------------------------------------------------------------------
# Cyclone / trap-or-env targeting
# ---------------------------------------------------------------------------

## Cyclone trap-or-env targeting delegated to input_handler.
func _setup_trap_env_targeting() -> void:
	if input_handler != null:
		input_handler.setup_trap_env_targeting()

func _tear_down_trap_env_targeting() -> void:
	if input_handler != null:
		input_handler.tear_down_trap_env_targeting()

# ---------------------------------------------------------------------------
# Trap helpers
# ---------------------------------------------------------------------------

## Presentation for traps the state sprang (CombatState._fire_traps_for already
## logged and consumed them): one at a time, flash the slot, play the card
## animation and run the trap's `resolve` callable at its impact, then a short
## gap. `reveals`: Array of {trap, slot_index, resolve}.
func play_trap_reveals(owner: String, reveals: Array) -> void:
	for entry: Dictionary in reveals:
		if not is_inside_tree():
			return
		var trap: TrapCardData = entry["trap"]
		_flash_trap_slot_for(owner, entry["slot_index"])
		var shown: Array[bool] = [false]
		_show_card_cast_anim(trap, owner == "enemy", func() -> void: shown[0] = true)
		# Wait for the full card animation to finish (~1.1s)
		while not shown[0] and is_inside_tree():
			await get_tree().process_frame
		# Small gap between sequential traps
		if is_inside_tree():
			await get_tree().create_timer(0.6).timeout

## Flash a trap slot gold to indicate it fired.
func _flash_trap_slot_for(owner: String, slot_idx: int) -> void:
	trap_env_display.flash_slot(owner, slot_idx)

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

## Centre-screen card reveal when an enemy summons a minion.
## Delegated to vfx_bridge — big-card reveal of an enemy summon.
func _show_enemy_summon_reveal(card: CardData) -> void:
	if vfx_bridge != null:
		await vfx_bridge.show_enemy_summon_reveal(card)

# Facades to CombatState's signal emit — external callers (HardcodedEffects,
# EffectResolver, RelicEffects) keep working unchanged. Subscribers below do
# the actual TrapEnvDisplay work.

# ---------------------------------------------------------------------------
# Rune & Ritual system
# ---------------------------------------------------------------------------

## Presenter hook — CombatState._fire_ritual, called before the runes are
## consumed: snapshot the rune panels + art now; the presenter runs the merge
## VFX on them at RITUAL_FIRED playback.
## Snapshot the player rune panels a ritual consumed (RITUAL_FIRED's `slots`, in
## pick order, and the `runes` that sat there): panels, glow colours and art.
## Empty when the VFX can't be anchored (no bridge, panels not resolved).
func _capture_ritual_visual(slot_indices: Array, runes: Array) -> Dictionary:
	if vfx_bridge == null or vfx_controller == null or trap_slot_panels.is_empty():
		return {}
	if slot_indices.size() < 2 or slot_indices.size() != runes.size():
		return {}
	var slots: Array = []
	var colors: Array = []
	var arts: Array = []
	for k in slot_indices.size():
		var i: int = slot_indices[k]
		if i < 0 or i >= trap_slot_panels.size():
			return {}
		var panel: Panel = trap_slot_panels[i] as Panel
		if panel == null or not panel.is_inside_tree():
			return {}
		var trap: TrapCardData = runes[k] as TrapCardData
		slots.append(panel)
		colors.append(trap.rune_glow_color)
		var art: Texture2D = null
		if trap.battlefield_art_path != "" and ResourceLoader.exists(trap.battlefield_art_path):
			art = load(trap.battlefield_art_path)
		arts.append(art)
	return {"slots": slots, "colors": colors, "arts": arts}

## Play the generic RitualFiringVFX on a captured rune set (awaitable). The
## presenter plays RUNE_PLACED (the halo) before RITUAL_FIRED, so the player
## sees: place rune → halo lands → THEN the ritual ignites.
func _run_ritual_visual(capture: Dictionary) -> void:
	if not is_inside_tree() or vfx_controller == null:
		return
	var vfx := RitualFiringVFX.create(capture["slots"], capture["colors"], capture["arts"])
	vfx_controller.spawn(vfx)
	await vfx.finished
	# Stop all glow tweens after consumption — prevents stale glow on repurposed slots
	if trap_env_display != null:
		for i in trap_slot_panels.size():
			trap_env_display.stop_rune_glow(i)

# ---------------------------------------------------------------------------
# Large card preview (hover over hand cards or board slots)
# ---------------------------------------------------------------------------

func _show_large_preview(card_data: CardData, source_visual: CardVisual = null) -> void:
	large_preview.show_card(card_data, source_visual)

func _hide_large_preview() -> void:
	large_preview.hide_card()

func _on_board_slot_hover_enter(slot: BoardSlot) -> void:
	if input_handler != null:
		input_handler.on_board_slot_hover_enter(slot)

func _on_enemy_hero_button_pressed() -> void:
	if input_handler != null:
		await input_handler.on_enemy_hero_button_pressed()

# ---------------------------------------------------------------------------
# Win / loss
# ---------------------------------------------------------------------------

func _on_victory() -> void:
	if state._combat_ended:
		return
	state._combat_ended = true
	# Delay to let the final damage popup show before transitioning
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
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
	if state._combat_ended:
		return
	state._combat_ended = true
	_disable_combat_buttons()
	if GameManager.has_revive:
		# Offer revive option — restart the same fight
		if game_over_label:
			game_over_label.text = "DEFEATED\nSecond Wind activates!"
		if restart_button:
			restart_button.text = "Revive & Retry"
			restart_button.disabled = false
		state._pending_revive = true
	else:
		GameManager.end_run(false)
		if game_over_label:
			game_over_label.text = "DEFEAT"
		if restart_button:
			restart_button.text = "Return to Menu"
	if game_over_panel:
		game_over_panel.visible = true

var _second_wind_indicator: Label = null

func _setup_second_wind_indicator(ui_root: Node) -> void:
	if ui_root == null or not GameManager.has_revive:
		return
	_second_wind_indicator = Label.new()
	_second_wind_indicator.text = "✦ Second Wind"
	_second_wind_indicator.add_theme_font_size_override("font_size", 16)
	_second_wind_indicator.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0, 1.0))
	_second_wind_indicator.add_theme_color_override("font_outline_color", Color(0.05, 0.10, 0.25, 1.0))
	_second_wind_indicator.add_theme_constant_override("outline_size", 3)
	_second_wind_indicator.tooltip_text = "Second Wind\nIf you are defeated this fight, you will revive at full HP and restart the same combat. Consumed on use."
	_second_wind_indicator.mouse_filter = Control.MOUSE_FILTER_STOP
	_second_wind_indicator.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_second_wind_indicator.position = Vector2(20, 20)
	ui_root.add_child(_second_wind_indicator)

func _disable_combat_buttons() -> void:
	if end_turn_essence_button:
		end_turn_essence_button.disabled = true
	if end_turn_mana_button:
		end_turn_mana_button.disabled = true
	if end_turn_button:
		end_turn_button.disabled = true
	_enemy_hero_panel.show_attackable(false)

func _on_restart_pressed() -> void:
	if state._pending_revive:
		# Consume revive and restart the same fight with full HP
		GameManager.has_revive = false
		GameManager.player_hp = GameManager.player_hp_max
		GameManager.go_to_scene("res://combat/board/CombatScene.tscn")
	else:
		GameManager.go_to_scene("res://ui/MainMenu.tscn")

# ---------------------------------------------------------------------------
# Visual helpers
# ---------------------------------------------------------------------------

func _update_champion_progress(current: int, total: int) -> void:
	if _enemy_hero_panel != null:
		_enemy_hero_panel.update_champion_progress(current, total)

func _on_champion_killed() -> void:
	if _enemy_hero_panel != null:
		_enemy_hero_panel.on_champion_killed()

func _spawn_void_imp_claw_vfx_at(source_pos: Vector2, owner_side: String) -> void:
	var target_panel: Control = _enemy_status_panel if owner_side == "player" else _player_status_panel
	if target_panel == null or vfx_controller == null:
		return
	var vfx := VoidImpClawVFX.create(target_panel, source_pos)
	vfx_controller.spawn(vfx)

## Void Netter's net VFX (presentation only — the 200 damage is the card's
## on-play step, journaled as DAMAGE_DEALT and shown by the presenter).
func _play_void_netter_on_play_vfx(source_minion: MinionInstance, target: MinionInstance, _owner_side: String) -> void:
	if source_minion == null or target == null or vfx_controller == null:
		return
	var source_slot: BoardSlot = _find_slot_for(source_minion)
	var target_slot: BoardSlot = _find_slot_for(target)
	if source_slot == null or target_slot == null:
		return
	var vfx := VoidNetterVFX.create(source_slot, target_slot, func() -> void: pass)
	vfx_controller.spawn(vfx)

func _play_frenzied_imp_vfx(source_minion: MinionInstance, target: MinionInstance, feral_count: int) -> void:
	if source_minion == null or target == null or vfx_controller == null:
		return
	var source_slot: BoardSlot = _find_slot_for(source_minion)
	var target_slot: BoardSlot = _find_slot_for(target)
	if source_slot == null or target_slot == null:
		return
	var source_pos: Vector2 = source_slot.get_global_rect().get_center()
	var target_pos: Vector2 = target_slot.get_global_rect().get_center()
	var vfx := FrenziedImpHurlVFX.create(source_pos, target_pos, feral_count, target_slot, target_slot)
	vfx_controller.spawn(vfx)
	await vfx.finished

## Death animation system delegated to vfx_bridge. Scene keeps thin wrappers
## so external callers (VfxController via _combat._flush_deferred_deaths)
## don't need to know about the bridge. State (_active_death_anims,
## _deferred_death_slots, _pending_sacrifice_ghost_delay) stays on scene
## since multiple non-VFX paths write to it.
func _animate_minion_death(slot: BoardSlot, pos: Vector2, dead_minion: MinionInstance = null) -> void:
	if vfx_bridge != null:
		await vfx_bridge.animate_minion_death(slot, pos, dead_minion)

func _clear_all_highlights() -> void:
	targeting.clear_all_highlights()
	_pending_relic_target = ""

## The BoardSlot view showing `minion`: by engine occupancy first, then by what
## the nodes still display (a dead minion held on a frozen node mid-animation).
func _find_slot_for(minion: MinionInstance) -> BoardSlot:
	if minion == null:
		return null
	var engine_slot: SlotState = state.slot_for(minion)
	if engine_slot != null:
		return slot_node(minion.owner, engine_slot.index)
	var slots := player_slots if minion.owner == "player" else enemy_slots
	for slot in slots:
		if slot.minion == minion:
			return slot
	return null

## The BoardSlot view for engine slot (side, index), or null when off-board.
func slot_node(side: String, index: int) -> BoardSlot:
	var slots: Array[BoardSlot] = player_slots if side == "player" else enemy_slots
	if index < 0 or index >= slots.size():
		return null
	return slots[index]

## Returns occupied BoardSlots belonging to the opponent of `owner_side`.
func _get_opponent_occupied_slots(owner_side: String) -> Array:
	var slots: Array[BoardSlot] = enemy_slots if owner_side == "player" else player_slots
	var result: Array = []
	for slot in slots:
		if slot.minion != null:
			result.append(slot)
	return result

# ---------------------------------------------------------------------------
# Attack animation — lunge + flash + damage popup
# ---------------------------------------------------------------------------

## Reparent a slot from its HBoxContainer to $UI for free-position animation.
## Returns [orig_parent, orig_index, placeholder] for later restore.
func _reparent_slot_for_lunge(slot: BoardSlot) -> Array:
	var atk_rect := slot.get_global_rect()
	var orig_parent: Control = slot.get_parent()
	var orig_index: int = slot.get_index()
	var placeholder := Control.new()
	placeholder.custom_minimum_size = Vector2(BoardSlot.SLOT_W, BoardSlot.SLOT_H)
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orig_parent.add_child(placeholder)
	orig_parent.move_child(placeholder, orig_index)
	orig_parent.remove_child(slot)
	$UI.add_child(slot)
	slot.position = atk_rect.position
	slot.size = atk_rect.size
	return [orig_parent, orig_index, placeholder]

## Restore a slot from $UI back to its original HBoxContainer position.
## Also unfreezes visuals and fires deferred death animations.
func _restore_slot_from_lunge(slot: BoardSlot, orig_parent: Control, orig_index: int, placeholder: Control) -> void:
	$UI.remove_child(slot)
	orig_parent.add_child(slot)
	orig_parent.move_child(slot, orig_index)
	placeholder.queue_free()
	slot.freeze_visuals = false
	slot._refresh_visuals()

func _play_attack_anim(atk_slot: BoardSlot, def_slot: BoardSlot, damage: int,
		attacker: MinionInstance = null, defender: MinionInstance = null,
		is_crit: bool = false, counter_damage: int = 0,
		damage_hp_delta: int = -1, counter_hp_delta: int = -1) -> void:
	# Defaults: if caller doesn't supply HP deltas, fall back to the popup damage
	# (preserves old behavior for any non-attack-resolution caller).
	if damage_hp_delta < 0:
		damage_hp_delta = damage
	if counter_hp_delta < 0:
		counter_hp_delta = counter_damage
	var atk_rect  := atk_slot.get_global_rect()
	var def_rect  := def_slot.get_global_rect()
	var direction := (def_rect.get_center() - atk_rect.get_center()).normalized()
	var lunge_pos := atk_rect.position + direction * 55.0

	# Champion strike detection
	var is_champ_attack: bool = attacker != null and attacker.card_data != null \
			and attacker.card_data is MinionCardData and (attacker.card_data as MinionCardData).is_champion

	var lunge_info := _reparent_slot_for_lunge(atk_slot)
	var orig_parent: Control = lunge_info[0]
	var orig_index: int = lunge_info[1]
	var placeholder: Control = lunge_info[2]

	var tw := create_tween()
	tw.tween_property(atk_slot, "position", lunge_pos, 0.10)
	tw.tween_callback(func() -> void:
		if is_champ_attack:
			AudioManager.play_sfx("res://assets/audio/sfx/minions/champion_claw_slash.wav")
			ChampionStrikeVFX.spawn_claw_mark(_vfx_layer, def_slot)
			ChampionStrikeVFX.shake(def_slot, self)
		else:
			AudioManager.play_sfx("res://assets/audio/sfx/minions/minion_clash.wav", -10.0)
		_flash_slot(def_slot)
		if damage > 0:
			var atk_school: int = Enums.DamageSchool.NONE
			if attacker != null and attacker.card_data is MinionCardData:
				atk_school = (attacker.card_data as MinionCardData).attack_damage_school
			_spawn_damage_popup(def_rect.get_center(), damage, is_crit, atk_school)
			# Combat damage already applied by the time the lunge tween reaches
			# this callback — current_health is post-damage. Reconstruct pre-HP
			# using the HP delta (clamped to pre_hp), not the popup damage which
			# may exceed it on overkill.
			if defender != null:
				var from_hp: int = defender.current_health + damage_hp_delta
				def_slot.animate_hp_change(from_hp, defender.current_health)
		if counter_damage > 0:
			_flash_slot(atk_slot)
			var def_school: int = Enums.DamageSchool.NONE
			if defender != null and defender.card_data is MinionCardData:
				def_school = (defender.card_data as MinionCardData).attack_damage_school
			_spawn_damage_popup(atk_slot.get_global_rect().get_center(), counter_damage, false, def_school)
			if attacker != null:
				var atk_from_hp: int = attacker.current_health + counter_hp_delta
				atk_slot.animate_hp_change(atk_from_hp, attacker.current_health)
	)
	tw.tween_property(atk_slot, "position", atk_rect.position, 0.16)
	tw.tween_callback(func() -> void:
		_restore_slot_from_lunge(atk_slot, orig_parent, orig_index, placeholder)
		def_slot.freeze_visuals = false
		def_slot._refresh_visuals()
		if attacker: state._refresh_slot_for(attacker)
		if defender: state._refresh_slot_for(defender)
	)
	await tw.finished

func _play_hero_attack_anim(atk_slot: BoardSlot, hero_panel: Control, attacker: MinionInstance = null) -> void:
	var atk_rect   := atk_slot.get_global_rect()
	var hero_rect  := hero_panel.get_global_rect()
	var direction  := (hero_rect.get_center() - atk_rect.get_center()).normalized()
	var lunge_pos  := atk_rect.position + direction * 55.0

	# Champion strike detection
	var is_champ_attack: bool = attacker != null and attacker.card_data != null \
			and attacker.card_data is MinionCardData and (attacker.card_data as MinionCardData).is_champion

	var lunge_info := _reparent_slot_for_lunge(atk_slot)
	var orig_parent: Control = lunge_info[0]
	var orig_index: int = lunge_info[1]
	var placeholder: Control = lunge_info[2]

	var tw := create_tween()
	tw.tween_property(atk_slot, "position", lunge_pos, 0.10)
	tw.tween_callback(func() -> void:
		if is_champ_attack:
			AudioManager.play_sfx("res://assets/audio/sfx/minions/champion_claw_slash.wav")
			ChampionStrikeVFX.spawn_claw_mark_on_panel(_vfx_layer, hero_panel)
			ChampionStrikeVFX.shake(hero_panel, self)
		else:
			AudioManager.play_sfx("res://assets/audio/sfx/minions/minion_attack_hero.wav")
		var ftw := create_tween()
		ftw.tween_property(hero_panel, "modulate", Color(1.8, 0.30, 0.30, 1.0), 0.06)
		ftw.tween_property(hero_panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.22)
	)
	tw.tween_property(atk_slot, "position", atk_rect.position, 0.16)
	tw.tween_callback(func() -> void:
		_restore_slot_from_lunge(atk_slot, orig_parent, orig_index, placeholder)
	)
	await tw.finished

func _flash_slot(slot: BoardSlot) -> void:
	if vfx_bridge != null:
		vfx_bridge.flash_slot(slot)

## Show a large centred card visual when a spell/trap/environment is cast or triggered.
## Delegated to vfx_bridge — animates the card preview during cast.
func _show_card_cast_anim(card: CardData, is_enemy: bool, on_impact: Callable) -> void:
	if vfx_bridge != null:
		vfx_bridge.show_card_cast_anim(card, is_enemy, on_impact)

## Delegated to vfx_bridge — "COUNTERED!" reveal + shake + fizzle.
func _show_spell_countered_anim(card: CardData) -> void:
	if vfx_bridge != null:
		vfx_bridge.show_spell_countered_anim(card)

## Show or hide the counter-spell warning label based on current counter state.
func _update_counter_warning() -> void:
	counter_warning.update()

## Hero/minion flash + popup primitives all delegated to vfx_bridge.
func _flash_hero(target: String, amount: int, on_done: Callable = Callable(), school: int = Enums.DamageSchool.NONE, is_crit: bool = false) -> void:
	if vfx_bridge != null:
		vfx_bridge.flash_hero(target, amount, on_done, school, is_crit)

func _flash_hero_heal(target: String, amount: int) -> void:
	if vfx_bridge != null:
		vfx_bridge.flash_hero_heal(target, amount)

func _spawn_damage_popup(screen_center: Vector2, damage: int, is_crit: bool = false,
		school: int = Enums.DamageSchool.NONE) -> void:
	if vfx_bridge != null:
		vfx_bridge.spawn_damage_popup(screen_center, damage, is_crit, school)

# ---------------------------------------------------------------------------
# Enemy attack visuals
# ---------------------------------------------------------------------------

# LogType / _log() are facades that delegate to CombatLog. Kept on the scene
# so the dozens of internal call sites and ~5 external callers (handlers,
# effects, relics, EnemyAI, CheatPanel) don't need to know about the move.
const _LogType := CombatLog.LogType

func _highlight_empty_player_slots() -> void:
	targeting.highlight_empty_player_slots()

func _highlight_valid_attack_targets() -> void:
	targeting.highlight_valid_attack_targets()
