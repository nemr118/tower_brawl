// Floating spirit lights for the "max" tiers: a soft pixel orb that pulses.
shader_type canvas_item;
render_mode blend_add, unshaded;
uniform float phase = 0.0;
void fragment() {
	vec2 q = floor(UV * 16.0) / 16.0 - 0.5;
	float r = length(q) * 2.0;
	float a = pow(clamp(1.0 - r, 0.0, 1.0), 2.0) * (0.7 + 0.3 * sin(TIME * 3.0 + phase));
	a = floor(a * 6.0) / 6.0;
	COLOR = vec4(COLOR.rgb * a, a);
}
