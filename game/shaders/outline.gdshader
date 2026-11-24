shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
// Inverted hull outline that keeps characters readable from the high camera.
uniform vec4 color : source_color = vec4(0.16, 0.12, 0.2, 1.0);
uniform float width = 0.022;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = color.rgb;
}
