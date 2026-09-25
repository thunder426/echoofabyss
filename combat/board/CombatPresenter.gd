## CombatPresenter.gd
## Plays the combat journal (LIVE_SIM_UNIFICATION_PLAN.md 3.2).
##
## The engine mutates synchronously and appends one CombatEvent per mutation.
## This node drains that journal one event at a time: for each event it plays
## the matching animation (awaiting it), then applies the event to the lagging
## ViewState and refreshes the UI. Nothing on screen changes before the event
## that explains it has been played; nothing here mutates gameplay.
##
## Draining starts deferred (end of frame) so a synchronous resolution — a
## whole spell, an attack with its counter — is fully journaled before its
## first event plays, which lets a few players look ahead: an attack consumes
## the damage events that follow it and shows them at the lunge's hit, a spell
## consumes its damage / corruption events and shows them at its VFX impact.
##
## `idle` fires whenever the queue empties; `pump_and_wait_idle()` is what the
## enemy turn, end-turn and tests wait on. `instant` skips every animation.
class_name CombatPresenter
extends Node

signal idle

var scene: Node = null
var state: CombatState = null
var view: ViewState = ViewState.new()
var cursor: int = 0
var instant: bool = false

var _draining: bool = false
var _start_queued: bool = false
var _consumed: Dictionary = {}        # seq → true: played early by a look-ahead
var _flights: Dictionary = {}         # CardInstance.instance_id → {visual, hand_index}
var _spell_pending: Array = []        # captured events of the spell being played

const _LOOKAHEAD_STOP: Array = [
	CombatEvent.Kind.ATTACK_STARTED, CombatEvent.Kind.SPELL_CAST, CombatEvent.Kind.MINION_PLAYED,
	CombatEvent.Kind.TURN_ENDED, CombatEvent.Kind.TURN_STARTED, CombatEvent.Kind.COMBAT_ENDED,
	CombatEvent.Kind.COMMAND,
]

## The beat between two enemy actions (and once more before its first attack),
## so consecutive moves read as separate. The enemy decides its turn at once;
## this is where it is paced.
const ENEMY_ACTION_DELAY := 0.55

var _enemy_actions: int = 0          # enemy commands played this enemy turn
var _enemy_attacking: bool = false   # an attack command has played this turn
var _enemy_last_cmd: String = ""


func setup(p_scene: Node, p_state: CombatState) -> void:
	scene = p_scene
	state = p_state
	view.sync_from(state)
	if not state.journaled.is_connected(_on_journaled):
		state.journaled.connect(_on_journaled)


# ---------------------------------------------------------------------------
# Pumping
# ---------------------------------------------------------------------------

func _on_journaled(_ev: CombatEvent) -> void:
	pump()


## Schedule a drain (end of frame) unless one is running or scheduled.
func pump() -> void:
	if _draining or _start_queued:
		return
	_start_queued = true
	call_deferred("_start_drain")


func _start_drain() -> void:
	_start_queued = false
	if _draining:
		return
	_drain()


func is_idle() -> bool:
	return not _draining and not _start_queued and state != null and cursor >= state.journal.size()


## Wait until every journaled event has been played.
func pump_and_wait_idle() -> void:
	pump()
	while not is_idle():
		await idle


func _drain() -> void:
	_draining = true
	while state != null and cursor < state.journal.size():
		var ev: CombatEvent = state.journal[cursor]
		cursor += 1
		var early: bool = _consumed.has(ev.seq)
		if early:
			_consumed.erase(ev.seq)
		if not early and not instant and is_inside_tree() and scene != null and is_instance_valid(scene):
			await _play(ev)
			if not is_inside_tree() or scene == null or not is_instance_valid(scene):
				break
		view.apply(ev)
		_emit_ui(ev)
	_draining = false
	idle.emit()


# ---------------------------------------------------------------------------
# Input-side registrations
# ---------------------------------------------------------------------------

## The hand visual popped for a minion play: MINION_PLAYED flies it to the slot.
func register_flight(inst: CardInstance, visual: CardVisual, hand_index: int) -> void:
	if inst == null or visual == null:
		return
	_flights[inst.instance_id] = {visual = visual, hand_index = hand_index}


func take_flight(inst: CardInstance) -> Dictionary:
	if inst == null or not _flights.has(inst.instance_id):
		return {}
	var f: Dictionary = _flights[inst.instance_id]
	_flights.erase(inst.instance_id)
	return f


# ---------------------------------------------------------------------------
# Look-ahead helpers
# ---------------------------------------------------------------------------

## The events after the cursor up to (not including) the first structural one.
func _peek_window(limit: int = 60) -> Array:
	var out: Array = []
	var i: int = cursor
	while i < state.journal.size() and out.size() < limit:
		var ev: CombatEvent = state.journal[i]
		if ev.kind in _LOOKAHEAD_STOP:
			break
		out.append(ev)
		i += 1
	return out


func _consume(ev: CombatEvent) -> void:
	_consumed[ev.seq] = true


static func _is_minion_damage(ev: CombatEvent, m: MinionInstance) -> bool:
	return ev.kind == CombatEvent.Kind.DAMAGE_DEALT and ev.payload.get("kind", "") == "minion" and ev.payload.get("minion", null) == m


static func _is_hero_damage(ev: CombatEvent, side: String) -> bool:
	return ev.kind == CombatEvent.Kind.DAMAGE_DEALT and ev.payload.get("kind", "") == "hero" and ev.side == side


# ---------------------------------------------------------------------------
# Playback
# ---------------------------------------------------------------------------

func _play(ev: CombatEvent) -> void:
	match ev.kind:
		CombatEvent.Kind.MINION_PLAYED:
			await _play_minion_played(ev)
		CombatEvent.Kind.TOKEN_SUMMONED, CombatEvent.Kind.CHAMPION_SUMMONED, CombatEvent.Kind.MINION_SUMMONED:
			await _play_summon(ev)
		CombatEvent.Kind.MINION_DIED, CombatEvent.Kind.MINION_SACRIFICED, CombatEvent.Kind.MINION_CONSUMED:
			await _play_death(ev)
		CombatEvent.Kind.DAMAGE_DEALT:
			_play_damage(ev)
		CombatEvent.Kind.HERO_HEALED:
			scene._flash_hero_heal(ev.side, ev.payload.get("amount", 0))
		CombatEvent.Kind.MINION_HEALED:
			var node: BoardSlot = scene._find_slot_for(ev.payload.get("minion", null))
			if node != null:
				node.refresh_stats_only()
		CombatEvent.Kind.BUFF_APPLIED:
			await _play_buffs(ev)
		CombatEvent.Kind.CORRUPTION_APPLIED:
			var node: BoardSlot = scene._find_slot_for(ev.payload.get("minion", null))
			if node != null:
				scene._play_corruption_apply_visual(node)
		CombatEvent.Kind.DETONATION:
			await _play_detonations(ev)
		CombatEvent.Kind.VOID_BOLT:
			await _play_void_bolt(ev)
		CombatEvent.Kind.VOID_MARKS_CHANGED:
			if ev.payload.get("value", 0) > view.enemy_void_marks:
				scene._show_void_mark_applied()
		CombatEvent.Kind.TRAP_FIRED:
			await scene.play_trap_reveals(ev.side, [{trap = ev.payload["trap"], slot_index = ev.payload.get("slot", 0)}])
		CombatEvent.Kind.TRAP_PLACED, CombatEvent.Kind.RUNE_PLACED:
			await _play_trap_placed(ev)
		CombatEvent.Kind.ENVIRONMENT_CHANGED:
			if ev.side == "player" and ev.payload.get("env", null) != null:
				await _cast_anim(ev.payload["env"], false)
		CombatEvent.Kind.SPELL_CAST:
			await _play_spell(ev)
		CombatEvent.Kind.SPELL_COUNTERED:
			scene._show_spell_countered_anim(ev.payload["spell"])
			scene._update_counter_warning()
			await _wait(0.3)
		CombatEvent.Kind.RITUAL_FIRED:
			var capture: Dictionary = scene._capture_ritual_visual(ev.payload.get("slots", []), ev.payload.get("runes", []))
			if not capture.is_empty():
				await scene._run_ritual_visual(capture)
		CombatEvent.Kind.ATTACK_STARTED:
			await _play_attack(ev)
		CombatEvent.Kind.PHASE_TRANSITION:
			scene._enemy_hero_panel.update(state.enemy_hp, state.enemy_hp_max, state, state.enemy_void_marks)
		CombatEvent.Kind.COMBAT_ENDED:
			if ev.payload.get("winner", "") == "player":
				scene._on_victory()
			else:
				scene._on_defeat()
		CombatEvent.Kind.VFX:
			await _play_vfx(ev)
		CombatEvent.Kind.COMMAND:
			await _pace_command(ev)
		CombatEvent.Kind.TURN_STARTED:
			_enemy_actions = 0
			_enemy_attacking = false
			_enemy_last_cmd = ""
		_:
			pass


## A beat before each enemy action after the first — none after spark fuel, which
## belongs to the play it pays for — and one more before its first attack after
## plays (the old play-phase / attack-phase gap).
func _pace_command(ev: CombatEvent) -> void:
	if ev.side != "enemy":
		return
	var cmd: String = ev.payload.get("cmd", "")
	var gap: float = 0.0
	if _enemy_actions > 0 and _enemy_last_cmd != "consume_minion":
		gap += ENEMY_ACTION_DELAY
	var attack: bool = cmd == "attack" or cmd == "attack_hero"
	if attack and not _enemy_attacking and _enemy_actions > 0:
		gap += ENEMY_ACTION_DELAY
	_enemy_attacking = _enemy_attacking or attack
	_enemy_actions += 1
	_enemy_last_cmd = cmd
	await _wait(gap)


## Card flight (player, from the popped hand visual) or the enemy reveal, then
## the landing punch. The engine already owns the slot; the node shows the
## minion at landing.
func _play_minion_played(ev: CombatEvent) -> void:
	var m: MinionInstance = ev.payload.get("minion", null)
	var node: BoardSlot = scene.slot_node(ev.side, ev.payload.get("slot", -1))
	if m == null or node == null:
		return
	var card: MinionCardData = m.card_data as MinionCardData
	var total_cost: int = card.essence_cost + card.mana_cost
	if ev.side == "player":
		var flight: Dictionary = take_flight(ev.payload.get("inst", null))
		if not flight.is_empty():
			await scene._animate_card_to_slot(flight["visual"], node, flight["hand_index"], total_cost, card.is_champion,
					func() -> void: node.show_minion(m))
		else:
			node.show_minion(m)
			await scene._animate_enemy_landing(node, total_cost, card.is_champion)
	else:
		await scene._show_enemy_summon_reveal(card)
		if not is_inside_tree():
			return
		AudioManager.play_sfx("res://assets/audio/sfx/minions/minion_summon.wav", -20.0)
		node.show_minion(m)
		await scene._animate_enemy_landing(node, total_cost, card.is_champion)
		if is_inside_tree():
			CardVfxRegistry.play_enemy_summon_reveal_extra(scene.vfx_controller, m, node, state.enemy_passives)
	if is_inside_tree():
		scene._maybe_spawn_aura_pulse(card, node)


## Champion banner, sigil reveal, or a plain show.
func _play_summon(ev: CombatEvent) -> void:
	var m: MinionInstance = ev.payload.get("minion", null)
	var node: BoardSlot = scene.slot_node(ev.side, ev.payload.get("slot", -1))
	if m == null or node == null:
		return
	var card: MinionCardData = m.card_data as MinionCardData
	if scene.vfx_bridge != null and card.is_champion and ev.kind != CombatEvent.Kind.MINION_SUMMONED:
		node.freeze_visuals = true
		node.show_minion(m)
		await scene.vfx_bridge.champion_summon_sequence(card, m, node)
		return
	if scene.vfx_bridge != null and CardVfxRegistry.has_token_summon(card.id):
		node.freeze_visuals = true
		node.show_minion(m)
		await CardVfxRegistry.play_token_summon(scene.vfx_bridge, card.id, m, card, node, ev.side)
		return
	node.freeze_visuals = false
	node.show_minion(m)


## Death / sacrifice ghost. The node still shows the minion (its slot-clear
## event follows this one); the ghost rises from the emptied slot.
func _play_death(ev: CombatEvent) -> void:
	var m: MinionInstance = ev.payload.get("minion", null)
	var node: BoardSlot = scene.slot_node(ev.side, ev.payload.get("slot", -1))
	if m == null or node == null:
		return
	if ev.kind == CombatEvent.Kind.MINION_SACRIFICED and scene.vfx_controller != null and node.minion == m:
		scene._on_sacrifice_occurred(m, ev.payload.get("source_tag", ""))
		await _wait(SacrificeVFX.MINION_VISIBLE_DURATION + SacrificeVFX.MINION_FADE_DURATION)
		scene._pending_sacrifice_ghost_delay.erase(m.get_instance_id())
	if not is_inside_tree():
		return
	var pos: Vector2 = node.global_position
	var shown: bool = node.minion == m
	if shown:
		node.show_empty()
	if ev.kind == CombatEvent.Kind.MINION_CONSUMED or not shown:
		return
	await scene._animate_minion_death(node, pos, m)


## An unconsumed damage event: slot flash + popup + HP tween, or the hero flash.
func _play_damage(ev: CombatEvent) -> void:
	var p: Dictionary = ev.payload
	if p.get("kind", "") == "hero":
		scene._flash_hero(ev.side, p.get("amount", 0), Callable(), p.get("school", Enums.DamageSchool.NONE), p.get("is_crit", false))
		return
	var m: MinionInstance = p.get("minion", null)
	var node: BoardSlot = scene._find_slot_for(m)
	if node == null:
		return
	scene._flash_slot(node)
	scene._spawn_damage_popup(node.get_global_rect().get_center(), p.get("amount", 0), p.get("is_crit", false), p.get("school", Enums.DamageSchool.NONE))
	node.animate_hp_change(p.get("hp_before", 0), p.get("hp_after", 0))


## Consecutive buff events play as one batch (one BuffApplyVFX per minion +
## source, all in parallel), then the batch is awaited.
func _play_buffs(first: CombatEvent) -> void:
	var batch: Array = [first]
	for ev in _peek_window():
		if ev.kind == CombatEvent.Kind.BUFF_APPLIED:
			batch.append(ev)
			_consume(ev)
		elif ev.kind != CombatEvent.Kind.MINION_STATS_CHANGED and ev.kind != CombatEvent.Kind.LOG:
			break
	var any: bool = false
	for ev in batch:
		var p: Dictionary = ev.payload
		if p.get("silent", false):
			continue
		scene._show_buff_apply(p.get("minion", null), p.get("source_tag", ""), p.get("atk_before", 0), p.get("hp_before", 0))
		any = true
	if not any:
		return
	await get_tree().process_frame
	if is_inside_tree() and scene._active_buff_vfx_count > 0:
		await scene.buff_vfx_batch_done


func _play_detonations(first: CombatEvent) -> void:
	var targets: Array = [{minion = first.payload["minion"], stacks = first.payload.get("stacks", 1)}]
	for ev in _peek_window():
		if ev.kind == CombatEvent.Kind.DETONATION:
			targets.append({minion = ev.payload["minion"], stacks = ev.payload.get("stacks", 1)})
			_consume(ev)
		elif ev.kind != CombatEvent.Kind.LOG:
			break
	await scene._play_corruption_detonations(targets)


## Projectile to the hero; the hero's damage event (which follows) shows at impact.
func _play_void_bolt(ev: CombatEvent) -> void:
	var target_side: String = "enemy" if ev.side == "player" else "player"
	var hit: CombatEvent = null
	for e in _peek_window(8):
		if _is_hero_damage(e, target_side):
			hit = e
			_consume(e)
			break
	var bolt: VoidBoltProjectile = null
	if ev.side == "player":
		bolt = scene._fire_void_bolt_projectile(ev.payload.get("source_minion", null), ev.payload.get("from_rune", false))
	else:
		bolt = scene._fire_enemy_void_bolt_projectile(ev.payload.get("source_minion", null))
	if bolt != null and is_inside_tree():
		await bolt.impact_hit
	if hit != null and is_inside_tree():
		_play_damage(hit)


func _play_trap_placed(ev: CombatEvent) -> void:
	var trap: TrapCardData = ev.payload["trap"]
	var is_enemy: bool = ev.side == "enemy"
	if trap.is_rune and scene.vfx_bridge != null:
		scene.vfx_bridge.hide_rune_slot_for_placement(trap, ev.side)
	if not is_enemy:
		await _cast_anim(trap, false)
	if trap.is_rune and scene.vfx_bridge != null and is_inside_tree():
		await scene.vfx_bridge.play_rune_placement_vfx(trap, ev.side)


## Cast animation, then the spell's VFX; the spell's damage / corruption /
## heal events (captured up to SPELL_RESOLVED) show at the VFX impact — or per
## slot as a wave touches it (play_captured_for_slot) — and any left over play
## after the VFX.
func _play_spell(ev: CombatEvent) -> void:
	var spell: SpellCardData = ev.payload["spell"]
	var target: Variant = ev.payload.get("target", null)
	var is_enemy: bool = ev.side == "enemy"
	var captured: Array = []
	var i: int = cursor
	var prev_kind: int = -1
	while i < state.journal.size():
		var e: CombatEvent = state.journal[i]
		i += 1
		if e.kind == CombatEvent.Kind.SPELL_RESOLVED and e.payload.get("spell", null) == spell:
			break
		if e.kind == CombatEvent.Kind.SPELL_CAST or e.kind == CombatEvent.Kind.ATTACK_STARTED:
			break
		var capture: bool = false
		if e.kind == CombatEvent.Kind.DAMAGE_DEALT:
			capture = prev_kind != CombatEvent.Kind.VOID_BOLT
		elif e.kind in [CombatEvent.Kind.CORRUPTION_APPLIED, CombatEvent.Kind.HERO_HEALED, CombatEvent.Kind.MINION_HEALED]:
			capture = true
		if capture:
			captured.append(e)
			_consume(e)
		prev_kind = e.kind
	await _cast_anim(spell, is_enemy)
	if not is_inside_tree():
		return
	var vfx_target: Variant = target
	if target is String:
		vfx_target = scene._enemy_status_panel if ev.side == "player" else scene._player_status_panel
	_spell_pending = captured
	var on_impact := func(_i: int) -> void:
		play_captured_all()
	if scene.vfx_controller != null:
		await scene.vfx_controller.play_spell(spell.id, ev.side, vfx_target, on_impact)
	play_captured_all()


## Every captured event of the spell being played that hasn't shown yet.
func play_captured_all() -> void:
	var pending: Array = _spell_pending
	_spell_pending = []
	for e in pending:
		_play_captured_event(e)


## The captured events for the minion shown on `slot` (a wave touching it).
func play_captured_for_slot(slot: BoardSlot) -> void:
	if slot == null or slot.minion == null:
		return
	var rest: Array = []
	for e in _spell_pending:
		if e.payload.get("minion", null) == slot.minion:
			_play_captured_event(e)
		else:
			rest.append(e)
	_spell_pending = rest
	if slot.freeze_visuals:
		slot.freeze_visuals = false
		slot._refresh_visuals()


func _play_captured_event(e: CombatEvent) -> void:
	if not is_inside_tree():
		return
	match e.kind:
		CombatEvent.Kind.DAMAGE_DEALT:
			_play_damage(e)
		CombatEvent.Kind.CORRUPTION_APPLIED:
			var node: BoardSlot = scene._find_slot_for(e.payload.get("minion", null))
			if node != null:
				scene._play_corruption_apply_visual(node)
		CombatEvent.Kind.HERO_HEALED:
			scene._flash_hero_heal(e.side, e.payload.get("amount", 0))
		CombatEvent.Kind.MINION_HEALED:
			var node: BoardSlot = scene._find_slot_for(e.payload.get("minion", null))
			if node != null:
				node.refresh_stats_only()
		_:
			pass


## Lunge with the strike's popups at the hit: the defender's and the counter's
## damage events (which follow) are consumed here.
func _play_attack(ev: CombatEvent) -> void:
	var attacker: MinionInstance = ev.payload.get("attacker", null)
	var target: Variant = ev.payload.get("target", null)
	if attacker == null:
		return
	var atk_node: BoardSlot = scene._find_slot_for(attacker)
	if target is String:
		var hero_side: String = "player" if target == "player_hero" else "enemy"
		var hit: CombatEvent = null
		for e in _peek_window():
			if _is_hero_damage(e, hero_side):
				hit = e
				_consume(e)
				break
		var school: int = Enums.DamageSchool.NONE
		if attacker.card_data is MinionCardData:
			school = (attacker.card_data as MinionCardData).attack_damage_school
		if school == Enums.DamageSchool.VOID_BOLT:
			var bolt: VoidBoltProjectile = scene._fire_void_bolt_projectile(attacker, false) if attacker.owner == "player" \
					else scene._fire_enemy_void_bolt_projectile(attacker)
			if bolt != null and is_inside_tree():
				await bolt.impact_hit
		elif atk_node != null:
			var panel: Control = scene._player_status_panel if hero_side == "player" else scene._enemy_status_panel
			if panel != null:
				atk_node.set_highlight(BoardSlot.HighlightMode.SELECTED)
				await scene._play_hero_attack_anim(atk_node, panel, attacker)
				if is_inside_tree():
					atk_node.clear_highlight()
		if hit != null and is_inside_tree():
			_play_damage(hit)
		return
	var defender: MinionInstance = target as MinionInstance
	if defender == null:
		return
	var def_node: BoardSlot = scene._find_slot_for(defender)
	var hit_d: CombatEvent = null
	var hit_a: CombatEvent = null
	for e in _peek_window():
		if hit_d == null and _is_minion_damage(e, defender):
			hit_d = e
			_consume(e)
		elif hit_a == null and _is_minion_damage(e, attacker):
			hit_a = e
			_consume(e)
	if atk_node == null or def_node == null:
		if hit_d != null: _play_damage(hit_d)
		if hit_a != null: _play_damage(hit_a)
		return
	var damage: int = hit_d.payload.get("amount", 0) if hit_d != null else 0
	var counter: int = hit_a.payload.get("amount", 0) if hit_a != null else 0
	var d_delta: int = (hit_d.payload.get("hp_before", 0) - hit_d.payload.get("hp_after", 0)) if hit_d != null else 0
	var a_delta: int = (hit_a.payload.get("hp_before", 0) - hit_a.payload.get("hp_after", 0)) if hit_a != null else 0
	var is_crit: bool = hit_d.payload.get("is_crit", false) if hit_d != null else false
	atk_node.set_highlight(BoardSlot.HighlightMode.SELECTED)
	def_node.set_highlight(BoardSlot.HighlightMode.INVALID)
	await scene._play_attack_anim(atk_node, def_node, damage, attacker, defender, is_crit, counter, d_delta, a_delta)
	if is_inside_tree():
		atk_node.clear_highlight()
		def_node.clear_highlight()


## Card-specific VFX requested by rules code (a VFX event). Positions resolve
## from the minions' slots at playback.
func _play_vfx(ev: CombatEvent) -> void:
	var p: Dictionary = ev.payload
	match p.get("name", ""):
		"grafted_butcher":
			var sac: MinionInstance = p.get("sac", null)
			var center: Vector2 = Vector2.ZERO
			if sac != null:
				var sac_node: BoardSlot = scene.slot_node(sac.owner, sac.slot_index)
				if sac_node != null:
					center = sac_node.global_position + sac_node.size * 0.5
			await scene._play_grafted_butcher_vfx(p.get("butcher", null), center, ev.side)
		"frenzied_imp":
			await scene._play_frenzied_imp_vfx(p.get("source", null), p.get("target", null), p.get("count", 0))
		"brood_call":
			await scene._play_brood_call_vfx(ev.side)
		"pack_frenzy":
			var nodes: Array = []
			for m in p.get("targets", []):
				var n: BoardSlot = scene._find_slot_for(m)
				if n != null:
					nodes.append(n)
			if not nodes.is_empty():
				await scene._play_pack_frenzy_vfx(ev.side, nodes, p.get("ancient", false))
		"atk_chevron":
			scene._spawn_atk_chevron(p.get("minion", null))
		"lifedrain_pulse":
			scene.vfx_bridge.pulse_lifedrain_icon(p.get("minion", null))
		"void_netter":
			scene._play_void_netter_on_play_vfx(p.get("source", null), p.get("target", null), ev.side)
		"presence_aura":
			scene._spawn_presence_aura_buff_vfx(p.get("minion", null), p.get("atk_delta", 0), p.get("hp_delta", 0))
		"pack_chain":
			scene.vfx_bridge.spawn_pack_chain_vfx(p.get("minion", null), ev.side)
		"pack_instinct":
			scene.vfx_bridge.spawn_pack_instinct_buff_vfx(p.get("minion", null), p.get("old_atk", 0))
		"feral_reinforcement":
			await scene._play_feral_reinforcement_vfx(p.get("source", null), p.get("card", null))
		"champion_acp_aura_pulse":
			scene._play_champion_acp_aura_pulse()
		"void_imp_claw":
			var m: MinionInstance = p.get("minion", null)
			var pos: Vector2 = Vector2.ZERO
			var n: BoardSlot = scene._find_slot_for(m)
			if n != null:
				pos = n.global_position + n.size / 2.0
			scene._spawn_void_imp_claw_vfx_at(pos, ev.side)
		"ritual_sacrifice":
			if scene.vfx_bridge == null:
				return
			var panels: Array = scene.enemy_trap_slot_panels
			var b_idx: int = p.get("blood_idx", -1)
			var d_idx: int = p.get("dominion_idx", -1)
			var blood_panel: Control = panels[b_idx] as Control if b_idx >= 0 and b_idx < panels.size() else null
			var dominion_panel: Control = panels[d_idx] as Control if d_idx >= 0 and d_idx < panels.size() else null
			if blood_panel == null or dominion_panel == null:
				return
			await scene.vfx_bridge.play_ritual_sacrifice_sequence(p.get("imp", null), p.get("blood_trap", null),
					p.get("dominion_trap", null), blood_panel, dominion_panel, p.get("targets", []),
					p.get("damage", 0), p.get("demon", null))
		_:
			pass


# ---------------------------------------------------------------------------
# Small awaitables
# ---------------------------------------------------------------------------

## The centred card preview (~1.1 s); returns when its impact beat fires.
func _cast_anim(card: CardData, is_enemy: bool) -> void:
	var shown: Array[bool] = [false]
	scene._show_card_cast_anim(card, is_enemy, func() -> void: shown[0] = true)
	var t0: int = Time.get_ticks_msec()
	while not shown[0] and is_inside_tree() and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	if not is_inside_tree() or seconds <= 0.0:
		return
	await get_tree().create_timer(seconds * BaseVfx.time_scale).timeout


# ---------------------------------------------------------------------------
# View → UI
# ---------------------------------------------------------------------------

func _emit_ui(ev: CombatEvent) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	var ui: CombatUI = scene.combat_ui
	var p: Dictionary = ev.payload
	match ev.kind:
		CombatEvent.Kind.LOG:
			if ui != null:
				ui.on_state_combat_log(p.get("msg", ""), p.get("log_type", 1))
		CombatEvent.Kind.HERO_HP_CHANGED:
			if ui != null:
				ui.on_state_hp_changed(ev.side, p.get("hp", 0), p.get("hp_max", 0), p.get("delta", 0))
		CombatEvent.Kind.VOID_MARKS_CHANGED:
			if ui != null:
				ui.on_state_void_marks_changed(ev.side, p.get("value", 0))
		CombatEvent.Kind.ARMOUR_CHANGED:
			if ui != null:
				ui.on_state_hero_armour_changed(ev.side, p.get("value", 0))
		CombatEvent.Kind.HERO_BUFF_CHANGED:
			if ui != null:
				ui.on_state_hero_buff_changed(ev.side)
		CombatEvent.Kind.FLESH_CHANGED:
			if ui != null:
				ui.on_state_flesh_changed(p.get("value", 0), p.get("max", 0))
		CombatEvent.Kind.FORGE_CHANGED:
			if ui != null:
				ui.on_state_forge_changed(p.get("value", 0), p.get("threshold", 0))
		CombatEvent.Kind.TRAPS_CHANGED:
			if ui != null:
				ui.on_state_traps_changed(ev.side)
		CombatEvent.Kind.ENVIRONMENT_CHANGED:
			if ui != null:
				ui.on_state_environment_changed(p.get("env", null))
		CombatEvent.Kind.RESOURCES_CHANGED:
			if ev.side == "player" and ui != null:
				ui.on_resources_changed(p.get("essence", 0), p.get("essence_max", 0), p.get("mana", 0), p.get("mana_max", 0))
				ui.refresh_end_turn_mode()
		CombatEvent.Kind.CARD_DRAWN:
			if ev.side == "player" and scene.hand_display != null:
				scene.hand_display.add_card(p.get("inst", null))
		CombatEvent.Kind.CARD_GENERATED:
			if ev.side == "player" and scene.hand_display != null:
				scene.hand_display.add_card_generated(p.get("inst", null))
		CombatEvent.Kind.CARD_PLAYED:
			if ev.side == "player" and scene.hand_display != null:
				var inst: CardInstance = p.get("inst", null)
				if inst != null:
					scene.hand_display.remove_card(inst)
				if ui != null:
					ui.refresh_hand_spell_costs()
		CombatEvent.Kind.SLOT_CHANGED:
			_apply_slot(ev)
		CombatEvent.Kind.MINION_STATS_CHANGED:
			var node: BoardSlot = scene._find_slot_for(p.get("minion", null))
			if node != null:
				node._refresh_visuals()
		CombatEvent.Kind.MINION_DIED, CombatEvent.Kind.MINION_SACRIFICED, CombatEvent.Kind.MINION_CONSUMED:
			if ev.side == "player" and scene.hand_display != null:
				scene.hand_display.refresh_condition_glows(scene, view.player_essence, view.player_mana)
			if ui != null:
				ui.refresh_hand_spell_costs()
		CombatEvent.Kind.TURN_STARTED:
			scene.show_turn_started(ev.side == "player", p.get("turn", 0))
			for s in scene.player_slots + scene.enemy_slots:
				(s as BoardSlot)._refresh_visuals()
			if scene._enemy_hero_panel != null:
				scene._enemy_hero_panel.update(view.enemy_hp, view.enemy_hp_max, state, view.enemy_void_marks)
		CombatEvent.Kind.RELIC_ACTIVATED:
			if scene._relic_bar != null:
				scene._relic_bar.refresh()
		CombatEvent.Kind.HAND_COSTS_CHANGED:
			if ev.side == "player" and ui != null:
				ui.refresh_hand_spell_costs()
		CombatEvent.Kind.SPELL_COUNTER_CHANGED:
			scene._update_counter_warning()
		CombatEvent.Kind.CHAMPION_PROGRESS:
			scene._update_champion_progress(p.get("current", 0), p.get("total", 0))
		CombatEvent.Kind.CHAMPION_KILLED:
			scene._on_champion_killed()
		_:
			pass


## Mirror the engine's slot occupancy onto the view node. Idempotent: the
## play / summon / death events that precede a slot change have usually shown
## or emptied the node already.
func _apply_slot(ev: CombatEvent) -> void:
	var node: BoardSlot = scene.slot_node(ev.side, ev.payload.get("slot", -1))
	if node == null:
		return
	var m: MinionInstance = ev.payload.get("minion", null)
	if m == null:
		if node.minion != null:
			node.show_empty()
	elif node.minion != m:
		node.freeze_visuals = false
		node.show_minion(m)
