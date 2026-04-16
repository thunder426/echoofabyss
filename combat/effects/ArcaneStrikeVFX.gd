## ArcaneStrikeVFX.gd
## Impact VFX for Arcane Strike — a quick, precise arcane fracture stamped onto
## the target. No projectile phase; the effect appears directly at impact.
##
## Layers:
##   1. Crack stamp (additive fracture texture — the main visual)
##   2. Light screen shake
##
## Spawn via VfxController — do not parent manually.
class_name ArcaneStrikeVFX
extends BaseVfx

const TEX_CRACK: Texture2D = preload("res://assets/art/fx/arcane_strike_impact.png")

# ── Arcane color palette ─────────────────────────────────────────────────────
const COLOR_BRIGHT: Color = Color(0.40, 0.55, 1.0, 0.95)   # Vivid arcane blue

# ── Sizing ───────────────────────────────────────────────────────────────────
const CRACK_SIZE: float = 160.0   # Crack stamp covers most of the slot

# ── Timing ───────────────────────────────────────────────────────────────────
const CRACK_HOLD: float    = 0.30
const CRACK_FADE: float    = 0.25

# ── Shake ────────────────────────────────────────────────────────────────────
const SHAKE_AMPLITUDE: float = 5.0
const SHAKE_TICKS: int       = 6

var _target_slot: BoardSlot


static func create(target_slot: BoardSlot) -> ArcaneStrikeVFX:
	var vfx := ArcaneStrikeVFX.new()
	vfx._target_slot = target_slot
	vfx.z_index = 200
	return vfx


func _play() -> void:
	if _target_slot == null:
		impact_hit.emit(0)
		finished.emit()
		queue_free()
		return
	var impact_pos: Vector2 = _target_slot.global_position + _target_slot.size * 0.5
	global_position = impact_pos
	AudioManager.play_sfx("res://assets/audio/sfx/spells/arcane_strike_impact.wav", -8.0)
	_spawn_crack_stamp()
	_do_shake()


# ═════════════════════════════════════════════════════════════════════════════
# Layer 1: Crack Stamp
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_crack_stamp() -> void:
	var stamp := Sprite2D.new()
	stamp.texture = TEX_CRACK
	var tex_size: float = maxf(stamp.texture.get_width(), stamp.texture.get_height())
	var target_scale: float = CRACK_SIZE / maxf(tex_size, 1.0)
	# Slam in slightly oversized, then settle
	stamp.scale = Vector2.ONE * (target_scale * 1.25)
	stamp.rotation = randf_range(-0.20, 0.20)
	stamp.modulate = Color(COLOR_BRIGHT.r, COLOR_BRIGHT.g, COLOR_BRIGHT.b, 0.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	stamp.material = mat
	add_child(stamp)

	var tw := create_tween()
	# Slam in
	tw.set_parallel(true)
	tw.tween_property(stamp, "modulate:a", COLOR_BRIGHT.a, 0.04) \
		.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(stamp, "scale", Vector2.ONE * target_scale, 0.06) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Signal damage at impact
	tw.chain().tween_callback(func() -> void: impact_hit.emit(0))
	# Hold
	tw.chain().tween_interval(CRACK_HOLD)
	# Fade out
	tw.chain().tween_property(stamp, "modulate:a", 0.0, CRACK_FADE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Signal completion and self-cleanup
	tw.chain().tween_callback(func():
		finished.emit()
		queue_free()
	)


# ═════════════════════════════════════════════════════════════════════════════
# Layer 2: Screen Shake
# ═════════════════════════════════════════════════════════════════════════════

func _do_shake() -> void:
	if _target_slot == null or not _target_slot.is_inside_tree():
		return
	ScreenShakeEffect.shake(_target_slot, _target_slot, SHAKE_AMPLITUDE, SHAKE_TICKS)
