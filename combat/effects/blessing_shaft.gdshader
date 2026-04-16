// blessing_shaft.gdshader
// Vertical "beam of light" column with upward-scrolling noise wisps,
// feathered top and bottom, warm-gold core and green edges.
// Designed for a ColorRect sized to the slot; renders the full rect.
//
// Progress (0 → 1) controls the phase of the sweep:
//   0.0  — column hidden (below threshold)
//   0.5  — column fully formed, wisps flowing
//   1.0  — column fading out from the bottom, trailing motes at top
//
// No texture dependencies — uses analytic value noise.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset : hint_range(0.0, 10.0) = 0.0;
uniform vec4  tint_core : source_color = vec4(1.0, 0.92, 0.55, 1.0);   // warm gold core
uniform vec4  tint_edge : source_color = vec4(0.55, 1.0, 0.65, 1.0);   // green edge glow
uniform float intensity : hint_range(0.0, 3.0) = 1.6;
uniform float column_width : hint_range(0.1, 1.0) = 0.55;              // width of the shaft (UV)
uniform float wisp_speed : hint_range(0.5, 6.0) = 2.2;
uniform float wisp_scale : hint_range(1.0, 20.0) = 6.0;

// Hash-based value noise — cheap, no texture needed.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Two-octave fbm for soft wispy texture.
float fbm(vec2 p) {
	return 0.6 * vnoise(p) + 0.4 * vnoise(p * 2.3);
}

void fragment() {
	vec2 uv = UV;  // 0..1 across the rect
	float t = TIME + time_offset;

	// ── Column mask: bell curve around x=0.5, width controlled by column_width.
	float dx = abs(uv.x - 0.5) / (column_width * 0.5);
	float col = 1.0 - smoothstep(0.6, 1.0, dx);   // inside shaft
	col *= 1.0 - smoothstep(0.0, 0.6, dx) * 0.35; // soft outside falloff
	if (col <= 0.001) discard;

	// ── Vertical feather: fade top and bottom.
	float feather_top = smoothstep(0.0, 0.18, uv.y);
	float feather_bot = smoothstep(0.0, 0.20, 1.0 - uv.y);
	float feather = feather_top * feather_bot;

	// ── Upward-scrolling wisps (y decreases over time so the texture moves up).
	vec2 wisp_uv = vec2(uv.x * wisp_scale * 0.6, uv.y * wisp_scale - t * wisp_speed);
	float wisps = fbm(wisp_uv);
	// Remap noise around 0.5 so the shaft isn't uniformly dark.
	wisps = 0.45 + wisps * 0.65;

	// ── Core-to-edge tint based on horizontal distance from centerline.
	float edge_mix = smoothstep(0.0, 1.0, dx);
	vec3 color = mix(tint_core.rgb, tint_edge.rgb, edge_mix);

	// ── Time-dependent progress envelope — shaft brightens, then fades.
	// Peak around progress=0.5, falling off toward 0 and 1.
	float env = smoothstep(0.0, 0.35, progress) * smoothstep(1.0, 0.55, progress);

	float alpha = col * feather * wisps * env * intensity;
	COLOR = vec4(color * alpha, alpha);
}
