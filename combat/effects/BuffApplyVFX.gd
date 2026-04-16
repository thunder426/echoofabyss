## BuffApplyVFX.gd
## Generic "minion gets buffed" VFX — the shared language for every
## player-played buff (on-play minion buffs, spell buffs). Per-card flavor
## VFX can run as an optional prelude before the common phases.
##
## Phases (common to every buff):
##   1. Blessing surge — shader-driven light shaft + textured glow particles
##                       rise through the slot with upward-scrolling wisps
##   2. Silhouette flash — low-alpha white-green pulse over the minion art
##   3. Stat label pulses — ATK then HP, each spawning BuffChevronVFX
##   4. Lingering motes — textured soft-glow motes drift and pulse briefly
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
const SURGE_TINT_CORE: Color = Color(1.00, 0.92, 0.55, 1.0)   # warm gold core
const SURGE_TINT_EDGE: Color = Color(0.55, 1.00, 0.65, 1.0)   # green edge glow
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

# --- Motes ---------------------------------------------------------------
const MOTE_COUNT:        int = 5
const MOTE_MIN_SIZE:     float = 10.0
const MOTE_MAX_SIZE:     float = 18.0
const MOTE_COLOR:        Color = Color(0.85, 1.00, 0.70, 0.85)

# ── Cached runtime glow texture ─────────────────────────────────────────
# A soft circular radial gradient built once and reused across every
# BuffApplyVFX instance. Avoids needing a PNG asset, stays pixel-perfect
# at any size thanks to TextureRect stretching.
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
			# Soft falloff — bright core, smooth edge. pow(1-r, 2.2) gives a
			# glow that stays visible in the center without a hard ring.
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			a = pow(a, 2.2)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex

var _slot: Control = null
var _atk_delta: int = 0
var _hp_delta: int = 0
var _prelude: Callable = Callable()


## Create a buff VFX for a slot.
## atk_delta/hp_delta — signed; only non-zero stats get a pulse + chevron.
## prelude — optional Callable() -> void (can be async with await). Runs
##           before the common phases so per-card flavor plays first.
##           Callers use this for "feel the difference" moments (e.g. a
##           rising flame column for Rage, falling leaves for Regrowth).
static func create(slot: Control, atk_delta: int, hp_delta: int,
		prelude: Callable = Callable()) -> BuffApplyVFX:
	var vfx := BuffApplyVFX.new()
	vfx._slot       = slot
	vfx._atk_delta  = atk_delta
	vfx._hp_delta   = hp_delta
	vfx._prelude    = prelude
	vfx.impact_count = 0   # apply VFX — no damage gate
	return vfx


func _play() -> void:
	var host: Node = get_parent()
	if _slot == null or not is_instance_valid(_slot) or host == null:
		finished.emit()
		queue_free()
		return

	# Optional per-card prelude (fire-and-await).
	if _prelude.is_valid():
		await _prelude.call()
		if not is_inside_tree() or not is_instance_valid(_slot):
			finished.emit()
			queue_free()
			return

	var slot_rect: Rect2 = Rect2(_slot.global_position, _slot.size)

	# ── Phase 1: Blessing surge ─────────────────────────────────────────
	_spawn_surge(host, slot_rect)

	# Schedule flash to start partway through the surge
	var timer := get_tree().create_timer(FLASH_START_AT)
	await timer.timeout
	if not is_inside_tree() or not is_instance_valid(_slot):
		finished.emit()
		queue_free()
		return
	_spawn_silhouette_flash(host, slot_rect)

	# Wait for surge phase to finish before pulsing labels
	var remain := SURGE_DURATION - FLASH_START_AT
	await get_tree().create_timer(maxf(remain, 0.0)).timeout
	if not is_inside_tree() or not is_instance_valid(_slot):
		finished.emit()
		queue_free()
		return

	# ── Phase 3: Sequential stat label pulses ───────────────────────────
	if _atk_delta != 0:
		_pulse_stat("atk")
		await get_tree().create_timer(PULSE_GAP).timeout
		if not is_inside_tree() or not is_instance_valid(_slot):
			finished.emit()
			queue_free()
			return
	if _hp_delta != 0:
		_pulse_stat("hp")

	# ── Phase 4: Lingering motes ────────────────────────────────────────
	_spawn_motes(host, slot_rect)

	await get_tree().create_timer(MOTE_DURATION).timeout
	finished.emit()
	queue_free()


# ─────────────────────────────────────────────────────────────────────────
# Phase implementations
# ─────────────────────────────────────────────────────────────────────────

## Phase 1 — a shader-driven light shaft rises through the slot with
## upward-scrolling noise wisps, accompanied by a handful of textured glow
## particles that drift up and fade. The shader handles the "column of light"
## feel; the particles sell the "motes drawn into the unit" beat.
func _spawn_surge(host: Node, rect: Rect2) -> void:
	# ── Shader shaft (one ColorRect with the blessing_shaft shader) ──
	var shaft := ColorRect.new()
	shaft.color = Color(1.0, 1.0, 1.0, 1.0)  # shader overrides
	shaft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shaft.z_index = 18
	shaft.z_as_relative = false
	# Extend slightly above and below the slot so the feather doesn't
	# cut sharply at the slot edge.
	var shaft_pad_top: float = 18.0
	var shaft_pad_bot: float = 10.0
	shaft.position = Vector2(rect.position.x, rect.position.y - shaft_pad_top)
	shaft.size     = Vector2(rect.size.x, rect.size.y + shaft_pad_top + shaft_pad_bot)

	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SHAFT
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("time_offset", randf() * 10.0)
	mat.set_shader_parameter("tint_core", SURGE_TINT_CORE)
	mat.set_shader_parameter("tint_edge", SURGE_TINT_EDGE)
	mat.set_shader_parameter("intensity", 1.6)
	mat.set_shader_parameter("column_width", 0.55)
	mat.set_shader_parameter("wisp_speed", 2.4)
	mat.set_shader_parameter("wisp_scale", 7.0)
	shaft.material = mat
	host.add_child(shaft)

	var tw_shaft := create_tween()
	tw_shaft.tween_method(func(p: float) -> void:
			mat.set_shader_parameter("progress", p),
			0.0, 1.0, SURGE_DURATION).set_trans(Tween.TRANS_SINE)
	tw_shaft.tween_callback(shaft.queue_free)

	# ── Textured glow particles rising through the shaft ──
	var glow_tex: Texture2D = _get_glow_texture()
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
		# Warm-gold tint with some per-particle jitter toward green.
		var mix_t: float = randf()
		var tint: Color = SURGE_TINT_CORE.lerp(SURGE_TINT_EDGE, mix_t * 0.6)
		tint.a = 0.0
		p.modulate = tint
		var add_mat := CanvasItemMaterial.new()
		add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = add_mat
		host.add_child(p)

		var delay: float = randf() * 0.20
		var peak_alpha: float = SURGE_PARTICLE_TINT.a * (0.7 + randf() * 0.3)
		# Rise in parallel with the alpha in/out sequence.
		var tw_rise := create_tween()
		tw_rise.tween_interval(delay)
		tw_rise.tween_property(p, "position:y", end_y, SURGE_DURATION - delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		# Horizontal wobble for organic motion.
		var wobble_x: float = start_x + (randf() - 0.5) * 24.0
		tw_rise.parallel().tween_property(p, "position:x", wobble_x, SURGE_DURATION - delay).set_trans(Tween.TRANS_SINE)

		var tw_alpha := create_tween()
		tw_alpha.tween_interval(delay)
		tw_alpha.tween_property(p, "modulate:a", peak_alpha, (SURGE_DURATION - delay) * 0.35).set_trans(Tween.TRANS_SINE)
		tw_alpha.tween_property(p, "modulate:a", 0.0, (SURGE_DURATION - delay) * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw_alpha.tween_callback(p.queue_free)


## Phase 2 — duplicate the minion art and flash a low-alpha white-green tint
## on top of it, so it reads as "the minion itself got empowered."
func _spawn_silhouette_flash(host: Node, rect: Rect2) -> void:
	var flash := ColorRect.new()
	flash.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.position = rect.position
	flash.size     = rect.size
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


## Phase 3 — pulse a stat label (scale-up + color flash), and spawn a chevron
## next to it. Mirrors the existing Pack Instinct animation so buffs feel
## consistent with the established language.
func _pulse_stat(which: String) -> void:
	if not is_instance_valid(_slot):
		return
	var lbl: Label = null
	var pulse_color: Color = PULSE_COLOR_ATK
	if which == "atk":
		lbl = _slot.get("_atk_label")
		pulse_color = PULSE_COLOR_ATK
	elif which == "hp":
		lbl = _slot.get("_hp_label")
		pulse_color = PULSE_COLOR_HP
	if lbl == null or not is_instance_valid(lbl):
		return

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
	# Stat labels are center-aligned within a wide column, so we measure the
	# actual rendered text width and park the chevron directly next to the
	# digits — not at the column edge. ATK goes to the right of the number,
	# HP goes to the left of it.
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


## Phase 4 — textured soft-glow motes drift upward and sideways while pulsing
## in scale, so the buff feels "settled" rather than just flashed. Uses the
## same runtime glow texture as the surge particles for visual consistency.
func _spawn_motes(host: Node, rect: Rect2) -> void:
	var glow_tex: Texture2D = _get_glow_texture()
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
		mote.modulate = Color(MOTE_COLOR.r, MOTE_COLOR.g, MOTE_COLOR.b, 0.0)
		var add_mat := CanvasItemMaterial.new()
		add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		mote.material = add_mat

		# Spawn around the minion's upper body — jittered, biased upward.
		var start_x: float = rect.position.x + rect.size.x * (0.20 + randf() * 0.60) - sz * 0.5
		var start_y: float = rect.position.y + rect.size.y * (0.18 + randf() * 0.38) - sz * 0.5
		mote.position = Vector2(start_x, start_y)
		# Small drift — mostly up, with lateral variation.
		var drift_x: float = (randf() - 0.5) * 32.0
		var drift_y: float = -12.0 - randf() * 18.0
		var start_scale: float = 0.6 + randf() * 0.2
		mote.scale = Vector2(start_scale, start_scale)
		host.add_child(mote)

		var delay: float = randf() * 0.10
		var peak_alpha: float = MOTE_COLOR.a * (0.75 + randf() * 0.25)
		# Alpha: fade in → hold → fade out.
		var tw_alpha := create_tween()
		tw_alpha.tween_interval(delay)
		tw_alpha.tween_property(mote, "modulate:a", peak_alpha, MOTE_DURATION * 0.25).set_trans(Tween.TRANS_SINE)
		tw_alpha.tween_property(mote, "modulate:a", 0.0, MOTE_DURATION * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw_alpha.tween_callback(mote.queue_free)
		# Drift upward/sideways.
		var tw_drift := create_tween()
		tw_drift.tween_interval(delay)
		tw_drift.tween_property(mote, "position", mote.position + Vector2(drift_x, drift_y), MOTE_DURATION - delay).set_trans(Tween.TRANS_SINE)
		# Gentle scale pulse — grows then shrinks back slightly for sparkle.
		var tw_scale := create_tween()
		tw_scale.tween_interval(delay)
		tw_scale.tween_property(mote, "scale", Vector2(1.05, 1.05), MOTE_DURATION * 0.35).set_trans(Tween.TRANS_SINE)
		tw_scale.tween_property(mote, "scale", Vector2(0.75, 0.75), MOTE_DURATION * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
