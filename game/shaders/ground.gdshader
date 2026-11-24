shader_type spatial;
// World-space ground: grass with colour patches, asphalt, plaza tiles or dirt,
// plus drifting cloud shadows during the day.
uniform int pattern = 0;
uniform vec4 color_a : source_color = vec4(0.47, 0.71, 0.38, 1.0);
uniform vec4 color_b : source_color = vec4(0.62, 0.79, 0.42, 1.0);
uniform vec4 color_c : source_color = vec4(0.36, 0.6, 0.36, 1.0);
global uniform float g_day;
global uniform float g_wet;
varying vec3 wpos;
#include "res://game/shaders/toon_light.gdshaderinc"

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return noise(p) * 0.55 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.15; }

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz;
	vec3 c;
	float rough = 0.9;
	if (pattern == 0) {
		float n = fbm(p * 0.09);
		float d = fbm(p * 0.6 + 7.0);
		c = mix(color_a.rgb, color_b.rgb, smoothstep(0.35, 0.7, n));
		c = mix(c, color_c.rgb, smoothstep(0.55, 0.8, d) * 0.6);
		float speck = step(0.985, hash(floor(p * 3.0)));
		c = mix(c, vec3(0.98, 0.95, 0.75), speck * 0.5);
	} else if (pattern == 1) {
		float n = fbm(p * 0.7);
		c = mix(color_a.rgb, color_b.rgb, n);
		c *= 0.95 + 0.1 * step(0.93, hash(floor(p * 6.0)));
		rough = mix(0.85, 0.25, g_wet);
	} else if (pattern == 2) {
		vec2 t = p * 1.0;
		vec2 f = fract(t);
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float checker = mod(floor(t.x) + floor(t.y), 2.0);
		c = mix(color_a.rgb, color_b.rgb, checker * 0.6 + hash(floor(t)) * 0.4);
		c = mix(color_c.rgb, c, smoothstep(0.02, 0.06, edge));
		rough = mix(0.8, 0.3, g_wet);
	} else {
		float n = fbm(p * 0.5);
		c = mix(color_a.rgb, color_b.rgb, n);
		c = mix(c, color_c.rgb, step(0.97, hash(floor(p * 5.0))) * 0.6);
	}
	float clouds = smoothstep(0.45, 0.75, fbm(p * 0.035 + vec2(TIME * 0.012, TIME * 0.007)));
	c *= 1.0 - clouds * 0.22 * g_day;
	c *= 1.0 - 0.18 * g_wet;
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.2 + 0.4 * g_wet;
}
