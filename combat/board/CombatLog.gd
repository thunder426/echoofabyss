## CombatLog.gd
## Owns the combat log UI: append messages with a type, render with the right
## colour, cap the visible history at MAX entries, auto-scroll to the bottom.
##
## Rules code logs through state._log(msg, Enums.LogType.X); the presenter
## plays each LOG journal event into write(). LogType is Enums.LogType (rules
## code mustn't depend on this UI helper); CombatScene aliases it as _LogType.
class_name CombatLog
extends RefCounted

const LogType := Enums.LogType

const MAX := 80

var _container: VBoxContainer = null
var _scroll: ScrollContainer = null

func setup(scene: Node) -> void:
	if scene.has_node("UI/CombatLogPanel/LogScroll"):
		_scroll = scene.get_node("UI/CombatLogPanel/LogScroll")
	if scene.has_node("UI/CombatLogPanel/LogScroll/LogContainer"):
		_container = scene.get_node("UI/CombatLogPanel/LogScroll/LogContainer")

func write(msg: String, type: int = Enums.LogType.PLAYER) -> void:
	if _container == null:
		return
	var lbl := Label.new()
	lbl.text = msg
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", _color_for(type))
	_container.add_child(lbl)
	while _container.get_child_count() > MAX:
		var old := _container.get_child(0)
		_container.remove_child(old)
		old.free()
	if _scroll != null:
		_scroll.set_deferred("scroll_vertical", 999999)

func _color_for(type: int) -> Color:
	match type:
		Enums.LogType.TURN:   return Color(0.50, 0.50, 0.62, 1)
		Enums.LogType.PLAYER: return Color(0.50, 0.82, 1.00, 1)
		Enums.LogType.ENEMY:  return Color(1.00, 0.55, 0.40, 1)
		Enums.LogType.DAMAGE: return Color(1.00, 0.38, 0.38, 1)
		Enums.LogType.HEAL:   return Color(0.35, 0.90, 0.55, 1)
		Enums.LogType.TRAP:   return Color(1.00, 0.85, 0.15, 1)
		Enums.LogType.DEATH:  return Color(0.65, 0.45, 0.75, 1)
	return Color(0.9, 0.9, 0.9, 1)
