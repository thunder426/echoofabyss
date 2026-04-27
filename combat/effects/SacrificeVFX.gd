## SacrificeVFX.gd
## Generic "minion is ritually consumed" VFX — the shared language for every
## sacrifice (Abyssal Sacrifice, Blood Pact, Soul Shatter, Void Devourer).
## Per-card flavor VFX can run as an optional prelude before the common phases.
##
## Phases (common to every sacrifice):
##   0. Dagger plunge — ritual dagger drops from above the slot, snaps upright
##                      at the card center with a screen-shake and flash, then
##                      holds briefly before fading with the sigil bloom
##   1. Rune sigil   — violet radial halo blooms beneath the minion
##   2. Drain        — dark overlay that sinks inward, desaturating the art
##   3. Shatter      — violet motes burst outward-then-downward with gravity
##
## Spawn via VfxController.spawn() — do not parent manually.
## Driven by SacrificeSystem.bus() `sacrifice_occurred` signal; CombatScene
## listens and spawns one VFX per sacrifice. Void Devourer emits twice for
## two adjacent sacs — each runs in parallel on its own slot.
class_name SacrificeVFX
extends BaseVfx

# --- Timing --------------------------------------------------------------
const DAGGER_APPROACH:  float = 0.30   # descent from above → impact at card center
const DAGGER_HOLD:      float = 0.45   # embedded pause — blade stays in while blood flies
const DAGGER_FADE:      float = 0.20   # knife fades out as the sigil blooms
const DAGGER_DURATION:  float = DAGGER_APPROACH + DAGGER_HOLD + DAGGER_FADE
# Minion card stays visible through the entire dagger animation (approach +
# hold + fade) and only begins fading once the dagger is gone. Used by
# CombatScene._schedule_sacrifice_unfreeze to know when to clear the slot.
const MINION_VISIBLE_DURATION: float = DAGGER_DURATION
const MINION_FADE_DURATION:    float = 0.15
const SIGIL_DURATION:   float = 0.35
const DRAIN_DURATION:   float = 0.35
const DRAIN_START_AT:   float = 0.20  # drain begins partway through sigil bloom
const SHATTER_DURATION: float = 0.45

# --- Dagger (Phase 0) ---------------------------------------------------
const TEX_DAGGER: Texture2D = preload("res://assets/art/fx/sacrifice_dagger.png")
const DAGGER_SIZE_MULT:     float = 1.20   # dagger height relative to slot height
const DAGGER_APPROACH_START_Y_MULT: float = -0.80  # start above the slot top
const DAGGER_START_TILT_DEG: float = 18.0
const DAGGER_IMPACT_FLASH_ALPHA: float = 0.75
const DAGGER_IMPACT_FLASH_DURATION: float = 0.12
const DAGGER_SHAKE_AMPLITUDE: float = 4.0
const DAGGER_SHAKE_TICKS:     int   = 3

# Blood burst — fast radial spray at impact, upward-biased (physically right
# for a downward stab: blood sprays back along the blade's trajectory).
const BLOOD_BURST_COUNT:     int   = 18
const BLOOD_BURST_RADIUS:    float = 80.0
const BLOOD_BURST_DURATION:  float = 0.55
const BLOOD_HIGH_FLIER_RATIO: float = 0.35  # share that shoot extra-high
const BLOOD_HIGH_FLIER_MULT: float = 1.65  # how much farther high fliers go
const BLOOD_DRIP_COUNT:      int   = 4   # slow drips during the hold
const BLOOD_COLOR:           Color = Color(0.55, 0.05, 0.08, 0.95)  # crimson

# Entry wound — near-black violet blob over the blade tip. Doubles as visual
# explanation for why the blade tip is hidden (it's inside the card).
const WOUND_TINT:        Color = Color(0.06, 0.02, 0.08, 1.0)   # near-black, violet tint
const WOUND_SIZE_MULT:   float = 0.32   # size relative to dagger height
const WOUND_PEAK_ALPHA:  float = 0.88

# --- Sigil (additive radial halo under the minion) ----------------------
const SIGIL_SIZE_MULT:    float = 1.15   # halo size relative to slot's shortest dim
const SIGIL_TINT:         Color = Color(0.55, 0.18, 0.85, 1.0)  # abyssal violet
const SIGIL_PEAK_ALPHA:   float = 0.90

# --- Drain (dark overlay that sinks inward) ------------------------------
const DRAIN_TINT:         Color = Color(0.10, 0.04, 0.18, 1.0)  # near-black violet
const DRAIN_PEAK_ALPHA:   float = 0.75

# --- Shatter motes -------------------------------------------------------
const MOTE_COUNT:         int   = 10
const MOTE_MIN_SIZE:      float = 10.0
const MOTE_MAX_SIZE:      float = 20.0
const MOTE_TINT:          Color = Color(0.65, 0.28, 0.95, 0.85)  # violet motes
const MOTE_BURST_RADIUS:  float = 70.0

# ── Cached runtime glow texture (shared across sacrifice instances) ─────
# Same trick as BuffApplyVFX: build a soft radial gradient once and reuse
# for every halo/mote. Sacrifice keeps its own cache so the tint-free white
# source can be modulated independently of the buff cache.
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
var _prelude: Callable = Callable()


## Create a sacrifice VFX for a slot.
## prelude — optional Callable() -> void (may await). Runs before the common
##           phases so per-card flavor plays first (e.g. blood-red sigil for
##           Blood Pact instead of the default abyssal violet).
static func create(slot: Control, prelude: Callable = Callable()) -> SacrificeVFX:
	var vfx := SacrificeVFX.new()
	vfx._slot    = slot
	vfx._prelude = prelude
	vfx.impact_count = 0   # apply VFX — no damage gate
	return vfx


func _play() -> void:
	var host: Node = get_parent()
	if _slot == null or not is_instance_valid(_slot) or host == null:
		finished.emit()
		queue_free()
		return

	# Optional per-card prelude.
	if _prelude.is_valid():
		await _prelude.call()
		if not is_inside_tree() or not is_instance_valid(_slot):
			finished.emit()
			queue_free()
			return

	var slot_rect: Rect2 = Rect2(_slot.global_position, _slot.size)

	# ── Phase 0: Dagger plunge ─────────────────────────────────────────
	await _spawn_dagger_plunge(host, slot_rect)
	if not is_inside_tree() or not is_instance_valid(_slot):
		finished.emit()
		queue_free()
		return

	# ── Phase 1: Sigil bloom ────────────────────────────────────────────
	_spawn_sigil(host, slot_rect)

	# Phase 2 starts partway through the sigil so the beats overlap.
	await get_tree().create_timer(DRAIN_START_AT).timeout
	if not is_inside_tree() or not is_instance_valid(_slot):
		finished.emit()
		queue_free()
		return
	_spawn_drain(host, slot_rect)

	# Wait for sigil + drain to finish before shattering. The shatter beat
	# lines up with the actual kill — by the time motes spawn, the minion
	# visual is either gone or being cleared by _on_minion_vanished.
	var remain := maxf(SIGIL_DURATION - DRAIN_START_AT, 0.0) + DRAIN_DURATION
	await get_tree().create_timer(remain).timeout
	if not is_inside_tree():
		finished.emit()
		queue_free()
		return

	# ── Phase 3: Shatter into motes ─────────────────────────────────────
	_spawn_shatter(host, slot_rect)

	await get_tree().create_timer(SHATTER_DURATION).timeout
	finished.emit()
	queue_free()


# ─────────────────────────────────────────────────────────────────────────
# Phase implementations
# ─────────────────────────────────────────────────────────────────────────

## Phase 0 — the ritual dagger drops from above the slot, snaps upright at
## the card center with a screen-shake flash, holds embedded while blood
## drips from the blade tip, then fades out as the sigil bloom begins.
##
## Awaited (unlike the other phases) so the sigil doesn't start until the
## knife has clearly contacted the card — that's the beat that reads as
## "the sacrifice begins."
func _spawn_dagger_plunge(host: Node, rect: Rect2) -> void:
	var dagger := TextureRect.new()
	dagger.texture       = TEX_DAGGER
	dagger.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	dagger.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dagger.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	dagger.z_index       = 23
	dagger.z_as_relative = false
	# Size the dagger so its vertical extent is ~120% of slot height — the
	# blade overhangs the card slightly at rest so the impact point sits
	# firmly inside the card rather than hanging off the top.
	var dagger_h: float = rect.size.y * DAGGER_SIZE_MULT
	# Assume a 1:2 aspect for the sacrifice dagger asset (portrait crop).
	var dagger_w: float = dagger_h * 0.5
	dagger.set_size(Vector2(dagger_w, dagger_h))
	dagger.pivot_offset = Vector2(dagger_w * 0.5, dagger_h * 0.5)

	# Rest position: centered horizontally, vertically biased so the blade
	# tip lands near the slot's lower-middle (where the sacrificed minion's
	# torso would be). Pommel extends above the card frame.
	var rest_pos: Vector2 = Vector2(
		rect.position.x + (rect.size.x - dagger_w) * 0.5,
		rect.position.y + rect.size.y * 0.55 - dagger_h * 0.5
	)
	var start_pos: Vector2 = Vector2(
		rest_pos.x,
		rect.position.y + rect.size.y * DAGGER_APPROACH_START_Y_MULT
	)
	dagger.position   = start_pos
	dagger.rotation   = deg_to_rad(DAGGER_START_TILT_DEG)
	dagger.modulate   = Color(1.0, 1.0, 1.0, 0.7)   # starts semi-transparent (incoming)
	dagger.scale      = Vector2(1.15, 1.15)          # slight "coming toward camera"
	host.add_child(dagger)

	# Approach — ease-IN descent so it looks thrown, not floated.
	var tw_move := create_tween().set_parallel(true)
	tw_move.tween_property(dagger, "position", rest_pos, DAGGER_APPROACH)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw_move.tween_property(dagger, "rotation", 0.0, DAGGER_APPROACH)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw_move.tween_property(dagger, "modulate:a", 1.0, DAGGER_APPROACH * 0.4)\
			.set_trans(Tween.TRANS_SINE)
	tw_move.tween_property(dagger, "scale", Vector2.ONE, DAGGER_APPROACH)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(DAGGER_APPROACH).timeout
	if not is_inside_tree() or not is_instance_valid(dagger):
		return

	# Impact beat — flash, shake, blood spray, entry wound. Blade tip sits
	# roughly at (rest_pos.x + dagger_w * 0.5, rest_pos.y + dagger_h * 0.92).
	var impact_point: Vector2 = Vector2(
		rest_pos.x + dagger_w * 0.5,
		rest_pos.y + dagger_h * 0.92
	)
	AudioManager.play_sfx("res://assets/audio/sfx/spells/sacrifice_dagger_stab.wav", -4.0)
	_spawn_impact_flash(host, impact_point, dagger_w)
	_spawn_blood_burst(host, impact_point)
	_spawn_entry_wound(host, impact_point, dagger_h)
	_spawn_blood_drips(host, impact_point)
	if _slot != null and is_instance_valid(_slot):
		shake(_slot, DAGGER_SHAKE_AMPLITUDE, DAGGER_SHAKE_TICKS)

	# Recoil — tiny bounce up then settle back, simulates a real stab rebound.
	var recoil_up: Vector2 = Vector2(rest_pos.x, rest_pos.y - 6.0)
	var tw_recoil := create_tween()
	tw_recoil.tween_property(dagger, "position", recoil_up, 0.08)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_recoil.tween_property(dagger, "position", rest_pos, 0.10)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Hold — knife stays embedded so the brain reads "stuck in the card."
	await get_tree().create_timer(DAGGER_HOLD).timeout
	if not is_inside_tree() or not is_instance_valid(dagger):
		return

	# Fade out as the sigil bloom is about to take over.
	var tw_fade := create_tween()
	tw_fade.tween_property(dagger, "modulate:a", 0.0, DAGGER_FADE)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw_fade.tween_callback(dagger.queue_free)
	await get_tree().create_timer(DAGGER_FADE).timeout


## Brief white flash at the blade's impact point — sells the "contact"
## frame without adding any new assets.
func _spawn_impact_flash(host: Node, point: Vector2, size: float) -> void:
	var glow_tex: Texture2D = _get_glow_texture()
	var flash := TextureRect.new()
	flash.texture       = glow_tex
	flash.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	flash.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flash.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 22
	flash.z_as_relative = false
	var fsz: float = size * 1.1
	flash.set_size(Vector2(fsz, fsz))
	flash.position = point - Vector2(fsz, fsz) * 0.5
	flash.pivot_offset = Vector2(fsz, fsz) * 0.5
	flash.modulate = Color(1.0, 0.92, 0.85, DAGGER_IMPACT_FLASH_ALPHA)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = mat
	host.add_child(flash)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "modulate:a", 0.0, DAGGER_IMPACT_FLASH_DURATION)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(flash, "scale", Vector2(1.6, 1.6), DAGGER_IMPACT_FLASH_DURATION)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(flash.queue_free)


## Impact blood burst — fast radial spray, upward-biased. Physically right
## for a downward stab: blood sprays back along the blade's incoming arc,
## not straight down. Each droplet flies out, arcs over, and falls with
## gravity before fading. Separate from the slower drip during the hold.
func _spawn_blood_burst(host: Node, point: Vector2) -> void:
	var glow_tex: Texture2D = _get_glow_texture()
	for i in BLOOD_BURST_COUNT:
		var drop := TextureRect.new()
		drop.texture       = glow_tex
		drop.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
		drop.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		drop.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		drop.z_index = 21
		drop.z_as_relative = false
		var sz: float = 9.0 + randf() * 7.0
		drop.set_size(Vector2(sz, sz))
		drop.pivot_offset = Vector2(sz, sz) * 0.5
		# Teardrop-ish proportion (vertically stretched) so the droplets
		# don't read as generic round motes.
		drop.scale = Vector2(0.7, 1.1)
		drop.modulate = Color(BLOOD_COLOR.r, BLOOD_COLOR.g, BLOOD_COLOR.b, 0.0)
		drop.position = point - Vector2(sz, sz) * 0.5
		host.add_child(drop)

		# Upward-biased fan: angle centered on -π/2 (straight up) with a
		# tight ±0.70 rad (~±40°) spread, so nearly every droplet shoots
		# upward-and-outward. A fraction of "high fliers" get a radius
		# boost and tighter cone, arcing noticeably higher than the pack.
		# Angle math: 0 = right, π/2 = down, -π/2 = up.
		var is_high_flier: bool = randf() < BLOOD_HIGH_FLIER_RATIO
		var spread: float = 0.80 if is_high_flier else 1.40
		var angle: float = -PI * 0.5 + (randf() - 0.5) * spread
		var flier_mult: float = BLOOD_HIGH_FLIER_MULT if is_high_flier else 1.0
		var radius: float = BLOOD_BURST_RADIUS * (0.60 + randf() * 0.55) * flier_mult
		var burst_offset: Vector2 = Vector2(cos(angle) * radius, sin(angle) * radius)
		# Gravity pulls every droplet down during the back half. High fliers
		# fall a proportionally longer distance since they started higher.
		var fall_y: float = 40.0 + randf() * 22.0
		if is_high_flier:
			fall_y += 28.0
		var fall_offset: Vector2 = Vector2(
			burst_offset.x + (randf() - 0.5) * 8.0,
			burst_offset.y + fall_y
		)

		var delay: float = randf() * 0.05
		var peak_alpha: float = BLOOD_COLOR.a * (0.85 + randf() * 0.15)
		var rise_t: float = BLOOD_BURST_DURATION * 0.35
		var fall_t: float = BLOOD_BURST_DURATION - rise_t

		# Position — spray outward fast, then fall under gravity.
		var tw_pos := create_tween()
		tw_pos.tween_interval(delay)
		tw_pos.tween_property(drop, "position",
				point - Vector2(sz, sz) * 0.5 + burst_offset,
				rise_t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw_pos.tween_property(drop, "position",
				point - Vector2(sz, sz) * 0.5 + fall_offset,
				fall_t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

		# Alpha — pop in, hold through rise, fade through fall.
		var tw_alpha := create_tween()
		tw_alpha.tween_interval(delay)
		tw_alpha.tween_property(drop, "modulate:a", peak_alpha, 0.05)\
				.set_trans(Tween.TRANS_SINE)
		tw_alpha.tween_property(drop, "modulate:a", peak_alpha, rise_t - 0.05)
		tw_alpha.tween_property(drop, "modulate:a", 0.0, fall_t)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw_alpha.tween_callback(drop.queue_free)


## Entry wound — a near-black violet blob at the blade tip. Hides the tip
## so the dagger reads as embedded rather than resting on top of the card,
## and also serves as the visual stab wound. Sits on the blade (z_index 24)
## and fades out with the dagger.
func _spawn_entry_wound(host: Node, point: Vector2, dagger_h: float) -> void:
	var glow_tex: Texture2D = _get_glow_texture()
	var wound := TextureRect.new()
	wound.texture       = glow_tex
	wound.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	wound.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wound.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	wound.z_index = 24   # over the dagger (z=23) so the tip is hidden
	wound.z_as_relative = false
	var wsz: float = dagger_h * WOUND_SIZE_MULT
	wound.set_size(Vector2(wsz, wsz))
	wound.pivot_offset = Vector2(wsz, wsz) * 0.5
	# Center the wound slightly above the raw blade tip so it covers the
	# last ~25% of the blade — that's enough to hide the tip without
	# chopping off the whole blade.
	wound.position = point - Vector2(wsz * 0.5, wsz * 0.65)
	wound.modulate = Color(WOUND_TINT.r, WOUND_TINT.g, WOUND_TINT.b, 0.0)
	wound.scale = Vector2(0.6, 0.45)  # oblong — wider than tall, reads as a cut
	host.add_child(wound)

	var tw := create_tween().set_parallel(true)
	# Expand + fade in on impact.
	tw.tween_property(wound, "modulate:a", WOUND_PEAK_ALPHA, 0.08)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(wound, "scale", Vector2(1.0, 0.75), 0.12)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Hold for the embedded phase, then fade with the dagger.
	tw.chain().tween_property(wound, "modulate:a", WOUND_PEAK_ALPHA, DAGGER_HOLD - 0.08)
	tw.chain().tween_property(wound, "modulate:a", 0.0, DAGGER_FADE)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(wound.queue_free)


## Slow blood drips from the embedded blade tip during the hold phase.
## Reads as "blood continues to seep from the wound" — distinct from the
## fast burst at impact. Fewer droplets, slower gravity, purely downward.
func _spawn_blood_drips(host: Node, point: Vector2) -> void:
	var glow_tex: Texture2D = _get_glow_texture()
	for i in BLOOD_DRIP_COUNT:
		var drop := TextureRect.new()
		drop.texture       = glow_tex
		drop.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
		drop.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		drop.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		drop.z_index = 21
		drop.z_as_relative = false
		var sz: float = 8.0 + randf() * 5.0
		drop.set_size(Vector2(sz, sz))
		drop.pivot_offset = Vector2(sz, sz) * 0.5
		drop.scale = Vector2(0.65, 1.25)
		drop.modulate = Color(BLOOD_COLOR.r, BLOOD_COLOR.g, BLOOD_COLOR.b, 0.0)
		drop.position = point - Vector2(sz, sz) * 0.5 \
				+ Vector2((randf() - 0.5) * 6.0, 0.0)
		host.add_child(drop)

		var fall_y: float = 26.0 + randf() * 18.0
		# Staggered start over the hold phase so drips look like a slow feed,
		# not a synchronized pulse.
		var delay: float = float(i) * (DAGGER_HOLD * 0.20) + randf() * 0.08
		var peak_alpha: float = BLOOD_COLOR.a * (0.8 + randf() * 0.2)
		var lifetime: float = DAGGER_HOLD + DAGGER_FADE - delay

		var tw_pos := create_tween()
		tw_pos.tween_interval(delay)
		tw_pos.tween_property(drop, "position",
				drop.position + Vector2((randf() - 0.5) * 4.0, fall_y),
				lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

		var tw_alpha := create_tween()
		tw_alpha.tween_interval(delay)
		tw_alpha.tween_property(drop, "modulate:a", peak_alpha, 0.10)\
				.set_trans(Tween.TRANS_SINE)
		tw_alpha.tween_property(drop, "modulate:a", peak_alpha, lifetime * 0.55)
		tw_alpha.tween_property(drop, "modulate:a", 0.0, lifetime * 0.35)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw_alpha.tween_callback(drop.queue_free)


## Phase 1 — a violet radial halo blooms beneath the minion art. The halo
## sits under the minion (z_index 17, below the slot's card layer if there
## is one, but above the board backdrop) and uses additive blend so it
## glows through whatever art is on the slot.
func _spawn_sigil(host: Node, rect: Rect2) -> void:
	var glow_tex: Texture2D = _get_glow_texture()
	var base_dim: float = minf(rect.size.x, rect.size.y)
	var sigil_size: float = base_dim * SIGIL_SIZE_MULT

	var halo := TextureRect.new()
	halo.texture       = glow_tex
	halo.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	halo.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	halo.set_size(Vector2(sigil_size, sigil_size))
	halo.pivot_offset  = Vector2(sigil_size, sigil_size) * 0.5
	halo.position      = rect.position + rect.size * 0.5 - Vector2(sigil_size, sigil_size) * 0.5
	halo.modulate      = Color(SIGIL_TINT.r, SIGIL_TINT.g, SIGIL_TINT.b, 0.0)
	halo.scale         = Vector2(0.75, 0.75)
	halo.z_index       = 17
	halo.z_as_relative = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = mat
	host.add_child(halo)

	# Bloom in, hold briefly, fade out as the drain takes over.
	var tw := create_tween().set_parallel(true)
	var bloom: float = SIGIL_DURATION * 0.45
	var fade:  float = SIGIL_DURATION - bloom
	tw.tween_property(halo, "modulate:a", SIGIL_PEAK_ALPHA, bloom).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(halo, "scale", Vector2(1.05, 1.05), bloom).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(halo, "modulate:a", 0.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(halo, "scale", Vector2(1.25, 1.25), fade).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(halo.queue_free)


## Phase 2 — a dark overlay materializes over the slot, starting at the
## edges and sinking inward, so the minion reads as being "drained" of
## light rather than just covered. Uses normal blend (not additive) so the
## overlay actually darkens the minion art.
func _spawn_drain(host: Node, rect: Rect2) -> void:
	var drain := ColorRect.new()
	drain.color = Color(DRAIN_TINT.r, DRAIN_TINT.g, DRAIN_TINT.b, 0.0)
	drain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drain.position = rect.position
	drain.size     = rect.size
	drain.pivot_offset = rect.size * 0.5
	drain.scale = Vector2(1.15, 1.15)  # starts slightly oversized, shrinks in
	drain.z_index = 19
	drain.z_as_relative = false
	host.add_child(drain)

	# Fade in + shrink to unit scale (sink inward), then a quick snap-out as
	# the minion vanishes. Half the drain is "grow dark", half is "snap".
	var tw := create_tween().set_parallel(true)
	var half := DRAIN_DURATION * 0.6
	tw.tween_property(drain, "color:a", DRAIN_PEAK_ALPHA, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(drain, "scale", Vector2.ONE, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(drain, "color:a", 0.0, DRAIN_DURATION - half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(drain, "scale", Vector2(0.7, 0.7), DRAIN_DURATION - half).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(drain.queue_free)


## Phase 3 — dark violet motes burst outward from the slot center, each on
## its own randomized arc, then fall a short distance before fading. Uses
## additive blend so the motes glow against dark backgrounds.
func _spawn_shatter(host: Node, rect: Rect2) -> void:
	var glow_tex: Texture2D = _get_glow_texture()
	var center: Vector2 = rect.position + rect.size * 0.5
	for i in MOTE_COUNT:
		var mote := TextureRect.new()
		mote.texture       = glow_tex
		mote.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
		mote.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mote.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		mote.z_index = 20
		mote.z_as_relative = false
		var sz: float = MOTE_MIN_SIZE + randf() * (MOTE_MAX_SIZE - MOTE_MIN_SIZE)
		mote.size = Vector2(sz, sz)
		mote.pivot_offset = mote.size * 0.5
		# Start clustered near the center, slight jitter so they don't all overlap.
		var jitter: Vector2 = Vector2(randf() - 0.5, randf() - 0.5) * 10.0
		mote.position = center - mote.size * 0.5 + jitter
		mote.modulate = Color(MOTE_TINT.r, MOTE_TINT.g, MOTE_TINT.b, 0.0)
		var add_mat := CanvasItemMaterial.new()
		add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		mote.material = add_mat
		host.add_child(mote)

		# Arc: burst outward on a random angle, with gravity pulling it down
		# over the back half so it reads as debris settling, not a symmetric
		# puff. Horizontal half-angle bias is slightly wider than vertical so
		# motes spread along the board rather than piling straight up.
		var angle: float = randf() * TAU
		var radius: float = MOTE_BURST_RADIUS * (0.55 + randf() * 0.55)
		var burst_x: float = cos(angle) * radius
		var burst_y: float = sin(angle) * radius * 0.75 - 8.0
		var fall_x: float = burst_x + (randf() - 0.5) * 8.0
		var fall_y: float = burst_y + 18.0 + randf() * 14.0  # gravity

		var delay: float = randf() * 0.06
		var peak_alpha: float = MOTE_TINT.a * (0.75 + randf() * 0.25)

		# Alpha: fade in fast → hold → fade out.
		var tw_alpha := create_tween()
		tw_alpha.tween_interval(delay)
		tw_alpha.tween_property(mote, "modulate:a", peak_alpha, SHATTER_DURATION * 0.20).set_trans(Tween.TRANS_SINE)
		tw_alpha.tween_property(mote, "modulate:a", 0.0, SHATTER_DURATION * 0.70).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw_alpha.tween_callback(mote.queue_free)

		# Position: burst out, then settle with gravity.
		var tw_pos := create_tween()
		tw_pos.tween_interval(delay)
		tw_pos.tween_property(mote, "position", center - mote.size * 0.5 + Vector2(burst_x, burst_y),
				SHATTER_DURATION * 0.40).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw_pos.tween_property(mote, "position", center - mote.size * 0.5 + Vector2(fall_x, fall_y),
				SHATTER_DURATION * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

		# Scale: punch up on burst, shrink as it falls.
		var start_scale: float = 0.5 + randf() * 0.2
		mote.scale = Vector2(start_scale, start_scale)
		var tw_scale := create_tween()
		tw_scale.tween_interval(delay)
		tw_scale.tween_property(mote, "scale", Vector2(1.1, 1.1), SHATTER_DURATION * 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw_scale.tween_property(mote, "scale", Vector2(0.55, 0.55), SHATTER_DURATION * 0.60).set_trans(Tween.TRANS_SINE)
