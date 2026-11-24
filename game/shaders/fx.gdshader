shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, depth_draw_never;
// Additive glow for tracers, muzzle flashes, sparks and zaps.
uniform vec4 color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float energy = 2.0;
instance uniform float fade = 1.0;
void fragment() {
	ALBEDO = color.rgb * energy * fade * COLOR.rgb;
	ALPHA = fade;
}
