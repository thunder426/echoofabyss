## VoidScreechVFX.gd
## Full VFX for the Void Screech spell — shader-based sonic wave with actual
## screen distortion + chromatic aberration, plus supporting overlays.
##
## Phases:
##   1. Windup (0.40s) — rune sigil + pulsing glow + inward particles per source
##   2. Burst  (0.90s) — SHADER-DRIVEN expanding radial wave that distorts screen
##                       pixels as it travels, with subtle red tint (almost
##                       invisible, just a shimmer). Fires `wave_arrived` from
##                       inside the builder once the earliest source's ring
##                       reaches the hero (geometry-driven, not fixed-time).
##                       `impact_hit` and all impact visuals listen for that beat.
##   3. Impact (0.75s) — let the impact wave + trailing burst play out before
##                       the host frees itself.
##
## Uses `sonic_wave.gdshader`.
class_name VoidScreechVFX
extends BaseVfx

const TEX_GLOW: Texture2D   = preload("res://assets/art/fx/glow_soft.png")
const TEX_RUNE: Texture2D   = preload("res://assets/art/fx/screech_rune.png")
const SHADER_SONIC: Shader  = preload("res://combat/effects/sonic_wave.gdshader")

const COLOR_SCREAM: Color      = Color(1.00, 0.22, 0.15, 1.0)
const COLOR_SCREAM_HOT: Color  = Color(1.00, 0.55, 0.30, 1.0)
const WAVE_TINT: Color         = Color(0.55, 0.30, 0.85, 0.18)

const WINDUP_DURATION: float  = 0.40
const BURST_DURATION: float   = 0.90
const IMPACT_DURATION: float  = 0.75
const OVERSHOOT_PX: float     = 220.0

const BEAT_WAVE_ARRIVED := "wave_arrived"

var _sources: Array = []
var _target_panel: Control = null
var _target_center: Vector2 = Vector2.ZERO
var _windup_nodes: Array[Node] = []
var _earliest_arrival: float = BURST_DURATION


static func create(sources: Array, target_panel: Control) -> VoidScreechVFX:
	var vfx := VoidScreechVFX.new()
	vfx._sources = sources
	vfx._target_panel = target_panel
	return vfx


func _play() -> void:
	if _sources.is_empty() or _target_panel == null or get_parent() == null:
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return

	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_screech.wav", -3.0)
	_target_center = _target_panel.global_position + _target_panel.size * 0.5

	var seq := sequence()
	# Impact damage + all impact visuals listen for the geometric arrival beat.
	# `wave_arrived` is fired from inside _build_burst via seq.emit_beat() at
	# the computed arrival time — not a fixed normalized fraction.
	seq.on(BEAT_WAVE_ARRIVED, _emit_impact_hit)
	seq.on(BEAT_WAVE_ARRIVED, _spawn_impact_wave)
	seq.on(BEAT_WAVE_ARRIVED, _flash_panel)
	seq.on(BEAT_WAVE_ARRIVED, _shake_panel)
	seq.on(BEAT_WAVE_ARRIVED, _full_screen_pulse)

	seq.run([
		VfxPhase.new("windup", WINDUP_DURATION, _build_windup),
		VfxPhase.new("burst",  BURST_DURATION,  _build_burst),
		VfxPhase.new("impact", IMPACT_DURATION, Callable()),
	])


func _emit_impact_hit() -> void:
	impact_hit.emit(0)


# ═════════════════════════════════════════════════════════════════════════════
# Phase builders
# ═════════════════════════════════════════════════════════════════════════════

func _build_windup(duration: float) -> void:
	var ui: Node = get_parent()
	if ui == null:
		return
	for src in _sources:
		var src_vec: Vector2 = src as Vector2
		_spawn_windup_at(ui, src_vec, duration, _windup_nodes)


func _build_burst(duration: float) -> void:
	var ui: Node = get_parent()
	if ui == null:
		return

	# Free leftover windup nodes (sequence finished waiting on the windup phase
	# already; some windup tweens self-free, but the rune+glow track WINDUP
	# duration internally).
	for n in _windup_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_windup_nodes.clear()

	# Compute earliest arrival across all sources, spawn one shader wave per source.
	_earliest_arrival = duration
	for src in _sources:
		var src_vec: Vector2 = src as Vector2
		var dist_to_hero: float = src_vec.distance_to(_target_center)
		var max_radius: float = dist_to_hero + OVERSHOOT_PX
		_spawn_sonic_wave(self, ui, src_vec, duration, max_radius)
		# easeOutCubic: progress(t) = 1 - (1 - t/D)^3, solve for r == dist_to_hero.
		var ratio: float = dist_to_hero / max_radius
		var arrival_t: float = duration * (1.0 - pow(1.0 - ratio, 1.0 / 3.0))
		if arrival_t < _earliest_arrival:
			_earliest_arrival = arrival_t

	# Schedule the wave_arrived beat at the geometric arrival time.
	# (Can't use Phase.emits() because the timing depends on geometry, not a
	# fixed normalized fraction.)
	var seq := sequence()
	if _earliest_arrival <= 0.0:
		seq.emit_beat(BEAT_WAVE_ARRIVED)
	else:
		var seq_ref := seq
		var tree := get_tree()
		if tree != null:
			tree.create_timer(_earliest_arrival).timeout.connect(func() -> void:
				if is_instance_valid(self) and is_inside_tree():
					seq_ref.emit_beat(BEAT_WAVE_ARRIVED))


# ═════════════════════════════════════════════════════════════════════════════
# Listeners — all fire on BEAT_WAVE_ARRIVED
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_impact_wave() -> void:
	var ui: Node = get_parent()
	if ui == null or _target_panel == null:
		return
	var impact_radius: float = maxf(_target_panel.size.x, _target_panel.size.y) * 0.7
	_spawn_sonic_wave(self, ui, _target_center, IMPACT_DURATION, impact_radius)


func _flash_panel() -> void:
	if _target_panel == null or not _target_panel.is_inside_tree():
		return
	var original_modulate: Color = _target_panel.modulate
	_target_panel.pivot_offset = _target_panel.size * 0.5
	var flash_tw := _target_panel.create_tween().set_parallel(true)
	flash_tw.tween_property(_target_panel, "modulate", Color(2.2, 0.25, 0.20, 1.0), 0.06)
	flash_tw.tween_property(_target_panel, "scale", Vector2(1.08, 1.08), 0.06)
	flash_tw.chain().tween_property(_target_panel, "modulate", original_modulate, 0.28)
	flash_tw.parallel().tween_property(_target_panel, "scale", Vector2.ONE, 0.28)


func _shake_panel() -> void:
	if _target_panel == null or not _target_panel.is_inside_tree():
		return
	ScreenShakeEffect.shake(_target_panel, self, 16.0, 12)


func _full_screen_pulse() -> void:
	var ui: Node = get_parent()
	if ui == null:
		return
	var flash := ColorRect.new()
	flash.color = Color(COLOR_SCREAM.r, COLOR_SCREAM.g, COLOR_SCREAM.b, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.z_index = 19
	flash.z_as_relative = false
	ui.add_child(flash)
	var vtw := flash.create_tween()
	vtw.tween_property(flash, "color:a", 0.16, 0.06).set_trans(Tween.TRANS_SINE)
	vtw.tween_property(flash, "color:a", 0.0, 0.38).set_trans(Tween.TRANS_SINE)
	vtw.tween_callback(flash.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Windup helpers
# ═════════════════════════════════════════════════════════════════════════════

static func _spawn_windup_at(ui: Node, src: Vector2, windup_dur: float, out_nodes: Array[Node]) -> void:
	# Rune sigil
	var rune := TextureRect.new()
	rune.texture = TEX_RUNE
	rune.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rune.stretch_mode = TextureRect.STRETCH_SCALE
	rune.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rune.modulate = Color(1.0, 1.0, 1.0, 0.0)
	rune.z_index = 12
	rune.z_as_relative = false
	var rune_size: float = 120.0
	rune.set_size(Vector2(rune_size, rune_size))
	rune.position = src - Vector2(rune_size, rune_size) * 0.5
	rune.pivot_offset = Vector2(rune_size, rune_size) * 0.5
	ui.add_child(rune)
	out_nodes.append(rune)
	var rtw := rune.create_tween().set_parallel(true)
	rtw.tween_property(rune, "modulate:a", 0.85, 0.20).set_trans(Tween.TRANS_SINE)
	rtw.tween_property(rune, "rotation", PI * 0.25, windup_dur + 0.1).set_trans(Tween.TRANS_SINE)
	rtw.tween_property(rune, "scale", Vector2(1.15, 1.15), windup_dur * 0.5).set_trans(Tween.TRANS_SINE)
	rtw.chain().tween_property(rune, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE)
	rtw.chain().tween_callback(rune.queue_free)

	# Pulsing red glow
	var glow := _make_additive_sprite(TEX_GLOW, COLOR_SCREAM)
	var glow_size: float = 160.0
	glow.set_size(Vector2(glow_size, glow_size))
	glow.position = src - Vector2(glow_size, glow_size) * 0.5
	glow.pivot_offset = Vector2(glow_size, glow_size) * 0.5
	glow.modulate.a = 0.0
	glow.z_index = 13
	glow.z_as_relative = false
	ui.add_child(glow)
	out_nodes.append(glow)
	var gtw := glow.create_tween().set_parallel(true)
	gtw.tween_property(glow, "modulate:a", 0.85, 0.22).set_trans(Tween.TRANS_SINE)
	gtw.tween_property(glow, "scale", Vector2(1.30, 1.30), windup_dur * 0.7).set_trans(Tween.TRANS_SINE)
	gtw.chain().tween_property(glow, "modulate:a", 0.0, 0.15)
	gtw.chain().tween_callback(glow.queue_free)

	# Inward-pulling particles
	var particle_count: int = 14
	for i in particle_count:
		var angle: float = (TAU / particle_count) * i + randf_range(-0.3, 0.3)
		var start_dist: float = randf_range(80.0, 130.0)
		var start_pos: Vector2 = src + Vector2(cos(angle), sin(angle)) * start_dist
		var mote := _make_additive_sprite(TEX_GLOW, COLOR_SCREAM_HOT)
		var s: float = randf_range(18.0, 28.0)
		mote.set_size(Vector2(s, s))
		mote.position = start_pos - Vector2(s, s) * 0.5
		mote.modulate.a = 0.0
		mote.z_index = 14
		mote.z_as_relative = false
		ui.add_child(mote)
		out_nodes.append(mote)
		var delay: float = randf_range(0.0, 0.15)
		var life: float = windup_dur - delay - 0.05
		var mtw := mote.create_tween().set_parallel(true)
		mtw.tween_interval(delay)
		mtw.tween_property(mote, "modulate:a", 0.95, 0.10).set_delay(delay)
		mtw.tween_property(mote, "position", src - Vector2(s, s) * 0.5, life).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		mtw.tween_property(mote, "scale", Vector2(0.4, 0.4), life).set_delay(delay)
		mtw.chain().tween_callback(mote.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Burst / impact — shader-driven distortion
# ═════════════════════════════════════════════════════════════════════════════

static func _spawn_sonic_wave(scene: Node, ui: Node, pos: Vector2,
		duration: float, max_radius_px: float) -> void:
	var vp := scene.get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var aspect: float = vp.x / vp.y

	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.z_index = 15
	rect.z_as_relative = false

	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SONIC
	mat.set_shader_parameter("aspect", aspect)
	mat.set_shader_parameter("tint", WAVE_TINT)
	mat.set_shader_parameter("radius_max", max_radius_px / vp.y)
	mat.set_shader_parameter("thickness", 0.11)
	mat.set_shader_parameter("strength", 0.028)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("alpha_multiplier", 1.0)
	mat.set_shader_parameter("center_uv", Vector2(pos.x / vp.x, pos.y / vp.y))
	rect.material = mat
	ui.add_child(rect)

	var tw := rect.create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			mat.set_shader_parameter("progress", p),
			0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, duration * 0.30).set_delay(duration * 0.70).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(rect.queue_free)


static func _make_additive_sprite(tex: Texture2D, color: Color) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = color
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tr.material = mat
	return tr
