// The light shafts with dust in them, the polish of 2026-10-25 (switch "shaft_motes" in
// client/polish.gd; NORMAL and HIGH only, as the shafts). The old shader (shaft.gdshader)
// never showed: it read UV, and a Polygon2D with no texture sends no UV (all 0), so its
// wedge was 0 everywhere. This one measures the wedge from the world position instead:
// world.gd draws three shafts at x = 420 + 540 i (phase = 2.1 i), each one 80 px wide at
// y = 60 and 300 px wide at y = 900 (leaning right). Then: the same soft wedge broken into
// a 3 px dither, and specks of dust that drift down slowly and twinkle where the light falls.
// (The old one also gave out its colour times its alpha, and blend_add multiplies by the alpha
// again: 0.16 x 0.16, too faint to see. Here the alpha is 1 and the colour is the light added.)
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 tint : source_color = vec4(0.95, 0.8, 0.5, 0.14);
uniform float phase = 0.0;

varying vec2 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world = VERTEX;
}

void fragment() {
	float cx = 420.0 + 540.0 * floor(phase / 2.1 + 0.5);
	float v = clamp((world.y - 60.0) / 840.0, 0.0, 1.0);
	float xl = cx - 40.0 - 70.0 * v;
	float xr = cx + 40.0 + 150.0 * v;
	float u = clamp((world.x - xl) / max(xr - xl, 1.0), 0.0, 1.0);
	// (1 - smoothstep(0.65, 1, u): a smoothstep with its edges reversed is undefined in GLSL)
	float wedge = (1.0 - v) * smoothstep(0.0, 0.35, u) * (1.0 - smoothstep(0.65, 1.0, u));
	float a = tint.a * wedge * (0.8 + 0.2 * sin(TIME * 0.9 + phase + v * 5.0));
	vec2 p = floor(FRAGCOORD.xy / 3.0);
	float d = mod(p.x + p.y * 2.0, 4.0) / 4.0;
	a = a > d * 0.12 ? a : 0.0;
	// the dust: a 3 px speck in some cells of a grid that drifts down and sways
	vec2 q = world / 3.0 + vec2(sin(TIME * 0.3 + phase) * 4.0, -TIME * 3.0);
	vec2 cell = floor(q / 6.0);
	float h = hash(cell + vec2(phase * 13.0, 0.0));
	vec2 inner = mod(q, 6.0);
	float m = (h > 0.86 && inner.x < 1.0 && inner.y < 1.0) ? 1.0 : 0.0;
	m *= (0.5 + 0.5 * sin(TIME * 2.0 + h * 40.0)) * wedge * 0.35;
	COLOR = vec4(tint.rgb * a + vec3(1.0, 0.92, 0.75) * m, 1.0);
}
