## Void Netter on-play VFX.
##
## Clean version:
##   1. A transparent void net flies to the target.
##   2. The same net expands slightly to wrap the target on impact.
## No rune language, no overlay frame on top of the net.
class_name VoidNetterVFX
extends BaseVfx

const TEX_PROJECTILE: Texture2D = preload("res://assets/art/fx/void_netter_wrap_net_v1.png")
const TEX_WRAP: Texture2D = preload("res://assets/art/fx/void_netter_slot_overlay_v1.png")
const SHADER_NET_MASK: Shader = preload("res://combat/effects/void_netter_net_mask.gdshader")

const TIME_SCALE := 2.5
const FLIGHT_DURATION := 0.26 * TIME_SCALE
const WRAP_HOLD := 0.30 * TIME_SCALE
const FADE_DURATION := 0.24 * TIME_SCALE

var _source_slot: BoardSlot = null
var _target_slot: BoardSlot = null
var _on_impact: Callable = Callable()

var _net: Sprite2D = null
var _follow_slot: bool = false


static func create(source_slot: BoardSlot, target_slot: BoardSlot,
		on_impact: Callable = Callable()) -> VoidNetterVFX:
	var vfx := VoidNetterVFX.new()
	vfx._source_slot = source_slot
	vfx._target_slot = target_slot
	vfx._on_impact = on_impact
	vfx.z_index = 200
	return vfx


func _play() -> void:
	if not _has_live_slots():
		_fire_impact()
		finished.emit()
		queue_free()
		return

	_build_net()
	AudioManager.play_sfx("res://assets/audio/sfx/minions/void_netter_throw.wav", -9.0)
	await _animate_flight()
	if not is_inside_tree():
		return

	AudioManager.play_sfx("res://assets/audio/sfx/minions/void_netter_snap.wav", -8.0)
	_animate_wrap()
	if _target_slot != null:
		ScreenShakeEffect.shake(_target_slot, self, 6.0, 5)

	await get_tree().create_timer(WRAP_HOLD).timeout
	if not is_inside_tree():
		return

	_fire_impact()

	var fade_tw := create_tween()
	fade_tw.tween_property(_net, "modulate:a", 0.0, FADE_DURATION)
	await fade_tw.finished
	if not is_inside_tree():
		return
	finished.emit()
	queue_free()


func _has_live_slots() -> bool:
	return _source_slot != null and _target_slot != null \
		and is_instance_valid(_source_slot) and is_instance_valid(_target_slot) \
		and _source_slot.is_inside_tree() and _target_slot.is_inside_tree()


func _fire_impact() -> void:
	impact_hit.emit(0)
	if _on_impact.is_valid():
		_on_impact.call()


func _build_net() -> void:
	_net = Sprite2D.new()
	_net.texture = TEX_PROJECTILE
	_net.position = _slot_center(_source_slot)
	_net.scale = Vector2.ONE * 0.10
	_net.modulate = Color(1.0, 1.0, 1.0, 0.96)
	add_child(_net)


func _animate_flight() -> void:
	if _net == null:
		return
	var start := _slot_center(_source_slot)
	var end := _slot_center(_target_slot)
	var delta := end - start
	var angle := delta.angle()
	var normal := delta.normalized().orthogonal()
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			var base := start.lerp(end, p)
			var arc := sin(p * PI) * -48.0
			_net.position = base + normal * arc
			_net.rotation = angle + p * TAU * 0.6,
			0.0, 1.0, FLIGHT_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_net, "scale", Vector2.ONE * 0.16, FLIGHT_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished


func _animate_wrap() -> void:
	if _net == null:
		return
	_net.position = _slot_center(_target_slot)
	_net.rotation = 0.0
	_net.texture = TEX_WRAP
	_net.scale = _wrap_scale_for_slot(_target_slot, _net.texture)
	_net.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var wrap_mat := ShaderMaterial.new()
	wrap_mat.shader = SHADER_NET_MASK
	wrap_mat.set_shader_parameter("tint_color", Color(1.0, 1.0, 1.0, 1.0))
	wrap_mat.set_shader_parameter("alpha_boost", 1.9)
	wrap_mat.set_shader_parameter("cutoff_low", 0.05)
	wrap_mat.set_shader_parameter("cutoff_high", 0.22)
	wrap_mat.set_shader_parameter("glow_strength", 0.18)
	_net.material = wrap_mat
	_follow_slot = true


func _process(_delta: float) -> void:
	if not _follow_slot or _net == null or _target_slot == null \
			or not is_instance_valid(_target_slot) or not _target_slot.is_inside_tree():
		return
	_net.position = _slot_center(_target_slot)


func _slot_center(slot: BoardSlot) -> Vector2:
	return slot.global_position + slot.size * 0.5


func _wrap_scale_for_slot(slot: BoardSlot, texture: Texture2D) -> Vector2:
	if slot == null or texture == null:
		return Vector2.ONE
	var tex_size := texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return Vector2.ONE
	return Vector2(slot.size.x / tex_size.x, slot.size.y / tex_size.y)
