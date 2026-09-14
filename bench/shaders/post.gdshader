// The whole picture (tiers T3+). A colour grade and a vignette always; with the
// "max" switches: shock ripples that bend the picture around blasts, heat
// shimmer above fires, a bloom of the bright parts, and the lightning flash.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform vec2 size = vec2(1920.0, 1080.0);
uniform float vignette = 0.45;
uniform float aberration = 0.0;
uniform float saturation = 1.18;
uniform vec3 lift = vec3(0.012, 0.004, 0.03);
uniform float bloom = 0.0;
uniform float flash = 0.0;
uniform int n_shock = 0;
uniform vec4 shock[8];      // xy centre (px), z radius, w strength
uniform int n_heat = 0;
uniform vec4 heat[16];      // xy base (px), z width, w strength

vec3 grab(vec2 uv) {
	return texture(screen, uv).rgb;
}

void fragment() {
	vec2 px = SCREEN_UV * size;
	vec2 off = vec2(0.0);
	for (int i = 0; i < n_shock; i++) {
		vec2 d = px - shock[i].xy;
		float len = length(d);
		float k = clamp(1.0 - abs(len - shock[i].z) / 36.0, 0.0, 1.0);
		off += d / max(len, 1.0) * k * k * 14.0 * shock[i].w;
	}
	for (int i = 0; i < n_heat; i++) {
		vec2 d = px - heat[i].xy;
		float k = clamp(1.0 - abs(d.x) / (heat[i].z * 0.5), 0.0, 1.0) * clamp(1.0 + d.y / 160.0, 0.0, 1.0) * step(d.y, 0.0);
		off.x += sin(px.y * 0.11 + TIME * 9.0 + px.x * 0.02) * 3.0 * k * heat[i].w;
	}
	vec2 uv = SCREEN_UV + off / size;
	vec2 split = (uv - 0.5) * aberration * 0.012;
	vec3 c = vec3(texture(screen, uv + split).r, texture(screen, uv).g, texture(screen, uv - split).b);
	if (bloom > 0.0) {
		vec3 b = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			vec2 o = vec2(cos(a), sin(a));
			b += max(grab(uv + o * 4.0 / size) - 0.62, 0.0);
			b += max(grab(uv + o * 10.0 / size) - 0.62, 0.0) * 0.7;
		}
		c += b * 0.14 * bloom;
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) + lift * (1.0 - l);
	c += vec3(0.55, 0.65, 1.0) * flash * 0.35;
	float d = distance(SCREEN_UV, vec2(0.5));
	c *= 1.0 - vignette * smoothstep(0.38, 0.9, d);
	COLOR = vec4(c, 1.0);
}
