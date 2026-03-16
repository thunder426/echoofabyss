## CostBadge.gd
## Draws a circular gem badge for card cost display.
## Set bg_color / rim_color then call queue_redraw().
class_name CostBadge
extends Control

var bg_color:  Color = Color(0.18, 0.06, 0.32, 0.95)
var rim_color: Color = Color(0.70, 0.28, 1.00, 1.00)

func _draw() -> void:
	var c := size / 2.0
	var r: float = min(size.x, size.y) * 0.48
	draw_circle(c, r, rim_color)         # outer rim
	draw_circle(c, r - 1.5, bg_color)   # inner fill
