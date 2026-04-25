## CounterWarning.gd
## The "⚠ Your next spell will be COUNTERED!" label that appears when an
## enemy spell-counter is armed. Owns the Label node, the fade-in/out tweens,
## and a subtle alpha pulse loop while visible.
##
## CombatScene reads scene._player_spell_counter to decide should_show; that
## state stays on scene (it's part of the broader spell-counter system).
## A facade method _update_counter_warning() on CombatScene lets handlers
## (CombatHandlers.gd) keep calling _scene._update_counter_warning() unchanged.
class_name CounterWarning
extends RefCounted

var _scene: Node2D = null
var label: Label = null

func _init(scene: Node2D) -> void:
	_scene = scene

func setup() -> void:
	var ui_root := _scene.get_node_or_null("UI")
	if ui_root == null:
		return
	label = Label.new()
	label.text = "⚠ Your next spell will be COUNTERED!"
	label.add_theme_font_override("font", _scene.DAMAGE_FONT)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchors_preset = Control.PRESET_CENTER_TOP
	label.position = Vector2(960 - 220, 460)
	label.size = Vector2(440, 30)
	label.z_index = 90
	label.visible = false
	ui_root.add_child(label)

## Show or hide based on scene._player_spell_counter > 0. Idempotent —
## skips work if visibility already matches.
func update() -> void:
	if label == null:
		return
	var should_show: bool = _scene._player_spell_counter > 0
	if should_show and not label.visible:
		label.visible = true
		label.modulate = Color(1, 1, 1, 0)
		var tw := _scene.create_tween()
		tw.tween_property(label, "modulate:a", 1.0, 0.3)
		# Subtle pulse loop while visible
		var pulse := _scene.create_tween().set_loops()
		pulse.tween_property(label, "modulate:a", 0.5, 0.8) \
			.set_trans(Tween.TRANS_SINE)
		pulse.tween_property(label, "modulate:a", 1.0, 0.8) \
			.set_trans(Tween.TRANS_SINE)
		label.set_meta("pulse_tween", pulse)
	elif not should_show and label.visible:
		if label.has_meta("pulse_tween"):
			var pulse: Tween = label.get_meta("pulse_tween")
			if pulse and pulse.is_valid():
				pulse.kill()
			label.remove_meta("pulse_tween")
		var tw := _scene.create_tween()
		tw.tween_property(label, "modulate:a", 0.0, 0.25)
		tw.tween_callback(func() -> void: label.visible = false)
