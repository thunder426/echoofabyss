## BuffChevronVFX.gd
## A small Control that procedurally draws an upward green chevron (▲) shape
## and animates it: fade-in, rise slightly, fade-out, queue_free.
## Used next to stat labels to signal a buff gain when the font can't render
## unicode arrow glyphs.
class_name BuffChevronVFX
extends Control

const COLOR_FILL: Color = Color(0.45, 1.00, 0.35, 1.0)
const COLOR_OUTLINE: Color = Color(0.10, 0.30, 0.08, 1.0)
const RISE_DISTANCE: float = 6.0
const FADE_IN: float = 0.10
const HOLD: float = 0.35
const FADE_OUT: float = 0.25

var alpha: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5
	z_as_relative = false

func play() -> void:
	alpha = 0.0
	modulate.a = 1.0
	var start_y: float = position.y
	var peak_y: float = start_y - RISE_DISTANCE
	# Fade-in + rise
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "alpha", 1.0, FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", peak_y, FADE_IN + HOLD).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Hold phase: queue_redraw each frame so alpha changes are reflected
	await tw.finished
	if not is_inside_tree():
		return
	# Fade-out
	var tw2 := create_tween()
	tw2.tween_property(self, "alpha", 0.0, FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw2.finished
	queue_free()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Upward triangle (chevron) — centered horizontally
	var w: float = size.x
	var h: float = size.y
	var apex: Vector2 = Vector2(w * 0.5, 0.0)
	var left: Vector2 = Vector2(0.0, h)
	var right: Vector2 = Vector2(w, h)
	var mid_left: Vector2 = Vector2(w * 0.3, h * 0.55)
	var mid_right: Vector2 = Vector2(w * 0.7, h * 0.55)
	# Chevron = upward triangle with notch cut from bottom (so it looks like ▲ with a hollow)
	var pts := PackedVector2Array([apex, right, mid_right, mid_left, left])
	var fill := COLOR_FILL
	fill.a = alpha
	var outline := COLOR_OUTLINE
	outline.a = alpha
	draw_colored_polygon(pts, fill)
	# Outline for contrast against light sprites
	draw_polyline(PackedVector2Array([apex, right, mid_right, mid_left, left, apex]), outline, 1.0, true)
