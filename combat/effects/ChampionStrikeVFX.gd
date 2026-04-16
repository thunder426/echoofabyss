## ChampionStrikeVFX.gd
## Overlays a bloody claw slash mark on the defender when a champion attacks,
## plus a meaty screen shake. The claw texture is additive-blended (black bg
## becomes transparent, bright areas glow). A slight random rotation keeps
## repeated strikes from looking identical.
##
## Call sites invoke spawn_claw_mark() at the moment of impact and shake()
## for the screen shake. Both are fire-and-forget.
class_name ChampionStrikeVFX
extends RefCounted

const TEX_CLAW: Texture2D = preload("res://assets/art/fx/claw_mark.png")

# ── Claw mark settings ──────────────────────────────────────────────────────
const CLAW_HOLD_TIME: float    = 0.35   # seconds the mark is fully visible
const CLAW_FADE_TIME: float    = 0.30   # seconds to fade out after hold
const CLAW_SLAM_TIME: float    = 0.05   # seconds for the slam-in scale
const CLAW_START_SCALE: float  = 1.35   # oversized on slam-in, then settles
const CLAW_END_SCALE: float    = 1.0    # resting scale during hold
const CLAW_ROTATION_JITTER: float = 0.25  # radians of random rotation (±)

# ── Screen shake settings ────────────────────────────────────────────────────
const SHAKE_AMPLITUDE: float = 8.0
const SHAKE_TICKS: int       = 8


## Stamp a bloody claw slash mark on a BoardSlot at the moment of impact.
## The mark slams in slightly oversized, settles, holds, then fades out.
static func spawn_claw_mark(parent: Node, target_slot: BoardSlot) -> void:
	var mark := TextureRect.new()
	mark.texture = TEX_CLAW
	mark.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.set_size(target_slot.size)
	mark.pivot_offset = target_slot.size * 0.5
	mark.global_position = target_slot.global_position
	mark.rotation = randf_range(-CLAW_ROTATION_JITTER, CLAW_ROTATION_JITTER)
	mark.scale = Vector2(CLAW_START_SCALE, CLAW_START_SCALE)
	mark.z_index = 4
	mark.z_as_relative = false
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Additive blend — black bg becomes transparent, bright areas glow
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mark.material = mat

	parent.add_child(mark)

	# Slam in → hold → fade out
	var tw := mark.create_tween()
	tw.tween_property(mark, "scale",
		Vector2(CLAW_END_SCALE, CLAW_END_SCALE), CLAW_SLAM_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(CLAW_HOLD_TIME)
	tw.tween_property(mark, "modulate:a", 0.0, CLAW_FADE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(mark.queue_free)


## Same as spawn_claw_mark but for a hero panel (Control, not BoardSlot).
static func spawn_claw_mark_on_panel(parent: Node, panel: Control) -> void:
	var mark := TextureRect.new()
	mark.texture = TEX_CLAW
	mark.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.set_size(panel.size)
	mark.pivot_offset = panel.size * 0.5
	mark.global_position = panel.global_position
	mark.rotation = randf_range(-CLAW_ROTATION_JITTER, CLAW_ROTATION_JITTER)
	mark.scale = Vector2(CLAW_START_SCALE, CLAW_START_SCALE)
	mark.z_index = 4
	mark.z_as_relative = false
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mark.material = mat

	parent.add_child(mark)

	var tw := mark.create_tween()
	tw.tween_property(mark, "scale",
		Vector2(CLAW_END_SCALE, CLAW_END_SCALE), CLAW_SLAM_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(CLAW_HOLD_TIME)
	tw.tween_property(mark, "modulate:a", 0.0, CLAW_FADE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(mark.queue_free)


## Screen shake for champion strikes — heavier than a normal minion hit,
## lighter than champion summoning.
##
## Shake target MUST be a Node2D or Control with a real position (a BoardSlot
## or hero panel). Passing a CanvasLayer no-ops — CanvasLayer has no
## `position` property and ScreenShakeEffect bails out.
static func shake(target: Node, scene: Node) -> void:
	await ScreenShakeEffect.shake(target, scene, SHAKE_AMPLITUDE, SHAKE_TICKS)
