// Fighters in tier T3: the light in 2 flat steps (Dead Cells' "2 tone cell
// shading"), a second dark outline pixel, a hit flash, and a flicker while the
// fighter stands in fire or poison.
shader_type canvas_item;

uniform float bands = 2.0;
uniform vec4 outline_color : source_color = vec4(0.03, 0.02, 0.06, 1.0);
uniform float flash = 0.0;
uniform float burn = 0.0;
uniform float poison = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.5) {
		vec2 t = TEXTURE_PIXEL_SIZE;
		float n = texture(TEXTURE, UV + vec2(t.x, 0.0)).a + texture(TEXTURE, UV - vec2(t.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, t.y)).a + texture(TEXTURE, UV - vec2(0.0, t.y)).a;
		c = n > 0.5 ? outline_color : vec4(0.0);
	}
	vec3 col = mix(c.rgb, vec3(1.0), flash);
	col = mix(col, vec3(1.0, 0.5, 0.12), burn * (0.25 + 0.25 * step(0.5, fract(TIME * 12.0))));
	col = mix(col, vec3(0.62, 0.25, 0.95), poison * 0.35);
	COLOR = vec4(col, c.a) * COLOR;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT_DIRECTION), 0.0);
	float stepped = floor(ndl * bands + 0.35) / bands;
	LIGHT = vec4(COLOR.rgb * LIGHT_COLOR.rgb * LIGHT_ENERGY * stepped, LIGHT_COLOR.a);
}
