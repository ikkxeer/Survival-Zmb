shader_type sky;
// Painterly gradient sky with sun, moon, stars and soft clouds. Colours are driven from script.
uniform vec3 top_color : source_color = vec3(0.35, 0.6, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.85, 0.92, 1.0);
uniform vec3 ground_color : source_color = vec3(0.55, 0.6, 0.55);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float stars = 0.0;
uniform float cloud_cover = 0.4;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 c = mix(horizon_color, top_color, smoothstep(0.0, 0.6, h));
	c = mix(c, ground_color, smoothstep(0.0, -0.15, h));
	float sd = dot(d, normalize(sun_dir));
	c += sun_color * (smoothstep(0.9985, 0.9992, sd) * 3.0 + pow(max(sd, 0.0), 24.0) * 0.35);
	float md = dot(d, normalize(moon_dir));
	c += vec3(0.85, 0.9, 1.0) * smoothstep(0.9988, 0.9993, md) * 1.6 + vec3(0.3, 0.4, 0.7) * pow(max(md, 0.0), 40.0) * 0.3;
	if (h > 0.0) {
		vec2 sp = d.xz / (h + 0.25);
		float s = step(0.996, hash(floor(sp * 120.0))) * stars * smoothstep(0.0, 0.3, h);
		c += vec3(s);
		float cl = smoothstep(0.5, 0.8, noise(sp * 2.0 + TIME * 0.01) * 0.6 + noise(sp * 5.0) * 0.4);
		c = mix(c, mix(horizon_color, vec3(1.0), 0.5), cl * cloud_cover * smoothstep(0.0, 0.25, h));
	}
	COLOR = c;
}
