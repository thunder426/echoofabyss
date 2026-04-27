## VoidDemonSparkBurstVFX.gd
## One-shot purple spark convergence played on a BoardSlot right after the
## Void Spawning summon sigil collapses. Each spark spawns at a random point
## on the slot's rectangular edge and tweens inward to the slot center.
##
## Phases:
##   1. emit (0.95s) — spawn sparks at EMIT_INTERVAL, each flies inward
##   2. tail (FLIGHT_MAX + 0.1s) — wait for last sparks to converge
##
## Spawn via VfxController.spawn.
class_name VoidDemonSparkBurstVFX
extends BaseVfx

const TEX_SPARK: Texture2D = preload("res://assets/art/fx/spark_sprite.png")

const COLOR_CORE: Color = Color(1.0, 0.85, 1.0, 1.0)
const COLOR_TAIL: Color = Color(0.65, 0.30, 0.95, 0.95)

const SPARK_SIZE_PX: float   = 9.0
const EDGE_INSET_PX: float   = 14.0
const FLIGHT_MIN: float      = 0.55
const FLIGHT_MAX: float      = 0.80
const EMIT_INTERVAL: float   = 0.018
const EMIT_DURATION: float   = 0.95
const TAIL_DURATION: float   = FLIGHT_MAX + 0.1

var _target_slot: BoardSlot = null
var _slot_size: Vector2 = Vector2.ZERO
var _scale_factor: float = 1.0
var _emit_active: bool = false


static func create(target_slot: BoardSlot) -> VoidDemonSparkBurstVFX:
	var vfx := VoidDemonSparkBurstVFX.new()
	vfx._target_slot = target_slot
	vfx.impact_count = 0
	vfx.z_index = 200
	return vfx


func _play() -> void:
	if _target_slot == null or not _target_slot.is_inside_tree():
		finished.emit()
		queue_free()
		return

	AudioManager.play_sfx("res://assets/audio/sfx/spells/void_spawning.wav", -8.0)

	_slot_size = _target_slot.size
	global_position = _target_slot.global_position + _slot_size * 0.5
	_scale_factor = SPARK_SIZE_PX / maxf(float(TEX_SPARK.get_width()), 1.0)

	sequence().run([
		VfxPhase.new("emit", EMIT_DURATION, _build_emit),
		VfxPhase.new("tail", TAIL_DURATION, Callable()),
	])


func _build_emit(duration: float) -> void:
	_emit_active = true
	_run_emit_loop(duration)


func _run_emit_loop(duration: float) -> void:
	var elapsed: float = 0.0
	while elapsed < duration and _emit_active:
		if not is_inside_tree():
			return
		_spawn_spark()
		await get_tree().create_timer(EMIT_INTERVAL).timeout
		elapsed += EMIT_INTERVAL


func _spawn_spark() -> void:
	var half: Vector2 = Vector2(
		maxf(_slot_size.x * 0.5 - EDGE_INSET_PX, 1.0),
		maxf(_slot_size.y * 0.5 - EDGE_INSET_PX, 1.0)
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
	spark.scale = Vector2(_scale_factor, _scale_factor) * 0.6
	spark.modulate = COLOR_CORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spark.material = mat
	add_child(spark)

	var flight: float = randf_range(FLIGHT_MIN, FLIGHT_MAX)
	var peak_scale: Vector2 = Vector2(_scale_factor, _scale_factor) * 1.1

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
