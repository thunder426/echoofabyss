## CombatInputHandler.gd
## Owns the click/hover/select/target chain — every "user touched something"
## handler used to live inline on CombatScene. The flow:
##
##   user clicks hand card → _on_hand_card_selected → _begin_spell_select /
##   _begin_minion_select → highlight valid targets → user clicks slot →
##   _on_player_slot_clicked_* / _on_enemy_slot_clicked → resolve into a
##   _try_play_* call on the scene → state mutates / VFX plays
##
## Scene keeps thin signal-receiving wrappers (since hand_display, slots, and
## enemy_hero_button are already wired to scene methods); the wrappers all
## delegate here. Selection-state fields (pending_play_card, selected_attacker,
## _awaiting_minion_target etc.) stay on scene so other scene paths can read
## them without reaching through this node.
##
## Migration is incremental. Methods land here in batches alongside their
## scene-side wrappers.
class_name CombatInputHandler
extends Node

## CombatScene back-ref. Used for: scene state flags (pending_play_card,
## selected_attacker), card-play orchestrators (_try_play_*, _apply_targeted_spell),
## targeting helper (_scene.targeting), large preview, hand/slot refs.
var _scene: Node = null
var state: CombatState = null

func setup(p_scene: Node, p_state: CombatState) -> void:
	_scene = p_scene
	state = p_state

# ─────────────────────────────────────────────────────────────────────────────
# Hover handlers — show the large preview / blink resource pips.
# ─────────────────────────────────────────────────────────────────────────────

## Player trap slot hover — show the large preview of the trap.
func on_trap_slot_hover(idx: int) -> void:
	if _scene == null:
		return
	if idx < _scene.active_traps.size():
		_scene._show_large_preview(_scene.active_traps[idx])

## Enemy trap slot hover — only previews face-up runes (concealed traps stay hidden).
func on_enemy_trap_slot_hover(idx: int) -> void:
	if _scene == null or _scene.enemy_ai == null:
		return
	var traps: Array = _scene.enemy_ai.active_traps
	if idx < traps.size():
		var trap: TrapCardData = traps[idx] as TrapCardData
		if trap.is_rune:
			_scene._show_large_preview(trap)

## Board slot hover — show large preview of the minion if any. Override stats
## with spawn values so the preview matches the card the player drew.
func on_board_slot_hover_enter(slot: BoardSlot) -> void:
	if _scene == null:
		return
	if slot.minion and slot.minion.card_data:
		_scene.large_preview.show_card(slot.minion.card_data)
		if _scene.large_preview.visual != null:
			_scene.large_preview.visual.override_stat_display(slot.minion.spawn_atk, slot.minion.spawn_health)

## Relic hover — preview resource gain (Mana Refill blinks +2 mana).
func on_relic_hovered(effect_id: String) -> void:
	if _scene == null:
		return
	match effect_id:
		"relic_refill_mana":
			var gain: int = mini(2, _scene.turn_manager.mana_max - _scene.turn_manager.mana)
			if gain > 0 and _scene._pip_bar != null:
				_scene._pip_bar.start_blink(0, 0, 0, gain)

func on_relic_unhovered() -> void:
	if _scene != null and _scene._pip_bar != null:
		_scene._pip_bar.stop_blink()

# ─────────────────────────────────────────────────────────────────────────────
# Hand-card selection chain — pick a card → enter spell/minion select → target.
# ─────────────────────────────────────────────────────────────────────────────

## Handle a hand card click. Spell/minion go through their respective begin_*
## chains; trap/environment play immediately.
func on_hand_card_selected(inst: CardInstance) -> void:
	if _scene == null or not _scene.turn_manager.is_player_turn:
		return
	_scene.selected_attacker = null
	_scene._clear_all_highlights()
	_scene.pending_play_card = inst
	if inst.card_data is SpellCardData:
		begin_spell_select(inst.card_data as SpellCardData)
	elif inst.card_data is TrapCardData:
		_scene._try_play_trap(inst.card_data as TrapCardData)
	elif inst.card_data is EnvironmentCardData:
		_scene._try_play_environment(inst.card_data as EnvironmentCardData)
	elif inst.card_data is MinionCardData:
		begin_minion_select(inst.card_data as MinionCardData)

## Cancel a pending card selection: clear state and deselect hand.
func cancel_card_select() -> void:
	if _scene == null:
		return
	if _scene._pip_bar != null:
		_scene._pip_bar.stop_blink()
	_scene.pending_play_card = null
	_scene.pending_minion_target = null
	_scene._awaiting_minion_target = false
	_scene._clear_all_highlights()
	if _scene.hand_display:
		_scene.hand_display.deselect_current()

## Hand card hover — show large preview and cost blink. Suppressed entirely
## while another card is pending a target selection.
func on_hand_card_hovered(card_data: CardData, visual: CardVisual) -> void:
	if _scene == null:
		return
	_scene._hovered_hand_visual = visual
	if _scene.pending_play_card != null:
		return  # targeting in progress — don't interrupt with another card's preview
	_scene._show_large_preview(card_data, visual)
	if _scene.turn_manager and _scene.turn_manager.is_player_turn:
		start_pip_blink_for_card(card_data)

## Hand card unhover — hide preview and stop blink (unless a targeted card is still pending).
func on_hand_card_unhovered() -> void:
	if _scene == null:
		return
	_scene._hovered_hand_visual = null
	_scene._hide_large_preview()
	if _scene.pending_play_card == null and _scene._pip_bar != null:
		_scene._pip_bar.stop_blink()

## Compute and start the pip blink preview for any card type. Used by hover
## preview and as a fallback when a targeted card is clicked.
func start_pip_blink_for_card(card_data: CardData) -> void:
	if _scene == null or _scene.turn_manager == null:
		return
	var ess_spend := 0
	var mna_spend := 0
	var ess_gain  := 0
	var mna_gain  := 0
	if card_data is SpellCardData:
		var spell := card_data as SpellCardData
		mna_spend = _scene._effective_spell_cost(spell)
		for step: Dictionary in spell.effect_steps:
			if step.get("type") != "CONVERT_RESOURCE":
				continue
			var amount: int    = step.get("amount", 0)
			var from: String   = step.get("convert_from", "")
			var to: String     = step.get("convert_to", "")
			var available: int = _scene.turn_manager.mana - mna_spend if from == "mana" \
					else _scene.turn_manager.essence - ess_spend
			var actual: int    = mini(amount, maxi(available, 0))
			if from == "mana":   mna_spend += actual
			elif from == "essence": ess_spend += actual
			if to == "essence": ess_gain += actual
			elif to == "mana":  mna_gain += actual
	elif card_data is MinionCardData:
		var mc := card_data as MinionCardData
		# piercing_void's +1 Mana now baked into mc.mana_cost via talent_overrides.
		ess_spend = maxi(0, mc.essence_cost - _scene._peek_fiendish_pact_discount(mc))
		mna_spend = maxi(0, mc.mana_cost)
	elif card_data is TrapCardData:
		mna_spend = _scene._effective_trap_cost(card_data as TrapCardData)
	elif card_data is EnvironmentCardData:
		mna_spend = (card_data as EnvironmentCardData).cost
	# Dark Mirror: reduce both costs for preview
	if _scene._relic_cost_reduction > 0:
		ess_spend = maxi(0, ess_spend - _scene._relic_cost_reduction)
		mna_spend = maxi(0, mna_spend - _scene._relic_cost_reduction)
	if not _scene.turn_manager.can_afford(ess_spend, mna_spend):
		return
	if _scene._pip_bar != null:
		_scene._pip_bar.start_blink(ess_spend, mna_spend, ess_gain, mna_gain)

## Handle a spell card being selected from hand. Instant spells cast immediately
## (cost preview shown on hover); targeted spells enter pending state and
## highlight valid targets.
func begin_spell_select(spell: SpellCardData) -> void:
	if _scene == null:
		return
	if not _scene.turn_manager.can_afford(0, _scene._effective_spell_cost(spell)):
		cancel_card_select()
		return
	if not _scene._player_can_afford_sparks(spell.void_spark_cost):
		cancel_card_select()
		return
	if spell.requires_target:
		start_pip_blink_for_card(spell)  # ensure blink runs even if card wasn't hovered
		_scene._highlight_spell_targets(spell)
	else:
		_scene._try_play_spell(spell)

## Handle a minion card being selected from hand. Affordability + board-space
## checks, then highlight valid placement / target slots.
func begin_minion_select(mc: MinionCardData) -> void:
	if _scene == null:
		return
	# piercing_void's +1 Mana now baked into mc.mana_cost via talent_overrides.
	var ess_cost := maxi(0, mc.essence_cost - _scene._peek_fiendish_pact_discount(mc))
	if not _scene.turn_manager.can_afford(ess_cost, maxi(0, mc.mana_cost)):
		cancel_card_select()
		return
	if not _scene._player_can_afford_sparks(mc.void_spark_cost):
		cancel_card_select()
		return
	# Check board space before highlighting
	if not _scene.player_slots.any(func(s: BoardSlot) -> bool: return s.is_empty()):
		cancel_card_select()
		return
	start_pip_blink_for_card(mc)
	var has_targets: bool = _scene._has_valid_minion_on_play_targets_for(_scene._effective_target_type(mc))
	var is_optional: bool = _scene._effective_target_optional(mc)
	var is_required: bool = mc.on_play_requires_target and not is_optional
	if is_required and has_targets:
		# Mandatory target — targets only; player must pick one before placement.
		_scene._awaiting_minion_target = true
		_scene._highlight_minion_on_play_targets(mc)
		_scene._show_target_prompt(_scene._effective_target_prompt(mc))
	elif is_optional and has_targets:
		# Optional target — highlight targets (yellow) AND empty slots (green).
		# Click a target to resolve effect + show placement; click a slot to
		# summon without the effect.
		_scene._awaiting_minion_target = true
		_scene._clear_all_highlights()
		var t_type: String = _scene._effective_target_type(mc)
		var yellow := Color(1.0, 0.9, 0.2, 1.0)
		var yellow_picker := func(_s: BoardSlot) -> Color: return yellow
		if t_type in ["enemy_minion", "corrupted_enemy_minion"]:
			_scene._highlight_slots(_scene.enemy_slots,
				func(s): return not s.is_empty() and _scene._is_valid_minion_on_play_target(s.minion, t_type),
				yellow_picker)
		if t_type in ["friendly_minion", "friendly_minion_other", "friendly_demon"]:
			_scene._highlight_slots(_scene.player_slots,
				func(s): return not s.is_empty() and _scene._is_valid_minion_on_play_target(s.minion, t_type),
				yellow_picker)
		_scene._highlight_slots(_scene.player_slots, func(s): return s.is_empty())
		_scene._show_target_prompt(_scene._effective_target_prompt(mc))
	else:
		# No valid targets (or card doesn't need one) — go straight to placement.
		# Effect will fire but resolve with null target (logs "no targets" and skips).
		_scene._awaiting_minion_target = false
		_scene._highlight_empty_player_slots()

func on_hand_card_deselected() -> void:
	if _scene == null:
		return
	if _scene._pip_bar != null:
		_scene._pip_bar.stop_blink()
	_scene.pending_play_card = null
	_scene.pending_minion_target = null
	_scene._awaiting_minion_target = false
	_scene._hide_target_prompt()
	_scene._tear_down_trap_env_targeting()
	_scene._clear_all_highlights()

# ─────────────────────────────────────────────────────────────────────────────
# Slot click handlers — resolve pending cards, select attackers, target spells.
# ─────────────────────────────────────────────────────────────────────────────

## Click on an empty player slot. If a minion card is pending, place it here
## (with its captured target if any). Otherwise no-op.
func on_player_slot_clicked_empty(slot: BoardSlot) -> void:
	if _scene == null:
		return
	# Seris — Corrupt Flesh targeting: clicking an empty slot cancels.
	if _scene._seris_corrupt_targeting:
		_scene._cancel_seris_corrupt_targeting()
		return
	if _scene.pending_play_card != null and _scene.pending_play_card.card_data is MinionCardData:
		var mc := _scene.pending_play_card.card_data as MinionCardData
		# Still waiting for a target? — slot clicks are blocked UNLESS the card's
		# target is optional, in which case the slot click bypasses targeting and
		# the minion summons without the effect resolving.
		if _scene._awaiting_minion_target and not _scene._effective_target_optional(mc):
			return
		var inst_to_play: CardInstance = _scene.pending_play_card
		var on_play_target: MinionInstance = _scene.pending_minion_target
		_scene.pending_minion_target = null
		_scene.pending_play_card = null
		_scene._awaiting_minion_target = false
		_scene._hide_target_prompt()
		_scene._clear_all_highlights()
		_scene._try_play_minion_animated(inst_to_play, slot, on_play_target)

## Click on an occupied player slot. Resolves Seris Corrupt-Flesh targeting,
## targeted spell on a friendly minion, targeted minion-on-play, or attacker
## selection — in that priority order.
func on_player_slot_clicked_occupied(_slot: BoardSlot, minion: MinionInstance) -> void:
	if _scene == null or not _scene.turn_manager.is_player_turn:
		return
	# Seris — Corrupt Flesh activated ability targeting mode.
	if _scene._seris_corrupt_targeting:
		_scene._seris_corrupt_apply_target(minion)
		return
	# If a targeted spell is waiting for a target, apply it
	if _scene.pending_play_card != null and _scene.pending_play_card.card_data is SpellCardData:
		var spell := _scene.pending_play_card.card_data as SpellCardData
		if spell.requires_target and _scene._is_valid_spell_target(minion, spell.target_type):
			_scene._apply_targeted_spell(spell, minion)
			return
	# If a targeted minion card is waiting for a friendly target, store it and show placement slots.
	# If the minion card is pending but NOT awaiting a target (board was shown), block attacker
	# selection so clicking an occupied slot doesn't accidentally select an attacker.
	if _scene.pending_play_card != null and _scene.pending_play_card.card_data is MinionCardData:
		var mc := _scene.pending_play_card.card_data as MinionCardData
		if _scene._awaiting_minion_target and _scene._is_valid_minion_on_play_target(minion, _scene._effective_target_type(mc)):
			_scene.pending_minion_target = minion
			_scene._awaiting_minion_target = false
			_scene._highlight_empty_player_slots()
			_scene._mark_selected_target(minion)
			_scene._show_target_prompt("Target selected. Choose a slot.")
		return  # swallow the click — don't fall through to attacker selection
	# Select this minion as the attacker if it can attack
	if minion.can_attack():
		_scene.selected_attacker = minion
		_scene._highlight_valid_attack_targets()
	else:
		_scene.selected_attacker = null
		_scene._clear_all_highlights()

## Click on an occupied enemy slot. Resolves relic targeting, targeted spell,
## targeted minion-on-play, or attack — in that priority order. Enforces Guard.
func on_enemy_slot_clicked(_slot: BoardSlot, minion: MinionInstance) -> void:
	if _scene == null or not _scene.turn_manager.is_player_turn:
		return
	# Seris — Corrupt Flesh targeting: enemy clicks cancel (target must be friendly Demon).
	if _scene._seris_corrupt_targeting:
		_scene._cancel_seris_corrupt_targeting()
		return
	# If a relic is awaiting a target, resolve it
	if _scene._pending_relic_target != "":
		_scene._resolve_relic_target_minion(minion)
		return
	# If a targeted spell that can hit enemy minions is pending, apply it here
	if _scene.pending_play_card != null and _scene.pending_play_card.card_data is SpellCardData:
		var spell := _scene.pending_play_card.card_data as SpellCardData
		if spell.requires_target and _scene._is_valid_spell_target(minion, spell.target_type):
			_scene._apply_targeted_spell(spell, minion)
			return
	# If a targeted minion card is waiting for an enemy target, store it and show placement slots
	if _scene.pending_play_card != null and _scene.pending_play_card.card_data is MinionCardData:
		var mc := _scene.pending_play_card.card_data as MinionCardData
		if _scene._awaiting_minion_target and _scene._is_valid_minion_on_play_target(minion, _scene._effective_target_type(mc)):
			_scene.pending_minion_target = minion
			_scene._awaiting_minion_target = false
			_scene._highlight_empty_player_slots()
			_scene._mark_selected_target(minion)
			_scene._show_target_prompt("Target selected. Choose a slot.")
			return
	if _scene.selected_attacker == null:
		return
	# Enforce Guard — must attack a Guard minion if one exists
	if CombatManager.board_has_taunt(_scene.enemy_board) and not minion.has_guard():
		return  # Invalid target
	_scene._log("Your %s attacks enemy %s" % [_scene.selected_attacker.card_data.card_name, minion.card_data.card_name])
	_scene._anim_pre_hp   = minion.current_health
	_scene._anim_atk_slot = _scene._find_slot_for(_scene.selected_attacker)
	_scene._anim_def_slot = _scene._find_slot_for(minion)
	if _scene._anim_atk_slot: _scene._anim_atk_slot.freeze_visuals = true
	if _scene._anim_def_slot: _scene._anim_def_slot.freeze_visuals = true
	_scene.combat_manager.resolve_minion_attack(_scene.selected_attacker, minion)
	_scene.selected_attacker = null
	_scene._clear_all_highlights()
	_scene._enemy_hero_panel.show_attackable(false)

# ─────────────────────────────────────────────────────────────────────────────
# Cyclone trap-or-env targeting + relic-on-hero + enemy-hero-spell + global input.
# ─────────────────────────────────────────────────────────────────────────────

## Stored gui_input connections so they can be disconnected cleanly.
var _active_trap_env_connections: Array = []  # Array[{node: Control, cb: Callable}]

## Wire trap slots and the env slot to receive Cyclone targeting clicks. Each
## slot gets a temporary gui_input handler that resolves the targeted spell.
## Connections are tracked so tear_down_trap_env_targeting can disconnect them.
func setup_trap_env_targeting() -> void:
	if _scene == null:
		return
	tear_down_trap_env_targeting()
	for i in _scene.trap_slot_panels.size():
		if i < _scene.active_traps.size():
			var cb := func(ev: InputEvent) -> void: on_trap_env_input(ev, i, null)
			_scene.trap_slot_panels[i].gui_input.connect(cb)
			_active_trap_env_connections.append({node = _scene.trap_slot_panels[i], cb = cb})
			_scene.trap_slot_panels[i].modulate = Color(1.3, 1.3, 0.5)
	var env_slot: Control = _scene.trap_env_display.env_slot
	if env_slot and _scene.active_environment:
		var env: EnvironmentCardData = _scene.active_environment
		var cb := func(ev: InputEvent) -> void: on_trap_env_input(ev, -1, env)
		env_slot.gui_input.connect(cb)
		_active_trap_env_connections.append({node = env_slot, cb = cb})
		env_slot.modulate = Color(1.3, 1.3, 0.5)

func tear_down_trap_env_targeting() -> void:
	for c in _active_trap_env_connections:
		if is_instance_valid(c.node):
			if c.node.gui_input.is_connected(c.cb):
				c.node.gui_input.disconnect(c.cb)
			c.node.modulate = Color.WHITE
	_active_trap_env_connections.clear()

## Cyclone resolve — left-click on a trap or env slot while a Cyclone-style
## spell is pending: pay cost, remove the trap/env, fire ON_PLAYER_SPELL_CAST.
func on_trap_env_input(event: InputEvent, trap_idx: int, env_data) -> void:
	if _scene == null:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _scene.pending_play_card == null or not _scene.pending_play_card.card_data is SpellCardData:
		return
	var spell := _scene.pending_play_card.card_data as SpellCardData
	if not _scene._pay_card_cost(0, _scene._effective_spell_cost(spell)):
		if _scene.hand_display:
			_scene.hand_display.deselect_current()
		return
	_scene.turn_manager.remove_from_hand(_scene.pending_play_card)
	_scene.pending_play_card = null
	tear_down_trap_env_targeting()
	if _scene.hand_display:
		_scene.hand_display.deselect_current()
	if trap_idx >= 0 and trap_idx < _scene.active_traps.size():
		var trap: TrapCardData = _scene.active_traps[trap_idx]
		_scene._log("You cast: %s → %s" % [spell.card_name, trap.card_name])
		if trap.is_rune:
			_scene._remove_rune_aura(trap)
		_scene.active_traps.erase(trap)
		_scene._update_trap_display()
		_scene._log("  Cyclone: %s removed." % trap.card_name, 1)  # PLAYER
	elif env_data != null and _scene.active_environment == env_data:
		_scene._log("You cast: %s → %s" % [spell.card_name, _scene.active_environment.card_name])
		_scene._log("  Cyclone: %s dispelled." % _scene.active_environment.card_name, 1)  # PLAYER
		_scene._unregister_env_rituals()
		_scene.active_environment = null
		_scene._update_environment_display()
	_scene._show_card_cast_anim(spell, false, func() -> void:
		var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
		spell_ctx.card = spell
		if _scene.trigger_manager != null:
			_scene.trigger_manager.fire(spell_ctx)
	)

## Fired when player clicks the enemy hero panel while relic targeting is active.
func on_relic_target_hero_input(event: InputEvent) -> void:
	if _scene == null:
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if _scene._pending_relic_target == "":
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_scene._resolve_relic_target_hero()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_scene._cancel_relic_targeting()

## Fired when player clicks the enemy hero panel while targeting a spell with
## "enemy_minion_or_hero". Identical pattern to _apply_targeted_spell but
## targets the hero directly (no minion).
func on_enemy_hero_spell_input(event: InputEvent) -> void:
	if _scene == null:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _scene.pending_play_card == null or not _scene.pending_play_card.card_data is SpellCardData:
		return
	var spell := _scene.pending_play_card.card_data as SpellCardData
	if not _scene._pay_card_cost(0, _scene._effective_spell_cost(spell)):
		if _scene.hand_display:
			_scene.hand_display.deselect_current()
		return
	_scene._log("You cast: %s → Enemy Hero" % spell.card_name)
	_scene.turn_manager.remove_from_hand(_scene.pending_play_card)
	if _scene.hand_display:
		_scene.hand_display.remove_card(_scene.pending_play_card)
		_scene.hand_display.deselect_current()
	_scene.pending_play_card = null
	_scene._clear_all_highlights()
	# P4B: invert resolve-at-impact for hero-target spells. State mutation
	# happens immediately; VFX plays purely visual.
	var scene := _scene
	_scene._show_card_cast_anim(spell, false, func() -> void:
		scene._capturing_spell_popups = true
		scene.state.cast_player_hero_spell(spell)
		var spell_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_SPELL_CAST, "player")
		spell_ctx.card = spell
		if scene.trigger_manager != null:
			scene.trigger_manager.fire(spell_ctx)
		scene._capturing_spell_popups = false
		var on_impact := func(_i: int) -> void: scene._drain_pending_spell_popups()
		await scene.vfx_controller.play_spell(spell.id, "player", scene._enemy_status_panel, on_impact)
		scene._drain_pending_spell_popups()
	)

## Global _input — F12 / C toggles cheat menu, ESC closes it, right-click cancels
## the current pending action (relic targeting → card targeting → attacker).
func handle_input(event: InputEvent) -> void:
	if _scene == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var focus_owner := _scene.get_viewport().gui_get_focus_owner()
		var typing: bool = focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is SpinBox
		if event.keycode == KEY_F12 or (event.keycode == KEY_C and not typing):
			_scene._cheat.toggle()
		elif event.keycode == KEY_ESCAPE and _scene._cheat.visible:
			_scene._cheat.toggle()
			_scene.get_viewport().set_input_as_handled()
	# Right-click cancels relic targeting, spell targeting, or minion placement
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _scene._seris_corrupt_targeting:
			_scene._cancel_seris_corrupt_targeting()
			_scene.get_viewport().set_input_as_handled()
		elif _scene._pending_relic_target != "":
			_scene._cancel_relic_targeting()
			_scene.get_viewport().set_input_as_handled()
		elif _scene.pending_play_card != null:
			cancel_card_select()
			_scene.get_viewport().set_input_as_handled()
		elif _scene.selected_attacker != null:
			_scene.selected_attacker = null
			_scene._clear_all_highlights()
			if _scene._enemy_hero_panel != null:
				_scene._enemy_hero_panel.show_attackable(false)
			_scene.get_viewport().set_input_as_handled()

## Click on the enemy hero button — resolve attack via the standard combat path.
## Damage logic (crit / lifedrain / siphon / school tagging) lives in
## resolve_minion_attack_hero. VFX is gated on the attacker's attack_damage_school:
## VOID_BOLT-school attacks spawn the void bolt projectile (and damage syncs
## with impact); other attacks play the normal lunge animation after damage.
func on_enemy_hero_button_pressed() -> void:
	if _scene == null:
		return
	if not _scene.turn_manager.is_player_turn or _scene.selected_attacker == null:
		return
	if CombatManager.board_has_taunt(_scene.enemy_board):
		return
	if not _scene.selected_attacker.can_attack_hero():
		return
	var attacker: MinionInstance = _scene.selected_attacker
	var atk_slot: BoardSlot = _scene._find_slot_for(attacker)
	var school := Enums.DamageSchool.NONE
	if attacker.card_data is MinionCardData:
		school = (attacker.card_data as MinionCardData).attack_damage_school
	# Clear selection state up-front so the click can't double-fire while we await VFX.
	_scene.selected_attacker = null
	_scene._clear_all_highlights()
	if school == Enums.DamageSchool.VOID_BOLT:
		# Void Bolt-flavored basic attack: fire projectile, await impact, then
		# resolve damage. resolve_minion_attack_hero still tags the DamageInfo
		# with VOID_BOLT via _attack_damage_info, so school flows correctly.
		_scene._log("Your %s strikes Enemy Hero with a Void Bolt!" % attacker.card_data.card_name, 1)  # PLAYER
		_scene._enemy_hero_panel.show_attackable(false)
		var bolt: VoidBoltProjectile = _scene._fire_void_bolt_projectile(attacker, false)
		if bolt != null and _scene.is_inside_tree():
			await bolt.impact_hit
		_scene.combat_manager.resolve_minion_attack_hero(attacker, "enemy")
	else:
		_scene._log("Your %s attacks Enemy Hero" % attacker.card_data.card_name)
		_scene.combat_manager.resolve_minion_attack_hero(attacker, "enemy")
		if atk_slot and _scene._enemy_status_panel:
			_scene._play_hero_attack_anim(atk_slot, _scene._enemy_status_panel, attacker)
	_scene._enemy_hero_panel.show_attackable(false)
