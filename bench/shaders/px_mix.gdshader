// Solid pixel particles (dust, smoke, debris): normal blending, lit by the
// scene's lights, corners snapped to a 3 px grid, alpha in 4 hard steps.
shader_type canvas_item;
render_mode blend_mix, world_vertex_coords;

uniform float grid = 3.0;

void vertex() {
	VERTEX = floor(VERTEX / grid + 0.5) * grid;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.a = floor(c.a * 4.0 + 0.5) / 4.0;
	COLOR = c;
}
