shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D flow_tex   : repeat_enable, filter_linear;

// Slot center in SCREEN_UV coords (0..1 across whole viewport).
uniform vec2  center_uv = vec2(0.5, 0.5);
// Aspect correction so the radial mask reads as a circle on screen.
// Pass (1.0, viewport_height / viewport_width) — x stays 1, y scales.
uniform vec2  aspect_correct = vec2(1.0, 1.0);

uniform float radius         : hint_range(0.0, 0.5)  = 0.08;
uniform float edge_softness  : hint_range(0.001, 0.1) = 0.025;
uniform float progress       : hint_range(0.0, 1.0) = 0.0;

// 0 = filled bloom; 1 = annular ring (impact)
uniform float ring_mode = 0.0;
uniform float ring_width : hint_range(0.001, 0.05) = 0.010;

uniform vec4  tint     : source_color = vec4(0.08, 0.42, 0.14, 0.85);
uniform vec4  rim_tint : source_color = vec4(0.20, 0.05, 0.30, 0.6);
uniform float distortion_strength : hint_range(0.0, 0.08) = 0.018;
uniform float ca_amount           : hint_range(0.0, 1.0)  = 0.35;
uniform float alpha_multiplier    : hint_range(0.0, 1.0)  = 1.0;
uniform float time_offset = 0.0;
uniform float flow_scroll_speed : hint_range(0.0, 2.0) = 0.35;
uniform float flow_scale        : hint_range(0.5, 6.0) = 3.0;

void fragment() {
	float t = TIME + time_offset;
	vec4 out_color = vec4(0.0);

	// Radial distance in aspect-corrected space so circle is round on screen.
	vec2 delta = (SCREEN_UV - center_uv) * aspect_correct;
	float dist = length(delta);

	if (ring_mode > 0.5) {
		// ── Ring mode: soft annulus centered on `radius` ───────────────────
		float edge = ring_width;
		float outer = radius + edge;
		float inner = radius - edge;
		float ring_a = smoothstep(outer, radius, dist) * smoothstep(inner, radius, dist);
		float sharp = exp(-pow((dist - radius) / max(edge * 0.35, 0.0001), 2.0));
		ring_a = max(ring_a, sharp * 0.85);
		vec3 rgb = mix(tint.rgb, rim_tint.rgb, 0.25);
		rgb += tint.rgb * 0.7 * sharp;
		out_color = vec4(rgb, ring_a * tint.a * alpha_multiplier);
	} else {
		// ── Bloom mode ─────────────────────────────────────────────────────
		vec2 flow_uv = SCREEN_UV * flow_scale + vec2(t * 0.05, t * flow_scroll_speed);
		float flow = texture(flow_tex, flow_uv).r;
		float perturb = (flow - 0.5) * 0.035 * (0.6 + 0.4 * progress);
		float noisy_dist = dist - perturb;

		float mask = 1.0 - smoothstep(radius - edge_softness, radius, noisy_dist);

		if (mask > 0.001) {
			float bell = clamp(progress * (1.0 - progress) * 4.0, 0.0, 1.0);
			vec2 dir = (dist > 1e-5) ? normalize(delta / aspect_correct) : vec2(0.0);
			float d_amt = distortion_strength * bell * mask;
			vec2 warp = dir * d_amt * ((flow - 0.5) * 2.0);
			vec2 warped_uv = SCREEN_UV + warp;

			vec3 sampled;
			sampled.r = texture(screen_tex, warped_uv + dir * d_amt * ca_amount).r;
			sampled.g = texture(screen_tex, warped_uv).g;
			sampled.b = texture(screen_tex, warped_uv - dir * d_amt * ca_amount).b;

			float r_norm = clamp(dist / max(radius, 0.001), 0.0, 1.0);
			vec3 corruption_col = mix(tint.rgb * 0.35, tint.rgb, r_norm);
			float rim = smoothstep(radius - edge_softness * 2.0, radius, dist);
			corruption_col = mix(corruption_col, rim_tint.rgb, rim * 0.55);

			vec3 final_rgb = sampled * 0.50 + corruption_col;
			float a = mask * tint.a * alpha_multiplier;
			out_color = vec4(final_rgb, a);
		}
	}

	COLOR = out_color;
}
