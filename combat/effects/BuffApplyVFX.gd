## BuffApplyVFX.gd
## Generic "minion gets buffed" VFX — the shared language for every
## player-played buff (on-play minion buffs, spell buffs). Per-card flavor
## VFX can run as an optional prelude before the common phases.
##
## Phases (common to every buff):
##   1. Surge   — shader-driven light shaft + textured glow particles rise
##                through the slot with upward-scrolling wisps. Mid-surge,
##                the `flash` beat fires and the silhouette flash listener
##                spawns a low-alpha tinted overlay on the slot.
##   2. Pulses  — ATK then HP stat label pulses (each spawning BuffChevronVFX),
##                with PULSE_GAP between them; only non-zero deltas pulse.
##   3. Motes   — textured soft-glow motes drift and pulse briefly.
##
## The optional prelude runs as a plain await before the sequence starts,
## so per-card flavor (Rage flame column, Regrowth leaves, etc.) can fully
## play out before the common surge.
##
## Spawn via VfxController.spawn() — do not parent manually.
## Driven by the BuffSystem.bus() `buff_applied` signal; CombatScene filters
## which tags qualify (on-play + spells only, no auras/setup).
class_name BuffApplyVFX
extends BaseVfx

# --- Timing --------------------------------------------------------------
const SURGE_DURATION:    float = 0.55
const FLASH_DURATION:    float = 0.22
const FLASH_START_AT:    float = 0.30   # flash starts mid-surge, at shaft peak
const PULSE_GAP:         float = 0.10   # between ATK and HP pulses
const MOTE_DURATION:     float = 0.55

# --- Surge (shader-driven light shaft + textured glow particles) --------
const SHADER_SHAFT: Shader = preload("res://combat/effects/blessing_shaft.gdshader")
const SURGE_TINT_CORE: Color = Color(1.00, 0.92, 0.55, 1.0)
const SURGE_TINT_EDGE: Color = Color(0.55, 1.00, 0.65, 1.0)
const SURGE_PARTICLE_COUNT: int = 7
const SURGE_PARTICLE_MIN_SIZE: float = 14.0
const SURGE_PARTICLE_MAX_SIZE: float = 28.0
const SURGE_PARTICLE_TINT: Color = Color(1.00, 0.95, 0.65, 0.85)

# --- Flash ---------------------------------------------------------------
const FLASH_COLOR:       Color = Color(0.85, 1.00, 0.80, 1.0)
const FLASH_PEAK_ALPHA:  float = 0.55

# --- Label pulse ---------------------------------------------------------
const PULSE_COLOR_ATK:   Color = Color(0.45, 1.00, 0.35, 1.0)
const PULSE_COLOR_HP:    Color = Color(0.50, 1.00, 0.80, 1.0)
const PULSE_UP_TIME:     float = 0.12
const PULSE_DOWN_TIME:   float = 0.25
const PULSE_TOTAL:       float = PULSE_UP_TIME + PULSE_DOWN_TIME

# --- Motes ---------------------------------------------------------------
const MOTE_COUNT:        int = 5
const MOTE_MIN_SIZE:     float = 10.0
const MOTE_MAX_SIZE:     float = 18.0
const MOTE_COLOR:        Color = Color(0.85, 1.00, 0.70, 0.85)

const BEAT_FLASH := "silhouette_flash"

# ── Cached runtime glow texture ─────────────────────────────────────────
const _GLOW_SIZE: int = 128
static var _glow_tex: Texture2D = null

static func _get_glow_texture() -> Texture2D:
	if _glow_tex != null:
		return _glow_tex
	var img := Image.create(_GLOW_SIZE, _GLOW_SIZE, false, Image.FORMAT_RGBA8)
	var center: float = float(_GLOW_SIZE) * 0.5
	var max_r: float = center
	for y in _GLOW_SIZE:
		for x in _GLOW_SIZE:
			var dx: float = float(x) - center
			var dy: float = float(y) - center
			var r: float = sqrt(dx * dx + dy * dy) / max_r
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			a = pow(a, 2.2)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex

var _slot: Control = null
var _atk_delta: int = 0
var _hp_delta: int = 0
var _prelude: Callable = Callable()
# Per-source palette overrides. Keys (all Color, all optional):
#   surge_core, surge_edge, surge_particle, flash,
#   pulse_atk, pulse_hp, mote
var _palette: Dictionary = {}
var _slot_rect: Rect2 = Rect2()

# Deferred buff state mutation. Set via set_buff_intents() by CombatScene._flush_buff_requests
# so that BuffSystem.apply runs at the pulse beat (state mutation aligned with
# the visible chevron + scale-pulse + value tween). When intents are set,
# they're applied lazily during _pulse_stat. When unset (legacy path or
# abort), no state mutation happens here — caller is responsible.
var _intents_minion: MinionInstance = null
var _intents: Array = []  # Array[{ buff_type: int, amount: int, is_hp_gain: bool }]
var _atk_intent_applied: bool = false
var _hp_intent_applied:  bool = false


static func create(slot: Control, atk_delta: int, hp_delta: int,
		prelude: Callable = Callable(),
		palette: Dictionary = {}) -> BuffApplyVFX:
	var vfx := BuffApplyVFX.new()
	vfx._slot       = slot
	vfx._atk_delta  = atk_delta
	vfx._hp_delta   = hp_delta
	vfx._prelude    = prelude
	vfx._palette    = palette
	vfx.impact_count = 0
	return vfx


## Hand over deferred buff intents. The VFX takes ownership and calls
## BuffSystem.apply for each at its pulse beat (per stat — atk intents fire
## with the ATK pulse, hp intents fire with the HP pulse), so state mutation
## is aligned with the visible chevron + value tween. `scene` is the
## CombatScene reference used to call _refresh_slot_for after each apply.
var _scene: Node = null
func set_buff_intents(minion: MinionInstance, intents: Array, scene: Node = null) -> void:
	_intents_minion = minion
	_intents = intents
	_scene = scene


func _pc(key: String, fallback: Color) -> Color:
	if _palette.has(key):
		return _palette[key]
	return fallback


## Apply any unapplied buff intents matching `is_hp` filter. Called from
## _pulse_stat at the moment the chevron + tween fire so state mutation
## lands on the same beat. Subsequent _refresh_slot_for in the BuffSystem
## emit path lets minion_stats_changed fire naturally.
func _apply_intents(is_hp: bool) -> void:
	if _intents_minion == null or not is_instance_valid(_intents_minion):
		return
	for intent in _intents:
		if intent["is_hp_gain"] != is_hp:
			continue
		var bt: int = intent["buff_type"]
		var amt: int = intent["amount"]
		# Skip if already applied (defensive — guard against double-apply if
		# this method is called twice for the same stat).
		if intent.get("_applied", false):
			continue
		if intent["is_hp_gain"]:
			BuffSystem.apply_hp_gain(_intents_minion, amt, _safe_source_tag())
		else:
			BuffSystem.apply(_intents_minion, bt, amt, _safe_source_tag())
		intent["_applied"] = true


## Source tag for BuffSystem.apply calls. Stored on the agg dict by
## CombatScene._request_buff_apply; we don't have direct access here so
## reuse the slot/source convention: BuffApplyVFX is per-source, so the tag
## is stable across all intents in this VFX. Caller (CombatScene) records
## the source on the first intent — pull from there.
func _safe_source_tag() -> String:
	if _intents.is_empty():
		return ""
	return _intents[0].get("_source_tag", "")


## Clear deferred state by force-applying any unapplied intents. Used by
## abort paths so the buff still lands even if the VFX never reaches its
## pulse phase (scene change, slot freed, etc.). Without this, the buff
## would silently fail to apply.
func _force_apply_remaining_intents() -> void:
	if _intents_minion == null or not is_instance_valid(_intents_minion):
		return
	for intent in _intents:
		if intent.get("_applied", false):
			continue
		var bt: int = intent["buff_type"]
		var amt: int = intent["amount"]
		if intent["is_hp_gain"]:
			BuffSystem.apply_hp_gain(_intents_minion, amt, _safe_source_tag())
		else:
			BuffSystem.apply(_intents_minion, bt, amt, _safe_source_tag())
		intent["_applied"] = true


func _play() -> void:
	if _slot == null or not is_instance_valid(_slot) or get_parent() == null:
		_force_apply_remaining_intents()
		finished.emit()
		queue_free()
		return

	# Prelude runs before the sequence starts so per-card flavor plays first.
	# Keep this as a plain await — preludes are async user code, not part of
	# the timeline shape.
	if _prelude.is_valid():
		await _prelude.call()
		if not is_inside_tree() or not is_instance_valid(_slot):
			_force_apply_remaining_intents()
			finished.emit()
			queue_free()
			return

	_slot_rect = Rect2(_slot.global_position, _slot.size)
	AudioManager.play_sfx("res://assets/audio/sfx/buffs/buff_apply.wav", -6.0)

	var has_atk := _atk_delta != 0
	var has_hp  := _hp_delta != 0
	var pulses_dur: float = 0.0
	if has_atk:
		pulses_dur += PULSE_TOTAL
	if has_atk and has_hp:
		pulses_dur += PULSE_GAP
	if has_hp:
		pulses_dur += PULSE_TOTAL

	var seq := sequence()
	seq.on(BEAT_FLASH, _spawn_silhouette_flash)
	seq.run([
		VfxPhase.new("surge",  SURGE_DURATION, _build_surge) \
			.emits(BEAT_FLASH, FLASH_START_AT / SURGE_DURATION),
		VfxPhase.new("pulses", pulses_dur,     _build_pulses),
		VfxPhase.new("motes",  MOTE_DURATION,  _build_motes),
	])


# ─────────────────────────────────────────────────────────────────────────
# Phase builders + listeners
# ─────────────────────────────────────────────────────────────────────────

func _build_surge(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var rect := _slot_rect

	# ── Shader shaft ──────────────────────────────────────────────────────
	var shaft := ColorRect.new()
	shaft.color = Color(1.0, 1.0, 1.0, 1.0)
	shaft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shaft.z_index = 18
	shaft.z_as_relative = false
	var shaft_pad_top: float = 18.0
	var shaft_pad_bot: float = 10.0
	shaft.position = Vector2(rect.position.x, rect.position.y - shaft_pad_top)
	shaft.size     = Vector2(rect.size.x, rect.size.y + shaft_pad_top + shaft_pad_bot)

	var surge_core: Color = _pc("surge_core", SURGE_TINT_CORE)
	var surge_edge: Color = _pc("surge_edge", SURGE_TINT_EDGE)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SHAFT
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("time_offset", randf() * 10.0)
	mat.set_shader_parameter("tint_core", surge_core)
	mat.set_shader_parameter("tint_edge", surge_edge)
	mat.set_shader_parameter("intensity", 1.6)
	mat.set_shader_parameter("column_width", 0.55)
	mat.set_shader_parameter("wisp_speed", 2.4)
	mat.set_shader_parameter("wisp_scale", 7.0)
	shaft.material = mat
	host.add_child(shaft)

	var tw_shaft := create_tween()
	tw_shaft.tween_method(func(p: float) -> void:
			mat.set_shader_parameter("progress", p),
			0.0, 1.0, duration).set_trans(Tween.TRANS_SINE)
	tw_shaft.tween_callback(shaft.queue_free)

	# ── Textured glow particles ───────────────────────────────────────────
	var glow_tex: Texture2D = _get_glow_texture()
	var particle_tint: Color = _pc("surge_particle", SURGE_PARTICLE_TINT)
	for i in SURGE_PARTICLE_COUNT:
		var p := TextureRect.new()
		p.texture = glow_tex
		p.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.z_index = 19
		p.z_as_relative = false
		var sz: float = SURGE_PARTICLE_MIN_SIZE + randf() * (SURGE_PARTICLE_MAX_SIZE - SURGE_PARTICLE_MIN_SIZE)
		p.size = Vector2(sz, sz)
		var x_frac: float = 0.20 + randf() * 0.60
		var start_x: float = rect.position.x + rect.size.x * x_frac - sz * 0.5
		var start_y: float = rect.position.y + rect.size.y - sz * 0.5 + randf() * 14.0
		var end_y: float   = rect.position.y - sz - randf() * 30.0
		p.position = Vector2(start_x, start_y)
		var mix_t: float = randf()
		var tint: Color = surge_core.lerp(surge_edge, mix_t * 0.6)
		tint.a = 0.0
		p.modulate = tint
		var add_mat := CanvasItemMaterial.new()
		add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = add_mat
		host.add_child(p)

		var delay: float = randf() * 0.20
		var peak_alpha: float = particle_tint.a * (0.7 + randf() * 0.3)
		var tw_rise := create_tween()
		tw_rise.tween_interval(delay)
		tw_rise.tween_property(p, "position:y", end_y, duration - delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var wobble_x: float = start_x + (randf() - 0.5) * 24.0
		tw_rise.parallel().tween_property(p, "position:x", wobble_x, duration - delay).set_trans(Tween.TRANS_SINE)

		var tw_alpha := create_tween()
		tw_alpha.tween_interval(delay)
		tw_alpha.tween_property(p, "modulate:a", peak_alpha, (duration - delay) * 0.35).set_trans(Tween.TRANS_SINE)
		tw_alpha.tween_property(p, "modulate:a", 0.0, (duration - delay) * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw_alpha.tween_callback(p.queue_free)


func _spawn_silhouette_flash() -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var flash_tint: Color = _pc("flash", FLASH_COLOR)
	var flash := ColorRect.new()
	flash.color = Color(flash_tint.r, flash_tint.g, flash_tint.b, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.position = _slot_rect.position
	flash.size     = _slot_rect.size
	flash.z_index  = 19
	flash.z_as_relative = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = mat
	host.add_child(flash)

	var half := FLASH_DURATION * 0.5
	var tw := create_tween()
	tw.tween_property(flash, "color:a", FLASH_PEAK_ALPHA, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "color:a", 0.0, FLASH_DURATION - half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(flash.queue_free)


func _build_pulses(_duration: float) -> void:
	# Pulses are sequential with a gap. Sequence one tween that handles ATK,
	# the gap, then HP — using stagger via tween_interval.
	if not is_instance_valid(_slot):
		return
	var has_atk := _atk_delta != 0
	var has_hp  := _hp_delta != 0
	if has_atk:
		_pulse_stat("atk")
	if has_atk and has_hp:
		# Schedule HP pulse after PULSE_TOTAL + PULSE_GAP via timer.
		var delay := PULSE_TOTAL + PULSE_GAP
		var t := get_tree().create_timer(delay)
		t.timeout.connect(func() -> void:
			if is_instance_valid(self) and is_instance_valid(_slot):
				_pulse_stat("hp"))
	elif has_hp:
		_pulse_stat("hp")


func _pulse_stat(which: String) -> void:
	if not is_instance_valid(_slot):
		return
	var lbl: Label = null
	var pulse_color: Color = _pc("pulse_atk", PULSE_COLOR_ATK)
	if which == "atk":
		lbl = _slot.get("_atk_label")
		pulse_color = _pc("pulse_atk", PULSE_COLOR_ATK)
	elif which == "hp":
		lbl = _slot.get("_hp_label")
		pulse_color = _pc("pulse_hp", PULSE_COLOR_HP)
	if lbl == null or not is_instance_valid(lbl):
		return

	# VFX-anchored state mutation + value tween. Apply the deferred buff
	# intents NOW (state mutation happens at the visible beat), then run the
	# tween from pre to current. minion_stats_changed fires from BuffSystem.apply
	# but the slot's smart-snap helpers handle that by tweening to the same
	# end value (or being yielded to by the active tween).
	var slot_node: BoardSlot = _slot as BoardSlot
	if slot_node != null and slot_node.minion != null:
		if which == "atk" and _atk_delta != 0:
			# Snapshot pre-mutation BEFORE applying intents.
			var pre_atk: int = slot_node.minion.effective_atk()
			_apply_intents(false)
			# Slot color tints / status icons reflect post-mutation state.
			if _scene != null and _scene.has_method("_refresh_slot_for"):
				_scene._refresh_slot_for(slot_node.minion)
			slot_node.animate_atk_change(pre_atk)
		elif which == "hp" and _hp_delta != 0:
			var pre_hp: int = slot_node.minion.current_health
			_apply_intents(true)
			if _scene != null and _scene.has_method("_refresh_slot_for"):
				_scene._refresh_slot_for(slot_node.minion)
			slot_node.animate_hp_change(pre_hp, slot_node.minion.current_health)

	lbl.pivot_offset = lbl.size * 0.5
	var original_color: Color = lbl.get_theme_color("font_color")
	var tw := lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2(1.35, 1.35), PULSE_UP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(c: Color) -> void:
			lbl.add_theme_color_override("font_color", c),
			original_color, pulse_color, PULSE_UP_TIME)
	tw.chain().tween_property(lbl, "scale", Vector2.ONE, PULSE_DOWN_TIME).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(func(c: Color) -> void:
			lbl.add_theme_color_override("font_color", c),
			pulse_color, original_color, PULSE_DOWN_TIME)

	var chevron := preload("res://combat/effects/BuffChevronVFX.gd").new()
	_slot.add_child(chevron)
	var chevron_size := Vector2(14, 16)
	var font: Font = lbl.get_theme_font("font")
	var font_size: int = lbl.get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(lbl.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var text_left_x: float = lbl.position.x + (lbl.size.x - text_width) * 0.5
	var text_right_x: float = text_left_x + text_width
	var y_offset: float = lbl.size.y * 0.5 - chevron_size.y * 0.5
	var chevron_offset: Vector2
	var gap: float = 2.0
	if which == "hp":
		chevron_offset = Vector2(text_left_x - lbl.position.x - chevron_size.x - gap, y_offset)
	else:
		chevron_offset = Vector2(text_right_x - lbl.position.x + gap, y_offset)
	chevron.position = lbl.position + chevron_offset
	chevron.set_size(chevron_size)
	chevron.play()


func _build_motes(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var glow_tex: Texture2D = _get_glow_texture()
	var mote_tint: Color = _pc("mote", MOTE_COLOR)
	for i in MOTE_COUNT:
		var mote := TextureRect.new()
		mote.texture = glow_tex
		mote.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		mote.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mote.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mote.z_index = 18
		mote.z_as_relative = false
		var sz: float = MOTE_MIN_SIZE + randf() * (MOTE_MAX_SIZE - MOTE_MIN_SIZE)
		mote.size = Vector2(sz, sz)
		mote.pivot_offset = mote.size * 0.5
		mote.modulate = Color(mote_tint.r, mote_tint.g, mote_tint.b, 0.0)
		var add_mat := CanvasItemMaterial.new()
		add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		mote.material = add_mat

		var start_x: float = _slot_rect.position.x + _slot_rect.size.x * (0.20 + randf() * 0.60) - sz * 0.5
		var start_y: float = _slot_rect.position.y + _slot_rect.size.y * (0.18 + randf() * 0.38) - sz * 0.5
		mote.position = Vector2(start_x, start_y)
		var drift_x: float = (randf() - 0.5) * 32.0
		var drift_y: float = -12.0 - randf() * 18.0
		var start_scale: float = 0.6 + randf() * 0.2
		mote.scale = Vector2(start_scale, start_scale)
		host.add_child(mote)

		var delay: float = randf() * 0.10
		var peak_alpha: float = mote_tint.a * (0.75 + randf() * 0.25)
		var tw_alpha := create_tween()
		tw_alpha.tween_interval(delay)
		tw_alpha.tween_property(mote, "modulate:a", peak_alpha, duration * 0.25).set_trans(Tween.TRANS_SINE)
		tw_alpha.tween_property(mote, "modulate:a", 0.0, duration * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw_alpha.tween_callback(mote.queue_free)
		var tw_drift := create_tween()
		tw_drift.tween_interval(delay)
		tw_drift.tween_property(mote, "position", mote.position + Vector2(drift_x, drift_y), duration - delay).set_trans(Tween.TRANS_SINE)
		var tw_scale := create_tween()
		tw_scale.tween_interval(delay)
		tw_scale.tween_property(mote, "scale", Vector2(1.05, 1.05), duration * 0.35).set_trans(Tween.TRANS_SINE)
		tw_scale.tween_property(mote, "scale", Vector2(0.75, 0.75), duration * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
