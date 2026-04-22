## VoidDemonSparkBurstVFX.gd
## One-shot purple spark convergence played on a BoardSlot right after the
## Void Spawning summon sigil collapses. Each spark spawns at a random point
## on the slot's rectangular edge and tweens inward to the slot center
## (additive blend), selling a "demon materialising from the rift" beat.
## Runs in parallel with the slot fade-in.
##
## Fire-and-forget: spawn via VfxController.spawn.
class_name VoidDemonSparkBurstVFX
extends BaseVfx

const TEX_SPARK: Texture2D = preload("res://assets/art/fx/spark_sprite.png")

# Purple palette — matches ARCANE_PURPLE sigil flavor.
const COLOR_CORE: Color = Color(1.0, 0.85, 1.0, 1.0)        # bright lavender-white
const COLOR_TAIL: Color = Color(0.65, 0.30, 0.95, 0.95)     # deep violet

const SPARK_SIZE_PX: float   = 9.0        # rendered spark diameter (texture is ~260px)
# Inset from slot edge so the full spark sprite (incl. peak-scale bloom) stays
# inside the slot rectangle. Accounts for peak-scale ~1.1 and some glow margin.
const EDGE_INSET_PX: float   = 14.0
const FLIGHT_MIN: float      = 0.55       # per-spark travel duration
const FLIGHT_MAX: float      = 0.80
# Continuous emission: spawn sparks at this interval over EMIT_DURATION.
const EMIT_INTERVAL: float   = 0.018      # seconds between spawns (~55/s)
const EMIT_DURATION: float   = 0.95       # how long sparks keep spawning
const TOTAL_DURATION: float  = EMIT_DURATION + FLIGHT_MAX + 0.1

var _target_slot: BoardSlot = null


static func create(target_slot: BoardSlot) -> VoidDemonSparkBurstVFX:
	var vfx := VoidDemonSparkBurstVFX.new()
	vfx._target_slot = target_slot
	vfx.impact_count = 0  # no damage gating
	vfx.z_index = 200
	return vfx


func _play() -> void:
	if _target_slot == null or not _target_slot.is_inside_tree():
		finished.emit()
		queue_free()
		return

	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_spawning.wav", -8.0)

	var slot_size: Vector2 = _target_slot.size
	var center: Vector2 = _target_slot.global_position + slot_size * 0.5
	global_position = center

	var scale_factor: float = SPARK_SIZE_PX / maxf(float(TEX_SPARK.get_width()), 1.0)

	# Continuous emitter — spawn one spark per EMIT_INTERVAL across EMIT_DURATION.
	var elapsed: float = 0.0
	while elapsed < EMIT_DURATION:
		if not is_inside_tree():
			return
		_spawn_spark(slot_size, scale_factor)
		await get_tree().create_timer(EMIT_INTERVAL).timeout
		elapsed += EMIT_INTERVAL

	# Let in-flight sparks finish their travel before finishing.
	await get_tree().create_timer(FLIGHT_MAX + 0.1).timeout
	finished.emit()
	queue_free()


## Spawn one spark on a random point of the slot's rectangular edge (in local
## coords relative to slot center), then tween to center + fade.
func _spawn_spark(slot_size: Vector2, scale_factor: float) -> void:
	# Inset the usable rectangle so sparks spawn fully inside the slot frame.
	var half: Vector2 = Vector2(
		maxf(slot_size.x * 0.5 - EDGE_INSET_PX, 1.0),
		maxf(slot_size.y * 0.5 - EDGE_INSET_PX, 1.0)
	)
	# Pick a uniform random angle around the slot center, then project the
	# ray out to the (inset) rectangular perimeter. Full 360° coverage
	# including corners, but always contained within the slot frame.
	var angle: float = randf() * TAU
	var dir: Vector2 = Vector2(cos(angle), sin(angle))
	var tx: float = half.x / maxf(absf(dir.x), 0.0001)
	var ty: float = half.y / maxf(absf(dir.y), 0.0001)
	var t: float = minf(tx, ty)
	var start_local: Vector2 = dir * t

	var spark := Sprite2D.new()
	spark.texture = TEX_SPARK
	spark.position = start_local
	spark.scale = Vector2(scale_factor, scale_factor) * 0.6
	spark.modulate = COLOR_CORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spark.material = mat
	add_child(spark)

	var flight: float = randf_range(FLIGHT_MIN, FLIGHT_MAX)
	var peak_scale: Vector2 = Vector2(scale_factor, scale_factor) * 1.1

	var tw := create_tween().set_parallel(true)
	# Fly inward to center.
	tw.tween_property(spark, "position", Vector2.ZERO, flight) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# Scale up during travel, then shrink to nothing at arrival.
	tw.tween_property(spark, "scale", peak_scale, flight * 0.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(spark, "scale", Vector2.ZERO, flight * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Colour shift core → tail midway, then fade alpha at arrival.
	tw.tween_property(spark, "modulate", COLOR_TAIL, flight * 0.6) \
		.set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(spark, "modulate:a", 0.0, flight * 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(spark.queue_free)
