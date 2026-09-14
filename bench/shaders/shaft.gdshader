// Light shafts from high windows: a soft wedge, breathing slowly, broken into a
// 3 px dither so it is pixel light, not a smooth gradient.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 tint : source_color = vec4(0.95, 0.8, 0.5, 0.16);
uniform float phase = 0.0;

void fragment() {
	float a = tint.a * (1.0 - UV.y) * smoothstep(0.0, 0.35, UV.x) * smoothstep(1.0, 0.65, UV.x);
	a *= 0.8 + 0.2 * sin(TIME * 0.9 + phase + UV.y * 5.0);
	vec2 p = floor(FRAGCOORD.xy / 3.0);
	float d = mod(p.x + p.y * 2.0, 4.0) / 4.0;
	a = a > d * 0.12 ? a : 0.0;
	COLOR = vec4(tint.rgb * a, a);
}
