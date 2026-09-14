// Dynamic fog over the whole arena (tiers T2+). Two layers of noise drift with
// the wind; everything that moves stirs it: fighters and arrows push it along
// their path and swirl it, blasts punch an expanding hole. Smoke clouds thicken
// it. Every light (torches, fires, blasts, glowing arrows) lights the fog around
// it, so light hangs in the air. The result is cut into pixel cells and a few
// density steps, so it stays pixel art.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise : repeat_enable, filter_linear;
uniform vec2 world_size = vec2(1920.0, 1080.0);
uniform float pixel = 6.0;
uniform float density = 0.55;
uniform float ground = 0.5;        // extra density low in the room
uniform float scale = 1.0;
uniform vec2 wind = vec2(0.012, 0.002);
uniform vec4 tint : source_color = vec4(0.42, 0.52, 0.68, 0.7);
uniform float ambient = 0.35;
uniform float flash = 0.0;         // lightning
uniform int n_dist = 0;
uniform vec4 dist[32];             // xy position, z radius, w strength
uniform vec4 dist_vel[32];         // xy velocity (px per tick)
uniform int n_lights = 0;
uniform vec4 lights[32];           // xy position, z radius, w energy
uniform vec4 light_col[32];
uniform int n_smoke = 0;
uniform vec4 smoke[16];            // xy position, z radius, w amount (0..1)

void fragment() {
	vec2 wp = (floor(UV * world_size / pixel) + 0.5) * pixel;
	vec2 disp = vec2(0.0);
	float clear = 0.0;
	for (int i = 0; i < n_dist; i++) {
		vec2 d = wp - dist[i].xy;
		float len = length(d);
		float f = clamp(1.0 - len / dist[i].z, 0.0, 1.0);
		f *= f;
		disp += (dist_vel[i].xy * 3.0 + vec2(-d.y, d.x) / max(len, 1.0) * 40.0 * dist[i].w) * f;
		clear = max(clear, f * dist[i].w);
	}
	vec2 p = (wp + disp) * scale / 700.0;
	float t = TIME;
	float n = texture(noise, p + wind * t).r * 0.62 + texture(noise, p * 2.1 - wind * t * 1.8).r * 0.38;
	float low = smoothstep(420.0, 1080.0, wp.y);
	float dens = smoothstep(0.38, 0.82, n) * (density + ground * low);
	for (int i = 0; i < n_smoke; i++) {
		float f = clamp(1.0 - length(wp - smoke[i].xy) / smoke[i].z, 0.0, 1.0);
		dens += smoke[i].w * smoothstep(0.0, 0.7, f) * (0.55 + 0.45 * n);
	}
	dens *= 1.0 - clear;
	vec3 lit = tint.rgb * (ambient + flash * 2.5);
	for (int i = 0; i < n_lights; i++) {
		float f = clamp(1.0 - length(wp - lights[i].xy) / lights[i].z, 0.0, 1.0);
		lit += light_col[i].rgb * lights[i].w * f * f;
	}
	dens = floor(clamp(dens, 0.0, 1.0) * 7.0) / 7.0;
	COLOR = vec4(lit, dens * tint.a);
}
