## AbyssalPlagueVFX.gd
## VFX for the Abyssal Plague spell — a green plague wave launches from the
## caster's hero panel and surges across the target's minion row.
##
## Phases:
##   1. windup (0.50s) — caster panel pulses sickly green
##   2. surge  (3.50s) — flood shader sweeps across the board; per-minion
##                        damage callbacks fire as the wave-front crosses
##                        each slot (geometric timing, scheduled via
##                        per-callback tween delays — orthogonal to phases).
##
## Damage resolves internally through `per_minion_cb`, so this VFX sets
## `impact_count = 0` (controller does NOT gate damage on impact_hit).
##
## Spawn via VfxController — do not parent manually.
class_name AbyssalPlagueVFX
extends BaseVfx

const SHADER_FLOOD: Shader   = preload("res://combat/effects/plague_flood.gdshader")
const TEX_FLOW: Texture2D    = preload("res://assets/art/fx/emerald_flow.png")
const TEX_DENSITY: Texture2D = preload("res://assets/art/fx/density_mask.png")

const WINDUP_DURATION: float = 0.50
const SURGE_DURATION: float  = 3.50
const OVERSHOOT_PX: float    = 180.0

var _caster_panel: Control = null
var _caster_side: String = "player"
var _all_slots: Array = []
var _occupied_slots: Array = []
var _per_minion_cb: Callable = Callable()


static func create(caster_panel: Control, caster_side: String,
		all_slots: Array, occupied_slots: Array,
		per_minion_cb: Callable = Callable()) -> AbyssalPlagueVFX:
	var vfx := AbyssalPlagueVFX.new()
	vfx._caster_panel = caster_panel
	vfx._caster_side = caster_side
	vfx._all_slots = all_slots
	vfx._occupied_slots = occupied_slots
	vfx._per_minion_cb = per_minion_cb
	vfx.impact_count = 0
	return vfx


func _play() -> void:
	var host: CanvasLayer = get_parent() as CanvasLayer
	if _caster_panel == null or host == null:
		finished.emit()
		queue_free()
		return

	sequence().run([
		VfxPhase.new("windup", WINDUP_DURATION, _build_windup),
		VfxPhase.new("surge",  SURGE_DURATION,  _build_surge),
	])


func _build_windup(_duration: float) -> void:
	_spawn_caster_glow(_caster_panel)
	AudioManager.play_sfx("res://assets/audio/sfx/spells/abyssal_plague_windup.wav", -4.0)


func _build_surge(duration: float) -> void:
	var host: CanvasLayer = get_parent() as CanvasLayer
	if host == null:
		return

	AudioManager.play_sfx("res://assets/audio/sfx/spells/abyssal_plague_wash.wav", -6.0)

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	var origin_y_uv: float
	var direction_y: float
	if _caster_side == "player":
		origin_y_uv = 1.05
		direction_y = -1.0
	else:
		origin_y_uv = -0.05
		direction_y = 1.0

	var farthest_y_delta_px: float = 0.0
	var origin_y_px: float = origin_y_uv * vp_size.y
	var min_x_px: float = INF
	var max_x_px: float = -INF
	for s in _all_slots:
		var slot_center_y: float = (s as Control).global_position.y + (s as Control).size.y * 0.5
		var delta: float = (slot_center_y - origin_y_px) * direction_y
		if delta > farthest_y_delta_px:
			farthest_y_delta_px = delta
		var slot_left: float = (s as Control).global_position.x
		var slot_right: float = slot_left + (s as Control).size.x
		if slot_left < min_x_px:
			min_x_px = slot_left
		if slot_right > max_x_px:
			max_x_px = slot_right
	if _all_slots.is_empty():
		farthest_y_delta_px = vp_size.y * 0.5
		min_x_px = vp_size.x * 0.15
		max_x_px = vp_size.x * 0.85
	var max_reach_px: float = farthest_y_delta_px + OVERSHOOT_PX
	var max_reach_uv: float = max_reach_px / vp_size.y
	var band_x_min_uv: float = min_x_px / vp_size.x
	var band_x_max_uv: float = max_x_px / vp_size.x

	var layer_configs: Array = [
		{
			"z": 15,
			"reach_scale": 1.0,
			"trail_length": 0.55,
			"lateral_scale": 1.0,
			"tint": Color(0.15, 0.70, 0.25, 0.70),
			"strength": 0.045,
			"front_strength": 1.2,
			"body_strength": 0.15,
			"ca_amount": 0.35,
			"front_width": 0.05,
			"flow_scale": 1.0,
			"flow_scroll_speed": 0.25,
			"density_scroll_speed": 0.10,
			"crest_wobble_amp": 0.025,
			"crest_wobble_freq": 7.5,
			"foam_threshold": 0.58,
			"foam_intensity": 1.8,
			"tendril_reach": 0.0,
			"foam_color": Color(0.78, 1.0, 0.70, 1.0),
			"edge_foam_width": 0.014,
			"edge_foam_intensity": 0.0,
			"edge_glow_reach": 0.018,
			"edge_glow_intensity": 0.0,
			"spray_reach": 0.025,
			"spray_density": 0.982,
			"spray_intensity": 1.3,
		},
	]

	var layer_rects: Array[ColorRect] = []
	var layer_mats: Array[ShaderMaterial] = []
	var base_time_offset: float = randf() * 50.0

	for i in layer_configs.size():
		var cfg: Dictionary = layer_configs[i]
		var rect := ColorRect.new()
		rect.color = Color(1, 1, 1, 1)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.z_index = cfg["z"]
		rect.z_as_relative = false

		var mat := ShaderMaterial.new()
		mat.shader = SHADER_FLOOD
		mat.set_shader_parameter("origin_y", origin_y_uv)
		mat.set_shader_parameter("direction_y", direction_y)
		mat.set_shader_parameter("reach", max_reach_uv * float(cfg["reach_scale"]))
		mat.set_shader_parameter("thickness", 0.30)
		mat.set_shader_parameter("trail_length", max_reach_uv * float(cfg["trail_length"]))

		var band_center_v: float = (band_x_min_uv + band_x_max_uv) * 0.5
		var band_half_v: float = (band_x_max_uv - band_x_min_uv) * 0.5 * float(cfg["lateral_scale"])
		mat.set_shader_parameter("band_x_min", band_center_v - band_half_v)
		mat.set_shader_parameter("band_x_max", band_center_v + band_half_v)

		mat.set_shader_parameter("strength",       float(cfg["strength"]))
		mat.set_shader_parameter("front_strength", float(cfg["front_strength"]))
		mat.set_shader_parameter("body_strength",  float(cfg["body_strength"]))
		mat.set_shader_parameter("ca_amount",      float(cfg["ca_amount"]))
		mat.set_shader_parameter("front_width",    float(cfg["front_width"]))

		mat.set_shader_parameter("tint", cfg["tint"])
		mat.set_shader_parameter("progress", 0.0)
		mat.set_shader_parameter("alpha_multiplier", 1.0)
		mat.set_shader_parameter("time_offset", base_time_offset + float(i) * 13.7)

		mat.set_shader_parameter("flow_tex",    TEX_FLOW)
		mat.set_shader_parameter("density_tex", TEX_DENSITY)
		mat.set_shader_parameter("flow_scale",           float(cfg["flow_scale"]))
		mat.set_shader_parameter("flow_scroll_speed",    float(cfg["flow_scroll_speed"]))
		mat.set_shader_parameter("density_scroll_speed", float(cfg["density_scroll_speed"]))

		mat.set_shader_parameter("crest_wobble_amp",  float(cfg["crest_wobble_amp"]))
		mat.set_shader_parameter("crest_wobble_freq", float(cfg["crest_wobble_freq"]))
		mat.set_shader_parameter("foam_threshold",    float(cfg["foam_threshold"]))
		mat.set_shader_parameter("foam_intensity",    float(cfg["foam_intensity"]))
		mat.set_shader_parameter("tendril_reach",     float(cfg["tendril_reach"]))
		mat.set_shader_parameter("foam_color",        cfg["foam_color"])

		mat.set_shader_parameter("edge_foam_width",     float(cfg["edge_foam_width"]))
		mat.set_shader_parameter("edge_foam_intensity", float(cfg["edge_foam_intensity"]))
		mat.set_shader_parameter("edge_glow_reach",     float(cfg["edge_glow_reach"]))
		mat.set_shader_parameter("edge_glow_intensity", float(cfg["edge_glow_intensity"]))
		mat.set_shader_parameter("spray_reach",         float(cfg["spray_reach"]))
		mat.set_shader_parameter("spray_density",       float(cfg["spray_density"]))
		mat.set_shader_parameter("spray_intensity",     float(cfg["spray_intensity"]))

		rect.material = mat
		host.add_child(rect)
		layer_rects.append(rect)
		layer_mats.append(mat)

	# Spark/droplet particles riding the wave front
	var particles := AbyssalPlagueParticles.spawn(
		host, origin_y_px, direction_y,
		min_x_px, max_x_px, max_reach_px, duration)
	host.add_child(particles)

	# Schedule per-minion damage callbacks based on wave-front geometry.
	if _per_minion_cb.is_valid():
		for s in _occupied_slots:
			var slot: BoardSlot = s as BoardSlot
			if slot == null or slot.minion == null:
				continue
			var slot_y: float = slot.global_position.y + slot.size.y * 0.5
			var y_delta_px: float = (slot_y - origin_y_px) * direction_y
			if y_delta_px <= 0.0:
				continue
			var y_delta_uv: float = y_delta_px / vp_size.y
			var ratio: float = y_delta_uv / max_reach_uv
			ratio = clampf(ratio, 0.0, 0.999)
			var arrival_t: float = duration * (1.0 - pow(1.0 - ratio, 1.0 / 3.0))
			_schedule_minion_hit(slot.minion, arrival_t)

	# Drive progress + fade
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(p: float) -> void:
			for m in layer_mats:
				m.set_shader_parameter("progress", p),
			0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
			for m in layer_mats:
				m.set_shader_parameter("alpha_multiplier", a),
			1.0, 0.0, duration * 0.30).set_delay(duration * 0.70).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(func() -> void:
			for r in layer_rects:
				r.queue_free())


# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

func _schedule_minion_hit(minion: MinionInstance, delay: float) -> void:
	_delayed_hit(minion, delay)


func _delayed_hit(minion: MinionInstance, delay: float) -> void:
	await get_tree().create_timer(maxf(delay, 0.0)).timeout
	if not is_inside_tree():
		return
	if _per_minion_cb.is_valid():
		_per_minion_cb.call(minion)
	var hit_variants: Array[String] = [
		"res://assets/audio/sfx/spells/abyssal_plague_hit_low.wav",
		"res://assets/audio/sfx/spells/abyssal_plague_hit_mid.wav",
		"res://assets/audio/sfx/spells/abyssal_plague_hit_high.wav",
	]
	AudioManager.play_sfx(hit_variants.pick_random(), -10.0)


func _spawn_caster_glow(panel: Control) -> void:
	var glow := ColorRect.new()
	glow.color = Color(0.25, 0.85, 0.20, 0.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_size(panel.size)
	glow.global_position = panel.global_position
	glow.z_index = 9
	glow.z_as_relative = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	get_parent().add_child(glow)
	var tw := glow.create_tween()
	tw.tween_property(glow, "color:a", 0.35, WINDUP_DURATION * 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(glow, "color:a", 0.0, WINDUP_DURATION * 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(glow.queue_free)
