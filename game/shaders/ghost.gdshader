shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, blend_mix, depth_draw_never;
// Build preview hologram.
uniform vec4 color : source_color = vec4(0.4, 1.0, 0.6, 0.45);
void fragment() {
	float scan = 0.75 + 0.25 * sin(TIME * 6.0 + FRAGCOORD.y * 0.15);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = color.rgb * (0.8 + rim);
	ALPHA = color.a * scan + rim * 0.3;
}
