## CombatUI.gd
## Owns "X happened → refresh Y" subscriber methods. State / CombatManager /
## TurnManager / BuffSystem signals all eventually need to push their changes
## into UI nodes (hero panels, pip bar, combat log, trap display, slots).
## Those subscribers used to live inline on CombatScene; this node is where
## they migrate to.
##
## Scope: this node OWNS the small "refresh on signal" methods. It does NOT
## own:
##   - the popup queue (lives on scene; both input flow and UI subscribers
##     read/write it)
##   - VFX (CombatVFXBridge)
##   - input handling (CombatInputHandler)
##   - card-play orchestration (`_try_play_*`, `_apply_targeted_spell` —
##     scene; they bridge state mutation + VFX + input feedback)
##
## All UI-node refs are reached through `_scene.X` (forwarding properties on
## scene). State is accessed directly via `state` or `_scene.state`.
class_name CombatUI
extends Node

## CombatScene back-ref. Used for UI-node refs (hero panels, pip bar, combat
## log, trap_env_display, _enemy_status_panel etc.) and shared scene state
## (combat_ended flag, popup queue when applicable).
var _scene: Node = null
var state: CombatState = null

func setup(p_scene: Node, p_state: CombatState) -> void:
	_scene = p_scene
	state = p_state

# ─────────────────────────────────────────────────────────────────────────────
# CombatState signal subscribers — the "X mutated → refresh Y" wiring.
# ─────────────────────────────────────────────────────────────────────────────

## Subscriber to CombatState.hp_changed — refreshes the appropriate hero panel
## whenever HP mutates. Lets us drop scattered `_hero_panel.update(...)` calls
## sprinkled through damage/heal paths; the signal does it for free.
## Note: enemy_void_marks and enemy_ai aren't HP-related, so the existing
## `_enemy_hero_panel.update(...)` calls on void-mark / AI-state paths stay.
func on_state_hp_changed(side: String, new_hp: int, mx: int, _delta: int) -> void:
	if _scene == null:
		return
	if side == "player":
		if _scene._player_hero_panel:
			_scene._player_hero_panel.update(new_hp, mx)
	else:
		if _scene._enemy_hero_panel:
			_scene._enemy_hero_panel.update(new_hp, mx, _scene.enemy_ai, _scene.enemy_void_marks)

## Subscriber to CombatState.void_marks_changed — refreshes the enemy hero
## panel so the stack count visual stays current without scattered manual
## `_enemy_hero_panel.update(...)` calls at every void mark mutation.
func on_state_void_marks_changed(side: String, _value: int) -> void:
	if _scene == null:
		return
	if side == "enemy" and _scene._enemy_hero_panel:
		_scene._enemy_hero_panel.update(_scene.enemy_hp, _scene.enemy_hp_max, _scene.enemy_ai, _scene.enemy_void_marks)

## Korrath — refresh the appropriate hero panel's debuff badges. State signals
## (hero_armour_changed, hero_buff_changed) route through here so the panel sees
## one update path; values are always read fresh off HeroState + BuffSystem so
## a future second source of armour/AB/corruption picks up automatically.
func _refresh_hero_korrath_badges(side: String) -> void:
	if _scene == null or state == null:
		return
	var hero: HeroState = state.player_hero if side == "player" else state.enemy_hero
	if hero == null:
		return
	var ab_total: int = BuffSystem.sum_type(hero, Enums.BuffType.ARMOUR_BREAK)
	var corrupt_stacks: int = BuffSystem.count_type(hero, Enums.BuffType.CORRUPTION)
	if side == "player":
		if _scene._player_hero_panel:
			_scene._player_hero_panel.update_korrath_debuffs(hero.armour, ab_total, corrupt_stacks)
	else:
		if _scene._enemy_hero_panel:
			_scene._enemy_hero_panel.update_korrath_debuffs(hero.armour, ab_total, corrupt_stacks)

func on_state_hero_armour_changed(side: String, _value: int) -> void:
	_refresh_hero_korrath_badges(side)

func on_state_hero_buff_changed(side: String) -> void:
	_refresh_hero_korrath_badges(side)

## Subscriber to CombatState.combat_log — forwards to the on-screen CombatLog.
## Lets handlers and effects log via state without holding a scene reference.
func on_state_combat_log(msg: String, log_type: int) -> void:
	if _scene == null or _scene.combat_log == null:
		return
	_scene.combat_log.write(msg, log_type)

## Subscriber to CombatState.flesh_changed — refreshes Seris's resource bar.
## Replaces the old Flesh.on_changed() callback chain.
func on_state_flesh_changed(_value: int, _max_value: int) -> void:
	if _scene == null:
		return
	if _scene._pip_bar != null:
		_scene._pip_bar.update_flesh()
	if _scene._player_hero_panel != null and _scene._player_hero_panel.resource_bar != null:
		_scene._player_hero_panel.resource_bar.refresh()

## Subscriber to CombatState.forge_changed — refreshes the forge widget on
## PipBar and the Soul Forge skill button on SerisResourceBar.
func on_state_forge_changed(_value: int, _threshold: int) -> void:
	if _scene == null:
		return
	if _scene._pip_bar != null:
		_scene._pip_bar.update_forge()
	if _scene._player_hero_panel != null and _scene._player_hero_panel.resource_bar != null:
		_scene._player_hero_panel.resource_bar.refresh()

## Subscriber to CombatState.traps_changed — refreshes the trap/rune slot
## panel for the affected side.
func on_state_traps_changed(side: String) -> void:
	if _scene != null and _scene.trap_env_display != null:
		_scene.trap_env_display.update_traps_for(side)

## Subscriber to CombatState.environment_changed — refreshes the env card
## display.
func on_state_environment_changed(_env: EnvironmentCardData) -> void:
	if _scene != null and _scene.trap_env_display != null:
		_scene.trap_env_display.update_environment()

## Subscriber to CombatState.minion_stats_changed — finds the minion's slot
## and triggers a visual re-render.
func on_state_minion_stats_changed(minion: MinionInstance) -> void:
	if state == null:
		return
	var slots: Array = state.player_slots if minion.owner == "player" else state.enemy_slots
	for slot in slots:
		if slot.minion == minion:
			slot._refresh_visuals()
			break

## Subscriber to CombatState.spell_damage_dealt — spawns the slot flash, damage
## popup, and refreshes the slot so the HP label updates IN SYNC with the
## floating "-N" number.
##
## Rule: floating damage number and HP-bar reduction display together. Every
## damage path that emits spell_damage_dealt gets this for free; callers do
## NOT need to call _refresh_slot_for separately for the HP label.
##
## When `_capturing_spell_popups` is set on scene (P4B inverted spell flow),
## the popup AND the refresh are deferred together — drained at VFX impact_hit
## via _drain_pending_spell_popups so the visual sync is preserved.
func on_state_spell_damage_dealt(target: MinionInstance, damage: int, school: int = Enums.DamageSchool.NONE) -> void:
	if _scene == null or target == null:
		return
	var slot: BoardSlot = _scene._find_slot_for(target)
	if slot == null:
		return
	# spell_damage_dealt fires BEFORE state applies damage — current_health is
	# still pre-damage. Snapshot pre/post values now so they're stable through
	# any deferred drain.
	var from_hp: int = target.current_health
	var to_hp: int = maxi(from_hp - damage, 0)
	if _scene._capturing_spell_popups:
		_scene._pending_spell_popups.append({
			slot = slot, damage = damage, minion = target, school = school,
			from_hp = from_hp, to_hp = to_hp,
		})
		return
	_scene._flash_slot(slot)
	_scene._spawn_damage_popup(slot.get_global_rect().get_center(), damage, false, school)
	# Anchor HP tween to the popup spawn moment — same call, guaranteed sync.
	if slot.has_method("animate_hp_change"):
		slot.animate_hp_change(from_hp, to_hp)

# ─────────────────────────────────────────────────────────────────────────────
# Display-refresh helpers with real logic. Trivial 1-line delegators
# (_update_*_display, _show/hide_large_preview, _refresh_slot_for, etc.) stay
# on scene — moving them just shifts the delegation without shrinking lines.
# ─────────────────────────────────────────────────────────────────────────────

## TurnManager subscriber — push essence/mana into label + pip-bar + hand
## playability refresh. Pulses pip-bar columns on gain/spend so the player
## sees a flash when resources move.
##
## NOTE: end-turn button mode is NOT updated here — temp gains (gain_mana,
## gain_essence) also fire this signal and must not flip the button layout.
## Use refresh_end_turn_mode() only after grow_essence_max / grow_mana_max or
## at turn start.
func on_resources_changed(essence: int, essence_max: int, mana: int, mana_max: int) -> void:
	if _scene == null:
		return
	if _scene.essence_label:
		_scene.essence_label.text = "%d/%d" % [essence, essence_max]
	if _scene.mana_label:
		_scene.mana_label.text = "%d/%d" % [mana, mana_max]
	if _scene.hand_display:
		_scene.hand_display.refresh_playability(essence, mana, _scene._relic_cost_reduction, _scene._relic_cost_reduction)
	refresh_hand_spell_costs()
	if _scene._pip_bar:
		_scene._pip_bar.update(essence, essence_max, mana, mana_max)
		# Pulse the column border to signal gain (green) or spend (red/orange)
		if _scene._prev_essence >= 0 and essence != _scene._prev_essence:
			_scene._pip_bar.pulse_col(true, essence > _scene._prev_essence)
		if _scene._prev_mana >= 0 and mana != _scene._prev_mana:
			_scene._pip_bar.pulse_col(false, mana > _scene._prev_mana)
	_scene._prev_essence = essence
	_scene._prev_mana    = mana

## Update end-turn panel layout based on permanent resource max values. Call
## only after grow_essence_max / grow_mana_max or at turn start (NOT on every
## resources_changed — temp gains shouldn't flip the layout).
func refresh_end_turn_mode() -> void:
	if _scene == null:
		return
	var at_cap: bool = (_scene.turn_manager.essence_max + _scene.turn_manager.mana_max) >= TurnManager.COMBINED_RESOURCE_CAP
	if _scene.end_turn_essence_button:
		_scene.end_turn_essence_button.visible = not at_cap
	if _scene.end_turn_mana_button:
		_scene.end_turn_mana_button.visible = not at_cap
	if _scene.has_node("UI/EndTurnPanel/ETSubLabel"):
		_scene.get_node("UI/EndTurnPanel/ETSubLabel").visible = not at_cap
	if _scene.end_turn_button:
		_scene.end_turn_button.visible = at_cap

## HandDisplay subscriber — fired when any hand-card draw/play animation
## finishes. Refreshes playability glow + condition glow for current resources.
func on_card_anim_finished() -> void:
	if _scene == null or _scene.hand_display == null:
		return
	_scene.hand_display.refresh_playability(_scene.turn_manager.essence, _scene.turn_manager.mana, _scene._relic_cost_reduction, _scene._relic_cost_reduction)
	_scene.hand_display.refresh_condition_glows(_scene, _scene.turn_manager.essence, _scene.turn_manager.mana)

## Refresh hand card cost displays + relic cost preview + playability glows +
## condition glows + the large preview's cost overlay (if visible). Called
## from many places — when discounts change, when essence/mana mutate, when
## minions enter/leave that have mana_cost_discount auras.
func refresh_hand_spell_costs() -> void:
	if _scene == null:
		return
	var net_discount: int = _scene._spell_mana_discount() - _scene.player_spell_cost_penalty
	var relic_red: int = _scene._relic_cost_reduction
	if _scene.hand_display:
		# Non-minion cards: mana discount includes relic reduction
		_scene.hand_display.refresh_spell_costs(net_discount + relic_red)
		# Minion cards: show essence and mana reductions from Dark Mirror
		_scene.hand_display.refresh_relic_cost_preview(relic_red, relic_red)
		_scene.hand_display.refresh_playability(_scene.turn_manager.essence, _scene.turn_manager.mana, relic_red, relic_red)
		_scene.hand_display.refresh_condition_glows(_scene, _scene.turn_manager.essence, _scene.turn_manager.mana)
	if _scene.large_preview != null and _scene.large_preview.is_visible():
		var extra: int = -(_scene._hovered_hand_visual.card_inst.mana_delta) if _scene._hovered_hand_visual != null and _scene._hovered_hand_visual.card_inst != null else 0
		_scene.large_preview.visual.apply_cost_discount(net_discount + relic_red + extra)
		_scene.large_preview.visual.apply_relic_cost_preview(relic_red, relic_red)
