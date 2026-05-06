## RitualFiringVFX.gd
## Generic "two runes ignite and merge" VFX — the shared visual for any ritual
## that consumes two runes to produce an effect. The runes brighten on their
## trap slots, lift off, translate (no self-rotation — the rune art keeps its
## upright posture) along an arc to screen center, then merge into a single
## combined sigil orb that holds briefly before handing off to the ritual-
## specific tail (e.g. DemonAscendantRitualVFX).
##
## Phases:
##   1. shine   (SHINE_DURATION)   — rune slots + (optional) source slot brighten in place
##   2. liftoff (LIFTOFF_DURATION) — small upward pop + scale-up before travel begins
##   3. travel  (TRAVEL_DURATION)  — runes translate toward screen center on individual
##                                   arcs (one curving out left, one right). Posture is
##                                   preserved — they DO NOT spin on their axis.
##   4. merge   (MERGE_HOLD_DURATION) — combined orb pulses at center; emits
##                                      `merge_complete` beat at phase start so callers
##                                      can chain ritual-specific tails synced to the merge
##
## The host emits `finished` at the end of the merge phase; tails are expected
## to await `merge_complete` and continue from there as separate VFX nodes
## (the merged orb persists until the tail spawns its own visuals).
##
## Spawn via VfxController.spawn().
class_name RitualFiringVFX
extends BaseVfx

const TEX_GLOW: Texture2D = preload("res://assets/art/fx/glow_soft.png")

# Halo styled after the casting glyph windup — uses the abyss faction's bold
# line-art glyph + casting_glyph_glow.gdshader so the runes appear ringed by a
# thickened, shader-driven halo (instead of a soft circular blob).
const TEX_HALO_GLYPH: Texture2D = preload("res://assets/art/fx/casting_glyphs/abyss_glyph.png")
const SHADER_GLYPH_GLOW: Shader = preload("res://combat/effects/casting_glyph_glow.gdshader")

# --- Timing (doubled from initial estimates per design call) -------------
const SHINE_DURATION:      float = 0.8
const LIFTOFF_DURATION:    float = 0.4
const TRAVEL_DURATION:     float = 1.6
const MERGE_HOLD_DURATION: float = 0.6

# --- Visual constants ----------------------------------------------------
const SHINE_PEAK_ALPHA:   float = 0.85
const SHINE_RING_MULT:    float = 1.20  # rune slot's shine halo size relative to slot's shortest dim

const RUNE_ICON_SIZE_PX:  float = 96.0  # in-flight rune token size
const RUNE_HALO_MULT:     float = 1.65  # glyph + halo container size relative to icon
const RUNE_HALO_THICKNESS: float = 6.0  # shader thickness param — thicker line = bolder ring
const RUNE_HALO_INTENSITY_BASE: float = 1.4   # base shader intensity at liftoff
const RUNE_HALO_INTENSITY_PEAK: float = 3.4   # shader intensity at merge — runes brighten as they converge

# Gradient halo (soft radial circle behind the shader glyph). Sized relative
# to the glyph's own footprint so the halo bleeds well past the line-art for
# a clear bloom read. Channel-suppressed tint per CastingWindupVFX.
const GRADIENT_HALO_SIZE_MULT:  float = 2.0
const GRADIENT_HALO_PEAK_ALPHA: float = 0.85

const TRAVEL_ARC_OFFSET:  float = 220.0 # how far each rune curves out from the straight line

# Merged orb at screen center — same casting-glyph treatment as the in-flight
# halos, scaled up. Intensity tweens drive bloom/hold/fade rather than alpha
# on a soft disc (per the no-static-glow-core rule).
const MERGE_ORB_SIZE_PX:        float = 240.0
const MERGE_ORB_THICKNESS:      float = 8.0
const MERGE_ORB_INTENSITY_PEAK: float = 4.5
const MERGE_ORB_WHITE_MIX_PEAK: float = 0.35

# --- Beat names (also exposed for listeners) -----------------------------
const BEAT_MERGE_COMPLETE: String = "merge_complete"

# --- State / params ------------------------------------------------------
var _slots: Array[Control] = []         # rune trap slot panels
var _slot_colors: Array = []            # Array[Color] — per-rune tint
var _rune_arts: Array = []              # Array[Texture2D|null] — per-rune battlefield art
var _extra_shine_slots: Array[Control] = []  # extra slots that should also shine (e.g. sacrificed minion's slot)
var _extra_shine_color: Color = Color(0.9, 0.85, 1.0, 1.0)

var _merge_position: Vector2 = Vector2.ZERO  # screen center, cached on _play
var _merged_orb: Control = null
var _merged_orb_mat: ShaderMaterial = null  # casting-glyph shader on the merged orb


## slots — Array[Control], the trap slot panels for the consumed runes (2+).
## colors — parallel Array[Color] of rune tints (one per slot).
## rune_arts — parallel Array[Texture2D|null] of battlefield art (one per slot).
## extra_shine_slots — additional slots that should shine in step 1 alongside
##   the runes (e.g. the sacrificed imp's slot for ritual_sacrifice).
## extra_shine_color — tint for the extra shine slots' halo (default warm white).
static func create(slots: Array, colors: Array, rune_arts: Array,
		extra_shine_slots: Array = [], extra_shine_color: Color = Color(0.9, 0.85, 1.0, 1.0)) -> RitualFiringVFX:
	var vfx := RitualFiringVFX.new()
	for s in slots:
		if s is Control:
			vfx._slots.append(s as Control)
	for c in colors:
		vfx._slot_colors.append(c)
	for a in rune_arts:
		vfx._rune_arts.append(a)
	for s in extra_shine_slots:
		if s is Control:
			vfx._extra_shine_slots.append(s as Control)
	vfx._extra_shine_color = extra_shine_color
	vfx.impact_count = 0   # this VFX has no damage gate
	vfx.z_index = 250
	return vfx


func _play() -> void:
	if _slots.size() < 2:
		finished.emit()
		queue_free()
		return
	# Filter out any slots that vanished between create() and _play().
	for s in _slots.duplicate():
		if s == null or not is_instance_valid(s) or not s.is_inside_tree():
			_slots.erase(s)
	if _slots.size() < 2:
		finished.emit()
		queue_free()
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_merge_position = vp_size * 0.5

	AudioManager.play_sfx("res://assets/audio/sfx/runes/rune_place.wav", -2.0)

	sequence().run([
		VfxPhase.new("shine",   SHINE_DURATION,      _build_shine),
		VfxPhase.new("liftoff", LIFTOFF_DURATION,    _build_liftoff),
		VfxPhase.new("travel",  TRAVEL_DURATION,     _build_travel),
		VfxPhase.new("merge",   MERGE_HOLD_DURATION, _build_merge) \
			.emits_at_start(BEAT_MERGE_COMPLETE),
	])

# ─────────────────────────────────────────────────────────────────────────
# Phase 1 — shine (rune slots + extras brighten in place)
# ─────────────────────────────────────────────────────────────────────────
func _build_shine(duration: float) -> void:
	for i in _slots.size():
		var slot: Control = _slots[i]
		var color: Color = _color_at(i)
		_spawn_shine_halo(slot, color, duration, SHINE_RING_MULT)
		if is_instance_valid(slot):
			shake(slot, 3.0, 4)
	# Extra slots (e.g. sacrificed imp's slot) get the warm shared shine.
	for slot in _extra_shine_slots:
		_spawn_shine_halo(slot, _extra_shine_color, duration, 1.05)

func _spawn_shine_halo(slot: Control, color: Color, duration: float, size_mult: float) -> void:
	if slot == null or not is_instance_valid(slot):
		return
	var host: Node = get_parent()
	if host == null:
		return
	var slot_short: float = minf(slot.size.x, slot.size.y)
	var size: float = slot_short * size_mult
	var center: Vector2 = slot.global_position + slot.size * 0.5
	var halo_pair: Array = _make_glyph_halo_at(center, size, color)
	var halo: Control = halo_pair[0]
	var mat: ShaderMaterial = halo_pair[1]
	halo.z_index = 247
	halo.z_as_relative = false
	# Override the in-flight halo defaults — slot shine is gentler (lower peak
	# intensity, no white-mix punch) since this is "the rune lighting up in
	# place", not "the rune charging into the merge".
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("thickness", 4.0)
	host.add_child(halo)
	halo.scale = Vector2(0.85, 0.85)
	# Alpha bloom + hold + fade. Shader intensity ramps with the alpha so the
	# halo has the same "charging" gradient feel as the in-flight halos.
	var bloom_t: float = duration * 0.35
	var hold_t:  float = duration * 0.55
	var down_t:  float = duration - bloom_t - hold_t
	var peak_intensity: float = 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(halo, "modulate:a", SHINE_PEAK_ALPHA, bloom_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(halo, "scale", Vector2(1.05, 1.05), bloom_t) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(halo, "modulate:a", SHINE_PEAK_ALPHA * 0.85, hold_t)
	tw.chain().tween_property(halo, "modulate:a", 0.0, down_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(halo.queue_free)
	# Shader-intensity ramp synced with alpha so the halo brightens cleanly.
	var tw_shader := create_tween().set_parallel(true)
	tw_shader.tween_method(func(v: float) -> void:
			if mat != null: mat.set_shader_parameter("intensity", v),
			0.0, peak_intensity, bloom_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_shader.chain().tween_method(func(v: float) -> void:
			if mat != null: mat.set_shader_parameter("intensity", v),
			peak_intensity, peak_intensity * 0.85, hold_t)
	tw_shader.chain().tween_method(func(v: float) -> void:
			if mat != null: mat.set_shader_parameter("intensity", v),
			peak_intensity * 0.85, 0.0, down_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# ─────────────────────────────────────────────────────────────────────────
# Phase 2 — liftoff (rune tokens spawn + pop upward at the slot)
# ─────────────────────────────────────────────────────────────────────────

# In-flight rune tokens, indexed parallel to _slots. Built in _build_liftoff,
# moved in _build_travel, consumed by _build_merge.
var _flight_tokens: Array[Control] = []
var _flight_starts: Array[Vector2] = []
var _flight_halos: Array[Control] = []
var _flight_halo_mats: Array[ShaderMaterial] = []  # per-token shader material so we can ramp intensity

func _build_liftoff(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	for i in _slots.size():
		var slot: Control = _slots[i]
		if slot == null or not is_instance_valid(slot):
			_flight_tokens.append(null)
			_flight_starts.append(Vector2.ZERO)
			_flight_halos.append(null)
			_flight_halo_mats.append(null)
			continue
		var color: Color = _color_at(i)
		var art: Texture2D = _art_at(i)
		var slot_center: Vector2 = slot.global_position + slot.size * 0.5

		# Casting-glyph-style halo — abyss faction line-art glyph run through
		# the casting_glyph_glow shader so the rune appears ringed by a bold
		# tinted halo that intensifies as it travels (instead of a soft blob).
		var halo_size: float = RUNE_ICON_SIZE_PX * RUNE_HALO_MULT
		var halo_pair: Array = _make_glyph_halo_at(slot_center, halo_size, color)
		var halo: Control = halo_pair[0]
		var halo_mat: ShaderMaterial = halo_pair[1]
		halo.z_index = 248
		halo.z_as_relative = false
		host.add_child(halo)

		# Token — uses rune's battlefield art if present, otherwise a glow disc
		# tinted to the rune color (plenty for the shine read).
		var token := _make_token_at(slot_center, RUNE_ICON_SIZE_PX, color, art)
		token.z_index = 249
		token.z_as_relative = false
		host.add_child(token)

		_flight_tokens.append(token)
		_flight_halos.append(halo)
		_flight_halo_mats.append(halo_mat)
		_flight_starts.append(slot_center)

		# Pop animation — fade in, scale punch, lift slightly upward.
		var lift_offset: Vector2 = Vector2(0.0, -16.0)
		var tw_token := create_tween().set_parallel(true)
		tw_token.tween_property(token, "modulate:a", 1.0, duration * 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw_token.tween_property(token, "scale", Vector2(1.10, 1.10), duration * 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw_token.tween_property(token, "position",
				slot_center + lift_offset - token.size * 0.5,
				duration * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		var tw_halo := create_tween().set_parallel(true)
		tw_halo.tween_property(halo, "modulate:a", 1.0, duration * 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw_halo.tween_property(halo, "scale", Vector2(1.10, 1.10), duration * 0.55) \
			.set_trans(Tween.TRANS_SINE)
		tw_halo.tween_property(halo, "position",
				slot_center + lift_offset - halo.size * 0.5,
				duration * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		# Update the flight start position to the post-liftoff position so
		# travel begins where liftoff actually ended.
		_flight_starts[i] = slot_center + lift_offset

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — travel (runes arc toward center, rotating)
# ─────────────────────────────────────────────────────────────────────────

# Travel state — _process advances along an arc per token while phase 3 is active.
var _travel_active: bool = false
var _travel_elapsed: float = 0.0
var _travel_duration: float = 0.0
var _travel_arc_signs: Array[float] = []  # +1 / -1 per token, alternating

func _build_travel(duration: float) -> void:
	_travel_active = true
	_travel_elapsed = 0.0
	_travel_duration = duration
	# Distribute arc directions so adjacent tokens curve out to different sides
	# (creates the spiral-toward-center read instead of two lines crossing).
	_travel_arc_signs.clear()
	for i in _flight_tokens.size():
		_travel_arc_signs.append(1.0 if i % 2 == 0 else -1.0)

func _process(delta: float) -> void:
	if not _travel_active:
		return
	_travel_elapsed += delta
	var t: float = clampf(_travel_elapsed / maxf(_travel_duration, 0.001), 0.0, 1.0)
	# Ease t cubically toward end so the convergence accelerates.
	var ease_t: float = 1.0 - pow(1.0 - t, 2.5)
	for i in _flight_tokens.size():
		var token: Control = _flight_tokens[i]
		var halo: Control = _flight_halos[i]
		if token == null or not is_instance_valid(token):
			continue
		var start: Vector2 = _flight_starts[i]
		var straight: Vector2 = start.lerp(_merge_position, ease_t)
		# Perpendicular arc — runes curve out away from the straight line.
		var to_center: Vector2 = _merge_position - start
		var perp: Vector2 = Vector2(-to_center.y, to_center.x).normalized()
		var sign: float = _travel_arc_signs[i] if i < _travel_arc_signs.size() else 1.0
		# 4 * t * (1-t) peaks at 1.0 mid-travel, returns to 0 at the ends.
		var bow: float = 4.0 * t * (1.0 - t) * TRAVEL_ARC_OFFSET * sign
		var pos: Vector2 = straight + perp * bow
		token.position = pos - token.size * 0.5
		# No self-rotation — the rune art keeps its upright posture, only
		# translates along the arc to center. (User design call: no tumble.)
		# Slight scale-up as runes near merge, suggesting they're picking up energy.
		var scale_pulse: float = lerpf(1.10, 1.30, ease_t)
		token.scale = Vector2(scale_pulse, scale_pulse)
		# Halo tracks the token. Brightening via shader intensity so the rune
		# reads as charging up as it nears the merge point.
		if halo != null and is_instance_valid(halo):
			halo.position = pos - halo.size * 0.5
			halo.scale = Vector2(scale_pulse * 1.10, scale_pulse * 1.10)
			var mat: ShaderMaterial = _flight_halo_mats[i]
			if mat != null:
				mat.set_shader_parameter("intensity",
						lerpf(RUNE_HALO_INTENSITY_BASE, RUNE_HALO_INTENSITY_PEAK, ease_t))

	if t >= 1.0:
		_travel_active = false

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — merge (combined orb pulses at center, tokens fade into it)
# ─────────────────────────────────────────────────────────────────────────
func _build_merge(duration: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return

	# Blend the rune colors into the merged orb tint.
	var blended: Color = _blend_colors(_slot_colors)

	# Merged orb — abyss glyph rendered through the casting-glyph shader (same
	# treatment as the in-flight halos, scaled up and blended-tinted). Bloom /
	# hold / fade is driven by the shader's `intensity` parameter so the orb
	# feels like a charging energy core, not a static soft disc.
	var orb_pair: Array = _make_glyph_halo_at(_merge_position, MERGE_ORB_SIZE_PX, blended)
	_merged_orb = orb_pair[0]
	_merged_orb_mat = orb_pair[1]
	_merged_orb.z_index = 252
	_merged_orb.z_as_relative = false
	# Override the in-flight halo's defaults — the merged orb wants a thicker
	# line and a touch of white-mix at peak so the convergence reads as bright.
	_merged_orb_mat.set_shader_parameter("intensity", 0.0)
	_merged_orb_mat.set_shader_parameter("thickness", MERGE_ORB_THICKNESS)
	host.add_child(_merged_orb)

	# Tokens collapse into the orb — fast convergence + alpha fade.
	for i in _flight_tokens.size():
		var token: Control = _flight_tokens[i]
		var halo: Control = _flight_halos[i]
		if token != null and is_instance_valid(token):
			var tw_token := create_tween().set_parallel(true)
			tw_token.tween_property(token, "position",
					_merge_position - token.size * 0.5, duration * 0.30) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw_token.tween_property(token, "modulate:a", 0.0, duration * 0.30) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw_token.tween_property(token, "scale", Vector2(0.4, 0.4), duration * 0.30) \
				.set_trans(Tween.TRANS_SINE)
			tw_token.chain().tween_callback(token.queue_free)
		if halo != null and is_instance_valid(halo):
			var tw_halo := create_tween().set_parallel(true)
			tw_halo.tween_property(halo, "modulate:a", 0.0, duration * 0.30) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw_halo.tween_property(halo, "position",
					_merge_position - halo.size * 0.5, duration * 0.30) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw_halo.tween_property(halo, "scale", Vector2(0.5, 0.5), duration * 0.30) \
				.set_trans(Tween.TRANS_SINE)
			tw_halo.chain().tween_callback(halo.queue_free)

	# Orb bloom — alpha pops in fast, then shader intensity ramps up to a
	# saturated peak through the hold, and fades out as the phase ends. The
	# tail VFX (e.g. DemonAscendantRitualVFX) spawns its projectiles at phase
	# start so they appear to launch from the bright orb.
	var bloom_in: float  = duration * 0.35
	var hold:     float  = duration * 0.40
	var fade_out: float  = duration - bloom_in - hold

	# Alpha + scale punch on the orb itself so the whole element pops in.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_merged_orb, "modulate:a", 1.0, bloom_in) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_merged_orb, "scale", Vector2(1.15, 1.15), bloom_in) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(_merged_orb, "scale", Vector2(1.0, 1.0), hold) \
		.set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(_merged_orb, "modulate:a", 0.0, fade_out) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_merged_orb, "scale", Vector2(1.40, 1.40), fade_out) \
		.set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(_merged_orb.queue_free)

	# Shader intensity ramp — drives the gradient halo's brightness so the
	# orb reads as "charging up", not as a static glow. White-mix nudges
	# toward white at peak so the convergence flashes properly.
	var orb_mat := _merged_orb_mat
	var tw_shader := create_tween().set_parallel(true)
	tw_shader.tween_method(func(v: float) -> void:
			if orb_mat != null: orb_mat.set_shader_parameter("intensity", v),
			0.0, MERGE_ORB_INTENSITY_PEAK, bloom_in) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_shader.tween_method(func(v: float) -> void:
			if orb_mat != null: orb_mat.set_shader_parameter("white_mix", v),
			0.0, MERGE_ORB_WHITE_MIX_PEAK, bloom_in) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_shader.chain().tween_method(func(v: float) -> void:
			if orb_mat != null: orb_mat.set_shader_parameter("intensity", v),
			MERGE_ORB_INTENSITY_PEAK, MERGE_ORB_INTENSITY_PEAK * 0.85, hold) \
		.set_trans(Tween.TRANS_SINE)
	tw_shader.chain().tween_method(func(v: float) -> void:
			if orb_mat != null: orb_mat.set_shader_parameter("intensity", v),
			MERGE_ORB_INTENSITY_PEAK * 0.85, 0.0, fade_out) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

## Per-rune color (defaults to abyssal violet if missing or transparent).
func _color_at(i: int) -> Color:
	var c: Color = Color(0.55, 0.18, 0.85, 1.0)
	if i < _slot_colors.size():
		var entry: Variant = _slot_colors[i]
		if entry is Color and (entry as Color).a > 0.0:
			c = entry as Color
	return c

func _art_at(i: int) -> Texture2D:
	if i < _rune_arts.size():
		var entry: Variant = _rune_arts[i]
		if entry is Texture2D:
			return entry as Texture2D
	return null

## Build a glow sprite centered at the given slot's center. Additive.
func _make_glow_at_slot(slot: Control, size: float, tint: Color, alpha: float) -> TextureRect:
	var center: Vector2 = slot.global_position + slot.size * 0.5
	var s := _make_glow_at(center, size, tint, alpha)
	s.z_index = 247
	s.z_as_relative = false
	return s

## Build a casting-glyph-style halo at the given screen center: a soft
## gradient radial circle BEHIND a shader-treated abyss glyph IN FRONT.
## Mirrors the visual language of CastingWindupVFX so the runes feel like
## charging energy elements, not flat silhouettes or static glow discs.
##
## Returns [container, shader_material]:
##   - container: a Control sized `size×size` with both halo + glyph inside,
##     so callers can move/scale/fade the whole element via the container's
##     position/scale/modulate.a.
##   - shader_material: the glyph's ShaderMaterial — callers animate its
##     `intensity` to drive the charge-up brightness.
func _make_glyph_halo_at(center: Vector2, size: float, color: Color) -> Array:
	var container := Control.new()
	container.set_size(Vector2(size, size))
	container.position      = center - Vector2(size, size) * 0.5
	container.pivot_offset  = Vector2(size, size) * 0.5
	container.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	container.modulate      = Color(1, 1, 1, 0)  # fade in via tween

	# ── Gradient halo behind — soft radial smoothstep^2 falloff. Tint is
	#    channel-suppressed so additive blending preserves hue at peak instead
	#    of washing to white (the trick CastingWindupVFX uses).
	var halo_size: float = size * GRADIENT_HALO_SIZE_MULT
	var halo_offset: Vector2 = (Vector2(size, size) - Vector2(halo_size, halo_size)) * 0.5
	var halo_tint: Color = _channel_suppress(color)
	var halo := TextureRect.new()
	halo.texture       = _get_gradient_halo_texture()
	halo.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	halo.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	halo.set_size(Vector2(halo_size, halo_size))
	halo.position      = halo_offset
	halo.pivot_offset  = Vector2(halo_size, halo_size) * 0.5
	halo.modulate      = Color(halo_tint.r, halo_tint.g, halo_tint.b, GRADIENT_HALO_PEAK_ALPHA)
	var halo_mat := CanvasItemMaterial.new()
	halo_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = halo_mat
	container.add_child(halo)

	# ── Shader-treated glyph in front — bold-line silhouette with the bloom
	#    tied to the shader `intensity` parameter (caller animates it).
	var glyph := TextureRect.new()
	glyph.texture       = TEX_HALO_GLYPH
	glyph.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	glyph.set_size(Vector2(size, size))

	var glyph_mat := ShaderMaterial.new()
	glyph_mat.shader = SHADER_GLYPH_GLOW
	glyph_mat.set_shader_parameter("intensity",  RUNE_HALO_INTENSITY_BASE)
	glyph_mat.set_shader_parameter("tint",       color)
	glyph_mat.set_shader_parameter("white_mix",  0.0)
	glyph_mat.set_shader_parameter("thickness",  RUNE_HALO_THICKNESS)
	glyph_mat.set_shader_parameter("tex_size",   Vector2(TEX_HALO_GLYPH.get_width(), TEX_HALO_GLYPH.get_height()))
	glyph.material = glyph_mat
	container.add_child(glyph)

	return [container, glyph_mat]

## Channel-suppression for halo tint so additive blending doesn't wash to
## white at peak. Same trick as CastingWindupVFX.HALO_SCALE_*. Picks
## suppression weights based on which channel dominates the source color so
## the halo stays close to the rune's identity hue.
func _channel_suppress(c: Color) -> Color:
	# Find dominant channel; scale others down. Output is roughly the same
	# perceived hue at deeper saturation. Defaults match the abyss palette.
	var r: float = c.r
	var g: float = c.g
	var b: float = c.b
	var max_ch: float = max(max(r, g), b)
	if max_ch <= 0.001:
		return c
	# Suppress non-dominant channels to ~30%, dominant stays full. Shifts the
	# additive output away from a white wash while preserving the hue.
	var sr: float = 0.30 if r < max_ch else 1.0
	var sg: float = 0.30 if g < max_ch else 1.0
	var sb: float = 0.30 if b < max_ch else 1.0
	return Color(r * sr, g * sg, b * sb, c.a)

# Soft radial gradient texture (smoothstep^2 falloff) — built once, shared.
# Same construction as CastingWindupVFX._get_glow_texture so the halos read
# identical to the casting windup the user explicitly approved.
const _GRADIENT_HALO_TEX_SIZE: int = 256
static var _gradient_halo_tex: ImageTexture = null

static func _get_gradient_halo_texture() -> ImageTexture:
	if _gradient_halo_tex != null:
		return _gradient_halo_tex
	var img := Image.create(_GRADIENT_HALO_TEX_SIZE, _GRADIENT_HALO_TEX_SIZE,
			false, Image.FORMAT_RGBA8)
	var centre: float = float(_GRADIENT_HALO_TEX_SIZE) * 0.5
	for y in _GRADIENT_HALO_TEX_SIZE:
		for x in _GRADIENT_HALO_TEX_SIZE:
			var dx: float = (float(x) - centre) / centre
			var dy: float = (float(y) - centre) / centre
			var r: float = sqrt(dx * dx + dy * dy)
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)  # smoothstep
			a = a * a                    # bias toward bright-centre / soft-outer
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_gradient_halo_tex = ImageTexture.create_from_image(img)
	return _gradient_halo_tex

## Build a glow sprite centered at a screen position. Additive.
func _make_glow_at(center: Vector2, size: float, tint: Color, alpha: float) -> TextureRect:
	var s := TextureRect.new()
	s.texture       = TEX_GLOW
	s.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	s.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	s.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	s.set_size(Vector2(size, size))
	s.position      = center - Vector2(size, size) * 0.5
	s.pivot_offset  = Vector2(size, size) * 0.5
	s.modulate      = Color(tint.r, tint.g, tint.b, alpha)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	return s

## Build the in-flight rune token — bare rune art only, no soft-glow background
## disc. The shader-driven halo (built separately via _make_glyph_halo_at)
## supplies all the surrounding glow; the token itself reads as a clean rune.
##
## Fallback: when a rune has no `battlefield_art_path` we render the abyss
## glyph through the casting-glyph shader instead, so the token still has a
## visible silhouette (rather than vanishing into nothing).
func _make_token_at(center: Vector2, size: float, tint: Color, art: Texture2D) -> Control:
	var holder := Control.new()
	holder.set_size(Vector2(size, size))
	holder.position = center - Vector2(size, size) * 0.5
	holder.pivot_offset = Vector2(size, size) * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate = Color(1, 1, 1, 0)  # fade in during liftoff
	holder.scale = Vector2(0.7, 0.7)

	if art != null:
		var art_rect := TextureRect.new()
		art_rect.texture       = art
		art_rect.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
		art_rect.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art_rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		art_rect.set_size(Vector2(size, size))
		holder.add_child(art_rect)
	else:
		# Fallback — abyss glyph, run through the same shader as the halo so
		# the silhouette stays consistent with the bold-line halo style.
		var glyph := TextureRect.new()
		glyph.texture       = TEX_HALO_GLYPH
		glyph.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		glyph.set_size(Vector2(size, size))
		var mat := ShaderMaterial.new()
		mat.shader = SHADER_GLYPH_GLOW
		mat.set_shader_parameter("intensity",  1.2)
		mat.set_shader_parameter("tint",       _brighten(tint, 1.30))
		mat.set_shader_parameter("white_mix",  0.10)
		mat.set_shader_parameter("thickness",  4.0)
		mat.set_shader_parameter("tex_size",   Vector2(TEX_HALO_GLYPH.get_width(), TEX_HALO_GLYPH.get_height()))
		glyph.material = mat
		holder.add_child(glyph)

	return holder

## Lighten a color by `mult` per channel, clamping to 1.0.
func _brighten(c: Color, mult: float) -> Color:
	return Color(
		clampf(c.r * mult, 0.0, 1.0),
		clampf(c.g * mult, 0.0, 1.0),
		clampf(c.b * mult, 0.0, 1.0),
		c.a)

## Average an Array of Colors. Returns abyssal violet if empty.
func _blend_colors(arr: Array) -> Color:
	if arr.is_empty():
		return Color(0.55, 0.18, 0.85, 1.0)
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	var n: int = 0
	for c in arr:
		if c is Color and (c as Color).a > 0.0:
			r += (c as Color).r
			g += (c as Color).g
			b += (c as Color).b
			n += 1
	if n <= 0:
		return Color(0.55, 0.18, 0.85, 1.0)
	return Color(r / float(n), g / float(n), b / float(n), 1.0)
