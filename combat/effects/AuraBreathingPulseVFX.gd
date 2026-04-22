## AuraBreathingPulseVFX.gd
## One-shot "I'm projecting an aura" flourish played on summon for aura-source
## minions (Rogue Imp Elder for now). A rectangular glow frame emits OUTWARD
## from the card/slot edges — the card interior is left untouched so the art
## stays readable. Two breathing cycles (~2s total), then fades out.
##
## Intentionally NOT persistent — always-on auras make the board too noisy.
## Strictly fires on the aura source's own summon, never on refreshes.
##
## Implementation: a custom _draw subnode paints a gradient rim around the
## slot rectangle. Each pixel's alpha = base_alpha * falloff(distance_to_edge)
## so the glow is strongest right at the card edge and fades to 0 at
## GLOW_SPREAD distance outward. Breathing is driven by animating the
## `intensity` + `spread` properties each phase.
##
## Fire-and-forget via VfxController.spawn. Emits impact_hit(0) at peak, then
## finished when the fade-out completes.
class_name AuraBreathingPulseVFX
extends BaseVfx

# Dark-green Feral Imp aura palette.
const COLOR_GLOW: Color = Color(0.35, 0.95, 0.30, 1.0)

# How far (in px) the glow extends outward from the card edges at peak.
const SPREAD_PEAK: float  = 42.0
const SPREAD_VALLEY: float = 28.0
const SPREAD_START: float = 14.0

# Alpha envelope.
const ALPHA_PEAK_1: float = 0.75
const ALPHA_VALLEY: float = 0.35
const ALPHA_PEAK_2: float = 0.60

# Timing — two breath cycles then fade.
const INHALE_1:  float = 0.50
const EXHALE_1:  float = 0.50
const INHALE_2:  float = 0.50
const FADE_OUT:  float = 0.50

var _target_slot: BoardSlot = null
var _rim: _RimGlow = null


static func create(target_slot: BoardSlot) -> AuraBreathingPulseVFX:
	var vfx := AuraBreathingPulseVFX.new()
	vfx._target_slot = target_slot
	vfx.impact_count = 0
	vfx.z_index = 90  # below minion art, above slot bg
	return vfx


func _play() -> void:
	if _target_slot == null or not _target_slot.is_inside_tree():
		finished.emit()
		queue_free()
		return

	# Anchor at the slot's TOP-LEFT so the rim draws aligned with the card
	# rectangle rather than centered on the midpoint.
	global_position = _target_slot.global_position

	_rim = _RimGlow.new()
	_rim.card_size = _target_slot.size
	_rim.color = COLOR_GLOW
	_rim.spread = SPREAD_START
	_rim.intensity = 0.0
	add_child(_rim)

	# ── Breath 1: inhale ───────────────────────────────────────────────────
	var tw1 := create_tween().set_parallel(true)
	tw1.tween_method(_set_intensity, 0.0, ALPHA_PEAK_1, INHALE_1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw1.tween_method(_set_spread, SPREAD_START, SPREAD_PEAK, INHALE_1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw1.finished
	if not is_inside_tree():
		finished.emit(); queue_free(); return

	impact_hit.emit(0)

	# ── Breath 1: exhale ───────────────────────────────────────────────────
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_method(_set_intensity, ALPHA_PEAK_1, ALPHA_VALLEY, EXHALE_1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw2.tween_method(_set_spread, SPREAD_PEAK, SPREAD_VALLEY, EXHALE_1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw2.finished
	if not is_inside_tree():
		finished.emit(); queue_free(); return

	# ── Breath 2: inhale (smaller peak) ────────────────────────────────────
	var tw3 := create_tween().set_parallel(true)
	tw3.tween_method(_set_intensity, ALPHA_VALLEY, ALPHA_PEAK_2, INHALE_2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw3.tween_method(_set_spread, SPREAD_VALLEY, SPREAD_PEAK, INHALE_2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw3.finished
	if not is_inside_tree():
		finished.emit(); queue_free(); return

	# ── Fade out — keep spreading outward while alpha dies ─────────────────
	var tw4 := create_tween().set_parallel(true)
	tw4.tween_method(_set_intensity, ALPHA_PEAK_2, 0.0, FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw4.tween_method(_set_spread, SPREAD_PEAK, SPREAD_PEAK * 1.35, FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw4.finished

	finished.emit()
	queue_free()


func _set_intensity(v: float) -> void:
	if _rim != null and is_instance_valid(_rim):
		_rim.intensity = v
		_rim.queue_redraw()


func _set_spread(v: float) -> void:
	if _rim != null and is_instance_valid(_rim):
		_rim.spread = v
		_rim.queue_redraw()


# ═══════════════════════════════════════════════════════════════════════════
# _RimGlow — inner helper node that paints the outward rectangular glow.
# ═══════════════════════════════════════════════════════════════════════════

class _RimGlow extends Node2D:
	var card_size: Vector2 = Vector2.ZERO
	var color: Color = Color.WHITE
	var spread: float = 0.0       # outward distance in px
	var intensity: float = 0.0    # alpha multiplier

	# Draw the rim as N concentric rectangular layers, each slightly larger
	# than the last, with falloff alpha. Additive blend via a CanvasItem
	# material set at construction.
	const STEPS: int = 14

	func _init() -> void:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat

	func _draw() -> void:
		if card_size == Vector2.ZERO or spread <= 0.0 or intensity <= 0.0:
			return
		# Paint from outermost (faintest) to innermost (brightest) so additive
		# blend accumulates naturally into a soft rim.
		for i in range(STEPS, 0, -1):
			var t: float = float(i) / float(STEPS)        # 1.0 at outer edge, → 0 at card edge
			var offset_px: float = spread * t
			# Cubic falloff: alpha strongest right at the card edge.
			var falloff: float = pow(1.0 - t, 2.2)
			var a: float = intensity * falloff
			if a <= 0.001:
				continue
			var rect := Rect2(
				Vector2(-offset_px, -offset_px),
				card_size + Vector2(offset_px, offset_px) * 2.0
			)
			var c := Color(color.r, color.g, color.b, a)
			# Use unfilled stroked rects so only the rim accumulates, not the
			# interior — otherwise the card face would get washed too.
			# Width grows with spread so gaps don't appear between rings.
			var width: float = maxf(spread / float(STEPS) * 1.6, 1.5)
			draw_rect(rect, c, false, width)
