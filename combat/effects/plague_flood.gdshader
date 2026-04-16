shader_type canvas_item;

uniform sampler2D screen_tex  : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D flow_tex    : repeat_enable, filter_linear;
uniform sampler2D density_tex : repeat_disable, filter_linear_mipmap;

uniform float origin_y    : hint_range(-0.1, 1.1)  = 1.0;
uniform float direction_y : hint_range(-1.0, 1.0)  = -1.0;
uniform float progress    : hint_range(0.0, 1.5)   = 0.0;
uniform float reach       : hint_range(0.1, 2.0)   = 1.0;
uniform float thickness   : hint_range(0.05, 2.0)  = 0.30;
uniform float trail_length : hint_range(0.1, 2.5)  = 1.5;
uniform float band_x_min  : hint_range(0.0, 1.0)   = 0.15;
uniform float band_x_max  : hint_range(0.0, 1.0)   = 0.85;
uniform float strength       : hint_range(0.0, 0.20)   = 0.02;
uniform float front_strength : hint_range(0.0, 3.0)    = 1.0;
uniform float body_strength  : hint_range(0.0, 1.0)    = 0.3;
uniform float ca_amount      : hint_range(0.0, 1.0)    = 0.4;
uniform float front_width    : hint_range(0.005, 0.15) = 0.045;
uniform vec4  tint : source_color = vec4(0.10, 0.70, 0.20, 0.50);
uniform float alpha_multiplier : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform float flow_scale        : hint_range(0.2, 5.0) = 1.2;
uniform float flow_scroll_speed : hint_range(0.0, 2.0) = 0.35;
uniform float density_scroll_speed : hint_range(0.0, 2.0) = 0.10;

// ── New uniforms ──────────────────────────────────────────────────────────
uniform float crest_wobble_amp  : hint_range(0.0, 0.08)  = 0.025;  // UV-y amplitude of crest undulation
uniform float crest_wobble_freq : hint_range(1.0, 20.0)  = 7.0;    // spatial frequency along X
uniform float foam_threshold    : hint_range(0.3, 0.9)   = 0.60;
uniform float foam_intensity    : hint_range(0.0, 3.0)   = 1.5;
uniform float tendril_reach     : hint_range(0.0, 0.20)  = 0.07;   // UV range tendrils extend past front
uniform vec4  foam_color : source_color = vec4(0.75, 1.0, 0.65, 1.0);

// ── Edge foam line + halo + spray droplets ────────────────────────────────
uniform float edge_foam_width     : hint_range(0.002, 0.05) = 0.010;
uniform float edge_foam_intensity : hint_range(0.0, 4.0)    = 2.2;
uniform float edge_glow_reach     : hint_range(0.002, 0.05) = 0.014;
uniform float edge_glow_intensity : hint_range(0.0, 2.0)    = 0.9;
uniform float spray_reach         : hint_range(0.002, 0.08) = 0.025;
uniform float spray_density       : hint_range(0.90, 0.999) = 0.988;
uniform float spray_intensity     : hint_range(0.0, 3.0)    = 1.6;

// ── Hash helper for fine-grained foam sparkle ─────────────────────────────
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	float t = TIME + time_offset;

	// ── Band membership ───────────────────────────────────────────────────
	float band_center = (band_x_min + band_x_max) * 0.5;
	float band_half   = (band_x_max - band_x_min) * 0.5;
	float raw_lateral = (SCREEN_UV.x - band_center) / max(band_half, 0.001);

	// ── Uneven crest — wide natural lobes, no high-freq noise ────────────
	// Triangle wave with light smoothstep preserves the natural curve shape
	// the user likes. No wisps / no small overlay noise — only wide lobes.
	// Summed sines, rectified to [0,1] so the front only bulges *forward*,
	// never retreats. Prevents the "wave curving back" look.
	float tide_x = SCREEN_UV.x + t * 0.04;
	float curve_a = sin(tide_x * 6.2832 * 1.8) * 0.5 + 0.5;
	float curve_b = sin(tide_x * 6.2832 * 0.9 + 1.37) * 0.5 + 0.5;
	float crest_raw = curve_a * 0.65 + curve_b * 0.35;

	// Rhythmic pulse — whole wave swells and settles together
	float wave_pulse = 0.85 + 0.15 * sin(t * 0.5);
	float wave_offset = crest_raw * 1.3 * crest_wobble_amp * wave_pulse;

	float front_y_base = origin_y + direction_y * progress * reach;
	float front_y = front_y_base + direction_y * wave_offset;
	float traveled = (front_y - SCREEN_UV.y) * direction_y;

	// in_band: 1 inside lateral band, 0 outside (with slight lateral softness)
	float in_band = 1.0 - smoothstep(0.95, 1.05, abs(raw_lateral));
	// Soft front edge — the deformed front_y is the *only* edge, no ahead-extension
	float ahead_ramp = smoothstep(-0.010, 0.002, traveled);
	float body_ramp = ahead_ramp;
	// trail_ramp: fade at tail
	float trail_ramp = 1.0 - smoothstep(trail_length - thickness, trail_length, traveled);

	float body_intensity = in_band * body_ramp * trail_ramp;
	float wave = body_intensity;

	// ── Depth gradient — brighter/denser at crest, fading into tail ───────
	// 0 at tail, 1 at crest
	float depth_t = clamp(1.0 - traveled / max(trail_length, 0.001), 0.0, 1.0);
	float crest_ramp = pow(depth_t, 1.4);

	// ── Flow texture for displacement ripple ──────────────────────────────
	vec2 flow_uv = vec2(SCREEN_UV.x * flow_scale + time_offset * 0.011,
	                    SCREEN_UV.y * flow_scale + direction_y * flow_scroll_speed * t);
	float flow_lum = dot(texture(flow_tex, flow_uv).rgb, vec3(0.21, 0.71, 0.08));

	// ── Displacement — stronger at crest, lifts battlefield as wave rolls ─
	float front_push = exp(-pow(traveled / max(front_width, 0.001), 2.0));
	float disp_y = (front_push * front_strength + (flow_lum - 0.5) * body_strength * body_intensity) * strength * in_band;
	float disp_x = (flow_lum - 0.5) * body_strength * strength * 0.4 * in_band;
	vec2 disp_uv = clamp(SCREEN_UV + vec2(disp_x, direction_y * disp_y), vec2(0.001), vec2(0.999));

	// ── Sample distorted screen ───────────────────────────────────────────
	vec4 warped = texture(screen_tex, disp_uv);

	// ── Chromatic aberration at front edge ────────────────────────────────
	float ca_shift = ca_amount * strength * front_push * in_band;
	float r_ch = texture(screen_tex, clamp(disp_uv + vec2(0.0,  direction_y * ca_shift), vec2(0.001), vec2(0.999))).r;
	float b_ch = texture(screen_tex, clamp(disp_uv + vec2(0.0, -direction_y * ca_shift), vec2(0.001), vec2(0.999))).b;
	warped.r = mix(warped.r, r_ch, front_push * ca_amount * 0.5 * in_band);
	warped.b = mix(warped.b, b_ch, front_push * ca_amount * 0.5 * in_band);

	// ── Flow surface — heavily blurred via LOD to kill fine-detail sparkle ─
	// textureLod at LOD 2.5 gives ~6× blur — no small shiny spots survive.
	vec2 flow_uv2 = vec2(SCREEN_UV.x * flow_scale * 1.3 + time_offset * 0.017 + 0.5,
	                     SCREEN_UV.y * flow_scale * 1.3 + direction_y * flow_scroll_speed * t * 0.8 + 0.3);
	vec3 flow_color = textureLod(flow_tex, flow_uv, 2.5).rgb * 0.7
	                 + textureLod(flow_tex, flow_uv2, 2.5).rgb * 0.3;

	// Tint intensifies toward crest — darker at trail (no caustic highlights)
	vec3 trail_tint = tint.rgb * 0.45;
	vec3 crest_tint = tint.rgb * 2.6;
	vec3 depth_tint = mix(trail_tint, crest_tint, crest_ramp);
	vec3 fluid_surface = flow_color * depth_tint;

	// Blend fluid on top of warped screen — more opaque toward crest
	float fluid_blend = body_intensity * (1.0 - front_push * 0.5) * tint.a * mix(0.35, 0.85, crest_ramp);
	warped.rgb = mix(warped.rgb, fluid_surface, clamp(fluid_blend, 0.0, 0.9));

	// ── Patch mask — large soft lobes only, no small blinky patches ──────
	// Low sample frequency (~1 cycle across screen) and very wide smoothstep
	// thresholds mean patches are big, soft-edged, and fade slowly.
	vec2 patch_uv = vec2(SCREEN_UV.x * 0.9 + t * 0.025, t * 0.015 + 0.2);
	float patch_n = texture(flow_tex, patch_uv).r;
	float patch_mask = smoothstep(0.30, 0.80, patch_n);
	vec2 patch_uv2 = vec2(SCREEN_UV.x * 0.6 - t * 0.020, t * 0.010 + 0.73);
	float patch_n2 = texture(flow_tex, patch_uv2).g;
	patch_mask *= smoothstep(0.20, 0.70, patch_n2);

	// ── Broken pale-green crest glow — only in patches, not a line ────────
	float edge_band = exp(-pow(traveled / max(edge_foam_width, 0.001), 2.0));
	vec3 crest_glow_color = tint.rgb * 1.9 + vec3(0.12, 0.22, 0.10);
	float crest_glow = edge_band * in_band * edge_foam_intensity;
	warped.rgb += crest_glow_color * crest_glow;

	// ── Outward halo — uniform rim (no patch gating) ──────────────────────
	float air_distance = max(-traveled, 0.0);
	float halo = exp(-pow(air_distance / max(edge_glow_reach, 0.001), 2.0));
	halo *= edge_glow_intensity * in_band * step(0.0, -traveled);
	warped.rgb += crest_glow_color * halo * 0.7;

	// ── Dark under-crest band — wave rolls forward, not sits flat ─────────
	// Darken a narrow strip just inside the body edge (traveled just > 0).
	float dark_t = smoothstep(0.0, 0.004, traveled) * (1.0 - smoothstep(0.006, 0.028, traveled));
	dark_t *= in_band * 0.45;
	warped.rgb = mix(warped.rgb, warped.rgb * 0.50, dark_t);

	// ── Alpha — body + patch-gated edge contributions ────────────────────
	float air_contribution = halo * 0.65;
	float final_wave = max(wave, air_contribution);
	warped.a = clamp(final_wave * alpha_multiplier, 0.0, 1.0);

	COLOR = warped;
}
