## FeralSurgePreludeVFX.gd
## Per-card flavor prelude for Feral Surge — runs before the common
## BuffApplyVFX phases via BuffVfxRegistry.
##
## Stamps the feral claw/fang sigil onto the slot center with a toxic-green
## halo bleeding crimson at the edges. Sigil drops in with a brief spin so
## the clawed silhouette reads as "raking in" rather than a static stamp.
## Generic blessing surge / stat pulse / motes follow from BuffApplyVFX.
class_name FeralSurgePreludeVFX
extends Node2D

signal finished

const TEX_STAMP: Texture2D = preload("res://assets/art/fx/feral_surge_mark.png")

const STAMP_FADE_IN:  float = 0.14
const STAMP_HOLD:     float = 0.20
const STAMP_FADE_OUT: float = 0.18
const STAMP_DURATION: float = STAMP_FADE_IN + STAMP_HOLD + STAMP_FADE_OUT

const STAMP_SIZE_PX: float = 120.0

# Halo — toxic emerald core bleeding crimson at the rim, matching the
# card art palette. Additive so it pops on dark and bright minion art.
const HALO_SIZE_MULT:  float = 2.20
const HALO_PEAK_ALPHA: float = 0.90
const HALO_TINT:       Color = Color(0.35, 1.00, 0.40, 1.0)

const _HALO_SIZE: int = 256
static var _halo_tex: Texture2D = null

## Two-stop radial: emerald core → crimson mid → transparent rim. Baked once,
## tinted per-instance via modulate (modulate stays white here so the baked
## color gradient shows through).
static func _get_halo_texture() -> Texture2D:
	if _halo_tex != null:
		return _halo_tex
	var img := Image.create(_HALO_SIZE, _HALO_SIZE, false, Image.FORMAT_RGBA8)
	var center: float = float(_HALO_SIZE) * 0.5
	var core: Color   = Color(0.30, 1.00, 0.35, 1.0)  # toxic green
	var mid: Color    = Color(1.00, 0.20, 0.15, 1.0)  # crimson bleed
	for y in _HALO_SIZE:
		for x in _HALO_SIZE:
			var dx: float = float(x) - center
			var dy: float = float(y) - center
			var r: float = clampf(sqrt(dx * dx + dy * dy) / center, 0.0, 1.0)
			# 0..0.55 green core → 0.55..1.0 crimson ring → transparent at edge
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


static func create(slot: Control) -> FeralSurgePreludeVFX:
	var vfx := FeralSurgePreludeVFX.new()
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

	AudioManager.play_sfx("res://assets/audio/sfx/spells/feral_surge.wav", -6.0)

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
	stamp.rotation      = deg_to_rad(-25.0)  # spins into place
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
# Prelude factory — called by BuffVfxRegistry when a "feral_surge" buff is
# applied. Returns the prelude Callable that BuffApplyVFX awaits before
# running its common phases.
# ═══════════════════════════════════════════════════════════════════════════

static func prelude_factory(slot: Control, _atk_d: int, _hp_d: int) -> Callable:
	return func() -> void:
		if slot == null or not is_instance_valid(slot) or not slot.is_inside_tree():
			return
		var vfx := FeralSurgePreludeVFX.create(slot)
		var host: Node = slot.get_tree().current_scene.get_node_or_null("VfxLayer")
		if host == null:
			host = slot.get_tree().current_scene
		host.add_child(vfx)
		await vfx.finished
