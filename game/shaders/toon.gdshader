shader_type spatial;
render_mode cull_back;
// Vertex colours carry the albedo; alpha < 1 marks surfaces that glow at night (windows, lamps).
uniform vec4 tint : source_color = vec4(1.0);
uniform float wind_amp = 0.0;
uniform float glow_always = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.78, 0.45);
global uniform float g_night_glow;
global uniform float g_wind;
instance uniform float flash = 0.0;
instance uniform vec4 itint : source_color = vec4(1.0);
instance uniform float burn = 0.0;
varying float v_glow;
#include "res://game/shaders/toon_light.gdshaderinc"

void vertex() {
	v_glow = 1.0 - COLOR.a;
	if (wind_amp > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float h = max(VERTEX.y - 0.4, 0.0);
		float s = sin(TIME * 1.5 + wp.x * 0.35 + wp.z * 0.27) + 0.45 * sin(TIME * 3.3 + wp.x * 0.9 + VERTEX.y);
		VERTEX.x += s * wind_amp * h * (0.4 + g_wind);
		VERTEX.z += cos(TIME * 1.2 + wp.z * 0.4) * wind_amp * 0.5 * h * (0.4 + g_wind);
	}
}

void fragment() {
	vec3 c = COLOR.rgb * tint.rgb * itint.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	float glow = v_glow * max(g_night_glow, glow_always);
	EMISSION = mix(c, glow_color, 0.65) * glow * 2.4 + vec3(1.0, 0.96, 0.9) * flash * 0.9
		+ vec3(1.0, 0.45, 0.1) * burn * (0.6 + 0.4 * sin(TIME * 30.0));
}
