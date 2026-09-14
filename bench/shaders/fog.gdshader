// Drifting fog bands: two layers of noise, cut into chunky pixels and a few
// alpha steps, so the mist has Dead Cells' "density in the air" but stays pixel.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform sampler2D noise : repeat_enable, filter_nearest;
uniform vec4 tint : source_color = vec4(0.35, 0.55, 0.75, 0.22);
uniform float speed = 0.015;
uniform vec2 cells = vec2(320.0, 40.0);

void fragment() {
	vec2 q = floor(UV * cells) / cells;
	float n = texture(noise, q * vec2(2.0, 0.6) + vec2(TIME * speed, 0.0)).r;
	n *= texture(noise, q * vec2(1.1, 0.9) - vec2(TIME * speed * 0.7, 0.3)).r * 1.8;
	float a = tint.a * n * sin(UV.y * 3.14159);
	a = floor(a * 12.0) / 12.0;
	COLOR = vec4(tint.rgb * a, a);
}
