## DarkEmpowermentPreludeVFX.gd
## Per-card flavor prelude for Dark Empowerment — runs before the common
## BuffApplyVFX phases via BuffVfxRegistry.
##
## Single phase: a Dark Empowerment sigil stamps onto the slot center
## (drop-in → hold → fade-out), additive-blended so the icon's black
## background reads as transparent. The demon-target variant tints the
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

	var center_px: Vector2 = _slot.global_position + _slot.size * 0.5
	var size: float = STAMP_SIZE_PX * (STAMP_DEMON_SCALE if _is_demon else 1.0)
	var tint: Color = STAMP_TINT_DEMON if _is_demon else STAMP_TINT_DEFAULT

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
	# Additive so the source PNG's pure-black background reads as transparent
	# without needing the artist to alpha-cut the asset first.
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	stamp.material = add_mat
	host.add_child(stamp)

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
