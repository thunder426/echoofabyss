shader_type canvas_item;

// Fullscreen radial sonic wave distortion.
// - A ring expands outward from `center_uv` (screen-space 0..1 coords).
// - Pixels near the ring are displaced radially, creating a glass/heat-haze warp.
// - The ring is subtly tinted with `tint` for an almost-transparent red shimmer.
//
// Usage: set all uniforms each frame during the wave's life.
//   progress  — 0..1 (how far the wave has expanded; multiplied by radius_max)
//   thickness — how wide the warped ring band is in UV units
//   strength  — max pixel displacement in UV space (keep small, e.g. 0.02)
//   tint      — RGBA applied additively inside the ring band

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 center_uv = vec2(0.5, 0.5);
uniform float progress : hint_range(0.0, 1.5) = 0.0;
uniform float radius_max : hint_range(0.1, 2.0) = 1.0;
uniform float thickness : hint_range(0.02, 0.5) = 0.12;
uniform float strength : hint_range(0.0, 0.1) = 0.02;
uniform float aspect : hint_range(0.5, 3.0) = 1.777; // viewport aspect (w/h) to keep ring circular
uniform vec4 tint : source_color = vec4(1.0, 0.25, 0.18, 0.35);
uniform float alpha_multiplier : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Aspect-correct radial distance from center (UV is 0..1, but screen is wider)
	vec2 to_center = SCREEN_UV - center_uv;
	to_center.x *= aspect;
	float dist = length(to_center);
	vec2 dir = dist > 0.0001 ? to_center / dist : vec2(0.0);
	// Undo aspect on direction to get a proper screen-space offset
	dir.x /= aspect;

	// Current wave radius
	float r = progress * radius_max;

	// How close this pixel is to the wave ring (0 = on ring, 1 = at band edge)
	float ring_dist = abs(dist - r);
	float ring_falloff = 1.0 - smoothstep(0.0, thickness, ring_dist);

	// Displacement: radial offset, peaks at the ring center, zero at edges
	// Use sin() shape so displacement looks like a wave passing through
	float wave_phase = (dist - r) / thickness;
	float wave_shape = sin(wave_phase * 3.14159) * ring_falloff;
	vec2 displaced_uv = SCREEN_UV + dir * wave_shape * strength;

	vec4 warped = texture(screen_tex, displaced_uv);

	// Add a faint red tint inside the ring band for visibility
	float tint_mask = ring_falloff * tint.a * alpha_multiplier;
	warped.rgb = mix(warped.rgb, warped.rgb + tint.rgb, tint_mask);

	// Chromatic aberration touch — red channel offset slightly more than blue
	// for a more "broken vision" feel inside the ring
	if (ring_falloff > 0.1) {
		vec2 ca_offset = dir * wave_shape * strength * 0.5;
		float r_channel = texture(screen_tex, displaced_uv + ca_offset).r;
		float b_channel = texture(screen_tex, displaced_uv - ca_offset).b;
		warped.r = mix(warped.r, r_channel, ring_falloff * 0.6);
		warped.b = mix(warped.b, b_channel, ring_falloff * 0.6);
	}

	// Only contribute where the ring is — outside the band, be fully transparent
	// so multiple stacked wave nodes don't each redraw the whole screen.
	// Without this, stacking N shaders makes only the topmost one's ring visible.
	warped.a = alpha_multiplier * ring_falloff;
	// Outside the ring, blend back to the unwarped screen color so we don't
	// visibly "punch a hole" — use the original screen sample, not warped.
	if (ring_falloff < 0.001) {
		warped = texture(screen_tex, SCREEN_UV);
		warped.a = 0.0;
	}
	COLOR = warped;
}
