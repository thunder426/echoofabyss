shader_type canvas_item;

// Windup glyph shader:
// - intensity: 0 = base, higher = stronger outward glow (multiplied brightness)
// - tint: faction color, the "dim" color of the glyph
// - white_mix: 0 = pure tint, 1 = pure white (color shift at peak / cast moment)
// - thickness: 0 = normal line width, higher = line appears thicker. Works by
//   sampling neighbour pixels and taking max luminance, then lowering the
//   alpha threshold — so thin white lines visually expand outward.
//
// The source PNG is white line-art on transparent, so `a` defines the shape
// and `rgb` is roughly white where the line is.

uniform float intensity  : hint_range(0.0, 8.0) = 0.0;
uniform vec4  tint       : source_color = vec4(1.0);
uniform float white_mix  : hint_range(0.0, 1.0) = 0.0;
uniform float thickness  : hint_range(0.0, 16.0) = 0.0;
uniform vec2  tex_size   = vec2(512.0, 512.0);

void fragment() {
    vec4 src = texture(TEXTURE, UV);
    float a  = src.a;

    // Thicken lines by sampling 4 neighbours at an offset proportional to
    // `thickness` (in pixels) and taking the max alpha. Cheap 4-tap dilation.
    if (thickness > 0.01) {
        vec2 px = vec2(1.0) / tex_size;
        float r = thickness;
        float a1 = texture(TEXTURE, UV + vec2( r, 0.0) * px).a;
        float a2 = texture(TEXTURE, UV + vec2(-r, 0.0) * px).a;
        float a3 = texture(TEXTURE, UV + vec2(0.0,  r) * px).a;
        float a4 = texture(TEXTURE, UV + vec2(0.0, -r) * px).a;
        a = max(a, max(max(a1, a2), max(a3, a4)));
    }

    // Base color: blend tint → white by white_mix.
    vec3 base_color = mix(tint.rgb, vec3(1.0), white_mix);

    // Luminance of source (used to drive glow strength on lit pixels).
    float lum = max(max(src.r, src.g), src.b);

    vec3 base = base_color * lum;
    // Normalize glow color so the brightest channel is 1.0 — this keeps the
    // perceived hue constant as intensity rises, instead of clamping to white.
    float mx = max(max(base_color.r, base_color.g), base_color.b);
    vec3 glow_color = base_color / max(mx, 0.0001);
    vec3 glow = glow_color * lum * intensity;
    COLOR = vec4(base + glow, a);
}
