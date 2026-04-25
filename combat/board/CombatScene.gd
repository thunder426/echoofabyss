## CombatScene.gd
## Root script for the combat scene.
## Wires together TurnManager, CombatManager, BoardSlots, and the UI.
## Handles player input (selecting cards, selecting targets, attacking).
extends Node2D

const CARD_VISUAL_SCENE := preload("res://combat/ui/CardVisual.tscn")
const DAMAGE_FONT: Font = preload("res://assets/fonts/cinzel/Cinzel-Bold.ttf")

# ---------------------------------------------------------------------------
# Node references — resolved automatically in _find_nodes()
# ---------------------------------------------------------------------------

var turn_manager: TurnManager
var enemy_ai: EnemyAI

## Most recent player resource-growth choice ("" | "essence" | "mana").
## Set by the end-turn buttons; read by F15 abyssal_mandate passive.
var last_player_growth: String = ""

## F15 Abyss Sovereign phase marker (1 = P1, 2 = P2). Flips to 2 via
## PhaseTransition when P1 HP hits 0. Non-F15 fights leave this at 1.
var _sovereign_phase: int = 1
## Turn number at which the P1→P2 transition fired. 0 = never transitioned.
var _sovereign_transition_turn: int = 0

## Stub hook for the Phase 2 transition VFX (screen darken, banner, portrait
## swap, etc.). Called by PhaseTransition after state has been reset. Leave
## empty until polish pass — transition still functions without VFX.
func _play_phase2_vfx() -> void:
	_log("THE SOVEREIGN REAWAKENS — Phase 2 begins.", _LogType.ENEMY)

## Deferred by _on_hero_damaged after a P1→P2 transition. Runs next frame so
## the current damage/attack resolution can finish before we yank player
## control. Ends the player turn and lets the normal enemy-turn pipeline fire.
func _force_end_player_turn_for_phase_transition() -> void:
	if _combat_ended:
		return
	if not turn_manager.is_player_turn:
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
	# End the turn — turn_manager will emit turn_ended(true) then turn_started(false),
	# which routes through _on_turn_started and kicks off enemy_ai.run_turn().
	turn_manager.end_player_turn()
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

## Popup stagger — popups near the same position get offset vertically so they don't overlap.
const _POPUP_STACK_THRESHOLD := 50.0  # pixels — popups within this distance stack
const _POPUP_STACK_OFFSET := 30.0     # pixels — vertical offset per stacked popup
var _recent_popups: Array = []        # Array[{center: Vector2, time: float}]

## True while an enemy summon card reveal is on screen — EnemyAI waits on this before its next action.
var _enemy_summon_reveal_active: bool = false
signal enemy_summon_reveal_done()

## True while an enemy spell cast animation + VFX is on screen — EnemyAI waits on this before its next action
## so consecutive enemy spells don't overlap their VFX.
var _enemy_spell_cast_active: bool = false
signal enemy_spell_cast_done()

## True while a minion on-play VFX is playing (e.g. Frenzied Imp's hurl). EnemyAI
## and consecutive actions await on_play_vfx_done before continuing so the full
## visual plays out before the next card/attack.
var _on_play_vfx_active: bool = false
signal on_play_vfx_done()

## Count of death animations currently playing (_animate_minion_death in-flight).
## EnemyAI and champion auto-summons await death_anims_done when this is > 0 so
## player can parse what just died before the next action.
var _active_death_anims: int = 0
signal death_anims_done()

# Enemy hero status panel
var _enemy_hero_panel: EnemyHeroPanel = null
var _enemy_status_panel: Control = null   ## alias → _enemy_hero_panel (backward-compat)
var _enemy_panel_bg: Panel = null         ## alias → _enemy_hero_panel.highlight_panel
var enemy_hp_max: int = 0

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

var combat_manager := CombatManager.new()

## Central event dispatcher — populated by _setup_triggers() in _ready().
var trigger_manager: TriggerManager
var _handlers: CombatHandlers
var _hardcoded: HardcodedEffects
var _relic_runtime: RelicRuntime
var _relic_effects: RelicEffects
var _relic_bar: RelicBar

## Centralised VFX dispatcher — resolved in _find_nodes. All spell/apply VFX
## should be parented via vfx_controller.spawn(vfx) so they render on VfxLayer
## (CanvasLayer layer=2, above UI).
var vfx_controller: VfxController = null
var _vfx_layer: CanvasLayer = null
var _vfx_shake_root: Control = null

## Relic state flags (set by relic effects, consumed by combat logic)
var _relic_hero_immune: bool = false    ## Bone Shield: ignore damage this turn
var _relic_cost_reduction: int = 0      ## Dark Mirror: reduce next card cost
var _relic_extra_turn: bool = false     ## Void Hourglass: take extra turn

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
# Each entry is {slot: BoardSlot, pos: Vector2, minion: MinionInstance} — position captured when slot is still in-place.
var _deferred_death_slots: Array = []

# Minions whose on-death effects are deferred until after the death animation +
# on-death icon VFX finishes.  CombatHandlers.on_minion_died_death_effect skips
# these; _animate_minion_death resolves them after the icon fades.
var _pending_on_death_vfx: Array[MinionInstance] = []

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
var _pending_relic_index: int = -1  ## Index into RelicRuntime.relics — used for refund on cancel

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
## (Removed: relic_first_card_free — old passive relic system replaced by activated relics)

# ---------------------------------------------------------------------------
# Talent state — reset each combat
# ---------------------------------------------------------------------------

## Void Mark stacks on the enemy hero (accumulate through the run)
var enemy_void_marks: int = 0

## Seris — active spell damage bonus from void_amplification, set at the start of a
## player spell cast (sum of Corruption stacks across friendly Demons * 50) and
## cleared after resolution. `_spell_dmg` adds it to every spell-damage target hit.
var _player_spell_damage_bonus: int = 0

## Seris — Corrupt Flesh activated ability. `_seris_corrupt_targeting` is true while
## the player is picking a friendly Demon to corrupt; `_seris_corrupt_used_this_turn`
## enforces the 1-per-turn cap. Reset to false on each ON_PLAYER_TURN_START.
var _seris_corrupt_targeting: bool = false
var _seris_corrupt_used_this_turn: bool = false

## Seris — Flesh counter. Gains 1 per friendly Demon death (Fleshbind passive), capped at player_flesh_max.
## Resets each combat (CombatScene is re-instantiated). Spent by Seris talent effects.
var player_flesh:     int = 0
var player_flesh_max: int = 5

## Seris — Fiendish Pact pending Mana discount. Set by the Fiendish Pact spell,
## consumed when the next Demon is played (capped at that card's mana_cost).
## Cleared at player turn start along with cost_delta.
var _fiendish_pact_pending: int = 0

## Seris — Forge Counter (Demon Forge branch). Incremented when a Demon is sacrificed; at threshold
## the Soul Forge talent auto-summons a Forged Demon and resets the counter.
## Threshold is set by CombatSetup from the talent registry (forge_momentum reduces it from 3 to 2).
var forge_counter:            int = 0
var forge_counter_threshold:  int = 3

## Behavior modules for Flesh/Forge primitives. Vars above stay on scene
## (SimState mirror constraint); these classes own only the gain/spend logic.
var flesh: Flesh = null
var forge: Forge = null

## Targeting helper — owns the on-play prompt label, target validation, and
## slot highlighting. CombatScene keeps thin facades for play-card flow.
var targeting: Targeting = null

## Bottom-left card preview shown on hand/board hover.
var large_preview: LargePreview = null

## "Your next spell will be COUNTERED" warning label.
var counter_warning: CounterWarning = null

## Passive-configurable stats — set by CombatSetup from the registry at combat start.
var void_mark_damage_per_stack: int = 25  ## deepened_curse sets this to 40
var rune_aura_multiplier:       int = 1   ## runic_attunement sets this to 2

## True until the first hit lands on the player (Shadow Veil: ignore first damage)
## (Removed: _shadow_veil_spent — old Shadow Veil replaced by Bone Shield activated relic)

## Set to true the moment victory/defeat is triggered — prevents re-entrant damage/scene calls
var _combat_ended: bool = false

## Pending spell cost penalty to apply to the enemy on their next turn (from Spell Taxer).
var _spell_tax_for_enemy_turn: int = 0

## Pending spell cost penalty to apply to the player on their next turn (from enemy Spell Taxer).
var _spell_tax_for_player_turn: int = 0

## When true, the player's current mana is set to 0 at the start of their next turn (Void Rift Lord).
var _void_mana_drain_pending: bool = false

## Active spell cost penalty for the player this turn (applied at turn start, cleared at turn end).
var player_spell_cost_penalty: int = 0

## Set to true by Silence Trap to skip the enemy spell's effect resolution.
var _spell_cancelled: bool = false

## When true, enemy traps cannot trigger (set by Saboteur Adept, cleared at player turn end).
var _enemy_traps_blocked: bool = false

## When true, player traps cannot trigger (set by enemy Saboteur Adept, cleared at enemy turn end).
var _player_traps_blocked: bool = false

## Spell counter: when > 0, next spell cast by this side is cancelled and counter decrements.
## Set by Phase Disruptor ON PLAY (COUNTER_SPELL effect).
var _player_spell_counter: int = 0
var _enemy_spell_counter: int = 0

## Persistent warning label shown when the player's next spell will be countered.
# _counter_warning_label moved into CounterWarning.gd (counter_warning.label)

## Transient prompt label shown during on-play target selection (required or
## optional). Text comes from MinionCardData.on_play_target_prompt. Shared
## across all targeted-play cards.
# _target_prompt_label moved into Targeting.gd (targeting.prompt_label)

## Prevents Soul Rune from firing more than once per enemy turn.
var _soul_rune_fires_this_turn: int = 0

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

## Act 4 passive stats — set dynamically by CombatSetup via scene.set().
var _vp_pre_crit_stacks: int = 0
var _spirit_conscription_fired: bool = false
var crit_multiplier: float = 2.0
var enemy_crit_multiplier: float = 0.0  ## Per-side override; 0 = use global
var _enemy_crits_consumed: int = 0  ## Total enemy crits consumed (for champion tracking)
var _player_crits_consumed: int = 0
var _last_crit_attacker: MinionInstance = null  ## Set by _apply_crit for post-crit processing
var _last_attack_was_crit: bool = false  ## Transient: true if the most recent attack consumed a crit
## Set by CombatManager.resolve_minion_attack / resolve_minion_attack_hero for the duration of
## the attack; read by death-trigger firing so ctx.attacker can be populated. Cleared after.
var _last_attacker: MinionInstance = null
var _dark_channeling_active: bool = false
var _dark_channeling_multiplier: float = 1.0
var _dark_channeling_amp_count: int = 0
var _dark_channeling_amp_by_spell: Dictionary = {}  ## spell_id -> count
var _dark_channeling_dmg_by_spell: Dictionary = {}  ## spell_id -> extra damage from amp

## Enemy champion state — set dynamically by CombatSetup via scene.set().
var _champion_summon_count: int = 0
var _corruption_detonation_times: int = 0
var _ritual_invoke_times: int = 0
var _handler_spark_buff_times: int = 0
var _smoke_veil_fires: int = 0
var _smoke_veil_damage_prevented: int = 0
var _abyssal_plague_fires: int = 0
var _abyssal_plague_kills: int = 0
var _champion_rip_attack_ids: Array = []
var _champion_rip_summoned: bool = false
var _champion_cb_death_count: int = 0
var _champion_cb_summoned: bool = false
var _champion_im_frenzy_count: int = 0
var _champion_im_summoned: bool = false
# Act 2 champion state
var _champion_acp_stacks_consumed: int = 0
var _champion_acp_summoned: bool = false
var _champion_vr_summoned: bool = false
var _champion_ch_spark_count: int = 0
var _champion_ch_summoned: bool = false
var _champion_ch_aura_dmg: int = 0

## Act 3 champion: Rift Stalker
var _champion_rs_spark_dmg: int = 0
var _champion_rs_summoned: bool = false

## Act 3 champion: Void Aberration
var _champion_va_sparks_consumed: int = 0
var _champion_va_summoned: bool = false

## Act 4 champion: Void Scout
var _champion_vs_crits_consumed: int = 0
var _champion_vs_summoned: bool = false

## Act 4 champion: Void Warband
var _champion_vw_spirits_consumed: int = 0
var _champion_vw_summoned: bool = false
var _vw_behemoth_plays: int = 0
var _vw_bastion_plays: int = 0
var _void_echo_fired_this_turn: bool = false
var _vw_death_crit_grants: int = 0
var _vw_behemoth_lost: Dictionary = {"consumed": 0, "damage": 0, "combat": 0, "survived": 0}
var _vw_bastion_lost: Dictionary = {"consumed": 0, "damage": 0, "combat": 0, "survived": 0}

## Act 4 champion: Void Captain
var _champion_vc_tc_cast: int = 0
var _champion_vc_summoned: bool = false

## Act 4 champion: Void Champion (F14)
var _champion_vch_crit_kills: int = 0
var _champion_vch_summoned: bool = false

## Act 3 champion: Void Herald
var _champion_vh_spark_cards_played: int = 0
var _champion_vh_summoned: bool = false

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	trigger_manager = TriggerManager.new()
	_hardcoded = HardcodedEffects.new()
	_hardcoded.setup(self)
	flesh = Flesh.new(self)
	forge = Forge.new(self)
	targeting = Targeting.new(self)
	large_preview = LargePreview.new(self)
	counter_warning = CounterWarning.new(self)
	_find_nodes()
	_connect_buff_signal()
	_register_buff_preludes()
	_connect_sacrifice_signal()
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
			fight_label.text = "Fight %d / %d" % [GameManager.run_node_index, GameManager.TOTAL_FIGHTS]

	# Build the deck from GameManager and begin combat
	var deck_ids: Array[String] = GameManager.player_deck
	var deck: Array[CardData] = CardDatabase.get_cards(deck_ids)
	turn_manager.player_board = player_board
	turn_manager.enemy_board = enemy_board
	_setup_enemy_ai()
	if GameManager.current_enemy != null:
		_active_enemy_passives = GameManager.current_enemy.passives.duplicate()
	var ui_root: Node = get_node_or_null("UI")
	_enemy_hero_panel = EnemyHeroPanel.new()
	_enemy_hero_panel.setup(self, ui_root)
	if ui_root:
		ui_root.add_child(_enemy_hero_panel)
	_enemy_status_panel = _enemy_hero_panel
	_enemy_panel_bg = _enemy_hero_panel.highlight_panel
	_enemy_hero_panel.hero_pressed.connect(_on_enemy_hero_button_pressed)
	_player_hero_panel = PlayerHeroPanel.new()
	_player_hero_panel.setup(self, ui_root)
	if ui_root:
		ui_root.add_child(_player_hero_panel)
	_player_status_panel = _player_hero_panel
	_player_hero_panel.update(player_hp, GameManager.player_hp_max)
	_setup_second_wind_indicator(ui_root)
	_pip_bar = PipBar.new()
	_pip_bar.setup(self, ui_root, essence_label, mana_label)
	large_preview.setup()
	turn_manager.start_combat(deck)
	_setup_triggers()
	_setup_relics()
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
	turn_manager            = $TurnManager
	enemy_ai               = $EnemyAI
	vfx_controller          = $VfxController
	_vfx_layer              = $VfxLayer
	_vfx_shake_root         = $VfxLayer/VfxShakeRoot
	vfx_controller.setup(self, _vfx_layer, _vfx_shake_root)
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
	if GameManager.current_enemy != null:
		enemy_ai._limited_cards = GameManager.current_enemy.limited_cards
	enemy_ai.setup_deck(enemy_deck)

func _connect_turn_manager() -> void:
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.resources_changed.connect(_on_resources_changed)
	turn_manager.card_drawn.connect(_on_card_drawn)
	turn_manager.card_generated.connect(_on_card_generated)

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
	combat_manager.scene = self
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
	if environment_slot:
		environment_slot.mouse_entered.connect(func() -> void:
			if active_environment:
				_show_large_preview(active_environment))
		environment_slot.mouse_exited.connect(_hide_large_preview)

func _on_trap_slot_hover(idx: int) -> void:
	if idx < active_traps.size():
		_show_large_preview(active_traps[idx])

func _on_enemy_trap_slot_hover(idx: int) -> void:
	var traps: Array = enemy_ai.active_traps if enemy_ai else []
	if idx < traps.size():
		var trap: TrapCardData = traps[idx] as TrapCardData
		# Only show preview for runes (face-up), not concealed traps
		if trap.is_rune:
			_show_large_preview(trap)

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
	_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)
	# Safety sweep: remove any dead minions still visually on the board.
	# This catches edge cases where minion_vanished fired but the slot wasn't properly cleared.
	_sweep_dead_minions()
	# Refresh all slot visuals — clears Exhausted badges and any stale occupied states
	for slot in player_slots + enemy_slots:
		slot._refresh_visuals()
	# Fire turn-start events — all effects are handled by registered listeners in _setup_triggers().
	if is_player_turn:
		imp_evolution_used_this_turn     = false
		player_spell_cost_penalty = _spell_tax_for_player_turn
		_spell_tax_for_player_turn = 0
		if _void_mana_drain_pending:
			_void_mana_drain_pending = false
			turn_manager.mana = 0
			turn_manager.resources_changed.emit(
				turn_manager.essence, turn_manager.essence_max,
				turn_manager.mana, turn_manager.mana_max)
			_log("  Void Rift Lord: your Mana has been drained to 0!", _LogType.ENEMY)
		_relic_hero_immune = false
		_relic_cost_reduction = 0
		for inst in turn_manager.player_hand:
			inst.cost_delta = 0
		_fiendish_pact_pending = 0
		_refresh_hand_spell_costs()
		if _relic_runtime:
			_relic_runtime.on_turn_start()
			if _relic_bar:
				_relic_bar.refresh()
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
		_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)

func _on_turn_ended(is_player_turn: bool) -> void:
	_clear_all_highlights()
	_enemy_hero_panel.show_attackable(false)
	selected_attacker = null
	pending_play_card = null
	if is_player_turn:
		# Imp Overload: temp Void Imps summoned this turn expire now
		for imp in _temp_imps.duplicate():
			if imp in player_board:
				_log("  Imp Overload: temp Void Imp expires.", _LogType.DEATH)
				combat_manager.kill_minion(imp)
		_temp_imps.clear()
		# Clear player spell cost penalty after player turn ends
		player_spell_cost_penalty = 0
		_enemy_traps_blocked = false
		# Void Hourglass: take another player turn instead of passing to enemy
		if _relic_extra_turn:
			_relic_extra_turn = false
			_log("  Void Hourglass: extra turn!", _LogType.PLAYER)
			turn_manager.start_player_turn()
	else:
		# Clear enemy spell cost penalty after their turn ends
		enemy_ai.spell_cost_penalty = 0
		_player_traps_blocked = false

func _on_resources_changed(essence: int, essence_max: int, mana: int, mana_max: int) -> void:
	if essence_label:
		essence_label.text = "%d/%d" % [essence, essence_max]
	if mana_label:
		mana_label.text = "%d/%d" % [mana, mana_max]
	if hand_display:
		hand_display.refresh_playability(essence, mana, _relic_cost_reduction, _relic_cost_reduction)
	_refresh_hand_spell_costs()
	if _pip_bar:
		_pip_bar.update(essence, essence_max, mana, mana_max)
		# Pulse the column border to signal gain (green) or spend (red/orange)
		if _prev_essence >= 0 and essence != _prev_essence:
			_pip_bar.pulse_col(true, essence > _prev_essence)
		if _prev_mana >= 0 and mana != _prev_mana:
			_pip_bar.pulse_col(false, mana > _prev_mana)
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
		# Don't refresh playability immediately — the shimmer animation sets modulate
		# and _refresh_playable_state is called at the end of the tween
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, "player")
	ctx.card = inst.card_data
	trigger_manager.fire(ctx)

func _on_card_generated(inst: CardInstance) -> void:
	if hand_display:
		hand_display.add_card_generated(inst)
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, "player")
	ctx.card = inst.card_data
	trigger_manager.fire(ctx)

func _on_card_anim_finished() -> void:
	if hand_display:
		hand_display.refresh_playability(turn_manager.essence, turn_manager.mana, _relic_cost_reduction, _relic_cost_reduction)
		hand_display.refresh_condition_glows(self, turn_manager.essence, turn_manager.mana)

func _on_end_turn_essence_pressed() -> void:
	turn_manager.grow_essence_max()
	last_player_growth = "essence"
	_do_end_turn()

func _on_end_turn_mana_pressed() -> void:
	turn_manager.grow_mana_max()
	last_player_growth = "mana"
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
	_pip_bar.stop_blink()
	pending_play_card = null
	pending_minion_target = null
	_awaiting_minion_target = false
	_clear_all_highlights()
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
		_pip_bar.stop_blink()

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
		var extra_mana := 1 if (_card_has_tag(mc, "base_void_imp") and _has_talent("piercing_void")) else 0
		ess_spend = maxi(0, mc.essence_cost - _peek_fiendish_pact_discount(mc))
		mna_spend = maxi(0, mc.mana_cost + extra_mana)
	elif card_data is TrapCardData:
		mna_spend = _effective_trap_cost(card_data as TrapCardData)
	elif card_data is EnvironmentCardData:
		mna_spend = (card_data as EnvironmentCardData).cost
	# Dark Mirror: reduce both costs for preview
	if _relic_cost_reduction > 0:
		ess_spend = maxi(0, ess_spend - _relic_cost_reduction)
		mna_spend = maxi(0, mna_spend - _relic_cost_reduction)
	if not turn_manager.can_afford(ess_spend, mna_spend):
		return
	_pip_bar.start_blink(ess_spend, mna_spend, ess_gain, mna_gain)

## Handle a spell card being selected from hand.
## Instant spells cast immediately (cost preview shown on hover).
## Targeted spells enter pending state and highlight valid targets.
func _begin_spell_select(spell: SpellCardData) -> void:
	if not turn_manager.can_afford(0, _effective_spell_cost(spell)):
		_cancel_card_select()
		return
	if not _player_can_afford_sparks(spell.void_spark_cost):
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
	var extra_mana := 1 if (_card_has_tag(mc, "base_void_imp") and _has_talent("piercing_void")) else 0
	var ess_cost := maxi(0, mc.essence_cost - _peek_fiendish_pact_discount(mc))
	if not turn_manager.can_afford(ess_cost, maxi(0, mc.mana_cost + extra_mana)):
		_cancel_card_select()
		return
	if not _player_can_afford_sparks(mc.void_spark_cost):
		_cancel_card_select()
		return
	# Check board space before highlighting
	if not player_slots.any(func(s: BoardSlot) -> bool: return s.is_empty()):
		_cancel_card_select()
		return
	_start_pip_blink_for_card(mc)   # ensure blink runs even if card wasn't hovered
	var has_targets: bool = _has_valid_minion_on_play_targets_for(_effective_target_type(mc))
	var is_optional: bool = _effective_target_optional(mc)
	var is_required: bool = mc.on_play_requires_target and not is_optional
	if is_required and has_targets:
		# Mandatory target — targets only; player must pick one before placement.
		_awaiting_minion_target = true
		_highlight_minion_on_play_targets(mc)
		_show_target_prompt(_effective_target_prompt(mc))
	elif is_optional and has_targets:
		# Optional target — highlight targets (yellow) AND empty slots (green).
		# Click a target to resolve effect + show placement; click a slot to
		# summon without the effect.
		_awaiting_minion_target = true
		_clear_all_highlights()
		var t_type: String = _effective_target_type(mc)
		var yellow := Color(1.0, 0.9, 0.2, 1.0)
		var yellow_picker := func(_s: BoardSlot) -> Color: return yellow
		if t_type in ["enemy_minion", "corrupted_enemy_minion"]:
			_highlight_slots(enemy_slots,
				func(s): return not s.is_empty() and _is_valid_minion_on_play_target(s.minion, t_type),
				yellow_picker)
		if t_type in ["friendly_minion", "friendly_minion_other", "friendly_demon"]:
			_highlight_slots(player_slots,
				func(s): return not s.is_empty() and _is_valid_minion_on_play_target(s.minion, t_type),
				yellow_picker)
		_highlight_slots(player_slots, func(s): return s.is_empty())
		_show_target_prompt(_effective_target_prompt(mc))
	else:
		# No valid targets (or card doesn't need one) — go straight to placement.
		# Effect will fire but resolve with null target (logs "no targets" and skips).
		_awaiting_minion_target = false
		_highlight_empty_player_slots()

func _on_hand_card_deselected() -> void:
	_pip_bar.stop_blink()
	pending_play_card = null
	pending_minion_target = null
	_awaiting_minion_target = false
	_hide_target_prompt()
	_tear_down_trap_env_targeting()
	_clear_all_highlights()

# ---------------------------------------------------------------------------
# Spell / Trap / Environment play
# ---------------------------------------------------------------------------

func _try_play_spell(spell: SpellCardData) -> void:
	if not _player_can_afford_sparks(spell.void_spark_cost):
		if hand_display:
			hand_display.deselect_current()
		return
	if spell.void_spark_cost > 0:
		_player_pay_sparks(spell.void_spark_cost)
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
	# Phase Disruptor counter: enemy counters player spell
	if _player_spell_counter > 0:
		_player_spell_counter -= 1
		_log("  Spell countered!", _LogType.ENEMY)
		_show_spell_countered_anim(spell)
		_update_counter_warning()
		return
	# Show large card preview; resolve effects on impact so damage visuals sync
	_show_card_cast_anim(spell, false, func() -> void:
		var resolve_damage := func(_i: int) -> void:
			_pre_player_spell_cast(spell)
			if not spell.effect_steps.is_empty():
				var ctx := EffectContext.make(self, "player")
				ctx.source_card_id = spell.id
				EffectResolver.run(spell.effect_steps, ctx)
			else:
				_resolve_spell_effect(spell.effect_id, null)
			_post_player_spell_cast(spell, null)
			var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
			spell_ctx.card = spell
			trigger_manager.fire(spell_ctx)
		await vfx_controller.play_spell(spell.id, "player", null, resolve_damage)
	)

func _try_play_trap(trap: TrapCardData) -> void:
	if active_traps.size() >= trap_slot_panels.size():
		_log("Trap slots are full.", _LogType.PLAYER)
		if hand_display:
			hand_display.deselect_current()
		return
	# Non-rune traps: only one of each type allowed on the board
	if not trap.is_rune:
		for existing in active_traps:
			if not existing.is_rune and existing.id == trap.id:
				_log("You already have %s set." % trap.card_name, _LogType.PLAYER)
				if hand_display:
					hand_display.deselect_current()
				pending_play_card = null
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
	trap_env_display.update_environment()

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
		var mc := pending_play_card.card_data as MinionCardData
		# Still waiting for a target? — slot clicks are blocked UNLESS the card's
		# target is optional, in which case the slot click bypasses targeting and
		# the minion summons without the effect resolving.
		if _awaiting_minion_target and not _effective_target_optional(mc):
			return
		var inst_to_play := pending_play_card
		var on_play_target := pending_minion_target
		pending_minion_target = null
		pending_play_card = null
		_awaiting_minion_target = false
		_hide_target_prompt()
		_clear_all_highlights()
		_try_play_minion_animated(inst_to_play, slot, on_play_target)

func _on_player_slot_clicked_occupied(_slot: BoardSlot, minion: MinionInstance) -> void:
	if not turn_manager.is_player_turn:
		return
	# Seris — Corrupt Flesh activated ability targeting mode.
	if _seris_corrupt_targeting:
		_seris_corrupt_apply_target(minion)
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
		if _awaiting_minion_target and _is_valid_minion_on_play_target(minion, _effective_target_type(mc)):
			pending_minion_target = minion
			_awaiting_minion_target = false
			_highlight_empty_player_slots()
			_mark_selected_target(minion)
			_show_target_prompt("Target selected. Choose a slot.")
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
	# If a relic is awaiting a target, resolve it
	if _pending_relic_target != "":
		_resolve_relic_target_minion(minion)
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
		if _awaiting_minion_target and _is_valid_minion_on_play_target(minion, _effective_target_type(mc)):
			pending_minion_target = minion
			_awaiting_minion_target = false
			_highlight_empty_player_slots()
			_mark_selected_target(minion)
			_show_target_prompt("Target selected. Choose a slot.")
			return
	if selected_attacker == null:
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
	_enemy_hero_panel.show_attackable(false)

# ---------------------------------------------------------------------------
# Minion play
# ---------------------------------------------------------------------------

func _try_play_minion(inst: CardInstance, slot: BoardSlot, on_play_target: MinionInstance = null) -> void:
	if not slot.is_empty():
		return
	var card := inst.card_data as MinionCardData
	if not _player_can_afford_sparks(card.void_spark_cost):
		return
	if card.void_spark_cost > 0:
		_player_pay_sparks(card.void_spark_cost)
	# Talent: piercing_void — base Void Imp costs +1 Mana
	var extra_mana := 1 if (_card_has_tag(card, "base_void_imp") and _has_talent("piercing_void")) else 0
	var fp_discount := _peek_fiendish_pact_discount(card)
	if not _pay_card_cost(maxi(0, card.essence_cost - fp_discount), maxi(0, card.mana_cost + extra_mana)):
		return
	if fp_discount > 0:
		_log("  Fiendish Pact: %s costs %d less Essence." % [card.card_name, fp_discount], _LogType.PLAYER)
		_consume_fiendish_pact_discount()
	_log("You play: %s" % card.card_name)
	var instance := MinionInstance.create(card, "player")
	instance.card_instance = inst
	# Place visually first so the slot is not mistakenly taken by tokens summoned during on-play.
	# Do NOT append to player_board yet — on-play effects should not see this minion on the board.
	AudioManager.play_sfx("res://assets/audio/sfx/minions/minion_summon.wav", -20.0)
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
	_maybe_spawn_aura_pulse(card, slot)
	_refresh_hand_spell_costs()


## Animated variant of _try_play_minion — fires card flight + landing before triggers.
## State changes happen immediately; triggers fire after landing animation.
## Called without await so input is never blocked.
func _try_play_minion_animated(inst: CardInstance, slot: BoardSlot, on_play_target: MinionInstance = null) -> void:
	if not slot.is_empty():
		return
	var card := inst.card_data as MinionCardData
	if not _player_can_afford_sparks(card.void_spark_cost):
		return
	if card.void_spark_cost > 0:
		_player_pay_sparks(card.void_spark_cost)
	var extra_mana := 1 if (_card_has_tag(card, "base_void_imp") and _has_talent("piercing_void")) else 0
	var fp_discount := _peek_fiendish_pact_discount(card)
	if not _pay_card_cost(maxi(0, card.essence_cost - fp_discount), maxi(0, card.mana_cost + extra_mana)):
		return
	if fp_discount > 0:
		_log("  Fiendish Pact: %s costs %d less Essence." % [card.card_name, fp_discount], _LogType.PLAYER)
		_consume_fiendish_pact_discount()
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
		_maybe_spawn_aura_pulse(card, slot)
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

## Pack Chain VFX — visualize pack_instinct when a new feral imp joins the pack.
## Refreshes the ENTIRE pack network: each feral imp re-links to its adjacent
## neighbors. Isolated imps (no adjacent feral imp) fall back to linking with the
## single nearest other feral imp by slot index distance.
## Chain endpoints are anchored at slot edges (facing each other), not slot centers.
func _spawn_pack_chain_vfx_for_new_imp(_new_imp: MinionInstance, side: String = "enemy") -> void:
	var slots: Array[BoardSlot] = enemy_slots if side == "enemy" else player_slots

	# Collect every feral-imp slot on this side
	var imp_slots: Array[BoardSlot] = []
	for s in slots:
		if s.minion != null and _minion_has_tag(s.minion, "feral_imp"):
			imp_slots.append(s)
	if imp_slots.size() < 2:
		return

	# Build the set of chain pairs — each imp links to adjacent imps (slot index ±1);
	# imps with no adjacent feral imp fall back to their single nearest by index distance.
	# Deduped so we don't render the same pair twice.
	var pairs: Dictionary = {}  # "lo:hi" → [BoardSlot, BoardSlot]
	for imp in imp_slots:
		var adjacent: Array[BoardSlot] = []
		for other in imp_slots:
			if other != imp and abs(other.index - imp.index) == 1:
				adjacent.append(other)
		var targets: Array[BoardSlot] = adjacent
		if targets.is_empty():
			var nearest: BoardSlot = null
			for other in imp_slots:
				if other == imp:
					continue
				if nearest == null or abs(other.index - imp.index) < abs(nearest.index - imp.index):
					nearest = other
			if nearest != null:
				targets.append(nearest)
		for t in targets:
			var lo: int = mini(imp.index, t.index)
			var hi: int = maxi(imp.index, t.index)
			var key := "%d:%d" % [lo, hi]
			if not pairs.has(key):
				# Always store with the lower-index slot first for consistent anchor calculation
				var lo_slot: BoardSlot = imp if imp.index < t.index else t
				var hi_slot: BoardSlot = t if imp.index < t.index else imp
				pairs[key] = [lo_slot, hi_slot]

	if pairs.is_empty():
		return

	# Small delay so the chain gets its own beat after the enemy summon reveal
	# has fully faded and the landing punch has resolved.
	await get_tree().create_timer(0.35).timeout
	if not is_inside_tree():
		return
	# Re-verify feral imps still alive after the delay (a kill effect could have cleared them)
	var any_alive := false
	for pair in pairs.values():
		if pair[0].minion != null and pair[1].minion != null:
			any_alive = true
			break
	if not any_alive:
		return

	# SFX once per burst (not per chain) to avoid audio stacking
	AudioManager.play_sfx("res://assets/audio/sfx/minions/pack_chain.wav", -4.0)

	for pair in pairs.values():
		var a: BoardSlot = pair[0]
		var b: BoardSlot = pair[1]
		if a.minion == null or b.minion == null:
			continue  # imp died during the delay
		var chain := preload("res://combat/effects/PackChainVFX.gd").new()
		vfx_controller.spawn(chain)
		var a_pos: Vector2 = _pack_chain_anchor(a, b)
		var b_pos: Vector2 = _pack_chain_anchor(b, a)
		chain.play(a_pos, b_pos)

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

## Subscribe to BuffSystem.bus() so every on-play / spell buff fires the
## generic BuffApplyVFX. Auras and setup grants pass emit_vfx=false at the
## call site, so they never reach here.
func _connect_buff_signal() -> void:
	var bus: Object = BuffSystem.bus()
	if bus == null:
		return
	if not bus.is_connected("buff_applied", _on_buff_applied):
		bus.connect("buff_applied", _on_buff_applied)
	if not bus.is_connected("corruption_removed", _on_corruption_removed):
		bus.connect("corruption_removed", _on_corruption_removed)

## The signal bus is a static Object that outlives this scene, so the
## connection must be torn down or it'll point at a freed receiver next run.
func _exit_tree() -> void:
	var bus: Object = BuffSystem.bus()
	if bus != null and bus.is_connected("buff_applied", _on_buff_applied):
		bus.disconnect("buff_applied", _on_buff_applied)
	if bus != null and bus.is_connected("corruption_removed", _on_corruption_removed):
		bus.disconnect("corruption_removed", _on_corruption_removed)
	var sac_bus: Object = SacrificeSystem.bus()
	if sac_bus != null and sac_bus.is_connected("sacrifice_occurred", _on_sacrifice_occurred):
		sac_bus.disconnect("sacrifice_occurred", _on_sacrifice_occurred)
	# Reset Seris Corrupt Flesh global — otherwise a non-Seris run after a Seris run
	# would see inverted corruption on its Demons.
	MinionInstance.corruption_inverts_on_friendly_demons = false

## Seris — called before a player spell's effect resolves. Sets
## _player_spell_damage_bonus from Void Amplification (sum of Corruption on
## friendly Demons * 50). Cleared by _post_player_spell_cast after resolution.
## Tracks re-entrancy via _spell_cast_depth so nested/recursive casts don't
## re-compute from partial state.
var _spell_cast_depth: int = 0
func _pre_player_spell_cast(_spell: SpellCardData) -> void:
	_spell_cast_depth += 1
	if _spell_cast_depth > 1:
		return  # nested cast (e.g. void_resonance recast) uses the outer bonus
	if _has_talent("void_amplification"):
		var total_stacks: int = 0
		for m in player_board:
			if (m.card_data as MinionCardData).minion_type == Enums.MinionType.DEMON:
				total_stacks += BuffSystem.count_type(m, Enums.BuffType.CORRUPTION)
		_player_spell_damage_bonus = total_stacks * 50
	else:
		_player_spell_damage_bonus = 0

## Seris — called after a player spell's effect resolves. Handles the Void
## Resonance (Seris capstone) double-cast: if the player still has ≥5 Flesh
## AFTER any cost the spell itself deducted, consume all 5 and recursively
## resolve the spell's effect once more targeting the same minion.
func _post_player_spell_cast(spell: SpellCardData, target: MinionInstance) -> void:
	# Only try double-cast at the outermost cast level, and only once per cast.
	if _spell_cast_depth == 1 \
			and _has_talent("void_resonance_seris") \
			and player_flesh >= 5 \
			and not _double_cast_in_progress:
		_double_cast_in_progress = true
		if _spend_flesh(5):
			_log("  Void Resonance: recasting %s." % spell.card_name, _LogType.PLAYER)
			# If the original target is dead / gone, per design the recast fizzles but Flesh is still spent.
			if target == null or (is_instance_valid(target) and target.current_health > 0):
				if not spell.effect_steps.is_empty():
					var ctx := EffectContext.make(self, "player")
					ctx.chosen_target = target
					ctx.source_card_id = spell.id
					EffectResolver.run(spell.effect_steps, ctx)
				else:
					_resolve_spell_effect(spell.effect_id, target)
		_double_cast_in_progress = false
	_spell_cast_depth = maxi(0, _spell_cast_depth - 1)
	if _spell_cast_depth == 0:
		_player_spell_damage_bonus = 0

## Reentrancy guard so the recast doesn't itself trigger another recast.
var _double_cast_in_progress: bool = false

## Forward BuffSystem.corruption_removed into the TriggerManager as ON_CORRUPTION_REMOVED
## so corrupt_detonation and future listeners can react uniformly. ctx.minion = the minion,
## ctx.damage = stacks removed (overloaded field — see EventContext comments).
func _on_corruption_removed(minion: MinionInstance, stacks: int) -> void:
	if trigger_manager == null or minion == null or stacks <= 0:
		return
	var ctx := EventContext.make(Enums.TriggerEvent.ON_CORRUPTION_REMOVED, minion.owner)
	ctx.minion = minion
	ctx.damage = stacks
	trigger_manager.fire(ctx)

## Subscribe to SacrificeSystem.bus() so every ritual sacrifice (Abyssal
## Sacrifice, Blood Pact, Soul Shatter, Void Devourer) fires the generic
## SacrificeVFX. Plain deaths (combat, fatigue) never reach here — they go
## through combat_manager.kill_minion directly without emitting.
func _connect_sacrifice_signal() -> void:
	var bus: Object = SacrificeSystem.bus()
	if bus == null:
		return
	if not bus.is_connected("sacrifice_occurred", _on_sacrifice_occurred):
		bus.connect("sacrifice_occurred", _on_sacrifice_occurred)

## Minions currently mid-sacrifice — maps instance_id → delay in seconds
## that _animate_minion_death should wait before starting its ghost rise.
## Populated by _on_sacrifice_occurred right before kill_minion is called;
## drained by _animate_minion_death_body when the death anim actually runs.
## Keeping it as a plain Dictionary (not a Set) so the delay value can be
## tuned per-source later if a prelude adds extra windup time.
var _pending_sacrifice_ghost_delay: Dictionary = {}

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
	# Restore the art's alpha for the next minion that occupies this slot;
	# _refresh_visuals hides it behind visible=false but modulate persists.
	if art != null and is_instance_valid(art):
		art.modulate.a = 1.0
	# Trim the ghost-rise delay by the time we've already spent (visible
	# duration + fade), since _animate_minion_death_body awaits the
	# remaining time before starting the ghost rise.
	var elapsed: float = delay + fade_t
	for entry in _deferred_death_slots:
		if entry.get("slot") == slot:
			var dead_m: MinionInstance = entry.get("minion")
			if dead_m != null:
				var id: int = dead_m.get_instance_id()
				if _pending_sacrifice_ghost_delay.has(id):
					var remaining: float = float(_pending_sacrifice_ghost_delay[id]) - elapsed
					_pending_sacrifice_ghost_delay[id] = maxf(remaining, 0.0)
	_flush_deferred_deaths()

## Pending buff VFX to spawn — keyed by (minion, source_tag) so:
##   • Multiple steps from the same source on the same minion coalesce into
##     one VFX with combined deltas (e.g. Dark Empowerment's +ATK + +HP).
##   • Different sources hitting the same minion in the same frame get their
##     own VFX so per-source preludes don't collide.
## Each entry value: { "minion": MinionInstance, "source": String,
##                     "atk": int, "hp": int }
var _pending_buff_vfx: Dictionary = {}

## Coalesce signals by (minion, source_tag) and schedule one VFX per bucket.
func _on_buff_applied(minion: MinionInstance, _buff_type: int,
		atk_delta: int, hp_delta: int, source_tag: String) -> void:
	if minion == null or not is_instance_valid(minion):
		return
	if vfx_controller == null:
		return
	# Pack Frenzy owns its full buff visual — skip the generic blessing surge.
	if source_tag == "pack_frenzy":
		return
	var key: String = "%d|%s" % [minion.get_instance_id(), source_tag]
	var agg: Dictionary = _pending_buff_vfx.get(key, {
		"minion": minion, "source": source_tag, "atk": 0, "hp": 0
	})
	agg["atk"] = int(agg["atk"]) + atk_delta
	agg["hp"]  = int(agg["hp"])  + hp_delta
	var was_empty: bool = _pending_buff_vfx.is_empty()
	_pending_buff_vfx[key] = agg
	if was_empty:
		call_deferred("_flush_buff_vfx")

## Spawn one BuffApplyVFX per bucket with aggregated deltas, then clear.
## Looks up a per-source prelude in BuffVfxRegistry; empty Callable = skip.
func _flush_buff_vfx() -> void:
	var pending: Dictionary = _pending_buff_vfx
	_pending_buff_vfx = {}
	for key in pending.keys():
		var agg: Dictionary = pending[key]
		var m: MinionInstance = agg["minion"] as MinionInstance
		if m == null or not is_instance_valid(m):
			continue
		var slot: BoardSlot = _find_slot_for(m)
		if slot == null or slot.minion != m:
			continue
		var atk_d: int = int(agg["atk"])
		var hp_d:  int = int(agg["hp"])
		if atk_d == 0 and hp_d == 0:
			continue
		var src:     String     = String(agg["source"])
		var prelude: Callable   = BuffVfxRegistry.build_prelude(src, slot, atk_d, hp_d)
		var palette: Dictionary = BuffVfxRegistry.get_palette(src)
		var vfx := BuffApplyVFX.create(slot, atk_d, hp_d, prelude, palette)
		vfx_controller.spawn(vfx)

## Per-imp buff-gain VFX: scale/color pulse on the ATK label + a small green
## procedural chevron to the right of it, both timed to coincide with the chain
## VFX so the player reads "chains link → ATK jumps up" as one beat.
## The caller (on_board_changed_pack_instinct) has already reverted the ATK
## label's text to the old value; this method updates it to the new value.
func _spawn_pack_instinct_buff_vfx(minion: MinionInstance, _delta_atk: int) -> void:
	# Defer so it lands in the same visual beat as the chain animation
	await get_tree().create_timer(0.45).timeout
	if not is_inside_tree():
		return
	var slot: BoardSlot = _find_slot_for(minion)
	if slot == null or slot.minion != minion:
		return  # minion died or moved

	# Flip the ATK label to the new (buffed) value now — synchronised with the pulse
	var atk_lbl: Label = slot._atk_label
	if atk_lbl == null:
		return
	atk_lbl.text = str(minion.effective_atk())

	# Pulse the ATK label — scale up briefly + color flash to green
	atk_lbl.pivot_offset = atk_lbl.size * 0.5
	var original_color: Color = atk_lbl.get_theme_color("font_color")
	var pulse_color := Color(0.45, 1.00, 0.35, 1.0)
	var tw := atk_lbl.create_tween().set_parallel(true)
	tw.tween_property(atk_lbl, "scale", Vector2(1.35, 1.35), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(c: Color) -> void:
			atk_lbl.add_theme_color_override("font_color", c),
			original_color, pulse_color, 0.12)
	tw.chain().tween_property(atk_lbl, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(func(c: Color) -> void:
			atk_lbl.add_theme_color_override("font_color", c),
			pulse_color, original_color, 0.35)

	# Spawn a procedural green chevron to the right of the ATK label.
	# Rendered via _draw() on a helper Control — no font glyph needed.
	var chevron := preload("res://combat/effects/BuffChevronVFX.gd").new()
	slot.add_child(chevron)
	# Anchor just past the right edge of the atk_label, vertically centered
	chevron.position = atk_lbl.position + Vector2(atk_lbl.size.x - 10.0, atk_lbl.size.y * 0.5 - 8.0)
	chevron.set_size(Vector2(14, 16))
	chevron.play()

## Return the point on `from` slot's edge closest to `toward` slot — so chain VFX
## appears to emerge from the side of the minion facing its neighbor, not from
## its dead center.
func _pack_chain_anchor(from: BoardSlot, toward: BoardSlot) -> Vector2:
	var from_center: Vector2 = from.global_position + from.size * 0.5
	var toward_center: Vector2 = toward.global_position + toward.size * 0.5
	var dir: Vector2 = (toward_center - from_center).normalized()
	# Pull the anchor ~35% of the slot size toward the neighbor (stops inside the sprite's edge)
	var offset: float = min(from.size.x, from.size.y) * 0.35
	return from_center + dir * offset

## Dramatic entrance sequence for champion token summons.
## Shows card reveal → banner → screen shake → gold flash → place minion → fire trigger.
func _champion_summon_sequence(card: MinionCardData, instance: MinionInstance, slot: BoardSlot) -> void:
	var owner: String = instance.owner

	# 1+2. Card reveal + "CHAMPION" banner shown together, held longer
	AudioManager.play_sfx("res://assets/audio/sfx/minions/champion_summon.wav")
	await _show_champion_reveal_with_banner(card)
	if not is_inside_tree(): slot.place_minion(instance); return

	# 3. Place the minion on the slot
	slot.place_minion(instance)
	_log("  %s summoned!" % card.card_name, _LogType.PLAYER)

	# 4. Fire summon trigger
	var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	var ctx := EventContext.make(event, owner)
	ctx.minion = instance
	ctx.card   = card
	trigger_manager.fire(ctx)

	# 5. Screen shake — shake the landed slot so the impact reads locally.
	await _champion_screen_shake(slot)

	# 6. Gold flash on the slot + expanded ripple
	_champion_slot_flash(slot)
	_spawn_slot_ripple(slot, 8, true)

## Card reveal + "CHAMPION" banner shown together, held long enough to read.
func _show_champion_reveal_with_banner(card: CardData) -> void:
	var vp := get_viewport().get_visible_rect().size

	# --- Card visual (offset above center so banner can sit below it) ---
	var visual: CardVisual = CARD_VISUAL_SCENE.instantiate()
	visual.apply_size_mode("combat_preview")
	visual.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	visual.z_index       = 20
	visual.z_as_relative = false
	visual.modulate      = Color(0, 0, 0, 0)
	$UI.add_child(visual)
	visual.setup(card)
	# Anchor card so its top is ~60px from the top edge (with minimum padding safety)
	var card_top_y: float = max(60.0, vp.y * 0.08)
	visual.position = Vector2(vp.x / 2.0 - visual.size.x / 2.0, card_top_y)

	# --- Banner (below the card, with a small gap) ---
	var banner_y: float = card_top_y + visual.size.y + 30.0
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.set_size(Vector2(vp.x, 80))
	bg.position = Vector2(0, banner_y)
	bg.z_index = 25
	bg.z_as_relative = false
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(bg)

	var title := Label.new()
	title.text = "★  C H A M P I O N  ★"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25, 0.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-200, 8)
	title.set_size(Vector2(400, 30))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(title)

	var name_lbl := Label.new()
	name_lbl.text = card.card_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.90, 0.75, 0.50, 0.0))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	name_lbl.position = Vector2(-200, 42)
	name_lbl.set_size(Vector2(400, 25))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(name_lbl)

	# --- Fade in (card + banner together) ---
	var t1 := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t1.tween_property(visual, "modulate", Color(1.2, 1.05, 0.75, 1.0), 0.3)
	t1.tween_property(bg, "color:a", 0.75, 0.3)
	t1.tween_property(title, "theme_override_colors/font_color:a", 1.0, 0.35)
	t1.tween_property(name_lbl, "theme_override_colors/font_color:a", 1.0, 0.4)
	await t1.finished
	if not is_inside_tree(): visual.queue_free(); bg.queue_free(); return

	# --- Hold (longer than before) ---
	await get_tree().create_timer(2.8).timeout
	if not is_inside_tree(): visual.queue_free(); bg.queue_free(); return

	# --- Fade out together ---
	var t2 := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t2.tween_property(visual, "modulate:a", 0.0, 0.35)
	t2.tween_property(bg, "modulate:a", 0.0, 0.35)
	await t2.finished
	visual.queue_free()
	bg.queue_free()

## Screen shake for champion entrance. Heavy impact with decay.
## Target MUST be a Node2D/Control with a real position — pass the slot the
## champion landed on. Shaking $UI (a CanvasLayer) no-ops.
func _champion_screen_shake(target: Node) -> void:
	await ScreenShakeEffect.shake(target, self, 18.0, 14)

## Gold flash overlay on a slot when a champion lands.
func _champion_slot_flash(slot: BoardSlot) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.82, 0.25, 0.6)
	flash.set_size(slot.size)
	flash.global_position = slot.global_position
	flash.z_index = 3
	flash.z_as_relative = false
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(flash)
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(flash, "color:a", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)

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
	BuffSystem.apply(minion, Enums.BuffType.CORRUPTION, penalty, "corruption", false, false)
	_log("  %s is Corrupted! (−%d ATK)" % [minion.card_data.card_name, penalty], _LogType.ENEMY)
	_refresh_slot_for(minion)
	var slot: BoardSlot = _find_slot_for(minion)
	if slot != null:
		var vfx := CorruptionApplyVFX.create(slot)
		vfx_controller.spawn(vfx)
		slot.blink_corruption_status()
		slot.flash_atk_debuff()

## Pulse the Abyss Cultist Patrol champion's slot with an emerald corruption
## aura (rim glow + smoke wisps + sonic shimmer). Fires each time the aura
## triggers an instant detonation, so the player learns the visual link
## "champion pulses -> my corrupted minion blows up."
func _play_champion_acp_aura_pulse() -> void:
	var champion: MinionInstance = null
	for m in enemy_board:
		if (m as MinionInstance).card_data.id == "champion_abyss_cultist_patrol":
			champion = m
			break
	if champion == null:
		return
	var slot: BoardSlot = _find_slot_for(champion)
	if slot == null:
		return
	vfx_controller.spawn(ChampionAuraCorruptionPulseVFX.create(slot))

## Detonate Corruption on a list of minions in parallel. Each target spawns a
## CorruptionDetonationVFX; on impact_hit, `on_impact.call(minion, stacks)` runs
## so the caller can remove stacks + refresh the slot + apply damage synced to
## the visible burst. Missing slots fall back to immediate application.
##
## Freezes each target slot's visuals so lethal damage keeps the card card
## parked under the burst — any deaths queue into _deferred_death_slots and
## flush once the last VFX finishes.
##
## Gates enemy actions: sets `_on_play_vfx_active` while detonations play and
## emits `on_play_vfx_done` when the last one finishes, so EnemyAI.commit_*
## awaits the full animation before the next enemy action.
##
## targets: Array of Dictionary { "minion": MinionInstance, "stacks": int }.
## on_impact: Callable(minion: MinionInstance, stacks: int) -> void.
func _play_corruption_detonations(targets: Array, on_impact: Callable) -> void:
	var spawnable: Array = []
	for t in targets:
		var m: MinionInstance = t["minion"]
		var stacks: int = t["stacks"]
		var slot: BoardSlot = _find_slot_for(m)
		if slot == null:
			on_impact.call(m, stacks)
		else:
			spawnable.append({"minion": m, "stacks": stacks, "slot": slot})
	if spawnable.is_empty():
		return

	_on_play_vfx_active = true
	var remaining_ref: Array = [spawnable.size()]

	for s in spawnable:
		var m: MinionInstance = s["minion"]
		var stacks: int = s["stacks"]
		var slot: BoardSlot = s["slot"]
		slot.freeze_visuals = true
		var vfx := CorruptionDetonationVFX.create(slot, stacks)
		vfx.impact_hit.connect(func(_i: int) -> void:
			on_impact.call(m, stacks)
		, CONNECT_ONE_SHOT)
		vfx.finished.connect(func() -> void:
			if is_instance_valid(slot):
				slot.freeze_visuals = false
				slot._refresh_visuals()
			remaining_ref[0] -= 1
			if remaining_ref[0] <= 0:
				_flush_deferred_deaths()
				_on_play_vfx_active = false
				on_play_vfx_done.emit()
		, CONNECT_ONE_SHOT)
		vfx_controller.spawn(vfx)

## Feral Reinforcement (Act 2 passive) — a radiant violet halo erupts from
## the summoned Human's slot, then a face-down card arcs toward the enemy hero
## panel's hand indicator and lands with a pulse on the hand count.
## The card identity stays hidden (face-down) — the player shouldn't know which
## Feral Imp the enemy drew.
## Blocking: sets `_on_play_vfx_active` and emits `on_play_vfx_done` when the
## full animation finishes, so the EnemyAI awaits it before its next action
## (same pattern as Frenzied Imp Hurl in _play_frenzied_imp_hurl_vfx).
func _play_feral_reinforcement_vfx(source: MinionInstance, _imp_card: CardData) -> void:
	if source == null:
		return
	var slot: BoardSlot = _find_slot_for(source)
	if slot == null or _enemy_hero_panel == null:
		return
	var ui_root: Node = get_node_or_null("UI")
	if ui_root == null:
		return
	_on_play_vfx_active = true

	var start_pos: Vector2 = slot.global_position + slot.size * 0.5
	var end_pos: Vector2   = _enemy_hero_panel.global_position + _enemy_hero_panel.size * 0.5

	# 1) Origin halo: soft radial gradient at the source slot, additive-blended,
	#    violet tint. Same procedural softcircle pattern CastingWindupVFX uses
	#    for its charge-up glow — no geometry, just diffuse outward light.
	const HALO_TINT := Color(0.90, 0.35, 1.00, 1.0)  # violet
	var origin_halo := _make_radial_halo(320.0, HALO_TINT)
	origin_halo.position = start_pos - origin_halo.size * 0.5
	origin_halo.z_index  = 17
	origin_halo.z_as_relative = false
	ui_root.add_child(origin_halo)
	origin_halo.modulate.a = 0.0
	var oh_tw := create_tween().set_trans(Tween.TRANS_SINE)
	oh_tw.tween_property(origin_halo, "modulate:a", 0.85, 0.36).set_ease(Tween.EASE_OUT)
	oh_tw.tween_property(origin_halo, "modulate:a", 0.0, 1.10).set_ease(Tween.EASE_IN)
	oh_tw.tween_callback(origin_halo.queue_free)

	# 2) Feral surge mark scorch on the slot (brief, tinted red).
	const TEX_SURGE: Texture2D = preload("res://assets/art/fx/feral_surge_mark.png")
	var mark := TextureRect.new()
	mark.texture       = TEX_SURGE
	mark.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	mark.z_index       = 17
	mark.z_as_relative = false
	mark.modulate      = Color(1.0, 0.35, 0.45, 0.0)
	var mark_size := slot.size * 0.9
	mark.size          = mark_size
	mark.position      = slot.global_position + (slot.size - mark_size) * 0.5
	mark.pivot_offset  = mark_size * 0.5
	mark.rotation      = randf_range(-0.25, 0.25)
	mark.scale         = Vector2(0.7, 0.7)
	ui_root.add_child(mark)
	var mark_tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	mark_tw.tween_property(mark, "modulate:a", 0.7, 0.24).set_ease(Tween.EASE_OUT)
	mark_tw.tween_property(mark, "scale", Vector2(1.05, 1.05), 0.50).set_ease(Tween.EASE_OUT)
	mark_tw.chain()
	mark_tw.tween_property(mark, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN)
	mark_tw.tween_callback(mark.queue_free)

	# 3) Face-down card fly-in — identity hidden so the player doesn't see which
	#    Feral Imp was drawn. Procedural card back (dark panel + violet border +
	#    glyph), arcs on a parabolic path toward the enemy hero panel. A soft
	#    additive halo rides behind the card, emitting outward light as it flies.
	var card_back := _make_feral_card_back()
	card_back.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	card_back.z_index        = 22
	card_back.z_as_relative  = false
	ui_root.add_child(card_back)
	card_back.pivot_offset   = card_back.size * 0.5
	var start_scale := Vector2(0.55, 0.55)
	var end_scale   := Vector2(0.22, 0.22)
	card_back.scale          = start_scale
	card_back.modulate       = Color(1.0, 1.0, 1.0, 0.0)
	# pivot_offset = size/2, so visual center stays at position + size/2 regardless of scale.
	card_back.position       = start_pos - card_back.size * 0.5

	var card_halo := _make_radial_halo(280.0, HALO_TINT)
	card_halo.z_index        = 21  # behind the card (22), above board
	card_halo.z_as_relative  = false
	card_halo.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	card_halo.modulate.a     = 0.0
	ui_root.add_child(card_halo)

	# Arc path: parabolic midpoint lifted above the straight line.
	var mid_pos: Vector2 = start_pos.lerp(end_pos, 0.5)
	mid_pos.y += -140.0

	var fly_duration: float = 1.10
	var t := create_tween().set_parallel(true)
	t.tween_property(card_back, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(card_halo, "modulate:a", 0.75, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(card_back, "scale", end_scale, fly_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(card_halo, "scale", Vector2(0.45, 0.45), fly_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(card_back, "rotation", randf_range(-0.35, 0.35), fly_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(card_back, "rotation", 0.0, fly_duration * 0.5).set_delay(fly_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	card_halo.scale = Vector2.ONE
	var arc_callable := func(p: float) -> void:
		if not is_instance_valid(card_back): return
		var a: Vector2 = start_pos.lerp(mid_pos, p)
		var b: Vector2 = mid_pos.lerp(end_pos, p)
		var pt: Vector2 = a.lerp(b, p)
		card_back.position = pt - card_back.size * 0.5
		if is_instance_valid(card_halo):
			card_halo.position = pt - card_halo.size * 0.5
	t.tween_method(arc_callable, 0.0, 1.0, fly_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.chain().tween_property(card_back, "modulate:a", 0.0, 0.30).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(card_halo, "modulate:a", 0.0, 0.36).set_ease(Tween.EASE_IN)
	t.tween_callback(card_back.queue_free)
	t.tween_callback(card_halo.queue_free)
	t.tween_callback(func() -> void:
		if _enemy_hero_panel and is_instance_valid(_enemy_hero_panel):
			_pulse_enemy_hand_indicator()
	)
	await t.finished
	_on_play_vfx_active = false
	on_play_vfx_done.emit()

## Procedural face-down card back used by Feral Reinforcement (and reusable for
## any "hidden card goes to enemy hand" effect). Dark panel + violet border +
## centered claw/imp glyph.
func _make_feral_card_back() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(160, 240)
	root.size = Vector2(160, 240)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color     = Color(0.08, 0.03, 0.10, 1.0)
	bg_style.border_color = Color(0.75, 0.25, 0.95, 1.0)
	bg_style.set_border_width_all(3)
	bg_style.set_corner_radius_all(8)
	bg_style.shadow_color = Color(0.60, 0.20, 0.90, 0.55)
	bg_style.shadow_size  = 10
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var inner := Panel.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 8; inner.offset_right = -8
	inner.offset_top  = 8; inner.offset_bottom = -8
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color     = Color(0.14, 0.05, 0.18, 1.0)
	inner_style.border_color = Color(0.45, 0.15, 0.60, 0.9)
	inner_style.set_border_width_all(1)
	inner_style.set_corner_radius_all(5)
	inner.add_theme_stylebox_override("panel", inner_style)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(inner)

	var glyph := Label.new()
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.text = "✦"
	glyph.add_theme_font_size_override("font_size", 96)
	glyph.add_theme_color_override("font_color", Color(0.95, 0.65, 1.0, 1.0))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(glyph)
	return root

## Soft radial-gradient halo — additive-blended, tinted. Used behind the
## face-down card in Feral Reinforcement so it emits diffuse outward light
## (same procedural softcircle pattern as CastingWindupVFX's glow halo).
## `diameter` is the on-screen halo size in pixels.
func _make_radial_halo(diameter: float, tint: Color) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture        = _get_radial_halo_texture()
	tr.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode   = TextureRect.STRETCH_SCALE
	tr.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	tr.size           = Vector2(diameter, diameter)
	tr.pivot_offset   = tr.size * 0.5
	tr.modulate       = tint
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tr.material       = mat
	return tr

## Cached procedural softcircle texture — white RGB, smoothstep-biased alpha
## falloff from bright center to 0 at the edge. Reused across all halo calls.
static var _radial_halo_tex: ImageTexture = null

static func _get_radial_halo_texture() -> ImageTexture:
	if _radial_halo_tex != null:
		return _radial_halo_tex
	const SIZE := 256
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre: float = float(SIZE) * 0.5
	for y in SIZE:
		for x in SIZE:
			var dx: float = (float(x) - centre) / centre
			var dy: float = (float(y) - centre) / centre
			var r: float  = sqrt(dx * dx + dy * dy)
			var a: float  = clampf(1.0 - r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)  # smoothstep
			a = a * a  # bias further toward bright-centre / soft-outer
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_radial_halo_tex = ImageTexture.create_from_image(img)
	return _radial_halo_tex

## Brief gold pulse on the enemy hand count label — used when a card is added
## to the enemy hand by a passive (Feral Reinforcement and similar).
func _pulse_enemy_hand_indicator() -> void:
	if _enemy_hero_panel == null:
		return
	_enemy_hero_panel.pivot_offset = _enemy_hero_panel.size * 0.5
	var tw := create_tween().set_trans(Tween.TRANS_BACK)
	tw.tween_property(_enemy_hero_panel, "modulate", Color(1.6, 1.3, 0.6, 1.0), 0.10).set_ease(Tween.EASE_OUT)
	tw.tween_property(_enemy_hero_panel, "modulate", Color.WHITE, 0.35).set_ease(Tween.EASE_IN_OUT)

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

## Return the deck belonging to the given owner.
func _friendly_deck(owner: String) -> Array:
	if owner == "player":
		return turn_manager.player_deck
	else:
		return enemy_ai.deck if enemy_ai else []

## Return the hand belonging to the given owner.
func _friendly_hand(owner: String) -> Array:
	if owner == "player":
		return turn_manager.player_hand
	else:
		return enemy_ai.hand if enemy_ai else []

## Seris Starter — Fiendish Pact discount for a single Demon play.
## Returns the Essence discount to subtract from this play's cost (0 if not applicable).
## Does NOT consume the pending yet — call _consume_fiendish_pact_discount after the pay succeeds.
func _peek_fiendish_pact_discount(mc: MinionCardData) -> int:
	if _fiendish_pact_pending <= 0:
		return 0
	if mc == null or mc.minion_type != Enums.MinionType.DEMON:
		return 0
	return mini(_fiendish_pact_pending, mc.essence_cost)

## Consume the Fiendish Pact pending discount after a Demon is successfully played.
## Also clears the display-only cost_delta on any remaining Demon cards in hand,
## since the effect is spent.
func _consume_fiendish_pact_discount() -> void:
	if _fiendish_pact_pending <= 0:
		return
	_fiendish_pact_pending = 0
	for inst in turn_manager.player_hand:
		if inst == null or inst.card_data == null:
			continue
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).minion_type == Enums.MinionType.DEMON:
			inst.cost_delta = 0
	if has_method("_refresh_hand_spell_costs"):
		_refresh_hand_spell_costs()

## Add a CardInstance to the given owner's hand.
func _add_to_owner_hand(owner: String, inst: CardInstance) -> void:
	if owner == "player":
		turn_manager.add_instance_to_hand(inst)
	else:
		enemy_ai.add_instance_to_hand(inst)

## Return the board slots belonging to the given owner.
func _friendly_slots(owner: String) -> Array:
	return player_slots if owner == "player" else enemy_slots

## Return the active traps belonging to the given owner.
func _friendly_traps(owner: String) -> Array:
	if owner == "player":
		return active_traps
	else:
		return enemy_ai.active_traps if enemy_ai else []

## Return the active traps belonging to the opponent of the given owner.
func _opponent_traps(owner: String) -> Array:
	return _friendly_traps(_opponent_of(owner))

## Return the unified card graveyard belonging to the given owner.
## Each entry is a CardInstance with `resolved_on_turn` stamped at play time.
func _friendly_graveyard(owner: String) -> Array:
	if owner == "player":
		return turn_manager.player_graveyard
	else:
		return enemy_ai.graveyard if enemy_ai else []

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
		SacrificeSystem.sacrifice(self, m, "void_devourer")
	if count > 0:
		BuffSystem.apply(devourer, Enums.BuffType.ATK_BONUS, count * 300, "void_devourer", false, false)
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
			if token_atk    > 0:
				instance.current_atk  = token_atk
				instance.spawn_atk    = token_atk
			if token_hp     > 0:
				instance.current_health = token_hp
				instance.spawn_health   = token_hp
			if token_shield > 0:
				instance.current_shield = token_shield
				BuffSystem.apply(instance, Enums.BuffType.SHIELD_BONUS, token_shield, "token", false, false)
			board.append(instance)
			# Champion tokens get a dramatic entrance (fire-and-forget — places minion on slot after animation)
			if data.is_champion:
				_champion_summon_sequence(data, instance, slot)
			else:
				# Void Spark tokens get the spark summon sigil VFX (covers
				# brood_imp on-death, soul_rune, and other spark sources).
				# Reserve the slot synchronously (so back-to-back SUMMONs land
				# in distinct slots) then reveal the minion after the sigil.
				if card_id == "void_spark" and vfx_controller != null:
					_summon_spark_with_sigil(instance, data, slot, owner)
					return
				# Void Demon tokens (Void Spawning, Fleshcraft Ritual) get the
				# purple ARCANE sigil + inward spark burst on reveal.
				if card_id == "void_demon" and vfx_controller != null:
					_summon_demon_with_sigil(instance, data, slot, owner)
					return
				# Brood Imp tokens (Matriarch's Broodling on-death) get the
				# dark-green BROOD_DARK sigil + green/black inward spark burst.
				if card_id == "brood_imp" and vfx_controller != null:
					_summon_brood_imp_with_sigil(instance, data, slot, owner)
					return
				slot.place_minion(instance)
				_log("  %s summoned!" % data.card_name, _LogType.PLAYER)
				var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
				var ctx   := EventContext.make(event, owner)
				ctx.minion = instance
				ctx.card   = data
				trigger_manager.fire(ctx)
			return

## Play SPARK sigil VFX, then reveal the summoned spark after the VFX ends.
## The slot is reserved immediately (minion occupies it, visuals frozen) so
## back-to-back SUMMON steps (e.g. Brood Imp's 2 sparks) land in distinct
## slots. Each summon plays its own sigil in parallel.
func _summon_spark_with_sigil(instance: MinionInstance, data: MinionCardData,
		slot: BoardSlot, owner: String) -> void:
	# Reserve the slot synchronously — is_empty() now returns false for it.
	slot.freeze_visuals = true
	slot.place_minion(instance)

	# Spawn sigil and wait for it to finish before revealing the minion.
	var sigil := SummonSigilVFX.create(slot, SummonSigilVFX.Flavor.SPARK)
	vfx_controller.spawn(sigil)
	await sigil.finished
	if not is_inside_tree():
		return

	# Reveal the minion — refresh visuals now that the sigil has collapsed,
	# then fade the slot in so the spark materialises rather than popping.
	slot.freeze_visuals = false
	slot.modulate.a = 0.0
	slot._refresh_visuals()
	var fade := create_tween()
	fade.tween_property(slot, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_log("  %s summoned!" % data.card_name, _LogType.PLAYER)
	var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	var ctx   := EventContext.make(event, owner)
	ctx.minion = instance
	ctx.card   = data
	trigger_manager.fire(ctx)


## Play purple ARCANE sigil VFX for a Void Demon token, then a short inward
## spark burst while the slot fades in. Mirrors _summon_spark_with_sigil but
## uses the Void Spawning visual language (purple rings + violet sparks).
func _summon_demon_with_sigil(instance: MinionInstance, data: MinionCardData,
		slot: BoardSlot, owner: String) -> void:
	slot.freeze_visuals = true
	slot.place_minion(instance)

	var sigil := SummonSigilVFX.create(slot, SummonSigilVFX.Flavor.ARCANE_PURPLE)
	vfx_controller.spawn(sigil)
	await sigil.finished
	if not is_inside_tree():
		return

	# Spark burst plays over an EMPTY-looking slot — sparks stream in from
	# all edges and converge to center. Demon fades in only after the last
	# spark has landed and disappeared.
	var burst := VoidDemonSparkBurstVFX.create(slot)
	vfx_controller.spawn(burst)
	await burst.finished
	if not is_inside_tree():
		return

	slot.freeze_visuals = false
	slot.modulate.a = 0.0
	slot._refresh_visuals()
	var fade := create_tween()
	fade.tween_property(slot, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_log("  %s summoned!" % data.card_name, _LogType.PLAYER)
	var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	var ctx   := EventContext.make(event, owner)
	ctx.minion = instance
	ctx.card   = data
	trigger_manager.fire(ctx)


## Play dark-green BROOD_DARK sigil VFX for a Brood Imp token summoned from
## Matriarch's Broodling on-death, then a green/black inward spark burst while
## the slot fades in. Mirrors _summon_demon_with_sigil.
func _summon_brood_imp_with_sigil(instance: MinionInstance, data: MinionCardData,
		slot: BoardSlot, owner: String) -> void:
	slot.freeze_visuals = true
	slot.place_minion(instance)

	var sigil := SummonSigilVFX.create(slot, SummonSigilVFX.Flavor.BROOD_DARK)
	vfx_controller.spawn(sigil)
	await sigil.finished
	if not is_inside_tree():
		return

	var burst := BroodImpSparkBurstVFX.create(slot)
	vfx_controller.spawn(burst)
	await burst.finished
	if not is_inside_tree():
		return

	slot.freeze_visuals = false
	slot.modulate.a = 0.0
	slot._refresh_visuals()
	var fade := create_tween()
	fade.tween_property(slot, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_log("  %s summoned!" % data.card_name, _LogType.PLAYER)
	var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
	var ctx   := EventContext.make(event, owner)
	ctx.minion = instance
	ctx.card   = data
	trigger_manager.fire(ctx)


## Aura-source minions play a one-shot breathing halo on their own summon to
## advertise "I project an aura" without the noise of a persistent effect.
## Strictly on-summon: never fires on aura refresh or when another source of
## the same aura enters play. Card-id gated (only minions listed here).
func _maybe_spawn_aura_pulse(card: CardData, slot: BoardSlot) -> void:
	if card == null or slot == null or vfx_controller == null:
		return
	match card.id:
		"rogue_imp_elder":
			vfx_controller.spawn(AuraBreathingPulseVFX.create(slot))
		"champion_abyss_cultist_patrol":
			# Same VFX used when the aura triggers on-detonation — playing it
			# on summon teaches the player what to watch for before the first trigger.
			vfx_controller.spawn(ChampionAuraCorruptionPulseVFX.create(slot))


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
	# Add cards directly to player hand
	for id in TestConfig.hand_cards:
		var card := CardDatabase.get_card(id)
		if card:
			turn_manager.add_to_hand(card)

	# Add cards directly to enemy hand
	if enemy_ai:
		for id in TestConfig.enemy_hand_cards:
			var ecard := CardDatabase.get_card(id)
			if ecard:
				enemy_ai.add_to_hand(ecard)

	# Pre-summon player board minions
	for id in TestConfig.player_board_cards:
		_summon_token(id, "player")

	# Pre-summon enemy board minions
	for id in TestConfig.enemy_board_cards:
		_summon_token(id, "enemy")

	# Pre-place player traps
	for id in TestConfig.player_traps:
		var trap_card := CardDatabase.get_card(id)
		if trap_card is TrapCardData and active_traps.size() < trap_slot_panels.size():
			active_traps.append(trap_card as TrapCardData)
	if not TestConfig.player_traps.is_empty():
		_update_trap_display()

	# Pre-place enemy traps
	if enemy_ai:
		for id in TestConfig.enemy_traps:
			var trap_card := CardDatabase.get_card(id)
			if trap_card is TrapCardData and enemy_ai.active_traps.size() < enemy_trap_slot_panels.size():
				enemy_ai.active_traps.append(trap_card as TrapCardData)
		if not TestConfig.enemy_traps.is_empty():
			_update_enemy_trap_display()

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

	# Override enemy starting resources (so test-cast spells on turn 1)
	if enemy_ai:
		if TestConfig.enemy_start_essence_max > 0:
			enemy_ai.essence_max = TestConfig.enemy_start_essence_max
			enemy_ai.essence     = TestConfig.enemy_start_essence_max
		if TestConfig.enemy_start_mana_max > 0:
			enemy_ai.mana_max = TestConfig.enemy_start_mana_max
			enemy_ai.mana     = TestConfig.enemy_start_mana_max

	_log("[TEST] Test config applied.", _LogType.TURN)
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
	_relic_runtime = RelicRuntime.new()
	_relic_runtime.setup(GameManager.player_relics, GameManager.relic_bonus_charges)
	_relic_effects = RelicEffects.new()
	_relic_effects.setup(self)

	if _relic_runtime.relics.is_empty():
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
	_relic_bar.setup(_relic_runtime)
	_relic_bar.relic_activated.connect(_on_relic_activated)
	_relic_bar.relic_hovered.connect(_on_relic_hovered)
	_relic_bar.relic_unhovered.connect(_on_relic_unhovered)

func _on_relic_hovered(effect_id: String) -> void:
	match effect_id:
		"relic_refill_mana":
			# Show mana gain preview: +2 mana (capped at max)
			var gain: int = mini(2, turn_manager.mana_max - turn_manager.mana)
			if gain > 0:
				_pip_bar.start_blink(0, 0, 0, gain)

func _on_relic_unhovered() -> void:
	_pip_bar.stop_blink()

func _on_relic_activated(index: int) -> void:
	if not turn_manager.is_player_turn:
		return
	var effect_id: String = _relic_runtime.activate(index)
	if effect_id == "":
		return
	_pip_bar.stop_blink()
	# Blood Chalice: enter targeting mode instead of resolving immediately
	if effect_id == "relic_execute":
		_pending_relic_index = index
		_begin_relic_targeting(effect_id)
		if _relic_bar:
			_relic_bar.refresh()
		return
	_relic_effects.resolve(effect_id)
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
	_log("  Blood Chalice: choose a target (right-click to cancel).", _LogType.PLAYER)

## Resolve a relic effect on a chosen enemy minion target.
func _resolve_relic_target_minion(minion: MinionInstance) -> void:
	var effect := _pending_relic_target
	_pending_relic_target = ""
	_pending_relic_index = -1
	_clear_all_highlights()
	match effect:
		"relic_execute":
			_spell_dmg(minion, 500,
					CombatManager.make_damage_info(0, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "relic_blood_chalice"))
			_log("  Relic: Blood Chalice — dealt 500 damage to %s." % minion.card_data.card_name, _LogType.PLAYER)

## Resolve a relic effect on the enemy hero.
func _resolve_relic_target_hero() -> void:
	var effect := _pending_relic_target
	_pending_relic_target = ""
	_pending_relic_index = -1
	_clear_all_highlights()
	match effect:
		"relic_execute":
			combat_manager.apply_hero_damage("enemy",
					CombatManager.make_damage_info(500, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "relic_blood_chalice"))
			_log("  Relic: Blood Chalice — dealt 500 damage to enemy hero.", _LogType.PLAYER)

## Cancel relic targeting — refund the charge and reset state.
func _cancel_relic_targeting() -> void:
	if _pending_relic_index >= 0 and _relic_runtime:
		_relic_runtime.refund(_pending_relic_index)
		_log("  Relic cancelled — charge refunded.", _LogType.PLAYER)
	_pending_relic_target = ""
	_pending_relic_index = -1
	_clear_all_highlights()
	if _relic_bar:
		_relic_bar.refresh()

## Fired when player clicks the enemy hero panel while relic targeting is active.
func _on_relic_target_hero_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if _pending_relic_target == "":
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_resolve_relic_target_hero()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_relic_targeting()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_cheat.toggle()
		elif event.keycode == KEY_ESCAPE and _cheat.visible:
			_cheat.toggle()
			get_viewport().set_input_as_handled()
	# Right-click cancels relic targeting, spell targeting, or minion placement
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _pending_relic_target != "":
			_cancel_relic_targeting()
			get_viewport().set_input_as_handled()
		elif pending_play_card != null:
			_cancel_card_select()
			get_viewport().set_input_as_handled()
		elif selected_attacker != null:
			selected_attacker = null
			_clear_all_highlights()
			_enemy_hero_panel.show_attackable(false)
			get_viewport().set_input_as_handled()

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

## Spawn the Brood Call portal VFX at the first empty slot that will receive
## the summoned imp. Awaits the full VFX (ramp → hold → collapse) so the token
## is placed after the portal has closed.
func _play_brood_call_vfx(owner: String) -> void:
	if vfx_controller == null:
		return
	var slots: Array = player_slots if owner == "player" else enemy_slots
	var target_slot: BoardSlot = null
	for s: BoardSlot in slots:
		if s.is_empty():
			target_slot = s
			break
	if target_slot == null:
		return
	var vfx := SummonSigilVFX.create(target_slot, SummonSigilVFX.Flavor.BROOD)
	vfx_controller.spawn(vfx)
	await vfx.finished

## Spawn the Grafted Butcher ON PLAY VFX — graft tether from the sacrificed
## minion's slot into the Butcher, engorge flash, then a crimson cleaver wave
## sweeps across the enemy board. Awaits `impact_hit` so the caller can apply
## 200 AoE damage synced to the wave's peak. Awaits `finished` so the visual
## settles before returning.
func _play_grafted_butcher_vfx(butcher: MinionInstance,
		sac_center: Vector2, butcher_owner: String) -> void:
	if vfx_controller == null:
		return
	var butcher_slot: BoardSlot = _find_slot_for(butcher) if butcher else null
	var butcher_panel: Control = butcher_slot
	var target_board: Control = $UI/EnemyBoard if butcher_owner == "player" else $UI/PlayerBoard
	var target_slots: Array = _get_opponent_occupied_slots(butcher_owner)
	var vfx := GraftedButcherVFX.create(butcher_panel, sac_center, target_board, target_slots)
	vfx_controller.spawn(vfx)
	await vfx.impact_hit

## Spawn the Pack Frenzy warcry VFX from the caster's hero panel, sweeping
## across the given friendly Feral Imp slots. Awaits `impact_hit` so the caller
## can apply buffs synced to the first imp ignition. Returns after the wave
## reaches the imps — lingering visuals continue in the background.
func _play_pack_frenzy_vfx(owner: String, target_slots: Array,
		is_matriarch: bool) -> void:
	if vfx_controller == null or target_slots.is_empty():
		return
	var caster_panel: Control = _player_hero_panel if owner == "player" else _enemy_hero_panel
	if caster_panel == null:
		return
	var vfx := PackFrenzyVFX.create(caster_panel, target_slots, is_matriarch)
	vfx_controller.spawn(vfx)
	# Track the live VFX so the enemy AI / turn flow can wait for it to finish
	# before continuing (see VfxController._play_pack_frenzy).
	_pack_frenzy_active_vfx = vfx
	vfx.finished.connect(func() -> void:
		if _pack_frenzy_active_vfx == vfx:
			_pack_frenzy_active_vfx = null,
		CONNECT_ONE_SHOT)
	await vfx.impact_hit

## The currently-playing Pack Frenzy VFX, or null. Read by VfxController so it
## can await the full visual (including glyphs + linger sparks) before
## returning from play_spell — otherwise the enemy's next action would start
## mid-VFX.
var _pack_frenzy_active_vfx: PackFrenzyVFX = null

## Spawn an ATK buff chevron next to a minion's ATK label. Used by Pack Frenzy
## since its VFX owns the full buff visual (the generic BuffApplyVFX — which
## normally spawns the chevron — is filtered out for source="pack_frenzy").
func _spawn_atk_chevron(minion: MinionInstance) -> void:
	if minion == null or not is_instance_valid(minion):
		return
	var slot: BoardSlot = _find_slot_for(minion)
	if slot == null or slot.minion != minion:
		return
	var lbl: Label = slot._atk_label
	if lbl == null:
		return
	var chevron := preload("res://combat/effects/BuffChevronVFX.gd").new()
	slot.add_child(chevron)
	var chevron_size := Vector2(14, 16)
	var font: Font = lbl.get_theme_font("font")
	var font_size: int = lbl.get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(lbl.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var text_left_x: float = lbl.position.x + (lbl.size.x - text_width) * 0.5
	var text_right_x: float = text_left_x + text_width
	var y_offset: float = lbl.size.y * 0.5 - chevron_size.y * 0.5
	var gap: float = 2.0
	chevron.position = Vector2(text_right_x + gap, lbl.position.y + y_offset)
	chevron.set_size(chevron_size)
	chevron.play()

## Pulse the lifedrain icon on a minion's status bar to highlight the grant
## from the Imp Matriarch's Ancient Frenzy aura. Fire-and-forget.
func _pulse_lifedrain_icon(minion: MinionInstance) -> void:
	if minion == null or not is_instance_valid(minion):
		return
	var slot: BoardSlot = _find_slot_for(minion)
	if slot == null or slot.minion != minion:
		return
	var status_bar: Node = slot.get_node_or_null("_status_bar")
	if status_bar == null:
		# _status_bar is added directly to the slot but not named — find by type.
		for child in slot.get_children():
			if child is HBoxContainer:
				status_bar = child
				break
	if status_bar == null:
		return
	# Find the lifedrain TextureRect by matching its texture's resource path.
	var icon: TextureRect = null
	for child in status_bar.get_children():
		var tr := child as TextureRect
		if tr == null or tr.texture == null:
			continue
		if String(tr.texture.resource_path).ends_with("icon_lifedrain.png"):
			icon = tr
			break
	if icon == null:
		return
	icon.pivot_offset = icon.size * 0.5
	var original_mod: Color = icon.modulate
	var pulse_color := Color(1.6, 0.6, 0.5, 1.0)
	var tw := icon.create_tween()
	for _cycle in 3:
		tw.tween_property(icon, "modulate", pulse_color, 0.14) \
				.set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(icon, "scale", Vector2(1.35, 1.35), 0.14) \
				.set_trans(Tween.TRANS_SINE)
		tw.tween_property(icon, "modulate", original_mod, 0.18) \
				.set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(icon, "scale", Vector2.ONE, 0.18) \
				.set_trans(Tween.TRANS_SINE)

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
	var net_discount := _spell_mana_discount() - player_spell_cost_penalty
	var relic_red := _relic_cost_reduction
	if hand_display:
		# Non-minion cards: mana discount includes relic reduction
		hand_display.refresh_spell_costs(net_discount + relic_red)
		# Minion cards: show essence and mana reductions from Dark Mirror
		hand_display.refresh_relic_cost_preview(relic_red, relic_red)
		hand_display.refresh_playability(turn_manager.essence, turn_manager.mana, relic_red, relic_red)
		hand_display.refresh_condition_glows(self, turn_manager.essence, turn_manager.mana)
	if large_preview.is_visible():
		var extra := -(_hovered_hand_visual.card_inst.cost_delta) if _hovered_hand_visual != null and _hovered_hand_visual.card_inst != null else 0
		large_preview.visual.apply_cost_discount(net_discount + relic_red + extra)
		large_preview.visual.apply_relic_cost_preview(relic_red, relic_red)

## Effective mana cost for a player spell after applying board discount and tax penalty.
func _effective_spell_cost(spell: SpellCardData) -> int:
	return maxi(0, spell.cost - _spell_mana_discount() + player_spell_cost_penalty)

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

## Void Bolt damage per Void Mark stack. Set by CombatSetup (deepened_curse → 40).
func _void_mark_damage_per_stack() -> int:
	return void_mark_damage_per_stack

## Add Void Mark stacks to the enemy hero.
func _apply_void_mark(stacks: int = 1) -> void:
	enemy_void_marks += stacks
	_log("  Void Mark x%d applied! (total: %d)" % [stacks, enemy_void_marks], _LogType.PLAYER)
	_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)
	if _enemy_status_panel and is_instance_valid(_enemy_status_panel):
		var vfx := VoidMarkApplyVFX.create(_enemy_status_panel)
		vfx_controller.spawn(vfx)

# Flesh / Forge facades — delegate to behavior modules. Names preserved so
# external callers (handlers, EffectResolver) keep working unchanged.
func _gain_flesh(amount: int = 1) -> void:
	flesh.gain(amount)

func _spend_flesh(amount: int) -> bool:
	return flesh.spend(amount)

func _on_flesh_spent(amount: int) -> void:
	flesh.on_spent(amount)

func _on_flesh_changed() -> void:
	flesh.on_changed()

func _forge_counter_tick(amount: int = 1) -> bool:
	return forge.tick(amount)

func _forge_counter_reset() -> void:
	forge.reset()

func _gain_forge_counter(amount: int = 1) -> bool:
	return forge.gain(amount)

func _on_forge_changed() -> void:
	forge.on_changed()

## Seris — fires for every friendly Demon SACRIFICE emit (not combat deaths).
## Handles Forge Counter ticks, Fiend Offering, and the auto Forged Demon summon.
## Silently no-ops for non-Seris runs (no soul_forge talent).
##
## Board-full rule: if an auto-summon would land but no slot is free, Flesh/
## counter costs are still paid — the summon just fails silently. This matches
## the user-facing "reduce flesh as well" decision so over-boarding isn't free.
func _on_demon_sacrificed(minion: MinionInstance, _source_tag: String) -> void:
	if minion == null or minion.owner != "player":
		return
	if not (minion.card_data is MinionCardData):
		return
	if (minion.card_data as MinionCardData).minion_type != Enums.MinionType.DEMON:
		return

	# Fiend Offering — sacrificed a Grafted Fiend, spend 2 Flesh → Lesser Demon.
	# Auto-spends when affordable (no opt-out UI yet); board-full still consumes Flesh.
	if _has_talent("fiend_offering") and "grafted_fiend" in (minion.card_data as MinionCardData).minion_tags:
		if _spend_flesh(2):
			_log("  Fiend Offering: +1 Lesser Demon attempt.", _LogType.PLAYER)
			_summon_token("lesser_demon", "player")

	if not _has_talent("soul_forge"):
		return

	# Forge Counter ticks; at threshold auto-summon Forged Demon and reset.
	if _forge_counter_tick(1):
		_log("  Soul Forge: threshold reached.", _LogType.PLAYER)
		_summon_forged_demon()
		_forge_counter_reset()

## Summon a Forged Demon and, if Abyssal Forge is active, grant a random aura
## (or all three if the player opts to spend 5 Flesh).
func _summon_forged_demon() -> void:
	_summon_token("forged_demon", "player")
	# Find the freshly summoned Forged Demon (last entry on the player board that matches).
	var forged: MinionInstance = null
	for i in range(player_board.size() - 1, -1, -1):
		var m: MinionInstance = player_board[i]
		if m.card_data.id == "forged_demon":
			forged = m
			break
	if forged == null:
		return  # board full; summon failed silently per design
	if _has_talent("abyssal_forge"):
		_grant_forged_demon_auras(forged)

## Seris — Corrupt Flesh activated ability. Entry point from SerisResourceBar button.
## Toggles targeting mode; player clicks a friendly Demon to apply Corruption.
## Costs are consumed inside _seris_corrupt_apply_target after a valid click so
## misclicks / cancels don't waste Flesh.
func _seris_corrupt_activate() -> void:
	if not _has_talent("corrupt_flesh"):
		return
	if _seris_corrupt_used_this_turn:
		_log("  Corrupt Flesh already used this turn.", _LogType.PLAYER)
		return
	if player_flesh < 1:
		return
	# Check there's at least one valid target (friendly Demon) before entering target mode.
	var has_target := false
	for m in player_board:
		if (m.card_data as MinionCardData).minion_type == Enums.MinionType.DEMON:
			has_target = true
			break
	if not has_target:
		_log("  Corrupt Flesh: no friendly Demon on board.", _LogType.PLAYER)
		return
	_seris_corrupt_targeting = true
	_log("  Corrupt Flesh: pick a friendly Demon.", _LogType.PLAYER)

## Applies Corrupt Flesh to the clicked minion. Called from _on_player_slot_clicked_occupied
## when _seris_corrupt_targeting is active. Non-Demon picks cancel targeting.
func _seris_corrupt_apply_target(minion: MinionInstance) -> void:
	_seris_corrupt_targeting = false
	if minion == null or minion.owner != "player":
		return
	if (minion.card_data as MinionCardData).minion_type != Enums.MinionType.DEMON:
		_log("  Corrupt Flesh: target must be a friendly Demon.", _LogType.PLAYER)
		return
	if not _spend_flesh(1):
		return
	var stacks: int = 2 if "grafted_fiend" in (minion.card_data as MinionCardData).minion_tags else 1
	for _i in stacks:
		BuffSystem.apply(minion, Enums.BuffType.CORRUPTION, 100, "corrupt_flesh", false, false)
	_seris_corrupt_used_this_turn = true
	_log("  Corrupt Flesh: %d Corruption stack(s) applied to %s." % [stacks, minion.card_data.card_name], _LogType.PLAYER)
	_refresh_slot_for(minion)

## Reset the 1/turn limit. Registered via CombatSetup for ON_PLAYER_TURN_START.
func _seris_corrupt_reset_turn() -> void:
	_seris_corrupt_used_this_turn = false

## Seris — Soul Forge activated ability. Spend 3 Flesh → summon a Grafted Fiend.
## Called from the SerisResourceBar's Forge button. Per design: no-op if the
## talent isn't active, the player can't afford it, or the board is full
## (board-full consumes nothing — contrast with sacrifice auto-summons where
## Flesh is still spent).
func _soul_forge_activate() -> void:
	if not _has_talent("soul_forge"):
		return
	if player_flesh < 3:
		return
	# Check for an empty slot before spending — active clicks should not waste
	# Flesh the way passive sacrifice auto-summons do.
	var has_slot := false
	for slot in player_slots:
		if slot.is_empty():
			has_slot = true
			break
	if not has_slot:
		_log("  Soul Forge: board full — no fiend summoned.", _LogType.PLAYER)
		return
	if not _spend_flesh(3):
		return
	_log("  Soul Forge: summoning Grafted Fiend.", _LogType.PLAYER)
	_summon_token("grafted_fiend", "player")

## Abyssal Forge (capstone) — grant auras to a freshly summoned Forged Demon.
## Default: one random aura. If the player has >=5 Flesh, spend all 5 and grant all three.
const _FORGED_DEMON_AURAS: Array[String] = ["void_growth", "void_pulse", "flesh_bond"]
func _grant_forged_demon_auras(forged: MinionInstance) -> void:
	if player_flesh >= 5 and _spend_flesh(5):
		forged.aura_tags = _FORGED_DEMON_AURAS.duplicate()
		_log("  Abyssal Forge: Forged Demon granted all three auras.", _LogType.PLAYER)
	else:
		var roll: String = _FORGED_DEMON_AURAS[randi() % _FORGED_DEMON_AURAS.size()]
		forged.aura_tags = [roll]
		_log("  Abyssal Forge: Forged Demon granted %s." % roll, _LogType.PLAYER)

## Pre-death hook — CombatManager asks "can this minion be saved?" before applying
## death. Return true and set minion.current_health to a non-zero value to save it.
## Seris's deathless_flesh talent spends 2 Flesh to save any friendly Grafted Fiend.
## New talents with similar "would die" effects should extend this method.
func _try_save_from_death(minion: MinionInstance) -> bool:
	if minion == null or minion.owner != "player":
		return false
	if _has_talent("deathless_flesh") \
			and minion.card_data is MinionCardData \
			and "grafted_fiend" in (minion.card_data as MinionCardData).minion_tags \
			and player_flesh >= 2:
		_spend_flesh(2)
		minion.current_health = 50
		_log("  Deathless Flesh: %s saved (2 Flesh spent)." % minion.card_data.card_name, _LogType.PLAYER)
		return true
	return false

## Siphon self-heal callback — CombatManager pings us so we can refresh the
## minion's HP display. Called from _siphon_self_heal after HP is updated.
func _on_minion_siphon_healed(minion: MinionInstance, healed: int) -> void:
	_log("  %s siphons %d HP" % [minion.card_data.card_name, healed], _LogType.PLAYER)
	if minion.slot_index >= 0:
		var board_slots: Array = player_slots if minion.owner == "player" else enemy_slots
		if minion.slot_index < board_slots.size():
			var slot: BoardSlot = board_slots[minion.slot_index]
			if slot and is_instance_valid(slot):
				slot._refresh_visuals()

## Generic minion heal — restores HP up to the minion's effective max (base + HP_BONUS buffs).
## Used by HEAL_MINION EffectStep. No-op if amount ≤ 0 or minion is already at full HP.
func _heal_minion(minion: MinionInstance, amount: int) -> void:
	if minion == null or amount <= 0 or minion.current_health <= 0:
		return
	var hp_cap: int = minion.card_data.health + BuffSystem.sum_type(minion, Enums.BuffType.HP_BONUS)
	var before := minion.current_health
	minion.current_health = mini(minion.current_health + amount, hp_cap)
	var healed := minion.current_health - before
	if healed <= 0:
		return
	_log("  %s healed for %d HP" % [minion.card_data.card_name, healed], _LogType.PLAYER if minion.owner == "player" else _LogType.ENEMY)
	_refresh_slot_for(minion)

## Restore a minion to full HP (effective max = base + HP_BONUS buffs). Used by HEAL_MINION_FULL.
func _heal_minion_full(minion: MinionInstance) -> void:
	if minion == null or minion.current_health <= 0:
		return
	var hp_cap: int = minion.card_data.health + BuffSystem.sum_type(minion, Enums.BuffType.HP_BONUS)
	if minion.current_health >= hp_cap:
		return
	var healed: int = hp_cap - minion.current_health
	minion.current_health = hp_cap
	_log("  %s healed to full (+%d HP)" % [minion.card_data.card_name, healed], _LogType.PLAYER if minion.owner == "player" else _LogType.ENEMY)
	_refresh_slot_for(minion)

## Sacrifice flow (strict rule: sacrifice is NOT death — does not fire ON DEATH).
##
## Order:
##   1. Run the minion's on_leave_effect_steps (declarative, source = minion).
##   2. Fire ON_*_MINION_SACRIFICED so board-wide listeners (Fleshbind, Blood/Soul Rune,
##      Soul Forge talent etc.) can react.
##   3. Fire ON_CORRUPTION_REMOVED if the sacrificed minion had Corruption stacks.
##   4. Erase from board and clear slot. Death animation is reused for visuals.
##
## Skips: ON_*_MINION_DIED, on_death_effect_steps, on-death icon VFX, granted_on_death_effects.
func _sacrifice_minion(minion: MinionInstance) -> void:
	if minion == null:
		return
	# Capture slot for the death animation BEFORE we touch the board.
	var dead_slot: BoardSlot = null
	var search_slots := player_slots if minion.owner == "player" else enemy_slots
	for s in search_slots:
		if s.minion == minion:
			dead_slot = s
			break
	# Step 1 — declarative ON LEAVE steps run while the minion is still on its slot.
	var card_data := minion.card_data as MinionCardData
	if card_data != null and not card_data.on_leave_effect_steps.is_empty():
		var leave_ctx := EffectContext.make(self, minion.owner)
		leave_ctx.source         = minion
		leave_ctx.source_card_id = card_data.id
		EffectResolver.run(card_data.on_leave_effect_steps, leave_ctx)
	# Step 2 — corruption removal still fires (Corrupt Detonation reads "by any means").
	var pre_corruption: int = BuffSystem.count_type(minion, Enums.BuffType.CORRUPTION)
	if pre_corruption > 0:
		var rm_ctx := EventContext.make(Enums.TriggerEvent.ON_CORRUPTION_REMOVED, minion.owner)
		rm_ctx.minion = minion
		rm_ctx.damage = pre_corruption
		trigger_manager.fire(rm_ctx)
	# Step 3 — fire the sacrifice event for board-wide listeners.
	var sac_event := Enums.TriggerEvent.ON_PLAYER_MINION_SACRIFICED if minion.owner == "player" \
		else Enums.TriggerEvent.ON_ENEMY_MINION_SACRIFICED
	var sac_ctx := EventContext.make(sac_event, minion.owner)
	sac_ctx.minion = minion
	trigger_manager.fire(sac_ctx)
	# Step 4 — remove from board and play death animation. We do NOT fire ON_*_MINION_DIED.
	var slot_is_frozen := dead_slot != null and dead_slot.freeze_visuals
	if minion.owner == "player":
		player_board.erase(minion)
		if not slot_is_frozen:
			_clear_slot_for(minion, player_slots)
		if hand_display:
			hand_display.refresh_condition_glows(self, turn_manager.essence, turn_manager.mana)
	else:
		enemy_board.erase(minion)
		if not slot_is_frozen:
			_clear_slot_for(minion, enemy_slots)
	_log("  %s was sacrificed" % minion.card_data.card_name, _LogType.DEATH)
	_refresh_hand_spell_costs()
	if dead_slot:
		if dead_slot.freeze_visuals:
			_deferred_death_slots.append({slot = dead_slot, pos = dead_slot.global_position, minion = minion})
		else:
			_animate_minion_death(dead_slot, dead_slot.global_position, minion)

## Seris — add kill stacks to a minion. Single entry point so both organic kills
## (via on_enemy_died_grafted_constitution) and direct grants (Flesh Sacrament) run
## the Fleshcraft talent reactions uniformly:
##   • flesh_infusion active → +100 ATK / +100 HP per stack added
##   • predatory_surge active and kill_stacks crosses 3 → grant SIPHON once
func _add_kill_stacks(minion: MinionInstance, count: int = 1) -> void:
	if minion == null or count <= 0:
		return
	minion.kill_stacks += count
	# flesh_infusion gates the kill-stack → stats conversion. The talent id is
	# "flesh_infusion" (the Fleshcraft T0 / branch unlock); the old grafted_constitution
	# talent id was merged into it. Buff source_tag stays "grafted_constitution" so UI
	# and tests that filter by that tag keep working.
	if _has_talent("flesh_infusion"):
		BuffSystem.apply(minion, Enums.BuffType.ATK_BONUS, 100 * count, "grafted_constitution", false, false)
		BuffSystem.apply_hp_gain(minion, 100 * count, "grafted_constitution", true)
		_log("  Grafted Constitution: %s +%d/+%d (kills: %d)." % [minion.card_data.card_name, 100 * count, 100 * count, minion.kill_stacks], _LogType.PLAYER)
	if _has_talent("predatory_surge") and minion.kill_stacks >= 3 \
			and not BuffSystem.has_type(minion, Enums.BuffType.GRANT_SIPHON):
		BuffSystem.apply(minion, Enums.BuffType.GRANT_SIPHON, 1, "predatory_surge", false, false)
		_log("  Predatory Surge: %s gains Siphon." % minion.card_data.card_name, _LogType.PLAYER)
	_refresh_slot_for(minion)

## Deal Void Bolt damage to the enemy hero, scaled by current Void Marks.
## CONVENTION: ALL Void Bolt damage in the game must go through this function
## so that talents like deepened_curse and future modifiers apply automatically.
## Void bolt passives are fired automatically in _on_hero_damaged when type == VOID_BOLT.
## source_minion: if provided, projectile fires from that minion's board slot.
## If null, auto-detects: checks for active void rune (fires from rune slot),
## otherwise fires from center-bottom (player hero area).
## is_minion_emitted: caller asserts this Void Bolt is a minion attack/effect (e.g.
## void_manifestation talent retag of basic attack, piercing_void retag of on-play).
## Default false → SPELL source for spell-cast / triggered-passive paths.
func _deal_void_bolt_damage(base_damage: int, source_minion: MinionInstance = null, from_rune: bool = false, is_minion_emitted: bool = false) -> void:
	var bonus := enemy_void_marks * _void_mark_damage_per_stack()
	var total := base_damage + bonus
	if bonus > 0:
		_log("  Void Bolt: %d dmg (base %d + %d from %d marks)" % [total, base_damage, bonus, enemy_void_marks], _LogType.PLAYER)
	else:
		_log("  Void Bolt: %d damage." % total, _LogType.PLAYER)
	# Fire projectile and wait for it to arrive before applying damage.
	# The projectile owns both cast and impact SFX internally.
	var bolt := _fire_void_bolt_projectile(source_minion, from_rune)
	if bolt != null and is_inside_tree():
		await bolt.impact_hit
	var src: Enums.DamageSource = Enums.DamageSource.MINION if is_minion_emitted else Enums.DamageSource.SPELL
	combat_manager.apply_hero_damage("enemy",
			CombatManager.make_damage_info(total, src, Enums.DamageSchool.VOID_BOLT, source_minion, "void_bolt"))

## Spawn and fly a void bolt projectile to the enemy hero panel.
## Returns the bolt node (or null if not spawned) so caller can await impact_hit.
func _fire_void_bolt_projectile(source_minion: MinionInstance = null, from_rune: bool = false) -> VoidBoltProjectile:
	if not is_inside_tree():
		return null
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	# Determine source position
	var from_pos: Vector2
	if source_minion != null:
		# Fire from the minion's board slot
		var found := false
		for slot in player_slots:
			if (slot as BoardSlot).minion == source_minion:
				from_pos = (slot as BoardSlot).global_position + (slot as BoardSlot).size / 2.0
				found = true
				break
		if not found:
			from_pos = Vector2(vp_size.x / 2.0, vp_size.y - 120)
	elif from_rune:
		# Fire from the void rune's trap slot
		var rune_pos := _find_void_rune_slot_position()
		if rune_pos != Vector2.ZERO:
			from_pos = rune_pos
		else:
			from_pos = Vector2(vp_size.x / 2.0, vp_size.y - 120)
	else:
		# Default: center-bottom (player hero area)
		from_pos = Vector2(vp_size.x / 2.0, vp_size.y - 120)
	# Target: enemy status panel center
	var to_pos: Vector2
	if _enemy_status_panel:
		to_pos = _enemy_status_panel.global_position + _enemy_status_panel.size / 2.0
	else:
		to_pos = Vector2(vp_size.x / 2.0, 80)
	var bolt := VoidBoltProjectile.create(from_pos, to_pos)
	vfx_controller.spawn(bolt)
	return bolt

## Enemy-cast Void Bolt — fires a projectile from the enemy minion's slot (or
## enemy hero area) to the player hero panel, then applies damage on impact.
## Does not participate in Void Marks (those only apply to the enemy hero).
## is_minion_emitted: see _deal_void_bolt_damage. Default false (SPELL source).
func _deal_enemy_void_bolt_damage(base_damage: int, source_minion: MinionInstance = null, is_minion_emitted: bool = false) -> void:
	_log("  Void Bolt: %d damage." % base_damage, _LogType.ENEMY)
	var bolt := _fire_enemy_void_bolt_projectile(source_minion)
	if bolt != null and is_inside_tree():
		await bolt.impact_hit
	var src: Enums.DamageSource = Enums.DamageSource.MINION if is_minion_emitted else Enums.DamageSource.SPELL
	combat_manager.apply_hero_damage("player",
			CombatManager.make_damage_info(base_damage, src, Enums.DamageSchool.VOID_BOLT, source_minion, "void_bolt"))

## Spawn a void bolt projectile flying from enemy side down to the player hero.
func _fire_enemy_void_bolt_projectile(source_minion: MinionInstance = null) -> VoidBoltProjectile:
	if not is_inside_tree():
		return null
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var from_pos: Vector2
	if source_minion != null:
		var found := false
		for slot in enemy_slots:
			if (slot as BoardSlot).minion == source_minion:
				from_pos = (slot as BoardSlot).global_position + (slot as BoardSlot).size / 2.0
				found = true
				break
		if not found:
			from_pos = Vector2(vp_size.x / 2.0, 200)
	elif _enemy_hero_panel:
		from_pos = _enemy_hero_panel.global_position + _enemy_hero_panel.size / 2.0
	else:
		from_pos = Vector2(vp_size.x / 2.0, 200)
	var to_pos: Vector2
	if _player_status_panel:
		to_pos = _player_status_panel.global_position + _player_status_panel.size / 2.0
	else:
		to_pos = Vector2(vp_size.x / 2.0, vp_size.y - 120)
	var bolt := VoidBoltProjectile.create(from_pos, to_pos)
	vfx_controller.spawn(bolt)
	return bolt

## Cycles through void rune slots so multiple runes alternate firing.
var _void_rune_fire_index: int = 0

## Find the global center position of the next Void Rune trap slot.
## Cycles through all void runes so each one fires in turn.
func _find_void_rune_slot_position() -> Vector2:
	var rune_slots: Array[int] = []
	for i in active_traps.size():
		var trap := active_traps[i] as TrapCardData
		if trap.is_rune and trap.rune_type == Enums.RuneType.VOID_RUNE:
			if i < trap_slot_panels.size():
				rune_slots.append(i)
	if rune_slots.is_empty():
		return Vector2.ZERO
	# Pick the next rune in rotation
	var idx: int = _void_rune_fire_index % rune_slots.size()
	_void_rune_fire_index += 1
	var slot_i: int = rune_slots[idx]
	var panel := trap_slot_panels[slot_i] as Panel
	return panel.global_position + panel.size / 2.0

## Tries to spend a card's costs, applying Dark Mirror relic discount if active.
## Returns true if the card can be played (and costs are deducted).
## Total spark value available on the player's board.
func _player_available_sparks() -> int:
	var total := 0
	for m: MinionInstance in player_board:
		total += (m.card_data as MinionCardData).spark_value
	return total

## True if the player can pay the given spark cost.
func _player_can_afford_sparks(cost: int) -> bool:
	return cost <= 0 or _player_available_sparks() >= cost

## Consume player board minions to pay spark cost. Same rules as enemy:
## eligible fuel must have spark_value <= cost, pick fewest bodies (biggest first).
## Void Spark tokens are killed (fire death triggers), spirits are consumed silently.
func _player_pay_sparks(cost: int) -> bool:
	if cost <= 0:
		return true
	var eligible: Array[MinionInstance] = []
	for m: MinionInstance in player_board:
		var sv: int = (m.card_data as MinionCardData).spark_value
		if sv > 0 and sv <= cost:
			eligible.append(m)
	eligible.sort_custom(func(a: MinionInstance, b: MinionInstance) -> bool:
		return (a.card_data as MinionCardData).spark_value > (b.card_data as MinionCardData).spark_value)
	var remaining := cost
	for m: MinionInstance in eligible:
		if remaining <= 0:
			break
		var sv: int = (m.card_data as MinionCardData).spark_value
		# Void Spark tokens: kill (fire death triggers for Blood Rune etc.)
		# Spirits: consume silently (no death triggers)
		if m.card_data.id == "void_spark":
			combat_manager.kill_minion(m)
		else:
			player_board.erase(m)
			_clear_slot_for(m, player_slots)
			_log("  %s consumed as spark fuel." % m.card_data.card_name)
		# Fire spark consumed event
		if sv > 0 and trigger_manager:
			var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPARK_CONSUMED, "player")
			ctx.minion = m
			ctx.damage = sv
			trigger_manager.fire(ctx)
		remaining -= sv
	return remaining <= 0

func _pay_card_cost(essence_cost: int, mana_cost: int) -> bool:
	_pip_bar.stop_blink()
	# Dark Mirror: reduce both essence and mana costs independently (minimum 0)
	if _relic_cost_reduction > 0:
		var reduction: int = _relic_cost_reduction
		_relic_cost_reduction = 0
		var essence_reduction: int = mini(reduction, essence_cost)
		var mana_reduction: int = mini(reduction, mana_cost)
		essence_cost -= essence_reduction
		mana_cost -= mana_reduction
		if essence_reduction + mana_reduction > 0:
			_log("  Dark Mirror: cost reduced by %d Essence and %d Mana!" % [essence_reduction, mana_reduction], _LogType.PLAYER)
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
	var damage: int = combat_manager.last_attack_damage
	var counter: int = combat_manager.last_counter_damage
	var is_crit: bool = _last_attack_was_crit
	_anim_pre_hp = 0
	var a := _anim_atk_slot
	var d := _anim_def_slot
	_anim_atk_slot = null
	_anim_def_slot = null
	if a and d:
		# Refresh happens inside _play_attack_anim after the lunge completes
		_play_attack_anim(a, d, damage, attacker, defender, is_crit, counter)
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

	# Locate the slot first so we can honour freeze_visuals — clearing a frozen
	# (mid-lunge) slot wipes the attacker's art mid-flight, which looks wrong.
	# If frozen, the clear is deferred to _restore_slot_from_lunge via the
	# death animation path below.
	var slot_is_frozen := dead_slot != null and dead_slot.freeze_visuals
	if minion.owner == "player":
		player_board.erase(minion)
		if not slot_is_frozen:
			_clear_slot_for(minion, player_slots)
		if hand_display:
			hand_display.refresh_condition_glows(self, turn_manager.essence, turn_manager.mana)
	else:
		enemy_board.erase(minion)
		if not slot_is_frozen:
			_clear_slot_for(minion, enemy_slots)
	_log("  %s died" % minion.card_data.card_name, _LogType.DEATH)
	# If the minion has on-death effects, defer their resolution until after the
	# death animation + on-death icon VFX so damage/summons play at the right time.
	if _minion_has_on_death(minion):
		_pending_on_death_vfx.append(minion)
	# Fire death events — handlers in _setup_triggers() apply all passive/talent/deathrattle effects.
	# on_minion_died_death_effect skips minions in _pending_on_death_vfx.
	# Snapshot corruption stacks BEFORE firing death — Corrupt Detonation fires on
	# any removal including death, and stacks are gone by the time death handlers
	# return. Fire the removal event first so detonation damage resolves before
	# downstream death effects see the now-stripped minion.
	var pre_corruption: int = BuffSystem.count_type(minion, Enums.BuffType.CORRUPTION)
	if pre_corruption > 0:
		var rm_ctx := EventContext.make(Enums.TriggerEvent.ON_CORRUPTION_REMOVED, minion.owner)
		rm_ctx.minion = minion
		rm_ctx.damage = pre_corruption
		trigger_manager.fire(rm_ctx)
	var ctx := EventContext.make(
		Enums.TriggerEvent.ON_PLAYER_MINION_DIED if minion.owner == "player"
		else Enums.TriggerEvent.ON_ENEMY_MINION_DIED,
		minion.owner)
	ctx.minion = minion
	ctx.attacker = _last_attacker
	trigger_manager.fire(ctx)
	_refresh_hand_spell_costs()
	# Death animation — defer if lunge is in progress so ghost positions correctly.
	# Position is captured NOW while the slot is still in its original container.
	if dead_slot:
		if dead_slot.freeze_visuals:
			_deferred_death_slots.append({slot = dead_slot, pos = dead_slot.global_position, minion = minion})
		else:
			_animate_minion_death(dead_slot, dead_slot.global_position, minion)

func _on_hero_damaged(target: String, info: Dictionary) -> void:
	if _combat_ended:
		return
	var amount: int = info.get("amount", 0)
	var school: int = info.get("school", Enums.DamageSchool.NONE)
	var is_crit: bool = _last_attack_was_crit
	if target == "player":
		# Bone Shield relic — hero immune this turn
		if _relic_hero_immune:
			_log("  Bone Shield absorbs %d damage!" % amount, _LogType.PLAYER)
			return
		player_hp -= amount
		_player_hero_panel.update(player_hp, GameManager.player_hp_max)
		_log("  You take %d damage  (HP: %d)" % [amount, player_hp], _LogType.DAMAGE)
		# Fire ON_HERO_DAMAGED for every landed hit, including lethal — handlers
		# can react to the killing blow (telemetry, future "save from death" cards).
		var _pctx := EventContext.make(Enums.TriggerEvent.ON_HERO_DAMAGED, "player")
		_pctx.damage = amount
		_pctx.damage_info = info
		trigger_manager.fire(_pctx)
		if player_hp <= 0:
			_flash_hero("player", amount, _on_defeat, school, is_crit)
		else:
			_flash_hero("player", amount, Callable(), school, is_crit)
	else:
		enemy_hp -= amount
		_log("  Enemy takes %d damage  (HP: %d)" % [amount, enemy_hp], _LogType.DAMAGE)
		_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)
		# Fire ON_ENEMY_HERO_DAMAGED for every landed hit, including lethal.
		# Symmetric counterpart to the player branch.
		var _ectx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_HERO_DAMAGED, "enemy")
		_ectx.damage = amount
		_ectx.damage_info = info
		trigger_manager.fire(_ectx)
		# Void Bolt passive trigger — keyed off school via lineage so any future
		# VOID_BOLT-derived sub-school still triggers it. Fires on every Void Bolt
		# hit including the killing blow, matching the trigger event semantics.
		if Enums.has_school(school, Enums.DamageSchool.VOID_BOLT) and _handlers:
			_handlers._apply_void_bolt_passives()
		if enemy_hp <= 0:
			# F15 Abyss Sovereign: intercept P1 death and transition to P2.
			# Transition mutates board/deck/passives synchronously, then we
			# defer a forced end-of-player-turn so the current damage/attack
			# resolution can unwind cleanly before control flips to enemy.
			var pt = preload("res://combat/board/PhaseTransition.gd")
			if pt.attempt(self):
				_flash_hero("enemy", amount, Callable(), school, is_crit)
				_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)
				call_deferred("_force_end_player_turn_for_phase_transition")
				return
			_flash_hero("enemy", amount, _on_victory, school, is_crit)
		else:
			_flash_hero("enemy", amount, Callable(), school, is_crit)

func _on_hero_healed(target: String, amount: int) -> void:
	if target == "player":
		player_hp = mini(player_hp + amount, GameManager.player_hp_max)
		_player_hero_panel.update(player_hp, GameManager.player_hp_max)
		_flash_hero_heal("player", amount)
		_log("  You heal %d HP  (HP: %d)" % [amount, player_hp], _LogType.HEAL)
	elif target == "enemy":
		enemy_hp = mini(enemy_hp + amount, enemy_hp_max)
		_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)
		_flash_hero_heal("enemy", amount)
		_log("  Enemy heals %d HP  (HP: %d)" % [amount, enemy_hp], _LogType.ENEMY)

# ---------------------------------------------------------------------------
# Targeted spell helpers
# ---------------------------------------------------------------------------

## Returns true if at least one valid target exists for this card's on-play target type.
## If false, the card skips targeting and goes straight to placement (effect fires but does nothing).
## Uses the card's raw target type — for talent-gated overrides see _has_valid_minion_on_play_targets_for.
# Targeting facades — delegate to Targeting helper. Kept on scene so the
# play-card flow doesn't need to prefix every call with `targeting.`.
func _has_valid_minion_on_play_targets(card: MinionCardData) -> bool:
	return targeting.has_valid_minion_on_play_targets(card)

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

func _spell_highlight_color_picker(spell: SpellCardData) -> Callable:
	return targeting.spell_highlight_color_picker(spell)

func _highlight_spell_targets(spell: SpellCardData) -> void:
	targeting.highlight_spell_targets(spell)

func _is_valid_spell_target(minion: MinionInstance, target_type: String) -> bool:
	return targeting.is_valid_spell_target(minion, target_type)
		"enemy_minion_or_hero":   return true
		"any_minion_or_enemy_hero": return true
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
		var resolve_damage := func(_i: int) -> void:
			_pre_player_spell_cast(spell)
			if not spell.effect_steps.is_empty():
				var ctx := EffectContext.make(self, "player")
				ctx.chosen_target = captured_target
				ctx.source_card_id = spell.id
				EffectResolver.run(spell.effect_steps, ctx)
			else:
				_resolve_spell_effect(spell.effect_id, captured_target)
			_post_player_spell_cast(spell, captured_target)
		await vfx_controller.play_spell(spell.id, "player", captured_target, resolve_damage)
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
		var resolve_damage := func(_i: int) -> void:
			_pre_player_spell_cast(spell)
			# Compute damage using the same bonus_amount/bonus_conditions logic as EffectResolver._amount.
			# Pick up damage_school from the step too — this hero-targeted path bypasses
			# EffectResolver entirely, so the school must be re-read here or it's lost.
			var base_dmg: int = 0
			var school: int = Enums.DamageSchool.NONE
			for step in spell.effect_steps:
				var s := EffectStep.from_dict(step) if step is Dictionary else step as EffectStep
				if s and s.effect_type == EffectStep.EffectType.DAMAGE_MINION:
					var ctx := EffectContext.make(self, "player")
					if ConditionResolver.check_all(s.conditions, ctx, null):
						base_dmg += s.amount
						if s.bonus_amount != 0 and not s.bonus_conditions.is_empty():
							if ConditionResolver.check_all(s.bonus_conditions, ctx, null):
								base_dmg += s.bonus_amount
						# First contributing damage step's school wins. (All damage steps
						# on a spell typically share a school; if not, that's a card design
						# question, not a plumbing concern.)
						if school == Enums.DamageSchool.NONE:
							school = s.damage_school
			var total: int = base_dmg + _player_spell_damage_bonus
			_log("  %s: %d Void damage to enemy hero." % [spell.card_name, total], _LogType.PLAYER)
			combat_manager.apply_hero_damage("enemy",
					CombatManager.make_damage_info(total, Enums.DamageSource.SPELL, school, null, spell.id))
			_post_player_spell_cast(spell, null)
		await vfx_controller.play_spell(spell.id, "player", _enemy_status_panel, resolve_damage)
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
## Traps play their animations one-by-one so they don't overlap.
func _fire_traps_for(owner: String, trigger: int, triggering_minion: MinionInstance = null) -> void:
	if owner == "enemy" and _enemy_traps_blocked:
		return
	if owner == "player" and _player_traps_blocked:
		return
	var traps: Array = active_traps if owner == "player" else (enemy_ai.active_traps if enemy_ai else [])
	if owner == "enemy" and enemy_ai == null:
		return
	# Collect matching traps first, then resolve sequentially
	var matching: Array[TrapCardData] = []
	for trap in traps.duplicate():
		if trap.is_rune:
			continue
		if trap.trigger != trigger:
			continue
		matching.append(trap)
	for trap in matching:
		if not is_inside_tree():
			return
		var slot_idx := traps.find(trap)
		_flash_trap_slot_for(owner, slot_idx)
		_log("⚡ %s%s triggered!" % [("Enemy " if owner == "enemy" else ""), trap.card_name], _LogType.TRAP)
		# Consume non-reusable trap immediately so a subsequent trigger (e.g. the
		# next enemy attack) during the ~1.1s cast animation doesn't re-fire it.
		if not trap.reusable:
			traps.erase(trap)
			_update_trap_display_for(owner)
		var effect_resolved := false
		_show_card_cast_anim(trap, owner == "enemy", func() -> void:
			var ctx := EffectContext.make(self, owner)
			ctx.trigger_minion = triggering_minion
			EffectResolver.run(trap.effect_steps, ctx)
			effect_resolved = true
		)
		# Wait for the full card animation to finish (~1.1s)
		while not effect_resolved and is_inside_tree():
			await get_tree().process_frame
		# Small gap between sequential traps
		if is_inside_tree():
			await get_tree().create_timer(0.6).timeout

## Flash a trap slot gold to indicate it fired.
func _flash_trap_slot_for(owner: String, slot_idx: int) -> void:
	trap_env_display.flash_slot(owner, slot_idx)

## Called by EnemyAI's minion_summoned signal.
## slot.place_minion and triggers are deferred until after the reveal animation.
func _on_enemy_minion_summoned(minion: MinionInstance, slot: BoardSlot) -> void:
	_log("Enemy summons: %s" % minion.card_data.card_name, _LogType.ENEMY)
	_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)
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
		AudioManager.play_sfx("res://assets/audio/sfx/minions/minion_summon.wav", -20.0)
		slot.place_minion(minion)
	# ON_PLAY effects are resolved by CombatHandlers.on_enemy_minion_played_effect registered in _setup_triggers().
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "enemy")
	ctx.minion = minion
	ctx.card = minion.card_data
	trigger_manager.fire(ctx)
	_maybe_spawn_aura_pulse(minion.card_data, slot)
	# Signal AFTER place_minion — guarantees AI continues only after the slot is occupied.
	enemy_summon_reveal_done.emit()
	if not is_inside_tree(): return
	if slot:
		_animate_enemy_landing(slot, total_cost, is_champion)
		# Corrupted Death passive: special VFX for Void-Touched Imp summons
		if minion.card_data.id == "void_touched_imp" and "corrupted_death" in _active_enemy_passives:
			var cd_vfx := CorruptedDeathSummonVFX.create(slot)
			vfx_controller.spawn(cd_vfx)

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
	visual.position     = vp / 2.0 - visual.size / 2.0
	visual.pivot_offset = visual.size * 0.5
	visual.scale        = Vector2(0.65, 0.65)

	# Fade in + scale-pop (parallel), matching spell preview feel.
	var t1 := create_tween().set_parallel(true)
	t1.tween_property(visual, "modulate:a", 1.0, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t1.tween_property(visual, "scale", Vector2(1.0, 1.0), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	_enemy_spell_cast_active = true
	_log("Enemy casts: %s" % spell.card_name, _LogType.ENEMY)
	_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)
	# Phase Disruptor counter: player counters enemy spell
	if _enemy_spell_counter > 0:
		_enemy_spell_counter -= 1
		_log("  Spell countered!", _LogType.PLAYER)
		_show_spell_countered_anim(spell)
		_enemy_spell_cast_active = false
		enemy_spell_cast_done.emit()
		return
	# Fire ON_ENEMY_SPELL_CAST BEFORE resolving so Null Seal can set _spell_cancelled.
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "enemy")
	ctx.card = spell
	trigger_manager.fire(ctx)
	var was_cancelled := _spell_cancelled
	_spell_cancelled = false
	if was_cancelled:
		_enemy_spell_cast_active = false
		enemy_spell_cast_done.emit()
		return
	# Capture chosen target before animation; dispatch to the correct EffectContext field by type.
	var chosen = enemy_ai.spell_chosen_target
	enemy_ai.spell_chosen_target = null
	# Show large card preview; resolve effects on impact so damage visuals sync
	_show_card_cast_anim(spell, true, func() -> void:
		# Build the damage-resolution callable so VfxController can fire it at
		# the impact moment of the chosen spell's VFX.
		var resolve_damage := func(_i: int) -> void:
			if not spell.effect_steps.is_empty():
				var ectx := EffectContext.make(self, "enemy")
				ectx.source_card_id = spell.id
				if chosen is MinionInstance:
					ectx.chosen_target = chosen
				else:
					ectx.chosen_object = chosen
				EffectResolver.run(spell.effect_steps, ectx)
			elif not spell.effect_id.is_empty():
				_resolve_spell_effect(spell.effect_id, null, "enemy")
		await vfx_controller.play_spell(spell.id, "enemy", chosen, resolve_damage)
		_enemy_spell_cast_active = false
		enemy_spell_cast_done.emit()
	)

## Called by EnemyAI's trap_placed signal.
func _on_enemy_trap_placed(trap: TrapCardData) -> void:
	if trap.is_rune:
		_log("Enemy places rune: %s" % trap.card_name, _LogType.ENEMY)
		_apply_rune_aura(trap, "enemy")
	else:
		_log("Enemy sets a trap.", _LogType.ENEMY)
	_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)
	_update_enemy_trap_display()

## Called by EnemyAI's environment_placed signal.
func _on_enemy_environment_placed(env: EnvironmentCardData) -> void:
	_log("Enemy plays environment: %s" % env.card_name, _LogType.ENEMY)
	_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)

# Facades to TrapEnvDisplay — kept so external callers (HardcodedEffects,
# EffectResolver, RelicEffects) keep working unchanged.
func _update_trap_display_for(owner: String) -> void:
	trap_env_display.update_traps_for(owner)

func _update_trap_display() -> void:
	trap_env_display.update_traps_for("player")

func _update_enemy_trap_display() -> void:
	trap_env_display.update_traps_for("enemy")

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
func _apply_rune_aura(rune: TrapCardData, owner: String = "player") -> void:
	var entries: Array = []

	# Primary handler — mirror trigger for enemy side
	if rune.aura_trigger >= 0 and not rune.aura_effect_steps.is_empty():
		var trigger: int = rune.aura_trigger if owner == "player" else Enums.mirror_trigger(rune.aura_trigger as Enums.TriggerEvent)
		var h := func(event_ctx: EventContext):
			var ctx := EffectContext.make(self, owner)
			ctx.trigger_minion = event_ctx.minion
			ctx.from_rune = true
			ctx.source_rune = rune
			EffectResolver.run(rune.aura_effect_steps, ctx)
		trigger_manager.register(trigger, h, 20)
		entries.append({event = trigger, handler = h})

		# Extra handler — same effect_steps, fires on a second event (e.g. sacrifice in
		# addition to death so Blood/Soul Rune react to ON LEAVE removals).
		if rune.aura_extra_trigger >= 0:
			var extra_trigger: int = rune.aura_extra_trigger if owner == "player" else Enums.mirror_trigger(rune.aura_extra_trigger as Enums.TriggerEvent)
			trigger_manager.register(extra_trigger, h, 20)
			entries.append({event = extra_trigger, handler = h})

	# Secondary handler (e.g. Soul Rune per-turn reset)
	if rune.aura_secondary_trigger >= 0 and not rune.aura_secondary_steps.is_empty():
		var sec_trigger: int = rune.aura_secondary_trigger if owner == "player" else Enums.mirror_trigger(rune.aura_secondary_trigger as Enums.TriggerEvent)
		var h2 := func(event_ctx: EventContext):
			var ctx := EffectContext.make(self, owner)
			ctx.trigger_minion = event_ctx.minion
			ctx.source_rune = rune
			EffectResolver.run(rune.aura_secondary_steps, ctx)
		trigger_manager.register(sec_trigger, h2, 20)
		entries.append({event = sec_trigger, handler = h2})

	# On-place steps run immediately at placement (e.g. Dominion Rune existing-minion sweep)
	if not rune.aura_on_place_steps.is_empty():
		var ctx := EffectContext.make(self, owner)
		EffectResolver.run(rune.aura_on_place_steps, ctx)

	if not entries.is_empty():
		_rune_aura_handlers.append({rune_id = rune.id, entries = entries})

## Unregister aura handlers when a rune is removed (destroyed or consumed by ritual).
## Finds the FIRST placement entry matching rune.id and removes only that one,
## so two runes of the same type are handled independently.
func _remove_rune_aura(rune: TrapCardData, owner: String = "player") -> void:
	for i in _rune_aura_handlers.size():
		if _rune_aura_handlers[i].rune_id == rune.id:
			for entry in _rune_aura_handlers[i].entries:
				trigger_manager.unregister(entry.event, entry.handler)
			_rune_aura_handlers.remove_at(i)
			break
	if not rune.aura_on_remove_steps.is_empty():
		var ctx := EffectContext.make(self, owner)
		EffectResolver.run(rune.aura_on_remove_steps, ctx)

## Apply or remove one layer of the Dominion Rune's ATK aura on all friendly Demons.
## active=true adds one bonus entry per-minion; active=false removes one entry per-minion,
## preserving buffs from any other Dominion Runes still on the board.
## amount is passed in from _apply_rune_aura so runic_attunement doubling is respected.
func _refresh_dominion_aura(active: bool, amount: int = 100) -> void:
	for m in player_board:
		if m.card_data.minion_type == Enums.MinionType.DEMON:
			if active:
				BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, amount, "dominion_rune", false, false)
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
## Wildcard runes (is_wildcard_rune = true) can substitute for any missing type.
func _runes_satisfy(runes: Array, required: Array[int]) -> bool:
	# Collect exact-match rune types and count wildcards
	var available: Array[int] = []
	var wildcards: int = 0
	for r in runes:
		var trap := r as TrapCardData
		if trap.is_wildcard_rune:
			wildcards += 1
		else:
			available.append(trap.rune_type)
	# Check each requirement: exact match first, then spend a wildcard
	var remaining_wildcards := wildcards
	for req in required:
		if req in available:
			available.erase(req)  # consume one exact match
		elif remaining_wildcards > 0:
			remaining_wildcards -= 1  # wildcard fills the gap
		else:
			return false
	return true

## Consume the required runes and cast the ritual effect.
## Exact rune type matches are consumed first; wildcard runes fill remaining gaps.
## Each rune instance is consumed at most once — tracked by index to avoid duplicates.
func _fire_ritual(ritual: RitualData) -> void:
	var consumed_indices: Array[int] = []
	for req in ritual.required_runes:
		var found := false
		# Try exact match first
		for i in active_traps.size():
			if i in consumed_indices:
				continue
			var trap := active_traps[i] as TrapCardData
			if trap.is_rune and not trap.is_wildcard_rune and trap.rune_type == req:
				consumed_indices.append(i)
				found = true
				break
		# Fall back to wildcard rune
		if not found:
			for i in active_traps.size():
				if i in consumed_indices:
					continue
				var trap := active_traps[i] as TrapCardData
				if trap.is_rune and trap.is_wildcard_rune:
					consumed_indices.append(i)
					break
	# Remove consumed runes in reverse index order so earlier indices stay valid
	consumed_indices.sort()
	consumed_indices.reverse()
	for i in consumed_indices:
		var trap := active_traps[i] as TrapCardData
		_remove_rune_aura(trap)
		active_traps.remove_at(i)
	# Stop all glow tweens before refreshing — prevents stale glow on repurposed slots
	for i in trap_slot_panels.size():
		trap_env_display.stop_rune_glow(i)
	_update_trap_display()
	_log("★ RITUAL — %s!" % ritual.ritual_name, _LogType.PLAYER)
	var ritual_ctx := EffectContext.make(self, "player")
	EffectResolver.run(ritual.effect_steps, ritual_ctx)
	# Fire ON_RITUAL_FIRED so registry-based handlers (ritual_surge) can respond
	var fired_ctx := EventContext.make(Enums.TriggerEvent.ON_RITUAL_FIRED, "player")
	trigger_manager.fire(fired_ctx)


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
const _ABYSS_HEROES_LIST     := ["lord_vael", "seris"]

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

func _add_tooltip_icon_block(parent: VBoxContainer, title: String, body: String, icon_path: String,
		title_color: Color, body_color: Color) -> void:
	var outer := HBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_BEGIN
	outer.add_theme_constant_override("separation", 10)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(outer)

	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon_bg := PanelContainer.new()
		icon_bg.custom_minimum_size = Vector2(44, 44)
		icon_bg.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_style := StyleBoxFlat.new()
		icon_style.bg_color = Color(0.12, 0.08, 0.18, 0.92)
		icon_style.border_color = Color(0.48, 0.28, 0.72, 0.95)
		icon_style.set_border_width_all(1)
		icon_style.set_corner_radius_all(5)
		icon_style.content_margin_left = 4.0
		icon_style.content_margin_right = 4.0
		icon_style.content_margin_top = 4.0
		icon_style.content_margin_bottom = 4.0
		icon_bg.add_theme_stylebox_override("panel", icon_style)
		outer.add_child(icon_bg)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(36, 36)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(icon_path)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_bg.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	text_box.add_theme_constant_override("separation", 3)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(text_box)

	if title != "":
		var title_lbl := Label.new()
		title_lbl.text = title
		title_lbl.add_theme_font_size_override("font_size", 15)
		title_lbl.add_theme_color_override("font_color", title_color)
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_box.add_child(title_lbl)

	var body_lbl := Label.new()
	body_lbl.text = body
	body_lbl.add_theme_font_size_override("font_size", 12)
	body_lbl.add_theme_color_override("font_color", body_color)
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(body_lbl)

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
	_talent_tip_vbox = tip_vbox

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
			_add_tooltip_icon_block(
				tip_vbox,
				"",
				passive.description,
				passive.icon_path,
				Color(0.90, 0.90, 0.90, 1.0),
				Color(0.65, 0.82, 0.70, 1.0)
			)

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
			_add_tooltip_icon_block(
				tip_vbox,
				td.talent_name,
				td.description,
				td.icon_path,
				Color(0.92, 0.85, 1.0, 1.0),
				Color(0.65, 0.62, 0.72, 1.0)
			)

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
		"pack_instinct": {
			"name": "Pack Instinct",
			"desc": "Each Feral Imp gains +50 ATK for every other Feral Imp on the board."
		},
		"champion_rogue_imp_pack": {
			"name": "Champion: Rogue Imp Pack",
			"desc": "Summoned after 4 Rabid Imps have attacked. SWIFT. AURA: All friendly FERAL IMP minions have +100 ATK."
		},
		"champion_corrupted_broodlings": {
			"name": "Champion: Corrupted Broodlings",
			"desc": "Summoned after 3 friendly minions have died. On death: Summon a Void-Touched Imp."
		},
		"champion_imp_matriarch": {
			"name": "Champion: Imp Matriarch",
			"desc": "Summoned after 2nd Pack Frenzy cast. GUARD. AURA: Pack Frenzy also gives all FERAL IMP minions +200 HP."
		},
		"champion_abyss_cultist_patrol": {
			"name": "Champion: Abyss Cultist Patrol",
			"desc": "Summoned after 5 corruption stacks consumed. AURA: Corruption applied to enemy minions instantly detonates for 100 damage per stack."
		},
		"champion_void_ritualist": {
			"name": "Champion: Void Ritualist",
			"desc": "Summoned when Ritual Sacrifice triggers. AURA: Rune placement costs 1 less Mana."
		},
		"champion_corrupted_handler": {
			"name": "Champion: Corrupted Handler",
			"desc": "Summoned after 3 Void Sparks created. AURA: Whenever a Void Spark is summoned, deal 200 damage to enemy hero."
		},
		"champion_duel": {
			"name": "Champion: Void Duel",
			"desc": "Enemy minions with Critical Strike have Spell Immune."
		},
		"corrupted_death": {
			"name": "Corrupted Death",
			"desc": "Void-Touched Imp costs 1 less Essence."
		},
		"ancient_frenzy": {
			"name": "Ancient Frenzy",
			"desc": "Pack Frenzy also gives all FERAL IMP minions Lifedrain this turn, and costs 1 less Mana. Starts with one extra Pack Frenzy in hand."
		},
		# ── Act 2 enemy passives ──────────────────────────────────────────────────
		"feral_reinforcement": {
			"name": "Feral Reinforcement",
			"desc": "The first Human summoned each turn adds a random FERAL IMP to your hand."
		},
		"corrupt_authority": {
			"name": "Corrupt Authority",
			"desc": "Each Human summoned applies 1 Corruption to a random enemy minion. Each FERAL IMP summoned consumes all Corruption stacks on enemy minions, dealing 100 damage per stack."
		},
		"ritual_sacrifice": {
			"name": "Ritual Sacrifice",
			"desc": "When a FERAL IMP is summoned and you have a Blood Rune and Dominion Rune active: consume both runes and the imp, deal 200 damage to 2 random enemy targets, then summon a 500/500 Demon."
		},
		"void_unraveling": {
			"name": "Void Unraveling",
			"desc": "When a FERAL IMP is summoned, all enemy Void Sparks are Corrupted and transferred to your board."
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

func _show_large_preview(card_data: CardData, source_visual: CardVisual = null) -> void:
	large_preview.show_card(card_data, source_visual)

func _hide_large_preview() -> void:
	large_preview.hide_card()

func _on_board_slot_hover_enter(slot: BoardSlot) -> void:
	if slot.minion and slot.minion.card_data:
		large_preview.show_card(slot.minion.card_data)
		if large_preview.visual != null:
			large_preview.visual.override_stat_display(slot.minion.spawn_atk, slot.minion.spawn_health)

func _on_enemy_hero_button_pressed() -> void:
	if not turn_manager.is_player_turn or selected_attacker == null:
		return
	if CombatManager.board_has_taunt(enemy_board):
		return
	if not selected_attacker.can_attack_hero():
		return
	# Void Manifestation: Void Imp clan minions deal Void Bolt damage to enemy hero
	if _minion_has_tag(selected_attacker, "void_imp") and _has_talent("void_manifestation"):
		var atk := selected_attacker.effective_atk()
		_log("Your %s attacks Enemy Hero with a Void Bolt!" % selected_attacker.card_data.card_name, _LogType.PLAYER)
		selected_attacker.attack_count += 1
		selected_attacker.state = Enums.MinionState.EXHAUSTED
		_refresh_slot_for(selected_attacker)
		var attacker_ref := selected_attacker
		selected_attacker = null
		_clear_all_highlights()
		_enemy_hero_panel.show_attackable(false)
		# void_manifestation talent retags Void Imp clan basic attack — MINION source.
		await _deal_void_bolt_damage(atk, attacker_ref, false, true)
		return
	_log("Your %s attacks Enemy Hero" % selected_attacker.card_data.card_name)
	var _hero_atk_slot := _find_slot_for(selected_attacker)
	var _hero_attacker_ref: MinionInstance = selected_attacker
	combat_manager.resolve_minion_attack_hero(selected_attacker, "enemy")
	if _hero_atk_slot and _enemy_status_panel:
		_play_hero_attack_anim(_hero_atk_slot, _enemy_status_panel, _hero_attacker_ref)
	selected_attacker = null
	_clear_all_highlights()
	_enemy_hero_panel.show_attackable(false)

# ---------------------------------------------------------------------------
# Win / loss
# ---------------------------------------------------------------------------

func _on_victory() -> void:
	if _combat_ended:
		return
	_combat_ended = true
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
	if _combat_ended:
		return
	_combat_ended = true
	_disable_combat_buttons()
	if GameManager.has_revive:
		# Offer revive option — restart the same fight
		if game_over_label:
			game_over_label.text = "DEFEATED\nSecond Wind activates!"
		if restart_button:
			restart_button.text = "Revive & Retry"
			restart_button.disabled = false
		_pending_revive = true
	else:
		GameManager.end_run(false)
		if game_over_label:
			game_over_label.text = "DEFEAT"
		if restart_button:
			restart_button.text = "Return to Menu"
	if game_over_panel:
		game_over_panel.visible = true

var _pending_revive: bool = false
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
	if _pending_revive:
		# Consume revive and restart the same fight with full HP
		GameManager.has_revive = false
		GameManager.player_hp = GameManager.player_hp_max
		GameManager.go_to_scene("res://combat/board/CombatScene.tscn")
	else:
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

func _play_void_netter_on_play_vfx(source_minion: MinionInstance, target: MinionInstance, owner_side: String) -> void:
	if source_minion == null or target == null:
		return
	var source_slot: BoardSlot = _find_slot_for(source_minion)
	var target_slot: BoardSlot = _find_slot_for(target)
	var apply_damage := func() -> void:
		if target == null or not is_instance_valid(target) or target.current_health <= 0:
			return
		# Void Netter on-play is a MINION-emitted effect on both sides. _spell_dmg
		# defaults to SPELL source, so pass an explicit info to keep this MINION-source.
		var netter_info := CombatManager.make_damage_info(0, Enums.DamageSource.MINION, Enums.DamageSchool.NONE, source_minion, "void_netter")
		if owner_side == "player":
			_spell_dmg(target, 200, netter_info)
			return
		var slot_now := _find_slot_for(target)
		combat_manager.apply_damage_to_minion(target,
				CombatManager.make_damage_info(200, Enums.DamageSource.MINION, Enums.DamageSchool.NONE, source_minion, "void_netter"))
		_refresh_slot_for(target)
		if slot_now != null:
			_flash_slot(slot_now)
			_spawn_damage_popup(slot_now.get_global_rect().get_center(), 200)
	if vfx_controller == null or source_slot == null or target_slot == null:
		apply_damage.call()
		return
	var vfx := VoidNetterVFX.create(source_slot, target_slot, apply_damage)
	vfx_controller.spawn(vfx)

func _play_frenzied_imp_vfx(source_minion: MinionInstance, target: MinionInstance, feral_count: int, apply_damage: Callable) -> void:
	if source_minion == null or target == null or vfx_controller == null:
		if apply_damage.is_valid():
			apply_damage.call()
		return
	var source_slot: BoardSlot = _find_slot_for(source_minion)
	var target_slot: BoardSlot = _find_slot_for(target)
	if source_slot == null or target_slot == null:
		if apply_damage.is_valid():
			apply_damage.call()
		return
	var source_pos: Vector2 = source_slot.get_global_rect().get_center()
	var target_pos: Vector2 = target_slot.get_global_rect().get_center()
	var vfx := FrenziedImpHurlVFX.create(source_pos, target_pos, feral_count, target_slot, target_slot)
	var fired: Array[bool] = [false]
	vfx.impact_hit.connect(func(_idx: int) -> void:
		if fired[0]:
			return
		fired[0] = true
		if apply_damage.is_valid():
			apply_damage.call())
	_on_play_vfx_active = true
	vfx_controller.spawn(vfx)
	await vfx.finished
	_on_play_vfx_active = false
	on_play_vfx_done.emit()

func _clear_slot_for(minion: MinionInstance, slots: Array[BoardSlot]) -> void:
	for slot in slots:
		if slot.minion == minion:
			slot.remove_minion()
			return

## Safety sweep: find any minion on a slot whose HP ≤ 0 and that is no longer in the
## board array, then clear the slot.  Guards against edge-case desync between board
## data and slot visuals (e.g. death during async animation callbacks).
func _sweep_dead_minions() -> void:
	for slot in player_slots:
		if slot.minion != null:
			if slot.minion.current_health <= 0 or not player_board.has(slot.minion):
				slot.remove_minion()
	for slot in enemy_slots:
		if slot.minion != null:
			if slot.minion.current_health <= 0 or not enemy_board.has(slot.minion):
				slot.remove_minion()

## Flash + dissolve upward death animation.
## Spawns a ghost overlay in $UI so the HBoxContainer layout is never disturbed.
## pos must be passed explicitly — do NOT read slot.global_position here, as the slot
## may have just been reparented and layout recalculation is deferred to the next frame.
func _animate_minion_death(slot: BoardSlot, pos: Vector2, dead_minion: MinionInstance = null) -> void:
	_active_death_anims += 1
	await _animate_minion_death_body(slot, pos, dead_minion)
	_active_death_anims -= 1
	if _active_death_anims <= 0:
		_active_death_anims = 0
		death_anims_done.emit()

func _animate_minion_death_body(slot: BoardSlot, pos: Vector2, dead_minion: MinionInstance = null) -> void:
	# If this death was a sacrifice, wait for the ritual VFX to reach its
	# shatter beat before starting the ghost rise — the soul leaves with
	# the motes, not while the sigil is still blooming.
	if dead_minion != null:
		var id: int = dead_minion.get_instance_id()
		if _pending_sacrifice_ghost_delay.has(id):
			var delay: float = float(_pending_sacrifice_ghost_delay[id])
			_pending_sacrifice_ghost_delay.erase(id)
			if delay > 0.0:
				await get_tree().create_timer(delay).timeout
				if not is_inside_tree():
					return
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

	ghost.queue_free()

	# Soul-rise: textured ghost sprite drifts upward while fading out
	var soul := TextureRect.new()
	soul.texture = load("res://assets/art/fx/ghost_card_soul.png")
	soul.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	soul.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	soul.z_index = 5
	soul.z_as_relative = false
	soul.mouse_filter = Control.MOUSE_FILTER_IGNORE
	soul.modulate = Color(1.0, 1.0, 1.0, 0.9)
	$UI.add_child(soul)
	var soul_sz := sz * 0.4
	soul.set_size(soul_sz)
	soul.pivot_offset = soul_sz / 2.0
	soul.global_position = pos + (sz - soul_sz) / 2.0

	var t2 := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t2.tween_property(soul, "global_position:y", soul.global_position.y - 50.0, 0.65)
	t2.tween_property(soul, "modulate:a", 0.0, 0.65)
	await t2.finished
	if is_instance_valid(soul):
		soul.queue_free()

	# On-death icon VFX — show if the dead minion had on-death effects
	if dead_minion != null and _minion_has_on_death(dead_minion):
		if not is_inside_tree(): return
		var icon_vfx := OnDeathIconVFX.create(pos, sz)
		vfx_controller.spawn(icon_vfx)
		await icon_vfx.finished
		# Void-Touched Imp: AoE death explosion VFX before damage resolves
		if dead_minion.card_data.id == "void_touched_imp":
			if not is_inside_tree(): return
			var origin_center: Vector2 = pos + sz * 0.5
			var opponent_slots: Array = _get_opponent_occupied_slots(dead_minion.owner)
			var opponent_board: Control = $UI/EnemyBoard if dead_minion.owner == "player" else $UI/PlayerBoard
			var death_vfx := VoidTouchedImpDeathVFX.create(origin_center, opponent_slots, opponent_board)
			vfx_controller.spawn(death_vfx)
			await death_vfx.impact_hit
			if not is_inside_tree(): return
		# Resolve deferred on-death effects now that the icon has faded
		_resolve_deferred_on_death(dead_minion)


## Returns true if a minion has any on-death effects (steps or granted).
func _minion_has_on_death(minion: MinionInstance) -> bool:
	if minion.card_data is MinionCardData:
		var card := minion.card_data as MinionCardData
		if not card.on_death_effect_steps.is_empty():
			return true
		if not card.on_death_effect.is_empty():
			return true
	if not minion.granted_on_death_effects.is_empty():
		return true
	return false


## Resolve on-death effects that were deferred for the icon VFX.
func _resolve_deferred_on_death(minion: MinionInstance) -> void:
	_pending_on_death_vfx.erase(minion)
	if not is_inside_tree():
		return
	if _handlers:
		_handlers._resolve_on_death(minion)

## Fire death animations queued during freeze_visuals. Called by VfxController
## after a damaging spell VFX finishes, and by _restore_slot_from_lunge after
## a lunge completes. Captured positions are used so the ghost lines up with
## the slot's original spot (not its post-lunge location).
func _flush_deferred_deaths() -> void:
	if _deferred_death_slots.is_empty():
		return
	var pending := _deferred_death_slots.duplicate()
	_deferred_death_slots.clear()
	for entry in pending:
		var slot: BoardSlot = entry.slot
		# Slot visuals were held during the lunge freeze — now that the attacker
		# has returned to origin, clear the art so the ghost rises from an empty slot.
		if slot != null and slot.minion != null:
			slot.remove_minion()
		_animate_minion_death(slot, entry.pos, entry.get("minion"))

func _clear_all_highlights() -> void:
	targeting.clear_all_highlights()
	_pending_relic_target = ""

func _find_slot_for(minion: MinionInstance) -> BoardSlot:
	var slots := player_slots if minion.owner == "player" else enemy_slots
	for slot in slots:
		if slot.minion == minion:
			return slot
	return null


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
	_flush_deferred_deaths()

func _play_attack_anim(atk_slot: BoardSlot, def_slot: BoardSlot, damage: int,
		attacker: MinionInstance = null, defender: MinionInstance = null,
		is_crit: bool = false, counter_damage: int = 0) -> void:
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
			_spawn_damage_popup(def_rect.get_center(), damage, is_crit)
		if counter_damage > 0:
			_flash_slot(atk_slot)
			_spawn_damage_popup(atk_slot.get_global_rect().get_center(), counter_damage)
	)
	tw.tween_property(atk_slot, "position", atk_rect.position, 0.16)
	tw.tween_callback(func() -> void:
		_restore_slot_from_lunge(atk_slot, orig_parent, orig_index, placeholder)
		def_slot.freeze_visuals = false
		def_slot._refresh_visuals()
		if attacker: _refresh_slot_for(attacker)
		if defender: _refresh_slot_for(defender)
	)

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


func _flash_slot(slot: BoardSlot) -> void:
	var tw := slot.create_tween()
	tw.tween_property(slot, "modulate", Color(1.8, 0.30, 0.30, 1.0), 0.06)
	tw.tween_property(slot, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.22)

## Show a large centred card visual when a spell/trap/environment is cast or triggered.
## Animates in → calls on_impact → holds → fades out.
## Pass Callable() for on_impact when there are no effects to delay.
func _show_card_cast_anim(card: CardData, is_enemy: bool, on_impact: Callable) -> void:
	# Spell-only casting windup glyph at the caster position.
	if card is SpellCardData:
		_spawn_casting_windup(is_enemy)
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
	# Hold so player can read the card
	tw.tween_interval(0.63)
	# Animate out
	tw.tween_property(cv, "modulate:a", 0.0, 0.22)
	tw.tween_callback(cv.queue_free)
	# Impact (VFX + damage) fires after preview fades so it isn't covered
	tw.tween_callback(on_impact)

## Spawn the faction-themed casting windup glyph at the caster position.
## Player: bottom-centre of the viewport, above the hand zone.
## Enemy: centred on the enemy hero panel.
func _spawn_casting_windup(is_enemy: bool) -> void:
	var faction: String
	var center: Vector2
	if is_enemy:
		# Faction by act — Act 1 feral, Act 2 corrupted, Act 3/4 abyss.
		var act: int = GameManager.get_current_act() if GameManager else 3
		match act:
			1: faction = "feral"
			2: faction = "corrupted"
			_: faction = "abyss"
		if _enemy_hero_panel and _enemy_hero_panel.is_inside_tree():
			center = _enemy_hero_panel.global_position + _enemy_hero_panel.size * 0.5
		else:
			var vp := get_viewport().get_visible_rect().size
			center = Vector2(vp.x * 0.5, 120.0)
	else:
		faction = "void"
		var vp2 := get_viewport().get_visible_rect().size
		center = Vector2(vp2.x * 0.5, vp2.y - 100.0)
	var windup := CastingWindupVFX.create(faction, center, is_enemy)
	vfx_controller.spawn(windup)

## Show a "COUNTERED!" animation: card appears, gets a red overlay + shake, then fizzles out.
func _show_spell_countered_anim(card: CardData) -> void:
	var cv: CardVisual = CARD_VISUAL_SCENE.instantiate() as CardVisual
	cv.apply_size_mode("combat_preview")
	cv.z_index = 100
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(cv)
	cv.setup(card)
	var vp := get_viewport().get_visible_rect().size
	var card_sz := Vector2(336.0, 504.0)
	var center_pos := (vp - card_sz) * 0.5
	cv.position     = center_pos
	cv.pivot_offset = card_sz * 0.5
	cv.modulate = Color(1.0, 1.0, 1.0, 0.0)
	cv.scale = Vector2(0.65, 0.65)
	# "COUNTERED!" text overlay
	var counter_lbl := Label.new()
	counter_lbl.text = "COUNTERED!"
	counter_lbl.add_theme_font_override("font", DAMAGE_FONT)
	counter_lbl.add_theme_font_size_override("font_size", 36)
	counter_lbl.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15, 1.0))
	counter_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	counter_lbl.add_theme_constant_override("shadow_offset_x", 3)
	counter_lbl.add_theme_constant_override("shadow_offset_y", 3)
	counter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counter_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	counter_lbl.set_anchors_preset(Control.PRESET_CENTER)
	counter_lbl.size = Vector2(336, 60)
	counter_lbl.position = Vector2(0, 220)
	counter_lbl.modulate = Color(1, 1, 1, 0)
	cv.add_child(counter_lbl)
	# Animate in
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cv, "modulate:a", 1.0, 0.22)
	tw.tween_property(cv, "scale", Vector2(1.0, 1.0), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(0.12)
	# Flash red tint + show COUNTERED text
	tw.tween_callback(func() -> void:
		counter_lbl.modulate = Color(1, 1, 1, 1)
	)
	tw.set_parallel(true)
	tw.tween_property(cv, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.15)
	tw.tween_property(counter_lbl, "scale", Vector2(1.2, 1.2), 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	# Shake
	var base_x := cv.position.x
	for i in 4:
		var offset_x := 12.0 if i % 2 == 0 else -12.0
		tw.tween_property(cv, "position:x", base_x + offset_x, 0.05)
	tw.tween_property(cv, "position:x", base_x, 0.05)
	# Hold briefly
	tw.tween_interval(0.5)
	# Fizzle out — shrink + fade
	tw.set_parallel(true)
	tw.tween_property(cv, "modulate:a", 0.0, 0.35)
	tw.tween_property(cv, "scale", Vector2(0.7, 0.7), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(cv.queue_free)

## Show or hide the counter-spell warning label based on current counter state.
func _update_counter_warning() -> void:
	counter_warning.update()

## Wrapper: apply spell damage to a minion + show flash and damage popup.
## info is optional — when omitted, defaults to (SPELL, NONE) per call-site convention.
func _spell_dmg(target: MinionInstance, damage: int, info: Dictionary = {}) -> void:
	var slot := _find_slot_for(target)
	var total := damage + _player_spell_damage_bonus
	if info.is_empty():
		info = CombatManager.make_damage_info(total, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE)
	else:
		info = info.duplicate()
		info["amount"] = total
	combat_manager.apply_damage_to_minion(target, info)
	_refresh_slot_for(target)
	if slot:
		_flash_slot(slot)
		_spawn_damage_popup(slot.get_global_rect().get_center(), damage)

## Flash a hero status panel and show a damage number.
## on_done (optional) is called after the flash animation completes.
## school is a DamageSchool int — VOID_BOLT (and any future VOID_BOLT sub-school) flashes purple.
func _flash_hero(target: String, amount: int, on_done: Callable = Callable(), school: int = Enums.DamageSchool.NONE, is_crit: bool = false) -> void:
	var panel := _player_status_panel if target == "player" else _enemy_status_panel
	if panel == null:
		if on_done.is_valid():
			on_done.call()
		return
	var flash_color: Color
	if Enums.has_school(school, Enums.DamageSchool.VOID_BOLT):
		flash_color = Color(1.2, 0.40, 1.8, 1.0)  # Purple flash for void bolt
	else:
		flash_color = Color(1.8, 0.30, 0.30, 1.0)  # Red flash for normal damage
	var tw := create_tween()
	tw.tween_property(panel, "modulate", flash_color, 0.06)
	tw.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.30)
	if on_done.is_valid():
		tw.tween_callback(on_done)
	var txt := "-%d!" % amount if is_crit else "-%d" % amount
	_spawn_popup(panel.get_global_rect().get_center(), txt, _dmg_color(school), is_crit)

func _flash_hero_heal(target: String, amount: int) -> void:
	var panel := _player_status_panel if target == "player" else _enemy_status_panel
	if panel == null:
		return
	var tw := create_tween()
	tw.tween_property(panel, "modulate", Color(0.30, 1.6, 0.40, 1.0), 0.06)
	tw.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.30)
	_spawn_popup(panel.get_global_rect().get_center(), "+%d" % amount, Color(0.30, 0.90, 0.40, 1.0))

func _dmg_color(school: int) -> Color:
	if Enums.has_school(school, Enums.DamageSchool.VOID_BOLT):
		return Color(0.75, 0.30, 1.0, 1.0)
	return Color(1.0, 0.22, 0.22, 1.0)

## Spawn a popup immediately. If another popup is near the same position,
## offset this one downward so they don't overlap.
func _spawn_popup(center: Vector2, text: String, color: Color, is_crit: bool = false) -> void:
	# Clean up expired entries
	var now := Time.get_ticks_msec() / 1000.0
	_recent_popups = _recent_popups.filter(func(e: Dictionary) -> bool:
		return now - (e.time as float) < 1.0)
	# Count how many recent popups are near this position
	var stack_count := 0
	for entry in _recent_popups:
		if (entry.center as Vector2).distance_to(center) < _POPUP_STACK_THRESHOLD:
			stack_count += 1
	_recent_popups.append({"center": center, "time": now})
	# Offset position downward for stacked popups
	var offset_center := center + Vector2(0, stack_count * _POPUP_STACK_OFFSET)
	_spawn_floating_popup(offset_center, text, color, is_crit)

func _spawn_floating_popup(screen_center: Vector2, text: String, color: Color, is_crit: bool = false) -> void:
	var lbl := Label.new()
	lbl.text = text
	var font_size: int = 44 if is_crit else 28
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_override("font", DAMAGE_FONT)
	if is_crit:
		lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		lbl.add_theme_constant_override("shadow_offset_x", 3)
		lbl.add_theme_constant_override("shadow_offset_y", 3)
	lbl.z_index = 200
	var popup_parent: Node = get_node_or_null("PopupLayer")
	if popup_parent == null:
		popup_parent = $UI
	popup_parent.add_child(lbl)
	# Pivot around text centre so pulse scales in-place.
	var text_size: Vector2 = lbl.get_minimum_size()
	lbl.size = text_size
	lbl.pivot_offset = text_size * 0.5
	lbl.position = screen_center - text_size * 0.5 + Vector2(randf_range(-12.0, 12.0), 0.0)
	if is_crit:
		# Crit: rise slower, linger longer, with a pulsing scale.
		var rise_end_y_c := maxf(lbl.position.y - 60.0, 16.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(lbl, "position:y", rise_end_y_c, 2.6) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(lbl, "modulate:a", 1.0, 0.4)
		# Single pop-in pulse for crit.
		var pop := create_tween()
		pop.tween_property(lbl, "scale", Vector2(1.5, 1.5), 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		# Hold + fade out (extra linger for crits).
		var fade := create_tween()
		fade.tween_interval(2.2)
		fade.tween_property(lbl, "modulate:a", 0.0, 0.9)
		fade.tween_callback(lbl.queue_free)
	else:
		var tw := create_tween()
		tw.set_parallel(true)
		var rise_end_y := maxf(lbl.position.y - 90.0, 16.0)
		tw.tween_property(lbl, "position:y", rise_end_y, 1.6) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(lbl, "modulate:a", 1.0, 0.9)
		tw.chain().tween_property(lbl, "modulate:a", 0.0, 0.7)
		tw.chain().tween_callback(lbl.queue_free)

## Minion damage popups.
func _spawn_damage_popup(screen_center: Vector2, damage: int, is_crit: bool = false) -> void:
	var txt := "-%d!" % damage if is_crit else "-%d" % damage
	_spawn_popup(screen_center, txt, Color(1.0, 0.22, 0.22, 1.0), is_crit)

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
		_play_hero_attack_anim(atk_slot, _player_status_panel, attacker)

# LogType / _log() are facades that delegate to CombatLog. Kept on the scene
# so the dozens of internal call sites and ~5 external callers (handlers,
# effects, relics, EnemyAI, CheatPanel) don't need to know about the move.
const _LogType := CombatLog.LogType

func _log(msg: String, type: int = CombatLog.LogType.PLAYER) -> void:
	combat_log.write(msg, type)

func _highlight_empty_player_slots() -> void:
	targeting.highlight_empty_player_slots()

func _highlight_valid_attack_targets() -> void:
	targeting.highlight_valid_attack_targets()

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
	# NOTE: on_player_minion_played_effect, on_enemy_minion_played_effect, on_void_archmagus_spell,
	# and on_summon_board_synergies are registered by CombatSetup.setup() (shared with sim).
	# Only register live-only handlers here to avoid double-registration.
	# NOTE: Old passive relic handlers (on_player_turn_relics, on_summon_relic) removed.
	# Relics are now activated abilities — see _setup_relics().
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
