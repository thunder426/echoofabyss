## RitualSummonImpactVFX.gd
## The "arrival" beat played at the empty enemy slot when the Demon Ascendant
## summon bolt lands. Replaces the old DemonAscendantRitualBeamVFX impact
## flash. Visuals:
##
##   - 3 STAGGERED shader-driven sonic shockwaves expand outward from the
##     impact point. These reuse `sonic_wave.gdshader` — the same shader that
##     drives Void Screech's hero-frame shockwave and minion-summon distortion
##     pulses — so pixels in the ring band warp + chromatic-aberrate as the
##     wave passes through. There is no "drawn ring" — the ring IS the screen
##     itself bending, which is exactly the read we want.
##   - Three passes stagger ~110ms apart and shrink in radius/intensity
##     (1.0 → 0.75 → 0.55 of base radius). Reads as a sonic-pulse train rather
##     than one big donut, and matches the "weaker echoes" feel of a real
##     shockwave.
##   - Tint is faint violet to thread the ritual color through the arrival
##     beat without overpowering the sigil that follows.
##   - The destination slot itself shakes (passed in via `slot_to_shake`),
##     not the screen — the shake is local, telegraphing where the summon
##     will appear.
##
## Spawn via VfxController.spawn().  This VFX has no logical impact_count
## (it's a punctuation effect, not a damage source).
class_name RitualSummonImpactVFX
extends BaseVfx

const SHADER_SONIC: Shader = preload("res://combat/effects/sonic_wave.gdshader")

# Per-pulse timing (each pulse runs for this long, staggered by PULSE_STAGGER).
# Slower than a hit-shockwave on purpose — this is a ritual landing, the
# pulses should *travel* across the screen visibly, not snap.
const PULSE_DURATION: float = 1.10
const PULSE_STAGGER:  float = 0.22

# Base radius of the strongest pulse, in pixels. Subsequent pulses scale this.
const BASE_RADIUS_PX: float = 360.0
const PULSE_RADIUS_SCALES: Array = [1.00, 0.78, 0.58]

const RING_THICKNESS: float = 0.09
const RING_STRENGTH:  float = 0.024
# Fully transparent tint — the shockwave reads via screen distortion +
# chromatic aberration only, no color wash. Setting alpha to 0.0 zeroes the
# tint contribution in sonic_wave.gdshader (tint_mask uses tint.a) while the
# warp + CA still play at full strength.
const RING_TINT: Color = Color(1.0, 1.0, 1.0, 0.0)

const SHAKE_AMPLITUDE: float = 6.0
const SHAKE_TICKS: int = 10

var _impact_pos: Vector2
var _slot_to_shake: Node = null  # Optional — typically the destination BoardSlot

static func create(impact_pos: Vector2, slot_to_shake: Node = null) -> RitualSummonImpactVFX:
	var vfx := RitualSummonImpactVFX.new()
	vfx._impact_pos = impact_pos
	vfx._slot_to_shake = slot_to_shake
	vfx.impact_count = 0  # punctuation effect — no damage gate
	vfx.z_index = 259
	return vfx

func _play() -> void:
	AudioManager.play_sfx("res://assets/audio/sfx/spells/portal_open.wav", -4.0)

	# Local slot shake — fires immediately, in parallel with the first pulse.
	if _slot_to_shake != null and _slot_to_shake.is_inside_tree():
		ScreenShakeEffect.shake(_slot_to_shake, self, SHAKE_AMPLITUDE, SHAKE_TICKS)

	# Fire all pulses on a stagger.
	for i in PULSE_RADIUS_SCALES.size():
		var delay: float = i * PULSE_STAGGER
		var radius_px: float = BASE_RADIUS_PX * float(PULSE_RADIUS_SCALES[i])
		_spawn_pulse_after(delay, radius_px)

	# End once the last pulse has had time to finish + fade.
	var total: float = (PULSE_RADIUS_SCALES.size() - 1) * PULSE_STAGGER + PULSE_DURATION
	await get_tree().create_timer(total).timeout
	finished.emit()
	queue_free()


func _spawn_pulse_after(delay: float, radius_px: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	var ui: Node = get_parent()
	if ui == null:
		return
	_spawn_sonic_wave(ui, _impact_pos, PULSE_DURATION, radius_px)


# ─────────────────────────────────────────────────────────────────────────
# Shader-driven sonic wave — one fullscreen ColorRect with the
# sonic_wave.gdshader doing the radial distortion. Mirrors the helper in
# VoidScreechVFX / CorruptedDeathSummonVFX so all three "summon shockwaves"
# in the game share the same visual vocabulary.
# ─────────────────────────────────────────────────────────────────────────
func _spawn_sonic_wave(ui: Node, pos: Vector2, duration: float, max_radius_px: float) -> void:
	var vp_rect := get_viewport().get_visible_rect()
	var vp: Vector2 = vp_rect.size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var aspect: float = vp.x / vp.y

	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.z_index = 15
	rect.z_as_relative = false

	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SONIC
	mat.set_shader_parameter("aspect", aspect)
	mat.set_shader_parameter("tint", RING_TINT)
	mat.set_shader_parameter("radius_max", max_radius_px / vp.y)
	mat.set_shader_parameter("thickness", RING_THICKNESS)
	mat.set_shader_parameter("strength", RING_STRENGTH)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("alpha_multiplier", 1.0)
	mat.set_shader_parameter("center_uv", Vector2(pos.x / vp.x, pos.y / vp.y))
	rect.material = mat
	ui.add_child(rect)

	var tw := rect.create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			mat.set_shader_parameter("progress", p),
			0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			mat.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, duration * 0.30).set_delay(duration * 0.70).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(rect.queue_free)
