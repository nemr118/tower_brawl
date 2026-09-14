// Glowing pixel particles (fire, sparks, embers, magic): added on top, no
// lighting, and every corner snapped to a 3 px grid so they read as pixel art.
shader_type canvas_item;
render_mode blend_add, unshaded, world_vertex_coords;

uniform float grid = 3.0;

void vertex() {
	VERTEX = floor(VERTEX / grid + 0.5) * grid;
}
