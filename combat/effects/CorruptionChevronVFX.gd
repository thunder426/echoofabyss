## CorruptionChevronVFX.gd
## Mirror of BuffChevronVFX — a downward red chevron (▼) that fades in,
## sinks slightly, then fades out. Used to flag a stat reduction (ATK drop
## from Corruption).
class_name CorruptionChevronVFX
extends Control

const COLOR_FILL: Color    = Color(1.00, 0.30, 0.30, 1.0)
const COLOR_OUTLINE: Color = Color(0.30, 0.05, 0.05, 1.0)
const SINK_DISTANCE: float = 6.0
const FADE_IN: float       = 0.10
const HOLD: float          = 0.35
const FADE_OUT: float      = 0.25

var alpha: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5
	z_as_relative = false

func play() -> void:
	alpha = 0.0
	modulate.a = 1.0
	var start_y: float = position.y
	var trough_y: float = start_y + SINK_DISTANCE
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "alpha", 1.0, FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", trough_y, FADE_IN + HOLD).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	if not is_inside_tree():
		return
	var tw2 := create_tween()
	tw2.tween_property(self, "alpha", 0.0, FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw2.finished
	queue_free()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Downward triangle (chevron) — centered horizontally, apex at bottom
	var w: float = size.x
	var h: float = size.y
	var apex: Vector2      = Vector2(w * 0.5, h)
	var left: Vector2      = Vector2(0.0, 0.0)
	var right: Vector2     = Vector2(w, 0.0)
	var mid_left: Vector2  = Vector2(w * 0.3, h * 0.45)
	var mid_right: Vector2 = Vector2(w * 0.7, h * 0.45)
	var pts := PackedVector2Array([apex, right, mid_right, mid_left, left])
	var fill := COLOR_FILL
	fill.a = alpha
	var outline := COLOR_OUTLINE
	outline.a = alpha
	draw_colored_polygon(pts, fill)
	draw_polyline(PackedVector2Array([apex, right, left, apex]), outline, 1.2, true)
