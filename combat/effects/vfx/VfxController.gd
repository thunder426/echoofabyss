## VfxController.gd
## Orchestrates VFX for combat — owns spell dispatch, target freeze, damage
## sync, and deferred death flush. Lives as a child of CombatScene.
##
## Before this controller:
##   CombatScene._apply_targeted_spell and _on_enemy_spell_cast each held
##   per-spell branches that created the VFX, picked a parent ($UI vs self),
##   awaited impact_hit, resolved damage, optionally froze the slot + awaited
##   finished + flushed _deferred_death_slots. ~40 lines duplicated twice.
##
## After:
##   CombatScene builds a `resolve_damage` Callable and calls
##   `vfx_controller.play_spell(spell_id, caster_side, target, resolve_damage)`.
##   The controller:
##     1. Freezes target slot(s) — makes ghost-over-empty-slot impossible.
##     2. Spawns the VFX under CombatScene.VfxLayer (layer 2 — above UI).
##     3. Awaits vfx.impact_hit(i) and fires resolve_damage.call(i).
##     4. Awaits vfx.finished.
##     5. Unfreezes slots + calls CombatScene._flush_deferred_deaths().
##
## Adding a new spell VFX: add a private `_play_*` method below and wire it in
## play_spell(). CombatScene does not change.
class_name VfxController
extends Node

## CombatScene — set via setup(). Used for _find_slot_for, hero panels,
## _flush_deferred_deaths, and the VfxLayer reference.
var _combat: Node2D = null
var _vfx_layer: CanvasLayer = null
var _shake_root: Control = null

## Resolve nodes from the scene. Called from CombatScene._find_nodes.
func setup(combat: Node2D, vfx_layer: CanvasLayer, shake_root: Control) -> void:
	_combat = combat
	_vfx_layer = vfx_layer
	_shake_root = shake_root

## Public entry — parent this VFX under the shared VfxLayer.
## Use from places that spawn VFX without the full spell-dispatch wrapper
## (e.g. OnDeathIcon, VoidMarkApply, etc.).
func spawn(vfx: Node) -> void:
	if _vfx_layer == null:
		push_error("VfxController.spawn: VfxLayer not set")
		return
	_vfx_layer.add_child(vfx)

## Dispatch a damaging spell VFX. Builds the target slot list, freezes slots
## (if applicable), plays the VFX, resolves damage on impact, unfreezes, and
## flushes deferred deaths.
##
## target: MinionInstance, Control (hero panel), or null for AoE spells that
##         compute their own targets.
## resolve_damage: Callable(index: int) -> void. Called once per impact_hit.
##                 For single-target spells, index is always 0.
func play_spell(spell_id: String, caster_side: String, target: Variant, resolve_damage: Callable) -> void:
	if _vfx_layer == null or _combat == null:
		push_error("VfxController.play_spell: not set up")
		resolve_damage.call(0)
		return
	match spell_id:
		"arcane_strike":
			await _play_arcane_strike(target, resolve_damage)
		"void_execution":
			await _play_void_execution(caster_side, target, resolve_damage)
		"void_screech":
			await _play_void_screech(caster_side, resolve_damage)
		"abyssal_plague":
			# Plague resolves damage per-minion internally (the callback per
			# impact_hit), so the caller's resolve_damage is ignored.
			await _play_abyssal_plague(caster_side)
		"pack_frenzy":
			# Pack Frenzy's VFX is spawned inside the hardcoded effect (it
			# needs the list of feral imp targets). resolve_damage kicks off
			# that effect chain; then we await the tracked VFX so the enemy
			# AI's next move waits for the full visual to finish.
			resolve_damage.call(0)
			var vfx: PackFrenzyVFX = _combat._pack_frenzy_active_vfx
			if vfx != null and is_instance_valid(vfx):
				await vfx.finished
		_:
			resolve_damage.call(0)


# ═════════════════════════════════════════════════════════════════════════════
# Per-spell dispatch
# ═════════════════════════════════════════════════════════════════════════════

func _play_arcane_strike(target: Variant, resolve_damage: Callable) -> void:
	var slot: BoardSlot = _combat._find_slot_for(target) if target is MinionInstance else null
	if slot == null:
		resolve_damage.call(0)
		return
	slot.freeze_visuals = true
	var vfx := ArcaneStrikeVFX.create(slot)
	_vfx_layer.add_child(vfx)
	await vfx.impact_hit
	resolve_damage.call(0)
	await vfx.finished
	slot.freeze_visuals = false
	slot._refresh_visuals()
	_combat._flush_deferred_deaths()

func _play_void_execution(caster_side: String, target: Variant, resolve_damage: Callable) -> void:
	var target_pos: Vector2
	var shake_target: Node = null
	var size_scale: float = 1.0
	if target is MinionInstance:
		var slot: BoardSlot = _combat._find_slot_for(target)
		if slot == null:
			resolve_damage.call(0)
			return
		target_pos = slot.get_global_rect().get_center()
		shake_target = slot
	elif target is Control:
		# Hero panel — offset downward a bit (matches old enemy-cast path)
		var panel := target as Control
		target_pos = panel.global_position + panel.size / 2.0 + Vector2(0, 30)
		size_scale = 0.55
		shake_target = panel
	else:
		resolve_damage.call(0)
		return
	# Void Execution's current impact is visually immediate — no freeze needed.
	var vfx := VoidExecutionVFX.create(target_pos, size_scale, shake_target)
	_vfx_layer.add_child(vfx)
	await vfx.impact_hit
	resolve_damage.call(0)

func _play_void_screech(caster_side: String, resolve_damage: Callable) -> void:
	var target_panel: Control = _combat._enemy_status_panel if caster_side == "player" else _combat._player_status_panel
	if target_panel == null:
		resolve_damage.call(0)
		return
	var caster_slots: Array[BoardSlot] = _combat.player_slots if caster_side == "player" else _combat.enemy_slots
	# Chorus mode: one wave per feral imp if 3+ are present.
	var feral_slots: Array[BoardSlot] = []
	for s in caster_slots:
		if s.minion != null and _combat._minion_has_tag(s.minion, "feral_imp"):
			feral_slots.append(s)
	var sources: Array = []
	if feral_slots.size() >= 3:
		for s in feral_slots:
			sources.append(s.global_position + s.size * 0.5)
	else:
		var center := Vector2.ZERO
		var count := 0
		for s in caster_slots:
			center += s.global_position + s.size * 0.5
			count += 1
		if count > 0:
			sources.append(center / float(count))
	var vfx := VoidScreechVFX.create(sources, target_panel)
	_vfx_layer.add_child(vfx)
	await vfx.impact_hit
	resolve_damage.call(0)
	await vfx.finished

func _play_abyssal_plague(caster_side: String) -> void:
	# Plague damage is staggered per-minion, timed to the visual wave front.
	# The VFX itself fires a per-minion callback at arrival (impact_count=0),
	# so damage resolves from inside the VFX rather than via impact_hit gating.
	var all_slots: Array = _combat.enemy_slots if caster_side == "player" else _combat.player_slots
	var occupied: Array = []
	for s in all_slots:
		if (s as BoardSlot).minion != null:
			occupied.append(s)
	var caster_panel: Control = _combat._player_status_panel if caster_side == "player" else _combat._enemy_status_panel
	var combat := _combat
	# Plague's EffectStep declares damage_school=VOID, but this VFX path bypasses
	# EffectResolver so the school must be re-stated here. Keep in sync with the
	# abyssal_plague spell definition in CardDatabase.gd.
	var plague_info := CombatManager.make_damage_info(0, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID, null, "abyssal_plague")
	var per_minion_cb := func(m: MinionInstance) -> void:
		if m == null or m.current_health <= 0:
			return
		combat._corrupt_minion(m)
		combat._spell_dmg(m, 100, plague_info)
	var vfx := AbyssalPlagueVFX.create(caster_panel, caster_side, all_slots, occupied, per_minion_cb)
	_vfx_layer.add_child(vfx)
	await vfx.finished
