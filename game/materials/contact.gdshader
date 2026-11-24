shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
	float r = length(UV*2.0-1.0);
	ALBEDO = vec3(0.09,0.075,0.095);
	ALPHA = 0.32*(1.0-smoothstep(0.15,1.0,r));
}
