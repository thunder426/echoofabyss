## DarkCommandPreludeVFX.gd
## Per-card flavor prelude for Dark Command — runs before the common
## BuffApplyVFX phases via BuffVfxRegistry.
##
## Stamps the Abyss Cultist command sigil onto the slot center with a
## white-violet halo bleeding deep violet at the rim. Sigil drops in with
## a brief counter-rotation so it reads as "etching" onto the minion.
## Generic blessing surge / stat pulse / motes follow from BuffApplyVFX,
## recolored to a violet/white palette via BuffVfxRegistry's palette.
class_name DarkCommandPreludeVFX
extends Node2D

signal finished

const TEX_STAMP: Texture2D = preload("res://assets/art/fx/dark_command_mark.png")

const STAMP_FADE_IN:  float = 0.14
const STAMP_HOLD:     float = 0.20
const STAMP_FADE_OUT: float = 0.18
const STAMP_DURATION: float = STAMP_FADE_IN + STAMP_HOLD + STAMP_FADE_OUT

const STAMP_SIZE_PX: float = 120.0

# Halo — white-violet core bleeding deep violet at the rim. Additive so it
# pops on dark and bright minion art equally.
const HALO_SIZE_MULT:  float = 2.20
const HALO_PEAK_ALPHA: float = 0.90

const _HALO_SIZE: int = 256
static var _halo_tex: Texture2D = null

## Two-stop radial: white-violet core → deep violet mid → transparent rim.
## Baked once, tinted per-instance via modulate (modulate stays white so the
## baked color gradient shows through).
static func _get_halo_texture() -> Texture2D:
	if _halo_tex != null:
		return _halo_tex
	var img := Image.create(_HALO_SIZE, _HALO_SIZE, false, Image.FORMAT_RGBA8)
	var center: float = float(_HALO_SIZE) * 0.5
	var core: Color   = Color(0.92, 0.78, 1.00, 1.0)  # white-violet
	var mid: Color    = Color(0.55, 0.15, 0.90, 1.0)  # deep violet
	for y in _HALO_SIZE:
		for x in _HALO_SIZE:
			var dx: float = float(x) - center
			var dy: float = float(y) - center
			var r: float = clampf(sqrt(dx * dx + dy * dy) / center, 0.0, 1.0)
			var col: Color
			if r < 0.55:
				var t: float = r / 0.55
				col = core.lerp(mid, t)
			else:
				col = mid
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			a = pow(a, 1.5)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	_halo_tex = ImageTexture.create_from_image(img)
	return _halo_tex

var _slot: Control = null


static func create(slot: Control) -> DarkCommandPreludeVFX:
	var vfx := DarkCommandPreludeVFX.new()
	vfx._slot   = slot
	vfx.z_index = 22
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
	var halo_size: float = STAMP_SIZE_PX * HALO_SIZE_MULT

	# ── Halo (under sigil) ────────────────────────────────────────────────
	var halo := TextureRect.new()
	halo.texture       = _get_halo_texture()
	halo.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	halo.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	halo.set_size(Vector2(halo_size, halo_size))
	halo.position      = center_px - Vector2(halo_size, halo_size) * 0.5
	halo.pivot_offset  = Vector2(halo_size, halo_size) * 0.5
	halo.modulate      = Color(1.0, 1.0, 1.0, 0.0)
	halo.scale         = Vector2(0.80, 0.80)
	halo.z_index       = 21
	halo.z_as_relative = false
	var halo_mat := CanvasItemMaterial.new()
	halo_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = halo_mat
	host.add_child(halo)

	# ── Sigil ─────────────────────────────────────────────────────────────
	var stamp := TextureRect.new()
	stamp.texture       = TEX_STAMP
	stamp.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	stamp.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stamp.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	stamp.set_size(Vector2(STAMP_SIZE_PX, STAMP_SIZE_PX))
	stamp.position      = center_px - Vector2(STAMP_SIZE_PX, STAMP_SIZE_PX) * 0.5
	stamp.pivot_offset  = Vector2(STAMP_SIZE_PX, STAMP_SIZE_PX) * 0.5
	stamp.modulate      = Color(1.0, 1.0, 1.0, 0.0)
	stamp.scale         = Vector2(1.65, 1.65)
	# Counter-rotate in (opposite of FeralSurge) so Abyss Order preludes
	# have their own kinetic signature.
	stamp.rotation      = deg_to_rad(25.0)
	stamp.z_index       = 22
	stamp.z_as_relative = false
	host.add_child(stamp)

	# Halo: bloom in ahead of sigil, hold, fade with subtle bloom-out.
	var tw_halo := create_tween().set_parallel(true)
	tw_halo.tween_property(halo, "modulate:a", HALO_PEAK_ALPHA, STAMP_FADE_IN * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_halo.tween_property(halo, "scale", Vector2.ONE, STAMP_FADE_IN * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_halo.chain().tween_property(halo, "modulate:a", HALO_PEAK_ALPHA, STAMP_HOLD)
	tw_halo.chain().tween_property(halo, "modulate:a", 0.0, STAMP_FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw_halo.parallel().tween_property(halo, "scale", Vector2(1.15, 1.15), STAMP_FADE_OUT).set_trans(Tween.TRANS_SINE)

	# Sigil: drop in with rotation to 0 + back-overshoot scale, hold, fade.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(stamp, "modulate:a", 1.0, STAMP_FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(stamp, "scale", Vector2.ONE, STAMP_FADE_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(stamp, "rotation", 0.0, STAMP_FADE_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(stamp, "modulate:a", 1.0, STAMP_HOLD)
	tw.chain().tween_property(stamp, "modulate:a", 0.0, STAMP_FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(stamp, "scale", Vector2(1.25, 1.25), STAMP_FADE_OUT).set_trans(Tween.TRANS_SINE)

	await get_tree().create_timer(STAMP_DURATION).timeout
	if is_instance_valid(halo):
		halo.queue_free()
	if is_instance_valid(stamp):
		stamp.queue_free()

	finished.emit()
	queue_free()


# ═══════════════════════════════════════════════════════════════════════════
# Palette — violet/white recolor for BuffApplyVFX's common phases. Values
# overwrite the default green/gold blessing palette one key at a time.
# ═══════════════════════════════════════════════════════════════════════════

const PALETTE: Dictionary = {
	"surge_core":     Color(1.00, 0.92, 1.00, 1.0),       # white-violet hot core
	"surge_edge":     Color(0.65, 0.30, 1.00, 1.0),       # bright violet edge
	"surge_particle": Color(0.95, 0.80, 1.00, 0.85),      # light violet motes in shaft
	"flash":          Color(0.90, 0.80, 1.00, 1.0),       # silhouette flash tint
	"pulse_atk":      Color(0.85, 0.45, 1.00, 1.0),       # pure violet ATK pulse
	"pulse_hp":       Color(1.00, 0.95, 1.00, 1.0),       # white-violet HP pulse
	"mote":           Color(0.90, 0.70, 1.00, 0.85),      # lingering violet motes
}


# ═══════════════════════════════════════════════════════════════════════════
# Prelude factory — called by BuffVfxRegistry when a "dark_command" buff is
# applied. Returns the prelude Callable that BuffApplyVFX awaits before
# running its common phases.
# ═══════════════════════════════════════════════════════════════════════════

static func prelude_factory(slot: Control, _atk_d: int, _hp_d: int) -> Callable:
	return func() -> void:
		if slot == null or not is_instance_valid(slot) or not slot.is_inside_tree():
			return
		var vfx := DarkCommandPreludeVFX.create(slot)
		var host: Node = slot.get_tree().current_scene.get_node_or_null("VfxLayer")
		if host == null:
			host = slot.get_tree().current_scene
		host.add_child(vfx)
		await vfx.finished
