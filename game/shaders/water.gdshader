shader_type spatial;
render_mode cull_disabled;
uniform vec4 deep : source_color = vec4(0.28, 0.62, 0.78, 1.0);
uniform vec4 shallow : source_color = vec4(0.55, 0.86, 0.9, 1.0);
global uniform float g_night_glow;
varying vec3 wpos;
#include "res://game/shaders/toon_light.gdshaderinc"
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 2.0 + wpos.x * 3.0) * 0.015 + cos(TIME * 1.7 + wpos.z * 2.5) * 0.015;
}
void fragment() {
	float w = sin(wpos.x * 6.0 + TIME * 2.2) * sin(wpos.z * 5.0 - TIME * 1.8);
	float sparkle = smoothstep(0.82, 0.95, w);
	ALBEDO = mix(deep.rgb, shallow.rgb, 0.5 + 0.5 * w) + sparkle * 0.25;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
	EMISSION = vec3(0.2, 0.5, 0.7) * g_night_glow * 0.35;
}
