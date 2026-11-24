shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D pattern : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 pigment : source_color;
uniform float frequency = 0.6;
varying vec3 world_pos;
varying vec3 surface_normal;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_normal = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
	vec3 n = abs(normalize(surface_normal));
	vec2 uv = n.y > max(n.x,n.z) ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	ALBEDO = pigment.rgb * texture(pattern,uv*frequency).rgb;
	ROUGHNESS = 0.89;
}
