## VoidImpClawVFX.gd
## Shadow claw slash over the target hero panel — used by Void Imp on-play
## (non-piercing-void branch: deal 100 damage to enemy hero).
##
## Phases:
##   1. Anticipation (0.08s) — brief dark shimmer at source minion position
##   2. Strike     (0.15s) — claw texture clip-revealed diagonally over hero panel
##   3. Impact     (0.10s) — panel flash + shake + purple glow burst
##   4. Dissolve   (0.30s) — claw fades, dark wisps float off
##
## Spawn via VfxController.spawn() — do not parent manually.
class_name VoidImpClawVFX
extends Node

signal finished
signal impact_hit

const TEX_CLAW: Texture2D = preload("res://assets/art/fx/void_imp_claw.png")
const TEX_GLOW: Texture2D = preload("res://assets/art/fx/glow_soft.png")

const COLOR_VOID: Color       = Color(0.65, 0.30, 1.0, 0.9)
const COLOR_VOID_DARK: Color  = Color(0.35, 0.12, 0.55, 0.7)


const ANTICIPATION_DUR: float = 0.08
const STRIKE_DUR: float       = 0.15
const IMPACT_DUR: float       = 0.10
const DISSOLVE_DUR: float     = 0.30
const TOTAL_DURATION: float   = ANTICIPATION_DUR + STRIKE_DUR + IMPACT_DUR + DISSOLVE_DUR

var _target_panel: Control = null
var _source_pos: Vector2 = Vector2.ZERO


static func create(target_panel: Control, source_pos: Vector2 = Vector2.ZERO) -> VoidImpClawVFX:
	var vfx := VoidImpClawVFX.new()
	vfx._target_panel = target_panel
	vfx._source_pos = source_pos
	return vfx


func _ready() -> void:
	_run()


func _run() -> void:
	# `host` = VfxLayer (CanvasLayer layer 2). All children parent to it so
	# they render above the HUD.
	var host: Node = get_parent()
	if _target_panel == null or host == null or not is_inside_tree():
		impact_hit.emit()
		finished.emit()
		queue_free()
		return

	var panel_center: Vector2 = _target_panel.global_position + _target_panel.size * 0.5

	# ── Phase 1: Anticipation — dark shimmer at source ───────────────────────
	if _source_pos != Vector2.ZERO:
		_spawn_anticipation(host)
	await get_tree().create_timer(ANTICIPATION_DUR).timeout
	if not is_inside_tree():
		impact_hit.emit()
		finished.emit()
		queue_free()
		return

	# ── Phase 2: Strike — claw revealed over hero panel ──────────────────────
	var claw_node := _spawn_claw_strike(host, panel_center)

	await get_tree().create_timer(STRIKE_DUR).timeout
	if not is_inside_tree():
		impact_hit.emit()
		finished.emit()
		queue_free()
		return

	# ── Phase 3: Impact — shake ──────────────────────────────────────────────
	impact_hit.emit()
	ScreenShakeEffect.shake(_target_panel, self, 10.0, 8)

	await get_tree().create_timer(IMPACT_DUR).timeout
	if not is_inside_tree():
		finished.emit()
		queue_free()
		return

	# ── Phase 4: Dissolve — claw fades + wisps ───────────────────────────────
	_spawn_dissolve_wisps(host, panel_center)
	if is_instance_valid(claw_node):
		var tw := create_tween()
		tw.tween_property(claw_node, "modulate:a", 0.0, DISSOLVE_DUR) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_callback(claw_node.queue_free)

	await get_tree().create_timer(DISSOLVE_DUR + 0.05).timeout
	finished.emit()
	queue_free()


# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: Anticipation
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_anticipation(ui: Node) -> void:
	var glow := _make_additive_rect(TEX_GLOW, COLOR_VOID_DARK)
	var s: float = 60.0
	glow.set_size(Vector2(s, s))
	glow.position = _source_pos - Vector2(s, s) * 0.5
	glow.pivot_offset = Vector2(s, s) * 0.5
	glow.modulate.a = 0.0
	glow.z_index = 12
	glow.z_as_relative = false
	ui.add_child(glow)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(glow, "modulate:a", 0.7, ANTICIPATION_DUR * 0.6)
	tw.tween_property(glow, "scale", Vector2(1.3, 1.3), ANTICIPATION_DUR) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(glow, "modulate:a", 0.0, 0.08)
	tw.chain().tween_callback(glow.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Phase 2: Claw Strike
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_claw_strike(ui: Node, center: Vector2) -> TextureRect:
	var claw := TextureRect.new()
	claw.texture = TEX_CLAW
	claw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	claw.stretch_mode = TextureRect.STRETCH_SCALE
	claw.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Size the claw slightly smaller than the hero panel
	var claw_size: float = maxf(_target_panel.size.x, _target_panel.size.y) * 0.75
	claw.set_size(Vector2(claw_size, claw_size))
	claw.position = center - Vector2(claw_size, claw_size) * 0.5
	claw.pivot_offset = Vector2(claw_size, claw_size) * 0.5
	claw.z_index = 16
	claw.z_as_relative = false

	# Additive blend so black bg becomes transparent
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	claw.material = mat

	# Start invisible and slightly offset up-left for slash motion
	claw.modulate = Color(COLOR_VOID.r, COLOR_VOID.g, COLOR_VOID.b, 0.0)
	claw.position += Vector2(-15, -20)
	claw.scale = Vector2(0.85, 0.85)
	ui.add_child(claw)

	# Animate: slash in from upper-left → center with scale snap
	var target_pos: Vector2 = center - Vector2(claw_size, claw_size) * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(claw, "modulate:a", COLOR_VOID.a, STRIKE_DUR * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(claw, "position", target_pos, STRIKE_DUR) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(claw, "scale", Vector2(1.05, 1.05), STRIKE_DUR * 0.7) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Slight overshoot then settle
	tw.chain().tween_property(claw, "scale", Vector2.ONE, 0.06) \
		.set_trans(Tween.TRANS_SINE)

	return claw


# ═════════════════════════════════════════════════════════════════════════════
# Phase 4: Dissolve Wisps
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_dissolve_wisps(ui: Node, center: Vector2) -> void:
	var wisp_count: int = 6
	for i in wisp_count:
		var angle: float = (TAU / wisp_count) * i + randf_range(-0.4, 0.4)
		var mote := _make_additive_rect(TEX_GLOW, COLOR_VOID_DARK)
		var s: float = randf_range(12.0, 22.0)
		mote.set_size(Vector2(s, s))
		mote.position = center + Vector2(randf_range(-20, 20), randf_range(-20, 20)) - Vector2(s, s) * 0.5
		mote.modulate.a = 0.8
		mote.z_index = 17
		mote.z_as_relative = false
		ui.add_child(mote)

		var drift: Vector2 = Vector2(cos(angle), sin(angle)) * randf_range(30, 60)
		var life: float = randf_range(0.20, DISSOLVE_DUR)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(mote, "position", mote.position + drift + Vector2(0, -15), life) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mote, "modulate:a", 0.0, life) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(mote, "scale", Vector2(0.3, 0.3), life)
		tw.chain().tween_callback(mote.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

static func _make_additive_rect(tex: Texture2D, color: Color) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = color
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tr.material = mat
	return tr
