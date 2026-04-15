## PackChainVFX.gd
## A Control that procedurally draws interlocking chain links between two points.
## Used to visualize pack_instinct links between feral imps on the enemy board.
##
## Lifecycle: forge-in → hold + pulse → fade out → queue_free.
## No external texture assets — chain is rendered entirely via _draw().
class_name PackChainVFX
extends Control

const LINK_SPACING: float = 14.0
const LINK_HALF_LENGTH: float = 7.5       # outer radius along chain direction
const LINK_HALF_THICKNESS: float = 4.0    # outer radius perpendicular to chain
const LINK_RING_THICKNESS: float = 2.0    # how thick the ring stroke is
const FORGE_DURATION: float = 0.25
const HOLD_DURATION: float = 0.55
const FADE_DURATION: float = 0.25

var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var progress: float = 0.0     # 0..1, portion of chain forged in
var alpha: float = 1.0        # 0..1, global alpha
var pulse_t: float = 0.0      # seconds since spawn, for gentle breathing glow

const _COLOR_IRON_DARK: Color = Color(0.18, 0.15, 0.14, 1.0)
const _COLOR_IRON_LIGHT: Color = Color(0.42, 0.34, 0.30, 1.0)
const _COLOR_RED_GLOW: Color = Color(1.0, 0.22, 0.12, 1.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 18
	z_as_relative = false
	# Fill parent so local (0,0) == parent (0,0), letting us use global-ish coords
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	pulse_t += delta
	queue_redraw()

## Play the full chain animation from a to b. Awaitable.
func play(a: Vector2, b: Vector2) -> void:
	start_pos = a
	end_pos = b
	progress = 0.0
	alpha = 1.0

	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "progress", 1.0, FORGE_DURATION)
	tw.tween_interval(HOLD_DURATION)
	tw.tween_property(self, "alpha", 0.0, FADE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	queue_free()

func _draw() -> void:
	if start_pos == end_pos:
		return
	var full_length: float = start_pos.distance_to(end_pos)
	if full_length < LINK_SPACING:
		return
	var visible_length: float = full_length * progress
	var dir: Vector2 = (end_pos - start_pos) / full_length
	var angle: float = dir.angle()

	# Gentle breathing pulse — widens glow slightly
	var pulse: float = 0.5 + 0.5 * sin(pulse_t * 10.0)

	var link_count: int = int(full_length / LINK_SPACING)
	for i in link_count:
		var along: float = i * LINK_SPACING + LINK_SPACING * 0.5
		if along > visible_length:
			break
		var center: Vector2 = start_pos + dir * along
		var vertical: bool = i % 2 == 0

		# ── Pass 1: outer red glow ─────────────────────────────────
		var glow_col := _COLOR_RED_GLOW
		glow_col.a = 0.28 * alpha * (0.7 + 0.3 * pulse)
		_draw_link(center, angle, vertical, 2.0, glow_col, 4.0)

		# ── Pass 2: iron link body (dark) ──────────────────────────
		var body_col := _COLOR_IRON_DARK
		body_col.a = alpha
		_draw_link(center, angle, vertical, 1.0, body_col, LINK_RING_THICKNESS + 0.5)

		# ── Pass 3: iron highlight (red-tinted rim) ────────────────
		var highlight := _COLOR_IRON_LIGHT.lerp(_COLOR_RED_GLOW, 0.35)
		highlight.a = alpha
		_draw_link(center, angle, vertical, 1.0, highlight, LINK_RING_THICKNESS - 0.8)

## Draw one chain link: an oriented oval outline.
## Rotated 90° when vertical=true to interlock with neighbors.
func _draw_link(center: Vector2, base_angle: float, vertical: bool, scale: float, col: Color, stroke: float) -> void:
	var rot: float = base_angle + (PI * 0.5 if vertical else 0.0)
	var a := LINK_HALF_LENGTH * scale
	var b := LINK_HALF_THICKNESS * scale
	# Approximate oval with a polyline of points around an ellipse.
	var pts := PackedVector2Array()
	var segments: int = 18
	for i in segments + 1:
		var t: float = float(i) / float(segments) * TAU
		var p := Vector2(cos(t) * a, sin(t) * b)
		# Rotate into chain direction
		p = p.rotated(rot)
		pts.append(center + p)
	draw_polyline(pts, col, stroke, true)
