shader_type canvas_item;

// Crescent shockwave distortion.
// Two horizontal bands (above and below a sweep line) get pushed vertically
// outward from the line — up for pixels above, down for pixels below.
// The bands have a finite horizontal reach around `head_x`, so distortion
// only emits near the crescent's leading edge, not across the whole strip.
//
// Usage (update per frame):
//   head_uv          — (u, v) of the current wave leading edge in UV space
//   head_reach       — horizontal half-width of the emission zone (UV units)
//   band_thickness   — vertical half-height of each band (UV units)
//   strength         — max pixel displacement in UV space
//   tint             — additive tint inside the bands
//   alpha_multiplier — fade the whole effect in/out

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 head_uv = vec2(0.5, 0.5);
uniform float head_reach : hint_range(0.02, 1.0) = 0.25;
uniform float band_thickness : hint_range(0.02, 0.5) = 0.18;
uniform float strength : hint_range(0.0, 0.1) = 0.02;
uniform float aspect : hint_range(0.5, 3.0) = 1.777;
uniform vec4 tint : source_color = vec4(1.0, 0.25, 0.25, 0.30);
uniform float alpha_multiplier : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Horizontal falloff — distortion only within `head_reach` of the head.
	// Aspect-correct so the emission zone is shaped sensibly on wide screens.
	float dx = (SCREEN_UV.x - head_uv.x) * aspect;
	float horiz_falloff = 1.0 - smoothstep(0.0, head_reach * aspect, abs(dx));

	// Vertical distance from the sweep line, plus which side we're on.
	float dy = SCREEN_UV.y - head_uv.y;
	float side = sign(dy);   // +1 below (y grows down in UV), -1 above
	float abs_dy = abs(dy);

	// Band profile: zero at the line, peaks mid-band, zero at outer edge.
	// sin(pi * t) where t = abs_dy / band_thickness in [0, 1].
	float t = clamp(abs_dy / band_thickness, 0.0, 1.0);
	float band = sin(t * 3.14159);
	float band_mask = band * horiz_falloff;

	// Displacement: push pixels outward vertically (up above the line, down below).
	vec2 displaced_uv = SCREEN_UV + vec2(0.0, side * band * strength) * horiz_falloff;
	vec4 warped = texture(screen_tex, displaced_uv);

	// Additive crimson shimmer inside the bands.
	float tint_mask = band_mask * tint.a * alpha_multiplier;
	warped.rgb = mix(warped.rgb, warped.rgb + tint.rgb, tint_mask);

	// Subtle chromatic aberration for "broken air" feel inside the bands.
	if (band_mask > 0.1) {
		vec2 ca_offset = vec2(0.0, side * band * strength * 0.4);
		float r_channel = texture(screen_tex, displaced_uv + ca_offset).r;
		float b_channel = texture(screen_tex, displaced_uv - ca_offset).b;
		warped.r = mix(warped.r, r_channel, band_mask * 0.5);
		warped.b = mix(warped.b, b_channel, band_mask * 0.5);
	}

	// Outside the bands contribute nothing so stacked effects don't redraw
	// the whole screen opaque.
	warped.a = alpha_multiplier * band_mask;
	if (band_mask < 0.001) {
		warped = texture(screen_tex, SCREEN_UV);
		warped.a = 0.0;
	}
	COLOR = warped;
}
