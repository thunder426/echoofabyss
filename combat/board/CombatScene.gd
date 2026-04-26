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

# ---------------------------------------------------------------------------
# Pure data layer — fields below are forwarded to a shared CombatState so the
# headless simulator (SimState extends CombatState) and live combat operate on
# the same shape. See design/refactors/COMBAT_STATE_MANIFEST.md.
# ---------------------------------------------------------------------------
var state: CombatState = CombatState.new()

## Forwarded to state.turn_manager (untyped Object) so CombatState methods
## (e.g. _on_flesh_spent → Flesh Bond draw) hit the same instance live + sim.
var turn_manager: TurnManager:
	get: return state.turn_manager
	set(v): state.turn_manager = v
var enemy_ai: EnemyAI

## Most recent player resource-growth choice ("" | "essence" | "mana").
## Set by the end-turn buttons; read by F15 abyssal_mandate passive.
var last_player_growth: String:
	get: return state.last_player_growth
	set(v): state.last_player_growth = v

## F15 Abyss Sovereign phase marker (1 = P1, 2 = P2). Flips to 2 via
## PhaseTransition when P1 HP hits 0. Non-F15 fights leave this at 1.
var _sovereign_phase: int:
	get: return state._sovereign_phase
	set(v): state._sovereign_phase = v
## Turn number at which the P1→P2 transition fired. 0 = never transitioned.
var _sovereign_transition_turn: int:
	get: return state._sovereign_transition_turn
	set(v): state._sovereign_transition_turn = v

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
var player_slots: Array[BoardSlot]:
	get: return state.player_slots
	set(v): state.player_slots = v
var enemy_slots: Array[BoardSlot]:
	get: return state.enemy_slots
	set(v): state.enemy_slots = v

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

## Re-entrancy guard for _do_end_turn — set true while we're awaiting in-flight
## VFX and tearing down the turn. Prevents a second click from queuing another
## end_player_turn() while the first is still in progress.
var _end_turn_in_progress: bool = false

# Enemy hero status panel
var _enemy_hero_panel: EnemyHeroPanel = null
var _enemy_status_panel: Control = null   ## alias → _enemy_hero_panel (backward-compat)
var _enemy_panel_bg: Panel = null         ## alias → _enemy_hero_panel.highlight_panel
var enemy_hp_max: int:
	get: return state.enemy_hp_max
	set(v): state.enemy_hp_max = v

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

## Forwarded to state.combat_manager so CombatState methods can apply damage
## via the same instance. Initialized in _ready so state's getter returns the
## live instance throughout the scene's lifetime.
var combat_manager: CombatManager:
	get: return state.combat_manager
	set(v): state.combat_manager = v

## Central event dispatcher — populated by _setup_triggers() in _ready().
## Forwarded to state.trigger_manager so CombatState methods (rune handling
## etc.) can access the same instance without holding a scene reference.
var trigger_manager: TriggerManager:
	get: return state.trigger_manager
	set(v): state.trigger_manager = v
var _handlers: CombatHandlers
var _hardcoded: HardcodedEffects:
	get: return state._hardcoded
	set(v): state._hardcoded = v
var _relic_runtime: RelicRuntime
var _relic_effects: RelicEffects
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

## Relic state flags (set by relic effects, consumed by combat logic) — forwarded to state.
var _relic_hero_immune: bool:
	get: return state._relic_hero_immune
	set(v): state._relic_hero_immune = v
var _relic_cost_reduction: int:
	get: return state._relic_cost_reduction
	set(v): state._relic_cost_reduction = v
var _relic_extra_turn: bool:
	get: return state._relic_extra_turn
	set(v): state._relic_extra_turn = v

# Live boards
var player_board: Array[MinionInstance]:
	get: return state.player_board
	set(v): state.player_board = v
var enemy_board: Array[MinionInstance]:
	get: return state.enemy_board
	set(v): state.enemy_board = v

# Hero HP
var player_hp: int:
	get: return state.player_hp
	set(v): state.player_hp = v
var enemy_hp: int:
	get: return state.enemy_hp
	set(v): state.enemy_hp = v

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

# Active global environment — forwarded to state.active_environment.
var active_environment: EnvironmentCardData:
	get: return state.active_environment
	set(v): state.active_environment = v

# Active traps and runes (shared pool, max 3 slots) — forwarded to state.active_traps.
var active_traps: Array[TrapCardData]:
	get: return state.active_traps
	set(v): state.active_traps = v
# Callables registered for the current environment's 2-rune rituals.
# Cleared and re-populated whenever the active environment changes.
var _env_ritual_handlers: Array[Callable]:
	get: return state._env_ritual_handlers
	set(v): state._env_ritual_handlers = v
# TriggerManager Callables registered per rune placement.
# Stored as an Array of {rune_id, entries} so two runes of the same type each
# get an independent entry and can be individually unregistered.
var _rune_aura_handlers: Array:
	get: return state._rune_aura_handlers
	set(v): state._rune_aura_handlers = v

# ---------------------------------------------------------------------------
# Relic state — reset each combat
# ---------------------------------------------------------------------------

## True until the first card is played this turn (Void Crystal: first card free)
## (Removed: relic_first_card_free — old passive relic system replaced by activated relics)

# ---------------------------------------------------------------------------
# Talent state — reset each combat
# ---------------------------------------------------------------------------

## Void Mark stacks on the enemy hero (accumulate through the run)
var enemy_void_marks: int:
	get: return state.enemy_void_marks
	set(v): state.enemy_void_marks = v

## Seris — active spell damage bonus from void_amplification, set at the start of a
## player spell cast (sum of Corruption stacks across friendly Demons * 50) and
## cleared after resolution. `_spell_dmg` adds it to every spell-damage target hit.
var _player_spell_damage_bonus: int:
	get: return state._player_spell_damage_bonus
	set(v): state._player_spell_damage_bonus = v

## Seris — Corrupt Flesh activated ability. `_seris_corrupt_targeting` is true while
## the player is picking a friendly Demon to corrupt; `_seris_corrupt_used_this_turn`
## enforces the 1-per-turn cap. Reset to false on each ON_PLAYER_TURN_START.
var _seris_corrupt_targeting: bool = false
var _seris_corrupt_used_this_turn: bool:
	get: return state._seris_corrupt_used_this_turn
	set(v): state._seris_corrupt_used_this_turn = v

## Seris — Flesh counter. Gains 1 per friendly Demon death (Fleshbind passive), capped at player_flesh_max.
## Resets each combat (CombatScene is re-instantiated). Spent by Seris talent effects.
var player_flesh: int:
	get: return state.player_flesh
	set(v): state.player_flesh = v
var player_flesh_max: int:
	get: return state.player_flesh_max
	set(v): state.player_flesh_max = v

## Seris — Fiendish Pact pending Mana discount. Set by the Fiendish Pact spell,
## consumed when the next Demon is played (capped at that card's mana_cost).
## Cleared at player turn start along with cost_delta.
var _fiendish_pact_pending: int:
	get: return state._fiendish_pact_pending
	set(v): state._fiendish_pact_pending = v

## Seris — Forge Counter (Demon Forge branch). Incremented when a Demon is sacrificed; at threshold
## the Soul Forge talent auto-summons a Forged Demon and resets the counter.
## Threshold is set by CombatSetup from the talent registry (forge_momentum reduces it from 3 to 2).
var forge_counter: int:
	get: return state.forge_counter
	set(v): state.forge_counter = v
var forge_counter_threshold: int:
	get: return state.forge_counter_threshold
	set(v): state.forge_counter_threshold = v

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

## Passive-configurable stats — forwarded to state (set by CombatSetup from registry).
var void_mark_damage_per_stack: int:
	get: return state.void_mark_damage_per_stack
	set(v): state.void_mark_damage_per_stack = v
var rune_aura_multiplier: int:
	get: return state.rune_aura_multiplier
	set(v): state.rune_aura_multiplier = v

## Set to true the moment victory/defeat is triggered — prevents re-entrant damage/scene calls
var _combat_ended: bool:
	get: return state._combat_ended
	set(v): state._combat_ended = v

## Cost penalties / once-per-turn / spell counter flags — all forwarded to state.
var _spell_tax_for_enemy_turn: int:
	get: return state._spell_tax_for_enemy_turn
	set(v): state._spell_tax_for_enemy_turn = v
var _spell_tax_for_player_turn: int:
	get: return state._spell_tax_for_player_turn
	set(v): state._spell_tax_for_player_turn = v
var _void_mana_drain_pending: bool:
	get: return state._void_mana_drain_pending
	set(v): state._void_mana_drain_pending = v
var player_spell_cost_penalty: int:
	get: return state.player_spell_cost_penalty
	set(v): state.player_spell_cost_penalty = v
var _spell_cancelled: bool:
	get: return state._spell_cancelled
	set(v): state._spell_cancelled = v
var _enemy_traps_blocked: bool:
	get: return state._enemy_traps_blocked
	set(v): state._enemy_traps_blocked = v
var _player_traps_blocked: bool:
	get: return state._player_traps_blocked
	set(v): state._player_traps_blocked = v
var _player_spell_counter: int:
	get: return state._player_spell_counter
	set(v): state._player_spell_counter = v
var _enemy_spell_counter: int:
	get: return state._enemy_spell_counter
	set(v): state._enemy_spell_counter = v

## Persistent warning label shown when the player's next spell will be countered.
# _counter_warning_label moved into CounterWarning.gd (counter_warning.label)

## Transient prompt label shown during on-play target selection (required or
## optional). Text comes from MinionCardData.on_play_target_prompt. Shared
## across all targeted-play cards.
# _target_prompt_label moved into Targeting.gd (targeting.prompt_label)

## Prevents Soul Rune from firing more than once per enemy turn.
var _soul_rune_fires_this_turn: int:
	get: return state._soul_rune_fires_this_turn
	set(v): state._soul_rune_fires_this_turn = v

## Void Imps summoned by Imp Overload that must die at end of the player's turn.
var _temp_imps: Array[MinionInstance]:
	get: return state._temp_imps
	set(v): state._temp_imps = v

## True once Imp Evolution has added a Senior Void Imp this turn; reset on turn start.
var imp_evolution_used_this_turn: bool:
	get: return state.imp_evolution_used_this_turn
	set(v): state.imp_evolution_used_this_turn = v

## Currently hovered hand card visual — used for pip-blink cost preview.
var _hovered_hand_visual: CardVisual = null

# ---------------------------------------------------------------------------
# Enemy passive state — populated from GameManager.current_enemy.passives
# ---------------------------------------------------------------------------

## Active passive IDs for the current encounter — forwarded to state.
var _active_enemy_passives: Array[String]:
	get: return state._active_enemy_passives
	set(v): state._active_enemy_passives = v

## Act 4 passive / crit / Dark Channeling state — all forwarded to state.
var _vp_pre_crit_stacks: int:
	get: return state._vp_pre_crit_stacks
	set(v): state._vp_pre_crit_stacks = v
var _spirit_conscription_fired: bool:
	get: return state._spirit_conscription_fired
	set(v): state._spirit_conscription_fired = v
var crit_multiplier: float:
	get: return state.crit_multiplier
	set(v): state.crit_multiplier = v
var enemy_crit_multiplier: float:
	get: return state.enemy_crit_multiplier
	set(v): state.enemy_crit_multiplier = v
var _enemy_crits_consumed: int:
	get: return state._enemy_crits_consumed
	set(v): state._enemy_crits_consumed = v
var _player_crits_consumed: int:
	get: return state._player_crits_consumed
	set(v): state._player_crits_consumed = v
var _last_crit_attacker: MinionInstance:
	get: return state._last_crit_attacker
	set(v): state._last_crit_attacker = v
var _last_attack_was_crit: bool:
	get: return state._last_attack_was_crit
	set(v): state._last_attack_was_crit = v
var _last_attacker: MinionInstance:
	get: return state._last_attacker
	set(v): state._last_attacker = v
var _dark_channeling_active: bool:
	get: return state._dark_channeling_active
	set(v): state._dark_channeling_active = v
var _dark_channeling_multiplier: float:
	get: return state._dark_channeling_multiplier
	set(v): state._dark_channeling_multiplier = v
var _dark_channeling_amp_count: int:
	get: return state._dark_channeling_amp_count
	set(v): state._dark_channeling_amp_count = v
var _dark_channeling_amp_by_spell: Dictionary:
	get: return state._dark_channeling_amp_by_spell
	set(v): state._dark_channeling_amp_by_spell = v
var _dark_channeling_dmg_by_spell: Dictionary:
	get: return state._dark_channeling_dmg_by_spell
	set(v): state._dark_channeling_dmg_by_spell = v

## Enemy champion state — all forwarded to state. CombatSetup mutates via
## scene.set("_champion_X", val) which routes through the property setter.
var _champion_summon_count: int:
	get: return state._champion_summon_count
	set(v): state._champion_summon_count = v
var _corruption_detonation_times: int:
	get: return state._corruption_detonation_times
	set(v): state._corruption_detonation_times = v
var _ritual_invoke_times: int:
	get: return state._ritual_invoke_times
	set(v): state._ritual_invoke_times = v
var _handler_spark_buff_times: int:
	get: return state._handler_spark_buff_times
	set(v): state._handler_spark_buff_times = v
var _smoke_veil_fires: int:
	get: return state._smoke_veil_fires
	set(v): state._smoke_veil_fires = v
var _smoke_veil_damage_prevented: int:
	get: return state._smoke_veil_damage_prevented
	set(v): state._smoke_veil_damage_prevented = v
var _abyssal_plague_fires: int:
	get: return state._abyssal_plague_fires
	set(v): state._abyssal_plague_fires = v
var _abyssal_plague_kills: int:
	get: return state._abyssal_plague_kills
	set(v): state._abyssal_plague_kills = v
var _champion_rip_attack_ids: Array:
	get: return state._champion_rip_attack_ids
	set(v): state._champion_rip_attack_ids = v
var _champion_rip_summoned: bool:
	get: return state._champion_rip_summoned
	set(v): state._champion_rip_summoned = v
var _champion_cb_death_count: int:
	get: return state._champion_cb_death_count
	set(v): state._champion_cb_death_count = v
var _champion_cb_summoned: bool:
	get: return state._champion_cb_summoned
	set(v): state._champion_cb_summoned = v
var _champion_im_frenzy_count: int:
	get: return state._champion_im_frenzy_count
	set(v): state._champion_im_frenzy_count = v
var _champion_im_summoned: bool:
	get: return state._champion_im_summoned
	set(v): state._champion_im_summoned = v
# Act 2 champion state
var _champion_acp_stacks_consumed: int:
	get: return state._champion_acp_stacks_consumed
	set(v): state._champion_acp_stacks_consumed = v
var _champion_acp_summoned: bool:
	get: return state._champion_acp_summoned
	set(v): state._champion_acp_summoned = v
var _champion_vr_summoned: bool:
	get: return state._champion_vr_summoned
	set(v): state._champion_vr_summoned = v
var _champion_ch_spark_count: int:
	get: return state._champion_ch_spark_count
	set(v): state._champion_ch_spark_count = v
var _champion_ch_summoned: bool:
	get: return state._champion_ch_summoned
	set(v): state._champion_ch_summoned = v
var _champion_ch_aura_dmg: int:
	get: return state._champion_ch_aura_dmg
	set(v): state._champion_ch_aura_dmg = v
## Act 3 champion: Rift Stalker
var _champion_rs_spark_dmg: int:
	get: return state._champion_rs_spark_dmg
	set(v): state._champion_rs_spark_dmg = v
var _champion_rs_summoned: bool:
	get: return state._champion_rs_summoned
	set(v): state._champion_rs_summoned = v
## Act 3 champion: Void Aberration
var _champion_va_sparks_consumed: int:
	get: return state._champion_va_sparks_consumed
	set(v): state._champion_va_sparks_consumed = v
var _champion_va_summoned: bool:
	get: return state._champion_va_summoned
	set(v): state._champion_va_summoned = v
## Act 4 champion: Void Scout
var _champion_vs_crits_consumed: int:
	get: return state._champion_vs_crits_consumed
	set(v): state._champion_vs_crits_consumed = v
var _champion_vs_summoned: bool:
	get: return state._champion_vs_summoned
	set(v): state._champion_vs_summoned = v
## Act 4 champion: Void Warband
var _champion_vw_spirits_consumed: int:
	get: return state._champion_vw_spirits_consumed
	set(v): state._champion_vw_spirits_consumed = v
var _champion_vw_summoned: bool:
	get: return state._champion_vw_summoned
	set(v): state._champion_vw_summoned = v
var _vw_behemoth_plays: int:
	get: return state._vw_behemoth_plays
	set(v): state._vw_behemoth_plays = v
var _vw_bastion_plays: int:
	get: return state._vw_bastion_plays
	set(v): state._vw_bastion_plays = v
var _void_echo_fired_this_turn: bool:
	get: return state._void_echo_fired_this_turn
	set(v): state._void_echo_fired_this_turn = v
var _vw_death_crit_grants: int:
	get: return state._vw_death_crit_grants
	set(v): state._vw_death_crit_grants = v
var _vw_behemoth_lost: Dictionary:
	get: return state._vw_behemoth_lost
	set(v): state._vw_behemoth_lost = v
var _vw_bastion_lost: Dictionary:
	get: return state._vw_bastion_lost
	set(v): state._vw_bastion_lost = v
## Act 4 champion: Void Captain
var _champion_vc_tc_cast: int:
	get: return state._champion_vc_tc_cast
	set(v): state._champion_vc_tc_cast = v
var _champion_vc_summoned: bool:
	get: return state._champion_vc_summoned
	set(v): state._champion_vc_summoned = v
## Act 4 champion: Void Champion (F14)
var _champion_vch_crit_kills: int:
	get: return state._champion_vch_crit_kills
	set(v): state._champion_vch_crit_kills = v
var _champion_vch_summoned: bool:
	get: return state._champion_vch_summoned
	set(v): state._champion_vch_summoned = v
## Act 3 champion: Void Herald
var _champion_vh_spark_cards_played: int:
	get: return state._champion_vh_spark_cards_played
	set(v): state._champion_vh_spark_cards_played = v
var _champion_vh_summoned: bool:
	get: return state._champion_vh_summoned
	set(v): state._champion_vh_summoned = v

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	combat_manager = CombatManager.new()
	trigger_manager = TriggerManager.new()
	_hardcoded = HardcodedEffects.new()
	_hardcoded.setup(self)
	# Register VFX-rich _summon_token so EffectResolver SUMMON steps fired
	# through state-created EffectContexts route into scene (sigils, champion
	# entrance, etc.). Sim leaves this unset → state's pure logic path runs.
	state._summon_delegate = _summon_token
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
	# Connect state signal subscribers BEFORE the initial display refresh calls
	# below — those calls emit traps_changed / environment_changed and would be
	# lost otherwise. Subscribers null-check the UI nodes they touch (hero
	# panels, pip bar) so connecting before those exist is safe.
	state.hp_changed.connect(_on_state_hp_changed)
	state.void_marks_changed.connect(_on_state_void_marks_changed)
	state.spell_damage_dealt.connect(_on_state_spell_damage_dealt)
	state.combat_log.connect(_on_state_combat_log)
	state.minion_stats_changed.connect(_on_state_minion_stats_changed)
	state.flesh_changed.connect(_on_state_flesh_changed)
	state.forge_changed.connect(_on_state_forge_changed)
	state.traps_changed.connect(_on_state_traps_changed)
	state.environment_changed.connect(_on_state_environment_changed)
	_update_environment_display()
	_update_trap_display()
	_update_enemy_trap_display()
	# If no run is active (e.g. launched directly for testing), start one now
	if not GameManager.run_active:
		GameManager.start_new_run()

	# HP resets to full at the start of every new combat.
	state.player_hp_max = GameManager.player_hp_max
	player_hp = GameManager.player_hp_max
	# Mirror GameManager talents into state so _has_talent reads from a single
	# source. Live combat is the writer; sim sets state.talents directly via
	# CombatSim before turning the engine on. (Hero passives are loaded later
	# in CombatSetup which already populates state.hero_passives if needed.)
	state.talents.assign(GameManager.unlocked_talents)
	state.player_hero_id = GameManager.current_hero

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
	# Initial panel sync — the hp_changed signal already fired above (in
	# `player_hp = GameManager.player_hp_max`) but the panels didn't exist yet,
	# so push the values manually now. Future HP changes route through the
	# signal subscriber.
	_player_hero_panel.update(player_hp, GameManager.player_hp_max)
	_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)
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
	var env_slot := trap_env_display.env_slot
	if env_slot:
		env_slot.mouse_entered.connect(func() -> void:
			if active_environment:
				_show_large_preview(active_environment))
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

## Resource pip / label refresh delegated to combat_ui.
func _on_resources_changed(essence: int, essence_max: int, mana: int, mana_max: int) -> void:
	if combat_ui != null:
		combat_ui.on_resources_changed(essence, essence_max, mana, mana_max)

func _refresh_end_turn_mode() -> void:
	if combat_ui != null:
		combat_ui.refresh_end_turn_mode()

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
	if not turn_manager.is_player_turn:
		return
	_end_turn_in_progress = true
	# Apply resource growth immediately — the player picked it, the pip should
	# reflect that choice while spell VFX completes.
	if growth == "essence":
		turn_manager.grow_essence_max()
		last_player_growth = "essence"
	elif growth == "mana":
		turn_manager.grow_mana_max()
		last_player_growth = "mana"
	# Drain any in-flight on-play VFX or death animations before relinquishing
	# the turn. Spell VFX no longer gates here — P4B mutates state before the
	# spell's projectile flight, so kills land regardless of when end-turn
	# fires. Loop because resolving one VFX can start the next.
	while _on_play_vfx_active or _active_death_anims > 0:
		if _on_play_vfx_active:
			await on_play_vfx_done
		if _active_death_anims > 0:
			await death_anims_done
	# Combat may have ended while we were awaiting (lethal spell on enemy hero).
	if _combat_ended:
		_end_turn_in_progress = false
		return
	if not turn_manager.is_player_turn:
		_end_turn_in_progress = false
		return
	selected_attacker = null
	pending_play_card = null
	pending_minion_target = null
	_awaiting_minion_target = false
	if hand_display:
		hand_display.deselect_current()
	turn_manager.end_player_turn()
	_end_turn_in_progress = false

# ---------------------------------------------------------------------------
# Hand card selection
# ---------------------------------------------------------------------------

## Hand-card chain delegated to input_handler. Scene wrappers preserve the
## external API (signal connections in _connect_ui still target these methods).
func _on_hand_card_selected(inst: CardInstance) -> void:
	if input_handler != null:
		input_handler.on_hand_card_selected(inst)

func _cancel_card_select() -> void:
	if input_handler != null:
		input_handler.cancel_card_select()

func _on_hand_card_hovered(card_data: CardData, visual: CardVisual) -> void:
	if input_handler != null:
		input_handler.on_hand_card_hovered(card_data, visual)

func _on_hand_card_unhovered() -> void:
	if input_handler != null:
		input_handler.on_hand_card_unhovered()

func _start_pip_blink_for_card(card_data: CardData) -> void:
	if input_handler != null:
		input_handler.start_pip_blink_for_card(card_data)

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
	# P4B: invert resolve-at-impact for AoE / untargeted spells. Freeze every
	# enemy minion slot so the wave can play over still-visible minions before
	# their death animations fire. State mutates immediately; popups capture
	# and drain at vfx.impact_hit (or, for plague-style VFX that ignores
	# resolve_damage, at the safety drain after VfxController returns). After
	# VFX finishes, unfreeze slots + flush deferred deaths so kills animate.
	_show_card_cast_anim(spell, false, func() -> void:
		var frozen_slots: Array[BoardSlot] = []
		for s in enemy_slots:
			if s.minion != null:
				s.freeze_visuals = true
				frozen_slots.append(s)
		_capturing_spell_popups = true
		state.cast_player_targeted_spell(spell, null)
		var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
		spell_ctx.card = spell
		trigger_manager.fire(spell_ctx)
		_capturing_spell_popups = false
		var on_impact := func(_i: int) -> void: _drain_pending_spell_popups()
		await vfx_controller.play_spell(spell.id, "player", null, on_impact)
		_drain_pending_spell_popups()
		# Unfreeze any slots we froze; refresh + flush so death animations play.
		for s in frozen_slots:
			if is_instance_valid(s):
				s.freeze_visuals = false
				s._refresh_visuals()
		_flush_deferred_deaths()
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
	state._update_environment_display()

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
	state.minion_summoned.emit("player", instance, slot.index)
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
		state.minion_summoned.emit("player", instance, slot.index)
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
var _spell_cast_depth: int:
	get: return state._spell_cast_depth
	set(v): state._spell_cast_depth = v

## Delegated to CombatState — sets _player_spell_damage_bonus from
## void_amplification at the outermost cast level only.
func _pre_player_spell_cast(spell: SpellCardData) -> void:
	state._pre_player_spell_cast(spell)

## Delegated to CombatState — handles Void Resonance recast at outermost cast level.
func _post_player_spell_cast(spell: SpellCardData, target: MinionInstance) -> void:
	state._post_player_spell_cast(spell, target)

## Reentrancy guard so the recast doesn't itself trigger another recast.
var _double_cast_in_progress: bool:
	get: return state._double_cast_in_progress
	set(v): state._double_cast_in_progress = v

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

## Champion entrance VFX (banner reveal, screen shake, gold flash) live on
## vfx_bridge — see CombatVFXBridge.champion_summon_sequence and friends.

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

## Apply one Corruption stack to a minion. State handles BuffSystem + log + slot
## refresh; scene wrapper adds the VFX + slot blink (UI-only).
func _corrupt_minion(minion: MinionInstance) -> void:
	state._corrupt_minion(minion)
	var slot: BoardSlot = _find_slot_for(minion)
	if slot != null:
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

func _play_corruption_detonations(targets: Array, on_impact: Callable) -> void:
	if vfx_bridge != null:
		vfx_bridge.play_corruption_detonations(targets, on_impact)

func _play_feral_reinforcement_vfx(source: MinionInstance, imp_card: CardData) -> void:
	if vfx_bridge != null:
		await vfx_bridge.play_feral_reinforcement_vfx(source, imp_card)

## Return a random living enemy minion, or null if the board is empty.
func _find_random_enemy_minion() -> MinionInstance:
	return _find_random_minion(enemy_board)

## Return a random Corrupted enemy minion, or null if none exist.
func _find_random_corrupted_enemy() -> MinionInstance:
	return _find_random_corrupted_minion(enemy_board)

# ---------------------------------------------------------------------------
# Owner-aware board helpers
# ---------------------------------------------------------------------------

## Owner-aware board helpers — delegate to CombatState (pure data).
func _friendly_board(owner: String) -> Array[MinionInstance]:
	return state._friendly_board(owner)

func _opponent_board(owner: String) -> Array[MinionInstance]:
	return state._opponent_board(owner)

func _opponent_of(owner: String) -> String:
	return state._opponent_of(owner)

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

## Seris Starter — Fiendish Pact discount peek. Delegated to CombatState.
func _peek_fiendish_pact_discount(mc: MinionCardData) -> int:
	return state._peek_fiendish_pact_discount(mc)

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
	return state._friendly_slots(owner)

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
			state.minion_summoned.emit(owner, instance, slot.index)
			# Champion tokens get a dramatic entrance (fire-and-forget — places minion on slot after animation)
			if data.is_champion and vfx_bridge != null:
				vfx_bridge.champion_summon_sequence(data, instance, slot)
			else:
				# Void Spark tokens get the spark summon sigil VFX (covers
				# brood_imp on-death, soul_rune, and other spark sources).
				# Reserve the slot synchronously (so back-to-back SUMMONs land
				# in distinct slots) then reveal the minion after the sigil.
				if card_id == "void_spark" and vfx_bridge != null:
					vfx_bridge.summon_spark_with_sigil(instance, data, slot, owner)
					return
				# Void Demon tokens (Void Spawning, Fleshcraft Ritual) get the
				# purple ARCANE sigil + inward spark burst on reveal.
				if card_id == "void_demon" and vfx_bridge != null:
					vfx_bridge.summon_demon_with_sigil(instance, data, slot, owner)
					return
				# Brood Imp tokens (Matriarch's Broodling on-death) get the
				# dark-green BROOD_DARK sigil + green/black inward spark burst.
				if card_id == "brood_imp" and vfx_bridge != null:
					vfx_bridge.summon_brood_imp_with_sigil(instance, data, slot, owner)
					return
				slot.place_minion(instance)
				_log("  %s summoned!" % data.card_name, _LogType.PLAYER)
				var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
				var ctx   := EventContext.make(event, owner)
				ctx.minion = instance
				ctx.card   = data
				trigger_manager.fire(ctx)
			return

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
	if input_handler != null:
		input_handler.on_relic_hovered(effect_id)

func _on_relic_unhovered() -> void:
	if input_handler != null:
		input_handler.on_relic_unhovered()

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
	if input_handler != null:
		input_handler.on_relic_target_hero_input(event)

func _input(event: InputEvent) -> void:
	if input_handler != null:
		input_handler.handle_input(event)

## Delegated to CombatState — entry point for EffectResolver HARDCODED steps.
func _resolve_hardcoded(id: String, ctx: EffectContext) -> void:
	state._resolve_hardcoded(id, ctx)

## Legacy shim for spells that still use effect_id instead of effect_steps.
func _resolve_spell_effect(effect_id: String, target: MinionInstance, owner: String = "player") -> void:
	state._resolve_spell_effect(effect_id, target, owner)

## Summon a 100/100 Void Spark into the first empty player slot.
func _summon_void_spark() -> void:
	_summon_token("void_spark", "player")

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

## Pure logic — delegated to CombatState.
func _find_last_non_echo_rune() -> TrapCardData:
	return state._find_last_non_echo_rune()

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
	return state._minion_has_tag(m, tag)

func _card_has_tag(card: CardData, tag: String) -> bool:
	return state._card_has_tag(card, tag)

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
			state.minion_summoned.emit("player", instance, slot.index)
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
	return state._has_talent(id)

## Refresh hand card cost displays / playability glows / preview overlay.
## Delegated to combat_ui.
func _refresh_hand_spell_costs() -> void:
	if combat_ui != null:
		combat_ui.refresh_hand_spell_costs()

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

## Delegated to CombatState — Void Bolt damage per Void Mark stack.
func _void_mark_damage_per_stack() -> int:
	return state._void_mark_damage_per_stack()

## Add Void Mark stacks to the enemy hero.
## Apply Void Mark stacks. State handles HP-marker mutation + log; scene
## wrapper adds the VFX (UI-only).
func _apply_void_mark(stacks: int = 1) -> void:
	state._apply_void_mark(stacks)
	if _enemy_status_panel and is_instance_valid(_enemy_status_panel):
		var vfx := VoidMarkApplyVFX.create(_enemy_status_panel)
		vfx_controller.spawn(vfx)

# Flesh / Forge facades — delegate to CombatState primitives. The state
# setters emit flesh_changed / forge_changed which refresh Seris's resource
# bar via the _on_state_*_changed subscribers. Wrappers preserved for
# external callers (handlers, EffectResolver).
func _gain_flesh(amount: int = 1) -> void:
	state._gain_flesh(amount)

func _spend_flesh(amount: int) -> bool:
	return state._spend_flesh(amount)

func _on_flesh_spent(amount: int) -> void:
	state._on_flesh_spent(amount)

func _forge_counter_tick(amount: int = 1) -> bool:
	return forge.tick(amount)

func _forge_counter_reset() -> void:
	forge.reset()

func _gain_forge_counter(amount: int = 1) -> bool:
	return forge.gain(amount)

## Seris — fires for every friendly Demon SACRIFICE emit (not combat deaths).
## Handles Forge Counter ticks, Fiend Offering, and the auto Forged Demon summon.
## Silently no-ops for non-Seris runs (no soul_forge talent).
##
## Board-full rule: if an auto-summon would land but no slot is free, Flesh/
## counter costs are still paid — the summon just fails silently. This matches
## the user-facing "reduce flesh as well" decision so over-boarding isn't free.
## Delegated to CombatState — Fiend Offering + Soul Forge counter tick.
func _on_demon_sacrificed(minion: MinionInstance, source_tag: String) -> void:
	state._on_demon_sacrificed(minion, source_tag)

## Delegated to CombatState — summons Forged Demon and applies Abyssal Forge auras.
func _summon_forged_demon() -> void:
	state._summon_forged_demon()

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
## Pure logic delegated to CombatState; scene clears the targeting flag.
func _seris_corrupt_apply_target(minion: MinionInstance) -> void:
	_seris_corrupt_targeting = false
	if minion != null and (minion.card_data as MinionCardData).minion_type != Enums.MinionType.DEMON:
		_log("  Corrupt Flesh: target must be a friendly Demon.", _LogType.PLAYER)
		return
	state._seris_corrupt_apply(minion)

## Reset the 1/turn limit. Registered via CombatSetup for ON_PLAYER_TURN_START.
func _seris_corrupt_reset_turn() -> void:
	state._seris_corrupt_reset_turn()

## Delegated to CombatState — Soul Forge activated ability (button handler in
## SerisResourceBar). Returns ignored by callers; state version returns bool.
func _soul_forge_activate() -> void:
	state._soul_forge_activate()

## Pre-death hook — delegated to CombatState (Seris's deathless_flesh talent).
func _try_save_from_death(minion: MinionInstance) -> bool:
	return state._try_save_from_death(minion)

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

## Pure logic — delegated to CombatState (logs + refresh via signals).
func _heal_minion(minion: MinionInstance, amount: int) -> void:
	state._heal_minion(minion, amount)

func _heal_minion_full(minion: MinionInstance) -> void:
	state._heal_minion_full(minion)

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
## Delegated to CombatState — runs ON LEAVE / corruption-removed / sacrifice
## triggers, removes from board, clears slot.minion (skipping frozen slots),
## logs DEATH. Scene captures dead_slot beforehand to queue the death animation
## after state mutates.
func _sacrifice_minion(minion: MinionInstance) -> void:
	if minion == null:
		return
	var dead_slot: BoardSlot = null
	var search_slots := player_slots if minion.owner == "player" else enemy_slots
	for s in search_slots:
		if s.minion == minion:
			dead_slot = s
			break
	state._sacrifice_minion(minion)
	if hand_display:
		hand_display.refresh_condition_glows(self, turn_manager.essence, turn_manager.mana)
	_refresh_hand_spell_costs()
	if dead_slot:
		if dead_slot.freeze_visuals:
			_deferred_death_slots.append({slot = dead_slot, pos = dead_slot.global_position, minion = minion})
		else:
			_animate_minion_death(dead_slot, dead_slot.global_position, minion)

## Pure logic — delegated to CombatState. Logs + slot refresh via signals.
func _add_kill_stacks(minion: MinionInstance, count: int = 1) -> void:
	state._add_kill_stacks(minion, count)

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
## Live-combat wrapper around CombatState._deal_void_bolt_damage — fires the
## projectile VFX and awaits impact before delegating to state for the
## (logging, dmg_log split, hero damage application) logic. Sim path skips
## the projectile entirely; state-internal logic is the source of truth.
func _deal_void_bolt_damage(base_damage: int, source_minion: MinionInstance = null, from_rune: bool = false, is_minion_emitted: bool = false) -> void:
	var bolt := _fire_void_bolt_projectile(source_minion, from_rune)
	if bolt != null and is_inside_tree():
		await bolt.impact_hit
	state._deal_void_bolt_damage(base_damage, source_minion, from_rune, is_minion_emitted)

## Delegated to vfx_bridge — fires the player's void bolt projectile.
func _fire_void_bolt_projectile(source_minion: MinionInstance = null, from_rune: bool = false) -> VoidBoltProjectile:
	if vfx_bridge == null:
		return null
	return vfx_bridge.fire_void_bolt_projectile(source_minion, from_rune)

## Enemy-cast Void Bolt — fires a projectile from the enemy minion's slot (or
## enemy hero area) to the player hero panel, then applies damage on impact.
## Does not participate in Void Marks (those only apply to the enemy hero).
## is_minion_emitted: see _deal_void_bolt_damage. Default false (SPELL source).
## Live-combat wrapper — fires enemy projectile VFX, awaits impact, delegates
## to state for log + damage application.
func _deal_enemy_void_bolt_damage(base_damage: int, source_minion: MinionInstance = null, is_minion_emitted: bool = false) -> void:
	var bolt := _fire_enemy_void_bolt_projectile(source_minion)
	if bolt != null and is_inside_tree():
		await bolt.impact_hit
	state._deal_enemy_void_bolt_damage(base_damage, source_minion, is_minion_emitted)

## Delegated to vfx_bridge — fires the enemy's void bolt projectile.
func _fire_enemy_void_bolt_projectile(source_minion: MinionInstance = null) -> VoidBoltProjectile:
	if vfx_bridge == null:
		return null
	return vfx_bridge.fire_enemy_void_bolt_projectile(source_minion)

## Cycles through void rune slots so multiple runes alternate firing.
var _void_rune_fire_index: int:
	get: return state._void_rune_fire_index
	set(v): state._void_rune_fire_index = v

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
	var dead_slot_index: int = -1
	for i in search_slots.size():
		if search_slots[i].minion == minion:
			dead_slot = search_slots[i]
			dead_slot_index = i
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
	# Re-emit through state so logic listeners (sim profiles, future relic
	# handlers) have a single chokepoint that doesn't depend on CombatManager.
	state.minion_died.emit(minion.owner, minion, dead_slot_index)
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

## Subscriber to CombatState.hp_changed — refreshes the appropriate hero panel
## whenever HP mutates. Lets us drop scattered `_hero_panel.update(...)` calls
## sprinkled through damage/heal paths; the signal does it for free.
## Note: enemy_void_marks and enemy_ai aren't HP-related, so the existing
## _enemy_hero_panel.update(...) calls on those paths still need to stay until
## void_marks_changed has its own signal.
## State-signal subscribers delegated to combat_ui. Scene's wrappers preserve
## the signal-connection target so the wiring in _connect_ui doesn't change.
func _on_state_hp_changed(side: String, new_hp: int, mx: int, delta: int) -> void:
	if combat_ui != null:
		combat_ui.on_state_hp_changed(side, new_hp, mx, delta)

func _on_state_void_marks_changed(side: String, value: int) -> void:
	if combat_ui != null:
		combat_ui.on_state_void_marks_changed(side, value)

func _on_state_combat_log(msg: String, log_type: int) -> void:
	if combat_ui != null:
		combat_ui.on_state_combat_log(msg, log_type)

func _on_state_flesh_changed(value: int, max_value: int) -> void:
	if combat_ui != null:
		combat_ui.on_state_flesh_changed(value, max_value)

func _on_state_forge_changed(value: int, threshold: int) -> void:
	if combat_ui != null:
		combat_ui.on_state_forge_changed(value, threshold)

func _on_state_traps_changed(side: String) -> void:
	if combat_ui != null:
		combat_ui.on_state_traps_changed(side)

func _on_state_environment_changed(env: EnvironmentCardData) -> void:
	if combat_ui != null:
		combat_ui.on_state_environment_changed(env)

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
		player_hp -= amount  # hp_changed signal updates _player_hero_panel
		state.damage_dealt.emit(str(info.get("source_card", "")), "player", amount, school, is_crit)
		_log("  You take %d damage  (HP: %d)" % [amount, player_hp], _LogType.DAMAGE)
		# Fire ON_HERO_DAMAGED for every landed hit, including lethal — handlers
		# can react to the killing blow (telemetry, future "save from death" cards).
		var _pctx := EventContext.make(Enums.TriggerEvent.ON_HERO_DAMAGED, "player")
		_pctx.damage = amount
		_pctx.damage_info = info
		trigger_manager.fire(_pctx)
		if player_hp <= 0:
			# Lethal — flash immediately so the defeat flow runs without delay.
			_flash_hero("player", amount, _on_defeat, school, is_crit)
		elif _capturing_spell_popups:
			_pending_hero_popups.append({kind = "damage", target = "player", amount = amount, school = school, is_crit = is_crit})
		else:
			_flash_hero("player", amount, Callable(), school, is_crit)
	else:
		enemy_hp -= amount  # hp_changed signal updates _enemy_hero_panel
		state.damage_dealt.emit(str(info.get("source_card", "")), "enemy", amount, school, is_crit)
		_log("  Enemy takes %d damage  (HP: %d)" % [amount, enemy_hp], _LogType.DAMAGE)
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
			# Lethal — flash immediately (skip queue) so the transition /
			# victory flow doesn't get visually disjointed from the kill.
			var pt = preload("res://combat/board/PhaseTransition.gd")
			if pt.attempt(self):
				_flash_hero("enemy", amount, Callable(), school, is_crit)
				_enemy_hero_panel.update(enemy_hp, enemy_hp_max, enemy_ai, enemy_void_marks)
				call_deferred("_force_end_player_turn_for_phase_transition")
				return
			_flash_hero("enemy", amount, _on_victory, school, is_crit)
		elif _capturing_spell_popups:
			_pending_hero_popups.append({kind = "damage", target = "enemy", amount = amount, school = school, is_crit = is_crit})
		else:
			_flash_hero("enemy", amount, Callable(), school, is_crit)

func _on_hero_healed(target: String, amount: int) -> void:
	# hp_changed signal handles panel refreshes for both sides.
	if target == "player":
		player_hp = mini(player_hp + amount, GameManager.player_hp_max)
		if _capturing_spell_popups:
			_pending_hero_popups.append({kind = "heal", target = "player", amount = amount})
		else:
			_flash_hero_heal("player", amount)
		_log("  You heal %d HP  (HP: %d)" % [amount, player_hp], _LogType.HEAL)
	elif target == "enemy":
		enemy_hp = mini(enemy_hp + amount, enemy_hp_max)
		if _capturing_spell_popups:
			_pending_hero_popups.append({kind = "heal", target = "enemy", amount = amount})
		else:
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
		# P4B: invert the resolve-at-impact pattern. Freeze the target slot BEFORE
		# mutating state so _on_minion_vanished sees freeze_visuals=true and defers
		# the death animation (slot.minion stays set, slot visual stays). Capture
		# popups so they sync with VFX impact instead of firing at mutation time.
		# Then mutate state immediately — kills land before any await.
		var target_slot: BoardSlot = _find_slot_for(captured_target)
		if target_slot != null:
			target_slot.freeze_visuals = true
		_capturing_spell_popups = true
		state.cast_player_targeted_spell(spell, captured_target)
		var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
		spell_ctx.card = spell
		trigger_manager.fire(spell_ctx)
		_capturing_spell_popups = false
		# Drain queued popups at vfx.impact_hit so they appear when projectile lands.
		var on_impact := func(_i: int) -> void: _drain_pending_spell_popups()
		await vfx_controller.play_spell(spell.id, "player", captured_target, on_impact)
	)

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

func _on_trap_env_input(event: InputEvent, trap_idx: int, env_data) -> void:
	if input_handler != null:
		input_handler.on_trap_env_input(event, trap_idx, env_data)

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
## Delegated to vfx_bridge — big-card reveal of an enemy summon.
func _show_enemy_summon_reveal(card: CardData) -> void:
	if vfx_bridge != null:
		await vfx_bridge.show_enemy_summon_reveal(card)

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
	# P4B: invert resolve-at-impact for enemy spell cast. Freeze the targeted
	# minion slot (or all player slots for AoE) before state mutates so death
	# animations defer until vfx finishes. Popups capture and drain at impact.
	_show_card_cast_anim(spell, true, func() -> void:
		var frozen_slots: Array[BoardSlot] = []
		if chosen is MinionInstance:
			var slot: BoardSlot = _find_slot_for(chosen)
			if slot != null:
				slot.freeze_visuals = true
				frozen_slots.append(slot)
		else:
			# AoE / non-minion target — freeze every player minion slot.
			for s in player_slots:
				if s.minion != null:
					s.freeze_visuals = true
					frozen_slots.append(s)
		_capturing_spell_popups = true
		state.cast_enemy_spell(spell, chosen)
		_capturing_spell_popups = false
		var on_impact := func(_i: int) -> void: _drain_pending_spell_popups()
		await vfx_controller.play_spell(spell.id, "enemy", chosen, on_impact)
		_drain_pending_spell_popups()
		for s in frozen_slots:
			if is_instance_valid(s):
				s.freeze_visuals = false
				s._refresh_visuals()
		_flush_deferred_deaths()
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

# Facades to CombatState's signal emit — external callers (HardcodedEffects,
# EffectResolver, RelicEffects) keep working unchanged. Subscribers below do
# the actual TrapEnvDisplay work.
func _update_trap_display_for(owner: String) -> void:
	state._update_trap_display_for(owner)

func _update_trap_display() -> void:
	state._update_trap_display()

func _update_enemy_trap_display() -> void:
	state._update_enemy_trap_display()

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

## Pure logic — delegated to CombatState.
func _unregister_env_rituals() -> void:
	state._unregister_env_rituals()

## Run teardown steps for the outgoing environment (e.g. remove persistent buffs).
## Called when the environment is replaced mid-turn so buffs don't linger.
func _unregister_env_aura(env: EnvironmentCardData) -> void:
	if not env.on_replace_effect_steps.is_empty():
		var ctx := EffectContext.make(self, "player")
		EffectResolver.run(env.on_replace_effect_steps, ctx)

## Register persistent aura event handlers for a newly placed rune.
## Delegated to CombatState — registers rune aura handlers and runs on-place steps.
func _apply_rune_aura(rune: TrapCardData, owner: String = "player") -> void:
	state._apply_rune_aura(rune, owner)

## Pure logic — delegated to CombatState.
func _remove_rune_aura(rune: TrapCardData, owner: String = "player") -> void:
	state._remove_rune_aura(rune, owner)

func _refresh_dominion_aura(active: bool, amount: int = 100) -> void:
	state._refresh_dominion_aura(active, amount)

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

## Pure logic — delegated to CombatState.
func _runes_satisfy(runes: Array, required: Array[int]) -> bool:
	return state._runes_satisfy(runes, required)

## Delegated to CombatState — rune consumption + effect resolution. Scene
## handles UI cleanup (rune-glow tweens) since traps_changed signal subscribers
## don't know about glow state.
func _fire_ritual(ritual: RitualData) -> void:
	state._fire_ritual(ritual)
	# Stop all glow tweens after consumption — prevents stale glow on repurposed slots
	if trap_env_display != null:
		for i in trap_slot_panels.size():
			trap_env_display.stop_rune_glow(i)


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
	if input_handler != null:
		input_handler.on_board_slot_hover_enter(slot)

func _on_enemy_hero_button_pressed() -> void:
	if input_handler != null:
		await input_handler.on_enemy_hero_button_pressed()

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

var _pending_revive: bool:
	get: return state._pending_revive
	set(v): state._pending_revive = v
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

## Public facade — handlers and effects call `_scene._refresh_slot_for(m)`.
## Delegates to CombatState which emits `minion_stats_changed`; subscriber below
## does the actual visual update.
func _refresh_slot_for(minion: MinionInstance) -> void:
	state._refresh_slot_for(minion)

func _on_state_minion_stats_changed(minion: MinionInstance) -> void:
	if combat_ui != null:
		combat_ui.on_state_minion_stats_changed(minion)

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

## Death animation system delegated to vfx_bridge. Scene keeps thin wrappers
## so external callers (VfxController via _combat._flush_deferred_deaths,
## CombatHandlers via _scene._minion_has_on_death) don't need to know about
## the bridge. State (_active_death_anims, _deferred_death_slots,
## _pending_on_death_vfx, _pending_sacrifice_ghost_delay) stays on scene
## since multiple non-VFX paths write to it.
func _animate_minion_death(slot: BoardSlot, pos: Vector2, dead_minion: MinionInstance = null) -> void:
	if vfx_bridge != null:
		await vfx_bridge.animate_minion_death(slot, pos, dead_minion)

func _minion_has_on_death(minion: MinionInstance) -> bool:
	return vfx_bridge != null and vfx_bridge.minion_has_on_death(minion)

func _resolve_deferred_on_death(minion: MinionInstance) -> void:
	if vfx_bridge != null:
		vfx_bridge.resolve_deferred_on_death(minion)

func _flush_deferred_deaths() -> void:
	if vfx_bridge != null:
		vfx_bridge.flush_deferred_deaths()

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

## Delegated to CombatState — applies damage and emits spell_damage_dealt.
## VFX (flash + popup) handled by _on_state_spell_damage_dealt subscriber.
func _spell_dmg(target: MinionInstance, damage: int, info: Dictionary = {}) -> void:
	state._spell_dmg(target, damage, info)

## P4B: while a player spell is mid-resolution (state mutates inside
## scene's wrapper BEFORE the VFX projectile lands), queue popup + flash
## events so they fire at vfx.impact_hit instead of immediately. This
## preserves the "damage popup appears when projectile hits" UX after
## inverting the resolve-at-impact pattern. Cleared when the VFX dispatcher
## drains the queue.
var _capturing_spell_popups: bool = false
var _pending_spell_popups: Array = []  # Array[{slot: BoardSlot, damage: int}]
## Hero popups queued during inverted spell flow — same purpose as
## _pending_spell_popups but for hero-target damage / heal that flows through
## combat_manager.hero_damaged / hero_healed (not spell_damage_dealt). Drained
## alongside minion popups at vfx.impact_hit. Lethal damage skips the queue
## so the defeat / victory flow can fire immediately.
var _pending_hero_popups: Array = []  # Array[{kind, target, amount, school, is_crit}]

func _on_state_spell_damage_dealt(target: MinionInstance, damage: int) -> void:
	if combat_ui != null:
		combat_ui.on_state_spell_damage_dealt(target, damage)

## Drain queued spell popups (minion + hero) — called from spell VFX
## controllers' resolve_damage callback at impact_hit so popups sync with
## projectile arrival even though state mutated earlier.
func _drain_pending_spell_popups() -> void:
	for p in _pending_spell_popups:
		var slot: BoardSlot = p.slot
		if slot != null and is_instance_valid(slot):
			_flash_slot(slot)
			_spawn_damage_popup(slot.get_global_rect().get_center(), p.damage)
	_pending_spell_popups.clear()
	for hp in _pending_hero_popups:
		if hp.kind == "heal":
			_flash_hero_heal(hp.target, hp.amount)
		else:
			_flash_hero(hp.target, hp.amount, Callable(), hp.school, hp.is_crit)
	_pending_hero_popups.clear()

## Drain ONE queued spell-damage popup matched to the given slot. Used by
## per-minion-impact VFX (e.g. Abyssal Plague's wave) so each popup fires when
## the wave actually touches that minion's slot, instead of all draining at
## the end of the VFX. Returns true if a popup was found and spawned.
func _drain_pending_spell_popup_for_slot(slot: BoardSlot) -> bool:
	if slot == null:
		return false
	for i in _pending_spell_popups.size():
		var p: Dictionary = _pending_spell_popups[i]
		if p.slot == slot:
			_pending_spell_popups.remove_at(i)
			if is_instance_valid(slot):
				_flash_slot(slot)
				_spawn_damage_popup(slot.get_global_rect().get_center(), p.damage)
			return true
	return false

## Hero/minion flash + popup primitives all delegated to vfx_bridge.
func _flash_hero(target: String, amount: int, on_done: Callable = Callable(), school: int = Enums.DamageSchool.NONE, is_crit: bool = false) -> void:
	if vfx_bridge != null:
		vfx_bridge.flash_hero(target, amount, on_done, school, is_crit)

func _flash_hero_heal(target: String, amount: int) -> void:
	if vfx_bridge != null:
		vfx_bridge.flash_hero_heal(target, amount)

func _spawn_damage_popup(screen_center: Vector2, damage: int, is_crit: bool = false) -> void:
	if vfx_bridge != null:
		vfx_bridge.spawn_damage_popup(screen_center, damage, is_crit)

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

## Public log facade — delegates to CombatState's signal so any caller (handlers,
## effects, this scene) routes through the same chokepoint. Subscriber
## `_on_state_combat_log` writes to the on-screen CombatLog UI.
func _log(msg: String, type: int = CombatLog.LogType.PLAYER) -> void:
	state._log(msg, type)

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
