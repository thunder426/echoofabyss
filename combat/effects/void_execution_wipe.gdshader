shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge_softness : hint_range(0.0, 0.3) = 0.08;
uniform float glow_strength : hint_range(0.0, 3.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Wipe from top-left to bottom-right following diagonal
	float wipe = (UV.x * 0.3 + UV.y * 0.7);
	float reveal = smoothstep(wipe - edge_softness, wipe + edge_softness, progress);
	// Edge glow — bright line at the reveal frontier
	float edge_dist = abs(wipe - progress);
	float edge_glow = exp(-edge_dist * 25.0) * glow_strength;
	vec3 glow_color = vec3(0.7, 0.3, 1.0);
	tex.rgb += glow_color * edge_glow;
	tex.a *= reveal;
	COLOR = tex;
}
