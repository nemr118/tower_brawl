// The purple walls (TowerFall's miasma, our own look): boiling pixel noise, dark
// purple at the arena's edge, brighter towards a ragged, glowing inner edge.
// side 0 is the left wall (its inner edge on the right), 1 the right wall.
// Before they kill (deadly 0) they are see-through and the edge pulses.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise : repeat_enable, filter_nearest;
uniform float deadly = 1.0;
uniform float side = 0.0;
uniform vec2 size_px = vec2(100.0, 1080.0);

void fragment() {
	vec2 px = floor(UV * size_px / 6.0) * 6.0;
	float in_px = side < 0.5 ? size_px.x - px.x : px.x;
	float wob = texture(noise, vec2(0.31, px.y / 700.0 + TIME * 0.07)).r * 46.0;
	float edge = in_px - wob;
	if (edge < 0.0) {
		discard;
	}
	float n = texture(noise, px / vec2(380.0, 260.0) + vec2(TIME * 0.02, TIME * 0.05)).r;
	float n2 = texture(noise, px / vec2(170.0, 120.0) - vec2(TIME * 0.04, 0.0)).r;
	float rim = 1.0 - smoothstep(0.0, 18.0, edge);
	float pulse = 0.5 + 0.5 * sin(TIME * 12.0);
	vec3 col = mix(vec3(0.14, 0.02, 0.22), vec3(0.62, 0.22, 0.92), clamp(n * n2 * 1.6, 0.0, 1.0));
	col = mix(col, vec3(0.98, 0.62, 1.0), rim * mix(0.5 + 0.5 * pulse, 0.85, deadly));
	float a = mix(0.42, 0.88, deadly) * (0.7 + 0.3 * n) + rim * 0.25;
	COLOR = vec4(col, clamp(floor(a * 6.0) / 6.0, 0.0, 1.0));
}
