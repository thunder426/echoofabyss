## CombatVFXBridge.gd
## Holds compound VFX orchestration that used to live on CombatScene — sigil
## summons, summon-reveal sequences, death animations, projectiles, and the
## small "show me what just happened" flourishes (flash, popup). The split
## from VfxController is intentional: VfxController.gd owns spell-specific
## dispatch (arcane_strike, void_execution, plague, etc.); this bridge owns
## everything else that used to be inline on the scene.
##
## Methods access state through `state` (CombatState) for triggers/logs and
## hold direct refs to `vfx_controller` and the scene-tree pieces they need.
## Scene-side callers route through `vfx_bridge.X(...)`; external callers
## (HardcodedEffects, RelicEffects) keep using their existing `_scene.X(...)`
## thin wrappers so they don't need to know the bridge exists.
##
## Migration is incremental — methods land here in batches alongside their
## scene-side callsites. Each batch keeps the original behaviour intact;
## tests rely on visual continuity, not internal call structure.
class_name CombatVFXBridge
extends Node

var _scene: Node = null  ## CombatScene back-ref — used by methods that need scene-side
                          ## UI panels, board refs, or scene-only helpers (`_find_slot_for`,
                          ## `_get_opponent_occupied_slots`, `_player_hero_panel` etc.).
var state: CombatState = null
var vfx_controller: VfxController = null

## Currently-playing Pack Frenzy VFX (or null). VfxController reads this via
## `_combat.vfx_bridge._pack_frenzy_active_vfx` so it can await the full
## glyphs + linger sparks before resuming enemy AI.
var _pack_frenzy_active_vfx: PackFrenzyVFX = null

func setup(p_scene: Node, p_state: CombatState, p_vfx: VfxController) -> void:
	_scene = p_scene
	state = p_state
	vfx_controller = p_vfx

# ─────────────────────────────────────────────────────────────────────────────
# Sigil summons — sigil VFX → optional spark burst → minion fade-in reveal
# ─────────────────────────────────────────────────────────────────────────────

## Play SPARK sigil VFX, then reveal the summoned spark after the VFX ends.
## The slot is reserved immediately (minion occupies it, visuals frozen) so
## back-to-back SUMMON steps (e.g. Brood Imp's 2 sparks) land in distinct
## slots. Each summon plays its own sigil in parallel.
func summon_spark_with_sigil(instance: MinionInstance, data: MinionCardData,
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

	_reveal_after_sigil(slot, data, instance, owner)

## Play purple ARCANE sigil VFX for a Void Demon token, then a short inward
## spark burst while the slot fades in. Mirrors summon_spark_with_sigil but
## uses the Void Spawning visual language (purple rings + violet sparks).
func summon_demon_with_sigil(instance: MinionInstance, data: MinionCardData,
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

	_reveal_after_sigil(slot, data, instance, owner)

## Play dark-green BROOD_DARK sigil VFX for a Brood Imp token summoned from
## Matriarch's Broodling on-death, then a green/black inward spark burst while
## the slot fades in. Mirrors summon_demon_with_sigil.
func summon_brood_imp_with_sigil(instance: MinionInstance, data: MinionCardData,
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

	_reveal_after_sigil(slot, data, instance, owner)

# ─────────────────────────────────────────────────────────────────────────────
# Champion / passive / on-play VFX (corruption detonations, feral reinforcement,
# champion ACP aura pulse). External-caller-facing — scene keeps thin wrappers.
# ─────────────────────────────────────────────────────────────────────────────

## Champion: Abyss Cultist Patrol — quick rim-light pulse on the champion's
## aura (rim glow + smoke wisps + sonic shimmer). Fires each time the aura
## triggers an instant detonation, so the player learns the visual link
## "champion pulses -> my corrupted minion blows up."
func play_champion_acp_aura_pulse() -> void:
	if _scene == null or vfx_controller == null:
		return
	var champion: MinionInstance = null
	for m in _scene.enemy_board:
		if (m as MinionInstance).card_data.id == "champion_abyss_cultist_patrol":
			champion = m
			break
	if champion == null:
		return
	var slot: BoardSlot = _scene._find_slot_for(champion)
	if slot == null:
		return
	vfx_controller.spawn(ChampionAuraCorruptionPulseVFX.create(slot))

## Detonate Corruption on a list of minions in parallel. Each target spawns a
## CorruptionDetonationVFX; on impact_hit, `on_impact.call(minion, stacks)` runs
## so the caller can remove stacks + refresh the slot + apply damage synced to
## the visible burst. Missing slots fall back to immediate application.
##
## Freezes each target slot's visuals so lethal damage keeps the card parked
## under the burst — any deaths queue into _deferred_death_slots and flush
## once the last VFX finishes.
##
## Gates enemy actions: sets scene's `_on_play_vfx_active` while detonations
## play and emits `on_play_vfx_done` when the last one finishes, so EnemyAI
## awaits the full animation before the next enemy action.
##
## targets: Array of Dictionary { "minion": MinionInstance, "stacks": int }.
## on_impact: Callable(minion: MinionInstance, stacks: int) -> void.
func play_corruption_detonations(targets: Array, on_impact: Callable) -> void:
	if _scene == null or vfx_controller == null:
		return
	var spawnable: Array = []
	for t in targets:
		var m: MinionInstance = t["minion"]
		var stacks: int = t["stacks"]
		var slot: BoardSlot = _scene._find_slot_for(m)
		if slot == null:
			on_impact.call(m, stacks)
		else:
			spawnable.append({"minion": m, "stacks": stacks, "slot": slot})
	if spawnable.is_empty():
		return

	_scene._on_play_vfx_active = true
	var remaining_ref: Array = [spawnable.size()]
	var scene := _scene

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
				scene._flush_deferred_deaths()
				scene._on_play_vfx_active = false
				scene.on_play_vfx_done.emit()
		, CONNECT_ONE_SHOT)
		vfx_controller.spawn(vfx)

## Feral Reinforcement (Act 2 passive) — radiant violet halo erupts from the
## summoned Human's slot, then a face-down card arcs toward the enemy hero
## panel's hand indicator and lands with a pulse on the hand count.
## Blocking: sets scene's `_on_play_vfx_active` and emits `on_play_vfx_done`
## when the FeralReinforcementVFX finishes, so EnemyAI awaits it before its
## next action (same pattern as Frenzied Imp Hurl).
##
## Visual implementation lives in FeralReinforcementVFX.gd; this wrapper
## resolves the slot/panel refs and owns the AI gate.
func play_feral_reinforcement_vfx(source: MinionInstance, _imp_card: CardData) -> void:
	if source == null or _scene == null or vfx_controller == null:
		return
	var slot: BoardSlot = _scene._find_slot_for(source)
	var enemy_panel: Control = _scene._enemy_hero_panel
	if slot == null or enemy_panel == null:
		return
	var ui_root: Node = _scene.get_node_or_null("UI")
	if ui_root == null:
		return

	_scene._on_play_vfx_active = true
	var vfx := FeralReinforcementVFX.create(slot, enemy_panel, ui_root, _scene)
	var scene := _scene
	vfx.finished.connect(func() -> void:
		scene._on_play_vfx_active = false
		scene.on_play_vfx_done.emit(),
		CONNECT_ONE_SHOT)
	vfx_controller.spawn(vfx)

# ─────────────────────────────────────────────────────────────────────────────
# Rune placement — generic VFX shared by every rune (player + enemy)
# ─────────────────────────────────────────────────────────────────────────────

## Hide the slot the rune just landed in so it reads as empty during the card
## preview and the VFX. Call right after `_update_trap_display()` so the slot
## never paints with the rune art before the VFX has revealed it. Paired with
## `play_rune_placement_vfx`, which fades the art in once the VFX finishes.
func hide_rune_slot_for_placement(trap: TrapCardData, owner: String) -> void:
	if _scene == null or trap == null or not trap.is_rune:
		return
	var slot_idx: int = _resolve_rune_slot_idx(owner)
	if slot_idx < 0:
		return
	var trap_env = _scene.trap_env_display
	if trap_env == null:
		return
	trap_env.hide_slot_for_placement(owner, slot_idx)

## Spawn the generic RunePlacementVFX on the trap slot the rune just landed in.
## The slot index is `active_traps.size() - 1` (the rune was already appended
## by the time this runs, on both sides). Tinted from `trap.rune_glow_color`
## with the rune's `battlefield_art_path` (if any) used for the stamp overlay.
##
## Blocking: sets `_on_play_vfx_active` and emits `on_play_vfx_done` when the
## VFX finishes, so EnemyAI's action loop awaits the placement read before
## continuing. On finish, calls `reveal_slot_after_placement` to re-render the
## slot with its real (rune-aware) styling and fade the art in.
func play_rune_placement_vfx(trap: TrapCardData, owner: String) -> void:
	if vfx_controller == null or _scene == null or trap == null or not trap.is_rune:
		return
	var slot_idx: int = _resolve_rune_slot_idx(owner)
	if slot_idx < 0:
		return
	var panels: Array = _scene.trap_slot_panels if owner == "player" else _scene.enemy_trap_slot_panels
	var panel: Panel = panels[slot_idx] as Panel
	if panel == null or not panel.is_inside_tree():
		return
	var art: Texture2D = null
	if trap.battlefield_art_path != "" and ResourceLoader.exists(trap.battlefield_art_path):
		art = load(trap.battlefield_art_path)
	_scene._on_play_vfx_active = true
	var vfx := RunePlacementVFX.create(panel, trap.rune_glow_color, art)
	var scene := _scene
	var captured_owner := owner
	var captured_idx := slot_idx
	vfx.finished.connect(func() -> void:
		var trap_env = scene.trap_env_display
		if trap_env != null:
			trap_env.reveal_slot_after_placement(captured_owner, captured_idx)
		scene._on_play_vfx_active = false
		scene.on_play_vfx_done.emit(),
		CONNECT_ONE_SHOT)
	vfx_controller.spawn(vfx)
	await vfx.finished

## Resolve the slot index of the most-recently-placed rune for the given side.
## Returns -1 if the side has no rune slots or the trap list is empty.
func _resolve_rune_slot_idx(owner: String) -> int:
	if _scene == null:
		return -1
	var panels: Array = _scene.trap_slot_panels if owner == "player" else _scene.enemy_trap_slot_panels
	if panels.is_empty():
		return -1
	var traps: Array
	if owner == "player":
		traps = _scene.active_traps
	elif _scene.enemy_ai != null:
		traps = _scene.enemy_ai.active_traps
	else:
		return -1
	var idx: int = traps.size() - 1
	if idx < 0 or idx >= panels.size():
		return -1
	return idx

# ─────────────────────────────────────────────────────────────────────────────
# Compound on-play / on-cast VFX with external callers (HardcodedEffects)
# ─────────────────────────────────────────────────────────────────────────────

## Spawn the Brood Call portal VFX at the first empty slot that will receive
## the summoned imp. Awaits the full VFX (ramp → hold → collapse) so the token
## is placed after the portal has closed.
##
## Also gates the AI: sets `_on_play_vfx_active` and emits `on_play_vfx_done`
## when the VFX finishes, so EnemyAI's commit_spell_cast awaits the portal
## before the next action. (The HardcodedEffects → EffectResolver chain doesn't
## propagate awaits, so the caller's `await _scene._play_brood_call_vfx(...)`
## alone isn't enough to block the AI loop.)
func play_brood_call_vfx(owner: String) -> void:
	if vfx_controller == null or _scene == null:
		return
	var slots: Array = _scene.player_slots if owner == "player" else _scene.enemy_slots
	var target_slot: BoardSlot = null
	for s: BoardSlot in slots:
		if s.is_empty():
			target_slot = s
			break
	if target_slot == null:
		return
	var vfx := SummonSigilVFX.create(target_slot, SummonSigilVFX.Flavor.BROOD)
	_scene._on_play_vfx_active = true
	var scene := _scene
	vfx.finished.connect(func() -> void:
		scene._on_play_vfx_active = false
		scene.on_play_vfx_done.emit(),
		CONNECT_ONE_SHOT)
	vfx_controller.spawn(vfx)
	await vfx.finished

## Spawn the Grafted Butcher ON PLAY VFX — graft tether from the sacrificed
## minion's slot into the Butcher, engorge flash, then a crimson cleaver wave
## sweeps across the enemy board. Awaits `impact_hit` so the caller can apply
## 200 AoE damage synced to the wave's peak.
func play_grafted_butcher_vfx(butcher: MinionInstance,
		sac_center: Vector2, butcher_owner: String) -> void:
	if vfx_controller == null or _scene == null:
		return
	var butcher_slot: BoardSlot = _scene._find_slot_for(butcher) if butcher else null
	var butcher_panel: Control = butcher_slot
	var target_board: Control = _scene.get_node("UI/EnemyBoard") if butcher_owner == "player" \
		else _scene.get_node("UI/PlayerBoard")
	var target_slots: Array = _scene._get_opponent_occupied_slots(butcher_owner)
	var vfx := GraftedButcherVFX.create(butcher_panel, sac_center, target_board, target_slots)
	vfx_controller.spawn(vfx)
	await vfx.impact_hit

## Spawn the Pack Frenzy warcry VFX from the caster's hero panel, sweeping
## across the given friendly Feral Imp slots. Awaits `impact_hit` so the caller
## can apply buffs synced to the first imp ignition. Tracked on the scene's
## `_pack_frenzy_active_vfx` field so VfxController can wait for the lingering
## glyphs before resuming enemy AI.
func play_pack_frenzy_vfx(owner: String, target_slots: Array,
		is_matriarch: bool) -> void:
	if vfx_controller == null or _scene == null or target_slots.is_empty():
		return
	var caster_panel: Control = _scene._player_hero_panel if owner == "player" else _scene._enemy_hero_panel
	if caster_panel == null:
		return
	var vfx := PackFrenzyVFX.create(caster_panel, target_slots, is_matriarch)
	vfx_controller.spawn(vfx)
	_pack_frenzy_active_vfx = vfx
	vfx.finished.connect(func() -> void:
		if _pack_frenzy_active_vfx == vfx:
			_pack_frenzy_active_vfx = null,
		CONNECT_ONE_SHOT)
	await vfx.impact_hit

## Spawn an ATK buff chevron next to a minion's ATK label. Used by Pack Frenzy
## since its VFX owns the full buff visual (the generic BuffApplyVFX — which
## normally spawns the chevron — is filtered out for source="pack_frenzy").
func spawn_atk_chevron(minion: MinionInstance) -> void:
	if minion == null or not is_instance_valid(minion) or _scene == null:
		return
	var slot: BoardSlot = _scene._find_slot_for(minion)
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

# ─────────────────────────────────────────────────────────────────────────────
# Champion summon entrance — banner + screen shake + gold flash + ripple
# ─────────────────────────────────────────────────────────────────────────────

## Dramatic entrance sequence for champion token summons.
## Shows card reveal → banner → screen shake → gold flash → place minion → fire trigger.
func champion_summon_sequence(card: MinionCardData, instance: MinionInstance, slot: BoardSlot) -> void:
	var owner: String = instance.owner

	# 1+2. Card reveal + "CHAMPION" banner shown together, held longer
	AudioManager.play_sfx("res://assets/audio/sfx/minions/champion_summon.wav")
	await show_champion_reveal_with_banner(card)
	if not is_inside_tree(): slot.place_minion(instance); return

	# 3. Place the minion on the slot
	slot.place_minion(instance)
	if state != null:
		state._log("  %s summoned!" % card.card_name, 1)  # PLAYER

	# 4. Fire summon trigger
	if state != null and state.trigger_manager != null:
		var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" \
			else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
		var ctx := EventContext.make(event, owner)
		ctx.minion = instance
		ctx.card = card
		state.trigger_manager.fire(ctx)

	# 5. Screen shake — shake the landed slot so the impact reads locally.
	await champion_screen_shake(slot)

	# 6. Gold flash on the slot + expanded ripple (ripple stays on scene since
	# it's used by non-champion card landings too).
	champion_slot_flash(slot)
	if _scene != null:
		_scene._spawn_slot_ripple(slot, 8, true)

## Card reveal + "CHAMPION" banner shown together, held long enough to read.
## Visual implementation lives in ChampionRevealVFX.gd; this wrapper resolves
## the UI root and awaits the VFX so callers (champion_summon_sequence) can
## chain placement + trigger fire after the reveal completes.
func show_champion_reveal_with_banner(card: CardData) -> void:
	if _scene == null or vfx_controller == null:
		return
	var ui_root: Node = _scene.get_node("UI")
	if ui_root == null:
		return
	var vfx := ChampionRevealVFX.create(card, ui_root)
	vfx_controller.spawn(vfx)
	await vfx.finished

## Screen shake for champion entrance. Heavy impact with decay.
## Target MUST be a Node2D/Control with a real position — pass the slot the
## champion landed on. Shaking $UI (a CanvasLayer) no-ops.
func champion_screen_shake(target: Node) -> void:
	if _scene == null:
		return
	await ScreenShakeEffect.shake(target, _scene, 18.0, 14)

## Gold flash overlay on a slot when a champion lands.
func champion_slot_flash(slot: BoardSlot) -> void:
	if _scene == null:
		return
	var ui_root: Node = _scene.get_node("UI")
	if ui_root == null:
		return
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.82, 0.25, 0.6)
	flash.set_size(slot.size)
	flash.global_position = slot.global_position
	flash.z_index = 3
	flash.z_as_relative = false
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(flash)
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(flash, "color:a", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# Primitives — slot/hero flash, damage popup, void-bolt projectiles
# ─────────────────────────────────────────────────────────────────────────────

const _POPUP_STACK_THRESHOLD := 50.0  # pixels — popups within this distance stack
const _POPUP_STACK_OFFSET := 30.0     # pixels — vertical offset per stacked popup
var _recent_popups: Array = []        # Array[{center: Vector2, time: float}]

## Brief red flash overlay on a slot when it takes damage.
func flash_slot(slot: BoardSlot) -> void:
	var tw := slot.create_tween()
	tw.tween_property(slot, "modulate", Color(1.8, 0.30, 0.30, 1.0), 0.06)
	tw.tween_property(slot, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.22)

## Flash a hero status panel and show a damage number.
## on_done (optional) is called after the flash animation completes.
## school is a DamageSchool int — VOID_BOLT (and any future VOID_BOLT sub-school) flashes purple.
func flash_hero(target: String, amount: int, on_done: Callable = Callable(),
		school: int = Enums.DamageSchool.NONE, is_crit: bool = false) -> void:
	if _scene == null:
		if on_done.is_valid():
			on_done.call()
		return
	var panel: Control = _scene._player_status_panel if target == "player" else _scene._enemy_status_panel
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

func flash_hero_heal(target: String, amount: int) -> void:
	if _scene == null:
		return
	var panel: Control = _scene._player_status_panel if target == "player" else _scene._enemy_status_panel
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

## Minion damage popups.
func spawn_damage_popup(screen_center: Vector2, damage: int, is_crit: bool = false) -> void:
	var txt := "-%d!" % damage if is_crit else "-%d" % damage
	_spawn_popup(screen_center, txt, Color(1.0, 0.22, 0.22, 1.0), is_crit)

## Spawn a popup immediately. If another popup is near the same position,
## offset this one downward so they don't overlap.
func _spawn_popup(center: Vector2, text: String, color: Color, is_crit: bool = false) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_recent_popups = _recent_popups.filter(func(e: Dictionary) -> bool:
		return now - (e.time as float) < 1.0)
	var stack_count := 0
	for entry in _recent_popups:
		if (entry.center as Vector2).distance_to(center) < _POPUP_STACK_THRESHOLD:
			stack_count += 1
	_recent_popups.append({"center": center, "time": now})
	var offset_center := center + Vector2(0, stack_count * _POPUP_STACK_OFFSET)
	_spawn_floating_popup(offset_center, text, color, is_crit)

func _spawn_floating_popup(screen_center: Vector2, text: String, color: Color, is_crit: bool = false) -> void:
	if _scene == null:
		return
	var lbl := Label.new()
	lbl.text = text
	var font_size: int = 44 if is_crit else 28
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_override("font", _DAMAGE_FONT)
	if is_crit:
		lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		lbl.add_theme_constant_override("shadow_offset_x", 3)
		lbl.add_theme_constant_override("shadow_offset_y", 3)
	lbl.z_index = 200
	var popup_parent: Node = _scene.get_node_or_null("PopupLayer")
	if popup_parent == null:
		popup_parent = _scene.get_node("UI")
	popup_parent.add_child(lbl)
	var text_size: Vector2 = lbl.get_minimum_size()
	lbl.size = text_size
	lbl.pivot_offset = text_size * 0.5
	lbl.position = screen_center - text_size * 0.5 + Vector2(randf_range(-12.0, 12.0), 0.0)
	if is_crit:
		var rise_end_y_c := maxf(lbl.position.y - 60.0, 16.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(lbl, "position:y", rise_end_y_c, 2.6) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(lbl, "modulate:a", 1.0, 0.4)
		var pop := create_tween()
		pop.tween_property(lbl, "scale", Vector2(1.5, 1.5), 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
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

## Spawn and fly a void bolt projectile to the enemy hero panel.
## Returns the bolt node (or null if not spawned) so caller can await impact_hit.
func fire_void_bolt_projectile(source_minion: MinionInstance = null, from_rune: bool = false) -> VoidBoltProjectile:
	if _scene == null or not _scene.is_inside_tree():
		return null
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var from_pos: Vector2
	if source_minion != null:
		var found := false
		for slot in _scene.player_slots:
			if (slot as BoardSlot).minion == source_minion:
				from_pos = (slot as BoardSlot).global_position + (slot as BoardSlot).size / 2.0
				found = true
				break
		if not found:
			from_pos = Vector2(vp_size.x / 2.0, vp_size.y - 120)
	elif from_rune:
		var rune_pos: Vector2 = _scene._find_void_rune_slot_position()
		if rune_pos != Vector2.ZERO:
			from_pos = rune_pos
		else:
			from_pos = Vector2(vp_size.x / 2.0, vp_size.y - 120)
	else:
		from_pos = Vector2(vp_size.x / 2.0, vp_size.y - 120)
	var to_pos: Vector2
	var enemy_panel: Control = _scene._enemy_status_panel
	if enemy_panel:
		to_pos = enemy_panel.global_position + enemy_panel.size / 2.0
	else:
		to_pos = Vector2(vp_size.x / 2.0, 80)
	var bolt := VoidBoltProjectile.create(from_pos, to_pos)
	if vfx_controller != null:
		vfx_controller.spawn(bolt)
	return bolt

## Spawn a void bolt projectile flying from enemy side down to the player hero.
func fire_enemy_void_bolt_projectile(source_minion: MinionInstance = null) -> VoidBoltProjectile:
	if _scene == null or not _scene.is_inside_tree():
		return null
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var from_pos: Vector2
	if source_minion != null:
		var found := false
		for slot in _scene.enemy_slots:
			if (slot as BoardSlot).minion == source_minion:
				from_pos = (slot as BoardSlot).global_position + (slot as BoardSlot).size / 2.0
				found = true
				break
		if not found:
			from_pos = Vector2(vp_size.x / 2.0, 200)
	elif _scene._enemy_hero_panel:
		from_pos = _scene._enemy_hero_panel.global_position + _scene._enemy_hero_panel.size / 2.0
	else:
		from_pos = Vector2(vp_size.x / 2.0, 200)
	var to_pos: Vector2
	var player_panel: Control = _scene._player_status_panel
	if player_panel:
		to_pos = player_panel.global_position + player_panel.size / 2.0
	else:
		to_pos = Vector2(vp_size.x / 2.0, vp_size.y - 120)
	var bolt := VoidBoltProjectile.create(from_pos, to_pos)
	if vfx_controller != null:
		vfx_controller.spawn(bolt)
	return bolt

# ─────────────────────────────────────────────────────────────────────────────
# Death animation — flash, soul-rise, on-death icon, deferred queue flush
# ─────────────────────────────────────────────────────────────────────────────

## Flash + dissolve upward death animation. Spawns a ghost overlay in $UI so
## the HBoxContainer layout is never disturbed. `pos` must be passed in by the
## caller (do not read slot.global_position here — slot may have just been
## reparented and layout recalculation is deferred).
##
## Ticks scene's `_active_death_anims` counter and emits `death_anims_done`
## when it drains to zero so end-turn / champion auto-summons can wait for
## kills to finish animating.
func animate_minion_death(slot: BoardSlot, pos: Vector2, dead_minion: MinionInstance = null) -> void:
	if _scene == null:
		return
	_scene._active_death_anims += 1
	await _animate_minion_death_body(slot, pos, dead_minion)
	_scene._active_death_anims -= 1
	if _scene._active_death_anims <= 0:
		_scene._active_death_anims = 0
		_scene.death_anims_done.emit()

func _animate_minion_death_body(slot: BoardSlot, pos: Vector2, dead_minion: MinionInstance = null) -> void:
	if _scene == null:
		return
	var ui_root: Node = _scene.get_node("UI")
	if ui_root == null:
		return
	# If this death was a sacrifice, wait for the ritual VFX to reach its
	# shatter beat before starting the ghost rise — the soul leaves with
	# the motes, not while the sigil is still blooming.
	if dead_minion != null:
		var id: int = dead_minion.get_instance_id()
		if _scene._pending_sacrifice_ghost_delay.has(id):
			var delay: float = float(_scene._pending_sacrifice_ghost_delay[id])
			_scene._pending_sacrifice_ghost_delay.erase(id)
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
	ui_root.add_child(ghost)
	ghost.set_size(sz)
	ghost.pivot_offset = sz / 2.0
	ghost.global_position = pos

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
	ui_root.add_child(soul)
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
	if dead_minion != null and minion_has_on_death(dead_minion):
		if not is_inside_tree(): return
		var icon_vfx := OnDeathIconVFX.create(pos, sz)
		if vfx_controller != null:
			vfx_controller.spawn(icon_vfx)
		await icon_vfx.finished
		# Void-Touched Imp: AoE death explosion VFX before damage resolves
		if dead_minion.card_data.id == "void_touched_imp":
			if not is_inside_tree(): return
			var origin_center: Vector2 = pos + sz * 0.5
			var opponent_slots: Array = _scene._get_opponent_occupied_slots(dead_minion.owner)
			var opponent_board: Control = _scene.get_node("UI/EnemyBoard") if dead_minion.owner == "player" \
				else _scene.get_node("UI/PlayerBoard")
			var death_vfx := VoidTouchedImpDeathVFX.create(origin_center, opponent_slots, opponent_board)
			if vfx_controller != null:
				vfx_controller.spawn(death_vfx)
			await death_vfx.impact_hit
			if not is_inside_tree(): return
		# Resolve deferred on-death effects now that the icon has faded
		resolve_deferred_on_death(dead_minion)

## Returns true if a minion has any on-death effects (steps or granted).
func minion_has_on_death(minion: MinionInstance) -> bool:
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
func resolve_deferred_on_death(minion: MinionInstance) -> void:
	if _scene == null:
		return
	_scene._pending_on_death_vfx.erase(minion)
	if not is_inside_tree():
		return
	if _scene._handlers != null:
		_scene._handlers._resolve_on_death(minion)

## Fire death animations queued during freeze_visuals. Called by VfxController
## (via scene's wrapper) after a damaging spell VFX finishes, and by
## _restore_slot_from_lunge after a lunge completes. Captured positions are
## used so the ghost lines up with the slot's original spot (not its
## post-lunge location).
func flush_deferred_deaths() -> void:
	if _scene == null:
		return
	var queue: Array = _scene._deferred_death_slots
	if queue.is_empty():
		return
	var pending := queue.duplicate()
	queue.clear()
	for entry in pending:
		var slot: BoardSlot = entry.slot
		# Slot visuals were held during the freeze — clear the art so the
		# ghost rises from an empty slot.
		if slot != null and slot.minion != null:
			slot.remove_minion()
		animate_minion_death(slot, entry.pos, entry.get("minion"))

# ─────────────────────────────────────────────────────────────────────────────
# Card-cast presentation — preview, countered, enemy summon reveal
# ─────────────────────────────────────────────────────────────────────────────

const _DAMAGE_FONT: Font = preload("res://assets/fonts/cinzel/Cinzel-Bold.ttf")

## Show large card preview while a spell resolves. Animates in → calls
## on_impact → holds → fades out. Pass Callable() for on_impact when there
## are no effects to delay.
func show_card_cast_anim(card: CardData, is_enemy: bool, on_impact: Callable) -> void:
	if _scene == null:
		return
	var ui_root: Node = _scene.get_node("UI")
	if ui_root == null:
		return
	# Spell-only casting windup glyph at the caster position.
	if card is SpellCardData:
		_spawn_casting_windup(is_enemy)
	var cv: CardVisual = preload("res://combat/ui/CardVisual.tscn").instantiate() as CardVisual
	cv.apply_size_mode("combat_preview")
	cv.z_index = 100
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(cv)
	cv.setup(card)
	var vp      := get_viewport().get_visible_rect().size
	var card_sz := Vector2(336.0, 504.0)
	cv.position     = (vp - card_sz) * 0.5
	cv.pivot_offset = card_sz * 0.5
	cv.modulate = Color(1.0, 1.0, 1.0, 0.0)
	cv.scale = Vector2(0.65, 0.65)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cv, "modulate:a", 1.0, 0.22)
	tw.tween_property(cv, "scale", Vector2(1.0, 1.0), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(0.63)
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
		var act: int = GameManager.get_current_act() if GameManager else 3
		match act:
			1: faction = "feral"
			2: faction = "corrupted"
			_: faction = "abyss"
		var enemy_panel: Control = _scene._enemy_hero_panel if _scene != null else null
		if enemy_panel != null and enemy_panel.is_inside_tree():
			center = enemy_panel.global_position + enemy_panel.size * 0.5
		else:
			var vp := get_viewport().get_visible_rect().size
			center = Vector2(vp.x * 0.5, 120.0)
	else:
		faction = "void"
		var vp2 := get_viewport().get_visible_rect().size
		center = Vector2(vp2.x * 0.5, vp2.y - 100.0)
	var windup := CastingWindupVFX.create(faction, center, is_enemy)
	if vfx_controller != null:
		vfx_controller.spawn(windup)

## "COUNTERED!" animation: card appears, gets a red overlay + shake, fizzles out.
func show_spell_countered_anim(card: CardData) -> void:
	if _scene == null:
		return
	var ui_root: Node = _scene.get_node("UI")
	if ui_root == null:
		return
	var cv: CardVisual = preload("res://combat/ui/CardVisual.tscn").instantiate() as CardVisual
	cv.apply_size_mode("combat_preview")
	cv.z_index = 100
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(cv)
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
	counter_lbl.add_theme_font_override("font", _DAMAGE_FONT)
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
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cv, "modulate:a", 1.0, 0.22)
	tw.tween_property(cv, "scale", Vector2(1.0, 1.0), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(0.12)
	tw.tween_callback(func() -> void:
		counter_lbl.modulate = Color(1, 1, 1, 1)
	)
	tw.set_parallel(true)
	tw.tween_property(cv, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.15)
	tw.tween_property(counter_lbl, "scale", Vector2(1.2, 1.2), 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	var base_x := cv.position.x
	for i in 4:
		var offset_x := 12.0 if i % 2 == 0 else -12.0
		tw.tween_property(cv, "position:x", base_x + offset_x, 0.05)
	tw.tween_property(cv, "position:x", base_x, 0.05)
	tw.tween_interval(0.5)
	tw.set_parallel(true)
	tw.tween_property(cv, "modulate:a", 0.0, 0.35)
	tw.tween_property(cv, "scale", Vector2(0.7, 0.7), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(cv.queue_free)

## Big-card reveal whenever the enemy summons a new minion. Caller toggles
## scene._enemy_summon_reveal_active around the call so EnemyAI can wait.
## Uses the same "combat_preview" size mode as the hover preview.
## Returns after the fade-out so callers can await it.
func show_enemy_summon_reveal(card: CardData) -> void:
	if _scene == null:
		return
	var ui_root: Node = _scene.get_node("UI")
	if ui_root == null:
		return
	_scene._enemy_summon_reveal_active = true
	var visual: CardVisual = preload("res://combat/ui/CardVisual.tscn").instantiate()
	visual.apply_size_mode("combat_preview")
	visual.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	visual.z_index       = 20
	visual.z_as_relative = false
	visual.modulate.a    = 0.0
	ui_root.add_child(visual)
	visual.setup(card)
	var vp := get_viewport().get_visible_rect().size
	visual.position     = vp / 2.0 - visual.size / 2.0
	visual.pivot_offset = visual.size * 0.5
	visual.scale        = Vector2(0.65, 0.65)

	var t1 := create_tween().set_parallel(true)
	t1.tween_property(visual, "modulate:a", 1.0, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t1.tween_property(visual, "scale", Vector2(1.0, 1.0), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t1.finished
	if not is_inside_tree():
		visual.queue_free()
		_scene._enemy_summon_reveal_active = false
		_scene.enemy_summon_reveal_done.emit()
		return

	await get_tree().create_timer(0.9).timeout
	if not is_inside_tree():
		visual.queue_free()
		_scene._enemy_summon_reveal_active = false
		_scene.enemy_summon_reveal_done.emit()
		return

	var t2 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t2.tween_property(visual, "modulate:a", 0.0, 0.22)
	await t2.finished
	visual.queue_free()
	_scene._enemy_summon_reveal_active = false
	# Do NOT emit enemy_summon_reveal_done here — scene's _enemy_summon_reveal_then_land
	# emits it after slot.place_minion() so the AI never acts before the minion lands.

## Shared tail of every sigil-style summon: unfreeze the slot, fade the
## minion in, log, fire ON_*_MINION_SUMMONED. Pulled out so the three
## variants above don't repeat 10 lines verbatim.
func _reveal_after_sigil(slot: BoardSlot, data: MinionCardData,
		instance: MinionInstance, owner: String) -> void:
	slot.freeze_visuals = false
	slot.modulate.a = 0.0
	slot._refresh_visuals()
	var fade := create_tween()
	fade.tween_property(slot, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if state != null:
		state._log("  %s summoned!" % data.card_name, 1)  # PLAYER
		if state.trigger_manager != null:
			var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" \
				else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
			var ctx := EventContext.make(event, owner)
			ctx.minion = instance
			ctx.card = data
			state.trigger_manager.fire(ctx)
