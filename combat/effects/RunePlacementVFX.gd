## RunePlacementVFX.gd
## Generic "a rune just landed" VFX — the shared visual for every rune
## placement (Void, Blood, Soul, Shadow, Dominion, Echo, Flesh, ...). One
## file, tinted per-rune from the trap's own `rune_glow_color` so each rune
## type reads as its own flavor without a separate VFX class.
##
## Phases (~0.85s total, blocking — caller awaits `finished` before resuming):
##   1. gather  (0.20s) — particles drift inward from slot edges, faint tinted
##                        ring sketches in. Sets up "something is being inscribed."
##   2. stamp   (0.30s) — bright tinted radial flash + sonic distortion ring +
##                        small slot shake. The rune's battlefield art (if any)
##                        scale-overshoots into place from alpha 0. Emits the
##                        reserved `impact_hit` beat at start so any future
##                        listener can sync to the inscription moment.
##   3. settle  (0.35s) — outer halo fades to soft, motes rise and fade.
##                        Hands off to TrapEnvDisplay's persistent rune glow.
##
## Tinting: caller passes the rune's `rune_glow_color`. The VFX brightens it
## for the flash and dims it for the halo so the same source color reads as
## both "core" and "edge" without a palette table.
##
## Spawn via VfxController.spawn(). Caller awaits `finished` to gate enemy
## actions / player flow until the placement reads.
class_name RunePlacementVFX
extends BaseVfx

const SHADER_SONIC: Shader = preload("res://combat/effects/sonic_wave.gdshader")
const TEX_GLOW:     Texture2D = preload("res://assets/art/fx/glow_soft.png")

# --- Timing --------------------------------------------------------------
const GATHER_DURATION: float = 0.20
const STAMP_DURATION:  float = 0.30
const SETTLE_DURATION: float = 0.35

# --- Gather phase --------------------------------------------------------
const GATHER_RING_SIZE_MULT:  float = 1.05  # of slot's shortest dim
const GATHER_RING_PEAK_ALPHA: float = 0.35
const GATHER_PARTICLE_COUNT:  int   = 8
const GATHER_PARTICLE_SIZE:   float = 14.0

# --- Stamp phase ---------------------------------------------------------
# Halo ring (no central core) — bright tinted ring that expands outward
# from slot edge, plus a wider soft outer wash that follows. The expanding
# ring is the bright bit; the wash gives it body without recreating a
# core-explosion silhouette.
const STAMP_HALO_START_MULT:  float = 0.85   # of slot's shortest dim — starts near slot edge
const STAMP_HALO_END_MULT:    float = 1.55   # expands outward
const STAMP_HALO_PEAK_ALPHA:  float = 0.80
const STAMP_WASH_SIZE_MULT:   float = 1.70
const STAMP_WASH_PEAK_ALPHA:  float = 0.30
const STAMP_RING_SCALE:       float = 0.75   # sonic distortion ring (shader)
const STAMP_RING_THICKNESS:   float = 0.060
const STAMP_RING_STRENGTH:    float = 0.018
const STAMP_RING_TINT_ALPHA:  float = 0.35
const STAMP_SHAKE_AMPLITUDE:  float = 6.0
const STAMP_SHAKE_TICKS:      int   = 6
const ART_OVERSHOOT_SCALE:    float = 1.08
const ART_FADE_IN:            float = 0.18

# Procedural ring texture — bright annular band, soft falloff on both edges,
# transparent center. Built once and reused across every placement. Same
# pattern as BuffApplyVFX._get_glow_texture.
const _RING_TEX_SIZE: int = 128
const _RING_INNER_RADIUS: float = 0.55  # 0..1 of texture half-width
const _RING_PEAK_RADIUS:  float = 0.78
const _RING_OUTER_RADIUS: float = 0.98
static var _ring_tex: Texture2D = null

static func _get_ring_texture() -> Texture2D:
	if _ring_tex != null:
		return _ring_tex
	var img := Image.create(_RING_TEX_SIZE, _RING_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var center: float = float(_RING_TEX_SIZE) * 0.5
	for y in _RING_TEX_SIZE:
		for x in _RING_TEX_SIZE:
			var dx: float = float(x) - center
			var dy: float = float(y) - center
			var r: float = sqrt(dx * dx + dy * dy) / center
			var a: float = 0.0
			if r >= _RING_INNER_RADIUS and r <= _RING_OUTER_RADIUS:
				if r <= _RING_PEAK_RADIUS:
					# Inner falloff: 0 at INNER, 1 at PEAK
					a = (r - _RING_INNER_RADIUS) / (_RING_PEAK_RADIUS - _RING_INNER_RADIUS)
				else:
					# Outer falloff: 1 at PEAK, 0 at OUTER
					a = 1.0 - (r - _RING_PEAK_RADIUS) / (_RING_OUTER_RADIUS - _RING_PEAK_RADIUS)
				a = pow(clampf(a, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_ring_tex = ImageTexture.create_from_image(img)
	return _ring_tex

# --- Settle phase --------------------------------------------------------
const SETTLE_HALO_SIZE_MULT:  float = 1.30
const SETTLE_HALO_PEAK_ALPHA: float = 0.55
const SETTLE_MOTE_COUNT:      int   = 5
const SETTLE_MOTE_MIN_SIZE:   float = 10.0
const SETTLE_MOTE_MAX_SIZE:   float = 18.0
const SETTLE_MOTE_RISE:       float = 36.0

var _panel: Control = null
var _glow_color: Color = Color(0.55, 0.18, 0.85, 1.0)  # default abyssal violet
var _rune_art: Texture2D = null
var _slot_center: Vector2 = Vector2.ZERO
var _slot_size: Vector2 = Vector2.ZERO
var _slot_short: float = 0.0
var _vp_size: Vector2 = Vector2.ZERO

static func create(panel: Control, glow_color: Color, rune_art: Texture2D = null) -> RunePlacementVFX:
	var vfx := RunePlacementVFX.new()
	vfx._panel = panel
	# rune_glow_color may have a == 0 (means "no custom glow"). Callers normalize
	# upstream, but guard here too — fall back to the default violet.
	if glow_color.a > 0.0:
		vfx._glow_color = glow_color
	vfx._rune_art = rune_art
	vfx.impact_count = 0
	return vfx

func _play() -> void:
	if _panel == null or not is_instance_valid(_panel) or not _panel.is_inside_tree():
		finished.emit()
		queue_free()
		return
	_vp_size = get_viewport().get_visible_rect().size
	if _vp_size.x <= 0.0 or _vp_size.y <= 0.0:
		finished.emit()
		queue_free()
		return
	_slot_size   = _panel.size
	_slot_center = _panel.global_position + _slot_size * 0.5
	_slot_short  = minf(_slot_size.x, _slot_size.y)

	# SFX is pre-aligned: the bell strike lands ~0.2s into the file, which
	# matches the stamp phase start (after the 0.20s gather phase).
	AudioManager.play_sfx("res://assets/audio/sfx/runes/rune_place.wav")

	sequence().run([
		VfxPhase.new("gather", GATHER_DURATION, _build_gather),
		VfxPhase.new("stamp",  STAMP_DURATION,  _build_stamp) \
			.emits_at_start(VfxSequence.RESERVED_IMPACT_HIT),
		VfxPhase.new("settle", SETTLE_DURATION, _build_settle),
	])

# ─────────────────────────────────────────────────────────────────────────
# Phase 1 — gather: faint inward sketch
# ─────────────────────────────────────────────────────────────────────────
func _build_gather(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var ring_size: float = _slot_short * GATHER_RING_SIZE_MULT
	var ring := _make_glow_sprite(ring_size, _glow_color, 0.0)
	host.add_child(ring)
	ring.scale = Vector2(0.6, 0.6)
	var ring_tw := create_tween().set_parallel(true)
	ring_tw.tween_property(ring, "modulate:a", GATHER_RING_PEAK_ALPHA, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ring_tw.tween_property(ring, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Particle inrush — small motes drift from slot edges toward center.
	for i in GATHER_PARTICLE_COUNT:
		_spawn_inrush_mote(host, i, duration)
	# Auto-fade ring just after the phase ends so it doesn't double-up with
	# the stamp flash.
	var fade := create_tween()
	fade.tween_interval(duration * 0.85)
	fade.tween_property(ring, "modulate:a", 0.0, duration * 0.4) \
		.set_trans(Tween.TRANS_SINE)
	fade.tween_callback(ring.queue_free)

func _spawn_inrush_mote(host: Node, idx: int, duration: float) -> void:
	var angle: float = TAU * float(idx) / float(GATHER_PARTICLE_COUNT) + randf_range(-0.15, 0.15)
	var start_radius: float = _slot_short * 0.55
	var start_pos: Vector2 = _slot_center + Vector2(cos(angle), sin(angle)) * start_radius
	var mote := _make_glow_sprite(GATHER_PARTICLE_SIZE, _glow_color, 0.85)
	host.add_child(mote)
	mote.position = start_pos - Vector2(GATHER_PARTICLE_SIZE, GATHER_PARTICLE_SIZE) * 0.5
	var travel := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	travel.tween_property(mote, "position",
			_slot_center - Vector2(GATHER_PARTICLE_SIZE, GATHER_PARTICLE_SIZE) * 0.5,
			duration)
	travel.tween_property(mote, "modulate:a", 0.0, duration)
	travel.chain().tween_callback(mote.queue_free)

# ─────────────────────────────────────────────────────────────────────────
# Phase 2 — stamp: flash + ring + shake + art overshoot
# ─────────────────────────────────────────────────────────────────────────
func _build_stamp(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	# 1. Halo ring — bright tinted annulus that blooms outward from slot edge.
	#    Replaces the old radial-flash core so the slot doesn't read as an
	#    explosion; the rune lights up its surroundings instead.
	_spawn_halo_ring(host, duration)
	# 2. Soft outer wash — wide low-alpha glow underneath the ring so the
	#    halo has body without a hot core. Reads as ambient radiance.
	_spawn_outer_wash(host, duration)

	# 3. Sonic distortion ring (Y-squashed for slight perspective).
	_spawn_distortion_ring(host, duration)

	# 4. Slot shake — small, this is a placement not an impact.
	if is_instance_valid(_panel):
		shake(_panel, STAMP_SHAKE_AMPLITUDE, STAMP_SHAKE_TICKS)

	# 5. Rune art overshoot stamp (only if the rune has battlefield art).
	if _rune_art != null:
		_spawn_art_stamp(host)

func _spawn_halo_ring(host: Node, duration: float) -> void:
	var start_size: float = _slot_short * STAMP_HALO_START_MULT
	var end_size:   float = _slot_short * STAMP_HALO_END_MULT
	var ring_color := _brighten(_glow_color, 1.45)
	var ring := _make_ring_sprite(end_size, ring_color, 0.0)
	host.add_child(ring)
	# Scale tween from start/end size ratio so the ring's stroke width stays
	# constant in pixels (the tween moves the visible band outward without
	# fattening it — TextureRect doesn't auto-scale stroke).
	var start_scale: float = start_size / end_size
	ring.scale = Vector2(start_scale, start_scale)
	var bloom_in: float  = duration * 0.30
	var bloom_out: float = duration * 0.70
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "modulate:a", STAMP_HALO_PEAK_ALPHA, bloom_in) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(ring, "modulate:a", 0.0, bloom_out) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)

func _spawn_outer_wash(host: Node, duration: float) -> void:
	var wash_size: float = _slot_short * STAMP_WASH_SIZE_MULT
	var wash_color := _brighten(_glow_color, 1.20)
	var wash := _make_glow_sprite(wash_size, wash_color, 0.0)
	host.add_child(wash)
	wash.scale = Vector2(0.85, 0.85)
	var fade_in: float  = duration * 0.30
	var fade_out: float = duration * 0.70
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(wash, "modulate:a", STAMP_WASH_PEAK_ALPHA, fade_in) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(wash, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(wash, "modulate:a", 0.0, fade_out) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(wash.queue_free)

func _spawn_distortion_ring(host: Node, duration: float) -> void:
	var ring_rect := ColorRect.new()
	ring_rect.color = Color(1, 1, 1, 1)
	ring_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring_rect.z_index = 21
	ring_rect.z_as_relative = false
	var center_uv: Vector2 = Vector2(_slot_center.x / _vp_size.x, _slot_center.y / _vp_size.y)
	var ring_max_radius_px: float = maxf(_slot_size.x, _slot_size.y) * STAMP_RING_SCALE
	var ring_max_radius_uv: float = ring_max_radius_px / _vp_size.y
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = SHADER_SONIC
	var ring_tint := Color(_glow_color.r, _glow_color.g, _glow_color.b, STAMP_RING_TINT_ALPHA)
	ring_mat.set_shader_parameter("center_uv", center_uv)
	ring_mat.set_shader_parameter("aspect", _vp_size.x / _vp_size.y)
	ring_mat.set_shader_parameter("radius_max", ring_max_radius_uv)
	ring_mat.set_shader_parameter("thickness", STAMP_RING_THICKNESS)
	ring_mat.set_shader_parameter("strength", STAMP_RING_STRENGTH)
	ring_mat.set_shader_parameter("tint", ring_tint)
	ring_mat.set_shader_parameter("progress", 0.0)
	ring_mat.set_shader_parameter("alpha_multiplier", 1.0)
	ring_rect.material = ring_mat
	host.add_child(ring_rect)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			ring_mat.set_shader_parameter("progress", p),
			0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			ring_mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, duration * 0.40
		).set_delay(duration * 0.60).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(ring_rect.queue_free)

func _spawn_art_stamp(host: Node) -> void:
	# Size the art to roughly fill the slot. TrapEnvDisplay will already be
	# drawing the persistent art underneath, so this overlay just adds the
	# overshoot/flash and then fades to hand off cleanly.
	var art_size: float = _slot_short * 0.85
	var art := TextureRect.new()
	art.texture = _rune_art
	art.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_size(Vector2(art_size, art_size))
	art.position     = _slot_center - Vector2(art_size, art_size) * 0.5
	art.pivot_offset = Vector2(art_size, art_size) * 0.5
	art.modulate     = Color(1, 1, 1, 0)
	art.scale        = Vector2(0.55, 0.55)
	art.z_index      = 22
	art.z_as_relative = false
	host.add_child(art)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(art, "modulate:a", 1.0, ART_FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(art, "scale", Vector2(ART_OVERSHOOT_SCALE, ART_OVERSHOOT_SCALE), ART_FADE_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(art, "scale", Vector2.ONE, 0.10) \
		.set_trans(Tween.TRANS_SINE)
	tw.chain().tween_interval(0.08)
	tw.chain().tween_property(art, "modulate:a", 0.0, 0.18) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(art.queue_free)

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — settle: lingering halo + rising motes
# ─────────────────────────────────────────────────────────────────────────
func _build_settle(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	# Outer halo decays from peak to nothing.
	var halo_size: float = _slot_short * SETTLE_HALO_SIZE_MULT
	var halo := _make_glow_sprite(halo_size, _glow_color, SETTLE_HALO_PEAK_ALPHA)
	host.add_child(halo)
	var halo_tw := create_tween().set_parallel(true)
	halo_tw.tween_property(halo, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	halo_tw.tween_property(halo, "scale", Vector2(1.15, 1.15), duration) \
		.set_trans(Tween.TRANS_SINE)
	halo_tw.chain().tween_callback(halo.queue_free)
	# Rising motes.
	for i in SETTLE_MOTE_COUNT:
		_spawn_settle_mote(host, i, duration)

func _spawn_settle_mote(host: Node, idx: int, duration: float) -> void:
	var size: float = randf_range(SETTLE_MOTE_MIN_SIZE, SETTLE_MOTE_MAX_SIZE)
	var mote := _make_glow_sprite(size, _glow_color, 0.85)
	host.add_child(mote)
	var x_off: float = randf_range(-_slot_size.x * 0.30, _slot_size.x * 0.30)
	var y_off: float = randf_range(-_slot_size.y * 0.10, _slot_size.y * 0.20)
	mote.position = _slot_center + Vector2(x_off, y_off) - Vector2(size, size) * 0.5
	var rise_offset: float = SETTLE_MOTE_RISE + randf_range(-8.0, 8.0)
	var stagger: float = float(idx) * (duration * 0.05)
	var tw := create_tween()
	tw.tween_interval(stagger)
	tw.set_parallel(true)
	tw.tween_property(mote, "position:y", mote.position.y - rise_offset, duration - stagger) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(mote, "modulate:a", 0.0, duration - stagger) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mote.queue_free)

# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

## Build an additive tinted soft-glow sprite centered on the slot.
## Returned sprite is positioned at slot center, sized `size x size`,
## with modulate.rgb = tint and modulate.a = alpha. Pivot is at center
## so callers can scale uniformly.
func _make_glow_sprite(size: float, tint: Color, alpha: float) -> TextureRect:
	var s := TextureRect.new()
	s.texture       = TEX_GLOW
	s.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	s.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	s.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	s.set_size(Vector2(size, size))
	s.position      = _slot_center - Vector2(size, size) * 0.5
	s.pivot_offset  = Vector2(size, size) * 0.5
	s.modulate      = Color(tint.r, tint.g, tint.b, alpha)
	s.z_index       = 20
	s.z_as_relative = false
	# Additive blend via CanvasItemMaterial — same trick as other glow VFX.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	return s

## Same as _make_glow_sprite but uses the procedural ring texture (annular,
## transparent center) so the bright part reads as a halo, not a core.
func _make_ring_sprite(size: float, tint: Color, alpha: float) -> TextureRect:
	var s := TextureRect.new()
	s.texture       = _get_ring_texture()
	s.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	s.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	s.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	s.set_size(Vector2(size, size))
	s.position      = _slot_center - Vector2(size, size) * 0.5
	s.pivot_offset  = Vector2(size, size) * 0.5
	s.modulate      = Color(tint.r, tint.g, tint.b, alpha)
	s.z_index       = 20
	s.z_as_relative = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	return s

func _brighten(c: Color, mult: float) -> Color:
	return Color(
		clampf(c.r * mult, 0.0, 1.0),
		clampf(c.g * mult, 0.0, 1.0),
		clampf(c.b * mult, 0.0, 1.0),
		c.a)
