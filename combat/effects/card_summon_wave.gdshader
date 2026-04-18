shader_type canvas_item;

// Rectangular (card-shaped) summon wave distortion.
// - The wave is a hollow rounded-rect band whose inner edge starts at the card
//   outline and expands outward as `progress` advances.
// - Pixels inside the band are displaced outward (away from the card center),
//   creating a glass/heat-haze warp that traces the card's silhouette.
// - No chromatic aberration — pure luminance-preserving warp with a subtle tint.
//
// Usage (set each frame of the wave's life):
//   progress      — 0..1, maps to expansion in UV units
//   expand_max    — max outward expansion from the card edge (UV units)
//   thickness     — width of the warp band (UV units)
//   strength      — max pixel displacement (UV units, e.g. 0.02)
//   tint          — RGBA tint added inside the band (use white/gold, alpha small)
//   rect_center   — card center in screen UV (0..1)
//   rect_half_size— card half-size in screen UV (x,y; aspect-compensated by caller)
//   aspect        — viewport w/h so the band reads as uniform thickness

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 rect_center = vec2(0.5, 0.5);
uniform vec2 rect_half_size = vec2(0.05, 0.08);
uniform float progress : hint_range(0.0, 1.5) = 0.0;
uniform float expand_max : hint_range(0.0, 0.5) = 0.1;
uniform float thickness : hint_range(0.005, 0.2) = 0.04;
uniform float strength : hint_range(0.0, 0.1) = 0.02;
uniform float aspect : hint_range(0.5, 3.0) = 1.777;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.2);
uniform float alpha_multiplier : hint_range(0.0, 1.0) = 1.0;
uniform float corner_radius : hint_range(0.0, 0.2) = 0.02;
// How far inside the card (negative SDF) the band starts. Larger magnitude =
// ripple begins deeper toward the center. Default matches old behavior.
uniform float band_start_inset : hint_range(0.0, 0.5) = 0.0;

void fragment() {
	// Aspect-correct offset from card center so the band reads uniform.
	vec2 to_center = SCREEN_UV - rect_center;
	vec2 p_aspect = vec2(to_center.x * aspect, to_center.y);
	vec2 half_aspect = vec2(rect_half_size.x * aspect, rect_half_size.y);

	// Rounded-rect SDF — shrink the rect by corner_radius, then the true
	// distance to that shrunken rect, minus the radius, gives rounded corners.
	vec2 shrunk = max(half_aspect - vec2(corner_radius), vec2(0.0));
	vec2 d = abs(p_aspect) - shrunk;
	float outside = length(max(d, vec2(0.0)));
	float inside = min(max(d.x, d.y), 0.0);
	float sdf = outside + inside - corner_radius;

	// Current band center — starts one thickness inside the card (hidden by
	// the inside clip) and walks outward. This makes the band *emerge* from
	// the edge instead of starting as a fixed halo some distance away from it.
	float band_start = -max(thickness, band_start_inset);
	float band_center = mix(band_start, expand_max + thickness, progress);

	// Band falloff from its center.
	float band_dist = abs(sdf - band_center);
	float band_falloff = 1.0 - smoothstep(0.0, thickness, band_dist);
	// When band_start_inset is 0 (legacy), keep the card art sharp by clipping
	// displacement inside the card. When the caller explicitly asked the wave
	// to start from inside, allow it to ripple across the card interior too.
	if (sdf < 0.0 && band_start_inset <= 0.0001) {
		band_falloff = 0.0;
	}

	// Outward direction from the card (normal to the nearest edge).
	// For exterior pixels, this is the gradient of the SDF.
	vec2 grad = vec2(0.0);
	if (sdf > 0.0001) {
		vec2 q = max(d, vec2(0.0));
		// Sign puts the push outward on each axis.
		grad = normalize(vec2(q.x * sign(p_aspect.x), q.y * sign(p_aspect.y)) + vec2(0.0001, 0.0));
	} else {
		// Inside the card: push radially outward from the card center so an
		// interior-started ripple has a meaningful displacement direction.
		grad = normalize(p_aspect + vec2(0.0001, 0.0));
	}
	// Undo aspect so the displacement is proper screen-space.
	grad.x /= aspect;

	// Sin-shaped wave so displacement peaks at band center, fades at edges.
	float phase = (sdf - band_center) / thickness;
	float wave_shape = sin(phase * 3.14159) * band_falloff;
	vec2 displaced_uv = SCREEN_UV + grad * wave_shape * strength;

	vec4 warped = texture(screen_tex, displaced_uv);

	// Additive tint inside the band.
	float tint_mask = band_falloff * tint.a * alpha_multiplier;
	warped.rgb = mix(warped.rgb, warped.rgb + tint.rgb, tint_mask);

	// Only contribute where the band is.
	warped.a = alpha_multiplier * band_falloff;
	if (band_falloff < 0.001) {
		warped = texture(screen_tex, SCREEN_UV);
		warped.a = 0.0;
	}
	COLOR = warped;
}
