shader_type canvas_item;

// Plague cloud boil shader — makes a static cloud texture read as volumetric
// gas that churns, hisses, and warps over time.
//
// Three layered effects combine:
//   1. Scrolling noise modulates alpha       → cloud "boils", parts fade in/out
//   2. UV displacement from a second noise   → silhouette edges drift/wobble
//   3. Optional tint color                   → sickly green via modulate
//
// Per-instance variation: set `seed_offset` so stacked copies of the same
// cloud texture don't sync their noise animation (keeps them looking distinct).

uniform float time_scale : hint_range(0.0, 2.0) = 0.35;
uniform float boil_strength : hint_range(0.0, 1.0) = 0.55;     // how aggressively parts fade in/out
uniform float boil_scale : hint_range(0.5, 8.0) = 3.0;          // frequency of the boil pattern
uniform float warp_strength : hint_range(0.0, 0.1) = 0.025;    // how much silhouette edges drift
uniform float warp_scale : hint_range(0.5, 8.0) = 2.0;
uniform float seed_offset : hint_range(0.0, 100.0) = 0.0;       // per-instance phase offset

// Hash & value-noise (avoids needing a NoiseTexture asset)
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// 2 octaves for a bit of detail without being expensive
float fbm(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.17) * 0.35;
}

void fragment() {
	float t = TIME * time_scale + seed_offset;

	// Warp UV using first noise field — silhouette edges drift
	vec2 warp = vec2(
		fbm(UV * warp_scale + vec2(t, 0.0)) - 0.5,
		fbm(UV * warp_scale + vec2(0.0, t) + vec2(17.3, 41.7)) - 0.5
	) * 2.0 * warp_strength;
	vec2 warped_uv = UV + warp;

	// Sample the cloud texture with warped UV
	vec4 tex = texture(TEXTURE, warped_uv);

	// Second noise field modulates alpha — this is the "boil"
	// Scrolls in a different direction so it's decorrelated from the warp
	float boil = fbm(UV * boil_scale + vec2(-t * 0.7, t * 0.4));
	// Remap so ~40% of the cloud stays solid and ~60% boils
	float boil_mask = mix(1.0, boil * 2.0, boil_strength);
	boil_mask = clamp(boil_mask, 0.0, 1.0);

	// Output: texture color × modulate × boil mask
	vec4 outc = tex * COLOR;
	outc.a *= boil_mask;
	COLOR = outc;
}
