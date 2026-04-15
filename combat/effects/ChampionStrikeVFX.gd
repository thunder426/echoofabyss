## ChampionStrikeVFX.gd
## Static helpers that layer extra visual effects on top of a champion's attack
## animation (afterimage trail + radial shockwave on the defender). Per-champion
## tweaks (color, afterimage count, lunge feel) are applied via a config dict.
##
## Call sites pass a BoardSlot for attacker and defender; the regular lunge
## animation is unchanged — these effects are additive overlays.
class_name ChampionStrikeVFX
extends RefCounted

## Per-champion config. Unknown champion IDs fall back to DEFAULT_CONFIG (gold).
const CHAMPION_CONFIGS: Dictionary = {
	# Fight 1 — Rogue Imp Pack (SWIFT + ferocious pack predator → crimson streaks)
	"champion_rogue_imp_pack": {
		"color":            Color(1.00, 0.18, 0.12, 1.0),  # crimson
		"afterimage_count": 5,
		"afterimage_spread": 22.0,
		"afterimage_alpha": 0.55,
		"shockwave_color":  Color(1.00, 0.30, 0.18, 1.0),
		"shockwave_scale":  2.6,
	},
}

const DEFAULT_CONFIG: Dictionary = {
	"color":            Color(1.00, 0.82, 0.25, 1.0),  # gold
	"afterimage_count": 3,
	"afterimage_spread": 16.0,
	"afterimage_alpha": 0.50,
	"shockwave_color":  Color(1.00, 0.82, 0.25, 1.0),
	"shockwave_scale":  2.3,
}

## Return the config for a given champion id, or DEFAULT_CONFIG if unknown.
static func config_for(champion_id: String) -> Dictionary:
	return CHAMPION_CONFIGS.get(champion_id, DEFAULT_CONFIG)

## Spawn a trail of colored silhouettes from start → end. Fades out over 0.35s.
## Parent is typically the scene's $UI layer.
static func spawn_afterimage_trail(parent: Node, atk_slot: BoardSlot, end_pos: Vector2, config: Dictionary) -> void:
	var count: int = config.get("afterimage_count", 3)
	var color: Color = config.get("color", Color.WHITE)
	var max_alpha: float = config.get("afterimage_alpha", 0.5)
	var start_pos: Vector2 = atk_slot.global_position
	var spread: float = config.get("afterimage_spread", 16.0)

	for i in count:
		var t_norm: float = float(i) / float(max(count - 1, 1))
		var pos := start_pos.lerp(end_pos, 1.0 - t_norm)
		# Jitter perpendicular to the lunge direction for a "ripping through air" feel
		var dir: Vector2 = (end_pos - start_pos).normalized()
		var perp := Vector2(-dir.y, dir.x)
		pos += perp * (sin(t_norm * PI) * spread * (randf() - 0.5) * 2.0)

		var ghost := ColorRect.new()
		ghost.color = Color(color.r, color.g, color.b, max_alpha * (1.0 - t_norm))
		ghost.set_size(atk_slot.size)
		ghost.position = pos
		ghost.z_index = 3
		ghost.z_as_relative = false
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(ghost)

		# Each ghost fades + scales down slightly
		var delay: float = t_norm * 0.04
		var tw := ghost.create_tween().set_parallel(true)
		tw.tween_interval(delay)
		tw.tween_property(ghost, "modulate:a", 0.0, 0.30).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(ghost, "scale", Vector2(0.92, 0.92), 0.30).set_delay(delay)
		tw.chain().tween_callback(ghost.queue_free)

## Spawn an expanding ring over the defender at the moment of impact.
static func spawn_shockwave(parent: Node, def_slot: BoardSlot, config: Dictionary) -> void:
	var color: Color = config.get("shockwave_color", Color.WHITE)
	var end_scale: float = config.get("shockwave_scale", 2.3)

	var ring := ColorRect.new()
	ring.color = Color(color.r, color.g, color.b, 0.75)
	ring.z_index = 4
	ring.z_as_relative = false
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ring)
	ring.set_size(def_slot.size)
	ring.pivot_offset = def_slot.size * 0.5
	ring.global_position = def_slot.global_position

	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale",      Vector2(end_scale, end_scale), 0.40).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ring, "modulate:a", 0.0,                           0.40).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(ring.queue_free)

## Mild screen shake — quarter the intensity of the summon shake. Call sites
## should pass the same $UI node used by _champion_screen_shake.
static func mild_shake(ui_node: Node, tree: SceneTree) -> void:
	if ui_node == null or tree == null:
		return
	var original_pos: Vector2 = ui_node.get("position") if ui_node.get("position") != null else Vector2.ZERO
	var ticks: int = 6
	var max_amp: float = 4.0
	for i in ticks:
		if not ui_node.is_inside_tree():
			ui_node.set("position", original_pos)
			return
		var decay: float = 1.0 - (float(i) / float(ticks))
		var amp: float = max_amp * decay
		var offset := Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		ui_node.set("position", original_pos + offset)
		await tree.create_timer(0.025).timeout
	ui_node.set("position", original_pos)
