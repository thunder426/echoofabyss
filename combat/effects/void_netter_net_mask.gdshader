shader_type canvas_item;

uniform vec4 tint_color : source_color = vec4(0.95, 0.82, 1.0, 1.0);
uniform float alpha_boost : hint_range(0.0, 4.0) = 1.5;
uniform float cutoff_low : hint_range(0.0, 1.0) = 0.08;
uniform float cutoff_high : hint_range(0.0, 1.0) = 0.28;
uniform float glow_strength : hint_range(0.0, 3.0) = 0.55;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float brightness = max(max(tex.r, tex.g), tex.b);
	float mask = smoothstep(cutoff_low, cutoff_high, brightness);
	vec3 glow = tex.rgb * (1.0 + glow_strength);
	COLOR.rgb = glow * tint_color.rgb;
	COLOR.a = mask * tint_color.a * alpha_boost;
}
