## VoidScreechVFX.gd
## Full VFX for the Void Screech spell — shader-based sonic wave with actual
## screen distortion + chromatic aberration, plus supporting overlays.
##
## Phases:
##   1. Windup (0.40s) — rune sigil + pulsing glow + inward particles per source
##   2. Burst  (0.90s) — SHADER-DRIVEN expanding radial wave that distorts screen
##                       pixels as it travels, with subtle red tint (almost
##                       invisible, just a shimmer)
##   3. Impact (0.75s) — panel-centered wave + panel flash/shake/scale + smoke
##                       + spark motes + full-screen red pulse
##
## Uses `sonic_wave.gdshader` — samples SCREEN_TEXTURE and warps pixels via
## sin-wave radial displacement around a configurable center_uv.
##
## Spawn via VfxController — do not parent manually.
class_name VoidScreechVFX
extends BaseVfx

const TEX_GLOW: Texture2D   = preload("res://assets/art/fx/glow_soft.png")
const TEX_RUNE: Texture2D   = preload("res://assets/art/fx/screech_rune.png")
const SHADER_SONIC: Shader  = preload("res://combat/effects/sonic_wave.gdshader")

const COLOR_SCREAM: Color      = Color(1.00, 0.22, 0.15, 1.0)
const COLOR_SCREAM_HOT: Color  = Color(1.00, 0.55, 0.30, 1.0)
# Tint used by the sonic wave shader — subtle purple shimmer, low alpha
const WAVE_TINT: Color         = Color(0.55, 0.30, 0.85, 0.18)

const WINDUP_DURATION: float  = 0.40
const BURST_DURATION: float   = 0.90
const IMPACT_DURATION: float  = 0.75

var _sources: Array = []
var _target_panel: Control = null


static func create(sources: Array, target_panel: Control) -> VoidScreechVFX:
	var vfx := VoidScreechVFX.new()
	vfx._sources = sources
	vfx._target_panel = target_panel
	return vfx


func _play() -> void:
	# `host` = VfxLayer (our parent). All UI children parent to it so they
	# render at layer 2, above the HUD.
	var host: Node = get_parent()
	if _sources.is_empty() or _target_panel == null or host == null:
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return

	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_screech.wav", -3.0)

	# ── Phase 1: Windup ──────────────────────────────────────────────────────
	var windup_nodes: Array[Node] = []
	for src in _sources:
		var src_vec: Vector2 = src as Vector2
		_spawn_windup(host, src_vec, windup_nodes)
	await get_tree().create_timer(WINDUP_DURATION).timeout
	if not is_inside_tree():
		finished.emit()
		queue_free()
		return
	for n in windup_nodes:
		if is_instance_valid(n):
			n.queue_free()

	var target_center: Vector2 = _target_panel.global_position + _target_panel.size * 0.5

	# ── Phase 2: Burst — shader wave expanding outward from each source ──────
	const OVERSHOOT_PX: float = 220.0
	var earliest_arrival: float = BURST_DURATION
	for src in _sources:
		var src_vec: Vector2 = src as Vector2
		var dist_to_hero: float = src_vec.distance_to(target_center)
		var max_radius: float = dist_to_hero + OVERSHOOT_PX
		_spawn_sonic_wave(self, host, src_vec, BURST_DURATION, max_radius)
		# Compute when this wave's ring crosses the hero (using easeOutCubic curve):
		# progress(t) = 1 - (1 - t/D)^3, solved for radius == dist_to_hero.
		var ratio: float = dist_to_hero / max_radius
		var arrival_t: float = BURST_DURATION * (1.0 - pow(1.0 - ratio, 1.0 / 3.0))
		if arrival_t < earliest_arrival:
			earliest_arrival = arrival_t

	# Fire impact the moment the first wave reaches the hero
	await get_tree().create_timer(earliest_arrival).timeout
	if not is_inside_tree():
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return

	# ── Phase 3: Impact ──────────────────────────────────────────────────────
	impact_hit.emit(0)
	_spawn_impact(self, host, _target_panel, target_center)

	# Unblock game flow as soon as impact fires — the trailing wave, flash, and
	# shake continue visually but don't gate enemy turn progression. A short
	# settle delay keeps the `finished` emission just past the impact peak.
	await get_tree().create_timer(0.15).timeout
	finished.emit()

	# Let the trailing visual effects play out, then clean up.
	var remaining_burst: float = maxf(BURST_DURATION - earliest_arrival, 0.0)
	var remaining_wait: float = maxf(remaining_burst + IMPACT_DURATION - 0.15, 0.0)
	if remaining_wait > 0.0:
		await get_tree().create_timer(remaining_wait).timeout
	queue_free()


# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: Windup
# ═════════════════════════════════════════════════════════════════════════════

static func _spawn_windup(ui: Node, src: Vector2, out_nodes: Array[Node]) -> void:
	# Rune sigil — normal blend
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
	rtw.tween_property(rune, "rotation", PI * 0.25, WINDUP_DURATION + 0.1).set_trans(Tween.TRANS_SINE)
	rtw.tween_property(rune, "scale", Vector2(1.15, 1.15), WINDUP_DURATION * 0.5).set_trans(Tween.TRANS_SINE)
	rtw.chain().tween_property(rune, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE)
	rtw.chain().tween_callback(rune.queue_free)

	# Pulsing red glow — additive
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
	gtw.tween_property(glow, "scale", Vector2(1.30, 1.30), WINDUP_DURATION * 0.7).set_trans(Tween.TRANS_SINE)
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
		var life: float = WINDUP_DURATION - delay - 0.05
		var mtw := mote.create_tween().set_parallel(true)
		mtw.tween_interval(delay)
		mtw.tween_property(mote, "modulate:a", 0.95, 0.10).set_delay(delay)
		mtw.tween_property(mote, "position", src - Vector2(s, s) * 0.5, life).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		mtw.tween_property(mote, "scale", Vector2(0.4, 0.4), life).set_delay(delay)
		mtw.chain().tween_callback(mote.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2 & Impact wave — shader-driven distortion
# ═════════════════════════════════════════════════════════════════════════════

## Spawn a shader-driven sonic wave centered at `pos`, expanding outward to
## `max_radius_px` over `duration`. Center is fixed — only the radius grows.
static func _spawn_sonic_wave(scene: Node, ui: Node, pos: Vector2,
		duration: float, max_radius_px: float) -> void:
	var vp := scene.get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var aspect: float = vp.x / vp.y

	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)  # shader overrides
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
	# Fade alpha in the last 30% so wave vanishes cleanly
	tw.tween_method(func(a: float) -> void:
			mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, duration * 0.30).set_delay(duration * 0.70).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(rect.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 3: Impact
# ═════════════════════════════════════════════════════════════════════════════

static func _spawn_impact(scene: Node, ui: Node, target_panel: Control, target_center: Vector2) -> void:
	# ── Shader-driven impact wave — small ring expanding outward from hero ───
	var impact_radius: float = maxf(target_panel.size.x, target_panel.size.y) * 0.7
	_spawn_sonic_wave(scene, ui, target_center, IMPACT_DURATION, impact_radius)

	# ── Red flash + scale wobble on hero panel ───────────────────────────────
	var original_modulate: Color = target_panel.modulate
	target_panel.pivot_offset = target_panel.size * 0.5
	var flash_tw := target_panel.create_tween().set_parallel(true)
	flash_tw.tween_property(target_panel, "modulate", Color(2.2, 0.25, 0.20, 1.0), 0.06)
	flash_tw.tween_property(target_panel, "scale", Vector2(1.08, 1.08), 0.06)
	flash_tw.chain().tween_property(target_panel, "modulate", original_modulate, 0.28)
	flash_tw.parallel().tween_property(target_panel, "scale", Vector2.ONE, 0.28)

	# ── Strong panel shake ───────────────────────────────────────────────────
	ScreenShakeEffect.shake(target_panel, scene, 16.0, 12)

	# ── Subtle full-screen red pulse ─────────────────────────────────────────
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
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

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
