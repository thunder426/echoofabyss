## BroodImpSparkBurstVFX.gd
## Dark-green / black spark convergence played on a BoardSlot right after the
## brood sigil collapses for a Matriarch's Broodling on-death Brood Imp summon.
## Mirrors VoidDemonSparkBurstVFX structure — each spark spawns on the slot
## edge and tweens inward to center (additive blend) — but recolored to sell
## the feral/abyssal brood read instead of arcane void.
##
## Fire-and-forget: spawn via VfxController.spawn.
class_name BroodImpSparkBurstVFX
extends BaseVfx

const TEX_SPARK: Texture2D = preload("res://assets/art/fx/spark_sprite.png")

# Dark green core → near-black tail. Core is a sickly acid-green so it still
# reads bright against the dim slot; tail is a deep charcoal-green.
const COLOR_CORE: Color = Color(0.55, 1.00, 0.45, 1.0)
const COLOR_TAIL: Color = Color(0.05, 0.12, 0.05, 0.95)

const SPARK_SIZE_PX: float   = 9.0
# Inset from slot edge so the full spark sprite (incl. peak-scale bloom) stays
# inside the slot rectangle.
const EDGE_INSET_PX: float   = 14.0
const FLIGHT_MIN: float      = 0.55
const FLIGHT_MAX: float      = 0.80
const EMIT_INTERVAL: float   = 0.018
const EMIT_DURATION: float   = 0.95
const TOTAL_DURATION: float  = EMIT_DURATION + FLIGHT_MAX + 0.1

var _target_slot: BoardSlot = null


static func create(target_slot: BoardSlot) -> BroodImpSparkBurstVFX:
	var vfx := BroodImpSparkBurstVFX.new()
	vfx._target_slot = target_slot
	vfx.impact_count = 0
	vfx.z_index = 200
	return vfx


func _play() -> void:
	if _target_slot == null or not _target_slot.is_inside_tree():
		finished.emit()
		queue_free()
		return

	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_spawning.wav", -10.0)

	var slot_size: Vector2 = _target_slot.size
	var center: Vector2 = _target_slot.global_position + slot_size * 0.5
	global_position = center

	var scale_factor: float = SPARK_SIZE_PX / maxf(float(TEX_SPARK.get_width()), 1.0)

	var elapsed: float = 0.0
	while elapsed < EMIT_DURATION:
		if not is_inside_tree():
			return
		_spawn_spark(slot_size, scale_factor)
		await get_tree().create_timer(EMIT_INTERVAL).timeout
		elapsed += EMIT_INTERVAL

	await get_tree().create_timer(FLIGHT_MAX + 0.1).timeout
	finished.emit()
	queue_free()


func _spawn_spark(slot_size: Vector2, scale_factor: float) -> void:
	# Inset so sparks spawn fully inside the slot frame.
	var half: Vector2 = Vector2(
		maxf(slot_size.x * 0.5 - EDGE_INSET_PX, 1.0),
		maxf(slot_size.y * 0.5 - EDGE_INSET_PX, 1.0)
	)
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
	tw.tween_property(spark, "position", Vector2.ZERO, flight) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(spark, "scale", peak_scale, flight * 0.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(spark, "scale", Vector2.ZERO, flight * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(spark, "modulate", COLOR_TAIL, flight * 0.6) \
		.set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(spark, "modulate:a", 0.0, flight * 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(spark.queue_free)
