## TrapEnvDisplay.gd
## Owns the trap-slot row and environment-slot UI:
##   - Resolves the panel/label/art nodes from the CombatScene tree
##   - Renders each slot based on the active trap / environment data
##   - Runs the rune-glow and sealed-pulse Tweens
##   - Provides a flash-on-fire animation
##
## State (`active_traps`, `active_environment`) lives on CombatScene because
## ~23 files read it directly (handlers, effects, AI profiles, sim, tests).
## This class is purely view — it asks the scene for the data on every
## update_*() call and re-renders.
##
## CombatScene keeps thin facades (_update_trap_display, _update_trap_display_for,
## _update_environment_display, _flash_trap_slot_for, plus the trap_slot_panels
## array as a public mirror) so existing callers keep working unchanged.
class_name TrapEnvDisplay
extends RefCounted

const _RUNE_GLOW_DEFAULT := Color(0.30, 0.15, 0.45, 1)
const _TRAP_BATTLEFIELD_ART := "res://assets/art/traps/trap_battlefield.png"
const _TRAP_SEALED_BORDER := Color(0.25, 0.12, 0.35, 0.6)
const _TRAP_SEALED_BG     := Color(0.04, 0.02, 0.06, 0.7)

# Reference back to CombatScene — used for _apply_slot_style, _apply_empty_slot,
# enemy_ai access, and read of active_traps / active_environment.
var _scene: Node2D = null

# Trap slot nodes (mirrored to scene.trap_slot_panels etc. so external readers
# like RelicEffects can still read trap_slot_panels.size()).
var player_panels: Array[Panel] = []
var player_labels: Array[Label] = []
var _player_art_containers: Array[CenterContainer] = []
var _player_arts: Array[TextureRect] = []
var _player_glow_tweens: Array = []  # Tween or null per slot

var enemy_panels: Array[Panel] = []
var enemy_labels: Array[Label] = []
var _enemy_art_containers: Array[CenterContainer] = []
var _enemy_arts: Array[TextureRect] = []
var _enemy_glow_tweens: Array = []

# Environment slot nodes
var env_slot: Panel = null
var env_name: Label = null
var env_desc: Label = null
var _env_art: TextureRect = null

func setup(scene: Node2D) -> void:
	_scene = scene
	_setup_environment_slot()
	_setup_trap_row(scene, "UI/TrapSlotsRow",      player_panels, player_labels,
			_player_art_containers, _player_arts, _player_glow_tweens)
	_setup_trap_row(scene, "UI/EnemyTrapSlotsRow", enemy_panels, enemy_labels,
			_enemy_art_containers, _enemy_arts, _enemy_glow_tweens)

func _setup_environment_slot() -> void:
	if not _scene.has_node("UI/EnvironmentSlot"):
		return
	env_slot = _scene.get_node("UI/EnvironmentSlot")
	if env_slot.has_node("SlotNameLabel"):
		env_name = env_slot.get_node("SlotNameLabel")
	if env_slot.has_node("SlotDescLabel"):
		env_desc = env_slot.get_node("SlotDescLabel")
	# Art rect — behind text, fills the slot
	_env_art = TextureRect.new()
	_env_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_env_art.stretch_mode = TextureRect.STRETCH_SCALE
	_env_art.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_env_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_env_art.modulate     = Color(1, 1, 1, 0.4)
	_env_art.visible      = false
	env_slot.add_child(_env_art)
	env_slot.move_child(_env_art, 0)

func _setup_trap_row(scene: Node, row_path: String,
		panels: Array[Panel], labels: Array[Label],
		art_containers: Array[CenterContainer], arts: Array[TextureRect],
		glow_tweens: Array) -> void:
	if not scene.has_node(row_path):
		return
	var row := scene.get_node(row_path)
	for i in 3:
		var panel := row.get_child(i) as Panel
		panels.append(panel)
		labels.append(panel.get_child(0) as Label)
		var art_center := CenterContainer.new()
		art_center.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_center.visible = false
		var art := TextureRect.new()
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		art.custom_minimum_size = Vector2(72, 72)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_center.add_child(art)
		panel.add_child(art_center)
		panel.move_child(art_center, 0)
		art_containers.append(art_center)
		arts.append(art)
		glow_tweens.append(null)

# ---------------------------------------------------------------------------
# Public renders
# ---------------------------------------------------------------------------

func update_environment() -> void:
	if env_slot == null:
		return
	var active = _scene.active_environment
	if active != null:
		_scene._apply_slot_style(env_slot, Color(0.02, 0.02, 0.04, 0.3), Color(0.15, 0.75, 0.35, 1))
		if env_name != null: env_name.visible = false
		if env_desc != null: env_desc.visible = false
		var header := env_slot.get_node_or_null("HeaderLabel")
		if header != null: header.visible = false
		env_slot.tooltip_text = ""
		if _env_art != null:
			_env_art.modulate = Color(1, 1, 1, 1)
			if active.art_path != "" and ResourceLoader.exists(active.art_path):
				_env_art.texture = load(active.art_path)
				_env_art.visible = true
			else:
				_env_art.visible = false
	else:
		_scene._apply_empty_slot(env_slot, env_name)
		if env_desc != null:
			env_desc.visible = true
			env_desc.text = ""
		var header := env_slot.get_node_or_null("HeaderLabel")
		if header != null: header.visible = true
		env_slot.tooltip_text = ""
		if _env_art != null: _env_art.visible = false

func update_traps_for(owner: String) -> void:
	var panels: Array = player_panels       if owner == "player" else enemy_panels
	var labels: Array = player_labels       if owner == "player" else enemy_labels
	var traps:  Array = _scene.active_traps if owner == "player" else (_scene.enemy_ai.active_traps if _scene.enemy_ai else [])
	var is_enemy := owner == "enemy"
	var is_player := owner == "player"
	for i in panels.size():
		var panel := panels[i] as Panel
		var lbl   := labels[i] as Label
		var art: TextureRect
		var art_container: CenterContainer
		if is_player and i < _player_arts.size():
			art = _player_arts[i]
			art_container = _player_art_containers[i]
		elif is_enemy and i < _enemy_arts.size():
			art = _enemy_arts[i]
			art_container = _enemy_art_containers[i]
		else:
			art = null
			art_container = null
		if i < traps.size():
			var trap := traps[i] as TrapCardData
			if trap.is_rune:
				var has_art := false
				if art_container != null:
					if trap.battlefield_art_path != "" and ResourceLoader.exists(trap.battlefield_art_path):
						art.texture = load(trap.battlefield_art_path)
						art.modulate = Color(1, 1, 1, 1)
						art_container.visible = true
						has_art = true
						lbl.visible = false
						var border_color: Color = _get_rune_glow_color(trap)
						_scene._apply_slot_style(panel, Color(0.02, 0.02, 0.04, 0.2), border_color)
					else:
						art_container.visible = false
				if not has_art:
					lbl.visible = true
					lbl.text = trap.card_name
					var fallback_border: Color = _get_rune_glow_color(trap)
					_scene._apply_slot_style(panel, Color(0.10, 0.04, 0.22, 1), fallback_border)
				panel.tooltip_text = ""
				start_rune_glow(i, trap, owner)
			elif is_enemy:
				if art_container != null and ResourceLoader.exists(_TRAP_BATTLEFIELD_ART):
					art.texture = load(_TRAP_BATTLEFIELD_ART)
					art.modulate = Color(0.55, 0.35, 0.65, 0.6)
					art_container.visible = true
					lbl.visible = false
				else:
					if art_container != null: art_container.visible = false
					lbl.visible = true
					lbl.text = trap.card_name
				_scene._apply_slot_style(panel, _TRAP_SEALED_BG, _TRAP_SEALED_BORDER)
				panel.tooltip_text = ""
				start_sealed_pulse(i, "enemy")
			else:
				if is_player and art_container != null and ResourceLoader.exists(_TRAP_BATTLEFIELD_ART):
					art.texture = load(_TRAP_BATTLEFIELD_ART)
					art.modulate = Color(0.55, 0.35, 0.65, 0.6)
					art_container.visible = true
					lbl.visible = false
				else:
					if art_container != null: art_container.visible = false
					lbl.visible = true
					lbl.text = trap.card_name
				_scene._apply_slot_style(panel, _TRAP_SEALED_BG, _TRAP_SEALED_BORDER)
				panel.tooltip_text = ""
				if is_player:
					start_sealed_pulse(i)
		else:
			_scene._apply_empty_slot(panel, lbl)
			panel.tooltip_text = ""
			if art_container != null: art_container.visible = false
			stop_rune_glow(i, owner)

func flash_slot(owner: String, slot_idx: int) -> void:
	var panels := player_panels if owner == "player" else enemy_panels
	if slot_idx >= 0 and slot_idx < panels.size():
		var panel := panels[slot_idx]
		_scene._apply_slot_style(panel, Color(0.35, 0.28, 0.0, 1), Color(1.0, 0.85, 0.1, 1))
		var tw := _scene.create_tween()
		tw.tween_interval(0.5)
		tw.tween_callback(func(): update_traps_for(owner))

# ---------------------------------------------------------------------------
# Rune glow / sealed pulse Tweens
# ---------------------------------------------------------------------------

func _get_rune_glow_color(trap: TrapCardData) -> Color:
	if trap.rune_glow_color.a > 0:
		return trap.rune_glow_color
	return _RUNE_GLOW_DEFAULT

func start_rune_glow(slot_idx: int, trap: TrapCardData, owner: String = "player") -> void:
	var tweens: Array = _player_glow_tweens if owner == "player" else _enemy_glow_tweens
	var panels: Array = player_panels       if owner == "player" else enemy_panels
	if slot_idx >= tweens.size():
		return
	if tweens[slot_idx] != null:
		return
	var panel: Panel = panels[slot_idx] as Panel
	var glow_color: Color = _get_rune_glow_color(trap)
	var bright := Color(glow_color.r * 1.4, glow_color.g * 1.4, glow_color.b * 1.4, 1.0)
	var dim    := Color(glow_color.r * 0.7, glow_color.g * 0.7, glow_color.b * 0.7, 1.0)
	var tween := _scene.create_tween().set_loops()
	tween.tween_property(panel, "modulate", bright, 1.2).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(panel, "modulate", dim, 1.2).set_ease(Tween.EASE_IN_OUT)
	tweens[slot_idx] = tween

func stop_rune_glow(slot_idx: int, owner: String = "player") -> void:
	var tweens: Array = _player_glow_tweens if owner == "player" else _enemy_glow_tweens
	var panels: Array = player_panels       if owner == "player" else enemy_panels
	if slot_idx >= tweens.size():
		return
	var tween = tweens[slot_idx]
	if tween != null and tween is Tween:
		(tween as Tween).kill()
	tweens[slot_idx] = null
	if slot_idx < panels.size():
		(panels[slot_idx] as Panel).modulate = Color(1, 1, 1, 1)

func start_sealed_pulse(slot_idx: int, owner: String = "player") -> void:
	var tweens: Array = _player_glow_tweens if owner == "player" else _enemy_glow_tweens
	var panels: Array = player_panels       if owner == "player" else enemy_panels
	if slot_idx >= tweens.size():
		return
	if tweens[slot_idx] != null:
		return
	var panel: Panel = panels[slot_idx]
	var tween := _scene.create_tween().set_loops()
	tween.tween_property(panel, "modulate", Color(1.15, 1.0, 1.2, 1.0), 2.0).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(panel, "modulate", Color(0.7, 0.6, 0.75, 1.0), 2.0).set_ease(Tween.EASE_IN_OUT)
	tweens[slot_idx] = tween
