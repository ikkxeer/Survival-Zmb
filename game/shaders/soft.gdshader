shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
// Alpha blended soft sprite (blob shadows, smoke puffs, rings, decals). Uses UV radial falloff.
uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 0.35);
uniform int shape = 0; // 0 disc, 1 ring, 2 soft puff
instance uniform float fade = 1.0;
instance uniform vec4 itint : source_color = vec4(1.0);
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float a;
	if (shape == 0) a = 1.0 - smoothstep(0.35, 1.0, r);
	else if (shape == 1) a = smoothstep(0.72, 0.84, r) * (1.0 - smoothstep(0.9, 1.0, r));
	else a = (1.0 - smoothstep(0.0, 1.0, r)) * 0.9;
	ALBEDO = color.rgb * itint.rgb;
	ALPHA = a * color.a * fade * itint.a;
}
