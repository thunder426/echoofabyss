---
name: create-vfx
description: Create a new VFX effect for Echo of Abyss — builds the GDScript file using the VfxSequence DSL, wires it into CombatScene/HardcodedEffects, and follows established VFX patterns
argument-hint: <effect_name> — e.g. "frost_nova_impact", "shadow_slash_projectile", "buff_shield_aura"
user-invocable: true
---

Create a new VFX effect for Echo of Abyss at `c:\Thunder\work\Projects\EchoOfAbyss`.

The effect to create is: `$ARGUMENTS`

# Architecture Reference

All VFX live in `echoofabyss/combat/effects/` as standalone GDScript files (no .tscn — everything is built in code).

**Canonical pattern: extend `BaseVfx`, declare phases via `VfxSequence`.** No `_ready()` override, no manual `await timer / is_inside_tree() / finished.emit / queue_free` boilerplate. The sequence runner owns all of that.

## The Sequence DSL

Every VFX is a phase list. Each phase has a name, duration, and builder Callable. The sequence:

1. Calls each phase's builder once at phase start (builder spawns sprites, configures tweens, kicks off particles)
2. Waits the phase duration
3. Fires any scheduled beats at their normalized t (0=start, 1=end, fractional=mid)
4. Auto-emits the host's `impact_hit` and `finished` signals; calls `queue_free` at the end

```gdscript
class_name MyEffectVFX
extends BaseVfx

const WINDUP_DUR: float = 0.20
const IMPACT_DUR: float = 0.40
const FADE_DUR: float   = 0.30

var _target_slot: BoardSlot = null

static func create(target_slot: BoardSlot) -> MyEffectVFX:
    var vfx := MyEffectVFX.new()
    vfx._target_slot = target_slot
    vfx.z_index = 200
    return vfx

func _play() -> void:
    var seq := sequence()
    seq.on("impact", _on_impact_listener)
    seq.run([
        VfxPhase.new("windup", WINDUP_DUR, _build_windup),
        VfxPhase.new("impact", IMPACT_DUR, _build_impact) \
            .emits_at_start("impact") \
            .emits_at_start(VfxSequence.RESERVED_IMPACT_HIT),
        VfxPhase.new("fade",   FADE_DUR,   _build_fade),
    ])

func _build_windup(duration: float) -> void:
    # Spawn windup sprites, run tweens of length `duration`
    pass

func _build_impact(duration: float) -> void:
    # Spawn impact visuals
    pass

func _build_fade(duration: float) -> void:
    # Fade out
    pass

func _on_impact_listener() -> void:
    # Damage sync, screen shake, audio, etc. fired together with impact_hit
    pass
```

## Mandatory Patterns

### 1. Extend `BaseVfx`
Always. Never `extends Node` / `extends Node2D` / `extends RefCounted`. The base provides `impact_hit` and `finished` signals, the `sequence()` accessor, the `time_scale` global, and the `shake()` helper.

### 2. Override `_play()` (not `_ready()`)
`BaseVfx._ready()` calls `_play()`. Your `_play()` builds the sequence and calls `seq.run([...])`. Don't override `_ready()`.

### 3. Use VfxSequence for the Timeline
- One `VfxPhase` per visible beat: windup, impact, fade, etc.
- Phase builders are 1-arg `Callable(duration: float)`. Receive the post-scale duration so internal tweens scale with the phase.
- Beats fire at named moments via `phase.emits(beat, t_norm)` / `.emits_at_start(beat)` / `.emits_at_end(beat)`.
- The reserved beat name `VfxSequence.RESERVED_IMPACT_HIT` forwards to the host's public `impact_hit(index)` signal.

### 4. Damage Sync via impact_hit Beat
If the VFX has a moment where damage should apply, schedule the `impact_hit` beat there:

```gdscript
VfxPhase.new("impact", IMPACT_DUR, _build_impact) \
    .emits_at_start(VfxSequence.RESERVED_IMPACT_HIT)
```

The caller awaits `vfx.impact_hit` to apply gameplay effects in sync with the visual. Do NOT apply damage inside the VFX itself.

### 5. Geometry-Driven Beats (when timing depends on state)
For VFX where impact timing depends on geometry (wave reaches target, projectile arrives), fire the beat from inside the builder via `seq.emit_beat()`:

```gdscript
func _build_burst(duration: float) -> void:
    # ... compute arrival_t from geometry ...
    var seq := sequence()
    get_tree().create_timer(arrival_t).timeout.connect(func() -> void:
        if is_instance_valid(self) and is_inside_tree():
            seq.emit_beat("wave_arrived"))
```

Pair with a listener that emits impact_hit:

```gdscript
seq.on("wave_arrived", func() -> void: impact_hit.emit(0))
seq.on("wave_arrived", _spawn_impact_flash)
seq.on("wave_arrived", _shake_panel)
```

### 6. Phase Builders Use the Post-Scale Duration
Builders receive their duration as an argument. Use that, not the const directly, so global / per-sequence time scaling propagates into internal tweens:

```gdscript
func _build_windup(duration: float) -> void:
    var tw := create_tween()
    tw.tween_property(sprite, "modulate:a", 1.0, duration * 0.4)  # 40% of phase
```

### 7. Per-VFX Slow-Mo (rare)
For VFX that legitimately need to ship slower than real-time (e.g. heavy spell impacts), use `seq.time_scale`:

```gdscript
const VFX_SLOWMO: float = 2.0
func _play() -> void:
    var seq := sequence()
    seq.time_scale = VFX_SLOWMO
    seq.run([...])
```

This composes with `BaseVfx.time_scale` (global debug knob), so a 2.0 VFX scaled by a global 0.5 plays at real-time. Avoid bare `* TIME_SCALE` constants on individual tweens — let the sequence handle it.

### 8. Particles & _process Loops Stay Orthogonal
Particle systems and `_process`-driven motion (arcs, spinning, continuous emission) are NOT phases. They live alongside the sequence:

```gdscript
var _spin_active: bool = false
var _spin_elapsed: float = 0.0

func _build_travel(duration: float) -> void:
    _spin_elapsed = 0.0
    _spin_active = true
    # ... spawn projectile sprite ...

func _process(delta: float) -> void:
    if not _spin_active:
        return
    _spin_elapsed += delta
    # ... drive arc + spin ...
```

The sequence advances phases on its own clock; `_process` advances the loop on the engine's. They coexist.

### 9. CanvasLayer for Full-Screen Shaders
Full-screen shader effects (distortion, screen flash) need a dedicated `CanvasLayer`:

```gdscript
var _fx_layer: CanvasLayer = null

func _build_distortion(duration: float) -> void:
    var scene := get_parent().get_parent() if get_parent() else null
    if scene == null: return
    _fx_layer = CanvasLayer.new()
    _fx_layer.layer = 2
    scene.add_child(_fx_layer)
    # ... add ColorRect with ShaderMaterial ...

func _build_cleanup(_duration: float) -> void:
    if is_instance_valid(_fx_layer):
        _fx_layer.queue_free()
```

The sequence's auto-`queue_free` handles the host node, but external CanvasLayers parented elsewhere need explicit cleanup.

## Available Shared Resources

### Shaders
- `res://combat/effects/sonic_wave.gdshader` — radial UV distortion ring. Uniforms: `center_uv`, `progress` (0-1), `radius_max`, `thickness`, `strength`, `aspect`, `tint`, `alpha_multiplier`.
- `res://combat/effects/plague_flood.gdshader` — vertical flood wave. Single-use complex.
- `res://combat/effects/void_execution_wipe.gdshader` — arc reveal wipe.
- `res://combat/effects/casting_glyph_glow.gdshader` — bold glyph glow with shader-driven thickness.
- `res://combat/effects/crescent_shockwave.gdshader` — directional shockwave band.
- `res://combat/effects/blessing_shaft.gdshader` — vertical light shaft for buff VFX.

### Textures
- `res://assets/art/fx/glow_soft.png` — universal soft circle (glows, body layers, shadows)
- `res://assets/art/fx/screech_rune.png`, `feral_glyph.png`, etc. — sigils
- `res://assets/art/fx/soft_smoke.png` — smoke wisps
- `res://assets/art/fx/fissure_dormant.png`, `fissure_erupt.png` — board-spanning fissure
- `res://assets/art/icons/icon_corruption.png`, `icon_voidmark.png`, `icon_on_death.png`

### Procedural Textures (cache as `static var`)
```gdscript
static var _circle_tex: ImageTexture

func _ensure_textures() -> void:
    if not _circle_tex:
        _circle_tex = _make_soft_circle()
```

### Utility
- `ScreenShakeEffect.shake(target, scene, amplitude, ticks)` — typical: mild (8.0, 8), medium (16.0, 12), heavy (24.0, 14).
- `BaseVfx.shake(target, amplitude, ticks)` — convenience wrapper.

## Techniques Catalog

### Particles
- `CPUParticles2D` for most cases; `GPUParticles2D` only for >100 particles.
- `local_coords = false` for trails (particles stay in world space as emitter moves).
- `local_coords = true` for bursts (particles relative to impact point).
- `one_shot = true` + `explosiveness = 1.0` for bursts.
- Always set `color_ramp` (Gradient) and `scale_amount_curve` (Curve) for fade-out.

### Parallax Particle Layers
Stack 2-3 emitters with different velocities/sizes/opacity for 3D depth. Used by VoidBoltProjectile.

### Sonic Wave Distortion
Reuse `sonic_wave.gdshader` — configure uniforms. Typical: `radius_max` 0.1-0.3, `thickness` 0.04-0.08, `strength` 0.01-0.03.

### Shockwave Ring (Y-squashed perspective)
```gdscript
ring.scale = Vector2(start_scale, start_scale * 0.6)  # Y-squash = perspective
```

### Volumetric Body (staggered depth)
Three glow sprites at slightly different positions/delays — back(dark) / mid / front(bright). Used by VoidBoltImpactVFX.

### Icon Stamp (status effect)
TextureRect drop-in with scale overshoot → hold → fade. Used by CorruptionApplyVFX, VoidMarkApplyVFX.

### Texture + Additive Blend + Clip Reveal (board-spanning)
For AoE effects spreading across the board (fissures, waves):
1. MJ-generated black-bg art, sized for the board (~960px wide)
2. `TextureRect` with `BLEND_MODE_ADD` — black drops out
3. `Control` parent with `clip_contents = true`, tween its width for left-to-right reveal

Used by VoidTouchedImpDeathVFX, GraftedButcherVFX.

## Color Palettes

| Theme | Colors |
|-------|--------|
| Void/Purple | `(0.7, 0.3, 1.0)` to `(0.45, 0.12, 0.65)` |
| Emerald/Corruption | `(0.15, 0.65, 0.08)` to `(0.78, 1.0, 0.70)` |
| Red/Crimson | `(1.0, 0.18, 0.12)` to `(1.0, 0.55, 0.30)` |
| White-hot | `(1.0, 0.9, 1.0)` |
| Shadow/Dark | `(0.1, 0.05, 0.15)` |

## Timing Reference

| Element | Duration |
|---------|----------|
| Projectile flight | 0.4 - 0.9s |
| Spell impact phase | 0.2 - 0.5s |
| Particle lifetime | 0.2 - 0.7s |
| Screen shake interval | 0.025s per tick |
| Icon stamp total | 0.4 - 0.5s |
| Sonic ring expand | 0.2 - 0.35s |
| Buff scale-pulse | 0.12s up + 0.25s down |

## Blending Rules
- **Additive** (`BLEND_MODE_ADD`): glows, flashes, energy, fire, sparks
- **Normal**: opaque sprites, icons, shadows, dark elements
- Never Multiply or Screen

## Reference Implementations

Pick the closest existing VFX as your starting template:

- **Simple impact stamp**: `ArcaneStrikeVFX` — 3 phases (slam → hold → fade), single beat
- **Multi-source geometry-driven impact**: `VoidScreechVFX` — earliest-arrival geometric beat, multi-listener
- **Projectile arc with spinning**: `FrenziedImpHurlVFX` — 4 phases, _process for arc + spin
- **Composite explosion**: `VoidBoltImpactVFX` — single phase with all layers
- **Stack of phases with different beat triggers**: `CorruptionDetonationVFX` — 3 phases, beat at specific t_norm
- **Apply / status icon**: `CorruptionApplyVFX`, `VoidMarkApplyVFX` — 2 phases, no impact gate
- **Buff scale-pulse + chevron**: `BuffApplyVFX` — surge → pulses → motes, BuffSystem.apply at chevron beat
- **Wave with per-target callback**: `AbyssalPlagueVFX` — per_minion_cb scheduled by geometric arrival
- **Board-spanning fissure**: `VoidTouchedImpDeathVFX` — clip-reveal pattern
- **Caster wave with per-imp ignition**: `PackFrenzyVFX` — geometric impact + listeners

## Steps to Create a New VFX

1. Read the user's description. Identify: trigger, position (slot/panel/origin), whether it needs `impact_hit`, the visual feel.
2. Choose the closest reference VFX from above. Copy its phase structure as a starting point.
3. Create the file at `echoofabyss/combat/effects/<EffectName>VFX.gd` extending `BaseVfx`.
4. Wire into the caller:
   - Spell VFX: add `_play_<effect>` method to `VfxController._SPELL_DISPATCH`
   - On-play / passive: add a wrapper on `CombatVFXBridge` or call site
   - Apply VFX (corruption, buff): register in `BuffVfxRegistry` or callsite
5. Test visually. VFX quality bar: shader-based distortion, layered phases, damage synced to impact beat. Reference VoidBoltImpactVFX for spell quality, CorruptionApplyVFX for status.

## GDScript Rules
- **Always use `: Type =` not `:=`** when reading from untyped Array or Dictionary.
- All effects must work for both player and enemy side — no hardcoding "player" or "enemy".

## What NOT to Do
- Don't create .tscn files — code-only.
- Don't use `extends Node` / `extends Node2D` — always `extends BaseVfx`.
- Don't override `_ready()` — override `_play()`.
- Don't hand-roll `await timer / is_inside_tree() / finished.emit / queue_free` — the sequence runner owns this.
- Don't use `GPUParticles2D` unless particle count >100.
- Don't apply gameplay effects (damage, buffs) inside VFX — emit beats, let the caller handle it.
- Don't use `TIME_SCALE` constants multiplied through every tween — use `seq.time_scale` once.
- Don't audio-trigger inside builders — audio at phase start is fine, but downstream sync should use beats.
- Don't use Multiply/Screen blend modes.
