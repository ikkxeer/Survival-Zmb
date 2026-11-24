shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_test_disabled;
// Billboard health bar for enemies and defences.
instance uniform float value = 1.0;
instance uniform vec4 fill : source_color = vec4(0.95, 0.35, 0.35, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV;
	float border = step(0.06, uv.y) * step(uv.y, 0.94) * step(0.015, uv.x) * step(uv.x, 0.985);
	vec3 c = uv.x < value ? fill.rgb : vec3(0.18, 0.15, 0.22);
	ALBEDO = mix(vec3(0.1, 0.08, 0.12), c, border);
	ALPHA = 0.92;
}
