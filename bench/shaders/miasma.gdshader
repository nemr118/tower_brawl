// A miasma cloud left by a miasma arrow: pixelated boiling noise in a circle,
// dark purple to bright violet, fading out with the cloud's life.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise : repeat_enable, filter_nearest;
uniform float life = 1.0;
uniform float seed = 0.0;

void fragment() {
	vec2 q = floor(UV * 40.0) / 40.0;
	float r = length(q - 0.5) * 2.0;
	float n = texture(noise, q * 1.3 + vec2(seed, TIME * 0.06)).r;
	float n2 = texture(noise, q * 2.7 - vec2(TIME * 0.1, seed)).r;
	float a = smoothstep(1.0, 0.3, r + (n - 0.5) * 0.6) * (0.5 + 0.5 * n2) * clamp(life * 3.0, 0.0, 1.0);
	a = floor(a * 5.0) / 5.0;
	vec3 col = mix(vec3(0.16, 0.03, 0.26), vec3(0.72, 0.3, 1.0), n2 * n2);
	COLOR = vec4(col, a * 0.8);
}
