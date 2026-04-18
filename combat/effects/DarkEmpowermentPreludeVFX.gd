## DarkEmpowermentPreludeVFX.gd
## Per-card flavor prelude for Dark Empowerment — runs before the common
## BuffApplyVFX phases via BuffVfxRegistry.
##
## Single phase: a Dark Empowerment sigil stamps onto the slot center
## (drop-in → hold → fade-out). The icon ships with a real alpha channel,
## so it's drawn with the default normal blend — additive would wash the
## sigil out against bright minion art. The demon-target variant tints the
## stamp crimson and scales it up slightly so the conditional bonus reads
## visually without needing a second asset.
##
## No flash, shaft, or distortion — the symbol is the entire prelude. The
## stat-change readout (chevrons, label pulse, motes) is handled by the
## generic BuffApplyVFX phases that run after this finishes.
class_name DarkEmpowermentPreludeVFX
extends Node2D

signal finished

const TEX_STAMP: Texture2D = preload("res://assets/art/icons/icon_dark_empowerment.png")

# Stamp timing — same beats as CorruptionApplyVFX so all "apply" VFX share
# the same rhythm of drop / hold / release.
const STAMP_FADE_IN:  float = 0.12
const STAMP_HOLD:     float = 0.22
const STAMP_FADE_OUT: float = 0.18
const STAMP_DURATION: float = STAMP_FADE_IN + STAMP_HOLD + STAMP_FADE_OUT

const STAMP_SIZE_PX:        float = 110.0
const STAMP_DEMON_SCALE:    float = 1.18  # demon variant reads as "more"
const STAMP_TINT_DEFAULT: Color = Color(1.0, 1.0, 1.0, 1.0)
# Crimson wash that lifts the icon's existing red core; chosen to keep the
# violet aura visible rather than wash it out.
const STAMP_TINT_DEMON:   Color = Color(1.00, 0.55, 0.55, 1.0)

# --- Halo (glowing aura under the sigil) ---------------------------------
# Bright violet (or crimson, demon variant) radial glow that bleeds past
# the sigil's edges. Additive so it shows up on any card art — dark or
# bright — and frames the icon instead of sitting flat on top of the card.
const HALO_SIZE_MULT:    float = 2.10   # halo extends well past sigil edges
const HALO_PEAK_ALPHA:   float = 0.85
const HALO_TINT_DEFAULT: Color = Color(0.55, 0.20, 0.95, 1.0)  # bright violet glow
const HALO_TINT_DEMON:   Color = Color(0.95, 0.20, 0.30, 1.0)  # bright crimson glow

# --- Cached halo texture --------------------------------------------------
const _HALO_SIZE: int = 256
static var _halo_tex: Texture2D = null

## Soft radial gradient — opaque white at center, transparent at edges.
## Sized once, tinted per-instance via TextureRect.modulate.
static func _get_halo_texture() -> Texture2D:
	if _halo_tex != null:
		return _halo_tex
	var img := Image.create(_HALO_SIZE, _HALO_SIZE, false, Image.FORMAT_RGBA8)
	var center: float = float(_HALO_SIZE) * 0.5
	for y in _HALO_SIZE:
		for x in _HALO_SIZE:
			var dx: float = float(x) - center
			var dy: float = float(y) - center
			var r: float = sqrt(dx * dx + dy * dy) / center
			# Quadratic-ish falloff: stays dense in the middle so the sigil
			# sits on a clear dark patch, fades smoothly to nothing at the rim.
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			a = pow(a, 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_halo_tex = ImageTexture.create_from_image(img)
	return _halo_tex

var _slot: Control = null
var _is_demon: bool = false


static func create(slot: Control, is_demon: bool) -> DarkEmpowermentPreludeVFX:
	var vfx := DarkEmpowermentPreludeVFX.new()
	vfx._slot     = slot
	vfx._is_demon = is_demon
	vfx.z_index   = 22
	return vfx


func _ready() -> void:
	_run()


func _run() -> void:
	var host: Node = get_parent()
	if _slot == null or not is_instance_valid(_slot) or host == null:
		finished.emit()
		queue_free()
		return

	AudioManager.play_sfx("res://assets/audio/sfx/spells/dark_empowerment_sigil.wav", -5.0)

	var center_px: Vector2 = _slot.global_position + _slot.size * 0.5
	var size: float = STAMP_SIZE_PX * (STAMP_DEMON_SCALE if _is_demon else 1.0)
	var tint: Color = STAMP_TINT_DEMON if _is_demon else STAMP_TINT_DEFAULT
	var halo_tint: Color = HALO_TINT_DEMON if _is_demon else HALO_TINT_DEFAULT
	var halo_size: float = size * HALO_SIZE_MULT

	# ── Halo (drawn first so it sits *under* the sigil) ────────────────────
	var halo := TextureRect.new()
	halo.texture       = _get_halo_texture()
	halo.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	halo.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	halo.set_size(Vector2(halo_size, halo_size))
	halo.position      = center_px - Vector2(halo_size, halo_size) * 0.5
	halo.pivot_offset  = Vector2(halo_size, halo_size) * 0.5
	halo.modulate      = Color(halo_tint.r, halo_tint.g, halo_tint.b, 0.0)
	halo.scale         = Vector2(0.85, 0.85)  # subtle bloom-in
	halo.z_index       = 21
	halo.z_as_relative = false
	# Additive — the glow brightens the card behind it so the halo is
	# visible against both dark and bright minion art.
	var halo_mat := CanvasItemMaterial.new()
	halo_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = halo_mat
	host.add_child(halo)

	# ── Sigil ──────────────────────────────────────────────────────────────
	var stamp := TextureRect.new()
	stamp.texture       = TEX_STAMP
	stamp.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	stamp.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stamp.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	stamp.set_size(Vector2(size, size))
	stamp.position      = center_px - Vector2(size, size) * 0.5
	stamp.pivot_offset  = Vector2(size, size) * 0.5
	stamp.modulate      = Color(tint.r, tint.g, tint.b, 0.0)
	stamp.scale         = Vector2(1.55, 1.55)
	stamp.z_index       = 22
	stamp.z_as_relative = false
	host.add_child(stamp)

	# Halo: bloom in slightly *ahead* of the sigil for a "shadow gathers,
	# then sigil lands" beat, then fade out together.
	var tw_halo := create_tween().set_parallel(true)
	tw_halo.tween_property(halo, "modulate:a", HALO_PEAK_ALPHA, STAMP_FADE_IN * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_halo.tween_property(halo, "scale", Vector2.ONE, STAMP_FADE_IN * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_halo.chain().tween_property(halo, "modulate:a", HALO_PEAK_ALPHA, STAMP_HOLD)  # hold
	tw_halo.chain().tween_property(halo, "modulate:a", 0.0, STAMP_FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw_halo.parallel().tween_property(halo, "scale", Vector2(1.10, 1.10), STAMP_FADE_OUT).set_trans(Tween.TRANS_SINE)

	# Drop in: fade up + scale to 1 with a back overshoot
	var tw := create_tween().set_parallel(true)
	tw.tween_property(stamp, "modulate:a", 1.0, STAMP_FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(stamp, "scale", Vector2.ONE, STAMP_FADE_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Hold (alpha noop just to advance the chain timeline)
	tw.chain().tween_property(stamp, "modulate:a", 1.0, STAMP_HOLD)
	# Release: fade out + slight scale up
	tw.chain().tween_property(stamp, "modulate:a", 0.0, STAMP_FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(stamp, "scale", Vector2(1.20, 1.20), STAMP_FADE_OUT).set_trans(Tween.TRANS_SINE)

	await get_tree().create_timer(STAMP_DURATION).timeout
	if is_instance_valid(halo):
		halo.queue_free()
	if is_instance_valid(stamp):
		stamp.queue_free()

	finished.emit()
	queue_free()


# ═══════════════════════════════════════════════════════════════════════════
# Prelude factory — called by BuffVfxRegistry when a "dark_empowerment"
# buff is applied. Returns the prelude Callable that BuffApplyVFX awaits
# before running its common phases.
# ═══════════════════════════════════════════════════════════════════════════

static func prelude_factory(slot: Control, _atk_d: int, hp_d: int) -> Callable:
	var is_demon: bool = hp_d > 0
	return func() -> void:
		if slot == null or not is_instance_valid(slot) or not slot.is_inside_tree():
			return
		var vfx := DarkEmpowermentPreludeVFX.create(slot, is_demon)
		var host: Node = slot.get_tree().current_scene.get_node_or_null("VfxLayer")
		if host == null:
			host = slot.get_tree().current_scene
		host.add_child(vfx)
		await vfx.finished
