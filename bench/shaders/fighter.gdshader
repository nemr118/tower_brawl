// Fighters, every look since p4.3 (they draw in the never-darkened threats
// layer): a dark edge pixel, then a bright outline glow_px wide in the
// fighter's colour (3 px; yours white and 4 px), a hit flash, and a flicker while the
// fighter stands in fire or poison. light() is the old T3 2-tone light, used
// only if the fighters are ever lit again. In Godot 4, COLOR comes into
// fragment() already multiplied by the texture, so the result is multiplied by
// the sprite's own tint (`tint`, from vertex()) instead: multiplying by COLOR
// gave every outline pixel the texture's alpha 0 (no outline, T3's dark one
// included, until p4.3) and squared the fighters' colours (darker).
shader_type canvas_item;

uniform float bands = 2.0;
uniform vec4 outline_color : source_color = vec4(0.03, 0.02, 0.06, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float glow_px = 3.0;
uniform float flash = 0.0;
uniform float burn = 0.0;
uniform float poison = 0.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.5) {
		vec2 t = TEXTURE_PIXEL_SIZE;
		float n = texture(TEXTURE, UV + vec2(t.x, 0.0)).a + texture(TEXTURE, UV - vec2(t.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, t.y)).a + texture(TEXTURE, UV - vec2(0.0, t.y)).a;
		if (n > 0.5) {
			c = outline_color;
		} else {
			float g = 0.0;
			for (int k = 2; k <= 4; k++) {
				float d = float(k);
				if (d > glow_px) {
					break;
				}
				g += texture(TEXTURE, UV + vec2(t.x, 0.0) * d).a + texture(TEXTURE, UV - vec2(t.x, 0.0) * d).a
					+ texture(TEXTURE, UV + vec2(0.0, t.y) * d).a + texture(TEXTURE, UV - vec2(0.0, t.y) * d).a
					+ texture(TEXTURE, UV + t * d * 0.7071).a + texture(TEXTURE, UV - t * d * 0.7071).a
					+ texture(TEXTURE, UV + vec2(t.x, -t.y) * d * 0.7071).a + texture(TEXTURE, UV + vec2(-t.x, t.y) * d * 0.7071).a;
			}
			c = g > 0.5 ? glow_color : vec4(0.0);
		}
	}
	vec3 col = mix(c.rgb, vec3(1.0), flash);
	col = mix(col, vec3(1.0, 0.5, 0.12), burn * (0.25 + 0.25 * step(0.5, fract(TIME * 12.0))));
	col = mix(col, vec3(0.62, 0.25, 0.95), poison * 0.35);
	COLOR = vec4(col, c.a) * tint;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT_DIRECTION), 0.0);
	float stepped = floor(ndl * bands + 0.35) / bands;
	LIGHT = vec4(COLOR.rgb * LIGHT_COLOR.rgb * LIGHT_ENERGY * stepped, LIGHT_COLOR.a);
}
